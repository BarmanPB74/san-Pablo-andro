class_name ClayStyle
extends Node3D
## Modo "plastilina": convierte TODO el mundo a un look de stop-motion hecho a mano.
## No toca los generadores de cada agente: recorre el árbol y cambia cada material
## (StandardMaterial3D / ORMMaterial3D / piso mojado) por su versión de arcilla
## (look/clay.gdshader): mismo color y patrón de textura, pero difuminado, con
## presiones de pulgar, huellas, brillo ceroso y la paleta del pueblo de plastilina
## (ladrillo frambuesa, malva, musgo, faroles ámbar).
##
## Uso (lo hace core/game.gd cuando time_of_day == "plastilina"):
##   ClayStyle.enabled = true      ← ANTES de construir el mundo (árboles, rejas, personaje cambian de forma)
##   add_child(ClayStyle.new())    ← DESPUÉS: convierte lo que existe y lo que se cree luego (autos, conos...)
##
## Se deja igual: materiales sin luz (letreros, cielo), transparentes con mezcla (vidrios),
## billboards y shaders propios (lluvia, montañas, cielo).

const SHADER_PATH := "res://look/clay.gdshader"
const CLAY_TEX := "res://art/tex/clay/clay_detail.png"
const WET_SHADER := "res://look/wet_asphalt.gdshader"

## true = el juego se construye en modo plastilina (árboles retorcidos, rejas de lanza, personaje cabezón).
static var enabled := false

static var _shaders := {}      # "cut_cull" → Shader
static var _conv := {}         # id material + modo → material de arcilla
static var _done_meshes := {}  # id de malla → true
static var _tex: Texture2D = null


## Luz de relleno que acompaña a la cámara (como el foco de un set de stop-motion):
## el personaje y lo cercano no se pierden en la noche morada. Sin sombras: barata.
var _fill: OmniLight3D


func _ready() -> void:
	name = "ClayStyle"
	apply_tree(get_tree().root)
	get_tree().node_added.connect(_on_node_added)
	_fill = OmniLight3D.new()
	_fill.name = "ClayFill"
	_fill.light_color = Color(1.0, 0.86, 0.74)
	_fill.light_energy = 0.9
	_fill.light_specular = 0.15
	_fill.omni_range = 9.0
	_fill.omni_attenuation = 1.4
	_fill.shadow_enabled = false
	_fill.set_meta("clay_done", true)
	add_child(_fill)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _fill:
		_fill.global_position = cam.global_position + cam.global_basis.y * 1.2 - cam.global_basis.z * 0.5


func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D or n is Light3D:
		_convert_node.call_deferred(n)


func _convert_node(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n is GeometryInstance3D:
		_convert_geo(n as GeometryInstance3D)
	elif n is Light3D:
		_warm_light(n as Light3D)


## Convierte todos los GeometryInstance3D que cuelgan de node.
static func apply_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		_convert_geo(node as GeometryInstance3D)
	elif node is Light3D:
		_warm_light(node as Light3D)
	for c in node.get_children():
		apply_tree(c)


static func _is_moving(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is PhysicsBody3D and not (p is StaticBody3D):
			return true
		p = p.get_parent()
	return false


## Luces de faroles y locales: más ámbar, como en una maqueta iluminada con bombillos.
static func _warm_light(l: Light3D) -> void:
	if l is DirectionalLight3D or l.has_meta("clay_done"):
		return
	l.set_meta("clay_done", true)
	var c := l.light_color
	if c.r >= c.b:   # no tocar neones fríos
		l.light_color = c.lerp(Color(1.0, 0.66, 0.34), 0.45)


static func _convert_geo(g: GeometryInstance3D) -> void:
	if g.has_meta("clay_done"):
		return
	g.set_meta("clay_done", true)
	var local := _is_moving(g)
	if g.material_override != null:
		g.material_override = clay_of(g.material_override, local)
	var mesh: Mesh = null
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var o := mi.get_surface_override_material(i)
				if o != null:
					mi.set_surface_override_material(i, clay_of(o, local))
	elif g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm != null:
			mesh = mm.mesh
	if mesh != null:
		var key := "%d_%s" % [mesh.get_instance_id(), local]
		if not _done_meshes.has(key):
			_done_meshes[key] = true
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				if m != null:
					mesh.surface_set_material(i, clay_of(m, local))


static func _shader(cutout: bool, cull_off: bool) -> Shader:
	var key := "%s_%s" % [cutout, cull_off]
	if _shaders.has(key):
		return _shaders[key]
	var base: Shader = load(SHADER_PATH)
	var sh := base
	if cutout or cull_off:
		var code := base.code
		if cull_off:
			code = code.replace("cull_back,", "cull_disabled,")
		if cutout:
			code = code.replace("// #ALPHA", "ALPHA = col.a;\n\tALPHA_SCISSOR_THRESHOLD = alpha_cut;")
		sh = Shader.new()
		sh.code = code
	_shaders[key] = sh
	return sh


static func _clay_tex() -> Texture2D:
	if _tex == null:
		_tex = load(CLAY_TEX)
	return _tex


## Versión de arcilla de un material (cacheada). Devuelve el original si no se debe tocar.
static func clay_of(m: Material, local := false) -> Material:
	if m == null or m.has_meta("clay"):
		return m
	var key := "%d_%s" % [m.get_instance_id(), local]
	if _conv.has(key):
		return _conv[key]
	var out: Material = m
	if m is BaseMaterial3D:
		out = _from_base(m as BaseMaterial3D, local)
	elif m is ShaderMaterial:
		out = _from_shader(m as ShaderMaterial, local)
	if out != m:
		out.set_meta("clay", true)
		out.set_meta("clay_src", m)   # material original (lo usa GothicClayAdapter para saber qué pieza es)
		if m.next_pass != null:
			out.next_pass = m.next_pass
	_conv[key] = out
	return out


static func _new_clay(cutout: bool, cull_off: bool, local: bool) -> ShaderMaterial:
	var c := ShaderMaterial.new()
	c.shader = _shader(cutout, cull_off)
	c.set_shader_parameter("clay_tex", _clay_tex())
	c.set_shader_parameter("clay_local", local)
	if local:
		# piezas pequeñas que se mueven (personaje, autos): huella más fina
		c.set_shader_parameter("clay_scale", 3.2)
		c.set_shader_parameter("clay_bump", 0.55)
	return c


static func _from_base(b: BaseMaterial3D, local: bool) -> Material:
	if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return b
	if b.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return b
	var tr := b.transparency
	if tr == BaseMaterial3D.TRANSPARENCY_ALPHA or tr == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
		return b
	var cutout := tr == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or tr == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	var c := _new_clay(cutout, b.cull_mode == BaseMaterial3D.CULL_DISABLED, local)
	c.render_priority = b.render_priority
	c.set_shader_parameter("base_color", b.albedo_color)
	if b.albedo_texture != null:
		c.set_shader_parameter("albedo_tex", b.albedo_texture)
		c.set_shader_parameter("has_tex", true)
	var mode := 0
	if b.uv1_triplanar:
		mode = 2 if (local or not b.uv1_world_triplanar) else 1
	c.set_shader_parameter("uv_mode", mode)
	c.set_shader_parameter("uv_scale", b.uv1_scale)
	c.set_shader_parameter("uv_offset", b.uv1_offset)
	if b.vertex_color_use_as_albedo:
		c.set_shader_parameter("use_vcolor", true)
		c.set_shader_parameter("vcolor_srgb", b.vertex_color_is_srgb)
	if cutout:
		c.set_shader_parameter("alpha_cut", b.alpha_scissor_threshold if tr == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5)
	if b.emission_enabled:
		c.set_shader_parameter("has_emission", true)
		c.set_shader_parameter("emission_color", b.emission)
		c.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
		if b.emission_texture != null:
			c.set_shader_parameter("emission_tex", b.emission_texture)
			c.set_shader_parameter("has_emission_tex", true)
	# Brillos: lo pulido (pintura de auto, metal) queda como plastilina más lisa y cerosa.
	if b.roughness < 0.35 and b.albedo_texture == null:
		c.set_shader_parameter("rough", 0.42)
		c.set_shader_parameter("spec", 0.5)
	return c


static func _from_shader(s: ShaderMaterial, local: bool) -> Material:
	if s.shader == null or s.shader.resource_path != WET_SHADER:
		return s
	var c := _new_clay(false, false, local)
	if s.get_shader_parameter("use_tex"):
		var tint = s.get_shader_parameter("tex_tint")
		var t: Color = Color(tint.x, tint.y, tint.z) if tint is Vector3 else (tint if tint is Color else Color.WHITE)
		c.set_shader_parameter("base_color", t)
		c.set_shader_parameter("albedo_tex", s.get_shader_parameter("tex_albedo"))
		c.set_shader_parameter("has_tex", true)
		var tile = s.get_shader_parameter("tex_tile_m")
		var k := 1.0 / maxf(float(tile) if tile != null else 4.0, 0.1)
		c.set_shader_parameter("uv_mode", 1)
		c.set_shader_parameter("uv_scale", Vector3(k, k, k))
	else:
		var bc = s.get_shader_parameter("base_color")
		var col: Color = Color(bc.x, bc.y, bc.z) if bc is Vector3 else (bc if bc is Color else Color(0.12, 0.12, 0.13))
		c.set_shader_parameter("base_color", col)
	c.set_shader_parameter("tex_blur", 0.8)   # pisos: se conserva la forma del adoquín
	return c

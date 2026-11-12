class_name GothicClayAdapter
extends Node
## Port a Godot de GothicClayCharacterAdapter.cs (Unity) que trajo Pablo.
## Adapta un personaje al estilo "arcilla gótica": piel beige mate, saco y pelo casi negros,
## bufanda a rayas verde/crema, zapatos café, ojos blancos algo brillantes y pupilas negras.
##
## Dos usos, igual que el original:
##   apply_gothic_clay_style()  → recolorea y vuelve mate cada pieza del personaje.
##   replace_with_clay_glb()    → esconde las mallas actuales y pone encima un modelo importado
##                                (p. ej. res://character/personaje_arcilla_gotica.glb) sin tocar
##                                la física ni la animación del jugador.
##
## Cómo reconoce cada pieza (en orden):
##   1) Por NOMBRE del nodo/malla, con las mismas reglas del C# (scarf/bufanda, eye, pupil,
##      hair/eyebrow/pelo/ceja, coat/jacket/torso/arm/pant/leg, shoe/zapato; lo demás = piel).
##      Sirve para modelos importados (GLB) con piezas nombradas.
##   2) Para Andro (PlayerModel), por el MATERIAL de cada superficie (skin, eye, hair, twill,
##      knit, shoe, sole). Andro pinta sus partes con color de vértice; la paleta del adaptador
##      se aplica en player_model.gd (constantes de plastilina) y aquí se ajusta el acabado.
##
## Diferencias con Unity: Godot usa rugosidad (= 1 − smoothness) y no hay Animator humanoide;
## el "hueso de la cabeza" es el pivote `head` de PlayerModel (o un hijo llamado Head).

# Valores por defecto = los del script original
const SKIN := Color(0.82, 0.75, 0.70)
const COAT := Color(0.11, 0.11, 0.13)
const HAIR := Color(0.08, 0.08, 0.09)
const SCARF_GREEN := Color(0.13, 0.36, 0.21)
const SCARF_CREAM := Color(0.88, 0.85, 0.80)
const SHOE := Color(0.26, 0.21, 0.17)
const EYE := Color(0.93, 0.92, 0.89)
const PUPIL := Color(0.03, 0.03, 0.03)

@export var existing_character_root: Node3D          ## vacío = el padre de este nodo
@export_file("*.glb", "*.gltf", "*.tscn") var gothic_clay_model_path := ""
@export_range(0.0, 1.0) var clay_smoothness := 0.12   ## arcilla mate (rugosidad ~0.88)
@export var normal_bump_scale := 0.65
@export var skin_tint := SKIN
@export var coat_tint := COAT
@export var hair_tint := HAIR
@export var scarf_green := SCARF_GREEN
@export var scarf_cream := SCARF_CREAM
@export var apply_on_ready := true

static var _clay_normal: Texture2D
static var _scarf_tex: Texture2D


func _ready() -> void:
	if not apply_on_ready:
		return
	# Esperar a que ClayStyle convierta los materiales (lo hace al entrar al árbol / un frame después).
	await get_tree().process_frame
	await get_tree().process_frame
	apply_gothic_clay_style()
	if gothic_clay_model_path != "":
		replace_with_clay_glb()


func _target() -> Node3D:
	return existing_character_root if existing_character_root != null else get_parent() as Node3D


# ------------------------------------------------------------------ estilo

func apply_gothic_clay_style() -> void:
	var target := _target()
	if target == null:
		return
	_ensure_textures()
	for mi in _meshes(target):
		var mesh := mi.mesh
		if mesh == null:
			continue
		var part_by_name := _role_from_name(String(mi.name).to_lower() + " " + String(mesh.resource_name).to_lower())
		for i in mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null:
				continue
			var role := part_by_name
			var andro := part_by_name == "" and _role_from_player_material(m) != ""
			if andro:
				role = _role_from_player_material(m)
			if role == "":
				role = "skin"
			# Andro trae sus colores en los vértices: solo se ajusta el acabado. Lo demás se recolorea como en Unity.
			var out := _styled(m, role, not andro)
			if out != m:
				mi.set_surface_override_material(i, out)


## Reglas de nombre del C# (mismo orden). "" = no decide por nombre.
static func _role_from_name(n: String) -> String:
	if n.contains("scarf") or n.contains("bufanda"):
		return "scarf"
	if n.contains("eye") and not n.contains("eyebrow") and not n.contains("undereye"):
		return "eye"
	if n.contains("pupil"):
		return "pupil"
	if n.contains("hair") or n.contains("eyebrow") or n.contains("pelo") or n.contains("ceja"):
		return "hair"
	for k in ["coat", "jacket", "torso", "arm", "pant", "leg"]:
		if n.contains(k):
			return "coat"
	if n.contains("shoe") or n.contains("zapato"):
		return "shoe"
	return ""


## Andro: el material de cada superficie dice qué pieza es (ClayStyle guarda el original en "clay_src").
static func _role_from_player_material(m: Material) -> String:
	var src: Material = m.get_meta("clay_src", m)
	var key := PlayerModel.material_key(src)
	match key:
		"skin": return "skin"
		"eye": return "eye"
		"hair": return "hair"
		"twill", "rip": return "coat"
		"knit": return "scarf"
		"shoe", "sole": return "shoe"
	return ""


func _tint(role: String) -> Color:
	match role:
		"coat": return coat_tint
		"hair": return hair_tint
		"shoe": return SHOE
		"eye": return EYE
		"pupil": return PUPIL
		"scarf": return Color.WHITE
	return skin_tint


func _smooth(role: String) -> float:
	match role:
		"eye": return 0.45
		"pupil": return 0.55
	return clay_smoothness


## recolor = true: la pieza no trae color de vértice (modelo importado) → se le pone el tinte.
func _styled(m: Material, role: String, recolor: bool) -> Material:
	var rough := 1.0 - _smooth(role)
	if m is ShaderMaterial and m.has_meta("clay"):
		var c := (m as ShaderMaterial).duplicate() as ShaderMaterial
		c.set_meta("clay", true)
		c.set_shader_parameter("rough", rough)
		c.set_shader_parameter("spec", 0.5 if role == "eye" or role == "pupil" else 0.25)
		c.set_shader_parameter("clay_bump", 0.0 if role == "eye" or role == "pupil" else normal_bump_scale)
		c.set_shader_parameter("sheen", 0.15 if role == "eye" else 0.3)
		# el personaje conserva sus colores (blancos de camisa/bufanda/ojos no se vuelven rosados)
		c.set_shader_parameter("grey_amount", 0.0)
		c.set_shader_parameter("brick_shift", 0.0)
		if recolor:
			c.set_shader_parameter("base_color", _tint(role))
			if role == "scarf":
				c.set_shader_parameter("albedo_tex", _scarf_tex)
				c.set_shader_parameter("has_tex", true)
				c.set_shader_parameter("uv_mode", 0)
				c.set_shader_parameter("tex_keep", 1.0)
		return c
	# Sin ClayStyle: material estándar mate como el original de Unity (URP/Lit).
	var s := StandardMaterial3D.new()
	s.roughness = rough
	s.metallic = 0.0
	if m is BaseMaterial3D and not recolor:
		var b := m as BaseMaterial3D
		s.albedo_color = b.albedo_color
		s.albedo_texture = b.albedo_texture
		s.vertex_color_use_as_albedo = b.vertex_color_use_as_albedo
		s.vertex_color_is_srgb = b.vertex_color_is_srgb
		s.uv1_scale = b.uv1_scale
	else:
		s.albedo_color = _tint(role)
		if role == "scarf":
			s.albedo_texture = _scarf_tex
	if role != "eye" and role != "pupil":
		s.normal_enabled = true
		s.normal_texture = _clay_normal
		s.normal_scale = normal_bump_scale
		s.uv1_triplanar = true
		s.uv1_scale = Vector3.ONE * 3.0
	return s


# ------------------------------------------------------------------ reemplazo por GLB

func replace_with_clay_glb() -> Node3D:
	if gothic_clay_model_path == "" or not ResourceLoader.exists(gothic_clay_model_path):
		push_warning("[GothicClay] Falta el modelo: %s (p. ej. personaje_arcilla_gotica.glb)" % gothic_clay_model_path)
		return null
	var target := _target()
	# Esconde las mallas actuales; la física (cápsula) y la animación del jugador siguen intactas.
	for mi in _meshes(target):
		mi.visible = false
	var inst := (load(gothic_clay_model_path) as PackedScene).instantiate() as Node3D
	inst.name = "GothicClayCharacter_Visual"
	target.add_child(inst)
	inst.transform = Transform3D.IDENTITY
	for mi in _meshes(inst):
		mi.set_meta("from_glb", true)
	# "Head" del modelo → pivote de la cabeza de Andro (sigue los giros de la animación)
	var head_bone: Node3D = target.get("head") if "head" in target else null
	var glb_head := inst.find_child("Head", true, false) as Node3D
	if head_bone != null and glb_head != null:
		glb_head.reparent(head_bone, true)
	ClayStyle.apply_tree(inst)
	apply_gothic_clay_style()
	return inst


# ------------------------------------------------------------------ utilidades

static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _ensure_textures() -> void:
	if _clay_normal == null:
		_clay_normal = _gen_clay_normal(256)
	if _scarf_tex == null:
		_scarf_tex = _gen_scarf(256)


## Igual que GenerateClayNormalMap del C#: ruido de dos escalas + crestas onduladas.
static func _gen_clay_normal(size: int) -> Texture2D:
	var n1 := FastNoiseLite.new()
	n1.noise_type = FastNoiseLite.TYPE_PERLIN
	n1.frequency = 0.12
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_PERLIN
	n2.frequency = 0.35
	n2.seed = 3
	var h := PackedFloat32Array()
	h.resize(size * size)
	for y in size:
		for x in size:
			var v := (n1.get_noise_2d(x, y) * 0.5 + 0.5) * 0.6 + (n2.get_noise_2d(x, y) * 0.5 + 0.5) * 0.25
			v += 0.08 * sin(x * 0.32 + y * 0.22 + 2.0 * sin(y * 0.05))
			h[y * size + x] = v
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var dx := h[y * size + (x + 1) % size] - h[y * size + (x - 1 + size) % size]
			var dy := h[((y + 1) % size) * size + x] - h[((y - 1 + size) % size) * size + x]
			var nv := Vector3(-dx * 2.2, -dy * 2.2, 1.0).normalized()
			img.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.y * 0.5 + 0.5, nv.z * 0.5 + 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Igual que GenerateScarfStripeTexture: franjas de 32 px verde/crema con ruido de tejido.
func _gen_scarf(size: int) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.4
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		var base := scarf_green if (y / 32) % 2 == 0 else scarf_cream
		for x in size:
			var k := noise.get_noise_2d(x, y) * 0.5 * 0.06
			img.set_pixel(x, y, Color(clampf(base.r + k, 0, 1), clampf(base.g + k, 0, 1), clampf(base.b + k, 0, 1)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

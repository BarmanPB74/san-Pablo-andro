class_name Portal
extends Area3D
## Puerta-portal (ref. 83528): marco de bronce con vetas doradas y, dentro, una galaxia espiral.
## Se "conjura": el marco crece desde el piso y el iris de la galaxia se abre desde el centro.
## Cuando el jugador cruza el plano, emite `entered` y el Stage hace el viaje.
## Todo se construye por código (sin assets), según CONTRACT.md.

signal entered(portal: Portal)

const GALAXY_SHADER := preload("res://stage/shaders/galaxy_portal.gdshader")

static var _bronze: StandardMaterial3D = null
static var _gold: StandardMaterial3D = null
static var _spill_tex: GradientTexture2D = null
static var _spill_mat: StandardMaterial3D = null

## Id de la escena a la que lleva (ver Stage.SCENES).
var target := ""
var size := Vector2(2.6, 5.6)
var is_open := false
var openness := 0.0          # 0 = cerrado, 1 = totalmente abierto

var _frame: Node3D
var _surface: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _spill: MeshInstance3D
var _tween: Tween
var _fired := false


func _init(p_target := "", p_size := Vector2(2.6, 5.6)) -> void:
	target = p_target
	size = p_size


func _ready() -> void:
	add_to_group("portal")
	collision_layer = 0
	collision_mask = 1 << 1          # solo el jugador (capa 2)
	monitoring = false
	_build()
	_apply(0.0)
	body_entered.connect(_on_body_entered)


static func _bronze_mat() -> StandardMaterial3D:
	if _bronze == null:
		_bronze = StandardMaterial3D.new()
		_bronze.albedo_color = Color(0.52, 0.39, 0.21)
		_bronze.metallic = 0.5
		_bronze.roughness = 0.5
		_bronze.emission_enabled = true
		_bronze.emission = Color(0.45, 0.32, 0.14)
		_bronze.emission_energy_multiplier = 0.25
	return _bronze


static func _gold_mat() -> StandardMaterial3D:
	if _gold == null:
		_gold = StandardMaterial3D.new()
		_gold.albedo_color = Color(0.9, 0.7, 0.35)
		_gold.emission_enabled = true
		_gold.emission = Color(1.0, 0.78, 0.4)
		_gold.emission_energy_multiplier = 2.2
		_gold.metallic = 0.9
		_gold.roughness = 0.3
	return _gold


static func _spill_material() -> StandardMaterial3D:
	if _spill_mat == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(0.6, 0.7, 1.0, 0.55), Color(0.4, 0.5, 0.95, 0.18), Color(0.3, 0.4, 0.9, 0.0)])
		_spill_tex = GradientTexture2D.new()
		_spill_tex.gradient = g
		_spill_tex.fill = GradientTexture2D.FILL_RADIAL
		_spill_tex.fill_from = Vector2(0.5, 0.5)
		_spill_tex.fill_to = Vector2(1.0, 0.5)
		_spill_tex.width = 128
		_spill_tex.height = 128
		_spill_mat = StandardMaterial3D.new()
		_spill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spill_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spill_mat.albedo_texture = _spill_tex
		_spill_mat.disable_receive_shadows = true
		_spill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _spill_mat


func _box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, collide := false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		sb.position = pos
		sb.add_child(cs)
		parent.add_child(sb)


func _build() -> void:
	var w := size.x
	var h := size.y
	var post := 0.34
	var depth := 0.42
	_frame = Node3D.new()
	_frame.name = "Frame"
	add_child(_frame)
	var bronze := _bronze_mat()
	var gold := _gold_mat()
	# jambas, dintel y umbral
	_box(_frame, Vector3(-(w * 0.5 + post * 0.5), h * 0.5, 0), Vector3(post, h, depth), bronze, true)
	_box(_frame, Vector3(w * 0.5 + post * 0.5, h * 0.5, 0), Vector3(post, h, depth), bronze, true)
	_box(_frame, Vector3(0, h + post * 0.5, 0), Vector3(w + post * 2.0, post, depth), bronze, false)
	_box(_frame, Vector3(0, 0.05, 0.0), Vector3(w + post * 2.0, 0.1, depth + 0.1), bronze, false)
	# corona escalonada
	_box(_frame, Vector3(0, h + post + 0.12, 0), Vector3(w * 0.85, 0.24, depth * 0.85), bronze)
	_box(_frame, Vector3(0, h + post + 0.34, 0), Vector3(w * 0.5, 0.2, depth * 0.7), bronze)
	_box(_frame, Vector3(0, h + post + 0.5, 0), Vector3(w * 0.22, 0.14, depth * 0.55), gold)
	# vetas doradas interiores
	_box(_frame, Vector3(-(w * 0.5 + 0.02), h * 0.5, depth * 0.22), Vector3(0.04, h, 0.04), gold)
	_box(_frame, Vector3(w * 0.5 + 0.02, h * 0.5, depth * 0.22), Vector3(0.04, h, 0.04), gold)
	_box(_frame, Vector3(0, h + 0.02, depth * 0.22), Vector3(w + 0.08, 0.04, 0.04), gold)
	# "greebles": bloques pequeños repartidos por las jambas (determinista)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	for side in [-1.0, 1.0]:
		var x: float = side * (w * 0.5 + post * 0.5)
		var y := 0.4
		while y < h - 0.2:
			var gh := rng.randf_range(0.16, 0.5)
			var gw := rng.randf_range(0.1, 0.22)
			var gd := rng.randf_range(0.06, 0.14)
			var gx := x + rng.randf_range(-0.07, 0.07)
			_box(_frame, Vector3(gx, y + gh * 0.5, depth * 0.5 + gd * 0.4), Vector3(gw, gh, gd), bronze)
			if rng.randf() < 0.3:
				_box(_frame, Vector3(gx, y + gh * 0.5, depth * 0.5 + gd * 0.9), Vector3(gw * 0.4, gh * 0.25, 0.03), gold)
			y += gh + rng.randf_range(0.1, 0.35)

	# superficie de la galaxia
	_surface = MeshInstance3D.new()
	_surface.name = "Galaxy"
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	_surface.mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = GALAXY_SHADER
	_mat.set_shader_parameter("aspect", w / h)
	_surface.material_override = _mat
	_surface.position = Vector3(0, h * 0.5, 0)
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)

	# luz que se derrama sobre el piso y mancha de luz
	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 0.62, 1.0)
	_light.omni_range = 11.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, h * 0.45, 1.6)
	add_child(_light)
	_spill = MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(w * 4.0, 7.0)
	sq.orientation = PlaneMesh.FACE_Y
	_spill.mesh = sq
	_spill.material_override = _spill_material()
	_spill.position = Vector3(0, 0.035, 3.2)
	_spill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_spill)

	# sensor: el plano del portal (un poco hacia adentro y afuera)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w * 0.9, h * 0.92, 0.7)
	cs.shape = bs
	cs.position = Vector3(0, h * 0.46, 0)
	add_child(cs)


## Aplica el grado de apertura (0..1): primero crece el marco, luego se abre el iris de la galaxia.
func _apply(t: float) -> void:
	openness = t
	var grow := clampf(t / 0.4, 0.0, 1.0)
	var iris := clampf((t - 0.3) / 0.7, 0.0, 1.0)
	grow = 1.0 - pow(1.0 - grow, 3.0)
	if _frame:
		_frame.scale = Vector3(1.0, maxf(grow, 0.001), 1.0)
		_frame.visible = t > 0.001
	if _mat:
		_mat.set_shader_parameter("reveal", iris)
	if _surface:
		_surface.visible = iris > 0.001
	if _light:
		_light.light_energy = iris * 2.6
		_light.visible = iris > 0.001
	if _spill:
		_spill.visible = iris > 0.001
		_spill.scale = Vector3(1, 1, 1) * lerpf(0.3, 1.0, iris)


func open(duration := 1.8) -> void:
	if is_open:
		return
	is_open = true
	_fired = false
	if _tween:
		_tween.kill()
	if duration <= 0.0:
		_apply(1.0)
		monitoring = true
		return
	_tween = create_tween()
	_tween.tween_method(_apply, openness, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func(): monitoring = true)


func close(duration := 0.9) -> void:
	is_open = false
	monitoring = false
	if _tween:
		_tween.kill()
	if duration <= 0.0:
		_apply(0.0)
		return
	_tween = create_tween()
	_tween.tween_method(_apply, openness, 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _on_body_entered(body: Node3D) -> void:
	if _fired or not is_open or not body.is_in_group("player"):
		return
	_fired = true
	entered.emit(self)

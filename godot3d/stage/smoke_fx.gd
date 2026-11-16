class_name SmokeFX
extends Node3D
## Humo gris del Umbral: tres láminas de niebla espesa a distintas alturas (ruido en coordenadas de mundo, con viento)
## y unas bocanadas grandes que suben despacio. Sigue al jugador en X/Z, así que el humo parece infinito.

const LAYER_SHADER := preload("res://stage/shaders/smoke_layer.gdshader")

## [altura, opacidad, escala de ruido, viento, cobertura, color]
const LAYERS := [
	[0.14, 0.70, 0.040, Vector2(0.6, 0.2), 0.36, Color(0.62, 0.62, 0.70)],
	[0.55, 0.52, 0.030, Vector2(-0.4, 0.5), 0.40, Color(0.67, 0.67, 0.75)],
	[1.10, 0.34, 0.022, Vector2(0.3, -0.5), 0.46, Color(0.72, 0.72, 0.79)],
]
const PUFFS := 26

var _puffs: CPUParticles3D


func _ready() -> void:
	name = "SmokeFX"
	var noise := FxTex.noise()
	for i in LAYERS.size():
		var L: Array = LAYERS[i]
		var mi := MeshInstance3D.new()
		mi.name = "Smoke%d" % i
		var pm := PlaneMesh.new()
		pm.size = Vector2(130, 130)
		mi.mesh = pm
		mi.position = Vector3(0, float(L[0]), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = LAYER_SHADER
		m.set_shader_parameter("noise_tex", noise)
		m.set_shader_parameter("opacity", L[1])
		m.set_shader_parameter("tex_scale", L[2])
		m.set_shader_parameter("wind", L[3])
		m.set_shader_parameter("coverage", L[4])
		m.set_shader_parameter("smoke_col", L[5])
		m.render_priority = i                     # de abajo hacia arriba
		mi.material_override = m
		add_child(mi)
	_build_puffs()


func _build_puffs() -> void:
	_puffs = CPUParticles3D.new()
	_puffs.name = "Puffs"
	_puffs.amount = PUFFS
	_puffs.lifetime = 18.0
	_puffs.preprocess = 18.0               # ya hay humo desde el primer cuadro
	_puffs.local_coords = false
	_puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_puffs.emission_box_extents = Vector3(32, 0.3, 32)
	_puffs.position = Vector3(0, 0.6, 0)
	_puffs.direction = Vector3.UP
	_puffs.spread = 14.0
	_puffs.gravity = Vector3.ZERO
	_puffs.initial_velocity_min = 0.12
	_puffs.initial_velocity_max = 0.35
	_puffs.scale_amount_min = 7.0
	_puffs.scale_amount_max = 14.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	_puffs.color_ramp = ramp
	var tint := Gradient.new()                 # cada bocanada con un gris ligeramente distinto (lila, azulado, rosado)
	tint.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	tint.colors = PackedColorArray([Color(0.70, 0.70, 0.78), Color(0.64, 0.72, 0.78), Color(0.78, 0.68, 0.74), Color(0.70, 0.70, 0.78)])
	_puffs.color_initial_ramp = tint
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	_puffs.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true             # sin esto el tamaño de la bocanada se pierde
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = FxTex.puff()
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_puffs.material_override = mat
	add_child(_puffs)


## Se queda centrado (X/Z) en el jugador.
func tick(_delta: float, target: Node3D) -> void:
	if is_instance_valid(target):
		global_position = Vector3(target.global_position.x, 0.0, target.global_position.z)

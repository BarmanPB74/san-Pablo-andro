class_name HubScene
extends StageScene
## El Umbral: la base plana desde la que Andro conjura puertas. Un disco de piso pulido con vetas doradas
## envuelto en niebla gris: solo se ve lo necesario para moverse (~35 m); más allá todo es niebla.
## El límite (muro invisible) queda dentro de la niebla, así que nunca se ve un borde.

const SKY_SHADER := preload("res://stage/shaders/star_sky.gdshader")
const FLOOR_SHADER := preload("res://stage/shaders/hub_floor.gdshader")

const FOG_COLOR := Color(0.47, 0.49, 0.52)
const PLAY_RADIUS := 34.0          # radio jugable (m)

## Dónde se conjura la puerta por defecto (frente al punto de partida).
var door_spot := Vector3(0, 0, -15)


func _init() -> void:
	title = "El Umbral"
	spawn_pos = Vector3(0, 0.1, 6)
	spawn_yaw = 0.0


func build() -> void:
	# cielo gris cubierto (casi todo lo tapa la niebla)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("zenith_col", Color(0.30, 0.32, 0.36))
	sky_mat.set_shader_parameter("horizon_col", FOG_COLOR)
	sky_mat.set_shader_parameter("band_strength", 0.0)
	sky_mat.set_shader_parameter("star_amount", 0.0)
	make_environment(sky_mat, FOG_COLOR, 0.034, 1.0,
		Color(0.9, 0.92, 1.0), 0.75, Vector3(-0.45, -0.75, -0.5))
	set_flat_ambient(Color(0.50, 0.52, 0.56), 0.8)
	env.fog_sky_affect = 1.0

	# piso: disco pulido que se pierde en la niebla (no hace falta más que ~4× el radio jugable)
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = FLOOR_SHADER
	floor_mat.set_shader_parameter("base_col", Color(0.13, 0.14, 0.16))
	floor_mat.set_shader_parameter("fade_dist", 38.0)
	add_ground(170.0, floor_mat)
	add_bounds_circle(PLAY_RADIUS)

	# anillo dorado donde aparece Andro
	var gold := glow_mat(Color(0.95, 0.74, 0.36), 1.0)
	for rr in [[2.3, 2.35], [3.4, 3.43]]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = rr[0]
		tm.outer_radius = rr[1]
		tm.rings = 48
		tm.ring_segments = 6
		ring.mesh = tm
		ring.scale = Vector3(1, 0.04, 1)
		ring.position = spawn_pos + Vector3(0, -0.07, 0)
		ring.material_override = gold
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)

	# esferas pálidas y oscuras medio enterradas, dentro del área jugable
	var cream := mat(Color(0.74, 0.72, 0.66), 0.9)
	var dark := mat(Color(0.07, 0.08, 0.11), 0.35, 0.6)
	var spheres := [
		[Vector3(-13, 0, -17), 1.7, cream], [Vector3(14, 0, -22), 1.2, dark],
		[Vector3(-22, 0, 4), 2.4, dark], [Vector3(20, 0, 9), 1.5, cream],
		[Vector3(-7, 0, -27), 2.6, cream], [Vector3(15, 0, -28), 2.0, dark],
	]
	for s in spheres:
		var r: float = s[1]
		add_sphere((s[0] as Vector3) + Vector3(0, r * 0.45, 0), r, s[2], true)

	# losas altas y oscuras que se insinúan en la niebla: dan escala y marcan el borde sin mostrarlo
	var slab := mat(Color(0.06, 0.065, 0.09), 0.5, 0.4)
	for p in [Vector3(-24, 0, -22), Vector3(0, 0, -31), Vector3(25, 0, -20), Vector3(-31, 0, -2), Vector3(30, 0, 8)]:
		add_box((p as Vector3) + Vector3(0, 12, 0), Vector3(6, 24, 2.0), slab, true, atan2(p.x, p.z) + PI)

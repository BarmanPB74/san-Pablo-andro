class_name RingsScene
extends StageScene
## Cámara de los Anillos (ref. 83531): una rotonda de piedra húmeda con un óculo por el que cae un haz
## de luz sobre tres anillos enlazados que giran, y debajo, en un altar al que se sube por una escalera,
## una esfera de luz.

const SKY_SHADER := preload("res://stage/shaders/star_sky.gdshader")
const ROCK_SHADER := preload("res://stage/shaders/rock.gdshader")
const BEAM_SHADER := preload("res://stage/shaders/light_beam.gdshader")
const ARCH_SHADER := preload("res://stage/shaders/arch.gdshader")

const R := 17.0               # radio de la rotonda
const WALL_H := 18.0
const OCULUS_R := 3.0
const DOME_H := 12.0

var _rings: Array[MeshInstance3D] = []
var _orb: MeshInstance3D
var _orb_light: OmniLight3D


func _init() -> void:
	title = "La Cámara de los Anillos"
	spawn_pos = Vector3(0, 0.1, 11.6)
	spawn_yaw = 0.0
	spawn_pitch = 0.1


func _stone(a: Color, b: Color, scale := 0.4, strata := 0.25) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("col_a", a)
	m.set_shader_parameter("col_b", b)
	m.set_shader_parameter("noise_scale", scale)
	m.set_shader_parameter("strata", strata)
	m.set_shader_parameter("rough", 0.7)
	return m


func build() -> void:
	var sky := ShaderMaterial.new()
	sky.shader = SKY_SHADER
	sky.set_shader_parameter("zenith_col", Color(0.62, 0.72, 0.80))
	sky.set_shader_parameter("horizon_col", Color(0.70, 0.78, 0.84))
	sky.set_shader_parameter("band_strength", 0.0)
	sky.set_shader_parameter("star_amount", 0.0)
	make_environment(sky, Color(0.10, 0.145, 0.155), 0.011, 1.0, Color(0.7, 0.85, 1.0), 0.0)
	sun.visible = false
	set_flat_ambient(Color(0.22, 0.31, 0.33), 1.2)

	var wall_mat := _stone(Color(0.08, 0.125, 0.125), Color(0.30, 0.38, 0.36), 0.45, 0.3)
	var floor_mat := _stone(Color(0.06, 0.10, 0.10), Color(0.24, 0.31, 0.30), 0.3, 0.05)
	var moss := _stone(Color(0.03, 0.07, 0.04), Color(0.13, 0.24, 0.12), 0.7, 0.0)

	# suelo y rotonda (muro + cúpula con óculo) en una sola malla de revolución
	add_ground(60.0, floor_mat)
	var profile: Array = [Vector2(R, 0.0), Vector2(R, WALL_H)]
	var a_max := acos(OCULUS_R / R)
	for k in range(1, 9):
		var a := a_max * float(k) / 8.0
		profile.append(Vector2(R * cos(a), WALL_H + DOME_H * sin(a)))
	var dome := MeshInstance3D.new()
	dome.mesh = Geo.lathe(profile, 48, true)
	dome.material_override = wall_mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
	add_bounds_circle(R + 0.4, 30.0)

	# nichos en arco alrededor del muro
	var arch_mat := ShaderMaterial.new()
	arch_mat.shader = ARCH_SHADER
	for k in 10:
		var th := TAU * (float(k) + 0.5) / 10.0
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(5.2, 13.0)
		mi.mesh = q
		mi.material_override = arch_mat
		mi.position = Vector3(sin(th) * (R - 0.08), 7.6, cos(th) * (R - 0.08))
		mi.rotation.y = th + PI                 # mira hacia el centro
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

	# escalera de entrada, plataforma redonda y altar (todo con colisión; peldaños de 20 cm)
	for i in 6:
		add_box(Vector3(0, 0.1 * float(i + 1), 10.2 - float(i)), Vector3(5.6, 0.2 * float(i + 1), 1.0), floor_mat, true)
	add_cylinder(Vector3(0, 0.6, 0), 5.2, 1.2, floor_mat, true, 40)
	add_cylinder(Vector3(0, 0.7, 0), 3.5, 1.4, wall_mat, true, 36)
	add_cylinder(Vector3(0, 0.8, 0), 2.0, 1.6, floor_mat, true, 28)
	# musgo en los bordes de la escalera
	for sx in [-1.0, 1.0]:
		add_box(Vector3(sx * 3.1, 0.55, 8.2), Vector3(0.7, 1.1, 5.4), moss, true)

	# esfera de luz sobre el altar
	_orb = add_sphere(Vector3(0, 2.3, 0), 0.38, glow_mat(Color(1.0, 0.98, 0.94), 5.0), false)
	_orb_light = OmniLight3D.new()
	_orb_light.light_color = Color(1.0, 0.95, 0.88)
	_orb_light.light_energy = 2.2
	_orb_light.omni_range = 11.0
	_orb_light.position = Vector3(0, 2.4, 0)
	add_child(_orb_light)

	# anillos enlazados (giran despacio)
	var ring_mat := mat(Color(0.46, 0.50, 0.50), 0.5, 0.55)
	var rot0 := [Vector3(1.2, 0.0, 0.0), Vector3(0.35, 0.0, 1.05), Vector3(-0.5, 0.7, 0.0)]
	for i in 3:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 2.15
		tm.outer_radius = 2.7
		tm.rings = 40
		tm.ring_segments = 14
		r.mesh = tm
		r.material_override = ring_mat
		r.position = Vector3(float(i - 1) * 0.55, 9.5 + float(i - 1) * 0.35, 0)
		r.rotation = rot0[i]
		add_child(r)
		_rings.append(r)

	# luz del óculo: foco con sombras + haz translúcido
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.82, 0.92, 1.0)
	spot.light_energy = 18.0
	spot.spot_range = 40.0
	spot.spot_angle = 19.0
	spot.spot_attenuation = 0.5
	spot.shadow_enabled = true
	spot.shadow_bias = 0.06
	add_child(spot)
	spot.look_at_from_position(Vector3(0, WALL_H + DOME_H + 3.0, 0), Vector3(0, 0, 0), Vector3.RIGHT)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = OCULUS_R
	cm.bottom_radius = 5.2
	cm.height = WALL_H + DOME_H
	cm.radial_segments = 32
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := ShaderMaterial.new()
	bm.shader = BEAM_SHADER
	bm.set_shader_parameter("height", WALL_H + DOME_H)
	bm.set_shader_parameter("intensity", 0.8)
	beam.material_override = bm
	beam.position = Vector3(0, (WALL_H + DOME_H) * 0.5, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	add_trigger("altar", Vector3(0, 3.0, 0), Vector3(7.0, 4.0, 7.0))


func tick(delta: float, _player: Node3D) -> void:
	if _rings.size() == 3:
		_rings[0].rotate_y(delta * 0.22)
		_rings[1].rotate_z(delta * 0.17)
		_rings[2].rotate_x(-delta * 0.2)
	if _orb:
		_orb.position.y = 2.3 + sin(_t * 1.1) * 0.08
		_orb_light.position.y = _orb.position.y + 0.1
		_orb_light.light_energy = 2.2 + sin(_t * 2.3) * 0.15

class_name FountainScene
extends StageScene
## La Fuente (ref. 83530): una plaza de hormigón verdoso y niebla, un muro enorme con un rostro
## de piedra de boca abierta y, de la boca, una cascada fina que cae a un estanque negro.

const SKY_SHADER := preload("res://stage/shaders/star_sky.gdshader")
const ROCK_SHADER := preload("res://stage/shaders/rock.gdshader")
const FALL_SHADER := preload("res://stage/shaders/waterfall.gdshader")
const WATER_SHADER := preload("res://stage/shaders/pool_water.gdshader")

const WALL_Z := -21.0          # plano del muro
const FACE_Z := -19.5          # origen del relieve del rostro
const FACE_Y := 1.6            # base del rostro
const FACE_W := 9.0
const FACE_H := 12.0

var _mist: Array[MeshInstance3D] = []
var _fall_top := 4.6


func _init() -> void:
	title = "La Fuente"
	spawn_pos = Vector3(0, 0.1, 8)
	spawn_yaw = 0.0


static func _g(x: float, y: float, cx: float, cy: float, sx: float, sy: float, amp: float) -> float:
	var dx := (x - cx) / sx
	var dy := (y - cy) / sy
	return amp * exp(-(dx * dx + dy * dy))


## Relieve del rostro (u horizontal, v vertical desde la barbilla). Devuelve z local.
static func face_height(u: float, v: float) -> float:
	var f := 0.0
	f += _g(u, v, 0.0, 6.0, 4.2, 6.5, 0.9)                 # volumen general del rostro
	f += _g(u, v, -2.3, 6.0, 1.7, 2.2, 0.8)                # mejilla izq.
	f += _g(u, v, 2.3, 6.0, 1.7, 2.2, 0.8)                 # mejilla der.
	f += _g(u, v, 0.0, 8.6, 0.55, 2.3, 0.9)                # puente de la nariz
	f += _g(u, v, 0.0, 6.9, 0.85, 0.8, 1.0)                # punta de la nariz
	f += _g(u, v, -0.95, 6.6, 0.5, 0.5, 0.55)              # aletas
	f += _g(u, v, 0.95, 6.6, 0.5, 0.5, 0.55)
	f -= _g(u, v, -0.45, 6.25, 0.25, 0.22, 0.45)           # fosas nasales
	f -= _g(u, v, 0.45, 6.25, 0.25, 0.22, 0.45)
	f -= _g(u, v, 0.0, 5.45, 0.35, 0.4, 0.3)               # surco
	f += _g(u, v, -0.7, 4.7, 1.0, 0.5, 0.75)               # labio superior (arco)
	f += _g(u, v, 0.7, 4.7, 1.0, 0.5, 0.75)
	f += _g(u, v, 0.0, 4.55, 0.4, 0.4, 0.2)
	f += _g(u, v, 0.0, 3.1, 1.7, 0.7, 1.0)                 # labio inferior
	f -= _g(u, v, 0.0, 3.95, 1.45, 0.42, 2.2)              # boca abierta
	f += _g(u, v, 0.0, 1.5, 1.6, 1.3, 0.8)                 # barbilla
	f -= _g(u, v, -2.0, 9.7, 1.0, 0.55, 0.8)               # cuencas
	f -= _g(u, v, 2.0, 9.7, 1.0, 0.55, 0.8)
	return f


func _rock(a: Color, b: Color, scale := 0.45, strata := 0.15) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("col_a", a)
	m.set_shader_parameter("col_b", b)
	m.set_shader_parameter("noise_scale", scale)
	m.set_shader_parameter("strata", strata)
	m.set_shader_parameter("rough", 0.78)
	return m


func build() -> void:
	var sky := ShaderMaterial.new()
	sky.shader = SKY_SHADER
	sky.set_shader_parameter("zenith_col", Color(0.015, 0.04, 0.05))
	sky.set_shader_parameter("horizon_col", Color(0.04, 0.09, 0.10))
	sky.set_shader_parameter("band_strength", 0.0)
	sky.set_shader_parameter("star_amount", 0.0)
	make_environment(sky, Color(0.06, 0.12, 0.135), 0.016, 1.0,
		Color(0.6, 0.82, 0.9), 0.9, Vector3(0.1, -0.6, -0.8))
	set_flat_ambient(Color(0.16, 0.25, 0.28), 1.2)

	var concrete := _rock(Color(0.07, 0.125, 0.14), Color(0.23, 0.34, 0.36))
	var dark := _rock(Color(0.04, 0.07, 0.08), Color(0.13, 0.2, 0.22))
	add_ground(300.0, concrete)

	# muro principal y el bloque que lo corta por arriba
	add_box(Vector3(0, 13, WALL_Z - 1.5), Vector3(46, 26, 3), concrete, true)
	add_box(Vector3(-6, 17.5, WALL_Z + 3.0), Vector3(30, 6, 8), dark, false)
	add_box(Vector3(-19, 9, WALL_Z + 2.0), Vector3(8, 18, 6), concrete, true)
	# muros bajos laterales con repisa (como bancas largas)
	for sx in [-1.0, 1.0]:
		add_box(Vector3(sx * 17.0, 0.7, -4.0), Vector3(2.4, 1.4, 34), concrete, true)
		add_box(Vector3(sx * 17.0, 1.55, -4.0), Vector3(3.2, 0.3, 34), dark, false)

	# el rostro: relieve sobre el muro
	var nu := 72
	var nv := 96
	var face_fn := func(i: int, j: int) -> Vector3:
		var uu := (float(i) / float(nu) - 0.5) * FACE_W
		var vv := float(j) / float(nv) * FACE_H
		var ex := minf(uu + FACE_W * 0.5, FACE_W * 0.5 - uu)
		var ey := minf(vv, FACE_H - vv)
		var edge := smoothstep(0.0, 0.9, minf(ex, ey))
		var z := -1.5 + (1.5 + face_height(uu, vv)) * edge
		return Vector3(uu, vv, z)
	var face := MeshInstance3D.new()
	face.name = "Rostro"
	face.mesh = Geo.grid_mesh(nu, nv, face_fn, false)
	face.material_override = concrete
	face.position = Vector3(0, FACE_Y, FACE_Z)
	add_child(face)

	# cascada que sale del labio inferior
	var mouth_y := FACE_Y + 3.35
	_fall_top = mouth_y
	var fall := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(1.25, mouth_y)
	fall.mesh = fq
	var fm := ShaderMaterial.new()
	fm.shader = FALL_SHADER
	fall.material_override = fm
	fall.position = Vector3(0, mouth_y * 0.5, FACE_Z + 1.55)
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fall)

	# estanque negro con curb de piedra
	var pool := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(26, 16)
	pool.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	wm.set_shader_parameter("center", Vector2(0.0, FACE_Z + 1.9))
	pool.material_override = wm
	pool.position = Vector3(0, 0.04, -12.5)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	for c in [[Vector3(0, 0.06, -4.3), Vector3(27, 0.12, 0.6)], [Vector3(-13.3, 0.06, -12.5), Vector3(0.6, 0.12, 16.6)],
			[Vector3(13.3, 0.06, -12.5), Vector3(0.6, 0.12, 16.6)]]:
		add_box(c[0], c[1], dark, false)

	# neblina al pie de la cascada (sprites de luz suave)
	var mist_tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0.8, 0.9, 0.95, 0.35), Color(0.6, 0.75, 0.82, 0.1), Color(0.5, 0.65, 0.75, 0.0)])
	mist_tex.gradient = g
	mist_tex.fill = GradientTexture2D.FILL_RADIAL
	mist_tex.fill_from = Vector2(0.5, 0.5)
	mist_tex.fill_to = Vector2(1.0, 0.5)
	mist_tex.width = 128
	mist_tex.height = 128
	var mist_mat := StandardMaterial3D.new()
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.albedo_texture = mist_tex
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mist_mat.disable_receive_shadows = true
	for i in 6:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(6.0, 6.0)
		mi.mesh = q
		mi.material_override = mist_mat
		mi.position = Vector3(randf_range(-1.6, 1.6), 1.2 + float(i) * 0.5, FACE_Z + 2.4 + randf_range(-0.5, 1.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mist.append(mi)

	# foco frío sobre el rostro y luz fría baja en el estanque
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.7, 0.9, 1.0)
	spot.light_energy = 16.0
	spot.spot_range = 46.0
	spot.spot_angle = 26.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = false
	add_child(spot)
	spot.look_at_from_position(Vector3(0, 20, 2), Vector3(0, 7, FACE_Z), Vector3.UP)
	var low := OmniLight3D.new()
	low.light_color = Color(0.4, 0.75, 0.85)
	low.light_energy = 1.4
	low.omni_range = 12.0
	low.position = Vector3(0, 1.6, FACE_Z + 3.0)
	add_child(low)

	# límites: plaza cerrada
	add_bounds_circle(34.0)
	add_trigger("estanque", Vector3(0, 2.0, -7.0), Vector3(16.0, 4.0, 5.0))


func tick(_delta: float, _player: Node3D) -> void:
	for i in _mist.size():
		var m := _mist[i]
		m.position.y = 1.2 + fposmod(_t * 0.25 + float(i) * 0.5, 3.4)
		m.scale = Vector3.ONE * (0.8 + 0.25 * sin(_t * 0.7 + float(i)))

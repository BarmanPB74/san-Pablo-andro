class_name PlanetsScene
extends StageScene
## Camino de los Planetas (ref. 83529): un cañón de arenisca roja bajo un cielo negro, columnas
## griegas a los lados y una alfombra de franjas con planetas que sube hasta una hilera de astros.

const SKY_SHADER := preload("res://stage/shaders/star_sky.gdshader")
const ROCK_SHADER := preload("res://stage/shaders/rock.gdshader")

const PATH_W := 5.4
const BAND_LEN := 6.0
const PATH_START := 12.0     # z donde empieza la alfombra
const PATH_END := -56.0


func _init() -> void:
	title = "Camino de los Planetas"
	spawn_pos = Vector3(0, 0.1, 17)
	spawn_yaw = 0.0
	spawn_pitch = 0.08


func _rock_mat(a: Color, b: Color, scale := 0.35, strata := 0.8) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("col_a", a)
	m.set_shader_parameter("col_b", b)
	m.set_shader_parameter("noise_scale", scale)
	m.set_shader_parameter("strata", strata)
	return m


func build() -> void:
	var sky := ShaderMaterial.new()
	sky.shader = SKY_SHADER
	sky.set_shader_parameter("zenith_col", Color(0.0, 0.0, 0.004))
	sky.set_shader_parameter("horizon_col", Color(0.02, 0.01, 0.015))
	sky.set_shader_parameter("band_strength", 0.45)
	sky.set_shader_parameter("star_amount", 1.0)
	make_environment(sky, Color(0.07, 0.035, 0.03), 0.0055, 1.0,
		Color(1.0, 0.9, 0.78), 1.0, Vector3(0.15, -0.5, -1.0))
	set_flat_ambient(Color(0.23, 0.2, 0.19), 0.9)
	env.sky.radiance_size = Sky.RADIANCE_SIZE_512

	# suelo de arena roja
	add_ground(500.0, _rock_mat(Color(0.30, 0.20, 0.14), Color(0.60, 0.44, 0.31), 0.22, 0.0))

	# alfombra con franjas (rojo, azul noche, naranja) y un filo dorado
	var red := mat(Color(0.58, 0.10, 0.05), 0.95)
	var navy := mat(Color(0.05, 0.08, 0.16), 0.95)
	var orange := mat(Color(0.80, 0.46, 0.10), 0.95)
	var order := [red, navy, orange, red, navy, orange, red, navy, orange, red, navy]
	var z := PATH_START
	for i in order.size():
		var cz := z - BAND_LEN * 0.5
		add_box(Vector3(0, 0.025, cz), Vector3(PATH_W, 0.05, BAND_LEN), order[i], false)
		z -= BAND_LEN
	var trim := mat(Color(0.7, 0.55, 0.25), 0.5, 0.4)
	for sx in [-1.0, 1.0]:
		add_box(Vector3(sx * (PATH_W * 0.5 + 0.06), 0.03, (PATH_START + z) * 0.5),
			Vector3(0.12, 0.07, PATH_START - z), trim, false)

	# planetas sobre la alfombra, uno por franja alterna
	var cols := [Color(0.84, 0.81, 0.72), Color(0.6, 0.18, 0.10), Color(0.30, 0.40, 0.55), Color(0.78, 0.5, 0.28), Color(0.7, 0.7, 0.72)]
	for i in 5:
		var pz := PATH_START - BAND_LEN * (1.0 + float(i) * 2.0) + 0.5
		var r := 0.55 + 0.1 * float(i % 3)
		var sm := mat(cols[i], 0.7)
		add_sphere(Vector3(0.0 + (-0.9 if i % 2 == 0 else 0.9) * 0.0, r, pz), r, sm, true)

	# hilera de astros en el cielo, al fondo del camino
	var sky_cols := [Color(0.62, 0.60, 0.58), Color(0.72, 0.22, 0.12), Color(0.36, 0.5, 0.78), Color(0.85, 0.55, 0.28), Color(0.88, 0.86, 0.8)]
	for i in 5:
		var pm := mat(sky_cols[i], 0.6)
		pm.emission_enabled = true
		pm.emission = sky_cols[i]
		pm.emission_energy_multiplier = 0.35
		add_sphere(Vector3(0, 12.0 + float(i) * 9.0, -92.0), 2.4 + 0.25 * float(i % 3), pm, false)

	# columnas griegas (dos pares) y tambores caídos
	var stone := _rock_mat(Color(0.50, 0.43, 0.34), Color(0.86, 0.78, 0.66), 0.5, 0.1)
	var col_mesh := Geo.column(1.05, 20.0)
	for zc in [4.0, -14.0]:
		for sx in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = col_mesh
			mi.material_override = stone
			mi.position = Vector3(sx * 9.2, 0, zc)
			add_child(mi)
			_add_cyl_collider(mi.position, 1.15, 20.0)
	var drum := Geo.boulder(1.0, 5)
	for d in [[Vector3(-6.5, 0.5, -30.0), 0.9], [Vector3(7.2, 0.4, -41.0), 0.7], [Vector3(-8.5, 0.6, -8.0), 1.0]]:
		var mi2 := MeshInstance3D.new()
		mi2.mesh = drum
		mi2.material_override = stone
		mi2.position = d[0]
		mi2.scale = Vector3.ONE * float(d[1])
		add_child(mi2)

	# paredes del cañón a ambos lados + rocas sueltas
	var rock := _rock_mat(Color(0.15, 0.085, 0.06), Color(0.50, 0.30, 0.20), 0.18, 0.5)
	var cliff_a := Geo.cliff(110.0, 17.0, 6.0, 11)
	var cliff_b := Geo.cliff(110.0, 19.0, 6.0, 37)
	for side in [-1.0, 1.0]:
		var mi3 := MeshInstance3D.new()
		mi3.mesh = cliff_a if side < 0 else cliff_b
		mi3.material_override = rock
		mi3.position = Vector3(side * 19.0, 0, -30.0)
		mi3.rotation.y = -side * PI * 0.5       # la cara mira al camino
		add_child(mi3)
	var rg := RandomNumberGenerator.new()
	rg.seed = 2024
	var boul := Geo.boulder(1.0, 9)
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var mi4 := MeshInstance3D.new()
		mi4.mesh = boul
		mi4.material_override = rock
		mi4.position = Vector3(side * rg.randf_range(11.5, 16.0), 0.3, rg.randf_range(-62.0, 16.0))
		mi4.scale = Vector3.ONE * rg.randf_range(0.8, 2.2)
		mi4.rotation.y = rg.randf() * TAU
		add_child(mi4)

	# límites invisibles: el cañón es un pasillo
	var wall := Vector3(1.0, 30.0, 110.0)
	for sx in [-1.0, 1.0]:
		_add_invisible(Vector3(sx * 15.5, 15.0, -30.0), wall)
	_add_invisible(Vector3(0, 15.0, -74.0), Vector3(40.0, 30.0, 1.0))
	_add_invisible(Vector3(0, 15.0, 24.0), Vector3(40.0, 30.0, 1.0))

	# objetivo: llegar al último astro de la alfombra
	add_trigger("planeta_final", Vector3(0, 2.5, PATH_END + 2.0), Vector3(9.0, 5.0, 6.0))


func _add_cyl_collider(pos: Vector3, radius: float, height: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos + Vector3(0, height * 0.5, 0)
	add_child(sb)


func _add_invisible(pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	sb.position = pos
	add_child(sb)

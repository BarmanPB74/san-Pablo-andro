extends Node3D
## Escena de retrato del personaje. Variante por variable de entorno CHAR_SHOT:
##   lineup (defecto): frente, 3/4, espalda, perfil caminando.
##   close: primer plano 3/4 a 3 m.   gaits: walk/run/sprint/jump.   stumble: secuencia de caída.

func _ready() -> void:
	var variant := OS.get_environment("CHAR_SHOT")
	if variant == "":
		variant = "lineup"
	ClayStyle.enabled = OS.get_environment("CLAY") == "1"
	_env()
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = Palette.sidewalk()
	add_child(floor_mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	match variant:
		"close":
			var m := _model(Vector3.ZERO, deg_to_rad(30.0), "idle", 0.0, 0.0)
			cam.position = Vector3(0, 1.1, 3.2)
			cam.look_at(Vector3(0, 0.92, 0))
			cam.fov = 40.0
		"face":
			var m2 := _model(Vector3.ZERO, deg_to_rad(20.0), "idle", 0.0, 0.0)
			cam.position = Vector3(0, 1.62, 1.1)
			cam.look_at(Vector3(0, 1.6, 0))
			cam.fov = 35.0
		"gaits":
			_model(Vector3(-2.4, 0, 0), -PI * 0.5, "walk", 1.6, 1.2)
			_model(Vector3(-0.8, 0, 0), -PI * 0.5, "run", 4.5, 1.2)
			_model(Vector3(0.8, 0, 0), -PI * 0.5, "sprint", 7.0, 1.3)
			_model(Vector3(2.4, 0, 0), -PI * 0.5, "jump", 3.0, 0.0)
			cam.position = Vector3(0, 1.1, 8.5)
			cam.look_at(Vector3(0, 0.9, 0))
		"cycle":
			var sp := float(OS.get_environment("CHAR_SPEED")) if OS.get_environment("CHAR_SPEED") != "" else 4.5
			for i in 6:
				_model(Vector3(-3.75 + i * 1.5, 0, 0), -PI * 0.5, "run", sp, i * TAU / 6.0)
			cam.position = Vector3(0, 1.0, 9.5)
			cam.look_at(Vector3(0, 0.9, 0))
		"actions":
			# Acciones de la fase 3.3 (perfil): agachado, agachado caminando, empujar, golpes 1-3, subir/bajar del auto
			var defs := [["crouch", 0.0, 0, 0.0], ["crouch_walk", 1.1, 0, 0.9], ["push", 1.4, 0, 0.9],
				["punch", 0.0, 0, 0.36], ["punch", 0.0, 1, 0.36], ["punch", 0.0, 2, 0.36],
				["enter_vehicle", 0.0, 0, 0.3], ["exit_vehicle", 0.0, 0, 0.0]]
			for i in defs.size():
				var d: Array = defs[i]
				var mm := PlayerModel.new()
				mm.position = Vector3(-4.9 + i * 1.4, 0, 0)
				mm.rotation.y = -PI * 0.5 + PI
				add_child(mm)
				mm.punch_idx = d[2]
				mm.punch_t = d[3] * [0.34, 0.38, 0.5][d[2]] if d[0] == "punch" else 0.0
				mm.snap_pose(d[0], d[1], 1.2)
				if d[0] == "enter_vehicle" or d[0] == "exit_vehicle":
					for f in 30:
						mm.animate(d[0], 0.0, 1.0 / 60.0)
			cam.position = Vector3(0, 1.0, 10.5)
			cam.look_at(Vector3(0, 0.85, 0))
		"night":
			_model(Vector3(-0.6, 0, 0), deg_to_rad(150.0), "idle", 0.0, 0.0)
			_model(Vector3(0.7, 0, 0), deg_to_rad(-40.0), "idle", 0.0, 0.0)
			cam.position = Vector3(0, 1.3, 3.6)
			cam.look_at(Vector3(0, 1.0, 0))
			for n in get_children():
				if n is DirectionalLight3D:
					n.light_energy *= 0.08
				if n is WorldEnvironment:
					n.environment.background_energy_multiplier = 0.05
					n.environment.ambient_light_energy = 0.08
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(1.5, 3.0, 1.5)
			lamp.light_color = Color(1.0, 0.75, 0.45)
			lamp.light_energy = 1.2
			lamp.omni_range = 7.0
			add_child(lamp)
		"stumble":
			var times := [0.2, 0.5, 1.0, 1.25, 1.45]
			for i in times.size():
				var mm := _model(Vector3(-3.2 + i * 1.6, 0, -0.6), -PI * 0.5, "idle", 0.0, 0.0)
				var steps := int(times[i] * 60.0)
				for f in steps:
					mm.animate("stumble", 0.0, 1.0 / 60.0)
			cam.position = Vector3(0, 1.4, 8.5)
			cam.look_at(Vector3(0, 0.6, 0))
		_:
			_model(Vector3(-2.1, 0, 0), 0.0, "idle", 0.0, 0.0)
			_model(Vector3(-0.7, 0, 0), deg_to_rad(35.0), "idle", 0.0, 0.0)
			_model(Vector3(0.7, 0, 0), PI, "idle", 0.0, 0.0)
			_model(Vector3(2.1, 0, 0), -PI * 0.5, "walk", 1.6, 1.25)
			cam.position = Vector3(0, 1.2, 7.0)
			cam.look_at(Vector3(0, 0.95, 0))


	if ClayStyle.enabled:
		add_child(ClayStyle.new())


func _model(pos: Vector3, yaw: float, state: String, speed: float, phase: float) -> PlayerModel:
	# Nota: el modelo mira hacia -Z; yaw = 0 lo pone de espaldas a la cámara en +Z,
	# así que giramos PI para que "0" sea de frente.
	var m := PlayerModel.new()
	m.position = pos
	m.rotation.y = yaw + PI
	add_child(m)
	m.snap_pose(state, speed, phase)
	return m


func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.3, 0.38, 0.5)
	psm.sky_horizon_color = Color(0.55, 0.58, 0.62)
	psm.ground_horizon_color = Color(0.4, 0.4, 0.42)
	psm.ground_bottom_color = Color(0.2, 0.2, 0.22)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.2
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(-35.0), 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(150.0), 0)
	fill.light_energy = 0.35
	add_child(fill)

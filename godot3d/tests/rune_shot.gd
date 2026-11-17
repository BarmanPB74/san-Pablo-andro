extends SceneTree
## Captura de las runas del dobladillo de Andro según el nivel (0..33), vistas desde la espalda.
## Uso: xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##        -s res://tests/rune_shot.gd -- <nivel> <salida.png> <cerca|lejos|aura> [carga 0..1]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var level: int = int(a[0]) if a.size() > 0 else 33
	var out: String = a[1] if a.size() > 1 else "/tmp/runes.png"
	var view: String = a[2] if a.size() > 2 else "cerca"
	var charge: float = float(a[3]) if a.size() > 3 else 0.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.21, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.66)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.6
	root.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.3, -0.6, -0.8), Vector3.UP)
	var m := AndroCloak.new()
	root.add_child(m)
	m.position = Vector3(0, 0.42, 0)
	m.level = level
	m.charge = charge
	for i in 40:
		m.animate("idle", 0.0, 1.0 / 60.0)
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	if view == "cerca":
		cam.global_position = Vector3(0.0, 1.0, 1.9)
		cam.look_at(Vector3(0.0, 0.86, 0.7))
	elif view == "aura":
		cam.global_position = Vector3(0.0, 1.6, 6.0)
		cam.look_at(Vector3(0.0, 1.3, 0.0))
	else:
		cam.global_position = Vector3(0.0, 1.8, 4.2)
		cam.look_at(Vector3(0.0, 1.0, 0.0))
	cam.current = true
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

extends SceneTree
## Retrato de Andro (AndroCloak) con luz neutra tipo ref. 83527 (cielo gris cubierto).
## Uso: xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##        -s res://tests/andro_cloak_shot.gd -- <vista: front|side|back|34> <salida.png> <pose: idle|walk|run|sprint|punch|jump|crouch>

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var view: String = a[0] if a.size() > 0 else "front"
	var out: String = a[1] if a.size() > 1 else "/tmp/cloak.png"
	var pose: String = a[2] if a.size() > 2 else "idle"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.64, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.75)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.4, -0.8, -0.5), Vector3.UP)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fl.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.16, 0.21, 0.1)
	gm.roughness = 1.0
	fl.material_override = gm
	root.add_child(fl)
	var m := AndroCloak.new()
	root.add_child(m)
	m.position = Vector3(0, 0.42, 0)
	await process_frame
	var state := "idle"
	var speed := 0.0
	match pose:
		"walk": state = "walk"; speed = 1.6
		"run": state = "run"; speed = 4.5
		"sprint": state = "sprint"; speed = 7.0
		"punch": state = "punch"
		"jump": state = "jump"
		"crouch": state = "crouch"
	m.rotation.y = 0.0
	var dt := 1.0 / 60.0
	var z := 0.0
	for i in 90:
		if speed > 0.0:
			z -= speed * dt
		m.position = Vector3(0, 0.42, z)
		if state == "punch":
			m.punch_idx = 0
			m.punch_t = 0.17
		m.animate(state, speed, dt)
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	var c := m.position + Vector3(0, 1.2, 0)
	var dir := Vector3(0, 0, 1)
	match view:
		"side": dir = Vector3(1, 0, 0)
		"back": dir = Vector3(0, 0, -1)
		"34": dir = Vector3(0.6, 0, 0.8)
	cam.global_position = c + dir * 7.0 + Vector3(0, 0.3, 0)
	cam.look_at(c)
	cam.current = true
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

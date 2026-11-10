extends SceneTree
## Captura del juego completo (main.tscn).
## Uso: xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tests/game_shot.gd -- <preset> <foot|drive|aerial> <salida.png>

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var preset: String = a[0] if a.size() > 0 else "overcast_day"
	var mode: String = a[1] if a.size() > 1 else "foot"
	var out: String = a[2] if a.size() > 2 else "/tmp/game.png"
	var main: Node = load("res://main.tscn").instantiate()
	main.set("time_of_day", preset)
	root.add_child(main)
	for i in 30: await physics_frame
	var p: Node3D = get_nodes_in_group("player")[0]
	if mode == "drive":
		var best: Node3D = null
		for v in get_nodes_in_group("vehicle"):
			if v.get("kind") == "taxi" and (best == null or v.global_position.length() < best.global_position.length()):
				best = v
		p.call("enter_vehicle", best)
		Input.action_press("move_forward")
		for i in 150: await physics_frame
		Input.action_press("move_left")
		for i in 25: await physics_frame
		Input.action_release("move_left")
		for i in 20: await physics_frame
	elif mode == "foot":
		Input.action_press("move_forward")
		for i in 50: await physics_frame
		Input.action_press("move_right")
		for i in 20: await physics_frame
	elif mode == "aerial":
		var cam := Camera3D.new()
		cam.far = 2600.0
		root.add_child(cam)
		cam.global_position = Vector3(70, 55, 90)
		cam.look_at(Vector3(-20, 0, -10))
		cam.current = true
	for i in 20: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit()

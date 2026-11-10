extends SceneTree
## Captura mirando hacia la copa de los árboles (para revisar manchas del follaje).
## Uso: xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tests/canopy_shot.gd -- <preset> <salida.png>

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var preset: String = a[0] if a.size() > 0 else "overcast_day"
	var out: String = a[1] if a.size() > 1 else "/tmp/canopy.png"
	var main: Node = load("res://main.tscn").instantiate()
	main.set("time_of_day", preset)
	root.add_child(main)
	for i in 30: await physics_frame
	var p: Node3D = get_nodes_in_group("player")[0]
	var cam := Camera3D.new()
	cam.fov = 75.0
	root.add_child(cam)
	cam.current = true
	cam.look_at_from_position(p.global_position + Vector3(4.5, 1.2, 4.5), p.global_position + Vector3(0.0, 8.5, 0.0))
	for i in 20: await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit()

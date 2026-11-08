extends SceneTree
## Captura del mapa real enfocando vehículos estacionados (F2-09). Args: <preset> <kind> <salida>
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var main: Node = load("res://main.tscn").instantiate()
	main.set("time_of_day", a[0])
	root.add_child(main)
	for i in 40: await physics_frame
	var target: Node3D = null
	for v in root.get_tree().get_nodes_in_group("vehicle"):
		if (v as Vehicle).kind == a[1]:
			target = v
			break
	var cam := Camera3D.new()
	cam.far = 2600.0
	cam.fov = 55.0
	root.add_child(cam)
	var b := target.global_basis
	cam.global_position = target.global_position - b.z * 5.5 + b.x * 3.2 + Vector3.UP * 1.7
	cam.look_at(target.global_position + Vector3.UP * 0.8 + b.z * 1.0)
	cam.current = true
	for i in 25: await process_frame
	root.get_viewport().get_texture().get_image().save_png(a[2])
	print("SHOT ", a[2], " at ", target.global_position)
	quit()

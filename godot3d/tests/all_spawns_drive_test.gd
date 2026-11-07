extends SceneTree
## Verifica que cada auto estacionado del mapa puede arrancar y avanzar.

func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 60: await physics_frame
	var fails := 0
	var dummy := Node3D.new()
	root.add_child(dummy)
	for v in get_nodes_in_group("vehicle"):
		var start: Vector3 = v.global_position
		var start_xf: Transform3D = v.global_transform
		v.enter(dummy)
		Input.action_press("move_forward")
		for i in 180: await physics_frame
		Input.action_release("move_forward")
		var kmh: float = v.get_speed_kmh()
		var moved := start.distance_to(v.global_position)
		var ok := kmh > 20.0 and moved > 10.0
		print("  %s %-7s %5.0f km/h  %5.1f m" % ["OK  " if ok else "FAIL", v.get("kind"), kmh, moved])
		if not ok: fails += 1
		v.exit()
		# Devuelve el auto a su puesto para que no estorbe al siguiente.
		v.global_transform = start_xf
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
		for i in 30: await physics_frame
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(fails)

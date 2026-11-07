extends SceneTree
## Prueba de integración: carga main.tscn completo y recorre el flujo
## caminar → subirse a un auto → manejar → bajarse.
## Uso: godot --headless --fixed-fps 60 -s res://tests/integration_test.gd

var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(60)
	var players := get_nodes_in_group("player")
	check(players.size() == 1, "hay un jugador")
	var vehicles := get_nodes_in_group("vehicle")
	check(vehicles.size() >= 6, "vehículos generados: %d" % vehicles.size())
	check(get_nodes_in_group("camera_rig").size() == 1, "hay CameraRig")
	var p: Node3D = players[0]
	var y0 := p.global_position.y
	await frames(60)
	check(absf(p.global_position.y - y0) < 0.5, "el jugador está parado sobre el suelo (y=%.2f)" % p.global_position.y)

	# Caminar 2 s hacia adelante
	var start := p.global_position
	Input.action_press("move_forward")
	await frames(120)
	Input.action_release("move_forward")
	check(p.global_position.distance_to(start) > 4.0, "camina/corre (%.1f m)" % p.global_position.distance_to(start))

	# Ir al taxi más cercano y subirse
	var v: Node3D = vehicles[0]
	var best := 1e9
	for c in vehicles:
		var d: float = p.global_position.distance_to(c.global_position)
		if d < best:
			best = d
			v = c
	p.global_position = v.get_entry_point() + Vector3(0, 0.1, 0)
	p.velocity = Vector3.ZERO
	await frames(20)
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(90)
	check(p.get("current_vehicle") == v and v.is_occupied(), "se sube al vehículo (%s)" % v.get("kind"))

	# Manejar 4 s
	Input.action_press("move_forward")
	await frames(240)
	var kmh: float = v.get_speed_kmh()
	Input.action_release("move_forward")
	check(kmh > 25.0, "el auto acelera por la calle (%.0f km/h)" % kmh)
	# Frenar: move_back frena y, ya detenido, pasa a reversa (como en GTA)
	Input.action_press("move_back")
	var t := 0
	while v.get_forward_speed() > 0.5 and t < 300:
		await frames(1)
		t += 1
	Input.action_release("move_back")
	check(t < 300, "frena hasta detenerse en %.1f s" % (t / 60.0))
	await frames(30)

	# Bajarse
	Input.action_press("interact")
	await frames(2)
	Input.action_release("interact")
	await frames(60)
	check(p.get("current_vehicle") == null and not v.is_occupied(), "se baja del vehículo")
	check(p.visible, "el jugador vuelve a ser visible")
	check(p.global_position.distance_to(v.global_position) < 6.0, "aparece junto al auto")

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(fails)

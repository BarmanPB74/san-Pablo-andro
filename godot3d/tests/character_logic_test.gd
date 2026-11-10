extends SceneTree
## Test headless del personaje:
##   /tmp/godot/... --headless --path . -s res://tests/character_logic_test.gd
## Verifica: aceleración progresiva, sprint, subir escalón 0.30 m, entrar/salir de auto, atropello.

var fails := 0
var scene: Node3D
var player: Player


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func():
		print("RESULT: TIMEOUT")
		quit(2))
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   ", msg)
	else:
		print("  FAIL ", msg)
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _hspeed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact"]:
		Input.action_release(a)


func _tap(action: String) -> void:
	await physics_frame
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)


func _run() -> void:
	await process_frame
	var packed: PackedScene = load("res://tests/scenes/character_test.tscn")
	scene = packed.instantiate()
	root.add_child(scene)
	await _frames(30)
	player = scene.get("player")
	_check(player != null and player.is_in_group("player"), "Player en grupo 'player'")
	_check(player.collision_layer == 2 and player.collision_mask == (1 | 4 | 8), "capas: layer 2, mask 1|3|4")
	_check(get_first_node_in_group("camera_rig") != null, "CameraRig en grupo 'camera_rig'")
	_check(player.is_on_floor(), "parado en el piso (y=%.3f)" % player.global_position.y)

	# 1) Aceleración progresiva al correr
	print("[1] aceleración")
	player.global_position = Vector3(40, 0.05, 60)
	await _frames(10)
	Input.action_press("move_forward")
	var samples: Array[float] = []
	for i in 90:
		await physics_frame
		if i in [2, 8, 15, 30, 60, 89]:
			samples.append(_hspeed())
	print("    v(t): ", samples)
	_check(samples[0] < 1.0, "no es instantánea (v@3f=%.2f < 1.0)" % samples[0])
	var mono := true
	for i in range(1, samples.size()):
		if samples[i] + 0.05 < samples[i - 1]:
			mono = false
	_check(mono, "velocidad creciente")
	_check(absf(samples[-1] - 4.5) < 0.4, "llega a correr ~4.5 (%.2f)" % samples[-1])

	# 2) Sprint
	print("[2] sprint")
	Input.action_press("sprint")
	var t_sprint := 0
	for i in 240:
		await physics_frame
		if _hspeed() > 6.5 and t_sprint == 0:
			t_sprint = i
	_check(_hspeed() > 6.6 and _hspeed() < 7.3, "velocidad de sprint ~7 (%.2f)" % _hspeed())
	_check(t_sprint > 20, "sprint progresivo (%d frames de 4.5 a 6.5)" % t_sprint)
	_check(player.state == "sprint", "estado sprint (%s)" % player.state)
	# Soltar: desaceleración con inercia
	_release_all()
	await _frames(10)
	var v_after := _hspeed()
	_check(v_after > 3.0, "inercia al soltar (v@10f=%.2f)" % v_after)
	await _frames(120)
	_check(_hspeed() < 0.1 and player.state == "idle", "se detiene -> idle (%.2f, %s)" % [_hspeed(), player.state])

	# 3) Derrape: sprint al norte y luego cambio brusco al sur
	print("[3] plant/derrape")
	player.global_position = Vector3(0, 0.05, 60)
	await _frames(5)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(150)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await _frames(2)
	_check(player.get("_skidding") == true, "derrapa al invertir a %.1f m/s" % _hspeed())
	await _frames(90)
	var fwd := Vector3(-sin(player.get_facing()), 0, -cos(player.get_facing()))
	_check(fwd.z > 0.9 and player.velocity.z > 2.0, "termina corriendo al sur (vz=%.2f)" % player.velocity.z)
	_release_all()
	await _frames(90)

	# 4) Escalón de 0.30 m (bloque en x=23..26)
	print("[4] escalón 0.30 m")
	player.global_position = Vector3(18, 0.05, 0)
	player.velocity = Vector3.ZERO
	await _frames(10)
	Input.action_press("move_right")
	var max_y := 0.0
	for i in 150:
		await physics_frame
		max_y = maxf(max_y, player.global_position.y)
		if player.global_position.x > 24.0:
			break
	_release_all()
	await _frames(10)
	_check(player.global_position.x > 23.5, "pasó el borde (x=%.2f)" % player.global_position.x)
	_check(player.global_position.y > 0.27 and player.global_position.y < 0.36, "encima del escalón (y=%.3f)" % player.global_position.y)

	# 4c) Sardinel de 0.35 m (x=-10..-6) y escalera de 4 peldaños de 0.17 m
	print("[4c] sardinel 0.35 m + escalera")
	player.global_position = Vector3(-2.5, 0.05, -6)
	player.velocity = Vector3.ZERO
	await _frames(10)
	Input.action_press("move_left")
	await _frames(90)
	_release_all()
	await _frames(20)
	_check(player.global_position.x < -6.5 and player.global_position.y > 0.33, "sube sardinel 0.35 (x=%.2f y=%.3f)" % [player.global_position.x, player.global_position.y])
	player.global_position = Vector3(0, 0.05, -10)
	player.velocity = Vector3.ZERO
	await _frames(10)
	Input.action_press("move_forward")
	await _frames(100)
	_release_all()
	await _frames(20)
	_check(player.global_position.y > 0.6, "sube escalera (y=%.3f z=%.2f)" % [player.global_position.y, player.global_position.z])

	# 4b) Salto
	print("[4b] salto")
	player.global_position = Vector3(0, 0.05, 30)
	player.velocity = Vector3.ZERO
	await _frames(20)
	var y0 := player.global_position.y
	await _tap("jump")
	var peak := y0
	var saw_jump := false
	for i in 90:
		await physics_frame
		peak = maxf(peak, player.global_position.y)
		saw_jump = saw_jump or player.state == "jump"
	_check(saw_jump and peak - y0 > 0.4 and peak - y0 < 0.95, "salto modesto (%.2f m)" % (peak - y0))
	_check(player.is_on_floor(), "aterriza")

	# 5) Vehículo
	var v: VehicleBody3D = scene.get("vehicle")
	if v == null:
		print("[5] SIN vehículo (vehicle_factory no disponible) — se omite")
	else:
		print("[5] entrar/salir de vehículo")
		await _frames(60)
		var ep: Vector3 = v.get_entry_point()
		player.global_position = ep + Vector3(2.2, 0.1, 0.8)
		player.velocity = Vector3.ZERO
		await _frames(15)
		await _tap("interact")
		var entered := false
		for i in 300:
			await physics_frame
			if i % 30 == 0:
				print("    t=%d state=%s pos=%s ep=%s d=%.2f" % [i, player.state, player.global_position, v.get_entry_point(), player.global_position.distance_to(v.get_entry_point())])
			if player.current_vehicle != null:
				entered = true
				break
		_check(entered, "entra al auto (camina a la puerta + anim)")
		_check(not player.visible and player.collision_layer == 0, "oculto y sin colisión")
		var rig: CameraRig = get_first_node_in_group("camera_rig")
		_check(rig.mode == "vehicle", "cámara en modo vehicle")
		await _frames(30)
		await _tap("interact")
		await _frames(5)
		_check(player.current_vehicle == null and player.visible, "sale del auto")
		_check(player.collision_layer == 2, "colisión restaurada")
		_check(rig.mode == "on_foot", "cámara en modo on_foot")
		await _frames(60)
		_check(player.is_on_floor(), "parado tras salir (y=%.2f)" % player.global_position.y)

		# 6) Atropello: lanzamos el auto contra el jugador a ~30 km/h
		print("[6] atropello")
		player.global_position = Vector3(-20, 0.05, -10)
		player.velocity = Vector3.ZERO
		await _frames(30)
		v.global_transform = Transform3D(Basis.IDENTITY, Vector3(-20, 0.6, -2))
		v.linear_velocity = Vector3.ZERO
		await _frames(20)
		var hit := false
		for i in 120:
			v.linear_velocity = Vector3(0, v.linear_velocity.y, -8.5)
			await physics_frame
			if player.state == "stumble":
				hit = true
				break
		_check(hit, "estado stumble al ser golpeado")
		var recovered := false
		for i in 180:
			await physics_frame
			if player.state != "stumble":
				recovered = true
				break
		_check(recovered, "se levanta (%s)" % player.state)

	# 7) stumble_from manual (sin auto)
	print("[7] stumble_from")
	player.global_position = Vector3(30, 0.05, 30)
	await _frames(10)
	player.stumble_from(Vector3(6, 0, 0))
	await _frames(5)
	_check(player.state == "stumble", "stumble_from")
	await _frames(130)
	_check(player.state != "stumble" and player.is_on_floor(), "recuperado")

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)

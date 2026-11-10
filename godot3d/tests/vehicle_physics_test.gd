extends SceneTree
## Test headless de física de vehículos. Uso:
## godot --headless --fixed-fps 60 --path . -s res://tests/vehicle_physics_test.gd [-- taxi sedan ...]
## Imprime métricas por tipo: 0-60/0-100, vel. máx., frenado 80→0, roll en curva a 60,
## derrape con freno de mano, sardinel de 0.15 m, salida segura y enderezado tras volcar.

const DT := 1.0 / 60.0
var driver: Node3D
var world: Node3D
var results := {}
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await physics_frame
	_ensure_actions()
	world = Node3D.new()
	root.add_child(world)
	_build_world()
	driver = Node3D.new()
	driver.name = "FakeDriver"
	world.add_child(driver)
	var kinds: Array = OS.get_cmdline_user_args()
	if kinds.is_empty():
		kinds = ["taxi", "sedan", "pickup", "buseta"]
	for k: String in kinds:
		results[k] = {}
		await _test_settle(k)
		await _test_accel(k)
		await _test_brake(k)
		await _test_curve(k)
		await _test_handbrake(k)
		await _test_fast_corner(k)
		await _test_curb(k)
		await _test_exit(k)
		await _test_flip(k)
		await _test_horn_crash(k)
		print("RESULT ", k, " ", JSON.stringify(results[k]))
	_print_table()
	print("FAILURES: ", failures.size())
	for f in failures:
		print("  FAIL ", f)
	quit(0 if failures.is_empty() else 1)


func _ensure_actions() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "handbrake", "horn", "interact"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "handbrake", "horn"]:
		Input.action_release(a)


func _static_box(pos: Vector3, size: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	sb.position = pos
	sb.rotation = rot
	world.add_child(sb)
	return sb


func _build_world() -> void:
	_static_box(Vector3(0, -0.5, -1500), Vector3(4000, 1, 4000))
	# Andén con sardinel de 0.15 m en x=500, empieza en z=-20.
	_static_box(Vector3(500, 0.075, -45), Vector3(40, 0.15, 50))


func _spawn(kind: String, pos := Vector3.ZERO, yaw := 0.0) -> Vehicle:
	var v := VehicleFactory.spawn(kind, Transform3D(Basis(Vector3.UP, yaw), pos), world)
	for i in 60:
		await physics_frame
	return v


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


var _prev_v := Vector3.ZERO
var _lat_f := 0.0


## Aceleración lateral real (filtrada) en g.
func _lat_g(v: Vehicle) -> float:
	var acc := (v.linear_velocity - _prev_v) / DT
	_prev_v = v.linear_velocity
	var right := v.global_basis.x
	right.y = 0
	_lat_f = lerpf(_lat_f, absf(acc.dot(right.normalized())), 0.1)
	return _lat_f / 9.81


func _roll_deg(v: Vehicle) -> float:
	return rad_to_deg(asin(clampf(v.global_basis.x.y, -1, 1)))


func _pitch_deg(v: Vehicle) -> float:
	return rad_to_deg(asin(clampf(-v.global_basis.z.y, -1, 1)))


## Mantiene una velocidad objetivo con el acelerador (control P).
func _cruise(v: Vehicle, target_kmh: float) -> void:
	var s := v.get_forward_speed() * 3.6
	var e := target_kmh - s
	if e > 0.0:
		Input.action_press("move_forward", clampf(e * 0.15, 0.05, 1.0))
	else:
		Input.action_release("move_forward")


func _speed_up(v: Vehicle, kmh: float, max_s := 40.0) -> bool:
	Input.action_press("move_forward")
	var t := 0.0
	while v.get_forward_speed() * 3.6 < kmh and t < max_s:
		await physics_frame
		t += DT
	Input.action_release("move_forward")
	return t < max_s


func _test_settle(kind: String) -> void:
	var v := await _spawn(kind, Vector3(-300, 0, 0))
	await _frames(120)
	results[kind]["ride_y"] = snappedf(v.global_position.y, 0.001)
	results[kind]["settle_roll"] = snappedf(_roll_deg(v), 0.01)
	# Rebote: soltar desde 0.25 m arriba y contar cruces del punto de equilibrio.
	var eq := v.global_position.y
	v.global_position.y += 0.25
	var crossings := 0
	var above := true
	for i in 240:
		await physics_frame
		var a := v.global_position.y > eq
		if a != above and absf(v.global_position.y - eq) > 0.003:
			crossings += 1
			above = a
	results[kind]["bounce_half_cycles"] = crossings
	v.queue_free()


func _test_accel(kind: String) -> void:
	var v := await _spawn(kind, Vector3(0, 0, 0))
	v.enter(driver)
	Input.action_press("move_forward")
	var t := 0.0
	var t60 := -1.0
	var t100 := -1.0
	var top := 0.0
	var max_pitch := 0.0
	var last_gain_t := 0.0
	while t < 75.0:
		await physics_frame
		t += DT
		var s := v.get_forward_speed() * 3.6
		if t < 3.0:
			max_pitch = maxf(max_pitch, _pitch_deg(v))
		if t60 < 0 and s >= 60.0:
			t60 = t
		if t100 < 0 and s >= 100.0:
			t100 = t
		if s > top + 0.2:
			top = s
			last_gain_t = t
		if t - last_gain_t > 6.0:
			break
	_release_all()
	results[kind]["0_60_s"] = snappedf(t60, 0.01)
	results[kind]["0_100_s"] = snappedf(t100, 0.01)
	results[kind]["top_kmh"] = snappedf(top, 0.1)
	results[kind]["launch_squat_pitch_deg"] = snappedf(max_pitch, 0.01)
	results[kind]["gear_at_top"] = v.gear
	v.queue_free()


func _test_brake(kind: String) -> void:
	var v := await _spawn(kind, Vector3(50, 0, 0))
	v.enter(driver)
	var target := 80.0
	if not await _speed_up(v, target + 0.5, 60.0):
		results[kind]["brake_80_m"] = -1
		failures.append("%s no llega a 80 km/h" % kind)
		v.queue_free()
		return
	var start := v.global_position
	Input.action_press("move_back")
	var t := 0.0
	var min_pitch := 0.0
	while v.get_forward_speed() > 0.3 and t < 20.0:
		await physics_frame
		t += DT
		min_pitch = minf(min_pitch, _pitch_deg(v))
	_release_all()
	var d := (v.global_position - start)
	d.y = 0
	results[kind]["brake_80_m"] = snappedf(d.length(), 0.1)
	results[kind]["brake_80_s"] = snappedf(t, 0.01)
	results[kind]["brake_dive_pitch_deg"] = snappedf(min_pitch, 0.01)
	v.queue_free()


func _test_curve(kind: String) -> void:
	var v := await _spawn(kind, Vector3(100, 0, 0))
	v.enter(driver)
	await _speed_up(v, 60.0)
	# Curva a la derecha de radio 50 m a 60 km/h durante 6 s (dirección con control P de yaw).
	var t := 0.0
	var max_roll := 0.0
	var max_lat := 0.0
	var flipped := false
	var yaw0 := v.global_rotation.y
	var steer := 0.3
	_prev_v = v.linear_velocity
	_lat_f = 0.0
	var speed_sum := 0.0
	var n := 0
	while t < 6.0:
		await physics_frame
		t += DT
		_cruise(v, 60.0)
		var target_yaw := v.linear_velocity.length() / 50.0
		steer = clampf(steer + (target_yaw - (-v.angular_velocity.y)) * 2.0 * DT, 0.0, 1.0)
		Input.action_press("move_right", steer)
		var lat := _lat_g(v)
		if t > 1.5:
			max_roll = maxf(max_roll, absf(_roll_deg(v)))
			max_lat = maxf(max_lat, lat)
			speed_sum += v.get_speed_kmh()
			n += 1
		if v.global_basis.y.y < 0.5:
			flipped = true
		if OS.has_environment("VEH_DEBUG") and int(t * 60) % 20 == 0:
			print("  curve st=%.3f wst=%.3f in=%.2f t=%.2f v=%.1f steer=%.2f yaw=%.3f tgt=%.3f lat=%.2f roll=%.2f thr=%.2f gear=%d" % [v._steer, v.front_wheels[0].steering, Input.get_action_strength("move_right") - Input.get_action_strength("move_left"), t, v.get_speed_kmh(), steer, -v.angular_velocity.y, target_yaw, lat, _roll_deg(v), v.throttle, v.gear])
	_release_all()
	results[kind]["curve60_roll_deg"] = snappedf(max_roll, 0.01)
	results[kind]["curve60_lat_g"] = snappedf(max_lat, 0.01)
	results[kind]["curve60_avg_kmh"] = snappedf(speed_sum / maxf(1, n), 0.1)
	results[kind]["curve60_turned_right"] = wrapf(v.global_rotation.y - yaw0, -PI, PI) < 0.0
	results[kind]["curve60_flipped"] = flipped
	if flipped:
		failures.append("%s se voltea en curva normal a 60" % kind)
	if not results[kind]["curve60_turned_right"]:
		failures.append("%s: move_right no gira a la derecha" % kind)
	v.queue_free()


func _test_handbrake(kind: String) -> void:
	var v := await _spawn(kind, Vector3(150, 0, 0))
	v.enter(driver)
	await _speed_up(v, 60.0)
	var t := 0.0
	var max_slip := 0.0
	var flipped := false
	Input.action_press("move_left")
	Input.action_press("handbrake")
	while t < 2.5:
		await physics_frame
		t += DT
		if t > 0.8:
			Input.action_release("handbrake")
		if t > 1.4:
			Input.action_release("move_left")
		var vel := v.linear_velocity
		vel.y = 0
		if vel.length() > 3.0:
			var fwd := -v.global_basis.z
			fwd.y = 0
			max_slip = maxf(max_slip, rad_to_deg(fwd.normalized().angle_to(vel.normalized())))
		if v.global_basis.y.y < 0.5:
			flipped = true
	_release_all()
	results[kind]["handbrake_slip_deg"] = snappedf(max_slip, 0.1)
	results[kind]["handbrake_flipped"] = flipped
	if flipped:
		failures.append("%s se voltea con freno de mano" % kind)
	v.queue_free()


## Entrar muy rápido a una curva: debería subvirar (ángulo de deriva del frente pequeño).
func _test_fast_corner(kind: String) -> void:
	var v := await _spawn(kind, Vector3(250, 0, 0))
	v.enter(driver)
	var target := 100.0 if kind != "buseta" else 75.0
	await _speed_up(v, target)
	Input.action_press("move_left")
	_prev_v = v.linear_velocity
	_lat_f = 0.0
	var t := 0.0
	var max_lat := 0.0
	var flipped := false
	while t < 3.0:
		await physics_frame
		t += DT
		_cruise(v, target)
		var lat := _lat_g(v)
		if t > 0.3:
			max_lat = maxf(max_lat, lat)
		if OS.has_environment("VEH_DEBUG") and int(t * 60) % 10 == 0:
			print("  fast t=%.2f v=%.1f yaw=%.3f vyaw_g=%.2f lat=%.2f roll=%.2f skid=%.2f/%.2f" % [t, v.get_speed_kmh(), v.angular_velocity.y, v.linear_velocity.length() * v.angular_velocity.y / 9.81, lat, _roll_deg(v), v.front_wheels[0].get_skidinfo(), v.rear_wheels[0].get_skidinfo()])
		if v.global_basis.y.y < 0.5:
			flipped = true
	_release_all()
	results[kind]["fast_corner_kmh"] = target
	results[kind]["fast_corner_lat_g"] = snappedf(max_lat, 0.01)
	var fwd := -v.global_basis.z
	results[kind]["fast_corner_end_slip_deg"] = snappedf(rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(v.linear_velocity.x, v.linear_velocity.z))), 0.1)
	results[kind]["fast_corner_flipped"] = flipped
	v.queue_free()


func _test_curb(kind: String) -> void:
	var v := await _spawn(kind, Vector3(500, 0, -10))
	var y0 := v.global_position.y
	v.enter(driver)
	var t := 0.0
	var climbed := false
	while t < 15.0:
		await physics_frame
		t += DT
		_cruise(v, 10.0)
		# Todo el auto sobre el andén (z < -20 - largo) y altura ~0.15.
		if v.global_position.z < -20.0 - float(v.profile.half_length) - 1.0 and v.global_position.y > y0 + 0.1:
			climbed = true
			break
	_release_all()
	results[kind]["curb15_climbed"] = climbed
	results[kind]["curb15_time_s"] = snappedf(t, 0.01)
	if not climbed:
		failures.append("%s no sube sardinel 0.15 m (z=%.2f y=%.2f)" % [kind, v.global_position.z, v.global_position.y])
	v.queue_free()


func _test_exit(kind: String) -> void:
	var v := await _spawn(kind, Vector3(-100, 0, 0))
	v.enter(driver)
	var ok := v.is_occupied()
	var p := v.exit()
	var left_ok := v.to_local(p).x < 0.0 and _free(p, v)
	# Muro pegado a la puerta izquierda: debe salir por la derecha.
	var v2 := await _spawn(kind, Vector3(-150, 0, 0))
	var wall := _static_box(Vector3(-150 - float(v2.profile.half_width) - 0.5, 1.5, 0), Vector3(0.6, 3, 12))
	await _frames(2)
	v2.enter(driver)
	var p2 := v2.exit()
	var right_ok := v2.to_local(p2).x > 0.0 and _free(p2, v2)
	results[kind]["exit_left_ok"] = ok and left_ok and not v.is_occupied()
	results[kind]["exit_blocked_goes_right"] = right_ok
	if not (left_ok and right_ok):
		failures.append("%s exit() no seguro: %s %s" % [kind, v.to_local(p), v2.to_local(p2)])
	wall.queue_free()
	v.queue_free()
	v2.queue_free()


func _free(feet: Vector3, v: Vehicle) -> bool:
	var space := v.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.92)
	q.collision_mask = 1 | 4 | 8
	return space.intersect_shape(q, 1).is_empty()


func _test_flip(kind: String) -> void:
	var v := await _spawn(kind, Vector3(-200, 0, 0))
	v.enter(driver)
	v.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(-200, 2.5, 0))
	await _frames(int(3.5 / DT))
	var waited_flipped := v.flipped_time
	Input.action_press("move_forward")
	await _frames(2)
	_release_all()
	await _frames(120)
	results[kind]["flip_recovered"] = waited_flipped >= 2.9 and v.global_basis.y.y > 0.9
	if not results[kind]["flip_recovered"]:
		failures.append("%s no se endereza (flip_t=%.2f up=%.2f)" % [kind, waited_flipped, v.global_basis.y.y])
	v.queue_free()


## Pito (señal) y choque contra un muro a ~50 km/h (daño, humo, bumper).
func _test_horn_crash(kind: String) -> void:
	var v := await _spawn(kind, Vector3(800, 0, 0))
	v.enter(driver)
	var honks := [0]
	v.horn_honked.connect(func(): honks[0] += 1)
	Input.action_press("horn")
	await _frames(20)
	Input.action_release("horn")
	await _frames(2)
	results[kind]["horn_ok"] = honks[0] == 1
	var wall := _static_box(Vector3(800, 1.5, -60), Vector3(10, 3, 1))
	await _speed_up(v, 50.0)
	Input.action_press("move_forward")
	var t := 0.0
	while t < 6.0 and v.damage <= 0.0:
		await physics_frame
		t += DT
	_release_all()
	await _frames(10)
	results[kind]["crash50_damage"] = snappedf(v.damage, 0.1)
	results[kind]["crash50_smoke"] = v.smoke.emitting
	if v.damage <= 0.0:
		failures.append("%s choque sin daño" % kind)
	wall.queue_free()
	v.queue_free()


func _print_table() -> void:
	var cols := ["0_60_s", "0_100_s", "top_kmh", "brake_80_m", "brake_dive_pitch_deg", "launch_squat_pitch_deg",
		"curve60_roll_deg", "curve60_lat_g", "fast_corner_lat_g", "handbrake_slip_deg", "bounce_half_cycles", "curb15_climbed",
		"exit_left_ok", "exit_blocked_goes_right", "flip_recovered", "horn_ok", "crash50_damage", "ride_y"]
	print("\n| métrica | ", " | ".join(results.keys()), " |")
	for c in cols:
		var row := "| %s |" % c
		for k in results:
			row += " %s |" % str(results[k].get(c, "-"))
		print(row)

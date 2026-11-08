class_name Vehicle
extends VehicleBody3D
## Vehículo conducible estilo GTA IV: pesado, suspensión blanda, balanceo y cabeceo.
## Convención: el FRENTE del auto es -Z local (como cualquier Node3D de Godot).
## Las VehicleWheel3D van rotadas 180° en Y para que engine_force > 0 empuje hacia -Z.
## El origen del cuerpo está a nivel del suelo (con el auto asentado).
## Lo construye VehicleFactory; este script solo maneja física, control y efectos.

signal driver_entered(driver: Node3D)
signal driver_exited(driver: Node3D)
signal horn_honked
signal crashed(impact_ms: float)

const KMH := 3.6
const FLIP_RESET_TIME := 3.0

## Si es true, todos los autos llevan las luces encendidas (lo puede activar LOOK de noche).
static var night_mode := false

var driver: Node3D = null
var kind := "sedan"
## Perfil de física (lo llena VehicleFactory, ver PROFILES allá).
var profile: Dictionary = {}

var front_wheels: Array[VehicleWheel3D] = []
var rear_wheels: Array[VehicleWheel3D] = []
var all_wheels: Array[VehicleWheel3D] = []
var wheel_visuals: Array[Node3D] = []
var wheel_hardpoints: Array[float] = []

## Estado de la transmisión (lectura para HUD).
var gear := 1          # -1 reversa, 1..N
var rpm := 800.0
var damage := 0.0      # 0..100
var throttle := 0.0
var is_braking := false
var flipped_time := 0.0

var _steer := 0.0
var _shift_timer := 0.0
var _prev_vel := Vector3.ZERO
var _lights_on := false
var _lights_requested := false
var _horn_on := false
var _horn_phase := 0.0

# Nodos visuales que asigna la fábrica.
var head_lens: MeshInstance3D
var tail_lens: MeshInstance3D
var head_spots: Array[SpotLight3D] = []
var bumper_front: Node3D
var smoke: CPUParticles3D
var horn_player: AudioStreamPlayer3D
var seat: Marker3D
var camera_anchor: Node3D


func _ready() -> void:
	add_to_group("vehicle")
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3)
	_prev_vel = linear_velocity
	_apply_parked()
	_refresh_lights()
	_set_brake_lights(false)


# ---------------------------------------------------------------- API pública

func is_occupied() -> bool:
	return driver != null


## Punto global junto a la puerta del conductor (lado izquierdo), a nivel del piso.
func get_entry_point() -> Vector3:
	return to_global(_door_local(-1.0))


func enter(new_driver: Node3D) -> void:
	if driver != null or new_driver == null:
		return
	driver = new_driver
	sleeping = false
	gear = 1
	_refresh_lights()
	driver_entered.emit(driver)


## Suelta el control y devuelve una posición global segura (pies del jugador).
## Prueba la puerta izquierda, luego la derecha, luego el techo.
func exit() -> Vector3:
	var old := driver
	driver = null
	_horn_stop()
	_apply_parked()
	_refresh_lights()
	_set_brake_lights(false)
	var pos := find_exit_position()
	if old != null:
		driver_exited.emit(old)
	return pos


func get_speed_kmh() -> float:
	return linear_velocity.length() * KMH


func get_camera_anchor() -> Node3D:
	return camera_anchor


## Enciende/apaga faros. Con conductor o de noche siempre quedan encendidos.
func set_lights(on: bool) -> void:
	_lights_requested = on
	_refresh_lights()


static func set_night(on: bool, tree: SceneTree) -> void:
	night_mode = on
	for v in tree.get_nodes_in_group("vehicle"):
		if v is Vehicle:
			(v as Vehicle)._refresh_lights()


## Velocidad con signo a lo largo del frente del auto (m/s, + = adelante).
func get_forward_speed() -> float:
	return -global_basis.z.dot(linear_velocity)


func is_flipped() -> bool:
	return global_basis.y.y < 0.35


## Endereza el auto (lo usa el jugador tras 3 s volcado).
func right_vehicle() -> void:
	var fwd := -global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	var b := Basis.looking_at(fwd.normalized(), Vector3.UP)
	global_transform = Transform3D(b, global_position + Vector3.UP * 1.2)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	flipped_time = 0.0


# ---------------------------------------------------------------- física

func _physics_process(delta: float) -> void:
	if profile.is_empty():
		return
	var v_f := get_forward_speed()
	_update_damage()
	_update_flip(delta)
	_apply_resistances()
	if driver == null:
		_apply_parked()
		_steer = move_toward(_steer, 0.0, 2.0 * delta)
		_apply_steer()
		_set_brake_lights(false)
		return

	var fwd_in := Input.get_action_strength("move_forward")
	var back_in := Input.get_action_strength("move_back")
	var steer_in := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var hand := Input.is_action_pressed("handbrake")

	# Dirección: ángulo máximo cae con la velocidad y el volante gira con velocidad limitada.
	var speed_t := clampf(absf(v_f) * KMH / float(profile.steer_ref_kmh), 0.0, 1.0)
	var max_angle := lerpf(float(profile.steer_max), float(profile.steer_min), speed_t * (2.0 - speed_t))
	var target := steer_in * max_angle
	var rate: float = profile.steer_rate * (1.6 if absf(target) < absf(_steer) else 1.0)
	_steer = move_toward(_steer, target, rate * delta)
	_apply_steer()

	# Acelerador / freno / reversa.
	var drive := 0.0     # -1..1 intención de tracción (negativa = reversa)
	var brake_in := 0.0
	if fwd_in > 0.05:
		if v_f < -0.8:
			brake_in = fwd_in
		else:
			drive = fwd_in
	if back_in > 0.05:
		if v_f > 0.8:
			brake_in = maxf(brake_in, back_in)
		elif fwd_in <= 0.05:
			drive = -back_in
	throttle = move_toward(throttle, absf(drive), 3.0 * delta)
	if drive < 0.0:
		gear = -1
	elif gear == -1 and drive > 0.0:
		gear = 1
	var total_force := _engine_force(v_f, delta) if drive != 0.0 else 0.0
	_update_rpm_idle(v_f, drive)

	var drive_wheels := _drive_wheels()
	var per_wheel := total_force / maxf(1.0, float(drive_wheels.size()))
	var brake_f: float = profile.brake * brake_in
	var engine_brake: float = profile.engine_brake if drive == 0.0 and brake_in == 0.0 else 0.0
	var hold := drive == 0.0 and brake_in == 0.0 and absf(v_f) < 0.4
	for w in front_wheels + rear_wheels:
		var is_front := front_wheels.has(w)
		var is_drive := drive_wheels.has(w)
		var ef := per_wheel * signf(drive) if is_drive else 0.0
		var br := brake_f * (1.15 if is_front else 0.85)
		if is_drive:
			br = maxf(br, engine_brake)
		if hold:
			br = maxf(br, float(profile.brake) * 0.4)
		var slip: float = profile.grip_front if is_front else profile.grip_rear
		if hand and not is_front:
			ef = 0.0
			br = maxf(br, float(profile.handbrake))
			slip *= float(profile.handbrake_grip)
		if br > 0.0 and absf(ef) > 0.0:
			ef = 0.0   # en Godot engine_force anula el freno: el freno manda
		w.engine_force = ef
		w.brake = br
		w.wheel_friction_slip = slip
	# Cuando el freno de mano está puesto en un FWD el motor sigue empujando adelante.
	is_braking = brake_in > 0.05 or hand
	_set_brake_lights(is_braking)
	_update_horn()

	# Volcado: tras 3 s el jugador endereza con acelerar/frenar.
	if flipped_time > FLIP_RESET_TIME and (fwd_in > 0.5 or back_in > 0.5 or hand):
		right_vehicle()


func _process(delta: float) -> void:
	if _horn_on:
		_fill_horn(delta)
	_update_wheel_visuals()


## Coloca la malla de cada rueda donde realmente toca el piso.
## (El raycast de VehicleBody3D en Godot 4.3 deja el nodo de la rueda unos cm hundido.)
func _update_wheel_visuals() -> void:
	for i in wheel_visuals.size():
		var w := all_wheels[i]
		var vis := wheel_visuals[i]
		var t := w.transform
		if w.is_in_contact():
			var r := w.wheel_radius
			var rest := w.wheel_rest_length
			var hp := wheel_hardpoints[i]
			var length := hp - t.origin.y
			var h := (length + r) * (rest + 2.0 * r) / (rest + r) - r
			t.origin.y = hp - h + r
		vis.transform = t


func _drive_wheels() -> Array[VehicleWheel3D]:
	match String(profile.drive):
		"fwd":
			return front_wheels
		"rwd":
			return rear_wheels
	return front_wheels + rear_wheels


## _steer > 0 = derecha. Con las ruedas rotadas 180°, steering positivo gira a la izquierda.
func _apply_steer() -> void:
	for w in front_wheels:
		w.steering = -_steer


## Curva de torque simple + caja automática. Devuelve fuerza total en las ruedas (N).
func _engine_force(v_f: float, delta: float) -> float:
	var r: float = profile.wheel_radius
	var ratios: Array = profile.gears
	var wheel_rpm := absf(v_f) / r * 60.0 / TAU
	if gear == -1:
		var rev_ratio: float = float(profile.reverse) * float(profile.final_drive)
		rpm = maxf(float(profile.rpm_idle) * 1.4, wheel_rpm * rev_ratio)
		if absf(v_f) * KMH > float(profile.max_reverse_kmh):
			return 0.0
		return _torque(rpm) * rev_ratio * float(profile.efficiency) / r * throttle

	_shift_timer = maxf(0.0, _shift_timer - delta)
	var ratio: float = float(ratios[gear - 1]) * float(profile.final_drive)
	var raw_rpm := wheel_rpm * ratio
	if _shift_timer <= 0.0:
		# A medio acelerador cambia antes (como una caja automática real).
		var up_rpm := lerpf(float(profile.rpm_peak) * 0.8, float(profile.shift_up), throttle)
		if raw_rpm > up_rpm and gear < ratios.size():
			gear += 1
			_shift_timer = float(profile.shift_time)
		elif gear > 1 and raw_rpm < float(profile.shift_down):
			var lower: float = float(ratios[gear - 2]) * float(profile.final_drive)
			if wheel_rpm * lower < up_rpm * 0.9:
				gear -= 1
				_shift_timer = float(profile.shift_time) * 0.5
	ratio = float(ratios[gear - 1]) * float(profile.final_drive)
	raw_rpm = wheel_rpm * ratio
	# Embrague que patina en arrancada: el motor no baja de ~60% del pico.
	var launch: float = float(profile.rpm_peak) * 0.75 * throttle
	rpm = clampf(maxf(raw_rpm, launch), float(profile.rpm_idle), float(profile.rpm_max) + 200.0)
	if _shift_timer > 0.0:
		return 0.0
	if absf(v_f) * KMH > float(profile.max_kmh):
		return 0.0
	return _torque(rpm) * ratio * float(profile.efficiency) / r * throttle


func _torque(at_rpm: float) -> float:
	if at_rpm > float(profile.rpm_max):
		return 0.0  # limitador
	var peak: float = profile.torque
	var x := (at_rpm - float(profile.rpm_peak)) / (float(profile.rpm_max) - float(profile.rpm_idle))
	return peak * clampf(1.0 - 1.6 * x * x, 0.45, 1.0)


func _update_rpm_idle(v_f: float, drive: float) -> void:
	if drive != 0.0:
		return
	var ratios: Array = profile.gears
	var g := clampi(gear, 1, ratios.size())
	var wheel_rpm := absf(v_f) / float(profile.wheel_radius) * 60.0 / TAU
	rpm = maxf(float(profile.rpm_idle), wheel_rpm * float(ratios[g - 1]) * float(profile.final_drive))
	# Bajar marchas al desacelerar.
	if gear > 1 and rpm < float(profile.shift_down) * 0.8:
		gear -= 1


## Resistencia aerodinámica + rodadura (Godot no las trae).
func _apply_resistances() -> void:
	var v := linear_velocity
	var s := v.length()
	if s < 0.05:
		return
	var on_ground := false
	for w in front_wheels:
		if w.is_in_contact():
			on_ground = true
	var f := -v * s * float(profile.drag)
	if on_ground:
		var horiz := Vector3(v.x, 0.0, v.z)
		if horiz.length() > 0.3:
			f += -horiz.normalized() * float(profile.rolling) * mass * 9.81
	apply_central_force(f)


func _apply_parked() -> void:
	for w in front_wheels + rear_wheels:
		w.engine_force = 0.0
		w.brake = float(profile.get("brake", 30.0)) * 0.8
		w.wheel_friction_slip = float(profile.get("grip_front", 1.0))
	throttle = 0.0
	# Estacionado en pendiente lateral (las carreras suben hacia el oriente), el
	# raycast de ruedas de Godot deja "reptar" el auto de lado varios metros.
	# Con velocidad muy baja anulamos ese deslizamiento lateral y el giro; un golpe
	# fuerte (> 1 m/s) sí lo sigue moviendo, como un auto con freno de mano real.
	if linear_velocity.length() < 1.0 and _any_wheel_contact():
		var right := global_basis.x
		linear_velocity -= right * linear_velocity.dot(right)
		linear_velocity -= global_basis.z * linear_velocity.dot(global_basis.z) * 0.5
		angular_velocity.y = 0.0


func _any_wheel_contact() -> bool:
	for w in front_wheels + rear_wheels:
		if w.is_in_contact():
			return true
	return false


# ---------------------------------------------------------------- volcado y daño

func _update_flip(delta: float) -> void:
	if is_flipped() and linear_velocity.length() < 3.0:
		flipped_time += delta
		# Anti-vuelco suave: solo si está volteado, un torque leve que ayuda a enderezar.
		if flipped_time > 1.0:
			var axis := global_basis.y.cross(Vector3.UP)
			apply_torque(axis.normalized() * mass * 1.5 if axis.length() > 0.01 else Vector3.ZERO)
	else:
		flipped_time = 0.0


func _update_damage() -> void:
	var dv := (linear_velocity - _prev_vel).length()
	_prev_vel = linear_velocity
	if dv > 4.0:
		var hit := dv - 4.0
		damage = minf(100.0, damage + hit * 4.5)
		crashed.emit(dv)
		if bumper_front != null and damage > 15.0:
			# Deformación leve del bumper: se cae y gira unos grados.
			var t := damage / 100.0
			bumper_front.rotation = Vector3(deg_to_rad(8.0 * t), deg_to_rad(randf_range(-6, 6) * t), deg_to_rad(10.0 * t))
			bumper_front.position.y = -0.06 * t
		if smoke != null:
			smoke.emitting = damage > 55.0


# ---------------------------------------------------------------- luces

func _refresh_lights() -> void:
	var on := _lights_requested or driver != null or night_mode
	_lights_on = on
	for s in head_spots:
		s.visible = on
	if head_lens != null:
		head_lens.material_override = MatActors.headlight(2.6) if on else MatActors.headlight(0.0)
	_set_brake_lights(is_braking and driver != null)


func _set_brake_lights(on: bool) -> void:
	if tail_lens == null:
		return
	var mat: Material
	if on:
		mat = MatActors.taillight(5.0)
	elif _lights_on:
		mat = MatActors.taillight(1.4)
	else:
		mat = MatActors.taillight(0.0)
	if tail_lens.material_override != mat:
		tail_lens.material_override = mat


# ---------------------------------------------------------------- pito

func _update_horn() -> void:
	var pressed := InputMap.has_action("horn") and Input.is_action_pressed("horn")
	if pressed and not _horn_on:
		_horn_on = true
		horn_honked.emit()
		if horn_player != null:
			horn_player.play()
	elif not pressed and _horn_on:
		_horn_stop()


func _horn_stop() -> void:
	_horn_on = false
	if horn_player != null and horn_player.playing:
		horn_player.stop()


## Pito de dos tonos (onda cuadrada suave) generado en tiempo real.
func _fill_horn(_delta: float) -> void:
	if horn_player == null or not horn_player.playing:
		return
	var pb := horn_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var gen := horn_player.stream as AudioStreamGenerator
	var f1: float = profile.get("horn_hz", 420.0)
	var f2 := f1 * 1.26
	var n := mini(pb.get_frames_available(), 2048)
	for i in n:
		_horn_phase += 1.0 / gen.mix_rate
		var a := signf(sin(TAU * f1 * _horn_phase)) * 0.25 + signf(sin(TAU * f2 * _horn_phase)) * 0.2
		pb.push_frame(Vector2(a, a))


# ---------------------------------------------------------------- salida segura

func _door_local(side: float) -> Vector3:
	var hw: float = profile.get("half_width", 0.9)
	var dz: float = profile.get("door_z", -0.2)
	return Vector3(side * (hw + 0.55), 0.0, dz)


## Busca dónde poner al jugador: izquierda, derecha, techo. Devuelve los pies.
func find_exit_position() -> Vector3:
	var space := get_world_3d().direct_space_state
	var cands: Array[Vector3] = [
		to_global(_door_local(-1.0)),
		to_global(_door_local(-1.0) + Vector3(-0.4, 0, 0)),
		to_global(_door_local(1.0)),
		to_global(_door_local(1.0) + Vector3(0.4, 0, 0)),
		to_global(Vector3(0, 0, float(profile.get("half_length", 2.2)) + 0.8)),
	]
	for c in cands:
		var feet := _ground_at(space, c)
		if _capsule_free(space, feet):
			return feet
	# Último recurso: encima del techo.
	return global_position + Vector3.UP * (float(profile.get("height", 1.5)) + 0.3)


func _ground_at(space: PhysicsDirectSpaceState3D, p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 2.0, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return p + Vector3.UP * 0.05
	return (hit.position as Vector3) + Vector3.UP * 0.05


func _capsule_free(space: PhysicsDirectSpaceState3D, feet: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (cap.height * 0.5 + 0.03))
	q.collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()

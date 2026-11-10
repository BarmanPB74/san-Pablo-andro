class_name Player
extends CharacterBody3D
## Andro a pie. Movimiento estilo GTA IV: inercia real, giro con radio que crece
## con la velocidad, derrape al cambiar de sentido a alta velocidad, escalones,
## atropellos (stumble) y entrar/salir de vehículos según CONTRACT.md.
##
## Vehículos: se usa duck typing (grupo "vehicle" + has_method) para no depender
## del orden en que se registra `class_name Vehicle`.

signal entered_vehicle(vehicle: Node3D)
signal exited_vehicle(vehicle: Node3D)
signal stumbled(impact_kmh: float)
## Un golpe del combo conectó con `body` (idx: 0 jab, 1 cruzado, 2 patada).
signal punched(body: Node3D, idx: int)

# ---------------- Ajustes de movimiento ----------------
@export var walk_speed := 1.6
@export var run_speed := 4.5
@export var sprint_speed := 7.0
@export var accel_walk := 5.0          # m/s² al arrancar caminando
@export var accel_run := 6.5
@export var accel_sprint := 4.0        # el sprint "carga" despacio
@export var decel := 7.5               # frenado al soltar
@export var skid_decel := 15.0         # plant: frenado brusco al invertir el sentido
@export var turn_rate_still := 11.0    # rad/s parado
@export var turn_rate_sprint := 3.0    # rad/s a sprint → radio ≈ 2.3 m
@export var jump_velocity := 3.7       # ≈ 0.7 m de salto
@export var air_control := 1.6         # m/s² de cambio en el aire
@export var step_height := 0.36
@export var hit_speed_kmh := 15.0
@export var interact_radius := 3.5
@export var crouch_speed := 1.15
@export var punch_reach := 1.15        # alcance del golpe (m) medido desde el pecho
@export var push_speed := 1.5          # rapidez máxima empujando algo pesado

const GRAVITY_MULT := 1.35
const CAPSULE_RADIUS := 0.3             # caída más "pesada" que la gravedad del mundo
const CAPSULE_H := 1.78
const CAPSULE_H_CROUCH := 1.2
const PUNCH_DUR := [0.34, 0.38, 0.5]    # duración de cada golpe del combo
const PUNCH_HIT := [0.12, 0.14, 0.2]    # instante en que conecta
const PUNCH_POWER := [4.5, 5.5, 9.0]    # velocidad (m/s) que recibe un objeto liviano

## Vehículo actual (VehicleBody3D que cumple la API Vehicle del contrato) o null.
var current_vehicle: VehicleBody3D = null
## Estado de animación actual (idle, walk, run, sprint, jump, fall, land, stumble,
## enter_vehicle, in_vehicle).
var state := "idle"
var model: PlayerModel
var camera_rig: Node3D

var _facing := 0.0                     # yaw del cuerpo (0 = mirando a -Z)
var _speed := 0.0                      # rapidez hacia adelante deseada (m/s)
var _skidding := false
var _land_timer := 0.0
var _stumble_timer := 0.0
var _enter_timer := 0.0
var _approach_vehicle: VehicleBody3D = null
var _approach_timer := 0.0
var _entering_vehicle: VehicleBody3D = null
var _step_smooth := 0.0                # compensación visual al subir escalones
var _was_on_floor := true
var _air_time := 0.0
var _anchor: Marker3D
var _hit_area: Area3D
var _saved_layer := 0
var _saved_mask := 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.81)
var _crouching := false
var _punch_t := -1.0                   # <0: sin golpear
var _punch_idx := 0
var _punch_queued := false
var _punch_hit_done := false
var _combo_timer := 0.0                # tiempo restante para encadenar el siguiente golpe
var _push_t := 0.0                     # >0 mientras empuja un objeto
var _exit_t := 1.0                     # <0.4: animación de bajar del auto
var _anchor_y := 1.55


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1 << 1                       # capa 2: player
	collision_mask = (1 << 0) | (1 << 2) | (1 << 3)  # world | vehicles | props
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(46.0)
	floor_constant_speed = true
	floor_stop_on_slope = true
	safe_margin = 0.02
	_facing = rotation.y
	rotation = Vector3.ZERO

	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = CAPSULE_RADIUS
		cap.height = CAPSULE_H
		cs.shape = cap
		cs.position = Vector3(0, 0.89, 0)
		add_child(cs)

	model = get_node_or_null("Model") as PlayerModel
	if model == null:
		model = PlayerModel.new()
		model.name = "Model"
		add_child(model)
	model.rotation.y = _facing

	_anchor = Marker3D.new()
	_anchor.name = "CameraAnchor"
	_anchor.position = Vector3(0, 1.55, 0)
	add_child(_anchor)

	# Sensor de atropellos: detecta vehículos (capa 3) alrededor del cuerpo
	_hit_area = Area3D.new()
	_hit_area.name = "HitSensor"
	_hit_area.collision_layer = 0
	_hit_area.collision_mask = 1 << 2
	_hit_area.monitorable = false
	var hs := CollisionShape3D.new()
	var hcap := CapsuleShape3D.new()
	hcap.radius = 0.45
	hcap.height = 1.9
	hs.shape = hcap
	hs.position = Vector3(0, 0.95, 0)
	_hit_area.add_child(hs)
	add_child(_hit_area)

	_attach_camera.call_deferred()


func _attach_camera() -> void:
	camera_rig = get_tree().get_first_node_in_group("camera_rig") as Node3D
	if camera_rig == null:
		camera_rig = CameraRig.new()
		camera_rig.name = "CameraRig"
		get_parent().add_child(camera_rig)
		camera_rig.global_position = _anchor.global_position
	if camera_rig.has_method("follow"):
		camera_rig.follow(get_camera_anchor(), "on_foot")


## Punto que sigue la cámara a pie (a la altura de la cabeza).
func get_camera_anchor() -> Node3D:
	return _anchor


func get_facing() -> float:
	return _facing


func get_forward_speed() -> float:
	return _speed


func is_in_vehicle() -> bool:
	return current_vehicle != null


# =====================================================================
#  FÍSICA
# =====================================================================

func _physics_process(delta: float) -> void:
	if current_vehicle != null:
		_process_in_vehicle()
		return

	match state:
		"stumble":
			_process_stumble(delta)
		"enter_vehicle":
			_process_entering(delta)
		_:
			_process_on_foot(delta)

	_check_vehicle_hits()

	# Animación
	_step_smooth = lerpf(_step_smooth, 0.0, 1.0 - exp(-12.0 * delta))
	model.position.y = _step_smooth
	model.rotation.y = _facing
	var hv := Vector2(velocity.x, velocity.z).length()
	model.punch_t = _punch_t
	model.punch_idx = _punch_idx
	model.animate(state, hv, delta)
	_anchor_y = lerpf(_anchor_y, 1.1 if _crouching else 1.55, 1.0 - exp(-9.0 * delta))
	_anchor.position.y = _anchor_y


func _process_on_foot(delta: float) -> void:
	var on_floor := is_on_floor()
	var input := _get_move_input()
	_exit_t += delta
	_push_t = maxf(0.0, _push_t - delta)
	_combo_timer = maxf(0.0, _combo_timer - delta)

	# Ir solo hacia la puerta de un auto (como en GTA)
	if _approach_vehicle != null:
		if input.length() > 0.2 or not is_instance_valid(_approach_vehicle):
			_approach_vehicle = null
		else:
			_approach_timer += delta
			var to: Vector3 = _approach_vehicle.get_entry_point() - global_position
			to.y = 0.0
			if to.length() < 0.45 or _approach_timer > 3.0:
				var av := _approach_vehicle
				_approach_vehicle = null
				_begin_enter(av)
				return
			input = to.normalized() * (1.0 if to.length() > 2.0 else 0.5)

	var input_len := minf(input.length(), 1.0)
	var target_speed := 0.0
	if input_len > 0.05:
		if Input.is_action_pressed("sprint"):
			target_speed = sprint_speed
		elif input_len < 0.6:
			target_speed = walk_speed
		else:
			target_speed = run_speed
	_update_crouch(on_floor)
	if _crouching:
		target_speed = minf(target_speed, crouch_speed)
	_update_punch(delta, on_floor)
	if _punch_t >= 0.0:
		target_speed = minf(target_speed, 1.0)
	if _push_t > 0.0:
		target_speed = minf(target_speed, push_speed)

	if on_floor:
		_ground_move(delta, input, input_len, target_speed)
		if Input.is_action_just_pressed("jump") and not _skidding and _punch_t < 0.0:
			if _crouching:
				_set_crouch(false)      # primero se levanta; el siguiente toque salta
			else:
				velocity.y = jump_velocity + _speed * 0.05
				state = "jump"
				_air_time = 0.0
				floor_snap_length = 0.0
		# Acciones que mandan sobre el paso: bajar del auto > golpear > empujar
		if state != "jump":
			if _exit_t < 0.4:
				state = "exit_vehicle"
			elif _punch_t >= 0.0:
				state = "punch"
			elif _push_t > 0.0 and _speed < 3.0 and state != "land":
				state = "push"
	else:
		_air_move(delta, input, input_len)

	# Gravedad
	if not on_floor:
		velocity.y -= _gravity * GRAVITY_MULT * delta
		_air_time += delta
	else:
		velocity.y = maxf(velocity.y, -0.5) if state != "jump" else velocity.y

	# Escalones / sardineles antes del deslizamiento
	if on_floor and state != "jump":
		_try_step_up(delta)

	var pre_vel := velocity
	move_and_slide()
	_post_move(pre_vel, delta)
	_handle_push(delta)

	# Interactuar (entrar a vehículos)
	if Input.is_action_just_pressed("interact"):
		_try_interact()


func _ground_move(delta: float, input: Vector3, input_len: float, target_speed: float) -> void:
	# Giro: la tasa máxima baja con la velocidad → radio de giro crece
	var sp_n := clampf(_speed / sprint_speed, 0.0, 1.0)
	var max_turn := lerpf(turn_rate_still, turn_rate_sprint, sqrt(sp_n))
	if input_len > 0.05:
		var desired := atan2(-input.x, -input.z)
		var diff := wrapf(desired - _facing, -PI, PI)
		# Plant / derrape: cambio brusco de sentido a alta velocidad
		if absf(diff) > deg_to_rad(110.0) and _speed > 3.2:
			_skidding = true
		if _skidding:
			_speed = move_toward(_speed, 0.0, skid_decel * delta)
			_facing += clampf(diff, -1.5 * delta, 1.5 * delta)
			if _speed < 1.0:
				_skidding = false
		else:
			_facing += clampf(diff, -max_turn * delta, max_turn * delta)
			# Si el ángulo es grande, el cuerpo frena para girar (no gira en seco)
			var align := clampf(cos(diff), 0.0, 1.0)
			var goal := target_speed * lerpf(0.35, 1.0, align)
			var accel := _accel_for(goal)
			# Aceleración progresiva: fuerte al inicio, suave al acercarse al tope
			var ratio := clampf(_speed / maxf(goal, 0.1), 0.0, 1.0)
			if _speed < goal:
				_speed = move_toward(_speed, goal, accel * (1.0 - 0.55 * ratio * ratio) * delta)
			else:
				_speed = move_toward(_speed, goal, decel * 0.8 * delta)
	else:
		_skidding = false
		# Frenado progresivo: el impulso se nota más desde el sprint
		var d := decel * (0.7 + 0.3 * clampf(1.0 - _speed / sprint_speed, 0.0, 1.0))
		_speed = move_toward(_speed, 0.0, d * delta)
	_facing = wrapf(_facing, -PI, PI)

	var fwd := Vector3(-sin(_facing), 0.0, -cos(_facing))
	var want := fwd * _speed
	# Agarre: la velocidad real persigue a la deseada (deriva lateral al girar rápido)
	var grip := 4.0 if _skidding else lerpf(16.0, 7.0, sp_n)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	hv = hv.lerp(want, 1.0 - exp(-grip * delta))
	velocity.x = hv.x
	velocity.z = hv.z

	if state in ["land"]:
		_land_timer -= delta
		if _land_timer <= 0.0:
			state = _gait_state()
	else:
		state = _gait_state()


func _accel_for(goal: float) -> float:
	if goal > run_speed + 0.1:
		return accel_sprint
	if goal > walk_speed + 0.1:
		return accel_run
	return accel_walk


func _gait_state() -> String:
	var hv := Vector2(velocity.x, velocity.z).length()
	if _crouching:
		return "crouch" if (hv < 0.25 and _speed < 0.25) else "crouch_walk"
	if hv < 0.25 and _speed < 0.25:
		return "idle"
	if hv < 2.6:
		return "walk"
	if hv < 5.6:
		return "run"
	return "sprint"


func _air_move(delta: float, input: Vector3, input_len: float) -> void:
	# Control aéreo bajo: casi se conserva la inercia
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if input_len > 0.05:
		hv += input.normalized() * input_len * air_control * delta
		var desired := atan2(-input.x, -input.z)
		_facing += clampf(wrapf(desired - _facing, -PI, PI), -2.0 * delta, 2.0 * delta)
	hv = hv.limit_length(maxf(sprint_speed, hv.length()))
	velocity.x = hv.x
	velocity.z = hv.z
	_speed = hv.length()


func _post_move(pre_vel: Vector3, delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		# Aterrizaje
		if state == "fall" or state == "jump":
			var impact := -pre_vel.y
			if _air_time > 0.25 or impact > 3.0:
				state = "land"
				_land_timer = clampf(0.12 + impact * 0.03, 0.12, 0.35)
				_speed *= 0.75
			else:
				state = _gait_state()
		floor_snap_length = 0.45
	elif not on_floor and _was_on_floor and state != "jump":
		# Bajó de un borde: unos frames de gracia antes de "caer"
		floor_snap_length = 0.45
	if on_floor:
		_air_time = 0.0
	elif state != "jump" and state != "stumble" and _air_time > 0.12:
		state = "fall"
	if state == "jump" and velocity.y < 0.0 and not on_floor:
		state = "fall"
	_was_on_floor = on_floor

	# Si chocó contra una pared, la rapidez deseada se reduce a la real
	if on_floor and get_slide_collision_count() > 0:
		var fwd := Vector3(-sin(_facing), 0.0, -cos(_facing))
		var real := Vector3(velocity.x, 0.0, velocity.z).dot(fwd)
		_speed = minf(_speed, maxf(0.0, real) + 0.5)


## Sube escalones/sardineles de hasta step_height: un rayo baja justo delante de
## la cápsula para hallar la altura del borde; si hay espacio, se sube el cuerpo.
func _try_step_up(delta: float) -> void:
	# Usa la intención (rumbo × rapidez): contra un borde la velocidad real es ~0
	var fwd := Vector3(-sin(_facing), 0.0, -cos(_facing))
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var spd := maxf(hv.length(), _speed)
	if spd < 0.15:
		return
	var dir := fwd if hv.length() < 0.3 else hv.normalized()
	var motion := dir * maxf(spd * delta, 0.05)
	var xf := global_transform
	var col := KinematicCollision3D.new()
	# Se prueba 4 cm más arriba para no "chocar" con el piso sobre el que está parado
	if not test_move(xf.translated(Vector3.UP * 0.04), motion, col, 0.001):
		return
	if col.get_normal().y > 0.7:
		return  # es rampa o piso: el slide lo maneja
	# Altura del borde justo delante
	var space := get_world_3d().direct_space_state
	var probe := global_position + dir * (CAPSULE_RADIUS + 0.06)
	var q := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * (step_height + 0.05),
		probe + Vector3.DOWN * 0.05, collision_mask & ~(1 << 1))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	if (hit.normal as Vector3).y < 0.7:
		return
	var rise: float = (hit.position as Vector3).y - global_position.y
	if rise <= 0.02 or rise > step_height + 0.01:
		return
	# ¿Cabe el cuerpo arriba y avanzando sobre el escalón?
	var up := Vector3(0.0, rise + 0.02, 0.0)
	if test_move(xf, up, null, 0.001):
		return
	if test_move(xf.translated(up), dir * 0.08, null, 0.001):
		return
	global_position += up
	_step_smooth -= up.y
	velocity.y = 0.0


func _process_stumble(delta: float) -> void:
	_stumble_timer += delta
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * GRAVITY_MULT * delta
	else:
		velocity.y = maxf(velocity.y, -0.5)
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		hv = hv.move_toward(Vector3.ZERO, 9.0 * delta)
		velocity.x = hv.x
		velocity.z = hv.z
	move_and_slide()
	_was_on_floor = is_on_floor()
	_speed = 0.0
	if _stumble_timer >= 1.75 and is_on_floor():
		state = "idle"
		floor_snap_length = 0.45


func _check_vehicle_hits() -> void:
	if state == "stumble" or _hit_area == null:
		return
	for body in _hit_area.get_overlapping_bodies():
		if not (body is VehicleBody3D) or body == current_vehicle:
			continue
		var vb := body as VehicleBody3D
		var vel := vb.linear_velocity
		var kmh := vel.length() * 3.6
		if vb.has_method("get_speed_kmh"):
			kmh = maxf(kmh, absf(float(vb.get_speed_kmh())))
		if kmh <= hit_speed_kmh:
			continue
		var to_me := global_position - vb.global_position
		to_me.y = 0.0
		if vel.length() > 0.1 and vel.normalized().dot(to_me.normalized()) < -0.2:
			continue  # se está alejando
		stumble_from(vel, kmh)
		return


## Atropello / empujón: cae en la dirección del impacto y se levanta (~1.6 s).
func stumble_from(impact_velocity: Vector3, kmh := -1.0) -> void:
	if current_vehicle != null:
		return
	if kmh < 0.0:
		kmh = impact_velocity.length() * 3.6
	var push := Vector3(impact_velocity.x, 0.0, impact_velocity.z)
	var strength := clampf(push.length() * 0.7, 2.5, 9.0)
	if push.length() < 0.01:
		push = -Vector3(-sin(_facing), 0.0, -cos(_facing))
	push = push.normalized()
	# Mira hacia el auto: así cae de espaldas, lejos de él
	_facing = atan2(push.x, push.z)
	velocity = push * strength + Vector3.UP * clampf(kmh * 0.06, 1.5, 4.5)
	_speed = 0.0
	_skidding = false
	_approach_vehicle = null
	_punch_t = -1.0
	_set_crouch(false, true)
	state = "stumble"
	_stumble_timer = 0.0
	floor_snap_length = 0.0
	stumbled.emit(kmh)


# =====================================================================
#  AGACHARSE · GOLPEAR · EMPUJAR
# =====================================================================

## Alterna el agachado con la acción "crouch". Correr/sprint lo cancela.
func _update_crouch(on_floor: bool) -> void:
	if Input.is_action_just_pressed("crouch") and on_floor and _punch_t < 0.0:
		_set_crouch(not _crouching)
	elif _crouching and Input.is_action_pressed("sprint"):
		_set_crouch(false)


## Cambia la cápsula entre de pie (1.78 m) y agachado (1.2 m). Para levantarse debe haber espacio
## encima (rayo contra el mundo); `force` salta esa comprobación (p. ej. al entrar a un auto).
func _set_crouch(on: bool, force := false) -> void:
	if on == _crouching:
		return
	if not on and not force:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, CAPSULE_H_CROUCH - 0.1, 0),
			global_position + Vector3(0, CAPSULE_H + 0.05, 0), 1)
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return
	_crouching = on
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape is CapsuleShape3D:
		var h := CAPSULE_H_CROUCH if on else CAPSULE_H
		(cs.shape as CapsuleShape3D).height = h
		cs.position.y = h * 0.5


## Combo de 3 golpes (jab, cruzado, patada) con la acción "punch". Pulsar de nuevo hacia el final
## de un golpe encadena el siguiente; si se deja pasar la ventana, el combo vuelve a empezar.
func _update_punch(delta: float, on_floor: bool) -> void:
	if _punch_t < 0.0:
		if Input.is_action_just_pressed("punch") and on_floor and state != "land":
			if _crouching:
				_set_crouch(false)
			_start_punch(0 if _combo_timer <= 0.0 else (_punch_idx + 1) % 3)
		return
	if Input.is_action_just_pressed("punch") and _punch_t > PUNCH_DUR[_punch_idx] * 0.4:
		_punch_queued = true
	_punch_t += delta
	if not _punch_hit_done and _punch_t >= PUNCH_HIT[_punch_idx]:
		_punch_hit_done = true
		_punch_hit()
	if _punch_t >= PUNCH_DUR[_punch_idx]:
		if _punch_queued and on_floor:
			_start_punch((_punch_idx + 1) % 3)
		else:
			_punch_t = -1.0
			_combo_timer = 0.45


func _start_punch(idx: int) -> void:
	_punch_idx = idx
	_punch_t = 0.0
	_punch_queued = false
	_punch_hit_done = false
	_skidding = false
	# Asistencia de puntería: se orienta hacia el objeto golpeable más cercano delante
	var fwd := Vector3(-sin(_facing), 0.0, -cos(_facing))
	var best: Node3D = null
	var best_d := 2.4
	for n in get_tree().get_nodes_in_group("props"):
		if not (n is RigidBody3D):
			continue
		var to: Vector3 = (n as Node3D).global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and d > 0.05 and fwd.dot(to / d) > 0.5:
			best_d = d
			best = n
	if best != null:
		var tp := best.global_position - global_position
		_facing = atan2(-tp.x, -tp.z)
	_speed = minf(_speed, 1.0)


## Daño del golpe: busca cuerpos en una esfera al frente del pecho. Los objetos livianos (conos…)
## salen despedidos; cualquier cuerpo con `take_hit(dir, power, attacker)` lo recibe (peatones futuros).
func _punch_hit() -> void:
	var fwd := Vector3(-sin(_facing), 0.0, -cos(_facing))
	# Cápsula vertical al frente (cubre desde el piso hasta la cabeza): golpea conos en el piso y cuerpos de pie
	var sph := CapsuleShape3D.new()
	sph.radius = 0.42 if _punch_idx < 2 else 0.5
	sph.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 0.85, 0) + fwd * punch_reach)
	q.collision_mask = (1 << 2) | (1 << 3)
	q.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(q, 8)
	for h in hits:
		var body := h.get("collider") as Node3D
		if body == null or body == current_vehicle or body is VehicleBody3D:
			continue
		var power: float = PUNCH_POWER[_punch_idx]
		if body.has_method("take_hit"):
			body.call("take_hit", fwd, power, self)
		elif body is RigidBody3D:
			var rb := body as RigidBody3D
			rb.sleeping = false
			rb.apply_central_impulse((fwd * power + Vector3.UP * power * 0.35) * minf(rb.mass, 20.0))
		punched.emit(body, _punch_idx)


## Empujar: al avanzar contra un RigidBody (no vehículo) se le transmite el movimiento; si es pesado
## el jugador se frena y adopta la pose de empujar.
func _handle_push(_delta: float) -> void:
	if state == "stumble" or state == "jump" or state == "fall":
		return
	var fwd := Vector3(-sin(_facing), 0.0, -cos(_facing))
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var rb := c.get_collider() as RigidBody3D
		if rb == null or rb is VehicleBody3D:
			continue
		var n := c.get_normal()
		n.y = 0.0
		if n.length() < 0.1 or _speed < 0.25 or fwd.dot(-n.normalized()) < 0.45:
			continue
		rb.sleeping = false
		# Iguala la velocidad del objeto a la del jugador (vence el rozamiento del piso)
		var dir := -n.normalized()
		var tv := maxf(push_speed * 0.85, minf(_speed + 0.5, 4.0)) if rb.mass <= 5.0 else push_speed * 0.85
		var dv := maxf(0.0, tv - rb.linear_velocity.dot(dir))
		rb.apply_central_impulse(dir * minf(rb.mass, 60.0) * dv * 0.6)
		if rb.mass > 5.0:
			_push_t = 0.25


# =====================================================================
#  VEHÍCULOS
# =====================================================================

func _try_interact() -> void:
	var best: VehicleBody3D = null
	var best_d := interact_radius
	for n in get_tree().get_nodes_in_group("vehicle"):
		if not (n is VehicleBody3D) or not n.has_method("get_entry_point") or not n.has_method("enter"):
			continue
		if n.has_method("is_occupied") and n.is_occupied():
			continue
		var d: float = global_position.distance_to(n.get_entry_point())
		if d <= best_d:
			best_d = d
			best = n
	if best == null:
		return
	if best_d < 0.6:
		_begin_enter(best)
	else:
		_approach_vehicle = best
		_approach_timer = 0.0


func _begin_enter(v: VehicleBody3D) -> void:
	_punch_t = -1.0
	_set_crouch(false, true)
	state = "enter_vehicle"
	_enter_timer = 0.0
	_entering_vehicle = v
	# Mirar hacia el auto
	var to := v.global_position - global_position
	to.y = 0.0
	if to.length() > 0.01:
		_facing = atan2(-to.x, -to.z)
	_speed = 0.0


func _process_entering(delta: float) -> void:
	_enter_timer += delta
	velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
	velocity.y -= _gravity * delta
	move_and_slide()
	var v := _entering_vehicle
	if v == null or not is_instance_valid(v) or (v.has_method("is_occupied") and v.is_occupied()):
		_entering_vehicle = null
		state = "idle"
		return
	if _enter_timer >= 0.6:
		_entering_vehicle = null
		enter_vehicle(v)


## Entra inmediatamente al vehículo (sin animación). Público para scripts/cinemáticas.
func enter_vehicle(v: VehicleBody3D) -> void:
	if v == null or current_vehicle != null:
		return
	current_vehicle = v
	state = "in_vehicle"
	visible = false
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.set_deferred("disabled", true)
	_hit_area.set_deferred("monitoring", false)
	velocity = Vector3.ZERO
	_speed = 0.0
	v.enter(self)
	if camera_rig and camera_rig.has_method("follow") and v.has_method("get_camera_anchor"):
		camera_rig.follow(v.get_camera_anchor(), "vehicle")
	entered_vehicle.emit(v)


## Sale del vehículo actual y reaparece en la posición segura que devuelve.
func exit_vehicle() -> void:
	var v := current_vehicle
	if v == null:
		return
	var pos: Vector3 = v.exit()
	current_vehicle = null
	global_position = pos + Vector3.UP * 0.05
	_facing = v.global_rotation.y
	visible = true
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs:
		cs.set_deferred("disabled", false)
	_hit_area.set_deferred("monitoring", true)
	# Hereda un poco de la velocidad del auto (salir en marcha)
	velocity = v.linear_velocity * 0.3
	velocity.y = 0.0
	_speed = 0.0
	state = "exit_vehicle"
	_exit_t = 0.0
	_crouching = false
	_punch_t = -1.0
	_was_on_floor = false
	floor_snap_length = 0.45
	model.rotation.y = _facing
	if camera_rig and camera_rig.has_method("follow"):
		camera_rig.follow(get_camera_anchor(), "on_foot")
	exited_vehicle.emit(v)


func _process_in_vehicle() -> void:
	if not is_instance_valid(current_vehicle):
		current_vehicle = null
		visible = true
		collision_layer = _saved_layer
		collision_mask = _saved_mask
		state = "idle"
		return
	# Viaja "dentro" del auto (para streaming, audio, etc.)
	global_position = current_vehicle.global_position
	if Input.is_action_just_pressed("interact"):
		exit_vehicle()


# =====================================================================
#  ENTRADA
# =====================================================================

## Dirección de movimiento en el mundo según la cámara (largo 0..1).
func _get_move_input() -> Vector3:
	var inputs := get_node_or_null("/root/Inputs")
	var mv: Vector2 = inputs.move_vector() if inputs else Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if mv.length() < 0.05:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	var yaw := 0.0
	if camera_rig and camera_rig.has_method("get_yaw"):
		yaw = camera_rig.get_yaw()
	elif cam:
		var f := -cam.global_basis.z
		yaw = atan2(-f.x, -f.z)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := fwd * mv.y + right * mv.x
	return dir.limit_length(1.0)

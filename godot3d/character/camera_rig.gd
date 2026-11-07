class_name CameraRig
extends Node3D
## Cámara en tercera persona sobre el hombro (a pie) y de persecución (en auto).
## Jerarquía: CameraRig (sigue al objetivo) → Yaw → Pitch → SpringArm3D → Camera3D.
## El SpringArm choca solo contra la capa 1 (world) para no atravesar paredes.

@export var mouse_sensitivity := 0.0025     # rad por píxel
@export var touch_sensitivity := 0.005
@export var pitch_min := deg_to_rad(-70.0)
@export var pitch_max := deg_to_rad(45.0)
@export var foot_distances: Array[float] = [2.3, 3.8]
@export var vehicle_distances: Array[float] = [6.0, 9.0]
@export var shoulder_offset := 0.55          # cámara a la derecha del hombro
@export var base_fov := 70.0
@export var sprint_fov := 79.0

var mode := "on_foot"
var target: Node3D = null

var yaw_node: Node3D
var pitch_node: Node3D
var spring: SpringArm3D
var camera: Camera3D

var _yaw := 0.0
var _pitch := deg_to_rad(-9.0)
var _dist_index := 0
var _shoulder := 0.0
var _last_manual := -10.0
var _time := 0.0
var _prev_target_pos := Vector3.ZERO
var _speed_f := 0.0
var _initialized := false


func _ready() -> void:
	add_to_group("camera_rig")
	top_level = true
	yaw_node = Node3D.new()
	yaw_node.name = "Yaw"
	add_child(yaw_node)
	pitch_node = Node3D.new()
	pitch_node.name = "Pitch"
	yaw_node.add_child(pitch_node)
	spring = SpringArm3D.new()
	spring.name = "SpringArm3D"
	spring.collision_mask = 1          # solo world
	var sph := SphereShape3D.new()
	sph.radius = 0.22
	spring.shape = sph
	spring.margin = 0.08
	spring.spring_length = foot_distances[0]
	pitch_node.add_child(spring)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = base_fov
	camera.near = 0.08
	camera.far = 2600.0  # montañas del valle (look/valley_backdrop) a ~2 km
	spring.add_child(camera)
	camera.current = true
	_apply_rotation()


## mode: "on_foot" | "vehicle"
func follow(new_target: Node3D, new_mode: String) -> void:
	var changed := new_mode != mode
	target = new_target
	mode = new_mode
	if changed or not _initialized:
		_dist_index = 0
	if target and target.is_inside_tree():
		_prev_target_pos = target.global_position
		if not _initialized:
			global_position = target.global_position
			_initialized = true
		if mode == "vehicle":
			# Arranca detrás del auto
			_yaw = _target_heading()
			_pitch = deg_to_rad(-12.0)
	# Excepciones del SpringArm: no chocar con el propio objetivo
	spring.clear_excluded_objects()
	var body := _find_body(target)
	if body:
		spring.add_excluded_object(body.get_rid())


func get_yaw() -> float:
	return _yaw


func get_camera() -> Camera3D:
	return camera


func _find_body(n: Node) -> CollisionObject3D:
	while n != null:
		if n is CollisionObject3D:
			return n
		n = n.get_parent()
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative * mouse_sensitivity)
	if event.is_action_pressed("camera_toggle"):
		_dist_index = (_dist_index + 1) % 2


func _look(d: Vector2) -> void:
	_yaw -= d.x
	_pitch = clampf(_pitch - d.y, pitch_min, pitch_max)
	_last_manual = _time


func _process(delta: float) -> void:
	_time += delta
	var inputs := get_node_or_null("/root/Inputs")
	var touch: Vector2 = inputs.take_touch_look() if inputs else Vector2.ZERO
	if touch.length_squared() > 0.0:
		_look(touch * touch_sensitivity)
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var tpos := target.global_position
	var tvel := (tpos - _prev_target_pos) / maxf(delta, 0.0001)
	_prev_target_pos = tpos
	var hs := Vector2(tvel.x, tvel.z).length()
	if hs > 60.0:
		hs = 0.0   # teletransporte (entrar/salir de un auto)
	_speed_f = lerpf(_speed_f, hs, 1.0 - exp(-4.0 * delta))

	if mode == "vehicle":
		_update_vehicle(tpos, delta)
	else:
		_update_foot(tpos, delta)
	_apply_rotation()


func _update_foot(tpos: Vector3, delta: float) -> void:
	# Horizontal rápido, vertical más suave (escalones, saltos)
	var p := global_position
	if p.distance_to(tpos) > 8.0:
		p = tpos
	var kh := 1.0 - exp(-16.0 * delta)
	var kv := 1.0 - exp(-7.0 * delta)
	p.x = lerpf(p.x, tpos.x, kh)
	p.z = lerpf(p.z, tpos.z, kh)
	p.y = lerpf(p.y, tpos.y, kv)
	global_position = p
	var dist: float = foot_distances[_dist_index]
	spring.spring_length = lerpf(spring.spring_length, dist, 1.0 - exp(-5.0 * delta))
	_shoulder = lerpf(_shoulder, shoulder_offset, 1.0 - exp(-5.0 * delta))
	spring.position = Vector3(_shoulder, 0.0, 0.0)
	# FOV: se abre con el sprint
	var sp := clampf((_speed_f - 4.5) / 2.5, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, lerpf(base_fov, sprint_fov, sp), 1.0 - exp(-3.0 * delta))


func _update_vehicle(tpos: Vector3, delta: float) -> void:
	var p := global_position
	if p.distance_to(tpos) > 25.0:
		p = tpos
	global_position = p.lerp(tpos, 1.0 - exp(-10.0 * delta))
	var dist: float = vehicle_distances[_dist_index]
	spring.spring_length = lerpf(spring.spring_length, dist + _speed_f * 0.04, 1.0 - exp(-3.0 * delta))
	_shoulder = lerpf(_shoulder, 0.0, 1.0 - exp(-5.0 * delta))
	spring.position = Vector3(_shoulder, 1.2, 0.0)
	# Sigue la dirección del auto con retraso, salvo si el jugador mueve la cámara
	if _time - _last_manual > 1.6 and _speed_f > 1.0:
		var heading := _target_heading()
		var k := 1.0 - exp(-2.2 * delta)
		_yaw += wrapf(heading - _yaw, -PI, PI) * k
		_pitch = lerpf(_pitch, deg_to_rad(-10.0), k)
	var kmh := _speed_f * 3.6
	var veh := _find_body(target)
	if veh and veh.has_method("get_speed_kmh"):
		kmh = absf(float(veh.get_speed_kmh()))
	var fov_t := clampf(kmh / 130.0, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, lerpf(68.0, 84.0, fov_t), 1.0 - exp(-2.0 * delta))


func _target_heading() -> float:
	if target == null:
		return _yaw
	var f := -target.global_basis.z
	var body := _find_body(target)
	if body:
		f = -body.global_basis.z
	return atan2(-f.x, -f.z)


func _apply_rotation() -> void:
	yaw_node.rotation = Vector3(0.0, _yaw, 0.0)
	pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)

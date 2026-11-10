extends Node3D
## Pista de pruebas de vehículos: piso grande, rampa, sardineles de 0.15 m, conos.
## Teclado: WASD/flechas manejar, Espacio freno de mano, H pito, F salir/entrar, 1-4 cambiar de auto.
## Con VEH_AUTODRIVE=1 (o autodrive=true) el sedán acelera y gira solo (para capturas).

@export var autodrive := false

var vehicles: Array[Vehicle] = []
var current: Vehicle
var cam: Camera3D
var driver: Node3D
var _t := 0.0


func _ready() -> void:
	if OS.get_environment("VEH_AUTODRIVE") != "":
		autodrive = true
	_build_env()
	_build_track()
	driver = Node3D.new()
	driver.name = "TestDriver"
	add_child(driver)
	var kinds := ["sedan", "taxi", "pickup", "buseta"]
	for i in kinds.size():
		var xf := Transform3D(Basis.IDENTITY, Vector3(-9.0 + i * 5.0, 0, 0))
		vehicles.append(VehicleFactory.spawn(kinds[i], xf, self))
	current = vehicles[0]
	current.enter(driver)
	cam = Camera3D.new()
	cam.fov = 65.0
	add_child(cam)
	cam.global_position = current.global_position + Vector3(0, 3, 7)


func _build_env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _static_box(pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation = rot
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	sb.add_child(mi)
	add_child(sb)


func _build_track() -> void:
	_static_box(Vector3(0, -0.5, -100), Vector3(400, 1, 400), Palette.asphalt())
	# Rampa (12 m, ~11°) y meseta.
	_static_box(Vector3(20, 1.1, -40), Vector3(6, 0.4, 12), Palette.concrete(), Vector3(deg_to_rad(11), 0, 0))
	_static_box(Vector3(20, 1.2, -51), Vector3(6, 2.4, 10), Palette.concrete())
	# Andenes con sardinel de 0.15 m.
	_static_box(Vector3(-25, 0.075, -40), Vector3(8, 0.15, 60), Palette.sidewalk())
	_static_box(Vector3(0, 0.075, -90), Vector3(30, 0.15, 6), Palette.sidewalk())
	for i in 6:
		_static_box(Vector3(-20.9, 0.075, -12 - i * 10), Vector3(0.2, 0.15, 9.8), Palette.curb())
	# Conos (props dinámicos, capa 4).
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.03
	cone_mesh.bottom_radius = 0.17
	cone_mesh.height = 0.5
	cone_mesh.radial_segments = 10
	cone_mesh.material = Palette.car_paint(Color(1.0, 0.4, 0.05))
	var shape := CylinderShape3D.new()
	shape.radius = 0.14
	shape.height = 0.5
	for i in 10:
		var rb := RigidBody3D.new()
		rb.collision_layer = 1 << 3
		rb.collision_mask = (1 << 0) | (1 << 2) | (1 << 3)
		rb.mass = 2.0
		rb.position = Vector3(-6 + (i % 2) * 2.5, 0.26, -15 - i * 5)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = cone_mesh
		rb.add_child(mi)
		add_child(rb)


func _physics_process(delta: float) -> void:
	_t += delta
	if autodrive:
		Input.action_press("move_forward", 0.8 if _t < 4.0 else 0.45)
		if _t > 2.2:
			Input.action_press("move_right", 0.7)


func _process(delta: float) -> void:
	if current == null:
		return
	var a := current.get_camera_anchor()
	var back := a.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var dist := 7.0 if current.kind != "buseta" else 11.0
	var target := a.global_position + back * dist + Vector3.UP * 1.6
	cam.global_position = cam.global_position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	cam.look_at(a.global_position, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			if current.is_occupied():
				current.exit()
			current = vehicles[k - KEY_1]
			current.enter(driver)
	if event.is_action_pressed("interact"):
		if current.is_occupied():
			driver.global_position = current.exit()
		else:
			current.enter(driver)

extends Node3D
## Escena de calibración del look. Preset por argumento:
##   ... -s res://tests/screenshot.gd -- res://tests/scenes/look_test.tscn out.png 60 rainy_night
## o variable de entorno LOOK_PRESET. En juego: teclas 1/2/3 cambian preset, P = post-fx.

@export var preset := "overcast_day"

var look: StreetLook


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 3:
		preset = args[3]
	elif OS.get_environment("LOOK_PRESET") != "":
		preset = OS.get_environment("LOOK_PRESET")

	look = StreetLook.new()
	look.name = "StreetLook"
	add_child(look)
	look.set_time_of_day(preset)

	_build_street()
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = Vector3(-2.2, 1.7, 16.0)
	cam.look_at(Vector3(1.0, 3.2, -30.0))
	cam.current = true


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		match (e as InputEventKey).keycode:
			KEY_1: look.set_time_of_day("overcast_day")
			KEY_2: look.set_time_of_day("golden_hour")
			KEY_3: look.set_time_of_day("rainy_night")
			KEY_P: look.set_post_fx_enabled(not look.enable_post_fx)


func _box(size: Vector3, pos: Vector3, mat: Material, shadow := true) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _omni(pos: Vector3, color: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	add_child(l)


func _build_street() -> void:
	# calzada (12 m) entre andenes, a lo largo de Z
	_box(Vector3(12, 0.2, 140), Vector3(0, -0.1, -40), Palette.asphalt())
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(40, 0.2, 140)
	col.shape = shp
	body.position = Vector3(0, -0.1, -40)
	body.add_child(col)
	add_child(body)
	_box(Vector3(4, 0.3, 140), Vector3(-8, 0.0, -40), Palette.sidewalk())
	_box(Vector3(4, 0.3, 140), Vector3(8, 0.0, -40), Palette.sidewalk())
	_box(Vector3(0.25, 0.32, 140), Vector3(-6.1, 0.01, -40), Palette.curb())
	_box(Vector3(0.25, 0.32, 140), Vector3(6.1, 0.01, -40), Palette.curb())
	# líneas viales discontinuas
	for i in 14:
		_box(Vector3(0.15, 0.02, 3.0), Vector3(0, 0.005, 20 - i * 8.0), Palette.road_line(), false)
	# plaza al fondo
	_box(Vector3(30, 0.3, 30), Vector3(0, -0.2, -125), Palette.plaza_tile())

	# edificios a ambos lados (ladrillo, estuco, concreto)
	var mats_l: Array[Material] = [Palette.brick(), Palette.stucco(1), Palette.stucco(2), Palette.concrete(), Palette.stucco(3)]
	var mats_r: Array[Material] = [Palette.stucco(0), Palette.brick(), Palette.stucco(4), Palette.stucco(5), Palette.brick()]
	for i in 5:
		var z := 10.0 - i * 20.0
		var hl := 9.0 + float((i * 7) % 4) * 3.0
		var hr := 8.0 + float((i * 5) % 3) * 4.0
		_building(Vector3(-14, 0, z), Vector3(8, hl, 18), mats_l[i], 1.0)
		_building(Vector3(14, 0, z), Vector3(8, hr, 18), mats_r[i], -1.0)

	# neones: cian, magenta, ámbar (con OmniLight corta para que se reflejen en el piso)
	_neon_sign(Vector3(-9.85, 4.0, 4.0), Vector3(0.12, 0.5, 3.2), Palette.NEON_CYAN)
	_neon_sign(Vector3(9.85, 3.4, -8.0), Vector3(0.12, 0.45, 2.6), Palette.NEON_MAGENTA)
	_neon_sign(Vector3(-9.85, 3.0, -24.0), Vector3(0.12, 1.6, 0.35), Palette.NEON_MAGENTA)
	_neon_sign(Vector3(9.85, 4.6, -30.0), Vector3(0.12, 0.4, 3.0), Palette.NEON_CYAN)
	_neon_sign(Vector3(-9.85, 3.6, -44.0), Vector3(0.12, 0.45, 2.4), Palette.NEON_AMBER)

	# postes con bombillo ámbar
	for z in [8.0, -14.0, -36.0, -58.0]:
		_lamp_post(Vector3(5.6, 0, z))
		_lamp_post(Vector3(-5.6, 0, z - 11.0))

	# persona (cápsula)
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.75
	var p := MeshInstance3D.new()
	p.mesh = cap
	p.material_override = Palette.cloth(Color(0.12, 0.13, 0.16))
	p.position = Vector3(-1.0, 0.75, 6.0)
	add_child(p)
	var head := SphereMesh.new()
	head.radius = 0.13
	head.height = 0.26
	var h := MeshInstance3D.new()
	h.mesh = head
	h.material_override = Palette.skin()
	h.position = Vector3(-1.0, 1.75, 6.0)
	add_child(h)

	# un carro simple (taxi) con faros
	_box(Vector3(1.8, 0.7, 4.2), Vector3(3.0, 0.35, -4.0), Palette.car_paint(Color(0.95, 0.75, 0.05)))
	_box(Vector3(1.6, 0.55, 2.2), Vector3(3.0, 0.95, -4.3), Palette.window_glass())
	_box(Vector3(0.35, 0.15, 0.05), Vector3(2.45, 0.45, -1.88), Palette.headlight(), false)
	_box(Vector3(0.35, 0.15, 0.05), Vector3(3.55, 0.45, -1.88), Palette.headlight(), false)
	_box(Vector3(0.3, 0.12, 0.05), Vector3(2.45, 0.5, -6.12), Palette.taillight(), false)
	_box(Vector3(0.3, 0.12, 0.05), Vector3(3.55, 0.5, -6.12), Palette.taillight(), false)
	_omni(Vector3(3.0, 0.5, -0.8), Color(1.0, 0.92, 0.8), 1.2, 7.0)

	# árbol del parque
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.25
	trunk.height = 4.0
	var t := MeshInstance3D.new()
	t.mesh = trunk
	t.material_override = Palette.bark()
	t.position = Vector3(-7.5, 2.0, -70)
	add_child(t)
	var crown := SphereMesh.new()
	crown.radius = 2.6
	crown.height = 4.0
	var c := MeshInstance3D.new()
	c.mesh = crown
	c.material_override = Palette.foliage()
	c.position = Vector3(-7.5, 5.0, -70)
	add_child(c)


func _building(base: Vector3, size: Vector3, mat: Material, facing: float) -> void:
	_box(size, base + Vector3(0, size.y * 0.5 - 0.05, 0), mat)
	# alero / techo
	_box(Vector3(size.x + 0.6, 0.25, size.z + 0.4), base + Vector3(0, size.y, 0), Palette.roof_tile())
	# ventanas en la fachada que mira a la calle
	var fx := base.x + facing * (size.x * 0.5 + 0.02)
	var floors := int(size.y / 3.0)
	for f in range(1, floors):
		for k in 4:
			var z := base.z - size.z * 0.5 + 2.5 + k * 4.3
			var lit := ((f * 3 + k * 7 + int(base.z)) % 5) == 0
			var mat_w := Palette.window_lit() if lit else Palette.window_glass()
			_box(Vector3(0.06, 1.3, 1.1), Vector3(fx, f * 3.0 + 0.6, z), mat_w, false)
	# puerta de local con reja
	_box(Vector3(0.08, 2.6, 3.0), Vector3(fx, 1.3, base.z), Palette.metal_dark(), false)


func _neon_sign(pos: Vector3, size: Vector3, color: Color) -> void:
	_box(size, pos, Palette.neon(color, 4.0), false)
	var side := -signf(pos.x)
	_omni(pos + Vector3(side * 1.2, -0.5, 0), color, 3.0, 10.0)


func _lamp_post(base: Vector3) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.09
	pole.height = 6.0
	var mi := MeshInstance3D.new()
	mi.mesh = pole
	mi.material_override = Palette.metal_dark()
	mi.position = base + Vector3(0, 3.0, 0)
	add_child(mi)
	var arm_dir := -signf(base.x)
	_box(Vector3(1.4, 0.08, 0.08), base + Vector3(arm_dir * 0.7, 6.0, 0), Palette.metal_dark())
	var bulb := SphereMesh.new()
	bulb.radius = 0.16
	bulb.height = 0.24
	var b := MeshInstance3D.new()
	b.mesh = bulb
	b.material_override = Palette.lamp_bulb()
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.position = base + Vector3(arm_dir * 1.35, 5.85, 0)
	add_child(b)
	_omni(b.position + Vector3(0, -0.3, 0), Color(1.0, 0.68, 0.38), 4.0, 14.0)

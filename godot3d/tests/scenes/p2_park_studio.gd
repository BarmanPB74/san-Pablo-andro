extends Node3D
## Estudio F2-06 (mobiliario del parque). Args de usuario: <escena> <png> <frames> [cam px,py,pz] [target tx,ty,tz] [preset]

func _v(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _mi(mesh: Mesh, xf: Transform3D) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.transform = xf
	add_child(m)


func _floor(mat: Material, x0: float, x1: float, z0: float, z1: float, y := 0.0) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	m.mesh = pm
	m.material_override = mat
	m.position = Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
	add_child(m)


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var look := StreetLook.new()
	add_child(look)
	look.set_time_of_day(a[5] if a.size() > 5 else "overcast_day")
	_floor(MatPaving.hex_pavers(), -20, 20, -20, 20)
	_floor(MatPaving.herringbone_pavers(), -20, -4, -20, 20, 0.01)
	_floor(MatGround.pasto(), 3.0, 12.0, -10.0, -2.0, WALL_TOP - 0.1)
	var w := ParkFurniture.planter_wall()
	var sh := Basis.IDENTITY
	# Jardinera de 9 x 8 con reja en dos lados.
	_mi(w, Transform3D(Basis.from_scale(Vector3(9, 1, 1)), Vector3(3, 0, -2.15)))
	_mi(w, Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(8, 1, 1)), Vector3(3.15, 0, -2)))
	_mi(ParkFurniture.planter_corner(), Transform3D(sh, Vector3(3.15, 0, -2.15)))
	var c := ParkFurniture.path_curb()
	_mi(c, Transform3D(Basis.from_scale(Vector3(9, 1, 1)), Vector3(3, 0, -1.92)))
	for i in 4:
		_mi(ParkFurniture.fence_segment(), Transform3D(sh, Vector3(3.0 + 1.9 * i, 0.45, -2.15)))
	_mi(ParkFurniture.fence_post(), Transform3D(sh, Vector3(3.0 + 7.6, 0.45, -2.15)))
	_mi(ParkFurniture.wood_bench(), Transform3D(sh, Vector3(4.8, 0, -1.4)))
	_mi(ParkFurniture.granite_bench(0), Transform3D(sh, Vector3(7.8, 0, -1.5)))
	_mi(ParkFurniture.granite_bench(1), Transform3D(sh, Vector3(10.5, 0, -1.5)))
	_mi(ParkFurniture.park_bin(), Transform3D(sh, Vector3(6.4, 0, -1.4)))
	_mi(ParkFurniture.park_lamp(0), Transform3D(sh, Vector3(2.2, 0, -1.0)))
	_mi(ParkFurniture.park_lamp(1), Transform3D(sh, Vector3(12.5, 0, -1.0)))
	for i in 4:
		_mi(ParkFurniture.food_cart(i), Transform3D(Basis(Vector3.UP, 0.3 * i), Vector3(-1.0 + 3.4 * i, 0, 3.5)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.45)
	l.light_energy = 1.4
	l.omni_range = 11.0
	l.position = Vector3(2.2, ParkFurniture.LAMP_LIGHT_Y, -1.0)
	add_child(l)
	var tot := 0
	for k in ParkFurniture.stats:
		tot += ParkFurniture.stats[k]
	print("TRIS ", ParkFurniture.stats)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 3000.0
	add_child(cam)
	cam.position = _v(a[3]) if a.size() > 3 else Vector3(6, 2.2, 9)
	cam.look_at(_v(a[4]) if a.size() > 4 else Vector3(6, 0.8, -1))
	cam.current = true

const WALL_TOP := ParkFurniture.WALL_H

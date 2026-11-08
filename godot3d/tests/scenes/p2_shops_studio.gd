extends Node3D
## Estudio F2-07 (locales comerciales). Args: <escena> <png> <frames> [vista] [preset]
## vista: far | near | blade | side ; preset: overcast_day | golden_hour | rainy_night

var _mm := {}


func place_mesh(key: String, mesh: Mesh, xf: Transform3D, shadow := true) -> void:
	if not _mm.has(key):
		_mm[key] = {"mesh": mesh, "xf": [], "shadow": shadow}
	_mm[key].xf.append(xf)


func place_node(node: Node3D, xf: Transform3D) -> void:
	node.transform = xf
	add_child(node)


func add_col_box(_xf: Transform3D, _size: Vector3) -> void:
	pass


func _box(mat: Material, c: Vector3, size: Vector3, rot := Basis.IDENTITY) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.transform = Transform3D(rot, c)
	add_child(mi)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view: String = args[3] if args.size() > 3 else "far"
	var preset: String = args[4] if args.size() > 4 else "overcast_day"
	var look := StreetLook.new()
	add_child(look)
	look.set_time_of_day(preset)
	var slope := Basis(Vector3.BACK, atan(BostonDistrict.SLOPE))
	_box(Palette.sidewalk(), Vector3(0, -0.1, 2.0), Vector3(60, 0.2, 4.0), slope)
	_box(Palette.asphalt(), Vector3(0, -0.3, 10.0), Vector3(60, 0.2, 12.0), slope)
	Shopfronts.debug_force_lattice = true
	var x := -19.0
	var i := 0
	for w: float in [8.0, 12.5, 7.5, 17.0]:
		var cx := x + w * 0.5
		var y := BostonDistrict.walk_y(cx)
		var mat: Material = Palette.brick() if i % 2 == 0 else Palette.stucco(i)
		_box(mat, Vector3(cx, y + 5.0, -5.0), Vector3(w, 12.0, 10.0))
		var xf := Transform3D(Basis.IDENTITY, Vector3(cx, y, 0))
		Shopfronts.build(self, xf, w, 3.4, i != 2, i % 2 == 1, true, i * 5 + 2)
		x += w
		i += 1
	for key in _mm:
		var d: Dictionary = _mm[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = d.mesh
		mm.instance_count = d.xf.size()
		for k in d.xf.size():
			mm.set_instance_transform(k, d.xf[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	var total := 0
	for k in Shopfronts.tri_count:
		total += int(Shopfronts.tri_count[k])
	print("SHOPF keys=", _mm.size(), " tris=", Shopfronts.tri_count)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 800.0
	add_child(cam)
	match view:
		"near":
			cam.position = Vector3(-6.5, 1.65, 3.6)
			cam.look_at(Vector3(-11.5, 2.2, 0.0))
		"blade":
			cam.position = Vector3(2.0, 1.7, 2.2)
			cam.look_at(Vector3(-8.0, 2.6, 0.2))
		"lattice":
			cam.position = Vector3(3.5, 1.6, 5.5)
			cam.look_at(Vector3(4.0, 1.9, 0.0))
		"side":
			cam.position = Vector3(12.0, 1.7, 2.6)
			cam.look_at(Vector3(-4.0, 2.0, -0.5))
		_:
			cam.position = Vector3(-3.0, 1.7, 9.5)
			cam.look_at(Vector3(-3.0, 2.3, 0.0))
	cam.current = true

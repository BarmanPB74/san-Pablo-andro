extends Node3D
## Estudio F2-05 (monumento / iglesia). Args de usuario tras escena/salida/frames:
## <modo: mon|church> <px,py,pz> <tx,ty,tz> [fov]

var tris := 0

func _v(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var mode: String = a[3] if a.size() > 3 else "mon"
	var look := StreetLook.new()
	look.enable_rain = false
	add_child(look)
	look.set_time_of_day("overcast_day")
	# Piso (baldosa de plaza) inclinado 4 % como el mapa.
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	fl.mesh = pm
	fl.material_override = Palette.plaza_tile()
	fl.transform = Transform3D(Basis(Vector3.BACK, atan(0.04)), Vector3.ZERO)
	add_child(fl)
	if mode == "mon":
		Monument.build(self)
	else:
		Church.build(self, Transform3D(Basis.IDENTITY, Vector3(0, 1.7, 0)), 1.7)
	var cam := Camera3D.new()
	cam.far = 2600.0
	cam.fov = float(a[6]) if a.size() > 6 else 60.0
	add_child(cam)
	cam.global_position = _v(a[4]) if a.size() > 4 else Vector3(0, 3, 14)
	cam.look_at(_v(a[5]) if a.size() > 5 else Vector3(0, 3.5, 0))
	cam.current = true
	print("STUDIO_TRIS ", tris)

func place_mesh(key: String, mesh: Mesh, xf: Transform3D, shadow := true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var t := 0
	for s in mesh.get_surface_count():
		t += mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
	tris += t
	print("MESH ", key, " tris=", t, " surfs=", mesh.get_surface_count())

func place_node(node: Node3D, xf: Transform3D) -> void:
	node.transform = xf
	add_child(node)

func add_col_box(_xf: Transform3D, _size: Vector3) -> void:
	pass

func add_col_cyl(_c: Vector3, _r: float, _h: float) -> void:
	pass

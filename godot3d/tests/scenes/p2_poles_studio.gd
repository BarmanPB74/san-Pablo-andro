extends Node3D
## Estudio F2-03 (postes). Args de usuario: [3] vista 0..3, [4] preset.

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var view := int(a[3]) if a.size() > 3 else 0
	var preset: String = a[4] if a.size() > 4 else "overcast_day"
	var look := StreetLook.new()
	look.initial_preset = preset
	look.enable_rain = false
	add_child(look)
	# piso: calzada + andén + fachada
	_box(Palette.asphalt(), Vector3(4, -0.1, 0), Vector3(8, 0.2, 120))
	_box(Palette.sidewalk(), Vector3(-1.25, 0.0, 0), Vector3(2.5, 0.3, 120))
	_box(Palette.brick(), Vector3(-4.5, 6, 0), Vector3(4, 12, 120))
	_box(Palette.stucco(2), Vector3(11.0, 6, 0), Vector3(4, 12, 120))
	var to_road := Vector3(1, 0, 0)
	var along := Vector3(to_road.z, 0, -to_road.x)
	var B := Basis(along, Vector3.UP, to_road)
	var sw := Poles.make_light_switch()
	add_child(sw)
	var pts := [Vector3(-0.5, 0.1, -33), Vector3(-0.5, 0.1, 0), Vector3(-0.5, 0.1, 33)]
	for i in pts.size():
		var p: Vector3 = pts[i]
		_mm(Poles.pole([1, 2, 3][i]), Transform3D(B, p))
		_mm(Poles.luminaire(), Transform3D(B, p))
		var l := Poles.make_lamp_light()
		l.transform = Poles.lamp_light_xform(Transform3D(B, p))
		sw.add_child(l)
		if i > 0:
			var r := Poles.span_transform(pts[i - 1], p, to_road)
			_mm(Poles.span(r[2], r[1]), r[0])
	var g := Poles.span_transform(pts[0], pts[0] + Vector3(0, 0, -1), to_road)
	_mm(Poles.guy(), Transform3D(Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(1, 0, 0) * -1).orthonormalized() if false else Basis(Vector3(0,0,1), Vector3.UP, Vector3(-1,0,0)), pts[0]))
	# acometidas
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in pts:
		var xf := Transform3D(B, p)
		Poles.append_cable(st, xf * Poles.DROP_LV, Vector3(-2.5, 5.2, p.z + 5.0), 0.25, 0.008, 3, 6)
		Poles.append_cable(st, xf * Poles.DROP_TEL, Vector3(9.0, 6.0, p.z - 4.0), 0.35, 0.01, 3, 6)
	var cm := st.commit()
	cm.surface_set_material(0, Poles.cable_mat())
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	add_child(mi)
	var cam := Camera3D.new()
	cam.far = 2600
	add_child(cam)
	var views := [
		[Vector3(6.5, 1.7, 14), Vector3(-0.5, 6.5, -6)],
		[Vector3(2.5, 9.3, 4.0), Vector3(-0.5, 9.0, 0)],
		[Vector3(4.5, 1.7, 20), Vector3(0, 5, -20)],
		[Vector3(3.0, 6.5, -30.5), Vector3(-0.6, 7.2, -33)],
	]
	cam.position = views[view][0]
	cam.look_at(views[view][1])
	cam.current = true
	# conteo de triángulos
	for k in 4:
		print("pole_%d tris=%d" % [k, _tris(Poles.pole(k))])
	print("lum tris=%d span33 tris=%d span66 tris=%d guy=%d" % [_tris(Poles.luminaire()), _tris(Poles.span(33, 1)), _tris(Poles.span(66, 1)), _tris(Poles.guy())])

func _tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		n += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n

func _mm(m: Mesh, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.transform = xf
	add_child(mi)

func _box(mat: Material, p: Vector3, s: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	mi.mesh = b
	mi.material_override = mat
	mi.position = p
	add_child(mi)

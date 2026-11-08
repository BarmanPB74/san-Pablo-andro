extends Node3D
## Estudio F2-04 (Traffic). Args: ... -- escena salida frames <vista 0..4> [preset]
## Calle N-S de 7 m (x -3.5..3.5) con andenes; cruce en z = 0 (calle E-O).

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view := int(args[3]) if args.size() > 3 else 0
	var look := StreetLook.new()
	add_child(look)
	look.set_time_of_day(args[4] if args.size() > 4 else "overcast_day")
	_slab(Vector3(0, -0.05, 0), Vector3(80, 0.1, 80), MatAsphalt.asphalt_new())
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_slab(Vector3(sx * 21.75, 0.075, sz * 21.75), Vector3(36.5, 0.15, 36.5), Palette.sidewalk())
	# pintura
	var d := Traffic.Decals.new()
	d.slope = 0.0
	d.base = 0.0
	d.lift = 0.006
	d.dashed("line_yellow", Vector2(0, 40), Vector2(0, 22))
	d.line("line_yellow", Vector2(0, 22), Vector2(0, 8.2))
	d.line("line_white", Vector2(3.2, 40), Vector2(3.2, 8.2))
	d.line("line_white", Vector2(-3.2, 40), Vector2(-3.2, 8.2))
	for i in 7:
		d.add("zebra_bar", Vector2(-3.0 + i * 1.0, 5.6), Vector2(1, 0), Vector2(3.0, 0.8))
	d.add("line_white", Vector2(1.75, 7.8), Vector2(1, 0), Vector2(0.55, 3.3), 3.3 / 2.56)
	d.add("text_pare", Vector2(1.75, 10.5), Vector2(0, -1))
	d.add("arrow_straight", Vector2(1.75, 16.0), Vector2(0, -1))
	d.add("num_30", Vector2(1.75, 24.0), Vector2(0, -1))
	d.add("arrow_turn", Vector2(-1.75, -16.0), Vector2(0, 1))
	for m in d.meshes("dec"):
		_mi(m[1], Transform3D.IDENTITY, false)
	# semáforo en esquina SE: brazo hacia el oeste, cabezas mirando al sur (+Z)
	var arm := Vector3(-1, 0, 0)
	var face := Vector3(0, 0, 1)
	var pb := Basis(arm, Vector3.UP, -face)
	var pxf := Transform3D(pb, Vector3(4.4, 0.15, 4.4))
	_mi(Traffic.signal_pole(4.0), pxf)
	var an := Traffic.signal_anchors(4.0)
	for h in an.heads:
		_mi(Traffic.signal_head("A"), pxf * h)
	_mi(Traffic.signal_head("A"), pxf * an.rep)
	_mi(Traffic.ped_head("B"), pxf * an.ped_arm)
	_mi(Traffic.ped_head("A"), pxf * an.ped_back)
	var w := Transform3D(Basis(Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1)), Vector3(-4.4, 0.15, 4.4))
	_mi(Traffic.signal_pole(7.0), Transform3D(Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0)) , Vector3(-4.4, 0.15, 4.4)))
	# señales
	var names := ["pare", "baje_en_2a", "velocidad_30", "no_parquear", "peligro_curva", "paso_peatonal", "ceda_el_paso", "una_via"]
	for i in names.size():
		_mi(Traffic.sign_post_named(names[i], 2.4 + 0.1 * (i % 2)), Transform3D(Basis.IDENTITY, Vector3(4.2, 0.15, 9.0 + i * 2.2)))
	_mi(Traffic.plate_post(Traffic.plate_index("C55"), Traffic.plate_index("K38")), Transform3D(Basis.IDENTITY, Vector3(-4.3, 0.15, -4.3)))
	for i in 4:
		_mi(Traffic.bollard(i % 2), Transform3D(Basis.IDENTITY, Vector3(-4.0, 0.15, 6.0 + i * 1.3)))
	_mi(Traffic.bin(0), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-4.6, 0.15, 12.0)))
	_mi(Traffic.bin(1), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-4.6, 0.15, 14.0)))
	_mi(Traffic.hydrant(0), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-4.3, 0.15, 16.5)))
	_mi(Traffic.hydrant(1), Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-4.3, 0.15, 18.0)))
	_mi(Traffic.manhole(0), Transform3D(Basis.IDENTITY, Vector3(1.6, 0.0, 13.0)))
	_mi(Traffic.manhole(1), Transform3D(Basis.IDENTITY, Vector3(-1.8, 0.0, 19.0)))
	_mi(Traffic.drain_grate(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-3.5, 0.0, 10.0)))
	var cyc := Traffic.Cycle.new()
	add_child(cyc)
	cyc.t = float(args[5]) if args.size() > 5 else 1.0
	var tot := 0
	for k in Traffic._mesh:
		print("TRIS ", k, " ", Traffic.tri_count(Traffic._mesh[k]), " surf ", Traffic._mesh[k].get_surface_count())
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	var views := [
		[Vector3(-1.5, 1.7, 22.0), Vector3(1.0, 2.5, 4.0)],
		[Vector3(1.0, 4.6, 7.5), Vector3(2.9, 4.9, 4.4)],
		[Vector3(-1.0, 1.6, 6.5), Vector3(4.2, 1.5, 12.0)],
		[Vector3(-1.5, 1.2, 15.0), Vector3(-4.3, 0.6, 14.0)],
		[Vector3(1.5, 6.0, 30.0), Vector3(0.0, 0.0, 10.0)],
		[Vector3(0.5, 14.0, 14.0), Vector3(0.5, 0.0, 13.9)],
	]
	cam.position = views[view][0]
	cam.look_at(views[view][1])
	cam.current = true


func _slab(p: Vector3, s: Vector3, m: Material) -> void:
	var b := BoxMesh.new()
	b.size = s
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = m
	mi.position = p
	add_child(mi)


func _mi(mesh: Mesh, xf: Transform3D, shadow := true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

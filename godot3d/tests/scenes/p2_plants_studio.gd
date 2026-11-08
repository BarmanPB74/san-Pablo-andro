extends Node3D
## Estudio F2-02 (Plants). Vista por 4º argumento: far | near | palm | hedge
## ... -s res://tests/screenshot.gd -- res://tests/scenes/p2_plants_studio.tscn out.png 30 near

func _mm(mesh: Mesh, xfs: Array, shadow := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _one(mesh: Mesh, p: Vector3, yaw := 0.0) -> void:
	_mm(mesh, [Transform3D(Basis(Vector3.UP, yaw), p)])


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view: String = args[3] if args.size() > 3 else "far"
	var look := StreetLook.new()
	add_child(look)
	look.set_time_of_day("overcast_day")
	# Piso: andén + pasto.
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	g.mesh = pm
	g.material_override = MatPaving.sidewalk_concrete_dry()
	add_child(g)
	var gr := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(14, 0.35, 8)
	gr.mesh = bm
	gr.position = Vector3(-4, 0.175, -6)
	gr.material_override = MatGround.pasto()
	add_child(gr)
	var tris := 0
	# Palmas altas.
	for v in Plants.TALL_PALM_VARIANTS:
		var m := Plants.tall_palm(v)
		tris = maxi(tris, m.get_meta("tris"))
		print("tall_palm_%d tris=%d" % [v, m.get_meta("tris")])
		_one(m, Vector3(4 + v * 3.5, 0, -4 - v), v * 1.3)
	for v in Plants.SMALL_PALM_VARIANTS:
		var m2 := Plants.small_palm(v)
		print("small_palm_%d tris=%d" % [v, m2.get_meta("tris")])
		_one(m2, Vector3(-8 + v * 2.5, 0.35, -4), v)
	for v in Plants.CLUMP_VARIANTS:
		var m3 := Plants.garden_clump(v)
		print("clump_%d tris=%d" % [v, m3.get_meta("tris")])
		_one(m3, Vector3(-10 + v * 1.4, 0.35, -8.5), v)
	var bed := Plants.garden_bed(4.0, 2.5, 0)
	print("bed tris=%d" % bed.get_meta("tris"))
	_one(bed, Vector3(-4, 0.35, -7.5))
	_one(Plants.garden_bed(3.0, 2.0, 1), Vector3(0.5, 0.35, -8))
	# Seto de 4 tramos sobre el borde de la jardinera.
	var xfs: Array = []
	for i in 6:
		xfs.append(Transform3D(Basis.IDENTITY, Vector3(-10 + i * Plants.HEDGE_SEG, 0.35, -2.4)))
	var h := Plants.hedge(0)
	print("hedge tris=%d" % h.get_meta("tris"))
	_mm(h, xfs)
	_one(Plants.hedge(1, 0.6, 0.7), Vector3(6, 0, 2))
	_one(Plants.hedge(2, 0.6, 0.7), Vector3(8, 0, 2))
	var iv := Plants.ivy_patch(5.0, 2.0)
	print("ivy tris=%d" % iv.get_meta("tris"))
	_one(iv, Vector3(-2, 0, 3), 0.0)
	for v in Plants.GRASS_VARIANTS:
		var gt := Plants.grass_tuft(v)
		print("grass tris=%d" % gt.get_meta("tris"))
		_one(gt, Vector3(2 + v, 0, 4), v)
	for v in Plants.AGAVE_VARIANTS:
		var ag := Plants.agave(v)
		print("agave tris=%d" % ag.get_meta("tris"))
		_one(ag, Vector3(4.5 + v * 1.4, 0, 4.5), v)
	for v in Plants.PIT_VARIANTS:
		var pt := Plants.tree_pit(v)
		print("pit tris=%d" % pt.get_meta("tris"))
		_one(pt, Vector3(-7 + v * 2.0, 0, 5))
	var cam := Camera3D.new()
	cam.far = 3000.0
	cam.fov = 60.0
	add_child(cam)
	match view:
		"near":
			cam.position = Vector3(-1, 1.7, 9.5)
			cam.look_at(Vector3(-2, 0.4, 2))
		"palm":
			cam.position = Vector3(1, 1.6, 8)
			cam.look_at(Vector3(7, 6, -5))
		"hedge":
			cam.position = Vector3(-3, 1.6, 2.5)
			cam.look_at(Vector3(-5, 0.4, -6))
		_:
			cam.position = Vector3(0, 3.0, 16)
			cam.look_at(Vector3(0, 2.5, -4))
	cam.current = true

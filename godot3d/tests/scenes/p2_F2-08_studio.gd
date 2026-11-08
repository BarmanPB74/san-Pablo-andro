extends Node3D
## Estudio de edificios (F2-08). Uso:
##   ... -s res://tests/screenshot.gd -- res://tests/scenes/p2_F2-08_studio.tscn out.png 30 <vista> [preset]
## vista: street | close | aerial | houses | night (night = rainy_night)
## Imita la API de BostonDistrict que usa Buildings (_st, _col_box, place_mesh, _shopfront).

var _batches := {}
var _mm := {}
var _rng := RandomNumberGenerator.new()
var tris := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view: String = args[3] if args.size() > 3 else "street"
	var preset: String = args[4] if args.size() > 4 else ("rainy_night" if view == "night" else "overcast_day")
	var look := StreetLook.new()
	add_child(look)
	look.set_time_of_day(preset)
	_rng.seed = 7
	# piso: calzada + andén
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	ground.material_override = Palette.asphalt()
	ground.position = Vector3(0, -0.15, 0)
	add_child(ground)
	var walk := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(120, 0.15, 2.5)
	walk.mesh = bm
	walk.material_override = Palette.sidewalk()
	walk.position = Vector3(0, -0.075, 1.25)
	add_child(walk)
	# fila de edificios a lo largo de X, fachada hacia +Z en z = 0
	var x := -48.0
	var t0 := Time.get_ticks_msec()
	var specs := [
		["house", 9.0, false], ["house", 11.0, true], ["house", 8.0, false],
		["brick", 12.0, false, 8], ["brick", 14.0, true, 6], ["brick", 13.0, false, 10],
		["stucco", 10.0, false, 5], ["modern", 15.0, true, 6], ["brick", 11.0, false, 7],
	]
	for sp in specs:
		var w: float = sp[1]
		var xf := Transform3D(Basis.IDENTITY, Vector3(x + w * 0.5, 0, 0))
		match String(sp[0]):
			"house": Buildings.house(self, xf, w, 15.0, sp[2], true)
			"brick": Buildings.apartment(self, xf, w, 15.0, sp[2], MatBrick.fachada_variante(int(x)), sp[3], true, true)
			"stucco": Buildings.apartment(self, xf, w, 15.0, sp[2], MatPlaster.stucco_house(5), sp[3], true, false)
			"modern": Buildings.modern(self, xf, w, 15.0, sp[2], sp[3], true)
		x += w
	# copia lejana (LOD plano) detrás
	Buildings.apartment(self, Transform3D(Basis.IDENTITY, Vector3(30, 0, -40)), 12.0, 15.0, false, MatBrick.fachada_variante(1), 8, false, true)
	Buildings.house(self, Transform3D(Basis.IDENTITY, Vector3(18, 0, -40)), 10.0, 15.0, false, false)
	var dt := Time.get_ticks_msec() - t0
	_flush()
	print("STUDIO build ms=", dt, " tris_batches=", tris)
	for k in _mm:
		print("  mm ", k, " n=", _mm[k].xf.size(), " tris/inst=", Buildings._tri_count(_mm[k].mesh))
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 1000.0
	add_child(cam)
	match view:
		"close":
			cam.position = Vector3(-6, 1.7, 6.5)
			cam.look_at(Vector3(-16, 5.0, 0))
		"aerial":
			cam.position = Vector3(10, 30, 40)
			cam.look_at(Vector3(-5, 8, 0))
		"houses":
			cam.position = Vector3(-30, 2.0, 9)
			cam.look_at(Vector3(-40, 4.0, 0))
		"modern":
			cam.position = Vector3(12, 2.0, 12)
			cam.look_at(Vector3(24, 8.0, 0))
		_:
			cam.position = Vector3(8, 1.7, 9)
			cam.look_at(Vector3(-12, 7, 0))
	cam.current = true


func walk_y(_x: float) -> float:
	return 0.0


func _st(mat: Material, _pos: Vector3, shadow: bool) -> SurfaceTool:
	var key := "%d_%d" % [mat.get_instance_id(), int(shadow)]
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"st": st, "mat": mat, "shadow": shadow}
	return _batches[key].st


func _col_box(_xf: Transform3D, _size: Vector3) -> void:
	pass


func place_mesh(key: String, mesh: Mesh, xf: Transform3D, shadow := true) -> void:
	if not _mm.has(key):
		_mm[key] = {"mesh": mesh, "xf": [], "shadow": shadow}
	_mm[key].xf.append(xf)


func _shopfront(xf: Transform3D, w: float, g: float) -> void:
	var st := _st(MatFacade.shopfront(_rng.randi_range(0, 3)), xf.origin, false)
	Buildings.emit_box(st, xf, Vector3(-w * 0.5 + 0.5, 0, 0.0), Vector3(w * 0.5 - 0.5, g - 0.5, 0.05), Buildings.PZ)


func _flush() -> void:
	for key in _batches:
		var bt: Dictionary = _batches[key]
		var mesh: ArrayMesh = bt.st.commit()
		if mesh.get_surface_count() == 0:
			continue
		tris += Buildings._tri_count(mesh)
		mesh.surface_set_material(0, bt.mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bt.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	for k in _mm:
		var d: Dictionary = _mm[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = d.mesh
		mm.instance_count = d.xf.size()
		for i in d.xf.size():
			mm.set_instance_transform(i, d.xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

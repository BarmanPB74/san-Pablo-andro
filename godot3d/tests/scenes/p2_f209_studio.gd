extends Node3D
## Estudio F2-09 (vehículos). Args: ... -- escena salida frames <vista> [preset]
## vistas: row (fila 3/4 frontal), rear (fila 3/4 trasera), close_<kind>, rclose_<kind>, side_<kind>, night

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view: String = args[3] if args.size() > 3 else "row"
	var look := StreetLook.new()
	add_child(look)
	look.set_time_of_day(args[4] if args.size() > 4 else "overcast_day")
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(80, 0.1, 80)
	bm.material = MatAsphalt.asphalt_new()
	g.mesh = bm
	g.position.y = -0.05
	add_child(g)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 0.1, 80)
	cs.shape = bs
	cs.position.y = -0.05
	sb.add_child(cs)
	add_child(sb)
	var kinds := ["taxi", "sedan", "pickup", "buseta"]
	var xs := [7.5, 2.5, -2.8, -9.0]
	var rear := view.begins_with("rear") or view.begins_with("rclose")
	var pos := {}
	for i in 4:
		var yaw := deg_to_rad(-35.0) if rear or true else 0.0
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(xs[i], 0, 0))
		var v := VehicleFactory.spawn(kinds[i], xf, self)
		v.freeze = true   # solo estudio: muestra la altura de diseño (origen = piso)
		v.global_position = xf.origin
		for wi in v.wheel_visuals.size():
			v.wheel_visuals[wi].position.y = v.all_wheels[wi].wheel_radius
		v.set_lights(view == "night" or (args.size() > 4 and args[4] == "rainy_night"))
		pos[kinds[i]] = xs[i]
		var tris := 0
		var mats := {}
		for n in v.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (n as MeshInstance3D).mesh
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				var idx = arr[Mesh.ARRAY_INDEX]
				var vc: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				tris += (idx.size() if idx != null and idx.size() > 0 else vc) / 3
				mats[m.surface_get_material(si)] = true
		print("STATS ", kinds[i], " tris=", tris, " mats=", mats.size(), " body_surfaces=", (v.get_node("Body") as MeshInstance3D).mesh.get_surface_count())
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.current = true
	if view == "row" or view == "night":
		cam.look_at_from_position(Vector3(-0.8, 4.0, -17.0), Vector3(-0.5, 0.9, 0), Vector3.UP)
	elif view == "rear":
		cam.look_at_from_position(Vector3(-0.8, 4.0, 17.0), Vector3(-0.5, 0.9, 0), Vector3.UP)
	else:
		var k := view.split("_")[1]
		var c := Vector3(pos[k], 0, 0)
		var d := 5.2 if k != "buseta" else 8.5
		var off := Vector3(-0.25, 0.25, -1.0).normalized() * d
		if view.begins_with("rclose"):
			off = Vector3(0.45, 0.3, 1.0).normalized() * d
		elif view.begins_with("side"):
			off = Vector3(-1.0, 0.12, -0.15).normalized() * d
		cam.look_at_from_position(c + off, c + Vector3(0, 0.75, 0), Vector3.UP)

extends Node3D
## Estudio F2-01: árboles (Trees). Args de usuario tras la escena/salida/frames: <vista> [kind]
## vista: "far" (fila de todas las variantes), "near" (tronco de cerca), "under" (bajo la copa).

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var view: String = args[3] if args.size() > 3 else "far"
	var look := StreetLook.new()
	add_child(look)
	look.set_time_of_day(args[4] if args.size() > 4 else "overcast_day")
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	floor_mi.mesh = pm
	floor_mi.material_override = MatGround.pasto()
	add_child(floor_mi)
	var tot := 0
	var i := 0
	for kind in [Trees.SAMAN, Trees.ANDEN, Trees.GUAYACAN_AMARILLO, Trees.GUAYACAN_ROSADO]:
		for s in Trees.VARIANTS:
			var t0 := Time.get_ticks_msec()
			var m := Trees.mesh(kind, s)
			print("tree kind=%d seed=%d tris=%d surf=%d ms=%d" % [kind, s, int(m.get_meta("tris")), m.get_surface_count(), Time.get_ticks_msec() - t0])
			var mi := MeshInstance3D.new()
			mi.mesh = m
			add_child(mi)
			mi.position = Vector3(-33 + (i % 6) * 13.0, 0, -6.0 - 16.0 * (i / 6))
			i += 1
	var cam := Camera3D.new()
	cam.far = 3000.0
	cam.fov = 65.0
	add_child(cam)
	match view:
		"near":
			cam.position = Vector3(-30.0, 1.6, -0.5)
			cam.look_at(Vector3(-33, 2.2, -6))
		"under":
			cam.position = Vector3(-27.0, 1.7, 1.0)
			cam.look_at(Vector3(-30, 7.0, -8))
		"flowers":
			cam.position = Vector3(10.0, 2.5, 10.0)
			cam.look_at(Vector3(5, 5.0, -18))
		_:
			cam.position = Vector3(0, 6.0, 26.0)
			cam.look_at(Vector3(0, 5.0, -12))
	cam.current = true

extends SceneTree
## F0: retrato de Andro con el preset "plastilina" real (StreetLook + ClayStyle). Uso:
## godot --path <proyecto> -s <este.gd> -- <vista: face|close|full|side|back> <salida.png>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var view: String = args[0] if args.size() > 0 else "face"
	var out: String = args[1] if args.size() > 1 else "/tmp/shot.png"
	ClayStyle.enabled = true
	var look := StreetLook.new()
	look.enable_backdrop = false
	look.enable_rain = false
	look.enable_post_fx = false
	look.follow_reflection_probe = false
	look.initial_preset = "plastilina"
	root.add_child(look)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = Palette.sidewalk()
	root.add_child(floor_mi)
	var m := PlayerModel.new()
	root.add_child(m)
	var yaw := 0.0
	match view:
		"side": yaw = -PI * 0.5
		"back": yaw = PI
		_: yaw = deg_to_rad(20.0) if view == "face" or view == "close" else 0.0
	m.rotation.y = yaw + PI
	m.snap_pose("idle", 0.0, 0.0)
	root.add_child(ClayStyle.new())
	var cam := Camera3D.new()
	cam.far = 2400.0
	root.add_child(cam)
	match view:
		"face":
			cam.fov = 35.0
			cam.position = Vector3(0, 1.80, 1.5)
			cam.look_at(Vector3(0, 1.78, 0))
		"close":
			cam.fov = 40.0
			cam.position = Vector3(0, 1.1, 3.2)
			cam.look_at(Vector3(0, 0.92, 0))
		_:
			cam.fov = 40.0
			cam.position = Vector3(0, 1.1, 5.0)
			cam.look_at(Vector3(0, 1.0, 0))
	cam.make_current()
	for i in 60:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

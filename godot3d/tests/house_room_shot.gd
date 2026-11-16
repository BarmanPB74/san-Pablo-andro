extends SceneTree
## Captura de un cuarto de La Casa. Uso:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     -s res://tests/house_room_shot.gd -- <cuarto> <salida.png> [game | cam:x,y,z,tx,ty,tz]
## game = cámara del juego con Andro en la puerta de llegada; cam: = cámara libre dentro del cuarto (Andro queda en su puerta).

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var id: String = a[0] if a.size() > 0 else "vestibulo"
	var out: String = a[1] if a.size() > 1 else "/tmp/room.png"
	var view: String = a[2] if a.size() > 2 else "game"
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", "casa")
	root.add_child(main)
	for i in 40:
		await physics_frame
	var stage: Stage = main.get("stage")
	stage.instant = true
	var house := stage.current as HouseScene
	var def: Dictionary = HouseRooms.DEFS[id]
	var arr := HouseRooms.arrival(id, def["doors"][0]["to"])
	if id == HouseRooms.START:
		arr = {"pos": HouseRooms.SPAWN_POS, "yaw": HouseRooms.SPAWN_YAW}
	var p: Node3D = get_nodes_in_group("player")[0]
	p.call("teleport", arr["pos"], arr["yaw"])
	house.load_room(id)
	for i in 40:
		await physics_frame
	var rig: Node3D = get_nodes_in_group("camera_rig")[0]
	rig.call("snap_behind", arr["yaw"], -0.08)
	if view.begins_with("cam:"):
		var v := view.substr(4).split(",")
		var cam := Camera3D.new()
		cam.fov = 75.0
		cam.far = 200.0
		root.add_child(cam)
		cam.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
		cam.look_at(Vector3(float(v[3]), float(v[4]), float(v[5])))
		cam.current = true
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

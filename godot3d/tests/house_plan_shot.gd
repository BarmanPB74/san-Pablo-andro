extends SceneTree
## Vista en planta de La Casa (cámara ortogonal desde arriba que no dibuja el techo ni el tejado) para revisar el plano y el mobiliario.
## Uso: xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##        -s res://tests/house_plan_shot.gd -- <salida.png> [centro_x centro_z tamaño]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp/casa_planta.png"
	var cx := float(a[1]) if a.size() > 1 else 0.0
	var cz := float(a[2]) if a.size() > 2 else 0.0
	var size := float(a[3]) if a.size() > 3 else 27.0
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", "casa")
	root.add_child(main)
	for i in 50:
		await physics_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.cull_mask = 1                          # sin la capa del techo (HouseScene.CEILING_LAYER)
	cam.far = 200.0
	root.add_child(cam)
	cam.global_position = Vector3(cx, 40.0, cz)
	cam.look_at(Vector3(cx, 0.0, cz), Vector3(0, 0, -1))
	cam.current = true
	for i in 25:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

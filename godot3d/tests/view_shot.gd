extends SceneTree
## Captura con cámara libre del juego completo (comparación con fotos de referencia).
## Uso: ... -s res://tests/view_shot.gd -- <preset> <px,py,pz> <tx,ty,tz> <salida.png> [fov]

func _v(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var main: Node = load("res://main.tscn").instantiate()
	main.set("time_of_day", a[0])
	root.add_child(main)
	for i in 20: await physics_frame
	var cam := Camera3D.new()
	cam.far = 2600.0
	cam.fov = float(a[4]) if a.size() > 4 else 70.0
	root.add_child(cam)
	cam.global_position = _v(a[1])
	cam.look_at(_v(a[2]))
	cam.current = true
	for i in 25: await process_frame
	root.get_viewport().get_texture().get_image().save_png(a[3])
	print("SHOT ", a[3])
	quit()

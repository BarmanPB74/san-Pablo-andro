extends SceneTree
## Varias capturas con cámara libre en una sola carga (ahorra el arranque).
## Uso: godot --path . -s res://tests/look_shots.gd -- <preset> <prefijo_salida> "nombre:px,h,pz:tx,h,tz" ...
## Las alturas (h) son sobre el andén (walk_y) de cada punto.

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var preset: String = a[0]
	var prefix: String = a[1]
	var main: Node = load("res://main.tscn").instantiate()
	main.set("time_of_day", preset)
	root.add_child(main)
	for i in 40: await physics_frame
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 900.0
	root.add_child(cam)
	cam.current = true
	for k in range(2, a.size()):
		var parts: PackedStringArray = a[k].split(":")
		var p := _v(parts[1])
		var t := _v(parts[2])
		cam.look_at_from_position(Vector3(p.x, 0.04 * p.x + p.y, p.z), Vector3(t.x, 0.04 * t.x + t.y, t.z))
		for i in 8: await process_frame
		var path := "%s_%s.png" % [prefix, parts[0]]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	quit()

func _v(s: String) -> Vector3:
	var f := s.split(",")
	return Vector3(float(f[0]), float(f[1]), float(f[2]))

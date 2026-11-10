extends SceneTree
## Uso: xvfb-run -a godot --path . --rendering-driver <vulkan|opengl3> -s res://tests/screenshot.gd -- <escena.tscn> <salida.png> [frames=90]
## Carga la escena, espera N frames y guarda la imagen del viewport.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else "res://main.tscn"
	var out: String = args[1] if args.size() > 1 else "/tmp/shot.png"
	var frames: int = int(args[2]) if args.size() > 2 else 90
	var packed: PackedScene = load(scene_path)
	root.add_child(packed.instantiate())
	for i in frames:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("SCREENSHOT_OK ", out)
	quit()

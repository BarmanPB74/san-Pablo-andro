extends SceneTree
## Capturas de F3 en la escena principal: aura de ki (carga), bola de fuego en vuelo y HUD con la barra.
## Uso: SPA_TOUCH=1 xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##        -s res://tests/powers_shot.gd -- <carga|fuego|explosion> <salida.png> [nivel] [escena]

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var mode: String = a[0] if a.size() > 0 else "carga"
	var out: String = a[1] if a.size() > 1 else "/tmp/powers.png"
	var level: int = int(a[2]) if a.size() > 2 else 0
	var scene: String = a[3] if a.size() > 3 else "umbral"
	Progress.save_enabled = false
	Story.save_enabled = false
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", scene)
	root.add_child(main)
	for i in 90:
		await physics_frame
	(main.get("story") as Story).skip()
	for i in 30:
		await physics_frame
	var player: Player = main.get("player")
	var book: SpellBook = main.get("spells")
	var prog: Progress = main.get("progress")
	prog.set_level(level)
	prog.add_points(2 if mode != "carga" else 0)
	book.values["fireball"] = 0.2 if mode == "carga" else 0.5
	match mode:
		"carga":
			Input.action_press("charge")
			for i in 55:
				await physics_frame
				await process_frame
		"fuego":
			Input.action_press("cast")
			await physics_frame
			await physics_frame
			Input.action_release("cast")
			for i in 17:
				await physics_frame
				await process_frame
		"explosion":
			Input.action_press("cast")
			await physics_frame
			await physics_frame
			Input.action_release("cast")
			var f: Fireball = null
			for i in 120:
				await physics_frame
				await process_frame
				if main.get_node_or_null("FireBurst") != null:
					break
			for i in 3:
				await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out, " bar=", book.value("fireball"), " fireballs=", main.get_children().filter(func(n): return n is Fireball).size())
	quit()

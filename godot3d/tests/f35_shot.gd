extends SceneTree
## Capturas de la tanda F3.5. Uso (SPA_TOUCH=1 para ver los botones):
##   -s res://tests/f35_shot.gd -- <portal|pausa|selector|ki|fuego|vuelo> <salida.png> [param] [escena]
## param: portal = etapa 0..2 · pausa = pestaña 0/1 · ki/fuego = rango de mejora 0..10

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var mode: String = a[0] if a.size() > 0 else "portal"
	var out: String = a[1] if a.size() > 1 else "/tmp/f35.png"
	var param: int = int(a[2]) if a.size() > 2 else 0
	var scene: String = a[3] if a.size() > 3 else "umbral"
	Progress.save_enabled = false
	Story.save_enabled = false
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", scene)
	root.add_child(main)
	for i in 90:
		await physics_frame
	var story: Story = main.get("story")
	story.skip()
	for i in 20:
		await physics_frame
	var player: Player = main.get("player")
	var book: SpellBook = main.get("spells")
	var prog: Progress = main.get("progress")
	var stage: Stage = main.get("stage")
	prog.set_level(24)
	match mode:
		"portal":
			story.set_stage(param)
			player.global_position = Vector3(3.2, 0.1, 1.5)
			stage.current.conjure_portal("casa", Vector3(0, 0, -5.5), 0.0, 0.01)
			for i in 150:
				await physics_frame
				await process_frame
		"pausa":
			prog.add_points(3)
			prog.upgrades["fireball"] = 4
			prog.upgrades["ki"] = 6
			(main.get("pause_menu") as PauseMenu).open(param)
			for i in 6:
				await process_frame
		"selector":
			(main.get("strip") as PowerStrip).open()
			for i in 6:
				await process_frame
		"ki":
			prog.upgrades["ki"] = param
			book.values["fireball"] = 0.2
			Input.action_press("charge")
			for i in 55:
				await physics_frame
				await process_frame
		"fuego":
			prog.upgrades["fireball"] = param
			book.values["fireball"] = 0.5
			Input.action_press("cast")
			await physics_frame
			await physics_frame
			Input.action_release("cast")
			for i in 22:
				await physics_frame
				await process_frame
		"vuelo":
			Input.action_press("fly")
			await physics_frame
			Input.action_release("fly")
			Input.action_press("jump")
			Input.action_press("move_forward")
			for i in 100:
				await physics_frame
				await process_frame
			Input.action_release("move_forward")
			for i in 30:
				await physics_frame
				await process_frame
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

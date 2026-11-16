extends SceneTree
## Captura de la rueda de mapas. Uso (con xvfb, ver stage_shot.gd):
##   -s res://tests/wheel_shot.gd -- <escena> <salida.png> <sector resaltado | -1> [bloquear:anillos]
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var scene: String = a[0] if a.size() > 0 else "umbral"
	var out: String = a[1] if a.size() > 1 else "/tmp/wheel.png"
	var hover_i: int = int(a[2]) if a.size() > 2 else -1
	Story.save_enabled = false
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", scene)
	root.add_child(main)
	for i in 60:
		await physics_frame
	var story: Story = main.get("story")
	var wheel: MapWheel = main.get("wheel")
	if a.size() > 3 and a[3].begins_with("bloquear:"):
		story.unlocked.erase(a[3].substr(9))
	story.skip()
	await physics_frame
	wheel.open()
	wheel.hover = hover_i
	for i in 40:
		await process_frame
	wheel.hover = hover_i
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

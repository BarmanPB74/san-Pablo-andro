extends SceneTree
## Captura del remolino de viaje a mitad de camino. Uso: ... -s res://tests/transition_shot.gd -- <cantidad 0..1> <salida.png>
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var amount := float(a[0]) if a.size() > 0 else 0.6
	var out: String = a[1] if a.size() > 1 else "/tmp/transition.png"
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", "casa")
	root.add_child(main)
	for i in 50:
		await physics_frame
	var fx: TransitionFX = main.get("fx")
	fx._set_amount(amount)
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

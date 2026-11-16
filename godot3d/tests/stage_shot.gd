extends SceneTree
## Captura del juego nuevo (main.tscn) en una escena concreta.
## Uso: xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##        -s res://tests/stage_shot.gd -- <escena> <salida.png> <vista> [pasos]
## vistas: follow (cámara del juego) | front (cámara de frente a Andro) | wide (cámara alta y lejana)
## pasos: "adelante:90" mueve hacia adelante N ticks antes de la foto; "tp:x,y,z,yaw" reubica a Andro.

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var scene: String = a[0] if a.size() > 0 else "umbral"
	var out: String = a[1] if a.size() > 1 else "/tmp/stage.png"
	var view: String = a[2] if a.size() > 2 else "follow"
	var steps: String = a[3] if a.size() > 3 else ""
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", scene)
	root.add_child(main)
	for i in 50:
		await physics_frame
	var p: Node3D = get_nodes_in_group("player")[0]
	if steps.begins_with("tp:"):
		var v := steps.substr(3).split(",")
		p.call("teleport", Vector3(float(v[0]), float(v[1]), float(v[2])), float(v[3]))
		for i in 30:
			await physics_frame
	elif steps.begins_with("adelante:"):
		Input.action_press("move_forward")
		for i in int(steps.substr(9)):
			await physics_frame
	if steps.contains("portal"):
		var st: Stage = main.get("stage")
		var f0: float = p.call("get_facing")
		var door := p.global_position + Vector3(-sin(f0), 0, -cos(f0)) * 7.0
		st.current.conjure_portal("casa", door, f0, 0.0)
		for i in 30:
			await physics_frame
	var rig: Node3D = get_nodes_in_group("camera_rig")[0]
	if view == "front" or view == "wide":
		var f: float = p.call("get_facing")
		var fwd := Vector3(-sin(f), 0, -cos(f))
		var cam := Camera3D.new()
		cam.far = 2600.0
		cam.fov = 55.0 if view == "front" else 70.0
		root.add_child(cam)
		if view == "front":
			cam.global_position = p.global_position + fwd * 5.2 + Vector3(0, 1.5, 0)
			cam.look_at(p.global_position + Vector3(0, 1.45, 0))
		else:
			cam.global_position = p.global_position - fwd * 9.0 + Vector3(0, 6.5, 0)
			cam.look_at(p.global_position + fwd * 8.0 + Vector3(0, 1.0, 0))
		cam.current = true
	for i in 25:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT_OK ", out)
	quit()

extends SceneTree
## Prueba headless del juego completo: Umbral → Casa → Umbral → Anillos → Umbral.
## Verifica escenas, portales (ida y vuelta), la rotación de destinos del Umbral y el presupuesto de geometría.
## Uso: godot --headless --fixed-fps 60 --path . -s res://tests/stage_test.gd

var fails := 0
var main: Node
var stage: Stage
var story: Story
var player: Player

const TRI_BUDGET := 120000
const MESH_BUDGET := 220


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func wait_scene(id: String, max_frames := 600) -> bool:
	var t := 0
	while (stage.current_id != id or stage.busy) and t < max_frames:
		await physics_frame
		t += 1
	await frames(30)
	return stage.current_id == id


func press_interact() -> void:
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(3)


func count_geometry(n: Node) -> Vector2i:
	var tris := 0
	var meshes := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		meshes += 1
		var m: Mesh = (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for c in n.get_children():
		var v := count_geometry(c)
		tris += v.x
		meshes += v.y
	return Vector2i(tris, meshes)


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	stage = main.get("stage")
	story = main.get("story")
	stage.instant = true
	check(stage != null and story != null, "el juego arma Stage y Story")
	check(await wait_scene("umbral"), "arranca en El Umbral")
	player = get_nodes_in_group("player")[0]
	check(get_nodes_in_group("vehicle").size() == 0, "no quedan vehículos del mapa viejo")
	check(root.find_child("BostonDistrict", true, false) == null, "el mapa de Boston ya no existe")

	var order := ["umbral", "casa", "umbral", "anillos", "umbral"]
	for i in order.size():
		var id: String = order[i]
		check(stage.current_id == id, "escena actual: %s (%s)" % [id, stage.current.title])
		check(player.is_on_floor(), "  Andro apoyado en el suelo (y=%.2f)" % player.global_position.y)
		check(player.global_position.y > -0.5 and player.global_position.y < 2.5, "  altura sana")
		var geo := count_geometry(stage.current)
		check(geo.x < TRI_BUDGET and geo.y < MESH_BUDGET, "  presupuesto: %d triángulos, %d mallas" % [geo.x, geo.y])
		check(stage.current.env != null and stage.current.sun != null, "  tiene ambiente y luz propios")
		check(stage.get_child_count() == 1, "  solo una escena viva")

		story.skip()
		check(story.can_conjure, "  ya se puede conjurar la puerta")
		if i == order.size() - 1:
			break
		var target := story.next_target()
		check(target == order[i + 1], "  la puerta lleva a %s" % order[i + 1])
		await press_interact()
		check(stage.current.portals.size() == 1, "  PUERTA conjura un portal")
		var portal: Portal = stage.current.portals[0]
		check(portal.target == target, "  el portal lleva a %s" % target)
		check(portal.size == stage.current.portal_size, "  el portal tiene el tamaño de la escena")
		if id == "casa":
			check(portal.global_position.y + portal.size.y + 1.0 < HouseScene.H, "  el portal cabe bajo el techo")
			check(absf(portal.global_position.x) < 11.0 and absf(portal.global_position.z) < 7.0, "  el portal queda dentro de la casa")
		var t := 0
		while not portal.monitoring and t < 400:
			await physics_frame
			t += 1
		check(portal.is_open and portal.monitoring, "  el portal termina de abrirse")
		# cruzar el portal
		player.call("teleport", portal.global_position + Vector3(0, 0.1, 0), 0.0)
		var ok := await wait_scene(target)
		check(ok, "  cruzar el portal viaja a %s" % target)
		if not ok:
			break

	# modo libre: desde el Umbral la puerta rota por los mapas; ya no hay dimensiones sueltas
	check(story.chapter >= Story.CHAPTERS.size(), "historia en modo libre")
	check(not stage.has_scene("planetas") and not stage.has_scene("fuente") and not stage.has_scene("cubo"), "las dimensiones viejas ya no existen")
	await press_interact()
	check(stage.current.portals.size() == 1 and (stage.current.portals[0] as Portal).target == "casa", "en modo libre la rotación vuelve a la casa")

	# movimiento: Andro avanza y la capa se arrastra
	var p0 := player.global_position
	Input.action_press("move_forward")
	await frames(90)
	Input.action_release("move_forward")
	check(player.global_position.distance_to(p0) > 3.0, "Andro se desplaza por el escenario (%.1f m)" % player.global_position.distance_to(p0))

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(fails)

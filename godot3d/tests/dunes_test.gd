extends SceneTree
## Prueba headless de la fase 4 (dimensión 1: Las Dunas Blancas): terreno caminable, pendientes, presupuesto, límites,
## vuelo, portal de ida y vuelta y entrada desde la rueda de mapas.
## Uso: godot --headless --fixed-fps 60 --path . -s res://tests/dunes_test.gd

var fails := 0
var stage: Stage
var story: Story
var player: Player


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func wait_scene(id: String) -> bool:
	var t := 0
	while (stage.current_id != id or stage.busy) and t < 900:
		await physics_frame
		t += 1
	await frames(20)
	return stage.current_id == id


func count_tris(n: Node) -> Vector2i:
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
	elif n is MultiMeshInstance3D:
		meshes += 1
		tris += (n as MultiMeshInstance3D).multimesh.instance_count * 2
	for c in n.get_children():
		var v := count_tris(c)
		tris += v.x
		meshes += v.y
	return Vector2i(tris, meshes)


func _initialize() -> void:
	Progress.save_enabled = false
	Story.save_enabled = false
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	stage = main.get("stage")
	story = main.get("story")
	player = main.get("player")
	stage.instant = true
	await wait_scene("umbral")
	story.skip()

	# --- catálogo y rueda
	check(stage.has_scene("dunas"), "Stage conoce la escena 'dunas'")
	check(MapCatalog.index_of("dunas") == 3, "ocupa el sector 4 de la rueda (índice %d)" % MapCatalog.index_of("dunas"))
	check(story.is_unlocked("dunas") and story.travel_block_reason("dunas") == "", "está abierta y se puede viajar")
	check(Story.MAPS.has("dunas"), "entra en la rotación de PUERTA")

	# --- forma del terreno (solo matemática)
	var max_slope := 0.0
	var max_h := -99.0
	var min_h := 99.0
	var step := 1.5
	for ix in range(-30, 31):
		for iz in range(-30, 31):
			var x := float(ix) * step
			var z := float(iz) * step
			if Vector2(x, z).length() > 40.0:
				continue                        # más allá del muro invisible no se camina
			var h := DunesScene.height(x, z)
			max_h = maxf(max_h, h)
			min_h = minf(min_h, h)
			var gx := (DunesScene.height(x + step, z) - h) / step
			var gz := (DunesScene.height(x, z + step) - h) / step
			max_slope = maxf(max_slope, Vector2(gx, gz).length())
	check(max_slope < 0.62, "pendiente máxima caminable (%.2f ≈ %.0f°)" % [max_slope, rad_to_deg(atan(max_slope))])
	check(max_h - min_h > 4.0, "hay dunas de verdad (desnivel %.1f m)" % (max_h - min_h))
	check(absf(DunesScene.height(0, 4)) < 0.05 and absf(DunesScene.height(5, -3)) < 0.05, "el valle de aparición es plano")

	# --- viajar con la rueda lógica (como lo hace el mapa)
	stage.go("dunas")
	check(await wait_scene("dunas"), "se viaja a Las Dunas Blancas")
	var sc := stage.current as DunesScene
	check(sc != null and sc.title == "Las Dunas Blancas", "título de la escena")
	check(sc.env != null and sc.sun != null, "tiene ambiente y luz propios")
	check(sc.find_child("Terreno", true, false) != null and sc.find_child("Luna", true, false) != null, "hay terreno y luna")
	var lights := 0
	for n in sc.find_children("*", "Light3D", true, false):
		lights += 1
	check(lights <= 2, "pocas luces (%d)" % lights)
	var geo := count_tris(sc)
	check(geo.x < 40000 and geo.y < 80, "presupuesto liviano: %d triángulos, %d mallas" % [geo.x, geo.y])
	check(player.is_on_floor(), "Andro aparece apoyado (y = %.2f)" % player.global_position.y)
	check(absf(float(player.fly_ceiling) - 60.0) < 0.01, "techo de vuelo 60 m")

	# --- caminar en varias direcciones: nunca se cae del mundo ni atraviesa el terreno
	var dirs := [0.0, 1.57, 3.14, 4.71]
	var worst_below := 0.0
	var worst_dist := 0.0
	for d in dirs:
		player.call("teleport", Vector3(0, 0.1, 4.0), d)
		await frames(10)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		for i in 360:
			await physics_frame
			var gy := DunesScene.height(player.global_position.x, player.global_position.z)
			worst_below = minf(worst_below, player.global_position.y - gy)
			worst_dist = maxf(worst_dist, Vector2(player.global_position.x, player.global_position.z).length())
		Input.action_release("move_forward")
		Input.action_release("sprint")
	check(worst_below > -0.4, "nunca atraviesa la arena (peor %.2f m)" % worst_below)
	check(worst_dist > 25.0 and worst_dist < 46.0, "recorre el desierto y el muro lo contiene (%.1f m)" % worst_dist)

	# --- vuelo libre sobre las dunas
	player.call("teleport", Vector3(0, 0.1, 4.0), 0.0)
	await frames(10)
	player.set_flying(true)
	Input.action_press("jump")
	await frames(180)
	Input.action_release("jump")
	check(player.global_position.y > 8.0 and player.global_position.y <= 60.05, "se puede volar alto (y = %.1f)" % player.global_position.y)
	player.set_flying(false)

	# --- portal de vuelta al Umbral
	player.call("teleport", Vector3(0, 0.1, 4.0), 0.0)
	await frames(20)
	check(story.next_target() == "umbral", "PUERTA en las dunas vuelve al Umbral")
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await frames(3)
	check(stage.current.portals.size() == 1, "PUERTA conjura un portal")
	var portal: Portal = stage.current.portals[0]
	var t := 0
	while not portal.monitoring and t < 400:
		await physics_frame
		t += 1
	check(portal.is_open, "el portal se abre sobre la arena (y = %.2f)" % portal.global_position.y)
	player.call("teleport", portal.global_position + Vector3(0, 0.1, 0), 0.0)
	check(await wait_scene("umbral"), "cruzar el portal vuelve al Umbral")

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)

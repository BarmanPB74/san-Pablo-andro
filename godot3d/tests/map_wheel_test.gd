extends SceneTree
## Prueba de la rueda circular de mapas (fase 2): geometría de los sectores, apertura/cierre (cámara lenta y Andro quieto),
## elegir por toque, ratón y teclado, mapas bloqueados o inexistentes, viaje directo entre mapas (sin pasar por el Umbral),
## desbloqueo y rotación de PUERTA que salta los mapas cerrados.
## Uso: godot --headless --fixed-fps 60 --path . -s res://tests/map_wheel_test.gd

var fails := 0
var stage: Stage
var story: Story
var wheel: MapWheel
var player: Node3D
var inputs: Node


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## Toque en coordenadas del juego (parse_input_event espera coordenadas de ventana: se compensa el escalado del stretch).
func tap(pos: Vector2) -> void:
	pos = root.get_final_transform() * pos
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = pos
	down.pressed = true
	Input.parse_input_event(down)
	await frames(2)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = pos
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func key(k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	wheel._input(e)


func portal_target() -> String:
	var ps: Array = stage.current.portals
	return (ps[0] as Portal).target if ps.size() == 1 else ""


func cross_portal() -> void:
	var p: Portal = stage.current.portals[0]
	p.entered.emit(p)
	await frames(8)


func _initialize() -> void:
	inputs = root.get_node("Inputs")
	Story.save_enabled = false              # la prueba no toca la partida guardada
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", "umbral")
	root.add_child(main)
	await frames(60)
	stage = main.get("stage")
	story = main.get("story")
	wheel = main.get("wheel")
	player = get_nodes_in_group("player")[0]
	stage.instant = true
	story.skip()
	await frames(5)

	# --- geometría
	check(wheel != null and MapCatalog.count() == 6, "la rueda existe y tiene %d sectores" % MapCatalog.count())
	var geo_ok := true
	for i in MapCatalog.count():
		if wheel.slot_at(wheel.slot_pos(i)) != i:
			geo_ok = false
	check(geo_ok, "tocar el centro de cada sector lo identifica")
	check(wheel.slot_at(wheel.wheel_center()) == -1, "el centro de la rueda no es un sector")
	check(wheel.slot_at(wheel.wheel_center() + Vector2(0, -wheel.r_out() - 40)) == -1, "fuera del aro no es un sector")
	check(wheel.slot_at(wheel.wheel_center() + Vector2(0, -wheel.r_in() - 20)) == 0, "el sector 0 queda arriba")
	check(wheel.slot_at(wheel.wheel_center() + Vector2(wheel.r_in() + 20, 0)) == 1 or wheel.slot_at(wheel.wheel_center() + Vector2(wheel.r_in() + 20, 0)) == 2,
		"los sectores avanzan en sentido horario")
	check(MapCatalog.index_of("casa") == 1 and MapCatalog.index_of("nada") == -1, "el catálogo ubica los mapas por id")

	# --- abrir y cerrar
	check(not wheel.is_open and Engine.time_scale == 1.0 and not UiLock.blocked, "empieza cerrada")
	wheel.open()
	check(wheel.is_open and UiLock.blocked and Engine.time_scale < 0.5, "al abrir: cámara lenta y entrada bloqueada")
	Input.action_press("move_forward")
	check(inputs.move_vector() == Vector2.ZERO, "abierta, Andro no recibe movimiento")
	Input.action_release("move_forward")
	wheel.close()
	check(not wheel.is_open and Engine.time_scale == 1.0 and not UiLock.blocked, "al cerrar se restaura el tiempo y la entrada")
	story.can_conjure = false
	wheel.open()
	check(not wheel.is_open, "no abre mientras la historia no da la puerta")
	story.can_conjure = true

	# --- sectores no elegibles
	wheel.open()
	check(not wheel.choose(4) and wheel.is_open, "un sector sin dimensión no deja viajar y la rueda sigue abierta")
	check(story.travel_block_reason("dim5") == "Aún no existe esta dimensión.", "  motivo: aún no existe")
	check(not wheel.choose(0) and story.travel_block_reason("umbral") == "Ya estás aquí.", "el mapa actual no es destino ('Ya estás aquí.')")
	story.unlocked.erase("anillos")
	check(not wheel.choose(2) and story.travel_block_reason("anillos") == "Aún no. Hay que pasar la historia.", "un mapa sin desbloquear sale con candado")
	story.unlock_map("anillos")
	check(story.is_unlocked("anillos"), "unlock_map lo abre")

	# --- elegir por toque: Umbral → Casa
	await tap(wheel.slot_pos(1))
	check(not wheel.is_open and Engine.time_scale == 1.0, "tocar un sector cierra la rueda")
	check(portal_target() == "casa", "el toque conjura un portal hacia la Casa")
	await cross_portal()
	check(stage.current_id == "casa", "el portal lleva a la Casa (%s)" % stage.current_id)

	# --- viaje directo Casa → Anillos (sin pasar por el Umbral), con ratón
	story.skip()
	await frames(5)
	wheel.open()
	check(wheel.is_open, "se abre también dentro de la Casa")
	wheel.press(wheel.slot_pos(2))
	check(wheel.hover == 2, "presionar resalta el sector")
	wheel.release(wheel.slot_pos(2))
	check(portal_target() == "anillos", "desde la Casa se conjura el portal a los Anillos, no al Umbral")
	# reemplazo: elegir otro destino cambia el portal
	wheel.open()
	wheel.press(wheel.slot_pos(0))
	wheel.release(wheel.slot_pos(0))
	check(portal_target() == "umbral", "elegir de nuevo reemplaza el portal (uno solo)")
	await cross_portal()
	check(stage.current_id == "umbral", "y lleva al Umbral")

	# --- teclado
	story.skip()
	await frames(5)
	wheel.open()
	key(KEY_RIGHT)
	check(wheel.hover == 0, "→ empieza en el primer sector")
	key(KEY_RIGHT)
	check(wheel.hover == 1, "→ avanza")
	key(KEY_LEFT)
	key(KEY_LEFT)
	check(wheel.hover == 5, "← retrocede con vuelta")
	key(KEY_ESCAPE)
	check(not wheel.is_open, "Esc cierra")
	wheel.open()
	key(KEY_RIGHT)
	key(KEY_RIGHT)
	key(KEY_ENTER)
	check(portal_target() == "casa" and not wheel.is_open, "Enter elige el sector resaltado")
	await cross_portal()
	check(stage.current_id == "casa", "Enter viajó a la Casa")

	# --- soltar en el centro cierra
	story.skip()
	await frames(5)
	wheel.open()
	wheel.press(wheel.wheel_center())
	wheel.release(wheel.wheel_center())
	check(not wheel.is_open, "tocar el centro cierra")
	check(story.next_target() == "umbral", "PUERTA dentro de un mapa sigue volviendo al Umbral")

	# --- PUERTA desde el Umbral salta los mapas cerrados
	await story.stage.go("umbral")
	await frames(5)
	story.skip()
	story.unlocked.erase("casa")
	check(story.next_target() == "anillos", "PUERTA desde el Umbral salta los mapas cerrados (%s)" % story.next_target())
	story.unlock_map("casa")
	var seen_casa := false
	for i in 4:
		story.free_index = i
		if story.next_target() == "casa":
			seen_casa = true
	check(seen_casa, "con la Casa abierta vuelve a entrar en la rotación")

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(fails)

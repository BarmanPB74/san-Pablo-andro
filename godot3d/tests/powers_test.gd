extends SceneTree
## Prueba headless de F3: nivel y puntos (Progress), barra de magia (SpellBook), runas por nivel (AndroCloak),
## bola de fuego (Fireball) y el flujo completo en la escena principal (cargar, lanzar, mejorar).
## Uso: godot --headless --fixed-fps 60 --path . -s res://tests/powers_test.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func _initialize() -> void:
	Progress.save_enabled = false
	Story.save_enabled = false
	_test_progress()
	_test_book()
	await _test_cloak_level()
	await _test_fireball()
	await _test_game_flow()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _test_progress() -> void:
	print("-- Progress")
	var p := Progress.new()
	check(p.level == 0 and p.points == 0, "empieza en nivel 0 sin puntos")
	check(Progress.MAX_LEVEL == 33 and AndroCloak.MAX_LEVEL == 33, "los niveles van de 0 a 33")
	p.add_xp(Progress.xp_needed(0) - 1)
	check(p.level == 0, "con un punto de experiencia menos no sube")
	p.add_xp(1)
	check(p.level == 1 and p.points == 1, "al completar la experiencia sube a 1 y da 1 punto")
	p.add_xp(100000)
	check(p.level == 33, "nunca pasa del nivel 33 (nivel %d)" % p.level)
	check(p.points == 33, "33 niveles ganados = 33 puntos (%d)" % p.points)
	p.add_xp(10)
	check(p.level == 33 and p.xp == 0, "en el nivel máximo la experiencia no cambia nada")
	p.set_level(12)
	check(p.level == 12 and p.points == 33, "set_level fija el nivel sin dar puntos")
	check(p.spend_point("fireball") and p.points == 32 and p.upgrade_count("fireball") == 1, "gastar un punto sube la mejora")
	var q := Progress.new()
	check(not q.spend_point("fireball"), "sin puntos no se puede mejorar")
	p.free()
	q.free()


func _test_book() -> void:
	print("-- SpellBook")
	var p := Progress.new()
	var b := SpellBook.new()
	b.setup(p)
	check(absf(b.cap("fireball") - 0.5) < 0.001, "el tope inicial es 50 %")
	check(absf(b.value("fireball") - 0.5) < 0.001, "empieza llena hasta el tope")
	var casts := 0
	for i in 12:
		if b.try_cast("fireball"):
			casts += 1
		b._process(0.4)         # pasa el enfriamiento pero apenas recarga
		b.values["fireball"] = maxf(0.0, b.value("fireball") - b.REGEN_RATE * 0.4)   # descuenta lo recargado
	check(casts == 5, "con 50 %% y costo 10 %% salen 5 bolas seguidas (salieron %d)" % casts)
	check(p.xp > 0 or p.level > 0, "lanzar da experiencia")
	check(p.points == p.level and p.level >= 1, "lanzar 5 bolas dio experiencia suficiente para el nivel 1 y su punto")
	p.points = 0
	check(not b.can_upgrade("fireball"), "sin puntos no se puede subir el tope")
	# recarga sola vs. cargando
	b.values["fireball"] = 0.0
	b.charging = false
	for i in 60:
		b._process(1.0 / 60.0)
	var solo: float = b.value("fireball")
	b.values["fireball"] = 0.0
	b.charging = true
	for i in 60:
		b._process(1.0 / 60.0)
	var cargando: float = b.value("fireball")
	check(absf(solo - SpellBook.REGEN_RATE) < 0.01, "se recarga sola: %.0f %% en 1 s" % (solo * 100.0))
	check(cargando > solo * 3.0, "cargando ki es más de 3 veces más rápido (%.0f %% en 1 s)" % (cargando * 100.0))
	check(cargando <= b.cap("fireball") + 0.0001, "nunca pasa del tope")
	b.charging = true
	for i in 120:
		b._process(1.0 / 60.0)
	check(absf(b.value("fireball") - 0.5) < 0.001, "llena el tope (50 %) en menos de 3 s")
	# mejoras
	p.add_points(3)
	check(b.upgrade("fireball") and absf(b.cap("fireball") - 0.55) < 0.001, "una mejora sube el tope a 55 %")
	b.upgrade("fireball")
	b.upgrade("fireball")
	check(absf(b.cap("fireball") - 0.65) < 0.001 and p.points == 0, "tres mejoras = 65 % y sin puntos")
	p.add_points(20)
	for i in 20:
		b.upgrade("fireball")
	check(absf(b.cap("fireball") - 1.0) < 0.001, "el tope máximo es 100 %")
	check(not b.can_upgrade("fireball"), "no se puede mejorar más allá del máximo")
	b.free()
	p.free()


func _test_cloak_level() -> void:
	print("-- Runas por nivel")
	var m := AndroCloak.new()
	root.add_child(m)
	await process_frame
	var mat: ShaderMaterial = (m.get_node("Body/Cloak") as MeshInstance3D).material_override
	check(mat.get_shader_parameter("rune_level") == 0.0, "nivel 0: runas apagadas")
	m.level = 16
	check(mat.get_shader_parameter("rune_level") == 16.0, "nivel 16 llega al shader")
	m.level = 99
	check(m.level == 33 and mat.get_shader_parameter("rune_level") == 33.0, "el nivel se limita a 33")
	m.level = -4
	check(m.level == 0, "y no baja de 0")
	var src := FileAccess.get_file_as_string("res://character/shaders/cloak.gdshader")
	check(src.contains("32554047") and src.contains("18667121"), "el shader lleva los glifos de EISEN-KERN")
	m.charge = 0.8
	m.animate("idle", 0.0, 0.016)
	check(absf(float(mat.get_shader_parameter("charge")) - 0.8) < 0.2, "la carga enciende la tela")
	# esfera elegida
	var i := m.orb_toward(Vector3(0, 0, -1))
	check(i >= 0 and i < 5, "orb_toward devuelve una esfera válida (%d)" % i)
	m.flash_orb(i)
	m.animate("idle", 0.0, 0.016)
	check(m.orb_global_position(i).distance_to(m.global_position) > 0.7, "la esfera queda fuera del campo de fuerza")
	m.queue_free()


func _test_fireball() -> void:
	print("-- Fireball")
	var world := Node3D.new()
	root.add_child(world)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 4, 0.5)
	cs.shape = box
	wall.add_child(cs)
	wall.position = Vector3(0, 2, -10)
	world.add_child(wall)
	var crate := RigidBody3D.new()
	crate.collision_layer = 1 << 3
	crate.gravity_scale = 0.0
	var ccs := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1, 1, 1)
	ccs.shape = cbox
	crate.add_child(ccs)
	crate.position = Vector3(3, 2, -5)
	world.add_child(crate)
	await physics_frame
	var ball := Fireball.launch(world, Vector3(0, 2, 0), Vector3(0, 0, -1))
	var hits := []
	var burst_seen := []
	ball.exploded.connect(func(at: Vector3, c: Object) -> void:
		hits.append([at, c])
		burst_seen.append(world.get_node_or_null("FireBurst") != null))
	for i in 120:
		await physics_frame
	check(hits.size() == 1, "la bola explota una sola vez")
	if hits.size() == 1:
		check(hits[0][1] == wall, "choca con la pared")
		check(absf((hits[0][0] as Vector3).z + 9.75) < 0.4, "explota en la cara de la pared (z = %.2f)" % (hits[0][0] as Vector3).z)
	check(not is_instance_valid(ball), "la bola se borra al explotar")
	check(burst_seen == [true], "al explotar aparece la explosión de chispas")
	var ball2 := Fireball.launch(world, Vector3(3, 2, 0), Vector3(0, 0, -1))
	for i in 24:
		await physics_frame
	check(crate.linear_velocity.z < -1.0, "empuja los objetos físicos (vz = %.1f)" % crate.linear_velocity.z)
	check(not is_instance_valid(ball2), "la segunda bola también explotó")
	var ball3 := Fireball.launch(world, Vector3(0, 6, 0), Vector3(0, 1, 0))
	for i in int(Fireball.LIFE * 60.0) + 10:
		await physics_frame
	check(not is_instance_valid(ball3), "si no choca con nada se apaga sola tras %.1f s" % Fireball.LIFE)
	world.queue_free()


func _test_game_flow() -> void:
	print("-- Escena principal")
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", "umbral")
	root.add_child(main)
	for i in 90:
		await physics_frame
	var player: Player = main.get("player")
	var book: SpellBook = main.get("spells")
	var prog: Progress = main.get("progress")
	var caster: PowerCaster = main.get("caster")
	check(book != null and prog != null and caster != null, "Game crea Progress, SpellBook y PowerCaster")
	if caster == null:
		return
	(main.get("story") as Story).skip()
	await physics_frame

	check(InputMap.has_action("cast") and InputMap.has_action("charge") and InputMap.has_action("fly") and InputMap.has_action("pause"), "las acciones cast, charge, fly y pause existen")
	check(player.model.level == prog.level, "el nivel de Andro viene de Progress")
	# lanzar
	book.values["fireball"] = 0.5
	var before: float = book.value("fireball")
	Input.action_press("cast")
	await physics_frame
	await physics_frame
	Input.action_release("cast")
	check(book.value("fireball") < before - 0.05, "lanzar gasta la barra (%.0f %% → %.0f %%)" % [before * 100.0, book.value("fireball") * 100.0])
	var found := false
	for i in 30:
		await physics_frame
		if main.get_node_or_null("Fireball") != null:
			found = true
	check(found, "la bola de fuego aparece en la escena tras el adelantón de la esfera")
	# cargar
	book.values["fireball"] = 0.0
	Input.action_press("charge")
	for i in 40:
		await physics_frame
		await process_frame
	check(caster.charging and player.charging, "mantener cargar activa la carga y deja a Andro quieto")
	check(caster.aura.visible and caster.aura.power > 0.3, "la aura de ki se enciende (%.2f)" % caster.aura.power)
	check(player.model.charge > 0.2, "la tela y las esferas se encienden (%.2f)" % player.model.charge)
	check(book.value("fireball") > 0.3, "la barra sube rápido cargando (%.0f %%)" % (book.value("fireball") * 100.0))
	Input.action_release("charge")
	for i in 90:
		await physics_frame
		await process_frame
	check(not caster.charging and caster.aura.power < 0.05, "al soltar la aura se apaga")
	# mejora con puntos desde la tecla
	prog.add_points(1)
	var cap0 := book.cap("fireball")
	check(book.upgrade("fireball") and book.cap("fireball") > cap0 + 0.04, "mejorar la bola de fuego sube el tope a %.0f %%" % (book.cap("fireball") * 100.0))
	# sube de nivel y se ven las runas
	prog.set_level(20)
	check(player.model.level == 20, "al subir de nivel cambian las runas de la capa")
	# con la rueda abierta no se lanza nada
	UiLock.blocked = true
	book.values["fireball"] = 0.5
	Input.action_press("cast")
	await physics_frame
	await physics_frame
	Input.action_release("cast")
	check(absf(book.value("fireball") - 0.55) < 0.06 or book.value("fireball") >= 0.5, "con la rueda abierta no se lanza")
	UiLock.blocked = false

	main.queue_free()

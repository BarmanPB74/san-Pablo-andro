extends SceneTree
## Prueba headless de la tanda F3.5: vuelo libre y techo, botones táctiles sin solaparse, etapas de color de ki y fuego,
## panel de pausa con mejoras, selector de poderes, vida y portales por etapa de la historia.
## Uso: godot --headless --fixed-fps 60 --path . -s res://tests/flight_pause_test.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


class Dummy extends StaticBody3D:
	var taken := 0.0

	func take_damage(a: float) -> void:
		taken += a


func _initialize() -> void:
	Progress.save_enabled = false
	Story.save_enabled = false
	_test_abilities()
	_test_vitals()
	await _test_fireball_ranks()
	await _test_game()
	await _test_portals()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _test_abilities() -> void:
	print("-- Habilidades y etapas")
	var ki_names := []
	var fb_names := []
	for t in 5:
		ki_names.append(Abilities.tier("ki", t * 2).name)
		fb_names.append(Abilities.tier("fireball", t * 2).name)
	check(ki_names == ["Blanco", "Amarillo", "Rojo", "Morado", "Morado y negro"], "el ki pasa por blanco, amarillo, rojo, morado y morado con negro")
	check(fb_names == ["Naranja", "Roja", "Azul", "Morada", "Morada y negra"], "la bola pasa por naranja, roja, azul, morada y morada con negra")
	check(Abilities.tier("ki", 0).core == Color(1, 1, 1), "el ki empieza blanco")
	check(Abilities.tier("ki", 10).get("dark", false) and Abilities.tier("fireball", 10).get("dark", false), "la última etapa de ambos lleva negro")
	check(Abilities.tier_of_rank(1) == 0 and Abilities.tier_of_rank(2) == 1 and Abilities.tier_of_rank(99) == 4, "el color cambia cada 2 rangos y se detiene en la 5ª etapa")
	check(Abilities.fireball_damage(10) > Abilities.fireball_damage(0) * 2.5, "más rango = bastante más daño (%d → %d)" % [Abilities.fireball_damage(0), Abilities.fireball_damage(10)])
	check(Abilities.fireball_radius(10) > Abilities.fireball_radius(0) * 2.0, "y una explosión más grande")
	check(absf(Abilities.fireball_cap(0) - 0.5) < 0.001 and absf(Abilities.fireball_cap(10) - 1.0) < 0.001, "el tope de magia va de 50 % a 100 %")
	var p := Progress.new()
	var b := SpellBook.new()
	b.setup(p)
	p.add_points(3)
	var rate0 := b.charge_rate()
	check(b.upgrade("ki") and b.rank("ki") == 1 and p.points == 2, "mejorar el ki cuesta 1 punto")
	check(b.charge_rate() > rate0 * 1.15, "y carga más rápido (%.2f → %.2f)" % [rate0, b.charge_rate()])
	p.add_points(20)
	for i in 20:
		b.upgrade("ki")
	check(b.rank("ki") == Abilities.MAX_RANK and not b.can_upgrade("ki"), "el ki llega al rango máximo y no pasa")
	b.free()
	p.free()


func _test_vitals() -> void:
	print("-- Vida")
	var v := Vitals.new()
	var died := []
	v.died.connect(func() -> void: died.append(1))
	check(v.hp == 100.0 and v.fraction() == 1.0, "empieza con la vida llena")
	v.take_damage(30.0)
	check(absf(v.hp - 70.0) < 0.01, "el daño la baja (%d)" % int(v.hp))
	v._process(2.0)
	check(v.hp == 70.0, "no se regenera justo después del golpe")
	v._process(5.0)
	v._process(2.0)
	check(v.hp > 70.0, "pasados unos segundos se regenera sola (%.0f)" % v.hp)
	v.take_damage(500.0)
	check(v.hp == 0.0 and died.size() == 1, "al llegar a 0 avisa que murió")
	v.heal(40.0)
	check(v.hp == 40.0, "curar sube la vida")
	v.free()


func _test_fireball_ranks() -> void:
	print("-- Bola de fuego por rango")
	var world := Node3D.new()
	root.add_child(world)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 6, 0.5)
	cs.shape = box
	wall.add_child(cs)
	wall.position = Vector3(0, 3, -10)
	world.add_child(wall)
	await physics_frame
	var results := {}
	for rk in [0, 10]:
		# un blanco a 2 m de la pared (solo lo alcanza una explosión grande) y una caja suelta
		var dummy := Dummy.new()
		dummy.collision_layer = 1 << 3
		var dcs := CollisionShape3D.new()
		var dbox := BoxShape3D.new()
		dbox.size = Vector3(1, 1, 1)
		dcs.shape = dbox
		dummy.add_child(dcs)
		dummy.position = Vector3(0, 1.0, -7.4 if rk == 0 else -7.4)
		world.add_child(dummy)
		await physics_frame
		var ball := Fireball.launch(world, Vector3(2.5, 1.0, 0), Vector3(0, 0, -1), rk)
		check(ball.rank == rk and ball.tier.name == ("Naranja" if rk == 0 else "Morada y negra"), "rango %d: bola %s" % [rk, ball.tier.name])
		for i in 90:
			await physics_frame
		results[rk] = dummy.taken
		dummy.queue_free()
		await physics_frame
	check(float(results[0]) == 0.0, "rango 0: la explosión chica no alcanza al blanco lejano")
	check(float(results[10]) > 0.0, "rango 10: la explosión grande sí lo alcanza y le hace daño (%d)" % int(results[10]))
	# daño directo
	var dummy2 := Dummy.new()
	dummy2.collision_layer = 1 << 3
	var d2 := CollisionShape3D.new()
	var b2 := BoxShape3D.new()
	b2.size = Vector3(1, 2, 1)
	d2.shape = b2
	dummy2.add_child(d2)
	dummy2.position = Vector3(0, 1, -5)
	world.add_child(dummy2)
	await physics_frame
	Fireball.launch(world, Vector3(0, 1, 0), Vector3(0, 0, -1), 0)
	for i in 60:
		await physics_frame
	check(absf(dummy2.taken - Abilities.fireball_damage(0)) < 0.5, "el golpe directo hace el daño completo (%d)" % int(dummy2.taken))
	world.queue_free()


func _test_game() -> void:
	print("-- Escena principal: vuelo, botones, paneles")
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", "umbral")
	root.add_child(main)
	for i in 90:
		await physics_frame
	(main.get("story") as Story).skip()
	var player: Player = main.get("player")
	var book: SpellBook = main.get("spells")
	var prog: Progress = main.get("progress")
	var caster: PowerCaster = main.get("caster")
	var touch: TouchControls = main.get("touch")
	var pause: PauseMenu = main.get("pause_menu")
	var strip: PowerStrip = main.get("strip")
	var stage: Stage = main.get("stage")
	var story: Story = main.get("story")
	await physics_frame

	# --- botones sin solaparse y dentro de la pantalla
	var vp := touch.get_viewport().get_visible_rect().size
	var bs: Array = touch._buttons
	var overlap := ""
	var outside := ""
	for i in bs.size():
		var a: Dictionary = bs[i]
		if a.center.x - a.radius < 0.0 or a.center.y - a.radius < 0.0 or a.center.x + a.radius > vp.x or a.center.y + a.radius > vp.y:
			outside += "%s " % a.action
		for j in range(i + 1, bs.size()):
			var c: Dictionary = bs[j]
			if (a.center as Vector2).distance_to(c.center) < float(a.radius) + float(c.radius) - 0.5:
				overlap += "%s/%s " % [a.action, c.action]
	check(overlap == "", "ningún botón táctil se solapa con otro (%s)" % overlap)
	check(outside == "", "todos caben en la pantalla (%s)" % outside)
	var actions := bs.map(func(b): return b.action)
	for a in ["jump", "crouch", "fly", "cast", "charge", "sprint", "punch", "interact", "pause", "power_panel", "map_wheel"]:
		check(actions.has(a), "hay botón para %s" % a)

	# --- vuelo en el Umbral
	var ceiling := (stage.current as StageScene).fly_ceiling
	check(absf(ceiling - 5.6) < 0.01, "techo del Umbral = altura del portal (%.1f m)" % ceiling)
	check(not player.flying, "empieza caminando")
	Input.action_press("fly")
	await physics_frame
	Input.action_release("fly")
	await physics_frame
	check(player.flying and player.state == "fly", "el botón VOLAR enciende el vuelo")
	check(touch.flying, "los botones cambian a SUBIR/BAJAR")
	Input.action_press("jump")
	for i in 120:
		await physics_frame
	var y1 := player.global_position.y
	check(y1 > 2.0, "mantener SUBIR eleva a Andro (y = %.1f)" % y1)
	for i in 240:
		await physics_frame
	var y2 := player.global_position.y
	check(y2 <= ceiling + 0.01 and y2 > ceiling - 0.3, "no pasa del techo de %.1f m (y = %.2f)" % [ceiling, y2])
	Input.action_release("jump")
	for i in 60:
		await physics_frame
	check(player.flying and absf(player.global_position.y - y2) < 0.4, "al soltar queda levitando, sin caer (y = %.2f)" % player.global_position.y)
	var x0 := player.global_position
	Input.action_press("move_forward")
	for i in 90:
		await physics_frame
	Input.action_release("move_forward")
	var moved := Vector2(player.global_position.x - x0.x, player.global_position.z - x0.z).length()
	check(moved > 4.0 or player.global_position.length() > 30.0, "vuela libremente por el espacio (%.1f m en 1,5 s)" % moved)
	# cargar ki y lanzar en vuelo
	book.values["fireball"] = 0.2
	Input.action_press("charge")
	for i in 40:
		await physics_frame
		await process_frame
	check(caster.charging and book.value("fireball") > 0.3, "se puede cargar ki volando")
	Input.action_release("charge")
	Input.action_press("crouch")
	for i in 300:
		await physics_frame
		if not player.flying:
			break
	Input.action_release("crouch")
	check(not player.flying and player.is_on_floor(), "mantener BAJAR aterriza y vuelve a caminar")
	check(not touch.flying, "los botones vuelven a SALTO/AGACHAR")
	# teleport apaga el vuelo
	player.set_flying(true)
	player.teleport(Vector3(0, 0.1, 6), 0.0)
	check(not player.flying, "cambiar de escena apaga el vuelo")

	# --- techo de vuelo dentro de la casa: altura de la sala menos la holgura
	stage.instant = true
	stage.go("casa")
	while stage.busy:
		await physics_frame
	await physics_frame
	player.set_flying(true)
	Input.action_press("jump")
	for i in 400:
		await physics_frame
	Input.action_release("jump")
	var hy := player.global_position.y
	var hceil := float(player.fly_ceiling)
	check(hceil > 6.0 and hceil < 11.0, "la casa fija un techo de vuelo por sala (%.1f m)" % hceil)
	check(hy > hceil - 0.4 and hy <= hceil + 0.05, "en la casa sube hasta el techo y no lo atraviesa (y = %.2f de %.1f)" % [hy, hceil])
	player.set_flying(false)
	stage.go("umbral")
	while stage.busy:
		await physics_frame
	await physics_frame

	# --- etapas de color según rango
	check(caster.aura._tier.name == "Blanco", "el aura del ki empieza blanca")
	prog.add_points(10)
	for i in 2:
		book.upgrade("ki")
	await process_frame
	await process_frame
	check(caster.aura._tier.name == "Amarillo", "con 2 mejoras el aura pasa a amarillo")
	check(player.model.charge_color.is_equal_approx(Abilities.tier("ki", 2).glow), "la tela y las esferas toman el color del ki")
	for i in 6:
		book.upgrade("ki")
	await process_frame
	check(caster.aura._tier.name == "Morado y negro" and caster.aura._dark.visible, "con 8 mejoras el aura es morada con zarcillos negros")

	# --- selector de poderes
	check(not strip.is_open, "el selector empieza cerrado")
	strip.open()
	check(strip.is_open and strip.index == 0, "el selector abre con la bola de fuego elegida")
	strip.choose(2)
	check(caster.active == "fireball", "elegir una casilla bloqueada (???) no cambia el poder")
	strip.choose(0)
	strip.close()
	check(not strip.is_open, "el selector se cierra")

	# --- panel de pausa
	prog.set_level(5)
	prog.points = 2
	prog.upgrades.clear()
	check(pause.open(), "la pausa se abre")
	check(paused and UiLock.blocked and pause.visible, "congela el juego y bloquea los controles")
	pause.select("fireball")
	var cap0 := book.cap("fireball")
	pause._upgrade_btn.pressed.emit()
	check(book.rank("fireball") == 1 and prog.points == 1 and book.cap("fireball") > cap0, "MEJORAR gasta 1 punto y sube el rango de la bola")
	pause._upgrade_btn.pressed.emit()
	check(book.rank("fireball") == 2 and prog.points == 0, "otra mejora: rango 2")
	check(pause._upgrade_btn.disabled, "sin puntos el botón se apaga")
	pause.show_tab(1)
	check(pause._tests.visible and not pause._detail.visible, "la pestaña PRUEBAS muestra los atajos")
	pause.close()
	check(not paused and not UiLock.blocked, "continuar reanuda el juego")
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	check(pause.is_open, "la acción pause (P / Esc / Start) también abre el panel")
	pause.close()
	check(not caster.aura._tier.is_empty(), "la pausa no rompe el aura")

	# --- portal por etapa de la historia
	check(story.stage_index == 0 and Portal.style_index == 0, "la historia empieza en la etapa de piedra")
	story.set_stage(1)
	check(Portal.style_index == 1, "etapa 1: los portales nuevos son celestiales")
	story.set_stage(2)
	check(Portal.style_index == 2, "etapa 2: los portales nuevos son dorados")
	story.set_stage(9)
	check(story.stage_index == 2, "la etapa no pasa de 2")
	story.set_stage(0)
	main.queue_free()
	await process_frame


func _test_portals() -> void:
	print("-- Portales por etapa")
	var counts := []
	for st in 4:
		Portal.style_index = st
		var holder := Node3D.new()
		root.add_child(holder)
		var p := Portal.new("casa", Vector2(2.6, 5.6))
		holder.add_child(p)
		p.open(0.0)
		await physics_frame
		var frame := p.get_node("Frame")
		counts.append(frame.get_child_count())
		check(p.style == st, "estilo %d construido" % st)
		check(p.monitoring and p.openness == 1.0, "estilo %d: abre y queda activo" % st)
		var colliders := 0
		for c in frame.get_children():
			if c is StaticBody3D:
				colliders += 1
		check(colliders >= 2, "estilo %d: las jambas tienen colisión (%d)" % [st, colliders])
		if st < 3:
			var view := p.get_node("View") as MeshInstance3D
			check((view.material_override as ShaderMaterial).get_shader_parameter("style") == st, "estilo %d: interior propio" % st)
			var small := Portal.new("umbral", Vector2(2.4, 3.6))
			holder.add_child(small)
			small.open(0.0)
			check(small.get_node("Frame").get_child_count() > 20, "estilo %d: también existe en tamaño pequeño (casa)" % st)
		check(frame.get_child_count() < 260, "estilo %d: %d piezas, liviano para el teléfono" % [st, frame.get_child_count()])
		holder.queue_free()
		await process_frame
	check(counts[0] != counts[1] and counts[1] != counts[2], "cada etapa tiene un marco distinto (%s)" % str(counts))
	Portal.style_index = 0

extends SceneTree
## Test headless del mundo: spawns, huecos en calles (raycasts) y cuerpos rígidos en pendiente.
## Uso: godot --headless --path . -s res://tests/world_test.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		fails += 1
		push_error("FALLO: " + msg)
		print("  FALLO  ", msg)


func _initialize() -> void:
	var script: GDScript = load("res://world/boston_district.gd")
	var d: Node3D = script.new()
	root.add_child(d)
	await process_frame
	await physics_frame
	await physics_frame
	print("== Spawns")
	var sp := get_nodes_in_group("spawn_player")
	var sv := get_nodes_in_group("spawn_vehicle")
	check(sp.size() >= 1, "hay spawn_player (%d)" % sp.size())
	check(sv.size() >= 6 and sv.size() <= 10, "6-10 spawn_vehicle (%d)" % sv.size())
	var kinds := {}
	for m in sv:
		kinds[m.get_meta("kind")] = true
	for k in ["taxi", "sedan", "pickup", "buseta"]:
		check(kinds.has(k), "hay spawn de tipo %s" % k)
	var space := d.get_world_3d().direct_space_state

	print("== Raycasts sobre calzadas")
	var holes := 0
	var bad_h := 0
	var samples := 0
	for s in d._xs:
		var z := BostonDistrict.Z_MIN + 1.0
		while z < BostonDistrict.Z_MAX - 1.0:
			for off in [-0.8, -0.4, 0.0, 0.4, 0.8]:
				var x: float = float(s.pos) + float(s.half) * off
				if s.wide and absf(x - float(s.pos)) < BostonDistrict.MEDIAN_HALF + 0.3:
					continue
				var r := _ray(space, x, z)
				samples += 1
				if r.is_empty():
					holes += 1
				elif absf(r.position.y - BostonDistrict.road_y(x)) > 0.05:
					bad_h += 1
			z += 2.0
	for s in d._zs:
		var x2 := BostonDistrict.X_MIN + 1.0
		while x2 < BostonDistrict.X_MAX - 1.0:
			for off in [-0.8, -0.4, 0.0, 0.4, 0.8]:
				var zz: float = float(s.pos) + float(s.half) * off
				if s.wide and absf(zz - float(s.pos)) < BostonDistrict.MEDIAN_HALF + 0.3:
					continue
				var r2 := _ray(space, x2, zz)
				samples += 1
				if r2.is_empty():
					holes += 1
				elif absf(r2.position.y - BostonDistrict.road_y(x2)) > 0.05:
					bad_h += 1
			x2 += 2.0
	check(holes == 0, "sin huecos en calzadas (%d muestras, %d huecos)" % [samples, holes])
	check(bad_h == 0, "calzada continua a la altura esperada (%d fuera de tolerancia)" % bad_h)

	print("== Rejilla global (todo el mapa tiene suelo)")
	var miss := 0
	var n := 0
	var gx := BostonDistrict.X_MIN + 2.0
	while gx < BostonDistrict.X_MAX - 2.0:
		var gz := BostonDistrict.Z_MIN + 2.0
		while gz < BostonDistrict.Z_MAX - 2.0:
			var rr := _ray(space, gx, gz)
			n += 1
			if rr.is_empty() or rr.position.y < BostonDistrict.road_y(gx) - 0.05:
				miss += 1
			gz += 5.0
		gx += 5.0
	check(miss == 0, "rejilla 5 m sin huecos (%d muestras, %d fallas)" % [n, miss])

	print("== Spawns apoyados sobre calzada")
	for m in sv:
		var p: Vector3 = m.global_position
		var r3 := _ray(space, p.x, p.z)
		check(not r3.is_empty() and absf(r3.position.y - BostonDistrict.road_y(p.x)) < 0.05, "%s sobre la calzada" % m.name)
	var pp: Vector3 = sp[0].global_position
	var r4 := _ray(space, pp.x, pp.z)
	check(not r4.is_empty() and absf(r4.position.y - pp.y) < 0.5, "spawn_player sobre el piso del parque")

	print("== Cuerpos rígidos en la pendiente")
	# Caja tipo auto empujada cuesta abajo por la Calle 55, cruzando varias intersecciones.
	var box := _make_body(BoxShape3D.new(), Vector3(200.0, BostonDistrict.road_y(200.0) + 0.6, -40.0 + 1.75), 0.15)
	(box.get_child(0) as CollisionShape3D).shape.size = Vector3(1.8, 1.0, 4.2)
	box.rotation.y = PI * 0.5
	box.linear_velocity = Vector3(-14.0, 0, 0)
	# Caja empujada por la Carrera 38 hacia el norte (tramo plano transversal a la pendiente).
	var box2 := _make_body(BoxShape3D.new(), Vector3(40.0 + 1.75, BostonDistrict.road_y(41.75) + 0.6, 180.0), 0.15)
	(box2.get_child(0) as CollisionShape3D).shape.size = Vector3(1.8, 1.0, 4.2)
	box2.linear_velocity = Vector3(0, 0, -14.0)
	# Esfera que rueda sola cuesta abajo por la Calle 54.
	var sph := SphereShape3D.new()
	sph.radius = 0.4
	var ball := _make_body(sph, Vector3(150.0, BostonDistrict.road_y(150.0) + 0.45, 40.0 + 1.0), 0.8)
	var start1 := box.position
	var start2 := box2.position
	var start3 := ball.position
	var min_v1 := 999.0
	var max_drop := 0.0
	var prev_v := box.linear_velocity.length()
	for i in 360:
		await physics_frame
		var v := box.linear_velocity.length()
		if i > 10 and i < 250:
			min_v1 = minf(min_v1, v)
			max_drop = maxf(max_drop, prev_v - v)
		prev_v = v
	var d1 := start1.distance_to(box.position)
	var d2 := start2.distance_to(box2.position)
	var d3 := start3.distance_to(ball.position)
	print("  caja C55: %.1f m, vel mín %.2f m/s, y final %.2f (calzada %.2f)" % [d1, min_v1, box.position.y, BostonDistrict.road_y(box.position.x)])
	print("  caja K38: %.1f m, y final %.2f" % [d2, box2.position.y])
	print("  esfera C54: %.1f m" % d3)
	check(d1 > 40.0, "la caja baja por la Calle 55 sin atascarse (%.1f m)" % d1)
	check(max_drop < 0.5, "sin golpes bruscos en juntas/cruces (máx caída de vel por frame %.3f m/s)" % max_drop)
	check(min_v1 > 3.0, "la caja no se frena en seco en cruces (vel mín %.2f)" % min_v1)
	check(absf(box.position.y - (BostonDistrict.road_y(box.position.x) + 0.5)) < 0.3, "la caja sigue sobre la calzada")
	check(d2 > 40.0, "la caja avanza por la Carrera 38 (%.1f m)" % d2)
	check(d3 > 3.0, "la esfera rueda sola por la pendiente (%.1f m)" % d3)
	check(ball.position.x < start3.x, "la esfera rueda hacia el oeste (cuesta abajo)")

	print("== Conos (props, capa 4)")
	var cones := get_nodes_in_group("props")
	check(cones.size() >= 6, "hay conos RigidBody3D (%d)" % cones.size())
	if cones.size() > 0:
		var c: RigidBody3D = cones[0]
		check(c.collision_layer == 8, "cono en capa 4")

	print("RESULTADO: %s (%d fallas)" % ["OK" if fails == 0 else "FALLÓ", fails])
	quit(0 if fails == 0 else 1)


func _ray(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -80.0, z), 1)
	return space.intersect_ray(q)


func _make_body(shape: Shape3D, pos: Vector3, friction: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	rb.add_child(cs)
	rb.mass = 1000.0 if shape is BoxShape3D else 20.0
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	rb.physics_material_override = pm
	rb.collision_layer = 1 << 2
	rb.collision_mask = 1
	rb.position = pos
	root.add_child(rb)
	return rb

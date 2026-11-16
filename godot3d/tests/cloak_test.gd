extends SceneTree
## Prueba headless del modelo de Andro (AndroCloak): malla, esferas, tela con inercia y golpe.
## Uso: godot --headless --path . -s res://tests/cloak_test.gd

var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func _initialize() -> void:
	var mesh := AndroCloak.build_cloak_mesh()
	var box := mesh.get_aabb()
	check(box.end.y > 2.0 and box.end.y < 2.2, "la cúpula llega a %.2f m de altura" % box.end.y)
	check(box.size.x < 1.8 and box.size.z < 1.8, "ancho del dobladillo razonable (%.2f × %.2f m)" % [box.size.x, box.size.z])
	check(box.position.y >= 0.0, "ningún vértice bajo el piso (min y = %.2f)" % box.position.y)
	var tris: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	check(tris < 6500, "malla liviana: %d triángulos" % tris)

	# sin rasgos humanos: el radio nunca se estrecha como un cuello entre la punta y la parte más ancha
	var widest_y := 0.0
	var widest_r := 0.0
	var neck := false
	var prev_r := 0.0
	var y: float = AndroCloak.FIELD_Y + AndroCloak.FIELD_R + 0.02
	while y > 1.0:
		var r := AndroCloak.base_radius(y)
		if r < prev_r - 0.002:
			neck = true
		prev_r = r
		if r > widest_r:
			widest_r = r
			widest_y = y
		y -= 0.02
	check(not neck, "el contorno crece de la punta al ecuador: sin cuello ni cabeza")
	check(AndroCloak.base_radius(AndroCloak.FIELD_Y) >= AndroCloak.FIELD_R - 0.001, "la tela cubre el ecuador de la esfera invisible (r = %.2f)" % AndroCloak.base_radius(AndroCloak.FIELD_Y))
	var layers := {}
	for c in (mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray):
		layers[snappedf(c.r, 0.1)] = true
	check(layers.size() == 2, "dos capas de tela: interior y manto (%d)" % layers.size())
	# el manto está abierto al frente (-Z): ningún vértice del manto cerca del eje frontal a media altura
	var arr := mesh.surface_get_arrays(0)
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cc: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var front_blocked := false
	var max_r := 0.0
	for k in vv.size():
		max_r = maxf(max_r, Vector2(vv[k].x, vv[k].z).length())
		if cc[k].r > 0.5 and absf(vv[k].x) < 0.05 and vv[k].z < -0.3 and vv[k].y > 0.6 and vv[k].y < 1.4:
			front_blocked = true
	check(not front_blocked, "el manto está abierto al frente")
	check(max_r <= Player.CAPSULE_RADIUS + 0.15, "la tela no sobresale mucho del campo de fuerza (%.2f m vs %.2f m)" % [max_r, Player.CAPSULE_RADIUS])
	check(Player.CAPSULE_RADIUS >= AndroCloak.FIELD_R + 0.07, "el campo de fuerza (cápsula %.2f m) cubre la tela" % Player.CAPSULE_RADIUS)

	var m := AndroCloak.new()
	root.add_child(m)
	await process_frame
	var orbs := 0
	for c in m.get_children():
		if c.name.begins_with("Orb"):
			orbs += 1
	check(orbs == 5, "5 esferas orbitando (%d)" % orbs)

	# quieto: la tela se asienta y casi no se arrastra
	var dt := 1.0 / 60.0
	for i in 60:
		m.animate("idle", 0.0, dt)
	check(m._drift.length() < 0.02, "quieto: la tela no se arrastra (%.3f)" % m._drift.length())

	# corriendo hacia -Z (adelante): el borde queda ATRÁS (+Z) y la capa se inclina al frente
	var z := 0.0
	for i in 60:
		z -= 6.0 * dt
		m.position = Vector3(0, 0, z)
		m.animate("sprint", 6.0, dt)
	check(m._drift.z > 0.2, "al correr el borde se queda atrás (drift.z = %.2f)" % m._drift.z)
	check(m._drift.length() <= 0.51, "arrastre limitado, movimiento controlado (%.2f)" % m._drift.length())
	check(m._body.rotation.x < -0.05, "se inclina hacia adelante (%.2f rad)" % m._body.rotation.x)

	# frenar en seco: la tela se adelanta y oscila antes de asentarse (resorte con rebote)
	var peak_neg := 0.0
	for i in 40:
		m.animate("idle", 0.0, dt)
		peak_neg = minf(peak_neg, m._drift.z)
	check(peak_neg < -0.01, "al frenar la tela rebota hacia adelante (%.3f)" % peak_neg)
	for i in 180:
		m.animate("idle", 0.0, dt)
	check(m._drift.length() < 0.03, "y vuelve a asentarse (%.3f)" % m._drift.length())

	# giro: se balancea de lado
	var yaw := 0.0
	for i in 40:
		yaw += 3.0 * dt
		m.rotation.y = yaw
		m.animate("walk", 1.6, dt)
	check(absf(m._roll) > 0.01, "al girar se ladea (roll %.3f)" % m._roll)

	# golpe telequinético: las esferas salen disparadas y brillan
	m.rotation.y = 0.0
	m.punch_idx = 0
	var min_z := 0.0
	for i in 20:
		m.punch_t = 0.17
		m.animate("punch", 0.0, dt)
	for o in m.get_children():
		if o.name == "Orb0":
			min_z = o.position.z
	check(min_z < -0.8, "el golpe lanza las esferas al frente (z = %.2f)" % min_z)
	check(float(m._orb_mat.get_shader_parameter("glow")) > 0.2, "las esferas brillan al golpear")

	# estelas: cada esfera tiene su estela y su cabeza coincide con la esfera
	var trail_err := 0.0
	var trails := 0
	for i in 5:
		var orb := m.get_node_or_null("Orb%d" % i) as Node3D
		var tr := m.get_node_or_null("Trail%d" % i) as Node3D
		if orb and tr:
			trails += 1
			var head: Vector3 = tr.global_transform * Vector3(0, 0, 1)
			trail_err = maxf(trail_err, head.distance_to(orb.global_position))
	check(trails == 5 and trail_err < 0.02, "5 estelas con la cabeza en su esfera (error %.3f m)" % trail_err)

	# campo de fuerza: ninguna esfera entra, ni corriendo ni al golpear
	var worst := 9.0
	for i in 120:
		var zz := -float(i) * 0.1
		m.position = Vector3(0, 0, zz)
		m.punch_idx = i % 3
		m.punch_t = 0.15 if i % 40 < 12 else 0.0
		m.animate("sprint" if i % 40 >= 12 else "punch", 7.0, dt)
		for o in m.get_children():
			if o.name.begins_with("Orb"):
				worst = minf(worst, Vector2((o as Node3D).position.x, (o as Node3D).position.z).length())
	check(worst >= AndroCloak.ORB_CLEARANCE, "ninguna esfera entra al campo de fuerza (mín. %.2f m)" % worst)

	# agachado y salto cambian la silueta
	for i in 40:
		m.animate("crouch", 0.0, dt)
	check(m._body.scale.y < 0.9, "agachado se encoge (%.2f)" % m._body.scale.y)

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(fails)

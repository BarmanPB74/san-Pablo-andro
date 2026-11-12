extends SceneTree
## F5–F7: bocas M1–M5, variantes de pelo, bufanda con colas encadenadas.
## Uso: godot --headless -s res://tests/andro_f5f7_test.gd   → imprime RESULT: PASS/FAIL

func _initialize() -> void:
	ClayStyle.enabled = true
	var ok := true
	var m := PlayerModel.new()
	root.add_child(m)
	root.add_child(ClayStyle.new())
	for i in 5:
		await process_frame
	# F5: 5 bocas, una visible a la vez, sin reconstruir mallas
	for i in 5:
		ok = ok and m.head.get_node_or_null("mouth_m%d" % (i + 1)) != null
	var shared := true
	for id in [2, 4, 5, 1]:
		m.set_mouth(id)
		var vis := 0
		for i in 5:
			if (m.head.get_node("mouth_m%d" % (i + 1)) as Node3D).visible:
				vis += 1
		shared = shared and vis == 1 and m.get_mouth() == id
	print("bocas: una visible a la vez = ", shared)
	ok = ok and shared
	# F6: 4 variantes de pelo; cada una cambia la malla y reutiliza la caché
	var tris: Array[int] = []
	for v in 4:
		m.set_hair_variant(v)
		await process_frame
		var hp := m.head.get_node_or_null("hair") as Node3D
		ok = ok and hp != null and m.get_hair_variant() == v
		tris.append(m.triangle_count())
	print("tris totales por variante de pelo: ", tris)
	ok = ok and tris[0] != tris[2] and tris[3] > tris[2]
	m.set_hair_variant(0)
	# F7: colas con cadena de pivotes (a: 4 segmentos, b: 3) que reaccionan al giro
	for nm in ["scarf_a1", "scarf_a2", "scarf_a3", "scarf_a4", "scarf_b1", "scarf_b2", "scarf_b3"]:
		var found := m.find_child(nm, true, false) != null
		ok = ok and found
	var a1 := m.find_child("scarf_a1", true, false) as Node3D
	var a2 := m.find_child("scarf_a2", true, false) as Node3D
	ok = ok and a2.get_parent() == a1
	m.global_rotation.y = 0.0
	for i in 40:
		m.global_rotation.y += 0.05
		m.animate("run", 5.0 + float(i) * 0.1, 0.016)
	print("balanceo cola a1: rot.z=%.3f rot.x=%.3f" % [a1.rotation.z, a1.rotation.x])
	ok = ok and absf(a1.rotation.z) > 0.01
	# variantes de bufanda: se reconstruyen las colas
	var before := m.triangle_count()
	m.set_scarf_variant(3)
	var fr := m.triangle_count()
	m.set_scarf_variant(2)
	print("tris bufanda: clásica ", before, " · flecos largos ", fr, " · corta ", m.triangle_count())
	ok = ok and fr > before and m.find_child("scarf_a1", true, false) != null
	m.set_scarf_variant(0)
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

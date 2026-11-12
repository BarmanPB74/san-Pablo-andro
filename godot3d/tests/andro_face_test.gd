extends SceneTree
## F4: piezas animables de la cara de Andro (ojos, párpados, cejas) y set_face().
## Uso: godot --headless -s res://tests/andro_face_test.gd   → imprime RESULT: PASS/FAIL

func _initialize() -> void:
	ClayStyle.enabled = true
	var ok := true
	var m := PlayerModel.new()
	root.add_child(m)
	root.add_child(ClayStyle.new())
	for i in 5:
		await process_frame
	# 1) seis piezas hijas de head, cada una con su malla
	for nm in ["eye_l", "eye_r", "lid_l", "lid_r", "brow_l", "brow_r"]:
		var p := m.head.get_node_or_null(nm) as Node3D
		var has_mesh := p != null and p.get_node_or_null("Mesh") is MeshInstance3D
		print("pieza ", nm, ": ", "OK" if has_mesh else "FALTA")
		ok = ok and has_mesh
	# 2) parpadeo en 3 poses: el párpado gira más cuanto más cerrado
	var lid := m.head.get_node("lid_l") as Node3D
	var rots: Array[float] = []
	for b in 3:
		m.set_face(b)
		rots.append(lid.rotation.x)
	print("rot. párpado por pose: ", rots)
	ok = ok and rots[0] == 0.0 and rots[1] < rots[0] and rots[2] < rots[1]
	# 3) mirada y cejas
	m.set_face(0, Vector2(0.2, 0.1), 1.0, -1.0)
	var eye := m.head.get_node("eye_r") as Node3D
	print("mirada: ", eye.rotation)
	ok = ok and not is_zero_approx(eye.rotation.y) and is_equal_approx(eye.rotation.x, 0.1)
	var bl := m.head.get_node("brow_l") as Node3D
	var br := m.head.get_node("brow_r") as Node3D
	ok = ok and bl.position.y > br.position.y
	# 4) los triángulos de las piezas cuentan en el total
	print("tris total: ", m.triangle_count())
	ok = ok and m.triangle_count() > 0
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

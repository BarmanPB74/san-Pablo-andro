extends SceneTree
## Prueba del adaptador "arcilla gótica" (port de GothicClayCharacterAdapter.cs).
## Uso: godot --headless -s res://tests/gothic_clay_adapter_test.gd   → imprime RESULT: PASS/FAIL

func _initialize() -> void:
	ClayStyle.enabled = true
	var ok := true
	# 1) Andro: el adaptador se agrega solo y deja mate la ropa/piel y brillantes los ojos
	var m := PlayerModel.new()
	root.add_child(m)
	root.add_child(ClayStyle.new())
	for i in 5: await process_frame
	var roles := {}
	for mi in GothicClayAdapter._meshes(m):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(s) as ShaderMaterial
			if mat == null:
				continue
			var r: float = mat.get_shader_parameter("rough")
			var src: Material = mat.get_meta("clay_src", null)
			roles[PlayerModel.material_key(src)] = r
	print("rugosidad por pieza: ", roles)
	ok = ok and is_equal_approx(float(roles.get("skin", 0)), 0.80) and is_equal_approx(float(roles.get("eye", 0)), 0.25)
	ok = ok and is_equal_approx(float(roles.get("twill", 0)), 0.80)
	# 2) Modelo importado con piezas nombradas (reglas por nombre del C#)
	var glb := Node3D.new()
	root.add_child(glb)
	for n in ["Scarf", "Eye_L", "Pupil_L", "Hair", "Coat", "Shoe_R", "Head"]:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.mesh = BoxMesh.new()
		mi.mesh.surface_set_material(0, StandardMaterial3D.new())
		glb.add_child(mi)
	ClayStyle.apply_tree(glb)
	var ad := GothicClayAdapter.new()
	ad.apply_on_ready = false
	ad.existing_character_root = glb
	glb.add_child(ad)
	ad.apply_gothic_clay_style()
	var expect := {"Scarf": Color.WHITE, "Eye_L": GothicClayAdapter.EYE, "Pupil_L": GothicClayAdapter.PUPIL,
		"Hair": GothicClayAdapter.HAIR, "Coat": GothicClayAdapter.COAT, "Shoe_R": GothicClayAdapter.SHOE, "Head": GothicClayAdapter.SKIN}
	for n in expect:
		var mi := glb.get_node(n) as MeshInstance3D
		var mat := mi.get_surface_override_material(0) as ShaderMaterial
		var col: Color = mat.get_shader_parameter("base_color") if mat else Color.BLACK
		var good: bool = mat != null and col.is_equal_approx(expect[n])
		print("  %s → %s %s" % [n, col, "ok" if good else "MAL"])
		ok = ok and good
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit()

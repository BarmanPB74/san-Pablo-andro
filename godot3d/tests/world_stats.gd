extends SceneTree
## Estadísticas de geometría del BostonDistrict (triángulos por material, instancias).

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var d: Node3D = load("res://world/boston_district.gd").new()
	root.add_child(d)
	await process_frame
	print("build_ms=", Time.get_ticks_msec() - t0)
	var per := {}
	var meshes := 0
	for n in d.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		meshes += 1
		if not (mi.mesh is ArrayMesh):
			continue
		var m: ArrayMesh = mi.mesh
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var key := (mat.resource_path + ":" + mat.get_class() + str(mat.get("albedo_color"))) if mat else "none"
			var tris: int = m.surface_get_array_len(s) / 3
			per[key] = per.get(key, 0) + tris
	var keys := per.keys()
	keys.sort_custom(func(a, b): return per[a] > per[b])
	for k in keys.slice(0, 20):
		print(k, " tris=", per[k])
	for n in d.find_children("*", "MultiMeshInstance3D", true, false):
		var mm: MultiMeshInstance3D = n
		print(mm.name, " instances=", mm.multimesh.instance_count)
	print("mesh_instances=", meshes, " labels=", d.find_children("*", "Label3D", true, false).size(), " shapes=", d.get_node("Colision").get_child_count())
	quit()

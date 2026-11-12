extends SceneTree
## F0: inventario del modelo de Andro (modo plastilina). Solo lee, no modifica nada.
## Uso: godot --headless --path godot3d -s res://tests/andro_inventory.gd   → tris, medidas y materiales por pivote.

func _init() -> void:
	ClayStyle.enabled = true
	var m := PlayerModel.new()
	root.add_child(m)
	await process_frame
	await process_frame
	await process_frame
	m.snap_pose("idle", 0.0, 0.0)
	await process_frame
	print("TRIS_TOTAL ", m.triangle_count())
	var total := AABB()
	var first := true
	var joints: Dictionary = m._joints
	for jn in joints:
		var n: Node3D = joints[jn]
		var mi := n.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null or mi.mesh == null:
			print("JOINT ", jn, " sin malla")
			continue
		var mesh := mi.mesh as ArrayMesh
		var tris := 0
		var mats := []
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			tris += (idx.size() if idx != null else vtx.size()) / 3
			var mat := mi.get_active_material(s)
			var key := "?"
			if mat != null:
				var src: Material = mat.get_meta("clay_src", mat)
				key = PlayerModel.material_key(src)
			mats.append(key)
		var wa := mi.global_transform * mesh.get_aabb()
		print("JOINT %-12s surf=%d tris=%5d scale=%.2f aabb_size=(%.3f, %.3f, %.3f) y=[%.3f..%.3f] mats=%s" % [
			jn, mesh.get_surface_count(), tris, mi.scale.x, wa.size.x, wa.size.y, wa.size.z, wa.position.y, wa.end.y, str(mats)])
		if first:
			total = wa
			first = false
		else:
			total = total.merge(wa)
	print("MODEL_AABB size=(%.3f, %.3f, %.3f) y=[%.3f..%.3f]" % [total.size.x, total.size.y, total.size.z, total.position.y, total.end.y])
	var head_mi := m.head.get_node("Mesh") as MeshInstance3D
	var hb := head_mi.global_transform * head_mi.mesh.get_aabb()
	print("HEAD size=(%.3f, %.3f, %.3f) y=[%.3f..%.3f]  altura/cabeza=%.2f" % [hb.size.x, hb.size.y, hb.size.z, hb.position.y, hb.end.y, total.size.y / hb.size.y])
	var uniq := {}
	for jn in joints:
		var mi2 := (joints[jn] as Node3D).get_node_or_null("Mesh") as MeshInstance3D
		if mi2 == null:
			continue
		for s in mi2.mesh.get_surface_count():
			var mt := mi2.get_active_material(s)
			if mt != null:
				uniq[mt.get_instance_id()] = true
	print("MATERIALES_UNICOS ", uniq.size())
	var ad := m.get_node_or_null("GothicClayAdapter")
	print("ADAPTER ", ad != null)
	quit()

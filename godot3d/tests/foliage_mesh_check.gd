extends SceneTree
## Revisa los meshes de árboles: normales/tangentes NaN o de largo cero, triángulos con UV degenerada.
## Uso: godot --headless --path . -s res://tests/foliage_mesh_check.gd

func _initialize() -> void:
	var kinds := {"SAMAN": Trees.SAMAN, "GUAY_AMARILLO": Trees.GUAYACAN_AMARILLO, "GUAY_ROSADO": Trees.GUAYACAN_ROSADO, "ANDEN": Trees.ANDEN}
	var bad_total := 0
	for kn in kinds:
		for v in Trees.VARIANTS:
			var m: Mesh = Trees.mesh(kinds[kn], v)
			for s in m.get_surface_count():
				var arr: Array = m.surface_get_arrays(s)
				var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var tan: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
				var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var bad_n := 0
				for n in nrm:
					if is_nan(n.x) or is_nan(n.y) or is_nan(n.z) or n.length() < 0.5:
						bad_n += 1
				var bad_t := 0
				for i in range(0, tan.size(), 4):
					var l := Vector3(tan[i], tan[i + 1], tan[i + 2]).length()
					if is_nan(l) or l < 0.5:
						bad_t += 1
				var deg := 0
				var tris := idx.size() / 3
				for t in tris:
					var a := uv[idx[t * 3]]; var b := uv[idx[t * 3 + 1]]; var c := uv[idx[t * 3 + 2]]
					if absf((b - a).cross(c - a)) < 1e-9:
						deg += 1
				bad_total += bad_n + bad_t
				print("%s v%d s%d: verts=%d tris=%d | normales malas=%d | tangentes malas=%d (de %d) | UV degeneradas=%d" % [kn, v, s, nrm.size(), tris, bad_n, bad_t, tan.size() / 4, deg])
	print("TOTAL MALAS: ", bad_total)
	quit()

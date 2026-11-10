class_name ContactShadows
extends RefCounted
## Sombras de contacto baratas para el renderer Mobile (no hay SSAO).
## Un solo MultiMesh de cuadrados planos con un degradado radial negro → 1 draw call para todo el distrito.
## Se ponen al pie de troncos, postes, faroles y bolardos para que "asienten" en el piso.
##
## Uso: var mmi := ContactShadows.build(blobs)  # blobs: Array de Vector4(x, y_suelo, z, radio_objeto)
##      add_child(mmi)

const LIFT := 0.03          ## separación del piso (evita z-fighting)
const MAX_DIST := 90.0      ## más lejos no se dibujan
const OPACITY := 0.55

static var _tex: GradientTexture2D = null
static var _mat: StandardMaterial3D = null


static func _texture() -> GradientTexture2D:
	if _tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, OPACITY), Color(0, 0, 0, OPACITY * 0.4), Color(0, 0, 0, 0)])
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(1.0, 0.5)
		_tex.width = 64
		_tex.height = 64
	return _tex


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_texture = _texture()
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.disable_receive_shadows = true
	return _mat


## Radio de la mancha según el radio del objeto (tronco 0.4 m → ~1.1 m; poste 0.1 m → ~0.45 m).
static func blob_radius(object_radius: float) -> float:
	return clampf(object_radius * 2.0 + 0.25, 0.35, 1.6)


## Quita duplicados (un mismo poste puede registrar 2 cilindros) y arma el MultiMesh.
static func build(blobs: Array) -> MultiMeshInstance3D:
	var best := {}   # celda de 0.3 m → Vector4
	for b: Vector4 in blobs:
		var key := Vector2i(roundi(b.x / 0.3), roundi(b.z / 0.3))
		if not best.has(key) or (best[key] as Vector4).w < b.w:
			best[key] = b
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2.ONE
	quad.material = _material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = best.size()
	var i := 0
	for key in best:
		var b: Vector4 = best[key]
		var d := blob_radius(b.w) * 2.0
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(d, 1.0, d)), Vector3(b.x, b.y + LIFT, b.z)))
		i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SombrasContacto"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = MAX_DIST
	return mmi

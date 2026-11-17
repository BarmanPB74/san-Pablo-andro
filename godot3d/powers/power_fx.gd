class_name PowerFx
extends RefCounted
## Texturas y materiales compartidos por los efectos de poder (se crean una vez).

static var _glow: GradientTexture2D


## Disco de luz suave (128 × 128, blanco al centro, transparente en el borde).
static func glow_tex() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.width = 128
		_glow.height = 128
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
	return _glow


## Material de partícula/halo: aditivo, sin luz, siempre de cara a la cámara, con el color de la partícula.
static func additive_billboard(tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.albedo_texture = glow_tex()
	m.albedo_color = tint
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	return m


## Halo fijo (un quad que mira a la cámara) para la bola de fuego.
static func halo(size: float, tint: Color) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = glow_tex()
	m.albedo_color = tint
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Material de humo negro (mezcla normal, no aditivo): zarcillos oscuros de la bola "morada y negra".
static func smoke_billboard() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = glow_tex()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	m.disable_receive_shadows = true
	return m

class_name TexMat
extends RefCounted
## Construye materiales PBR desde los sets de texturas generados en art/tex/
## (<base>_albedo.png, _normal.png, _orm.png, opcional _emission.png).
## Todos los mat_<familia>.gd usan esto para que la carga sea uniforme y cacheada.

static var _cache := {}


## base: ruta res:// SIN sufijo, p. ej. "res://art/tex/stone/granito".
## opts (todas opcionales):
##   "tile_m": float      metros por repetición en modo triplanar (default 2.0)
##   "triplanar": bool    proyección triplanar en espacio de mundo (default true; ideal para BoxMesh del mapa)
##   "uv_scale": Vector3  escala UV si triplanar = false
##   "tint": Color        multiplica el albedo (variaciones sin nuevas texturas)
##   "normal_scale": float
##   "rough_add": float   suma a la rugosidad (+ seco / - mojado), vía roughness como multiplicador
##   "emission_energy": float
##   "transparent": bool  usa alpha scissor (follaje)
##   "cull_disabled": bool
static func pbr(base: String, opts := {}) -> ORMMaterial3D:
	var key := base + str(opts)
	if _cache.has(key):
		return _cache[key]
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(base + "_albedo.png")
	m.normal_enabled = ResourceLoader.exists(base + "_normal.png")
	if m.normal_enabled:
		m.normal_texture = load(base + "_normal.png")
		m.normal_scale = float(opts.get("normal_scale", 1.0))
	if ResourceLoader.exists(base + "_orm.png"):
		m.orm_texture = load(base + "_orm.png")
	m.roughness = clampf(1.0 + float(opts.get("rough_add", 0.0)), 0.0, 1.0)
	m.metallic = 1.0
	if opts.has("tint"):
		m.albedo_color = opts["tint"]
	if ResourceLoader.exists(base + "_emission.png"):
		m.emission_enabled = true
		m.emission_texture = load(base + "_emission.png")
		m.emission_energy_multiplier = float(opts.get("emission_energy", 2.0))
	if opts.get("transparent", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	if opts.get("cull_disabled", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if opts.get("triplanar", true):
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		var t := 1.0 / float(opts.get("tile_m", 2.0))
		m.uv1_scale = Vector3(t, t, t)
		m.uv1_triplanar_sharpness = 4.0
	else:
		m.uv1_scale = opts.get("uv_scale", Vector3.ONE)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m

class_name Palette
extends RefCounted
## Biblioteca compartida de materiales. TODOS los agentes piden materiales aquí
## (nunca crean StandardMaterial3D sueltos), así el look se ajusta en un solo sitio.
## Dueño: agente LOOK. Las firmas públicas NO cambian; solo el interior.
##
## Dirección de color: ciudad mojada tras la lluvia. Fachadas con color
## antioqueño pero algo desaturadas, negros profundos, superficies de piso
## con shader de humedad (look/wet_asphalt.gdshader) controlado globalmente
## por StreetLook vía Palette.set_weather().

static var _cache := {}
static var _detail_tex: Texture2D = null

const WET_SHADER := "res://look/wet_asphalt.gdshader"
const VALLEY_SHADER := "res://look/valley.gdshader"

## Estado global del clima (lo fija StreetLook según el preset).
static var weather_wetness := 0.7
static var weather_rain := 0.0
static var weather_sky := Color(0.45, 0.5, 0.55)


static func _cached(key: String, builder: Callable) -> Material:
	if not _cache.has(key):
		_cache[key] = builder.call()
	return _cache[key]


static func _std(albedo: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	return m


## Textura de ruido compartida (una sola en memoria) para dar suciedad/variación
## a superficies grandes. Se aplica triplanar en espacio de mundo: no necesita UVs.
static func _detail() -> Texture2D:
	if _detail_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.02
		n.fractal_octaves = 4
		n.seed = 7
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.8, 0.8, 0.8))
		ramp.set_color(1, Color(1.0, 1.0, 1.0))
		var t := NoiseTexture2D.new()
		t.width = 256
		t.height = 256
		t.seamless = true
		t.generate_mipmaps = true
		t.noise = n
		t.color_ramp = ramp
		_detail_tex = t
	return _detail_tex


## Material estándar con ruido de detalle triplanar (barato: 1 textura de 256²).
## scale = repeticiones por metro.
static func _rich(albedo: Color, rough := 0.85, metal := 0.0, scale := 0.25) -> StandardMaterial3D:
	var m := _std(albedo, rough, metal)
	m.albedo_texture = _detail()
	m.roughness_texture = _detail()
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * scale
	# el ruido multiplica 0.8..1.0: compensamos para mantener el valor medio
	m.albedo_color = Color(albedo.r * 1.11, albedo.g * 1.11, albedo.b * 1.11, albedo.a)
	m.roughness = clampf(rough * 1.15, 0.0, 1.0)
	return m


## Superficie de piso mojado (ShaderMaterial con wet_asphalt.gdshader).
static func _wet(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(WET_SHADER)
	for k in params:
		m.set_shader_parameter(k, params[k])
	m.set_shader_parameter("wetness", weather_wetness)
	m.set_shader_parameter("rain", weather_rain)
	m.set_shader_parameter("sky_reflection", weather_sky)
	return m


## Fija el clima global en todos los materiales de piso mojado ya creados
## (y en los que se creen después). Lo llama StreetLook.set_time_of_day().
## wetness 0..1 (seco..encharcado), rain 0..1 (ondas en charcos),
## sky: color del cielo que reflejan los charcos por fresnel,
## night 0..1: luces de barrios en las montañas del fondo.
static func set_weather(wetness: float, rain: float, sky: Color, night := 0.0) -> void:
	weather_wetness = clampf(wetness, 0.0, 1.0)
	weather_rain = clampf(rain, 0.0, 1.0)
	weather_sky = sky
	if USE_TEXTURES:
		MatAsphalt.sync_weather()   # sus materiales mojados viven en otro caché
	for k in _cache:
		var m = _cache[k]
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			var sm := m as ShaderMaterial
			if sm.shader.resource_path == WET_SHADER:
				sm.set_shader_parameter("wetness", weather_wetness)
				sm.set_shader_parameter("rain", weather_rain)
				sm.set_shader_parameter("sky_reflection", weather_sky)
			elif sm.shader.resource_path == VALLEY_SHADER:
				sm.set_shader_parameter("night", night)


# ---------- Texturas PBR (Fase 1 gráfica) ----------
## true: las funciones de abajo devuelven los materiales con texturas reales de art/mat/.
## false: vuelve a los materiales procedurales originales (útil para comparar o si el
## teléfono va justo de memoria).
const USE_TEXTURES := true

## Divide un color entre 0.8: las texturas de tela/piel tienen base 0.8, así el tono
## final coincide con el color que pidió el modelo.
static func _undim(c: Color) -> Color:
	return Color(minf(c.r / 0.8, 1.0), minf(c.g / 0.8, 1.0), minf(c.b / 0.8, 1.0), c.a)


# ---------- Suelo urbano ----------
static func asphalt() -> Material:          # asfalto mojado (shader con charcos)
	if USE_TEXTURES:
		return MatAsphalt.asphalt_worn()    # Boston: barrio tradicional, asfalto con parches
	return wet_asphalt()

## Asfalto mojado con charcos procedurales, reflejo fresnel y ondas de lluvia.
static func wet_asphalt() -> Material:
	return _cached("wet_asphalt", func(): return _wet({
		"base_color": Color(0.105, 0.11, 0.12),
		"puddle_color": Color(0.02, 0.025, 0.03),
		"puddle_coverage": 0.6,
		"dry_roughness": 0.8,
		"damp_roughness": 0.4,
	}))

static func sidewalk() -> Material:         # andén de concreto (losas, algo húmedo)
	if USE_TEXTURES:
		return MatPaving.sidewalk_concrete()
	return _cached("sidewalk", func(): return _wet({
		"base_color": Color(0.46, 0.45, 0.43),
		"puddle_color": Color(0.1, 0.105, 0.11),
		"puddle_coverage": 0.22,
		"puddle_scale": 0.18,
		"dry_roughness": 0.85,
		"damp_roughness": 0.5,
		"color_variation": 0.22,
		"tile_size": 1.0,
		"groove_width": 0.018,
		"groove_color": Color(0.16, 0.16, 0.16),
		"reflect_boost": 0.35,
	}))

static func curb() -> Material:             # sardinel
	if USE_TEXTURES:
		return MatPaving.curb()
	return _cached("curb", func(): return _rich(Color(0.56, 0.55, 0.52), 0.75, 0.0, 0.5))

static func plaza_tile() -> Material:       # adoquín / baldosa del parque
	if USE_TEXTURES:
		return MatPaving.hex_pavers()       # adoquín hexagonal gris del Parque de Boston
	return _cached("plaza_tile", func(): return _wet({
		"base_color": Color(0.42, 0.25, 0.18),
		"puddle_color": Color(0.1, 0.06, 0.05),
		"puddle_coverage": 0.3,
		"puddle_scale": 0.15,
		"dry_roughness": 0.8,
		"damp_roughness": 0.42,
		"color_variation": 0.3,
		"tile_size": 0.5,
		"groove_width": 0.012,
		"groove_color": Color(0.14, 0.11, 0.1),
		"tile_variation": 0.18,
		"reflect_boost": 0.4,
	}))

static func grass() -> Material:
	if USE_TEXTURES:
		return MatGround.pasto()
	return _cached("grass", func(): return _rich(Color(0.13, 0.25, 0.12), 0.9, 0.0, 0.4))

static func road_line() -> Material:        # pintura vial (algo brillante por humedad)
	return _cached("road_line", func(): return _std(Color(0.85, 0.78, 0.5), 0.35))

# ---------- Edificios ----------
static func brick() -> Material:            # ladrillo antioqueño
	if USE_TEXTURES:
		return MatBrick.fachada_naranja()
	return _cached("brick", func(): return _rich(Color(0.46, 0.21, 0.13), 0.85, 0.0, 0.35))

static func stucco(variant := 0) -> Material:  # fachada pintada (0..5)
	# tonos antioqueños, un poco desaturados para que el neón mande
	var cols := [Color(0.78, 0.74, 0.64), Color(0.66, 0.45, 0.36), Color(0.42, 0.55, 0.6),
		Color(0.8, 0.64, 0.36), Color(0.5, 0.6, 0.48), Color(0.72, 0.72, 0.7)]
	if USE_TEXTURES:
		return MatPlaster.stucco_house(variant)
	var c: Color = cols[posmod(variant, cols.size())]
	return _cached("stucco_%d" % posmod(variant, cols.size()), func(): return _rich(c, 0.88, 0.0, 0.2))

static func concrete() -> Material:
	if USE_TEXTURES:
		return MatPlaster.concrete_board()
	return _cached("concrete", func(): return _rich(Color(0.42, 0.43, 0.44), 0.85, 0.0, 0.25))

static func roof_tile() -> Material:        # teja de barro
	if USE_TEXTURES:
		return MatPlaster.roof_clay()
	return _cached("roof_tile", func(): return _rich(Color(0.42, 0.17, 0.09), 0.7, 0.0, 0.6))

static func window_glass() -> Material:     # vidrio oscuro que refleja el cielo
	return _cached("window_glass", func():
		var m := _std(Color(0.035, 0.05, 0.06), 0.06, 0.6)
		m.rim_enabled = false
		return m)

static func window_lit() -> Material:       # ventana iluminada cálida (ámbar)
	return _cached("window_lit", func():
		var m := _std(Color(1.0, 0.72, 0.42), 0.3)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.66, 0.34)
		m.emission_energy_multiplier = 1.6
		return m)

static func metal_dark() -> Material:       # rejas, postes
	return _cached("metal_dark", func(): return _std(Color(0.06, 0.065, 0.07), 0.38, 0.8))

static func wood() -> Material:
	return _cached("wood", func(): return _rich(Color(0.3, 0.18, 0.1), 0.75, 0.0, 0.8))

static func bronze() -> Material:           # estatua (pátina verdosa)
	if USE_TEXTURES:
		return MatStone.bronce(0.6)
	return _cached("bronze", func(): return _std(Color(0.28, 0.27, 0.18), 0.38, 0.9))

static func stone() -> Material:            # pedestal / iglesia
	if USE_TEXTURES:
		return MatStone.sillar()
	return _cached("stone", func(): return _rich(Color(0.52, 0.5, 0.47), 0.85, 0.0, 0.3))

static func foliage() -> Material:          # verde profundo, ligeramente teal
	if USE_TEXTURES:
		return MatFoliage.hedge()           # copas/setos macizos; las tarjetas llegan en la fase 2
	return _cached("foliage", func(): return _rich(Color(0.08, 0.2, 0.1), 0.8, 0.0, 0.7))

static func bark() -> Material:
	if USE_TEXTURES:
		return _cached("bark_tex", func(): return TexMat.pbr("res://art/tex/ground/corteza_tropical", {"tile_m": 2.0}))
	return _cached("bark", func(): return _rich(Color(0.2, 0.14, 0.1), 0.95, 0.0, 1.0))

# ---------- Luz / neón ----------
## color: tono del neón; energy: intensidad de emisión (glow lo convierte en bloom).
## Unshaded: el color sale saturado y por encima del umbral de glow.
static func neon(color: Color, energy := 4.0) -> Material:
	var key := "neon_%s_%.1f" % [color.to_html(), energy]
	return _cached(key, func():
		var m := _std(color, 0.4)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# unshaded ignora emission: el albedo pasa un poco de 1.0 (HDR) para cruzar el
		# umbral del glow sin quemar el color a blanco (el neón debe verse saturado).
		var k := clampf(energy * 0.3, 1.0, 1.8)
		m.albedo_color = Color(color.r * k, color.g * k, color.b * k)
		m.disable_fog = false
		return m)

## Colores de neón de referencia (cian, magenta, ámbar).
const NEON_CYAN := Color(0.0, 0.72, 1.0)
const NEON_MAGENTA := Color(1.0, 0.04, 0.55)
const NEON_AMBER := Color(1.0, 0.5, 0.08)

static func lamp_bulb() -> Material:        # bombillo de farol (sodio ámbar)
	return neon(Color(1.0, 0.72, 0.42), 6.0)

# ---------- Vehículos ----------
## paint: color de carrocería. Pintura brillante con algo de metal (clear coat).
static func car_paint(paint: Color) -> Material:
	if USE_TEXTURES:
		return MatActors.car_paint_dirty(paint, 0.6)
	return _cached("paint_%s" % paint.to_html(), func():
		var m := _std(paint, 0.22, 0.45)
		m.clearcoat_enabled = true
		m.clearcoat = 0.6
		m.clearcoat_roughness = 0.15
		return m)

static func tire() -> Material:
	if USE_TEXTURES:
		return MatActors.tire()
	return _cached("tire", func(): return _std(Color(0.035, 0.035, 0.038), 0.85))

static func chrome() -> Material:
	return _cached("chrome", func(): return _std(Color(0.8, 0.8, 0.82), 0.12, 1.0))

static func headlight() -> Material:
	return neon(Color(1.0, 0.95, 0.85), 3.0)

static func taillight() -> Material:
	return neon(Color(1.0, 0.08, 0.05), 3.0)

# ---------- Personaje ----------
static func cloth(color: Color, rough := 0.9) -> Material:
	if USE_TEXTURES:
		return MatActors.jacket_ripstop(_undim(color))
	return _cached("cloth_%s_%.2f" % [color.to_html(), rough], func(): return _std(color, rough))

static func skin(tone := Color(0.62, 0.45, 0.34)) -> Material:
	if USE_TEXTURES:
		return MatActors.skin(_undim(tone))
	return _cached("skin_%s" % tone.to_html(), func():
		var m := _std(tone, 0.55)
		# rim suave: separa la silueta del fondo oscuro/mojado
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.5
		return m)

# ---------- Look (agente LOOK) ----------
## Montañas lejanas del valle (color por vértice, neblina propia, luces nocturnas).
static func mountain_far() -> Material:
	return _cached("mountain_far", func():
		var m := ShaderMaterial.new()
		m.shader = load(VALLEY_SHADER)
		return m)

## Gota de lluvia (streak vertical, billboard en Y, para GPUParticles3D).
static func rain_drop() -> Material:
	return _cached("rain_drop", func():
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.72, 0.82, 0.9, 0.24)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		return m)

## Punto suave radial (64²) para partículas.
static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Salpicadura en el piso (billboard de partículas, usa color de vértice para fade).
static func rain_splash() -> Material:
	return _cached("rain_splash", func():
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.8, 0.88, 0.95, 0.35)
		m.albedo_texture = _soft_dot()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.disable_receive_shadows = true
		return m)

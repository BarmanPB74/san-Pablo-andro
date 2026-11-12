class_name StreetLook
extends Node
## Dirección de arte técnica: "ciudad mojada tras la lluvia" (teal + ámbar + neón).
## Crea en _ready(): WorldEnvironment (cielo con nubes, tonemap ACES, glow con
## umbral, niebla de profundidad + altura, ajustes y LUT 3D de color), un
## DirectionalLight3D con sombras PSSM de 2 cortes, el anillo de montañas del
## valle, la lluvia (solo "rainy_night") y el post-proceso de pantalla.
##
## Uso: var look := StreetLook.new(); add_child(look); look.set_time_of_day("golden_hour")
## Solo funciones del renderer Mobile: sin SSR, SSAO, SSIL, SDFGI ni volumetric fog.

const SKY_SHADER := "res://look/sky_clouds.gdshader"
const PRESET_NAMES: Array[String] = ["overcast_day", "golden_hour", "rainy_night", "tinta_y_papel", "plastilina"]

## Cada preset: todos los números del look en un solo lugar para calibrar.
const PRESETS := {
	"overcast_day": {
		"sun_elev": 52.0, "sun_az": -35.0, "sun_color": Color(0.9, 0.95, 1.0), "sun_energy": 1.0,
		"shadow_opacity": 0.7, "shadow_blur": 2.0,
		"zenith": Color(0.3, 0.37, 0.43), "horizon": Color(0.66, 0.71, 0.73),
		"ground": Color(0.1, 0.12, 0.12), "cloud_light": Color(0.83, 0.86, 0.88),
		"cloud_dark": Color(0.36, 0.42, 0.46), "cloud_cover": 0.82, "sun_glow": 0.35,
		"sun_disk": 0.0, "silver": 1.0, "sky_energy": 1.0,
		"amb_color": Color(0.42, 0.52, 0.55), "amb_sky": 0.75, "amb_energy": 1.0,
		"fog_color": Color(0.56, 0.63, 0.66), "fog_density": 0.0045, "fog_sky": 0.3,
		"fog_height": 1.5, "fog_height_density": 0.04, "fog_scatter": 0.0, "fog_aerial": 0.25,
		"exposure": 1.1, "white": 6.0,
		"glow": 0.55, "glow_strength": 1.0, "glow_bloom": 0.0, "glow_threshold": 1.0,
		"contrast": 1.18, "saturation": 1.0, "brightness": 1.0,
		"lut_shadow": Color(-0.035, 0.01, 0.03), "lut_high": Color(1.04, 1.0, 0.92), "lut_amount": 1.0,
		"wetness": 0.7, "rain": 0.0, "reflect": Color(0.5, 0.56, 0.6),
		"haze": Color(0.58, 0.64, 0.67), "haze_base": 0.6, "haze_top": 0.35, "night": 0.0,
		"rain_fx": 0.0, "vignette": 0.3, "grain": 0.025, "aberration": 0.0015,
	},
	"golden_hour": {
		"sun_elev": 8.0, "sun_az": -100.0, "sun_color": Color(1.0, 0.6, 0.3), "sun_energy": 1.7,
		"shadow_opacity": 0.85, "shadow_blur": 1.5,
		"zenith": Color(0.24, 0.31, 0.42), "horizon": Color(0.95, 0.62, 0.38),
		"ground": Color(0.12, 0.1, 0.1), "cloud_light": Color(1.0, 0.7, 0.48),
		"cloud_dark": Color(0.3, 0.28, 0.35), "cloud_cover": 0.55, "sun_glow": 1.4,
		"sun_disk": 6.0, "silver": 2.0, "sky_energy": 1.0,
		"amb_color": Color(0.16, 0.42, 0.55), "amb_sky": 0.2, "amb_energy": 1.0,
		"fog_color": Color(0.62, 0.5, 0.42), "fog_density": 0.0035, "fog_sky": 0.25,
		"fog_height": 1.0, "fog_height_density": 0.03, "fog_scatter": 0.4, "fog_aerial": 0.35,
		"exposure": 1.2, "white": 6.0,
		"glow": 0.7, "glow_strength": 1.05, "glow_bloom": 0.02, "glow_threshold": 0.95,
		"contrast": 1.2, "saturation": 1.1, "brightness": 1.0,
		"lut_shadow": Color(-0.06, 0.02, 0.05), "lut_high": Color(1.06, 0.97, 0.84), "lut_amount": 1.0,
		"wetness": 0.5, "rain": 0.0, "reflect": Color(0.8, 0.58, 0.42),
		"haze": Color(0.78, 0.56, 0.42), "haze_base": 0.6, "haze_top": 0.3, "night": 0.0,
		"rain_fx": 0.0, "vignette": 0.35, "grain": 0.03, "aberration": 0.002,
	},
	"rainy_night": {
		"sun_elev": 38.0, "sun_az": 30.0, "sun_color": Color(0.55, 0.72, 0.9), "sun_energy": 0.35,
		"shadow_opacity": 0.6, "shadow_blur": 3.0,
		"zenith": Color(0.025, 0.04, 0.05), "horizon": Color(0.15, 0.18, 0.19),
		"ground": Color(0.02, 0.025, 0.03), "cloud_light": Color(0.3, 0.26, 0.24),
		"cloud_dark": Color(0.03, 0.04, 0.05), "cloud_cover": 0.92, "sun_glow": 0.0,
		"sun_disk": 0.0, "silver": 0.0, "sky_energy": 1.0,
		"amb_color": Color(0.2, 0.33, 0.4), "amb_sky": 0.3, "amb_energy": 1.6,
		"fog_color": Color(0.09, 0.13, 0.15), "fog_density": 0.01, "fog_sky": 0.25,
		"fog_height": 2.0, "fog_height_density": 0.08, "fog_scatter": 0.0, "fog_aerial": 0.0,
		"exposure": 2.2, "white": 6.0,
		"glow": 1.25, "glow_strength": 1.15, "glow_bloom": 0.05, "glow_threshold": 0.85,
		"contrast": 1.18, "saturation": 1.15, "brightness": 1.0,
		"lut_shadow": Color(-0.03, 0.012, 0.03), "lut_high": Color(1.05, 0.98, 0.88), "lut_amount": 1.0,
		"wetness": 1.0, "rain": 1.0, "reflect": Color(0.2, 0.26, 0.29),
		"haze": Color(0.06, 0.09, 0.1), "haze_base": 0.6, "haze_top": 0.45, "night": 1.0,
		"rain_fx": 0.85, "vignette": 0.45, "grain": 0.04, "aberration": 0.0025,
	},
	"tinta_y_papel": {
		# Ilustración melancólica: paleta apagada beige-oliva, sombras suaves, contorno de tinta y grano de papel.
		"sun_elev": 46.0, "sun_az": -40.0, "sun_color": Color(0.98, 0.95, 0.84), "sun_energy": 0.95,
		"shadow_opacity": 0.55, "shadow_blur": 3.5,
		"zenith": Color(0.62, 0.62, 0.52), "horizon": Color(0.80, 0.78, 0.66),
		"ground": Color(0.3, 0.29, 0.24), "cloud_light": Color(0.88, 0.86, 0.74),
		"cloud_dark": Color(0.6, 0.58, 0.48), "cloud_cover": 0.55, "sun_glow": 0.15,
		"sun_disk": 0.0, "silver": 0.3, "sky_energy": 1.0,
		"amb_color": Color(0.62, 0.6, 0.5), "amb_sky": 0.6, "amb_energy": 1.15,
		"fog_color": Color(0.78, 0.76, 0.64), "fog_density": 0.006, "fog_sky": 0.5,
		"fog_height": 1.5, "fog_height_density": 0.03, "fog_scatter": 0.0, "fog_aerial": 0.4,
		"exposure": 1.55, "white": 6.0,
		"glow": 0.2, "glow_strength": 0.8, "glow_bloom": 0.0, "glow_threshold": 1.1,
		"contrast": 1.12, "saturation": 0.38, "brightness": 1.0,
		"lut_shadow": Color(0.0, 0.0, -0.02), "lut_high": Color(1.04, 1.0, 0.88), "lut_amount": 1.0,
		"wetness": 0.15, "rain": 0.0, "reflect": Color(0.7, 0.68, 0.58),
		"haze": Color(0.78, 0.76, 0.64), "haze_base": 0.7, "haze_top": 0.4, "night": 0.0,
		"rain_fx": 0.0, "vignette": 0.4, "grain": 0.045, "aberration": 0.0,
		"ink": 0.6, "paper": 0.7,
	},
	"plastilina": {
		# Pueblo de plastilina stop-motion: anochecer morado, faroles ámbar, ladrillo frambuesa,
		# musgo verde y sombras violeta. Va con ClayStyle (materiales de arcilla) y desenfoque de maqueta.
		"sun_elev": 34.0, "sun_az": 35.0, "sun_color": Color(0.84, 0.86, 1.0), "sun_energy": 0.62,
		"shadow_opacity": 0.78, "shadow_blur": 2.5,
		"zenith": Color(0.1, 0.055, 0.19), "horizon": Color(0.42, 0.27, 0.5),
		"ground": Color(0.07, 0.045, 0.09), "cloud_light": Color(0.56, 0.42, 0.66),
		"cloud_dark": Color(0.17, 0.1, 0.25), "cloud_cover": 0.72, "sun_glow": 0.25,
		"sun_disk": 0.0, "silver": 0.7, "sky_energy": 1.0,
		"amb_color": Color(0.5, 0.5, 0.56), "amb_sky": 0.05, "amb_energy": 1.25,
		"fog_color": Color(0.3, 0.25, 0.4), "fog_density": 0.007, "fog_sky": 0.12,
		"fog_height": 1.2, "fog_height_density": 0.05, "fog_scatter": 0.0, "fog_aerial": 0.2,
		"exposure": 1.95, "white": 6.0,
		"glow": 0.7, "glow_strength": 1.0, "glow_bloom": 0.02, "glow_threshold": 1.0,
		"contrast": 1.1, "saturation": 1.08, "brightness": 1.0,
		"lut_shadow": Color(0.008, -0.004, 0.022), "lut_high": Color(1.05, 0.99, 0.9), "lut_amount": 1.0,
		"wetness": 0.05, "rain": 0.0, "reflect": Color(0.32, 0.22, 0.42),
		"haze": Color(0.34, 0.21, 0.42), "haze_base": 0.65, "haze_top": 0.4, "night": 1.0,
		"rain_fx": 0.0, "vignette": 0.5, "grain": 0.018, "aberration": 0.0, "vignette_color": Color(0.06, 0.02, 0.09),
		"dof_far": 60.0, "dof_far_t": 40.0, "dof_near": 0.0, "dof_amount": 0.012,
	},
}

@export var initial_preset := "overcast_day"
@export var enable_backdrop := true
@export var enable_rain := true
@export var enable_post_fx := true
@export var lut_size := 24               # resolución del LUT 3D (24³ ≈ 41 KB)
## ReflectionProbe que sigue a la cámara (por saltos): los charcos reflejan
## edificios y neones. Se recaptura solo al moverse > probe_snap metros.
@export var follow_reflection_probe := true
@export var probe_snap := 40.0

var world_env: WorldEnvironment
var environment: Environment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var backdrop: ValleyBackdrop
var rain_fx: RainFX
var post_fx: PostFX
var probe: ReflectionProbe
var current_preset := ""
var is_compatibility := false            # GL Compatibility (sin RenderingDevice)

var _lut_cache := {}


func _ready() -> void:
	is_compatibility = RenderingServer.get_rendering_device() == null
	_setup_shadows_global()
	_build_environment()
	_build_sun()
	if enable_backdrop:
		backdrop = ValleyBackdrop.new()
		backdrop.name = "ValleyBackdrop"
		add_child(backdrop)
	if enable_rain:
		rain_fx = RainFX.new()
		rain_fx.name = "Rain"
		add_child(rain_fx)
	if follow_reflection_probe:
		probe = ReflectionProbe.new()
		probe.name = "StreetProbe"
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.size = Vector3(160.0, 50.0, 160.0)
		probe.box_projection = false
		probe.enable_shadows = false
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		probe.max_distance = 300.0
		probe.intensity = 1.0
		add_child(probe)
	post_fx = PostFX.new()
	post_fx.name = "PostFX"
	post_fx.enabled = enable_post_fx
	add_child(post_fx)
	set_time_of_day(current_preset if current_preset != "" else initial_preset)


## Cambia el ambiente completo. preset: "overcast_day" | "golden_hour" | "rainy_night".
func set_time_of_day(preset: String) -> void:
	if not PRESETS.has(preset):
		push_warning("StreetLook: preset desconocido '%s', uso overcast_day" % preset)
		preset = "overcast_day"
	current_preset = preset
	if environment == null:
		return   # aún no está en el árbol: se aplica en _ready()
	_apply(PRESETS[preset])


func _process(_delta: float) -> void:
	if probe == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	var snapped_pos := Vector3(snappedf(c.x, probe_snap), maxf(c.y, 1.0) , snappedf(c.z, probe_snap))
	# a ~5 m del piso: los objetos cercanos no dominan el reflejo (sin box projection)
	snapped_pos.y = snappedf(snapped_pos.y, 4.0) + 4.0
	if probe.global_position.distance_squared_to(snapped_pos) > 1.0:
		probe.global_position = snapped_pos   # mover un probe UPDATE_ONCE lo recaptura


func get_time_of_day() -> String:
	return current_preset


## Activa/desactiva el post-proceso de pantalla (viñeta/grano/aberración).
func set_post_fx_enabled(v: bool) -> void:
	enable_post_fx = v
	if post_fx:
		post_fx.enabled = v


## Calidad baja para teléfonos calientes: sin post-fx, sombras más cortas, glow más barato.
func set_low_quality(v: bool) -> void:
	set_post_fx_enabled(not v)
	if sun:
		sun.directional_shadow_max_distance = 70.0 if v else 120.0
	if environment:
		environment.set_glow_level(1, 0.0 if v else 0.5)
		environment.set_glow_level(5, 0.0 if v else 0.35)


# ---------------------------------------------------------------- construcción

func _setup_shadows_global() -> void:
	# Atlas direccional 2048 con 16 bits: suficiente para 2 cortes en 120 m.
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	sky_material = ShaderMaterial.new()
	sky_material.shader = load(SKY_SHADER)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128     # reflejos del cielo baratos
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	environment.glow_enabled = true
	environment.glow_normalized = false
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_hdr_scale = 2.0
	environment.glow_hdr_luminance_cap = 12.0
	# niveles: 1-2 = halo apretado del tubo de neón, 3-5 = bloom amplio
	var levels := [0.0, 0.5, 0.8, 1.0, 0.7, 0.35, 0.0]
	for i in levels.size():
		environment.set_glow_level(i, levels[i])

	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL

	environment.adjustment_enabled = true

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = environment
	# Desenfoque de maqueta (solo presets con "dof_far"): lo lejano se ve como una miniatura filmada.
	world_env.camera_attributes = CameraAttributesPractical.new()
	add_child(world_env)


func _build_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_split_1 = 0.22        # primer corte a ~26 m (detalle cerca)
	sun.directional_shadow_blend_splits = false  # más barato en móvil
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_pancake_size = 20.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)


# ---------------------------------------------------------------- aplicar preset

func _apply(p: Dictionary) -> void:
	# --- luz principal ---
	sun.rotation_degrees = Vector3(-float(p.sun_elev), float(p.sun_az), 0.0)
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.shadow_opacity = p.shadow_opacity
	sun.shadow_blur = p.shadow_blur
	sun.shadow_enabled = float(p.sun_energy) > 0.05

	# --- cielo ---
	sky_material.set_shader_parameter("zenith_color", p.zenith)
	sky_material.set_shader_parameter("horizon_color", p.horizon)
	sky_material.set_shader_parameter("ground_color", p.ground)
	sky_material.set_shader_parameter("cloud_light", p.cloud_light)
	sky_material.set_shader_parameter("cloud_dark", p.cloud_dark)
	sky_material.set_shader_parameter("cloud_cover", p.cloud_cover)
	sky_material.set_shader_parameter("sun_glow", p.sun_glow)
	sky_material.set_shader_parameter("sun_disk", p.sun_disk)
	sky_material.set_shader_parameter("silver_lining", p.silver)
	sky_material.set_shader_parameter("energy", p.sky_energy)

	# --- luz ambiente (cielo teñido de teal) ---
	environment.ambient_light_color = p.amb_color
	environment.ambient_light_sky_contribution = p.amb_sky
	environment.ambient_light_energy = p.amb_energy

	# --- niebla de distancia + de altura ---
	environment.fog_light_color = p.fog_color
	environment.fog_light_energy = 1.0
	environment.fog_density = p.fog_density
	environment.fog_sky_affect = p.fog_sky
	environment.fog_height = p.fog_height
	environment.fog_height_density = p.fog_height_density
	environment.fog_sun_scatter = p.fog_scatter
	environment.fog_aerial_perspective = p.fog_aerial

	# --- tonemap / glow ---
	environment.tonemap_exposure = p.exposure
	environment.tonemap_white = p.white
	environment.glow_intensity = p.glow
	environment.glow_strength = p.glow_strength
	environment.glow_bloom = p.glow_bloom
	# Compatibility (GL) trabaja en LDR: el umbral HDR debe ser menor.
	environment.glow_hdr_threshold = float(p.glow_threshold) * (0.8 if is_compatibility else 1.0)

	# --- ajustes + LUT 3D (sombras → teal, altas luces → ámbar) ---
	environment.adjustment_brightness = p.brightness
	environment.adjustment_contrast = p.contrast
	environment.adjustment_saturation = p.saturation
	environment.adjustment_color_correction = _get_lut(current_preset, p)

	# --- desenfoque tipo maqueta (stop-motion) ---
	var ca := world_env.camera_attributes as CameraAttributesPractical
	if ca:
		var far := float(p.get("dof_far", 0.0))
		ca.dof_blur_far_enabled = far > 0.0
		ca.dof_blur_near_enabled = far > 0.0 and float(p.get("dof_near", 0.0)) > 0.0
		if far > 0.0:
			ca.dof_blur_far_distance = far
			ca.dof_blur_far_transition = float(p.get("dof_far_t", 20.0))
			ca.dof_blur_near_distance = float(p.get("dof_near", 1.0))
			ca.dof_blur_near_transition = float(p.get("dof_near_t", 0.8))
			ca.dof_blur_amount = float(p.get("dof_amount", 0.06))

	# --- materiales globales (charcos, reflejo de cielo, luces de laderas) ---
	Palette.set_weather(p.wetness, p.rain, p.reflect, p.night)
	if backdrop:
		backdrop.set_look(p.haze, p.haze_base, p.haze_top, p.night)
	if rain_fx:
		rain_fx.set_intensity(p.rain_fx)
	if post_fx:
		post_fx.set_params(p.vignette, p.grain, p.aberration, p.get("vignette_color", Color(0.0, 0.015, 0.02)))
		post_fx.set_ink(float(p.get("ink", 0.0)), float(p.get("paper", 0.0)))


# ---------------------------------------------------------------- LUT 3D

func _get_lut(key: String, p: Dictionary) -> Texture3D:
	if _lut_cache.has(key):
		return _lut_cache[key]
	var tex := build_split_tone_lut(lut_size, p.lut_shadow, p.lut_high, p.lut_amount)
	_lut_cache[key] = tex
	return tex


## LUT 3D de "split toning" generado por código.
## shadow_offset: color sumado en sombras (p. ej. (-0.03, 0.01, 0.03) = teal).
## high_mult: multiplicador en altas luces (p. ej. (1.05, 0.98, 0.88) = ámbar).
## Protege los colores muy saturados (neón) para que no se ensucien.
static func build_split_tone_lut(n: int, shadow_offset: Color, high_mult: Color, amount := 1.0) -> ImageTexture3D:
	var images: Array[Image] = []
	var inv := 1.0 / float(n)
	for b in n:
		var data := PackedByteArray()
		data.resize(n * n * 3)
		var idx := 0
		var fb := (b + 0.5) * inv
		for g in n:
			var fg := (g + 0.5) * inv
			for r in n:
				var fr := (r + 0.5) * inv
				var lum := fr * 0.2126 + fg * 0.7152 + fb * 0.0722
				var chroma := maxf(fr, maxf(fg, fb)) - minf(fr, minf(fg, fb))
				var protect := 1.0 - 0.65 * smoothstep(0.35, 0.85, chroma)
				var ws := (1.0 - smoothstep(0.0, 0.55, lum)) * amount * protect
				var wh := smoothstep(0.4, 1.0, lum) * amount * protect
				var cr := fr + shadow_offset.r * ws
				var cg := fg + shadow_offset.g * ws
				var cb := fb + shadow_offset.b * ws
				cr = lerpf(cr, cr * high_mult.r, wh)
				cg = lerpf(cg, cg * high_mult.g, wh)
				cb = lerpf(cb, cb * high_mult.b, wh)
				data[idx] = int(clampf(cr, 0.0, 1.0) * 255.0 + 0.5)
				data[idx + 1] = int(clampf(cg, 0.0, 1.0) * 255.0 + 0.5)
				data[idx + 2] = int(clampf(cb, 0.0, 1.0) * 255.0 + 0.5)
				idx += 3
		images.append(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, data))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, n, n, n, false, images)
	return tex

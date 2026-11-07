class_name MatAsphalt
extends RefCounted
## Familia ASPHALT (Fase 1): asfalto con texturas PBR + atlas de pintura vial.
## Texturas: art/tex/asphalt/ (generadas por tools/texgen/asphalt.py).
##
## Las calles usan look/wet_asphalt.gdshader con use_tex = true: charcos, humedad y ondas de
## lluvia se combinan con la textura (proyección en XZ de mundo, sin UVs). Los parámetros por
## defecto replican Palette.wet_asphalt(); el clima se toma de Palette.weather_* al crear.
## OJO integrador: Palette.set_weather() solo actualiza los materiales de Palette._cache; llama
## también MatAsphalt.sync_weather() (o mete estos materiales en ese cache).

const WET_SHADER := "res://look/wet_asphalt.gdshader"
const TEX := "res://art/tex/asphalt/"

## Atlas road_decals (1024 px = 2.56 m, 1 px = 2.5 mm). Rect2 en UV (0..1).
## La vía corre a lo largo de V; flechas y textos se leen con el conductor llegando desde V=1.
const DECAL_UV := {
	"line_yellow": Rect2(0.0 / 1024, 0.0, 80.0 / 1024, 1.0),          # continua amarilla 12 cm, tilea en V
	"dash_white": Rect2(80.0 / 1024, 0.0, 80.0 / 1024, 1.0),          # un trazo de discontinua 12 cm x 2.4 m
	"line_white": Rect2(160.0 / 1024, 0.0, 80.0 / 1024, 1.0),         # continua blanca 12 cm, tilea en V
	"zebra_bar": Rect2(256.0 / 1024, 0.0, 768.0 / 1024, 320.0 / 1024),  # franja de cebra (largo en U)
	"arrow_straight": Rect2(256.0 / 1024, 320.0 / 1024, 192.0 / 1024, 704.0 / 1024),
	"arrow_turn": Rect2(448.0 / 1024, 320.0 / 1024, 256.0 / 1024, 704.0 / 1024),  # derecha; espejar U = izquierda
	"num_30": Rect2(704.0 / 1024, 320.0 / 1024, 320.0 / 1024, 352.0 / 1024),
	"text_pare": Rect2(704.0 / 1024, 672.0 / 1024, 320.0 / 1024, 352.0 / 1024),
}
## Tamaño recomendado del quad en metros (ancho X, largo en sentido de la vía).
## Líneas y cebra a escala 1:1 del atlas; flechas y textos estirados en la vía (como en la realidad,
## para que se lean en perspectiva).
const DECAL_SIZE_M := {
	"line_yellow": Vector2(0.20, 2.56),    # el ancho visible de la línea es 0.12 m
	"dash_white": Vector2(0.20, 2.56),     # dejar ~3.5 m de espacio entre trazos
	"line_white": Vector2(0.20, 2.56),
	"zebra_bar": Vector2(1.92, 0.80),      # ¡X = sentido de la vía! franja 1.8 x 0.5 m; repetir cada 1.0 m a lo ancho de la calle
	"arrow_straight": Vector2(0.95, 3.5),
	"arrow_turn": Vector2(1.25, 3.5),
	"num_30": Vector2(1.6, 3.2),
	"text_pare": Vector2(2.4, 2.6),
}

static var _cache := {}


static func _wet_tex(key: String, base: String, tile_m: float, params: Dictionary) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(WET_SHADER)
	for k in params:
		m.set_shader_parameter(k, params[k])
	m.set_shader_parameter("use_tex", true)
	m.set_shader_parameter("tex_albedo", load(base + "_albedo.png"))
	m.set_shader_parameter("tex_normal", load(base + "_normal.png"))
	m.set_shader_parameter("tex_orm", load(base + "_orm.png"))
	m.set_shader_parameter("tex_tile_m", tile_m)
	m.set_shader_parameter("wetness", Palette.weather_wetness)
	m.set_shader_parameter("rain", Palette.weather_rain)
	m.set_shader_parameter("sky_reflection", Palette.weather_sky)
	_cache[key] = m
	return m


## Copia el clima global (Palette.weather_*) a los materiales mojados de esta familia.
static func sync_weather() -> void:
	for k in _cache:
		var m = _cache[k]
		if m is ShaderMaterial:
			m.set_shader_parameter("wetness", Palette.weather_wetness)
			m.set_shader_parameter("rain", Palette.weather_rain)
			m.set_shader_parameter("sky_reflection", Palette.weather_sky)


## Calzada principal, asfalto NUEVO oscuro con agregado fino (como la foto 3), mojado con charcos.
## tile_m = 4.0 (1024 px). Para vías recién pavimentadas y avenidas.
static func asphalt_new() -> ShaderMaterial:
	return _wet_tex("new", TEX + "asphalt_new", 4.0, {
		"puddle_color": Color(0.02, 0.025, 0.03),
		"puddle_coverage": 0.6,
		"dry_roughness": 0.8,
		"damp_roughness": 0.4,
		"tex_normal_strength": 1.0,
	})


## Calzada VIEJA: asfalto gris oxidado con grietas finas, grietas selladas con brea, parches de
## reparación más oscuros y manchas de aceite. tile_m = 6.0 (1024 px). Calles de barrio, callejones,
## parqueaderos, bordes de vía. Más charcos (pavimento irregular).
static func asphalt_worn() -> ShaderMaterial:
	return _wet_tex("worn", TEX + "asphalt_worn", 6.0, {
		"puddle_color": Color(0.02, 0.025, 0.03),
		"puddle_coverage": 0.7,
		"dry_roughness": 0.85,
		"damp_roughness": 0.45,
		"tex_normal_strength": 1.0,
	})


## Versión SECA sin shader (ORMMaterial3D triplanar de mundo) por si se necesita barata o sin clima.
## tile_m = 4.0 (nuevo) / 6.0 (gastado).
static func asphalt_new_dry() -> Material:
	return TexMat.pbr(TEX + "asphalt_new", {"tile_m": 4.0})


static func asphalt_worn_dry() -> Material:
	return TexMat.pbr(TEX + "asphalt_worn", {"tile_m": 6.0})


## Pintura vial (atlas RGBA): para QUADS planos con UV (PlaneMesh/QuadMesh) puestos ~1-2 cm sobre
## la calzada; usar DECAL_UV para la sub-región y DECAL_SIZE_M para el tamaño. Sin tileo triplanar.
## Alpha mezclada (pintura gastada deja ver el asfalto), rugosidad algo baja (pintura + humedad).
## Recomendado en el MeshInstance3D: cast_shadow = OFF.
static func road_decals() -> Material:
	if _cache.has("decals"):
		return _cache["decals"]
	var base: ORMMaterial3D = TexMat.pbr(TEX + "road_decals", {"triplanar": false, "rough_add": -0.15})
	var m := base.duplicate() as ORMMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	m.render_priority = 1
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.normal_scale = 0.6
	_cache["decals"] = m
	return m


## Ayuda: QuadMesh horizontal (normal +Y) ya mapeado a una región del atlas. Usar con road_decals().
## El largo del quad (size.y) va a lo largo de -Z local (adelante); rotar el MeshInstance3D con la vía.
static func decal_mesh(name: String, size := Vector2.ZERO) -> ArrayMesh:
	var r: Rect2 = DECAL_UV[name]
	var sz: Vector2 = size if size != Vector2.ZERO else DECAL_SIZE_M[name]
	var hx := sz.x * 0.5
	var hz := sz.y * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	# V=0 (arriba del atlas) = adelante (-Z)
	var v := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var uv := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(v[i])
	st.generate_tangents()
	return st.commit()

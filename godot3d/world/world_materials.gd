class_name WorldMaterials
extends RefCounted
## Materiales extra del mundo que Palette (dueño: agente LOOK) todavía no tiene.
## Mismo patrón de caché que Palette. Si LOOK agrega equivalentes, se puede migrar aquí.

static var _cache := {}


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


static func _glow(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := _std(albedo, 0.4)
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	return m


## Pintura vial blanca (pasos peatonales, líneas de carril).
static func paint_white() -> Material:
	return _cached("paint_white", func(): return _std(Color(0.88, 0.88, 0.86), 0.6))

## Fondo oscuro de los avisos de locales.
static func sign_panel() -> Material:
	return _cached("sign_panel", func(): return _std(Color(0.05, 0.05, 0.06), 0.5, 0.3))

## Interior iluminado de un local abierto (cálido, emisión suave).
static func shop_interior() -> Material:
	return _cached("shop_interior", func(): return _glow(Color(0.55, 0.45, 0.32), Color(1.0, 0.8, 0.55), 0.45))

## Persiana metálica de local cerrado.
static func shutter() -> Material:
	return _cached("shutter", func(): return _std(Color(0.4, 0.41, 0.43), 0.5, 0.6))

## Toldos de lona (0..4).
static func awning(variant := 0) -> Material:
	var cols := [Color(0.62, 0.1, 0.1), Color(0.08, 0.38, 0.22), Color(0.1, 0.22, 0.52),
		Color(0.85, 0.45, 0.08), Color(0.75, 0.7, 0.2)]
	var i: int = posmod(variant, cols.size())
	return _cached("awning_%d" % i, func(): return _std(cols[i], 0.9))

## Muros de la iglesia (crema neorrománico).
static func church_wall() -> Material:
	return _cached("church_wall", func(): return _std(Color(0.86, 0.8, 0.68), 0.9))

## Vitral del rosetón: emisión tenue.
static func rosette() -> Material:
	return _cached("rosette", func(): return _glow(Color(0.35, 0.18, 0.35), Color(0.95, 0.55, 0.35), 0.8))

## Carátula del reloj de la torre.
static func clock_face() -> Material:
	return _cached("clock_face", func(): return _glow(Color(0.92, 0.9, 0.82), Color(1.0, 0.95, 0.8), 0.5))

## Huecos oscuros (portales, campanario, ventanas profundas).
static func dark_opening() -> Material:
	return _cached("dark_opening", func(): return _std(Color(0.025, 0.025, 0.03), 0.95))

## Poste de concreto de la red eléctrica.
static func pole_concrete() -> Material:
	return _cached("pole_concrete", func(): return _std(Color(0.63, 0.62, 0.6), 0.85))

## Azotea plana (impermeabilizante gris oscuro).
static func roof_flat() -> Material:
	return _cached("roof_flat", func(): return _std(Color(0.3, 0.29, 0.28), 0.9))

static func hydrant() -> Material:
	return _cached("hydrant", func(): return _std(Color(0.85, 0.62, 0.05), 0.5))

static func bin_green() -> Material:
	return _cached("bin_green", func(): return _std(Color(0.08, 0.33, 0.15), 0.6))

static func cone_orange() -> Material:
	return _cached("cone_orange", func(): return _std(Color(0.95, 0.33, 0.05), 0.55))

## Bombillo de semáforo apagado.
static func signal_off() -> Material:
	return _cached("signal_off", func(): return _std(Color(0.06, 0.06, 0.05), 0.3))

## Carritos de comida callejera (0..3).
static func cart(variant := 0) -> Material:
	var cols := [Color(0.85, 0.15, 0.12), Color(0.95, 0.75, 0.1), Color(0.15, 0.45, 0.8), Color(0.2, 0.6, 0.3)]
	var i: int = posmod(variant, cols.size())
	return _cached("cart_%d" % i, func(): return _std(cols[i], 0.45, 0.2))

## Follaje de guayacán florecido (amarillo / rosado), típico de Medellín.
static func blossom(pink := false) -> Material:
	if pink:
		return _cached("blossom_pink", func(): return _std(Color(0.78, 0.35, 0.55), 0.9))
	return _cached("blossom_yellow", func(): return _std(Color(0.85, 0.7, 0.1), 0.9))

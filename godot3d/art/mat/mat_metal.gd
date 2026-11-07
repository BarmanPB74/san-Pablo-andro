class_name MatMetal
extends RefCounted
## Familia METAL (F1-08): rejas, postes, celosías, bolardos y señales de tránsito.
## Texturas en res://art/tex/metal/ generadas por tools/texgen/metal.py.

const DIR := "res://art/tex/metal/"

## Orden de celdas del atlas de señales (4x4, fila a fila, de arriba-izquierda).
const SIGNS: PackedStringArray = [
	"pare", "ceda_el_paso", "no_parquear", "velocidad_30",
	"baje_en_2a", "peligro_curva", "paso_peatonal", "una_via",
	"doble_sentido", "prohibido_girar", "calle_55_peru", "carrera_38",
	"calle_54_caracas", "carrera_39", "calle_58_echeverri", "carrera_43_girardot",
]

## Lado recomendado (m) del QuadMesh CUADRADO de cada señal: la forma la recorta el alpha.
## Las placas rectangulares ocupan la franja central (~52 % de alto) del cuadrado.
const SIGN_SIZE_M: PackedFloat32Array = [
	0.75, 0.90, 0.75, 0.75,
	0.75, 0.75, 0.75, 0.80,
	0.80, 0.75, 0.70, 0.70,
	0.70, 0.70, 0.70, 0.70,
]

static var _sign_cache := {}


## Rejas bajas del parque, barandas, marcos de hierro pintados de verde.
## Esmalte verde gastado con desconchones, imprimación y óxido chorreado. tile_m = 1.0 (triplanar).
static func green_paint(opts := {}) -> Material:
	return TexMat.pbr(DIR + "pintura_verde", _merge({"tile_m": 1.0}, opts))


## Postes de semáforo, soportes de señales, tubos de baranda, cajas eléctricas metálicas.
## Acero galvanizado con lentejuelas de zinc, óxido blanco y chorreados. tile_m = 1.0 (triplanar).
static func galvanized(opts := {}) -> Material:
	return TexMat.pbr(DIR + "galvanizado", _merge({"tile_m": 1.0}, opts))


## Poste de concreto centrifugado (alumbrado/energía) con afiches viejos y grafitis.
## UV CILÍNDRICAS (triplanar = false): U = una vuelta completa, V = 1.8 m de alto por repetición.
## Usar sobre CylinderMesh (ver nota de UV abajo). height_m = altura del cilindro.
## Nota CylinderMesh de Godot 4.3: el costado usa U 0..1 alrededor y V 0..0.5 (las tapas usan 0.5..1).
## Por eso la escala V se multiplica por 2: uv_scale.y = 2 * round(height/1.8).
static func concrete_pole(height_m := 9.0, opts := {}) -> Material:
	var reps := maxf(1.0, round(height_m / 1.8))
	return TexMat.pbr(DIR + "poste_concreto", _merge(
		{"triplanar": false, "uv_scale": Vector3(1.0, reps * CYL_SIDE_V_FACTOR, 1.0)}, opts))

## El costado de CylinderMesh ocupa V 0..0.5 (verificado en Godot 4.3 headless), de ahí el factor 2.
const CYL_SIDE_V_FACTOR := 2.0


## Variante triplanar del concreto del poste (para cajas/BoxMesh o postes prismáticos). tile_m = 1.8.
static func concrete_pole_triplanar(opts := {}) -> Material:
	return TexMat.pbr(DIR + "poste_concreto", _merge({"tile_m": 1.8}, opts))


## Celosía de lámina de corte láser (fachadas de locales, cerramientos, puertas de reja decorativas).
## RGBA con alpha scissor, sin culling. Patrón geométrico-floral, módulo de 25 cm. tile_m = 2.0 (triplanar).
## Para paneles planos es mejor un QuadMesh/BoxMesh delgado; el triplanar mapea por la cara mayor.
static func laser_lattice(opts := {}) -> Material:
	return TexMat.pbr(DIR + "celosia", _merge(
		{"tile_m": 2.0, "transparent": true, "cull_disabled": true}, opts))


## Bolardos, tubos de protección, defensas: pintura amarilla de tráfico con golpes y óxido. tile_m = 1.0.
static func yellow_paint(opts := {}) -> Material:
	return TexMat.pbr(DIR + "pintura_amarilla", _merge({"tile_m": 1.0}, opts))


## Rayado negro-amarillo a 45° de obstáculos (bases de postes, barreras, columnas de parqueadero).
## Franjas de 12.5 cm. tile_m = 1.0 (triplanar).
static func hazard_stripes(opts := {}) -> Material:
	return TexMat.pbr(DIR + "amarilla_rayado", _merge({"tile_m": 1.0}, opts))


## Señal de tránsito del atlas 4x4 (celdas de 256 px). index = posición en SIGNS (0..15).
## Material NO triplanar con uv1_scale = (0.25, 0.25) y uv1_offset = celda: aplicar sobre un QuadMesh
## cuadrado (UV 0..1, origen arriba-izquierda) de lado SIGN_SIZE_M[index]. Alpha scissor recorta la forma.
## Cara trasera: poner un segundo quad/lámina con galvanized() (el reverso de las señales es aluminio).
## Si se usa otra malla con UV 0..1 propias, el mapeo de la celda es: uv_atlas = uv * 0.25 + (col, fila) * 0.25.
static func sign(index: int) -> Material:
	index = clampi(index, 0, SIGNS.size() - 1)
	if _sign_cache.has(index):
		return _sign_cache[index]
	var base: ORMMaterial3D = TexMat.pbr(DIR + "senales", {"triplanar": false, "transparent": true})
	var m: ORMMaterial3D = base.duplicate()
	m.uv1_scale = Vector3(0.25, 0.25, 1.0)
	m.uv1_offset = Vector3(float(index % 4) * 0.25, float(index / 4) * 0.25, 0.0)
	# las celdas tienen 8 px de margen transparente; el mipmap no sangra entre señales
	_sign_cache[index] = m
	return m


## Igual que sign() pero por nombre ("pare", "calle_55_peru", ...).
static func sign_named(sign_name: String) -> Material:
	var i := SIGNS.find(sign_name)
	return MatMetal.sign(maxi(i, 0))   # calificado: `sign` a secas es la función global de GDScript


## Material completo del atlas (UV 0..1 = todo el atlas), para mallas con UV ya preparadas por celda.
static func sign_atlas() -> Material:
	return TexMat.pbr(DIR + "senales", {"triplanar": false, "transparent": true})


static func _merge(defaults: Dictionary, opts: Dictionary) -> Dictionary:
	var d := defaults.duplicate()
	d.merge(opts, true)
	return d

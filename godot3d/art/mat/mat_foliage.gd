class_name MatFoliage
extends RefCounted
## Materiales de follaje (familia "foliage", texturas en res://art/tex/foliage/, generadas por
## tools/texgen/foliage.py). Dos tipos:
##  - TARJETAS (quads cruzados, UV 0..1 del quad mapeadas a una celda del atlas): albedo RGBA con
##    alpha scissor 0.5, doble cara, sin triplanar, y backlight verde amarillento para simular la
##    luz que atraviesa la hoja (translucidez barata, válida en renderer Mobile).
##  - SUPERFICIES OPACAS tileables (hiedra de suelo, cajas de seto) con triplanar en mundo.
## Atlases 2x2: usa cell_uv(i) para el Rect2 UV de la celda i (0 = arriba-izq, 1 = arriba-der,
## 2 = abajo-izq, 3 = abajo-der). En las plantas de jardín la base de la planta está en el borde
## inferior de la celda; en la copa los ramilletes se centran (las ramas salen por abajo).

const BASE := "res://art/tex/foliage/"
const BACKLIGHT := Color(0.42, 0.52, 0.16)   # verde amarillento suave (luz trasmitida)

static var _cache := {}


## Rect2 en UV de la celda i de un atlas 2x2 (i = 0..3, fila mayor).
static func cell_uv(i: int) -> Rect2:
	return Rect2(Vector2(float(i % 2), float(i / 2)) * 0.5, Vector2(0.5, 0.5))


## Material de tarjeta común: TexMat.pbr(transparent, doble cara, sin triplanar) + backlight.
## Se duplica para no alterar el material cacheado en TexMat.
static func _card(name: String, backlight: Color = BACKLIGHT, tint: Color = Color.WHITE) -> Material:
	var key := name + str(backlight) + str(tint)
	if _cache.has(key):
		return _cache[key]
	var base_m: ORMMaterial3D = TexMat.pbr(BASE + name, {
		"transparent": true,
		"cull_disabled": true,
		"triplanar": false,
		"tint": tint,
	})
	var m: ORMMaterial3D = base_m.duplicate()
	m.backlight_enabled = true
	m.backlight = backlight
	_cache[key] = m
	return m


## Copa de árbol grande (samán / leguminosa de hoja fina, y árbol de hoja oval oscura).
## Atlas 1024 2x2: 0 samán denso, 1 samán colgante ralo, 2 samán soleado amarillento,
## 3 hoja oval oscura (tipo urapán/laurel de la ref. 6). Celda ~1.2 m: quads de 1.0-1.5 m.
## No usa tile_m (UV del quad). Úsese en MultiMesh de quads cruzados dentro de la copa.
static func canopy_cards(tint: Color = Color.WHITE) -> Material:
	return _card("canopy_atlas", BACKLIGHT, tint)


## Fronda de palma plumosa (areca / palma real joven), vista superior, 512 x 1024 (ancho x alto).
## Base del raquis en v = 1 (abajo, centro), punta en v = 0. Quad ~1.2 m x 2.4 m, rotado
## e inclinado hacia afuera desde la corona; 8-12 frondas por palma. Sin tile_m.
static func palm_frond(tint: Color = Color.WHITE) -> Material:
	return _card("palm_frond", Color(0.45, 0.55, 0.18), tint)


## Plantas de jardín (jardineras, separadores, bordes de andén), atlas 1024 2x2, vistas de lado:
## 0 crotón moteado verde-amarillo, 1 helecho, 2 heliconia / hoja ancha, 3 planta de hoja morada.
## Celda ~1 m: quads cruzados de 0.6-1.2 m apoyados en el suelo por el borde inferior. Sin tile_m.
static func garden_plants(tint: Color = Color.WHITE) -> Material:
	return _card("garden_atlas", BACKLIGHT, tint)


## Hiedra / cobertura de suelo vista superior (jardineras, bajo árboles, taludes, separadores).
## Opaca y tileable, triplanar en mundo, tile_m = 1.0 m.
static func ivy_ground() -> Material:
	return TexMat.pbr(BASE + "ivy_ground", {"tile_m": 1.0, "triplanar": true})


## Seto denso recortado (cajas de seto del parque y antejardines, setos redondos).
## Opaco y tileable, triplanar en mundo, tile_m = 1.0 m. `tint` permite setos más amarillos/oscuros.
static func hedge(tint: Color = Color.WHITE) -> Material:
	return TexMat.pbr(BASE + "hedge", {"tile_m": 1.0, "triplanar": true, "tint": tint})

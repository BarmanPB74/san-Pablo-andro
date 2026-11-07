class_name MatBrick
extends RefCounted
## Materiales de ladrillo de fachada medellinense (familia "brick", Fase 1).
## Texturas generadas por tools/texgen/brick.py en res://art/tex/brick/.
## Todas usan proyección triplanar en espacio de mundo (1 tile = tile_m x tile_m metros).
## `tint` multiplica el albedo para variar edificios sin texturas nuevas
## (p. ej. Color(1.05, 0.97, 0.92) más claro/amarillento, Color(0.9, 0.85, 0.85) más oscuro).
## `rough_add` (+ seco / - mojado) se pasa directo a TexMat.

const DIR := "res://art/tex/brick/"


static func _opts(tile_m: float, tint: Color, rough_add: float, extra := {}) -> Dictionary:
	var o := {"tile_m": tile_m}
	if tint != Color.WHITE:
		o["tint"] = tint
	if rough_add != 0.0:
		o["rough_add"] = rough_add
	o.merge(extra, true)
	return o


## Muros de fachada de ladrillo a la vista naranja-terracota (edificios residenciales de Boston).
## Aparejo de soga, ladrillo 23.4 x 6.5 cm, junta gris 1 cm rehundida. tile_m = 1.95 (26 hiladas x 8 piezas).
static func fachada_naranja(tint := Color.WHITE, rough_add := 0.0) -> Material:
	return TexMat.pbr(DIR + "fachada_naranja", _opts(1.95, tint, rough_add))


## Fachadas antiguas/descuidadas: ladrillo más rojizo y oscuro, eflorescencias blancas, chorreaduras de
## lluvia y verdín en juntas. Misma geometría que fachada_naranja. tile_m = 1.95.
static func fachada_vieja(tint := Color.WHITE, rough_add := 0.0) -> Material:
	return TexMat.pbr(DIR + "fachada_vieja", _opts(1.95, tint, rough_add))


## Ladrillo parado ("petaco"/sardinel, aparejo apilado vertical): dinteles sobre ventanas, remates de muro,
## antepechos de balcón, bordes de jardineras. Piezas de canto 6.5 cm, 24.4 cm de alto. tile_m = 0.975
## (13 piezas en horizontal x 4 filas).
static func petaco(tint := Color.WHITE, rough_add := 0.0) -> Material:
	return TexMat.pbr(DIR + "petaco", _opts(0.975, tint, rough_add))


## Calado / celosía de ladrillo con huecos (alpha scissor, doble cara): cerramientos de escaleras,
## patios de ropas y cuartos de basura de los edificios. Huecos de 8 x ~8.5 cm, paso 30 cm.
## tile_m = 0.90 (12 hiladas x 3 piezas). Usar sobre un BoxMesh delgado (~0.12 m) o un QuadMesh.
static func calado(tint := Color.WHITE, rough_add := 0.0) -> Material:
	return TexMat.pbr(DIR + "calado", _opts(0.90, tint, rough_add, {"transparent": true, "cull_disabled": true}))


## Franja de placa de concreto de entrepiso (borde de losa entre pisos de ladrillo, frentes de balcón,
## voladizos): pañete/concreto gris con marcas de formaleta horizontales, goterón (ranura) y chorreaduras
## de mugre debajo. tile_m = 1.0; el goterón es una ranura horizontal que se repite cada 1 m en vertical
## (a 0.88 del tile), así que en franjas de ~0.3 m puede no verse: es un detalle, el resto del tile
## funciona como concreto de losa genérico.
static func losa_entrepiso(tint := Color.WHITE, rough_add := 0.0) -> Material:
	return TexMat.pbr(DIR + "losa_entrepiso", _opts(1.0, tint, rough_add))


## Variantes rápidas de tinte para que no todos los edificios se vean iguales.
## i: índice del edificio (cualquier entero); devuelve fachada naranja o vieja con tinte determinista.
static func fachada_variante(i: int) -> Material:
	var tints: Array[Color] = [
		Color(1.0, 1.0, 1.0),
		Color(1.06, 0.98, 0.92),   # más claro/amarillento (ladrillo de Itagüí)
		Color(0.94, 0.88, 0.86),   # más oscuro
		Color(1.02, 0.93, 0.90),   # más rosado
	]
	var t: Color = tints[absi(i) % tints.size()]
	if absi(i) % 5 == 4:
		return fachada_vieja(t)
	return fachada_naranja(t)

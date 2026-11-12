class_name MatStone
extends RefCounted
## Familia "stone": piedras y esculturas (Parque de Boston, iglesia, bancas).
## Texturas generadas por tools/texgen/stone.py en art/tex/stone/.
## Todas en triplanar de mundo (BoxMesh del mapa). En la imagen "arriba" = arriba del mundo:
## los escurrimientos del mármol/bronce/sillar bajan en las caras verticales.
## Variantes "wet": rough_add negativo (lluvia, look ciudad mojada).

const BASE := "res://art/tex/stone/"


## Enchape de PIZARRA negra-gris en lajas irregulares con mortero claro.
## Jardineras/muretes del Parque de Boston (ref. 4). tile_m = 1.5 (lajas ~18 cm).
static func pizarra(wet := false) -> Material:
	return TexMat.pbr(BASE + "pizarra_lajas", {"tile_m": 1.5, "rough_add": -0.35 if wet else 0.0})


## LAJA de piedra gris en piezas grandes irregulares con juntas anchas de tierra/musgo: piso de las
## plazoletas del Parque de Boston (fuente y tarima). tile_m = 3.0.
static func laja_plaza(wet := false) -> Material:
	if ClayStyle.enabled:
		return MatPaving.brick_sidewalk()   # plazoletas de ladrillo en modo plastilina
	return TexMat.pbr(BASE + "laja_irregular", {"tile_m": 3.0, "rough_add": -0.3 if wet else 0.0})


## GRANITO gris claro moteado, acabado abujardado. Bancas, bordes de jardinera, bordillos,
## escalones (ref. 1). tile_m = 1.0.
static func granito(wet := false) -> Material:
	return TexMat.pbr(BASE + "granito_abujardado", {"tile_m": 1.0, "rough_add": -0.3 if wet else 0.0})


## Granito más oscuro/sucio (misma textura con tinte) para bordillos muy transitados.
## tile_m = 1.0.
static func granito_sucio() -> Material:
	return TexMat.pbr(BASE + "granito_abujardado", {"tile_m": 1.0, "tint": Color(0.82, 0.81, 0.79)})


## MÁRMOL blanco con vetas grises suaves y pátina urbana (escurrimientos oscuros).
## Pedestal del monumento del Parque de Boston (refs. 2 y 5), placas conmemorativas. tile_m = 2.0.
static func marmol() -> Material:
	return TexMat.pbr(BASE + "marmol_blanco", {"tile_m": 2.0})


## Mármol con más suciedad (tinte gris cálido) para zócalos/partes bajas del pedestal y
## bajo molduras: usarlo en el cuerpo inferior del pedestal. tile_m = 2.0.
static func marmol_sucio() -> Material:
	return TexMat.pbr(BASE + "marmol_blanco", {"tile_m": 2.0, "tint": Color(0.80, 0.79, 0.76)})


## SILLAR de arenisca beige en hiladas (~33 cm, sillares 55-110 cm, junta ~1 cm).
## Muros de la iglesia neorrománica, zócalos de piedra. tile_m = 3.0.
static func sillar(wet := false) -> Material:
	return TexMat.pbr(BASE + "sillar_arenisca", {"tile_m": 3.0, "rough_add": -0.25 if wet else 0.0})


## BRONCE de escultura: bronce oscuro, verdigrís en zonas expuestas y escurrimientos,
## manchas pulidas por roce (ORM.B = metal alto salvo en el verdigrís).
## Estatua del Parque de Boston, placas, bustos. tile_m = 1.0 (en estatuas pequeñas usar 0.5).
static func bronce(tile_m := 1.0) -> Material:
	return TexMat.pbr(BASE + "bronce_patina", {"tile_m": tile_m})


## CANTO RODADO (piedra de río) incrustado en concreto. Bordes de jardín, franjas
## decorativas de andén, base de fuentes y alcorques. tile_m = 1.0.
static func canto_rodado(wet := false) -> Material:
	return TexMat.pbr(BASE + "canto_rodado", {"tile_m": 1.0, "rough_add": -0.3 if wet else 0.0})

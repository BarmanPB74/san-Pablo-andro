class_name MatPlaster
extends RefCounted
## Familia "plaster": fachadas pintadas, concreto y techos (texturas en art/tex/plaster/,
## generadas por tools/texgen/plaster.py). Todas usan triplanar en espacio de mundo por defecto.

const _B := "res://art/tex/plaster/"

## Mismos 6 tonos antioqueños de Palette.stucco(variant) (crema, terracota, azul, ocre, verde, gris).
const HOUSE_TINTS: Array[Color] = [Color(0.78, 0.74, 0.64), Color(0.66, 0.45, 0.36), Color(0.42, 0.55, 0.6),
	Color(0.8, 0.64, 0.36), Color(0.5, 0.6, 0.48), Color(0.72, 0.72, 0.7)]


## Estuco/pañete pintado (albedo casi blanco y neutro: el color lo pone `tint`).
## Superficie: fachadas de casas y edificios pintados, muros de cerramiento, pedestales.
## tile_m = 3.0 (un tile = un piso de 3 m). El tile trae humedad/salpicado abajo (0-0.45 m),
## chorreaduras bajo un alféizar a 1.0 m (x 0.9-2.1 m) y suciedad bajo losa arriba:
## alinea la base de cada piso con y = múltiplo de 3 m para que coincida con el piso real.
static func stucco(tint: Color = Color.WHITE) -> Material:
	return TexMat.pbr(_B + "stucco", {"tile_m": 3.0, "tint": tint})


## Atajo: estuco con uno de los 6 tonos de casa (variant 0..5, con wrap).
static func stucco_house(variant: int) -> Material:
	return stucco(HOUSE_TINTS[posmod(variant, HOUSE_TINTS.size())])


## Concreto a la vista con marcas de formaleta de tablas (15 cm), amarres, poros y chorreaduras.
## Superficie: columnas, muros de contención, culatas, puentes, bases de edificios.
## tile_m = 3.0 (tablas horizontales; usar en caras verticales).
static func concrete_board() -> Material:
	return TexMat.pbr(_B + "concrete_board", {"tile_m": 3.0})


## Concreto liso/pulido de edificio moderno, con junta de panel cada 2 m.
## Superficie: fachadas/losas de edificios modernos (ref. edificio de vidrio), voladizos, bordes de losa,
## bancas y pedestales modernos.
## tile_m = 2.0
static func concrete_smooth() -> Material:
	return TexMat.pbr(_B + "concrete_smooth", {"tile_m": 2.0})


## Teja de barro española (canal y cobija, 6 pares/2 m, hileras de 40 cm) con musgo y suciedad.
## Superficie: techos inclinados de casas antiguas. La pendiente baja hacia +V de la imagen;
## con triplanar en un techo inclinado la proyección superior la orienta según Z de mundo.
## Para techos con UV propias pasa triplanar=false (uv_scale = metros_del_faldón / 2).
## tile_m = 2.0
static func roof_clay(triplanar := true, uv_scale := Vector3.ONE) -> Material:
	if triplanar:
		return TexMat.pbr(_B + "roof_clay", {"tile_m": 2.0})
	return TexMat.pbr(_B + "roof_clay", {"triplanar": false, "uv_scale": uv_scale})


## Zócalo de enchape de piedra laja irregular con mortero (casas antioqueñas).
## Superficie: franja inferior de fachadas (0-0.8 m), jardineras, bases de muros y escalas.
## tile_m = 1.0
static func stone_base() -> Material:
	return TexMat.pbr(_B + "stone_base", {"tile_m": 1.0})


## Lámina ondulada de fibrocemento (eternit) gastada: 11 ondas/2 m, traslapo, ganchos con óxido,
## manchas negras de líquen y musgo. Las ondas corren a lo largo de la pendiente (+V).
## Superficie: techos de casas humildes, talleres, garajes, cubiertas de patios y kioscos.
## tile_m = 2.0
static func fibrocement(triplanar := true, uv_scale := Vector3.ONE) -> Material:
	if triplanar:
		return TexMat.pbr(_B + "fibrocement", {"tile_m": 2.0})
	return TexMat.pbr(_B + "fibrocement", {"triplanar": false, "uv_scale": uv_scale})

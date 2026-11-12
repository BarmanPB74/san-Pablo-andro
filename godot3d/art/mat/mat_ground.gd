class_name MatGround
extends RefCounted
## Familia "ground" (Fase 1): cortezas, pasto, mantillo y musgo.
## Texturas en res://art/tex/ground/ generadas por tools/texgen/ground.py.
##
## CORTEZAS (corteza_tropical, corteza_lisa, palma): NO usan triplanar. Se proyectan con las UV
## del mesh, que deben ser CILÍNDRICAS: U = vuelta alrededor del tronco (0..1), V = altura.
## CylinderMesh de Godot 4 las tiene, pero sus laterales ocupan solo V ∈ [0, 0.5] (las tapas
## usan la otra mitad), por eso cyl_uv_scale() multiplica la escala vertical por 2.
## La escala U se redondea a un entero de repeticiones para que no haya costura en la vuelta.
## Las tapas de los cilindros quedan con textura sin sentido: ocúltalas (cap_top/cap_bottom = false)
## o tápalas con otro material.
## Si el mesh no es un CylinderMesh (p. ej. un ArrayMesh propio con V ∈ [0,1] en el lateral),
## pasa side_v_range = 1.0.

const DIR := "res://art/tex/ground/"


## Escala UV para un tronco cilíndrico de `radius` y `height` metros con un tile físico de `tile_m`.
## side_v_range: fracción de V que ocupa el lateral (0.5 en CylinderMesh de Godot 4).
static func cyl_uv_scale(radius: float, height: float, tile_m: float, side_v_range := 0.5) -> Vector3:
	var circ := TAU * maxf(radius, 0.01)
	var u_reps := maxf(1.0, roundf(circ / tile_m))
	var v_reps := height / tile_m / side_v_range
	return Vector3(u_reps, v_reps, 1.0)


## Corteza de árbol tropical grande (ceiba, samán, caucho, guayacán viejo del Parque de Boston):
## fisuras verticales profundas, parches de musgo y líquen gris. Tile 2 m x 2 m (1024 px).
## Para el CylinderMesh del tronco (UV cilíndricas, sin triplanar). radius/height en metros.
static func corteza_tropical(radius := 0.4, height := 6.0, tint := Color.WHITE) -> Material:
	return TexMat.pbr(DIR + "corteza_tropical", {
		"triplanar": false, "uv_scale": cyl_uv_scale(radius, height, 2.0),
		"tint": tint, "normal_scale": 1.2})


## Corteza lisa clara con manchas de líquen (guayacán joven, urapán, árboles de andén delgados).
## Tile 1 m x 1 m (512 px). UV cilíndricas, sin triplanar.
static func corteza_lisa(radius := 0.18, height := 4.0, tint := Color.WHITE) -> Material:
	return TexMat.pbr(DIR + "corteza_lisa", {
		"triplanar": false, "uv_scale": cyl_uv_scale(radius, height, 1.0),
		"tint": tint})


## Tronco de palma (palma real / manila / areca de los andenes): anillos horizontales cada ~9 cm,
## cicatrices de hoja y grietas finas. Tile 1 m de alto (512 px). UV cilíndricas, sin triplanar.
static func palma(radius := 0.15, height := 8.0, tint := Color.WHITE) -> Material:
	return TexMat.pbr(DIR + "palma", {
		"triplanar": false, "uv_scale": cyl_uv_scale(radius, height, 1.0),
		"tint": tint})


## Pasto corto de jardinera / prado del parque, con calvas de tierra. Tile 3 m (1024 px), triplanar
## en espacio de mundo: úsalo en las cajas/planos de jardineras y zonas verdes.
## tint permite variar (más seco: Color(1.05, 1.0, 0.85)).
static func pasto(tint := Color.WHITE) -> Material:
	if ClayStyle.enabled and tint == Color.WHITE:
		tint = Color(0.75, 1.25, 0.6)   # prado de plastilina: verde musgo vivo
	return TexMat.pbr(DIR + "pasto", {"tile_m": 3.0, "tint": tint})


## Tierra/mantillo de jardinera con hojarasca seca, ramitas y piedritas. Tile 2 m (512 px), triplanar.
## Para el interior de jardineras de pizarra/ladrillo, alcorques y bases de árboles.
static func mantillo(tint := Color.WHITE) -> Material:
	return TexMat.pbr(DIR + "mantillo", {"tile_m": 2.0, "tint": tint})


## Musgo puro (cojines + pelusa) para mezclar en juntas y bordes (shaders de mezcla del integrador),
## o directamente en tapas de muros húmedos y bases de troncos. Tile 1 m (512 px), triplanar.
static func musgo(tint := Color.WHITE) -> Material:
	return TexMat.pbr(DIR + "musgo", {"tile_m": 1.0, "tint": tint})


## Variante de musgo con UV propias (por ejemplo, un cilindro-collar en la base de un tronco).
static func musgo_uv(uv_scale: Vector3) -> Material:
	return TexMat.pbr(DIR + "musgo", {"triplanar": false, "uv_scale": uv_scale})

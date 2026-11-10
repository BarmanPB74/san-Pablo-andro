class_name MatActors
extends RefCounted
## Materiales PBR de la familia "actors": vehículos y el personaje Andro.
## Texturas en res://art/tex/actors/ (generadas por tools/texgen/actors.py).
## Todos usan UV propias de las primitivas (triplanar = false) salvo car_paint_dirty().
## Las telas, piel y tenis tienen albedo neutro (media ~0.8) y aceptan `tint`: el color final
## ≈ tint * 0.8, así que se puede pasar directamente el color de PlayerModel (C_JACKET, SKIN_TONE…)
## o aclararlo un poco (tint / 0.8) si se quiere el valor exacto.

const DIR := "res://art/tex/actors/"

## Textos del atlas de placas (índice = celda). 0..5 particulares amarillas, 6..7 servicio público blancas.
const PLATE_TEXTS := ["SPA 742", "BOS 155", "MED 038", "ANT 516", "PBL 204", "CAF 873", "TXS 418", "BUS 307"]
const PLATE_PUBLIC := [6, 7]

static var _cache := {}


# ================================================================== VEHÍCULOS

## Pintura de carrocería con polvo/barro encima (detail albedo con la máscara en alfa).
## Para la ArrayMesh de carrocería (sin UV): triplanar en mundo, tile_m = 1.0 m.
## `dirt` 0..1 reduce/aumenta la suciedad aclarando u oscureciendo el detail (aprox.).
## (Más sucio abajo lo hará luego un shader; esto es la versión sin shader.)
static func car_paint_dirty(paint: Color, dirt := 1.0) -> Material:
	var key := "paint_%s_%.2f" % [paint.to_html(), dirt]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = paint
	m.metallic = 0.35
	m.roughness = 0.32
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
	m.detail_albedo = load(DIR + "veh_dirt_albedo.png")
	if dirt < 0.999:
		# La máscara de detalle (canal R) escala la cantidad de suciedad.
		var g := Gradient.new()
		g.set_color(0, Color(dirt, dirt, dirt))
		g.set_color(1, Color(dirt, dirt, dirt))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		gt.width = 4
		m.detail_mask = gt
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE  # tile_m = 1.0
	m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## Máscara de suciedad (RGBA: rgb color polvo, A = cantidad) para el shader de carrocería futuro.
## 1 tile = 1.0 m.
static func dirt_mask() -> Texture2D:
	return load(DIR + "veh_dirt_albedo.png")


## Llanta para CylinderMesh (eje del cilindro = eje de la rueda). Layout de UV de Godot 4.3:
## banda lateral (v 0..0.5) = rodamiento con 40 tacos; tapas (discos en v 0.5..1) = flancos
## "URBANA 185/65 R15". Una vuelta de textura = una vuelta de la rueda (uv_scale = 1).
static func tire() -> Material:
	return TexMat.pbr(DIR + "veh_tire", {"triplanar": false, "uv_scale": Vector3.ONE})


## Rin de aleación de 5 rayos partidos, vista frontal con alfa (huecos entre rayos).
## Para un QuadMesh (o PlaneMesh) de lado = 2 * radio del rin, pegado al flanco por fuera.
static func rim() -> Material:
	return TexMat.pbr(DIR + "veh_rim", {"triplanar": false, "transparent": true, "cull_disabled": true})


## Placa del atlas 2x4 para un QuadMesh de 0.33 x 0.16 m. index 0..7 (ver PLATE_TEXTS).
static func plate(index: int) -> Material:
	index = posmod(index, 8)
	var key := "plate_%d" % index
	if _cache.has(key):
		return _cache[key]
	var base: ORMMaterial3D = TexMat.pbr(DIR + "veh_plate", {"triplanar": false, "transparent": true})
	var m: ORMMaterial3D = base.duplicate()
	m.uv1_scale = Vector3(0.5, 0.25, 1.0)
	m.uv1_offset = Vector3(0.5 * (index % 2), 0.25 * (index / 2), 0.0)
	_cache[key] = m
	return m


## Índice de placa determinista para un texto/semilla; `public` elige las blancas (taxi/buseta).
static func plate_index(seed_text: String, public := false) -> int:
	var h := absi(seed_text.hash())
	return PLATE_PUBLIC[h % 2] if public else h % 6


## Faro delantero (mitad superior del atlas veh_lights), para QuadMesh ~0.34 x 0.12 m (aspecto 2:1).
## Emite (DRL + proyectores) con `energy`; pasa 0.0 para apagado.
static func headlight(energy := 2.0) -> Material:
	return _light_half("head", 0.0, energy)


## Stop trasero (mitad inferior del atlas veh_lights), QuadMesh aspecto 2:1. `energy` alto = frenando.
static func taillight(energy := 1.5) -> Material:
	return _light_half("tail", 0.5, energy)


static func _light_half(tag: String, v0: float, energy: float) -> Material:
	var key := "light_%s_%.2f" % [tag, energy]
	if _cache.has(key):
		return _cache[key]
	var base: ORMMaterial3D = TexMat.pbr(DIR + "veh_lights", {"triplanar": false, "transparent": true})
	var m: ORMMaterial3D = base.duplicate()
	m.uv1_scale = Vector3(1.0, 0.5, 1.0)
	m.uv1_offset = Vector3(0.0, v0, 0.0)
	m.emission_enabled = energy > 0.0
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


# ================================================================== PERSONAJE

## Chaqueta técnica (nylon ripstop, rejilla 9 mm, costura vertical pespunteada). tile_m = 0.30.
## uv_scale por defecto pensado para la CapsuleMesh del torso (circunf. ~1.1 m, alto 0.5 m).
static func jacket_ripstop(tint := Color.WHITE, uv_scale := Vector3(3.6, 1.7, 1.0)) -> Material:
	return TexMat.pbr(DIR + "cloth_ripstop", {"triplanar": false, "uv_scale": uv_scale, "tint": tint})


## Buzo de algodón en punto jersey (puntos de 2.3 mm). tile_m = 0.15.
static func hoodie_knit(tint := Color.WHITE, uv_scale := Vector3(6.0, 3.0, 1.0)) -> Material:
	return TexMat.pbr(DIR + "cloth_knit", {"triplanar": false, "uv_scale": uv_scale, "tint": tint})


## Pantalón cargo en sarga gruesa (wale diagonal 3.9 mm). tile_m = 0.25.
## Default para CapsuleMesh de muslo/canilla (circunf. ~0.5 m, alto ~0.4 m).
static func cargo_twill(tint := Color.WHITE, uv_scale := Vector3(2.0, 1.6, 1.0)) -> Material:
	return TexMat.pbr(DIR + "cloth_twill", {"triplanar": false, "uv_scale": uv_scale, "tint": tint})


## Piel con poros sutiles y variación (neutro cálido claro). tile_m = 0.12.
## Pasar el tono como tint (p. ej. PlayerModel.SKIN_TONE o STUBBLE_TONE). Default para la cabeza (SphereMesh r~0.1).
static func skin(tint := Color.WHITE, uv_scale := Vector3(5.0, 2.5, 1.0)) -> Material:
	return TexMat.pbr(DIR + "skin", {"triplanar": false, "uv_scale": uv_scale, "tint": tint, "normal_scale": 0.6})


## Tenis: cuero sintético perforado arriba (v 0..0.64), goma de suela abajo (v 0.66..1). tile_m = 0.25 en u.
## Con uv_scale.y = 1 una cara del pie muestra cuero + suela; para piezas solo-suela usar sneaker_sole().
static func sneaker(tint := Color.WHITE, uv_scale := Vector3(1.0, 1.0, 1.0)) -> Material:
	return TexMat.pbr(DIR + "sneaker", {"triplanar": false, "uv_scale": uv_scale, "tint": tint})


## Solo la franja de goma de la suela del tenis (v 0.66..1 del mismo set).
static func sneaker_sole(tint := Color.WHITE) -> Material:
	var key := "sole_%s" % tint.to_html()
	if _cache.has(key):
		return _cache[key]
	var base: ORMMaterial3D = TexMat.pbr(DIR + "sneaker", {"triplanar": false, "tint": tint})
	var m: ORMMaterial3D = base.duplicate()
	m.uv1_scale = Vector3(1.0, 0.32, 1.0)
	m.uv1_offset = Vector3(0.0, 0.67, 0.0)
	_cache[key] = m
	return m


## Pañoleta de algodón a rayas verde/blanco (Antioquia), franjas de 4 cm. tile_m = 0.16.
## Ya trae color; tint opcional (blanco = sin cambio).
static func scarf_antioquia(tint := Color.WHITE, uv_scale := Vector3(3.5, 0.6, 1.0)) -> Material:
	return TexMat.pbr(DIR + "scarf", {"triplanar": false, "uv_scale": uv_scale, "tint": tint, "cull_disabled": true})

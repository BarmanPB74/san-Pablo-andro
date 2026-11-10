class_name MatFacade
extends RefCounted
## Materiales de la familia FACADE: ventanas, vitrinas, letreros y toldos.
## Texturas en res://art/tex/facade/ (generadas por tools/texgen/facade.py).
## Los atlas NO son triplanares: usan las UV del mesh (QuadMesh/PlaneMesh/cara de BoxMesh con UV 0..1)
## y estas funciones fijan uv1_scale/uv1_offset para mostrar una sola celda.
## night = true activa la emisión (interiores encendidos, cajas de luz, neones); de día va apagada.

const BASE := "res://art/tex/facade/"

## Celdas de windows() que tienen interior encendido de noche (las demás quedan oscuras).
const LIT_WINDOWS: Array[int] = [0, 2, 5, 7, 8, 10, 13, 15]
## Celdas de sign() que son banda 2:1 (el resto son cuadradas 1:1).
const SIGN_BAND: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15]
## Contenido de cada celda de sign():
## 0 Panadería La Esquina (madera pintada) · 1 Droguería Boston (caja de luz) · 2 Tienda Don Chepe (placa)
## 3 Café Capiro (letras de bronce retroiluminadas) · 4 Ferretería El Tornillo (placa) · 5 Restaurante Doña Rosa (pintado)
## 6 Barbería Andro · 7 Licorera La 55 (caja de luz) · 8 Papelería Córdova (caja de luz) · 9 Heladería Guayacán (pintado)
## 10 aviso redondo colgante blanco "Ak" · 11 aviso redondo negro/dorado "Mz" · 12 neón cian "Café"
## 13 neón magenta "Bar" · 14 neón ámbar "24 H" · 15 neón "ABIERTO" (banda 2:1)
const SIGN_NAMES := ["panaderia", "drogueria", "tienda", "cafe_capiro", "ferreteria", "restaurante",
	"barberia", "licorera", "papeleria", "heladeria", "redondo_ak", "redondo_mz",
	"neon_cafe", "neon_bar", "neon_24h", "neon_abierto"]
## Vitrinas: 0 café · 1 panadería · 2 droguería · 3 tienda de barrio.
enum Shop { CAFE, PANADERIA, DROGUERIA, TIENDA }

static var _cache := {}


static func _cell(set_name: String, cols: int, cell: int, night: bool, extra := {}, band := false) -> ORMMaterial3D:
	var c := posmod(cell, cols * cols)
	var key := "%s_%d_%s_%s" % [set_name, c, night, str(extra)]
	if _cache.has(key):
		return _cache[key]
	var opts := {"triplanar": false, "emission_energy": float(extra.get("emission_energy", 2.0))}
	for k in extra:
		opts[k] = extra[k]
	var m: ORMMaterial3D = TexMat.pbr(BASE + set_name, opts).duplicate()
	var s := 1.0 / float(cols)
	var col := c % cols
	var row := c / cols
	if band:
		# banda 2:1 centrada verticalmente en la celda
		m.uv1_scale = Vector3(s, s * 0.5, 1.0)
		m.uv1_offset = Vector3(col * s, row * s + s * 0.25, 0.0)
	else:
		m.uv1_scale = Vector3(s, s, 1.0)
		m.uv1_offset = Vector3(col * s, row * s, 0.0)
	m.emission_enabled = night
	_cache[key] = m
	return m


## Ventana residencial (atlas 4x4, celda = ventana de ~1.4 x 1.4 m con marco incluido hasta el borde).
## Uso: quad de ventana en fachadas (MultiMesh por celda). Marcos aluminio/negro/blanco/bronce, cortinas,
## persianas y rejas. De noche solo las celdas LIT_WINDOWS emiten interior cálido. tile_m: no aplica (UV 0..1).
static func window(cell: int, night := false) -> Material:
	return _cell("windows", 4, cell, night, {"emission_energy": 1.6})


## Vitrina de local completa (atlas 2x2, celda ≈ 3.2 x 3.2 m: caja de cortina metálica arriba, vidrio con
## interior en perspectiva falsa, puerta y zócalo de granito). cell: Shop.CAFE/PANADERIA/DROGUERIA/TIENDA.
## Uso: quad en el frente de los locales de primer piso. tile_m: no aplica (UV 0..1).
static func shopfront(cell: int, night := false) -> Material:
	return _cell("shopfronts", 2, cell, night, {"emission_energy": 1.5})


## Letrero/aviso (atlas 4x4, alpha scissor). Celdas en SIGN_BAND usan un quad de proporción 2:1
## (p. ej. 2.4 x 1.2 m); las demás 1:1 (avisos redondos ~0.6 m, neones ~0.8 m). Ver sign_aspect().
## De noche emiten las cajas de luz, letras retroiluminadas y neones. tile_m: no aplica (UV 0..1).
static func sign(cell: int, night := false) -> Material:
	var c := posmod(cell, 16)
	return _cell("signs", 4, c, night, {"transparent": true, "cull_disabled": true, "emission_energy": 3.0},
		SIGN_BAND.has(c))


## Ancho/alto que debe tener el quad de sign(cell).
static func sign_aspect(cell: int) -> float:
	return 2.0 if SIGN_BAND.has(posmod(cell, 16)) else 1.0


## Lona de toldo a rayas verde/crudo, gastada (desteñido, manchas de agua, escurrimientos).
## tile_m = 1.5 m (8 franjas de 18.75 cm). Triplanar por defecto: sirve directo en BoxMesh/CylinderMesh.
static func awning_striped(triplanar := true) -> Material:
	if triplanar:
		return TexMat.pbr(BASE + "awning_stripes", {"tile_m": 1.5, "cull_disabled": true})
	return TexMat.pbr(BASE + "awning_stripes", {"triplanar": false, "cull_disabled": true})


## Lona de toldo lisa color crudo, gastada; usar tint para variar (rojo, verde, azul, terracota).
## tile_m = 1.5 m.
static func awning_plain(tint := Color(1, 1, 1), triplanar := true) -> Material:
	var o := {"tile_m": 1.5, "cull_disabled": true, "tint": tint}
	if not triplanar:
		o["triplanar"] = false
	return TexMat.pbr(BASE + "awning_plain", o)

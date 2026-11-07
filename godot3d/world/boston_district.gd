class_name BostonDistrict
extends Node3D
## Barrio Boston (comuna 10 La Candelaria, Medellín) construido 100 % por código.
## Origen = pie de la estatua de José María Córdova, a nivel del andén del parque.
## -Z = norte, +X = este. El terreno sube hacia el ESTE con pendiente SLOPE.
##
## Cuadrícula (ver README_mapa.md):
##   Carrera n  → x = (38.5 - n) * BLOCK   (Cra 38 = +40, Cra 39 = -40, Cra 43 = -360)
##   Calle n    → z = (54.5 - n) * BLOCK   (Cl 55 = -40, Cl 54 = +40, Cl 52 = +200, Cl 58 = -280)
##
## Rendimiento: la geometría estática se fusiona con SurfaceTool por (trozo 3x3, material);
## ventanas, árboles y bombillos van en MultiMesh. Colisión: un ConcavePolygonShape3D para
## todo el suelo + cajas/cilindros simples para edificios y mobiliario.

const SLOPE: float = 0.04          # 4 % de pendiente hacia el este
const CURB: float = 0.15           # altura del sardinel
const BLOCK: float = 80.0          # distancia entre ejes de vías
const ROAD_HALF: float = 3.5       # media calzada de vía normal (2 carriles = 7 m)
const WALK: float = 2.5            # andén normal
const WIDE_ROAD_HALF: float = 9.0  # vía ancha: 2 calzadas de 7 m + separador de 4 m
const WIDE_WALK: float = 3.0
const MEDIAN_HALF: float = 2.0
const X_MIN: float = -410.0
const X_MAX: float = 245.0
const Z_MIN: float = -325.0
const Z_MAX: float = 262.0
const CHUNKS: int = 2
const SEED: int = 1955
const MAX_SHOP_LABELS: int = 46

const CARRERAS := [43, 42, 41, 40, 39, 38, 37, 36]  # de oeste a este
const CALLES := [58, 57, 56, 55, 54, 53, 52]        # de norte a sur
const WIDE_IDS := ["K43", "C52"]
const MAIN_IDS := ["C54", "C55", "K38", "K39", "C58", "K43", "C52"]  # vías comerciales
const STREET_NAMES := {"C52": "La Playa", "C54": "Caracas", "C55": "Perú", "C58": "Echeverri", "K43": "Girardot"}

const SHOP_NAMES := [
	"Panadería La Esquina", "Droguería Boston", "Tienda Don Chepe", "Billares El Tiple",
	"Café Perú", "Ferretería Caracas", "Fonda La Candelaria", "Peluquería Estilo",
	"Arepas Doña Rosa", "Licorera El Parque", "Miscelánea Sofi", "Papelería El Lápiz",
	"Heladería Polo Sur", "Asadero Pollo Dorado", "Sastrería Medellín", "Cacharrería La 55",
	"Bar El Recuerdo", "Taller Moto Boston", "Sabor Paisa", "Frutería Tropical",
	"Cigarrería Echeverri", "Granero La 58", "Variedades Córdova", "Bar Tango Viejo",
	"Óptica Visión", "Pan de Yuca Boston", "Cerrajería El Candado", "Minimercado Sufragio",
	"Bar La Gardeliana", "Empanadas El Paisa", "Tienda La Montaña", "Rapitienda Girardot",
]

const _BOX_FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
]

var _rng := RandomNumberGenerator.new()
var _xs: Array = []   # carreras: {"id","n","pos","half","walk","wide"}
var _zs: Array = []   # calles
var _batches := {}    # clave → {"st": SurfaceTool, "mat": Material, "shadow": bool}
var _col_faces := PackedVector3Array()
var _col_shapes: Array = []   # [Shape3D, Transform3D]
var _excl: Array[Rect2] = []  # zonas sin edificios procedurales (iglesia, teatro)
var _mm := {}                 # nombre → {"mesh": Mesh, "mat": Material, "xf": Array, "shadow": bool}
var _shop_i := 0
var _labels := 0
var _lights := 0
var _cur_main := false


# ------------------------------------------------------------------ API pública
## Altura del andén (nivel peatonal) en x.
static func walk_y(x: float) -> float:
	return SLOPE * x

## Altura de la calzada en x.
static func road_y(x: float) -> float:
	return SLOPE * x - CURB

static func carrera_x(n: int) -> float:
	return (38.5 - n) * BLOCK

static func calle_z(n: int) -> float:
	return (54.5 - n) * BLOCK


func _ready() -> void:
	_rng.seed = SEED
	_setup_streets()
	_build_ground()
	_build_markings()
	_build_park()
	_build_church()
	_build_theatre()
	_build_blocks()
	_build_poles_and_cables()
	_build_traffic_lights()
	_build_street_trees()
	_build_small_furniture()
	_build_cones()
	_build_spawns()
	_build_bounds()
	_flush()


# ------------------------------------------------------------------ vías
func _setup_streets() -> void:
	for n in CARRERAS:
		var id := "K%d" % n
		var wide: bool = id in WIDE_IDS
		_xs.append({"id": id, "n": n, "pos": carrera_x(n), "wide": wide,
			"half": WIDE_ROAD_HALF if wide else ROAD_HALF, "walk": WIDE_WALK if wide else WALK})
	for n in CALLES:
		var id := "C%d" % n
		var wide: bool = id in WIDE_IDS
		_zs.append({"id": id, "n": n, "pos": calle_z(n), "wide": wide,
			"half": WIDE_ROAD_HALF if wide else ROAD_HALF, "walk": WIDE_WALK if wide else WALK})


## Intervalos de manzana en un eje: [{a, b, lo(street|null), hi(street|null)}] (borde de calzada a borde).
func _cells(streets: Array, vmin: float, vmax: float) -> Array:
	var out: Array = []
	for i in streets.size() + 1:
		var lo: Variant = streets[i - 1] if i > 0 else null
		var hi: Variant = streets[i] if i < streets.size() else null
		var a: float = vmin if lo == null else float(lo.pos) + float(lo.half)
		var b: float = vmax if hi == null else float(hi.pos) - float(hi.half)
		out.append({"a": a, "b": b, "lo": lo, "hi": hi})
	return out


func _build_ground() -> void:
	# Calzada: un plano inclinado continuo en rejilla (intersecciones planas y rampas sin escalones).
	var nx := 24
	var nz := 22
	for i in nx:
		for j in nz:
			var x0: float = lerpf(X_MIN, X_MAX, float(i) / nx)
			var x1: float = lerpf(X_MIN, X_MAX, float(i + 1) / nx)
			var z0: float = lerpf(Z_MIN, Z_MAX, float(j) / nz)
			var z1: float = lerpf(Z_MIN, Z_MAX, float(j + 1) / nz)
			_tilted_top(Palette.asphalt(), x0, x1, z0, z1, -CURB, false, false)
	# Colisión de la calzada: UNA caja inclinada sin juntas (las ruedas no tropiezan con aristas internas).
	var ang := atan(SLOPE)
	var cxm := (X_MIN + X_MAX) * 0.5
	var thick := 4.0
	var gb := BoxShape3D.new()
	gb.size = Vector3((X_MAX - X_MIN) / cos(ang) + 4.0, thick, Z_MAX - Z_MIN + 4.0)
	_col_shapes.append([gb, Transform3D(Basis(Vector3.BACK, ang), Vector3(cxm, SLOPE * cxm - CURB - thick * 0.5 / cos(ang), (Z_MIN + Z_MAX) * 0.5))])
	# Manzanas: losa elevada CURB (andén + lote). El costado es el sardinel.
	for cx in _cells(_xs, X_MIN, X_MAX):
		for cz in _cells(_zs, Z_MIN, Z_MAX):
			var x0: float = cx.a
			var x1: float = cx.b
			var z0: float = cz.a
			var z1: float = cz.b
			if _is_park_cell(cx, cz):
				var w := WALK
				_tslab(Palette.sidewalk(), Palette.curb(), x0, x1, z0, z0 + w, 0.0, -CURB)
				_tslab(Palette.sidewalk(), Palette.curb(), x0, x1, z1 - w, z1, 0.0, -CURB)
				_tslab(Palette.sidewalk(), Palette.curb(), x0, x0 + w, z0 + w, z1 - w, 0.0, -CURB)
				_tslab(Palette.sidewalk(), Palette.curb(), x1 - w, x1, z0 + w, z1 - w, 0.0, -CURB)
				_tslab(Palette.plaza_tile(), Palette.curb(), x0 + w, x1 - w, z0 + w, z1 - w, 0.0, -CURB)
			else:
				_tslab(Palette.sidewalk(), Palette.curb(), x0, x1, z0, z1, 0.0, -CURB)
	# Separadores de vías anchas (con cortes en cada cruce).
	for s in _xs:
		if s.wide:
			var cuts: Array = []
			for c in _zs:
				cuts.append([float(c.pos) - float(c.half) - 4.0, float(c.pos) + float(c.half) + 4.0])
			for seg in _segments(Z_MIN, Z_MAX, cuts):
				_tslab(Palette.grass(), Palette.curb(), float(s.pos) - MEDIAN_HALF, float(s.pos) + MEDIAN_HALF, seg[0], seg[1], 0.0, -CURB)
	for s in _zs:
		if s.wide:
			var cuts: Array = []
			for c in _xs:
				cuts.append([float(c.pos) - float(c.half) - 4.0, float(c.pos) + float(c.half) + 4.0])
			for seg in _segments(X_MIN, X_MAX, cuts):
				_tslab(Palette.grass(), Palette.curb(), seg[0], seg[1], float(s.pos) - MEDIAN_HALF, float(s.pos) + MEDIAN_HALF, 0.0, -CURB)


## Resta intervalos [a,b] (cuts) de [vmin,vmax].
func _segments(vmin: float, vmax: float, cuts: Array) -> Array:
	var out: Array = []
	var t := vmin
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for c in cuts:
		if c[0] > t + 0.5:
			out.append([t, minf(c[0], vmax)])
		t = maxf(t, c[1])
	if vmax > t + 0.5:
		out.append([t, vmax])
	return out


func _is_park_cell(cx: Dictionary, cz: Dictionary) -> bool:
	return cx.lo != null and cx.lo.id == "K39" and cz.lo != null and cz.lo.id == "C55"


func _build_markings() -> void:
	var yellow := Palette.road_line()
	var white := WorldMaterials.paint_white()
	# Líneas longitudinales por tramo entre cruces.
	for s in _xs:
		var cuts: Array = []
		for c in _zs:
			cuts.append([float(c.pos) - float(c.half), float(c.pos) + float(c.half)])
		for seg in _segments(Z_MIN + 2.0, Z_MAX - 2.0, cuts):
			if s.wide:
				for off in [-(MEDIAN_HALF + 3.5), MEDIAN_HALF + 3.5]:
					_dashes(white, float(s.pos) + off, seg[0] + 4.0, seg[1] - 4.0, true)
			else:
				_dashes(yellow, float(s.pos), seg[0] + 4.0, seg[1] - 4.0, true)
	for s in _zs:
		var cuts: Array = []
		for c in _xs:
			cuts.append([float(c.pos) - float(c.half), float(c.pos) + float(c.half)])
		for seg in _segments(X_MIN + 2.0, X_MAX - 2.0, cuts):
			if s.wide:
				for off in [-(MEDIAN_HALF + 3.5), MEDIAN_HALF + 3.5]:
					_dashes(white, float(s.pos) + off, seg[0] + 4.0, seg[1] - 4.0, false)
			else:
				_dashes(yellow, float(s.pos), seg[0] + 4.0, seg[1] - 4.0, false)
	# Cebras en todos los cruces (4 accesos).
	for k in _xs:
		for c in _zs:
			var kx: float = k.pos
			var kh: float = k.half
			var cz: float = c.pos
			var ch: float = c.half
			for side: float in [-1.0, 1.0]:
				# Sobre la carrera, a cada lado de la calle.
				var za := cz + side * (ch + 0.6)
				var zb := cz + side * (ch + 3.6)
				var u := kx - kh + 0.5
				while u + 0.5 < kx + kh - 0.3:
					if not (k.wide and absf(u + 0.25 - kx) < MEDIAN_HALF):
						_paint(white, u, u + 0.5, minf(za, zb), maxf(za, zb))
					u += 1.1
				# Sobre la calle, a cada lado de la carrera.
				var xa := kx + side * (kh + 0.6)
				var xb := kx + side * (kh + 3.6)
				var v := cz - ch + 0.5
				while v + 0.5 < cz + ch - 0.3:
					if not (c.wide and absf(v + 0.25 - cz) < MEDIAN_HALF):
						_paint(white, minf(xa, xb), maxf(xa, xb), v, v + 0.5)
					v += 1.1


func _dashes(mat: Material, at: float, a: float, b: float, along_z: bool) -> void:
	var t := a
	while t + 3.0 <= b:
		if along_z:
			_paint(mat, at - 0.07, at + 0.07, t, t + 3.0)
		else:
			_paint(mat, t, t + 3.0, at - 0.07, at + 0.07)
		t += 6.0


func _paint(mat: Material, x0: float, x1: float, z0: float, z1: float) -> void:
	_tilted_top(mat, x0, x1, z0, z1, -CURB + 0.02, false, false)


# ------------------------------------------------------------------ parque
func _build_park() -> void:
	# Jardineras elevadas en L por cuadrante, dejando plaza central 24x24 y caminos en cruz.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for r in [[12.0, 31.0, 2.5, 31.0], [2.5, 12.0, 12.0, 31.0]]:
				var xa: float = sx * r[0]
				var xb: float = sx * r[1]
				var za: float = sz * r[2]
				var zb: float = sz * r[3]
				_tslab(Palette.grass(), Palette.concrete(), minf(xa, xb), maxf(xa, xb), minf(za, zb), maxf(za, zb), 0.35, 0.0)
	# Árboles del parque (deterministas, dentro de las jardineras).
	var spots := [Vector2(20, 8), Vector2(27, 19), Vector2(17, 26), Vector2(7, 23), Vector2(28, 6),
		Vector2(22, 14), Vector2(28, 28), Vector2(9, 16), Vector2(15, 4)]
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for p in spots:
				var jitter := Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5))
				var q: Vector2 = (p + jitter) * Vector2(sx, sz)
				var kind := 0
				var roll := _rng.randf()
				if roll < 0.15:
					kind = 1
				elif roll < 0.25:
					kind = 2
				_tree(Vector3(q.x, walk_y(q.x) + 0.35, q.y), _rng.randf_range(1.1, 1.5), kind)
	# Estatua ecuestre sobre pedestal escalonado.
	_statue()
	# Bancas alrededor de la plaza mirando a la estatua y a lo largo de los caminos.
	for ang: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		for u in [-7.0, 7.0]:
			var b := Basis(Vector3.UP, ang)
			var p := b * Vector3(u, 0, 11.2)
			_bench(Transform3D(b * Basis(Vector3.UP, PI), Vector3(p.x, walk_y(p.x), p.z)))
		for d in [17.0, 25.0]:
			var b2 := Basis(Vector3.UP, ang)
			var p2 := b2 * Vector3(3.2, 0, d)
			_bench(Transform3D(b2 * Basis(Vector3.UP, -PI * 0.5), Vector3(p2.x, walk_y(p2.x), p2.z)))
	# Faroles del parque.
	var lamp_pos: Array = []
	for d in [16.0, 27.0]:
		for ang: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			lamp_pos.append(Basis(Vector3.UP, ang) * Vector3(-3.2, 0, d))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			lamp_pos.append(Vector3(11.6 * sx, 0, 11.6 * sz))
	for i in lamp_pos.size():
		var p: Vector3 = lamp_pos[i]
		_park_lamp(Vector3(p.x, walk_y(p.x), p.z), i % 2 == 0)
	# Carritos de comida callejera.
	_food_cart(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(8.5, walk_y(8.5), 8.5)), 0)
	_food_cart(Transform3D(Basis(Vector3.UP, -PI * 0.75), Vector3(-8.5, walk_y(-8.5), -8.5)), 1)
	_food_cart(Transform3D(Basis(Vector3.UP, 0.0), Vector3(18.0, walk_y(18.0), 35.0)), 2)
	_food_cart(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-35.0, walk_y(-35.0), -12.0)), 3)
	_food_cart(Transform3D(Basis(Vector3.UP, PI), Vector3(-14.0, walk_y(-14.0), -35.0)), 0)
	# Placas de nomenclatura en las esquinas del parque.
	_street_plate(Vector3(35.0, 0, -35.0), "Calle 55 · Perú", "Carrera 38")
	_street_plate(Vector3(-35.0, 0, -35.0), "Calle 55 · Perú", "Carrera 39")
	_street_plate(Vector3(35.0, 0, 35.0), "Calle 54 · Caracas", "Carrera 38")
	_street_plate(Vector3(-35.0, 0, 35.0), "Calle 54 · Caracas", "Carrera 39")


func _statue() -> void:
	var stone := Palette.stone()
	var bronze := Palette.bronze()
	var o := Transform3D.IDENTITY
	# Pedestal escalonado (el primer escalón se entierra para absorber la pendiente).
	_box(stone, o.translated(Vector3(0, -0.2, 0)), Vector3(7.0, 0.7, 7.0))
	_box(stone, o.translated(Vector3(0, 0.3, 0)), Vector3(6.0, 0.3, 6.0))
	_box(stone, o.translated(Vector3(0, 0.6, 0)), Vector3(5.0, 0.3, 5.0))
	_box(stone, o.translated(Vector3(0, 2.25, 0)), Vector3(3.4, 3.0, 3.4))
	_box(stone, o.translated(Vector3(0, 3.9, 0)), Vector3(4.0, 0.35, 4.0))
	_box(stone, o.translated(Vector3(0, 4.22, 0)), Vector3(3.3, 0.3, 3.3))
	_box(bronze, o.translated(Vector3(0, 2.4, 1.72)), Vector3(1.6, 0.9, 0.06))  # placa
	_col_box(o.translated(Vector3(0, 1.0, 0)), Vector3(7.0, 3.0, 7.0))
	_col_box(o.translated(Vector3(0, 2.4, 0)), Vector3(4.0, 4.6, 4.0))
	# Caballo y jinete (mira al sur, +Z) a partir de primitivas.
	var t := Transform3D(Basis.IDENTITY, Vector3(0, 4.37, 0))
	_box(bronze, t.translated_local(Vector3(0, 0.05, 0)), Vector3(1.3, 0.1, 2.9))
	_cyl(bronze, t * Vector3(0, 1.55, -1.05), t * Vector3(0, 1.6, 1.0), 0.52, 0.5, 8, true)
	_cyl(bronze, t * Vector3(0, 1.75, 0.85), t * Vector3(0, 2.6, 1.4), 0.34, 0.24, 8, true)
	_box(bronze, t * Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3(0, 2.62, 1.72)), Vector3(0.3, 0.32, 0.85))
	_box(bronze, t.translated_local(Vector3(0.1, 2.95, 1.35)), Vector3(0.06, 0.2, 0.08))
	_box(bronze, t.translated_local(Vector3(-0.1, 2.95, 1.35)), Vector3(0.06, 0.2, 0.08))
	_cyl(bronze, t * Vector3(0, 2.7, 1.25), t * Vector3(0, 1.9, 0.55), 0.08, 0.05, 5, false)  # crin
	# Patas: delantera izquierda levantada (paso de vencedores).
	_cyl(bronze, t * Vector3(0.25, 1.25, 0.8), t * Vector3(0.25, 0.75, 1.15), 0.12, 0.1, 6, false)
	_cyl(bronze, t * Vector3(0.25, 0.75, 1.15), t * Vector3(0.25, 0.55, 0.95), 0.1, 0.09, 6, true)
	_cyl(bronze, t * Vector3(-0.25, 1.25, 0.85), t * Vector3(-0.25, 0.08, 0.95), 0.12, 0.09, 6, true)
	_cyl(bronze, t * Vector3(0.25, 1.25, -0.85), t * Vector3(0.27, 0.08, -0.95), 0.13, 0.09, 6, true)
	_cyl(bronze, t * Vector3(-0.25, 1.25, -0.85), t * Vector3(-0.27, 0.08, -1.05), 0.13, 0.09, 6, true)
	_cyl(bronze, t * Vector3(0, 1.8, -1.1), t * Vector3(0, 0.75, -1.5), 0.12, 0.05, 5, false)  # cola
	# Jinete.
	_cyl(bronze, t * Vector3(0, 2.05, 0.05), t * Vector3(0, 2.95, 0.0), 0.24, 0.2, 8, true)
	_cyl(bronze, t * Vector3(0.22, 2.1, 0.05), t * Vector3(0.52, 1.5, 0.25), 0.11, 0.08, 6, true)
	_cyl(bronze, t * Vector3(-0.22, 2.1, 0.05), t * Vector3(-0.52, 1.5, 0.25), 0.11, 0.08, 6, true)
	_cyl(bronze, t * Vector3(0, 2.95, 0), t * Vector3(0, 3.28, 0.02), 0.14, 0.13, 8, true)    # cabeza
	_cyl(bronze, t * Vector3(0, 3.26, 0), t * Vector3(0, 3.48, -0.04), 0.16, 0.13, 8, true)   # morrión
	_cyl(bronze, t * Vector3(0.24, 2.85, 0), t * Vector3(0.5, 3.35, 0.35), 0.07, 0.06, 6, true)   # brazo alzado
	_cyl(bronze, t * Vector3(0.5, 3.35, 0.35), t * Vector3(0.58, 4.25, 0.55), 0.025, 0.015, 4, true)  # sable
	_cyl(bronze, t * Vector3(-0.24, 2.8, 0), t * Vector3(-0.15, 2.3, 0.5), 0.07, 0.06, 6, true)  # riendas


func _bench(xf: Transform3D) -> void:
	var wood := Palette.wood()
	var metal := Palette.metal_dark()
	_box(wood, xf.translated_local(Vector3(0, 0.45, 0)), Vector3(1.8, 0.07, 0.45))
	_box(wood, xf * Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 0.8, -0.24)), Vector3(1.8, 0.35, 0.05))
	for u in [-0.75, 0.75]:
		_box(metal, xf.translated_local(Vector3(u, 0.2, 0)), Vector3(0.06, 0.6, 0.45))
	_col_box(xf.translated_local(Vector3(0, 0.45, 0)), Vector3(1.8, 0.9, 0.5))


func _park_lamp(p: Vector3, with_light: bool) -> void:
	var metal := Palette.metal_dark()
	_cyl(metal, p + Vector3(0, -0.2, 0), p + Vector3(0, 3.9, 0), 0.08, 0.06, 6, false)
	_cyl(metal, p + Vector3(0, -0.2, 0), p + Vector3(0, 0.5, 0), 0.16, 0.14, 6, true)
	_cyl(metal, p + Vector3(0, 4.3, 0), p + Vector3(0, 4.55, 0), 0.32, 0.05, 6, true)
	_mm_add("bulb", Transform3D(Basis.from_scale(Vector3.ONE * 0.26), p + Vector3(0, 4.1, 0)))
	_col_cyl(p + Vector3(0, 2.0, 0), 0.1, 4.0)
	if with_light and _lights < 12:
		_lights += 1
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.45)
		l.light_energy = 1.4
		l.omni_range = 11.0
		l.shadow_enabled = false
		l.position = p + Vector3(0, 3.8, 0)
		add_child(l)


func _food_cart(xf: Transform3D, variant: int) -> void:
	var paint := WorldMaterials.cart(variant)
	var chrome := Palette.chrome()
	_box(paint, xf.translated_local(Vector3(0, 0.75, 0)), Vector3(1.7, 0.8, 0.85))
	_box(chrome, xf.translated_local(Vector3(0, 1.18, 0)), Vector3(1.8, 0.06, 0.95))
	_box(Palette.window_glass(), xf.translated_local(Vector3(0, 1.45, -0.1)), Vector3(1.4, 0.5, 0.5))
	for u in [-0.6, 0.6]:
		var a := xf * Vector3(u, 0.3, -0.45)
		var b := xf * Vector3(u, 0.3, 0.45)
		_cyl(Palette.tire(), a, a + (b - a).normalized() * -0.08, 0.3, 0.3, 8, true)
		_cyl(Palette.tire(), b, b + (b - a).normalized() * 0.08, 0.3, 0.3, 8, true)
	var top := xf * Vector3(0.7, 2.6, 0)
	_cyl(chrome, xf * Vector3(0.7, 1.2, 0), top, 0.03, 0.03, 4, false)
	_cyl(WorldMaterials.awning(variant + 1), top + Vector3(0, -0.4, 0), top + Vector3(0, 0.15, 0), 1.3, 0.05, 8, true)
	_mm_add("bulb", Transform3D(Basis.from_scale(Vector3.ONE * 0.12), top + Vector3(0, -0.55, 0)))
	_col_box(xf.translated_local(Vector3(0, 0.75, 0)), Vector3(1.8, 1.5, 1.0))


func _street_plate(p: Vector3, calle: String, carrera: String) -> void:
	var y := walk_y(p.x)
	var base := Vector3(p.x, y, p.z)
	_cyl(Palette.metal_dark(), base, base + Vector3(0, 3.0, 0), 0.05, 0.05, 6, false)
	_col_cyl(base + Vector3(0, 1.5, 0), 0.06, 3.0)
	# Placa de la calle (texto mirando al este/oeste) y de la carrera (norte/sur).
	var panel := WorldMaterials.paint_white()
	_box(panel, Transform3D(Basis.IDENTITY, base + Vector3(0, 2.8, 0)), Vector3(0.06, 0.32, 1.6))
	_box(panel, Transform3D(Basis.IDENTITY, base + Vector3(0, 2.4, 0)), Vector3(1.4, 0.32, 0.06))
	var sx: float = signf(-p.x)
	var sz: float = signf(-p.z)
	_label(calle, Transform3D(Basis(Vector3.UP, sx * PI * 0.5), base + Vector3(sx * 0.04, 2.8, 0)), Color(0.05, 0.15, 0.4), 36, 0.006)
	_label(carrera, Transform3D(Basis(Vector3.UP, 0.0 if sz > 0.0 else PI), base + Vector3(0, 2.4, sz * 0.04)), Color(0.05, 0.15, 0.4), 36, 0.006)
	_label(calle, Transform3D(Basis(Vector3.UP, -sx * PI * 0.5), base + Vector3(-sx * 0.04, 2.8, 0)), Color(0.05, 0.15, 0.4), 36, 0.006)


# ------------------------------------------------------------------ iglesia del Sufragio
func _build_church() -> void:
	# Calle 55 #39-61 → cuadra entre Cra 39 y Cra 40, frente sobre la Calle 55 (mira al norte).
	var xc := -72.0
	var zf := -30.5               # línea de fachada
	var zb := 12.0                # fondo de la nave
	var wall := WorldMaterials.church_wall()
	var stone := Palette.stone()
	var dark := WorldMaterials.dark_opening()
	var floor_y := walk_y(-60.0) + 0.9
	_excl.append(Rect2(-88.0, -36.0, 42.5, 60.0))
	# Podio que absorbe la pendiente.
	var podium_h := floor_y - (walk_y(-86.0) - 0.6)
	var pod := Transform3D(Basis.IDENTITY, Vector3(xc, floor_y - podium_h * 0.5, (zf + zb + 10.0) * 0.5))
	_box(stone, pod, Vector3(26.0, podium_h, zb + 10.0 - zf))
	_col_box(pod, Vector3(26.0, podium_h, zb + 10.0 - zf))
	# Escalinata hacia la Calle 55.
	var steps := 6
	var base_y := walk_y(-80.0)
	for i in steps:
		var top := base_y + (floor_y - base_y) * float(i + 1) / steps
		var z0 := -34.0 + 0.55 * i
		var bot := walk_y(-86.0) - 0.5
		var sxf := Transform3D(Basis.IDENTITY, Vector3(xc, (top + bot) * 0.5, (z0 + zf) * 0.5))
		var ssz := Vector3(18.0, top - bot, zf - z0)
		_box(stone, sxf, ssz)
		_col_box(sxf, ssz)
	# Nave.
	var nave_h := 15.0
	var nave := Transform3D(Basis.IDENTITY, Vector3(xc, floor_y + nave_h * 0.5, (zf + zb) * 0.5))
	_box(wall, nave, Vector3(18.0, nave_h, zb - zf))
	_col_box(nave, Vector3(18.0, nave_h, zb - zf))
	_gable(Palette.roof_tile(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(xc, floor_y + nave_h, (zf + zb) * 0.5 + 0.5)), zb - zf + 1.0, 19.0, 5.0)
	# Cornisas.
	_box(stone, Transform3D(Basis.IDENTITY, Vector3(xc, floor_y + nave_h - 0.2, (zf + zb) * 0.5)), Vector3(18.6, 0.4, zb - zf + 0.2))
	_box(stone, Transform3D(Basis.IDENTITY, Vector3(xc, floor_y + 0.6, (zf + zb) * 0.5)), Vector3(18.3, 1.2, zb - zf + 0.2))
	# Ábside semicircular.
	_cyl(wall, Vector3(xc, floor_y, zb), Vector3(xc, floor_y + 12.0, zb), 7.5, 7.5, 12, false)
	_cyl(Palette.roof_tile(), Vector3(xc, floor_y + 12.0, zb), Vector3(xc, floor_y + 15.5, zb), 7.9, 0.4, 12, true)
	_col_cyl(Vector3(xc, floor_y + 6.0, zb), 7.5, 12.0)
	# Ventanas de arco de medio punto en los costados.
	var z := zf + 6.0
	while z < zb - 3.0:
		for sx: float in [-1.0, 1.0]:
			var wx: float = xc + sx * 9.03
			var wb := Basis(Vector3.UP, sx * PI * 0.5)
			_box(dark, Transform3D(wb, Vector3(wx, floor_y + 7.0, z)), Vector3(1.4, 4.0, 0.08))
			_cyl(dark, Vector3(wx, floor_y + 9.0, z), Vector3(wx + sx * 0.08, floor_y + 9.0, z), 0.7, 0.7, 10, true)
			_cyl(stone, Vector3(wx - sx * 0.02, floor_y + 9.0, z), Vector3(wx + sx * 0.05, floor_y + 9.0, z), 0.95, 0.95, 10, true)
		z += 6.0
	# Fachada principal: frontón, portal, rosetón.
	var fz := zf - 0.05
	_box(wall, Transform3D(Basis.IDENTITY, Vector3(xc, floor_y + 9.0, zf - 0.4)), Vector3(13.0, 18.0, 0.8))
	_gable(wall, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(xc, floor_y + 18.0, zf - 0.4)), 0.8, 13.0, 4.0)
	_box(stone, Transform3D(Basis.IDENTITY, Vector3(xc, floor_y + 18.0, zf - 0.6)), Vector3(13.4, 0.35, 0.6))
	_cyl(Palette.metal_dark(), Vector3(xc, floor_y + 22.0, zf - 0.4), Vector3(xc, floor_y + 24.0, zf - 0.4), 0.06, 0.06, 4, false)
	_box(Palette.metal_dark(), Transform3D(Basis.IDENTITY, Vector3(xc, floor_y + 23.4, zf - 0.4)), Vector3(0.9, 0.1, 0.1))
	for d in [[0.0, 2.0, 4.6], [-4.3, 1.1, 3.0], [4.3, 1.1, 3.0]]:
		var dx: float = d[0]
		var r: float = d[1]
		var h: float = d[2]
		_box(stone, Transform3D(Basis.IDENTITY, Vector3(xc + dx, floor_y + h * 0.5, fz - 0.35)), Vector3(r * 2.0 + 0.9, h + 0.2, 0.25))
		_cyl(stone, Vector3(xc + dx, floor_y + h, fz - 0.3), Vector3(xc + dx, floor_y + h, fz - 0.5), r + 0.45, r + 0.45, 14, true)
		_box(Palette.wood(), Transform3D(Basis.IDENTITY, Vector3(xc + dx, floor_y + h * 0.5, fz - 0.55)), Vector3(r * 2.0, h, 0.1))
		_cyl(dark, Vector3(xc + dx, floor_y + h, fz - 0.5), Vector3(xc + dx, floor_y + h, fz - 0.56), r, r, 14, true)
	_cyl(stone, Vector3(xc, floor_y + 11.0, fz - 0.3), Vector3(xc, floor_y + 11.0, fz - 0.55), 2.6, 2.6, 16, true)
	_cyl(WorldMaterials.rosette(), Vector3(xc, floor_y + 11.0, fz - 0.55), Vector3(xc, floor_y + 11.0, fz - 0.6), 2.1, 2.1, 16, true)
	# Torres campanario.
	for sx: float in [-1.0, 1.0]:
		var tx: float = xc + sx * 8.5
		var tz := zf + 1.8
		var tb := floor_y
		var shaft := Transform3D(Basis.IDENTITY, Vector3(tx, tb + 11.0, tz))
		_box(wall, shaft, Vector3(5.2, 22.0, 5.2))
		_col_box(shaft, Vector3(5.2, 22.0, 5.2))
		for yy: float in [8.0, 15.0, 22.0]:
			_box(stone, Transform3D(Basis.IDENTITY, Vector3(tx, tb + yy, tz)), Vector3(5.6, 0.4, 5.6))
		# Campanario con vanos de arco en las cuatro caras.
		_box(wall, Transform3D(Basis.IDENTITY, Vector3(tx, tb + 25.0, tz)), Vector3(4.6, 6.0, 4.6))
		for k in 4:
			var fb := Basis(Vector3.UP, k * PI * 0.5)
			var n := fb * Vector3(0, 0, 1)
			var c := Vector3(tx, tb + 24.6, tz) + n * 2.32
			_box(dark, Transform3D(fb, c), Vector3(1.6, 3.2, 0.06))
			_cyl(dark, c + Vector3(0, 1.6, 0), c + Vector3(0, 1.6, 0) + n * 0.06, 0.8, 0.8, 10, true)
		_box(stone, Transform3D(Basis.IDENTITY, Vector3(tx, tb + 28.2, tz)), Vector3(5.2, 0.45, 5.2))
		_cyl(Palette.roof_tile(), Vector3(tx, tb + 28.4, tz), Vector3(tx, tb + 35.0, tz), 3.1, 0.05, 4, true)
		_cyl(Palette.metal_dark(), Vector3(tx, tb + 35.0, tz), Vector3(tx, tb + 36.6, tz), 0.05, 0.05, 4, false)
		_box(Palette.metal_dark(), Transform3D(Basis.IDENTITY, Vector3(tx, tb + 36.1, tz)), Vector3(0.7, 0.08, 0.08))
		# Ventanas angostas del fuste.
		for yy: float in [5.0, 12.0, 18.5]:
			_box(dark, Transform3D(Basis.IDENTITY, Vector3(tx, tb + yy, tz - 2.63)), Vector3(0.6, 1.8, 0.06))
		# Reloj en la torre oriental.
		if sx > 0.0:
			var cc := Vector3(tx, tb + 20.0, tz - 2.62)
			_cyl(stone, cc, cc + Vector3(0, 0, -0.08), 1.2, 1.2, 16, true)
			_cyl(WorldMaterials.clock_face(), cc + Vector3(0, 0, -0.08), cc + Vector3(0, 0, -0.12), 1.0, 1.0, 16, true)
			_box(Palette.metal_dark(), Transform3D(Basis(Vector3.BACK, 0.5), cc + Vector3(0.15, 0.25, -0.15)), Vector3(0.06, 0.7, 0.03))
			_box(Palette.metal_dark(), Transform3D(Basis(Vector3.BACK, -1.2), cc + Vector3(-0.2, 0.08, -0.15)), Vector3(0.06, 0.5, 0.03))
	# Plazuela del Sufragio en la esquina con la Cra 39 (aproximada): baldosa, árboles, bancas.
	_tslab(Palette.plaza_tile(), Palette.curb(), -59.0, -46.0, -34.0, 20.0, 0.02, -0.05)
	for pz: float in [-26.0, -12.0, 2.0, 14.0]:
		_tree(Vector3(-52.5, walk_y(-52.5), pz), _rng.randf_range(0.9, 1.2), 1 if pz == -12.0 else 0)
		_bench(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-49.0, walk_y(-49.0) + 0.02, pz + 5.0)))
	# Atrio: faroles.
	_park_lamp(Vector3(xc - 9.5, walk_y(xc - 9.5), -33.2), false)
	_park_lamp(Vector3(xc + 9.5, walk_y(xc + 9.5), -33.2), false)


# ------------------------------------------------------------------ teatro (La Playa con Cra 40)
func _build_theatre() -> void:
	var x0 := -112.0
	var x1 := -60.0
	var z0 := 222.0
	var z1 := 258.0
	_excl.append(Rect2(x0 - 1.0, z0 - 8.0, x1 - x0 + 2.0, z1 - z0 + 8.0))
	var gy := walk_y(x1)
	var bot := walk_y(x0) - 1.0
	var conc := Palette.concrete()
	var main_xf := Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, (gy + 14.0 + bot) * 0.5, (z0 + z1) * 0.5 + 3.0))
	var main_sz := Vector3(x1 - x0, gy + 14.0 - bot, z1 - z0 - 6.0)
	_box(Palette.brick(), main_xf, main_sz)
	_col_box(main_xf, main_sz)
	# Caja escénica más alta y marquesina en voladizo.
	var fly := Transform3D(Basis.IDENTITY, Vector3(-74.0, (gy + 20.0 + bot) * 0.5, 246.0))
	_box(conc, fly, Vector3(22.0, gy + 20.0 - bot, 20.0))
	_box(conc, Transform3D(Basis.IDENTITY, Vector3(-86.0, gy + 4.6, z0 - 2.0)), Vector3(40.0, 0.4, 8.0))
	for px: float in [-104.0, -94.0, -78.0, -68.0]:
		_cyl(conc, Vector3(px, walk_y(px) - 0.2, z0 - 5.5), Vector3(px, gy + 4.5, z0 - 5.5), 0.25, 0.25, 8, false)
		_col_cyl(Vector3(px, walk_y(px) + 2.0, z0 - 5.5), 0.25, 4.5)
	_box(WorldMaterials.shop_interior(), Transform3D(Basis.IDENTITY, Vector3(-86.0, walk_y(-86.0) + 2.0, z0 + 0.05)), Vector3(30.0, 4.0, 0.12))
	var sign_xf := Transform3D(Basis(Vector3.UP, PI), Vector3(-86.0, gy + 5.6, z0 - 6.05))
	_box(WorldMaterials.sign_panel(), sign_xf, Vector3(16.0, 1.6, 0.2))
	_box(Palette.neon(Color(1.0, 0.65, 0.15)), sign_xf.translated_local(Vector3(0, 0.85, 0.12)), Vector3(16.0, 0.08, 0.08), false)
	_box(Palette.neon(Color(1.0, 0.65, 0.15)), sign_xf.translated_local(Vector3(0, -0.85, 0.12)), Vector3(16.0, 0.08, 0.08), false)
	_label("TEATRO", sign_xf.translated_local(Vector3(0, 0, 0.12)), Color(1.0, 0.75, 0.3), 140, 0.008)


# ------------------------------------------------------------------ manzanas y edificios
func _build_blocks() -> void:
	for cx in _cells(_xs, X_MIN, X_MAX):
		for cz in _cells(_zs, Z_MIN, Z_MAX):
			if _is_park_cell(cx, cz):
				continue
			var x0: float = cx.a + (float(cx.lo.walk) if cx.lo != null else 0.0)
			var x1: float = cx.b - (float(cx.hi.walk) if cx.hi != null else 0.0)
			var z0: float = cz.a + (float(cz.lo.walk) if cz.lo != null else 0.0)
			var z1: float = cz.b - (float(cz.hi.walk) if cz.hi != null else 0.0)
			if x1 - x0 < 8.0 or z1 - z0 < 8.0:
				continue
			var edge: bool = cx.lo == null or cx.hi == null or cz.lo == null or cz.hi == null
			var dns := minf(15.0, (z1 - z0) * 0.5)
			var dew := minf(15.0, (x1 - x0) * 0.5)
			var has_n: bool = cz.lo != null
			var has_s: bool = cz.hi != null
			if has_n:
				_frontage(Vector3(x0, 0, z0), Vector3(x1, 0, z0), PI, dns, cz.lo.id in MAIN_IDS)
			if has_s:
				_frontage(Vector3(x0, 0, z1), Vector3(x1, 0, z1), 0.0, dns, cz.hi.id in MAIN_IDS)
			var za: float = z0 + (dns if has_n else 0.0)
			var zb: float = z1 - (dns if has_s else 0.0)
			if cx.lo != null and zb - za > 6.0:
				_frontage(Vector3(x0, 0, za), Vector3(x0, 0, zb), -PI * 0.5, dew, cx.lo.id in MAIN_IDS)
			if cx.hi != null and zb - za > 6.0:
				_frontage(Vector3(x1, 0, za), Vector3(x1, 0, zb), PI * 0.5, dew, cx.hi.id in MAIN_IDS)
			# Relleno del interior de manzana (patios / techos bajos), y cierre alto en el borde.
			var ix0: float = x0 + (dew if cx.lo != null else 0.0) - 0.5
			var ix1: float = x1 - (dew if cx.hi != null else 0.0) + 0.5
			var iz0: float = z0 + (dns if has_n else 0.0) - 0.5
			var iz1: float = z1 - (dns if has_s else 0.0) + 0.5
			if ix1 - ix0 > 2.0 and iz1 - iz0 > 2.0:
				var r := Rect2(ix0, iz0, ix1 - ix0, iz1 - iz0)
				if not _hits_excl(r):
					var h := 14.0 if edge else _rng.randf_range(3.5, 6.0)
					var by := walk_y(ix0) - 1.0
					var top := walk_y((ix0 + ix1) * 0.5) + h
					var fxf := Transform3D(Basis.IDENTITY, Vector3((ix0 + ix1) * 0.5, (top + by) * 0.5, (iz0 + iz1) * 0.5))
					_box(Palette.concrete() if edge else (Palette.roof_tile() if _rng.randf() < 0.6 else WorldMaterials.roof_flat()), fxf, Vector3(ix1 - ix0, top - by, iz1 - iz0))
					if edge:
						_col_box(fxf, Vector3(ix1 - ix0, top - by, iz1 - iz0))


func _hits_excl(r: Rect2) -> bool:
	for e in _excl:
		if e.intersects(r):
			return true
	return false


func _frontage(a: Vector3, b: Vector3, angle: float, depth: float, main: bool) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var out := Vector3(sin(angle), 0, cos(angle))
	var t := 0.0
	while t < length - 0.5:
		var w := _rng.randf_range(7.0, 15.0)
		if length - (t + w) < 6.0:
			w = length - t
		var mid := a + dir * (t + w * 0.5)
		var c0 := mid - dir * w * 0.5
		var c1 := mid + dir * w * 0.5 - out * depth
		var rect := Rect2(minf(c0.x, c1.x), minf(c0.z, c1.z), absf(c1.x - c0.x), absf(c1.z - c0.z))
		if not _hits_excl(rect):
			var xf := Transform3D(Basis(Vector3.UP, angle), Vector3(mid.x, walk_y(mid.x), mid.z))
			_building(xf, w, depth, main)
		t += w


func _building(xf: Transform3D, w: float, d: float, main: bool) -> void:
	var r := _rng.randf()
	var shop := _rng.randf() < (0.75 if main else 0.22)
	var near := absf(xf.origin.x) < 130.0 and absf(xf.origin.z) < 130.0
	_cur_main = main
	if r < (0.38 if main else 0.5):
		_house(xf, w, d, shop, near)
	elif r < 0.82:
		var floors := 4 + int(pow(_rng.randf(), 2.0) * 6.0)
		_apartment(xf, w, d, shop, Palette.brick(), floors, near)
	else:
		_apartment(xf, w, d, shop, Palette.stucco(_rng.randi_range(0, 5)), _rng.randi_range(3, 6), near)


## Casa antigua de dos pisos: alero de teja, balcón de madera/hierro, rejas.
func _house(xf: Transform3D, w: float, d: float, shop: bool, near: bool) -> void:
	var g := 3.4 if shop else 3.1
	var h := g + 3.0
	var wall := Palette.stucco(_rng.randi_range(0, 5))
	var trim := Palette.stucco(_rng.randi_range(0, 5))
	_box(wall, xf.translated_local(Vector3(0, (h - 1.2) * 0.5, -d * 0.5)), Vector3(w, h + 1.2, d))
	_col_box(xf.translated_local(Vector3(0, (h - 1.2) * 0.5, -d * 0.5)), Vector3(w, h + 1.2, d))
	_box(trim, xf.translated_local(Vector3(0, -0.3, 0.03)), Vector3(w, 1.8, 0.06))   # zócalo
	_box(trim, xf.translated_local(Vector3(0, g, 0.05)), Vector3(w, 0.2, 0.1))       # cornisa de entrepiso
	# Techo a dos aguas con alero sobre el andén.
	_gable(Palette.roof_tile(), xf.translated_local(Vector3(0, h, (-d - 0.3 + 1.0) * 0.5)), w + 0.06, d + 1.3, 1.6)
	_box(Palette.wood(), xf.translated_local(Vector3(0, h - 0.08, 0.5)), Vector3(w, 0.12, 0.95))
	if shop:
		_shopfront(xf, w, g)
	else:
		_box(Palette.wood(), xf.translated_local(Vector3(-w * 0.5 + 1.1, 1.15, 0.04)), Vector3(1.1, 2.3, 0.08))
		_window_row(xf, -w * 0.5 + 2.2, w * 0.5 - 0.3, 1.65, 1.1, 1.4, 2.4, near, 0.25)
	# Segundo piso: ventanas altas y quizá balcón.
	var up_y := g + 1.45
	_window_row(xf, -w * 0.5 + 0.3, w * 0.5 - 0.3, up_y, 1.0, 1.9, 2.3, false, 0.35)
	if _rng.randf() < 0.6:
		var bl := minf(w - 1.0, _rng.randf_range(3.5, 7.0))
		var bmat := Palette.wood() if _rng.randf() < 0.6 else Palette.metal_dark()
		var by := g + 0.15
		_box(Palette.wood(), xf.translated_local(Vector3(0, by, 0.45)), Vector3(bl, 0.12, 0.9))
		_box(bmat, xf.translated_local(Vector3(0, by + 1.0, 0.87)), Vector3(bl, 0.06, 0.06))
		_box(bmat, xf.translated_local(Vector3(0, by + 0.15, 0.87)), Vector3(bl, 0.05, 0.05))
		var u := -bl * 0.5
		while u <= bl * 0.5 + 0.01:
			_box(bmat, xf.translated_local(Vector3(u, by + 0.55, 0.87)), Vector3(0.05, 0.85, 0.05), false, true)
			u += 0.55
		for su: float in [-1.0, 1.0]:
			_box(bmat, xf.translated_local(Vector3(su * bl * 0.5, by + 0.55, 0.45)), Vector3(0.05, 0.9, 0.85))


## Edificio de apartamentos de ladrillo o estuco, 3-9 pisos, balcones sólidos, tanque de agua.
func _apartment(xf: Transform3D, w: float, d: float, shop: bool, mat: Material, floors: int, near: bool) -> void:
	var g := 3.4
	var fh := 2.8
	var h := g + fh * (floors - 1) + 0.8
	_box(mat, xf.translated_local(Vector3(0, (h - 1.2) * 0.5, -d * 0.5)), Vector3(w, h + 1.2, d))
	_col_box(xf.translated_local(Vector3(0, (h - 1.2) * 0.5, -d * 0.5)), Vector3(w, h + 1.2, d))
	var conc := Palette.concrete()
	_box(WorldMaterials.roof_flat(), xf.translated_local(Vector3(0, h + 0.03, -d * 0.5)), Vector3(w - 0.3, 0.06, d - 0.3))
	_box(conc, xf.translated_local(Vector3(0, h + 0.45, 0.0)), Vector3(w, 0.9, 0.2))   # antepecho de fachada
	if shop:
		_shopfront(xf, w, g)
	else:
		_box(Palette.concrete(), xf.translated_local(Vector3(0, g * 0.5 - 0.6, 0.04)), Vector3(w, g + 1.2, 0.08))
		_box(Palette.metal_dark(), xf.translated_local(Vector3(-w * 0.5 + 1.0, 1.15, 0.1)), Vector3(1.2, 2.3, 0.06))
		if w > 9.0:
			_box(WorldMaterials.shutter(), xf.translated_local(Vector3(w * 0.5 - 2.2, 1.3, 0.1)), Vector3(3.2, 2.6, 0.06))
		else:
			_window_row(xf, -w * 0.5 + 2.0, w * 0.5 - 0.3, 1.7, 1.2, 1.3, 2.4, near, 0.3)
	var big := mat != Palette.brick()
	var balcony := _rng.randf() < 0.4
	var bl := minf(w - 1.0, w * 0.5)
	for f in range(1, floors):
		var fy := g + fh * (f - 1)
		_box(conc, xf.translated_local(Vector3(0, fy, 0.06)), Vector3(w + 0.1, 0.18, 0.14))
		_window_row(xf, -w * 0.5 + 0.4, w * 0.5 - 0.4, fy + 1.45, 2.0 if big else 1.4, 1.4, 3.0 if big else 2.4, false, 0.32)
		if balcony:
			_box(conc, xf.translated_local(Vector3(0, fy + 0.05, 0.55)), Vector3(bl, 0.15, 1.1))
			_box(mat, xf.translated_local(Vector3(0, fy + 0.55, 1.08)), Vector3(bl, 0.9, 0.08))
	if _rng.randf() < 0.35:
		var p := xf * Vector3(_rng.randf_range(-w * 0.3, w * 0.3), h + 0.1, -d * 0.5)
		_cyl(Palette.concrete(), p, p + Vector3(0, 1.6, 0), 1.0, 1.0, 8, true)


## Primer piso comercial: interior iluminado o persiana, aviso con neón y toldo.
func _wants_label(xf: Transform3D) -> bool:
	return absf(xf.origin.x) < 130.0 and absf(xf.origin.z) < 130.0 and _cur_main


func _shopfront(xf: Transform3D, w: float, g: float) -> void:
	var ow := maxf(2.5, w - 1.2)
	var oh := g - 0.5
	var open := _rng.randf() < 0.7
	_box(Palette.concrete(), xf.translated_local(Vector3(-w * 0.5 + 0.3, oh * 0.5, 0.08)), Vector3(0.5, oh, 0.16))
	_box(Palette.concrete(), xf.translated_local(Vector3(w * 0.5 - 0.3, oh * 0.5, 0.08)), Vector3(0.5, oh, 0.16))
	if open:
		_box(WorldMaterials.shop_interior(), xf.translated_local(Vector3(0, oh * 0.5, 0.03)), Vector3(ow - 0.4, oh, 0.06), false)
		_box(Palette.metal_dark(), xf.translated_local(Vector3(0, oh + 0.05, 0.1)), Vector3(ow, 0.12, 0.12))
		# Vidriera con marcos y zócalo bajo.
		_box(Palette.metal_dark(), xf.translated_local(Vector3(0, 0.35, 0.09)), Vector3(ow - 0.4, 0.7, 0.08), false)
		var mu := -ow * 0.5 + 0.2 + 1.6
		while mu < ow * 0.5 - 0.6:
			_box(Palette.metal_dark(), xf.translated_local(Vector3(mu, oh * 0.5, 0.09)), Vector3(0.07, oh, 0.07), false, true)
			mu += 1.6
	else:
		_box(WorldMaterials.shutter(), xf.translated_local(Vector3(0, oh * 0.5, 0.06)), Vector3(ow - 0.4, oh, 0.08))
		var y := 0.4
		while y < oh:
			_box(Palette.metal_dark(), xf.translated_local(Vector3(0, y, 0.11)), Vector3(ow - 0.4, 0.03, 0.03), false)
			y += 0.5
	# Aviso.
	var colors := [Color(0.1, 0.9, 1.0), Color(1.0, 0.15, 0.75), Color(1.0, 0.62, 0.1)]
	var col: Color = colors[_rng.randi_range(0, 2)]
	var neon := Palette.neon(col)
	var sw := minf(w - 0.8, 9.0)
	var sy := g - 0.05
	var sxf := xf.translated_local(Vector3(0, sy, 0.14))
	_box(WorldMaterials.sign_panel(), sxf, Vector3(sw, 0.75, 0.18), false)
	_box(neon, sxf.translated_local(Vector3(0, 0.37, 0.1)), Vector3(sw, 0.07, 0.07), false)
	_box(neon, sxf.translated_local(Vector3(0, -0.37, 0.1)), Vector3(sw, 0.07, 0.07), false)
	_box(neon, sxf.translated_local(Vector3(-sw * 0.5, 0, 0.1)), Vector3(0.07, 0.8, 0.07), false)
	_box(neon, sxf.translated_local(Vector3(sw * 0.5, 0, 0.1)), Vector3(0.07, 0.8, 0.07), false)
	var name: String = SHOP_NAMES[_shop_i % SHOP_NAMES.size()]
	_shop_i += 1
	# Texto solo en avisos de vías comerciales cerca del parque (cada Label3D es un draw call).
	if _wants_label(xf) and _labels < MAX_SHOP_LABELS:
		var px: float = 0.21 * minf(1.0, sw / (name.length() * 0.2 + 0.4))
		_label(name.to_upper(), sxf.translated_local(Vector3(0, 0, 0.1)), col.lightened(0.35), 64, px * 0.03)
	# Toldo inclinado.
	if open and _rng.randf() < 0.5:
		_box(WorldMaterials.awning(_rng.randi_range(0, 4)), xf * Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, oh - 0.1, 0.6)), Vector3(ow, 0.05, 1.3))


## Fila de ventanas entre u0 y u1 (local) a la altura y. Quads en MultiMesh; rejas opcionales.
func _window_row(xf: Transform3D, u0: float, u1: float, y: float, ww: float, wh: float, spacing: float, rejas: bool, lit: float) -> void:
	var span := u1 - u0
	if span < ww:
		return
	var n := maxi(1, int(span / spacing))
	var step := span / n
	for i in n:
		var u := u0 + step * (i + 0.5)
		var wxf := xf * Transform3D(Basis.from_scale(Vector3(ww, wh, 1.0)), Vector3(u, y, 0.03))
		_mm_add("win_lit" if _rng.randf() < lit else "win_glass", wxf)
		if rejas:
			var m := Palette.metal_dark()
			for k in 3:
				var bu := u - ww * 0.5 + ww * (k + 0.5) / 3.0
				_box(m, xf.translated_local(Vector3(bu, y, 0.12)), Vector3(0.03, wh, 0.03), false, true)
			_box(m, xf.translated_local(Vector3(u, y + wh * 0.5, 0.12)), Vector3(ww + 0.1, 0.04, 0.12), false)
			_box(m, xf.translated_local(Vector3(u, y - wh * 0.5, 0.12)), Vector3(ww + 0.1, 0.04, 0.12), false)


# ------------------------------------------------------------------ red eléctrica y alumbrado
func _build_poles_and_cables() -> void:
	for s in _xs:
		var x: float = float(s.pos) + (float(s.half) + 0.6 if s.wide else -(float(s.half) + 0.5))
		var pts: Array = []
		var z := Z_MIN + 6.0
		while z < Z_MAX - 6.0:
			var clear := true
			for c in _zs:
				if absf(z - float(c.pos)) < float(c.half) + float(c.walk) + 1.5:
					clear = false
			if absf(x) < 34.0 and absf(z) < 34.0:
				clear = false
			if clear:
				pts.append(Vector3(x, walk_y(x), z))
			z += 33.0
		_pole_line(pts, Vector3(1, 0, 0) * (-1.0 if s.wide else 1.0))
	for s in _zs:
		var zz: float = float(s.pos) + (float(s.half) + 0.6 if s.wide else -(float(s.half) + 0.5))
		var pts2: Array = []
		var xx := X_MIN + 6.0
		while xx < X_MAX - 6.0:
			var clear2 := true
			for c in _xs:
				if absf(xx - float(c.pos)) < float(c.half) + float(c.walk) + 1.5:
					clear2 = false
			if xx > -88.0 and xx < -56.0 and absf(zz + 40.0) < 10.0:
				clear2 = false   # frente a la iglesia
			if clear2:
				pts2.append(Vector3(xx, walk_y(xx), zz))
			xx += 33.0
		_pole_line(pts2, Vector3(0, 0, 1) * (-1.0 if s.wide else 1.0))


## Postes con cruceta, luminaria (uno sí, uno no) y 3 cables con catenaria.
func _pole_line(pts: Array, to_road: Vector3) -> void:
	var conc := WorldMaterials.pole_concrete()
	var metal := Palette.metal_dark()
	var along := Vector3(to_road.z, 0, -to_road.x)
	for i in pts.size():
		var p: Vector3 = pts[i]
		_cyl(conc, p + Vector3(0, -0.3, 0), p + Vector3(0, 9.6, 0), 0.17, 0.11, 6, true)
		_box(conc, Transform3D(Basis.looking_at(along), p + Vector3(0, 9.0, 0)), Vector3(1.8, 0.14, 0.14))
		_col_cyl(p + Vector3(0, 4.5, 0), 0.17, 9.0)
		if i % 2 == 0:
			var a := p + Vector3(0, 7.8, 0)
			var b := a + to_road * 2.2 + Vector3(0, 0.35, 0)
			_cyl(metal, a, b, 0.05, 0.04, 4, false)
			_box(metal, Transform3D(Basis.looking_at(to_road), b + to_road * 0.25), Vector3(0.3, 0.14, 0.7), false)
			_mm_add("bulb", Transform3D(Basis.from_scale(Vector3(0.22, 0.06, 0.4)), b + to_road * 0.25 + Vector3(0, -0.08, 0)))
		if i > 0:
			var q: Vector3 = pts[i - 1]
			if p.distance_to(q) < 45.0:
				for k in [-0.8, 0.0, 0.8]:
					var off: Vector3 = to_road * k + Vector3(0, 9.1, 0)
					_cable(q + off, p + off, 0.45)


func _cable(a: Vector3, b: Vector3, sag: float) -> void:
	var segs := 4
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t) + Vector3(0, -4.0 * sag * t * (1.0 - t), 0)
		_cyl(Palette.metal_dark(), prev, p, 0.022, 0.022, 3, false, false)
		prev = p


func _build_traffic_lights() -> void:
	for k in _xs:
		for c in _zs:
			var important: bool = (k.id in ["K38", "K39"] and c.id in ["C54", "C55"]) or k.wide or c.wide or (c.id == "C58" and k.id in ["K38", "K40"])
			if not important:
				continue
			var cx: float = k.pos
			var cz: float = c.pos
			var kh: float = k.half
			var chh: float = c.half
			var carrera_green := _rng.randf() < 0.5
			# SE: tráfico hacia el norte (viene del sur). NW: hacia el sur. NE: hacia el oeste. SW: hacia el este.
			_signal(Vector3(cx + kh + 0.9, 0, cz + chh + 0.9), Vector3(-1, 0, 0), kh, Vector3(0, 0, 1), carrera_green)
			_signal(Vector3(cx - kh - 0.9, 0, cz - chh - 0.9), Vector3(1, 0, 0), kh, Vector3(0, 0, -1), carrera_green)
			_signal(Vector3(cx + kh + 0.9, 0, cz - chh - 0.9), Vector3(0, 0, 1), chh, Vector3(1, 0, 0), not carrera_green)
			_signal(Vector3(cx - kh - 0.9, 0, cz + chh + 0.9), Vector3(0, 0, -1), chh, Vector3(-1, 0, 0), not carrera_green)


func _signal(p: Vector3, arm_dir: Vector3, arm_len: float, face: Vector3, green: bool) -> void:
	var metal := Palette.metal_dark()
	var base := Vector3(p.x, walk_y(p.x), p.z)
	_cyl(metal, base + Vector3(0, -0.2, 0), base + Vector3(0, 5.6, 0), 0.1, 0.08, 6, true)
	_col_cyl(base + Vector3(0, 2.8, 0), 0.12, 5.6)
	var reach: float = minf(arm_len + 0.5, 7.0)
	var tip := base + Vector3(0, 5.4, 0) + arm_dir * reach
	_cyl(metal, base + Vector3(0, 5.4, 0), tip, 0.06, 0.05, 4, false)
	var hb := Basis.looking_at(-face)   # el frente local +Z mira hacia `face`
	var head := Transform3D(hb, tip + Vector3(0, -0.6, 0))
	_box(metal, head, Vector3(0.42, 1.15, 0.3), false)
	var cols := [Color(1, 0.1, 0.05), Color(1, 0.6, 0.05), Color(0.1, 1, 0.45)]
	var on := 2 if green else 0
	for i in 3:
		var m: Material = Palette.neon(cols[i], 3.0) if i == on else WorldMaterials.signal_off()
		_box(m, head.translated_local(Vector3(0, 0.35 - i * 0.35, 0.16)), Vector3(0.24, 0.24, 0.04), false)
	# Repetidor bajo en el poste.
	var low := Transform3D(hb, base + Vector3(0, 2.8, 0) + face * 0.2)
	_box(metal, low, Vector3(0.3, 0.85, 0.22), false)
	for i in 3:
		var m2: Material = Palette.neon(cols[i], 3.0) if i == on else WorldMaterials.signal_off()
		_box(m2, low.translated_local(Vector3(0, 0.26 - i * 0.26, 0.12)), Vector3(0.17, 0.17, 0.03), false)


func _build_street_trees() -> void:
	# La Playa: bulevar arborizado en el separador.
	for s in _zs:
		if s.wide:
			var x := X_MIN + 8.0
			while x < X_MAX - 8.0:
				var ok := true
				for c in _xs:
					if absf(x - float(c.pos)) < float(c.half) + 6.0:
						ok = false
				if ok:
					var roll := _rng.randf()
					_tree(Vector3(x, walk_y(x), float(s.pos)), _rng.randf_range(1.1, 1.5), 1 if roll < 0.25 else (2 if roll < 0.4 else 0))
				x += 11.0
	for s in _xs:
		if s.wide:
			var z := Z_MIN + 8.0
			while z < Z_MAX - 8.0:
				var ok2 := true
				for c in _zs:
					if absf(z - float(c.pos)) < float(c.half) + 6.0:
						ok2 = false
				if ok2:
					_tree(Vector3(float(s.pos), walk_y(float(s.pos)), z), _rng.randf_range(0.8, 1.1), 0 if _rng.randf() < 0.8 else 1)
				z += 14.0
	# Árboles sueltos en andenes de calles normales.
	for s in _zs:
		if s.wide:
			continue
		var x2 := X_MIN + 15.0
		while x2 < X_MAX - 15.0:
			if _rng.randf() < 0.12:
				var ok3 := true
				for c in _xs:
					if absf(x2 - float(c.pos)) < float(c.half) + 8.0:
						ok3 = false
				if absf(x2) < 40.0 or (x2 > -90.0 and x2 < -54.0):
					ok3 = false
				if ok3:
					var zz: float = float(s.pos) + float(s.half) + 1.0
					_tree(Vector3(x2, walk_y(x2), zz), _rng.randf_range(0.6, 0.85), 0)
			x2 += 9.0


## kind: 0 = verde, 1 = guayacán amarillo, 2 = guayacán rosado.
func _tree(base: Vector3, s: float, kind: int) -> void:
	var trunk_h := 5.0 * s
	_mm_add("trunk", Transform3D(Basis.from_scale(Vector3(s, trunk_h, s)), base + Vector3(0, trunk_h * 0.5 - 0.1, 0)))
	_col_cyl(base + Vector3(0, 1.5, 0), 0.25 * s, 3.0)
	var leaf := "leaf" if kind == 0 else ("leaf_y" if kind == 1 else "leaf_p")
	var n := 3 + _rng.randi_range(0, 2)
	for i in n:
		var a := TAU * i / n + _rng.randf()
		var r := _rng.randf_range(0.8, 1.6) * s
		var c := base + Vector3(cos(a) * r, trunk_h + _rng.randf_range(-0.2, 1.2) * s, sin(a) * r)
		var sc := _rng.randf_range(1.8, 2.6) * s
		_mm_add(leaf, Transform3D(Basis.from_scale(Vector3(sc, sc * 0.75, sc)), c))
	_mm_add(leaf, Transform3D(Basis.from_scale(Vector3(2.4, 1.9, 2.4) * s), base + Vector3(0, trunk_h + 1.4 * s, 0)))


func _build_small_furniture() -> void:
	# Canecas en esquinas del parque y aleatorias en andenes cerca del centro.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_bin(Vector3(sx * 33.0, 0, sz * 30.5))
	for k in _xs:
		for c in _zs:
			var kx: float = k.pos
			var cz: float = c.pos
			if absf(kx) > 300.0 or absf(cz) > 250.0:
				continue
			var corner := Vector3(kx + (float(k.half) + 1.2) * (1.0 if _rng.randf() < 0.5 else -1.0), 0,
				cz + (float(c.half) + 3.0) * (1.0 if _rng.randf() < 0.5 else -1.0))
			var roll := _rng.randf()
			if roll < 0.35:
				_hydrant(corner)
			elif roll < 0.65:
				_bin(corner)


func _bin(p: Vector3) -> void:
	var base := Vector3(p.x, walk_y(p.x), p.z)
	_cyl(WorldMaterials.bin_green(), base, base + Vector3(0, 0.95, 0), 0.3, 0.33, 8, true)
	_cyl(Palette.metal_dark(), base + Vector3(0, 0.95, 0), base + Vector3(0, 1.02, 0), 0.35, 0.35, 8, true)
	_col_cyl(base + Vector3(0, 0.5, 0), 0.34, 1.0)


func _hydrant(p: Vector3) -> void:
	var base := Vector3(p.x, walk_y(p.x), p.z)
	var m := WorldMaterials.hydrant()
	_cyl(m, base, base + Vector3(0, 0.6, 0), 0.15, 0.14, 8, true)
	_cyl(m, base + Vector3(0, 0.6, 0), base + Vector3(0, 0.75, 0), 0.17, 0.06, 8, true)
	_cyl(m, base + Vector3(-0.25, 0.42, 0), base + Vector3(0.25, 0.42, 0), 0.06, 0.06, 6, true)
	_col_cyl(base + Vector3(0, 0.38, 0), 0.18, 0.76)


func _build_cones() -> void:
	# Pequeña obra en la Calle 55 frente a la cuadra de la iglesia y en la Cra 38: conos tumbables.
	var spots: Array = []
	for i in 6:
		spots.append(Vector3(-100.0 + i * 2.2, 0, -40.0 + 2.2))
	for i in 4:
		spots.append(Vector3(40.0 - 2.3, 0, -70.0 - i * 2.4))
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.17
	mesh.height = 0.7
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.material = WorldMaterials.cone_orange()
	var band := CylinderMesh.new()
	band.top_radius = 0.085
	band.bottom_radius = 0.11
	band.height = 0.12
	band.radial_segments = 8
	band.rings = 1
	band.material = WorldMaterials.paint_white()
	var shape := CylinderShape3D.new()
	shape.radius = 0.15
	shape.height = 0.7
	var foot := BoxShape3D.new()
	foot.size = Vector3(0.4, 0.04, 0.4)
	for p in spots:
		var rb := RigidBody3D.new()
		rb.name = "Cono"
		rb.collision_layer = 1 << 3
		rb.collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)
		rb.mass = 2.5
		rb.add_to_group("props")
		rb.position = Vector3(p.x, road_y(p.x) + 0.37, p.z)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		rb.add_child(mi)
		var bi := MeshInstance3D.new()
		bi.mesh = band
		bi.position = Vector3(0, 0.1, 0)
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(bi)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		rb.add_child(cs)
		var fs := CollisionShape3D.new()
		fs.shape = foot
		fs.position = Vector3(0, -0.33, 0)
		rb.add_child(fs)
		rb.sleeping = true
		add_child(rb)


# ------------------------------------------------------------------ spawns y límites
func _build_spawns() -> void:
	var sp := Marker3D.new()
	sp.name = "SpawnPlayer"
	sp.add_to_group("spawn_player")
	# Frente a la estatua (lado sur), mirando al norte hacia el monumento.
	sp.position = Vector3(0.0, walk_y(0.0) + 0.1, 9.0)
	add_child(sp)
	# Autos estacionados contra el sardinel, mirando en el sentido del carril (tráfico por la derecha).
	# Convención: el frente del vehículo es -Z local del Marker (como Node3D.look_at).
	var cars := [
		["taxi", "C55", 1.0, -20.0], ["sedan", "C55", -1.0, 12.0],
		["taxi", "C54", 1.0, 16.0], ["pickup", "C54", -1.0, -18.0],
		["sedan", "K38", -1.0, 14.0], ["taxi", "K39", 1.0, -14.0],
		["pickup", "K39", -1.0, 18.0], ["buseta", "C52", 1.0, -10.0],
		["buseta", "K43", -1.0, 10.0], ["sedan", "C58", 1.0, 20.0],
	]
	for c in cars:
		var kind: String = c[0]
		var sid: String = c[1]
		var dir: float = c[2]          # +1 = hacia +X / hacia el norte(-Z) en carreras
		var along: float = c[3]
		var s := _street(sid)
		var is_carrera := sid.begins_with("K")
		var half: float = s.half
		var curb_off := half - 1.6   # deja ~0.6 m al sardinel para poder arrancar sin rozarlo
		var pos := Vector3.ZERO
		var fwd := Vector3.ZERO
		if is_carrera:
			# Hacia el norte (-Z) se va por el carril oriental (+X).
			fwd = Vector3(0, 0, -dir)
			pos = Vector3(float(s.pos) + dir * curb_off, 0, along)
		else:
			# Hacia el este (+X) se va por el carril sur (+Z).
			fwd = Vector3(dir, 0, 0)
			pos = Vector3(along, 0, float(s.pos) + dir * curb_off)
		pos.y = road_y(pos.x) + 0.3
		var m := Marker3D.new()
		m.name = "SpawnVehicle_%s_%s" % [kind, sid]
		m.add_to_group("spawn_vehicle")
		m.set_meta("kind", kind)
		m.transform = Transform3D(Basis.looking_at(fwd), pos)
		add_child(m)


func _street(id: String) -> Dictionary:
	for s in _xs + _zs:
		if s.id == id:
			return s
	return {}


func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "Limites"
	body.collision_layer = 1
	body.collision_mask = 0
	var walls := [
		[Vector3(X_MIN - 1.0, 0, (Z_MIN + Z_MAX) * 0.5), Vector3(2, 120, Z_MAX - Z_MIN + 4)],
		[Vector3(X_MAX + 1.0, 0, (Z_MIN + Z_MAX) * 0.5), Vector3(2, 120, Z_MAX - Z_MIN + 4)],
		[Vector3((X_MIN + X_MAX) * 0.5, 0, Z_MIN - 1.0), Vector3(X_MAX - X_MIN + 4, 120, 2)],
		[Vector3((X_MIN + X_MAX) * 0.5, 0, Z_MAX + 1.0), Vector3(X_MAX - X_MIN + 4, 120, 2)],
		[Vector3((X_MIN + X_MAX) * 0.5, -40.0, (Z_MIN + Z_MAX) * 0.5), Vector3(X_MAX - X_MIN + 4, 2, Z_MAX - Z_MIN + 4)],
	]
	for wv in walls:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = wv[1]
		cs.shape = b
		cs.position = wv[0]
		body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------------ geometría base
func _st(mat: Material, pos: Vector3, shadow: bool) -> SurfaceTool:
	var cx := clampi(int((pos.x - X_MIN) / (X_MAX - X_MIN) * CHUNKS), 0, CHUNKS - 1)
	var cz := clampi(int((pos.z - Z_MIN) / (Z_MAX - Z_MIN) * CHUNKS), 0, CHUNKS - 1)
	var key := "%d_%d_%d_%d" % [cx, cz, mat.get_instance_id(), int(shadow)]
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"st": st, "mat": mat, "shadow": shadow, "name": "%d_%d" % [cx, cz]}
	return _batches[key].st


## Cuadrilátero con sombreado plano; corrige el orden para que el frente mire hacia n
## (Godot: caras frontales en sentido horario).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = d
		d = t
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


func _col_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = d
		d = t
	_col_faces.append_array([a, b, c, a, c, d])


## Caja orientada. Omite la cara inferior si queda enterrada; `bar` = sin tapas (barrotes).
func _box(mat: Material, xf: Transform3D, size: Vector3, shadow := true, bar := false) -> void:
	var st := _st(mat, xf.origin, shadow)
	var h := size * 0.5
	var bottom := (xf * Vector3(0, -h.y, 0)).y
	var buried := bottom <= walk_y(xf.origin.x) + 0.05 and absf(xf.basis.y.y) > 0.99
	for f in _BOX_FACES:
		var n: Vector3 = f[0]
		if n.y < -0.5 and (buried or bar):
			continue
		if n.y > 0.5 and bar:
			continue
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var uu := u * h
		var vv := v * h
		_quad(st, xf * (c - uu - vv), xf * (c + uu - vv), xf * (c + uu + vv), xf * (c - uu + vv), (xf.basis * n).normalized())


## Cilindro / cono entre a y b (radios ra, rb), sombreado plano.
func _cyl(mat: Material, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, caps: bool, shadow := true) -> void:
	var st := _st(mat, (a + b) * 0.5, shadow)
	var axis := b - a
	if axis.length() < 0.0001:
		return
	axis = axis.normalized()
	var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var p1 := axis.cross(ref).normalized()
	var p2 := axis.cross(p1).normalized()
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := p1 * cos(a0) + p2 * sin(a0)
		var d1 := p1 * cos(a1) + p2 * sin(a1)
		var n := (d0 + d1).normalized()
		if rb < 0.001:
			_tri(st, a + d0 * ra, a + d1 * ra, b, (n + axis * (ra / (b - a).length())).normalized())
		else:
			_quad(st, a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb, n)
		if caps:
			_tri(st, a, a + d0 * ra, a + d1 * ra, -axis)
			if rb >= 0.001:
				_tri(st, b, b + d0 * rb, b + d1 * rb, axis)


## Prisma a dos aguas: base w (x) × d (z) en y=0 local, cumbrera paralela a X a altura h.
func _gable(mat: Material, xf: Transform3D, w: float, d: float, h: float) -> void:
	var st := _st(mat, xf.origin, true)
	var x := w * 0.5
	var z := d * 0.5
	var A := xf * Vector3(-x, 0, -z)
	var B := xf * Vector3(x, 0, -z)
	var C := xf * Vector3(x, 0, z)
	var D := xf * Vector3(-x, 0, z)
	var R0 := xf * Vector3(-x, h, 0)
	var R1 := xf * Vector3(x, h, 0)
	var nb := xf.basis
	_quad(st, D, C, R1, R0, (nb * Vector3(0, z, h)).normalized())
	_quad(st, A, B, R1, R0, (nb * Vector3(0, z, -h)).normalized())
	_tri(st, A, D, R0, (nb * Vector3(-1, 0, 0)).normalized())
	_tri(st, B, C, R1, (nb * Vector3(1, 0, 0)).normalized())
	_quad(st, A, B, C, D, (nb * Vector3(0, -1, 0)).normalized())


## Cara superior inclinada (y = SLOPE*x + off) subdividida por nada; opcionalmente con colisión.
func _tilted_top(mat: Material, x0: float, x1: float, z0: float, z1: float, off: float, collide: bool, shadow: bool) -> void:
	var st := _st(mat, Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5), shadow)
	var n := Vector3(-SLOPE, 1.0, 0.0).normalized()
	var a := Vector3(x0, SLOPE * x0 + off, z0)
	var b := Vector3(x1, SLOPE * x1 + off, z0)
	var c := Vector3(x1, SLOPE * x1 + off, z1)
	var d := Vector3(x0, SLOPE * x0 + off, z1)
	_quad(st, a, b, c, d, n)
	if collide:
		_col_quad(a, b, c, d, n)


## Losa inclinada con tapa (top_mat) y costados (side_mat), con colisión.
func _tslab(top_mat: Material, side_mat: Material, x0: float, x1: float, z0: float, z1: float, top: float, bot: float) -> void:
	_tilted_top(top_mat, x0, x1, z0, z1, top, true, false)
	var st := _st(side_mat, Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5), false)
	var t0 := SLOPE * x0 + top
	var t1 := SLOPE * x1 + top
	var b0 := SLOPE * x0 + bot
	var b1 := SLOPE * x1 + bot
	var sides := [
		[Vector3(x0, b0, z0), Vector3(x1, b1, z0), Vector3(x1, t1, z0), Vector3(x0, t0, z0), Vector3(0, 0, -1)],
		[Vector3(x0, b0, z1), Vector3(x1, b1, z1), Vector3(x1, t1, z1), Vector3(x0, t0, z1), Vector3(0, 0, 1)],
		[Vector3(x0, b0, z0), Vector3(x0, b0, z1), Vector3(x0, t0, z1), Vector3(x0, t0, z0), Vector3(-1, 0, 0)],
		[Vector3(x1, b1, z0), Vector3(x1, b1, z1), Vector3(x1, t1, z1), Vector3(x1, t1, z0), Vector3(1, 0, 0)],
	]
	for s in sides:
		_quad(st, s[0], s[1], s[2], s[3], s[4])
		_col_quad(s[0], s[1], s[2], s[3], s[4])


func _col_box(xf: Transform3D, size: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = size
	_col_shapes.append([b, xf])


func _col_cyl(center: Vector3, r: float, h: float) -> void:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	_col_shapes.append([c, Transform3D(Basis.IDENTITY, center)])


func _mm_add(kind: String, xf: Transform3D) -> void:
	if not _mm.has(kind):
		var mesh: Mesh
		var mat: Material
		var shadow := true
		match kind:
			"win_glass", "win_lit":
				var q := QuadMesh.new()
				q.size = Vector2.ONE
				mesh = q
				mat = Palette.window_glass() if kind == "win_glass" else Palette.window_lit()
				shadow = false
			"bulb":
				var s := SphereMesh.new()
				s.radius = 1.0
				s.height = 2.0
				s.radial_segments = 8
				s.rings = 4
				mesh = s
				mat = Palette.lamp_bulb()
				shadow = false
			"trunk":
				var c := CylinderMesh.new()
				c.top_radius = 0.16
				c.bottom_radius = 0.26
				c.height = 1.0
				c.radial_segments = 6
				c.rings = 1
				mesh = c
				mat = Palette.bark()
			_:
				var sp := SphereMesh.new()
				sp.radius = 1.0
				sp.height = 2.0
				sp.radial_segments = 8
				sp.rings = 5
				mesh = sp
				mat = Palette.foliage() if kind == "leaf" else WorldMaterials.blossom(kind == "leaf_p")
		_mm[kind] = {"mesh": mesh, "mat": mat, "xf": [], "shadow": shadow}
	_mm[kind].xf.append(xf)


func _label(text: String, xf: Transform3D, color: Color, font_size: int, pixel: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.double_sided = false
	l.shaded = false
	l.transform = xf
	l.visibility_range_end = 110.0
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	_labels += 1


func _flush() -> void:
	var geo := Node3D.new()
	geo.name = "Geometria"
	add_child(geo)
	var proxies := {}
	for key in _batches:
		var bt: Dictionary = _batches[key]
		var st: SurfaceTool = bt.st
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		mesh.surface_set_material(0, bt.mat)
		var mi := MeshInstance3D.new()
		mi.name = "Trozo_%s" % bt.name
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geo.add_child(mi)
		if bt.shadow:
			if not proxies.has(bt.name):
				var nst := SurfaceTool.new()
				nst.begin(Mesh.PRIMITIVE_TRIANGLES)
				proxies[bt.name] = nst
			(proxies[bt.name] as SurfaceTool).append_from(mesh, 0, Transform3D.IDENTITY)
	# Sombras: un proxy por trozo (solo sombra) en vez de un caster por material → pocas llamadas en el pase de sombras.
	for key in proxies:
		var pst: SurfaceTool = proxies[key]
		var pm := pst.commit()
		var pmi := MeshInstance3D.new()
		pmi.name = "Sombra_%s" % key
		pmi.mesh = pm
		pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		geo.add_child(pmi)
	_batches.clear()
	for kind in _mm:
		var d: Dictionary = _mm[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = d.mesh
		var arr: Array = d.xf
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%s" % kind
		mmi.multimesh = mm
		mmi.material_override = d.mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geo.add_child(mmi)
	# Colisión estática (capa 1).
	var body := StaticBody3D.new()
	body.name = "Colision"
	body.collision_layer = 1
	body.collision_mask = 0
	var ground := ConcavePolygonShape3D.new()
	ground.set_faces(_col_faces)
	var gcs := CollisionShape3D.new()
	gcs.name = "Suelo"
	gcs.shape = ground
	body.add_child(gcs)
	for s in _col_shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s[0]
		cs.transform = s[1]
		body.add_child(cs)
	add_child(body)

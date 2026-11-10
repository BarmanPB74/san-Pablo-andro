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
var _contact: Array[Vector4] = []   # 2.2: bases (x, y_suelo, z, radio) para ContactShadows
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
	_p2plants_park()
	_flush()
	add_child(ContactShadows.build(_contact))


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
				# F2-02: algunas manzanas residenciales (sin vía comercial alrededor) con andén de ladrillo (ref. 6).
				var top_mat: Material = MatPaving.brick_sidewalk() if _p2plants_brick_cell(cx, cz) else Palette.sidewalk()
				_tslab(top_mat, Palette.curb(), x0, x1, z0, z1, 0.0, -CURB)
	# F2-02: franja táctil guía en andenes de vías comerciales y alerta en las esquinas.
	_p2plants_tactile()
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
	# F2-04: pintura vial con el atlas MatAsphalt.road_decals() fusionada en mallas por trozo
	# (1 draw call por trozo de 160 m), más tapas de alcantarilla y sumideros en la calzada.
	# RNG propio (no consume _rng: no altera el determinismo del resto del distrito).
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 404
	var d := Traffic.Decals.new()
	d.slope = SLOPE
	d.base = -CURB
	for s in _xs:
		_p2tr_road_paint(d, rng, s, true, _zs)
	for s in _zs:
		_p2tr_road_paint(d, rng, s, false, _xs)
	for m in d.meshes("p2tr_decal"):
		place_mesh(m[0], m[1], Transform3D.IDENTITY, false)


## ¿Cruce con semáforo? (misma regla que usaba _build_traffic_lights).
func _p2tr_signalized(k: Dictionary, c: Dictionary) -> bool:
	return (k.id in ["K38", "K39"] and c.id in ["C54", "C55"]) or k.wide or c.wide or (c.id == "C58" and k.id in ["K38", "K40"])


## Punto del mundo (XZ) a `a` m a lo largo de la vía s y `l` m del eje (l > 0: este / sur).
func _p2tr_w(s: Dictionary, along_z: bool, a: float, l: float) -> Vector2:
	return Vector2(float(s.pos) + l, a) if along_z else Vector2(a, float(s.pos) + l)


func _p2tr_dir(along_z: bool, sgn: float) -> Vector2:
	return Vector2(0, sgn) if along_z else Vector2(sgn, 0)


## Líneas, cebras, líneas de pare, flechas, "PARE", "30", tapas y sumideros de una vía.
func _p2tr_road_paint(d: Traffic.Decals, rng: RandomNumberGenerator, s: Dictionary, along_z: bool, crosses: Array) -> void:
	var half: float = s.half
	var wide: bool = s.wide
	var inner := MEDIAN_HALF if wide else 0.0
	var tilt := Basis(Vector3(0, 0, 1), atan(SLOPE))
	var cuts: Array = []
	for c in crosses:
		cuts.append([float(c.pos) - float(c.half), float(c.pos) + float(c.half)])
	var lo := (Z_MIN if along_z else X_MIN) + 2.0
	var hi := (Z_MAX if along_z else X_MAX) - 2.0
	# --- líneas longitudinales por tramo
	for seg in _segments(lo, hi, cuts):
		var a0: float = seg[0] + 4.7
		var a1: float = seg[1] - 4.7
		if a1 - a0 < 3.0:
			continue
		for sd: float in [-1.0, 1.0]:
			d.line("line_white", _p2tr_w(s, along_z, a0, sd * (half - 0.3)), _p2tr_w(s, along_z, a1, sd * (half - 0.3)))
			if wide:
				d.line("line_yellow", _p2tr_w(s, along_z, a0, sd * (inner + 0.2)), _p2tr_w(s, along_z, a1, sd * (inner + 0.2)))
				d.dashed("dash_white", _p2tr_w(s, along_z, a0 + 2.0, sd * (inner + 3.5)), _p2tr_w(s, along_z, a1 - 2.0, sd * (inner + 3.5)))
		if not wide:
			# eje amarillo: continuo cerca de los cruces, discontinuo en el medio de la cuadra
			if a1 - a0 > 44.0:
				d.line("line_yellow", _p2tr_w(s, along_z, a0, 0.0), _p2tr_w(s, along_z, a0 + 16.0, 0.0))
				d.dashed("line_yellow", _p2tr_w(s, along_z, a0 + 19.0, 0.0), _p2tr_w(s, along_z, a1 - 16.0, 0.0), 2.56, 6.0)
				d.line("line_yellow", _p2tr_w(s, along_z, a1 - 16.0, 0.0), _p2tr_w(s, along_z, a1, 0.0))
			else:
				d.line("line_yellow", _p2tr_w(s, along_z, a0, 0.0), _p2tr_w(s, along_z, a1, 0.0))
			# "30" a mitad de cuadra en algunas vías
			if a1 - a0 > 50.0 and rng.randf() < 0.35:
				var mid := (a0 + a1) * 0.5
				for sd2: float in [-1.0, 1.0]:
					var t2: float = -sd2 if along_z else sd2
					d.add("num_30", _p2tr_w(s, along_z, mid - t2 * 5.0, sd2 * 1.75), _p2tr_dir(along_z, t2))
		# tapas de alcantarilla en los carriles
		var a := a0 + rng.randf_range(4.0, 20.0)
		while a < a1 - 3.0:
			if rng.randf() < 0.7:
				var lat := rng.randf_range(-1.0, 1.0)
				var l := signf(lat) * (inner + (half - inner) * rng.randf_range(0.3, 0.7)) if wide else lat * 1.9
				var p := _p2tr_w(s, along_z, a, l)
				var v := rng.randi_range(0, 1)
				place_mesh("p2tr_manhole_%d" % v, Traffic.manhole(v),
					Transform3D(tilt * Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, road_y(p.x) - 0.004, p.y)), false)
			a += rng.randf_range(30.0, 46.0)
	# --- accesos a cada cruce
	for c in crosses:
		var k: Dictionary = s if along_z else c
		var cl: Dictionary = c if along_z else s
		var sig := _p2tr_signalized(k, cl)
		var cpos: float = c.pos
		var chalf: float = c.half
		var lat_dir := _p2tr_dir(not along_z, 1.0)
		# cebras a ambos lados del cruce
		for side: float in [-1.0, 1.0]:
			var ac := cpos + side * (chalf + 2.1)
			var l := -half + 0.5
			while l <= half - 0.45:
				if not (wide and absf(l) < MEDIAN_HALF + 0.3):
					d.add("zebra_bar", _p2tr_w(s, along_z, ac, l), lat_dir, Vector2(3.0, 0.8))
				l += 1.0
		# línea de pare, flecha o "PARE", sumidero
		for sd: float in [-1.0, 1.0]:
			var t: float = -sd if along_z else sd     # sentido de marcha en el eje de la vía
			var fwd := _p2tr_dir(along_z, t)
			var a_stop := cpos - t * (chalf + 4.2)
			var lane_w := half - inner
			d.add("line_white", _p2tr_w(s, along_z, a_stop, sd * (inner + lane_w * 0.5)), lat_dir,
				Vector2(0.55, lane_w - 0.3), (lane_w - 0.3) / 2.56)
			var lanes: Array = [sd * (inner + 1.75)] if not wide else [sd * (inner + 1.75), sd * (inner + 5.25)]
			if not sig and not along_z:
				d.add("text_pare", _p2tr_w(s, along_z, a_stop - t * 2.3, sd * 1.75), fwd)
			else:
				for ln in lanes:
					d.add("arrow_straight", _p2tr_w(s, along_z, a_stop - t * 7.5, ln), fwd)
			# sumidero junto al sardinel, antes de la cebra
			var g := _p2tr_w(s, along_z, cpos - t * (chalf + 5.6), sd * half)
			var to_c := Vector3(-sd, 0, 0) if along_z else Vector3(0, 0, -sd)
			place_mesh("p2tr_grate", Traffic.drain_grate(),
				Transform3D(tilt * Basis.looking_at(-to_c), Vector3(g.x, road_y(g.x) - 0.004, g.y)), false)


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
	# Jardineras en L por cuadrante (muro enchapado en pizarra, reja verde hacia los senderos),
	# plaza central 24x24 en espina de pescado y senderos hexagonales con bordillo (F2-06).
	_p2park_planters()
	_p2park_pavers()
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
	# Fase 3: pila (fuente) y tarima redonda en las dos esquinas libres de la plaza central, y el león
	# de piedra echado al pie del pedestal (mira hacia el oeste, como en las fotos).
	ParkPlaza.build_fountain(self, Vector3(-8.0, walk_y(-8.0), 8.0))
	ParkPlaza.build_stage(self, Vector3(8.0, walk_y(8.0), -8.0))
	ParkPlaza.build_lion(self, Vector3(0.0, 0.0, 2.1), PI * 0.5)
	# Bancas: de madera contra los muros de la plaza mirando a la estatua; de granito en los senderos,
	# arrimadas al bordillo y mirando al centro del sendero. Canecas junto a ellas.
	for ang: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var b := Basis(Vector3.UP, ang)
		for u in [-7.0, 7.0]:
			var p := b * Vector3(u, 0, 11.45)
			_bench(Transform3D(b * Basis(Vector3.UP, PI), Vector3(p.x, walk_y(p.x), p.z)))
		var k := 1
		for d in [17.0, 25.0]:
			var p2 := b * Vector3(2.05, 0, d)
			_bench(Transform3D(b * Basis(Vector3.UP, -PI * 0.5), Vector3(p2.x, walk_y(p2.x), p2.z)), k)
			k += 1
		var pb := b * Vector3(9.3, 0, 11.6)
		_p2park_bin(Transform3D(b * Basis(Vector3.UP, PI), Vector3(pb.x, walk_y(pb.x), pb.z)))
		var pb2 := b * Vector3(2.0, 0, 21.0)
		_p2park_bin(Transform3D(b * Basis(Vector3.UP, -PI * 0.5), Vector3(pb2.x, walk_y(pb2.x), pb2.z)))
	# Faroles del parque (linterna en los senderos, globo en las esquinas de la plaza).
	var lamp_pos: Array = []
	for d in [16.0, 27.0]:
		for ang: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			lamp_pos.append(Basis(Vector3.UP, ang) * Vector3(-2.0, 0, d))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			lamp_pos.append(Vector3(11.6 * sx, 0, 11.6 * sz))
	for i in lamp_pos.size():
		var p: Vector3 = lamp_pos[i]
		_park_lamp(Vector3(p.x, walk_y(p.x), p.z), i % 2 == 0, 0 if i < 8 else 1)
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
	# Monumento a José María Córdova (F2-05): figura de pie en bronce sobre pedestal alto de mármol,
	# seto redondo, bordillo de granito y reja baja verde. Mallas, placa y colisiones en Monument.
	Monument.build(self)


## kind 0 = banca de listones de madera con costados de hierro; 1/2 = bancas de granito (F2-06).
## La banca mira a +Z local.
func _bench(xf: Transform3D, kind := 0) -> void:
	var sxf := _p2park_sheared(xf)
	if kind == 0:
		place_mesh("park_bench_wood", ParkFurniture.wood_bench(), sxf)
		_col_box(xf.translated_local(Vector3(0, 0.45, -0.02)), Vector3(1.8, 0.9, 0.55))
	else:
		place_mesh("park_bench_granite_%d" % (kind - 1), ParkFurniture.granite_bench(kind - 1), sxf)
		_col_box(xf.translated_local(Vector3(0, 0.23, 0)), Vector3(1.9, 0.46, 0.52))


## Farol de hierro fundido (variant 0 = linterna hexagonal, 1 = globo). Luz cálida sin sombra si with_light.
func _park_lamp(p: Vector3, with_light: bool, variant := 0) -> void:
	place_mesh("park_lamp_%d" % (variant % 2), ParkFurniture.park_lamp(variant), Transform3D(Basis(Vector3.UP, 0.4 * float(variant)), p))
	_col_cyl(p + Vector3(0, 0.3, 0), 0.21, 0.6)
	_col_cyl(p + Vector3(0, 2.2, 0), 0.08, 4.4)
	if with_light and _lights < 16:
		_lights += 1
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.45)
		l.light_energy = 2.0
		l.omni_range = 12.0
		l.shadow_enabled = false
		l.distance_fade_enabled = true   # 2.2: luz por zonas — las lejanas se apagan solas
		l.distance_fade_begin = 45.0
		l.distance_fade_length = 15.0
		l.position = p + Vector3(0, ParkFurniture.LAMP_LIGHT_Y, 0)
		add_child(l)


## Carrito de comida callejera (variant % 3: mango, arepas, salpicón; colores por variant % 4).
func _food_cart(xf: Transform3D, variant: int) -> void:
	place_mesh("park_cart_%d" % posmod(variant, 4), ParkFurniture.food_cart(variant), _p2park_sheared(xf))
	_col_box(xf.translated_local(Vector3(-0.13, 0.62, 0)), Vector3(2.0, 1.24, 0.85))
	_col_cyl(xf * Vector3(0.62, 1.7, -0.2), 0.03, 1.5)


# ------------------------------------------------------------------ parque F2-06 (helpers propios)
## Aplica la cizalla de la pendiente (y += SLOPE·x) para que el mueble asiente sobre el piso inclinado.
func _p2park_sheared(xf: Transform3D) -> Transform3D:
	var shear := Basis(Vector3(1, SLOPE, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	return Transform3D(shear * xf.basis, xf.origin)


## Transformación para piezas lineales de a→b (XZ): X local a lo largo, Z local = d × arriba,
## X escalada por `sx`; con cizalla de pendiente. y_off sobre walk_y del inicio.
func _p2park_line(a: Vector2, b: Vector2, y_off: float, sx: float) -> Transform3D:
	var d := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
	var z := d.cross(Vector3.UP)
	return _p2park_sheared(Transform3D(Basis(d * sx, Vector3.UP, z), Vector3(a.x, walk_y(a.x) + y_off, a.y)))


## Caja de colisión a lo largo de a→b (inclinada con la pendiente si va en X).
func _p2park_col_line(a: Vector2, b: Vector2, h: float, w: float) -> void:
	var c := (a + b) * 0.5
	var l := a.distance_to(b)
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var bas := Basis(Vector3.BACK, atan(SLOPE)) if along_x else Basis.IDENTITY
	var size := Vector3(l, h, w) if along_x else Vector3(w, h, l)
	_col_box(Transform3D(bas, Vector3(c.x, walk_y(c.x) + h * 0.5, c.y)), size)


## Jardineras en L: tapa de pasto a +0.35 (misma huella de siempre, ver README_mapa "Jardineras del parque"),
## muros de pizarra de 0.30 × 0.45, reja baja verde y bordillo hacia los senderos hexagonales.
func _p2park_planters() -> void:
	var wall := ParkFurniture.planter_wall()
	var fence := ParkFurniture.fence_segment()
	var curb := ParkFurniture.path_curb()
	var t := ParkFurniture.WALL_T * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var m := Vector2(sx, sz)
			for r in [[12.0, 31.0, 2.5, 31.0], [2.5, 12.0, 12.0, 31.0]]:
				var xa: float = sx * r[0]
				var xb: float = sx * r[1]
				var za: float = sz * r[2]
				var zb: float = sz * r[3]
				_tilted_top(MatGround.pasto(), minf(xa, xb), maxf(xa, xb), minf(za, zb), maxf(za, zb), 0.35, true, false)
			# Bordes: [inicio, fin, normal hacia dentro, ¿reja y bordillo?]
			var edges := [
				[Vector2(2.5, 12), Vector2(12, 12), Vector2(0, 1), false],
				[Vector2(12, 2.5), Vector2(12, 12), Vector2(1, 0), false],
				[Vector2(12, 2.5), Vector2(31, 2.5), Vector2(0, 1), true],
				[Vector2(31, 2.5), Vector2(31, 31), Vector2(-1, 0), true],
				[Vector2(2.5, 31), Vector2(31, 31), Vector2(0, -1), true],
				[Vector2(2.5, 12), Vector2(2.5, 31), Vector2(1, 0), true],
			]
			for e in edges:
				var n: Vector2 = e[2] * m
				var a: Vector2 = e[0] * m + n * t
				var b: Vector2 = e[1] * m + n * t
				place_mesh("park_wall", wall, _p2park_line(a, b, 0.0, a.distance_to(b)))
				var fenced: bool = e[3]
				_p2park_col_line(a, b, ParkFurniture.WALL_H + (ParkFurniture.FENCE_H if fenced else 0.0), ParkFurniture.WALL_T)
				if fenced:
					var ca: Vector2 = e[0] * m - n * 0.08
					var cb: Vector2 = e[1] * m - n * 0.08
					place_mesh("park_curb", curb, _p2park_line(ca, cb, 0.0, ca.distance_to(cb)), false)
			# Esquina entrante (12, 12).
			var cc := Vector2(12.0 + t, 12.0 + t) * m
			place_mesh("park_wall_corner", ParkFurniture.planter_corner(), Transform3D(Basis.IDENTITY, Vector3(cc.x, walk_y(cc.x), cc.y)))
			# Rejas sobre el eje de los muros (los tramos encadenan postes en las esquinas).
			var runs := [
				[Vector2(12 + t, 2.5 + t), Vector2(31 - t, 2.5 + t)],
				[Vector2(31 - t, 2.5 + t), Vector2(31 - t, 31 - t)],
				[Vector2(2.5 + t, 31 - t), Vector2(31 - t, 31 - t)],
				[Vector2(2.5 + t, 12 + t), Vector2(2.5 + t, 31 - t)],
			]
			for rn in runs:
				var a: Vector2 = rn[0] * m
				var b: Vector2 = rn[1] * m
				var l := a.distance_to(b)
				var cnt := maxi(1, roundi(l / ParkFurniture.FENCE_LEN))
				var s := l / (cnt * ParkFurniture.FENCE_LEN)
				for i in cnt:
					var p := a.lerp(b, float(i) / cnt)
					place_mesh("park_fence", fence, _p2park_line(p, b, ParkFurniture.WALL_H, s))
			var pe := Vector2(31 - t, 31 - t) * m
			place_mesh("park_fence_post", ParkFurniture.fence_post(), Transform3D(Basis.IDENTITY, Vector3(pe.x, walk_y(pe.x) + ParkFurniture.WALL_H, pe.y)))


## Pisos del parque sobre la losa de la manzana: plaza en espina de pescado, senderos hexagonales,
## bordillos en la boca de los senderos y en el borde con el andén perimetral.
func _p2park_pavers() -> void:
	var hb := MatPaving.herringbone_pavers()
	var hx := MatPaving.hex_pavers()
	var off := 0.012
	_tilted_top(hb, -12.0, 12.0, -12.0, 12.0, off, false, false)
	for s: float in [-1.0, 1.0]:
		_tilted_top(hx, -2.5, 2.5, minf(12.0 * s, 31.0 * s), maxf(12.0 * s, 31.0 * s), off, false, false)
		_tilted_top(hx, minf(12.0 * s, 31.0 * s), maxf(12.0 * s, 31.0 * s), -2.5, 2.5, off, false, false)
		_tilted_top(hx, -34.0, 34.0, minf(31.0 * s, 34.0 * s), maxf(31.0 * s, 34.0 * s), off, false, false)
		_tilted_top(hx, minf(31.0 * s, 34.0 * s), maxf(31.0 * s, 34.0 * s), -31.0, 31.0, off, false, false)
	var curb := ParkFurniture.path_curb()
	for s: float in [-1.0, 1.0]:
		# boca de cada sendero (cambio de espina de pescado a hexagonal)
		place_mesh("park_curb", curb, _p2park_line(Vector2(-2.5, 12.0 * s), Vector2(2.5, 12.0 * s), 0.0, 5.0), false)
		place_mesh("park_curb", curb, _p2park_line(Vector2(12.0 * s, -2.5), Vector2(12.0 * s, 2.5), 0.0, 5.0), false)
		# borde con el andén perimetral
		var e := 33.92 * s
		place_mesh("park_curb", curb, _p2park_line(Vector2(-34.0, e), Vector2(34.0, e), 0.0, 68.0), false)
		place_mesh("park_curb", curb, _p2park_line(Vector2(e, -34.0), Vector2(e, 34.0), 0.0, 68.0), false)


## Caneca de parque (poste hacia -Z local).
func _p2park_bin(xf: Transform3D) -> void:
	place_mesh("park_bin", ParkFurniture.park_bin(), _p2park_sheared(xf))
	_col_cyl(xf.origin + Vector3(0, 0.5, 0), 0.24, 1.0)


func _street_plate(p: Vector3, calle: String, carrera: String) -> void:
	# F2-04: poste galvanizado con placas verdes de nomenclatura del atlas (doble cara).
	# "Calle 55 · Perú" → C55, "Carrera 38" → K38. La placa de la calle va paralela a la calle.
	var y := walk_y(p.x)
	var base := Vector3(p.x, y, p.z)
	var cparts := calle.split(" ")
	var kparts := carrera.split(" ")
	var ci := Traffic.plate_index("C" + (cparts[1] if cparts.size() > 1 else ""))
	var ki := Traffic.plate_index("K" + (kparts[1] if kparts.size() > 1 else ""))
	place_mesh("p2tr_platepost_%d_%d" % [ci, ki], Traffic.plate_post(ci, ki), Transform3D(Basis.IDENTITY, base))
	_col_cyl(base + Vector3(0, 1.7, 0), 0.06, 3.4)
	if ci < 0 or ki < 0:
		# vía sin placa en el atlas: rótulo de texto sobre una placa genérica
		var sx: float = signf(-p.x)
		_label(calle if ci < 0 else carrera, Transform3D(Basis(Vector3.UP, sx * PI * 0.5), base + Vector3(sx * 0.05, 3.0, 0)), Color(0.95, 0.97, 0.95), 36, 0.006)


# ------------------------------------------------------------------ iglesia del Sufragio
func _build_church() -> void:
	# Calle 55 #39-61. La fachada da a la Carrera 39 y MIRA AL ESTE, hacia el parque (Cra 39 es su costado
	# oeste); la nave se extiende hacia el oeste y las torres quedan a norte y sur de la fachada (fotos de
	# referencia). Marco local de Church: fachada a -Z local, nave a +Z. Con Basis(UP, -PI/2):
	# local (x, y, z) → mundo (cx - z, y, cz + x).
	var cx := -52.0                  # línea de fachada
	var cz := -20.0                  # eje de la nave, cerca de la esquina con la Cl 55
	var step_drop := 0.6             # 6 peldaños de 0.1 m desde el andén
	var y0 := walk_y(cx + 3.5)       # andén al pie de la escalinata
	var floor_y := y0 + step_drop
	var stone := Palette.stone()
	var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(cx, floor_y, cz))
	_excl.append(Rect2(cx - Church.L - 14.0, cz - 14.0, Church.L + 14.0 + 8.0, 28.0))
	# Podio que absorbe la pendiente (el terreno baja hacia el oeste) bajo toda la nave.
	var west_x := cx - Church.L - 10.0
	var podium_h := floor_y - (walk_y(west_x) - 0.6)
	var pod := Transform3D(Basis.IDENTITY, Vector3((cx + west_x) * 0.5, floor_y - podium_h * 0.5, cz))
	_box(stone, pod, Vector3(cx - west_x, podium_h, 26.0))
	_col_box(pod, Vector3(cx - west_x, podium_h, 26.0))
	# Escalinata hacia la Cra 39 (colisión; los peldaños de granito los dibuja Church).
	for i in 6:
		var top := floor_y - step_drop + step_drop * float(i + 1) / 6.0
		var depth := 3.5 - 0.55 * float(i)
		_col_box(Transform3D(Basis.IDENTITY, Vector3(cx + depth * 0.5, top - 1.25, cz)), Vector3(depth, 2.5, Church.W))
	# Iglesia: nave, ábside, torres, fachada, escalinata (mallas en MultiMesh por key).
	Church.build(self, xf, step_drop)
	_col_box(xf * Transform3D(Basis.IDENTITY, Vector3(0, Church.NAVE_H * 0.5, Church.L * 0.5)), Vector3(Church.W, Church.NAVE_H, Church.L))
	_col_cyl(xf * Vector3(0, 6.0, Church.L), 7.5, 12.0)
	for sx: float in [-1.0, 1.0]:
		_col_box(xf * Transform3D(Basis.IDENTITY, Vector3(sx * Church.TW_X, 11.0, Church.TW_Z)), Vector3(5.2, 22.0, 5.2))
	# Baldosa frente a la escalinata, entre la acera de la Cra 39 y el primer peldaño.
	_tslab(Palette.plaza_tile(), Palette.curb(), cx + 2.5, -46.0, cz - 14.0, cz + 14.0, 0.02, -0.05)
	# Faroles flanqueando la escalinata.
	_park_lamp(Vector3(cx + 3.0, walk_y(cx + 3.0), cz - 10.5), false)
	_park_lamp(Vector3(cx + 3.0, walk_y(cx + 3.0), cz + 10.5), false)
	# Árboles y bancas en la acera de la Cra 39 al sur de la iglesia (frente al colegio).
	for pz: float in [2.0, 14.0]:
		_tree(Vector3(-52.5, walk_y(-52.5), pz), _rng.randf_range(0.9, 1.2), 0)
		_bench(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-49.0, walk_y(-49.0) + 0.02, pz + 5.0)))


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
		_apartment(xf, w, d, shop, MatBrick.fachada_variante(_rng.randi_range(0, 5)), floors, near)
	elif r < 0.9 and w >= 9.0:
		# Edificio moderno de vidrio y concreto liso (F2-08, Buildings.modern).
		Buildings.modern(self, xf, w, d, shop, _rng.randi_range(4, 7), near)
	else:
		_apartment(xf, w, d, shop, MatPlaster.stucco_house(_rng.randi_range(0, 5)), _rng.randi_range(3, 6), near)


## Casa antioqueña de dos pisos (F2-08, world/props/buildings.gd): zócalo de piedra, estuco de color,
## moldura, puertas/ventanas rehundidas con reja, balcón de madera o balconcillos, alero con canecillos y teja.
## Llama a _shopfront si tiene local. Colisión: caja w × (g + 4.2) × d como antes.
func _house(xf: Transform3D, w: float, d: float, shop: bool, near: bool) -> void:
	Buildings.house(self, xf, w, d, shop, near)


## Edificio de apartamentos de ladrillo (mat de MatBrick) o estuco, 3-9 pisos (F2-08, buildings.gd):
## franjas de losa, ventanas rehundidas con alféizar y dintel de petaco, balcones, calado de escalera,
## antejardín, retranqueo superior, azotea con cuarto de máquinas/tanque/antena. Llama a _shopfront.
func _apartment(xf: Transform3D, w: float, d: float, shop: bool, mat: Material, floors: int, near: bool) -> void:
	var brick := mat.resource_path.contains("brick") or (mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null and (mat as BaseMaterial3D).albedo_texture.resource_path.contains("/brick/"))
	Buildings.apartment(self, xf, w, d, shop, mat, floors, near, brick)


## Primer piso comercial: interior iluminado o persiana, aviso con neón y toldo.
func _wants_label(xf: Transform3D) -> bool:
	return absf(xf.origin.x) < 130.0 and absf(xf.origin.z) < 130.0 and _cur_main


func _shopfront(xf: Transform3D, w: float, g: float) -> void:
	# F2-07: locales modelados en world/props/shopfronts.gd (vitrinas, puerta, cortina, dintel con letrero
	# del atlas, toldos, avisos de bandera, celosía, materas, neones). Se consumen del _rng exactamente los
	# mismos sorteos que antes para no alterar el resto del barrio; la variación propia usa semilla local.
	var open := _rng.randf() < 0.7
	_rng.randi_range(0, 2)   # (antes: color del neón)
	var awning := false
	if open and _rng.randf() < 0.5:
		awning = true
		_rng.randi_range(0, 4)   # (antes: material del toldo)
	var near := absf(xf.origin.x) < 130.0 and absf(xf.origin.z) < 130.0
	# Edificio moderno (g = 4 m): marcos laterales de concreto de 0.45 m → el local va entre ellos.
	var ws := w - 0.9 if g > 3.7 else w
	Shopfronts.build(self, xf, ws, g, open, awning, near or _wants_label(xf), _shop_i)
	_shop_i += 1


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
	var sw := Poles.make_light_switch()   # enciende las luminarias según el preset de StreetLook
	place_node(sw, Transform3D.IDENTITY)
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
			if absf(x + 44.0) < 3.0 and z > -36.0 and z < -4.0:
				clear = false   # frente a la iglesia (fachada sobre la Cra 39)
			if clear:
				pts.append(Vector3(x, walk_y(x), z))
			z += 33.0
		_pole_line(pts, Vector3(1, 0, 0) * (-1.0 if s.wide else 1.0), s, sw)
	for s in _zs:
		var zz: float = float(s.pos) + (float(s.half) + 0.6 if s.wide else -(float(s.half) + 0.5))
		var pts2: Array = []
		var xx := X_MIN + 6.0
		while xx < X_MAX - 6.0:
			var clear2 := true
			for c in _xs:
				if absf(xx - float(c.pos)) < float(c.half) + float(c.walk) + 1.5:
					clear2 = false
			if clear2:
				pts2.append(Vector3(xx, walk_y(xx), zz))
			xx += 33.0
		_pole_line(pts2, Vector3(0, 0, 1) * (-1.0 if s.wide else 1.0), s, sw)


## Línea de postes de concreto (world/props/poles.gd): 4 variantes (básico, transformador, rollos de
## telecom, botella de empalme + medidor), luminaria LED en 2 de cada 3 postes (luz real en 1 de cada 2
## luminarias), vanos de 10 cables con catenaria (también sobre los cruces), retenidas en los extremos y
## acometidas a las fachadas. Variación determinista por posición (no consume _rng).
func _pole_line(pts: Array, to_road: Vector3, street: Dictionary, sw: Node3D) -> void:
	var along := Vector3(to_road.z, 0, -to_road.x)
	var pb := Basis(along, Vector3.UP, to_road)
	var r := RandomNumberGenerator.new()
	var side := -1.0 if to_road.x + to_road.z > 0.0 else 1.0       # lado de la vía donde está la línea
	var edge: float = float(street.half) + float(street.walk)       # distancia del eje a las fachadas
	var lums := 0
	for i in pts.size():
		var p: Vector3 = pts[i]
		r.seed = hash(Vector2i(int(p.x * 10.0), int(p.z * 10.0)))
		var roll := r.randf()
		var variant := 0
		if roll < 0.2:
			variant = 1
		elif roll < 0.5:
			variant = 2
		elif roll < 0.7:
			variant = 3
		var xf := Transform3D(pb, p)
		place_mesh("p2poles_pole_%d" % variant, Poles.pole(variant), xf, true)
		_col_cyl(p + Vector3(0, Poles.POLE_TOP * 0.5, 0), Poles.POLE_R0, Poles.POLE_TOP)
		if i % 3 != 1:
			place_mesh("p2poles_lum", Poles.luminaire(), xf, false)
			# luz real en 1 de cada 2 luminarias, solo en la zona jugable central (reparto uniforme, ≤ 72)
			if lums % 2 == 0 and absf(p.x) < 230.0 and absf(p.z) < 230.0 and sw.get_child_count() < 72:
				sw.add_child(Poles.make_lamp_light())
				(sw.get_child(sw.get_child_count() - 1) as Node3D).transform = Poles.lamp_light_xform(xf)
			lums += 1
		# vano hacia el poste anterior (33 m; 66 m sobre un cruce)
		if i > 0:
			var q: Vector3 = pts[i - 1]
			if q.distance_to(p) < 70.0:
				var sp := Poles.span_transform(q, p, to_road)
				var sxf: Transform3D = sp[0]
				var quad := int(p.x > (X_MIN + X_MAX) * 0.5) + 2 * int(p.z > (Z_MIN + Z_MAX) * 0.5)
				place_mesh("p2poles_span_%d_%d_q%d" % [int(sp[2]), int(sp[1]), quad], Poles.span(sp[2], sp[1]), sxf, false)
		# retenidas en los extremos de la línea
		if i == 0 or i == pts.size() - 1:
			var nb: Vector3 = pts[1] if i == 0 else pts[i - 1]
			if pts.size() > 1:
				var away := Vector3(p.x - nb.x, 0, p.z - nb.z).normalized()
				var gx := -away
				place_mesh("p2poles_guy", Poles.guy(), Transform3D(Basis(gx, Vector3.UP, gx.cross(Vector3.UP)), p), false)
		# acometidas a las fachadas (cerca: baja tensión; enfrente: telecom cruzando la calle)
		var st := _st(Poles.cable_mat(), p, false)
		var n_drops := r.randi_range(0, 2)
		for k in n_drops:
			var off := r.randf_range(2.5, 9.0) * (1.0 if k == 0 else -1.0)
			var f := _p2poles_facade(street, p, to_road, along, side * edge, off, r.randf_range(4.6, 5.4))
			if f != Vector3.INF:
				Poles.append_cable(st, xf * Poles.DROP_LV, f, r.randf_range(0.12, 0.3), 0.008, 3, 5)
		if not street.wide and r.randf() < 0.55:
			var f2 := _p2poles_facade(street, p, to_road, along, -side * edge, r.randf_range(-7.0, 7.0), r.randf_range(5.6, 6.4))
			if f2 != Vector3.INF:
				Poles.append_cable(st, xf * Poles.DROP_TEL, f2, r.randf_range(0.25, 0.5), 0.01, 3, 7)


## Punto en la fachada a `dist` (con signo) del eje de la vía, desplazado `off` a lo largo de la línea, a
## `h` m sobre el andén. Vector3.INF si allí no hay edificio (parque, iglesia, teatro, borde del mapa).
func _p2poles_facade(street: Dictionary, p: Vector3, to_road: Vector3, along: Vector3, dist: float, off: float, h: float) -> Vector3:
	var axis: Vector3 = to_road.abs()
	var q := p + along * off
	q += axis * (float(street.pos) + dist - p.dot(axis))
	if absf(q.x) < 40.0 and absf(q.z) < 40.0:
		return Vector3.INF
	if q.x < X_MIN + 2.0 or q.x > X_MAX - 2.0 or q.z < Z_MIN + 2.0 or q.z > Z_MAX - 2.0:
		return Vector3.INF
	if _hits_excl(Rect2(q.x - 1.0, q.z - 1.0, 2.0, 2.0)):
		return Vector3.INF
	for c in (_zs if axis.x > 0.5 else _xs):   # no sobre la calzada de una vía transversal
		if absf((q.z if axis.x > 0.5 else q.x) - float(c.pos)) < float(c.half) + float(c.walk) + 0.5:
			return Vector3.INF
	q.y = walk_y(q.x) + h
	return q


## Cable suelto con catenaria (lote del distrito, material de cable de Poles).
func _cable(a: Vector3, b: Vector3, sag: float) -> void:
	Poles.append_cable(_st(Poles.cable_mat(), (a + b) * 0.5, false), a, b, sag, 0.012, 3, 6)


func _build_traffic_lights() -> void:
	# F2-04: un único nodo cicla las lentes de todos los semáforos (grupos de fase A/B).
	place_node(Traffic.Cycle.new(), Transform3D.IDENTITY)
	for k in _xs:
		for c in _zs:
			var important: bool = _p2tr_signalized(k, c)
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
			# placas de nomenclatura en los postes SE y NW (si el atlas tiene ambas vías)
			for sg: float in [-1.0, 1.0]:
				_p2tr_pole_plates(Vector3(cx + sg * (kh + 0.9), 0, cz + sg * (chh + 0.9)), c.id, k.id, sg)
	_p2tr_stop_signs()


## green: el grupo de fase de este acceso arranca en verde ("A") o en rojo ("B").
func _signal(p: Vector3, arm_dir: Vector3, arm_len: float, face: Vector3, green: bool) -> void:
	var base := Vector3(p.x, walk_y(p.x), p.z)
	_col_cyl(base + Vector3(0, 3.1, 0), 0.13, 6.2)
	var reach: float = minf(arm_len + 0.5, 7.0)
	var g := "A" if green else "B"
	var other := "B" if green else "A"
	var pxf := Transform3D(Basis(arm_dir, Vector3.UP, -face), base)   # brazo = +X local, cabezas a -Z
	var rkey := "p2tr_pole_%d" % int(snappedf(reach, 0.5) * 10.0)
	place_mesh(rkey, Traffic.signal_pole(reach), pxf)
	var an: Dictionary = Traffic.signal_anchors(reach)
	for h in an.heads:
		place_mesh("p2tr_head_" + g, Traffic.signal_head(g), pxf * (h as Transform3D))
	place_mesh("p2tr_head_" + g, Traffic.signal_head(g), pxf * (an.rep as Transform3D))
	# peatonales: la que mira por el brazo sirve el cruce de la vía transversal (otro grupo)
	place_mesh("p2tr_ped_" + other, Traffic.ped_head(other), pxf * (an.ped_arm as Transform3D))
	place_mesh("p2tr_ped_" + g, Traffic.ped_head(g), pxf * (an.ped_back as Transform3D))


## Placas verdes en un poste de semáforo: la de la calle paralela a la calle, la de la carrera
## paralela a la carrera; desplazadas hacia fuera del cruce (sg: lado de la esquina).
func _p2tr_pole_plates(p: Vector3, calle_id: String, carrera_id: String, sg: float) -> void:
	var ci := Traffic.plate_index(calle_id)
	var ki := Traffic.plate_index(carrera_id)
	var base := Vector3(p.x, walk_y(p.x), p.z)
	if ci >= 0:
		place_mesh("p2tr_plate_%d" % ci, Traffic.street_plate(ci), Transform3D(Basis.IDENTITY, base + Vector3(0, 4.2, sg * 0.13)))
	if ki >= 0:
		place_mesh("p2tr_plate_%d" % ki, Traffic.street_plate(ki), Transform3D(Basis(Vector3.UP, PI * 0.5), base + Vector3(sg * 0.13, 3.72, 0)))


## Señales de PARE en los accesos de las calles a cruces sin semáforo (la carrera tiene prelación).
func _p2tr_stop_signs() -> void:
	for k in _xs:
		for c in _zs:
			if _p2tr_signalized(k, c):
				continue
			var kx: float = k.pos
			var kh: float = k.half
			var cz: float = c.pos
			var ch: float = c.half
			for sd: float in [-1.0, 1.0]:
				# sd = +1: tráfico hacia el este (carril sur), señal antes del cruce en el andén sur.
				var off := kh + 4.6
				var x := kx - sd * off
				var z := cz + sd * (ch + 0.45)
				if not c.wide and sd < 0.0 and _p2tr_near_cable_pole(x):
					x -= sd * 1.3
				var face := Vector3(-sd, 0, 0)
				place_mesh("p2tr_sign_pare", Traffic.sign_post_named("pare", 2.35),
					Transform3D(Basis.looking_at(-face), Vector3(x, walk_y(x), z)))
				_col_cyl(Vector3(x, walk_y(x) + 1.2, z), 0.05, 2.4)


## ¿Hay un poste de energía de las calles (andén norte) a menos de 0.7 m en X?
func _p2tr_near_cable_pole(x: float) -> bool:
	var t := fposmod(x - (X_MIN + 6.0), 33.0)
	return t < 0.7 or t > 32.3


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
					_p2plants_pit(Vector3(x2, walk_y(x2), zz))   # F2-02: alcorque con plantas
			x2 += 9.0
	# F2-02: palmas en separadores y andenes residenciales, macizos en los separadores.
	_p2plants_street_palms()


# ------------------------------------------------------------------ vegetación baja F2-02 (helpers propios)
## Coloca un modelo de Plants agrupado por región (~220 × 200 m) para que el MultiMesh se pueda recortar.
func _p2plants_place(key: String, mesh: Mesh, xf: Transform3D, shadow := true) -> void:
	var rx := int((xf.origin.x - X_MIN) / 330.0)
	var rz := int((xf.origin.z - Z_MIN) / 300.0)
	place_mesh("p2plants_%s_r%d_%d" % [key, rx, rz], mesh, xf, shadow)


## Cizalla de la pendiente (y += SLOPE·x) para piezas planas que deben asentar sobre el piso inclinado.
func _p2plants_sheared(xf: Transform3D) -> Transform3D:
	var shear := Basis(Vector3(1, SLOPE, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	return Transform3D(shear * xf.basis, xf.origin)


## Variante determinista a partir de la posición (no consume _rng).
func _p2plants_hash(p: Vector3, n: int) -> int:
	return posmod(int(floor(p.x * 3.7)) * 73856093 ^ int(floor(p.z * 3.1)) * 19349663, n)


## Alcorque de andén (marco + mantillo + plantas) bajo un árbol de andén.
func _p2plants_pit(base: Vector3) -> void:
	var v := _p2plants_hash(base, Plants.PIT_VARIANTS)
	_p2plants_place("pit_%d" % v, Plants.tree_pit(v),
		_p2plants_sheared(Transform3D(Basis(Vector3.UP, PI * 0.5 * (v % 2)), base)), false)


func _p2plants_palm(base: Vector3, r: RandomNumberGenerator, with_pit: bool) -> void:
	var v := r.randi() % Plants.TALL_PALM_VARIANTS
	var s := r.randf_range(0.9, 1.1)
	_p2plants_place("palm_%d" % v, Plants.tall_palm(v),
		Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s, s)), base))
	add_col_cyl(base + Vector3(0, 1.5, 0), 0.2, 3.0)
	if with_pit:
		_p2plants_pit(base)


func _p2plants_street_palms() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 202
	# Separador de La Playa: palma entre cada par de árboles (uno sí, uno no) y macizos en las puntas.
	for s in _zs:
		if not s.wide:
			continue
		var x := X_MIN + 8.0 + 5.5
		var k := 0
		while x < X_MAX - 8.0:
			var ok := true
			for c in _xs:
				if absf(x - float(c.pos)) < float(c.half) + 6.0:
					ok = false
			if ok and k % 2 == 0:
				_p2plants_palm(Vector3(x, walk_y(x) - 0.05, float(s.pos)), r, false)
			k += 1
			x += 11.0
		for c in _xs:
			for side: float in [-1.0, 1.0]:
				var bx: float = float(c.pos) + side * (float(c.half) + 4.0 + 2.6)
				if bx < X_MIN + 3.0 or bx > X_MAX - 3.0:
					continue
				var mix := r.randi() % 3
				_p2plants_place("bed_m%d" % mix, Plants.garden_bed(4.0, 3.0, mix),
					_p2plants_sheared(Transform3D(Basis.IDENTITY, Vector3(bx, walk_y(bx), float(s.pos)))))
	# Separador de la Cra 43 (Girardot): palmas intercaladas y macizos en las puntas.
	for s in _xs:
		if not s.wide:
			continue
		var px: float = float(s.pos)
		var z := Z_MIN + 8.0 + 7.0
		var k2 := 0
		while z < Z_MAX - 8.0:
			var ok2 := true
			for c in _zs:
				if absf(z - float(c.pos)) < float(c.half) + 6.0:
					ok2 = false
			if ok2 and k2 % 2 == 1:
				_p2plants_palm(Vector3(px, walk_y(px) - 0.05, z), r, false)
			k2 += 1
			z += 14.0
		for c in _zs:
			for side: float in [-1.0, 1.0]:
				var bz: float = float(c.pos) + side * (float(c.half) + 4.0 + 2.6)
				if bz < Z_MIN + 3.0 or bz > Z_MAX - 3.0:
					continue
				var mix2 := r.randi() % 3
				_p2plants_place("bed_m%d" % mix2, Plants.garden_bed(4.0, 3.0, mix2),
					_p2plants_sheared(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(px, walk_y(px), bz))))
	# Andenes residenciales (carreras no comerciales), costado oriental: palmas con alcorque (ref. 7).
	for s in _xs:
		if s.wide or s.id in MAIN_IDS:
			continue
		var ax: float = float(s.pos) + float(s.half) + 1.0
		var z2 := Z_MIN + 10.0
		while z2 < Z_MAX - 10.0:
			var roll := r.randf()
			var ok3 := roll < 0.3
			for c in _zs:
				if absf(z2 - float(c.pos)) < float(c.half) + float(c.walk) + 5.0:
					ok3 = false
			if ok3:
				_p2plants_palm(Vector3(ax, walk_y(ax), z2), r, true)
			z2 += 10.0


## ¿Manzana residencial con andén de ladrillo? (ninguna vía comercial alrededor; 1 de cada 3 por posición).
func _p2plants_brick_cell(cx: Dictionary, cz: Dictionary) -> bool:
	for st in [cx.lo, cx.hi, cz.lo, cz.hi]:
		if st == null or st.id in MAIN_IDS:
			return false
	return posmod(int(cx.a) * 7 + int(cz.a) * 13, 3) == 0


## Baldosa táctil: franja guía de 40 cm a (andén - 0.5 m) del sardinel en los andenes de las vías
## comerciales, y alerta en cada esquina (cuadro 0.8 m + franja hasta el sardinel del cruce).
func _p2plants_tactile() -> void:
	var gx := MatPaving.tactile_guide(true)    # barras a lo largo de X (andenes de calles)
	var gz := MatPaving.tactile_guide(false)   # barras a lo largo de Z (andenes de carreras)
	var al := MatPaving.tactile_alert()
	var off := 0.008
	for cx in _cells(_xs, X_MIN, X_MAX):
		for cz in _cells(_zs, Z_MIN, Z_MAX):
			if cx.lo == null or cx.hi == null or cz.lo == null or cz.hi == null:
				continue
			# Esquinas de la franja (cruce con la franja del andén perpendicular).
			var jx0: float = float(cx.a) + float(cx.lo.walk) - 0.5
			var jx1: float = float(cx.b) - float(cx.hi.walk) + 0.5
			var jz0: float = float(cz.a) + float(cz.lo.walk) - 0.5
			var jz1: float = float(cz.b) - float(cz.hi.walk) + 0.5
			# Andenes a lo largo de las calles (norte y sur de la manzana).
			for side in [[cz.lo, float(cz.a), 1.0], [cz.hi, float(cz.b), -1.0]]:
				var st: Dictionary = side[0]
				if not (st.id in MAIN_IDS):
					continue
				var curb: float = side[1]
				var dir: float = side[2]
				var lc := snappedf(curb + dir * (float(st.walk) - 0.5) - 0.2, 0.4) + 0.2
				_tilted_top(gx, jx0 + 0.4, jx1 - 0.4, lc - 0.2, lc + 0.2, off, false, false)
				for jx in [jx0, jx1]:
					_tilted_top(al, jx - 0.4, jx + 0.4, minf(curb, lc + dir * 0.4), maxf(curb, lc + dir * 0.4), off, false, false)
			# Andenes a lo largo de las carreras (oeste y este de la manzana).
			for side2 in [[cx.lo, float(cx.a), 1.0], [cx.hi, float(cx.b), -1.0]]:
				var st2: Dictionary = side2[0]
				if not (st2.id in MAIN_IDS):
					continue
				var curb2: float = side2[1]
				var dir2: float = side2[2]
				var lc2 := snappedf(curb2 + dir2 * (float(st2.walk) - 0.5) - 0.2, 0.4) + 0.2
				_tilted_top(gz, lc2 - 0.2, lc2 + 0.2, jz0 + 0.4, jz1 - 0.4, off, false, false)
				for jz in [jz0, jz1]:
					_tilted_top(al, minf(curb2, lc2 + dir2 * 0.4), maxf(curb2, lc2 + dir2 * 0.4), jz - 0.4, jz + 0.4, off, false, false)


## Siembra de las jardineras del parque (cuadrantes, coordenadas u,v ≥ 0 multiplicadas por el signo):
## setos tras las rejas del perímetro, macizos al pie de los árboles, hiedra en los bordes hacia los
## senderos, palmas pequeñas, una palma alta por cuadrante, agaves y matas de pasto.
## Huella de las jardineras: [12..31]×[2.5..31] y [2.5..12]×[12..31], tapa a walk_y + 0.35, muros de 0.30.
func _p2plants_park() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 303
	var top := 0.35
	var q := 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var m := Vector2(sx, sz)
			var P := func(u: float, v: float, yaw: float) -> Transform3D:
				var w := Vector2(u, v) * m
				return _p2plants_sheared(Transform3D(Basis(Vector3.UP, yaw), Vector3(w.x, walk_y(w.x) + top, w.y)))
			# Setos detrás de la reja perimetral (u = 30.25 y v = 30.25), con hueco en la esquina exterior.
			var hv := 0
			for run in [[Vector2(30.25, 3.3), Vector2(30.25, 29.6)], [Vector2(3.3, 30.25), Vector2(29.6, 30.25)]]:
				var a: Vector2 = run[0]
				var b: Vector2 = run[1]
				var l := a.distance_to(b)
				var n := int(ceil(l / Plants.HEDGE_SEG))
				var along := (b - a).normalized() * m
				var yaw := atan2(-along.y, along.x)
				for i in n:
					var c := a.lerp(b, (i + 0.5) / n)
					_p2plants_place("hedge_%d" % (hv % Plants.HEDGE_VARIANTS), Plants.hedge(hv % Plants.HEDGE_VARIANTS),
						P.call(c.x, c.y, yaw).scaled_local(Vector3(l / (n * Plants.HEDGE_SEG), 1, 1)))
					hv += 1
				var cw := (a + b) * 0.5 * m
				var cy := walk_y(cw.x) + top + 0.45
				var hs := Vector3(l, 0.9, 0.7) if absf(along.x) > 0.5 else Vector3(0.7, 0.9, l)
				var hb := Basis(Vector3.BACK, atan(SLOPE)) if absf(along.x) > 0.5 else Basis.IDENTITY
				add_col_box(Transform3D(hb, Vector3(cw.x, cy, cw.y)), hs)
			# Macizos al pie de los árboles (los que no quedan contra el seto).
			for sp in [Vector2(20, 8), Vector2(17, 25.5), Vector2(7, 23), Vector2(22, 14), Vector2(9, 16), Vector2(15.5, 5.2)]:
				var mix := r.randi() % 3
				_p2plants_place("pbed_%d" % mix, Plants.garden_bed(3.2, 2.2, mix),
					P.call(sp.x, sp.y, r.randf_range(-0.3, 0.3)))
			# Hiedra en los bordes que dan a los senderos y a la plaza (franja de 1.2 m).
			var ivy_runs := [
				[Vector2(12.6, 3.45), Vector2(29.4, 3.45), true],    # junto al sendero E-O
				[Vector2(3.45, 12.6), Vector2(3.45, 29.4), false],   # junto al sendero N-S
				[Vector2(3.0, 12.95), Vector2(11.6, 12.95), true],   # hacia la plaza
				[Vector2(12.95, 3.0), Vector2(12.95, 11.6), false],
			]
			for ir in ivy_runs:
				var a2: Vector2 = ir[0]
				var b2: Vector2 = ir[1]
				var l2 := a2.distance_to(b2)
				var cnt := maxi(1, int(round(l2 / 4.2)))
				for i in cnt:
					var c2 := a2.lerp(b2, (i + 0.5) / cnt)
					var iv := (q + i) % 3
					var along_u: bool = ir[2]
					_p2plants_place("ivy_%d" % iv, Plants.ivy_patch(4.2, 1.2, iv),
						P.call(c2.x, c2.y, 0.0 if along_u else PI * 0.5).scaled_local(Vector3(l2 / (cnt * 4.2), 1, 1)), false)
			# Palmas pequeñas en macolla y una palma alta.
			for sp2 in [Vector2(5.0, 14.6), Vector2(25.0, 9.8), Vector2(13.6, 28.4)]:
				var v := r.randi() % Plants.SMALL_PALM_VARIANTS
				_p2plants_place("spalm_%d" % v, Plants.small_palm(v), P.call(sp2.x, sp2.y, r.randf() * TAU))
			var tp := Vector2(13.6, 20.0) * m
			var tb := Vector3(tp.x, walk_y(tp.x) + top - 0.05, tp.y)
			var tv := q % Plants.TALL_PALM_VARIANTS
			_p2plants_place("palm_%d" % tv, Plants.tall_palm(tv), Transform3D(Basis(Vector3.UP, r.randf() * TAU), tb))
			add_col_cyl(tb + Vector3(0, 1.5, 0), 0.2, 3.0)
			# Agaves junto a la esquina de la plaza y matas de pasto alto al pie del seto.
			for sp3 in [Vector2(4.2, 13.9), Vector2(5.6, 13.6), Vector2(13.8, 4.6)]:
				var av := r.randi() % Plants.AGAVE_VARIANTS
				_p2plants_place("agave_%d" % av, Plants.agave(av), P.call(sp3.x, sp3.y, r.randf() * TAU))
			for i in 8:
				var gu := r.randf_range(4.0, 28.0)
				var gp := Vector2(gu, 29.4) if i % 2 == 0 else Vector2(29.4, gu)
				var gv := r.randi() % Plants.GRASS_VARIANTS
				_p2plants_place("grass_%d" % gv, Plants.grass_tuft(gv), P.call(gp.x, gp.y, r.randf() * TAU), false)
			q += 1


## kind: 0 = verde, 1 = guayacán amarillo, 2 = guayacán rosado.
func _tree(base: Vector3, s: float, kind: int) -> void:
	# Fase 2 (F2-01): árboles procedurales de world/props/trees.gd (Trees). Consume exactamente los
	# mismos números de _rng que la versión anterior (1 randi + 4 randf por bloque de copa) para no
	# alterar el resto del mapa; esos valores dan la variación (semilla, giro, escala).
	var n := 3 + _rng.randi_range(0, 2)
	var r: Array[float] = []
	for i in n * 4:
		r.append(_rng.randf())
	var tk := Trees.SAMAN
	var sc := s / 1.3
	if kind == 1:
		tk = Trees.GUAYACAN_AMARILLO
	elif kind == 2:
		tk = Trees.GUAYACAN_ROSADO
	elif s < 1.05:
		tk = Trees.ANDEN
		sc = s / 0.85
	sc *= 0.92 + 0.16 * r[2]
	var seed := (n - 3 + int(r[3] * 3.0)) % Trees.VARIANTS
	var xf := Transform3D(Basis(Vector3.UP, r[0] * TAU).scaled(Vector3.ONE * sc), base)
	place_mesh("p2tree_%d_%d" % [tk, seed], Trees.mesh(tk, seed), xf)
	add_col_cyl(base + Vector3(0, 1.5, 0), Trees.trunk_radius(tk) * sc, 3.0)


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
	_p2tr_bollards()
	_p2tr_extra_signs()


## Variante/rumbo deterministas por posición (no consumen _rng).
func _p2tr_hash(p: Vector3) -> int:
	return absi(int(floor(p.x * 7.31) * 73856093) ^ int(floor(p.z * 5.17) * 19349663))


## Rumbo hacia la calzada más cercana (+Z del modelo mirando a la vía).
func _p2tr_face_road(p: Vector3) -> Basis:
	var best := 1e9
	var dir := Vector3(0, 0, 1)
	for k in _xs:
		var dx: float = float(k.pos) - p.x
		if absf(dx) < best:
			best = absf(dx)
			dir = Vector3(signf(dx), 0, 0)
	for c in _zs:
		var dz: float = float(c.pos) - p.z
		if absf(dz) < best:
			best = absf(dz)
			dir = Vector3(0, 0, signf(dz))
	return Basis.looking_at(-dir)


func _bin(p: Vector3) -> void:
	var base := Vector3(p.x, walk_y(p.x), p.z)
	var v := _p2tr_hash(p) % 2
	place_mesh("p2tr_bin_%d" % v, Traffic.bin(v), Transform3D(_p2tr_face_road(p), base))
	_col_cyl(base + Vector3(0, 0.55, 0), 0.32, 1.1)


func _hydrant(p: Vector3) -> void:
	var base := Vector3(p.x, walk_y(p.x), p.z)
	var v := _p2tr_hash(p) % 2
	place_mesh("p2tr_hydrant_%d" % v, Traffic.hydrant(v), Transform3D(_p2tr_face_road(p), base))
	_col_cyl(base + Vector3(0, 0.4, 0), 0.18, 0.8)


## Bolardos amarillos flanqueando las cebras de los cruces que rodean el parque.
func _p2tr_bollards() -> void:
	for kid in ["K38", "K39"]:
		for cid in ["C54", "C55"]:
			var k := _street(kid)
			var c := _street(cid)
			var kx: float = k.pos
			var kh: float = k.half
			var cz: float = c.pos
			var ch: float = c.half
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					for q in [Vector2(kh + 0.35, ch + 3.95), Vector2(kh + 3.95, ch + 0.35), Vector2(kh + 0.35, ch + 4.9), Vector2(kh + 4.9, ch + 0.35)]:
						var x: float = kx + sx * q.x
						var z: float = cz + sz * q.y
						var v := _p2tr_hash(Vector3(x, 0, z)) % 2
						place_mesh("p2tr_bollard_%d" % v, Traffic.bollard(v), Transform3D(Basis.IDENTITY, Vector3(x, walk_y(x), z)))
						_col_cyl(Vector3(x, walk_y(x) + 0.45, z), 0.09, 0.9)


func _p2tr_sign(sign_name: String, x: float, z: float, face: Vector3, top := 2.5) -> void:
	place_mesh("p2tr_sign_%s_%d" % [sign_name, int(top * 100.0)], Traffic.sign_post_named(sign_name, top),
		Transform3D(Basis.looking_at(-face), Vector3(x, walk_y(x), z)))
	_col_cyl(Vector3(x, walk_y(x) + 1.2, z), 0.05, 2.4)


## Señales sueltas: velocidad 30 en las carreras del parque, paso peatonal antes de las cebras del
## parque, no parquear frente a la iglesia y "BAJE EN 2a" en la parte alta (oriente) del barrio.
func _p2tr_extra_signs() -> void:
	var off := ROAD_HALF + 0.45
	for kx: float in [40.0, -40.0]:
		_p2tr_sign("velocidad_30", kx + off, 74.0, Vector3(0, 0, 1))      # hacia el norte, andén este
		var zs := -74.0
		if fposmod(zs - (Z_MIN + 6.0), 33.0) < 0.8 or fposmod(zs - (Z_MIN + 6.0), 33.0) > 32.2:
			zs -= 1.5
		_p2tr_sign("velocidad_30", kx - off, zs, Vector3(0, 0, -1))      # hacia el sur, andén oeste
	for cz: float in [-40.0, 40.0]:
		_p2tr_sign("paso_peatonal", -57.5, cz + off, Vector3(-1, 0, 0), 2.6)
		var xw := 57.5
		if _p2tr_near_cable_pole(xw):
			xw += 1.5
		_p2tr_sign("paso_peatonal", xw, cz - off, Vector3(1, 0, 0), 2.6)
	for x: float in [-96.0, -66.0]:
		_p2tr_sign("no_parquear", x, -40.0 + off, Vector3(-1, 0, 0), 2.4)
	for cid in ["C54", "C55", "C56"]:
		var cz2: float = _street(cid).pos
		var xb := 168.0
		if _p2tr_near_cable_pole(xb):
			xb += 1.5
		_p2tr_sign("baje_en_2a", xb, cz2 - off, Vector3(1, 0, 0), 2.7)


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
	if h >= 0.5 and r <= 1.0:   # 2.2: base de troncos, postes y faroles → sombra de contacto
		_contact.append(Vector4(center.x, center.y - h * 0.5, center.z, r))
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


## API común de la Fase 2 para colocar modelos de world/props/.
## key: nombre único del modelo+variante (p. ej. "tree_saman_0"). mesh: ArrayMesh con
## sus materiales por superficie (se respetan; no hay material_override).
## Todas las instancias de una key se dibujan en UN MultiMesh (pocas draw calls).
func place_mesh(key: String, mesh: Mesh, xf: Transform3D, shadow := true) -> void:
	if not _mm.has(key):
		_mm[key] = {"mesh": mesh, "mat": null, "xf": [], "shadow": shadow}
	_mm[key].xf.append(xf)


## Para modelos que necesitan nodos propios (luces, partículas, cuerpos dinámicos, Label3D).
## Se agregan como hijos del distrito. Úsalo con moderación (cada nodo cuesta).
func place_node(node: Node3D, xf: Transform3D) -> void:
	node.transform = xf
	add_child(node)


## Colisiones estáticas para props (capa 1). Se suman al StaticBody único del distrito.
func add_col_box(xf: Transform3D, size: Vector3) -> void:
	_col_box(xf, size)


func add_col_cyl(center: Vector3, r: float, h: float) -> void:
	_col_cyl(center, r, h)


## Cilindro con transformada propia (p. ej. inclinado con el terreno).
func add_col_cyl_xf(xf: Transform3D, r: float, h: float) -> void:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	_col_shapes.append([c, xf])


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

class_name PlayerModel
extends Node3D
## "Andro" — protagonista original paisa, construido 100 % por código.
## Antihéroe urbano: chaqueta técnica corta gris carbón con vivos ámbar y franja
## reflectiva, buzo verde oscuro, pañoleta a rayas verde/blanco (Antioquia), cargo
## negro con rodilleras, tenis blancos de suela gruesa, guantes sin dedos y mochila
## cruzada. Altura ~1.78 m, pies en y = 0, mira hacia -Z.
##
## Fase 2: las piezas son mallas generadas (loft de secciones superelípticas, tubos
## sobre trayectorias y elipsoides deformadas) con UV en metros, normales suaves y
## tangentes. Todo lo que cuelga de un pivote se fusiona en UNA MeshInstance3D con
## una superficie por material; los colores van por color de vértice sobre los
## materiales PBR de MatActors (ripstop, punto, sarga, piel, tenis, pañoleta).
## Las mallas se cachean (static) por pivote: varios Andro comparten geometría.
##
## Jerarquía articulada (todos los pivotes rotan; la malla cuelga de ellos):
##   root (pies, para caídas) → hips → spine → chest → neck → head
##                                            chest → upper_arm_l/r → forearm → hand
##                                    hips → thigh_l/r → shin → foot
## Convención de rotación local (x): + adelanta una extremidad colgante,
## - la lleva atrás; en el tronco, x negativo = inclinarse hacia adelante.

# ---------------- Colores (sRGB; van como color de vértice) ----------------
const C_JACKET := Color(0.215, 0.225, 0.242)
const C_JACKET_DARK := Color(0.125, 0.132, 0.145)
const C_AMBER := Color(0.95, 0.58, 0.14)
const C_HOODIE := Color(0.07, 0.2, 0.13)
const C_HOODIE_RIB := Color(0.05, 0.15, 0.1)
const C_SCARF_GREEN := Color(0.0, 0.43, 0.2)
const C_SCARF_WHITE := Color(0.92, 0.93, 0.9)
const C_PANTS := Color(0.17, 0.178, 0.195)
const C_KNEEPAD := Color(0.14, 0.145, 0.155)
const C_SHOE := Color(0.9, 0.9, 0.88)
const C_SOLE := Color(0.97, 0.96, 0.93)
const C_GUM := Color(0.62, 0.6, 0.56)
const C_LACE := Color(0.55, 0.56, 0.58)
const C_GLOVE := Color(0.035, 0.035, 0.04)
const C_BAG := Color(0.1, 0.115, 0.1)
const C_STRAP := Color(0.03, 0.03, 0.035)
const C_ZIP := Color(0.22, 0.23, 0.25)
const C_HAIR := Color(0.045, 0.035, 0.03)
const C_EYE := Color(0.03, 0.02, 0.015)
const C_IRIS := Color(0.16, 0.09, 0.05)
const C_SCLERA := Color(0.78, 0.74, 0.68)
const C_LIP := Color(0.52, 0.32, 0.27)
const SKIN_TONE := Color(0.66, 0.46, 0.34)      # mestizo cálido
const STUBBLE_TONE := Color(0.4, 0.29, 0.23)    # barba de pocos días

# Longitudes de los segmentos (m)
const THIGH_LEN := 0.43
const SHIN_LEN := 0.38
const HIPS_HEIGHT := 0.95
const HEAD_Y := 0.93          # escala vertical de la cabeza
const EYE_Y := 0.134          # altura de los ojos en el pivote head

## Pivotes públicos (para otros sistemas: p. ej. apuntar, IK futura).
var root: Node3D
var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var upper_arm_l: Node3D
var forearm_l: Node3D
var hand_l: Node3D
var upper_arm_r: Node3D
var forearm_r: Node3D
var hand_r: Node3D
var thigh_l: Node3D
var shin_l: Node3D
var foot_l: Node3D
var thigh_r: Node3D
var shin_r: Node3D
var foot_r: Node3D

var _joints: Dictionary = {}       # nombre → Node3D
var _state := "idle"
var _time := 0.0
var _phase := 0.0
var _prev_speed := 0.0
var _accel_f := 0.0
var _prev_yaw := 0.0
var _turn_f := 0.0
var _land_t := 0.0
var _stumble_t := 0.0
var _enter_t := 0.0
var _exit_t := 0.0
var _crouch_w := 0.0               # peso de la postura agachada (filtrado)
var _push_w := 0.0                 # peso de la postura de empujar (filtrado)

## Los fija Player: segundos desde que empezó el golpe actual y cuál del combo (0 jab, 1 cruzado, 2 patada).
var punch_t := 0.0
var punch_idx := 0
var _air_t := 0.0
var _gait_g := 0.0                 # mezcla caminar→correr filtrada
var _gait_s := 0.0                 # mezcla correr→sprint filtrada
var _move_w := 0.0                 # peso de locomoción filtrado
var _hips_y := 0.0
var _built := false

# Constructor de mallas (estado temporal por pivote)
var _sts: Dictionary = {}          # Material → SurfaceTool
var _cnt: Dictionary = {}          # Material → nº de vértices
static var _mesh_cache: Dictionary = {}   # nombre de pivote → ArrayMesh
static var _mats: Dictionary = {}
static var _tiles: Dictionary = {}        # Material → metros por repetición de textura


func _ready() -> void:
	if not _built:
		_build()


# =====================================================================
#  CONSTRUCCIÓN
# =====================================================================

func _build() -> void:
	_built = true
	root = _pivot("root", self, Vector3.ZERO)
	hips = _pivot("hips", root, Vector3(0, HIPS_HEIGHT, 0))
	spine = _pivot("spine", hips, Vector3(0, 0.1, 0))
	chest = _pivot("chest", spine, Vector3(0, 0.2, 0))
	neck = _pivot("neck", chest, Vector3(0, 0.24, 0.005))
	head = _pivot("head", neck, Vector3(0, 0.065, -0.005))
	for side in [-1, 1]:
		var sx := float(side)
		var sfx := "l" if side < 0 else "r"
		var ua := _pivot("upper_arm_" + sfx, chest, Vector3(0.2 * sx, 0.175, 0.0))
		var fa := _pivot("forearm_" + sfx, ua, Vector3(0, -0.29, 0))
		var hd := _pivot("hand_" + sfx, fa, Vector3(0, -0.25, 0))
		var th := _pivot("thigh_" + sfx, hips, Vector3(0.09 * sx, -0.04, 0.0))
		var sh := _pivot("shin_" + sfx, th, Vector3(0, -THIGH_LEN, 0))
		var ft := _pivot("foot_" + sfx, sh, Vector3(0, -SHIN_LEN, 0))
		if side < 0:
			upper_arm_l = ua; forearm_l = fa; hand_l = hd
			thigh_l = th; shin_l = sh; foot_l = ft
		else:
			upper_arm_r = ua; forearm_r = fa; hand_r = hd
			thigh_r = th; shin_r = sh; foot_r = ft
	_dress(hips, "hips", _geo_pelvis)
	_dress(spine, "spine", _geo_spine)
	_dress(chest, "chest", _geo_chest)
	_dress(neck, "neck", _geo_neck)
	_dress(head, "head", _geo_head)
	for side in [-1, 1]:
		var sfx := "l" if side < 0 else "r"
		_dress(_joints["upper_arm_" + sfx], "upper_arm_" + sfx, _geo_upper_arm.bind(float(side)))
		_dress(_joints["forearm_" + sfx], "forearm_" + sfx, _geo_forearm.bind(float(side)))
		_dress(_joints["hand_" + sfx], "hand_" + sfx, _geo_hand.bind(float(side)))
		_dress(_joints["thigh_" + sfx], "thigh_" + sfx, _geo_thigh.bind(float(side)))
		_dress(_joints["shin_" + sfx], "shin_" + sfx, _geo_shin.bind(float(side)))
		_dress(_joints["foot_" + sfx], "foot_" + sfx, _geo_foot.bind(float(side)))
	_prev_yaw = global_rotation.y if is_inside_tree() else 0.0


func _pivot(pname: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	parent.add_child(n)
	_joints[pname] = n
	return n


## Cuelga del pivote una sola MeshInstance3D con todas sus piezas (cacheada).
func _dress(pivot: Node3D, key: String, builder: Callable) -> void:
	var mesh: ArrayMesh
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key]
	else:
		_sts.clear()
		_cnt.clear()
		builder.call()
		mesh = ArrayMesh.new()
		for mat in _sts:
			var st: SurfaceTool = _sts[mat]
			st.generate_tangents()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		_sts.clear()
		_cnt.clear()
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	pivot.add_child(mi)


## Triángulos totales del modelo (para presupuesto/tests).
func triangle_count() -> int:
	var tris := 0
	for k in _joints:
		var n: Node3D = _joints[k]
		var mi := n.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return tris


# ---------------------------------------------------------------------
#  Materiales (MatActors + color de vértice). Las UV se generan en metros
#  y aquí se divide por el tile de cada textura.
# ---------------------------------------------------------------------

static func _vcmat(key: String, base: Material, tile: float) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: BaseMaterial3D = base.duplicate()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	_mats[key] = m
	_tiles[m] = tile
	return m

static func _rip() -> Material:     # chaqueta, vivos, guantes, rodilleras, mochila
	return _vcmat("rip", MatActors.jacket_ripstop(Color.WHITE, Vector3.ONE), 0.3)

static func _knit() -> Material:    # buzo
	return _vcmat("knit", MatActors.hoodie_knit(Color.WHITE, Vector3.ONE), 0.15)

static func _twill() -> Material:   # cargo
	return _vcmat("twill", MatActors.cargo_twill(Color.WHITE, Vector3.ONE), 0.25)

static func _skin() -> Material:
	return _vcmat("skin", MatActors.skin(Color.WHITE, Vector3.ONE), 0.12)

static func _hair() -> Material:    # el punto a escala fina da fibra de pelo
	return _vcmat("hair", MatActors.hoodie_knit(Color.WHITE, Vector3.ONE), 0.045)

static func _shoe() -> Material:    # UV propias (u/0.25, v 0..0.64)
	return _vcmat("shoe", MatActors.sneaker(Color.WHITE, Vector3.ONE), 1.0)

static func _sole() -> Material:    # v 0..1 = alto de la suela
	return _vcmat("sole", MatActors.sneaker_sole(Color.WHITE), 1.0)

static func _scarf() -> Material:
	var m := MatActors.scarf_antioquia(Color.WHITE, Vector3.ONE)
	_tiles[m] = 0.16
	return m

static func _glow() -> Material:    # franja reflectiva (brilla de noche con el glow)
	return Palette.neon(Color(1.0, 0.6, 0.18), 1.3)


## El albedo de las telas tiene media ~0.8: compensamos para llegar al color pedido.
static func _c(c: Color) -> Color:
	return Color(minf(c.r / 0.8, 1.0), minf(c.g / 0.8, 1.0), minf(c.b / 0.8, 1.0))


# ---------------------------------------------------------------------
#  Primitivas de malla
# ---------------------------------------------------------------------

func _st(mat: Material) -> SurfaceTool:
	if not _sts.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sts[mat] = st
		_cnt[mat] = 0
	return _sts[mat]


## Emite una rejilla cerrada en u (nr filas × m columnas). Normales suaves por
## acumulación de caras (los polos se promedian), orientación hacia afuera
## automática, costura UV duplicada. col: Color o Callable(p) -> Color.
## uvf: Callable(p, uv_metros) -> Vector2 opcional (ya en unidades de textura).
func _grid(mat: Material, P: PackedVector3Array, nr: int, m: int, xf: Transform3D,
		col: Variant, uvf := Callable()) -> void:
	var N := PackedVector3Array()
	N.resize(nr * m)
	for i in nr - 1:
		for j in m:
			var j1 := (j + 1) % m
			var ia := i * m + j
			var ib := i * m + j1
			var ic := (i + 1) * m + j1
			var id := (i + 1) * m + j
			var f1 := (P[ib] - P[ia]).cross(P[ic] - P[ia])
			var f2 := (P[ic] - P[ia]).cross(P[id] - P[ia])
			N[ia] += f1 + f2
			N[ib] += f1
			N[ic] += f1 + f2
			N[id] += f2
	var cen := PackedVector3Array()
	cen.resize(nr)
	var s := 0.0
	for i in nr:
		var c := Vector3.ZERO
		for j in m:
			c += P[i * m + j]
		c /= float(m)
		cen[i] = c
		var spread := 0.0
		for j in m:
			spread = maxf(spread, (P[i * m + j] - c).length_squared())
		if spread < 1e-10:
			var avg := Vector3.ZERO
			for j in m:
				avg += N[i * m + j]
			for j in m:
				N[i * m + j] = avg
		for j in m:
			s += N[i * m + j].dot(P[i * m + j] - c)
	var flip := s < 0.0
	for k in N.size():
		var nn := N[k]
		if flip:
			nn = -nn
		N[k] = nn.normalized() if nn.length_squared() > 1e-20 else Vector3.UP
	# UV en metros: u = fracción del perímetro medio, v = distancia acumulada
	var per := 0.0
	var per_n := 0
	var vcum := PackedFloat32Array()
	vcum.resize(nr)
	for i in nr:
		var pr := 0.0
		for j in m:
			pr += (P[i * m + (j + 1) % m] - P[i * m + j]).length()
		if pr > 1e-4:
			per += pr
			per_n += 1
		if i > 0:
			var d := 0.0
			for j in m:
				d += (P[i * m + j] - P[(i - 1) * m + j]).length()
			vcum[i] = vcum[i - 1] + d / float(m)
	per = per / float(maxi(per_n, 1))
	var tile: float = _tiles.get(mat, 0.3)
	var nb := xf.basis.inverse().transposed()
	var st := _st(mat)
	var base: int = _cnt[mat]
	for i in nr:
		for j in m + 1:
			var k := i * m + (j % m)
			var p := xf * P[k]
			var n := (nb * N[k]).normalized()
			var uv := Vector2(float(j) / float(m) * per, vcum[i])
			if uvf.is_valid():
				uv = uvf.call(p, uv)
			else:
				uv /= tile
			var c: Color = col.call(p) if col is Callable else col
			st.set_color(c)
			st.set_normal(n)
			st.set_uv(uv)
			st.add_vertex(p)
	_cnt[mat] = base + nr * (m + 1)
	var w := m + 1
	for i in nr - 1:
		for j in m:
			var a := base + i * w + j
			var b := a + 1
			var c2 := a + w + 1
			var d := a + w
			if flip:
				st.add_index(a); st.add_index(b); st.add_index(c2)
				st.add_index(a); st.add_index(c2); st.add_index(d)
			else:
				st.add_index(a); st.add_index(c2); st.add_index(b)
				st.add_index(a); st.add_index(d); st.add_index(c2)


## Anillo de loft: sección superelíptica horizontal. bf = semiprofundidad hacia
## adelante (-z), bb = hacia atrás (+z), n = exponente (2 elipse, 4+ caja redondeada),
## w = amplitud de pliegues de tela, tilt = pendiente y por z (anillos inclinados).
static func _rr(y: float, a: float, bf: float, bb: float, cz := 0.0, n := 2.0, w := 0.0,
		cx := 0.0, tilt := 0.0) -> Dictionary:
	return {"y": y, "a": a, "bf": bf, "bb": bb, "cz": cz, "n": n, "w": w, "cx": cx, "tilt": tilt}

static func _r(y: float, a: float, b: float, cz := 0.0, n := 2.0, w := 0.0, cx := 0.0) -> Dictionary:
	return _rr(y, a, b, b, cz, n, w, cx)


func _loft(mat: Material, rings: Array, segs: int, xf := Transform3D.IDENTITY,
		col: Variant = Color.WHITE, uvf := Callable(), deform := Callable()) -> void:
	var nr := rings.size()
	var P := PackedVector3Array()
	P.resize(nr * segs)
	for i in nr:
		var r: Dictionary = rings[i]
		var a: float = r["a"]
		var n: float = r["n"]
		var w: float = r["w"]
		var ph := float(i) * 1.7
		for j in segs:
			var th := TAU * float(j) / float(segs)
			var c := cos(th)
			var s := sin(th)
			var ex := signf(c) * pow(absf(c), 2.0 / n)
			var ez := signf(s) * pow(absf(s), 2.0 / n)
			var wr := 1.0 + w * (0.6 * sin(5.0 * th + ph) + 0.4 * sin(11.0 * th + ph * 2.3))
			var bz: float = r["bf"] if s < 0.0 else r["bb"]
			var x: float = r["cx"] + a * ex * wr
			var z: float = r["cz"] + bz * ez * wr
			var y: float = r["y"] + (z - r["cz"]) * r["tilt"]
			var p := Vector3(x, y, z)
			if deform.is_valid():
				p = deform.call(p)
			P[i * segs + j] = p
	_grid(mat, P, nr, segs, xf, col, uvf)


## Tubo a lo largo de una trayectoria; ra = semiancho (eje "side"), rb = semigrosor.
## side = T × up. caps: tapas redondeadas en los extremos.
func _tube(mat: Material, path: PackedVector3Array, ra: Variant, rb: Variant, segs: int,
		up: Vector3, col: Variant, caps := true, n := 2.0, xf := Transform3D.IDENTITY) -> void:
	var np := path.size()
	var rows: Array[PackedVector3Array] = []
	var first := PackedVector3Array()
	var last := PackedVector3Array()
	for i in np:
		var t := (path[mini(i + 1, np - 1)] - path[maxi(i - 1, 0)]).normalized()
		var sd := t.cross(up)
		if sd.length_squared() < 1e-6:
			sd = t.cross(Vector3(1, 0, 0.3))
		sd = sd.normalized()
		var nm := sd.cross(t).normalized()
		var a: float = ra[i] if ra is Array else float(ra)
		var b: float = rb[i] if rb is Array else float(rb)
		var row := PackedVector3Array()
		row.resize(segs)
		for j in segs:
			var th := TAU * float(j) / float(segs)
			var c := cos(th)
			var s := sin(th)
			row[j] = path[i] + sd * a * signf(c) * pow(absf(c), 2.0 / n) + nm * b * signf(s) * pow(absf(s), 2.0 / n)
		rows.append(row)
		if i == 0:
			first.resize(segs)
			first.fill(path[0] - t * minf(a, b) * 0.6)
		if i == np - 1:
			last.resize(segs)
			last.fill(path[i] + t * minf(a, b) * 0.6)
	if caps:
		rows.push_front(first)
		rows.append(last)
	var P := PackedVector3Array()
	for r in rows:
		P.append_array(r)
	_grid(mat, P, rows.size(), segs, xf, col)


func _ellip(mat: Material, c: Vector3, r: Vector3, col: Variant, rot := Vector3.ZERO,
		segs := 12, rn := 7, xf := Transform3D.IDENTITY) -> void:
	var rings: Array = []
	for k in rn + 1:
		var ph := PI * float(k) / float(rn)
		rings.append(_r(-r.y * cos(ph), r.x * sin(ph), r.z * sin(ph)))
	_loft(mat, rings, segs, xf * Transform3D(Basis.from_euler(rot), c), col)


## Interpolación Catmull-Rom de anillos clave (ordenados por y) en las alturas ys.
static func _resample(keys: Array, ys: Array) -> Array:
	var out: Array = []
	for y in ys:
		out.append(_ring_at(keys, y))
	return out

static func _ring_at(keys: Array, y: float) -> Dictionary:
	var n := keys.size()
	var i := 0
	while i < n - 2 and y > float(keys[i + 1]["y"]):
		i += 1
	var k1: Dictionary = keys[i]
	var k2: Dictionary = keys[i + 1]
	var k0: Dictionary = keys[maxi(i - 1, 0)]
	var k3: Dictionary = keys[mini(i + 2, n - 1)]
	var t := clampf((y - float(k1["y"])) / maxf(float(k2["y"]) - float(k1["y"]), 1e-5), 0.0, 1.0)
	var out := {}
	for key in k1:
		var p0: float = k0[key]
		var p1: float = k1[key]
		var p2: float = k2[key]
		var p3: float = k3[key]
		out[key] = 0.5 * (2.0 * p1 + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
	out["y"] = y
	return out


## Punto sobre la superficie de un loft (adelante o atrás) en (x, y), con offset hacia afuera.
static func _on_surf(keys: Array, x: float, y: float, front: bool, off := 0.0) -> Vector3:
	var r := _ring_at(keys, y)
	var a: float = r["a"]
	var n: float = r["n"]
	var t := clampf(absf(x - float(r["cx"])) / a, 0.0, 0.999)
	var e := pow(1.0 - pow(t, n), 1.0 / n)
	var z: float = float(r["cz"]) - float(r["bf"]) * e - off if front else float(r["cz"]) + float(r["bb"]) * e + off
	return Vector3(x, y, z)


static func _surf_path(keys: Array, from: Vector2, to: Vector2, front: bool, off: float, pts := 6) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in pts:
		var q := from.lerp(to, float(i) / float(pts - 1))
		out.append(_on_surf(keys, q.x, q.y, front, off))
	return out


# ---------------------------------------------------------------------
#  Pelvis (cargo) y abdomen (buzo)
# ---------------------------------------------------------------------

func _geo_pelvis() -> void:
	var rings := [
		_r(-0.168, 0.0, 0.0, 0.0),
		_rr(-0.165, 0.05, 0.045, 0.05, 0.0, 2.0),
		_rr(-0.13, 0.13, 0.092, 0.11, 0.004, 2.2, 0.02),
		_rr(-0.07, 0.165, 0.104, 0.124, 0.006, 2.3, 0.015),
		_rr(0.0, 0.168, 0.104, 0.118, 0.0, 2.4),
		_rr(0.06, 0.16, 0.1, 0.11, 0.0, 2.4),
		_r(0.07, 0.0, 0.0, 0.0),
	]
	_loft(_twill(), rings, 20, Transform3D.IDENTITY, _c(C_PANTS))
	# Bolsillos traseros (parches con pespunte)
	for sx in [-1.0, 1.0]:
		var c := _on_surf(rings.slice(1, 6), 0.075 * sx, -0.07, false, 0.0)
		_loft(_twill(), [
			_r(-0.125, 0.0, 0.0, c.z, 2.0, 0.0, 0.075 * sx),
			_rr(-0.12, 0.045, 0.006, 0.006, c.z, 4.0, 0.0, 0.075 * sx),
			_rr(-0.035, 0.05, 0.006, 0.006, c.z - 0.004, 4.0, 0.0, 0.075 * sx),
			_r(-0.03, 0.0, 0.0, c.z - 0.004, 2.0, 0.0, 0.075 * sx)],
			10, Transform3D.IDENTITY, _c(C_PANTS * 1.25))


func _geo_spine() -> void:
	var rings := [
		_r(-0.125, 0.0, 0.0),
		_rr(-0.125, 0.16, 0.118, 0.12, 0.0, 2.4),
		_rr(-0.088, 0.162, 0.119, 0.121, 0.0, 2.4),
		_rr(-0.082, 0.156, 0.112, 0.114, 0.0, 2.4, 0.035),
		_rr(-0.03, 0.163, 0.118, 0.118, 0.0, 2.4, 0.04),
		_rr(0.05, 0.168, 0.119, 0.118, 0.0, 2.4, 0.02),
		_rr(0.15, 0.17, 0.12, 0.12, 0.0, 2.4),
		_rr(0.24, 0.15, 0.1, 0.1, 0.0, 2.2),
		_r(0.25, 0.0, 0.0),
	]
	var rib := _c(C_HOODIE_RIB)
	var body := _c(C_HOODIE)
	_loft(_knit(), rings, 24, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return rib if p.y < -0.085 else body)


# ---------------------------------------------------------------------
#  Torso: chaqueta, capucha, pañoleta, mochila cruzada
# ---------------------------------------------------------------------

## Anillos exteriores de la chaqueta (también sirven para pegar detalles a la superficie).
static func _jacket_rings() -> Array:
	return [
		_rr(-0.197, 0.187, 0.129, 0.128, 0.0, 2.6),
		_rr(-0.17, 0.192, 0.133, 0.131, 0.0, 2.6, 0.01),
		_rr(-0.163, 0.189, 0.13, 0.129, 0.0, 2.6, 0.015),
		_rr(-0.1, 0.185, 0.127, 0.126, 0.0, 2.6, 0.03),
		_rr(-0.02, 0.19, 0.133, 0.128, 0.0, 2.6, 0.015),
		_rr(0.07, 0.2, 0.139, 0.13, 0.0, 2.5, 0.006),
		_rr(0.145, 0.205, 0.134, 0.131, 0.0, 2.6),
		_rr(0.195, 0.212, 0.118, 0.123, 0.005, 3.0),
		_rr(0.23, 0.19, 0.1, 0.11, 0.008, 2.8),
		_rr(0.252, 0.13, 0.092, 0.1, 0.008, 2.3),
		_rr(0.262, 0.104, 0.09, 0.095, 0.007, 2.0),
		_rr(0.29, 0.1, 0.089, 0.093, 0.006, 2.0, 0.012),
		_rr(0.308, 0.097, 0.087, 0.09, 0.004, 2.0),
	]


func _geo_chest() -> void:
	var rip := _rip()
	var keys := _jacket_rings()
	var rings: Array = [_r(-0.197, 0.0, 0.0)] + keys + [
		_rr(0.314, 0.088, 0.078, 0.081, 0.004, 2.0),
		_rr(0.295, 0.074, 0.066, 0.07, 0.004, 2.0),
		_r(0.28, 0.0, 0.0, 0.004),
	]
	var cj := _c(C_JACKET)
	var cd := _c(C_JACKET_DARK)
	var ca := _c(C_AMBER)
	var cz := _c(C_ZIP)
	var cs := _c(C_STRAP)
	# Cuerpo: dobladillo y cuello oscuros, vivo ámbar en el borde del cuello
	_loft(rip, rings, 26, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		if p.y > 0.309:
			return ca
		if p.y < -0.166 or p.y > 0.258:
			return cd
		return cj)

	# Cremallera frontal hasta el cuello alto + vivos ámbar a cada lado
	var up_f := Vector3(0, 0, -1)
	_tube(rip, _surf_path(keys, Vector2(0, -0.195), Vector2(0, 0.307), true, 0.002, 8), 0.0055, 0.0035, 5, up_f, cz)
	for sx in [-1.0, 1.0]:
		_tube(rip, _surf_path(keys, Vector2(0.015 * sx, -0.19), Vector2(0.015 * sx, 0.302), true, 0.0015, 8),
			0.0032, 0.0028, 4, up_f, ca)
		# Bolsillos de mano: cremallera diagonal con ribete
		_tube(rip, _surf_path(keys, Vector2(0.105 * sx, -0.035), Vector2(0.16 * sx, -0.14), true, 0.002, 5),
			0.007, 0.003, 5, up_f, cd)
		# Vivo de hombro (costura raglán)
		var sh := PackedVector3Array([Vector3(0.105 * sx, 0.257, 0.008), Vector3(0.14 * sx, 0.236, 0.008),
			Vector3(0.172 * sx, 0.212, 0.006)])
		_tube(rip, sh, 0.0035, 0.004, 5, Vector3(0, 1, 0), ca)
	# Bolsillo de pecho izquierdo (cremallera ámbar) y parche oscuro a la derecha
	_tube(rip, _surf_path(keys, Vector2(-0.055, 0.155), Vector2(-0.15, 0.115), true, 0.002, 5),
		0.004, 0.003, 5, up_f, ca)
	var pc := _on_surf(keys, 0.1, 0.14, true, 0.0)
	_loft(rip, [_r(0.12, 0.0, 0.0, pc.z, 2, 0, 0.1), _rr(0.122, 0.028, 0.004, 0.004, pc.z - 0.002, 5.0, 0.0, 0.1),
		_rr(0.158, 0.028, 0.004, 0.004, pc.z - 0.004, 5.0, 0.0, 0.1), _r(0.16, 0.0, 0.0, pc.z - 0.004, 2, 0, 0.1)],
		12, Transform3D.IDENTITY, cd)

	# Franja reflectiva en la espalda + línea ámbar baja
	var up_b := Vector3(0, 0, 1)
	_tube(_glow(), _surf_path(keys, Vector2(-0.175, 0.1), Vector2(0.175, 0.1), false, 0.002, 9),
		0.012, 0.003, 6, up_b, Color.WHITE, true, 4.0)
	_tube(rip, _surf_path(keys, Vector2(-0.16, -0.05), Vector2(0.16, -0.05), false, 0.002, 9),
		0.003, 0.004, 5, up_b, ca)

	# --- Capucha baja: rollo grueso alrededor del cuello + paño sobre la espalda ---
	_ellip(rip, Vector3(0, 0.175, 0.128), Vector3(0.13, 0.085, 0.045), cj, Vector3(-0.35, 0, 0), 14, 7)
	var hood := PackedVector3Array()
	var hra: Array = []
	var hrb: Array = []
	for i in 9:
		var t := float(i) / 8.0
		var ang := lerpf(-1.75, 1.75, t)          # 0 = atrás
		var rr := 0.1 + 0.02 * cos(ang * 0.5)
		hood.append(Vector3(sin(ang) * rr, 0.262 - 0.012 * cos(ang * 0.5), cos(ang) * (rr + 0.012) + 0.006))
		var k := cos(ang * 0.5)
		hra.append(0.022 + 0.022 * k)
		hrb.append(0.02 + 0.03 * k)
	_tube(rip, hood, hra, hrb, 8, Vector3(0, 1, 0), cj)
	# Vivo ámbar en el borde de la capucha
	var edge := PackedVector3Array()
	for i in 9:
		var p := hood[i]
		edge.append(p + Vector3(0, float(hrb[i]) * 0.95, 0))
	_tube(rip, edge, 0.004, 0.004, 5, Vector3(0, 0, 1), ca)
	# Cordones de la capucha con herretes
	for sx in [-1.0, 1.0]:
		var top := _on_surf(keys, 0.045 * sx, 0.275, true, 0.003)
		var mid := _on_surf(keys, 0.05 * sx, 0.2, true, 0.006)
		var end := _on_surf(keys, 0.055 * sx + 0.004, 0.125 + 0.015 * sx, true, 0.008)
		_tube(rip, PackedVector3Array([top, mid.lerp(top, 0.3), mid, end]), 0.0035, 0.0035, 5, up_f, _c(C_LACE))
		_tube(rip, PackedVector3Array([end, end + Vector3(0.001 * sx, -0.022, -0.001)]), 0.005, 0.005, 6, up_f, ca)

	# --- Pañoleta a rayas (Antioquia): rollo al cuello, nudo y puntas al pecho ---
	var scarf := _scarf()
	var srings := [
		_rr(0.268, 0.0, 0.0, 0.0, -0.006, 2.0, 0.0, 0.0, 0.25),
		_rr(0.27, 0.09, 0.092, 0.088, -0.006, 2.0, 0.0, 0.0, 0.25),
		_rr(0.284, 0.108, 0.114, 0.1, -0.012, 2.0, 0.05, 0.0, 0.25),
		_rr(0.302, 0.106, 0.112, 0.098, -0.013, 2.0, 0.07, 0.0, 0.25),
		_rr(0.318, 0.09, 0.094, 0.085, -0.01, 2.0, 0.03, 0.0, 0.25),
		_rr(0.322, 0.068, 0.07, 0.066, -0.008, 2.0, 0.0, 0.0, 0.25),
		_rr(0.31, 0.0, 0.0, 0.0, -0.008, 2.0, 0.0, 0.0, 0.25),
	]
	_loft(scarf, srings, 20, Transform3D.IDENTITY, Color.WHITE, func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(p.y / 0.16, atan2(p.x, p.z) / TAU * 0.62 / 0.3))
	_ellip(scarf, Vector3(0.022, 0.278, -0.118), Vector3(0.03, 0.025, 0.02), Color.WHITE, Vector3(0.2, 0, 0.3), 12, 6)
	for k in 2:
		var x0 := 0.022 + (0.0 if k == 0 else -0.012)
		var ln := 0.15 if k == 0 else 0.11
		var tip := PackedVector3Array()
		var tra: Array = []
		for i in 6:
			var t := float(i) / 5.0
			var y := 0.272 - ln * t
			var x := x0 + (0.012 if k == 0 else -0.01) * t
			tip.append(_on_surf(keys, x, y, true, 0.012 + 0.006 * (1.0 - t) + 0.004 * k))
			tra.append(lerpf(0.032, 0.004, t * t) * (1.0 if k == 0 else 0.85))
		_tube(scarf, tip, tra, 0.005, 6, up_f, Color.WHITE, true, 2.5)

	# --- Mochila pequeña cruzada (hombro izq. → cadera der.) ---
	var shoulder := Vector3(-0.145, 0.252, 0.004)
	var fpath := PackedVector3Array([shoulder])
	fpath.append_array(_surf_path(keys, Vector2(-0.13, 0.215), Vector2(0.165, -0.15), true, 0.012, 7))
	_tube(rip, fpath, 0.019, 0.004, 6, up_f, cs, true, 4.0)
	var bpath := PackedVector3Array([shoulder])
	bpath.append_array(_surf_path(keys, Vector2(-0.13, 0.215), Vector2(0.03, -0.05), false, 0.008, 6))
	_tube(rip, bpath, 0.019, 0.004, 6, up_b, cs, true, 4.0)
	var bxf0 := Transform3D(Basis.from_euler(Vector3(0.05, 0, 0.5)), Vector3(0.085, -0.115, 0.172))
	_tube(rip, PackedVector3Array([fpath[fpath.size() - 1], Vector3(0.2, -0.13, -0.02), Vector3(0.205, -0.1, 0.07),
		bxf0 * Vector3(0.118, 0.0, 0.0)]), 0.019, 0.004, 6, Vector3(1, 0, 0), cs, true, 4.0)
	# Hebilla/regulador en la correa delantera
	var bk := _on_surf(keys, -0.03, 0.09, true, 0.018)
	var ang_s := 0.78
	_loft(rip, [_r(-0.016, 0.0, 0.0), _r(-0.015, 0.024, 0.005, 0.0, 5.0), _r(0.015, 0.024, 0.005, 0.0, 5.0),
		_r(0.016, 0.0, 0.0)], 8, Transform3D(Basis.from_euler(Vector3(0, 0, ang_s)), bk), cz)
	# Bolso a la espalda baja-derecha (caja redondeada con cremallera ámbar)
	var bxf := Transform3D(Basis.from_euler(Vector3(0.05, 0, 0.5)), Vector3(0.085, -0.115, 0.172))
	var cb := _c(C_BAG)
	_loft(rip, [_r(-0.076, 0.0, 0.0), _r(-0.074, 0.112, 0.034, 0.0, 4.0), _r(-0.06, 0.122, 0.04, 0.0, 4.0, 0.01),
		_r(0.052, 0.122, 0.043, 0.0, 4.0, 0.01), _r(0.07, 0.11, 0.036, 0.0, 4.0), _r(0.075, 0.0, 0.0)],
		20, bxf, cb)
	_tube(rip, PackedVector3Array([Vector3(-0.1, 0.071, 0.0), Vector3(0.0, 0.074, 0.0), Vector3(0.1, 0.071, 0.0)]),
		0.004, 0.012, 5, Vector3(0, 1, 0), ca, true, 2.0, bxf)
	# bolsillo frontal del bolso con solapa
	_loft(rip, [_r(-0.055, 0.0, 0.0, 0.046), _r(-0.052, 0.07, 0.007, 0.046, 4.0), _r(0.02, 0.075, 0.008, 0.047, 4.0),
		_r(0.024, 0.0, 0.0, 0.047)], 12, bxf, _c(C_BAG * 1.35))
	_tube(rip, PackedVector3Array([Vector3(-0.07, 0.018, 0.056), Vector3(0.07, 0.018, 0.056)]), 0.003, 0.003, 5,
		Vector3(0, 0, 1), ca, true, 2.0, bxf)


# ---------------------------------------------------------------------
#  Cuello y cabeza
# ---------------------------------------------------------------------

func _geo_neck() -> void:
	var stub := _c(STUBBLE_TONE)
	var skin := _c(SKIN_TONE)
	_loft(_skin(), [_r(-0.03, 0.0, 0.0), _rr(-0.03, 0.05, 0.05, 0.052, 0.005), _rr(0.04, 0.049, 0.049, 0.05, 0.004),
		_rr(0.09, 0.052, 0.054, 0.05, -0.002), _rr(0.125, 0.05, 0.05, 0.05, -0.005), _r(0.13, 0.0, 0.0, -0.005)],
		16, Transform3D.IDENTITY, func(p: Vector3) -> Color:
			return skin.lerp(stub, 0.6 * clampf((p.y - 0.06) / 0.04, 0.0, 1.0) * clampf(-p.z / 0.03, 0.0, 1.0)))


## Anillos clave de la cabeza (frente = -z). y ya escalado por HEAD_Y.
static func _head_keys() -> Array:
	var raw := [
		[0.0, 0.032, 0.022, 0.03, -0.064, 2.4],
		[0.015, 0.049, 0.04, 0.05, -0.052, 2.4],
		[0.035, 0.062, 0.056, 0.075, -0.032, 2.4],
		[0.06, 0.07, 0.075, 0.085, -0.018, 2.4],
		[0.09, 0.071, 0.088, 0.095, -0.01, 2.4],
		[0.12, 0.074, 0.093, 0.1, -0.006, 2.5],
		[0.145, 0.077, 0.095, 0.104, -0.004, 2.5],
		[0.17, 0.078, 0.094, 0.105, 0.0, 2.4],
		[0.195, 0.074, 0.087, 0.1, 0.003, 2.3],
		[0.215, 0.062, 0.073, 0.088, 0.005, 2.2],
		[0.23, 0.04, 0.048, 0.06, 0.006, 2.0],
	]
	var out: Array = []
	for r in raw:
		out.append(_rr(r[0] * HEAD_Y, r[1], r[2], r[3], r[4], r[5]))
	return out


## Modelado fino de la cara: cuencas, arco superciliar, pómulos, surco bajo el labio.
func _head_deform(p: Vector3) -> Vector3:
	if p.z > -0.02:
		return p
	var q := p
	var fz := clampf((-p.z - 0.02) / 0.05, 0.0, 1.0)
	for sx in [-1.0, 1.0]:
		var dx: float = p.x - sx * 0.033
		var dy: float = p.y - EYE_Y
		q.z += 0.009 * exp(-(dx * dx / 0.00036 + dy * dy / 0.00016)) * fz
		var dx2: float = p.x - sx * 0.052
		var dy2: float = p.y - 0.106
		q.z -= 0.005 * exp(-(dx2 * dx2 + dy2 * dy2) / 0.0004) * fz
		# mejilla hundida bajo el pómulo
		var dx3: float = p.x - sx * 0.05
		var dy3: float = p.y - 0.07
		q.z += 0.004 * exp(-(dx3 * dx3 + dy3 * dy3) / 0.0003) * fz
	var gb := exp(-pow((p.y - 0.152) / 0.011, 2.0)) * clampf(1.0 - absf(p.x) / 0.07, 0.0, 1.0)
	q.z -= 0.006 * gb * fz
	# surco mentolabial y mentón
	q.z += 0.003 * exp(-pow((p.y - 0.038) / 0.006, 2.0)) * clampf(1.0 - absf(p.x) / 0.03, 0.0, 1.0) * fz
	return q


func _head_z(x: float, y: float, keys: Array) -> float:
	var p := _on_surf(keys, x, y, true, 0.0)
	return _head_deform(p).z


func _geo_head() -> void:
	var skin_m := _skin()
	var hair_m := _hair()
	var keys := _head_keys()
	var ys: Array = []
	var y := 0.0
	while y < 0.214:
		ys.append(y)
		y += 0.0095 if (y > 0.04 and y < 0.17) else 0.014
	ys.append(0.2139)
	var rings: Array = [_r(-0.004, 0.0, 0.0, -0.05)] + _resample(keys, ys) + [_r(0.218, 0.0, 0.0, 0.006)]
	var skin := _c(SKIN_TONE)
	var stub := _c(STUBBLE_TONE * 0.82)
	var hairc := _c(C_HAIR)
	var head_col := func(p: Vector3) -> Color:
		# barba de pocos días: mandíbula, mentón, bigote; patillas hacia el pelo
		var low := clampf((0.088 - p.y) / 0.026, 0.0, 1.0)
		var front := clampf((0.045 - p.z) / 0.035, 0.0, 1.0)
		var k := low * front
		var cheek := clampf((p.y - 0.058) / 0.025, 0.0, 1.0) * clampf((absf(p.x) - 0.03) / 0.015, 0.0, 1.0) \
			* clampf((-p.z - 0.055) / 0.02, 0.0, 1.0)
		k *= 1.0 - 0.6 * cheek
		var burn := clampf((absf(p.x) - 0.058) / 0.012, 0.0, 1.0) * clampf((p.y - 0.06) / 0.04, 0.0, 1.0) \
			* clampf((0.03 - absf(p.z + 0.005)) / 0.02, 0.0, 1.0)
		var base: Color = skin
		# Sombreado de piel por zona (color de vértice): da volumen y vida a la cara
		var fr := clampf((-p.z - 0.03) / 0.05, 0.0, 1.0)          # solo la cara frontal
		var warm := Color(1.06, 0.9, 0.86)
		var cool := Color(0.86, 0.82, 0.86)
		var shade := Color.WHITE
		for sx in [-1.0, 1.0]:
			var ex: float = p.x - sx * 0.034
			var ey: float = p.y - EYE_Y
			# cuenca del ojo y ojera (más oscura/azulada debajo)
			var socket := exp(-(ex * ex / 0.0009 + ey * ey / 0.0005))
			var under := exp(-(ex * ex / 0.0006 + pow(ey + 0.017, 2.0) / 0.00005))
			shade = shade.lerp(shade * cool, clampf(socket * 0.5 + under * 0.6, 0.0, 0.7) * fr)
			# rubor de pómulo
			var cx: float = p.x - sx * 0.05
			var cy: float = p.y - 0.088
			shade = shade.lerp(shade * warm, exp(-(cx * cx / 0.0008 + cy * cy / 0.0006)) * 0.55 * fr)
			# oreja y borde de la oreja más rojizos
			var ear := clampf((absf(p.x) - 0.078) / 0.012, 0.0, 1.0) * clampf(1.0 - absf(p.y - 0.113) / 0.04, 0.0, 1.0)
			shade = shade.lerp(shade * Color(1.1, 0.88, 0.84), ear * 0.6)
		# punta de la nariz y aletas más cálidas
		var nose := exp(-(p.x * p.x / 0.00018 + pow(p.y - 0.088, 2.0) / 0.00012)) * fr
		shade = shade.lerp(shade * Color(1.08, 0.88, 0.84), nose * 0.6)
		# frente un poco más clara y sombra bajo la mandíbula
		var fore := clampf((p.y - 0.155) / 0.03, 0.0, 1.0) * fr
		shade = shade.lerp(shade * Color(1.03, 1.02, 0.98), fore * 0.7)
		var jaw := clampf((0.03 - p.y) / 0.04, 0.0, 1.0)
		shade = shade.lerp(shade * Color(0.78, 0.72, 0.72), jaw * 0.8)
		base = Color(skin.r * shade.r, skin.g * shade.g, skin.b * shade.b)
		var sb := Color(stub.r * shade.r, stub.g * shade.g, stub.b * shade.b)
		var c: Color = base.lerp(sb, clampf(k, 0.0, 1.0) * 0.9)
		return c.lerp(hairc, burn * 0.8)
	_loft(skin_m, rings, 28, Transform3D.IDENTITY, head_col, Callable(), _head_deform)

	# Ojos: esclerótica, iris y línea de pestañas; cejas
	var up_f := Vector3(0, 0, -1)
	for sx in [-1.0, 1.0]:
		var ex: float = 0.032 * sx
		var ez := _head_z(ex, EYE_Y, keys)
		_ellip(skin_m, Vector3(ex, EYE_Y, ez + 0.0035), Vector3(0.0125, 0.0075, 0.006), _c(C_SCLERA), Vector3.ZERO, 10, 5)
		_ellip(skin_m, Vector3(ex - 0.001 * sx, EYE_Y - 0.0005, ez - 0.0018), Vector3(0.0058, 0.0058, 0.002),
			_c(C_IRIS), Vector3.ZERO, 8, 4)
		var lash := PackedVector3Array()
		for i in 4:
			var t := float(i) / 3.0
			var lx: float = ex + sx * lerpf(-0.013, 0.013, t)
			lash.append(Vector3(lx, EYE_Y + 0.0055 + 0.0025 * sin(t * PI), _head_z(lx, EYE_Y + 0.006, keys) - 0.0005))
		_tube(hair_m, lash, 0.0018, 0.0022, 3, up_f, _c(C_EYE))
		# Ceja recta y algo baja hacia el centro (mirada seria)
		var brow := PackedVector3Array()
		var bra: Array = []
		for i in 4:
			var t := float(i) / 3.0
			var bx: float = sx * lerpf(0.014, 0.054, t)
			var by: float = EYE_Y + 0.016 + 0.005 * sin(t * 2.4) - 0.002 * (1.0 - t)
			brow.append(Vector3(bx, by, _head_z(bx, by, keys) - 0.0015))
			bra.append(lerpf(0.0042, 0.0028, t))
		_tube(hair_m, brow, bra, 0.0026, 4, up_f, _c(C_HAIR))
		# Orejas con hélice marcada
		var er := _ring_at(keys, 0.115)
		var eo := Vector3(sx * (float(er["a"]) + 0.004), 0.113, 0.014)
		_ellip(skin_m, eo, Vector3(0.008, 0.029, 0.018), skin, Vector3(0.0, -0.35 * sx, 0.12 * sx), 10, 6)
		_tube(skin_m, PackedVector3Array([eo + Vector3(0.006 * sx, 0.024, -0.006), eo + Vector3(0.009 * sx, 0.02, 0.012),
			eo + Vector3(0.008 * sx, -0.004, 0.018), eo + Vector3(0.006 * sx, -0.022, 0.008)]),
			0.004, 0.004, 5, Vector3(sx, 0, 0), skin)
	# Nariz: puente → punta, aletas
	var nose := PackedVector3Array()
	var nra: Array = []
	var nrb: Array = []
	var nys := [0.148, 0.128, 0.106, 0.092, 0.085]
	var nout := [0.0, 0.005, 0.012, 0.017, 0.014]
	var nw := [0.0058, 0.0064, 0.0075, 0.0095, 0.0075]
	for i in 5:
		nose.append(Vector3(0, nys[i], _head_z(0.0, nys[i], keys) - nout[i] + 0.006))
		nra.append(nw[i])
		nrb.append(0.005 + 0.003 * float(i) / 4.0)
	_tube(skin_m, nose, nra, nrb, 8, up_f, skin)
	for sx in [-1.0, 1.0]:
		var az := _head_z(0.012 * sx, 0.09, keys)
		_ellip(skin_m, Vector3(0.0115 * sx, 0.0895, az - 0.003), Vector3(0.0068, 0.0055, 0.0075), skin,
			Vector3(0, 0.3 * sx, 0), 8, 5)
	# Labios
	var lipc := _c(C_LIP)
	for k in 2:
		var ly := 0.0605 if k == 0 else 0.054
		var lip := PackedVector3Array()
		for i in 5:
			var t := float(i) / 4.0
			var lx := lerpf(-0.022, 0.022, t)
			var bulge := sin(t * PI)
			lip.append(Vector3(lx, ly + (0.001 if k == 0 else -0.0008) * bulge, _head_z(lx, ly, keys) + 0.0018 - 0.002 * bulge))
		_tube(skin_m, lip, 0.0028 if k == 0 else 0.0034, 0.0022 if k == 0 else 0.003, 6, Vector3(0, 1, 0), lipc)

	# Pelo: casquete con línea de pelo inclinada + mechones con volumen
	var hk := [
		_rr(0.128, 0.079, 0.094, 0.104, 0.0, 2.3, 0.0, 0.0, -0.58),
		_rr(0.13, 0.085, 0.1, 0.112, 0.0, 2.3, 0.02, 0.0, -0.55),
		_rr(0.155, 0.087, 0.101, 0.113, 0.002, 2.3, 0.02, 0.0, -0.4),
		_rr(0.18, 0.087, 0.098, 0.112, 0.004, 2.3, 0.025, 0.0, -0.25),
		_rr(0.205, 0.083, 0.093, 0.106, 0.006, 2.3, 0.03, 0.0, -0.12),
		_rr(0.226, 0.07, 0.08, 0.092, 0.006, 2.2, 0.03),
		_rr(0.241, 0.046, 0.054, 0.066, 0.006, 2.0),
		_r(0.246, 0.0, 0.0, 0.006),
	]
	var fade := hairc.lerp(_c(SKIN_TONE * 0.75), 0.3)
	_loft(hair_m, [_r(0.2, 0.0, 0.0)] + hk, 24, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return fade.lerp(hairc, clampf((p.y - 0.13 + 0.25 * p.z) / 0.05, 0.0, 1.0)))
	var up := Vector3(0, 1, 0)
	# Copete: mechones que nacen en la coronilla, suben y caen sobre la línea del pelo
	var jit := [0.004, -0.006, 0.003, -0.002, 0.006, -0.004, 0.002, -0.005]
	for i in 7:
		var t := float(i) / 6.0
		var x0 := lerpf(-0.056, 0.056, t) + float(jit[i])
		var lift := 0.6 - absf(t - 0.4) * 0.9
		var sw := 0.012 * (t - 0.4)
		var p := PackedVector3Array([Vector3(x0 * 0.8, 0.226, 0.05), Vector3(x0 * 0.95, 0.243 + 0.009 * lift, 0.0),
			Vector3(x0 + sw, 0.245 + 0.012 * lift, -0.055), Vector3(x0 * 1.04 + sw * 2.0, 0.222 + 0.008 * lift, -0.095),
			Vector3(x0 * 1.02 + sw * 2.5 + float(jit[7 - i]), 0.2 + 0.006 * lift, -0.104)])
		_tube(hair_m, p, [0.022, 0.026, 0.024, 0.017, 0.007], [0.008, 0.01, 0.01, 0.007, 0.003], 5, up, hairc, true, 2.0)
	# Coronilla hacia la nuca
	for i in 3:
		var x0 := lerpf(-0.04, 0.04, float(i) / 2.0)
		var p := PackedVector3Array([Vector3(x0, 0.236, 0.01), Vector3(x0 * 1.1, 0.225, 0.07),
			Vector3(x0 * 1.15, 0.19, 0.108), Vector3(x0 * 1.1, 0.15, 0.118)])
		_tube(hair_m, p, [0.02, 0.022, 0.018, 0.005], [0.007, 0.009, 0.007, 0.002], 5, Vector3(0, 0.4, 1).normalized(), hairc)


# ---------------------------------------------------------------------
#  Brazos y manos
# ---------------------------------------------------------------------

func _geo_upper_arm(sx: float) -> void:
	var rings := [
		_r(0.034, 0.0, 0.0, 0.0, 2.0, 0.0, -sx * 0.025),
		_r(0.031, 0.03, 0.036, 0.0, 2.0, 0.0, -sx * 0.02),
		_r(0.018, 0.055, 0.06, 0.0, 2.0, 0.0, -sx * 0.01),
		_r(0.0, 0.068, 0.069),
		_r(-0.04, 0.068, 0.067, 0.0, 2.0, 0.008),
		_r(-0.1, 0.064, 0.062, 0.0, 2.0, 0.012),
		_r(-0.17, 0.061, 0.06, 0.0, 2.0, 0.02),
		_r(-0.24, 0.056, 0.055, 0.0, 2.0, 0.04),
		_r(-0.29, 0.056, 0.056, 0.0, 2.0, 0.05),
		_r(-0.315, 0.05, 0.05),
		_r(-0.32, 0.0, 0.0),
	]
	_loft(_rip(), rings, 14, Transform3D.IDENTITY, _c(C_JACKET))
	# Vivo ámbar por el costado exterior
	var pp := PackedVector3Array()
	for yy in [0.0, -0.06, -0.14, -0.21, -0.28]:
		var r := _ring_at(rings.slice(1, 10), yy)
		pp.append(Vector3(sx * (float(r["a"]) + 0.001), yy, 0.0))
	_tube(_rip(), pp, 0.0035, 0.003, 5, Vector3(sx, 0, 0), _c(C_AMBER))
	# Banda reflectiva
	_loft(_glow(), [_r(-0.058, 0.062, 0.06), _r(-0.06, 0.0705, 0.0695), _r(-0.078, 0.0695, 0.0685), _r(-0.08, 0.061, 0.059)],
		16, Transform3D.IDENTITY, Color.WHITE)


func _geo_forearm(_sx: float) -> void:
	var rings := [
		_r(0.05, 0.0, 0.0),
		_r(0.045, 0.04, 0.04),
		_r(0.02, 0.06, 0.06, 0.0, 2.0, 0.03),
		_r(0.0, 0.064, 0.064, 0.0, 2.0, 0.05),
		_r(-0.05, 0.06, 0.058, 0.0, 2.0, 0.035),
		_r(-0.12, 0.054, 0.052, 0.0, 2.0, 0.015),
		_r(-0.185, 0.049, 0.047),
		_r(-0.192, 0.053, 0.05),
		_r(-0.198, 0.054, 0.051),
		_r(-0.238, 0.051, 0.048),
		_r(-0.245, 0.042, 0.04),
		_r(-0.24, 0.0, 0.0),
	]
	var cj := _c(C_JACKET)
	var cd := _c(C_JACKET_DARK)
	_loft(_rip(), rings, 14, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return cd if p.y < -0.189 else cj)


func _geo_hand(sx: float) -> void:
	var rip := _rip()
	var skin_m := _skin()
	var skin := _c(SKIN_TONE)
	var glove := _c(C_GLOVE)
	# Muñeca (piel) y palma con guante sin dedos
	_loft(skin_m, [_r(0.03, 0.0, 0.0), _r(0.028, 0.022, 0.026), _r(-0.012, 0.022, 0.027), _r(-0.014, 0.0, 0.0)],
		10, Transform3D.IDENTITY, skin)
	var palm := [
		_r(0.006, 0.0, 0.0),
		_r(0.004, 0.023, 0.03, 0.0, 2.6),
		_r(-0.008, 0.024, 0.032, 0.0, 2.6),
		_r(-0.035, 0.019, 0.041, -0.002, 3.2),
		_r(-0.07, 0.016, 0.043, -0.002, 3.6),
		_r(-0.094, 0.0145, 0.041, -0.002, 3.6),
		_r(-0.101, 0.009, 0.034, -0.002, 3.0),
		_r(-0.103, 0.0, 0.0, -0.002),
	]
	_loft(rip, palm, 12, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return _c(C_STRAP * 1.6) if p.y > -0.012 else glove)
	# Dedos (curvados hacia la palma, que mira al cuerpo)
	var fz := [-0.03, -0.01, 0.01, 0.029]
	var fl := [0.07, 0.077, 0.071, 0.058]
	var fr := [0.0085, 0.0088, 0.0083, 0.0072]
	for i in 4:
		var L: float = fl[i]
		var z: float = fz[i]
		var p := PackedVector3Array([Vector3(0.0, -0.088, z), Vector3(-sx * 0.003, -0.088 - L * 0.42, z),
			Vector3(-sx * 0.012, -0.088 - L * 0.78, z * 1.05), Vector3(-sx * 0.022, -0.088 - L, z * 1.08)])
		_tube(skin_m, p, fr[i], float(fr[i]) * 0.95, 5, Vector3(0, 0, -1), skin)
	# Pulgar: base con guante, punta de piel
	var t0 := Vector3(-sx * 0.012, -0.018, -0.03)
	var t1 := Vector3(-sx * 0.02, -0.045, -0.046)
	var t2 := Vector3(-sx * 0.026, -0.068, -0.052)
	var t3 := Vector3(-sx * 0.028, -0.082, -0.05)
	_tube(rip, PackedVector3Array([t0, t1, t1.lerp(t2, 0.35)]), [0.012, 0.0115, 0.0105], 0.011, 6, Vector3(sx, 0, 0), glove)
	_tube(skin_m, PackedVector3Array([t1.lerp(t2, 0.2), t2, t3]), [0.0098, 0.0092, 0.008], 0.0088, 6, Vector3(sx, 0, 0), skin)
	# Correa de velcro en la muñeca
	_loft(rip, [_r(0.0, 0.0245, 0.0315, 0.0, 3.0), _r(-0.004, 0.0265, 0.034, 0.0, 3.0), _r(-0.016, 0.026, 0.034, 0.0, 3.0),
		_r(-0.02, 0.023, 0.032, 0.0, 3.0)], 12, Transform3D.IDENTITY, _c(C_STRAP * 2.5))


# ---------------------------------------------------------------------
#  Piernas: cargo con bolsillos y rodilleras, tenis de suela gruesa
# ---------------------------------------------------------------------

static func _thigh_rings() -> Array:
	return [
		_r(0.07, 0.09, 0.095),
		_r(0.0, 0.098, 0.1, 0.004, 2.0, 0.025),
		_r(-0.1, 0.094, 0.094, 0.0, 2.0, 0.02),
		_r(-0.2, 0.086, 0.085, 0.0, 2.0, 0.012),
		_r(-0.3, 0.076, 0.077, 0.0, 2.0, 0.02),
		_r(-0.38, 0.069, 0.071, 0.0, 2.0, 0.035),
		_r(-0.45, 0.064, 0.066, 0.0, 2.0, 0.03),
	]


func _geo_thigh(sx: float) -> void:
	var tw := _twill()
	var keys := _thigh_rings()
	_loft(tw, [_r(0.075, 0.0, 0.0)] + keys + [_r(-0.46, 0.0, 0.0)], 16, Transform3D.IDENTITY, _c(C_PANTS))
	# Bolsillo cargo con fuelle y solapa con broche
	var pr: Array = []
	for yy in [-0.34, -0.335, -0.3, -0.25, -0.21, -0.205]:
		var r := _ring_at(keys, yy)
		var edge: bool = yy < -0.336 or yy > -0.206
		pr.append(_rr(yy, 0.008 if edge else 0.011, 0.05 if edge else 0.056, 0.05 if edge else 0.056, 0.004, 4.0,
			0.0 if edge else 0.03, sx * (float(r["a"]) - 0.003)))
	_loft(tw, [_r(-0.342, 0.0, 0.0, 0.004, 2, 0, float(pr[0]["cx"]))] + pr + [_r(-0.203, 0.0, 0.0, 0.004, 2, 0, float(pr[5]["cx"]))],
		14, Transform3D.IDENTITY, _c(C_PANTS * 1.15))
	var fr: Array = []
	for yy in [-0.228, -0.224, -0.198, -0.194]:
		var r := _ring_at(keys, yy)
		var e2: bool = yy < -0.226 or yy > -0.196
		fr.append(_rr(yy, 0.005 if e2 else 0.008, 0.058 if e2 else 0.061, 0.058 if e2 else 0.061, 0.004, 5.0, 0.0,
			sx * (float(r["a"]) + 0.01)))
	_loft(tw, [_r(-0.23, 0.0, 0.0, 0.004, 2, 0, float(fr[0]["cx"]))] + fr + [_r(-0.192, 0.0, 0.0, 0.004, 2, 0, float(fr[3]["cx"]))],
		14, Transform3D.IDENTITY, _c(C_PANTS * 1.3))
	_ellip(_rip(), Vector3(sx * (float(_ring_at(keys, -0.215)["a"]) + 0.019), -0.215, 0.004), Vector3(0.004, 0.006, 0.006),
		_c(C_ZIP), Vector3.ZERO, 8, 4)
	# Costura exterior (pespunte)
	var seam := PackedVector3Array()
	for yy in [0.03, -0.1, -0.19]:
		var r := _ring_at(keys, yy)
		seam.append(Vector3(sx * (float(r["a"]) + 0.0005), yy, 0.0))
	_tube(tw, seam, 0.0025, 0.002, 4, Vector3(sx, 0, 0), _c(C_PANTS * 1.6))


func _geo_shin(_sx: float) -> void:
	var tw := _twill()
	var rings := [
		_r(0.06, 0.0, 0.0),
		_r(0.055, 0.058, 0.06),
		_r(0.0, 0.068, 0.07, -0.002, 2.0, 0.03),
		_r(-0.08, 0.063, 0.066, 0.006, 2.0, 0.012),
		_r(-0.18, 0.058, 0.062, 0.006, 2.0, 0.01),
		_r(-0.27, 0.055, 0.057, 0.0, 2.0, 0.025),
		_r(-0.305, 0.061, 0.063, 0.0, 2.0, 0.07),
		_r(-0.338, 0.067, 0.069, -0.002, 2.0, 0.08),
		_r(-0.362, 0.066, 0.068, -0.006, 2.0, 0.06),
		_r(-0.372, 0.058, 0.061, -0.006),
		_r(-0.366, 0.046, 0.05, -0.006),
		_r(-0.35, 0.0, 0.0, -0.006),
	]
	_loft(tw, rings, 16, Transform3D.IDENTITY, _c(C_PANTS))
	# Rodillera articulada (sintética), cubre el frente de la rodilla
	var pad := [
		_r(0.062, 0.0, 0.0, -0.052),
		_rr(0.058, 0.03, 0.006, 0.006, -0.056, 3.0),
		_rr(0.038, 0.044, 0.008, 0.008, -0.066, 3.2),
		_rr(0.005, 0.049, 0.009, 0.009, -0.071, 3.2),
		_rr(-0.03, 0.048, 0.009, 0.009, -0.07, 3.2),
		_rr(-0.06, 0.04, 0.008, 0.008, -0.064, 3.2),
		_rr(-0.075, 0.028, 0.006, 0.006, -0.06, 3.0),
		_r(-0.078, 0.0, 0.0, -0.059),
	]
	_loft(_rip(), pad, 14, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return _c(C_KNEEPAD * 0.7) if absf(p.y + 0.012) < 0.006 else _c(C_KNEEPAD))


func _geo_foot(sx: float) -> void:
	# El loft corre a lo largo del pie (+y del loft = hacia la punta, -Z del pivote).
	var xf := Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3.ZERO)
	# [avance, semiancho, alto inferior, alto superior]
	var prof := [
		[-0.086, 0.03, -0.071, 0.015],
		[-0.072, 0.044, -0.073, 0.045],
		[-0.04, 0.048, -0.073, 0.052],
		[0.0, 0.05, -0.073, 0.048],
		[0.04, 0.053, -0.073, 0.022],
		[0.09, 0.055, -0.073, -0.005],
		[0.14, 0.053, -0.071, -0.024],
		[0.178, 0.045, -0.069, -0.038],
		[0.198, 0.032, -0.067, -0.048],
	]
	var rings: Array = [_r(-0.09, 0.0, 0.0, -0.03)]
	for q in prof:
		var bot: float = q[2]
		var top: float = q[3]
		# frente del anillo (-z local del loft) = abajo tras rotar
		rings.append(_rr(q[0], q[1], (top - bot) * 0.5, (top - bot) * 0.5, (top + bot) * 0.5, 2.6))
	rings.append(_r(0.206, 0.0, 0.0, -0.058))
	var cs := _c(C_SHOE)
	var green := _c(C_SCARF_GREEN)
	var shoe_col := func(p: Vector3) -> Color:
		# talón verde (guiño a Antioquia)
		if p.z > 0.076 and p.y > -0.03 and absf(p.x) < 0.03:
			return green
		return cs
	var shoe_uv := func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25 + (0.5 if p.x * sx > 0.0 else 0.0), clampf((0.052 - p.y) / 0.125, 0.0, 1.0) * 0.64)
	_loft(_shoe(), rings, 16, xf, shoe_col, shoe_uv)
	# Suela gruesa: entresuela + suela de goma con perfil (escalón) y puntera levantada
	var sole_rings := func(bot: float, top: float, grow: float, inset: float) -> Array:
		var out: Array = [_r(-0.094 + inset, 0.0, 0.0, 0.5 * (bot + top))]
		for q in [[-0.09, 0.034], [-0.075, 0.05], [-0.04, 0.054], [0.03, 0.057], [0.1, 0.061], [0.16, 0.057],
				[0.195, 0.044], [0.212, 0.026]]:
			var f: float = q[0]
			var lift := 0.012 * pow(clampf((f - 0.12) / 0.09, 0.0, 1.0), 2.0) + 0.004 * clampf((-0.06 - f) / 0.03, 0.0, 1.0)
			out.append(_rr(f, float(q[1]) + grow - inset, (top - bot) * 0.5, (top - bot) * 0.5, (top + bot) * 0.5 + lift, 5.0))
		out.append(_r(0.217 - inset, 0.0, 0.0, 0.5 * (bot + top) + 0.012))
		return out
	_loft(_sole(), sole_rings.call(-0.09, -0.064, 0.006, 0.0), 14, xf, _c(C_SOLE), func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25, clampf((-0.064 - p.y) / 0.026, 0.0, 1.0)))
	_loft(_sole(), sole_rings.call(-0.1, -0.088, 0.004, 0.003), 12, xf, _c(C_GUM), func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25, 0.4 + clampf((-0.088 - p.y) / 0.012, 0.0, 1.0) * 0.6))
	# Lengüeta y cordones (sobre el empeine, delante del bajo del pantalón)
	var top_at := func(f: float) -> float:
		for i in prof.size() - 1:
			var a: Array = prof[i]
			var b: Array = prof[i + 1]
			if f <= float(b[0]):
				return lerpf(float(a[3]), float(b[3]), (f - float(a[0])) / (float(b[0]) - float(a[0])))
		return -0.048
	_tube(_shoe(), PackedVector3Array([Vector3(0, top_at.call(0.05) + 0.004, -0.05), Vector3(0, top_at.call(0.09) + 0.002, -0.09),
		Vector3(0, top_at.call(0.125), -0.125)]), 0.021, 0.004, 6, Vector3(0, 1, 0), cs)
	var cl := _c(C_LACE)
	for i in 4:
		var f := 0.06 + 0.022 * float(i)
		var top: float = top_at.call(f) + 0.005
		_tube(_shoe(), PackedVector3Array([Vector3(-0.026, top - 0.007, -f + 0.004), Vector3(0, top + 0.001, -f),
			Vector3(0.026, top - 0.007, -f - 0.004)]), 0.005, 0.0022, 5, Vector3(0, 1, 0.3), cl)
# =====================================================================
#  ANIMACIÓN PROCEDURAL
# =====================================================================

## state: idle | walk | run | sprint | jump | fall | land | stumble | enter_vehicle | exit_vehicle |
##        crouch | crouch_walk | punch | push
## speed: velocidad horizontal real (m/s). delta: paso de tiempo.
func animate(state: String, speed: float, delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	_time += delta
	if state != _state:
		_on_state_change(_state, state)
		_state = state

	# Aceleración longitudinal y velocidad de giro filtradas (dan peso al cuerpo)
	var acc := (speed - _prev_speed) / delta
	_prev_speed = speed
	_accel_f = lerpf(_accel_f, clampf(acc, -14.0, 14.0), 1.0 - exp(-5.0 * delta))
	var yaw := global_rotation.y
	var dyaw := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	_turn_f = lerpf(_turn_f, clampf(dyaw, -8.0, 8.0), 1.0 - exp(-7.0 * delta))
	_land_t = maxf(0.0, _land_t - delta * 3.2)

	var t := {}
	for k in _joints:
		t[k] = Vector3.ZERO
	var rate := 14.0
	var plant := true             # ajustar cadera para que los pies pisen el suelo
	var plant_w := 1.0
	var root_rot := Vector3.ZERO
	var root_pos := Vector3.ZERO
	var hips_extra := 0.0

	match state:
		"jump", "fall":
			_air_t += delta
			rate = 7.0
			plant = false
			_pose_air(t, state == "jump", speed)
		"stumble":
			_stumble_t += delta
			rate = 10.0
			plant = false
			var r := _pose_stumble(t)
			root_rot = r[0]
			root_pos = r[1]
			hips_extra = r[2]
			plant_w = r[3]
		"enter_vehicle":
			_enter_t += delta
			rate = 9.0
			_pose_locomotion(t, 0.0, delta)
			_pose_enter(t, _enter_t)
		"exit_vehicle":
			_exit_t += delta
			rate = 11.0
			_pose_locomotion(t, 0.0, delta)
			_pose_enter(t, maxf(0.0, 0.5 - _exit_t * 1.4))
		_:
			_air_t = 0.0
			_pose_locomotion(t, speed, delta)
			# Inclinación hacia la curva (todo el cuerpo pivota en los pies)
			var roll := clampf(_turn_f * speed * 0.03, -0.32, 0.32)
			root_rot.z = roll
			var crouching := state == "crouch" or state == "crouch_walk"
			_crouch_w = lerpf(_crouch_w, 1.0 if crouching else 0.0, 1.0 - exp(-10.0 * delta))
			_push_w = lerpf(_push_w, 1.0 if state == "push" else 0.0, 1.0 - exp(-12.0 * delta))
			if _crouch_w > 0.01:
				_add_crouch(t, _crouch_w)
			if _push_w > 0.01:
				_add_push(t, _push_w)
			if state == "punch":
				rate = 22.0
				var pr := _pose_punch(t)
				root_pos += pr
	if _land_t > 0.0 and state != "stumble":
		_add_land(t, _land_t)

	# Aplicar con suavizado exponencial (inercia visual)
	var k := 1.0 - exp(-rate * delta)
	for jn in _joints:
		var node: Node3D = _joints[jn]
		if jn == "root":
			continue
		node.rotation = node.rotation.lerp(t[jn], k)
	root.rotation = root.rotation.lerp(root_rot, 1.0 - exp(-(rate * 0.8) * delta))
	root.position = root.position.lerp(root_pos, k)

	# Cadera: plantar el pie más bajo en el suelo (cinemática directa 2D)
	var target_y := hips_extra
	var dl := _leg_drop(thigh_l, shin_l)
	var dr := _leg_drop(thigh_r, shin_r)
	if plant:
		target_y += -minf(dl, dr) + _run_bob()
	elif state == "stumble":
		target_y += -minf(dl, dr) * plant_w
	_hips_y = lerpf(_hips_y, target_y, 1.0 - exp(-20.0 * delta))
	hips.position.y = HIPS_HEIGHT + _hips_y


func _on_state_change(prev: String, next: String) -> void:
	if next == "land" or ((prev == "fall" or prev == "jump") and next != "stumble"):
		_land_t = clampf(0.6 + _air_t * 0.8, 0.6, 1.0)
	if next == "stumble":
		_stumble_t = 0.0
	if next == "enter_vehicle":
		_enter_t = 0.0
	if next == "exit_vehicle":
		_exit_t = 0.0
	if next == "jump":
		_air_t = 0.0


## Cuánto baja el tobillo respecto a la pierna estirada (m), por cadera + rodilla.
func _leg_drop(th: Node3D, sh: Node3D) -> float:
	var a := th.rotation.x + hips.rotation.x
	var b := a + sh.rotation.x
	var vert := THIGH_LEN * cos(a) + SHIN_LEN * cos(b)
	return (THIGH_LEN + SHIN_LEN) - vert


func _run_bob() -> float:
	# Al correr hay fase de vuelo: el cuerpo sube cuando las piernas se abren
	return _move_w * _gait_g * (0.035 + 0.02 * _gait_s) * (-cos(2.0 * _phase))


func _pose_locomotion(t: Dictionary, speed: float, delta: float) -> void:
	var g_t := clampf((speed - 1.6) / 2.9, 0.0, 1.0)     # caminar → correr
	var s_t := clampf((speed - 4.5) / 2.5, 0.0, 1.0)     # correr → sprint
	var m_t := clampf(speed / 0.9, 0.0, 1.0)
	var kf := 1.0 - exp(-6.0 * delta)
	_gait_g = lerpf(_gait_g, g_t, kf)
	_gait_s = lerpf(_gait_s, s_t, kf)
	_move_w = lerpf(_move_w, m_t, 1.0 - exp(-8.0 * delta))
	var g := _gait_g
	var s := _gait_s
	var m := _move_w

	# Fase basada en la distancia recorrida (los pies no "patinan")
	var stride := lerpf(lerpf(1.4, 2.7, g), 3.7, s)      # metros por ciclo (2 pasos)
	_phase = fmod(_phase + speed * delta / stride * TAU, TAU)
	var pl := _phase
	var pr := _phase + PI

	# ---------- Reposo (respiración, peso en una pierna) ----------
	var breath := sin(_time * 1.55)
	var idle := 1.0 - m
	var accel_lean := clampf(_accel_f * 0.03, -0.3, 0.3)   # + acelera, - frena

	# ---------- Piernas ----------
	for side in [-1, 1]:
		var sfx := "l" if side < 0 else "r"
		var p: float = pl if side < 0 else pr
		var amp_t := lerpf(lerpf(0.36, 0.55, g), 0.72, s)
		var thigh := sin(p) * amp_t + lerpf(0.03, 0.28, g) + 0.08 * s
		# Balanceo: la rodilla se flexiona sobre todo al inicio (talón hacia el glúteo al correr)
		var swing := maxf(0.0, cos(p + lerpf(0.25, 0.6, g)))
		var knee_sw := lerpf(lerpf(0.8, 1.6, g), 2.0, s)
		var knee_st := lerpf(0.06, 0.3, g) * (0.5 + 0.5 * maxf(0.0, -cos(p)))
		var knee := -(knee_st + knee_sw * pow(swing, 1.3)) - 0.3 * g * maxf(0.0, sin(p))
		var foot_world := -0.32 * maxf(0.0, -sin(p)) * maxf(0.0, cos(p) + 0.3) + 0.12 * maxf(0.0, sin(p)) * (1.0 - g)
		var foot := foot_world - thigh - knee
		# reposo: pierna derecha relajada (peso en la izquierda)
		var it := 0.06 if side > 0 else -0.02
		var ik := -0.12 if side > 0 else -0.03
		t["thigh_" + sfx] = Vector3(thigh * m + it * idle, 0.0, 0.03 * side * idle - 0.02 * side * m)
		t["shin_" + sfx] = Vector3(knee * m + ik * idle, 0.0, 0.0)
		t["foot_" + sfx] = Vector3(foot * m - (it + ik) * idle, 0.0, -0.03 * side * idle)

	# ---------- Tronco ----------
	var lean := m * (0.03 + 0.12 * g + 0.16 * s) + accel_lean * (0.4 + 0.6 * m)
	var twist := m * lerpf(0.09, 0.16, g)
	t["hips"] = Vector3(-lean * 0.25, -twist * sin(pl), 0.045 * sin(pl) * m * (1.0 - g) + 0.03 * idle)
	t["spine"] = Vector3(-lean * 0.4 + 0.015 * breath * idle, twist * 0.6 * sin(pl), -0.02 * idle)
	t["chest"] = Vector3(-lean * 0.35 - 0.018 * breath * idle, twist * 0.75 * sin(pl), -0.01 * idle)
	t["neck"] = Vector3(lean * 0.35, -twist * 0.2 * sin(pl), 0.0)
	var look := sin(_time * 0.21) * 0.18 + sin(_time * 0.53) * 0.05
	t["head"] = Vector3(lean * 0.35 + 0.02 * breath * idle, look * idle - twist * 0.15 * sin(pl), -0.03 * idle)
	# Movimiento secundario (acción superpuesta): cabeza y hombros reaccionan con retraso
	# a la aceleración y al giro; la cabeza se estabiliza contra el balanceo del torso.
	var head_lag := clampf(-_accel_f * 0.012, -0.12, 0.12)
	var turn_lead := clampf(_turn_f * 0.07, -0.25, 0.25)
	t["neck"] += Vector3(head_lag * 0.5, turn_lead * 0.4, -turn_lead * 0.15)
	t["head"] += Vector3(head_lag * 0.6 - 0.02 * m * sin(2.0 * pl + 0.6), turn_lead * 0.6, -turn_lead * 0.2 \
		+ 0.035 * m * sin(pl) * (1.0 - 0.5 * g))
	t["chest"] += Vector3(0.012 * m * (1.0 + g) * sin(2.0 * pl + 0.4) + 0.012 * breath * m, 0.0,
		-0.035 * m * sin(pl) + turn_lead * 0.12)
	t["spine"] += Vector3(0.0, 0.0, 0.02 * m * sin(pl))

	# ---------- Brazos (contrapeso a las piernas) ----------
	for side in [-1, 1]:
		var sfx := "l" if side < 0 else "r"
		var p: float = pl if side < 0 else pr
		var amp_a := lerpf(lerpf(0.32, 0.85, g), 1.15, s)
		var arm := -sin(p) * amp_a + 0.08 * g + 0.05 * s - accel_lean * 0.6
		var elbow := lerpf(lerpf(0.22, 1.6, g), 1.75, s) + 0.22 * maxf(0.0, -sin(p)) * m
		var out := 0.07 + 0.08 * g * m + 0.03 * breath * idle
		t["upper_arm_" + sfx] = Vector3(arm * m + 0.04 * idle, 0.0, side * out)
		t["forearm_" + sfx] = Vector3(elbow * m + 0.14 * idle, 0.0, 0.0)
		t["hand_" + sfx] = Vector3(0.1 + 0.25 * g * m, -side * 0.15, 0.0)


func _add_land(t: Dictionary, l: float) -> void:
	# Absorción del aterrizaje: rodillas, cadera baja, tronco hacia adelante
	var e := l * l * (3.0 - 2.0 * l)
	for sfx in ["l", "r"]:
		t["thigh_" + sfx] += Vector3(0.55 * e, 0, 0)
		t["shin_" + sfx] += Vector3(-1.05 * e, 0, 0)
		t["foot_" + sfx] += Vector3(0.5 * e, 0, 0)
		t["upper_arm_" + sfx] += Vector3(0.25 * e, 0, 0)
		t["forearm_" + sfx] += Vector3(0.4 * e, 0, 0)
	t["spine"] += Vector3(-0.22 * e, 0, 0)
	t["chest"] += Vector3(-0.12 * e, 0, 0)
	t["head"] += Vector3(0.2 * e, 0, 0)


func _pose_air(t: Dictionary, rising: bool, speed: float) -> void:
	var g := clampf(speed / 5.0, 0.0, 1.0)
	if rising:
		# Despegue: pierna de impulso recogida, brazos arriba
		t["thigh_l"] = Vector3(0.75 + 0.2 * g, 0, -0.03)
		t["shin_l"] = Vector3(-1.1, 0, 0)
		t["foot_l"] = Vector3(0.2, 0, 0)
		t["thigh_r"] = Vector3(-0.05 - 0.25 * g, 0, 0.03)
		t["shin_r"] = Vector3(-0.55, 0, 0)
		t["foot_r"] = Vector3(-0.35, 0, 0)
		t["upper_arm_l"] = Vector3(-0.5 * g + 0.3, 0, -0.35)
		t["upper_arm_r"] = Vector3(0.9, 0, 0.3)
		t["forearm_l"] = Vector3(0.7, 0, 0)
		t["forearm_r"] = Vector3(0.9, 0, 0)
		t["spine"] = Vector3(-0.1 - 0.1 * g, 0, 0)
		t["head"] = Vector3(0.1, 0, 0)
	else:
		# Caída: piernas buscando el suelo, brazos abiertos para equilibrio
		var w := sin(_time * 7.0) * 0.12
		t["thigh_l"] = Vector3(0.45, 0, -0.06)
		t["shin_l"] = Vector3(-0.7, 0, 0)
		t["foot_l"] = Vector3(0.15, 0, 0)
		t["thigh_r"] = Vector3(0.1, 0, 0.06)
		t["shin_r"] = Vector3(-0.45, 0, 0)
		t["foot_r"] = Vector3(0.1, 0, 0)
		t["upper_arm_l"] = Vector3(0.35 + w, 0, -0.75)
		t["upper_arm_r"] = Vector3(0.25 - w, 0, 0.8)
		t["forearm_l"] = Vector3(0.5, 0, 0)
		t["forearm_r"] = Vector3(0.6, 0, 0)
		t["spine"] = Vector3(-0.08, 0, 0)
		t["head"] = Vector3(0.12, 0, 0)


## Atropello: cae de espaldas, queda en el suelo, se incorpora a cuclillas y se
## levanta (≈1.7 s). Devuelve [rotación de root, posición de root, ajuste de cadera,
## peso de apoyo de pies].
func _pose_stumble(t: Dictionary) -> Array:
	var st := _stumble_t
	var fall := smoothstep(0.0, 0.42, st)
	var sit_up := smoothstep(0.85, 1.3, st)           # el tronco vuelve a vertical
	var crouch := smoothstep(0.8, 1.2, st) * (1.0 - smoothstep(1.3, 1.75, st))
	var down := fall * (1.0 - sit_up)
	var flail := sin(clampf(st / 0.5, 0.0, 1.0) * PI)
	var root_rot := Vector3(1.42 * down, 0.0, 0.25 * flail * (1.0 - sit_up))
	var root_pos := Vector3(0.0, 0.06 * down, 0.0)
	# Brazos: agitan al caer; en cuclillas se apoyan sobre las rodillas
	t["upper_arm_l"] = Vector3(1.6 * flail + 0.2 * down + 0.55 * crouch, 0, -0.5 * flail - 0.25 * down - 0.1 * crouch)
	t["upper_arm_r"] = Vector3(1.2 * flail + 0.3 * down + 0.45 * crouch, 0, 0.65 * flail + 0.3 * down + 0.1 * crouch)
	t["forearm_l"] = Vector3(0.9 * flail + 0.3 * down + 0.5 * crouch, 0, 0)
	t["forearm_r"] = Vector3(0.5 * flail + 0.4 * down + 0.6 * crouch, 0, 0)
	# Piernas: una se levanta con el golpe; luego cuclillas
	t["thigh_l"] = Vector3(0.7 * flail + 0.1 * down + 1.65 * crouch, 0, -0.08 * down - 0.08 * crouch)
	t["thigh_r"] = Vector3(0.25 * flail + 0.35 * down + 1.45 * crouch, 0, 0.12 * down + 0.08 * crouch)
	t["shin_l"] = Vector3(-0.6 * flail - 0.1 * down - 2.2 * crouch, 0, 0)
	t["shin_r"] = Vector3(-0.3 * flail - 0.6 * down - 1.95 * crouch, 0, 0)
	t["foot_l"] = Vector3(0.3 * down + 0.55 * crouch, 0, 0)
	t["foot_r"] = Vector3(0.3 * down + 0.5 * crouch, 0, 0)
	t["hips"] = Vector3(-0.25 * crouch, 0, 0)
	t["spine"] = Vector3(-0.35 * flail - 0.45 * crouch, 0, 0.1 * flail)
	t["chest"] = Vector3(-0.25 * crouch + 0.1 * down, 0, 0)
	t["neck"] = Vector3(0.25 * crouch, 0, 0)
	t["head"] = Vector3(-0.35 * down + 0.25 * crouch - 0.2 * flail, 0.3 * down, 0)
	return [root_rot, root_pos, 0.0, sit_up]


func _pose_enter(t: Dictionary, time: float) -> void:
	# Abre la puerta y se agacha para meterse al auto (≈0.6 s); al bajar se usa en reversa
	var e := smoothstep(0.0, 0.4, time)
	t["upper_arm_l"] = Vector3(1.25 * e, 0, -0.2 * e)
	t["forearm_l"] = Vector3(0.35 * e, 0, 0)
	t["upper_arm_r"] = Vector3(0.5 * e, 0, 0.25 * e)
	t["forearm_r"] = Vector3(0.6 * e, 0, 0)
	t["thigh_r"] = Vector3(0.75 * e, 0, 0)
	t["shin_r"] = Vector3(-1.0 * e, 0, 0)
	t["thigh_l"] = Vector3(0.1 * e, 0, 0)
	t["shin_l"] = Vector3(-0.35 * e, 0, 0)
	t["spine"] = Vector3(-0.35 * e, -0.2 * e, 0)
	t["chest"] = Vector3(-0.15 * e, 0, 0)
	t["head"] = Vector3(0.25 * e, 0, 0)


## Agachado (rodillas y cadera flexionadas, tronco inclinado): se suma a la pose de locomoción.
func _add_crouch(t: Dictionary, c: float) -> void:
	var e := c * c * (3.0 - 2.0 * c)
	for sfx in ["l", "r"]:
		t["thigh_" + sfx] += Vector3(0.95 * e, 0, 0)
		t["shin_" + sfx] += Vector3(-1.75 * e, 0, 0)
		t["foot_" + sfx] += Vector3(0.8 * e, 0, 0)
		t["upper_arm_" + sfx] += Vector3(0.3 * e, 0, 0)
		t["forearm_" + sfx] += Vector3(0.45 * e, 0, 0)
	t["hips"] += Vector3(-0.1 * e, 0, 0)
	t["spine"] += Vector3(-0.22 * e, 0, 0)
	t["chest"] += Vector3(-0.1 * e, 0, 0)
	t["neck"] += Vector3(0.12 * e, 0, 0)
	t["head"] += Vector3(0.2 * e, 0, 0)


## Empujar un objeto: brazos estirados al frente, cuerpo inclinado, hombros cargados.
func _add_push(t: Dictionary, w: float) -> void:
	var e := w * w * (3.0 - 2.0 * w)
	for side in [-1, 1]:
		var sfx := "l" if side < 0 else "r"
		t["upper_arm_" + sfx] = (t["upper_arm_" + sfx] as Vector3).lerp(Vector3(1.4, 0.0, side * 0.12), e)
		t["forearm_" + sfx] = (t["forearm_" + sfx] as Vector3).lerp(Vector3(0.18, 0.0, 0.0), e)
		t["hand_" + sfx] = (t["hand_" + sfx] as Vector3).lerp(Vector3(0.3, 0.0, 0.0), e)
	t["hips"] += Vector3(-0.16 * e, 0, 0)
	t["spine"] += Vector3(-0.24 * e, 0, 0)
	t["chest"] += Vector3(-0.1 * e, 0, 0)
	t["head"] += Vector3(0.28 * e, 0, 0)


## Golpe del combo: 0 jab izquierdo, 1 cruzado derecho, 2 patada frontal. Pone los brazos/piernas
## directamente (guardia + extensión) y devuelve el desplazamiento de root (estocada).
func _pose_punch(t: Dictionary) -> Vector3:
	var dur: float = [0.34, 0.38, 0.5][punch_idx]
	var p := clampf(punch_t / dur, 0.0, 1.0)
	var ext := smoothstep(0.08, 0.34, p) * (1.0 - smoothstep(0.5, 0.92, p))
	# postura de guardia (escalonada, rodillas flexionadas)
	t["thigh_l"] = Vector3(0.32, 0.0, -0.05)
	t["shin_l"] = Vector3(-0.55, 0.0, 0.0)
	t["foot_l"] = Vector3(0.23, 0.0, 0.0)
	t["thigh_r"] = Vector3(-0.22, 0.0, 0.05)
	t["shin_r"] = Vector3(-0.5, 0.0, 0.0)
	t["foot_r"] = Vector3(0.0, 0.0, 0.0)
	t["upper_arm_l"] = Vector3(0.85, 0.0, -0.18)
	t["forearm_l"] = Vector3(1.55, 0.0, 0.0)
	t["upper_arm_r"] = Vector3(0.95, 0.0, 0.2)
	t["forearm_r"] = Vector3(1.6, 0.0, 0.0)
	t["hand_l"] = Vector3(0.2, 0.0, 0.0)
	t["hand_r"] = Vector3(0.2, 0.0, 0.0)
	t["hips"] = Vector3(-0.1, 0.0, 0.0)
	t["spine"] = Vector3(-0.14, 0.0, 0.0)
	t["chest"] = Vector3(-0.08, 0.0, 0.0)
	t["head"] = Vector3(0.18, 0.0, 0.0)
	var lunge := 0.0
	match punch_idx:
		0:   # jab izquierdo: brazo recto a la altura del hombro, el torso gira un poco
			t["upper_arm_l"] = Vector3(0.85 + 0.65 * ext, 0.0, -0.18 + 0.1 * ext)
			t["forearm_l"] = Vector3(1.55 - 1.45 * ext, 0.0, 0.0)
			t["hand_l"] = Vector3(0.2 - 0.2 * ext, 0.0, 0.0)
			t["spine"] += Vector3(0.0, 0.3 * ext, 0.0)
			t["chest"] += Vector3(0.0, 0.2 * ext, 0.0)
			t["hips"] += Vector3(0.0, 0.1 * ext, 0.0)
			lunge = 0.1 * ext
		1:   # cruzado derecho: más giro de cadera y hombro
			t["upper_arm_r"] = Vector3(0.95 + 0.6 * ext, -0.1 * ext, 0.2 - 0.12 * ext)
			t["forearm_r"] = Vector3(1.6 - 1.5 * ext, 0.0, 0.0)
			t["hand_r"] = Vector3(0.2 - 0.2 * ext, 0.0, 0.0)
			t["spine"] += Vector3(-0.06 * ext, -0.5 * ext, 0.0)
			t["chest"] += Vector3(0.0, -0.3 * ext, 0.0)
			t["hips"] += Vector3(0.0, -0.3 * ext, 0.0)
			t["thigh_r"] += Vector3(0.12 * ext, 0.0, 0.0)
			lunge = 0.16 * ext
		_:   # patada frontal con la pierna derecha
			t["thigh_r"] = Vector3(-0.22 + 1.75 * ext, 0.0, 0.05)
			t["shin_r"] = Vector3(-0.5 + 0.35 * ext, 0.0, 0.0)
			t["foot_r"] = Vector3(0.0 + 0.5 * ext, 0.0, 0.0)
			t["thigh_l"] = Vector3(0.32 - 0.15 * ext, 0.0, -0.05)
			t["shin_l"] = Vector3(-0.55 - 0.25 * ext, 0.0, 0.0)
			t["upper_arm_l"] += Vector3(0.0, 0.0, -0.5 * ext)
			t["upper_arm_r"] += Vector3(-0.5 * ext, 0.0, 0.3 * ext)
			t["spine"] += Vector3(0.25 * ext, 0.0, 0.0)
			t["hips"] += Vector3(0.1 * ext, 0.0, 0.0)
			lunge = 0.08 * ext
	return Vector3(0.0, 0.0, -lunge)


## Fuerza una pose instantánea (útil al reaparecer o para retratos).
func snap_pose(state: String, speed: float, phase := 0.0) -> void:
	_phase = phase
	_gait_g = clampf((speed - 1.6) / 2.9, 0.0, 1.0)
	_gait_s = clampf((speed - 4.5) / 2.5, 0.0, 1.0)
	_move_w = clampf(speed / 0.9, 0.0, 1.0)
	_prev_speed = speed
	for i in 40:
		_phase = phase - speed * (1.0 / 60.0) / maxf(0.01, lerpf(lerpf(1.4, 2.7, _gait_g), 3.7, _gait_s)) * TAU
		animate(state, speed, 1.0 / 60.0)

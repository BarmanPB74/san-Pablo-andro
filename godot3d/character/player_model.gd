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
static var C_HAIR := Color(0.045, 0.035, 0.03)
const C_EYE := Color(0.03, 0.02, 0.015)
const C_IRIS := Color(0.16, 0.09, 0.05)
const C_SCLERA := Color(0.78, 0.74, 0.68)
static var C_LIP := Color(0.52, 0.32, 0.27)
static var SKIN_TONE := Color(0.76, 0.62, 0.52)  # piel clara, algo pálida (en plastilina: beige mate)
# Modo plastilina (ClayStyle.enabled): cabeza y manos grandes, ojos saltones, bufanda tejida a rayas.
const CLAY_HEAD_K := 1.6
const CLAY_HAND_K := 1.28
# Paleta de plastilina = la del adaptador "arcilla gótica" (character/gothic_clay_adapter.gd)
const C_CLAY_SKIN := Color(0.64, 0.62, 0.59)   # arcilla pálida "blanco sucio/hueso" (lámina)
const C_CLAY_EYE := GothicClayAdapter.EYE
# Traje oscuro + camisa blanca (concepto de Pablo: figura alta y delgada)
static var C_SUIT := Color(0.06, 0.06, 0.068)
static var C_SUIT_LAPEL := Color(0.035, 0.035, 0.042)
static var C_SHIRT := Color(0.86, 0.86, 0.83)
static var C_TROUSER := Color(0.06, 0.06, 0.068)
static var C_BUTTON := Color(0.03, 0.03, 0.035)
static var C_VEST := Color(0.86, 0.86, 0.83)     # chaleco café que asoma en la abertura del abrigo (F8)
const SATCHEL_ON := false      # F8: el video 68105 no lleva bandolera (true la devuelve)
static var C_DRESS_SHOE := Color(0.035, 0.035, 0.04)
const BEARD_ON := false         # barba (cáscara de pelo); el concepto actual va afeitado
const ARM_K := 1.1              # brazos 10 % más largos
const STUBBLE_TONE := Color(0.4, 0.29, 0.23)    # barba de pocos días

# Longitudes de los segmentos (m)
const THIGH_LEN := 0.46
const SHIN_LEN := 0.41
const HIPS_HEIGHT := 1.01
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
var _mouth := 1                    # boca activa (1..5)
var _hair_variant := 0
var _scarf_variant := 0
var _scarf_chain: Array = []        # [cola a (segmentos), cola b]
var _pieces: Dictionary = {}       # piezas animables de la cara (eye_l, lid_l, brow_l…): nombre → Node3D
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
	var clay := ClayStyle.enabled
	SKIN_TONE = C_CLAY_SKIN if clay else Color(0.76, 0.62, 0.52)
	# Arcilla gótica (láminas de referencia de Pablo): saco ciruela-carbón CERRADO (sin camisa a la vista),
	# pantalón más oscuro, pelo café-ciruela en mechones gruesos, zapatos gris-café, labios apagados.
	# F8 (video 68105): abrigo gris carbón neutro (algo amarillo en albedo para compensar la luz morada), chaleco café oscuro, botones negros, pantalón casi negro
	C_SUIT = Color(0.30, 0.30, 0.245) if clay else Color(0.06, 0.06, 0.068)
	C_SUIT_LAPEL = Color(0.225, 0.225, 0.185) if clay else Color(0.035, 0.035, 0.042)
	C_TROUSER = Color(0.2, 0.2, 0.16) if clay else Color(0.06, 0.06, 0.068)
	C_SHIRT = C_SUIT if clay else Color(0.86, 0.86, 0.83)
	C_VEST = Color(0.34, 0.31, 0.2) if clay else C_SHIRT
	C_BUTTON = Color(0.11, 0.11, 0.11) if clay else Color(0.03, 0.03, 0.035)   # botones negros pequeños
	C_HAIR = Color(0.27, 0.25, 0.25) if clay else Color(0.045, 0.035, 0.03)
	C_DRESS_SHOE = Color(0.3, 0.22, 0.17) if clay else Color(0.035, 0.035, 0.04)  # botines de cuero café
	C_LIP = Color(0.42, 0.2, 0.2) if clay else Color(0.52, 0.32, 0.27)          # rojo apagado (labio inferior)
	root = _pivot("root", self, Vector3.ZERO)
	hips = _pivot("hips", root, Vector3(0, HIPS_HEIGHT, 0))
	spine = _pivot("spine", hips, Vector3(0, 0.1, 0))
	chest = _pivot("chest", spine, Vector3(0, 0.2, 0))
	neck = _pivot("neck", chest, Vector3(0, 0.24, 0.005))
	head = _pivot("head", neck, Vector3(0, 0.09, -0.005))
	for side in [-1, 1]:
		var sx := float(side)
		var sfx := "l" if side < 0 else "r"
		var ua := _pivot("upper_arm_" + sfx, chest, Vector3(0.19 * sx, 0.175, 0.0))
		var fa := _pivot("forearm_" + sfx, ua, Vector3(0, -0.29 * ARM_K, 0))
		var hd := _pivot("hand_" + sfx, fa, Vector3(0, -0.25 * ARM_K, 0))
		var th := _pivot("thigh_" + sfx, hips, Vector3(0.082 * sx, -0.04, 0.0))
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
	if clay:
		_build_face_pieces()
	for side in [-1, 1]:
		var sfx := "l" if side < 0 else "r"
		_dress(_joints["upper_arm_" + sfx], "upper_arm_" + sfx, _geo_upper_arm.bind(float(side)))
		_dress(_joints["forearm_" + sfx], "forearm_" + sfx, _geo_forearm.bind(float(side)))
		_dress(_joints["hand_" + sfx], "hand_" + sfx, _geo_hand.bind(float(side)))
		_dress(_joints["thigh_" + sfx], "thigh_" + sfx, _geo_thigh.bind(float(side)))
		_dress(_joints["shin_" + sfx], "shin_" + sfx, _geo_shin.bind(float(side)))
		_dress(_joints["foot_" + sfx], "foot_" + sfx, _geo_foot.bind(float(side)))
	_prev_yaw = global_rotation.y if is_inside_tree() else 0.0
	if clay:
		var ad := GothicClayAdapter.new()
		ad.name = "GothicClayAdapter"
		add_child(ad)


func _pivot(pname: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	parent.add_child(n)
	_joints[pname] = n
	return n


## Construye (o recupera de la caché) la malla de un builder.
func _bake(key: String, builder: Callable) -> ArrayMesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	_sts.clear()
	_cnt.clear()
	builder.call()
	var mesh := ArrayMesh.new()
	for mat in _sts:
		var st: SurfaceTool = _sts[mat]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	_sts.clear()
	_cnt.clear()
	_mesh_cache[key] = mesh
	return mesh


## Pieza animable de la cara: un Node3D que gira en `origin` (coordenadas de la malla de la cabeza, sin escalar)
## con una MeshInstance3D "Mesh" cuyos vértices quedan donde los dejó el builder. Escala igual que la cabeza.
func _dress_piece(nm: String, origin: Vector3, builder: Callable, parent: Node3D = null, k := CLAY_HEAD_K,
		cache_key := "") -> Node3D:
	var mesh := _bake("piece_" + (cache_key if cache_key != "" else nm), builder)
	var pv := Node3D.new()
	pv.name = nm
	pv.position = origin * k
	pv.scale = Vector3.ONE * k
	pv.set_meta("base_pos", pv.position)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.position = -origin
	pv.add_child(mi)
	(parent if parent != null else head).add_child(pv)
	_pieces[nm] = pv
	return pv


## Cuelga del pivote una sola MeshInstance3D con todas sus piezas (cacheada).
func _dress(pivot: Node3D, key: String, builder: Callable) -> void:
	var clay := ClayStyle.enabled
	if clay:
		key += "_clay"
	var mesh := _bake(key, builder)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	if clay and key.begins_with("head"):
		mi.scale = Vector3.ONE * CLAY_HEAD_K
	elif clay and key.begins_with("hand"):
		mi.scale = Vector3.ONE * CLAY_HAND_K
	pivot.add_child(mi)


## Triángulos totales del modelo (para presupuesto/tests).
func triangle_count() -> int:
	var tris := 0
	var nodes: Array = _joints.values() + _pieces.values()
	for n in nodes:
		var mi := (n as Node3D).get_node_or_null("Mesh") as MeshInstance3D
		if mi == null or not (n as Node3D).visible:
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

static func _eye() -> Material:     # globo ocular y pupila (pieza propia: el adaptador la deja brillante)
	return _vcmat("eye", MatActors.skin(Color.WHITE, Vector3.ONE), 0.12)

## Nombre de la pieza a la que pertenece un material de Andro ("" si no es suyo).
static func material_key(m: Material) -> String:
	for k in _mats:
		if _mats[k] == m:
			return k
	if MatActors.scarf_antioquia(Color.WHITE, Vector3.ONE) == m:
		return "knit"
	return ""

static func _leather() -> Material: # bolso y correa (cuero de arcilla)
	return _vcmat("leather", MatActors.cargo_twill(Color.WHITE, Vector3.ONE), 0.25)

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

## Copia los anillos escalados: ky en altura, kx en ancho, kz en profundidad.
static func _sc(rings: Array, ky: float, kx: float, kz := -1.0) -> Array:
	var k_z := kx if kz < 0.0 else kz
	var out: Array = []
	for r in rings:
		var d: Dictionary = (r as Dictionary).duplicate()
		d["y"] = float(d["y"]) * ky
		d["a"] = float(d["a"]) * kx
		d["bf"] = float(d["bf"]) * k_z
		d["bb"] = float(d["bb"]) * k_z
		d["cz"] = float(d["cz"]) * k_z
		d["cx"] = float(d["cx"]) * kx
		out.append(d)
	return out


func _geo_pelvis() -> void:
	var rings := _sc([
		_r(-0.168, 0.0, 0.0, 0.0),
		_rr(-0.165, 0.05, 0.045, 0.05, 0.0, 2.0),
		_rr(-0.13, 0.13, 0.092, 0.11, 0.004, 2.2, 0.012),
		_rr(-0.07, 0.165, 0.104, 0.124, 0.006, 2.3, 0.01),
		_rr(0.0, 0.168, 0.104, 0.118, 0.0, 2.4),
		_rr(0.06, 0.16, 0.1, 0.11, 0.0, 2.4),
		_r(0.07, 0.0, 0.0, 0.0),
	], 1.0, 0.84, 0.9)
	_loft(_twill(), rings, 20, Transform3D.IDENTITY, _c(C_TROUSER))
	# Cinturón fino con hebilla
	var rk := rings.slice(1, 6)
	var rb := _ring_at(rk, 0.045)
	var belt := [_r(0.032, 0.0, 0.0, float(rb["cz"])),
		_rr(0.033, float(rb["a"]) + 0.003, float(rb["bf"]) + 0.003, float(rb["bb"]) + 0.003, float(rb["cz"]), float(rb["n"])),
		_rr(0.056, float(rb["a"]) + 0.003, float(rb["bf"]) + 0.003, float(rb["bb"]) + 0.003, float(rb["cz"]), float(rb["n"])),
		_r(0.057, 0.0, 0.0, float(rb["cz"]))]
	_loft(_rip(), belt, 20, Transform3D.IDENTITY, _c(C_STRAP * 1.4))
	var bf := _on_surf(rk, 0.0, 0.045, true, 0.005)
	_loft(_rip(), [_r(0.034, 0.0, 0.0), _rr(0.035, 0.011, 0.004, 0.004, 0.0, 4.0), _rr(0.056, 0.011, 0.004, 0.004, 0.0, 4.0),
		_r(0.057, 0.0, 0.0)], 10, Transform3D(Basis.IDENTITY, bf), _c(C_ZIP * 2.2))


func _geo_spine() -> void:
	# Camisa blanca (se ve en la abertura del saco)
	var rings := _sc([
		_r(-0.125, 0.0, 0.0),
		_rr(-0.125, 0.16, 0.118, 0.12, 0.0, 2.4),
		_rr(-0.088, 0.162, 0.119, 0.121, 0.0, 2.4),
		_rr(-0.03, 0.163, 0.118, 0.118, 0.0, 2.4, 0.02),
		_rr(0.05, 0.168, 0.119, 0.118, 0.0, 2.4, 0.012),
		_rr(0.15, 0.17, 0.12, 0.12, 0.0, 2.4),
		_rr(0.24, 0.15, 0.1, 0.1, 0.0, 2.2),
		_r(0.25, 0.0, 0.0),
	], 1.0, 0.84, 0.9)
	_loft(_knit(), rings, 24, Transform3D.IDENTITY, _c(C_SHIRT))


# ---------------------------------------------------------------------
#  Torso: saco oscuro abierto sobre camisa blanca
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


static func _blazer_rings() -> Array:
	# Hasta el hombro igual que la chaqueta pero más estrecho; el cuello queda bajo el cuello de camisa
	var k := _jacket_rings().slice(0, 10)
	var out := _sc(k, 1.0, 0.88, 0.9)
	out.insert(0, _rr(-0.3, 0.158, 0.113, 0.113, 0.0, 2.6))
	out.insert(1, _rr(-0.26, 0.162, 0.115, 0.115, 0.0, 2.6, 0.01))
	out.append_array([_rr(0.262, 0.088, 0.078, 0.082, 0.007, 2.0), _rr(0.28, 0.07, 0.066, 0.07, 0.006, 2.0)])
	return out


func _geo_chest() -> void:
	var tw := _twill()
	var keys := _blazer_rings()
	var rings: Array = [_r(-0.302, 0.0, 0.0)] + keys + [_r(0.287, 0.0, 0.0, 0.006)]
	var csuit := _c(C_SUIT)
	var cl := _c(C_SUIT_LAPEL)
	var cw := _c(C_SHIRT)
	var cv := _c(C_VEST)
	var cb := _c(C_BUTTON)
	var clay := ClayStyle.enabled
	# Semiancho de la abertura (V) en cada altura: ancha arriba, estrecha abajo
	var hw := func(y: float) -> float:
		if clay:    # F8: franja estrecha de chaleco hasta la cintura
			return 0.034 + 0.03 * clampf((y + 0.05) / 0.33, 0.0, 1.0)
		return 0.03 + 0.04 * clampf((y + 0.1) / 0.38, 0.0, 1.0) if y > -0.1 else 0.03
	var y_open := -0.24 if clay else -0.29
	_loft(tw, rings, 26, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		if not clay and p.z < -0.02 and p.y > y_open and absf(p.x) < hw.call(p.y):
			return cw
		return csuit)
	var up_f := Vector3(0, 0, -1)
	if clay:    # F8: chaleco como pieza sobre el pecho (bordes nítidos) y cantos del abrigo a cada lado
		var vp := PackedVector3Array()
		var vw: Array = []
		for i in 8:
			var y := lerpf(0.255, y_open, float(i) / 7.0)
			vp.append(_on_surf(keys, 0.0, y, true, 0.0015))
			vw.append(float(hw.call(y)))
		_tube(tw, vp, vw, 0.004, 10, up_f, cv, true, 6.0)
		for sx in [-1.0, 1.0]:
			var ep := PackedVector3Array()
			for i in 8:
				var y := lerpf(0.2, y_open - 0.06, float(i) / 7.0)
				ep.append(_on_surf(keys, sx * float(hw.call(y)), y, true, 0.003))
			_tube(tw, ep, 0.009, 0.005, 6, up_f, csuit)
	# Solapas: siguen los bordes de la V desde el cuello hasta la cintura
	for sx in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var y_lap := 0.12 if clay else -0.1     # F8: solapa corta (video 68105)
		for i in 7:
			var y := lerpf(0.275, y_lap, float(i) / 6.0)
			var x: float = sx * (float(hw.call(y)) + 0.012 * (1.0 - float(i) / 6.0))
			pts.append(_on_surf(keys, x, y, true, 0.004))
		_tube(tw, pts, [0.012, 0.022, 0.026, 0.024, 0.02, 0.014, 0.008], 0.007, 6, up_f, cl)
		if not clay:    # bolsillo con solapa en la cadera (en arcilla va en los faldones)
			_tube(tw, _surf_path(keys, Vector2(0.075 * sx, -0.11), Vector2(0.16 * sx, -0.115), true, 0.003, 4),
				0.006, 0.004, 5, up_f, cl)
		elif sx > 0.0:  # botonadura: borde derecho de la abertura (a la izquierda de quien mira)
			for y in [0.1, -0.03, -0.155, -0.28]:
				var bx: float = float(hw.call(y)) + 0.009
				_ellip(tw, _on_surf(keys, bx, y, true, 0.004), Vector3(0.0085, 0.0085, 0.0038), cb, Vector3.ZERO, 8, 4)
	# Bolsillito de pecho (ribete)
	_tube(tw, _surf_path(keys, Vector2(-0.14, 0.14), Vector2(-0.085, 0.145), true, 0.003, 4), 0.004, 0.003, 5, up_f, cl)
	# Cuello del saco por detrás y a los lados
	var coll := PackedVector3Array()
	for i in 9:
		var ang := lerpf(-1.9, 1.9, float(i) / 8.0)     # 0 = atrás
		var rr := 0.083
		coll.append(Vector3(sin(ang) * rr, 0.262, cos(ang) * (rr + 0.004) + 0.004))
	_tube(tw, coll, 0.018, 0.016, 6, Vector3(0, 1, 0), cl)
	# Botones de la camisa (o del chaleco) y cuello
	for i in (3 if clay else 5):
		var y := lerpf(0.2 if clay else 0.235, -0.14, float(i) / (2.0 if clay else 4.0))
		_ellip(tw, _on_surf(keys, 0.0, y, true, 0.003), Vector3(0.0045, 0.0045, 0.0025), cv.darkened(0.45) if clay else cb, Vector3.ZERO, 8, 4)
	var collar := [
		_r(0.252, 0.0, 0.0, 0.0),
		_rr(0.255, 0.066, 0.064, 0.068, 0.004, 2.2),
		_rr(0.27, 0.062, 0.06, 0.064, 0.003, 2.1),
		_rr(0.296, 0.058, 0.057, 0.06, 0.002, 2.1),
		_rr(0.3, 0.056, 0.055, 0.058, 0.002, 2.0),
		_r(0.301, 0.0, 0.0, 0.002)]
	_loft(tw, collar, 18, Transform3D.IDENTITY, _c(C_TROUSER) if clay else cw)    # cuello alto negro en arcilla
	if ClayStyle.enabled:
		_clay_scarf(keys)
		_clay_satchel(keys)


# ---------------------------------------------------------------------
#  Cuello y cabeza
# ---------------------------------------------------------------------

func _geo_neck() -> void:
	var stub := _c(STUBBLE_TONE)
	var skin := _c(SKIN_TONE)
	_loft(_skin(), [_r(-0.03, 0.0, 0.0), _rr(-0.03, 0.05, 0.05, 0.052, 0.005), _rr(0.04, 0.046, 0.046, 0.048, 0.004),
		_rr(0.09, 0.046, 0.048, 0.046, -0.002), _rr(0.15, 0.045, 0.046, 0.045, -0.005), _r(0.155, 0.0, 0.0, -0.005)],
		16, Transform3D.IDENTITY, func(p: Vector3) -> Color:
			return skin.lerp(stub, 0.6 * clampf((p.y - 0.06) / 0.04, 0.0, 1.0) * clampf(-p.z / 0.03, 0.0, 1.0)))


## Anillos clave de la cabeza (frente = -z). y ya escalado por HEAD_Y.
static func _head_keys() -> Array:
	var raw := [
		[0.0, 0.026, 0.02, 0.028, -0.064, 2.3],     # F2: mentón más estrecho
		[0.015, 0.04, 0.038, 0.048, -0.052, 2.3],
		[0.035, 0.05, 0.054, 0.072, -0.034, 2.3],   # mandíbula
		[0.06, 0.058, 0.072, 0.083, -0.019, 2.3],   # mejillas hundidas
		[0.09, 0.066, 0.088, 0.095, -0.01, 2.4],
		[0.12, 0.072, 0.093, 0.1, -0.006, 2.5],
		[0.145, 0.077, 0.095, 0.104, -0.004, 2.5],
		[0.17, 0.08, 0.094, 0.105, 0.0, 2.4],
		[0.195, 0.076, 0.087, 0.1, 0.003, 2.3],
		[0.215, 0.062, 0.073, 0.088, 0.005, 2.2],
		[0.23, 0.04, 0.048, 0.06, 0.006, 2.0],
	]
	var out: Array = []
	for r in raw:
		out.append(_rr(r[0] * HEAD_Y, r[1], r[2], r[3], r[4], r[5]))
	return out


## Modelado fino de la cara: cuencas, arco superciliar, pómulos, surco bajo el labio.
const BEARD_THICK := 0.0065    # espesor de la barba en mejillas (m)
const BEARD_CHIN := 0.006      # largo extra en el mentón (m)


## Máscara de barba en coordenadas de cabeza: x = cobertura (0–1), y = zona de mentón (largo extra).
func _beard_mask(q: Vector3) -> Vector2:
	var front := clampf((0.03 - q.z) / 0.05, 0.0, 1.0)
	var ax := absf(q.x)
	# borde superior: línea de la mejilla, que sube hacia las patillas
	var top := 0.062 + 0.045 * clampf((ax - 0.03) / 0.04, 0.0, 1.0)
	var mv := clampf((top - q.y) / 0.014, 0.0, 1.0)
	var must := clampf(1.0 - ax / 0.036, 0.0, 1.0) * clampf((0.078 - q.y) / 0.008, 0.0, 1.0) \
		* clampf((q.y - 0.061) / 0.006, 0.0, 1.0)
	var m := maxf(mv, must)
	var mouth := clampf(exp(-(q.x * q.x / 0.0005 + pow(q.y - 0.0575, 2.0) / 0.000035)) * 1.6, 0.0, 1.0)
	m *= (1.0 - mouth) * front
	var chin := clampf((0.045 - q.y) / 0.04, 0.0, 1.0) * clampf(1.0 - ax / 0.04, 0.0, 1.0) * front
	return Vector2(m, chin)


func _head_deform(p: Vector3) -> Vector3:
	if p.z > -0.02:
		return p
	var q := p
	var fz := clampf((-p.z - 0.02) / 0.05, 0.0, 1.0)
	for sx in [-1.0, 1.0]:
		var dx: float = p.x - sx * 0.033
		var dy: float = p.y - EYE_Y
		q.z += 0.011 * exp(-(dx * dx / 0.00036 + dy * dy / 0.00016)) * fz
		var dx2: float = p.x - sx * 0.054
		var dy2: float = p.y - 0.102
		q.z -= 0.008 * exp(-(dx2 * dx2 + dy2 * dy2) / 0.0004) * fz   # pómulo marcado
		# mejilla hundida bajo el pómulo
		var dx3: float = p.x - sx * 0.044
		var dy3: float = p.y - 0.066
		q.z += 0.009 * exp(-(dx3 * dx3 + dy3 * dy3) / 0.00045) * fz
	var gb := exp(-pow((p.y - 0.152) / 0.011, 2.0)) * clampf(1.0 - absf(p.x) / 0.07, 0.0, 1.0)
	q.z -= 0.008 * gb * fz
	# surco mentolabial y mentón
	q.z += 0.004 * exp(-pow((p.y - 0.038) / 0.006, 2.0)) * clampf(1.0 - absf(p.x) / 0.03, 0.0, 1.0) * fz
	q.z -= 0.004 * exp(-pow((p.y - 0.012) / 0.012, 2.0)) * clampf(1.0 - absf(p.x) / 0.025, 0.0, 1.0) * fz   # punta del mentón
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
			shade = shade.lerp(shade * warm, exp(-(cx * cx / 0.0008 + cy * cy / 0.0006)) * 0.3 * fr)
			# mejilla hundida: gris ceniza (#8E8581 de la lámina)
			var hx: float = p.x - sx * 0.046
			var hy: float = p.y - 0.066
			shade = shade.lerp(shade * Color(0.84, 0.82, 0.85), exp(-(hx * hx / 0.001 + hy * hy / 0.00045)) * 0.75 * fr)
			# oreja y borde de la oreja más rojizos
			var ear := clampf((absf(p.x) - 0.078) / 0.012, 0.0, 1.0) * clampf(1.0 - absf(p.y - 0.113) / 0.04, 0.0, 1.0)
			shade = shade.lerp(shade * Color(1.1, 0.88, 0.84), ear * 0.35)
		# punta de la nariz y aletas más cálidas
		var nose := exp(-(p.x * p.x / 0.00018 + pow(p.y - 0.088, 2.0) / 0.00012)) * fr
		shade = shade.lerp(shade * Color(1.08, 0.88, 0.84), nose * 0.4)
		# frente un poco más clara y sombra bajo la mandíbula
		var fore := clampf((p.y - 0.155) / 0.03, 0.0, 1.0) * fr
		shade = shade.lerp(shade * Color(1.03, 1.02, 0.98), fore * 0.7)
		var jaw := clampf((0.03 - p.y) / 0.04, 0.0, 1.0)
		shade = shade.lerp(shade * Color(0.78, 0.72, 0.72), jaw * 0.8)
		base = Color(skin.r * shade.r, skin.g * shade.g, skin.b * shade.b)
		var sb := Color(stub.r * shade.r, stub.g * shade.g, stub.b * shade.b)
		var c: Color = base.lerp(sb, clampf(k, 0.0, 1.0) * (0.9 if BEARD_ON else 0.0))
		return c.lerp(hairc, burn * 0.8)
	_loft(skin_m, rings, 28, Transform3D.IDENTITY, head_col, Callable(), _head_deform)

	# Barba completa: cáscara de pelo que sobresale solo donde hay barba (el resto queda hundido
	# dentro de la piel). Cubre mejillas, patillas, bigote y mentón; deja libres los labios.
	var bys: Array = []
	var byy := 0.0
	while byy < 0.104:
		bys.append(byy)
		byy += 0.0055
	var beard_rings: Array = [_r(-0.004, 0.0, 0.0, -0.05)] + _resample(keys, bys)
	var beard_deform := func(p: Vector3) -> Vector3:
		var q := _head_deform(p)
		var bm := _beard_mask(q)
		var dir := Vector2(q.x, q.z).normalized()
		var out := lerpf(-0.016, BEARD_THICK + BEARD_CHIN * bm.y, bm.x)
		q.x += dir.x * out
		q.z += dir.y * out
		q.y -= BEARD_CHIN * 1.3 * bm.y * bm.x
		return q
	var beard_col := func(p: Vector3) -> Color:
		var bm := _beard_mask(p)
		var jitter := 0.85 + 0.3 * fposmod(sin(p.x * 913.0 + p.y * 571.0 + p.z * 337.0) * 43758.5, 1.0)
		var hc := Color(hairc.r * jitter * 1.7, hairc.g * jitter * 1.6, hairc.b * jitter * 1.5)
		return stub.lerp(hc, smoothstep(0.15, 0.7, bm.x))
	if BEARD_ON:
		_loft(hair_m, beard_rings, 56, Transform3D.IDENTITY, beard_col, Callable(), beard_deform)

	# Ojos: esclerótica, iris y línea de pestañas; cejas
	var up_f := Vector3(0, 0, -1)
	for sx in [-1.0, 1.0]:
		var ex: float = 0.034 * sx
		var ez := _head_z(ex, EYE_Y, keys)
		var clay_eyes := ClayStyle.enabled
		if clay_eyes:
			_clay_eye_bag(skin_m, ex, sx, ez)
		else:
			_ellip(skin_m, Vector3(ex, EYE_Y, ez + 0.0035), Vector3(0.0172, 0.0122, 0.0068), _c(C_SCLERA), Vector3.ZERO, 10, 5)
			_ellip(skin_m, Vector3(ex - 0.001 * sx, EYE_Y - 0.0005, ez - 0.0018), Vector3(0.0088, 0.0088, 0.002),
				_c(C_IRIS), Vector3.ZERO, 8, 4)
		var lash := PackedVector3Array()
		for i in 4:
			var t := float(i) / 3.0
			var lx: float = ex + sx * lerpf(-0.0175, 0.0175, t)
			lash.append(Vector3(lx, EYE_Y + 0.0095 + 0.0025 * sin(t * PI), _head_z(lx, EYE_Y + 0.01, keys) - 0.0005))
		if not clay_eyes:
			_tube(hair_m, lash, 0.0018, 0.0022, 3, up_f, _c(C_EYE))
		# Ceja recta y algo baja hacia el centro (mirada seria)
		var brow := PackedVector3Array()
		var bra: Array = []
		for i in 4:
			var t := float(i) / 3.0
			var bx: float = sx * lerpf(0.014, 0.054, t)
			var by: float = EYE_Y + 0.024 + 0.005 * sin(t * 2.4) - 0.002 * (1.0 - t)
			brow.append(Vector3(bx, by, _head_z(bx, by, keys) - 0.0015))
			bra.append(lerpf(0.0042, 0.0028, t))
		if not clay_eyes:
			_tube(hair_m, brow, bra, 0.0026, 4, up_f, _c(C_HAIR))
		# Orejas (F3): concha, hélix, antihélix y lóbulo; la izquierda un poco más grande y alta (asimetría)
		var er := _ring_at(keys, 0.115)
		var ek: float = 1.07 if sx < 0.0 else 1.0
		var eo := Vector3(sx * (float(er["a"]) + 0.004), 0.113 + (0.003 if sx < 0.0 else 0.0), 0.014)
		if ClayStyle.enabled:
			_clay_ear(skin_m, eo, sx, ek, skin)
		else:
			_ellip(skin_m, eo, Vector3(0.008, 0.029, 0.018), skin, Vector3(0.0, -0.35 * sx, 0.12 * sx), 10, 6)
			_tube(skin_m, PackedVector3Array([eo + Vector3(0.006 * sx, 0.024, -0.006), eo + Vector3(0.009 * sx, 0.02, 0.012),
				eo + Vector3(0.008 * sx, -0.004, 0.018), eo + Vector3(0.006 * sx, -0.022, 0.008)]),
				0.004, 0.004, 5, Vector3(sx, 0, 0), skin)
	# Nariz: puente → punta, aletas
	var nose := PackedVector3Array()
	var nra: Array = []
	var nrb: Array = []
	var nys := [0.148, 0.128, 0.106, 0.092, 0.087]      # F3: punta redondeada y algo levantada
	var nout := [0.0, 0.007, 0.017, 0.026, 0.026]
	var nw := [0.0058, 0.0066, 0.0079, 0.0104, 0.0088]
	for i in 5:
		nose.append(Vector3(0, nys[i], _head_z(0.0, nys[i], keys) - nout[i] + 0.006))
		nra.append(nw[i])
		nrb.append(0.005 + 0.003 * float(i) / 4.0)
	_tube(skin_m, nose, nra, nrb, 8, up_f, skin)
	for sx in [-1.0, 1.0]:
		var az := _head_z(0.012 * sx, 0.09, keys)
		_ellip(skin_m, Vector3(0.0125 * sx, 0.0885, az - 0.004), Vector3(0.0072, 0.0058, 0.0082), skin,
			Vector3(0, 0.3 * sx, 0), 8, 5)
		if ClayStyle.enabled:    # fosa nasal: punto oscuro bajo el ala
			_ellip(skin_m, Vector3(0.0062 * sx, 0.0842, _head_z(0.0, 0.087, keys) - 0.0215), Vector3(0.0026, 0.0017, 0.0026),
				_c(SKIN_TONE * 0.55), Vector3.ZERO, 6, 4)
	# Labios
	var lipc := _c(C_LIP)
	for k in (0 if ClayStyle.enabled else 2):     # en arcilla la boca son piezas aparte (F5)
		var ly := 0.0605 if k == 0 else 0.054
		var lip := PackedVector3Array()
		for i in 5:
			var t := float(i) / 4.0
			var lx := lerpf(-0.022, 0.022, t)
			var bulge := sin(t * PI)
			lip.append(Vector3(lx, ly + (0.001 if k == 0 else -0.0008) * bulge, _head_z(lx, ly, keys) + 0.0018 - 0.002 * bulge))
		_tube(skin_m, lip, 0.0028 if k == 0 else 0.0034, 0.0022 if k == 0 else 0.003, 6, Vector3(0, 1, 0), lipc if (k == 1 or not ClayStyle.enabled) else _c(SKIN_TONE * 0.9))

	# Pelo: casquete con línea de pelo inclinada + mechones con volumen
	if ClayStyle.enabled:
		return     # F6: en arcilla el pelo es una pieza aparte (_geo_hair)
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
	var rings := _sc([
		_r(0.034, 0.0, 0.0, 0.0, 2.0, 0.0, -sx * 0.025),
		_r(0.031, 0.03, 0.036, 0.0, 2.0, 0.0, -sx * 0.02),
		_r(0.018, 0.055, 0.06, 0.0, 2.0, 0.0, -sx * 0.01),
		_r(0.0, 0.068, 0.069),
		_r(-0.04, 0.068, 0.067, 0.0, 2.0, 0.008),
		_r(-0.1, 0.064, 0.062, 0.0, 2.0, 0.012),
		_r(-0.17, 0.061, 0.06, 0.0, 2.0, 0.02),
		_r(-0.24, 0.056, 0.055, 0.0, 2.0, 0.03),
		_r(-0.29, 0.056, 0.056, 0.0, 2.0, 0.03),
		_r(-0.315, 0.05, 0.05),
		_r(-0.32, 0.0, 0.0),
	], ARM_K, 0.82, 0.84)
	_loft(_twill(), rings, 14, Transform3D.IDENTITY, _c(C_SUIT))


func _geo_forearm(_sx: float) -> void:
	var rings := _sc([
		_r(0.05, 0.0, 0.0),
		_r(0.045, 0.04, 0.04),
		_r(0.02, 0.06, 0.06, 0.0, 2.0, 0.015),
		_r(0.0, 0.064, 0.064, 0.0, 2.0, 0.02),
		_r(-0.05, 0.06, 0.058, 0.0, 2.0, 0.015),
		_r(-0.12, 0.054, 0.052, 0.0, 2.0, 0.01),
		_r(-0.185, 0.049, 0.047),
		_r(-0.2, 0.049, 0.047),
		_r(-0.238, 0.047, 0.045),
		_r(-0.245, 0.04, 0.038),
		_r(-0.24, 0.0, 0.0),
	], ARM_K, 0.8, 0.82)
	var cs := _c(C_SUIT)
	var cw := _c(C_SUIT_LAPEL) if ClayStyle.enabled else _c(C_SHIRT)
	_loft(_twill(), rings, 14, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return cw if p.y < (-0.205 if ClayStyle.enabled else -0.232) * ARM_K else cs)


func _geo_hand(sx: float) -> void:
	var skin_m := _skin()
	var skin := _c(SKIN_TONE)
	# Muñeca y palma (manos descubiertas)
	_loft(skin_m, [_r(0.03, 0.0, 0.0), _r(0.028, 0.02, 0.024), _r(-0.012, 0.02, 0.025), _r(-0.014, 0.0, 0.0)],
		10, Transform3D.IDENTITY, skin)
	var palm := [
		_r(0.006, 0.0, 0.0),
		_r(0.004, 0.022, 0.028, 0.0, 2.6),
		_r(-0.008, 0.023, 0.03, 0.0, 2.6),
		_r(-0.035, 0.018, 0.038, -0.002, 3.2),
		_r(-0.07, 0.015, 0.04, -0.002, 3.6),
		_r(-0.094, 0.0135, 0.038, -0.002, 3.6),
		_r(-0.101, 0.009, 0.032, -0.002, 3.0),
		_r(-0.103, 0.0, 0.0, -0.002),
	]
	_loft(skin_m, palm, 12, Transform3D.IDENTITY, skin)
	# Dedos largos y delgados, algo curvados
	var fz := [-0.028, -0.009, 0.009, 0.027]
	var clay_h := ClayStyle.enabled
	var fl := [0.066, 0.072, 0.068, 0.056] if clay_h else [0.074, 0.082, 0.076, 0.062]
	var fr := [0.0104, 0.0108, 0.0104, 0.0094] if clay_h else [0.0078, 0.008, 0.0076, 0.0066]
	for i in 4:
		var L: float = fl[i]
		var z: float = fz[i]
		var p := PackedVector3Array([Vector3(0.0, -0.088, z), Vector3(-sx * 0.003, -0.088 - L * 0.42, z),
			Vector3(-sx * 0.012, -0.088 - L * 0.78, z * 1.05), Vector3(-sx * 0.022, -0.088 - L, z * 1.08)])
		_tube(skin_m, p, fr[i], float(fr[i]) * 0.95, 5, Vector3(0, 0, -1), skin)
	# Pulgar
	var t0 := Vector3(-sx * 0.012, -0.018, -0.028)
	var t1 := Vector3(-sx * 0.02, -0.045, -0.044)
	var t2 := Vector3(-sx * 0.026, -0.068, -0.05)
	var t3 := Vector3(-sx * 0.028, -0.082, -0.048)
	var tk := 1.25 if ClayStyle.enabled else 1.0
	_tube(skin_m, PackedVector3Array([t0, t1, t2, t3]), [0.011 * tk, 0.0105 * tk, 0.0095 * tk, 0.0082 * tk], 0.0098 * tk, 6, Vector3(sx, 0, 0), skin)


# ---------------------------------------------------------------------
#  Piernas: pantalón de vestir entubado y zapatos negros
# ---------------------------------------------------------------------

static func _thigh_rings() -> Array:
	return _sc([
		_r(0.07, 0.09, 0.095),
		_r(0.0, 0.098, 0.1, 0.004, 2.0, 0.012),
		_r(-0.1, 0.094, 0.094, 0.0, 2.0, 0.01),
		_r(-0.2, 0.086, 0.085, 0.0, 2.0, 0.008),
		_r(-0.3, 0.076, 0.077, 0.0, 2.0, 0.01),
		_r(-0.38, 0.069, 0.071, 0.0, 2.0, 0.015),
		_r(-0.45, 0.064, 0.066, 0.0, 2.0, 0.012),
	], THIGH_LEN / 0.43, 0.8, 0.84)


func _geo_thigh(sx: float) -> void:
	var tw := _twill()
	var keys := _thigh_rings()
	var ky := THIGH_LEN / 0.43
	_loft(tw, [_r(0.075, 0.0, 0.0)] + keys + [_r(-0.46 * ky, 0.0, 0.0)], 16, Transform3D.IDENTITY, _c(C_TROUSER))
	# Raya del pantalón (línea al frente)
	var crease := PackedVector3Array()
	for yy in [0.02, -0.12, -0.25, -0.36]:
		crease.append(_on_surf(keys, 0.0, yy * ky, true, 0.0008))
	_tube(tw, crease, 0.003, 0.0014, 4, Vector3(0, 0, -1), _c(C_TROUSER * 1.5))


func _geo_shin(_sx: float) -> void:
	var ky := SHIN_LEN / 0.38
	var rings := _sc([
		_r(0.06, 0.0, 0.0),
		_r(0.055, 0.058, 0.06),
		_r(0.0, 0.068, 0.07, -0.002, 2.0, 0.015),
		_r(-0.08, 0.063, 0.066, 0.006, 2.0, 0.008),
		_r(-0.18, 0.058, 0.062, 0.006, 2.0, 0.006),
		_r(-0.27, 0.055, 0.057, 0.0, 2.0, 0.008),
		_r(-0.34, 0.056, 0.058, 0.0, 2.0, 0.012),
		_r(-0.372, 0.056, 0.058, -0.002),
		_r(-0.376, 0.0, 0.0, -0.002),
	], ky, 0.8, 0.84)
	_loft(_twill(), rings, 16, Transform3D.IDENTITY, _c(C_TROUSER))
	var crease := PackedVector3Array()
	for yy in [0.03, -0.1, -0.22, -0.34]:
		crease.append(_on_surf(rings.slice(1, 8), 0.0, yy * ky, true, 0.0008))
	_tube(_twill(), crease, 0.003, 0.0014, 4, Vector3(0, 0, -1), _c(C_TROUSER * 1.5))


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
	var cs := _c(C_DRESS_SHOE)
	var shoe_col := func(_p: Vector3) -> Color:
		return cs
	var shoe_uv := func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25, 0.8 + 0.1 * p.x)
	_loft(_sole(), rings, 16, xf, shoe_col, shoe_uv)
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
	_loft(_sole(), sole_rings.call(-0.09, -0.064, 0.006, 0.0), 14, xf, _c(C_DRESS_SHOE * 1.3), func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25, clampf((-0.064 - p.y) / 0.026, 0.0, 1.0)))
	_loft(_sole(), sole_rings.call(-0.1, -0.088, 0.004, 0.003), 12, xf, _c(C_DRESS_SHOE * 1.8), func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25, 0.4 + clampf((-0.088 - p.y) / 0.012, 0.0, 1.0) * 0.6))


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
	_update_cloth(speed, delta)

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


# ---------------------------------------------------------------------
#  Modo plastilina: ojos saltones y bufanda tejida
# ---------------------------------------------------------------------

## Ojo de muñeco de plastilina: globo blanco grande que sobresale, pupila pequeña negra,
## párpado superior de piel que cae un poco (mirada cansada) y ceja gruesa encima.
## Ojera: rollito de arcilla más oscuro (malva) bajo el ojo. Queda en la malla de la cabeza (no se anima).
func _clay_eye_bag(skin_m: Material, ex: float, _sx: float, ez: float) -> void:
	var up_f := Vector3(0, 0, -1)
	var c := _eye_center(ex, ez)
	var bag := PackedVector3Array()
	for i in 5:
		var t := float(i) / 4.0
		var a := lerpf(-1.05, 1.05, t)
		bag.append(c + Vector3(sin(a) * 0.0285, -cos(a) * 0.0275, -0.0045 - 0.004 * cos(a)))
	_tube(skin_m, bag, [0.0035, 0.006, 0.007, 0.006, 0.0035], 0.0035, 6, up_f, _c(Color(0.46, 0.40, 0.42)))   # ojera morada/marrón (#5B4653 de la lámina, sin magenta)


## Centro del globo ocular (hundido en la cuenca: sobresale menos que antes).
func _eye_center(ex: float, ez: float) -> Vector3:
	return Vector3(ex * 1.06, EYE_Y - 0.002, ez + 0.001)

const EYE_R := Vector3(0.028, 0.028, 0.017)    # radios del globo ocular
const MOUTH_Y := 0.0555                          # altura del centro de la boca
const TEETH := Color(0.72, 0.70, 0.64)


## Boca M1 neutro · M2 asombrado (O) · M3 triste · M4 hablando (dientes) · M5 tenso (dientes apretados).
func set_mouth(id: int) -> void:
	if not _pieces.has("mouth_m1"):
		return
	_mouth = clampi(id, 1, 5)
	for i in 5:
		(_pieces["mouth_m%d" % (i + 1)] as Node3D).visible = (i + 1) == _mouth


func get_mouth() -> int:
	return _mouth


## Un labio: curva de x0 a x1 con altura y(t) y grosor; sigue la superficie de la cara.
func _lip(keys: Array, mat: Material, col: Color, w: float, yf: Callable, ra: float, rb: float, out: float, n := 7) -> void:
	var path := PackedVector3Array()
	for i in n:
		var t := float(i) / float(n - 1)
		var lx := lerpf(-w, w, t)
		var ly: float = yf.call(t)
		path.append(Vector3(lx, ly, _head_z(lx, ly, keys) + 0.0016 - out * sin(t * PI)))
	_tube(mat, path, ra, rb, 6, Vector3(0, 1, 0), col)


## Interior oscuro (disco) pegado a la cara y dientes opcionales.
func _mouth_cavity(keys: Array, c_y: float, rx: float, ry: float) -> void:
	_ellip(_eye(), Vector3(0.0, c_y, _head_z(0.0, c_y, keys) - 0.0004), Vector3(rx, ry, 0.0035),
		_c(Color(0.1, 0.045, 0.055)), Vector3.ZERO, 12, 6)


func _teeth_row(keys: Array, y: float, w: float, n: int, sz: Vector3) -> void:
	for i in n:
		var x := lerpf(-w, w, float(i) / float(n - 1))
		_ellip(_eye(), Vector3(x, y, _head_z(x, y, keys) - 0.0032), sz, _c(TEETH), Vector3.ZERO, 6, 4)


func _geo_mouth(id: int) -> void:
	var keys := _head_keys()
	var sm := _skin()
	var lc := _c(C_LIP)
	var lc_up := _c(C_LIP * 0.92)
	var my := MOUTH_Y
	match id:
		1:   # neutro: labios de arcilla ligeramente bajos, comisuras algo caídas
			_lip(keys, sm, lc_up, 0.022, func(t: float) -> float: return my + 0.0045 + 0.001 * sin(t * PI) - 0.0012 * absf(2.0 * t - 1.0), 0.0029, 0.0024, 0.002)
			_lip(keys, sm, lc, 0.022, func(t: float) -> float: return my - 0.0025 - 0.0008 * sin(t * PI) - 0.0006 * absf(2.0 * t - 1.0), 0.0036, 0.0032, 0.002)
		2:   # asombrado: "O" abierta con interior oscuro
			_mouth_cavity(keys, my, 0.0105, 0.0145)
			var ring := PackedVector3Array()
			for i in 13:
				var a := TAU * float(i) / 12.0
				var x := sin(a) * 0.0118
				var y := my + cos(a) * 0.0158
				ring.append(Vector3(x, y, _head_z(x, y, keys) - 0.0008))
			_tube(sm, ring, 0.0032, 0.0036, 6, Vector3(0, 0, -1), lc)
		3:   # triste: curva hacia abajo, labio inferior empujado hacia arriba
			_lip(keys, sm, lc_up, 0.021, func(t: float) -> float: return my - 0.0045 + 0.0085 * sin(t * PI), 0.0027, 0.0022, 0.0016)
			_lip(keys, sm, lc, 0.021, func(t: float) -> float: return my - 0.0045 + 0.004 * sin(t * PI) - 0.001, 0.0038, 0.0034, 0.0026)
		4:   # hablando: abierta con dientes superiores
			_mouth_cavity(keys, my, 0.0185, 0.0078)
			_teeth_row(keys, my + 0.0042, 0.0125, 6, Vector3(0.0034, 0.0042, 0.0022))
			_lip(keys, sm, lc_up, 0.0215, func(t: float) -> float: return my + 0.0088 + 0.0014 * sin(t * PI) - 0.0016 * absf(2.0 * t - 1.0), 0.0027, 0.0023, 0.0018)
			_lip(keys, sm, lc, 0.0215, func(t: float) -> float: return my - 0.0088 - 0.0016 * sin(t * PI) + 0.0014 * absf(2.0 * t - 1.0), 0.0036, 0.0032, 0.002)
		_:   # tenso: comisuras hacia atrás, dientes apretados
			_mouth_cavity(keys, my, 0.0225, 0.0036)
			_teeth_row(keys, my, 0.0185, 8, Vector3(0.0031, 0.0033, 0.002))
			_lip(keys, sm, lc_up, 0.0255, func(t: float) -> float: return my + 0.0042 - 0.0012 * absf(2.0 * t - 1.0), 0.0022, 0.002, 0.0006)
			_lip(keys, sm, lc, 0.0255, func(t: float) -> float: return my - 0.0042 + 0.0006 * absf(2.0 * t - 1.0), 0.0026, 0.0024, 0.0008)


## Piezas animables de la cara (F4): globo (mirada), párpado superior (parpadeo) y ceja, por lado.
func _build_face_pieces() -> void:
	var keys := _head_keys()
	for sx in [-1.0, 1.0]:
		var sfx := "l" if sx < 0.0 else "r"
		var ex: float = 0.034 * sx
		var ez := _head_z(ex, EYE_Y, keys)
		var c := _eye_center(ex, ez)
		_dress_piece("eye_" + sfx, c, _geo_eyeball.bind(c, sx))
		_dress_piece("lid_" + sfx, c, _geo_lid.bind(c))
		var bo := Vector3(ex * 1.08, EYE_Y + 0.04, ez - 0.012)
		_dress_piece("brow_" + sfx, bo, _geo_brow.bind(ex, ez, sx))
	# Boca (F5): 5 piezas cacheadas, una visible a la vez
	var mo := Vector3(0.0, MOUTH_Y, _head_z(0.0, MOUTH_Y, keys))
	for i in 5:
		var mp := _dress_piece("mouth_m%d" % (i + 1), mo, _geo_mouth.bind(i + 1))
		mp.visible = i == 0
	_mouth = 1
	set_hair_variant(0)
	_build_scarf_tails(0)
	_build_coat_skirt()


## Globo ocular: esclerótica gris-blanca, iris oscuro, pupila y UN solo brillo (esfera de plástico sin vida).
func _geo_eyeball(c: Vector3, sx: float) -> void:
	var em := _eye()
	_ellip(em, c, EYE_R, _c(C_CLAY_EYE), Vector3.ZERO, 14, 8)
	var g := Vector3(-0.003 * sx, -0.001, 0.0)       # la mirada cae un poco hacia adentro
	_ellip(em, c + g + Vector3(0, 0, -0.0163), Vector3(0.0108, 0.0108, 0.0024), _c(Color(0.2, 0.17, 0.17)), Vector3.ZERO, 10, 4)
	_ellip(em, c + g + Vector3(0, 0, -0.0176), Vector3(0.0058, 0.0058, 0.0016), _c(GothicClayAdapter.PUPIL), Vector3.ZERO, 8, 4)
	_ellip(em, c + Vector3(0.0065, 0.0045, -0.0162), Vector3(0.0029, 0.0029, 0.0011), _c(Color(0.95, 0.95, 0.97)), Vector3.ZERO, 8, 4)


## Párpado superior: casquete grueso de arcilla que gira en el centro del ojo (rotation.x < 0 lo baja).
## Reposo: el borde queda a ≈ 68° desde la vertical (párpado pesado, mirada cansada).
func _geo_lid(c: Vector3) -> void:
	var sm := _skin()
	var col := _c(SKIN_TONE * 0.93)
	var m := 16
	var rows: Array = [[0.0, 1.05], [0.35, 1.045], [0.7, 1.045], [0.95, 1.045], [1.1, 1.05], [1.17, 1.1], [1.23, 1.075], [1.32, 0.985]]
	var P := PackedVector3Array()
	for r in rows:
		var ph: float = r[0]
		var k: float = r[1]
		for j in m:
			var th := TAU * float(j) / float(m)
			P.append(c + Vector3(EYE_R.x * k * sin(ph) * sin(th), EYE_R.y * k * cos(ph), -EYE_R.z * k * sin(ph) * cos(th)))
	_grid(sm, P, rows.size(), m, Transform3D.IDENTITY, col)


## Ceja gruesa de plastilina, un poco caída hacia afuera (pieza propia: sube, baja e inclina).
func _geo_brow(ex: float, ez: float, sx: float) -> void:
	var brow := PackedVector3Array()
	for i in 4:
		var t := float(i) / 3.0
		var bx: float = ex * 1.08 + sx * lerpf(-0.02, 0.022, t)
		brow.append(Vector3(bx, EYE_Y + 0.04 + 0.005 * sin(t * PI) - 0.007 * t, ez - 0.012))
	_tube(_hair(), brow, [0.0075, 0.0085, 0.0075, 0.005], 0.005, 6, Vector3(0, 0, -1), _c(C_HAIR * 0.8))


## Cara por pasos (stop-motion). blink: 0 abierto, 1 entrecerrado, 2 cerrado.
## gaze: x = hacia +x de la cabeza, y = arriba (radianes, ±0.3 es mucho). brow_*: −1 baja … +1 sube.
func set_face(blink: int, gaze := Vector2.ZERO, brow_l := 0.0, brow_r := 0.0) -> void:
	if _pieces.is_empty():
		return
	var rx: float = [0.0, -0.55, -1.2][clampi(blink, 0, 2)]
	for sfx in ["l", "r"]:
		(_pieces["lid_" + sfx] as Node3D).rotation = Vector3(rx, 0.0, 0.0)
		(_pieces["eye_" + sfx] as Node3D).rotation = Vector3(gaze.y, -gaze.x, 0.0)
		var b: Node3D = _pieces["brow_" + sfx]
		var v: float = brow_l if sfx == "l" else brow_r
		b.position = (b.get_meta("base_pos") as Vector3) + Vector3(0.0, v * 0.007 * CLAY_HEAD_K, 0.0)
		b.rotation = Vector3(0.0, 0.0, v * 0.25 * (1.0 if sfx == "l" else -1.0))


## Oreja de arcilla: concha, hélix, antihélix y lóbulo (alrededor de eo; ek = escala; sx = lado).
func _clay_ear(skin_m: Material, eo: Vector3, sx: float, ek: float, skin: Color) -> void:
	var rot := Vector3(0.0, -0.5 * sx, 0.14 * sx)
	var ec := eo + Vector3(0.006 * sx, 0, 0)
	_ellip(skin_m, ec, Vector3(0.0105, 0.04, 0.028) * ek, skin, rot, 12, 7)
	# hélix: aro que sube por delante, rodea la parte alta y cae por detrás
	var helix := PackedVector3Array()
	for i in 9:
		var t := lerpf(deg_to_rad(215.0), deg_to_rad(-35.0), float(i) / 8.0)
		helix.append(eo + Vector3(0.0105 * sx, 0.0, 0.0) + Vector3(0.0, sin(t) * 0.037, cos(t) * 0.025 - 0.001) * ek)
	_tube(skin_m, helix, 0.0048 * ek, 0.0048 * ek, 6, Vector3(sx, 0, 0), skin)
	# antihélix: arco interior más corto
	var anti := PackedVector3Array()
	for i in 6:
		var t := lerpf(deg_to_rad(200.0), deg_to_rad(-10.0), float(i) / 5.0)
		anti.append(eo + Vector3(0.0092 * sx, 0.004, 0.0) + Vector3(0.0, sin(t) * 0.022, cos(t) * 0.014) * ek)
	_tube(skin_m, anti, 0.0032 * ek, 0.0032 * ek, 5, Vector3(sx, 0, 0), skin)
	# concha: hueco oscuro al centro
	_ellip(skin_m, eo + Vector3(0.0105 * sx, 0.002, 0.0015), Vector3(0.0035, 0.011, 0.008) * ek, skin.darkened(0.28), rot, 8, 5)
	# lóbulo
	_ellip(skin_m, eo + Vector3(0.0075 * sx, -0.039 * ek, 0.007), Vector3(0.0072, 0.0095, 0.0095) * ek, skin, Vector3.ZERO, 8, 5)


## Bufanda (lámina #042). En la malla del pecho quedan las dos vueltas al cuello y el nudo; las dos colas son
## piezas con cadena de pivotes (_build_scarf_tails) que reaccionan con retraso a la aceleración y al giro.
## Colores de la lámina: verde marchito #2B452B, blanco sucio #B2ACA0, óxido #8C5A3E en las puntas.
## Los albedos se calibran midiendo capturas (el render los sube): ver ANDRO_CONTEXTO §5.
const SCARF_G := Color(0.095, 0.17, 0.1)
const SCARF_W := Color(0.58, 0.585, 0.57)
const SCARF_RUST := Color(0.4, 0.25, 0.18)
const STRIPE_W := [0.55, 0.34, 0.7, 0.4, 0.5, 0.3, 0.8, 0.36]     # anchos irregulares: verde, blanco, verde…
const SCARF_VARIANTS := ["clasica", "torcida", "corta_rota", "flecos_largos"]

## Color de la raya en la posición u (unidades de ancho): ancho irregular, un poco de desgaste.
static func _stripe_col(u: float, p: Vector3) -> Color:
	var total := 0.0
	for w in STRIPE_W:
		total += float(w)
	var v := fposmod(u, total)
	var white := false
	for w in STRIPE_W:
		if v < float(w):
			break
		v -= float(w)
		white = not white
	var jit := 0.92 + 0.16 * fposmod(sin(p.x * 913.0 + p.y * 571.0 + p.z * 337.0) * 43758.5, 1.0)
	var c := SCARF_W if white else SCARF_G
	return _c(Color(c.r * jit, c.g * jit, c.b * jit))


func _clay_scarf(keys: Array) -> void:
	var km := _knit()
	var total := 0.0
	for w in STRIPE_W:
		total += float(w)
	# vuelta alrededor del cuello (ligeramente caída hacia adelante)
	var ring := PackedVector3Array()
	for i in 41:
		var a := TAU * float(i) / 40.0
		ring.append(Vector3(sin(a) * 0.098, 0.262 + 0.012 * cos(a) - 0.014 * maxf(-cos(a), 0.0), cos(a) * 0.092 + 0.004))
	_tube(km, ring, 0.032, 0.026, 10, Vector3(0, 1, 0), func(p: Vector3) -> Color:
		return _stripe_col((atan2(p.x, p.z) / TAU + 0.5) * total * 2.0, p), false)
	# segunda vuelta más baja y floja
	var ring2 := PackedVector3Array()
	for i in 41:
		var a := TAU * float(i) / 40.0
		ring2.append(Vector3(sin(a) * 0.104, 0.236 - 0.02 * maxf(-cos(a), 0.0), cos(a) * 0.098 + 0.004))
	_tube(km, ring2, 0.028, 0.022, 10, Vector3(0, 1, 0), func(p: Vector3) -> Color:
		return _stripe_col((atan2(p.x, p.z) / TAU + 0.5) * total * 2.0 + 1.3, p), false)
	# nudo entrelazado al frente: dos bultos de lana cruzados
	var kc := _on_surf(keys, -0.006, 0.224, true, 0.027)
	_ellip(km, kc, Vector3(0.036, 0.027, 0.026), func(p: Vector3) -> Color:
		return _stripe_col((p.x * 0.5 + p.y) / 0.03, p), Vector3(0.0, 0.0, 0.35), 12, 7)
	_ellip(km, kc + Vector3(0.024, -0.015, 0.004), Vector3(0.026, 0.02, 0.02), func(p: Vector3) -> Color:
		return _stripe_col((p.x * 0.5 - p.y) / 0.03 + 1.0, p), Vector3(0.0, 0.0, -0.6), 10, 6)


## Puntos de articulación de una cola (espacio del pecho). tail 0 = larga (izquierda), 1 = corta (derecha).
func _scarf_joints(keys: Array, variant: int, tail: int) -> PackedVector3Array:
	var short := variant == 2
	var y_end: float = [-0.12, -0.03][tail] if not short else [-0.05, 0.07][tail]
	var x0: float = [-0.03, 0.035][tail]
	var x1: float = [-0.048, 0.06][tail]
	var nseg: int = [4, 3][tail]
	return _surf_path(keys, Vector2(x0, 0.226), Vector2(x1, y_end), true, 0.032 - 0.007 * float(tail), nseg + 1)


## Una pieza (segmento) de cola. seg 0..n-1; el último lleva los flecos.
func _geo_scarf_seg(variant: int, tail: int, seg: int) -> void:
	var km := _knit()
	var keys := _blazer_rings()
	var J := _scarf_joints(keys, variant, tail)
	var n := J.size() - 1
	var y_top := J[0].y
	var y_len := maxf(y_top - J[n].y, 0.05)
	var a := J[seg]
	var b := J[seg + 1]
	var dirv := (b - a).normalized()
	var s0 := float(seg) / float(n)
	var s1 := float(seg + 1) / float(n)
	var up := Vector3(0, 0, -1)
	if variant == 1:    # torcida: la tira gira sobre su eje
		up = up.rotated(dirv, 0.7 * float(seg) * (1.0 if tail == 0 else -1.0))
	var wd := func(s: float) -> float: return lerpf(0.036, 0.026, s) - (0.004 if tail == 1 else 0.0)
	var mid := a.lerp(b, 0.5)
	var path := PackedVector3Array([a - dirv * (0.0 if seg == 0 else 0.004), mid, b + dirv * (0.0 if seg == n - 1 else 0.004)])
	var col := func(p: Vector3) -> Color:
		var c := _stripe_col((y_top - p.y) / 0.042 + float(tail) * 0.8, p)
		var rust := smoothstep(0.8, 1.0, (y_top - p.y) / y_len)
		if variant == 2:
			rust = smoothstep(0.55, 0.9, (y_top - p.y) / y_len)
		return c.lerp(_c(SCARF_RUST), rust * 0.85)
	_tube(km, path, [wd.call(s0), wd.call((s0 + s1) * 0.5), wd.call(s1)], [0.009, 0.009, 0.008], 8, up, col, true, 3.0)
	if seg == n - 1:    # flecos
		var nf := 10 if variant == 3 else (3 if variant == 2 else 5)
		var fl := 0.05 if variant == 3 else (0.016 if variant == 2 else 0.024)
		var half: float = float(wd.call(1.0)) * 0.8
		for f in nf:
			var fx := b.x + lerpf(-half, half, float(f) / float(maxi(nf - 1, 1)))
			var len_f := fl * (0.7 + 0.5 * fposmod(sin(float(f) * 12.9898 + float(tail) * 4.0) * 43758.5, 1.0))
			_tube(km, PackedVector3Array([Vector3(fx, b.y + 0.004, b.z), Vector3(fx + 0.002 * sin(float(f)), b.y - len_f, b.z - 0.004)]),
				0.0042, 0.0042, 4, Vector3(0, 0, -1), _c(SCARF_RUST.lerp(SCARF_W if f % 2 == 0 else SCARF_G, 0.45)))


## Cuelga las colas (cadena de pivotes hija del pecho) de la variante pedida. Mallas cacheadas.
func _build_scarf_tails(variant: int) -> void:
	for t in _scarf_chain:
		for pv in t:
			_pieces.erase(String((pv as Node3D).name))
		if t.size() > 0 and is_instance_valid(t[0]):
			(t[0] as Node3D).get_parent().remove_child(t[0])
			(t[0] as Node3D).queue_free()
	_scarf_chain = []
	var keys := _blazer_rings()
	for tail in 2:
		var J := _scarf_joints(keys, variant, tail)
		var chain: Array = []
		var parent: Node3D = chest
		var prev := Vector3.ZERO
		for i in J.size() - 1:
			var nm := "scarf_%s%d" % [["a", "b"][tail], i + 1]
			var pv := _dress_piece(nm, J[i], _geo_scarf_seg.bind(variant, tail, i), parent, 1.0,
				"scarf_%s_%d_%d" % [SCARF_VARIANTS[variant], tail, i])
			pv.position = J[i] - prev
			chain.append(pv)
			parent = pv
			prev = J[i]
		_scarf_chain.append(chain)
	_scarf_variant = variant


## Variante de bufanda: 0 clásica, 1 torcida, 2 corta/rota, 3 flecos largos.
func set_scarf_variant(v: int) -> void:
	if chest == null or not ClayStyle.enabled:
		return
	_build_scarf_tails(clampi(v, 0, SCARF_VARIANTS.size() - 1))
	for t in _scarf_chain:
		_style_piece(t[0])


func get_scarf_variant() -> int:
	return _scarf_variant


## Faldones del abrigo (F8, video 68105): el abrigo baja a medio muslo. Dos mitades (izquierda/derecha) hijas de
## `hips` que giran en la cadera siguiendo a su muslo (sin atravesar las piernas al caminar). Cada mitad es una
## concha con grosor: va por fuera de adelante hacia atrás y vuelve por dentro; el dobladillo queda cerrado.
const SKIRT_ROWS := [    # [y en hips, semiancho, fondo adelante, fondo atrás]
	[0.05, 0.154, 0.108, 0.109],      # dentro del saco
	[0.022, 0.164, 0.12, 0.121],      # costura de cintura: el faldón monta por fuera del saco
	[0.0, 0.165, 0.12, 0.121],
	[-0.1, 0.167, 0.119, 0.122],
	[-0.2, 0.173, 0.121, 0.125],
	[-0.27, 0.177, 0.122, 0.127],
	[-0.3, 0.178, 0.122, 0.127],
]
const SKIRT_PIVOT := Vector3(0.0, -0.04, 0.0)

static func _skirt_pt(row: Array, ang: float, sx: float, inset: float, k := 1.0) -> Vector3:
	var sn := sin(ang)
	var cs := cos(ang)
	var e := 2.0 / 2.6     # mismo exponente que los anillos del saco (_blazer_rings)
	var a: float = float(row[1]) * k - inset
	var b: float = (float(row[2]) if cs > 0.0 else float(row[3])) * k - inset
	return Vector3(sx * a * signf(sn) * pow(absf(sn), e), float(row[0]), -b * signf(cs) * pow(absf(cs), e))


func _geo_coat_skirt(sx: float) -> void:
	var tw := _twill()
	var cs := _c(C_SUIT)
	var cl := _c(C_SUIT_LAPEL)
	var cb := _c(C_BUTTON)
	var k := 1.02 if sx > 0.0 else 1.0           # la mitad derecha monta sobre la izquierda al frente
	var a0 := -0.16 if sx > 0.0 else 0.0
	var a1 := PI - 0.025                          # abertura trasera
	var K := 12
	var th := 0.008
	var P := PackedVector3Array()
	var rows: Array = [SKIRT_ROWS[0]] + SKIRT_ROWS + [SKIRT_ROWS[SKIRT_ROWS.size() - 1]]
	for i in rows.size():
		var cap := i == 0 or i == rows.size() - 1
		for j in K:
			P.append(_skirt_pt(rows[i], lerpf(a0, a1, float(j) / float(K - 1)), sx, th * 0.5 if cap else 0.0, k))
		for j in K:
			P.append(_skirt_pt(rows[i], lerpf(a1, a0, float(j) / float(K - 1)), sx, th * 0.5 if cap else th, k))
	var hem_y: float = float(SKIRT_ROWS[SKIRT_ROWS.size() - 1][0])
	_grid(tw, P, rows.size(), K * 2, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return cs.lerp(cl, 0.5 * smoothstep(hem_y + 0.03, hem_y, p.y)))   # dobladillo gastado
	# bolsillo con solapa
	var r_p: Array = SKIRT_ROWS[3]
	var flap := PackedVector3Array()
	for j in 5:
		var q := _skirt_pt(r_p, lerpf(0.42, 0.98, float(j) / 4.0), sx, -0.004, k)
		flap.append(q + Vector3(0, 0.004, 0))
	_tube(tw, flap, 0.016, 0.006, 6, Vector3(0, 1, 0), cl)
	# botones que siguen la botonadura del pecho (solo en la mitad derecha)
	if sx > 0.0:
		for y in [-0.12, -0.24]:
			var row := [y, 0.0, 0.0, 0.0]
			for ri in SKIRT_ROWS.size() - 1:
				var r0: Array = SKIRT_ROWS[ri]
				var r1: Array = SKIRT_ROWS[ri + 1]
				if y <= float(r0[0]) and y >= float(r1[0]):
					var t: float = (float(r0[0]) - y) / (float(r0[0]) - float(r1[0]))
					row = [y, lerpf(r0[1], r1[1], t), lerpf(r0[2], r1[2], t), lerpf(r0[3], r1[3], t)]
			var bp := _skirt_pt(row, asin(0.038 / float(row[1])), sx, -0.003, k)
			_ellip(tw, bp, Vector3(0.0085, 0.0085, 0.0038), cb, Vector3.ZERO, 8, 4)


func _build_coat_skirt() -> void:
	for side in [-1, 1]:
		var sfx := "l" if side < 0 else "r"
		_dress_piece("coat_" + sfx, SKIRT_PIVOT, _geo_coat_skirt.bind(float(side)), hips, 1.0)


## Inercia de las colas: la bufanda es más lenta que el pelo. Se separan del pecho al acelerar, frenar o correr
## y se balancean hacia los lados al girar. Cada segmento aporta un poco; la cadena se curva sola.
func _update_cloth(speed: float, delta: float) -> void:
	# faldones: siguen a su muslo (un poco menos) y se abren un poco al correr
	var kc := 1.0 - exp(-14.0 * delta)
	for sfx in ["l", "r"]:
		var cp: Node3D = _pieces.get("coat_" + sfx)
		if cp != null:
			var th: Node3D = _joints["thigh_" + sfx]
			var tx := clampf(th.rotation.x * 0.62, -0.95, 0.5)
			cp.rotation.x = lerpf(cp.rotation.x, tx, kc)
			cp.rotation.z = lerpf(cp.rotation.z, (0.05 if sfx == "r" else -0.05) * clampf(speed / 6.0, 0.0, 1.0), kc)
	if _scarf_chain.is_empty():
		return
	var run := clampf(speed / 6.0, 0.0, 1.0)
	var k := 1.0 - exp(-4.0 * delta)
	for tail in _scarf_chain.size():
		var chain: Array = _scarf_chain[tail]
		for i in chain.size():
			var pv: Node3D = chain[i]
			var w := 0.55 if tail == 0 else 0.75     # la corta se mueve más
			var rx := (clampf(-_accel_f * 0.018, 0.0, 0.3) + clampf(_accel_f * 0.012, 0.0, 0.2) + 0.1 * run) * w
			var rz := clampf(_turn_f * 0.035, -0.3, 0.3) * w
			rx += 0.02 * sin(float(Time.get_ticks_msec()) * 0.0013 + float(tail * 2 + i) * 0.7)   # respiración
			pv.rotation.x = lerpf(pv.rotation.x, rx, k)
			pv.rotation.z = lerpf(pv.rotation.z, rz, k)


## Bandolera: correa cruzada (hombro derecho → cadera izquierda, por delante y por detrás) y bolso de arcilla.
func _clay_satchel(keys: Array) -> void:
	var tw := _twill()
	var lm := _leather()
	# lámina asset #043: marrón oscuro #3D2B1F, marrón tierra #5C4033, metal oxidado #6E5B4F
	var cs := _c(Color(0.24, 0.17, 0.12))
	var cbag := _c(Color(0.36, 0.25, 0.2))
	var cflap := _c(Color(0.28, 0.19, 0.14))
	var cmetal := _c(Color(0.43, 0.36, 0.31))
	for front in ([true, false] if SATCHEL_ON else []):
		var path := _surf_path(keys, Vector2(0.12, 0.25), Vector2(-0.165, -0.25), front, 0.008, 14)
		_tube(lm, path, 0.016, 0.006, 6, Vector3(0, 0, -1.0 if front else 1.0), cs, false, 3.0)
	if not SATCHEL_ON:
		_tube(tw, _surf_path(keys, Vector2(-0.135, 0.12), Vector2(-0.085, 0.123), true, 0.006, 4), 0.005, 0.003, 5,
			Vector3(0, 0, -1), _c(Color(0.62, 0.42, 0.18)))
		return
	# remate de la correa sobre el hombro
	_tube(lm, PackedVector3Array([_on_surf(keys, 0.12, 0.25, true, 0.008), Vector3(0.125, 0.285, 0.0),
		_on_surf(keys, 0.12, 0.25, false, 0.008)]), 0.016, 0.006, 6, Vector3(1, 0, 0), cs, false, 3.0)
	# bolso colgado en la cadera izquierda: cuerpo, tapa y broche
	var bc := Vector3(-0.2, -0.285, 0.02)
	_ellip(lm, bc, Vector3(0.045, 0.075, 0.085), cbag, Vector3.ZERO, 12, 7)
	_ellip(lm, bc + Vector3(-0.012, 0.03, 0.0), Vector3(0.042, 0.05, 0.09), cflap, Vector3.ZERO, 12, 6)
	# dos correíllas con hebilla sobre la tapa (cara exterior del bolso)
	for zz in [-0.035, 0.035]:
		_tube(lm, PackedVector3Array([bc + Vector3(-0.05, 0.06, zz), bc + Vector3(-0.056, 0.02, zz), bc + Vector3(-0.05, -0.03, zz)]),
			0.007, 0.002, 4, Vector3(-1, 0, 0), cs)
		_tube(lm, PackedVector3Array([bc + Vector3(-0.058, 0.008, zz - 0.008), bc + Vector3(-0.059, 0.008, zz + 0.008),
			bc + Vector3(-0.058, -0.006, zz + 0.008), bc + Vector3(-0.057, -0.006, zz - 0.008), bc + Vector3(-0.058, 0.008, zz - 0.008)]),
			0.0018, 0.0018, 4, Vector3(-1, 0, 0), cmetal, false)
	# vivo ocre del bolsillo de pecho (detalle de la lámina)
	_tube(tw, _surf_path(keys, Vector2(-0.135, 0.12), Vector2(-0.085, 0.123), true, 0.006, 4), 0.005, 0.003, 5,
		Vector3(0, 0, -1), _c(Color(0.62, 0.42, 0.18)))


## Cabello gótico despeinado (lámina asset #044-B), pieza aparte de la cabeza (F6). Casquete + mechones gruesos y
## aplanados en 3 capas (frente, sienes, nuca), volumen asimétrico (más a la derecha), remolino en la coronilla y
## puntas con polvo mate #78716C. Colores: base #1C1A1A, medios #322E2E, sombra #241F1C.
## Variantes (hoja): 0 clásico, 1 viento/acción, 2 mojado/aplastado, 3 extra caótico.
const HAIR_VARIANTS := ["clasico", "viento", "mojado", "caotico"]
const HAIR_ORIGIN := Vector3(0.0, 0.125, 0.0)    # el pelo gira/oscila alrededor de aquí

func _geo_hair(variant: int) -> void:
	var hair_m := _hair()
	var hairc := _c(C_HAIR)
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
	# parámetros por variante
	var count_k := 1.0
	var len_k := 1.0
	var rnd_k := 1.0
	var grav_k := 1.0
	var wide_k := 1.0
	var wind := Vector3.ZERO
	match variant:
		1:
			len_k = 1.2
			grav_k = 0.1
			wind = Vector3(0.1, 0.1, 0.95)       # barrido hacia atrás
		2:
			count_k = 0.8
			len_k = 0.55
			rnd_k = 0.35
			grav_k = 3.0
			wide_k = 1.35
		3:
			count_k = 1.5
			len_k = 1.2
			rnd_k = 1.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 44 + variant * 101
	var dark := Color(0.28, 0.26, 0.26)
	var mid := Color(0.38, 0.35, 0.35)
	var dust := Color(0.47, 0.44, 0.42)
	var C := Vector3(0.0, 0.128, 0.004)
	var R := Vector3(0.092, 0.122, 0.114)
	# [cantidad, theta_min, theta_max, phi_min, phi_max, tipo]  (phi 0 = frente, 90 = derecha, 180 = nuca)
	var zones := [
		[8, 0.0, 26.0, -180.0, 180.0, "top"],
		[6, 8.0, 22.0, -180.0, 180.0, "swirl"],
		[16, 30.0, 62.0, -180.0, 180.0, "mid"],
		[7, 42.0, 62.0, -60.0, 60.0, "fringe"],
		[4, 52.0, 70.0, 70.0, 120.0, "side"],
		[4, 52.0, 70.0, -120.0, -70.0, "side"],
		[15, 58.0, 118.0, 120.0, 240.0, "back"],
	]
	for z in zones:
		for i in maxi(1, roundi(float(z[0]) * count_k)):
			var th := deg_to_rad(rng.randf_range(z[1], z[2]))
			var ph := deg_to_rad(rng.randf_range(z[3], z[4]))
			var kind: String = z[5]
			var P := C + Vector3(R.x * sin(th) * sin(ph), R.y * cos(th), -R.z * sin(th) * cos(ph))
			var n := Vector3((P.x - C.x) / (R.x * R.x), (P.y - C.y) / (R.y * R.y), (P.z - C.z) / (R.z * R.z)).normalized()
			var rnd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * rnd_k
			var asym := 1.0 + 0.35 * signf(P.x)       # más volumen a la derecha
			var d: Vector3
			var L: float
			var grav := 0.0
			match kind:
				"top":
					d = n + Vector3(0.35, 0.45, 0) + rnd * 0.6
					L = rng.randf_range(0.05, 0.078) * asym
				"swirl":    # remolino: los mechones giran alrededor de la coronilla
					d = n + Vector3(cos(ph), 0.0, -sin(ph)).rotated(Vector3.UP, PI * 0.5) * 1.1 + rnd * 0.25
					L = rng.randf_range(0.04, 0.06)
					grav = 0.1
				"mid":
					d = n + Vector3(0.15, 0.25, 0) + rnd * 0.6
					L = rng.randf_range(0.045, 0.075) * asym
					grav = 0.15
				"fringe":
					d = n * 0.35 + Vector3(rng.randf_range(-0.6, 0.6) + 0.35, -0.75, -0.45)
					L = rng.randf_range(0.045, 0.065)
					grav = 0.3
				"side":     # sienes: suben y van hacia atrás, sin cubrir las orejas
					d = n + Vector3(0, 0.15, 0.55) + rnd * 0.3
					L = rng.randf_range(0.04, 0.055)
					grav = 0.1
				_:
					d = n + Vector3(0, -0.45, 0.3) + rnd * 0.5
					L = rng.randf_range(0.05, 0.08)
					grav = 0.25
			d = (d + wind * (0.0 if kind == "fringe" else 1.0) + (wind * 0.5 if kind == "fringe" else Vector3.ZERO)).normalized()
			L *= len_k
			grav *= grav_k
			var curl := d.cross(n).normalized() * rng.randf_range(-0.3, 0.3)
			var pts := PackedVector3Array()
			for tries in 6:
				pts = PackedVector3Array()
				for k in 5:
					var t := float(k) / 4.0
					pts.append(P - n * 0.012 + d * L * t + (curl + Vector3(0, -grav, 0)) * L * t * t)
				# el flequillo no tapa las cejas (están en ~0.174)
				if kind != "fringe" or pts[4].y >= 0.186:
					break
				L *= 0.85
			var w0 := rng.randf_range(0.019, 0.03) * wide_k
			var ra := [w0 * 0.95, w0, w0 * 0.8, w0 * 0.45, 0.0025]
			var rb := [0.008, 0.0085, 0.007, 0.004, 0.0015]
			var base := dark.lerp(mid, rng.randf())
			var p0 := P
			var dd := d
			var LL := L
			_tube(hair_m, pts, ra, rb, 5, n, func(p: Vector3) -> Color:
				var t := clampf((p - p0).dot(dd) / LL, 0.0, 1.0)
				return _c(base.lerp(dust, 0.35 * smoothstep(0.55, 1.0, t))))
	# mechón grande asimétrico que cruza la frente (de la coronilla derecha hacia la sien izquierda)
	if variant != 1:
		var sl := 0.5 if variant == 2 else 1.0
		_tube(hair_m, PackedVector3Array([Vector3(0.035, 0.236, -0.02), Vector3(0.01, 0.242 - 0.02 * (1.0 - sl), -0.075),
			Vector3(-0.03, 0.222 - 0.03 * (1.0 - sl), -0.108), Vector3(-0.058, 0.2, -0.108), Vector3(-0.072, 0.19, -0.095)]),
			[0.026, 0.03, 0.026, 0.016, 0.004], [0.01, 0.011, 0.009, 0.006, 0.002], 6, Vector3(0, 1, -0.4).normalized(),
			_c(mid.lerp(dark, 0.4)))


## Cambia la variante de pelo (0 clásico, 1 viento, 2 mojado, 3 caótico). Mallas cacheadas: no hay tirones.
func set_hair_variant(v: int) -> void:
	if head == null or not ClayStyle.enabled:
		return
	v = clampi(v, 0, HAIR_VARIANTS.size() - 1)
	var old: Node3D = _pieces.get("hair")
	if old != null:
		old.get_parent().remove_child(old)
		old.queue_free()
		_pieces.erase("hair")
	var hp := _dress_piece("hair", HAIR_ORIGIN, _geo_hair.bind(v), null, CLAY_HEAD_K, "hair_" + HAIR_VARIANTS[v])
	_hair_variant = v
	_style_piece(hp)


## Piezas creadas después de _ready: convierten el material a arcilla y lo estila el adaptador (en ese orden).
func _style_piece(n: Node3D) -> void:
	if not is_inside_tree():
		return
	ClayStyle.apply_tree(n)
	var ad := get_node_or_null("GothicClayAdapter")
	if ad != null:
		ad.apply_to(n)


func get_hair_variant() -> int:
	return _hair_variant

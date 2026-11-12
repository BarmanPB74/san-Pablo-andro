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
const CLAY_HEAD_SY := 1.13     # F9 (ref. 68107): cabeza más alta que ancha; estira en y desde el mentón
const CLAY_HEAD_S := Vector3(CLAY_HEAD_K, CLAY_HEAD_K * CLAY_HEAD_SY, CLAY_HEAD_K)
const CLAY_HAND_K := 1.4      # R2 (68107): manos grandes que llegan a medio muslo
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
const THIGH_LEN := 0.43        # F9 (68107): piernas −3 cm cada tramo (≈3.8 cabezas; pie sigue en y=0)
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
	C_TROUSER = Color(0.33, 0.328, 0.205) if clay else Color(0.06, 0.06, 0.068)    # F9: carbón neutro (albedo cálido contra la luz morada)
	C_SHIRT = C_SUIT if clay else Color(0.86, 0.86, 0.83)
	C_VEST = Color(0.42, 0.36, 0.215) if clay else C_SHIRT    # F9: suéter café de punto (68107, se ve ≈#4D3730)
	C_BUTTON = Color(0.11, 0.11, 0.11) if clay else Color(0.03, 0.03, 0.035)   # botones negros pequeños
	C_HAIR = Color(0.27, 0.25, 0.25) if clay else Color(0.045, 0.035, 0.03)
	C_DRESS_SHOE = Color(0.36, 0.33, 0.1) if clay else Color(0.035, 0.035, 0.04)  # F9: derby de cuero café oscuro
	# labio fino rosado (ref. 68107, se ve ≈ #C99995); en arcilla se deriva de la piel
	C_LIP = Color(C_CLAY_SKIN.r * 1.03, C_CLAY_SKIN.g * 0.86, C_CLAY_SKIN.b * 0.84) if clay else Color(0.52, 0.32, 0.27)
	root = _pivot("root", self, Vector3.ZERO)
	hips = _pivot("hips", root, Vector3(0, HIPS_HEIGHT, 0))
	spine = _pivot("spine", hips, Vector3(0, 0.1, 0))
	chest = _pivot("chest", spine, Vector3(0, 0.2, 0))
	neck = _pivot("neck", chest, Vector3(0, 0.24, 0.005))
	head = _pivot("head", neck, Vector3(0, 0.09, -0.005))
	for side in [-1, 1]:
		var sx := float(side)
		var sfx := "l" if side < 0 else "r"
		var ua := _pivot("upper_arm_" + sfx, chest, Vector3(0.205 * sx, 0.175, 0.0))   # R2 (68107): hombros anchos con hombrera
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
	var sv := CLAY_HEAD_S if parent == null else Vector3.ONE * k    # piezas de la cabeza: misma escala que su malla
	pv.position = origin * sv
	pv.scale = sv
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
		mi.scale = CLAY_HEAD_S
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
		# R2 (68107): abrigo como tubo ancho (sin entallar) y hombros cuadrados con hombrera (techo plano hasta el cuello)
		_rr(-0.197, 0.199, 0.131, 0.13, 0.0, 2.7),
		_rr(-0.17, 0.202, 0.134, 0.132, 0.0, 2.7, 0.01),
		_rr(-0.163, 0.2, 0.132, 0.131, 0.0, 2.7, 0.015),
		_rr(-0.1, 0.199, 0.13, 0.129, 0.0, 2.7, 0.03),
		_rr(-0.02, 0.2, 0.134, 0.13, 0.0, 2.7, 0.015),
		_rr(0.07, 0.206, 0.139, 0.131, 0.0, 2.6, 0.006),
		_rr(0.145, 0.218, 0.134, 0.132, 0.0, 2.8),
		_rr(0.195, 0.242, 0.12, 0.125, 0.005, 3.4),
		_rr(0.23, 0.232, 0.104, 0.114, 0.008, 3.8),
		_rr(0.252, 0.178, 0.094, 0.102, 0.008, 3.0),
		_rr(0.262, 0.104, 0.09, 0.095, 0.007, 2.0),
		_rr(0.29, 0.1, 0.089, 0.093, 0.006, 2.0, 0.012),
		_rr(0.308, 0.097, 0.087, 0.09, 0.004, 2.0),
	]


static func _blazer_rings() -> Array:
	# Hasta el hombro igual que la chaqueta pero más estrecho; el cuello queda bajo el cuello de camisa
	var k := _jacket_rings().slice(0, 10)
	var out := _sc(k, 1.0, 0.88, 0.9)
	out.insert(0, _rr(-0.3, 0.162, 0.113, 0.113, 0.0, 2.6))
	out.insert(1, _rr(-0.26, 0.168, 0.116, 0.116, 0.0, 2.6, 0.01))
	out.append_array([_rr(0.262, 0.088, 0.078, 0.082, 0.007, 2.0), _rr(0.28, 0.07, 0.066, 0.07, 0.006, 2.0)])
	return out


## R2: color de la solapa ancha (68107): canto exterior enrollado algo más claro.
static func _lapel_col(p: Vector3, hw: Callable, y_lap: float, cl: Color, cs: Color) -> Color:
	var t := clampf((0.21 - p.y) / (0.21 - y_lap), 0.0, 1.0)
	var wl := lerpf(0.06, 0.068, t / 0.14) if t < 0.14 else lerpf(0.068, 0.006, (t - 0.14) / 0.86)
	var f := clampf((absf(p.x) - float(hw.call(p.y)) + 0.004) / wl, 0.0, 1.0)
	return cl.lerp(cs.lightened(0.12), 0.7 * smoothstep(0.6, 1.0, f))


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
		if clay:    # F9 (68107): abrigo ABIERTO, el suéter ocupa el tercio central del pecho y se abre un poco abajo
			return 0.07 + 0.012 * clampf((-0.04 - y) / 0.25, 0.0, 1.0) - 0.006 * clampf((y - 0.17) / 0.08, 0.0, 1.0)
		return 0.03 + 0.04 * clampf((y + 0.1) / 0.38, 0.0, 1.0) if y > -0.1 else 0.03
	var y_open := -0.33 if clay else -0.29
	_loft(tw, rings, 26, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		if not clay and p.z < -0.02 and p.y > y_open and absf(p.x) < hw.call(p.y):
			return cw
		return csuit)
	var up_f := Vector3(0, 0, -1)
	if clay:    # F9: suéter de punto como concha fina pegada al pecho (bordes nítidos) y cantos del abrigo a cada lado
		var y_rib := y_open + 0.045
		var ys := [0.255, 0.19, 0.12, 0.05, -0.02, -0.09, -0.16, -0.23, y_rib + 0.003, y_rib - 0.003, y_open]
		var NR := ys.size()
		var NC := 41      # R2 (68107): canalé vertical fino; columnas impares en relieve (+1.3 mm) y más claras
		var sp := PackedVector3Array()
		for i in NR + 2:
			var y: float = ys[clampi(i - 1, 0, NR - 1)]
			var cap := i == 0 or i == NR + 1
			var w: float = float(hw.call(y)) + 0.006
			for j in NC:      # cara exterior (izq → der) y vuelta por dentro (der → izq)
				var x := lerpf(-w, w, float(j) / float(NC - 1))
				sp.append(_on_surf(keys, x, y, true, 0.003 if cap else 0.0055 + (0.0013 if j % 2 == 1 else 0.0)))
			for j in NC:
				var x := lerpf(w, -w, float(j) / float(NC - 1))
				sp.append(_on_surf(keys, x, y, true, 0.003 if cap else 0.0005))
		_grid(_knit(), sp, NR + 2, NC * 2, Transform3D.IDENTITY, func(p: Vector3) -> Color:
			var w: float = float(hw.call(p.y)) + 0.006
			var odd := roundi((p.x + w) / (2.0 * w) * float(NC - 1)) % 2 == 1
			var c := cv.darkened(0.16) if p.y < y_rib else cv     # elástico del borde, algo más oscuro
			return c.lightened(0.06) if odd else c.darkened(0.1))
		for sx in [-1.0, 1.0]:
			var ep := PackedVector3Array()
			for i in 8:
				var y := lerpf(0.2, y_open, float(i) / 7.0)
				ep.append(_on_surf(keys, sx * float(hw.call(y)), y, true, 0.003))
			_tube(tw, ep, 0.009, 0.005, 6, up_f, csuit)
	# Solapas: siguen los bordes de la V desde el cuello hasta la cintura
	for sx in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var y_lap := 0.12 if clay else -0.1
		if clay:    # F9 (68107): solapa con muesca (cuello corto arriba + solapa ancha que baja hasta medio pecho)
			y_lap = -0.045
			var cpts := PackedVector3Array()
			for i in 3:
				var y := lerpf(0.278, 0.224, float(i) / 2.0)
				cpts.append(_on_surf(keys, sx * (float(hw.call(y)) + 0.02), y, true, 0.005))
			_tube(tw, cpts, [0.013, 0.019, 0.022], 0.008, 6, up_f, cl)
			# R2: solapa ancha como concha pegada al pecho (no flota en los bordes); el pico superior sube hacia
			# afuera y deja la muesca contra el cuello. Baja hasta medio pecho sobre el suéter.
			var NRl := 8
			var NCl := 7
			var lp := PackedVector3Array()
			for i in NRl + 2:
				var ii := clampi(i - 1, 0, NRl - 1)
				var t := float(ii) / float(NRl - 1)
				var y := lerpf(0.21, y_lap, t)
				var cap := i == 0 or i == NRl + 1
				var wl := lerpf(0.06, 0.068, t / 0.14) if t < 0.14 else lerpf(0.068, 0.006, (t - 0.14) / 0.86)
				var x0: float = float(hw.call(y)) - 0.004
				for j in NCl:    # cara exterior (x creciente) y vuelta por dentro
					var f := float(j) / float(NCl - 1)
					var fo := f if sx > 0.0 else 1.0 - f
					lp.append(_on_surf(keys, sx * lerpf(x0, x0 + wl, fo), y + (0.016 * fo if ii == 0 else 0.0), true,
						0.005 if cap else 0.0095))
				for j in NCl:
					var f := 1.0 - float(j) / float(NCl - 1)
					var fo := f if sx > 0.0 else 1.0 - f
					lp.append(_on_surf(keys, sx * lerpf(x0, x0 + wl, fo), y + (0.016 * fo if ii == 0 else 0.0), true,
						0.005 if cap else 0.0015))
			_grid(tw, lp, NRl + 2, NCl * 2, Transform3D.IDENTITY, func(p: Vector3) -> Color: return _lapel_col(p, hw, y_lap, cl, csuit))
		else:
			for i in 7:
				var y := lerpf(0.275, y_lap, float(i) / 6.0)
				var x: float = sx * (float(hw.call(y)) + 0.012 * (1.0 - float(i) / 6.0))
				pts.append(_on_surf(keys, x, y, true, 0.004))
			_tube(tw, pts, [0.012, 0.022, 0.026, 0.024, 0.02, 0.014, 0.008], 0.007, 6, up_f, cl)
		if not clay:    # bolsillo con solapa en la cadera (en arcilla va en los faldones)
			_tube(tw, _surf_path(keys, Vector2(0.075 * sx, -0.11), Vector2(0.16 * sx, -0.115), true, 0.003, 4),
				0.006, 0.004, 5, up_f, cl)
		elif sx > 0.0:  # F9: un solo botón a la cintura en el canto derecho (a la izquierda de quien mira)
			var by := -0.24
			_ellip(tw, _on_surf(keys, float(hw.call(by)) + 0.022, by, true, 0.005), Vector3(0.009, 0.009, 0.004), cb, Vector3.ZERO, 8, 4)
	# Bolsillito de pecho (ribete)
	var pk := [Vector2(-0.178, 0.115), Vector2(-0.128, 0.12)] if clay else [Vector2(-0.14, 0.14), Vector2(-0.085, 0.145)]   # F9: fuera de la solapa ancha
	_tube(tw, _surf_path(keys, pk[0], pk[1], true, 0.003, 4), 0.004, 0.003, 5, up_f, cl)
	# Cuello del saco por detrás y a los lados
	var coll := PackedVector3Array()
	for i in 9:
		var ang := lerpf(-1.9, 1.9, float(i) / 8.0)     # 0 = atrás
		var rr := 0.083
		coll.append(Vector3(sin(ang) * rr, 0.262, cos(ang) * (rr + 0.004) + 0.004))
	_tube(tw, coll, 0.018, 0.016, 6, Vector3(0, 1, 0), cl)
	if clay:    # R2 (68107): costura central de la espalda y pliegues suaves de arcilla (cintura y omóplatos)
		var bk := Vector3(0, 0, 1)
		_tube(tw, _surf_path(keys, Vector2(0.0, 0.245), Vector2(0.0, -0.3), false, 0.0008, 14), 0.0032, 0.0016, 6, bk,
			csuit.darkened(0.14))
		for f in [[Vector2(-0.13, -0.11), Vector2(0.0, -0.135), Vector2(0.13, -0.115), 0.018],
				[Vector2(-0.11, -0.19), Vector2(0.01, -0.205), Vector2(0.12, -0.185), 0.016],
				[Vector2(-0.16, 0.07), Vector2(-0.1, 0.0), Vector2(-0.05, -0.06), 0.014],
				[Vector2(0.16, 0.07), Vector2(0.1, 0.0), Vector2(0.05, -0.06), 0.014]]:
			var fp := PackedVector3Array()
			for i in 7:
				var u := float(i) / 6.0
				var q: Vector2 = (f[0] as Vector2).lerp(f[1], u).lerp((f[1] as Vector2).lerp(f[2], u), u)
				fp.append(_on_surf(keys, q.x, q.y, false, -0.001))
			var fw: float = f[3]
			_tube(tw, fp, [fw * 0.3, fw * 0.8, fw, fw, fw, fw * 0.8, fw * 0.3], [0.001, 0.0018, 0.0022, 0.0022, 0.0022, 0.0018, 0.001],
				8, bk, csuit, true, 2.0)
	# Botones de la camisa (o del chaleco) y cuello
	for i in (0 if clay else 5):    # F9: el suéter de punto no lleva botones
		var y := lerpf(0.2 if clay else 0.235, -0.14, float(i) / (2.0 if clay else 4.0))
		_ellip(tw, _on_surf(keys, 0.0, y, true, 0.003), Vector3(0.0045, 0.0045, 0.0025), cv.darkened(0.45) if clay else cb, Vector3.ZERO, 8, 4)
	var collar := [
		_r(0.252, 0.0, 0.0, 0.0),
		_rr(0.255, 0.066, 0.064, 0.068, 0.004, 2.2),
		_rr(0.27, 0.062, 0.06, 0.064, 0.003, 2.1),
		_rr(0.296, 0.058, 0.057, 0.06, 0.002, 2.1),
		_rr(0.3, 0.056, 0.055, 0.058, 0.002, 2.0),
		_r(0.301, 0.0, 0.0, 0.002)]
	if clay:    # R2 (68107): cuello alto DOBLADO y más alto (tapa el cuello bajo la mandíbula), canalé vertical
		collar = [
			_r(0.25, 0.0, 0.0, 0.0),
			_rr(0.253, 0.066, 0.064, 0.068, 0.004, 2.2),
			_rr(0.272, 0.06, 0.058, 0.062, 0.003, 2.1),
			_rr(0.284, 0.06, 0.058, 0.062, 0.002, 2.1),
			_rr(0.29, 0.066, 0.064, 0.068, 0.002, 2.1),     # borde del doblez
			_rr(0.306, 0.068, 0.066, 0.07, 0.002, 2.1),
			_rr(0.318, 0.064, 0.062, 0.066, 0.002, 2.0),
			_rr(0.324, 0.055, 0.053, 0.057, 0.002, 2.0),    # canto vuelto hacia dentro
			_r(0.325, 0.0, 0.0, 0.002)]
		var ck := cv.darkened(0.08)
		_loft(_knit(), collar, 48, Transform3D.IDENTITY, func(p: Vector3) -> Color:
			var rib := cos(24.0 * atan2(p.x, p.z - 0.002))      # ±1 en columnas alternas (48 segmentos)
			var c := ck.lightened(0.05 * maxf(rib, 0.0)).darkened(0.1 * maxf(-rib, 0.0))
			return c.darkened(0.25 * (1.0 - smoothstep(0.0, 0.006, absf(p.y - 0.287)))))   # sombra bajo el doblez
	else:
		_loft(tw, collar, 18, Transform3D.IDENTITY, cw)
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
		# R2 (68107, medido en cara.jpg): óvalo largo con mandíbula ANCHA y redondeada; mentón redondo, no en punta
		[0.0, 0.029, 0.022, 0.03, -0.062, 2.2],
		[0.015, 0.046, 0.04, 0.05, -0.05, 2.25],
		[0.035, 0.059, 0.056, 0.079, -0.033, 2.3],  # mandíbula; atrás, nuca más llena y redonda
		[0.06, 0.067, 0.072, 0.089, -0.019, 2.35],  # mejillas (el hundido lo da _head_deform)
		[0.09, 0.0705, 0.088, 0.095, -0.01, 2.4],
		[0.12, 0.0735, 0.093, 0.1, -0.006, 2.5],
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
		q.z -= 0.006 * exp(-(dx2 * dx2 + dy2 * dy2) / 0.0005) * fz   # pómulo suave (R2)
		# mejilla hundida bajo el pómulo
		var dx3: float = p.x - sx * 0.045
		var dy3: float = p.y - 0.066
		q.z += 0.009 * exp(-(dx3 * dx3 + dy3 * dy3) / 0.00045) * fz
		# R2: surco nasogeniano suave (de la aleta de la nariz a la comisura) con la mejilla algo abultada por fuera
		var nl := _nasolabial(p, sx)
		q.z += (0.0016 * exp(-nl.x * nl.x / 1.2e-5) - 0.0011 * exp(-pow(nl.x - 0.0055, 2.0) / 2.5e-5)) * nl.y * fz
	var gb := exp(-pow((p.y - 0.152) / 0.011, 2.0)) * clampf(1.0 - absf(p.x) / 0.07, 0.0, 1.0)
	q.z -= 0.008 * gb * fz
	# surco mentolabial y mentón (R2: punta redonda y ancha con hoyuelo al centro)
	q.z += 0.0035 * exp(-pow((p.y - 0.037) / 0.006, 2.0)) * clampf(1.0 - absf(p.x) / 0.03, 0.0, 1.0) * fz
	q.z -= 0.005 * exp(-pow((p.y - 0.014) / 0.012, 2.0) - p.x * p.x / 0.0005) * fz   # punta del mentón
	q.z += 0.0012 * exp(-(p.x * p.x / 1.6e-5 + pow(p.y - 0.017, 2.0) / 6e-5)) * fz   # hoyuelo
	return q


## Surco nasogeniano del lado sx: x = distancia con signo a la línea (positiva hacia la mejilla), y = peso a lo largo.
static func _nasolabial(p: Vector3, sx: float) -> Vector2:
	var a := Vector2(0.017, 0.084)
	var b := Vector2(0.037, 0.05)
	var q := Vector2(p.x * sx, p.y)
	var ab := b - a
	var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var d := q - (a + ab * t)
	var nrm := Vector2(ab.y, -ab.x).normalized()     # hacia afuera (mejilla)
	if nrm.x < 0.0:
		nrm = -nrm
	var s := d.dot(nrm) if t > 0.0 and t < 1.0 else d.length() * signf(d.dot(nrm))
	return Vector2(s, sin(t * PI) * 0.8 + 0.2 * (1.0 - t))


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
			* clampf((0.03 - absf(p.z + 0.005)) / 0.02, 0.0, 1.0) \
			* clampf((EAR_ZF - 0.003 - p.z) / 0.008, 0.0, 1.0)    # R2: la patilla acaba delante de la oreja
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
			var ear := clampf((p.x * sx - 0.055) / 0.01, 0.0, 1.0) \
				* exp(-(pow(p.y - EAR_Y, 2.0) / 0.0007 + pow(p.z - 0.004, 2.0) / 0.0005))   # R2: piel junto a la raíz
			shade = shade.lerp(shade * Color(1.1, 0.88, 0.84), ear * 0.3)
			# R2: surco nasogeniano, sombra suave
			var nlc := _nasolabial(p, sx)
			shade = shade.lerp(shade * Color(0.88, 0.84, 0.87), exp(-nlc.x * nlc.x / 1.4e-5) * nlc.y * 0.4 * fr)
		# R2: hoyuelo del mentón, sombra suave
		shade = shade.lerp(shade * Color(0.9, 0.86, 0.88), exp(-(p.x * p.x / 2e-5 + pow(p.y - 0.017, 2.0) / 6e-5)) * 0.4 * fr)
		# punta de la nariz y aletas más cálidas
		var nose := exp(-(p.x * p.x / 0.00018 + pow(p.y - 0.088, 2.0) / 0.00012)) * fr
		shade = shade.lerp(shade * Color(1.08, 0.88, 0.84), nose * 0.4)
		# frente un poco más clara y sombra bajo la mandíbula
		var fore := clampf((p.y - 0.155) / 0.03, 0.0, 1.0) * fr
		shade = shade.lerp(shade * Color(1.03, 1.02, 0.98), fore * 0.7)
		var jaw := clampf((0.03 - p.y) / 0.04, 0.0, 1.0)
		shade = shade.lerp(shade * Color(0.78, 0.72, 0.72), jaw * 0.8)
		shade *= _eye_shade(p)    # ojeras (agente B, ronda 2)
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
		if ClayStyle.enabled:    # R2: la oreja nace pegada al cráneo (raíz calculada sobre la piel)
			_clay_ear(skin_m, keys, sx, ek, skin, EAR_Y + (0.003 if sx < 0.0 else 0.0))
		else:
			_ellip(skin_m, eo, Vector3(0.008, 0.029, 0.018), skin, Vector3(0.0, -0.35 * sx, 0.12 * sx), 10, 6)
			_tube(skin_m, PackedVector3Array([eo + Vector3(0.006 * sx, 0.024, -0.006), eo + Vector3(0.009 * sx, 0.02, 0.012),
				eo + Vector3(0.008 * sx, -0.004, 0.018), eo + Vector3(0.006 * sx, -0.022, 0.008)]),
				0.004, 0.004, 5, Vector3(sx, 0, 0), skin)
	# Nariz: puente → punta, aletas
	var nose := PackedVector3Array()
	var nra: Array = []
	var nrb: Array = []
	# Ronda 2 (ref. 68107): nariz larga y RECTA desde el entrecejo, que se ensancha hacia abajo; punta en BULBO
	# redondo y rosado que sobresale mucho de perfil, aletas carnosas visibles a los lados.
	# Puente: tubo cuya cara frontal sigue una recta (raíz → bulbo) y cuya cara trasera queda dentro de la piel.
	var nys := [0.157, 0.142, 0.127, 0.113, 0.101, 0.092]
	var nw := [0.0088, 0.0102, 0.0116, 0.0128, 0.0138, 0.0142]
	var z_root := _head_z(0.0, 0.157, keys) - 0.0035
	for i in 6:
		var ny: float = nys[i]
		var zf := lerpf(z_root, -0.1295, (0.157 - ny) / (0.157 - 0.094))     # línea frontal del perfil
		# el centro del tubo queda EN la piel: se ve medio óvalo, más ancho justo donde toca la cara (no un palo pegado)
		var zc := _head_z(0.0, ny, keys) + 0.001
		nose.append(Vector3(0, ny, zc))
		nra.append(nw[i])
		nrb.append(maxf(zc - zf, 0.005))
	var nose_tip := Vector3(0.0, 0.0875, -0.1185)    # centro del bulbo: su frente queda en z ≈ −0.131 (≈ 0.03 por delante del ojo)
	var pinkc := Color(skin.r * 0.97, skin.g * 0.86, skin.b * 0.86)   # punta rosada (ref. #C5A097 frente a #D0BBB1)
	var nose_col := func(p: Vector3) -> Color:
		return skin.lerp(pinkc, clampf(1.3 - (p - nose_tip).length() / 0.03, 0.0, 1.0))
	_tube(skin_m, nose, nra, nrb, 12, up_f, nose_col)
	_ellip(skin_m, nose_tip, Vector3(0.0152, 0.0122, 0.0128), nose_col, Vector3.ZERO, 14, 9)   # bulbo
	_ellip(skin_m, Vector3(0.0, 0.0805, -0.108), Vector3(0.0065, 0.0046, 0.0115), nose_col, Vector3(0.35, 0, 0), 10, 6)   # columela
	for sx in [-1.0, 1.0]:
		# aleta: pegada al costado del bulbo (sin "bolas" sueltas), un poco más atrás y arriba que la punta
		_ellip(skin_m, Vector3(0.0138 * sx, 0.0818, -0.1015), Vector3(0.0072, 0.0066, 0.0112), nose_col,
			Vector3(0.2, 0.5 * sx, 0), 10, 6)
		if ClayStyle.enabled:    # fosa nasal: punto oscuro bajo la punta (casi oculto de frente)
			_ellip(skin_m, Vector3(0.0064 * sx, 0.0772, -0.1115), Vector3(0.003, 0.0012, 0.0042),
				_c(Color(SKIN_TONE.r * 0.5, SKIN_TONE.g * 0.4, SKIN_TONE.b * 0.42)), Vector3.ZERO, 8, 4)
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
		# R2 (68107): manga gruesa de abrigo, copa de hombro cuadrada (hombrera)
		_r(0.036, 0.0, 0.0, 0.0, 2.0, 0.0, -sx * 0.02),
		_r(0.034, 0.042, 0.044, 0.0, 2.6, 0.0, -sx * 0.016),
		_r(0.02, 0.062, 0.062, 0.0, 2.6, 0.0, -sx * 0.008),
		_r(0.0, 0.068, 0.068, 0.0, 2.3),
		_r(-0.04, 0.067, 0.066, 0.0, 2.0, 0.008),
		_r(-0.1, 0.064, 0.062, 0.0, 2.0, 0.012),
		_r(-0.17, 0.061, 0.06, 0.0, 2.0, 0.02),
		_r(-0.24, 0.057, 0.056, 0.0, 2.0, 0.03),
		_r(-0.29, 0.057, 0.057, 0.0, 2.0, 0.03),
		_r(-0.315, 0.05, 0.05),
		_r(-0.32, 0.0, 0.0),
	], ARM_K, 0.97, 0.95)
	_loft(_twill(), rings, 14, Transform3D.IDENTITY, _c(C_SUIT))


func _geo_forearm(_sx: float) -> void:
	var rings := _sc([
		_r(0.05, 0.0, 0.0),
		_r(0.045, 0.04, 0.04),
		_r(0.02, 0.06, 0.06, 0.0, 2.0, 0.015),
		_r(0.0, 0.064, 0.064, 0.0, 2.0, 0.02),
		_r(-0.05, 0.06, 0.058, 0.0, 2.0, 0.015),
		_r(-0.12, 0.054, 0.052, 0.0, 2.0, 0.01),
		_r(-0.185, 0.05, 0.048),
		_r(-0.2, 0.051, 0.049),
		_r(-0.238, 0.051, 0.049),
		_r(-0.245, 0.043, 0.041),
		_r(-0.24, 0.0, 0.0),
	], ARM_K, 0.97, 0.97)    # R2 (68107): manga gruesa hasta el puño
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
	var clay_h := ClayStyle.enabled
	if clay_h:    # R2 (68107): palma gruesa de arcilla (de frente se ve el canto ancho de la mano en "C")
		palm = _sc(palm, 1.0, 1.3, 1.0)
	_loft(skin_m, palm, 12, Transform3D.IDENTITY, skin)
	# Dedos largos y delgados, algo curvados
	var fz := [-0.028, -0.009, 0.009, 0.027]
	var fl := [0.072, 0.08, 0.075, 0.062] if clay_h else [0.074, 0.082, 0.076, 0.062]
	var fr := [0.0112, 0.0117, 0.0112, 0.0102] if clay_h else [0.0078, 0.008, 0.0076, 0.0066]
	var fc := [0.8, 1.0, 1.12, 1.25] if clay_h else [1.0, 1.0, 1.0, 1.0]     # R2: el índice menos curvado, el meñique más
	var fs := 1.0 if clay_h else 0.0                                         # R2: dedos algo separados (abanico)
	var fk := 1.6 if clay_h else 1.0                                         # R2: relajados, curvados hacia la palma
	for i in 4:
		var L: float = fl[i]
		var z: float = fz[i]
		var cu: float = float(fc[i]) * fk
		var p := PackedVector3Array([Vector3(0.0, -0.088, z), Vector3(-sx * 0.003 * cu, -0.088 - L * 0.42, z * (1.0 + 0.12 * fs)),
			Vector3(-sx * 0.013 * cu, -0.088 - L * 0.75, z * (1.05 + 0.2 * fs)), Vector3(-sx * 0.026 * cu, -0.088 - L * 0.94, z * (1.08 + 0.26 * fs))])
		_tube(skin_m, p, [fr[i], float(fr[i]) * 1.04, float(fr[i]) * 0.98, float(fr[i]) * 0.9], float(fr[i]) * 0.95, 6,
			Vector3(0, 0, -1), skin)
	# Pulgar (arcilla: grueso y separado de los dedos, hacia la palma y adelante)
	var tq := 1.0 if clay_h else 0.0
	var t0 := Vector3(-sx * (0.012 + 0.006 * tq), -0.018, -0.028)
	var t1 := Vector3(-sx * (0.02 + 0.012 * tq), -0.045, -0.044 - 0.004 * tq)
	var t2 := Vector3(-sx * (0.026 + 0.016 * tq), -0.068, -0.05 - 0.004 * tq)
	var t3 := Vector3(-sx * (0.028 + 0.016 * tq), -0.082, -0.048 - 0.002 * tq)
	var tk := 1.35 if ClayStyle.enabled else 1.0
	_tube(skin_m, PackedVector3Array([t0, t1, t2, t3]), [0.011 * tk, 0.0105 * tk, 0.0095 * tk, 0.0082 * tk], 0.0098 * tk, 6, Vector3(sx, 0, 0), skin)


# ---------------------------------------------------------------------
#  Piernas: pantalón de vestir recto (F9, 68107: pernera algo holgada, pliegue sobre el zapato) y zapatos café
# ---------------------------------------------------------------------

static func _thigh_rings() -> Array:
	return _sc([
		_r(0.07, 0.09, 0.095),
		_r(0.0, 0.096, 0.1, 0.004, 2.0, 0.012),
		_r(-0.1, 0.09, 0.092, 0.0, 2.0, 0.01),
		_r(-0.2, 0.084, 0.086, 0.0, 2.0, 0.01),
		_r(-0.3, 0.079, 0.081, 0.0, 2.0, 0.012),
		_r(-0.38, 0.076, 0.078, 0.0, 2.0, 0.016),
		_r(-0.45, 0.074, 0.076, 0.0, 2.0, 0.012),
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
	_tube(tw, crease, 0.003, 0.0014, 4, Vector3(0, 0, -1), _c(C_TROUSER * 1.12))


func _geo_shin(_sx: float) -> void:
	var ky := SHIN_LEN / 0.38
	var rings := _sc([
		_r(0.06, 0.0, 0.0),
		_r(0.055, 0.066, 0.068),
		_r(0.0, 0.075, 0.077, -0.002, 2.0, 0.015),
		_r(-0.08, 0.074, 0.076, 0.002, 2.0, 0.008),
		_r(-0.18, 0.073, 0.075, 0.002, 2.0, 0.006),
		_r(-0.27, 0.073, 0.075, 0.0, 2.0, 0.008),
		_rr(-0.33, 0.074, 0.077, 0.075, -0.001, 2.0, 0.01),
		# pliegue suave (quiebre) y ruedo inclinado: adelante descansa sobre el empeine, atrás tapa el talón
		_rr(-0.36, 0.078, 0.085, 0.078, -0.004, 2.0, 0.022, 0.0, -0.12),
		_rr(-0.385, 0.079, 0.084, 0.08, -0.006, 2.0, 0.016, 0.0, -0.25),
		_rr(-0.398, 0.078, 0.082, 0.079, -0.006, 2.0, 0.01, 0.0, -0.25),
		_rr(-0.4, 0.0, 0.0, 0.0, -0.006, 2.0, 0.0, 0.0, -0.25),
	], ky, 0.8, 0.84)
	_loft(_twill(), rings, 16, Transform3D.IDENTITY, _c(C_TROUSER))
	var crease := PackedVector3Array()
	for yy in [0.03, -0.1, -0.22, -0.34]:
		crease.append(_on_surf(rings.slice(1, 8), 0.0, yy * ky, true, 0.0008))
	_tube(_twill(), crease, 0.003, 0.0014, 4, Vector3(0, 0, -1), _c(C_TROUSER * 1.12))


func _geo_foot(sx: float) -> void:
	# El loft corre a lo largo del pie (+y del loft = hacia la punta, -Z del pivote).
	# F9 (68107): derby/botín bajo de cuero café, punta redondeada, suela fina oscura; ~0.28 m de largo,
	# talón bajo (el ruedo del pantalón lo tapa por detrás y descansa sobre el empeine).
	var xf := Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3.ZERO)
	# [avance, semiancho, alto inferior, alto superior]
	var prof := [
		[-0.074, 0.03, -0.083, -0.042],
		[-0.064, 0.042, -0.084, -0.036],
		[-0.035, 0.048, -0.084, -0.026],
		[0.0, 0.05, -0.084, 0.006],
		[0.04, 0.052, -0.084, -0.004],
		[0.08, 0.054, -0.084, -0.02],
		[0.12, 0.054, -0.084, -0.036],
		[0.155, 0.049, -0.083, -0.047],
		[0.178, 0.037, -0.082, -0.055],
	]
	var rings: Array = [_r(-0.078, 0.0, 0.0, -0.064)]
	for q in prof:
		var bot: float = q[2]
		var top: float = q[3]
		# frente del anillo (-z local del loft) = abajo tras rotar
		rings.append(_rr(q[0], q[1], (top - bot) * 0.5, (top - bot) * 0.5, (top + bot) * 0.5, 2.6))
	rings.append(_r(0.189, 0.0, 0.0, -0.07))
	var cs := _c(C_DRESS_SHOE)
	var shoe_col := func(p: Vector3) -> Color:    # puntera algo más clara (cuero lustrado)
		return cs.lerp(cs * 1.22, smoothstep(0.08, 0.17, -p.z))
	var shoe_uv := func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25, 0.8 + 0.1 * p.x)
	_loft(_sole(), rings, 16, xf, shoe_col, shoe_uv)
	# Suela fina oscura (vira + suela) con la puntera apenas levantada
	var sole_rings := func(bot: float, top: float, grow: float, inset: float) -> Array:
		var out: Array = [_r(-0.08 + inset, 0.0, 0.0, 0.5 * (bot + top))]
		for q in [[-0.077, 0.032], [-0.067, 0.046], [-0.035, 0.051], [0.03, 0.054], [0.09, 0.058], [0.14, 0.056],
				[0.172, 0.045], [0.188, 0.028]]:
			var f: float = q[0]
			var lift := 0.008 * pow(clampf((f - 0.12) / 0.07, 0.0, 1.0), 2.0) + 0.002 * clampf((-0.05 - f) / 0.03, 0.0, 1.0)
			out.append(_rr(f, float(q[1]) + grow - inset, (top - bot) * 0.5, (top - bot) * 0.5, (top + bot) * 0.5 + lift, 5.0))
		out.append(_r(0.193 - inset, 0.0, 0.0, 0.5 * (bot + top) + 0.009))
		return out
	_loft(_sole(), sole_rings.call(-0.092, -0.081, 0.004, 0.0), 14, xf, _c(C_DRESS_SHOE * 0.62), func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25, clampf((-0.081 - p.y) / 0.011, 0.0, 1.0)))
	_loft(_sole(), sole_rings.call(-0.1, -0.091, 0.003, 0.002), 12, xf, _c(C_DRESS_SHOE * 0.42), func(p: Vector3, _uv: Vector2) -> Vector2:
		return Vector2(-p.z / 0.25, 0.4 + clampf((-0.091 - p.y) / 0.009, 0.0, 1.0) * 0.6))


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
		var out := 0.1 + 0.08 * g * m + 0.06 * idle + 0.03 * breath * idle   # R2 (68107): mangas gruesas, brazos algo abiertos
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
## Ojera (ref. 68107, ronda 2): degradado de color en la piel (_eye_shade) + párpado inferior blando en geometría.
## Queda en la malla de la cabeza (no se anima). (_bag_ring/_eye_rim quedan disponibles, ya sin uso aquí.)
func _clay_eye_bag(skin_m: Material, ex: float, _sx: float, ez: float) -> void:
	var c := _eye_center(ex, ez)
	var sk := SKIN_TONE
	# Ronda 2: la ojera es color de vértice de la piel (_eye_shade, llamado desde head_col); aquí solo queda
	# un párpado inferior blando: casquete fino pegado al globo que tapa su borde de abajo (sin aro de perfil).
	var rows: Array = [[0.0, 1.035], [0.5, 1.035], [0.85, 1.04], [0.97, 1.05], [1.04, 1.035], [1.08, 1.0]]
	var tilt := Basis(Vector3(1, 0, 0), -0.42)      # polo hacia atrás: por delante solo cubre ≈ 0.6 rad desde abajo
	var m := 24
	var P := PackedVector3Array()
	for r in rows:
		var ph: float = r[0]
		var k: float = r[1]
		for j in m:
			var th := TAU * float(j) / float(m)
			var u := tilt * Vector3(sin(ph) * sin(th), -cos(ph), -sin(ph) * cos(th))
			P.append(c + Vector3(EYE_R.x * u.x, EYE_R.y * u.y, EYE_R.z * u.z) * k)
	_grid(skin_m, P, rows.size(), m, Transform3D.IDENTITY, _c(Color(sk.r * 0.9, sk.g * 0.83, sk.b * 0.84)))


## Ojera (ref. 68107) como multiplicador del color de la piel de la cabeza (p en coordenadas sin escalar):
## degradado malva-gris alrededor del ojo, más oscuro bajo el ojo y en el lagrimal, que se aclara hacia la mejilla,
## y sombra rosada-malva sobre el párpado superior. Devuelve BLANCO lejos de los ojos.
func _eye_shade(p: Vector3) -> Color:
	if p.z > -0.03 or absf(p.y - EYE_Y) > 0.06:
		return Color.WHITE
	var out := Color.WHITE
	var keys_r := Vector2(EYE_R.x, EYE_R.y)
	for sx in [-1.0, 1.0]:
		var c := Vector2(0.034 * 1.12 * sx, EYE_Y - 0.001)
		var d := Vector2(p.x - c.x, p.y - c.y)
		var rn := Vector2(d.x / keys_r.x, d.y / keys_r.y).length()    # 1 = borde del globo
		var below := clampf(-d.y / keys_r.y, 0.0, 1.4)                  # 0 a la altura del centro … abajo
		var above := clampf(d.y / keys_r.y, 0.0, 1.6)
		var inner := clampf(-d.x * sx / keys_r.x, 0.0, 1.0)              # hacia el lagrimal
		# banda bajo el ojo: máxima justo debajo del borde, se apaga hacia la mejilla (≈ 0.7 R más abajo)
		var ring := exp(-pow(maxf(rn - 1.0, 0.0) / 0.34, 2.0)) * smoothstep(0.65, 1.0, rn)
		var outer := clampf((d.x * sx / keys_r.x - 0.6) / 0.6, 0.0, 1.0)      # se apaga hacia la sien
		var bag := ring * smoothstep(0.0, 0.55, below) * (1.0 + 0.35 * inner) * (1.0 - 0.6 * outer)
		# lagrimal: sombra en el ángulo interno
		var tear := exp(-(pow((d.x + sx * keys_r.x * 0.95) / 0.009, 2.0) + pow((d.y + 0.003) / 0.012, 2.0)))
		# párpado superior: velo rosado-malva entre el ojo y la ceja
		var lid := ring * smoothstep(0.0, 0.4, above) * (1.0 - smoothstep(1.2, 1.6, above))
		var k_bag := clampf(bag * 1.0 + tear * 0.6, 0.0, 1.0)
		out = out * Color(1.0, 1.0, 1.0).lerp(Color(0.6, 0.55, 0.5), k_bag)
		out = out * Color(1.0, 1.0, 1.0).lerp(Color(0.87, 0.77, 0.77), clampf(lid * 0.85, 0.0, 1.0))
	return out


## Arco de ojera alrededor de la parte baja del ojo (a ∈ [−amax, amax], 0 = abajo), a `off` del borde del globo.
## w = semiancho radial (se afina en las puntas), d = semigrosor; on_eye: se pega al globo (rollo), si no a la piel.
func _bag_ring(mat: Material, c: Vector3, keys: Array, amax: float, off: float, w: float, d: float, on_eye: bool, col: Color,
		a0 := 0.0) -> void:
	var path := PackedVector3Array()
	var ws: Array = []
	var n := 11
	for i in n:
		var t := float(i) / float(n - 1)
		var a := a0 + lerpf(-amax, amax, t)
		var rim := _eye_rim(c, a, keys)
		var p := rim + Vector3(sin(a) * off, -cos(a) * off, 0.0)
		p.z = (rim.z - 0.0014) if on_eye else minf(_head_z(p.x, p.y, keys) - d * 0.7, rim.z + 0.004)   # sin colas hacia la sien
		path.append(p)
		ws.append(lerpf(w * 0.3, w, pow(sin(PI * t), 0.6)))
	_tube(mat, path, ws, d, 8, Vector3(0, 0, -1), col)


## Punto del borde donde el globo (dirección a; 0 = abajo) entra en la piel de la cuenca.
func _eye_rim(c: Vector3, a: float, keys: Array) -> Vector3:
	var p := Vector3.ZERO
	for i in 14:
		var rho := 0.5 + 0.05 * float(i)
		p.x = c.x + sin(a) * EYE_R.x * rho
		p.y = c.y - cos(a) * EYE_R.y * rho
		var ze := c.z - EYE_R.z * sqrt(maxf(0.0, 1.0 - rho * rho))
		p.z = _head_z(p.x, p.y, keys)
		if ze >= p.z - 0.0005:
			return p
	return p


## Centro del globo ocular (hundido en la cuenca: sobresale menos que antes).
func _eye_center(ex: float, ez: float) -> Vector3:
	return Vector3(ex * 1.12, EYE_Y - 0.001, ez + 0.0068)   # ref. 68107: globo grande que asoma suave de perfil

## Radios del globo ocular. Ronda 2 (ref. 68107): más grande y redondo; y se divide entre CLAY_HEAD_SY (la cabeza
## se estira en y) para que se VEA redondo (≈ 0.059 de ancho, ≈ 3/4 de la distancia entre pupilas).
const EYE_R := Vector3(0.0293, 0.0293 / CLAY_HEAD_SY, 0.0215)
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
		1:   # neutro (ref. 68107): sonrisa suave y cerrada: línea curva hacia arriba, labio inferior rosado tenue, hoyuelos
			# Ronda 2: sonrisa cerrada AMPLIA (≈ 0.87 × distancia entre pupilas): línea fina rojo oscuro en "U" con las
			# comisuras subiendo y hundidas, y debajo una banda fina de labio inferior rosado (C_LIP).
			var sk := SKIN_TONE
			var crease := _c(Color(0.34, 0.2, 0.19))                            # línea de la boca (ref. ≈ #4A2420)
			var w := 0.033
			var line_y := func(x: float) -> float: return my - 0.0019 + 0.0078 * pow(absf(x) / w, 2.3)
			var cp := PackedVector3Array()
			var cra: Array = []
			var crb: Array = []
			for i in 15:
				var t := float(i) / 14.0
				var x := lerpf(-w, w, t)
				var y: float = line_y.call(x)
				cp.append(Vector3(x, y, _head_z(x, y, keys) + 0.0009))
				cra.append(0.0015)
				crb.append(lerpf(0.00045, 0.00095, pow(sin(t * PI), 0.5)))
			_tube(sm, cp, cra, crb, 6, Vector3(0, 1, 0), crease)
			var lp := PackedVector3Array()
			var lra: Array = []
			var lrb: Array = []
			for i in 11:
				var t := float(i) / 10.0
				var x := lerpf(-0.0255, 0.0255, t)
				var s := sin(t * PI)
				var y: float = line_y.call(x) - 0.0009 - 0.0021 * s
				lp.append(Vector3(x, y, _head_z(x, y, keys) + 0.0015 - 0.0009 * s))
				lra.append(0.002)
				lrb.append(0.0006 + 0.0019 * pow(s, 0.7))
			_tube(sm, lp, lra, lrb, 6, Vector3(0, 1, 0), _c(C_LIP))
			for sx in [-1.0, 1.0]:      # comisuras hundidas: pliegue corto y suave que sube desde la punta de la línea
				var dimple := PackedVector3Array()
				for i in 4:
					var u := float(i) / 3.0
					var dx: float = sx * (w + 0.0012 + 0.0016 * sin(u * PI))
					var dy := my + 0.0085 - 0.0085 * u
					dimple.append(Vector3(dx, dy, _head_z(dx, dy, keys) + 0.0004))
				_tube(sm, dimple, 0.0012, 0.0008, 5, Vector3(0, 0, -1), _c(Color(sk.r * 0.8, sk.g * 0.7, sk.b * 0.7)))
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
		var bo := Vector3(sx * 0.04, _brow_y(0.5), _head_z(sx * 0.04, _brow_y(0.5), keys) - 0.003)   # centro de la ceja
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


## Globo ocular (ref. 68107): esclerótica blanco roto SIN iris, pupila negra pequeña casi centrada y un brillo de cristal.
const C_CLAY_SCLERA := Color(0.585, 0.635, 0.645)   # albedo frío: la luz del preset lo calienta → blanco roto #BCBBB9 (medido)

func _eye_front(c: Vector3, off: Vector2) -> Vector3:     # punto de la superficie frontal del globo
	var q := 1.0 - pow(off.x / EYE_R.x, 2.0) - pow(off.y / EYE_R.y, 2.0)
	return c + Vector3(off.x, off.y, -EYE_R.z * sqrt(maxf(q, 0.0)))

func _geo_eyeball(c: Vector3, sx: float) -> void:
	var em := _eye()
	_ellip(em, c, EYE_R, _c(C_CLAY_SCLERA), Vector3.ZERO, 20, 12)
	var g := Vector2(-0.001 * sx, 0.0)                 # pupila centrada, mirando al frente (apenas hacia adentro)
	_ellip(em, _eye_front(c, g) + Vector3(0, 0, 0.0004), Vector3(0.0057, 0.0057 / CLAY_HEAD_SY, 0.0013), _c(GothicClayAdapter.PUPIL), Vector3.ZERO, 12, 4)
	_ellip(em, _eye_front(c, Vector2(0.0092, 0.0078)) + Vector3(0, 0, 0.0003), Vector3(0.0034, 0.0025, 0.0008),
		_c(Color(0.78, 0.78, 0.8)), Vector3(0, 0, 0.5), 8, 4)


## Párpado superior: casquete fino de piel malva que gira en el centro del ojo (rotation.x < 0 lo baja).
## Reposo (ref. 68107): ojo bien abierto. Casquete de 76° con el polo inclinado 0.35 rad hacia atrás: el borde
## queda a ≈ 56° de la vertical por delante (algo más bajo en las esquinas) y al cerrarse cubre todo el globo.
func _geo_lid(c: Vector3) -> void:
	var sm := _skin()
	var col := _c(Color(SKIN_TONE.r * 0.87, SKIN_TONE.g * 0.8, SKIN_TONE.b * 0.82))   # rosado-malva (ref. #A58582)
	var m := 24
	var rows: Array = [[0.0, 1.06], [0.4, 1.055], [0.8, 1.055], [1.09, 1.06], [1.2, 1.075], [1.27, 1.065], [1.32, 1.0]]
	# ronda 2: casquete 0.12 rad más atrás (ojo muy abierto: el borde frontal queda a ≈ 49° de la vertical)
	var tilt := Basis(Vector3(1, 0, 0), 0.47)
	var P := PackedVector3Array()
	for r in rows:
		var ph: float = r[0]
		var k: float = r[1]
		for j in m:
			var th := TAU * float(j) / float(m)
			var u := tilt * Vector3(sin(ph) * sin(th), cos(ph), -sin(ph) * cos(th))
			P.append(c + Vector3(EYE_R.x * u.x, EYE_R.y * u.y, EYE_R.z * u.z) * k)
	_grid(sm, P, rows.size(), m, Transform3D.IDENTITY, col)


## Ceja (ref. 68107): rollo grueso de plastilina casi negra en arco suave; extremo interior romo,
## exterior afinado y algo caído. Sigue la frente (pieza propia: sube, baja e inclina).
const C_BROW := Color(0.33, 0.32, 0.27)    # se ve casi negro neutro (#2A2929, medido: el material de pelo oscurece mucho)

func _brow_y(t: float) -> float:
	# ronda 2 (ref. 68107): más alta y en arco suave; el extremo exterior cae pasado el borde del ojo
	return EYE_Y + 0.046 + 0.0075 * sin(t * PI * 0.85) - 0.0165 * t * t

func _geo_brow(_ex: float, _ez: float, sx: float) -> void:
	var keys := _head_keys()
	var brow := PackedVector3Array()
	for i in 7:
		var t := float(i) / 6.0
		var bx: float = sx * lerpf(0.0115, 0.07, t)     # de encima del lagrimal a pasar el borde exterior del ojo
		var by := _brow_y(t)
		brow.append(Vector3(bx, by, _head_z(bx, by, keys) - 0.0018))
	# gruesa (semialto 0.0083 junto al entrecejo, sección algo cuadrada: extremo interior romo), afinada hacia fuera
	_tube(_hair(), brow, [0.0081, 0.0083, 0.008, 0.0072, 0.006, 0.0047, 0.0033],
		[0.0052, 0.0054, 0.0052, 0.0048, 0.0042, 0.0036, 0.0028], 10, Vector3(0, 0, -1), _c(C_BROW), true, 2.5)


## Cara por pasos (stop-motion). blink: 0 abierto, 1 entrecerrado, 2 cerrado.
## gaze: x = hacia +x de la cabeza, y = arriba (radianes, ±0.3 es mucho). brow_*: −1 baja … +1 sube.
func set_face(blink: int, gaze := Vector2.ZERO, brow_l := 0.0, brow_r := 0.0) -> void:
	if _pieces.is_empty():
		return
	var rx: float = [0.0, -0.9, -1.88][clampi(blink, 0, 2)]    # el párpado de reposo es más alto (ojo abierto)
	# el globo (ya escalado con CLAY_HEAD_S) es redondo en x-y y achatado en z: al girar, el casquete se encoge en su
	# y local (que queda hacia delante) y se estira en su z local (que queda vertical) para taparlo entero sin abultar.
	# (ronda 2: parte de CLAY_HEAD_S; antes perdía el estirado en y de la cabeza y el globo asomaba por encima)
	var bi := clampi(blink, 0, 2)
	var ls := CLAY_HEAD_S * Vector3([1.0, 1.04, 1.12][bi], [1.0, 0.88, 0.82][bi], [1.0, 1.2, 1.5][bi])
	for sfx in ["l", "r"]:
		var lid: Node3D = _pieces["lid_" + sfx]
		lid.rotation = Vector3(rx, 0.0, 0.0)
		lid.scale = ls
		(_pieces["eye_" + sfx] as Node3D).rotation = Vector3(gaze.y, -gaze.x, 0.0)
		var b: Node3D = _pieces["brow_" + sfx]
		var v: float = brow_l if sfx == "l" else brow_r
		b.position = (b.get_meta("base_pos") as Vector3) + Vector3(0.0, v * 0.007 * CLAY_HEAD_K, 0.0)
		b.rotation = Vector3(0.0, 0.0, v * 0.25 * (1.0 if sfx == "l" else -1.0))


## Orejas (R2, ref. 68107): centro a la altura entre ceja y punta de nariz, raíz justo detrás de la mandíbula.
const EAR_Y := 0.107      # centro de la oreja (sin escalar; la malla se estira ×CLAY_HEAD_SY)
const EAR_ZF := -0.011    # z del borde delantero (raíz) de la oreja
const EAR_OPEN := 27.0    # grados: la parte de atrás se separa del cráneo (de frente se ve de canto)
const EAR_TILT := 12.0    # grados: la parte de arriba se abre más que la de abajo (lóbulo pegado)


## x de la superficie del cráneo (anillos sin deformar) en la altura y y la profundidad z, lado +x.
static func _skull_x(keys: Array, y: float, z: float) -> float:
	var r := _ring_at(keys, y)
	var cz: float = r["cz"]
	var b: float = r["bf"] if z < cz else r["bb"]
	var n: float = r["n"]
	var t := clampf(absf(z - cz) / b, 0.0, 0.999)
	return float(r["cx"]) + float(r["a"]) * pow(1.0 - pow(t, n), 1.0 / n)


## Oreja de arcilla: concha, hélix, antihélix, trago y lóbulo, en un marco propio (U arriba, V atrás, N afuera)
## cuya raíz (borde delantero) está hundida 2 mm en la piel del cráneo; un "puente" de piel por detrás une la
## concha con la cabeza, así que no hay hueco desde ningún ángulo. ek = escala; sx = lado; y0 = centro.
func _clay_ear(skin_m: Material, keys: Array, sx: float, ek: float, skin: Color, y0: float) -> void:
	var sk := Color(skin.r, skin.g * 0.95, skin.b * 0.94)            # borde algo más rosado
	var pink := Color(skin.r * 0.86, skin.g * 0.66, skin.b * 0.67)   # interior rosado
	var hh := 0.0265 * ek        # semialto (con hélix y lóbulo: ≈ 0.06 de alto)
	var ww := 0.0172 * ek        # semifondo (a lo largo de la cabeza)
	var root := Vector3(sx * (_skull_x(keys, y0, EAR_ZF + 0.004) - 0.002), y0, EAR_ZF)
	var be := deg_to_rad(EAR_TILT)
	var al := deg_to_rad(EAR_OPEN)
	var U := Vector3(sx * sin(be), cos(be), 0.0)
	var V := Vector3(sx * sin(al), 0.0, cos(al))
	V = (V - U * V.dot(U)).normalized()
	var N := U.cross(V) * sx                     # hacia afuera de la cabeza
	var rot := Basis(N, U, N.cross(U)).get_euler()
	var E := func(u: float, v: float, w: float) -> Vector3:
		return root + U * u + V * v + N * w
	var th := 0.0042 * ek        # semigrosor de la concha
	var face := 0.0022 + th      # cara exterior de la concha (w)
	# puente de piel: une la parte de atrás de la oreja con el cráneo (se ve de espalda y de frente)
	_ellip(skin_m, E.call(-0.04 * hh, 0.9 * ww, -0.0075), Vector3(0.0108, 0.82 * hh, 0.88 * ww), skin.lerp(sk, 0.6), rot, 12, 7)
	# concha (lámina principal)
	_ellip(skin_m, E.call(0.05 * hh, ww, 0.0022), Vector3(th, hh, ww), sk, rot, 14, 8)
	# hélix: aro que sube por delante, rodea la parte alta y cae por detrás hasta el lóbulo
	var helix := PackedVector3Array()
	for i in 10:
		var t := lerpf(deg_to_rad(158.0), deg_to_rad(-58.0), float(i) / 9.0)
		helix.append(E.call(0.05 * hh + 0.9 * hh * sin(t), ww + 0.86 * ww * cos(t), face - 0.0005))
	_tube(skin_m, helix, 0.0042 * ek, 0.0034 * ek, 6, N, sk)
	# antihélix: arco interior más corto, rosado claro
	var anti := PackedVector3Array()
	for i in 6:
		var t := lerpf(deg_to_rad(150.0), deg_to_rad(-25.0), float(i) / 5.0)
		anti.append(E.call(0.12 * hh + 0.5 * hh * sin(t), 1.08 * ww + 0.42 * ww * cos(t), face - 0.0012))
	_tube(skin_m, anti, 0.0027 * ek, 0.0024 * ek, 5, N, sk.lerp(pink, 0.4))
	# concha: hueco rosado al centro
	_ellip(skin_m, E.call(-0.12 * hh, 0.8 * ww, face - 0.0016), Vector3(0.0022, 0.36 * hh, 0.42 * ww), sk.lerp(pink, 0.7), rot, 8, 5)
	# trago: bultito delante de la concha
	_ellip(skin_m, E.call(-0.2 * hh, 0.2 * ww, face - 0.0015), Vector3(0.0035, 0.2 * hh, 0.22 * ww), sk, rot, 8, 5)
	# lóbulo: abajo, pegado a la cara
	_ellip(skin_m, E.call(-0.8 * hh, 0.85 * ww, 0.0018), Vector3(0.0055, 0.33 * hh, 0.6 * ww), sk, rot, 8, 5)


## Bufanda (referencia 68107). En la malla del pecho queda la vuelta gruesa al cuello (sin nudo visible); las dos
## colas son piezas con cadena de pivotes (_build_scarf_tails) que cuelgan por delante y reaccionan al movimiento.
## Color que se VE en la referencia: verde hierba ≈ #3E7F3A, blanco crema ≈ #D0CDBC (rayas regulares).
## Los albedos se calibran midiendo capturas (el render los cambia): ver ANDRO_CONTEXTO §5.
const SCARF_G := Color(0.355, 0.462, 0.335)
const SCARF_W := Color(0.595, 0.615, 0.58)
const SCARF_RUST := Color(0.4, 0.25, 0.18)    # solo la variante corta/rota
const STRIPE_W := [0.026, 0.019]     # rayas regulares (unidades del pecho, a lo largo de la bufanda): verde, blanco
const SCARF_VARIANTS := ["clasica", "torcida", "corta_rota", "flecos_largos"]

## Color de la raya en la posición u (distancia a lo largo de la bufanda, unidades del pecho).
static func _stripe_col(u: float, p: Vector3) -> Color:
	var per := float(STRIPE_W[0]) + float(STRIPE_W[1])
	var white := fposmod(u, per) >= float(STRIPE_W[0])
	var jit := 0.95 + 0.1 * fposmod(sin(p.x * 913.0 + p.y * 571.0 + p.z * 337.0) * 43758.5, 1.0)
	var c := SCARF_W if white else SCARF_G
	return _c(Color(c.r * jit, c.g * jit, c.b * jit))


## Parámetros t (0..1) para un tramo de bufanda que va de u0 a u0 + length: cada borde de raya lleva dos filas
## de vértices muy juntas (±eps) para que el cambio de color sea nítido, más una fila a mitad de cada raya.
static func _stripe_ts(u0: float, length: float, eps := 0.0007) -> PackedFloat32Array:
	var per := float(STRIPE_W[0]) + float(STRIPE_W[1])
	var bounds: Array[float] = []
	var k := floorf(u0 / per) - 1.0
	while k * per < u0 + length + per:
		for b in [k * per, k * per + float(STRIPE_W[0])]:
			var t := (float(b) - u0) / length
			if t > eps / length * 2.0 and t < 1.0 - eps / length * 2.0:
				bounds.append(t)
		k += 1.0
	var ts := PackedFloat32Array([0.0])
	var e := eps / length
	for t in bounds:
		var last := ts[ts.size() - 1]
		ts.append((last + t - e) * 0.5)
		ts.append(t - e)
		ts.append(t + e)
	ts.append((ts[ts.size() - 1] + 1.0) * 0.5)
	ts.append(1.0)
	return ts


func _clay_scarf(_keys: Array) -> void:
	var km := _knit()
	var per := float(STRIPE_W[0]) + float(STRIPE_W[1])
	var cz := 0.004
	# Vuelta gruesa y abultada (rollo a rayas, se ve también de espalda): alta atrás, cae hacia el pecho.
	# La segunda vuelta es solo el arco delantero, pegado debajo (bulto de lana doble); sus puntas entran en la primera.
	# Las rayas cruzan el rollo; filas de vértices dobles en cada borde para que no se difuminen.
	# [rx, rz, y0, inclinación, caída delante, radio radial, radio vertical, fase, arco desde, arco hasta]
	for r in [[0.1, 0.094, 0.274, 0.012, 0.016, 0.039, 0.045, 0.0, 0.0, 1.0],
			[0.106, 0.1, 0.25, 0.012, 0.034, 0.033, 0.034, 0.4, 0.28, 0.72]]:
		var rx: float = r[0]
		var rz: float = r[1]
		var y0: float = r[2]
		var tilt: float = r[3]
		var droop: float = r[4]
		var circ := TAU * sqrt((rx * rx + rz * rz) * 0.5)
		var L := float(maxi(roundi(circ / per), 1)) * per
		var ph: float = float(r[7]) * per
		var f0: float = r[8]
		var f1: float = r[9]
		var ring := PackedVector3Array()
		for t in _stripe_ts(ph + f0 * L, (f1 - f0) * L, 0.0012):
			var a := TAU * lerpf(f0, f1, t)
			ring.append(Vector3(sin(a) * rx, y0 + tilt * cos(a) - droop * maxf(-cos(a), 0.0), cos(a) * rz + cz))
		_tube(km, ring, r[5], r[6], 12, Vector3(0, 1, 0), func(p: Vector3) -> Color:
			return _stripe_col(fposmod(atan2(p.x / rx, (p.z - cz) / rz) / TAU, 1.0) * L + ph, p), f1 - f0 < 0.99)


## Puntos de articulación de una cola (espacio del pecho). tail 0 = larga (+X: a la izquierda de quien mira),
## 1 = un poco más corta (−X). Salen de debajo de la vuelta del cuello y bajan casi paralelas hasta la cintura.
func _scarf_joints(keys: Array, variant: int, tail: int) -> PackedVector3Array:
	var short := variant == 2
	var y_end: float = [-0.137, -0.117][tail] if not short else [-0.05, -0.025][tail]
	var x0: float = [0.048, -0.046][tail]
	var x1: float = [0.064, -0.06][tail]
	var nseg: int = [4, 3][tail]
	return _surf_path(keys, Vector2(x0, 0.25), Vector2(x1, y_end), true, 0.03, nseg + 1)


## Una pieza (segmento) de cola. seg 0..n-1; el último lleva los flecos.
func _geo_scarf_seg(variant: int, tail: int, seg: int) -> void:
	var km := _knit()
	var keys := _blazer_rings()
	var J := _scarf_joints(keys, variant, tail)
	var n := J.size() - 1
	# longitud de arco: las rayas se miden a lo largo de la cola; la fase deja una raya verde justo encima de los flecos
	var cum := PackedFloat32Array([0.0])
	for i in n:
		cum.append(cum[i] + J[i].distance_to(J[i + 1]))
	var l_tot := cum[n]
	var u_off := float(STRIPE_W[0]) * 0.5 - l_tot
	var a := J[seg]
	var b := J[seg + 1]
	var dirv := (b - a).normalized()
	var s0 := float(seg) / float(n)
	var s1 := float(seg + 1) / float(n)
	var up := Vector3(0, 0, -1)
	if variant == 1:    # torcida: la tira gira sobre su eje
		up = up.rotated(dirv, 0.7 * float(seg) * (1.0 if tail == 0 else -1.0))
	var wd := func(s: float) -> float: return lerpf(0.047, 0.044, s)
	var ext0 := 0.012 if seg == 0 else 0.004    # arriba se mete bajo la vuelta del cuello; entre piezas, solape
	var ext1 := 0.0 if seg == n - 1 else 0.004
	var la := cum[seg] - ext0
	var lb := cum[seg + 1] + ext1
	var path := PackedVector3Array()
	var ra: Array = []
	var rb: Array = []
	for t in _stripe_ts(la + u_off, lb - la):
		var s := lerpf(la, lb, t)
		path.append(a + dirv * (s - cum[seg]))
		ra.append(wd.call(lerpf(s0, s1, clampf((s - cum[seg]) / maxf(cum[seg + 1] - cum[seg], 1e-4), 0.0, 1.0))))
		rb.append(0.011)
	var col := func(p: Vector3) -> Color:
		var s := cum[seg] + (p - a).dot(dirv)
		var c := _stripe_col(s + u_off, p)
		if variant == 2:    # corta/rota: algo de desgaste en la punta
			c = c.lerp(_c(SCARF_RUST), smoothstep(0.6, 1.0, s / l_tot) * 0.5)
		return c
	_tube(km, path, ra, rb, 8, up, col, true, 3.0)
	if seg == n - 1:    # flecos: verdes y algunos blancos, gruesos y bien visibles
		var nf := 10 if variant == 3 else (4 if variant == 2 else 8)
		var fl := 0.085 if variant == 3 else (0.02 if variant == 2 else 0.062)    # ref. 68107: flecos largos
		var half: float = float(wd.call(1.0)) * 0.86
		var side := dirv.cross(up).normalized()
		for f in nf:
			var fo := b + side * lerpf(-half, half, float(f) / float(maxi(nf - 1, 1)))
			var len_f := fl * (0.85 + 0.25 * fposmod(sin(float(f) * 12.9898 + float(tail) * 4.0) * 43758.5, 1.0))
			var fc := _c(SCARF_W if f % 2 == 1 else SCARF_G)
			if variant == 2:
				fc = fc.lerp(_c(SCARF_RUST), 0.4)
			_tube(km, PackedVector3Array([fo - dirv * 0.006, fo + dirv * len_f + side * 0.002 * sin(float(f) * 2.3)
				+ Vector3(0, 0, -0.003)]), 0.0052, 0.0048, 5, up, fc)


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
	# R2 (68107): tubo ancho y recto que se abre un poco hacia el dobladillo, algo más largo (hem ≈ 0.62 m)
	[0.05, 0.16, 0.11, 0.111],        # dentro del saco
	[0.022, 0.18, 0.124, 0.125],      # costura de cintura: el faldón monta por fuera del saco
	[0.0, 0.181, 0.124, 0.125],
	[-0.1, 0.186, 0.124, 0.127],
	[-0.2, 0.192, 0.126, 0.131],
	[-0.29, 0.198, 0.128, 0.134],
	[-0.33, 0.2, 0.128, 0.134],
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
	var k := 1.02 if sx > 0.0 else 1.0
	var a0 := 0.42                                # F9 (68107): abrigo abierto al frente (se ve el pantalón)
	var a1 := PI + 0.03 if sx > 0.0 else PI - 0.01    # abertura trasera (F9: cerrada en reposo, la derecha monta)
	var K := 20
	var th := 0.008
	var P := PackedVector3Array()
	var rows: Array = [SKIRT_ROWS[0]] + SKIRT_ROWS + [SKIRT_ROWS[SKIRT_ROWS.size() - 1]]
	# R2: pliegues verticales suaves de arcilla que crecen hacia el dobladillo (misma onda por fuera y por dentro)
	var fold := func(q: Vector3, ang: float) -> Vector3:
		var f := 0.0035 * sin(ang * 7.0 + 0.6 * sx) * smoothstep(0.0, -0.3, q.y)
		return q + Vector3(q.x, 0.0, q.z).normalized() * f
	for i in rows.size():
		var cap := i == 0 or i == rows.size() - 1
		for j in K:
			var ang := lerpf(a0, a1, float(j) / float(K - 1))
			P.append(fold.call(_skirt_pt(rows[i], ang, sx, th * 0.5 if cap else 0.0, k), ang))
		for j in K:
			var ang := lerpf(a1, a0, float(j) / float(K - 1))
			P.append(fold.call(_skirt_pt(rows[i], ang, sx, th * 0.5 if cap else th, k), ang))
	var hem_y: float = float(SKIRT_ROWS[SKIRT_ROWS.size() - 1][0])
	_grid(tw, P, rows.size(), K * 2, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return cs.lerp(cl, 0.5 * smoothstep(hem_y + 0.03, hem_y, p.y)))   # dobladillo gastado
	# R2 (68107): bolsillo con solapa a la altura de la cadera, cerca del costado: concha pegada al faldón,
	# más separada abajo (el canto inferior hace sombra)
	var row_at := func(y: float) -> Array:
		for ri in SKIRT_ROWS.size() - 1:
			var r0: Array = SKIRT_ROWS[ri]
			var r1: Array = SKIRT_ROWS[ri + 1]
			if y <= float(r0[0]) and y >= float(r1[0]):
				var t: float = (float(r0[0]) - y) / (float(r0[0]) - float(r1[0]))
				return [y, lerpf(r0[1], r1[1], t), lerpf(r0[2], r1[2], t), lerpf(r0[3], r1[3], t)]
		return SKIRT_ROWS[3]
	var y_p := -0.085
	var fys := [y_p + 0.014, y_p + 0.002, y_p - 0.01, y_p - 0.02]
	var NCp := 7
	var FP := PackedVector3Array()
	for i in fys.size() + 2:
		var ii := clampi(i - 1, 0, fys.size() - 1)
		var cap := i == 0 or i == fys.size() + 1
		var rp: Array = row_at.call(float(fys[ii]))
		var off := lerpf(0.003, 0.0085, float(ii) / float(fys.size() - 1))
		for j in NCp:
			var f := float(j) / float(NCp - 1)
			var ang := lerpf(0.7, 1.3, f if sx > 0.0 else 1.0 - f)
			FP.append(fold.call(_skirt_pt(rp, ang, sx, -(0.003 + off) * 0.5 if cap else -off, k), ang))
		for j in NCp:
			var f := 1.0 - float(j) / float(NCp - 1)
			var ang := lerpf(0.7, 1.3, f if sx > 0.0 else 1.0 - f)
			FP.append(fold.call(_skirt_pt(rp, ang, sx, -(0.003 + off) * 0.5 if cap else -0.001, k), ang))
	_grid(tw, FP, fys.size() + 2, NCp * 2, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		return cs.lerp(cl, 0.6 * smoothstep(y_p - 0.008, y_p - 0.02, p.y)))   # canto inferior más oscuro
	if sx > 0.0:    # R2: canto de la abertura trasera (el faldón derecho monta sobre el izquierdo)
		var vp := PackedVector3Array()
		for i in 6:
			var rv: Array = row_at.call(lerpf(0.0, hem_y + 0.002, float(i) / 5.0))
			vp.append(fold.call(_skirt_pt(rv, a1 - 0.012, sx, -0.0015, k), a1 - 0.012))
		_tube(tw, vp, 0.003, 0.0018, 5, Vector3(0, 0, 1), cs.darkened(0.16))


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
	if not SATCHEL_ON:    # F9 (68107): sin vivo ocre; el bolsillo de pecho es el ribete oscuro de _geo_chest
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


## Cabello de la referencia 68107 (12-nov-2026): un BLOQUE de arcilla casi negra y mate en tupé/flat-top alto.
## Arriba 5 rollos de bordes redondeados alineados de lado a lado (de frente: ladrillos con surcos, en dos pisos:
## bloque alto que sobresale + bloque bajo sobre la frente) que corren de la frente a la coronilla; por detrás bajan
## 7 franjas verticales hasta la nuca. Lados cortos pegados al cráneo y peinados hacia atrás (surcos de peine),
## patilla corta delante de la oreja; la oreja queda libre. Línea de pelo recta y alta: no tapa las cejas. Sin púas.
## Variantes: 0 clásico (la referencia), 1 viento (rollos echados hacia atrás), 2 mojado (aplastado y más oscuro),
## 3 caótico (rollos desalineados). Se ve ≈ #1E1C1C–#3A3838: el albedo HAIR_BLOCK se calibra midiendo (§5).
const HAIR_VARIANTS := ["clasico", "viento", "mojado", "caotico"]
const HAIR_ORIGIN := Vector3(0.0, 0.125, 0.0)    # el pelo gira/oscila alrededor de aquí
const HAIR_BLOCK := Color(0.4, 0.4, 0.365)       # albedo (G > R se vuelve oliva: clay_grade satura los verdes)

func _geo_hair(variant: int) -> void:
	var hair_m := _hair()
	var keys := _head_keys()
	var top_y: float = float(keys[keys.size() - 1]["y"])
	var h_k := 1.0       # altura del tupé (1 = referencia)
	var lean := 0.0      # rollos echados hacia atrás (viento)
	var jit := 0.0       # desorden (caótico)
	var dk := 1.0        # oscurecido (mojado)
	match variant:
		1:
			lean = 0.6
			h_k = 0.85
		2:
			h_k = 0.45
			dk = 0.8
		3:
			jit = 1.0
			h_k = 1.06
	var rng := RandomNumberGenerator.new()
	rng.seed = 68107 + variant * 101
	var base := HAIR_BLOCK * dk
	# ¿p está dentro del cráneo? (mismos anillos que _geo_head; arriba cierra en un casquete de 4 mm)
	var inside := func(p: Vector3) -> bool:
		if p.y < 0.0 or p.y > top_y + 0.004:
			return false
		var r := _ring_at(keys, minf(p.y, top_y))
		var sh := 1.0 - maxf(p.y - top_y, 0.0) / 0.004
		var cz: float = r["cz"]
		var a: float = float(r["a"]) * sh
		var b: float = (float(r["bf"]) if p.z < cz else float(r["bb"])) * sh
		if a < 1e-5 or b < 1e-5:
			return false
		var n: float = r["n"]
		return pow(absf(p.x - float(r["cx"])) / a, n) + pow(absf(p.z - cz) / b, n) <= 1.0
	# distancia desde c (dentro del cráneo) hasta su superficie en la dirección d
	var skull := func(c: Vector3, d: Vector3) -> float:
		var lo := 0.0
		var hi := 0.2
		for it in 15:
			var m := (lo + hi) * 0.5
			if inside.call(c + d * m):
				lo = m
			else:
				hi = m
		return lo
	var C0 := Vector3(0.0, 0.14, 0.005)
	# dirección desde C0: phi 0 = frente (−z), +PI/2 = derecha (+x); e = elevación
	var dir := func(phi: float, e: float) -> Vector3:
		return Vector3(sin(phi) * cos(e), sin(e), -cos(phi) * cos(e))
	# elevación a la que el cráneo, en el ángulo phi, está a la altura y
	var at_y := func(phi: float, y: float) -> float:
		var lo := -1.4
		var hi := PI * 0.5
		for it in 15:
			var m := (lo + hi) * 0.5
			var d: Vector3 = dir.call(phi, m)
			if (C0 + d * float(skull.call(C0, d))).y < y:
				lo = m
			else:
				hi = m
		return lo
	# línea de pelo: recta y alta en la frente, sube sobre la oreja, baja por detrás hasta la nuca
	var hairline := func(phi: float) -> float:
		var t := absf(rad_to_deg(wrapf(phi, -PI, PI)))
		var KP := [[0.0, 0.194], [40.0, 0.19], [58.0, 0.18], [70.0, 0.17], [110.0, 0.168], [121.0, 0.115],
			[138.0, 0.066], [160.0, 0.046], [180.0, 0.04]]
		for k in KP.size() - 1:
			if t <= float(KP[k + 1][0]):
				var u := (t - float(KP[k][0])) / (float(KP[k + 1][0]) - float(KP[k][0]))
				return lerpf(KP[k][1], KP[k + 1][1], smoothstep(0.0, 1.0, u))
		return 0.04

	# 1) Casquete pegado al cráneo por encima de la línea de pelo: bajo rollos y franjas no queda piel.
	#    La última fila se hunde en la piel: canto de arcilla limpio.
	# grosor del casquete: fino en la línea de pelo; en los lados sube hasta el ancho de los rollos (sin escalón)
	var shell_off := func(phi: float, ys: float) -> float:
		var a := absf(rad_to_deg(wrapf(phi, -PI, PI)))
		var sf := smoothstep(30.0, 62.0, a) * (1.0 - smoothstep(105.0, 140.0, a))
		return 0.0075 + 0.013 * sf * smoothstep(0.165, 0.215, ys)
	var M := 48
	var NR := 14
	var P := PackedVector3Array()
	P.resize((NR + 1) * M)
	for j in M:
		var phi := TAU * float(j) / float(M)
		var e0: float = at_y.call(phi, hairline.call(phi))
		for i in NR + 1:
			var e := lerpf(PI * 0.5, e0, float(mini(i, NR - 1)) / float(NR - 1))
			var d: Vector3 = dir.call(phi, e)
			var q := C0 + d * float(skull.call(C0, d))
			P[i * M + j] = q + d * (float(shell_off.call(phi, q.y)) if i < NR else -0.002)
	var hcol := _c(base)
	_grid(hair_m, P, NR + 1, M, Transform3D.IDENTITY, func(p: Vector3) -> Color:
		var g := 0.8 + 0.14 * (0.5 + 0.5 * sin(p.y * 820.0 - absf(p.z) * 90.0))   # surcos de peine hacia atrás
		return Color(hcol.r * g, hcol.g * g, hcol.b * g))

	# 2) Rollos del tupé (ref. 68107, ronda 2): 5 de la MISMA altura que van de la frente a la NUCA, en planos casi
	#    verticales. De perfil siguen la silueta redondeada medida en perfil_cabeza.jpg (sube desde la frente, se curva
	#    sobre la coronilla y baja lisa por la nuca); hacia los lados la silueta se encoge en z como la planta del
	#    cráneo: el frente sigue la curva de la frente (sin alero) y por detrás el bloque queda ancho y redondo.
	#    Tres piezas por rollo: piso bajo sobre la frente, rollo alto hasta la coronilla y franja de la nuca que
	#    termina redondeada sobre el cuello. En las caras de fuera, surcos de peine paralelos de adelante hacia atrás.
	# silueta de perfil: radio desde (y 0.14, z 0.005) por ángulo psi (grados: 0 frente, 90 arriba, 180 atrás)
	var RP := [[10.0, 0.098], [29.0, 0.106], [34.0, 0.12], [40.0, 0.134], [48.0, 0.141], [60.0, 0.147],
		[75.0, 0.146], [90.0, 0.137], [108.0, 0.134], [128.0, 0.138], [148.0, 0.139], [162.0, 0.135],
		[182.0, 0.122], [205.0, 0.114], [232.0, 0.1], [262.0, 0.09]]
	var rp := func(psd: float) -> float:
		for k in RP.size() - 1:
			if psd <= float(RP[k + 1][0]):
				var u := clampf((psd - float(RP[k][0])) / (float(RP[k + 1][0]) - float(RP[k][0])), 0.0, 1.0)
				return lerpf(RP[k][1], RP[k + 1][1], smoothstep(0.0, 1.0, u))
		return 0.1
	# planta: cuánto se encoge la silueta en z a la distancia x del centro (delante más que detrás)
	var plan := func(x: float, front: bool) -> float:
		var t := minf(absf(x) / (0.08 if front else 0.11), 0.98)
		var n := 2.0
		return pow(1.0 - pow(t, n), 1.0 / n)
	# índices de a a b (incluidos) cada st
	var idx := func(a: int, b: int, st: int) -> Array:
		var out: Array = []
		var k := a
		while k < b:
			out.append(k)
			k += st
		out.append(b)
		return out
	var phi_of := func(q: Vector3) -> float:
		return atan2(q.x - C0.x, -(q.z - C0.z))
	var xs := [-0.068, -0.034, 0.0, 0.034, 0.068]
	var bw := 0.0162     # semiancho de cada rollo: el bloque llega al ancho de la cabeza en las sienes
	if variant == 3:
		xs += [-0.017, 0.05]      # caótico: dos rollos de más, montados y torcidos
	var hz := Vector3(0, 0, 1)
	var NPS := 126          # muestras de psi cada 2°, de 10° a 260°
	# ancho del bloque según la altura: máximo en las sienes, algo menos arriba y se cierra en U hacia la nuca
	var wy := func(y: float) -> float:
		return 1.0 - 0.05 * smoothstep(0.24, 0.3, y) - 0.28 * (1.0 - smoothstep(0.02, 0.13, y))
	for i in xs.size():
		var x0: float = xs[i] + jit * rng.randf_range(-0.007, 0.007)
		var side := minf(absf(x0) / 0.068, 1.0)
		var beta := signf(x0) * 0.05 * side + jit * rng.randf_range(-0.2, 0.2)
		var V := Vector3(sin(beta), cos(beta), 0.0)
		var up := V.cross(hz).normalized()
		var C := Vector3(x0 - 0.1 * tan(beta), 0.14, 0.005)
		var rk := 1.0 + jit * rng.randf_range(-0.07, 0.05)
		var bc := base * (0.93 + 0.1 * rng.randf())
		# muestras: centro del rollo, semigrosor radial, dirección y radios interior/exterior desde C
		var mids := PackedVector3Array()
		var half: Array = []
		var dirs: Array = []
		var rins: Array = []
		var routs: Array = []
		for k in NPS:
			var psd := 10.0 + 2.0 * float(k)
			var psi := deg_to_rad(psd)
			var R: float = float(rp.call(psd)) * rk * (1.0 - 0.03 * side * side)    # los de fuera, un pelo más bajos
			var y := 0.14 + R * sin(psi)
			var x: float = x0 * float(wy.call(y)) + (y - 0.24) * tan(beta)
			var c := cos(psi)
			var p := Vector3(x, y, 0.005 - R * c * float(plan.call(x, c > 0.0)))
			var d := (p - C).normalized()
			var ri: float = skull.call(C, d)
			var ro := ri + maxf(((p - C).length() - ri) * h_k, 0.009)
			var rin := ri - 0.006
			var m := C + d * (ro + rin) * 0.5
			m.z += lean * maxf(m.y - 0.19, 0.0)
			mids.append(m)
			half.append((ro - rin) * 0.5)
			dirs.append(d)
			rins.append(rin)
			routs.append(ro)
		# tramo: de la línea de pelo de la frente a la de la nuca (los de fuera terminan detrás de la oreja)
		var k0 := 0
		while k0 < NPS - 8 and mids[k0].y < float(hairline.call(phi_of.call(mids[k0]))) + 0.006:
			k0 += 1
		var k3 := k0 + 6
		while k3 < NPS - 1 and (k3 < 55 or mids[k3 + 1].y > float(hairline.call(phi_of.call(mids[k3 + 1]))) + 0.004):
			k3 += 1
		# pliegue entre el piso bajo y el rollo alto (≈ 30 % de la cara frontal); relativo a la altura del rollo para
		# que la variante aplastada (mojado) no convierta todo en piso bajo
		var ymax := 0.0
		for k in range(k0, k3):
			ymax = maxf(ymax, mids[k].y)
		var yct: float = lerpf(mids[k0].y, ymax, 0.58)
		var k1 := k0 + 1
		while k1 < mini(k0 + 12, k3 - 6) and mids[k1].y < yct:
			k1 += 1
		var k2 := clampi(74 + int(jit * rng.randf_range(-4.0, 3.0)), k1 + 3, k3 - 2)    # coronilla (≈ 158°)
		var cc := _c(bc)
		var cl := _c(bc * 0.88)
		var cb := _c(bc * 0.95)
		var yc: float = mids[k1].y
		var yb: float = mids[k2].y
		var bwq := bw
		var x0q := x0
		var tb := tan(beta)
		# surcos: las caras laterales de cada rollo se oscurecen (sombra entre rollos de la referencia)
		var edge := func(p: Vector3, w: float) -> float:
			var wk: float = wy.call(p.y)
			var dx: float = p.x - x0q * wk - (p.y - 0.24) * tb
			if absf(x0q) > 0.05 and dx * x0q > 0.0:
				return 0.86    # cara de fuera de los rollos laterales: es el lado del bloque, no un surco (le da la luz)
			return 1.0 - 0.42 * smoothstep(0.55, 1.0, absf(dx) / (w * wk))
		var low := PackedVector3Array()
		var low_a: Array = []
		var low_b: Array = []
		for k in range(k0, k1 + 2):
			low.append(mids[k])
			low_a.append(float(half[k]) - 0.004)
			low_b.append(bw * 0.93 * float(wy.call(mids[k].y)))
		_tube(hair_m, low, low_a, low_b, 16, up, func(p: Vector3) -> Color:
			var g: float = float(edge.call(p, bwq * 0.93)) * (1.0 - 0.3 * smoothstep(yc - 0.012, yc, p.y))
			return Color(cl.r * g, cl.g * g, cl.b * g), true, 4.0)
		var hi := PackedVector3Array()
		var hi_a: Array = []
		var hi_b: Array = []
		for k in idx.call(k1, k2 + 1, 3):
			var u := float(k - k1) / float(k2 + 1 - k1)
			hi.append(mids[k])
			hi_a.append(float(half[k]) * (1.0 - 0.2 * smoothstep(0.8, 1.0, u)) + 0.002 * (1.0 - smoothstep(0.0, 0.25, u)))
			hi_b.append(bw * float(wy.call(mids[k].y)))
		_tube(hair_m, hi, hi_a, hi_b, 16, up, func(p: Vector3) -> Color:
			var g: float = float(edge.call(p, bwq)) * (1.0 - 0.16 * smoothstep(0.25, 0.28, p.y))   # tapa: le da la luz
			return Color(cc.r * g, cc.g * g, cc.b * g), true, 4.0)
		var bk := PackedVector3Array()
		var bk_a: Array = []
		var bk_b: Array = []
		for k in idx.call(k2 - 1, k3, 3):
			var u := float(k - k2 + 1) / float(k3 - k2 + 1)
			bk.append(mids[k])
			bk_a.append(float(half[k]) - 0.002 + 0.002 * smoothstep(0.8, 1.0, u))
			bk_b.append(bw * 0.96 * float(wy.call(mids[k].y)) * (1.0 - 0.25 * smoothstep(0.75, 1.0, u)))   # punta redonda
		_tube(hair_m, bk, bk_a, bk_b, 16, up, func(p: Vector3) -> Color:
			var g: float = float(edge.call(p, bwq * 0.96)) * (1.0 - 0.35 * smoothstep(yb - 0.014, yb, p.y))
			return Color(cb.r * g, cb.g * g, cb.b * g), true, 4.0)
		# surcos de peine en la cara de fuera de los rollos laterales (lo que se ve de perfil)
		if absf(x0) > 0.05 and variant != 2:
			var sg := signf(x0)
			for f in [0.28, 0.46, 0.64, 0.8]:
				var off: float = bw * pow(1.0 - pow(absf(2.0 * f - 1.0), 4.0), 0.25) - 0.0004
				var line := PackedVector3Array()
				for k in idx.call(k0 + 2, k3 - 1, 3):
					var q: Vector3 = C + (dirs[k] as Vector3) * lerpf(float(rins[k]), float(routs[k]), f)
					q += up * sg * off * float(wy.call(q.y))
					q.z += lean * maxf(q.y - 0.19, 0.0)
					line.append(q)
				_tube(hair_m, line, 0.0011, 0.0009, 4, up * sg, _c(bc * 0.55), true)

	# 4) Lados: cordones peinados hacia atrás (surcos de peine) y patilla corta delante de la oreja
	for sx in [-1.0, 1.0]:
		for k in (1 if variant == 2 else 3):     # mojado: lados lisos, casi sin surcos
			var y0 := 0.176 + 0.014 * float(k)
			var path := PackedVector3Array()
			for m in 6:
				var u := float(m) / 5.0
				var phi: float = sx * deg_to_rad(lerpf(64.0 + 4.0 * k, 128.0 - 6.0 * k, u))
				var e: float = at_y.call(phi, y0 + 0.006 * sin(u * PI) - 0.012 * u)
				var d: Vector3 = dir.call(phi, e)
				var q := C0 + d * float(skull.call(C0, d))
				path.append(q + d * (float(shell_off.call(phi, q.y)) - 0.0005))
			_tube(hair_m, path, [0.002, 0.005, 0.006, 0.006, 0.005, 0.002], [0.0012, 0.0025, 0.0028, 0.0028, 0.0025, 0.0012],
				6, Vector3(sx, 0, 0), _c(base * 0.95), true)
		var sb := PackedVector3Array()
		for m in 4:
			var u := float(m) / 3.0
			var phi: float = sx * deg_to_rad(77.0 + 2.0 * u)     # pegada delante de la oreja
			var e: float = at_y.call(phi, lerpf(0.172, 0.142, u))
			var d: Vector3 = dir.call(phi, e)
			sb.append(C0 + d * (float(skull.call(C0, d)) - 0.0005))     # integración: patilla plana y hundida en la piel
		_tube(hair_m, sb, [0.009, 0.0085, 0.007, 0.004], [0.0022, 0.002, 0.0018, 0.0012], 6, Vector3(sx, 0, 0),
			_c(base * 0.85), true, 3.0)


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

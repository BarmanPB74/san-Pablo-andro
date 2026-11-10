class_name Shopfronts
extends RefCounted
## Locales comerciales del primer piso (F2-07). Ref. foto 1: café con fachada de vidrio, marco oscuro,
## celosía de corte láser en arco, aviso redondo colgante con brazo de hierro, letrero sobre el dintel,
## materas con plantas al frente e interior cálido.
##
## Uso desde el distrito:  Shopfronts.build(self, xf, w, g, open, awning, near, shop_i)
##   xf: base de la fachada (y = andén, +Z local = hacia la calle, X = a lo largo de la fachada).
## Todo se coloca con d.place_mesh() (MultiMesh por key = variante cacheada); solo las OmniLight de los
## neones y un nodo de sincronía día/noche van con d.place_node().
##
## Piezas (cada una ≤ 4 materiales, cacheada en _meshes):
##   bay_<c>      vitrina 2.4 m (escalable en X): zócalo de granito, vidrio con interior (MatFacade.shopfront),
##                perfilería oscura con travesaño, caja de cortina enrollable galvanizada.
##   door_<c>     puerta de vidrio 1.2 m con marco, zócalo de patada, manija vertical y umbral de granito.
##   shutter      cortina metálica corrugada bajada (local cerrado), escalable en X.
##   post         pilar de marco perimetral con base de granito.
##   fascia_<t>   dintel (banda de 0.9 m) en 3 colores, escalable en X.
##   sign_<c>     letrero del atlas MatFacade.sign (banda 2:1) con caja de 8 cm.
##   blade_<c>    aviso de bandera: redondo colgante o neón cuadrado con brazo y tornapunta de hierro.
##   awn_<v>      toldo con faldón festoneado y brazos de hierro, escalable en X.
##   lattice      celosía de corte láser (MatMetal.laser_lattice) con vano en arco y marco.
##   planter_<v>  matera con tierra y plantas de tarjetas (MatFoliage.garden_plants).
##   neon_<k>     tubo de neón (Palette.neon) alrededor del letrero; con OmniLight corta solo de noche.
##   open         letrero "ABIERTO" de neón colgado tras el vidrio.
## Noche: las vitrinas y letreros usan emisión; NightSync lee StreetLook.current_preset (PRESETS.night) y
## ajusta la energía (set_night). Las luces de neón solo se encienden de noche.

const G := 3.4                 # altura de primer piso para la que están modeladas las piezas
const BAY_W := 2.4
const DOOR_W := 1.2
const POST_W := 0.3
const FASCIA_Y0 := 2.42
const FASCIA_Y1 := 3.34
const SIGN_W := 1.5
const SIGN_H := 0.75
const SIGN_Y := 2.97
const SINK := 0.55             # cuánto bajan zócalos y pilares bajo el andén (pendiente del 4 %)
const MAX_LIGHTS := 14
const NEON_COLS: Array[Color] = [Color(0.1, 0.85, 1.0), Color(1.0, 0.12, 0.6), Color(1.0, 0.55, 0.12)]
## Letrero (atlas MatFacade.sign 0..9) → vitrina (MatFacade.Shop) coherente con el negocio.
const SIGN_TO_SHOP: Array[int] = [1, 2, 3, 0, 3, 0, 0, 3, 3, 0]
const GROUP_LIGHTS := "shopf_night_lights"

static var _meshes := {}
static var _mats := {}
static var _emis: Array = []       # [material, energía de día, energía de noche]
static var _night := 0.0
static var tri_count := {}         # key → triángulos (para el informe)
static var debug_force_lattice := false   # solo para la escena de estudio


# ================================================================== colocación
## Construye el primer piso comercial de una fachada de ancho w. open/awning vienen del _rng del distrito
## (para no alterar su secuencia); el resto de la variación sale de una semilla local por posición.
static func build(d, xf: Transform3D, w: float, g: float, open: bool, awning: bool, near: bool, shop_i: int) -> void:
	var rng := RandomNumberGenerator.new()
	var o := xf.origin
	rng.seed = hash(Vector3i(roundi(o.x * 10.0), roundi(o.y * 10.0), roundi(o.z * 10.0))) ^ (shop_i * 7919)
	if not d.has_meta("shopf_sync"):
		d.set_meta("shopf_sync", true)
		d.set_meta("shopf_lights", 0)
		d.place_node(NightSync.new(), Transform3D.IDENTITY)
	var base := xf
	if absf(g - G) > 0.01:
		base = xf * Transform3D(Basis.from_scale(Vector3(1.0, g / G, 1.0)), Vector3.ZERO)
	var n_u := 1 if w < 9.5 else (2 if w < 16.0 else 3)
	var x_l := -w * 0.5 + POST_W * 0.5 + 0.02
	var x_r := w * 0.5 - POST_W * 0.5 - 0.02
	var inner := (x_r - x_l - POST_W * (n_u - 1) - POST_W) / n_u
	var posts: Array[float] = [x_l]
	for u in n_u:
		var ux0 := x_l + POST_W * 0.5 + u * (inner + POST_W)
		var ux1 := ux0 + inner
		posts.append(ux1 + POST_W * 0.5)
		var u_open := open if u == 0 else rng.randf() < 0.75
		var u_awn := awning if u == 0 else rng.randf() < 0.4
		_unit(d, base, ux0, ux1, u_open, u_awn, near, shop_i * 3 + u, rng)
	for px in posts:
		_put(d, "shopf_post", _post(), base, px, 0.0, 1.0, false)


static func _dy(base: Transform3D, lx: float) -> float:
	var wx := (base * Vector3(lx, 0.0, 0.5)).x
	return BostonDistrict.walk_y(wx) - base.origin.y


## Coloca mesh en x local lx (y ajustada a la pendiente del andén), escalado sx en X.
static func _put(d, key: String, mesh: Mesh, base: Transform3D, lx: float, ly: float, sx: float, shadow: bool, step := true) -> void:
	var y := ly + (_dy(base, lx) if step else 0.0)
	d.place_mesh(key, mesh, base * Transform3D(Basis.from_scale(Vector3(sx, 1.0, 1.0)), Vector3(lx, y, 0.0)), shadow)


static func _unit(d, base: Transform3D, x0: float, x1: float, open: bool, awning: bool, near: bool, sid: int, rng: RandomNumberGenerator) -> void:
	var uw := x1 - x0
	var cx := (x0 + x1) * 0.5
	var dyu := _dy(base, cx)
	var sc := posmod(sid * 7 + rng.randi_range(0, 9), 10)
	var cell := SIGN_TO_SHOP[sc]
	if rng.randf() < 0.25:
		cell = rng.randi_range(0, 3)
	# --- puerta y vitrinas
	var rem := uw - DOOR_W
	var door_pos := 0   # -1 izquierda, 0 centro, 1 derecha
	if rem * 0.5 >= 1.4:
		door_pos = [-1, 0, 0, 1][rng.randi_range(0, 3)]
	else:
		door_pos = -1 if rng.randf() < 0.5 else 1
	var door_x := cx
	var segs: Array = []   # [x_inicio, x_fin] de vitrinas
	if door_pos == 0:
		segs = [[x0, cx - DOOR_W * 0.5], [cx + DOOR_W * 0.5, x1]]
	elif door_pos < 0:
		door_x = x0 + DOOR_W * 0.5
		segs = [[x0 + DOOR_W, x1]]
	else:
		door_x = x1 - DOOR_W * 0.5
		segs = [[x0, x1 - DOOR_W]]
	var lattice := open and door_pos == 0 and uw >= 4.4 and (rng.randf() < 0.35 or debug_force_lattice)
	if open:
		_put(d, "shopf_door_%d" % cell, _door(cell), base, door_x, 0.0, 1.0, false)
		for s in segs:
			var L: float = s[1] - s[0]
			var n := maxi(1, roundi(L / BAY_W))
			var bw := L / n
			for k in n:
				_put(d, "shopf_bay_%d" % cell, _bay(cell), base, s[0] + bw * (k + 0.5), 0.0, bw / BAY_W, false)
		if near and rng.randf() < 0.3:
			var sg: Array = segs[rng.randi_range(0, segs.size() - 1)]
			var nb := maxi(1, roundi((sg[1] - sg[0]) / BAY_W))
			var ox: float = sg[0] + (sg[1] - sg[0]) / nb * (rng.randi_range(0, nb - 1) + 0.5) + rng.randf_range(-0.25, 0.25)
			_put(d, "shopf_open", _open_sign(), base, ox, 0.0, 1.0, false)
	else:
		# cortina abajo de punta a punta; caja de cortina con las mismas vitrinas detrás (no se ven)
		_put(d, "shopf_shutter", _shutter(), base, cx, 0.0, uw, false)
	# --- dintel y letrero
	var tint := rng.randi_range(0, 2)
	_put(d, "shopf_fascia_%d" % tint, _fascia(tint), base, cx, dyu, uw, false, false)
	var sign_x := cx
	var has_sign := uw >= SIGN_W + 0.3
	if lattice:
		# el letrero no puede quedar detrás de la celosía (±1.17 m alrededor de la puerta)
		var cl := door_x - 1.2 - SIGN_W * 0.5
		var cr := door_x + 1.2 + SIGN_W * 0.5
		if cl - SIGN_W * 0.5 >= x0 + 0.05:
			sign_x = cl
		elif cr + SIGN_W * 0.5 <= x1 - 0.05:
			sign_x = cr
		else:
			has_sign = false
	if has_sign:
		_put(d, "shopf_sign_%d" % sc, _sign(sc), base, sign_x, dyu, 1.0, false, false)
		if open and near and rng.randf() < 0.28:
			var k := rng.randi_range(0, 2)
			_put(d, "shopf_neon_%d" % k, _neon(k), base, sign_x, dyu, 1.0, false, false)
			_light(d, base * Vector3(sign_x, SIGN_Y + dyu, 0.9), NEON_COLS[k], 1.4)
	# --- celosía en arco alrededor de la puerta (foto 1)
	if lattice:
		_put(d, "shopf_lattice", _lattice(), base, door_x, _dy(base, door_x), 1.0, false, false)
	# --- toldo
	elif awning and open:
		var v := rng.randi_range(0, 2)
		_put(d, "shopf_awn_%d" % v, _awning(v), base, cx, dyu, uw - 0.1, true, false)
	# --- aviso de bandera en el extremo
	if rng.randf() < (0.5 if lattice else 0.3) or not has_sign:
		var bc: int = [10, 11, 10, 11, 12, 13, 14][rng.randi_range(0, 6)]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var bx := x0 - POST_W * 0.5 if side < 0.0 else x1 + POST_W * 0.5
		var bxf := base * Transform3D(Basis.IDENTITY, Vector3(bx, dyu, 0.2))
		d.place_mesh("shopf_blade_%d" % bc, _blade(bc), bxf, true)
		if bc >= 12 and near:
			var col: Color = [Color(0.2, 0.9, 1.0), Color(1.0, 0.2, 0.75), Color(1.0, 0.65, 0.2)][bc - 12]
			_light(d, bxf * Vector3(0.0, 2.72, 0.62), col, 0.9)
	# --- materas con plantas
	if open and rng.randf() < 0.55:
		var np := rng.randi_range(1, 2)
		for i in np:
			var sg2: Array = segs[rng.randi_range(0, segs.size() - 1)]
			if sg2[1] - sg2[0] < 1.2:
				continue
			var px: float = rng.randf_range(sg2[0] + 0.55, sg2[1] - 0.55)
			if lattice and absf(px - door_x) < 1.65:
				continue
			var pv := rng.randi_range(0, 3)
			var pxf := base * Transform3D(Basis.IDENTITY, Vector3(px, _dy(base, px), 0.42))
			d.place_mesh("shopf_planter_%d" % pv, _planter(pv), pxf, true)
			d.add_col_box(pxf.translated_local(Vector3(0, 0.22, 0)), Vector3(0.9, 0.44, 0.4))


static func _light(d, pos: Vector3, col: Color, energy: float) -> void:
	var n: int = d.get_meta("shopf_lights", 0)
	if n >= MAX_LIGHTS:
		return
	d.set_meta("shopf_lights", n + 1)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 4.5
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	l.light_specular = 0.6
	l.distance_fade_enabled = true
	l.distance_fade_begin = 60.0
	l.distance_fade_length = 20.0
	l.visible = _night > 0.5
	l.add_to_group(GROUP_LIGHTS)
	d.place_node(l, Transform3D(Basis.IDENTITY, pos))


# ================================================================== día / noche
## n: 0 = día, 1 = noche. Ajusta la emisión de vitrinas y letreros (materiales propios de este módulo).
static func set_night(n: float) -> void:
	_night = n
	for e in _emis:
		(e[0] as BaseMaterial3D).emission_energy_multiplier = lerpf(float(e[1]), float(e[2]), n)


static func _emissive(m: BaseMaterial3D, day: float, night: float) -> BaseMaterial3D:
	m.emission_enabled = true
	m.emission_energy_multiplier = lerpf(day, night, _night)
	_emis.append([m, day, night])
	return m


## Nodo que vigila el preset de StreetLook y conmuta emisión + luces de neón.
class NightSync extends Node3D:
	var _look: Node = null
	var _t := 0.0
	var _last := -1.0

	func _ready() -> void:
		name = "ShopNightSync"

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0:
			return
		_t = 0.5
		if _look == null or not is_instance_valid(_look):
			_look = _find(get_tree().root)
			if _look == null:
				_t = 3.0
		var n := 0.0
		if _look != null:
			var p: Dictionary = StreetLook.PRESETS.get(_look.get("current_preset"), {})
			n = float(p.get("night", 0.0))
		if n != _last:
			_last = n
			Shopfronts.set_night(n)
			get_tree().call_group(Shopfronts.GROUP_LIGHTS, "set_visible", n > 0.5)

	func _find(node: Node) -> Node:
		if node is StreetLook:
			return node
		for c in node.get_children():
			var r := _find(c)
			if r != null:
				return r
		return null


# ================================================================== materiales
static func _mat(key: String, f: Callable) -> Material:
	if not _mats.has(key):
		_mats[key] = f.call()
	return _mats[key]


static func _frame_mat() -> Material:   # perfilería y hierro: galvanizado pintado gris carbón
	return _mat("frame", func(): return MatMetal.galvanized({"tint": Color(0.16, 0.16, 0.17)}))


static func _box_mat() -> Material:     # caja de cortina y cortina
	return _mat("box", func(): return MatMetal.galvanized({"tint": Color(0.78, 0.79, 0.8)}))


static func _fascia_mat(t: int) -> Material:
	var tints: Array[Color] = [Color(0.2, 0.2, 0.21), Color(0.16, 0.27, 0.21), Color(0.42, 0.16, 0.13)]
	return _mat("fascia%d" % t, func(): return TexMat.pbr("res://art/tex/plaster/concrete_smooth", {"tile_m": 2.0, "tint": tints[t]}))


static func _glass_mat(cell: int) -> Material:
	return _mat("glass%d" % cell, func():
		var m: ORMMaterial3D = (MatFacade.shopfront(cell, true) as ORMMaterial3D).duplicate()
		m.roughness = 0.6
		return _emissive(m, 0.55, 1.9))


static func _sign_mat(cell: int, both := false) -> Material:
	return _mat("sign%d_%s" % [cell, both], func():
		var m: ORMMaterial3D = (MatFacade.sign(cell, true) as ORMMaterial3D).duplicate()
		m.cull_mode = BaseMaterial3D.CULL_BACK
		var neon := cell >= 12
		return _emissive(m, 0.6 if neon else 0.12, 3.2 if neon else 1.3))


static func _soil_mat() -> Material:
	return MatGround.mantillo(Color(0.7, 0.66, 0.62))


# ================================================================== piezas
static func _cached(key: String, f: Callable) -> Mesh:
	if not _meshes.has(key):
		var k: Kit = f.call()
		_meshes[key] = k.commit()
		tri_count[key] = k.tris
	return _meshes[key]


## Vitrina de 2.4 m (se escala en X al ancho real).
static func _bay(cell: int) -> Mesh:
	return _cached("bay%d" % cell, func():
		var k := Kit.new()
		var fr := _frame_mat()
		var hw := BAY_W * 0.5
		k.bbox(MatStone.granito(), Vector3(0, (0.38 - SINK) * 0.5, 0.06), Vector3(BAY_W, 0.38 + SINK, 0.12), 0.012, true)
		k.quad(_glass_mat(cell), Vector3(-hw, 2.32, 0.035), Vector3(hw, 2.32, 0.035), Vector3(hw, 0.38, 0.035), Vector3(-hw, 0.38, 0.035),
			Vector3.BACK, [Vector2(0.015, 0.115), Vector2(0.985, 0.115), Vector2(0.985, 0.87), Vector2(0.015, 0.87)])
		k.bbox(fr, Vector3(0, 0.41, 0.075), Vector3(BAY_W, 0.06, 0.09), 0.01, true)        # alféizar
		k.bbox(fr, Vector3(0, 2.3, 0.075), Vector3(BAY_W, 0.07, 0.09), 0.01, true)         # cabezal
		k.bbox(fr, Vector3(0, 1.98, 0.06), Vector3(BAY_W, 0.045, 0.06), 0.008, true)       # travesaño
		for sx: float in [-1.0, 1.0]:
			k.bbox(fr, Vector3(sx * (hw - 0.03), 1.36, 0.075), Vector3(0.06, 1.96, 0.09), 0.01, true)
		k.bbox(_box_mat(), Vector3(0, 2.49, 0.14), Vector3(BAY_W, 0.27, 0.28), 0.04, true)  # caja de cortina
		k.bbox(fr, Vector3(0, 2.36, 0.25), Vector3(BAY_W, 0.03, 0.05), 0.005, true)        # labio de salida
		return k)


## Puerta de vidrio de 1.2 m con umbral de granito.
static func _door(cell: int) -> Mesh:
	return _cached("door%d" % cell, func():
		var k := Kit.new()
		var fr := _frame_mat()
		var hw := DOOR_W * 0.5
		k.bbox(MatStone.granito(), Vector3(0, (0.04 - SINK) * 0.5, 0.14), Vector3(DOOR_W, 0.04 + SINK, 0.28), 0.01, true)
		k.quad(_glass_mat(cell), Vector3(-0.5, 2.26, 0.012), Vector3(0.5, 2.26, 0.012), Vector3(0.5, 0.05, 0.012), Vector3(-0.5, 0.05, 0.012),
			Vector3.BACK, [Vector2(0.36, 0.115), Vector2(0.64, 0.115), Vector2(0.64, 0.99), Vector2(0.36, 0.99)])
		for sx: float in [-1.0, 1.0]:
			k.bbox(fr, Vector3(sx * (hw - 0.04), 1.17, 0.06), Vector3(0.08, 2.34, 0.12), 0.012, true)   # jamba
			k.bbox(fr, Vector3(sx * 0.46, 1.16, 0.035), Vector3(0.08, 2.24, 0.04), 0.008, true)          # larguero
		k.bbox(fr, Vector3(0, 2.3, 0.06), Vector3(DOOR_W, 0.08, 0.12), 0.012, true)
		k.bbox(fr, Vector3(0, 2.22, 0.035), Vector3(0.88, 0.07, 0.04), 0.008, true)
		k.bbox(fr, Vector3(0, 0.13, 0.035), Vector3(0.88, 0.18, 0.04), 0.008, true)          # zócalo de patada
		k.cyl(_box_mat(), Vector3(0.3, 0.75, 0.11), Vector3(0.3, 1.55, 0.11), 0.017, 8)  # manija
		for hy: float in [0.82, 1.48]:
			k.cyl(_box_mat(), Vector3(0.3, hy, 0.05), Vector3(0.3, hy, 0.11), 0.01, 6)
		k.bbox(_box_mat(), Vector3(0, 2.49, 0.14), Vector3(DOOR_W, 0.27, 0.28), 0.04, true)
		return k)


## Cortina metálica corrugada (local cerrado). Ancho 1 m, se escala en X.
static func _shutter() -> Mesh:
	return _cached("shutter", func():
		var k := Kit.new()
		var m := _box_mat()
		var y := 0.0
		var p := 0.09
		while y < 2.34 - 0.001:
			var y1 := minf(y + p, 2.34)
			var ym := (y + y1) * 0.5
			k.quad(m, Vector3(-0.5, ym, 0.17), Vector3(0.5, ym, 0.17), Vector3(0.5, y, 0.15), Vector3(-0.5, y, 0.15), Vector3(0, -0.6, 1).normalized())
			k.quad(m, Vector3(-0.5, y1, 0.15), Vector3(0.5, y1, 0.15), Vector3(0.5, ym, 0.17), Vector3(-0.5, ym, 0.17), Vector3(0, 0.6, 1).normalized())
			y = y1
		k.bbox(_frame_mat(), Vector3(0, 0.04, 0.17), Vector3(1.0, 0.08, 0.06), 0.01, true)
		k.bbox(m, Vector3(0, 2.49, 0.14), Vector3(1.0, 0.27, 0.28), 0.04, true)
		k.bbox(_frame_mat(), Vector3(0, (0.02 - SINK) * 0.5, 0.08), Vector3(1.0, 0.02 + SINK, 0.16), 0.0, true)
		return k)


## Pilar del marco perimetral con base de granito.
static func _post() -> Mesh:
	return _cached("post", func():
		var k := Kit.new()
		k.bbox(_frame_mat(), Vector3(0, (FASCIA_Y1 + 0.38) * 0.5, 0.1), Vector3(POST_W, FASCIA_Y1 - 0.38, 0.2), 0.02, true)
		k.bbox(MatStone.granito(), Vector3(0, (0.38 - SINK) * 0.5, 0.11), Vector3(POST_W + 0.04, 0.38 + SINK, 0.22), 0.015, true)
		k.bbox(_box_mat(), Vector3(0, 1.2, 0.205), Vector3(0.06, 2.3, 0.02), 0.0, true)     # guía de cortina
		return k)


## Dintel: banda de 1 m (escala X = ancho del local) con gotero arriba.
static func _fascia(t: int) -> Mesh:
	return _cached("fascia%d" % t, func():
		var k := Kit.new()
		var m := _fascia_mat(t)
		k.bbox(m, Vector3(0, (FASCIA_Y0 + FASCIA_Y1) * 0.5, 0.11), Vector3(1.0, FASCIA_Y1 - FASCIA_Y0, 0.22), 0.02, true)
		k.bbox(_frame_mat(), Vector3(0, FASCIA_Y1 + 0.02, 0.13), Vector3(1.0, 0.04, 0.27), 0.008, true)
		k.bbox(_frame_mat(), Vector3(0, 2.62, 0.225), Vector3(1.0, 0.03, 0.02), 0.0, true)  # moldura inferior
		return k)


## Letrero de dintel (atlas de letreros, banda 2:1) sobre caja de 8 cm.
static func _sign(cell: int) -> Mesh:
	return _cached("sign%d" % cell, func():
		var k := Kit.new()
		var hw := SIGN_W * 0.5
		var hh := SIGN_H * 0.5
		var z := 0.315
		k.quad(_sign_mat(cell), Vector3(-hw, SIGN_Y + hh, z), Vector3(hw, SIGN_Y + hh, z), Vector3(hw, SIGN_Y - hh, z), Vector3(-hw, SIGN_Y - hh, z),
			Vector3.BACK, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		k.bbox(_frame_mat(), Vector3(0, SIGN_Y, 0.262), Vector3(SIGN_W - 0.1, SIGN_H - 0.14, 0.08), 0.01, true)
		return k)


## Neón de color k alrededor del letrero.
static func _neon(kk: int) -> Mesh:
	return _cached("neon%d" % kk, func():
		var k := Kit.new()
		var m := Palette.neon(NEON_COLS[kk], 4.0)
		var hw := SIGN_W * 0.5 + 0.07
		var hh := SIGN_H * 0.5 + 0.03
		var z := 0.34
		k.cyl(m, Vector3(-hw, SIGN_Y + hh, z), Vector3(hw, SIGN_Y + hh, z), 0.014, 6)
		k.cyl(m, Vector3(-hw, SIGN_Y - hh, z), Vector3(hw, SIGN_Y - hh, z), 0.014, 6)
		k.cyl(m, Vector3(-hw, SIGN_Y - hh, z), Vector3(-hw, SIGN_Y + hh, z), 0.014, 6)
		k.cyl(m, Vector3(hw, SIGN_Y - hh, z), Vector3(hw, SIGN_Y + hh, z), 0.014, 6)
		return k)


## "ABIERTO" de neón colgado tras el vidrio (0.56 x 0.28 m) con dos cadenitas.
static func _open_sign() -> Mesh:
	return _cached("open", func():
		var k := Kit.new()
		k.quad(_sign_mat(15), Vector3(-0.28, 1.86, 0.045), Vector3(0.28, 1.86, 0.045), Vector3(0.28, 1.58, 0.045), Vector3(-0.28, 1.58, 0.045),
			Vector3.BACK, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		return k)


## Aviso de bandera perpendicular a la fachada: placa, brazo, tornapunta y aviso de doble cara.
static func _blade(cell: int) -> Mesh:
	return _cached("blade%d" % cell, func():
		var k := Kit.new()
		var fr := _frame_mat()
		var is_round := cell <= 11
		var s := 0.64 if is_round else 0.6
		var ay := 3.12
		k.bbox(fr, Vector3(0, ay - 0.12, 0.012), Vector3(0.12, 0.4, 0.024), 0.006, true)    # placa de anclaje
		k.cyl(fr, Vector3(0, ay, 0.02), Vector3(0, ay, 1.0), 0.016, 8)                     # brazo
		k.cyl(fr, Vector3(0, ay - 0.28, 0.02), Vector3(0, ay, 0.5), 0.011, 6)              # tornapunta
		# voluta sencilla entre brazo y tornapunta
		var c := Vector3(0, ay - 0.08, 0.2)
		for i in 8:
			var a0 := TAU * i / 8.0
			var a1 := TAU * (i + 1) / 8.0
			k.cyl(fr, c + Vector3(0, sin(a0), cos(a0)) * 0.06, c + Vector3(0, sin(a1), cos(a1)) * 0.06, 0.007, 4)
		k.bbox(fr, Vector3(0, ay, 1.0), Vector3(0.04, 0.04, 0.04), 0.008, true)            # remate
		var zc := 0.62
		var top := ay + 0.035 if is_round else ay - 0.1
		if not is_round:
			for zz: float in [zc - 0.22, zc + 0.22]:
				k.cyl(fr, Vector3(0, ay, zz), Vector3(0, top, zz), 0.006, 4)
		var y0 := top - s
		var m := _sign_mat(cell)
		var hz := s * 0.5
		var t := 0.014
		# cara +X y cara -X (U invertida para que se lea bien desde ambos lados)
		k.quad(m, Vector3(t, top, zc + hz), Vector3(t, top, zc - hz), Vector3(t, y0, zc - hz), Vector3(t, y0, zc + hz),
			Vector3.RIGHT, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		k.quad(m, Vector3(-t, top, zc - hz), Vector3(-t, top, zc + hz), Vector3(-t, y0, zc + hz), Vector3(-t, y0, zc - hz),
			Vector3.LEFT, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		if is_round:
			# canto del disco (centro de la imagen en (128,140)/256, radio 108/256)
			var cy := top - s * 140.0 / 256.0
			var r := s * 105.0 / 256.0
			var n := 20
			for i in n:
				var a0 := TAU * i / n
				var a1 := TAU * (i + 1) / n
				var p0 := Vector3(0, cy + sin(a0) * r, zc + cos(a0) * r)
				var p1 := Vector3(0, cy + sin(a1) * r, zc + cos(a1) * r)
				var nn := Vector3(0, sin((a0 + a1) * 0.5), cos((a0 + a1) * 0.5))
				k.quad(_box_mat(), p0 + Vector3(t, 0, 0), p1 + Vector3(t, 0, 0), p1 - Vector3(t, 0, 0), p0 - Vector3(t, 0, 0), nn)
			k.cyl(fr, Vector3(0, ay, zc), Vector3(0, top - 0.03, zc), 0.006, 4)
		else:
			k.bbox(fr, Vector3(0, top - s * 0.5, zc), Vector3(2 * t - 0.004, s - 0.06, s - 0.06), 0.004, false)
		return k)


## Toldo con faldón festoneado y brazos de hierro. Ancho 1 m (escala X).
static func _awning(v: int) -> Mesh:
	return _cached("awn%d" % v, func():
		var k := Kit.new()
		var tints: Array[Color] = [Color.WHITE, Color(0.62, 0.16, 0.12), Color(0.2, 0.36, 0.5)]
		var m: Material = MatFacade.awning_striped() if v == 0 else MatFacade.awning_plain(tints[v])
		var fr := _frame_mat()
		var y_top := 2.6
		var z_top := 0.24
		var y_f := 2.2
		var z_f := 1.2
		var sag := 0.03
		var rows := 4
		var prev_y := y_top
		var prev_z := z_top
		for r in range(1, rows + 1):
			var t := float(r) / rows
			var yy := lerpf(y_top, y_f, t) + sin(t * PI) * sag
			var zz := lerpf(z_top, z_f, t)
			var nrm := Vector3(0, zz - prev_z, -(yy - prev_y)).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			k.quad(m, Vector3(-0.5, prev_y, prev_z), Vector3(0.5, prev_y, prev_z), Vector3(0.5, yy, zz), Vector3(-0.5, yy, zz), nrm)
			prev_y = yy
			prev_z = zz
		# faldón festoneado
		var sc := 6
		var vh := 0.2
		for i in sc:
			var xa := -0.5 + float(i) / sc
			var xb := -0.5 + float(i + 1) / sc
			var xm := (xa + xb) * 0.5
			k.quad(m, Vector3(xa, y_f, z_f), Vector3(xb, y_f, z_f), Vector3(xb, y_f - vh + 0.04, z_f), Vector3(xa, y_f - vh + 0.04, z_f), Vector3.BACK)
			k.tri(m, Vector3(xa, y_f - vh + 0.04, z_f), Vector3(xb, y_f - vh + 0.04, z_f), Vector3(xm, y_f - vh - 0.02, z_f), Vector3.BACK)
		# costados (cachetes)
		for sx: float in [-0.5, 0.5]:
			k.tri(m, Vector3(sx, y_top, z_top), Vector3(sx, y_f, z_f), Vector3(sx, y_f - vh + 0.04, z_f), Vector3(signf(sx), 0, 0))
		# tubo frontal y brazos
		k.cyl(fr, Vector3(-0.5, y_f, z_f - 0.02), Vector3(0.5, y_f, z_f - 0.02), 0.02, 6)
		k.cyl(fr, Vector3(-0.5, y_top, z_top - 0.02), Vector3(0.5, y_top, z_top - 0.02), 0.025, 6)
		for sx: float in [-0.46, 0.46]:
			k.cyl(fr, Vector3(sx, 1.95, 0.24), Vector3(sx, y_f - 0.02, z_f - 0.06), 0.014, 6)
			k.bbox(fr, Vector3(sx, 1.95, 0.235), Vector3(0.06, 0.1, 0.03), 0.005, true)
		return k)


## Celosía de corte láser con vano en arco (2.2 m de ancho, centrada en la puerta).
static func _lattice() -> Mesh:
	return _cached("lattice", func():
		var k := Kit.new()
		var lm := MatMetal.laser_lattice()
		var fr := _frame_mat()
		var ow := 1.12
		var iw := 0.62
		var spring := 2.2
		var top := FASCIA_Y1 + 0.04
		var z := 0.4
		var y_b := 0.0
		# jambas
		for sx: float in [-1.0, 1.0]:
			var a := sx * iw
			var b := sx * ow
			k.quad(lm, Vector3(minf(a, b), spring, z), Vector3(maxf(a, b), spring, z), Vector3(maxf(a, b), y_b, z), Vector3(minf(a, b), y_b, z), Vector3.BACK)
		# enjuta sobre el arco y paños sobre las jambas
		var n := 12
		for i in n:
			var a0 := PI * i / n
			var a1 := PI * (i + 1) / n
			var p0 := Vector3(-cos(a0) * iw, spring + sin(a0) * iw, z)
			var p1 := Vector3(-cos(a1) * iw, spring + sin(a1) * iw, z)
			k.quad(lm, Vector3(p0.x, top, z), Vector3(p1.x, top, z), p1, p0, Vector3.BACK)
			k.cyl(fr, p0, p1, 0.022, 4)
		for sx: float in [-1.0, 1.0]:
			k.quad(lm, Vector3(minf(sx * iw, sx * ow), top, z), Vector3(maxf(sx * iw, sx * ow), top, z),
				Vector3(maxf(sx * iw, sx * ow), spring, z), Vector3(minf(sx * iw, sx * ow), spring, z), Vector3.BACK)
			k.bbox(fr, Vector3(sx * (ow + 0.025), top * 0.5, z), Vector3(0.05, top, 0.05), 0.008, true)
			k.bbox(fr, Vector3(sx * iw, spring * 0.5, z), Vector3(0.044, spring, 0.044), 0.006, true)
			for by: float in [0.6, 1.9, 3.0]:
				k.bbox(fr, Vector3(sx * (ow - 0.1), by, (z + 0.2) * 0.5), Vector3(0.04, 0.04, z - 0.2), 0.0, true)
		k.bbox(fr, Vector3(0, top + 0.025, z), Vector3(2 * ow + 0.1, 0.05, 0.05), 0.008, true)
		return k)


## Matera con tierra y plantas (tarjetas cruzadas del atlas de jardín).
static func _planter(v: int) -> Mesh:
	return _cached("planter%d" % v, func():
		var k := Kit.new()
		var pm: Material = MatStone.pizarra() if v % 2 == 0 else MatPlaster.concrete_smooth()
		k.bbox(pm, Vector3(0, 0.22, 0), Vector3(0.9, 0.44, 0.4), 0.02, false)
		k.quad(_soil_mat(), Vector3(-0.42, 0.42, -0.17), Vector3(0.42, 0.42, -0.17), Vector3(0.42, 0.42, 0.17), Vector3(-0.42, 0.42, 0.17), Vector3.UP)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711 + v * 31
		var fm := MatFoliage.garden_plants()
		var cells: Array = [[0, 1], [2, 1], [3, 0], [1, 2]][v]
		for i in 3:
			var cell: int = cells[i % 2]
			var r := MatFoliage.cell_uv(cell)
			var h := rng.randf_range(0.5, 0.8) * (1.15 if i == 1 else 1.0)
			var wq := h * rng.randf_range(0.8, 1.0)
			var c := Vector3(-0.27 + 0.27 * i + rng.randf_range(-0.05, 0.05), 0.4, rng.randf_range(-0.05, 0.05))
			var yaw := rng.randf() * PI
			for j in 2:
				var a := yaw + j * PI * 0.5
				var dx := Vector3(cos(a), 0, sin(a)) * wq * 0.5
				var nn := Vector3(-sin(a), 0, cos(a))
				var uv := [r.position, r.position + Vector2(r.size.x, 0), r.position + r.size, r.position + Vector2(0, r.size.y)]
				k.quad(fm, c - dx + Vector3(0, h, 0), c + dx + Vector3(0, h, 0), c + dx, c - dx, nn, uv, true)
		return k)


# ================================================================== constructor de mallas
## Mini-kit de SurfaceTool por material: quads/triángulos orientados, cajas con chaflán y cilindros.
class Kit:
	var st := {}
	var mats := {}
	var order: Array = []
	var tris := 0

	func _s(m: Material) -> SurfaceTool:
		var id := m.get_instance_id()
		if not st.has(id):
			var s := SurfaceTool.new()
			s.begin(Mesh.PRIMITIVE_TRIANGLES)
			st[id] = s
			mats[id] = m
			order.append(id)
		return st[id]

	static func _puv(p: Vector3, n: Vector3) -> Vector2:
		var a := n.abs()
		if a.y >= a.x and a.y >= a.z:
			return Vector2(p.x, p.z)
		if a.x >= a.z:
			return Vector2(p.z, -p.y)
		return Vector2(p.x, -p.y)

	## Triángulo; se reordena para que la cara frontal mire hacia n (Godot: frontal = horario).
	func tri(m: Material, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua := Vector2.INF, ub := Vector2.INF, uc := Vector2.INF) -> void:
		var s := _s(m)
		if ua == Vector2.INF:
			ua = _puv(a, n)
			ub = _puv(b, n)
			uc = _puv(c, n)
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		for v in [[a, ua], [b, ub], [c, uc]]:
			s.set_normal(n)
			s.set_uv(v[1])
			s.add_vertex(v[0])
		tris += 1

	## Quad a-b-c-d en orden de perímetro. uv opcional (4 Vector2). two_sided: también la cara de atrás.
	func quad(m: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv: Array = [], two_sided := false) -> void:
		if uv.size() == 4:
			tri(m, a, b, c, n, uv[0], uv[1], uv[2])
			tri(m, a, c, d, n, uv[0], uv[2], uv[3])
		else:
			tri(m, a, b, c, n)
			tri(m, a, c, d, n)
		if two_sided:
			if uv.size() == 4:
				tri(m, a, b, c, -n, uv[0], uv[1], uv[2])
				tri(m, a, c, d, -n, uv[0], uv[2], uv[3])
			else:
				tri(m, a, b, c, -n)
				tri(m, a, c, d, -n)

	## Caja con chaflán b en todas las aristas. skip_back: omite la cara -Z (contra el muro).
	func bbox(m: Material, c: Vector3, size: Vector3, b: float, skip_back := false) -> void:
		var h := size * 0.5
		b = minf(b, minf(h.x, minf(h.y, h.z)) * 0.9)
		var ax: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		var hv: Array[float] = [h.x, h.y, h.z]
		for i in 3:
			for sgn: float in [-1.0, 1.0]:
				if skip_back and i == 2 and sgn < 0.0:
					continue
				var nrm := ax[i] * sgn
				var j := (i + 1) % 3
				var l := (i + 2) % 3
				var cc := c + nrm * hv[i]
				var u := ax[j] * (hv[j] - b)
				var v := ax[l] * (hv[l] - b)
				quad(m, cc - u - v, cc + u - v, cc + u + v, cc - u + v, nrm)
		if b <= 0.0:
			return
		# aristas
		for i in 3:
			var j := (i + 1) % 3
			var l := (i + 2) % 3
			for si: float in [-1.0, 1.0]:
				for sj: float in [-1.0, 1.0]:
					if skip_back and ((i == 2 and si < 0.0) or (j == 2 and sj < 0.0)):
						continue
					var nrm := (ax[i] * si + ax[j] * sj).normalized()
					var pa := c + ax[i] * si * hv[i] + ax[j] * sj * (hv[j] - b)
					var pb := c + ax[i] * si * (hv[i] - b) + ax[j] * sj * hv[j]
					var e := ax[l] * (hv[l] - b)
					quad(m, pa - e, pa + e, pb + e, pb - e, nrm)
		# esquinas
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					if skip_back and sz < 0.0:
						continue
					var p0 := c + Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
					var p1 := c + Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
					var p2 := c + Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
					tri(m, p0, p1, p2, Vector3(sx, sy, sz).normalized())

	## Cilindro (sin tapas) de a a b, radio r, seg lados, normales suaves.
	func cyl(m: Material, a: Vector3, b: Vector3, r: float, seg: int) -> void:
		var axis := (b - a).normalized()
		var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
		var u := axis.cross(ref).normalized()
		var v := axis.cross(u).normalized()
		var s := _s(m)
		var L := a.distance_to(b)
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var n0 := u * cos(a0) + v * sin(a0)
			var n1 := u * cos(a1) + v * sin(a1)
			var q := [[a + n0 * r, n0, Vector2(float(i) / seg, 0)], [b + n0 * r, n0, Vector2(float(i) / seg, L)],
				[b + n1 * r, n1, Vector2(float(i + 1) / seg, L)], [a + n1 * r, n1, Vector2(float(i + 1) / seg, 0)]]
			var nf: Vector3 = (n0 + n1).normalized()
			var idx := [0, 1, 2, 0, 2, 3]
			if ((q[1][0] - q[0][0]) as Vector3).cross(q[2][0] - q[0][0]).dot(nf) > 0.0:
				idx = [0, 2, 1, 0, 3, 2]
			for t in idx:
				s.set_normal(q[t][1])
				s.set_uv(q[t][2])
				s.add_vertex(q[t][0])
			tris += 2

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for id in order:
			var s: SurfaceTool = st[id]
			s.generate_tangents()
			s.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[id])
		return mesh

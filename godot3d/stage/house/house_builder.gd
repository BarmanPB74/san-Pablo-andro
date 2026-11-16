class_name HouseBuilder
extends RefCounted
## Constructor de UN cuarto de La Casa. Todo por código y fundido en una malla por material (pocas llamadas de dibujo);
## las colisiones son cajas en un solo StaticBody3D. Sin exterior: no hay cielo, sol ni sombras, solo luces Omni sin sombra.
##
## Cada muro tiene un marco local (x a lo largo del muro, de izquierda a derecha visto desde dentro; y arriba; z hacia dentro
## del cuarto, la cara interior en z = 0 y el muro hacia z negativo). Las puertas son arcos apuntados equiláteros de 3.2 m de
## luz con un velo de bruma que cubre el hueco: al cruzarlo, el gestor (HouseScene) descarga este cuarto y carga el vecino.
## Medidas pensadas para Andro (campo de fuerza = cápsula de 1.32 m de ancho y 1.86 m de alto, y flota).

const T := 0.8                              # grosor de los muros
const DOOR_W := 3.2
const DOOR_SPRING := 1.6                    # altura donde nace el arco
const DOOR_APEX := DOOR_SPRING + 0.866 * DOOR_W
const ARCH_N := 8                           # segmentos por lado de cada arco
const ARRIVE_DIST := 2.8                    # a cuántos metros de la puerta aparece Andro al llegar

static var _ubox: BoxMesh
static var _ucyl: CylinderMesh

var dim: Vector3                            # (ancho x, alto y, fondo z)
var room_id := ""
var doors: Array = []                       # [{side, at, to}] (at = x ó z del mundo a lo largo del muro)
var door_areas: Array = []                  # [{area, door}] sensores de los velos
var node: Node3D
var body: StaticBody3D
var tris := 0
var light_count := 0
var _mats := HouseMaterials.all()
var _st := {}
var _blocks: Array = []                     # zonas de muro reservadas (chimeneas): {side, x, half}; sin ventanas ni pilastras ahí
var _qa := {}                               # caras a medida (arcos) por material: vértices, normales, uv


func _init(p_id: String, p_dim: Vector3, p_doors: Array) -> void:
	room_id = p_id
	dim = p_dim
	doors = p_doors
	node = Node3D.new()
	node.name = "Room_" + p_id
	body = StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = 1
	body.collision_mask = 0
	node.add_child(body)


# ------------------------------------------------------------------ primitivas

static func _unit_box() -> BoxMesh:
	if _ubox == null:
		_ubox = BoxMesh.new()
		_ubox.size = Vector3.ONE
	return _ubox


static func _unit_cyl() -> CylinderMesh:
	if _ucyl == null:
		_ucyl = CylinderMesh.new()
		_ucyl.top_radius = 0.5
		_ucyl.bottom_radius = 0.5
		_ucyl.height = 1.0
		_ucyl.radial_segments = 12
		_ucyl.rings = 1
	return _ucyl


func _surf(mkey: String) -> SurfaceTool:
	var st: SurfaceTool = _st.get(mkey)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mkey] = st
	return st


## Caja visual (sin colisión) con centro `c` y tamaño `s`.
func vbox(c: Vector3, s: Vector3, mkey: String) -> void:
	_surf(mkey).append_from(_unit_box(), 0, Transform3D(Basis.from_scale(s), c))
	tris += 12


## Caja visual con transformación completa (rotada) y tamaño `s`.
func vbox_t(t: Transform3D, s: Vector3, mkey: String) -> void:
	_surf(mkey).append_from(_unit_box(), 0, Transform3D(t.basis * Basis.from_scale(s), t.origin))
	tris += 12


## Cilindro visual vertical: centro `c`, radios (rx, rz) y altura `h`.
func vcyl(c: Vector3, rx: float, h: float, mkey: String, rz := -1.0) -> void:
	var z := rx if rz < 0.0 else rz
	_surf(mkey).append_from(_unit_cyl(), 0, Transform3D(Basis.from_scale(Vector3(rx * 2.0, h, z * 2.0)), c))
	tris += 48


func col(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	cs.position = c
	body.add_child(cs)


func col_cyl(c: Vector3, radius: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = h
	cs.shape = sh
	cs.position = c
	body.add_child(cs)


func box(c: Vector3, s: Vector3, mkey: String, collide := true) -> void:
	vbox(c, s, mkey)
	if collide:
		col(c, s)


## Mueble o pieza apoyada en el piso: centro (x, z), tamaño (sx, sy, sz) y base a la altura `y0`.
func f(x: float, z: float, sx: float, sy: float, sz: float, mkey: String, y0 := 0.0, collide := true) -> void:
	box(Vector3(x, y0 + sy * 0.5, z), Vector3(sx, sy, sz), mkey, collide)


func cyl(x: float, z: float, r: float, h: float, mkey: String, y0 := 0.0, collide := true) -> void:
	vcyl(Vector3(x, y0 + h * 0.5, z), r, h, mkey)
	if collide:
		col_cyl(Vector3(x, y0 + h * 0.5, z), r, h)


func light(pos: Vector3, energy: float, range_m: float, color := Color(0.95, 0.80, 0.60)) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	l.position = pos
	node.add_child(l)
	light_count += 1


# ------------------------------------------------------------------ marcos de muro

static func frame_for(dim_v: Vector3, side: String) -> Transform3D:
	var hw := dim_v.x * 0.5
	var hd := dim_v.z * 0.5
	match side:
		"N":
			return Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(0, 0, -hd))
		"S":
			return Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)), Vector3(0, 0, hd))
		"E":
			return Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3(hw, 0, 0))
	return Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(-hw, 0, 0))


## x local a lo largo del muro de una coordenada del mundo (x para N/S, z para E/W).
static func local_x_for(side: String, at: float) -> float:
	return -at if (side == "S" or side == "W") else at


## Dónde y hacia dónde mira Andro al llegar por esta puerta (al interior del cuarto): {pos, yaw}.
static func arrival_for(dim_v: Vector3, door: Dictionary) -> Dictionary:
	var side: String = door["side"]
	var p := frame_for(dim_v, side) * Vector3(local_x_for(side, float(door["at"])), 0.1, ARRIVE_DIST)
	var yaw := 0.0
	match side:
		"N":
			yaw = PI
		"S":
			yaw = 0.0
		"E":
			yaw = PI * 0.5
		_:
			yaw = -PI * 0.5
	return {"pos": p, "yaw": yaw}


func frame_of(side: String) -> Transform3D:
	return frame_for(dim, side)


## Largo útil de un muro (cara interior).
func inner_len(side: String) -> float:
	return dim.x if (side == "N" or side == "S") else dim.z


func local_x(side: String, at: float) -> float:
	return local_x_for(side, at)


## Centro de una puerta en el mundo (sobre la cara interior, a ras del piso).
func door_pos(door: Dictionary) -> Vector3:
	var side: String = door["side"]
	return frame_of(side) * Vector3(local_x(side, float(door["at"])), 0.0, 0.0)


func arrival(door: Dictionary) -> Dictionary:
	return arrival_for(dim, door)


## Caja en el marco `fr` con límites locales; la caja del mundo sale de rotar el centro y el tamaño.
func fbox(fr: Transform3D, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mkey: String, collide := true) -> void:
	var lc := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	var v := fr.basis * Vector3(x1 - x0, y1 - y0, z1 - z0)
	box(fr * lc, Vector3(absf(v.x), absf(v.y), absf(v.z)), mkey, collide)


func fcol(fr: Transform3D, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	var lc := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	var v := fr.basis * Vector3(x1 - x0, y1 - y0, z1 - z0)
	col(fr * lc, Vector3(absf(v.x), absf(v.y), absf(v.z)))


# ------------------------------------------------------------------ geometría a medida (arcos)

## Altura del arco apuntado en x_rel (0 = clave). rr = radio / luz: 1.0 equilátero (sube 0.87·w), 0.6 más bajo (0.59·w).
static func arch_y(x_rel: float, w: float, spring: float, rr := 1.0) -> float:
	var r := w * rr
	var cx := (-w * 0.5 + r) if x_rel <= 0.0 else (w * 0.5 - r)
	var dx := x_rel - cx
	return spring + sqrt(maxf(r * r - dx * dx, 0.0))


## Cuánto sube un arco de luz w y razón rr sobre su arranque.
static func arch_rise(w: float, rr := 1.0) -> float:
	return sqrt(w * w * rr - w * w * 0.25)


func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, key: String) -> void:
	var d: Dictionary = _qa.get(key, {})
	if d.is_empty():
		d = {"v": [], "n": [], "uv": []}          # Array (por referencia); se convierten a Packed al cerrar
		_qa[key] = d
	for p in [a, b, c]:
		d["v"].append(p)
		d["n"].append(n)
		d["uv"].append(Vector2(p.x + p.z, p.y))
	tris += 1


## Cuadrilátero con vértices en el marco `fr`. La cara visible es la del lado de `toward` (punto local).
func quad(fr: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, toward: Vector3, mkey: String) -> void:
	var wa := fr * a
	var wb := fr * b
	var wc := fr * c
	var wd := fr * d
	var n := (wb - wa).cross(wc - wa)
	if n.length() < 0.000001:
		n = (wc - wa).cross(wd - wa)
		if n.length() < 0.000001:
			return
	n = n.normalized()
	if n.dot((fr * toward) - wa) < 0.0:
		var tmp := wb
		wb = wd
		wd = tmp
		n = -n
	_tri(wa, wc, wb, n, mkey)      # sentido horario visto desde el frente
	_tri(wa, wd, wc, n, mkey)


## Muro sobre una puerta: cara interior entre la curva del arco y el techo, más el intradós (el grosor del arco).
func arch_top(fr: Transform3D, xc: float, w: float, spring: float, y_top: float, mkey: String) -> void:
	var prev_x := xc - w * 0.5
	var prev_y := spring
	for i in range(1, 2 * ARCH_N + 1):
		var xr := -w * 0.5 + w * float(i) / float(2 * ARCH_N)
		var cx := xc + xr
		var cy := arch_y(xr, w, spring)
		if y_top > prev_y + 0.001 or y_top > cy + 0.001:
			quad(fr, Vector3(prev_x, prev_y, 0), Vector3(cx, cy, 0), Vector3(cx, y_top, 0), Vector3(prev_x, y_top, 0), Vector3(xc, y_top, 1), mkey)
		quad(fr, Vector3(prev_x, prev_y, 0), Vector3(cx, cy, 0), Vector3(cx, cy, -T), Vector3(prev_x, prev_y, -T), Vector3(xc, spring * 0.5, -T * 0.5), mkey)
		prev_x = cx
		prev_y = cy


## Panel plano con forma de ventanal apuntado (de y0 hasta el arco) pegado a la pared, en z = zc.
func lancet(fr: Transform3D, xc: float, w: float, y0: float, spring: float, zc: float, mkey: String) -> void:
	var prev_x := xc - w * 0.5
	var prev_y := spring
	for i in range(1, 2 * ARCH_N + 1):
		var xr := -w * 0.5 + w * float(i) / float(2 * ARCH_N)
		var cx := xc + xr
		var cy := arch_y(xr, w, spring)
		quad(fr, Vector3(prev_x, y0, zc), Vector3(cx, y0, zc), Vector3(cx, cy, zc), Vector3(prev_x, prev_y, zc), Vector3(xc, y0, zc + 1.0), mkey)
		prev_x = cx
		prev_y = cy


## Nervadura: cajas pequeñas siguiendo la curva del arco, en el plano XY del transform `t`.
func rib_curve(t: Transform3D, xc: float, w: float, spring: float, zc: float, thick: float, depth: float, mkey: String, rr := 1.0) -> void:
	var prev := Vector3(xc - w * 0.5, spring, zc)
	for i in range(1, 2 * ARCH_N + 1):
		var xr := -w * 0.5 + w * float(i) / float(2 * ARCH_N)
		var cur := Vector3(xc + xr, arch_y(xr, w, spring, rr), zc)
		var seg := cur - prev
		var tt := t * Transform3D(Basis(Vector3(0, 0, 1), atan2(seg.y, seg.x)), (prev + cur) * 0.5)
		vbox_t(tt, Vector3(seg.length() + thick * 0.5, thick, depth), mkey)
		prev = cur


## Transform para un arco libre (entre columnas) cuyo plano es XY (axis_z = false) o ZY (axis_z = true) en `origin`.
static func arch_plane(origin: Vector3, axis_z: bool) -> Transform3D:
	if axis_z:
		return Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), origin)
	return Transform3D(Basis.IDENTITY, origin)


# ------------------------------------------------------------------ envolvente del cuarto

func build_floor(border := 1.4, main := "floor", edge := "floor2") -> void:
	var hw := dim.x * 0.5
	var hd := dim.z * 0.5
	box(Vector3(0, -0.4, 0), Vector3(dim.x + 2.0 * T, 0.8, dim.z + 2.0 * T), main)
	# cenefa de piedra más clara junto a los muros
	vbox(Vector3(0, 0.01, -hd + border * 0.5), Vector3(dim.x, 0.02, border), edge)
	vbox(Vector3(0, 0.01, hd - border * 0.5), Vector3(dim.x, 0.02, border), edge)
	vbox(Vector3(-hw + border * 0.5, 0.01, 0), Vector3(border, 0.02, dim.z - 2.0 * border), edge)
	vbox(Vector3(hw - border * 0.5, 0.01, 0), Vector3(border, 0.02, dim.z - 2.0 * border), edge)


## Techo con vigas oscuras. `across_x`: las vigas cruzan el cuarto a lo ancho (a lo largo de x) si es true.
func build_ceiling(beam_gap := 4.5, across_x := false) -> void:
	var h := dim.y
	box(Vector3(0, h + 0.4, 0), Vector3(dim.x + 2.0 * T, 0.8, dim.z + 2.0 * T), "ceiling")
	var span := dim.z if across_x else dim.x
	var n := maxi(1, roundi(span / beam_gap))
	var step := span / float(n)
	for i in range(1, n):
		var p := -span * 0.5 + step * float(i)
		if across_x:
			vbox(Vector3(0, h - 0.3, p), Vector3(dim.x, 0.6, 0.55), "beam")
		else:
			vbox(Vector3(p, h - 0.3, 0), Vector3(0.55, 0.6, dim.z), "beam")


func build_walls() -> void:
	for side in ["N", "S", "E", "W"]:
		_wall(side)


func _wall(side: String) -> void:
	var fr := frame_of(side)
	var big_l := inner_len(side) + (2.0 * T if (side == "N" or side == "S") else 0.0)
	var xs: Array = []
	for dd in doors:
		var d: Dictionary = dd
		if d["side"] == side:
			xs.append(local_x(side, float(d["at"])))
	xs.sort()
	var cur := -big_l * 0.5
	for xc in xs:
		var x0: float = xc - DOOR_W * 0.5
		var x1: float = xc + DOOR_W * 0.5
		if x0 > cur + 0.001:
			fbox(fr, cur, x0, 0.0, dim.y, -T, 0.0, "wall")
		arch_top(fr, xc, DOOR_W, DOOR_SPRING, dim.y, "wall")
		fcol(fr, x0, x1, DOOR_APEX, dim.y, -T, 0.0)
		_door_frame(fr, xc)
		cur = x1
	if cur < big_l * 0.5 - 0.001:
		fbox(fr, cur, big_l * 0.5, 0.0, dim.y, -T, 0.0, "wall")


## Jambas de piedra y nervadura apuntada alrededor de la puerta.
func _door_frame(fr: Transform3D, xc: float) -> void:
	var half := DOOR_W * 0.5
	for s in [-1.0, 1.0]:
		var xj: float = xc + s * (half + 0.2)
		fbox(fr, xj - 0.2, xj + 0.2, 0.0, DOOR_SPRING, 0.0, 0.2, "trim", false)
	rib_curve(fr, xc, DOOR_W + 0.8, DOOR_SPRING, 0.1, 0.3, 0.2, "trim")


## Zócalo, cornisa, pilastras y ventanales ciegos en una pared. Las pilastras y ventanas evitan las puertas.
func dress_wall(side: String, gap := 7.0, windows := true, win_w := 2.6) -> void:
	var fr := frame_of(side)
	var inner := inner_len(side)
	var h := dim.y
	var dxs: Array[float] = []
	for dd in doors:
		var d: Dictionary = dd
		if d["side"] == side:
			dxs.append(local_x(side, float(d["at"])))
	dxs.sort()
	# zócalo entre puertas
	var cur := -inner * 0.5
	for dx in dxs:
		var a: float = dx - DOOR_W * 0.5 - 0.4
		if a > cur + 0.01:
			fbox(fr, cur, a, 0.0, 0.5, 0.0, 0.18, "trim", false)
		cur = dx + DOOR_W * 0.5 + 0.4
	if cur < inner * 0.5 - 0.01:
		fbox(fr, cur, inner * 0.5, 0.0, 0.5, 0.0, 0.18, "trim", false)
	# cornisa
	fbox(fr, -inner * 0.5, inner * 0.5, h - 0.55, h, 0.0, 0.4, "trim", false)
	fbox(fr, -inner * 0.5, inner * 0.5, h - 0.7, h - 0.55, 0.0, 0.25, "stone", false)
	# pilastras y ventanales en cada tramo
	var n := maxi(1, roundi(inner / gap))
	var step := inner / float(n)
	for i in range(1, n):
		var x := -inner * 0.5 + step * float(i)
		if _near_door(x, dxs, 1.0) or _blocked(side, x, 0.7):
			continue
		_pilaster(fr, x, h)
	if not windows:
		return
	var spring := clampf(h * 0.45, 2.8, 5.0)
	var ww := win_w
	while spring + 0.866 * ww > h - 0.9 and ww > 1.4:
		ww -= 0.2
	for i in n:
		var x := -inner * 0.5 + step * (float(i) + 0.5)
		if _near_door(x, dxs, ww * 0.5 + 0.6) or _blocked(side, x, ww * 0.5 + 0.4):
			continue
		_blind_window(fr, x, ww, 1.6, spring)


## Reserva un tramo de muro (x local, semiancho) para que dress_wall no ponga ventanas ni pilastras ahí. Llamar antes de dress_wall.
func reserve(side: String, x: float, half: float) -> void:
	_blocks.append({"side": side, "x": x, "half": half})


func _blocked(side: String, x: float, margin: float) -> bool:
	for bl in _blocks:
		if bl["side"] == side and absf(x - float(bl["x"])) < float(bl["half"]) + margin:
			return true
	return false


func _near_door(x: float, dxs: Array[float], margin: float) -> bool:
	for dx in dxs:
		if absf(x - dx) < DOOR_W * 0.5 + margin:
			return true
	return false


func _pilaster(fr: Transform3D, x: float, h: float) -> void:
	fbox(fr, x - 0.65, x + 0.65, 0.0, 0.7, 0.0, 0.6, "trim")
	fbox(fr, x - 0.42, x + 0.42, 0.7, h - 0.9, 0.0, 0.42, "stone")
	fbox(fr, x - 0.65, x + 0.65, h - 0.9, h - 0.55, 0.0, 0.6, "trim", false)


## Ventanal apuntado ciego (vidrio oscuro con un resplandor frío) con marco de piedra.
func _blind_window(fr: Transform3D, x: float, w: float, y0: float, spring: float) -> void:
	lancet(fr, x, w, y0, spring, 0.03, "glass")
	rib_curve(fr, x, w + 0.5, spring, 0.07, 0.25, 0.14, "trim")
	for s in [-1.0, 1.0]:
		fbox(fr, x + s * (w * 0.5 + 0.125) - 0.125, x + s * (w * 0.5 + 0.125) + 0.125, y0 - 0.2, spring, 0.0, 0.14, "trim", false)
	fbox(fr, x - w * 0.5 - 0.25, x + w * 0.5 + 0.25, y0 - 0.35, y0 - 0.15, 0.0, 0.3, "trim", false)     # alféizar


## Chimenea o nicho hondo en un muro: hueco apuntado negro con marco, repisa y (opcional) llama con luz.
func hearth(side: String, x: float, w: float, h_open: float, fire := true) -> void:
	_blocks.append({"side": side, "x": x, "half": w * 0.5 + 1.3})      # llamarla ANTES de dress_wall/_shell
	var fr := frame_of(side)
	var spring := h_open
	lancet(fr, x, w, 0.0, spring, 0.04, "void")
	fbox(fr, x - w * 0.5 - 0.9, x - w * 0.5, 0.0, spring + 1.2, 0.0, 0.9, "stone")
	fbox(fr, x + w * 0.5, x + w * 0.5 + 0.9, 0.0, spring + 1.2, 0.0, 0.9, "stone")
	fbox(fr, x - w * 0.5 - 1.2, x + w * 0.5 + 1.2, spring + 1.2, spring + 1.6, 0.0, 1.2, "trim")           # repisa
	rib_curve(fr, x, w + 0.6, spring, 0.06, 0.3, 0.16, "trim")
	if fire:
		fbox(fr, x - 0.7, x + 0.7, 0.0, 0.25, 0.1, 0.9, "iron", false)                                        # leños
		fbox(fr, x - 0.5, x + 0.5, 0.25, 0.85, 0.15, 0.6, "flame", false)
		light(fr * Vector3(x, 1.4, 1.8), 0.9, 12.0, Color(0.95, 0.66, 0.44))


# ------------------------------------------------------------------ piezas sueltas

## Columna con base y capitel; colisión cilíndrica.
func column(x: float, z: float, r: float, h: float) -> void:
	vbox(Vector3(x, 0.3, z), Vector3(2.0 * r + 0.5, 0.6, 2.0 * r + 0.5), "trim")
	vcyl(Vector3(x, 0.6 + (h - 1.3) * 0.5, z), r, h - 1.3, "stone")
	vbox(Vector3(x, h - 0.35, z), Vector3(2.0 * r + 0.7, 0.7, 2.0 * r + 0.7), "trim")
	col_cyl(Vector3(x, h * 0.5, z), r + 0.25, h)


## Arco libre apuntado (de piedra) entre dos columnas: plano XY (axis_z = false) o ZY (true) con centro `origin`.
func free_arch(origin: Vector3, axis_z: bool, span: float) -> void:
	var rr := 0.62
	var spring := dim.y - 0.9 - arch_rise(span, rr)                 # la clave queda justo bajo el techo
	rib_curve(arch_plane(Vector3(origin.x, 0.0, origin.z), axis_z), 0.0, span, spring, 0.0, 0.55, 0.7, "trim", rr)


func rug(x: float, z: float, sx: float, sz: float, mkey := "rug") -> void:
	vbox(Vector3(x, 0.02, z), Vector3(sx, 0.04, sz), mkey)


func candle(pos: Vector3, h := 0.35) -> void:
	vbox(pos + Vector3(0, h * 0.5, 0), Vector3(0.1, h, 0.1), "candle")
	vbox(pos + Vector3(0, h + 0.07, 0), Vector3(0.07, 0.14, 0.07), "flame")


## Candelabro de pie con tres velas; `lit` agrega luz.
func candelabrum(x: float, z: float, y0 := 0.0, lit := false) -> void:
	vcyl(Vector3(x, y0 + 0.5, z), 0.07, 1.0, "iron")
	vbox(Vector3(x, y0 + 0.04, z), Vector3(0.5, 0.08, 0.5), "iron")
	vbox(Vector3(x, y0 + 1.02, z), Vector3(0.6, 0.06, 0.1), "iron")
	for dx in [-0.25, 0.0, 0.25]:
		candle(Vector3(x + dx, y0 + 1.05, z), 0.25)
	if lit:
		light(Vector3(x, y0 + 1.8, z), 0.5, 8.0)


## Candelabro colgante: aro octogonal de hierro con 8 velas, cadena al techo y una luz debajo.
func chandelier(pos: Vector3, r: float, energy: float, range_m: float, color := Color(0.95, 0.80, 0.60)) -> void:
	var seg := 2.0 * r * sin(PI / 8.0) + 0.08
	for i in 8:
		var a := TAU * float(i) / 8.0
		var c := pos + Vector3(cos(a) * r, 0.0, sin(a) * r)
		vbox_t(Transform3D(Basis(Vector3.UP, -a - PI * 0.5), c), Vector3(seg, 0.1, 0.12), "iron")
		vbox(c + Vector3(0, 0.22, 0), Vector3(0.1, 0.34, 0.1), "candle")
		vbox(c + Vector3(0, 0.46, 0), Vector3(0.07, 0.14, 0.07), "flame")
	vbox(pos, Vector3(0.3, 0.3, 0.3), "iron")
	var chain := dim.y - pos.y
	vbox(pos + Vector3(0, chain * 0.5, 0), Vector3(0.08, chain, 0.08), "iron")
	light(pos + Vector3(0, -0.9, 0), energy, range_m, color)


## Brasero: pie de hierro, cuenco y llama; `lit` agrega luz.
func brazier(x: float, z: float, lit := true) -> void:
	vcyl(Vector3(x, 0.45, z), 0.1, 0.9, "iron")
	vbox(Vector3(x, 0.05, z), Vector3(0.7, 0.1, 0.7), "iron")
	vcyl(Vector3(x, 1.05, z), 0.55, 0.3, "iron")
	vcyl(Vector3(x, 1.4, z), 0.32, 0.45, "flame")
	col_cyl(Vector3(x, 0.8, z), 0.5, 1.6)
	if lit:
		light(Vector3(x, 2.2, z), 0.7, 10.0, Color(0.95, 0.70, 0.48))


# ------------------------------------------------------------------ cierre

## Arma el cuarto: malla fundida por material, velos y sensores de las puertas. Devuelve el nodo raíz del cuarto.
func finish() -> Node3D:
	var keys := _st.keys()
	keys.sort()
	for k in keys:
		var st: SurfaceTool = _st[k]
		var mi := MeshInstance3D.new()
		mi.name = "M_" + str(k)
		mi.mesh = st.commit()
		mi.material_override = _mats[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
	_st.clear()
	for k in _qa.keys():
		var d: Dictionary = _qa[k]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(d["v"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(d["n"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(d["uv"])
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var qi := MeshInstance3D.new()
		qi.name = "Q_" + str(k)
		qi.mesh = am
		qi.material_override = _mats[k]
		qi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(qi)
	_qa.clear()
	for dd in doors:
		var d: Dictionary = dd
		var side: String = d["side"]
		var fr := frame_of(side)
		var lx := local_x(side, float(d["at"]))
		var veil := MeshInstance3D.new()
		veil.name = "Veil_" + str(d["to"])
		var qm := QuadMesh.new()
		qm.size = Vector2(DOOR_W + 0.3, DOOR_APEX + 0.1)
		veil.mesh = qm
		veil.material_override = _mats["veil"]
		veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		veil.transform = fr * Transform3D(Basis.IDENTITY, Vector3(lx, (DOOR_APEX + 0.1) * 0.5, -T * 0.5))
		node.add_child(veil)
		fcol(fr, lx - DOOR_W * 0.5, lx + DOOR_W * 0.5, 0.0, DOOR_APEX, -T, -0.3)      # tope: Andro se detiene en el umbral del velo
		var area := Area3D.new()
		area.name = "Door_" + str(d["to"])
		area.collision_layer = 0
		area.collision_mask = 1 << 1
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		var v := fr.basis * Vector3(DOOR_W - 0.2, 3.4, 0.1)
		sh.size = Vector3(absf(v.x), absf(v.y), absf(v.z))
		cs.shape = sh
		area.add_child(cs)
		area.position = fr * Vector3(lx, 1.7, -T * 0.5)
		node.add_child(area)
		door_areas.append({"area": area, "door": d})
	return node

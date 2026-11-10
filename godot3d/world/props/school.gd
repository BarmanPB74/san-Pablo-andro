class_name School
extends RefCounted
## Colegio contiguo a la iglesia del Sufragio (F3.2), al sur de la iglesia sobre la Cra 39, según el
## Street View de referencia: cuerpo largo de 4 niveles en pañete crema, cornisa ocre con dentículos,
## ventanas altas pareadas con marco ocre, balcón corrido con baranda de hierro en el segundo nivel,
## zócalo de piedra, portón con arco de medio punto y un patio delantero con reja.
## (El nombre del letrero es el del colegio real que está ahí; no hay logos ni marcas.)
##
## Marco local (igual que Church): origen = centro de la fachada a nivel del piso; la fachada mira a -Z
## local, +X recorre la fachada, el cuerpo se extiende hacia +Z (D m). Con Basis(UP, -PI/2):
## local (x, y, z) → mundo (ox - z, y, oz + x), es decir fachada al ESTE, +X local = +Z mundo (sur).

const L := 39.5            # largo de la fachada (a lo largo de la Cra 39)
const D := 13.0            # fondo del cuerpo
const H0 := 4.3            # alto del primer nivel
const HF := 3.4            # alto de cada nivel superior
const H := H0 + HF * 3.0   # 14.5 m hasta la cornisa
const BAYS := 10
const PITCH := L / BAYS
const BELOW := 3.0         # cuánto se hunde el cuerpo bajo el piso (absorbe la pendiente)
const PORTAL_BAY := 5
const FRONT := 4.6         # patio: distancia de la fachada a la reja (m)

static var _mesh: ArrayMesh
static var _wall: Material
static var _trim: Material
static var _base: Material
static var _dark: Material
static var _glass: Material
static var _metal: Material
static var _roof: Material
static var _white: Material


static func _mats() -> void:
	if _wall:
		return
	_wall = MatPlaster.stucco(Color(0.95, 0.92, 0.83))
	_trim = MatPlaster.stucco(Color(0.90, 0.74, 0.44))
	_base = MatPlaster.stone_base()
	_dark = WorldMaterials.dark_opening()
	_glass = Palette.window_glass()
	_metal = Palette.metal_dark()
	_roof = WorldMaterials.roof_flat()
	_white = MatPlaster.stucco(Color(0.97, 0.96, 0.92))


static func _T(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func portal_x() -> float:
	return -L * 0.5 + (PORTAL_BAY + 0.5) * PITCH


# ------------------------------------------------------------------ piezas
## Ventana alta de dos hojas con marco ocre. face = marco de la cara (su -Z es hacia afuera).
static func _window(k: McKit, face: Transform3D, cx: float, y0: float, w: float, h: float, grille: bool) -> void:
	var n := (face.basis * Vector3(0, 0, -1)).normalized()
	var P := func(x: float, y: float, z: float) -> Vector3: return face * Vector3(x, y, z)
	k.quad("dark", _dark, P.call(cx - w * 0.5, y0, -0.02), P.call(cx + w * 0.5, y0, -0.02), P.call(cx + w * 0.5, y0 + h, -0.02), P.call(cx - w * 0.5, y0 + h, -0.02), n)
	for s: float in [-1.0, 1.0]:
		var a := cx + s * 0.04
		var b := cx + s * (w * 0.5 - 0.06)
		var lo := minf(a, b)
		var hi := maxf(a, b)
		k.quad("glass", _glass, P.call(lo, y0 + 0.06, -0.05), P.call(hi, y0 + 0.06, -0.05), P.call(hi, y0 + h - 0.06, -0.05), P.call(lo, y0 + h - 0.06, -0.05), n)
	k.box("white", _white, face * _T(cx, y0 + h * 0.5, -0.07), Vector3(0.08, h, 0.07), 0.0, "xXyYz")
	k.box("white", _white, face * _T(cx, y0 + h * 0.62, -0.07), Vector3(w, 0.06, 0.07), 0.0, "xXyYz")
	for s: float in [-1.0, 1.0]:
		k.box("trim", _trim, face * _T(cx + s * (w * 0.5 + 0.09), y0 + h * 0.5, -0.07), Vector3(0.18, h + 0.1, 0.14), 0.0, "xXyYz")
	k.box("trim", _trim, face * _T(cx, y0 + h + 0.12, -0.11), Vector3(w + 0.6, 0.24, 0.22), 0.0, "xXyYz")
	k.box("trim", _trim, face * _T(cx, y0 - 0.06, -0.11), Vector3(w + 0.42, 0.12, 0.22), 0.0, "xXyYz")
	if grille:
		var nb := 7
		for i in nb:
			var bx := cx - w * 0.5 + w * (float(i) + 0.5) / float(nb)
			k.box("metal", _metal, face * _T(bx, y0 + h * 0.5, -0.17), Vector3(0.022, h, 0.022), 0.0, "xXyYz")
		for ry: float in [0.12, 0.5, 0.88]:
			k.box("metal", _metal, face * _T(cx, y0 + h * ry, -0.17), Vector3(w, 0.03, 0.03), 0.0, "xXyYz")


## Vano oscuro de medio punto (rectángulo + medio disco) en el plano z del marco.
static func _arch_panel(k: McKit, face: Transform3D, cx: float, y0: float, w: float, hr: float, z: float) -> void:
	var r := w * 0.5
	var n := (face.basis * Vector3(0, 0, -1)).normalized()
	k.quad("dark", _dark, face * Vector3(cx - r, y0, z), face * Vector3(cx + r, y0, z), face * Vector3(cx + r, y0 + hr, z), face * Vector3(cx - r, y0 + hr, z), n)
	var segs := 10
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		k.tri("dark", _dark, face * Vector3(cx, y0 + hr, z), face * Vector3(cx + cos(a0) * r, y0 + hr + sin(a0) * r, z), face * Vector3(cx + cos(a1) * r, y0 + hr + sin(a1) * r, z), n)


## Ventanas de una cara: n bayas de ancho `pitch` centradas en x = 0; ancho total = n * pitch.
## skip = baya con portal (sin ventana en el primer nivel); balcony_from = primera baya con balcón corrido.
static func _face_windows(k: McKit, face: Transform3D, n: int, pitch: float, skip := -1, balcony_from := 99) -> void:
	for i in n:
		var cx := -pitch * float(n) * 0.5 + (float(i) + 0.5) * pitch
		if i != skip:
			_window(k, face, cx, 1.55, 1.5, 1.45, true)
		for f in 3:
			if f == 0 and i == skip:
				continue   # sobre el portal va el letrero del colegio
			var y0 := H0 + HF * float(f) + 0.5
			var hh := 1.95
			if f == 0 and i >= balcony_from:
				y0 = H0 + 0.12
				hh = 2.4
			_window(k, face, cx, y0, 2.0, hh, false)


## Cuerpo del colegio (todas las caras visibles) como una sola malla.
static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	_mats()
	var k := McKit.new()
	# Volumen principal y zócalo.
	k.box("wall", _wall, _T(0, (H - BELOW) * 0.5, D * 0.5), Vector3(L, H + BELOW, D), 0.0, "xXzZ")
	k.box("base", _base, _T(0, (1.15 - BELOW) * 0.5, -0.09), Vector3(L + 0.2, 1.15 + BELOW, 0.18), 0.0, "xXyYz")
	# Azotea y pretil.
	k.quad("roof", _roof, Vector3(-L * 0.5, H, 0.0), Vector3(L * 0.5, H, 0.0), Vector3(L * 0.5, H, D), Vector3(-L * 0.5, H, D), Vector3.UP)
	k.box("wall", _wall, _T(0, H + 0.45, 0.2), Vector3(L, 0.9, 0.4), 0.0, "xXyYzZ")
	k.box("trim", _trim, _T(0, H + 0.93, 0.2), Vector3(L + 0.12, 0.12, 0.52), 0.0, "xXyYzZ")
	# Cornisa con dentículos y bandas de entrepiso.
	k.box("trim", _trim, _T(0, H - 0.3, -0.3), Vector3(L + 0.24, 0.6, 0.6), 0.0, "xXyYz")
	var nd := int(L / 0.46)
	for i in nd:
		var dx := -L * 0.5 + 0.23 + (L - 0.46) * float(i) / float(nd - 1)
		k.box("trim", _trim, _T(dx, H - 0.72, -0.14), Vector3(0.2, 0.22, 0.2), 0.0, "xXyz")
	for f in 3:
		k.box("trim", _trim, _T(0, H0 + HF * float(f) - 0.02, -0.07), Vector3(L + 0.1, 0.22, 0.14), 0.0, "xXyYz")
	# Pilastras de esquina y a los lados del portal.
	for s: float in [-1.0, 1.0]:
		k.box("trim", _trim, _T(s * (L * 0.5 - 0.3), (H - BELOW) * 0.5 + 0.55, -0.1), Vector3(0.6, H - 1.1 + BELOW, 0.2), 0.0, "xXyYz")
	var px := portal_x()
	for s: float in [-1.0, 1.0]:
		k.box("trim", _trim, _T(px + s * 2.35, (H0 + 1.15) * 0.5 + 0.55, -0.12), Vector3(0.5, H0 + 0.5, 0.24), 0.0, "xXyYz")
	# Ventanas de la fachada (balcón corrido en las tres bayas del sur) y de los costados.
	var front := Transform3D.IDENTITY
	_face_windows(k, front, BAYS, PITCH, PORTAL_BAY, 7)
	var south := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(L * 0.5, 0, D * 0.5))
	_face_windows(k, south, 3, D / 3.0)
	var west := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, D))
	_face_windows(k, west, BAYS, PITCH)
	# Balcón corrido del segundo nivel (bayas 7..9): losa con borde ocre. La baranda se coloca aparte.
	var bx0 := -L * 0.5 + 7.0 * PITCH
	var bw := L * 0.5 - bx0
	k.box("trim", _trim, _T(bx0 + bw * 0.5, H0 - 0.1, -0.55), Vector3(bw, 0.2, 1.1), 0.0, "xXyYz")
	for i in 4:
		var cx := bx0 + (float(i) + 0.5) * bw / 4.0
		k.box("trim", _trim, _T(cx, H0 - 0.45, -0.18), Vector3(0.22, 0.5, 0.3), 0.0, "xXyz")
	# Portal con arco de medio punto, jambas, escalones y puerta de hierro.
	var pw := 3.0
	var pr := pw * 0.5
	var ys := 2.55
	_arch_panel(k, front, px, 0.0, pw, ys, -0.03)
	k.arch("trim", _trim, _T(px, ys, 0), pr, pr + 0.4, -0.22, 0.22, 12, "fi")
	for s: float in [-1.0, 1.0]:
		k.box("trim", _trim, _T(px + s * (pr + 0.2), ys * 0.5, -0.11), Vector3(0.4, ys, 0.22), 0.0, "xXyYz")
	k.box("trim", _trim, _T(px, ys + pr + 0.45, -0.14), Vector3(0.55, 0.5, 0.28), 0.0, "xXyYz")
	for i in 2:
		var top := -0.15 + 0.13 * float(i)
		k.box("trim", _trim, _T(px, (top - 0.5) * 0.5, -1.05 + 0.5 * float(i)), Vector3(pw + 1.2, top + 0.5, 0.5), 0.0, "xXyYz")
	var nb := 10
	for i in nb + 1:
		var bxp := px - pr + 0.1 + (pw - 0.2) * float(i) / float(nb)
		k.box("metal", _metal, _T(bxp, 1.5, -0.1), Vector3(0.035, 3.0, 0.035), 0.0, "xXyYz")
	for ry: float in [0.15, 1.5, 2.95]:
		k.box("metal", _metal, _T(px, ry, -0.1), Vector3(pw - 0.1, 0.07, 0.05), 0.0, "xXyYz")
	# Placa del letrero sobre el arco (el texto va como Label3D).
	k.box("metal", _metal, _T(px, H0 + 1.55, -0.14), Vector3(6.6, 1.05, 0.1), 0.0, "xXyYz")
	k.box("trim", _trim, _T(px, H0 + 1.55, -0.1), Vector3(6.9, 1.3, 0.04), 0.0, "xXyYz")
	_mesh = k.commit()
	return _mesh


# ------------------------------------------------------------------ colocación
## xf = marco del colegio (ver arriba). Coloca cuerpo, baranda, reja del patio, letrero y colisiones.
static func build(d: Node, xf: Transform3D) -> void:
	_mats()
	d.place_mesh("p32_school", mesh(), xf, true)
	var bx0 := -L * 0.5 + 7.0 * PITCH
	var bw := L * 0.5 - bx0
	d.place_mesh("p32_school_rail_%d" % int(bw), Buildings.rail_metal(bw), xf * _T(bx0 + bw * 0.5, H0 + 0.0, -1.0), true)
	d.add_col_box(xf * _T(0, H * 0.5, D * 0.5), Vector3(L, H, D))
	# Letrero.
	var lt := xf * Transform3D(Basis(Vector3.UP, PI), Vector3(portal_x(), H0 + 1.55, -0.21))
	d._label("COLEGIO EL SUFRAGIO", lt, Color(0.96, 0.94, 0.86), 64, 0.0095)
	# Reja del patio con portón abierto frente al portal: muro bajo + barrotes (mundo → marco local).
	var gate := 1.7
	var segs := [[-L * 0.5 - 1.0, portal_x() - gate], [portal_x() + gate, L * 0.5 + 0.5]]
	for sg in segs:
		_fence(d, xf, sg[0], sg[1])


## Muro bajo con reja de hierro entre u0 y u1 (coordenada local X) a FRONT m de la fachada.
static func _fence(d: Node, xf: Transform3D, u0: float, u1: float) -> void:
	var len := u1 - u0
	var key := "p32_fence_%d" % int(round(len * 10.0))
	var k := McKit.new()
	k.box("base", _base, _T(len * 0.5, 0.3, 0), Vector3(len, 0.6, 0.3), 0.0, "xXyYzZ")
	k.box("metal", _metal, _T(len * 0.5, 1.48, 0), Vector3(len, 0.06, 0.06), 0.0, "xXyYzZ")
	k.box("metal", _metal, _T(len * 0.5, 0.72, 0), Vector3(len, 0.04, 0.04), 0.0, "xXyYzZ")
	var np := maxi(2, int(round(len / 2.4)) + 1)
	for i in np:
		var px := len * float(i) / float(np - 1)
		k.box("metal", _metal, _T(px, 1.05, 0), Vector3(0.12, 1.1, 0.12), 0.0, "xXyYzZ")
		k.box("metal", _metal, _T(px, 1.66, 0), Vector3(0.16, 0.12, 0.16), 0.0, "xXyYzZ")
	var nb := int(len / 0.14)
	for i in nb:
		var bx := 0.07 + (len - 0.14) * float(i) / float(nb - 1)
		k.box("metal", _metal, _T(bx, 1.1, 0), Vector3(0.016, 0.8, 0.016), 0.0, "xXyYzZ")
	var m := k.commit()
	var f := xf * _T(u0, 0.0, -FRONT)
	d.place_mesh(key, m, f, false)
	d.add_col_box(f * _T(len * 0.5, 0.8, 0), Vector3(len, 1.6, 0.3))

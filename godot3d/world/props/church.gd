class_name Church
extends RefCounted
## Iglesia neorrománica de Nuestra Señora del Sufragio (Calle 55 #39-61), F2-05.
## Marco local: origen = centro de la fachada a nivel del piso de la iglesia; la fachada mira a -Z (norte,
## Calle 55), +X = este, la nave se extiende hacia +Z (42.5 m) con ábside semicircular al fondo.
## Fachada: dos torres campanario (5.2 m, remate piramidal de piedra con pináculos), cuerpo central con
## pórtico avanzado (arquivoltas de medio punto en tres órdenes sobre columnillas), rosetón con tracería,
## piñón con arquillos lombardos escalonados, ventanas geminadas (ajimeces), cornisas y bandas lombardas.
## Pañete crema (MatPlaster.stucco) + sillar de arenisca (MatStone.sillar) en zócalos, cornisas, esquinas y
## portadas; escalinata de granito (MatStone.granito). Mallas cacheadas en static var.

const W := 18.0          # ancho de la nave
const L := 42.5          # largo de la nave (fachada → fondo)
const NAVE_H := 15.0
const TW_X := 8.5        # eje de cada torre
const TW_Z := 1.8
const TW_HS := 2.6       # semilado de torre
const BODY_HX := 5.9     # semiancho visible del cuerpo central (entre torres)

static var _body: ArrayMesh
static var _front: ArrayMesh
static var _extras := {}

static var _plaster: Material
static var _sillar: Material
static var _dark: Material


static func _mats() -> void:
	if _plaster:
		return
	_plaster = MatPlaster.stucco(Color(0.95, 0.84, 0.72))
	_sillar = MatStone.sillar()
	if ClayStyle.enabled:
		# pueblo de plastilina: iglesia de ladrillo rojo con remates de piedra
		_plaster = MatBrick.fachada_vieja(Color(0.92, 0.8, 0.8))
	_dark = WorldMaterials.dark_opening()


## Coloca la iglesia. xf = marco local (ver arriba). step_drop = desnivel (m) entre el piso de la iglesia
## y el andén al pie de la escalinata (6 peldaños desde z = -3.5).
static func build(d: Node, xf := Transform3D.IDENTITY, step_drop := 1.7) -> void:
	d.place_mesh("p2church_body", body(), xf, true)
	d.place_mesh("p2church_front", front(), xf, true)
	d.place_mesh("p2church_extras", extras(step_drop), xf, true)
	# Colisiones propias del detalle nuevo (el distrito conserva podio, peldaños, nave, torres y ábside):
	# pórtico avanzado y muretes laterales de la escalinata.
	d.add_col_box(xf * _T(0, 4.5, -0.7), Vector3(8.0, 9.0, 0.6))
	for s: float in [-1.0, 1.0]:
		for i in 3:
			var p := _parapet(step_drop, i)
			d.add_col_box(xf * _T(s * PARAPET_X, p.y, p.z), Vector3(0.7, p.x, -p.w))


const PARAPET_X := 8.65


## Murete i (0..2): Vector4(alto, y_centro, z_centro, z0).
static func _parapet(step_drop: float, i: int) -> Vector4:
	var top := -step_drop + step_drop * float(2 * i + 2) / 6.0 + 0.35
	var z0 := -3.5 + 1.1 * i
	return Vector4(3.0, top - 1.5, z0 * 0.5, z0)


# ------------------------------------------------------------------ utilidades de cara/fachada
## Marco de una cara de torre/muro: local -Z = normal hacia afuera, origen en el plano de la cara.
static func _face(cx: float, cz: float, hs: float, k: int) -> Transform3D:
	var angs := [0.0, -PI * 0.5, PI, PI * 0.5]
	var b := Basis(Vector3.UP, angs[k])
	return Transform3D(b, Vector3(cx, 0, cz) + b * Vector3(0, 0, -hs))


static func _T(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## Vano oscuro de medio punto (rectángulo + medio disco) en el plano z del marco.
static func _apanel(k: McKit, xf: Transform3D, cx: float, y0: float, w: float, hr: float, z := -0.01) -> void:
	var r := w * 0.5
	var n := (xf.basis * Vector3(0, 0, -1)).normalized()
	k.quad("dark", _dark, xf * Vector3(cx - r, y0, z), xf * Vector3(cx + r, y0, z), xf * Vector3(cx + r, y0 + hr, z), xf * Vector3(cx - r, y0 + hr, z), n)
	var segs := 8
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		k.tri("dark", _dark, xf * Vector3(cx, y0 + hr, z), xf * Vector3(cx + cos(a0) * r, y0 + hr + sin(a0) * r, z), xf * Vector3(cx + cos(a1) * r, y0 + hr + sin(a1) * r, z), n)


## Ventana de medio punto con derrame: vano oscuro + arco de sillar + alféizar.
static func _window(k: McKit, xf: Transform3D, cx: float, y0: float, w: float, hr: float) -> void:
	_apanel(k, xf, cx, y0, w, hr, -0.02)
	var r := w * 0.5
	k.arch("sillar", _sillar, xf * _T(cx, y0 + hr, 0), r, r + 0.2, -0.12, 0.12, 7, "fi")
	for s: float in [-1.0, 1.0]:
		k.box("sillar", _sillar, xf * _T(cx + s * (r + 0.1), y0 + hr * 0.5, -0.06), Vector3(0.2, hr, 0.12), 0.0, "z")
	k.box("sillar", _sillar, xf * _T(cx, y0 - 0.07, -0.1), Vector3(w + 0.55, 0.14, 0.2), 0.0, "xXzY")


## Ventana geminada (ajimez): dos luces de medio punto separadas por columnilla, bajo un arco mayor.
static func _ajimez(k: McKit, xf: Transform3D, cx: float, y0: float, w: float, hr: float) -> void:
	var wl := (w - 0.2) * 0.5
	var rl := wl * 0.5
	for s: float in [-1.0, 1.0]:
		var lx := cx + s * (wl * 0.5 + 0.1)
		_apanel(k, xf, lx, y0, wl, hr, -0.02)
		k.arch("sillar", _sillar, xf * _T(lx, y0 + hr, 0), rl, rl + 0.1, -0.08, 0.08, 6, "fi")
	# Columnilla con basa y capitel.
	k.cyl("sillar", _sillar, xf * Vector3(cx, y0 + 0.12, -0.1), xf * Vector3(cx, y0 + hr - 0.12, -0.1), 0.065, 0.06, 6, false)
	k.box("sillar", _sillar, xf * _T(cx, y0 + 0.06, -0.1), Vector3(0.2, 0.12, 0.2), 0.0, "xXzY")
	k.box("sillar", _sillar, xf * _T(cx, y0 + hr - 0.06, -0.1), Vector3(0.24, 0.14, 0.24), 0.0, "xXzYy")
	# Arco mayor que abraza el par.
	var R := w * 0.5 + 0.05
	k.arch("sillar", _sillar, xf * _T(cx, y0 + hr, 0), R, R + 0.2, -0.14, 0.14, 8, "fi")
	for s: float in [-1.0, 1.0]:
		k.box("sillar", _sillar, xf * _T(cx + s * (R + 0.1), y0 + hr * 0.5, -0.07), Vector3(0.2, hr, 0.14), 0.0, "xXz")
	k.box("sillar", _sillar, xf * _T(cx, y0 - 0.08, -0.12), Vector3(w + 0.7, 0.16, 0.24), 0.0, "xXzY")


## Banda de arquillos ciegos lombardos entre x0 y x1 con arranque en y (ménsulas colgantes).
static func _lombard(k: McKit, xf: Transform3D, x0: float, x1: float, y: float, sp: float) -> void:
	var n := maxi(1, int(round((x1 - x0) / sp)))
	var s := (x1 - x0) / float(n)
	var r := s * 0.5
	for i in n:
		var cx := x0 + s * (i + 0.5)
		k.arch("sillar", _sillar, xf * _T(cx, y, 0), r - 0.07, r, -0.09, 0.09, 3, "fi")
	for i in n + 1:
		k.box("sillar", _sillar, xf * _T(x0 + s * i, y - 0.1, -0.06), Vector3(0.14, 0.24, 0.12), 0.0, "xXzy")
	k.box("sillar", _sillar, xf * _T((x0 + x1) * 0.5, y + r + 0.08, -0.07), Vector3(x1 - x0 + 0.1, 0.16, 0.14), 0.02, "xXzYy")


## Cornisa perimetral en un prisma cuadrado (torres): dos escalones de sillar con bisel.
static func _cornice(k: McKit, cx: float, cz: float, hs: float, y: float) -> void:
	k.box("sillar", _sillar, _T(cx, y - 0.12, cz), Vector3(hs * 2 + 0.22, 0.24, hs * 2 + 0.22), 0.03, "xXzZy")
	k.box("sillar", _sillar, _T(cx, y + 0.12, cz), Vector3(hs * 2 + 0.5, 0.26, hs * 2 + 0.5), 0.05)


# ------------------------------------------------------------------ cuerpo: nave, ábside, torres
static func body() -> ArrayMesh:
	if _body:
		return _body
	_mats()
	var k := McKit.new()
	var roof := MatPlaster.roof_clay(false, Vector3(0.5, 0.5, 1.0))
	var hx := W * 0.5
	var zt := TW_Z + TW_HS       # fondo de las torres
	# --- Muros laterales de la nave (pañete) con zócalo de sillar.
	for s: float in [-1.0, 1.0]:
		var n := Vector3(s, 0, 0)
		k.quad("plaster", _plaster, Vector3(s * hx, -1.0, zt), Vector3(s * hx, -1.0, L), Vector3(s * hx, NAVE_H, L), Vector3(s * hx, NAVE_H, zt), n)
		k.box("sillar", _sillar, _T(s * (hx + 0.06), 0.45, (zt + L) * 0.5), Vector3(0.12, 1.9, L - zt), 0.03, "xXY")
		# Contrafuertes y ventanas entre ellos.
		var z := zt + 2.5
		var bz: Array = []
		while z < L - 1.0:
			bz.append(z)
			z += 6.0
		bz.append(L - 0.45)
		for zz: float in bz:
			k.box("sillar", _sillar, _T(s * (hx + 0.35), 5.5, zz), Vector3(0.7, 13.0, 0.9), 0.04, "xXzZ")
			k.square_lathe("sillar", _sillar, _T(s * (hx + 0.35), 0.0, zz), [Vector2(0.45, -1.0), Vector2(0.45, 1.6), Vector2(0.35, 1.75)], 0.03, false, Vector2(0.78, 1.0))
			k.box("sillar", _sillar, Transform3D(Basis(Vector3.BACK, s * 0.6), Vector3(s * (hx + 0.25), 12.15, zz)), Vector3(0.55, 0.6, 0.92), 0.0, "xXzZY")
		var fb := Transform3D(Basis(Vector3.UP, -s * PI * 0.5), Vector3(s * hx, 0, 0))
		for i in bz.size() - 1:
			var zc: float = (bz[i] + bz[i + 1]) * 0.5
			# Marco fb: local -Z = +sX mundo; local +X = +sZ mundo.
			var lx := zc * s
			_window(k, fb, lx, 5.0, 1.5, 4.2)
		# Banda lombarda bajo el alero.
		var la := zt if s > 0.0 else -L
		var lb := L if s > 0.0 else -zt
		_lombard(k, fb, la + 0.4, lb - 0.4, 13.9, 1.2)
		# Cornisa de alero.
		k.box("sillar", _sillar, _T(s * (hx + 0.2), NAVE_H - 0.2, (zt + L) * 0.5), Vector3(0.4, 0.4, L - zt + 0.4), 0.05, "xXyYZ")
	# Tramo del muro lateral entre el cuerpo central y las torres está oculto por las torres.
	
	# --- Muro trasero (piñón sobre el ábside).
	k.quad("plaster", _plaster, Vector3(-hx, -1.0, L), Vector3(hx, -1.0, L), Vector3(hx, NAVE_H, L), Vector3(-hx, NAVE_H, L), Vector3.BACK)
	k.tri("plaster", _plaster, Vector3(-hx, NAVE_H, L), Vector3(hx, NAVE_H, L), Vector3(0, NAVE_H + 5.0, L), Vector3.BACK)
	# --- Techo a dos aguas de teja (UV: V a lo largo de la pendiente).
	var rz0 := 0.3
	var rz1 := L + 0.6
	var eave := Vector2(hx + 0.75, NAVE_H - 0.3)
	var ridge := Vector2(0.0, NAVE_H + 5.0)
	var slope_len := eave.distance_to(ridge)
	for s: float in [-1.0, 1.0]:
		var a := Vector3(s * eave.x, eave.y, rz0)
		var b := Vector3(s * eave.x, eave.y, rz1)
		var c := Vector3(0, ridge.y, rz1)
		var dd := Vector3(0, ridge.y, rz0)
		var n := (Vector3(s * (ridge.y - eave.y), eave.x, 0)).normalized()
		k.quad_uv("roof", roof, [a, b, c, dd], [Vector2(rz0, slope_len), Vector2(rz1, slope_len), Vector2(rz1, 0), Vector2(rz0, 0)], n)
		# Canto del alero (espesor) y faldón inferior.
		var a2 := a + Vector3(0, -0.18, 0)
		var b2 := b + Vector3(0, -0.18, 0)
		k.quad("sillar", _sillar, a2, b2, b, a, Vector3(s, 0, 0))
		k.quad("plaster", _plaster, Vector3(s * hx, eave.y - 0.18, rz0), Vector3(s * hx, eave.y - 0.18, rz1), b2, a2, Vector3.DOWN)
	# Cumbrera.
	k.box("roof", roof, _T(0, ridge.y + 0.05, (rz0 + rz1) * 0.5), Vector3(0.4, 0.22, rz1 - rz0), 0.06, "xXYzZ")
	# --- Ábside semicircular con zócalo, contrafuertes, ventanas y cubierta cónica de teja.
	var ar := 7.5
	var ah := 12.0
	var asg := 16
	k.lathe("plaster", _plaster, _T(0, 0, L), [Vector2(ar, -1.0), Vector2(ar, ah)], asg)
	k.lathe("sillar", _sillar, _T(0, 0, L), [Vector2(ar + 0.12, -1.0), Vector2(ar + 0.12, 0.9), Vector2(ar, 1.05)], asg)
	k.lathe("sillar", _sillar, _T(0, 0, L), [Vector2(ar, ah - 0.5), Vector2(ar + 0.25, ah - 0.3), Vector2(ar + 0.3, ah)], asg)
	for i in 5:
		var a := PI * (0.12 + 0.19 * i)
		var dir := Vector3(cos(a), 0, sin(a))
		var bp := Vector3(0, 0, L) + dir * (ar + 0.3)
		var bb := Basis(Vector3.UP, -a + PI * 0.5)
		k.box("sillar", _sillar, Transform3D(bb, bp + Vector3(0, 5.2, 0)), Vector3(0.8, 12.4, 0.6), 0.04, "xXzZ")
		if i < 4:
			var wa := PI * (0.215 + 0.19 * i)
			var wdir := Vector3(cos(wa), 0, sin(wa))
			var wf := Transform3D(Basis(Vector3.UP, -wa - PI * 0.5), Vector3(0, 0, L) + wdir * (ar + 0.01))
			_window(k, wf, 0.0, 4.5, 1.2, 3.4)
	# Cono de teja (quads por sector con UV radiales).
	var cone_r := ar + 0.7
	var apex := Vector3(0, ah + 3.6, L)
	var slant := Vector2(cone_r, 3.6).length()
	for i in asg:
		var a0 := TAU * float(i) / asg
		var a1 := TAU * float(i + 1) / asg
		var p0 := Vector3(cos(a0) * cone_r, ah - 0.15, L + sin(a0) * cone_r)
		var p1 := Vector3(cos(a1) * cone_r, ah - 0.15, L + sin(a1) * cone_r)
		var am := (a0 + a1) * 0.5
		var n := Vector3(cos(am) * 3.6, cone_r, sin(am) * 3.6).normalized()
		var arc := cone_r * (a1 - a0)
		k.quad_uv("roof", roof, [p0, p1, apex + (p1 - apex) * 0.02, apex + (p0 - apex) * 0.02], [Vector2(0, slant), Vector2(arc, slant), Vector2(arc * 0.02, 0), Vector2(0, 0)], n)
	
	# --- Torres campanario.
	for s: float in [-1.0, 1.0]:
		_tower(k, s * TW_X, TW_Z, s)
	_body = k.commit()
	return _body


static func _tower(k: McKit, tx: float, tz: float, side: float) -> void:
	var hs := TW_HS
	var top := 22.0
	# Fuste de pañete (caras exteriores) y esquineros de sillar.
	k.box("plaster", _plaster, _T(tx, (top - 1.5) * 0.5, tz), Vector3(hs * 2, top + 1.5, hs * 2), 0.0, "xXzZ")
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box("sillar", _sillar, _T(tx + sx * (hs - 0.25), (top - 1.5) * 0.5, tz + sz * (hs - 0.25)), Vector3(0.62, top + 1.5, 0.62), 0.03, "xXzZ")
	# Zócalo.
	k.square_lathe("sillar", _sillar, _T(tx, 0, tz), [Vector2(hs + 0.18, -1.5), Vector2(hs + 0.18, 1.2), Vector2(hs + 0.08, 1.35), Vector2(hs + 0.04, 1.35)], 0.04, false)
	# Cornisas de nivel y bandas lombardas en las caras visibles (frente, exterior, fondo alto).
	_cornice(k, tx, tz, hs, 8.0)
	_cornice(k, tx, tz, hs, 15.0)
	_cornice(k, tx, tz, hs, top)
	var outer := 1 if side > 0.0 else 3
	for kf in [0, outer]:
		var f := _face(tx, tz, hs + 0.0, kf)
		_lombard(k, f, -hs + 0.55, hs - 0.55, top - 0.65, 0.8)
	# Vanos: frente → puerta lateral (en front()), ventana alta, ajimez, reloj/óculo.
	for kf in [0, outer, 2]:
		var f := _face(tx, tz, hs, kf)
		if kf != 2:
			_window(k, f, 0.0, 4.6 if kf == 0 else 3.2, 0.8, 2.0 if kf == 0 else 2.6)
			_ajimez(k, f, 0.0, 10.0, 2.1, 2.3)
		if kf == outer:
			_window(k, f, 0.0, 16.6, 0.8, 2.6)
	# Óculo en la torre occidental (la oriental lleva el reloj, ver extras()).
	if side < 0.0:
		var f0 := _face(tx, tz, hs, 0)
		for i in 2:
			k.arch("sillar", _sillar, f0 * Transform3D(Basis(Vector3.BACK, PI * i), Vector3(0, 18.6, 0)), 0.75, 1.0, -0.14, 0.14, 8, "fio")
		var n := (f0.basis * Vector3(0, 0, -1)).normalized()
		for i in 12:
			var a0 := TAU * i / 12.0
			var a1 := TAU * (i + 1) / 12.0
			k.tri("dark", _dark, f0 * Vector3(0, 18.6, -0.02), f0 * Vector3(cos(a0) * 0.75, 18.6 + sin(a0) * 0.75, -0.02), f0 * Vector3(cos(a1) * 0.75, 18.6 + sin(a1) * 0.75, -0.02), n)
	# Campanario (cuerpo de campanas) retranqueado con ajimeces abiertos en las 4 caras.
	var bh := 4.6 * 0.5
	var by0 := top + 0.25
	var by1 := 28.0
	k.box("plaster", _plaster, _T(tx, (by0 + by1) * 0.5, tz), Vector3(bh * 2, by1 - by0, bh * 2), 0.0, "xXzZ")
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box("sillar", _sillar, _T(tx + sx * (bh - 0.2), (by0 + by1) * 0.5, tz + sz * (bh - 0.2)), Vector3(0.5, by1 - by0, 0.5), 0.03, "xXzZ")
	for kf in 4:
		var f := _face(tx, tz, bh, kf)
		_ajimez(k, f, 0.0, by0 + 0.6, 2.6, 2.4)
		_lombard(k, f, -bh + 0.45, bh - 0.45, by1 - 0.55, 0.75)
	_cornice(k, tx, tz, bh, by1 + 0.1)
	# Remate piramidal de piedra con pináculos en las esquinas.
	k.square_lathe("sillar", _sillar, _T(tx, 0, tz), [Vector2(bh + 0.15, by1 + 0.36), Vector2(bh - 0.05, by1 + 0.7), Vector2(0.06, 35.2)], 0.04, true)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.square_lathe("sillar", _sillar, _T(tx + sx * (bh + 0.02), 0, tz + sz * (bh + 0.02)), [Vector2(0.24, by1 + 0.3), Vector2(0.24, by1 + 0.85), Vector2(0.3, by1 + 0.95), Vector2(0.02, by1 + 2.4)], 0.02, true)


# ------------------------------------------------------------------ fachada central: pórtico, rosetón, piñón
static func front() -> ArrayMesh:
	if _front:
		return _front
	_mats()
	var k := McKit.new()
	var wood := Palette.wood()
	var bx := BODY_HX
	var wz := -0.4               # plano del muro de la fachada central
	var px := 3.5                # semiancho del pórtico avanzado
	var pz := -1.0               # frente del pórtico
	var ph := 7.2                # alto del pórtico (hasta la cornisa)
	var ys := 3.6                # arranque de las arquivoltas
	var N := Vector3(0, 0, -1)
	# --- Muro central (pañete) en piezas alrededor del pórtico.
	var P := func(x: float, y: float) -> Vector3: return Vector3(x, y, wz)
	k.quad("plaster", _plaster, P.call(-bx, -0.5), P.call(-px, -0.5), P.call(-px, 18.0), P.call(-bx, 18.0), N)
	k.quad("plaster", _plaster, P.call(px, -0.5), P.call(bx, -0.5), P.call(bx, 18.0), P.call(px, 18.0), N)
	k.quad("plaster", _plaster, P.call(-px, ph), P.call(px, ph), P.call(px, 18.0), P.call(-px, 18.0), N)
	# Zócalo del muro central.
	for s: float in [-1.0, 1.0]:
		k.box("sillar", _sillar, _T(s * (px + bx) * 0.5, 0.35, wz - 0.06), Vector3(bx - px, 1.3, 0.12), 0.02, "zY")
	# Lesenas (pilastras planas) y cornisa del cuerpo central con banda lombarda.
	for s: float in [-1.0, 1.0]:
		k.box("sillar", _sillar, _T(s * 4.7, 9.0, wz - 0.08), Vector3(0.6, 18.0, 0.16), 0.03, "xXz")
	_lombard(k, Transform3D(Basis.IDENTITY, Vector3(0, 0, wz)), -bx + 0.2, bx - 0.2, 17.35, 0.85)
	k.box("sillar", _sillar, _T(0, 18.05, wz - 0.25), Vector3(bx * 2, 0.4, 0.5), 0.05, "zyY")
	# --- Piñón con arquillos escalonados, cornisas inclinadas, óculo y cruz.
	var gh := 4.4
	var g0 := 18.25
	k.tri("plaster", _plaster, P.call(-bx, g0), P.call(bx, g0), P.call(0, g0 + gh), N)
	var ang := atan2(gh, bx)
	var rl := Vector2(bx, gh).length()
	for s: float in [-1.0, 1.0]:
		var rb := Basis(Vector3.BACK, -s * ang)
		k.box("sillar", _sillar, Transform3D(rb, Vector3(s * bx * 0.5, g0 + gh * 0.5 + 0.22, wz - 0.22)), Vector3(rl + 0.5, 0.36, 0.56), 0.05, "xXzZyY")
		for i in 5:
			var t := (float(i) + 0.7) / 5.6
			var cx := s * bx * (1.0 - t)
			var cy := g0 + gh * t - 0.75
			k.arch("sillar", _sillar, _T(cx, cy, wz), 0.36, 0.46, -0.1, 0.1, 4, "fi")
			for e: float in [-1.0, 1.0]:
				k.box("sillar", _sillar, _T(cx + e * 0.41, cy - 0.16, wz - 0.05), Vector3(0.1, 0.32, 0.1), 0.0, "xXz")
	# Óculo del piñón.
	for i in 2:
		k.arch("sillar", _sillar, Transform3D(Basis(Vector3.BACK, PI * i), Vector3(0, g0 + 1.6, wz)), 0.45, 0.65, -0.12, 0.12, 8, "fio")
	for i in 10:
		var a0 := TAU * i / 10.0
		var a1 := TAU * (i + 1) / 10.0
		k.tri("dark", _dark, Vector3(0, g0 + 1.6, wz - 0.02), Vector3(cos(a0) * 0.45, g0 + 1.6 + sin(a0) * 0.45, wz - 0.02), Vector3(cos(a1) * 0.45, g0 + 1.6 + sin(a1) * 0.45, wz - 0.02), N)
	k.box("sillar", _sillar, _T(0, g0 + gh + 0.45, wz - 0.22), Vector3(0.7, 0.6, 0.7), 0.05)
	# --- Pórtico avanzado de sillar: frente con vano de medio punto, costados, piñoncito y cornisa.
	k.wall_with_arch("sillar", _sillar, Transform3D.IDENTITY, -px, px, -0.5, ph, pz, 0.0, 3.0, ys, N, 10)
	for s: float in [-1.0, 1.0]:
		k.quad("sillar", _sillar, Vector3(s * px, -0.5, pz), Vector3(s * px, -0.5, wz), Vector3(s * px, ph, wz), Vector3(s * px, ph, pz), Vector3(s, 0, 0))
		# Contrafuertes del pórtico.
		k.box("sillar", _sillar, _T(s * (px + 0.25), ph * 0.5 - 0.3, pz + 0.25), Vector3(0.5, ph + 0.6, 0.5), 0.04, "xXzZ")
	k.box("sillar", _sillar, _T(0, ph + 0.15, (pz + wz) * 0.5 - 0.1), Vector3(px * 2 + 1.2, 0.3, wz - pz + 0.4), 0.05)
	var pgh := 1.7
	k.tri("sillar", _sillar, Vector3(-px, ph + 0.3, pz), Vector3(px, ph + 0.3, pz), Vector3(0, ph + 0.3 + pgh, pz), N)
	var pang := atan2(pgh, px)
	var prl := Vector2(px, pgh).length()
	for s: float in [-1.0, 1.0]:
		var rb := Basis(Vector3.BACK, -s * pang)
		k.box("sillar", _sillar, Transform3D(rb, Vector3(s * px * 0.5, ph + 0.3 + pgh * 0.5 + 0.18, (pz + wz) * 0.5 - 0.05)), Vector3(prl + 0.5, 0.3, wz - pz + 0.5), 0.05)
		# Arquillos lombardos bajo la cornisa inclinada del pórtico.
		for i in 3:
			var t := (float(i) + 0.8) / 3.8
			k.arch("sillar", _sillar, _T(s * px * (1.0 - t), ph + 0.3 + pgh * t - 0.5, pz), 0.24, 0.31, -0.08, 0.08, 4, "fi")
	# Cruz de piedra sobre el piñoncito.
	k.box("sillar", _sillar, _T(0, ph + 0.3 + pgh + 0.5, pz + 0.2), Vector3(0.16, 0.9, 0.16), 0.02)
	k.box("sillar", _sillar, _T(0, ph + 0.3 + pgh + 0.65, pz + 0.2), Vector3(0.55, 0.15, 0.16), 0.02)
	# Arquivoltas en tres órdenes (cada una más adelantada) sobre jambas escalonadas con columnillas.
	var orders := 3
	for o in orders:
		var r0 := 1.8 + 0.4 * o
		var z0 := -0.33 * (o + 1)
		var zb := -0.33 * o
		if o == orders - 1:
			z0 = pz
		k.arch("sillar", _sillar, _T(0, ys, 0), r0, r0 + 0.4, z0, zb - z0, 12, "fi")
		# Toro (bocel) en el borde de cada arquivolta.
		var tor: Array = []
		for i in 13:
			var a := PI * i / 12.0
			tor.append(Vector3(cos(a) * (r0 + 0.02), ys + sin(a) * (r0 + 0.02), z0 - 0.02))
		k.tube("sillar", _sillar, tor, [0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08], 5, false, Vector3(0, 0, -1))
		for s: float in [-1.0, 1.0]:
			# Jamba.
			k.box("sillar", _sillar, _T(s * (r0 + 0.2), ys * 0.5 - 0.25, (z0 + zb) * 0.5), Vector3(0.4, ys + 0.5, zb - z0), 0.0, "xXz")
			# Imposta corrida.
			k.box("sillar", _sillar, _T(s * (r0 + 0.2), ys - 0.08, z0 + 0.02), Vector3(0.5, 0.16, 0.12), 0.02, "xXzYy")
			# Columnilla adosada: basa ática, fuste, capitel cúbico.
			var cxp := s * (r0 + 0.02)
			var cz := z0 - 0.02
			k.square_lathe("sillar", _sillar, _T(cxp, 0, cz), [Vector2(0.2, -0.3), Vector2(0.2, 0.35), Vector2(0.16, 0.45)], 0.03, true)
			k.cyl("sillar", _sillar, Vector3(cxp, 0.45, cz), Vector3(cxp, ys - 0.38, cz), 0.115, 0.105, 7, false)
			k.square_lathe("sillar", _sillar, _T(cxp, 0, cz), [Vector2(0.13, ys - 0.4), Vector2(0.21, ys - 0.12), Vector2(0.21, ys - 0.02)], 0.02, true)
	# Dintel, tímpano liso (pañete) y puertas de madera con herrajes.
	k.box("sillar", _sillar, _T(0, ys + 0.12, -0.08), Vector3(3.7, 0.24, 0.16), 0.02, "xXzyY")
	var segs := 12
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		k.tri("plaster", _plaster, Vector3(0, ys + 0.24, -0.01), Vector3(cos(a0) * 1.8, ys + 0.24 + sin(a0) * 1.56, -0.01), Vector3(cos(a1) * 1.8, ys + 0.24 + sin(a1) * 1.56, -0.01), N)
	# Crismón/cruz en relieve en el tímpano.
	k.box("sillar", _sillar, _T(0, ys + 1.0, -0.05), Vector3(0.14, 0.9, 0.08), 0.02)
	k.box("sillar", _sillar, _T(0, ys + 1.15, -0.05), Vector3(0.6, 0.14, 0.08), 0.02)
	for s: float in [-1.0, 1.0]:
		k.box("wood", wood, _T(s * 0.9, ys * 0.5, 0.02), Vector3(1.78, ys, 0.1), 0.02, "zxX")
		for yy: float in [0.6, 1.8, 3.0]:
			k.box("wood", wood, _T(s * 0.9, yy, -0.05), Vector3(1.6, 0.12, 0.05), 0.01, "zyY")
	# Puertas laterales (bajo las torres): portada de medio punto de sillar sobre madera oscura.
	for s: float in [-1.0, 1.0]:
		var tf := _face(s * TW_X, TW_Z, TW_HS, 0)
		var nn := (tf.basis * Vector3(0, 0, -1)).normalized()
		for i in 2:
			k.arch("sillar", _sillar, tf * Transform3D(Basis.IDENTITY, Vector3(0, 2.6, 0)), 0.95 + 0.25 * i, 1.2 + 0.25 * i, -0.12 * (i + 1), 0.12, 10, "fi")
			for e: float in [-1.0, 1.0]:
				k.box("sillar", _sillar, tf * _T(e * (1.075 + 0.25 * i), 1.15, -0.06 * (i + 1)), Vector3(0.25, 2.9, 0.12 * (i + 1)), 0.02, "xXz")
		k.box("wood", wood, tf * _T(0, 1.3, -0.02), Vector3(1.9, 2.6, 0.04), 0.0, "z")
		for i in 8:
			var a0 := PI * float(i) / 8.0
			var a1 := PI * float(i + 1) / 8.0
			k.tri("wood", wood, tf * Vector3(0, 2.6, -0.02), tf * Vector3(cos(a0) * 0.95, 2.6 + sin(a0) * 0.95, -0.02), tf * Vector3(cos(a1) * 0.95, 2.6 + sin(a1) * 0.95, -0.02), nn)
	# --- Rosetón: marco escalonado de sillar, tracería radial y vitral (en extras()).
	var rc := Vector3(0, 11.3, wz)
	for i in 2:
		var rb := Basis(Vector3.BACK, PI * i)
		k.arch("sillar", _sillar, Transform3D(rb, rc), 2.1, 2.45, -0.36, 0.36, 12, "fio")
		k.arch("sillar", _sillar, Transform3D(rb, rc), 2.45, 2.8, -0.2, 0.2, 12, "fo")
		k.arch("sillar", _sillar, Transform3D(rb, rc + Vector3(0, 0, -0.08)), 0.8, 0.95, -0.12, 0.12, 8, "fio")
	for i in 12:
		var a := TAU * i / 12.0
		var dir := Vector3(cos(a), sin(a), 0)
		k.box("sillar", _sillar, Transform3D(Basis(Vector3.BACK, a - PI * 0.5), rc + dir * 1.52 + Vector3(0, 0, -0.14)), Vector3(0.1, 1.2, 0.12), 0.0, "xXz")
		# Lóbulos (arquillos) en el borde del rosetón.
		k.arch("sillar", _sillar, Transform3D(Basis(Vector3.BACK, a - PI * 0.5), rc + dir * 1.82 + Vector3(0, 0, -0.06)), 0.22, 0.3, -0.1, 0.1, 4, "fi")
	k.cyl("sillar", _sillar, rc + Vector3(0, 0, 0.0), rc + Vector3(0, 0, -0.2), 0.32, 0.3, 10, true)
	_front = k.commit()
	return _front


# ------------------------------------------------------------------ extras: escalinata, vitral, reloj, cruces, puertas de torre
static func extras(step_drop: float) -> ArrayMesh:
	var key := str(snappedf(step_drop, 0.01))
	if _extras.has(key):
		return _extras[key]
	_mats()
	var k := McKit.new()
	var gran := MatStone.granito()
	var metal := Palette.metal_dark()
	# Escalinata de granito: 6 peldaños con nariz biselada, entre muretes laterales escalonados.
	var steps := 6
	for i in steps:
		var top := -step_drop + step_drop * float(i + 1) / steps
		var z0 := -3.5 + 0.55 * i
		var bot := top - 2.5
		k.box("granito", gran, _T(0, (top + bot) * 0.5, (z0 + 0.0) * 0.5), Vector3(18.0, top - bot, -z0), 0.025, "xXYz")
	for s: float in [-1.0, 1.0]:
		for i in 3:
			var p := _parapet(step_drop, i)
			k.box("granito", gran, _T(s * PARAPET_X, p.y, p.z), Vector3(0.7, p.x, -p.w), 0.04, "xXYz")
	# Vitral del rosetón (emisión tenue) y del óculo.
	var rc := Vector3(0, 11.3, -0.4)
	var vit := WorldMaterials.rosette()
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		k.tri("vitral", vit, rc + Vector3(0, 0, -0.03), rc + Vector3(cos(a0) * 2.12, sin(a0) * 2.12, -0.03), rc + Vector3(cos(a1) * 2.12, sin(a1) * 2.12, -0.03), Vector3(0, 0, -1))
	# Reloj en la torre oriental.
	var f := _face(TW_X, TW_Z, TW_HS, 0)
	var cc := f * Vector3(0, 18.6, 0)
	var n := (f.basis * Vector3(0, 0, -1)).normalized()
	k.cyl("metal", metal, cc, cc + n * 0.12, 1.12, 1.12, 20, true)
	var face_m := WorldMaterials.clock_face()
	for i in 20:
		var a0 := TAU * i / 20.0
		var a1 := TAU * (i + 1) / 20.0
		k.tri("reloj", face_m, cc + n * 0.13, cc + n * 0.13 + Vector3(cos(a0), sin(a0), 0) * 0.98, cc + n * 0.13 + Vector3(cos(a1), sin(a1), 0) * 0.98, n)
	for i in 12:
		var a := TAU * i / 12.0
		k.box("metal", metal, Transform3D(Basis(Vector3.BACK, a), cc + n * 0.15 + Vector3(sin(a), cos(a), 0) * 0.82), Vector3(0.05, 0.16 if i % 3 == 0 else 0.09, 0.02), 0.0, "zxXyY")
	k.box("metal", metal, Transform3D(Basis(Vector3.BACK, 0.5), cc + n * 0.17 + Vector3(-0.12, 0.22, 0)), Vector3(0.06, 0.5, 0.02), 0.0, "zxXyY")
	k.box("metal", metal, Transform3D(Basis(Vector3.BACK, -1.2), cc + n * 0.17 + Vector3(-0.28, -0.11, 0)), Vector3(0.05, 0.68, 0.02), 0.0, "zxXyY")
	# Cruces de hierro sobre los remates de las torres y el piñón.
	for p: Vector3 in [Vector3(-TW_X, 35.1, TW_Z), Vector3(TW_X, 35.1, TW_Z), Vector3(0, 23.1, -0.62)]:
		k.box("metal", metal, _T(p.x, p.y + 0.9, p.z), Vector3(0.09, 1.8, 0.09), 0.0)
		k.box("metal", metal, _T(p.x, p.y + 1.25, p.z), Vector3(0.8, 0.08, 0.08), 0.0)
		k.ellipsoid("metal", metal, _T(p.x, p.y + 0.1, p.z), Vector3(0.14, 0.14, 0.14), 6, 3)
	var mesh := k.commit()
	_extras[key] = mesh
	return mesh

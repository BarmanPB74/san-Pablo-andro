class_name ParkFurniture
extends RefCounted
## F2-06 — Mobiliario y bordes del Parque de Boston (refs. 1, 2, 4 y 5).
## Todas las funciones devuelven ArrayMesh multi-superficie CACHEADAS (una construcción por variante).
## Convenciones locales: Y arriba, suelo en y = 0, "frente" del mueble = +Z local.
## Los Mat* de la Fase 1 son triplanar en mundo: las UV generadas solo sirven para las tangentes.
##
## Piezas:
##   planter_wall()     muro de jardinera enchapado en PIZARRA, 1 m de largo en X (escalar X al largo
##                      del tramo), grosor 0.30, alto 0.45 sobre el piso (0.08 enterrado). z ∈ [-0.15, 0.15].
##   planter_corner()   bloque de pizarra 0.30 × 0.30 para esquinas entrantes.
##   path_curb()        bordillo de concreto 1 m en X (escalable), 0.16 de ancho, asoma 0.05.
##   fence_segment()    reja baja verde de 1.9 m (poste en x = 0, barrotes, pasamanos), base y = 0, alto 0.66.
##   fence_post()       poste suelto para cerrar un tramo de reja.
##   granite_bench(v)   banca de granito maciza (v = 0 losa sobre 2 bloques, v = 1 bloque monolítico).
##   wood_bench()       banca de listones de madera con costados de hierro fundido (frente +Z).
##   park_lamp(v)       farol de hierro fundido (v = 0 linterna hexagonal, v = 1 globo). Luz a LAMP_LIGHT_Y.
##   park_bin()         caneca de parque: canasta de listones verdes sobre poste.
##   food_cart(v)       carrito callejero (v % 3: 0 mango, 1 arepas, 2 salpicón; v cambia colores).
##                      Largo en X (manubrio en -X, ruedas en +X), mostrador hacia +Z.

const LAMP_LIGHT_Y := 3.95
const FENCE_LEN := 1.9
const FENCE_H := 0.66
const WALL_H := 0.45
const WALL_T := 0.30

static var _cache := {}
static var stats := {}   # clave → triángulos (para informes)


# ------------------------------------------------------------------ materiales
## Hierro fundido pintado verde muy oscuro (faroles, costados de banca).
static func iron() -> Material:
	return MatMetal.green_paint({"tint": Color(0.36, 0.42, 0.38)})


## Esmalte verde de las rejas bajas.
static func fence_paint() -> Material:
	return MatMetal.green_paint()


## Material de color por vértice (lona de sombrilla, pintura del carrito, fruta, llantas).
static func paint_vc() -> Material:
	if not _cache.has("mat_vc"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.62
		m.cull_mode = BaseMaterial3D.CULL_BACK
		_cache["mat_vc"] = m
	return _cache["mat_vc"]


## Vidrio claro de vitrina (transparente, poco brillo).
static func glass() -> Material:
	if not _cache.has("mat_glass"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.82, 0.9, 0.95, 0.18)
		m.roughness = 0.06
		m.metallic_specular = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["mat_glass"] = m
	return _cache["mat_glass"]


## Vidrio esmerilado encendido de los faroles.
static func lamp_glass() -> Material:
	return Palette.lamp_bulb()


# ------------------------------------------------------------------ constructor
class MB:
	var sts := {}
	var mats := {}
	var order: Array = []
	var tris := 0
	var col := Color.WHITE

	func _s(mat: Material) -> SurfaceTool:
		var id := mat.get_instance_id()
		if not sts.has(id):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[id] = st
			mats[id] = mat
			order.append(id)
		return sts[id]

	static func uvp(p: Vector3, n: Vector3) -> Vector2:
		var a := n.abs()
		if a.y >= a.x and a.y >= a.z:
			return Vector2(p.x, p.z)
		if a.x >= a.z:
			return Vector2(p.z, -p.y)
		return Vector2(p.x, -p.y)

	func tri_n(mat: Material, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
		var st := _s(mat)
		var ref := na + nb + nc
		if (b - a).cross(c - a).dot(ref) > 0.0:
			var t := b
			b = c
			c = t
			var tn := nb
			nb = nc
			nc = tn
		var fn := ref.normalized()
		for v in [[a, na], [b, nb], [c, nc]]:
			st.set_color(col)
			st.set_normal(v[1])
			st.set_uv(uvp(v[0], fn))
			st.add_vertex(v[0])
		tris += 1

	func tri(mat: Material, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
		tri_n(mat, a, b, c, n, n, n)

	func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		tri(mat, a, b, c, n)
		tri(mat, a, c, d, n)

	## Caja con chaflán en las 12 aristas. faces: letras de caras a dibujar (x=-X, X=+X, ...).
	func box(mat: Material, xf: Transform3D, size: Vector3, bevel := 0.0, faces := "xXyYzZ") -> void:
		var h := size * 0.5
		var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
		var ins := h - Vector3(b, b, b)
		var bas := xf.basis
		var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		var keys := ["xX", "yY", "zZ"]
		for ai in 3:
			for s: float in [-1.0, 1.0]:
				if not faces.contains(keys[ai][0 if s < 0.0 else 1]):
					continue
				var n: Vector3 = axes[ai] * s
				var u: Vector3 = axes[(ai + 1) % 3]
				var v: Vector3 = axes[(ai + 2) % 3]
				var hu: float = ins[(ai + 1) % 3]
				var hv: float = ins[(ai + 2) % 3]
				var c := n * h[ai]
				quad(mat, xf * (c - u * hu - v * hv), xf * (c + u * hu - v * hv), xf * (c + u * hu + v * hv), xf * (c - u * hu + v * hv), (bas * n).normalized())
		if b <= 0.0:
			return
		for ai in 3:
			var u: Vector3 = axes[(ai + 1) % 3]
			var v: Vector3 = axes[(ai + 2) % 3]
			var e: Vector3 = axes[ai]
			for su: float in [-1.0, 1.0]:
				for sv: float in [-1.0, 1.0]:
					var p1: Vector3 = u * su * h[(ai + 1) % 3] + v * sv * ins[(ai + 2) % 3]
					var p2: Vector3 = u * su * ins[(ai + 1) % 3] + v * sv * h[(ai + 2) % 3]
					var he: float = ins[ai]
					var n := (u * su + v * sv).normalized()
					quad(mat, xf * (p1 - e * he), xf * (p1 + e * he), xf * (p2 + e * he), xf * (p2 - e * he), (bas * n).normalized())
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					tri(mat, xf * Vector3(sx * h.x, sy * ins.y, sz * ins.z), xf * Vector3(sx * ins.x, sy * h.y, sz * ins.z),
						xf * Vector3(sx * ins.x, sy * ins.y, sz * h.z), (bas * Vector3(sx, sy, sz)).normalized())

	## Barra (caja) entre a y b; `side` = eje lateral aproximado (debe ser ⟂ a b-a).
	func beam(mat: Material, a: Vector3, b: Vector3, w: float, t: float, side := Vector3.RIGHT, bevel := 0.0, faces := "xXyYzZ") -> void:
		var y := (b - a)
		var l := y.length()
		y = y / l
		var x := (side - y * side.dot(y)).normalized()
		var z := x.cross(y).normalized()
		box(mat, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, l, t), bevel, faces)

	## Torno: profile = [Vector2(r, y), ...] de abajo hacia arriba. smooth = normales suaves alrededor.
	func lathe(mat: Material, xf: Transform3D, profile: Array, sides: int, smooth := true, cap_top := true, rot := 0.0) -> void:
		for i in profile.size() - 1:
			var p0: Vector2 = profile[i]
			var p1: Vector2 = profile[i + 1]
			var d := p1 - p0
			if d.length() < 1e-6:
				continue
			var pn := Vector2(d.y, -d.x).normalized()   # (radial, y)
			for j in sides:
				var a0 := rot + TAU * j / sides
				var a1 := rot + TAU * (j + 1) / sides
				var c0 := Vector3(cos(a0), 0, sin(a0))
				var c1 := Vector3(cos(a1), 0, sin(a1))
				var n0: Vector3
				var n1: Vector3
				if smooth:
					n0 = (c0 * pn.x + Vector3.UP * pn.y).normalized()
					n1 = (c1 * pn.x + Vector3.UP * pn.y).normalized()
				else:
					var cm := ((c0 + c1) * 0.5).normalized()
					n0 = (cm * pn.x + Vector3.UP * pn.y).normalized()
					n1 = n0
				var bn := xf.basis
				var A := xf * (c0 * p0.x + Vector3.UP * p0.y)
				var B := xf * (c1 * p0.x + Vector3.UP * p0.y)
				var C := xf * (c1 * p1.x + Vector3.UP * p1.y)
				var D := xf * (c0 * p1.x + Vector3.UP * p1.y)
				var wn0 := (bn * n0).normalized()
				var wn1 := (bn * n1).normalized()
				if p0.x > 1e-5:
					tri_n(mat, A, B, C, wn0, wn1, wn1)
				if p1.x > 1e-5:
					tri_n(mat, A, C, D, wn0, wn1, wn0)
		var last: Vector2 = profile[profile.size() - 1]
		if cap_top and last.x > 1e-5:
			var top := xf * Vector3(0, last.y, 0)
			for j in sides:
				var a0 := rot + TAU * j / sides
				var a1 := rot + TAU * (j + 1) / sides
				tri(mat, top, xf * Vector3(cos(a0) * last.x, last.y, sin(a0) * last.x),
					xf * Vector3(cos(a1) * last.x, last.y, sin(a1) * last.x), (xf.basis * Vector3.UP).normalized())

	## Cilindro entre dos puntos.
	func cyl(mat: Material, a: Vector3, b: Vector3, r: float, sides: int, caps := true) -> void:
		var axis := (b - a).normalized()
		var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var x := axis.cross(ref).normalized()
		var z := x.cross(axis).normalized()
		var xf := Transform3D(Basis(x, axis, z), a)
		var l := (b - a).length()
		var prof := [Vector2(0, 0), Vector2(r, 0), Vector2(r, l), Vector2(0, l)] if caps else [Vector2(r, 0), Vector2(r, l)]
		lathe(mat, xf, prof, sides, true, false)

	## Extrusión en X (x0..x1) de una sección convexa [(z, y)] en orden perimetral. caps = tapas planas.
	func extrude_x(mat: Material, xf: Transform3D, sec: Array, x0: float, x1: float, caps := true) -> void:
		var n := sec.size()
		var cen := Vector2.ZERO
		for p: Vector2 in sec:
			cen += p
		cen /= float(n)
		for i in n:
			var p0: Vector2 = sec[i]
			var p1: Vector2 = sec[(i + 1) % n]
			var e := p1 - p0
			var nn := Vector2(e.y, -e.x).normalized()
			if nn.dot((p0 + p1) * 0.5 - cen) < 0.0:
				nn = -nn
			var wn := (xf.basis * Vector3(0, nn.y, nn.x)).normalized()
			quad(mat, xf * Vector3(x0, p0.y, p0.x), xf * Vector3(x1, p0.y, p0.x), xf * Vector3(x1, p1.y, p1.x), xf * Vector3(x0, p1.y, p1.x), wn)
		if caps:
			for i in range(1, n - 1):
				var a: Vector2 = sec[0]
				var b: Vector2 = sec[i]
				var c: Vector2 = sec[i + 1]
				tri(mat, xf * Vector3(x0, a.y, a.x), xf * Vector3(x0, b.y, b.x), xf * Vector3(x0, c.y, c.x), (xf.basis * Vector3.LEFT).normalized())
				tri(mat, xf * Vector3(x1, a.y, a.x), xf * Vector3(x1, b.y, b.x), xf * Vector3(x1, c.y, c.x), (xf.basis * Vector3.RIGHT).normalized())

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for id in order:
			var st: SurfaceTool = sts[id]
			st.generate_tangents()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[id])
		return mesh


static func _done(key: String, b: MB) -> ArrayMesh:
	var m := b.commit()
	_cache[key] = m
	stats[key] = b.tris
	return m


# ------------------------------------------------------------------ jardineras y bordes
static func planter_wall() -> ArrayMesh:
	if _cache.has("wall"):
		return _cache["wall"]
	var b := MB.new()
	var h := WALL_H
	var t := WALL_T * 0.5
	var c := 0.03
	# Sección con chaflán en las aristas superiores (los extremos son planos: se escala en X).
	b.extrude_x(MatStone.pizarra(), Transform3D.IDENTITY,
		[Vector2(-t, -0.08), Vector2(t, -0.08), Vector2(t, h - c), Vector2(t - c, h), Vector2(-t + c, h), Vector2(-t, h - c)], 0.0, 1.0, true)
	return _done("wall", b)


static func planter_corner() -> ArrayMesh:
	if _cache.has("corner"):
		return _cache["corner"]
	var b := MB.new()
	b.box(MatStone.pizarra(), Transform3D(Basis.IDENTITY, Vector3(0, (WALL_H - 0.08) * 0.5, 0)), Vector3(WALL_T, WALL_H + 0.08, WALL_T), 0.02, "xXyzZ")
	return _done("corner", b)


static func path_curb() -> ArrayMesh:
	if _cache.has("curb"):
		return _cache["curb"]
	var b := MB.new()
	b.extrude_x(MatPaving.curb(), Transform3D.IDENTITY,
		[Vector2(-0.08, -0.06), Vector2(0.08, -0.06), Vector2(0.08, 0.035), Vector2(0.065, 0.05), Vector2(-0.065, 0.05), Vector2(-0.08, 0.035)], 0.0, 1.0, false)
	return _done("curb", b)


static func _post(b: MB, x: float) -> void:
	var m := fence_paint()
	b.box(m, Transform3D(Basis.IDENTITY, Vector3(x, FENCE_H * 0.5 - 0.02, 0)), Vector3(0.05, FENCE_H + 0.04, 0.05), 0.006, "xXyzZ")
	# Capitel y remate de bola.
	b.box(m, Transform3D(Basis.IDENTITY, Vector3(x, FENCE_H + 0.03, 0)), Vector3(0.07, 0.02, 0.07), 0.004)
	b.lathe(m, Transform3D(Basis.IDENTITY, Vector3(x, FENCE_H + 0.04, 0)),
		[Vector2(0.012, 0.0), Vector2(0.03, 0.02), Vector2(0.034, 0.04), Vector2(0.026, 0.062), Vector2(0.0, 0.075)], 6, true, false)
	# Placa de anclaje con pernos sobre el muro.
	b.box(m, Transform3D(Basis.IDENTITY, Vector3(x, 0.005, 0)), Vector3(0.11, 0.012, 0.11), 0.0, "xXYzZ")


static func fence_segment() -> ArrayMesh:
	if _cache.has("fence"):
		return _cache["fence"]
	var b := MB.new()
	var m := fence_paint()
	_post(b, 0.0)
	var x0 := 0.025
	var x1 := FENCE_LEN - 0.025
	# Pasamanos (platina con borde redondeado) y travesaño inferior.
	b.extrude_x(m, Transform3D.IDENTITY, [Vector2(-0.025, 0.585), Vector2(0.025, 0.585), Vector2(0.025, 0.6), Vector2(0.015, 0.612), Vector2(-0.015, 0.612), Vector2(-0.025, 0.6)], x0, x1, false)
	b.box(m, Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, 0.09, 0)), Vector3(x1 - x0, 0.03, 0.012), 0.0, "yYzZ")
	b.box(m, Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, 0.53, 0)), Vector3(x1 - x0, 0.025, 0.012), 0.0, "yYzZ")
	# Barrotes cuadrados cada ~12 cm.
	var n := 15
	for i in n:
		var x := lerpf(0.12, FENCE_LEN - 0.12, float(i) / (n - 1))
		b.box(m, Transform3D(Basis.IDENTITY, Vector3(x, 0.33, 0)), Vector3(0.016, 0.52, 0.016), 0.0, "xXzZ")
	return _done("fence", b)


static func fence_post() -> ArrayMesh:
	if _cache.has("fence_post"):
		return _cache["fence_post"]
	var b := MB.new()
	_post(b, 0.0)
	return _done("fence_post", b)


# ------------------------------------------------------------------ bancas
static func granite_bench(v: int) -> ArrayMesh:
	var key := "gbench_%d" % (v % 2)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var top := MatStone.granito()
	var dirty := MatStone.granito_sucio()
	if v % 2 == 0:
		# Losa gruesa sobre dos bloques (ref. 1).
		b.box(top, Transform3D(Basis.IDENTITY, Vector3(0, 0.39, 0)), Vector3(1.9, 0.13, 0.5), 0.018)
		for x: float in [-0.62, 0.62]:
			b.box(dirty, Transform3D(Basis.IDENTITY, Vector3(x, 0.155, 0)), Vector3(0.24, 0.39, 0.4), 0.012, "xXyYzZ")
	else:
		# Bloque monolítico con zócalo rehundido.
		b.box(top, Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0)), Vector3(1.6, 0.36, 0.52), 0.03)
		b.box(dirty, Transform3D(Basis.IDENTITY, Vector3(0, 0.04, 0)), Vector3(1.5, 0.14, 0.44), 0.01, "xXzZ")
	return _done(key, b)


static func wood_bench() -> ArrayMesh:
	if _cache.has("wbench"):
		return _cache["wbench"]
	var b := MB.new()
	var w := Palette.wood()
	var fe := iron()
	# Costados de hierro fundido (perfil en el plano YZ).
	for x: float in [-0.78, 0.78]:
		var P := func(z: float, y: float) -> Vector3: return Vector3(x, y, z)
		var segs := [
			[P.call(0.2, -0.02), P.call(0.2, 0.42)],      # pata delantera
			[P.call(-0.21, -0.02), P.call(-0.17, 0.42)],  # pata trasera
			[P.call(0.25, 0.41), P.call(-0.2, 0.41)],     # apoyo del asiento
			[P.call(-0.17, 0.4), P.call(-0.27, 0.88)],    # respaldo
			[P.call(0.2, 0.4), P.call(0.23, 0.64)],       # parante del brazo
			[P.call(0.26, 0.64), P.call(-0.2, 0.67)],     # brazo
			[P.call(0.19, 0.1), P.call(-0.2, 0.1)],       # travesaño bajo
		]
		for s in segs:
			b.beam(fe, s[0], s[1], 0.045, 0.05, Vector3.RIGHT, 0.008)
		# Voluta del brazo y zapatas.
		b.lathe(fe, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x - 0.03, 0.645, 0.26)), [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.06), Vector2(0.0, 0.06)], 8, true, false)
		for z: float in [0.2, -0.21]:
			b.box(fe, Transform3D(Basis.IDENTITY, Vector3(x, 0.01, z)), Vector3(0.07, 0.03, 0.09), 0.006, "xXYzZ")
	# Listones del asiento.
	for z: float in [0.19, 0.085, -0.02, -0.125]:
		b.box(w, Transform3D(Basis.IDENTITY, Vector3(0, 0.45, z)), Vector3(1.86, 0.035, 0.088), 0.008)
	# Listones del respaldo (siguen la inclinación).
	var r0 := Vector3(0, 0.4, -0.17)
	var r1 := Vector3(0, 0.88, -0.27)
	var up := (r1 - r0).normalized()
	var fw := Vector3.RIGHT.cross(up).normalized()
	if fw.z < 0.0:
		fw = -fw
	for t: float in [0.42, 0.66, 0.9]:
		var c := r0.lerp(r1, t) + fw * 0.045
		b.box(w, Transform3D(Basis(Vector3.RIGHT, up, Vector3.RIGHT.cross(up)), c), Vector3(1.86, 0.1, 0.03), 0.008)
	# Pernos (cabezas) en los listones sobre los costados.
	for x: float in [-0.78, 0.78]:
		for z: float in [0.19, 0.085, -0.02, -0.125]:
			b.box(fe, Transform3D(Basis.IDENTITY, Vector3(x, 0.47, z)), Vector3(0.018, 0.006, 0.018), 0.0, "xXYzZ")
	return _done("wbench", b)


# ------------------------------------------------------------------ farol
static func park_lamp(v: int) -> ArrayMesh:
	var key := "lamp_%d" % (v % 2)
	if _cache.has(key):
		return _cache[key]
	var b := MB.new()
	var fe := iron()
	var gl := lamp_glass()
	var o := Transform3D.IDENTITY
	# Basa ochavada con molduras.
	b.lathe(fe, o, [Vector2(0.21, -0.06), Vector2(0.21, 0.1), Vector2(0.185, 0.13), Vector2(0.17, 0.16),
		Vector2(0.15, 0.44), Vector2(0.17, 0.47), Vector2(0.17, 0.51), Vector2(0.12, 0.56), Vector2(0.09, 0.6)], 8, false, false, PI / 8.0)
	# Fuste estriado (12 lados suaves) con anillos.
	b.lathe(fe, o, [Vector2(0.09, 0.6), Vector2(0.085, 0.66), Vector2(0.065, 0.7), Vector2(0.065, 0.74), Vector2(0.075, 0.77),
		Vector2(0.06, 0.8), Vector2(0.052, 3.2), Vector2(0.07, 3.24), Vector2(0.07, 3.28), Vector2(0.05, 3.32), Vector2(0.048, 3.5),
		Vector2(0.065, 3.53), Vector2(0.065, 3.57)], 10, true, false)
	# Ménsulas ornamentales cruzadas bajo la luminaria.
	for ang: float in [0.0, PI * 0.5]:
		var d := Vector3(cos(ang), 0, sin(ang))
		b.box(fe, Transform3D(Basis(Vector3.UP, ang), Vector3(0, 3.42, 0)), Vector3(0.36, 0.022, 0.022), 0.004)
		for s: float in [-1.0, 1.0]:
			b.lathe(fe, Transform3D(Basis.IDENTITY, Vector3(0, 3.39, 0) + d * 0.18 * s), [Vector2(0.0, 0.0), Vector2(0.022, 0.0), Vector2(0.026, 0.03), Vector2(0.0, 0.06)], 6, true, false)
	if v % 2 == 0:
		# Linterna hexagonal: copa, vidrio, techo con remate.
		b.lathe(fe, o, [Vector2(0.065, 3.57), Vector2(0.1, 3.64), Vector2(0.15, 3.7), Vector2(0.155, 3.73)], 6, false, false)
		b.lathe(gl, o, [Vector2(0.0, 3.73), Vector2(0.14, 3.73), Vector2(0.185, 4.13), Vector2(0.0, 4.13)], 6, false, false)
		for j in 6:
			var a := TAU * j / 6.0
			var c := Vector3(cos(a), 0, sin(a))
			b.cyl(fe, c * 0.143 + Vector3(0, 3.73, 0), c * 0.19 + Vector3(0, 4.13, 0), 0.011, 4, false)
		b.lathe(fe, o, [Vector2(0.0, 4.12), Vector2(0.22, 4.12), Vector2(0.24, 4.15), Vector2(0.24, 4.18),
			Vector2(0.12, 4.32), Vector2(0.05, 4.38), Vector2(0.05, 4.42), Vector2(0.03, 4.44), Vector2(0.035, 4.49), Vector2(0.0, 4.56)], 6, false, false)
	else:
		# Globo opalino sobre collarín.
		b.lathe(fe, o, [Vector2(0.065, 3.57), Vector2(0.12, 3.65), Vector2(0.12, 3.69), Vector2(0.09, 3.71)], 10, true, false)
		var prof: Array = []
		for i in 9:
			var t := PI * (0.12 + 0.88 * float(i) / 8.0)
			prof.append(Vector2(sin(t) * 0.22, 3.92 - cos(t) * 0.22))
		prof.insert(0, Vector2(0.0, prof[0].y))
		b.lathe(gl, o, prof, 12, true, false)
		b.lathe(fe, o, [Vector2(0.0, 4.13), Vector2(0.05, 4.13), Vector2(0.03, 4.17), Vector2(0.0, 4.2)], 8, true, false)
	return _done(key, b)


# ------------------------------------------------------------------ caneca
static func park_bin() -> ArrayMesh:
	if _cache.has("bin"):
		return _cache["bin"]
	var b := MB.new()
	var gp := fence_paint()
	var fe := iron()
	# Poste trasero.
	b.lathe(fe, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.27)), [Vector2(0.06, -0.03), Vector2(0.05, 0.05), Vector2(0.04, 0.08), Vector2(0.04, 1.02), Vector2(0.045, 1.04), Vector2(0.0, 1.06)], 8, true, false)
	b.box(fe, Transform3D(Basis.IDENTITY, Vector3(0, 0.88, -0.235)), Vector3(0.08, 0.06, 0.05), 0.005)
	# Canasta de listones.
	var n := 14
	for i in n:
		var a := TAU * i / n
		var c := Vector3(cos(a), 0, sin(a))
		b.box(gp, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), c * 0.205 + Vector3(0, 0.62, 0)), Vector3(0.06, 0.6, 0.018), 0.004, "xXzZ")
	for y: float in [0.36, 0.86]:
		b.lathe(fe, Transform3D.IDENTITY, [Vector2(0.2, y - 0.02), Vector2(0.225, y - 0.02), Vector2(0.225, y + 0.02), Vector2(0.2, y + 0.02), Vector2(0.2, y - 0.02)], 14, true, false)
	# Fondo y bolsa interior.
	b.lathe(fe, Transform3D.IDENTITY, [Vector2(0.0, 0.33), Vector2(0.2, 0.33), Vector2(0.2, 0.35), Vector2(0.0, 0.35)], 10, true, false)
	b.col = Color(0.05, 0.05, 0.05)
	b.lathe(paint_vc(), Transform3D.IDENTITY, [Vector2(0.18, 0.35), Vector2(0.19, 0.82), Vector2(0.215, 0.9), Vector2(0.17, 0.82), Vector2(0.17, 0.4)], 10, true, false)
	return _done("bin", b)


# ------------------------------------------------------------------ carrito de comida
const _CART_SCHEMES := [
	[Color(0.85, 0.12, 0.1), Color(0.98, 0.8, 0.12), Color(0.95, 0.95, 0.9)],   # rojo / amarillo
	[Color(0.1, 0.35, 0.8), Color(0.96, 0.96, 0.94), Color(0.98, 0.75, 0.1)],   # azul / blanco
	[Color(0.12, 0.55, 0.25), Color(0.98, 0.5, 0.08), Color(0.97, 0.94, 0.85)], # verde / naranja
	[Color(0.9, 0.1, 0.45), Color(0.1, 0.65, 0.85), Color(0.98, 0.85, 0.1)],    # fucsia / cian
]


static func food_cart(v: int) -> ArrayMesh:
	var key := "cart_%d" % posmod(v, 4)
	if _cache.has(key):
		return _cache[key]
	var kind := posmod(v, 3)
	var sch: Array = _CART_SCHEMES[posmod(v, 4)]
	var b := MB.new()
	var steel := MatMetal.galvanized()
	var vc := paint_vc()
	var gl := glass()
	# Gabinete de acero inoxidable.
	b.box(steel, Transform3D(Basis.IDENTITY, Vector3(0, 0.66, 0)), Vector3(1.4, 0.56, 0.68), 0.02)
	# Tablero frontal pintado con franja y faldón trasero.
	b.col = sch[0]
	b.box(vc, Transform3D(Basis.IDENTITY, Vector3(0, 0.66, 0.346)), Vector3(1.3, 0.46, 0.012), 0.004, "xXyYZ")
	b.col = sch[1]
	b.box(vc, Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0.354)), Vector3(1.3, 0.08, 0.008), 0.0, "xXyYZ")
	b.box(vc, Transform3D(Basis.IDENTITY, Vector3(0, 0.66, -0.346)), Vector3(1.3, 0.46, 0.012), 0.004, "xXyYz")
	b.col = sch[2]
	for x: float in [-0.45, -0.15, 0.15, 0.45]:
		b.lathe(vc, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.78, 0.352)), [Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.06, 0.008), Vector2(0.0, 0.008)], 8, false, false)
	# Mostrador.
	b.box(steel, Transform3D(Basis.IDENTITY, Vector3(0, 0.955, 0)), Vector3(1.55, 0.03, 0.8), 0.008)
	# Manubrio y patas en -X.
	for z: float in [-0.28, 0.28]:
		b.cyl(steel, Vector3(-0.68, 0.92, z), Vector3(-0.98, 0.95, z), 0.016, 6, false)
		b.cyl(steel, Vector3(-0.6, 0.4, z), Vector3(-0.62, 0.0, z), 0.02, 6, false)
		b.col = Color(0.05, 0.05, 0.05)
		b.box(vc, Transform3D(Basis.IDENTITY, Vector3(-0.62, 0.015, z)), Vector3(0.06, 0.03, 0.06), 0.005, "xXYzZ")
	b.cyl(steel, Vector3(-0.98, 0.95, -0.3), Vector3(-0.98, 0.95, 0.3), 0.02, 6, true)
	b.col = Color(0.08, 0.08, 0.08)
	b.cyl(vc, Vector3(-0.98, 0.95, -0.14), Vector3(-0.98, 0.95, 0.14), 0.026, 8, true)   # puño
	# Ruedas (llanta, rin, 6 radios, eje) en +X.
	b.cyl(steel, Vector3(0.42, 0.28, -0.42), Vector3(0.42, 0.28, 0.42), 0.015, 6, false)
	for z: float in [-0.39, 0.39]:
		var c := Vector3(0.42, 0.28, z)
		var rot := Basis(Vector3.RIGHT, PI * 0.5)
		b.col = Color(0.04, 0.04, 0.045)
		b.lathe(vc, Transform3D(rot, c - Vector3(0, 0, 0.025)), [Vector2(0.24, 0.0), Vector2(0.27, 0.005), Vector2(0.28, 0.025), Vector2(0.27, 0.045), Vector2(0.24, 0.05), Vector2(0.235, 0.025), Vector2(0.24, 0.0)], 16, true, false)
		b.lathe(steel, Transform3D(rot, c - Vector3(0, 0, 0.02)), [Vector2(0.235, 0.01), Vector2(0.235, 0.03), Vector2(0.215, 0.03), Vector2(0.215, 0.01), Vector2(0.235, 0.01)], 16, true, false)
		b.lathe(steel, Transform3D(rot, c - Vector3(0, 0, 0.035)), [Vector2(0.0, 0.0), Vector2(0.045, 0.0), Vector2(0.045, 0.07), Vector2(0.0, 0.07)], 8, true, false)
		for k in 6:
			var a := TAU * k / 6.0
			var d := Vector3(cos(a), sin(a), 0)
			b.cyl(steel, c + d * 0.04, c + d * 0.218, 0.006, 3, false)
	# Carga según tipo.
	var fruit := [Color(0.98, 0.72, 0.08), Color(0.55, 0.78, 0.2), Color(0.9, 0.2, 0.18), Color(0.98, 0.55, 0.1), Color(0.97, 0.9, 0.4)]
	if kind == 0 or kind == 2:
		var vw := 1.15 if kind == 0 else 1.25
		var vh := 0.44 if kind == 0 else 0.5
		var vd := 0.52
		var cy := 0.97 + vh * 0.5
		# Vitrina: vidrio + marco de aluminio.
		b.box(gl, Transform3D(Basis.IDENTITY, Vector3(0, cy, 0)), Vector3(vw, vh, vd), 0.0, "xXYzZ")
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.box(steel, Transform3D(Basis.IDENTITY, Vector3(sx * vw * 0.5, cy, sz * vd * 0.5)), Vector3(0.025, vh, 0.025), 0.0, "xXYzZ")
			b.box(steel, Transform3D(Basis.IDENTITY, Vector3(sx * vw * 0.5, 0.97 + vh, 0)), Vector3(0.025, 0.025, vd), 0.0)
		for sz: float in [-1.0, 1.0]:
			b.box(steel, Transform3D(Basis.IDENTITY, Vector3(0, 0.97 + vh, sz * vd * 0.5)), Vector3(vw, 0.025, 0.025), 0.0)
		# Bandeja y fruta en vasos (2 filas).
		b.box(steel, Transform3D(Basis.IDENTITY, Vector3(0, 1.02, 0)), Vector3(vw - 0.08, 0.02, vd - 0.08), 0.0, "Y")
		var cols := 6 if kind == 0 else 4
		for row in 2:
			for i in cols:
				var x := lerpf(-vw * 0.5 + 0.1, vw * 0.5 - 0.1, float(i) / float(cols - 1))
				var z := -0.11 + 0.22 * row
				b.col = fruit[(i + row * 2 + v) % fruit.size()]
				if kind == 0:
					# vaso de mango biche/maduro: palitos de fruta asomando del vaso
					b.lathe(vc, Transform3D(Basis.IDENTITY, Vector3(x, 1.03, z)), [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.05, 0.12), Vector2(0.035, 0.17), Vector2(0.0, 0.19)], 6, false, false)
				else:
					# tazón de salpicón (fruta picada)
					b.lathe(vc, Transform3D(Basis.IDENTITY, Vector3(x, 1.03, z)), [Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.09, 0.08), Vector2(0.06, 0.11), Vector2(0.0, 0.12)], 7, false, false)
		if kind == 2:
			# Dos botellones de jugo sobre la vitrina.
			for i in 2:
				var p := Vector3(-0.25 + 0.5 * i, 0.97 + vh, 0)
				b.col = fruit[2 + i]
				b.lathe(vc, Transform3D(Basis.IDENTITY, p), [Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.1, 0.22), Vector2(0.0, 0.22)], 10, true, false)
				b.lathe(gl, Transform3D(Basis.IDENTITY, p), [Vector2(0.11, 0.0), Vector2(0.115, 0.3), Vector2(0.06, 0.36)], 10, true, false)
				b.lathe(steel, Transform3D(Basis.IDENTITY, p + Vector3(0, 0.36, 0)), [Vector2(0.0, 0.0), Vector2(0.065, 0.0), Vector2(0.065, 0.025), Vector2(0.0, 0.03)], 10, true, false)
	else:
		# Arepas: parrilla sobre caja de fogón, arepas y pipeta de gas.
		b.box(steel, Transform3D(Basis.IDENTITY, Vector3(0.08, 1.04, 0)), Vector3(0.95, 0.14, 0.55), 0.01)
		b.col = Color(0.06, 0.06, 0.06)
		b.box(vc, Transform3D(Basis.IDENTITY, Vector3(0.08, 1.12, 0)), Vector3(0.9, 0.02, 0.5), 0.003)
		for i in 7:
			b.cyl(vc, Vector3(-0.35, 1.135, -0.21 + 0.07 * i), Vector3(0.51, 1.135, -0.21 + 0.07 * i), 0.005, 3, false)
		for i in 6:
			var p := Vector3(-0.22 + 0.27 * (i % 3), 1.14, -0.11 + 0.22 * (i / 3))
			b.col = Color(0.93, 0.84, 0.6).lerp(Color(0.75, 0.5, 0.25), 0.2 * (i % 3))
			b.lathe(vc, Transform3D(Basis.IDENTITY, p), [Vector2(0.0, 0.0), Vector2(0.075, 0.0), Vector2(0.08, 0.01), Vector2(0.075, 0.022), Vector2(0.0, 0.024)], 8, true, false)
		# pila de arepas listas en una canasta
		b.col = Color(0.62, 0.45, 0.22)
		b.lathe(vc, Transform3D(Basis.IDENTITY, Vector3(-0.58, 0.97, 0.2)), [Vector2(0.0, 0.0), Vector2(0.11, 0.0), Vector2(0.14, 0.09), Vector2(0.12, 0.09), Vector2(0.0, 0.03)], 8, false, false)
		b.col = Color(0.95, 0.88, 0.65)
		b.lathe(vc, Transform3D(Basis.IDENTITY, Vector3(-0.58, 1.0, 0.2)), [Vector2(0.0, 0.0), Vector2(0.09, 0.0), Vector2(0.09, 0.07), Vector2(0.0, 0.075)], 8, true, false)
		# pipeta de gas bajo el carrito
		b.col = Color(0.75, 0.75, 0.72)
		b.lathe(vc, Transform3D(Basis.IDENTITY, Vector3(-0.2, 0.0, 0.55)), [Vector2(0.0, 0.0), Vector2(0.13, 0.0), Vector2(0.15, 0.04), Vector2(0.15, 0.42), Vector2(0.11, 0.5), Vector2(0.03, 0.52), Vector2(0.03, 0.58), Vector2(0.0, 0.58)], 10, true, false)
		b.cyl(steel, Vector3(-0.2, 0.56, 0.55), Vector3(-0.1, 0.98, 0.33), 0.008, 3, false)
	# Sombrilla de colores (8 paños alternos, faldón festoneado, varillas).
	var pole_b := Vector3(0.62, 0.97, -0.2)
	var apex := Vector3(0.62, 2.48, -0.2)
	b.cyl(steel, pole_b, apex, 0.018, 6, false)
	b.cyl(steel, pole_b, pole_b + Vector3(0, -0.12, 0), 0.03, 6, false)
	var R := 1.15
	var rim_y := 2.12
	for k in 8:
		var a0 := TAU * k / 8.0 + PI / 8.0
		var a1 := TAU * (k + 1) / 8.0 + PI / 8.0
		var p0 := Vector3(apex.x + cos(a0) * R, rim_y, apex.z + sin(a0) * R)
		var p1 := Vector3(apex.x + cos(a1) * R, rim_y, apex.z + sin(a1) * R)
		var mid := (p0 + p1) * 0.5
		var c: Color = sch[0] if k % 2 == 0 else sch[1]
		var n_out := (p1 - p0).cross(apex - p0).normalized()
		if n_out.y < 0.0:
			n_out = -n_out
		b.col = c
		b.tri(vc, apex, p0, p1, n_out)
		b.col = c.darkened(0.25)
		b.tri(vc, apex, p1, p0, -n_out)   # cara inferior
		# Faldón (dos festones por paño).
		b.col = c
		for f in 2:
			var q0 := p0.lerp(p1, f * 0.5)
			var q1 := p0.lerp(p1, f * 0.5 + 0.5)
			var qm := (q0 + q1) * 0.5 + Vector3(0, -0.12, 0)
			var rn := Vector3(mid.x - apex.x, 0, mid.z - apex.z).normalized()
			b.tri(vc, q0, q1, qm, rn)
			b.tri(vc, q0, qm, q1, -rn)
		# Varilla bajo la lona.
		b.cyl(steel, apex + Vector3(0, -0.03, 0), p0 + Vector3(0, -0.02, 0), 0.006, 3, false)
		b.cyl(steel, apex.lerp(p0, 0.5) + Vector3(0, -0.03, 0), apex + Vector3(0, -0.55, 0), 0.005, 3, false)
	b.lathe(steel, Transform3D(Basis.IDENTITY, apex), [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.025, 0.06), Vector2(0.0, 0.09)], 6, true, false)
	return _done(key, b)

class_name McKit
extends RefCounted
## Constructor de mallas multi-superficie para Monument y Church (F2-05).
## Uso: var k := McKit.new(); k.box("piedra", mat, xf, size, bevel); ... ; var mesh := k.commit()
## - Cada "surf" (clave) = una superficie del ArrayMesh con su material.
## - Los triángulos se orientan solos según la normal de referencia (no hay que pensar en el winding).
## - UV: proyección de caja en metros (los Mat* son triplanar en mundo y las ignoran; sirven para
##   generate_tangents()).

var _st := {}        # surf → SurfaceTool
var _mat := {}       # surf → Material
var _order: Array[String] = []
var tris := 0


func _surf(surf: String, mat: Material) -> SurfaceTool:
	if not _st.has(surf):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[surf] = st
		_mat[surf] = mat
		_order.append(surf)
	return _st[surf]


static func _uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.y >= a.x and a.y >= a.z:
		return Vector2(p.x, p.z)
	if a.x >= a.z:
		return Vector2(p.z, -p.y)
	return Vector2(p.x, -p.y)


## Triángulo con normales por vértice; se reordena para que la cara frontal mire hacia las normales.
func tri_n(surf: String, mat: Material, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var st := _surf(surf, mat)
	var ref := na + nb + nc
	# Godot: cara frontal = horario visto desde fuera → (b-a)×(c-a) apunta HACIA DENTRO.
	if (b - a).cross(c - a).dot(ref) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	var fn := ref.normalized()
	for v in [[a, na], [b, nb], [c, nc]]:
		st.set_normal(v[1])
		st.set_uv(_uv(v[0], fn))
		st.add_vertex(v[0])
	tris += 1


## Quad con UV explícitas (techos con textura orientada a la pendiente).
func quad_uv(surf: String, mat: Material, p: Array, uv: Array, n: Vector3) -> void:
	var st := _surf(surf, mat)
	for t in [[0, 1, 2], [0, 2, 3]]:
		var ia: int = t[0]
		var ib: int = t[1]
		var ic: int = t[2]
		if (p[ib] - p[ia]).cross(p[ic] - p[ia]).dot(n) > 0.0:
			var tmp := ib
			ib = ic
			ic = tmp
		for i in [ia, ib, ic]:
			st.set_normal(n)
			st.set_uv(uv[i])
			st.add_vertex(p[i])
		tris += 1


func tri(surf: String, mat: Material, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	tri_n(surf, mat, a, b, c, n, n, n)


## Quad plano a-b-c-d (en orden de perímetro). Si n es cero se calcula y se orienta "hacia afuera" de `out_hint`.
func quad(surf: String, mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n := Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (b - a).cross(d - a)
		if n.length_squared() < 1e-12:
			n = (c - b).cross(a - b)
		n = n.normalized()
	tri(surf, mat, a, b, c, n)
	tri(surf, mat, a, c, d, n)


## Caja con chaflán `bevel` en las 12 aristas (44 triángulos; 12 si bevel = 0).
## `faces` permite omitir caras: cadena con letras de las caras a dibujar ("xXyYzZ" = todas; x = -X, X = +X).
func box(surf: String, mat: Material, xf: Transform3D, size: Vector3, bevel := 0.0, faces := "xXyYzZ") -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var ins := h - Vector3(b, b, b)
	var bas := xf.basis
	# Caras principales.
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
			var wn := (bas * n).normalized()
			quad(surf, mat, xf * (c - u * hu - v * hv), xf * (c + u * hu - v * hv), xf * (c + u * hu + v * hv), xf * (c - u * hu + v * hv), wn)
	if b <= 0.0:
		return
	# Biseles de arista (12) y esquinas (8).
	for ai in 3:
		var u: Vector3 = axes[(ai + 1) % 3]
		var v: Vector3 = axes[(ai + 2) % 3]
		for su: float in [-1.0, 1.0]:
			for sv: float in [-1.0, 1.0]:
				var e: Vector3 = axes[ai]
				var hu: float = h[(ai + 1) % 3]
				var hv: float = h[(ai + 2) % 3]
				var iu: float = ins[(ai + 1) % 3]
				var iv: float = ins[(ai + 2) % 3]
				var he: float = ins[ai]
				var p1 := u * su * hu + v * sv * iv
				var p2 := u * su * iu + v * sv * hv
				var fu: String = keys[(ai + 1) % 3][0 if su < 0.0 else 1]
				var fv: String = keys[(ai + 2) % 3][0 if sv < 0.0 else 1]
				if not faces.contains(fu) and not faces.contains(fv):
					continue
				var n := (u * su + v * sv).normalized()
				quad(surf, mat, xf * (p1 - e * he), xf * (p1 + e * he), xf * (p2 + e * he), xf * (p2 - e * he), (bas * n).normalized())
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				if not (faces.contains("x" if sx < 0.0 else "X") or faces.contains("y" if sy < 0.0 else "Y") or faces.contains("z" if sz < 0.0 else "Z")):
					continue
				var a := Vector3(sx * h.x, sy * ins.y, sz * ins.z)
				var bb := Vector3(sx * ins.x, sy * h.y, sz * ins.z)
				var c := Vector3(sx * ins.x, sy * ins.y, sz * h.z)
				tri(surf, mat, xf * a, xf * bb, xf * c, (bas * Vector3(sx, sy, sz)).normalized())


## Malla en rejilla: rows[i] = PackedVector3Array (anillo/sección i). Normales por diferencias
## centrales, orientadas para alejarse de `centers[i]` (o del centroide del anillo si no se dan).
## closed = el anillo es cerrado. flip = invierte (superficie interior).
func grid(surf: String, mat: Material, rows: Array, closed: bool, flip := false, centers: Array = []) -> void:
	var nr := rows.size()
	if nr < 2:
		return
	var nc: int = rows[0].size()
	var cen: Array = []
	for i in nr:
		if centers.size() == nr:
			cen.append(centers[i])
		else:
			var s := Vector3.ZERO
			for p: Vector3 in rows[i]:
				s += p
			cen.append(s / float(nc))
	var norms: Array = []
	for i in nr:
		var row := PackedVector3Array()
		row.resize(nc)
		for j in nc:
			var jp := (j + 1) % nc if closed else mini(j + 1, nc - 1)
			var jm := (j - 1 + nc) % nc if closed else maxi(j - 1, 0)
			var ip := mini(i + 1, nr - 1)
			var im := maxi(i - 1, 0)
			var du: Vector3 = rows[i][jp] - rows[i][jm]
			var dv: Vector3 = rows[ip][j] - rows[im][j]
			var n := du.cross(dv)
			var p: Vector3 = rows[i][j]
			var away: Vector3 = p - cen[i]
			if n.length_squared() < 1e-14:
				n = away if away.length_squared() > 1e-12 else (rows[ip][j] - rows[im][j])
			n = n.normalized()
			if n.dot(away) < 0.0:
				n = -n
			if flip:
				n = -n
			row[j] = n
		norms.append(row)
	var segs := nc if closed else nc - 1
	for i in nr - 1:
		for j in segs:
			var j2 := (j + 1) % nc
			var a: Vector3 = rows[i][j]
			var b: Vector3 = rows[i][j2]
			var c: Vector3 = rows[i + 1][j2]
			var d: Vector3 = rows[i + 1][j]
			var na: Vector3 = norms[i][j]
			var nb: Vector3 = norms[i][j2]
			var ncc: Vector3 = norms[i + 1][j2]
			var nd: Vector3 = norms[i + 1][j]
			if (a - b).length_squared() > 1e-10:
				tri_n(surf, mat, a, b, c, na, nb, ncc)
			if (c - d).length_squared() > 1e-10:
				tri_n(surf, mat, a, c, d, na, ncc, nd)


## Torno: perfil = [Vector2(r, y), ...] de abajo hacia arriba. sides = lados. Liso.
## rot = rotación inicial (rad). sx/sz escalan el radio (secciones elípticas).
func lathe(surf: String, mat: Material, xf: Transform3D, profile: Array, sides: int, rot := 0.0, sx := 1.0, sz := 1.0) -> void:
	var rows: Array = []
	var cens: Array = []
	for pr: Vector2 in profile:
		var row := PackedVector3Array()
		for k in sides:
			var a := rot + TAU * float(k) / float(sides)
			row.append(xf * Vector3(cos(a) * pr.x * sx, pr.y, sin(a) * pr.x * sz))
		rows.append(row)
		cens.append(xf * Vector3(0, pr.y, 0))
	grid(surf, mat, rows, true, false, cens)


## Torno CUADRADO de caras planas (molduras de pedestales, cornisas). profile = [Vector2(semiancho, y)].
## half_xz = proporción (ancho_x, ancho_z) relativa al semiancho; chamfer = chaflán de esquina (m).
## cap_top cierra arriba con una tapa plana.
func square_lathe(surf: String, mat: Material, xf: Transform3D, profile: Array, chamfer := 0.03, cap_top := true, aspect := Vector2.ONE) -> void:
	var rings: Array = []
	for pr: Vector2 in profile:
		var hx := pr.x * aspect.x
		var hz := pr.x * aspect.y
		var c := minf(chamfer, minf(hx, hz) * 0.4)
		var r := PackedVector3Array([
			Vector3(hx - c, pr.y, -hz), Vector3(hx, pr.y, -hz + c), Vector3(hx, pr.y, hz - c), Vector3(hx - c, pr.y, hz),
			Vector3(-hx + c, pr.y, hz), Vector3(-hx, pr.y, hz - c), Vector3(-hx, pr.y, -hz + c), Vector3(-hx + c, pr.y, -hz)])
		rings.append(r)
	for i in rings.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var n2 := Vector2(p1.y - p0.y, -(p1.x - p0.x))
		if n2.length_squared() < 1e-12:
			continue
		n2 = n2.normalized()
		for j in 8:
			var j2 := (j + 1) % 8
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][j2]
			var c2: Vector3 = rings[i + 1][j2]
			var d: Vector3 = rings[i + 1][j]
			var e := b - a
			if e.length_squared() < 1e-12:
				e = c2 - d
			var nh := e.cross(Vector3.UP).normalized()
			var mid := (a + b) * 0.5
			if nh.dot(Vector3(mid.x, 0, mid.z)) < 0.0:
				nh = -nh
			var n := (nh * n2.x + Vector3.UP * n2.y).normalized()
			quad(surf, mat, xf * a, xf * b, xf * c2, xf * d, (xf.basis * n).normalized())
	if cap_top:
		var top: PackedVector3Array = rings[rings.size() - 1]
		var cy: float = profile[profile.size() - 1].y
		var nn := (xf.basis * Vector3.UP).normalized()
		for j in 8:
			tri(surf, mat, xf * Vector3(0, cy, 0), xf * top[j], xf * top[(j + 1) % 8], nn)


## Tubo a lo largo de una polilínea con radios por punto (secciones circulares/elípticas).
## pts: Array[Vector3]; radii: Array[float] o Array[Vector2] (rx, rz en el marco local de la sección).
## up_hint orienta la sección. caps cierra los extremos con un vértice.
func tube(surf: String, mat: Material, pts: Array, radii: Array, sides: int, caps := true, up_hint := Vector3(0, 0, 1), wobble := 0.0, wob_n := 0) -> void:
	var rows: Array = []
	var cens: Array = []
	var n := pts.size()
	var d0: Vector3 = (pts[1] - pts[0]).normalized()
	var d1: Vector3 = (pts[n - 1] - pts[n - 2]).normalized()
	if caps:
		var cap0 := PackedVector3Array()
		cap0.resize(sides)
		cap0.fill(pts[0])
		rows.append(cap0)
		cens.append(pts[0] + d0 * 0.01)
	for i in n:
		rows.append(_ring_at(pts, radii, i, sides, up_hint, wobble, float(i) / float(n - 1), wob_n))
		cens.append(pts[i])
	if caps:
		var cap1 := PackedVector3Array()
		cap1.resize(sides)
		cap1.fill(pts[n - 1])
		rows.append(cap1)
		cens.append(pts[n - 1] - d1 * 0.01)
	grid(surf, mat, rows, true, false, cens)


func _ring_at(pts: Array, radii: Array, i: int, sides: int, up_hint: Vector3, wobble: float, t: float, wob_n: int) -> PackedVector3Array:
	var n := pts.size()
	var p: Vector3 = pts[i]
	var dir: Vector3
	if i == 0:
		dir = pts[1] - pts[0]
	elif i == n - 1:
		dir = pts[n - 1] - pts[n - 2]
	else:
		dir = pts[i + 1] - pts[i - 1]
	dir = dir.normalized()
	var side := up_hint.cross(dir)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT.cross(dir)
	side = side.normalized()
	var fwd := dir.cross(side).normalized()
	var r: Variant = radii[i]
	var rx: float
	var rz: float
	if r is Vector2:
		rx = r.x
		rz = r.y
	else:
		rx = float(r)
		rz = float(r)
	var row := PackedVector3Array()
	for k in sides:
		var a := TAU * float(k) / float(sides)
		var w := 1.0
		if wob_n > 0:
			w += wobble * sin(a * wob_n + t * 2.0)
		row.append(p + side * cos(a) * rx * w + fwd * sin(a) * rz * w)
	return row


## Cilindro simple a→b (con tapas opcionales).
func cyl(surf: String, mat: Material, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, caps := true) -> void:
	var dir := (b - a).normalized()
	var hint := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	tube(surf, mat, [a, b], [ra, rb], sides, caps, hint)


## Esfera/elipsoide low-poly.
func ellipsoid(surf: String, mat: Material, xf: Transform3D, r: Vector3, seg_u := 8, seg_v := 6) -> void:
	var rows: Array = []
	var cens: Array = []
	for i in seg_v + 1:
		var th := PI * float(i) / float(seg_v) - PI * 0.5
		var row := PackedVector3Array()
		for k in seg_u:
			var a := TAU * float(k) / float(seg_u)
			row.append(xf * Vector3(cos(th) * cos(a) * r.x, sin(th) * r.y, cos(th) * sin(a) * r.z))
		rows.append(row)
		cens.append(xf * Vector3(0, sin(th) * r.y * 0.5, 0))
	grid(surf, mat, rows, true, false, cens)


## Arco de medio punto extruido (intradós + caras frontal/trasera), para arquivoltas.
## c = centro del arco (base de las dovelas en y de impostas), r0/r1 radios interior/exterior,
## depth hacia +Z local (desde z0 a z0+depth). Caras orientadas por el marco xf.
func arch(surf: String, mat: Material, xf: Transform3D, r0: float, r1: float, z0: float, depth: float, segs := 10, faces := "fbio") -> void:
	for k in segs:
		var a0 := PI * float(k) / float(segs)
		var a1 := PI * float(k + 1) / float(segs)
		var i0 := Vector3(cos(a0) * r0, sin(a0) * r0, 0)
		var i1 := Vector3(cos(a1) * r0, sin(a1) * r0, 0)
		var o0 := Vector3(cos(a0) * r1, sin(a0) * r1, 0)
		var o1 := Vector3(cos(a1) * r1, sin(a1) * r1, 0)
		var zf := Vector3(0, 0, z0)
		var zb := Vector3(0, 0, z0 + depth)
		var bs := xf.basis
		if faces.contains("f"):
			quad(surf, mat, xf * (i0 + zf), xf * (o0 + zf), xf * (o1 + zf), xf * (i1 + zf), (bs * Vector3(0, 0, -1)).normalized())
		if faces.contains("b"):
			quad(surf, mat, xf * (i0 + zb), xf * (o0 + zb), xf * (o1 + zb), xf * (i1 + zb), (bs * Vector3(0, 0, 1)).normalized())
		var am := (a0 + a1) * 0.5
		if faces.contains("i"):
			quad(surf, mat, xf * (i0 + zf), xf * (i1 + zf), xf * (i1 + zb), xf * (i0 + zb), (bs * Vector3(-cos(am), -sin(am), 0)).normalized())
		if faces.contains("o"):
			quad(surf, mat, xf * (o0 + zf), xf * (o1 + zf), xf * (o1 + zb), xf * (o0 + zb), (bs * Vector3(cos(am), sin(am), 0)).normalized())


## Panel plano con hueco de arco de medio punto (muro alrededor de un vano): rectángulo [x0,x1]×[y0,y1]
## en el plano z = zp del marco, con vano de ancho 2r centrado en cx, con arranque del arco en ys (y del centro).
## El vano va desde y0 hasta ys + r. Normal = n_local.
func wall_with_arch(surf: String, mat: Material, xf: Transform3D, x0: float, x1: float, y0: float, y1: float, zp: float, cx: float, r: float, ys: float, n_local: Vector3, segs := 8) -> void:
	var bs := xf.basis
	var wn := (bs * n_local).normalized()
	var P := func(x: float, y: float) -> Vector3: return xf * Vector3(x, y, zp)
	# Lados del vano.
	quad(surf, mat, P.call(x0, y0), P.call(cx - r, y0), P.call(cx - r, ys), P.call(x0, ys), wn)
	quad(surf, mat, P.call(cx + r, y0), P.call(x1, y0), P.call(x1, ys), P.call(cx + r, ys), wn)
	# Franja superior completa.
	if y1 > ys + r:
		quad(surf, mat, P.call(x0, ys + r), P.call(x1, ys + r), P.call(x1, y1), P.call(x0, y1), wn)
	# Enjutas (abanico desde las esquinas superiores).
	for k in segs:
		var a0 := PI * float(k) / float(segs)
		var a1 := PI * float(k + 1) / float(segs)
		var p0 := Vector2(cx + cos(a0) * r, ys + sin(a0) * r)
		var p1 := Vector2(cx + cos(a1) * r, ys + sin(a1) * r)
		var corner := Vector2(x1, ys + r) if (a0 + a1) * 0.5 < PI * 0.5 else Vector2(x0, ys + r)
		tri(surf, mat, P.call(p0.x, p0.y), P.call(p1.x, p1.y), P.call(corner.x, corner.y), wn)
	# Triángulos laterales que faltan (entre el arranque y la esquina).
	tri(surf, mat, P.call(cx + r, ys), P.call(x1, ys), P.call(x1, ys + r), wn)
	tri(surf, mat, P.call(cx - r, ys), P.call(x0, ys), P.call(x0, ys + r), wn)
	# Cuña central superior (entre las dos mitades del abanico).
	tri(surf, mat, P.call(cx, ys + r), P.call(x1, ys + r), P.call(x0, ys + r), wn)


func commit(tangents := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s in _order:
		var st: SurfaceTool = _st[s]
		if tangents:
			st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat[s])
	return mesh

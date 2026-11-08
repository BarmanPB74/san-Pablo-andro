class_name Buildings
extends RefCounted
## Edificios del barrio (Fase 2, agente F2-08 "buildings").
## Construye fachadas con PROFUNDIDAD dentro de los lotes de BostonDistrict:
##  - casa antioqueña de 2 pisos (zócalo de piedra, estuco de color, moldura de entrepiso, alero con
##    canecillos de madera, teja de barro con UV propias, balcón de madera o balconcillos de hierro),
##  - edificio de apartamentos de ladrillo (franjas de losa, ventanas rehundidas con alféizar y dintel de
##    petaco, balcones con antepecho de ladrillo o baranda, calado en la escalera, antejardín con muro bajo
##    y escalas, retranqueo del último piso, tanques/cuartos de máquinas/antenas en azotea),
##  - edificio de apartamentos pintado (misma lógica con estuco),
##  - edificio moderno de vidrio y concreto liso (losas gruesas, parteluces, visera superior).
##
## Rendimiento: TODO lo que es geometría propia de cada edificio se escribe en los lotes del distrito
## (`d._st(mat, pos, shadow)`: 1 superficie por material por trozo 2x2 del mapa → muy pocas draw calls).
## Las ventanas usan el atlas MatFacade.window con UV por celda dentro de un único material (día) y otro
## (encendidas) → 2 materiales para TODAS las ventanas del mapa. Lo repetido y con muchos triángulos
## (barandas, canecillos, tanques, antenas, parteluces) va por `d.place_mesh` (MultiMesh por key).
## Las caras ocultas (traseras, internas) no se emiten. Cerca del parque (`near`) se modela el rehundido
## de ventanas; lejos se usa una versión plana más barata.
##
## Convención de cada lote: xf = transform del lote (origen en el centro del frente, a nivel del andén),
## +X local a lo largo de la fachada, +Z local hacia la calle; el edificio ocupa z ∈ [-dep, 0].

# Máscaras de caras de caja
const PX := 1
const NX := 2
const PY := 4
const NY := 8
const PZ := 16
const NZ := 32
const ALL := 63

## Celdas del atlas de ventanas por uso (ver art/tex/facade/windows_albedo.png).
const UP_CELLS: Array[int] = [0, 1, 3, 6, 7, 10, 12, 14]        # pisos altos, sin reja
const REJA_CELLS: Array[int] = [2, 5, 8, 9, 13, 15, 4, 11]      # primer piso / casas, con reja
const HOUSE_UP_CELLS: Array[int] = [3, 10, 0, 7]                 # marcos de madera / cortinas
## Celda sin luz interior → celda parecida que sí tiene interior encendido de noche.
const LIT_SWAP := {1: 0, 3: 7, 4: 5, 6: 7, 9: 8, 11: 13, 12: 10, 14: 0}

static var _mats := {}
static var _meshes := {}


# ------------------------------------------------------------------ materiales propios
## Atlas completo de ventanas (UV de la malla eligen la celda). lit = interior encendido (emisión).
static func win_mat(lit: bool) -> Material:
	var key := "win_%s" % lit
	if not _mats.has(key):
		var m: ORMMaterial3D = (MatFacade.window(0, lit) as ORMMaterial3D).duplicate()
		m.uv1_scale = Vector3.ONE
		m.uv1_offset = Vector3.ZERO
		_mats[key] = m
	return _mats[key]


## Teja de barro con UV propias (metros/2 → la canal corre a lo largo de la pendiente en cualquier orientación).
static func roof_mat() -> Material:
	if not _mats.has("roof"):
		_mats["roof"] = (MatPlaster.roof_clay(false, Vector3.ONE) as ORMMaterial3D).duplicate()
	return _mats["roof"]


## Tanque plástico negro de agua (típico en azoteas de Medellín).
static func tank_mat() -> Material:
	if not _mats.has("tank"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.06, 0.065, 0.07)
		m.roughness = 0.55
		_mats["tank"] = m
	return _mats["tank"]


static func _brick_mat(i: int) -> Material:
	# 3 tintes de ladrillo naranja + el viejo: pocas superficies por trozo.
	return MatBrick.fachada_variante([0, 1, 2, 4, 0, 1][posmod(i, 6)])


# ------------------------------------------------------------------ contexto de construcción
class Ctx:
	var d                       # BostonDistrict (llamadas dinámicas: _st, _col_box, place_mesh, _shopfront)
	var xf: Transform3D
	var org: Vector3
	var rng := RandomNumberGenerator.new()
	var near := true

	func _init(district, t: Transform3D, is_near: bool) -> void:
		d = district
		xf = t
		org = t.origin
		near = is_near
		rng.seed = hash(Vector3i(roundi(t.origin.x * 10.0), roundi(t.origin.y * 10.0), roundi(t.origin.z * 10.0)))

	func st(mat: Material, shadow: bool) -> SurfaceTool:
		return d._st(mat, org, shadow)

	## Caja en coordenadas locales del lote entre lo y hi; solo las caras de `mask`.
	func box(mat: Material, lo: Vector3, hi: Vector3, mask := ALL, shadow := true) -> void:
		Buildings.emit_box(st(mat, shadow), xf, lo, hi, mask)

	## Quad local (4 esquinas en orden cualquiera alrededor) con normal local n.
	func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, e: Vector3, n: Vector3, shadow := false) -> void:
		Buildings.emit_face(st(mat, shadow), xf * a, xf * b, xf * c, xf * e, (xf.basis * n).normalized())

	## Polígono convexo local (abanico).
	func poly(mat: Material, pts: Array, n: Vector3, shadow := true) -> void:
		var s := st(mat, shadow)
		var wn := (xf.basis * n).normalized()
		var wp := PackedVector3Array()
		for p in pts:
			wp.append(xf * (p as Vector3))
		if (wp[1] - wp[0]).cross(wp[2] - wp[0]).dot(wn) > 0.0:
			wp.reverse()
		var ns := PackedVector3Array()
		ns.resize(wp.size())
		ns.fill(wn)
		s.add_triangle_fan(wp, PackedVector2Array(), PackedColorArray(), PackedVector2Array(), ns)

	## Vidrio de ventana: rect local en el plano z, celda del atlas, encendida o no.
	func window(cell: int, x0: float, x1: float, y0: float, y1: float, z: float, lit: bool) -> void:
		if lit and Buildings.LIT_SWAP.has(cell):
			cell = Buildings.LIT_SWAP[cell]
		var s := st(Buildings.win_mat(lit), false)
		var col := cell % 4
		var row := cell / 4
		var e := 0.006
		var u0 := (col + e) * 0.25
		var u1 := (col + 1.0 - e) * 0.25
		var v0 := (row + e) * 0.25
		var v1 := (row + 1.0 - e) * 0.25
		var n := xf.basis.z.normalized()
		var t := Plane(xf.basis.x.normalized(), 1.0)
		# frente = +Z: visto de frente, -X queda a la izquierda (u0), arriba = v0
		var vs := PackedVector3Array([xf * Vector3(x0, y1, z), xf * Vector3(x1, y1, z), xf * Vector3(x1, y0, z), xf * Vector3(x0, y0, z)])
		var uv := PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
		if (vs[1] - vs[0]).cross(vs[2] - vs[0]).dot(n) > 0.0:
			vs = PackedVector3Array([vs[0], vs[3], vs[2], vs[1]])
			uv = PackedVector2Array([uv[0], uv[3], uv[2], uv[1]])
		s.add_triangle_fan(vs, uv, PackedColorArray(), PackedVector2Array(), PackedVector3Array([n, n, n, n]), [t, t, t, t])

	func mesh(key: String, m: Mesh, local: Transform3D, shadow := true) -> void:
		d.place_mesh(key, m, xf * local, shadow)

	func col(lo: Vector3, hi: Vector3) -> void:
		d._col_box(xf.translated_local((lo + hi) * 0.5), hi - lo)


# ------------------------------------------------------------------ emisores de geometría
## Cara plana (abanico de 4) con la cara frontal mirando hacia n (Godot: horario visto de frente).
static func emit_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, e: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = e
		e = t
	st.add_triangle_fan(PackedVector3Array([a, b, c, e]), PackedVector2Array(), PackedColorArray(),
		PackedVector2Array(), PackedVector3Array([n, n, n, n]))


static func emit_box(st: SurfaceTool, xf: Transform3D, lo: Vector3, hi: Vector3, mask := ALL) -> void:
	var b := xf.basis
	if mask & PX:
		emit_face(st, xf * Vector3(hi.x, lo.y, lo.z), xf * Vector3(hi.x, hi.y, lo.z), xf * Vector3(hi.x, hi.y, hi.z), xf * Vector3(hi.x, lo.y, hi.z), b.x.normalized())
	if mask & NX:
		emit_face(st, xf * Vector3(lo.x, lo.y, lo.z), xf * Vector3(lo.x, hi.y, lo.z), xf * Vector3(lo.x, hi.y, hi.z), xf * Vector3(lo.x, lo.y, hi.z), -b.x.normalized())
	if mask & PY:
		emit_face(st, xf * Vector3(lo.x, hi.y, lo.z), xf * Vector3(hi.x, hi.y, lo.z), xf * Vector3(hi.x, hi.y, hi.z), xf * Vector3(lo.x, hi.y, hi.z), b.y.normalized())
	if mask & NY:
		emit_face(st, xf * Vector3(lo.x, lo.y, lo.z), xf * Vector3(hi.x, lo.y, lo.z), xf * Vector3(hi.x, lo.y, hi.z), xf * Vector3(lo.x, lo.y, hi.z), -b.y.normalized())
	if mask & PZ:
		emit_face(st, xf * Vector3(lo.x, lo.y, hi.z), xf * Vector3(hi.x, lo.y, hi.z), xf * Vector3(hi.x, hi.y, hi.z), xf * Vector3(lo.x, hi.y, hi.z), b.z.normalized())
	if mask & NZ:
		emit_face(st, xf * Vector3(lo.x, lo.y, lo.z), xf * Vector3(hi.x, lo.y, lo.z), xf * Vector3(hi.x, hi.y, lo.z), xf * Vector3(lo.x, hi.y, lo.z), -b.z.normalized())


## Caja con UV en metros (proyección por cara) y tangentes, para mallas de props (place_mesh).
static func _mbox(st: SurfaceTool, xf: Transform3D, lo: Vector3, hi: Vector3, mask := ALL) -> void:
	emit_box(st, xf, lo, hi, mask)


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit(parts: Array) -> ArrayMesh:
	# parts: [[SurfaceTool, Material], ...] → ArrayMesh multi-superficie
	var am := ArrayMesh.new()
	for p in parts:
		var st: SurfaceTool = p[0]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, p[1])
	return am


static func _tri_count(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# ------------------------------------------------------------------ mallas repetidas (MultiMesh)
## Baranda metálica de balcón: pasamanos, platina inferior y barrotes cada ~11 cm. Largo L a lo largo de X,
## centrada en x, base en y=0, plano z=0. Alto 0.95 m.
static func rail_metal(L: float) -> Mesh:
	var key := "rail_m_%.1f" % L
	if _meshes.has(key):
		return _meshes[key]
	var st := _new_st()
	var I := Transform3D.IDENTITY
	var h := 0.95
	emit_box(st, I, Vector3(-L * 0.5, h - 0.05, -0.025), Vector3(L * 0.5, h, 0.025), ALL)       # pasamanos
	emit_box(st, I, Vector3(-L * 0.5, 0.06, -0.012), Vector3(L * 0.5, 0.1, 0.012), PY | NY | PZ | NZ)
	emit_box(st, I, Vector3(-L * 0.5, h - 0.2, -0.008), Vector3(L * 0.5, h - 0.17, 0.008), PY | NY | PZ | NZ)
	var n := maxi(2, int(L / 0.11))
	for i in n + 1:
		var x := -L * 0.5 + 0.02 + (L - 0.04) * float(i) / float(n)
		var r := 0.03 if (i == 0 or i == n) else 0.009
		emit_box(st, I, Vector3(x - r, 0.0, -r), Vector3(x + r, h - 0.05, r), PX | NX | PZ | NZ)
	var m := _commit([[st, Palette.metal_dark()]])
	_meshes[key] = m
	return m


## Baranda de madera torneada (casas antiguas): balaustres cuadrados cada 15 cm, pasamanos y solera.
static func rail_wood(L: float) -> Mesh:
	var key := "rail_w_%.1f" % L
	if _meshes.has(key):
		return _meshes[key]
	var st := _new_st()
	var I := Transform3D.IDENTITY
	var h := 0.95
	emit_box(st, I, Vector3(-L * 0.5, h - 0.07, -0.05), Vector3(L * 0.5, h, 0.05), ALL)
	emit_box(st, I, Vector3(-L * 0.5, 0.0, -0.04), Vector3(L * 0.5, 0.08, 0.04), PY | PZ | NZ | PX | NX)
	var n := maxi(2, int(L / 0.15))
	for i in n + 1:
		var x := -L * 0.5 + 0.04 + (L - 0.08) * float(i) / float(n)
		var r := 0.055 if (i == 0 or i == n) else 0.022
		emit_box(st, I, Vector3(x - r, 0.08, -r), Vector3(x + r, h - 0.07, r), PX | NX | PZ | NZ)
	var m := _commit([[st, Palette.wood()]])
	_meshes[key] = m
	return m


## Canecillo de alero: viga de madera 10x16 cm, 1.2 m, con la punta cortada en bisel (sale hacia +Z).
static func canecillo() -> Mesh:
	if _meshes.has("canecillo"):
		return _meshes["canecillo"]
	var st := _new_st()
	var I := Transform3D.IDENTITY
	var w := 0.05
	var L := 1.12
	var p := [Vector3(0, 0.16, 0), Vector3(0, 0.0, 0), Vector3(0, 0.0, L - 0.22), Vector3(0, 0.08, L), Vector3(0, 0.16, L)]
	for sx: float in [-w, w]:
		var pts := PackedVector3Array()
		for q in p:
			pts.append((q as Vector3) + Vector3(sx, 0, 0))
		var n := Vector3(signf(sx), 0, 0)
		if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0.0:
			pts.reverse()
		var ns := PackedVector3Array([n, n, n, n, n])
		st.add_triangle_fan(pts, PackedVector2Array(), PackedColorArray(), PackedVector2Array(), ns)
	# fondo, bisel, testa
	emit_face(st, Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, L - 0.22), Vector3(-w, 0, L - 0.22), Vector3.DOWN)
	var bn := Vector3(0, -0.22, 0.08).normalized()
	emit_face(st, Vector3(-w, 0, L - 0.22), Vector3(w, 0, L - 0.22), Vector3(w, 0.08, L), Vector3(-w, 0.08, L), bn)
	emit_face(st, Vector3(-w, 0.08, L), Vector3(w, 0.08, L), Vector3(w, 0.16, L), Vector3(-w, 0.16, L), Vector3.BACK)
	var m := _commit([[st, Palette.wood()]])
	_meshes["canecillo"] = m
	return m


## Tanque plástico de agua (2000 L) con tapa, sobre base de concreto.
static func tank() -> Mesh:
	if _meshes.has("tank"):
		return _meshes["tank"]
	var st := _new_st()
	var sb := _new_st()
	var I := Transform3D.IDENTITY
	emit_box(sb, I, Vector3(-0.8, 0, -0.8), Vector3(0.8, 0.2, 0.8), PX | NX | PY | PZ | NZ)
	_cyl(st, Vector3(0, 0.2, 0), Vector3(0, 1.55, 0), 0.72, 0.68, 12, false)
	_cyl(st, Vector3(0, 1.55, 0), Vector3(0, 1.75, 0), 0.68, 0.36, 12, false)
	_cyl(st, Vector3(0, 1.75, 0), Vector3(0, 1.85, 0), 0.36, 0.34, 12, true)
	for y: float in [0.6, 1.1]:
		_cyl(st, Vector3(0, y, 0), Vector3(0, y + 0.06, 0), 0.74, 0.74, 12, false)
	var m := _commit([[st, tank_mat()], [sb, MatBrick.losa_entrepiso()]])
	_meshes["tank"] = m
	return m


## Antena de TV / mástil con travesaños y riostra.
static func antenna() -> Mesh:
	if _meshes.has("antenna"):
		return _meshes["antenna"]
	var st := _new_st()
	_cyl(st, Vector3.ZERO, Vector3(0, 3.2, 0), 0.03, 0.02, 6, false)
	for i in 4:
		var y := 2.2 + i * 0.3
		var L := 0.9 - i * 0.15
		_cyl(st, Vector3(-L * 0.5, y, 0), Vector3(L * 0.5, y, 0), 0.01, 0.01, 4, false)
	_cyl(st, Vector3(0, 2.0, 0), Vector3(0.0, 2.0, 0.45), 0.012, 0.012, 4, false)
	var m := _commit([[st, Palette.metal_dark()]])
	_meshes["antenna"] = m
	return m


## Parteluz vertical de aluminio (edificio moderno): 7 x 35 cm, 1 m de alto (escalar en Y).
static func fin() -> Mesh:
	if _meshes.has("fin"):
		return _meshes["fin"]
	var st := _new_st()
	emit_box(st, Transform3D.IDENTITY, Vector3(-0.035, 0, -0.35), Vector3(0.035, 1.0, 0.0), PX | NX | PZ)
	var m := _commit([[st, Palette.metal_dark()]])
	_meshes["fin"] = m
	return m


static func _cyl(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, cap: bool) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var p1 := axis.cross(ref).normalized()
	var p2 := axis.cross(p1).normalized()
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := p1 * cos(a0) + p2 * sin(a0)
		var d1 := p1 * cos(a1) + p2 * sin(a1)
		emit_face(st, a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb, (d0 + d1).normalized())
	if cap:
		var pts := PackedVector3Array()
		for i in sides:
			var an := TAU * i / sides
			pts.append(b + (p1 * cos(an) + p2 * sin(an)) * rb)
		if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(axis) > 0.0:
			pts.reverse()
		var ns := PackedVector3Array()
		ns.resize(sides)
		ns.fill(axis)
		st.add_triangle_fan(pts, PackedVector2Array(), PackedColorArray(), PackedVector2Array(), ns)


static func _rail_len(L: float) -> float:
	# cubetas de 0.5 m para compartir MultiMesh
	return maxf(0.5, snappedf(L, 0.5))


## Coloca una baranda metálica/madera de largo L con centro local c, girada `yaw` (0 = a lo largo de X).
static func _rail(b: Ctx, wood: bool, L: float, c: Vector3, yaw: float) -> void:
	var Lb := _rail_len(L)
	var m := rail_wood(Lb) if wood else rail_metal(Lb)
	var t := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(L / Lb, 1, 1)), c)
	b.mesh(("bld_rw_%.1f" if wood else "bld_rm_%.1f") % Lb, m, t, true)


# ------------------------------------------------------------------ piel de fachada con vanos
## Vanos de un piso: Array de Dictionary {u, w, y0, y1, kind, cell, lit}. kind: "win" | "door" | "dark" | "calado".
## Construye la piel de muro (z ∈ [-r, 0]) alrededor de los vanos entre y_lo e y_hi: machones de piso a
## piso (con las caras laterales = rehundido), antepecho bajo el vano y dintel sobre él.
## sill_mat: alféizar saliente (null = sin alféizar); lintel_mat: dintel de petaco (null = sin dintel).
static func _skin(b: Ctx, wall: Material, y_lo: float, y_hi: float, w: float, r: float, ops: Array,
		sill_mat: Material, lintel_mat: Material, pilaster := 0.0) -> void:
	var cur := -w * 0.5
	var first := true
	for op in ops:
		var a: float = float(op.u) - float(op.w) * 0.5
		var e: float = float(op.u) + float(op.w) * 0.5
		if a - cur > 0.01:
			var zf := pilaster if first else 0.0
			b.box(wall, Vector3(cur, y_lo, -r), Vector3(a, y_hi, zf), PZ | PX | (NX if first else 0))
		first = false
		_opening(b, wall, op, y_lo, y_hi, r, sill_mat, lintel_mat)
		cur = e
	if w * 0.5 - cur > 0.01:
		b.box(wall, Vector3(cur, y_lo, -r), Vector3(w * 0.5, y_hi, pilaster), PZ | NX | PX)


static func _opening(b: Ctx, wall: Material, op: Dictionary, y_lo: float, y_hi: float, r: float,
		sill_mat: Material, lintel_mat: Material) -> void:
	var a: float = float(op.u) - float(op.w) * 0.5
	var e: float = float(op.u) + float(op.w) * 0.5
	var y0: float = op.y0
	var y1: float = op.y1
	if y0 - y_lo > 0.01:
		b.box(wall, Vector3(a, y_lo, -r), Vector3(e, y0, 0.0), PZ | (PY if sill_mat == null else 0))
	if y_hi - y1 > 0.01:
		b.box(wall, Vector3(a, y1, -r), Vector3(e, y_hi, 0.0), PZ | NY)
	match String(op.kind):
		"win", "door":
			b.window(int(op.cell), a, e, y0, y1, -r + 0.035, bool(op.lit))
			# marco perimetral de aluminio/madera (da canto a la ventana dentro del vano)
			if sill_mat != null and op.kind == "win":
				b.box(sill_mat, Vector3(a - 0.05, y0 - 0.06, -r), Vector3(e + 0.05, y0 + 0.012, 0.05), PZ | PY | NY | PX | NX, false)
			if lintel_mat != null:
				b.box(lintel_mat, Vector3(a - 0.12, y1, 0.0), Vector3(e + 0.12, minf(y1 + 0.245, y_hi), 0.015), PZ | NY | PX | NX, false)
		"dark":
			b.quad(WorldMaterials.dark_opening(), Vector3(a, y0, -r + 0.01), Vector3(e, y0, -r + 0.01), Vector3(e, y1, -r + 0.01), Vector3(a, y1, -r + 0.01), Vector3.BACK)
		"calado":
			b.quad(WorldMaterials.dark_opening(), Vector3(a, y0, -r + 0.01), Vector3(e, y0, -r + 0.01), Vector3(e, y1, -r + 0.01), Vector3(a, y1, -r + 0.01), Vector3.BACK)
			b.quad(MatBrick.calado(), Vector3(a, y0, -0.06), Vector3(e, y0, -0.06), Vector3(e, y1, -0.06), Vector3(a, y1, -0.06), Vector3.BACK)


## Versión lejana: muro plano (lo pone el cuerpo) + vidrio pegado a la fachada.
static func _flat_ops(b: Ctx, ops: Array) -> void:
	for op in ops:
		var a: float = float(op.u) - float(op.w) * 0.5
		var e: float = float(op.u) + float(op.w) * 0.5
		match String(op.kind):
			"win", "door":
				b.window(int(op.cell), a, e, float(op.y0), float(op.y1), 0.02, bool(op.lit))
			_:
				b.quad(WorldMaterials.dark_opening(), Vector3(a, op.y0, 0.02), Vector3(e, op.y0, 0.02), Vector3(e, op.y1, 0.02), Vector3(a, op.y1, 0.02), Vector3.BACK)


## Reparte n vanos de ancho ww en [u0, u1] con paso ~spacing; devuelve los centros.
static func _bays(u0: float, u1: float, ww: float, spacing: float) -> Array:
	var out := []
	var span := u1 - u0
	if span < ww + 0.4:
		return out
	var n := maxi(1, int(span / spacing))
	var step := span / n
	for i in n:
		out.append(u0 + step * (i + 0.5))
	return out


static func _pick_cell(b: Ctx, main: int, pool: Array[int]) -> int:
	return main if b.rng.randf() < 0.8 else pool[b.rng.randi_range(0, pool.size() - 1)]


# ------------------------------------------------------------------ CASA ANTIOQUEÑA
## Casa de 2 pisos. Huella w x dep, alto de muro g + 3.0, techo a dos aguas con alero de 1 m.
static func house(d, xf: Transform3D, w: float, dep: float, shop: bool, near: bool) -> void:
	var b := Ctx.new(d, xf, near)
	var rng := b.rng
	var g := 3.4 if shop else 3.1
	var h := g + 3.0
	var vw := rng.randi_range(0, 5)
	var vt := posmod(vw + rng.randi_range(1, 5), 6)
	var wall := MatPlaster.stucco_house(vw)
	var trim := MatPlaster.stucco_house(vt)
	var r := 0.22 if near else 0.0
	# Cuerpo (muros laterales = culatas) y colisión como antes.
	b.box(wall, Vector3(-w * 0.5, -1.2, -dep), Vector3(w * 0.5, h, -r), PX | NX | NZ | (PZ if r == 0.0 else 0))
	b.col(Vector3(-w * 0.5, -1.2, -dep), Vector3(w * 0.5, h, 0.0))
	# ---- primer piso
	if shop:
		b.box(wall, Vector3(-w * 0.5, -1.2, -r), Vector3(w * 0.5, g, 0.0), PZ | PX | NX)
		d._shopfront(xf, w, g)
	else:
		var door_u := (-w * 0.5 + 1.0) if rng.randf() < 0.5 else (w * 0.5 - 1.0)
		var ops := [{"u": door_u, "w": 1.15, "y0": 0.0, "y1": 2.45, "kind": "dark", "cell": 0, "lit": false}]
		var rc: int = REJA_CELLS[rng.randi_range(0, 3)]
		var lo := -w * 0.5 + 0.3 if door_u > 0.0 else door_u + 0.9
		var hi := door_u - 0.9 if door_u > 0.0 else w * 0.5 - 0.3
		for u in _bays(lo, hi, 1.15, 2.3):
			ops.append({"u": u, "w": 1.15, "y0": 0.95, "y1": 2.4, "kind": "win", "cell": _pick_cell(b, rc, REJA_CELLS), "lit": rng.randf() < 0.25})
		ops.sort_custom(func(p, q): return float(p.u) < float(q.u))
		if near:
			_skin(b, wall, -1.2, g - 0.05, w, r, ops, MatPlaster.stone_base(), null)
		else:
			_flat_ops(b, ops)
		# Puerta de madera de dos hojas con tablero, montante oscuro arriba.
		var dz := -r + 0.05 if near else 0.02
		b.box(Palette.wood(), Vector3(door_u - 0.56, 0.0, dz - 0.05), Vector3(door_u - 0.01, 2.1, dz), PZ, false)
		b.box(Palette.wood(), Vector3(door_u + 0.01, 0.0, dz - 0.05), Vector3(door_u + 0.56, 2.1, dz), PZ, false)
		if near:
			for sx: float in [-0.28, 0.28]:
				b.box(Palette.wood(), Vector3(door_u + sx - 0.17, 0.25, dz), Vector3(door_u + sx + 0.17, 0.95, dz + 0.03), PZ | PY | NY | PX | NX, false)
				b.box(Palette.wood(), Vector3(door_u + sx - 0.17, 1.15, dz), Vector3(door_u + sx + 0.17, 1.9, dz + 0.03), PZ | PY | NY | PX | NX, false)
			b.box(Palette.wood(), Vector3(door_u - 0.62, 2.1, dz - 0.05), Vector3(door_u + 0.62, 2.18, dz + 0.02), PZ | NY, false)
		# Zócalo de piedra (0 a 0.85 m), interrumpido en la puerta.
		var zz := 0.05
		b.box(MatPlaster.stone_base(), Vector3(-w * 0.5, -1.2, -0.02), Vector3(door_u - 0.58, 0.85, zz), PZ | PY | NX | PX)
		b.box(MatPlaster.stone_base(), Vector3(door_u + 0.58, -1.2, -0.02), Vector3(w * 0.5, 0.85, zz), PZ | PY | NX | PX)
		# Escalón de la puerta
		b.box(MatStone.granito(), Vector3(door_u - 0.65, -0.2, -0.02), Vector3(door_u + 0.65, 0.12, 0.28), PZ | PY | PX | NX, false)
	# ---- moldura de entrepiso
	b.box(trim, Vector3(-w * 0.5, g - 0.05, -r), Vector3(w * 0.5, g + 0.25, 0.08), PZ | PY | NY | PX | NX)
	# ---- segundo piso: puertas-ventana altas de madera
	var uc: int = HOUSE_UP_CELLS[rng.randi_range(0, HOUSE_UP_CELLS.size() - 1)]
	var up := []
	for u in _bays(-w * 0.5 + 0.4, w * 0.5 - 0.4, 1.05, 2.3):
		up.append({"u": u, "w": 1.05, "y0": g + 0.45, "y1": g + 2.55, "kind": "door", "cell": _pick_cell(b, uc, HOUSE_UP_CELLS), "lit": rng.randf() < 0.3})
	if near:
		_skin(b, wall, g + 0.25, h, w, r, up, null, null)
		# vierteaguas/remarco de las puertas-ventana
		for op in up:
			b.box(trim, Vector3(float(op.u) - 0.68, g + 2.55, -0.02), Vector3(float(op.u) + 0.68, g + 2.7, 0.06), PZ | PY | NY | PX | NX, false)
	else:
		_flat_ops(b, up)
	var corrido := rng.randf() < 0.55 and up.size() > 0
	if corrido:
		# Balcón corrido de madera sobre la moldura.
		var bl := minf(w - 0.6, maxf(3.0, float(up[-1].u) - float(up[0].u) + 1.8))
		var cu := (float(up[0].u) + float(up[-1].u)) * 0.5
		var by := g + 0.25
		b.box(Palette.wood(), Vector3(cu - bl * 0.5, by, 0.0), Vector3(cu + bl * 0.5, by + 0.12, 0.92), PZ | PY | NY | PX | NX)
		if near:
			_rail(b, true, bl, Vector3(cu, by + 0.12, 0.87), 0.0)
			_rail(b, true, 0.85, Vector3(cu - bl * 0.5 + 0.05, by + 0.12, 0.44), PI * 0.5)
			_rail(b, true, 0.85, Vector3(cu + bl * 0.5 - 0.05, by + 0.12, 0.44), PI * 0.5)
			# ménsulas bajo el balcón
			var u := cu - bl * 0.5 + 0.2
			while u <= cu + bl * 0.5 - 0.1:
				b.box(Palette.wood(), Vector3(u - 0.05, by - 0.28, 0.0), Vector3(u + 0.05, by, 0.75), PZ | NY | PX | NX, false)
				u += 1.1
		else:
			b.box(Palette.wood(), Vector3(cu - bl * 0.5, by + 0.85, 0.82), Vector3(cu + bl * 0.5, by + 1.0, 0.92), PZ | PY, false)
	elif near:
		# Balconcillos de hierro por ventana.
		for op in up:
			var u: float = op.u
			b.box(MatStone.granito(), Vector3(u - 0.7, g + 0.3, 0.0), Vector3(u + 0.7, g + 0.44, 0.38), PZ | PY | NY | PX | NX)
			_rail(b, false, 1.4, Vector3(u, g + 0.44, 0.35), 0.0)
	# ---- alero, canecillos y techo de teja
	var a := 1.0
	var zb := -dep - 0.3
	var zr := (a + zb) * 0.5
	var rh := 1.6
	var ry := h + rh
	var wx := w * 0.5 + 0.02
	# tabla del alero (sofito de madera) y tapa
	b.box(Palette.wood(), Vector3(-wx, h - 0.03, -r), Vector3(wx, h, a), NY | PZ, true)
	if near:
		var u := -w * 0.5 + 0.3
		while u < w * 0.5 - 0.1:
			b.mesh("bld_canecillo", canecillo(), Transform3D(Basis.IDENTITY, Vector3(u, h - 0.19, -r)), false)
			u += 0.6
	_roof(b, wall, -wx, wx, a, zb, zr, h, ry, r)


## Techo a dos aguas con teja (UV propias), culatas triangulares, cumbrera y tapa del alero.
static func _roof(b: Ctx, wall: Material, x0: float, x1: float, zf: float, zb: float, zr: float, y0: float, ry: float, r: float) -> void:
	var t := 0.12
	var st := b.st(roof_mat(), true)
	_roof_slope(b, st, x0, x1, Vector3(0, y0 + t, zf), Vector3(0, ry + t, zr))
	_roof_slope(b, st, x0, x1, Vector3(0, y0 + t, zb), Vector3(0, ry + t, zr))
	# canto (espesor) en los bordes de alero
	b.box(Palette.wood(), Vector3(x0, y0 - 0.1, zf - 0.05), Vector3(x1, y0 + t + 0.02, zf), PZ | NY | PY)
	# culatas: triángulos de muro sobre el cuerpo (z de zb+0.3 a -r) y tapa de madera en el vuelo
	var yF := func(z: float) -> float: return y0 + (ry - y0) * (zf - z) / (zf - zr)
	for sx: float in [x0 + 0.02, x1 - 0.02]:
		var n := Vector3(signf(sx), 0, 0)
		var zbb := zb + 0.3
		var yb := y0 + (ry - y0) * (z_abs(zbb - zb)) / (zr - zb)
		b.poly(wall, [Vector3(sx, y0, zbb), Vector3(sx, y0, -r), Vector3(sx, yF.call(-r), -r), Vector3(sx, ry, zr), Vector3(sx, yb, zbb)], n)
		b.poly(Palette.wood(), [Vector3(sx, y0, -r), Vector3(sx, y0, zf), Vector3(sx, y0 + t, zf), Vector3(sx, yF.call(-r) + t, -r)], n, false)
	# cumbrera
	b.box(MatPlaster.roof_clay(), Vector3(x0, ry + t - 0.02, zr - 0.13), Vector3(x1, ry + t + 0.1, zr + 0.13), PY | PZ | NZ | PX | NX)


static func z_abs(v: float) -> float:
	return absf(v)


## Faldón de teja: de la línea de alero `eave` (z, y) a la cumbrera `ridge`; UV: u = x/2, v = distancia/2.
static func _roof_slope(b: Ctx, st: SurfaceTool, x0: float, x1: float, eave: Vector3, ridge: Vector3) -> void:
	var xf := b.xf
	var p0 := xf * Vector3(x0, ridge.y, ridge.z)
	var p1 := xf * Vector3(x1, ridge.y, ridge.z)
	var p2 := xf * Vector3(x1, eave.y, eave.z)
	var p3 := xf * Vector3(x0, eave.y, eave.z)
	var slope_len := Vector2(eave.z - ridge.z, eave.y - ridge.y).length()
	var tang := xf.basis.x.normalized()
	var down := (p3 - p0).normalized()
	var n := tang.cross(down).normalized()
	if n.y < 0.0:
		n = -n
	# binormal (arriba en la imagen) = -down; w para que cross(n, t) * w = -down
	var w := 1.0 if n.cross(tang).dot(-down) > 0.0 else -1.0
	var tp := Plane(tang, w)
	var vs := PackedVector3Array([p0, p1, p2, p3])
	var uv := PackedVector2Array([Vector2(x0 * 0.5, 0), Vector2(x1 * 0.5, 0), Vector2(x1 * 0.5, slope_len * 0.5), Vector2(x0 * 0.5, slope_len * 0.5)])
	if (vs[1] - vs[0]).cross(vs[2] - vs[0]).dot(n) > 0.0:
		vs = PackedVector3Array([vs[0], vs[3], vs[2], vs[1]])
		uv = PackedVector2Array([uv[0], uv[3], uv[2], uv[1]])
	st.add_triangle_fan(vs, uv, PackedColorArray(), PackedVector2Array(), PackedVector3Array([n, n, n, n]), [tp, tp, tp, tp])


# ------------------------------------------------------------------ APARTAMENTOS (ladrillo o estuco)
## floors = pisos totales (primer piso de 3.4 m + pisos de 2.8 m). brick: ladrillo a la vista con losas.
static func apartment(d, xf: Transform3D, w: float, dep: float, shop: bool, wall: Material, floors: int, near: bool, brick: bool) -> void:
	var b0 := Ctx.new(d, xf, near)
	var rng := b0.rng
	var g := 3.4
	var fh := 2.8
	var yt := g + fh * (floors - 1)        # placa de cubierta
	var h := yt + 0.9                      # remate del antepecho de azotea (como antes)
	var r := 0.18 if near else 0.0
	# Antejardín (solo residencial, sin local): retrocede la fachada s metros.
	var s := 0.0
	if not shop and dep > 10.0 and rng.randf() < 0.55:
		s = rng.randf_range(2.2, 3.0)
	var b := Ctx.new(d, xf.translated_local(Vector3(0, 0, -s)), near)
	b.rng = rng
	var de := dep - s
	# Retranqueo del último piso en edificios altos (volúmenes escalonados).
	var step := floors >= 6 and rng.randf() < 0.45
	var sb := 2.0 if step else 0.0
	var yb := (yt - fh) if step else yt     # alto del volumen principal
	var slab_mat: Material = MatBrick.losa_entrepiso() if brick else wall
	var trim_mat: Material = MatBrick.losa_entrepiso() if brick else MatPlaster.concrete_smooth()
	# ---- cuerpo y colisión
	b.box(wall, Vector3(-w * 0.5, -1.2, -de), Vector3(w * 0.5, yb, -r), PX | NX | NZ | (PZ if r == 0.0 else 0))
	b.col(Vector3(-w * 0.5, -1.2, -de), Vector3(w * 0.5, yb + 0.9, 0.0))
	if step:
		b.box(wall, Vector3(-w * 0.5, yb, -de), Vector3(w * 0.5, yt, -sb - r), PX | NX | NZ | (PZ if r == 0.0 else 0))
		b.col(Vector3(-w * 0.5, yb, -de), Vector3(w * 0.5, h, -sb))
	# ---- primer piso
	var lit_p := 0.3
	var rc: int = REJA_CELLS[rng.randi_range(0, REJA_CELLS.size() - 1)]
	if shop:
		b.box(wall, Vector3(-w * 0.5, -1.2, -r), Vector3(w * 0.5, g, 0.0), PZ | PX | NX)
		d._shopfront(b.xf, w, g)
	else:
		var eu := -w * 0.5 + 1.3 if rng.randf() < 0.5 else w * 0.5 - 1.3
		var ops := [{"u": eu, "w": 1.6, "y0": 0.45 if s > 0.0 else 0.0, "y1": 2.5, "kind": "door", "cell": 6, "lit": rng.randf() < 0.5}]
		var lo := -w * 0.5 + 0.4 if eu > 0.0 else eu + 1.3
		var hi := eu - 1.3 if eu > 0.0 else w * 0.5 - 0.4
		for u in _bays(lo, hi, 1.3, 2.5):
			ops.append({"u": u, "w": 1.3, "y0": 1.0, "y1": 2.45, "kind": "win", "cell": _pick_cell(b, rc, REJA_CELLS), "lit": rng.randf() < lit_p})
		ops.sort_custom(func(p, q): return float(p.u) < float(q.u))
		var gm: Material = MatPlaster.concrete_board() if (brick and rng.randf() < 0.4) else wall
		if near:
			_skin(b, gm, -1.2, g - 0.12, w, r, ops, trim_mat, null)
		else:
			b.box(gm, Vector3(-w * 0.5, -1.2, 0.0), Vector3(w * 0.5, g - 0.12, 0.01), PZ)
			_flat_ops(b, ops)
		# marquesina de acceso
		b.box(MatPlaster.concrete_smooth(), Vector3(eu - 1.2, 2.75, -r), Vector3(eu + 1.2, 2.9, 1.1), PZ | PY | NY | PX | NX)
		if s > 0.0:
			_garden(b, wall, w, s, eu)
	# ---- pisos altos
	var ww := 1.5 if brick else 1.25
	var spacing := rng.randf_range(2.4, 2.9)
	var cell: int = UP_CELLS[rng.randi_range(0, UP_CELLS.size() - 1)]
	var stair_u := 99.0
	if brick and near and w >= 10.0 and rng.randf() < 0.55:
		stair_u = (w * 0.5 - 1.15) * (1.0 if rng.randf() < 0.5 else -1.0)
	var lo2 := -w * 0.5 + 0.5
	var hi2 := w * 0.5 - 0.5
	if stair_u < 0.0:
		lo2 = stair_u + 1.25
	elif stair_u < 50.0:
		hi2 = stair_u - 1.25
	var bays := _bays(lo2, hi2, ww, spacing)
	# Balcones: columna(s) de balcones en vanos elegidos.
	var bal_kind := rng.randi_range(0, 2) if rng.randf() < 0.65 else -1   # 0 antepecho de ladrillo, 1 baranda, 2 mixto
	var bal_bays := {}
	if bal_kind >= 0 and bays.size() > 0:
		if bays.size() >= 3 and rng.randf() < 0.5:
			bal_bays[0] = true
			bal_bays[bays.size() - 1] = true
		else:
			bal_bays[rng.randi_range(0, bays.size() - 1)] = true
	var lintel: Material = MatBrick.petaco() if brick else null
	for f in range(1, floors):
		var y := g + fh * (f - 1)
		var top_floor := step and f == floors - 1
		var bf := b
		if top_floor:
			bf = Ctx.new(d, b.xf.translated_local(Vector3(0, 0, -sb)), near)
			bf.rng = rng
		# franja de losa de entrepiso
		bf.box(slab_mat, Vector3(-w * 0.5 - 0.02, y - 0.12, -r), Vector3(w * 0.5 + 0.02, y + 0.12, 0.05), PZ | PY | NY | PX | NX)
		var ops := []
		for i in bays.size():
			var u: float = bays[i]
			var is_bal: bool = bal_bays.has(i) and not top_floor
			if is_bal:
				ops.append({"u": u, "w": ww + 0.2, "y0": y + 0.12, "y1": y + 2.3, "kind": "door", "cell": _pick_cell(b, cell, UP_CELLS), "lit": rng.randf() < lit_p})
			else:
				ops.append({"u": u, "w": ww, "y0": y + 0.95, "y1": y + 2.35, "kind": "win", "cell": _pick_cell(b, cell, UP_CELLS), "lit": rng.randf() < lit_p})
		if stair_u < 50.0:
			ops.append({"u": stair_u, "w": 1.5, "y0": y + 0.12, "y1": y + fh - 0.12, "kind": "calado", "cell": 0, "lit": false})
		ops.sort_custom(func(p, q): return float(p.u) < float(q.u))
		if near:
			_skin(bf, wall, y + 0.12, y + fh - 0.12, w, r, ops, trim_mat, lintel, 0.06 if brick else 0.0)
		else:
			_flat_ops(bf, ops)
		# balcones
		for i in bal_bays:
			if top_floor:
				continue
			_balcony(bf, wall, slab_mat, bays[i], ww + 1.3, y, bal_kind, f, near, brick)
	# franja de losa de cubierta + antepecho de azotea con remate
	var bt := b if not step else Ctx.new(d, b.xf.translated_local(Vector3(0, 0, -sb)), near)
	bt.box(slab_mat, Vector3(-w * 0.5 - 0.02, yt - 0.12, -r), Vector3(w * 0.5 + 0.02, yt + 0.12, 0.05), PZ | NY | PX | NX)
	bt.box(wall, Vector3(-w * 0.5, yt + 0.12, -r), Vector3(w * 0.5, h, 0.0), PZ | PX | NX)
	bt.box(trim_mat, Vector3(-w * 0.5 - 0.05, h, -r - 0.05), Vector3(w * 0.5 + 0.05, h + 0.08, 0.06), PZ | PY | NY | PX | NX)
	if step:
		# terraza del retranqueo: losa y baranda/antepecho al borde del volumen principal
		b.box(slab_mat, Vector3(-w * 0.5 - 0.02, yb - 0.12, -r), Vector3(w * 0.5 + 0.02, yb + 0.12, 0.05), PZ | NY | PX | NX)
		b.box(WorldMaterials.roof_flat(), Vector3(-w * 0.5, yb, -sb - r), Vector3(w * 0.5, yb + 0.13, 0.0), PY, false)
		if brick and rng.randf() < 0.5:
			b.box(wall, Vector3(-w * 0.5, yb + 0.12, -0.15), Vector3(w * 0.5, yb + 1.0, 0.0), PZ | PY | NZ | PX | NX)
		else:
			b.box(wall, Vector3(-w * 0.5, yb + 0.12, -0.15), Vector3(w * 0.5, yb + 0.3, 0.0), PZ | PY | PX | NX)
			if near:
				var n := maxi(1, int(round(w / 3.0)))
				for k in n:
					var L := w / n
					_rail(b, false, L - 0.05, Vector3(-w * 0.5 + L * (k + 0.5), yb + 0.3, -0.07), 0.0)
	# azotea
	var zs := -sb - r
	b.box(WorldMaterials.roof_flat(), Vector3(-w * 0.5, yt + 0.12, -de), Vector3(w * 0.5, yt + 0.14, zs), PY, false)
	for sx: float in [-1.0, 1.0]:
		b.box(wall, Vector3(sx * w * 0.5 - (0.15 if sx > 0 else 0.0), yt, -de), Vector3(sx * w * 0.5 + (0.15 if sx < 0 else 0.0), h, zs), PY | NX | PX)
	_rooftop(b, wall, trim_mat, w, de, yt + 0.14, zs)


## Balcón de un vano: losa saliente, antepecho de ladrillo o baranda metálica (MultiMesh).
static func _balcony(b: Ctx, wall: Material, slab: Material, u: float, bw: float, y: float, kind: int, f: int, near: bool, brick: bool) -> void:
	var bd := 1.05
	var x0 := u - bw * 0.5
	var x1 := u + bw * 0.5
	b.box(slab, Vector3(x0, y - 0.12, 0.0), Vector3(x1, y + 0.12, bd), PZ | PY | NY | PX | NX)
	var solid := kind == 0 or (kind == 2 and f % 2 == 1)
	if solid or not near:
		# antepecho de ladrillo (frente y costados) con remate de petaco
		var am: Material = wall
		b.box(am, Vector3(x0, y + 0.12, bd - 0.12), Vector3(x1, y + 1.0, bd), PZ | NZ | PX | NX)
		if near:
			for sx: float in [x0, x1 - 0.12]:
				b.box(am, Vector3(sx, y + 0.12, 0.0), Vector3(sx + 0.12, y + 1.0, bd - 0.12), PX | NX)
			b.box(MatBrick.petaco() if brick else MatPlaster.concrete_smooth(), Vector3(x0 - 0.02, y + 1.0, -0.0), Vector3(x1 + 0.02, y + 1.06, bd + 0.02), PY | PZ | PX | NX, false)
	else:
		# sardinel bajo + baranda
		b.box(slab, Vector3(x0, y + 0.12, bd - 0.1), Vector3(x1, y + 0.25, bd), PZ | PY | NZ | PX | NX, false)
		_rail(b, false, bw - 0.06, Vector3(u, y + 0.25, bd - 0.05), 0.0)
		_rail(b, false, bd - 0.1, Vector3(x0 + 0.03, y + 0.12, (bd - 0.1) * 0.5), PI * 0.5)
		_rail(b, false, bd - 0.1, Vector3(x1 - 0.03, y + 0.12, (bd - 0.1) * 0.5), PI * 0.5)


## Antejardín: muro bajo de ladrillo con remate, seto, sendero y escalas de acceso (z de 0 a s).
static func _garden(b: Ctx, wall: Material, w: float, s: float, eu: float) -> void:
	var pw := 1.7
	var hedge := MatFoliage.hedge()
	var brick_w: Material = MatBrick.fachada_variante(0)
	for side in 2:
		var x0 := -w * 0.5 if side == 0 else eu + pw * 0.5
		var x1 := eu - pw * 0.5 if side == 0 else w * 0.5
		if x1 - x0 < 0.3:
			continue
		# jardinera elevada 0.65 m (muro de 15 cm) con seto
		b.box(brick_w, Vector3(x0, -0.3, s - 0.15), Vector3(x1, 0.65, s), PZ | PY | PX | NX)
		b.box(MatBrick.petaco(), Vector3(x0, 0.65, s - 0.17), Vector3(x1, 0.72, s + 0.02), PZ | PY | PX | NX, false)
		b.box(MatGround.mantillo(), Vector3(x0, 0.0, 0.0), Vector3(x1, 0.55, s - 0.15), PY, false)
		b.box(hedge, Vector3(x0 + 0.15, 0.55, 0.25), Vector3(x1 - 0.15, 1.15, s - 0.35), PY | PZ | PX | NX)
		b.col(Vector3(x0, -0.3, 0.0), Vector3(x1, 0.72, s))
	# sendero y escalas: tres peldaños de granito hasta un descanso de +0.45 m
	var g := MatStone.granito()
	b.box(g, Vector3(eu - pw * 0.5, 0.0, 0.0), Vector3(eu + pw * 0.5, 0.45, s - 0.9), PY | PZ, false)
	for k in 3:
		var z1 := s - 0.9 + 0.3 * (k + 1)
		b.box(g, Vector3(eu - pw * 0.5, 0.0, s - 0.9 + 0.3 * k), Vector3(eu + pw * 0.5, 0.45 - 0.15 * (k + 1) + 0.15, z1), PY | PZ, false)
	# pasamanos metálico
	_rail(b, false, 1.2, Vector3(eu + pw * 0.5 - 0.05, 0.3, s - 0.6), PI * 0.5)


## Azotea: cuarto de máquinas / punto fijo, tanque de agua, antenas.
static func _rooftop(b: Ctx, wall: Material, trim: Material, w: float, de: float, y: float, zf: float) -> void:
	var rng := b.rng
	if rng.randf() < 0.6 and w > 7.0 and de > 6.0:
		var cx := rng.randf_range(-w * 0.5 + 2.0, w * 0.5 - 2.0)
		var cz := rng.randf_range(-de + 2.0, minf(zf - 2.5, -de + 6.0))
		b.box(wall, Vector3(cx - 1.4, y, cz - 1.4), Vector3(cx + 1.4, y + 2.6, cz + 1.4), PX | NX | PZ | NZ)
		b.box(trim, Vector3(cx - 1.5, y + 2.6, cz - 1.5), Vector3(cx + 1.5, y + 2.75, cz + 1.5), ALL & ~NY)
		b.box(Palette.metal_dark(), Vector3(cx - 0.45, y, cz + 1.4), Vector3(cx + 0.45, y + 2.05, cz + 1.43), PZ, false)
		if rng.randf() < 0.7:
			b.mesh("bld_tank", tank(), Transform3D(Basis.IDENTITY, Vector3(cx + rng.randf_range(-0.6, 0.6), y + 2.75, cz)))
	elif rng.randf() < 0.6:
		b.mesh("bld_tank", tank(), Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-w * 0.3, w * 0.3), y, rng.randf_range(-de + 1.5, zf - 1.5))))
	if rng.randf() < 0.35:
		b.mesh("bld_antenna", antenna(), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-w * 0.4, w * 0.4), y, rng.randf_range(-de + 1.0, zf - 1.0))), false)


# ------------------------------------------------------------------ EDIFICIO MODERNO (vidrio y concreto)
static func modern(d, xf: Transform3D, w: float, dep: float, shop: bool, floors: int, near: bool) -> void:
	var b := Ctx.new(d, xf, near)
	var rng := b.rng
	var g := 4.0
	var fh := 3.0
	var yt := g + fh * (floors - 1)
	var h := yt + 1.0
	var conc := MatPlaster.concrete_smooth()
	var rg := 0.7                               # retroceso del vidrio
	var glass := Palette.window_glass()
	b.box(conc, Vector3(-w * 0.5, -1.2, -dep), Vector3(w * 0.5, yt, -rg), PX | NX | NZ)
	b.col(Vector3(-w * 0.5, -1.2, -dep), Vector3(w * 0.5, h, 0.0))
	# marco lateral de concreto en toda la altura
	for sx: float in [-1.0, 1.0]:
		var xa := sx * w * 0.5
		var xb := sx * (w * 0.5 - 0.45)
		b.box(conc, Vector3(minf(xa, xb), -1.2, -rg), Vector3(maxf(xa, xb), h, 0.35), PZ | PX | NX | PY)
	var gx0 := -w * 0.5 + 0.45
	var gx1 := w * 0.5 - 0.45
	# primer piso
	if shop:
		b.box(conc, Vector3(gx0, -1.2, -rg), Vector3(gx1, g, 0.0), PZ)
		d._shopfront(xf, w, g)
	else:
		b.quad(glass, Vector3(gx0, 0, -rg - 0.6), Vector3(gx1, 0, -rg - 0.6), Vector3(gx1, g - 0.3, -rg - 0.6), Vector3(gx0, g - 0.3, -rg - 0.6), Vector3.BACK)
		b.box(conc, Vector3(gx0, -1.2, -rg - 0.6), Vector3(gx1, 0.05, 0.0), PY, false)
		b.box(conc, Vector3(gx0, g - 0.3, -rg - 0.6), Vector3(gx1, g, 0.0), NY, false)
		var u := gx0 + 2.5
		while u < gx1 - 1.0:
			b.box(conc, Vector3(u - 0.2, 0.0, -0.4), Vector3(u + 0.2, g, 0.0), PZ | PX | NX)
			u += 5.0
	var lit_c := 6
	for f in range(1, floors):
		var y := g + fh * (f - 1)
		# losa gruesa saliente
		b.box(conc, Vector3(gx0, y - 0.3, -rg), Vector3(gx1, y + 0.2, 0.35), PZ | PY | NY)
		# vidrio de piso a techo (paños de 1.5 m; algunos con interior encendido)
		var n := maxi(1, int((gx1 - gx0) / 1.5))
		var pw := (gx1 - gx0) / n
		for k in n:
			var x0 := gx0 + pw * k
			if rng.randf() < 0.18:
				b.window(lit_c, x0, x0 + pw, y + 0.2, y + fh - 0.3, -rg + 0.02, true)
			else:
				b.quad(glass, Vector3(x0, y + 0.2, -rg + 0.02), Vector3(x0 + pw, y + 0.2, -rg + 0.02), Vector3(x0 + pw, y + fh - 0.3, -rg + 0.02), Vector3(x0, y + fh - 0.3, -rg + 0.02), Vector3.BACK)
			if near and k > 0:
				b.mesh("bld_fin", fin(), Transform3D(Basis.from_scale(Vector3(1, fh - 0.5, 1)), Vector3(x0, y + 0.2, 0.3)), false)
		# baranda de vidrio sobre la losa (vidrio + pasamanos)
		if near:
			b.box(Palette.metal_dark(), Vector3(gx0, y + 1.05, 0.25), Vector3(gx1, y + 1.1, 0.3), PZ | PY | NY, false)
	# visera superior (volumen pesado de concreto) y azotea
	b.box(conc, Vector3(-w * 0.5, yt - 0.3, -rg), Vector3(w * 0.5, h, 1.0), PZ | PY | NY | PX | NX)
	b.box(WorldMaterials.roof_flat(), Vector3(-w * 0.5, yt, -dep), Vector3(w * 0.5, yt + 0.02, -rg), PY, false)
	_rooftop(b, conc, conc, w, dep, yt + 0.02, -rg)

class_name Plants
extends RefCounted
## Vegetación baja y de andén (F2-02): palmas altas y pequeñas, macizos de jardín, setos recortados,
## parches de hiedra, matas de pasto alto, agaves y alcorques de andén.
## Todas las funciones devuelven ArrayMesh multi-superficie (≤ 4 materiales) CACHEADOS por variante.
## Origen de cada modelo = punto de apoyo en el suelo (y = 0). Unidades en metros.
## Los modelos planos (seto, hiedra, macizo, alcorque) asumen suelo horizontal: en el mapa se colocan
## con la base inclinada según la pendiente (ver BostonDistrict._p2plants_*).

const TALL_PALM_VARIANTS := 3
const SMALL_PALM_VARIANTS := 2
const CLUMP_VARIANTS := 5
const HEDGE_VARIANTS := 3
const GRASS_VARIANTS := 2
const AGAVE_VARIANTS := 2
const PIT_VARIANTS := 3
const HEDGE_SEG := 2.0          # largo de un tramo de seto (se repite cada 2 m)

## Recorte (en fracción de celda) del contenido opaco de cada celda del atlas de jardín:
## [u0, v0, u1, v1] → 0 crotón, 1 helecho, 2 heliconia, 3 hoja morada.
const GARDEN_CROP := [
	[0.24, 0.32, 0.98, 1.0],
	[0.09, 0.58, 0.91, 1.0],
	[0.14, 0.26, 0.96, 1.0],
	[0.09, 0.54, 0.92, 1.0],
]

static var _cache := {}
static var _info := {}


# ================================================================== materiales propios
static func _own_mat(key: String, make: Callable) -> Material:
	if not _cache.has("mat_" + key):
		_cache["mat_" + key] = make.call()
	return _cache["mat_" + key]


## Capitel (crownshaft) verde liso de la palma real / areca y racimos de frutos: color por vértice
## (una sola superficie para ambos → una draw call menos por palma).
static func _crown_mat() -> Material:
	return _own_mat("crown", func():
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		m.roughness = 0.55
		m.metallic_specular = 0.4
		return m)


## Hojas de pasto alto con color por vértice (base oscura → punta amarillenta), doble cara.
static func _grass_mat() -> Material:
	return _own_mat("grass", func():
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		m.roughness = 0.8
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.backlight_enabled = true
		m.backlight = Color(0.25, 0.3, 0.08)
		return m)


## Agave azul verdoso ceroso, borde amarillento por color de vértice.
static func _agave_mat() -> Material:
	return _own_mat("agave", func():
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		m.roughness = 0.45
		m.metallic_specular = 0.55
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m)


# ================================================================== constructor de mallas
class _B:
	var st := {}
	var mat := {}
	var order: Array = []
	var tris := 0
	var tangents := {}
	var color := Color.WHITE   # color de vértice por defecto (solo lo usan los materiales con vertex color)

	func s(key: String, m: Material, tan := true) -> SurfaceTool:
		if not st.has(key):
			var t := SurfaceTool.new()
			t.begin(Mesh.PRIMITIVE_TRIANGLES)
			st[key] = t
			mat[key] = m
			order.append(key)
			tangents[key] = tan
		return st[key]

	## Triángulo con normal/uv/color por vértice; se reordena para que la cara frontal mire a la normal.
	func tri(key: String, m: Material, p: Array, n: Array, uv: Array, col: Array = []) -> void:
		var t := s(key, m)
		var ref: Vector3 = n[0] + n[1] + n[2]
		var idx := [0, 1, 2]
		if (p[1] - p[0]).cross(p[2] - p[0]).dot(ref) > 0.0:
			idx = [0, 2, 1]
		for i in idx:
			t.set_normal(n[i])
			t.set_uv(uv[i])
			t.set_color(col[i] if col.size() == 3 else color)
			t.add_vertex(p[i])
		tris += 1

	## Cuadrilátero a-b-c-d (orden perimetral).
	func quad(key: String, m: Material, p: Array, n: Array, uv: Array, col: Array = []) -> void:
		var c1: Array = [] if col.is_empty() else [col[0], col[1], col[2]]
		var c2: Array = [] if col.is_empty() else [col[0], col[2], col[3]]
		tri(key, m, [p[0], p[1], p[2]], [n[0], n[1], n[2]], [uv[0], uv[1], uv[2]], c1)
		tri(key, m, [p[0], p[2], p[3]], [n[0], n[2], n[3]], [uv[0], uv[2], uv[3]], c2)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for k in order:
			var t: SurfaceTool = st[k]
			if tangents[k]:
				t.generate_tangents()
			t.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat[k])
		mesh.set_meta("tris", tris)
		return mesh


static func _rng(name: String, variant: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(name) + variant * 7919 + 17
	return r


## Ruido suave barato (suma de senos), rango ≈ [-1, 1].
static func _noise(x: float, y: float, sd: float) -> float:
	return 0.5 * sin(x * 2.1 + sd) * sin(y * 1.7 + sd * 1.3) \
		+ 0.3 * sin(x * 4.3 - y * 3.7 + sd * 0.7) + 0.2 * sin(x * 7.9 + y * 6.1 + sd * 2.1)


# ================================================================== piezas
## Fronda arqueada: tira curva de `segs` segmentos con sección en V invertida (folíolos colgantes).
## base: arranque, az: azimut, elev: elevación inicial (rad), droop: cuánto cae hacia la punta (rad).
static func _frond(b: _B, m: Material, base: Vector3, az: float, elev: float, L: float, droop: float,
		fold: float, roll: float, segs: int = 6) -> void:
	var horiz := Vector3(cos(az), 0.0, sin(az))
	var side0 := Vector3(-sin(az), 0.0, cos(az))
	var W := L * 0.5
	var rows: Array = []
	var p := base
	for i in segs + 1:
		var t := float(i) / segs
		var th := elev - droop * pow(t, 1.5)
		var d := (horiz * cos(th) + Vector3.UP * sin(th)).normalized()
		var side := side0.rotated(d, roll * t)
		var n := side.cross(d).normalized()
		if n.y < 0.0:
			n = -n
		var uc := lerpf(0.5, 0.66, t)
		var v := 1.0 - t
		# Ancho reducido al arranque (el raquis desnudo) para que no se vea una lámina rígida.
		var ws := 1.0 if t > 0.15 else lerpf(0.4, 1.0, t / 0.15)
		var l := p - side * W * uc * ws - n * fold * W * uc * ws
		var r := p + side * W * (1.0 - uc) * ws - n * fold * W * (1.0 - uc) * ws
		var ns := (n + Vector3.UP * 0.5).normalized()
		rows.append([l, p, r, (ns - side * 0.35).normalized(), ns, (ns + side * 0.35).normalized(), uc, v])
		p += d * (L / segs)
	for i in segs:
		var A: Array = rows[i]
		var B2: Array = rows[i + 1]
		b.quad("frond", m, [A[0], A[1], B2[1], B2[0]], [A[3], A[4], B2[4], B2[3]],
			[Vector2(0, A[7]), Vector2(A[6], A[7]), Vector2(B2[6], B2[7]), Vector2(0, B2[7])])
		b.quad("frond", m, [A[1], A[2], B2[2], B2[1]], [A[4], A[5], B2[5], B2[4]],
			[Vector2(A[6], A[7]), Vector2(1, A[7]), Vector2(1, B2[7]), Vector2(B2[6], B2[7])])


## Tubo a lo largo de una polilínea (radios por punto). UV cilíndricas: U = vuelta, V = arco·v_per_m.
static func _tube(b: _B, key: String, m: Material, pts: Array, radii: Array, sides: int, v_per_m: float,
		cap_top: bool = false) -> void:
	var frames: Array = []
	var ref := Vector3.FORWARD
	for i in pts.size():
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			t = (pts[i] - pts[i - 1]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		if absf(t.dot(ref)) > 0.95:
			ref = Vector3.RIGHT
		var nn := t.cross(ref).normalized()
		var bb := nn.cross(t).normalized()
		frames.append([nn, bb])
	var arc := 0.0
	var vs: Array = [0.0]
	for i in range(1, pts.size()):
		arc += (pts[i] - pts[i - 1]).length()
		vs.append(arc * v_per_m)
	for i in pts.size() - 1:
		for j in sides:
			var a0 := TAU * j / sides
			var a1 := TAU * (j + 1) / sides
			var f0: Array = frames[i]
			var f1: Array = frames[i + 1]
			var d00: Vector3 = f0[0] * cos(a0) + f0[1] * sin(a0)
			var d01: Vector3 = f0[0] * cos(a1) + f0[1] * sin(a1)
			var d10: Vector3 = f1[0] * cos(a0) + f1[1] * sin(a0)
			var d11: Vector3 = f1[0] * cos(a1) + f1[1] * sin(a1)
			var u0 := float(j) / sides
			var u1 := float(j + 1) / sides
			b.quad(key, m, [pts[i] + d00 * radii[i], pts[i] + d01 * radii[i], pts[i + 1] + d11 * radii[i + 1], pts[i + 1] + d10 * radii[i + 1]],
				[d00, d01, d11, d10],
				[Vector2(u0, vs[i]), Vector2(u1, vs[i]), Vector2(u1, vs[i + 1]), Vector2(u0, vs[i + 1])])
	if cap_top:
		var k := pts.size() - 1
		var c: Vector3 = pts[k]
		var ax: Vector3 = (pts[k] - pts[k - 1]).normalized()
		for j in sides:
			var a0 := TAU * j / sides
			var a1 := TAU * (j + 1) / sides
			var f: Array = frames[k]
			var d0: Vector3 = f[0] * cos(a0) + f[1] * sin(a0)
			var d1: Vector3 = f[0] * cos(a1) + f[1] * sin(a1)
			b.tri(key, m, [c + d0 * radii[k], c + d1 * radii[k], c + ax * radii[k] * 1.2], [ax, ax, ax],
				[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE])


## Tarjeta del atlas de jardín apoyada en el suelo: base en `at`, girada `yaw`, inclinada hacia fuera `tilt`.
static func _garden_card(b: _B, m: Material, at: Vector3, yaw: float, h: float, cell: int, tilt: float,
		flip: bool) -> void:
	var cr: Array = GARDEN_CROP[cell]
	var aspect: float = (cr[2] - cr[0]) / (cr[3] - cr[1])
	var w := h * aspect
	var side := Vector3(cos(yaw), 0.0, sin(yaw))
	var out := Vector3(-sin(yaw), 0.0, cos(yaw))
	var up := (Vector3.UP * cos(tilt) + out * sin(tilt)).normalized()
	var o := Vector2(float(cell % 2), float(cell / 2)) * 0.5
	var u0: float = o.x + cr[0] * 0.5
	var u1: float = o.x + cr[2] * 0.5
	var v0: float = o.y + cr[1] * 0.5
	var v1: float = o.y + cr[3] * 0.5
	if flip:
		var tmp := u0
		u0 = u1
		u1 = tmp
	var bl := at - side * w * 0.5
	var br := at + side * w * 0.5
	var nb := (Vector3.UP * 0.6 + out * 0.4 - side * 0.3).normalized()
	var nb2 := (Vector3.UP * 0.6 + out * 0.4 + side * 0.3).normalized()
	var nt := (Vector3.UP + out * 0.3).normalized()
	b.quad("garden", m, [bl, br, br + up * h, bl + up * h], [nb, nb2, nt, nt],
		[Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)])


## Mata de jardín (3-5 tarjetas cruzadas) de un tipo de celda, en `at`.
static func _clump(b: _B, m: Material, r: RandomNumberGenerator, at: Vector3, cell: int, h: float) -> void:
	var n := 3 if cell == 2 else 4
	var y0 := r.randf() * PI
	for i in n:
		var yaw := y0 + PI * i / n + r.randf_range(-0.2, 0.2)
		var off := Vector3(r.randf_range(-0.08, 0.08), 0.0, r.randf_range(-0.08, 0.08)) * h
		_garden_card(b, m, at + off - Vector3(0, 0.03, 0), yaw, h * r.randf_range(0.85, 1.1), cell,
			r.randf_range(0.05, 0.3) * (1.0 if i % 2 == 0 else -1.0), r.randf() < 0.5)


static func _clump_h(cell: int) -> float:
	match cell:
		0: return 0.85
		1: return 0.5
		2: return 1.25
	return 0.5


# ================================================================== modelos públicos
## Palma alta (palma real / areca de andén, ref. 3 y 7): tronco anillado curvo, capitel verde,
## 10-12 frondas arqueadas de 6 segmentos y racimos de frutos. ~900 triángulos.
static func tall_palm(variant: int) -> ArrayMesh:
	var key := "tall_palm_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var H: float = [8.5, 11.0, 6.8][variant % 3]
	var bend: float = [0.07, 0.12, 0.035][variant % 3]
	var r0: float = [0.15, 0.13, 0.19][variant % 3]
	var b := _B.new()
	var trunk_m := MatGround.palma(r0, H, Color(0.78, 0.74, 0.67))
	var pts: Array = []
	var rad: Array = []
	var rings := 14
	for i in rings + 1:
		var t := float(i) / rings
		var wob := Vector3(sin(t * 5.0 + variant) * 0.03, 0, cos(t * 4.0 + variant) * 0.03) * t
		pts.append(Vector3(bend * H * t * t, H * t, 0.0) + wob)
		rad.append(r0 * (1.0 + 0.45 * exp(-t * 30.0)) * lerpf(1.0, 0.82, t))
	pts[0] = pts[0] - Vector3(0, 0.08, 0)
	_tube(b, "trunk", trunk_m, pts, rad, 9, 1.0 / (2.0 * H))
	# Capitel liso (más grueso en medio).
	var top: Vector3 = pts[rings]
	var ax: Vector3 = (pts[rings] - pts[rings - 1]).normalized()
	var cs_len: float = [1.1, 1.3, 0.6][variant % 3]
	var cr := float(rad[rings])
	var cpts := [top - ax * 0.05, top + ax * cs_len * 0.35, top + ax * cs_len * 0.8, top + ax * cs_len]
	var crad := [cr * 1.05, cr * 1.35, cr * 1.2, cr * 0.75]
	b.color = Color(0.33, 0.42, 0.2)
	_tube(b, "crown", _crown_mat(), cpts, crad, 8, 1.0, true)
	var crown: Vector3 = top + ax * cs_len
	# Frondas.
	var frond_m := MatFoliage.palm_frond(Color(0.86, 0.86, 0.72) if variant == 2 else Color(0.8, 0.86, 0.76))
	var nf := 12 + (variant % 2) * 2
	var ga := 2.39996
	for i in nf:
		var age := float(i) / nf        # 0 = joven (arriba), 1 = vieja (abajo)
		var az := i * ga + r.randf_range(-0.2, 0.2)
		var elev := lerpf(1.15, -0.05, age) + r.randf_range(-0.12, 0.12)
		var L := r.randf_range(3.0, 3.8) * (1.15 if variant == 2 else 1.0) * lerpf(0.8, 1.0, age)
		var droop := lerpf(0.8, 1.9, age) * (1.15 if variant == 2 else 1.0)
		var at: Vector3 = crown - ax * lerpf(0.0, 0.25, age) + Vector3(cos(az), 0, sin(az)) * cr * 0.6
		_frond(b, frond_m, at, az, elev, L, droop, 0.32, r.randf_range(-0.5, 0.5))
	# Flecha (hoja nueva enrollada) que sale recta del centro.
	_tube(b, "crown", _crown_mat(), [crown, crown + ax * 0.9 + Vector3(0.05, 0, 0)], [cr * 0.35, 0.01], 5, 1.0)
	# Racimos de frutos colgando bajo el capitel.
	var sm := _crown_mat()
	b.color = Color(0.55, 0.38, 0.14)
	for k in 2:
		var az2 := r.randf() * TAU
		var dir := Vector3(cos(az2), 0, sin(az2))
		var base: Vector3 = top - ax * 0.05 + dir * cr * 1.1
		for j in 9:
			var q: Vector3 = base + dir * r.randf_range(0.05, 0.3) + Vector3(r.randf_range(-0.12, 0.12), -r.randf_range(0.1, 0.55), r.randf_range(-0.12, 0.12))
			_octa(b, sm, q, r.randf_range(0.04, 0.06))
	var mesh := b.commit()
	_cache[key] = mesh
	_info[key] = {"height": H + cs_len, "radius": r0}
	return mesh


## Altura aproximada del capitel de una palma alta (para colisión/cálculos).
static func tall_palm_height(variant: int) -> float:
	tall_palm(variant)
	return _info["tall_palm_%d" % variant].height


static func _octa(b: _B, m: Material, c: Vector3, s: float) -> void:
	var v := [Vector3(s, 0, 0), Vector3(0, 0, s), Vector3(-s, 0, 0), Vector3(0, 0, -s)]
	for i in 4:
		var a: Vector3 = v[i]
		var bb: Vector3 = v[(i + 1) % 4]
		for yy in [s * 1.3, -s * 1.3]:
			var tip := Vector3(0, yy, 0)
			var n := (a + bb + tip).normalized()
			b.tri("crown", m, [c + a, c + bb, c + tip], [n, n, n], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE])


## Palma pequeña de jardín (areca en macolla, 1.2-2.6 m): 3-5 tallos finos con 5-6 frondas cada uno.
static func small_palm(variant: int) -> ArrayMesh:
	var key := "small_palm_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var b := _B.new()
	var stem_m := MatGround.palma(0.05, 2.0, Color(0.85, 0.95, 0.75))
	var frond_m := MatFoliage.palm_frond()
	var ns := 3 + variant * 2
	for s in ns:
		var az := TAU * s / ns + r.randf_range(-0.3, 0.3)
		var lean := r.randf_range(0.05, 0.22)
		var h := r.randf_range(1.0, 2.2) * (0.8 if variant == 0 else 1.0)
		var dir := Vector3(cos(az) * lean, 1.0, sin(az) * lean).normalized()
		var p0 := Vector3(cos(az), 0, sin(az)) * 0.08 - Vector3(0, 0.05, 0)
		var pts := [p0, p0 + dir * h * 0.5, p0 + dir * h + Vector3(cos(az), 0, sin(az)) * 0.05 * h]
		_tube(b, "stem", stem_m, pts, [0.045, 0.038, 0.03], 5, 1.0 / 4.0)
		var tip: Vector3 = pts[2]
		var nf := 5 + r.randi_range(0, 1)
		for i in nf:
			var faz := az + TAU * i / nf + r.randf_range(-0.3, 0.3)
			var age := float(i) / nf
			_frond(b, frond_m, tip, faz, lerpf(1.1, 0.35, age) + r.randf_range(-0.1, 0.1),
				r.randf_range(1.0, 1.5) * (0.85 + h * 0.08), lerpf(0.6, 1.2, age), 0.25, r.randf_range(-0.4, 0.4), 4)
	var mesh := b.commit()
	_cache[key] = mesh
	return mesh


## Mata de jardín individual: 0 crotón, 1 helecho, 2 heliconia, 3 hoja morada, 4 mezcla crotón+morada.
static func garden_clump(variant: int) -> ArrayMesh:
	var key := "clump_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var b := _B.new()
	var m := MatFoliage.garden_plants()
	if variant < 4:
		_clump(b, m, r, Vector3.ZERO, variant, _clump_h(variant))
	else:
		_clump(b, m, r, Vector3(-0.2, 0, 0), 0, 0.8)
		_clump(b, m, r, Vector3(0.35, 0, 0.15), 3, 0.45)
	var mesh := b.commit()
	_cache[key] = mesh
	return mesh


## Macizo de jardín (ref. 1, 3 y 7): base de mantillo w × d con matas mezcladas (densidad ~2/m²).
## mix: 0 tropical (helecho + heliconia + crotón), 1 colorido (crotón + morada), 2 helechos.
## Origen en el centro de la base.
static func garden_bed(w: float, d: float, mix: int, variant: int = 0) -> ArrayMesh:
	var key := "bed_%.1f_%.1f_%d_%d" % [w, d, mix, variant]
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var b := _B.new()
	var m := MatFoliage.garden_plants()
	_soil(b, w, d, 0.04)
	var cells: Array = [[1, 2, 0, 1, 3], [0, 3, 0, 3, 1], [1, 1, 1, 2, 3]][mix % 3]
	var step := 0.75
	var nx := maxi(1, int(w / step))
	var nz := maxi(1, int(d / step))
	for i in nx:
		for j in nz:
			var p := Vector3(-w * 0.5 + (i + 0.5) * w / nx + r.randf_range(-0.2, 0.2), 0.0,
				-d * 0.5 + (j + 0.5) * d / nz + r.randf_range(-0.2, 0.2))
			var cell: int = cells[r.randi() % cells.size()]
			# Las altas (heliconia) hacia el centro, las bajas al borde.
			var edge := minf(w * 0.5 - absf(p.x), d * 0.5 - absf(p.z))
			if cell == 2 and edge < 0.6:
				cell = 1
			_clump(b, m, r, p, cell, _clump_h(cell) * r.randf_range(0.8, 1.15))
	var mesh := b.commit()
	_cache[key] = mesh
	return mesh


## Base de mantillo levemente abombada (montículo) de w × d.
static func _soil(b: _B, w: float, d: float, hmax: float) -> void:
	var sm := MatGround.mantillo()
	var nx := maxi(2, int(ceil(w / 0.6)))
	var nz := maxi(2, int(ceil(d / 0.6)))
	var P := func(i: int, j: int) -> Vector3:
		var x := -w * 0.5 + w * i / nx
		var z := -d * 0.5 + d * j / nz
		var e := minf(minf(i, nx - i) / float(nx), minf(j, nz - j) / float(nz)) * 2.0
		return Vector3(x, -0.01 + hmax * smoothstep(0.0, 0.5, e), z)
	for i in nx:
		for j in nz:
			var a: Vector3 = P.call(i, j)
			var bb: Vector3 = P.call(i + 1, j)
			var c: Vector3 = P.call(i + 1, j + 1)
			var dd: Vector3 = P.call(i, j + 1)
			var n := (c - a).cross(bb - dd).normalized()
			if n.y < 0:
				n = -n
			b.quad("soil", sm, [a, bb, c, dd], [n, n, n, n],
				[Vector2(a.x, a.z), Vector2(bb.x, bb.z), Vector2(c.x, c.z), Vector2(dd.x, dd.z)])


## Tramo de seto recortado de HEDGE_SEG m (eje X, centrado en x = 0): sección con aristas redondeadas,
## superficie con ondulación suave y algunas ramitas (tarjetas) sobresaliendo por arriba.
## Para filas largas repítelo cada HEDGE_SEG m (los extremos se solapan 5 cm).
static func hedge(variant: int, width: float = 0.7, height: float = 0.9) -> ArrayMesh:
	var key := "hedge_%d_%.2f_%.2f" % [variant, width, height]
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var b := _B.new()
	var tint: Color = [Color.WHITE, Color(0.95, 1.05, 0.8), Color(0.8, 0.9, 0.8)][variant % 3]
	var hm := MatFoliage.hedge(tint)
	var W := width * 0.5
	var R := minf(0.2, W * 0.6)
	# Perfil (y, z) de izquierda-abajo a derecha-abajo, con normales.
	var prof: Array = []
	prof.append([Vector2(-W * 0.96, -0.05), Vector2(-1, -0.2)])
	prof.append([Vector2(-W, height * 0.45), Vector2(-1, 0)])
	prof.append([Vector2(-W, height - R), Vector2(-1, 0)])
	for k in range(1, 3):
		var a := PI - PI * 0.5 * k / 3.0
		prof.append([Vector2(-W + R + cos(a) * R, height - R + sin(a) * R), Vector2(cos(a), sin(a))])
	prof.append([Vector2(-W + R, height), Vector2(0, 1)])
	prof.append([Vector2(0, height + 0.02), Vector2(0, 1)])
	prof.append([Vector2(W - R, height), Vector2(0, 1)])
	for k in range(1, 3):
		var a := PI * 0.5 - PI * 0.5 * k / 3.0
		prof.append([Vector2(W - R + cos(a) * R, height - R + sin(a) * R), Vector2(cos(a), sin(a))])
	prof.append([Vector2(W, height - R), Vector2(1, 0)])
	prof.append([Vector2(W, height * 0.45), Vector2(1, 0)])
	prof.append([Vector2(W * 0.96, -0.05), Vector2(1, -0.2)])
	var L := HEDGE_SEG * 0.5 + 0.05
	var segs := 8
	var sd := float(variant) * 3.7
	var grid: Array = []
	for i in segs + 1:
		var x := -L + 2.0 * L * i / segs
		var row: Array = []
		for pr in prof:
			var pz: Vector2 = pr[0]
			var nn: Vector2 = pr[1].normalized()
			var n3 := Vector3(0, nn.y, nn.x)
			# Desplazamiento a lo largo de la normal (sin mover los extremos para que empalmen).
			var disp := 0.035 * _noise(x * 1.3, pz.x * 2.0 + pz.y * 2.0, sd) if pz.y > 0.05 else 0.0
			row.append([Vector3(x, pz.y, pz.x) + n3 * disp, n3])
		grid.append(row)
	for i in segs:
		for j in prof.size() - 1:
			var a: Array = grid[i][j]
			var bb: Array = grid[i + 1][j]
			var c: Array = grid[i + 1][j + 1]
			var dd: Array = grid[i][j + 1]
			b.quad("hedge", hm, [a[0], bb[0], c[0], dd[0]], [a[1], bb[1], c[1], dd[1]],
				[Vector2(a[0].x, a[0].y), Vector2(bb[0].x, bb[0].y), Vector2(c[0].x, c[0].y), Vector2(dd[0].x, dd[0].y)])
	# Tapas (abanico) en ambos extremos: quedan ocultas al empalmar tramos, visibles al final de la fila.
	for e in [0, segs]:
		var row: Array = grid[e]
		var cen := Vector3(row[0][0].x, height * 0.45, 0)
		var n := Vector3(-1 if e == 0 else 1, 0, 0)
		for j in prof.size() - 1:
			b.tri("hedge", hm, [cen, row[j][0], row[j + 1][0]], [n, n, n], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE])
	# Ramitas sueltas (tarjetas de hoja oscura) sobresaliendo de la tapa.
	var cm := MatFoliage.canopy_cards(Color(0.75, 0.9, 0.6) * Color(tint.r, tint.g, tint.b))
	var cell := MatFoliage.cell_uv(3)
	for k in 9:
		var p := Vector3(r.randf_range(-L + 0.2, L - 0.2), height - 0.22, r.randf_range(-W * 0.8, W * 0.8))
		var yaw := r.randf() * PI
		var s := r.randf_range(0.45, 0.6)
		var side := Vector3(cos(yaw), 0, sin(yaw)) * s * 0.5
		var up := Vector3(r.randf_range(-0.2, 0.2), 1, r.randf_range(-0.2, 0.2)).normalized() * s
		var n := Vector3.UP
		b.quad("sprig", cm, [p - side, p + side, p + side + up, p - side + up], [n, n, n, n],
			[cell.position + Vector2(0, cell.size.y), cell.end, cell.position + Vector2(cell.size.x, 0), cell.position])
	var mesh := b.commit()
	_cache[key] = mesh
	return mesh


## Parche de hiedra rastrera (ref. 6) de w × d: montículo de 10-16 cm con borde irregular y hojitas
## (tarjetas) que desbordan el contorno. Origen en el centro, y = 0 = suelo.
static func ivy_patch(w: float, d: float, variant: int = 0) -> ArrayMesh:
	var key := "ivy_%.1f_%.1f_%d" % [w, d, variant]
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var b := _B.new()
	var im := MatFoliage.ivy_ground()
	var nx := maxi(3, int(ceil(w / 0.4)))
	var nz := maxi(3, int(ceil(d / 0.4)))
	var sd := float(variant) * 2.3 + w
	var H := func(x: float, z: float) -> float:
		var e := minf(w * 0.5 - absf(x), d * 0.5 - absf(z))
		var f := smoothstep(0.0, 0.35, e)
		return -0.03 + f * (0.17 + 0.07 * _noise(x * 1.5, z * 1.5, sd))
	var P := func(i: int, j: int) -> Vector3:
		var x := -w * 0.5 + w * i / nx
		var z := -d * 0.5 + d * j / nz
		# Contorno irregular: los vértices del borde se meten hacia dentro.
		if i == 0 or i == nx:
			x -= signf(x) * (0.06 + 0.06 * _noise(z * 3.0, 0.0, sd))
		if j == 0 or j == nz:
			z -= signf(z) * (0.06 + 0.06 * _noise(x * 3.0, 1.0, sd))
		return Vector3(x, H.call(x, z), z)
	var N := func(p: Vector3) -> Vector3:
		var e := 0.08
		var hx: float = H.call(p.x + e, p.z) - H.call(p.x - e, p.z)
		var hz: float = H.call(p.x, p.z + e) - H.call(p.x, p.z - e)
		return Vector3(-hx, 2.0 * e, -hz).normalized()
	for i in nx:
		for j in nz:
			var a: Vector3 = P.call(i, j)
			var bb: Vector3 = P.call(i + 1, j)
			var c: Vector3 = P.call(i + 1, j + 1)
			var dd: Vector3 = P.call(i, j + 1)
			b.quad("ivy", im, [a, bb, c, dd], [N.call(a), N.call(bb), N.call(c), N.call(dd)],
				[Vector2(a.x, a.z), Vector2(bb.x, bb.z), Vector2(c.x, c.z), Vector2(dd.x, dd.z)])
	# Hojas que desbordan el contorno (tarjetas bajas inclinadas hacia fuera).
	var cm := MatFoliage.canopy_cards(Color(0.5, 0.64, 0.4))
	var cell := MatFoliage.cell_uv(3)
	var per := 2.0 * (w + d)
	var n_cards := int(per / 0.3)
	for k in n_cards:
		var t := (float(k) + r.randf()) / n_cards * per
		var p: Vector3
		var out: Vector3
		if t < w:
			p = Vector3(-w * 0.5 + t, 0, -d * 0.5); out = Vector3.FORWARD
		elif t < w + d:
			p = Vector3(w * 0.5, 0, -d * 0.5 + t - w); out = Vector3.RIGHT
		elif t < 2.0 * w + d:
			p = Vector3(w * 0.5 - (t - w - d), 0, d * 0.5); out = Vector3.BACK
		else:
			p = Vector3(-w * 0.5, 0, d * 0.5 - (t - 2.0 * w - d)); out = Vector3.LEFT
		p += -out * 0.32
		var s := r.randf_range(0.45, 0.6)
		var side := out.cross(Vector3.UP).rotated(Vector3.UP, r.randf_range(-0.4, 0.4)) * s * 0.5
		var dir := (out * 0.97 - Vector3.UP * 0.2).normalized() * s
		var n := (Vector3.UP + out * 0.3).normalized()
		p.y = 0.13
		b.quad("fringe", cm, [p - side, p + side, p + side + dir, p - side + dir], [n, n, n, n],
			[cell.position + Vector2(0, cell.size.y), cell.end, cell.position + Vector2(cell.size.x, 0), cell.position])
	# Hojas sueltas sobre la superficie (rompen lo plano del montículo).
	for k in int(w * d * 1.5):
		var x := r.randf_range(-w * 0.5 + 0.3, w * 0.5 - 0.3)
		var z := r.randf_range(-d * 0.5 + 0.3, d * 0.5 - 0.3)
		var p := Vector3(x, float(H.call(x, z)) - 0.04, z)
		var yaw := r.randf() * TAU
		var fwd := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-sin(yaw), 0, cos(yaw)) * 0.22
		var dir := (fwd * 0.85 + Vector3.UP * 0.5).normalized() * 0.42
		var n := Vector3.UP
		b.quad("fringe", cm, [p - side, p + side, p + side + dir, p - side + dir], [n, n, n, n],
			[cell.position + Vector2(0, cell.size.y), cell.end, cell.position + Vector2(cell.size.x, 0), cell.position])
	var mesh := b.commit()
	_cache[key] = mesh
	return mesh


## Mata de pasto alto / ornamental (0.4-0.8 m): ~26 hojas arqueadas con color por vértice.
static func grass_tuft(variant: int) -> ArrayMesh:
	var key := "grass_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var b := _B.new()
	var gm := _grass_mat()
	var base_c := Color(0.1, 0.17, 0.05)
	var mid_c := Color(0.25, 0.36, 0.1)
	var tip_c: Color = [Color(0.55, 0.58, 0.26), Color(0.4, 0.5, 0.18)][variant % 2]
	for k in 26:
		var az := r.randf() * TAU
		var dir := Vector3(cos(az), 0, sin(az))
		var side := Vector3(-sin(az), 0, cos(az))
		var h := r.randf_range(0.4, 0.8) * (1.0 if variant == 0 else 0.75)
		var out := r.randf_range(0.1, 0.5) * h
		var p0 := dir * r.randf_range(0.0, 0.1) - Vector3(0, 0.02, 0)
		var p1 := p0 + dir * out * 0.35 + Vector3(0, h * 0.55, 0)
		var p2 := p0 + dir * out + Vector3(0, h, 0) - Vector3(0, out * 0.4, 0)
		var w0 := 0.025
		var n := (Vector3.UP + dir * 0.5).normalized()
		b.quad("grass", gm, [p0 - side * w0, p0 + side * w0, p1 + side * w0 * 0.7, p1 - side * w0 * 0.7],
			[n, n, n, n], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0.5), Vector2(0, 0.5)],
			[base_c, base_c, mid_c, mid_c])
		b.tri("grass", gm, [p1 - side * w0 * 0.7, p1 + side * w0 * 0.7, p2], [n, n, n],
			[Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 0)], [mid_c, mid_c, tip_c])
	var mesh := b.commit()
	_cache[key] = mesh
	return mesh


## Agave (ref. 7): roseta de 14-18 hojas carnosas en V con punta fina.
static func agave(variant: int) -> ArrayMesh:
	var key := "agave_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var b := _B.new()
	var am := _agave_mat()
	var body := Color(0.36, 0.5, 0.45) if variant == 0 else Color(0.42, 0.52, 0.32)
	var edge := Color(0.62, 0.62, 0.3) if variant == 0 else Color(0.7, 0.66, 0.28)
	var nl := 14 + variant * 4
	for k in nl:
		var az := k * 2.39996
		var age := float(k) / nl
		var dir := Vector3(cos(az), 0, sin(az))
		var side := Vector3(-sin(az), 0, cos(az))
		var elev := lerpf(1.25, 0.35, age) + r.randf_range(-0.1, 0.1)
		var L := lerpf(0.55, 0.95, age) * (1.0 if variant == 0 else 0.8)
		var wb := 0.09
		var segs := 3
		var p := Vector3(0, 0.03, 0) + dir * 0.03
		var prev: Array = []
		for i in segs + 1:
			var t := float(i) / segs
			var th := elev - 0.35 * t * t * (1.0 - age * 0.5)
			var d := (dir * cos(th) + Vector3.UP * sin(th)).normalized()
			var n := side.cross(d).normalized()
			if n.y < 0:
				n = -n
			var ww := wb * (1.0 - t) * (1.0 if t < 0.99 else 0.0) + 0.004
			var row := [p - side * ww + n * ww * 0.5, p, p + side * ww + n * ww * 0.5, n]
			if i > 0:
				var nA: Vector3 = prev[3]
				var nB: Vector3 = row[3]
				b.quad("agave", am, [prev[0], prev[1], row[1], row[0]], [nA, nA, nB, nB],
					[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], [edge, body, body, edge])
				b.quad("agave", am, [prev[1], prev[2], row[2], row[1]], [nA, nA, nB, nB],
					[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], [body, edge, edge, body])
			prev = row
			p += d * (L / segs)
	var mesh := b.commit()
	_cache[key] = mesh
	return mesh


## Alcorque de andén (1.2 × 1.2 m, ref. 1): marco de sardinel de 10 cm, mantillo y plantas bajas
## alrededor del hueco central (r 0.35) donde va el tronco. Origen = centro a nivel del andén.
static func tree_pit(variant: int) -> ArrayMesh:
	var key := "pit_%d" % variant
	if _cache.has(key):
		return _cache[key]
	var r := _rng(key, variant)
	var b := _B.new()
	var cm := MatPaving.curb_dry()
	var S := 0.6
	var t := 0.1
	var hgt := 0.1
	# Marco: 4 piezas con bisel superior exterior.
	for k in 4:
		var rot := Basis(Vector3.UP, PI * 0.5 * k)
		var x0 := -S
		var x1 := S - t
		var z0 := -S
		var z1 := -S + t
		var c := 0.02
		var pts := [Vector3(x0, -0.02, z0), Vector3(x0, hgt - c, z0), Vector3(x0, hgt, z0 + c), Vector3(x0, hgt, z1),
			Vector3(x0, -0.02, z1)]
		var pts2: Array = []
		for p in pts:
			pts2.append(Vector3(x1, p.y, p.z))
		var ns := [Vector3(0, 0, -1), Vector3(0, 0.7, -0.7).normalized(), Vector3.UP, Vector3(0, 0, 1)]
		for i in 4:
			var n: Vector3 = rot * ns[i]
			b.quad("curb", cm, [rot * pts[i], rot * pts2[i], rot * pts2[i + 1], rot * pts[i + 1]], [n, n, n, n],
				[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	# Mantillo dentro del marco.
	var sm := MatGround.mantillo()
	var inner := S - t
	var n := Vector3.UP
	b.quad("soil", sm, [Vector3(-inner, 0.03, -inner), Vector3(inner, 0.03, -inner), Vector3(inner, 0.03, inner),
		Vector3(-inner, 0.03, inner)], [n, n, n, n], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	# Plantas bajas en las esquinas.
	var gm := MatFoliage.garden_plants()
	var cells: Array = [[1, 3, 1], [0, 1, 3], [1, 1, 0]][variant % 3]
	var nplants := 3 + variant % 2
	for k in nplants:
		var a := TAU * k / nplants + r.randf_range(-0.3, 0.3) + PI * 0.25
		var p := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.38, 0.48) * 1.2
		p.x = clampf(p.x, -inner + 0.1, inner - 0.1)
		p.z = clampf(p.z, -inner + 0.1, inner - 0.1)
		var cell: int = cells[k % cells.size()]
		_clump(b, gm, r, p + Vector3(0, 0.03, 0), cell, _clump_h(cell) * 0.7)
	var mesh := b.commit()
	_cache[key] = mesh
	return mesh

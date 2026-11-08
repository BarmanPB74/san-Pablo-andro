class_name Trees
extends RefCounted
## Árboles grandes del parque y de los andenes (Fase 2, agente F2-01 "trees").
## Todo procedural: tronco y ramas como tubos generalizados (UV continuas, torsión, curvatura,
## contrafuertes en la base), collar de musgo con borde irregular, raíces superficiales y copa de
## tarjetas cruzadas del atlas MatFoliage con normales "esféricas" (gradiente de un elipsoide que
## envuelve la copa) para que la luz sea suave y no se noten los planos.
##
## Uso:  var m := Trees.mesh(Trees.SAMAN, semilla)   # semilla 0..VARIANTS-1, ArrayMesh cacheada
##       Trees.trunk_radius(kind) → radio del tronco a 1.3 m (para colisión), en metros a escala 1.
##       Trees.height(kind) → altura nominal a escala 1.
## Superficies: 0 corteza (MatGround), 1 musgo (MatGround.musgo, triplanar), 2 copa (shader propio).
## Las UV de corteza están en unidades de tile (U entero alrededor del tronco → sin costura),
## por eso se pide el material con parámetros que dan uv_scale = (1,1,1).

const SAMAN := 0
const ANDEN := 1
const GUAYACAN_AMARILLO := 2
const GUAYACAN_ROSADO := 3
const VARIANTS := 3

static var _meshes := {}
static var _leaf_mats := {}
static var _shader: Shader

## Parámetros por especie. Longitudes en metros (escala 1).
const SPECIES := {
	SAMAN: {
		"fork_h": [3.6, 4.4], "r_base": 0.40, "r_top": 0.31, "flare": 0.55, "lobes": 5, "lobe_amp": 0.32,
		"lean": 0.35, "twist": 0.12, "bark": "tropical", "tint": Color(0.92, 0.92, 0.88),
		"L": [ # por nivel: hijos, apertura (grados), largo, r0 (fracción del radio padre), r1, lados, anillos, curvatura, afuera, arriba
			[3, 34.0, 5.2, 0.82, 0.55, 9, 7, 0.16, 0.07, 0.07],
			[2, 34.0, 3.4, 0.85, 0.45, 7, 5, 0.22, 0.22, 0.0],
			[3, 38.0, 2.2, 0.85, 0.25, 5, 4, 0.26, 0.12, 0.22],
		],
		"cells": [0, 1, 2], "card": [2.2, 3.0], "per_tip": 18, "blob": [2.4, 1.1],
		"moss_h": [0.6, 1.3], "roots": 5, "height": 13.0,
	},
	ANDEN: {
		"fork_h": [2.7, 3.1], "r_base": 0.17, "r_top": 0.14, "flare": 0.35, "lobes": 3, "lobe_amp": 0.15,
		"lean": 0.18, "twist": 0.08, "bark": "lisa", "tint": Color(0.5, 0.48, 0.44),
		"L": [
			[3, 28.0, 2.5, 0.80, 0.50, 7, 5, 0.18, 0.08, 0.10],
			[2, 30.0, 1.7, 0.85, 0.45, 5, 4, 0.22, 0.10, 0.10],
			[3, 36.0, 1.0, 0.85, 0.25, 4, 3, 0.25, 0.05, 0.25],
		],
		"cells": [3, 3, 0], "card": [1.4, 1.9], "per_tip": 10, "blob": [1.1, 0.8],
		"moss_h": [0.3, 0.6], "roots": 0, "height": 8.0,
	},
	GUAYACAN_AMARILLO: {
		"fork_h": [3.0, 3.6], "r_base": 0.25, "r_top": 0.2, "flare": 0.45, "lobes": 4, "lobe_amp": 0.22,
		"lean": 0.3, "twist": 0.10, "bark": "tropical", "tint": Color(0.82, 0.8, 0.76),
		"L": [
			[3, 32.0, 3.2, 0.80, 0.50, 8, 6, 0.22, 0.10, 0.14],
			[2, 32.0, 2.3, 0.85, 0.45, 6, 4, 0.26, 0.12, 0.10],
			[3, 36.0, 1.4, 0.85, 0.25, 4, 3, 0.28, 0.05, 0.25],
		],
		"cells": [0, 1, 2], "card": [1.6, 2.3], "per_tip": 10, "blob": [1.4, 0.9],
		"moss_h": [0.4, 0.9], "roots": 4, "height": 10.5,
	},
}


static func _sp(kind: int) -> Dictionary:
	return SPECIES[GUAYACAN_AMARILLO if kind == GUAYACAN_ROSADO else kind]


static func trunk_radius(kind: int) -> float:
	return float(_sp(kind).r_base) * 1.05


static func height(kind: int) -> float:
	return float(_sp(kind).height)


# ------------------------------------------------------------------ geometría auxiliar
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func add(p: Vector3, nn: Vector3, t: Vector2, col := Color.WHITE) -> int:
		v.append(p)
		n.append(nn)
		uv.append(t)
		c.append(col)
		return v.size() - 1

	## Triángulo con cara frontal hacia la normal de vértice (Godot: frente = horario).
	func tri(a: int, b: int, cc: int) -> void:
		var gn := (v[b] - v[a]).cross(v[cc] - v[a])
		if gn.dot(n[a] + n[b] + n[cc]) > 0.0:
			idx.append_array([a, cc, b])
		else:
			idx.append_array([a, b, cc])

	func tris() -> int:
		return idx.size() / 3


static func _perp(t: Vector3) -> Vector3:
	var ref := Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD
	return (ref - t * t.dot(ref)).normalized()


## Factor de radio por ángulo: contrafuertes que se desvanecen con la altura + nudosidad.
static func _lobe(lb: Dictionary, h: float, a: float) -> float:
	if lb.is_empty():
		return 1.0
	var amp: float = lb.amp * exp(-h / float(lb.decay))
	var c := maxf(0.0, cos(float(lb.n) * a + float(lb.ph)))
	return 1.0 + amp * c * c + float(lb.knot) * sin(3.0 * a + h * 1.9 + float(lb.ph)) * 0.5


## Tubo generalizado con marco de transporte paralelo. U entero alrededor (sin costura), V = metros/tile.
static func _tube(g: Geo, pts: PackedVector3Array, rad: PackedFloat32Array, segs: int, tile: float,
		twist: float, lb: Dictionary, close_tip: bool) -> void:
	var m := pts.size()
	var tans: Array[Vector3] = []
	for i in m:
		tans.append((pts[mini(i + 1, m - 1)] - pts[maxi(i - 1, 0)]).normalized())
	var nrm := _perp(tans[0])
	var ureps := maxf(1.0, roundf(TAU * rad[0] / tile))
	var vacc := 0.0
	var start := g.v.size()
	for i in m:
		if i > 0:
			var ax := tans[i - 1].cross(tans[i])
			if ax.length() > 1e-5:
				nrm = nrm.rotated(ax.normalized(), tans[i - 1].angle_to(tans[i]))
			nrm = (nrm - tans[i] * tans[i].dot(nrm)).normalized()
			vacc += pts[i].distance_to(pts[i - 1])
		var bin := tans[i].cross(nrm)
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, m - 1)
		var dr := (rad[i1] - rad[i0]) / maxf(pts[i1].distance_to(pts[i0]), 0.001)
		var r := rad[i]
		if close_tip and i == m - 1:
			r = 0.0
		for j in segs + 1:
			var a := TAU * float(j) / float(segs) + twist * vacc
			var d := nrm * cos(a) + bin * sin(a)
			var nn := (d - tans[i] * dr).normalized()
			g.add(pts[i] + d * r * _lobe(lb, vacc, a), nn, Vector2(ureps * float(j) / float(segs), -vacc / tile))
	for i in m - 1:
		for j in segs:
			var a0 := start + i * (segs + 1) + j
			var b0 := a0 + segs + 1
			g.tri(a0, a0 + 1, b0)
			g.tri(a0 + 1, b0 + 1, b0)


static func _bark_mat(sp: Dictionary) -> Material:
	# Parámetros elegidos para que uv_scale = (1,1,1): las UV del mesh ya van en tiles.
	if sp.bark == "tropical":
		return MatGround.corteza_tropical(0.3, 1.0, sp.tint)
	return MatGround.corteza_lisa(0.15, 0.5, sp.tint)


static func _bark_tile(sp: Dictionary) -> float:
	return 2.0 if sp.bark == "tropical" else 1.0


# ------------------------------------------------------------------ construcción
static func mesh(kind: int, seed: int) -> ArrayMesh:
	seed = posmod(seed, VARIANTS)
	var key := "%d_%d" % [kind, seed]
	if _meshes.has(key):
		return _meshes[key]
	var sp := _sp(kind)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (kind + 1) + 104729 * (seed + 1)
	var bark := Geo.new()
	var moss := Geo.new()
	var leaves := Geo.new()
	var tile := _bark_tile(sp)

	# --- tronco: eje analítico con inclinación y ondulación suave
	var fork_h := rng.randf_range(sp.fork_h[0], sp.fork_h[1])
	var lean_a := rng.randf() * TAU
	var lean_dir := Vector3(cos(lean_a), 0, sin(lean_a))
	var lean: float = sp.lean * rng.randf_range(0.5, 1.2)
	var wob_ph := rng.randf() * TAU
	var lb := {"n": sp.lobes, "amp": sp.lobe_amp, "decay": 0.55, "ph": rng.randf() * TAU, "knot": 0.05}
	var r_base: float = sp.r_base * rng.randf_range(0.9, 1.1)
	var r_top: float = sp.r_top * r_base / float(sp.r_base)
	var twist: float = sp.twist * (1.0 if rng.randf() < 0.5 else -1.0)
	var rings := 11
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	for i in rings + 1:
		var h := -0.15 + (fork_h + 0.15) * pow(float(i) / rings, 1.25)
		var t := maxf(h, 0.0) / fork_h
		var off := lean_dir * lean * t * t + Vector3(sin(h * 0.9 + wob_ph), 0, cos(h * 0.7 + wob_ph)) * 0.04 * t
		pts.append(Vector3(0, h, 0) + off)
		rad.append(lerpf(r_base, r_top, t) * (1.0 + float(sp.flare) * exp(-maxf(h, 0.0) / 0.45)))
	_tube(bark, pts, rad, 12, tile, twist, lb, false)
	var trunk_end := pts[rings]
	var trunk_dir := (pts[rings] - pts[rings - 2]).normalized()

	# --- collar de musgo (borde superior irregular) siguiendo el mismo eje/lóbulos
	var mh: Array = sp.moss_h
	var cseg := 14
	var hk := PackedFloat32Array()
	for j in cseg + 1:
		hk.append(rng.randf_range(mh[0], mh[1]) if j < cseg else hk[0])
	var cstart := moss.v.size()
	var nrm0 := _perp((pts[1] - pts[0]).normalized())
	var bin0 := (pts[1] - pts[0]).normalized().cross(nrm0)
	for k in 4:
		for j in cseg + 1:
			var htop := hk[j]
			var h := -0.12 + (htop + 0.12) * float(k) / 3.0
			var t := maxf(h, 0.0) / fork_h
			var cen := Vector3(0, h, 0) + lean_dir * lean * t * t + Vector3(sin(h * 0.9 + wob_ph), 0, cos(h * 0.7 + wob_ph)) * 0.04 * t
			var a := TAU * float(j) / cseg + twist * (h + 0.15)
			var d := nrm0 * cos(a) + bin0 * sin(a)
			var r := lerpf(r_base, r_top, t) * (1.0 + float(sp.flare) * exp(-maxf(h, 0.0) / 0.45)) * _lobe(lb, h + 0.15, a)
			var thick := 0.035 * (1.0 - 0.7 * float(k) / 3.0)
			moss.add(cen + d * (r + thick), (d + Vector3.UP * 0.15).normalized(), Vector2.ZERO)
	for k in 3:
		for j in cseg:
			var a0 := cstart + k * (cseg + 1) + j
			moss.tri(a0, a0 + 1, a0 + cseg + 1)
			moss.tri(a0 + 1, a0 + cseg + 2, a0 + cseg + 1)

	# --- raíces superficiales (contrafuertes que se meten al suelo)
	var nroots: int = sp.roots
	for k in nroots:
		var a: float = -float(lb.ph) / float(sp.lobes) + TAU * float(k) / float(maxi(nroots, 1)) + rng.randf_range(-0.25, 0.25)
		var dh := Vector3(cos(a), 0, sin(a))
		var rp := PackedVector3Array()
		var rr := PackedFloat32Array()
		var length := rng.randf_range(1.0, 1.8) * r_base / 0.4
		for q in 6:
			var u := float(q) / 5.0
			var side := dh.cross(Vector3.UP) * sin(u * 3.0 + a) * 0.12 * u
			rp.append(dh * (r_base * 0.45 + length * u) + side + Vector3(0, 0.34 * pow(1.0 - u, 1.4) - 0.12 * u, 0))
			rr.append(lerpf(r_base * 0.55, r_base * 0.16, pow(u, 0.7)))
		_tube(bark, rp, rr, 6, tile, 0.0, {}, false)

	# --- ramas recursivas
	var tips: Array = []
	_branch_children(bark, sp, rng, trunk_end, trunk_dir, r_top, 0, tips, tile, twist, pts)

	# --- copa
	_canopy(leaves, sp, rng, tips, kind)
	if kind == GUAYACAN_AMARILLO or kind == GUAYACAN_ROSADO:
		_flower_carpet(leaves, rng, sp)

	var am := ArrayMesh.new()
	_commit(am, bark, _bark_mat(sp), true)
	_commit(am, moss, MatGround.musgo(Color(0.95, 1.0, 0.9)), false)
	_commit(am, leaves, _leaf_mat(kind), true)
	am.set_meta("tris", bark.tris() + moss.tris() + leaves.tris())
	_meshes[key] = am
	return am


static func _branch_children(g: Geo, sp: Dictionary, rng: RandomNumberGenerator, p: Vector3, d: Vector3,
		pr: float, level: int, tips: Array, tile: float, twist: float, parent_pts: PackedVector3Array) -> void:
	var L: Array = sp.L[level]
	var k: int = L[0]
	if level == 0 and rng.randf() < 0.3:
		k = 2 if k == 3 else 3
	var phi0 := rng.randf() * TAU
	var e1 := _perp(d)
	var e2 := d.cross(e1)
	for c in k:
		var phi := phi0 + TAU * float(c) / float(k) + rng.randf_range(-0.35, 0.35)
		var side := e1 * cos(phi) + e2 * sin(phi)
		var spread := deg_to_rad(float(L[1]) * rng.randf_range(0.8, 1.25))
		var cd := (d * cos(spread) + side * sin(spread)).normalized()
		# Punto de arranque: en el tronco, algunas ramas salen un poco más abajo.
		var sp0 := p - d * pr * 0.6
		if level == 0 and c > 0 and parent_pts.size() > 3 and rng.randf() < 0.5:
			sp0 = parent_pts[parent_pts.size() - 3]
		var length: float = float(L[2]) * rng.randf_range(0.8, 1.2)
		var nring: int = L[6]
		var r0: float = pr * float(L[3])
		var r1: float = r0 * float(L[4])
		var bp := PackedVector3Array([sp0])
		var br := PackedFloat32Array([r0])
		var dd := cd
		var q := sp0
		var outward := Vector3(cd.x, 0, cd.z).normalized()
		for i in nring:
			var rnd := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			dd = (dd + rnd * float(L[7]) + outward * float(L[8]) + Vector3.UP * float(L[9])).normalized()
			q += dd * length / float(nring)
			bp.append(q)
			var t := float(i + 1) / float(nring)
			br.append(lerpf(r0, r1, t))
		var last: bool = level == (sp.L as Array).size() - 1
		var segs: int = L[5]
		_tube(g, bp, br, segs, tile, twist * 0.5, {}, last)
		if last:
			tips.append([q, dd, bp[nring / 2 + 1]])
		else:
			_branch_children(g, sp, rng, q, dd, r1, level + 1, tips, tile, twist, bp)


static func _canopy(g: Geo, sp: Dictionary, rng: RandomNumberGenerator, tips: Array, kind: int) -> void:
	var cards: Array = []   # [centro, arriba, frente, tamaño, celda, flor]
	var blob: Array = sp.blob
	var csize: Array = sp.card
	var cells: Array = sp.cells
	var flowers := kind == GUAYACAN_AMARILLO or kind == GUAYACAN_ROSADO
	for tp in tips:
		var tip: Vector3 = tp[0]
		var td: Vector3 = tp[1]
		var mid: Vector3 = tp[2]
		var green_cluster := flowers and rng.randf() < 0.18
		for i in int(sp.per_tip):
			var src := tip if i < int(sp.per_tip) - 2 else mid
			var rv := Vector3(rng.randfn(), rng.randfn() * 0.6, rng.randfn()) * float(blob[0]) * 0.55
			var c := src + rv + td * 0.35 + Vector3.UP * float(blob[1]) * 0.4
			var up := (td * 0.5 + Vector3.UP * 0.8 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.6), rng.randf_range(-1, 1)) * 0.5).normalized()
			var f := _perp(up).rotated(up, rng.randf() * TAU)
			var cell: int = cells[rng.randi_range(0, cells.size() - 1)]
			var fl := 0.0
			if flowers:
				fl = 0.0 if green_cluster else rng.randf_range(0.8, 1.0)
			cards.append([c, up, f, rng.randf_range(csize[0], csize[1]), cell, fl])
	if cards.is_empty():
		return
	# Elipsoide que envuelve la copa: centro y semiejes.
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for cd in cards:
		lo = lo.min(cd[0])
		hi = hi.max(cd[0])
	var cen := (lo + hi) * 0.5
	var ext := ((hi - lo) * 0.5).max(Vector3(0.8, 0.8, 0.8)) + Vector3(0.6, 0.6, 0.6)
	cen.y -= ext.y * 0.15   # centro un poco bajo: la parte alta de la copa recibe más luz
	for cd in cards:
		var c: Vector3 = cd[0]
		var up: Vector3 = cd[1]
		var f: Vector3 = cd[2]
		var s: float = cd[3]
		var right := up.cross(f).normalized()
		var rect := MatFoliage.cell_uv(int(cd[4]))
		var flip := rng.randf() < 0.5
		var hue := rng.randf_range(0.88, 1.08)
		var tint := Color(hue * rng.randf_range(0.96, 1.04), hue, hue * rng.randf_range(0.92, 1.02), float(cd[5]))
		var corners := [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]
		var ids: Array[int] = []
		for co in corners:
			var p := c + right * float(co[0]) * s * 0.5 + up * float(co[1]) * s * 0.5
			var rel := (p - cen) / ext
			var grad := Vector3(rel.x / ext.x, rel.y / ext.y, rel.z / ext.z).normalized()
			var nn := (grad + Vector3.UP * 0.3).normalized()
			var dist := clampf(rel.length(), 0.0, 1.2)
			var ao := clampf(0.38 + 0.62 * dist, 0.38, 1.0) * (0.86 + 0.14 * clampf(grad.y * 0.5 + 0.5, 0.0, 1.0))
			var u := (float(co[0]) * 0.5 + 0.5)
			if flip:
				u = 1.0 - u
			var uv := rect.position + Vector2(u, 1.0 - (float(co[1]) * 0.5 + 0.5)) * rect.size
			ids.append(g.add(p, nn, uv, Color(tint.r * ao, tint.g * ao, tint.b * ao, tint.a)))
		# Cara frontal según la normal esférica (el shader des-voltea la cara trasera).
		g.tri(ids[0], ids[1], ids[2])
		g.tri(ids[0], ids[2], ids[3])


## Alfombra de flores caídas bajo los guayacanes (tarjetas horizontales a ras de suelo).
static func _flower_carpet(g: Geo, rng: RandomNumberGenerator, sp: Dictionary) -> void:
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.6, 2.6)
		var c := Vector3(cos(a) * r, 0.05, sin(a) * r)
		var s := rng.randf_range(1.2, 1.8)
		var rot := rng.randf() * TAU
		var ax := Vector3(cos(rot), 0, sin(rot))
		var az := Vector3(-sin(rot), 0, cos(rot))
		var rect := MatFoliage.cell_uv(rng.randi_range(0, 2))
		var ids: Array[int] = []
		for co in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
			var p: Vector3 = c + ax * float(co[0]) * s * 0.5 + az * float(co[1]) * s * 0.5
			var uv := rect.position + Vector2(float(co[0]) * 0.5 + 0.5, float(co[1]) * 0.5 + 0.5) * rect.size
			ids.append(g.add(p, Vector3.UP, uv, Color(0.8, 0.8, 0.8, 1.0)))
		g.tri(ids[0], ids[1], ids[2])
		g.tri(ids[0], ids[2], ids[3])


static func _commit(am: ArrayMesh, g: Geo, mat: Material, tangents: bool) -> void:
	if g.idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g.v
	arr[Mesh.ARRAY_NORMAL] = g.n
	arr[Mesh.ARRAY_TEX_UV] = g.uv
	arr[Mesh.ARRAY_COLOR] = g.c
	arr[Mesh.ARRAY_INDEX] = g.idx
	if tangents:
		var st := SurfaceTool.new()
		st.create_from_arrays(arr, Mesh.PRIMITIVE_TRIANGLES)
		st.generate_tangents()
		st.commit(am)
	else:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(am.get_surface_count() - 1, mat)


# ------------------------------------------------------------------ material de copa
const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Copa de árbol: atlas MatFoliage + normales esféricas del mesh (no se voltean en la cara trasera),
// AO/variación por color de vértice y recoloreo a flor (COLOR.a = cantidad de flor).
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_orm : hint_default_white, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 flower_a : source_color = vec4(1.0, 0.8, 0.1, 1.0);
uniform vec4 flower_b : source_color = vec4(0.95, 0.65, 0.05, 1.0);
uniform vec4 backlight_col : source_color = vec4(0.42, 0.52, 0.16, 1.0);
uniform float wind = 1.0;

void vertex() {
	float h = max(VERTEX.y - 2.5, 0.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = TIME * 1.4 + wp.x * 0.35 + wp.z * 0.29;
	VERTEX.xz += vec2(sin(ph), cos(ph * 0.83)) * wind * 0.006 * h;
}

void fragment() {
	vec4 a = texture(tex_albedo, UV);
	vec3 col = a.rgb * tint.rgb;
	float leafness = clamp((a.g / (a.r + 0.02) - 1.0) * 5.0, 0.0, 1.0) * step(a.b, a.g);
	float lum = dot(a.rgb, vec3(0.3, 0.59, 0.11));
	float nz = fract(sin(dot(floor(UV * 96.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 fl = mix(flower_a.rgb, flower_b.rgb, nz) * (0.45 + 1.9 * lum);
	col = mix(col, fl, leafness * COLOR.a);
	ALBEDO = col * COLOR.rgb;
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 orm = texture(tex_orm, UV).rgb;
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = 0.0;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	NORMAL_MAP = texture(tex_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.5;
	BACKLIGHT = mix(backlight_col.rgb, fl * 0.5, leafness * COLOR.a) * COLOR.rgb;
}
"""


static func _leaf_mat(kind: int) -> Material:
	if _leaf_mats.has(kind):
		return _leaf_mats[kind]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = LEAF_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	var base := MatFoliage.BASE + "canopy_atlas"
	m.set_shader_parameter("tex_albedo", load(base + "_albedo.png"))
	m.set_shader_parameter("tex_normal", load(base + "_normal.png"))
	m.set_shader_parameter("tex_orm", load(base + "_orm.png"))
	m.set_shader_parameter("backlight_col", MatFoliage.BACKLIGHT)
	match kind:
		ANDEN:
			m.set_shader_parameter("tint", Color(0.92, 0.98, 0.9))
		GUAYACAN_AMARILLO:
			m.set_shader_parameter("flower_a", Color(1.0, 0.82, 0.12))
			m.set_shader_parameter("flower_b", Color(0.96, 0.66, 0.06))
		GUAYACAN_ROSADO:
			m.set_shader_parameter("flower_a", Color(0.95, 0.58, 0.76))
			m.set_shader_parameter("flower_b", Color(0.85, 0.42, 0.66))
	_leaf_mats[kind] = m
	return m

class_name Traffic
extends RefCounted
## Señalización y mobiliario vial (F2-04): semáforos vehiculares y peatonales con ciclo, postes con
## brazo en bandera, señales de lámina con marco/abrazaderas/tubo galvanizado, placas de nomenclatura,
## bolardos, canecas públicas, hidrantes, sumideros y tapas de alcantarilla, y pintura vial (decals).
##
## Todas las funciones de malla devuelven ArrayMesh multi-superficie CACHEADAS (static var) para
## usar con BostonDistrict.place_mesh(key, mesh, xf, shadow). Convención: frente del modelo = +Z
## local, Y arriba, origen en el pie (sobre el andén) salvo que se diga otra cosa.
##
## Semáforos: las lentes usan UN ShaderMaterial por grupo de fase ("A" / "B"). El nodo
## Traffic.Cycle (colócalo una vez con place_node) cambia los uniformes de esos dos materiales,
## así todos los semáforos del mapa ciclan sin nodos ni draw calls extra.

const LENS_SHADER := """
shader_type spatial;
render_mode cull_back;
// UV.x codifica la lente: 0.1 roja, 0.3 ámbar, 0.5 verde, 0.7 peatón rojo, 0.9 peatón verde.
// UV2 = coordenadas locales de la lente en -1..1 (y arriba).
uniform float l_red = 1.0;
uniform float l_amber = 0.0;
uniform float l_green = 0.0;
uniform float p_red = 1.0;
uniform float p_walk = 0.0;
uniform float energy = 7.0;

float seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

float stand(vec2 q) {
	float d = length(q - vec2(0.0, 0.62)) - 0.14;
	d = min(d, seg(q, vec2(0.0, 0.40), vec2(0.0, -0.05), 0.15));
	d = min(d, seg(q, vec2(-0.21, 0.36), vec2(-0.23, -0.06), 0.06));
	d = min(d, seg(q, vec2(0.21, 0.36), vec2(0.23, -0.06), 0.06));
	d = min(d, seg(q, vec2(-0.08, -0.12), vec2(-0.08, -0.78), 0.075));
	d = min(d, seg(q, vec2(0.08, -0.12), vec2(0.08, -0.78), 0.075));
	return d;
}

float walk(vec2 q) {
	float d = length(q - vec2(0.06, 0.62)) - 0.14;
	d = min(d, seg(q, vec2(0.03, 0.40), vec2(0.0, -0.05), 0.13));
	d = min(d, seg(q, vec2(0.0, 0.34), vec2(-0.26, 0.04), 0.055));
	d = min(d, seg(q, vec2(0.04, 0.34), vec2(0.28, 0.10), 0.055));
	d = min(d, seg(q, vec2(0.0, -0.10), vec2(-0.30, -0.78), 0.075));
	d = min(d, seg(q, vec2(0.0, -0.10), vec2(0.18, -0.42), 0.075));
	d = min(d, seg(q, vec2(0.18, -0.42), vec2(0.22, -0.80), 0.07));
	return d;
}

void fragment() {
	float code = UV.x;
	vec2 q = UV2;
	vec3 col;
	float on;
	float mask = 1.0;
	if (code < 0.2) { col = vec3(1.0, 0.07, 0.03); on = l_red; }
	else if (code < 0.4) { col = vec3(1.0, 0.42, 0.02); on = l_amber; }
	else if (code < 0.6) { col = vec3(0.10, 1.0, 0.55); on = l_green; }
	else if (code < 0.8) { col = vec3(1.0, 0.10, 0.04); on = p_red; mask = smoothstep(0.03, -0.03, stand(q)); }
	else { col = vec3(0.15, 1.0, 0.6); on = p_walk; mask = smoothstep(0.03, -0.03, walk(q)); }
	// matriz de LEDs
	vec2 g = fract(q * 6.5) - 0.5;
	float led = smoothstep(0.46, 0.22, length(g));
	float r = length(q);
	float hot = 1.0 - 0.35 * smoothstep(0.2, 1.0, r);
	float lit = on * mask * mix(0.55, 1.0, led) * hot;
	ALBEDO = col * 0.05 + vec3(0.012);
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
	METALLIC = 0.0;
	// lente apagada: se adivina el color y la figura
	EMISSION = col * (lit * energy + 0.03 * (0.4 + mask));
}
"""

static var _mesh := {}
static var _mats := {}


# ================================================================== materiales propios

static func lens_mat(group: String) -> ShaderMaterial:
	var k := "lens_" + group
	if not _mats.has(k):
		if not _mats.has("lens_shader"):
			var nsh := Shader.new()
			nsh.code = LENS_SHADER
			_mats["lens_shader"] = nsh
		var sh: Shader = _mats["lens_shader"]
		var m := ShaderMaterial.new()
		m.shader = sh
		_mats[k] = m
	return _mats[k]


static func _std(key: String, albedo: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = albedo
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


## Plástico/aluminio fundido negro de las cajas de semáforo (algo satinado).
static func housing_mat() -> Material:
	return _std("housing", Color(0.035, 0.037, 0.04), 0.48, 0.15)

## Banda retrorreflectiva blanca de bolardos.
static func reflect_white() -> Material:
	return _std("reflect", Color(0.86, 0.87, 0.85), 0.35)

## Rojo del bonete del hidrante.
static func hydrant_red() -> Material:
	return _std("hyd_red", Color(0.62, 0.06, 0.04), 0.5)

## Interior oscuro (bolsa de caneca, fondo de sumidero).
static func void_dark() -> Material:
	return _std("void", Color(0.015, 0.015, 0.015), 0.95)

## Hierro fundido (tapas de alcantarilla, rejillas): galvanizado muy oscurecido.
static func cast_iron() -> Material:
	return MatMetal.galvanized({"tint": Color(0.30, 0.28, 0.26), "tile_m": 0.8})


static func _concrete() -> Material:
	return Palette.concrete()


# ================================================================== constructor de mallas

class B:
	var st := {}
	var mats := {}
	var order: Array = []
	var tris := 0

	func s(mat: Material) -> SurfaceTool:
		var k := mat.get_instance_id()
		if not st.has(k):
			var t := SurfaceTool.new()
			t.begin(Mesh.PRIMITIVE_TRIANGLES)
			st[k] = t
			mats[k] = mat
			order.append(k)
		return st[k]

	static func _uvp(p: Vector3, n: Vector3) -> Vector2:
		var a := n.abs()
		if a.y >= a.x and a.y >= a.z:
			return Vector2(p.x, p.z)
		if a.x >= a.z:
			return Vector2(p.z, -p.y)
		return Vector2(p.x, -p.y)

	## Triángulo; se reordena para que el frente mire hacia n (Godot: horario = frente).
	func tri(mat: Material, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb := Vector3.ZERO, nc := Vector3.ZERO, uv := [], uv2 := []) -> void:
		if nb == Vector3.ZERO:
			nb = na
		if nc == Vector3.ZERO:
			nc = na
		var t := s(mat)
		var vs := [[a, na, 0], [b, nb, 1], [c, nc, 2]]
		if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
			vs = [[a, na, 0], [c, nc, 2], [b, nb, 1]]
		var fn := (na + nb + nc).normalized()
		for v in vs:
			t.set_normal(v[1])
			t.set_uv(uv[v[2]] if uv.size() == 3 else _uvp(v[0], fn))
			if uv2.size() == 3:
				t.set_uv2(uv2[v[2]])
			t.add_vertex(v[0])
		tris += 1

	func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv := []) -> void:
		if uv.size() == 4:
			tri(mat, a, b, c, n, n, n, [uv[0], uv[1], uv[2]])
			tri(mat, a, c, d, n, n, n, [uv[0], uv[2], uv[3]])
		else:
			tri(mat, a, b, c, n)
			tri(mat, a, c, d, n)

	## Caja con chaflán en las 12 aristas (26 caras). bevel = 0 → caja simple.
	func box(mat: Material, xf: Transform3D, size: Vector3, bevel := 0.0) -> void:
		var h := size * 0.5
		var c := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
		var verts: Array = []
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					if c <= 0.0:
						verts.append(Vector3(sx * h.x, sy * h.y, sz * h.z))
					else:
						verts.append(Vector3(sx * h.x, sy * (h.y - c), sz * (h.z - c)))
						verts.append(Vector3(sx * (h.x - c), sy * h.y, sz * (h.z - c)))
						verts.append(Vector3(sx * (h.x - c), sy * (h.y - c), sz * h.z))
		var nb := xf.basis.inverse().transposed()
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if dx == 0 and dy == 0 and dz == 0:
						continue
					var n := Vector3(dx, dy, dz).normalized()
					var best := -1e9
					for v in verts:
						best = maxf(best, n.dot(v))
					var face: Array = []
					for v in verts:
						if n.dot(v) > best - 1e-5:
							face.append(v)
					if face.size() < 3:
						continue
					var ctr := Vector3.ZERO
					for v in face:
						ctr += v
					ctr /= face.size()
					var u: Vector3 = (face[0] - ctr).normalized()
					var w := n.cross(u)
					face.sort_custom(func(p: Vector3, q: Vector3) -> bool:
						return atan2((p - ctr).dot(w), (p - ctr).dot(u)) < atan2((q - ctr).dot(w), (q - ctr).dot(u)))
					var wn: Vector3 = (nb * n).normalized()
					for i in range(1, face.size() - 1):
						tri(mat, xf * face[0], xf * face[i], xf * face[i + 1], wn)

	## Cilindro/tronco de cono de a a b (normales suaves). caps: tapas planas.
	func cyl(mat: Material, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, caps := true, rot := 0.0) -> void:
		var ax := (b - a).normalized()
		var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
		var u := ax.cross(ref).normalized()
		var v := ax.cross(u)
		var slope := (ra - rb) / maxf((b - a).length(), 1e-4)
		for i in sides:
			var a0 := TAU * i / sides + rot
			var a1 := TAU * (i + 1) / sides + rot
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var n0 := (d0 + ax * slope).normalized()
			var n1 := (d1 + ax * slope).normalized()
			if ra > 0.0005:
				tri(mat, a + d0 * ra, a + d1 * ra, b + d1 * rb, n0, n1, n1)
			if rb > 0.0005:
				tri(mat, a + d0 * ra, b + d1 * rb, b + d0 * rb, n0, n1, n0)
			if caps:
				if ra > 0.0005:
					tri(mat, a, a + d0 * ra, a + d1 * ra, -ax)
				if rb > 0.0005:
					tri(mat, b, b + d1 * rb, b + d0 * rb, ax)

	## Polígono 2D (plano XY del xf, CCW) extruido en Z de z0 a z1.
	func prism(mat: Material, xf: Transform3D, pts: PackedVector2Array, z0: float, z1: float, cap0 := true, cap1 := true) -> void:
		var nb := xf.basis.inverse().transposed()
		var n := pts.size()
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= n
		for i in n:
			var p := pts[i]
			var q := pts[(i + 1) % n]
			var e := q - p
			var on := Vector3(e.y, -e.x, 0).normalized()
			if Vector2(on.x, on.y).dot((p + q) * 0.5 - c) < 0.0:
				on = -on
			var wn: Vector3 = (nb * on).normalized()
			quad(mat, xf * Vector3(p.x, p.y, z0), xf * Vector3(q.x, q.y, z0), xf * Vector3(q.x, q.y, z1), xf * Vector3(p.x, p.y, z1), wn)
			if cap1:
				tri(mat, xf * Vector3(c.x, c.y, z1), xf * Vector3(p.x, p.y, z1), xf * Vector3(q.x, q.y, z1), (nb * Vector3(0, 0, 1)).normalized())
			if cap0:
				tri(mat, xf * Vector3(c.x, c.y, z0), xf * Vector3(p.x, p.y, z0), xf * Vector3(q.x, q.y, z0), (nb * Vector3(0, 0, -1)).normalized())

	## Tubo doblado por una lista de puntos (anillos), sin tapas salvo caps.
	func bent(mat: Material, pts: Array, r: float, sides: int, caps := false) -> void:
		for i in pts.size() - 1:
			cyl(mat, pts[i], pts[i + 1], r, r, sides, caps or i == 0 or i == pts.size() - 2)

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for k in order:
			var t: SurfaceTool = st[k]
			t.generate_tangents()
			mesh = t.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[k])
		return mesh


static func _cached(key: String, f: Callable) -> ArrayMesh:
	if not _mesh.has(key):
		var b := B.new()
		f.call(b)
		_mesh[key] = b.commit()
		_mesh[key].set_meta("tris", b.tris)
	return _mesh[key]


## Triángulos de una malla de este módulo (para presupuesto/QA).
static func tri_count(mesh: Mesh) -> int:
	return int(mesh.get_meta("tris", 0))


static func _bolts(b: B, mat: Material, y: float, half: float, r := 0.012, h := 0.035) -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * half, y, sz * half)
			b.cyl(mat, p, p + Vector3(0, h, 0), r * 1.6, r * 1.6, 6, false)
			b.cyl(mat, p + Vector3(0, h, 0), p + Vector3(0, h + 0.03, 0), r * 1.6, r * 0.6, 6, false)


# ================================================================== semáforos

## Caja vehicular de 3 luces (300 mm) con viseras y placa de contraste con borde amarillo.
## Origen = centro de la caja; frente +Z. Alto 1.04 m. 3 superficies (caja, borde, lentes del grupo).
static func signal_head(group: String) -> ArrayMesh:
	return _cached("head_" + group, func(b: B) -> void:
		var hm := housing_mat()
		var ym := MatMetal.yellow_paint()
		var lm := lens_mat(group)
		b.box(hm, Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(0.36, 1.04, 0.24), 0.025)
		# placa de contraste (negra) con borde reflectivo amarillo
		b.box(hm, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.135)), Vector3(0.66, 1.34, 0.014))
		# borde amarillo: marco plano (solo caras frontales y traseras)
		var bz := -0.127
		var fr := [[Vector2(-0.33, 0.62), Vector2(0.33, 0.67)], [Vector2(-0.33, -0.67), Vector2(0.33, -0.62)],
			[Vector2(0.28, -0.62), Vector2(0.33, 0.62)], [Vector2(-0.33, -0.62), Vector2(-0.28, 0.62)]]
		for f in fr:
			var lo: Vector2 = f[0]
			var hi: Vector2 = f[1]
			b.quad(ym, Vector3(lo.x, lo.y, bz), Vector3(hi.x, lo.y, bz), Vector3(hi.x, hi.y, bz), Vector3(lo.x, hi.y, bz), Vector3(0, 0, 1))
			b.quad(ym, Vector3(lo.x, lo.y, bz - 0.017), Vector3(hi.x, lo.y, bz - 0.017), Vector3(hi.x, hi.y, bz - 0.017), Vector3(lo.x, hi.y, bz - 0.017), Vector3(0, 0, -1))
		# soportes superior/inferior
		for sy in [-1.0, 1.0]:
			b.box(hm, Transform3D(Basis.IDENTITY, Vector3(0, sy * 0.56, -0.02)), Vector3(0.12, 0.08, 0.16))
		var codes := [0.1, 0.3, 0.5]
		for i in 3:
			var y := 0.33 - i * 0.33
			_lens(b, lm, Vector3(0, y, 0.121), 0.105, codes[i], 10)
			_visor(b, hm, Vector3(0, y, 0.12), 0.125, 0.22)
	)


## Caja peatonal (figura roja quieta arriba, verde caminando abajo). Origen = centro; frente +Z.
static func ped_head(group: String) -> ArrayMesh:
	return _cached("ped_" + group, func(b: B) -> void:
		var hm := housing_mat()
		var lm := lens_mat(group)
		b.box(hm, Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(0.32, 0.64, 0.2), 0.02)
		var codes := [0.7, 0.9]
		for i in 2:
			var y := 0.155 - i * 0.31
			var z := 0.101
			var h := 0.125
			var uv := [Vector2(codes[i], 0), Vector2(codes[i], 0), Vector2(codes[i], 0)]
			var p := [Vector3(-h, -h, z), Vector3(h, -h, z), Vector3(h, h, z), Vector3(-h, h, z)]
			var q := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
			for t in [[0, 1, 2], [0, 2, 3]]:
				b.tri(lm, p[t[0]] + Vector3(0, y, 0), p[t[1]] + Vector3(0, y, 0), p[t[2]] + Vector3(0, y, 0), Vector3(0, 0, 1), Vector3.ZERO, Vector3.ZERO, uv, [q[t[0]], q[t[1]], q[t[2]]])
			# visera de 3 lados
			var vz0 := 0.1
			var vz1 := 0.22
			var hh := 0.145
			b.box(hm, Transform3D(Basis.IDENTITY, Vector3(0, y + hh, (vz0 + vz1) * 0.5)), Vector3(hh * 2.0 + 0.01, 0.008, vz1 - vz0))
			for sx in [-1.0, 1.0]:
				b.tri(hm, Vector3(sx * hh, y + hh, vz0), Vector3(sx * hh, y + hh, vz1), Vector3(sx * hh, y - hh * 0.6, vz0), Vector3(sx, 0, 0))
				b.tri(hm, Vector3(sx * hh, y + hh, vz0), Vector3(sx * hh, y + hh, vz1), Vector3(sx * hh, y - hh * 0.6, vz0), Vector3(-sx, 0, 0))
		for sy in [-1.0, 1.0]:
			b.box(hm, Transform3D(Basis.IDENTITY, Vector3(0, sy * 0.35, -0.02)), Vector3(0.1, 0.07, 0.12), 0.008)
	)


static func _lens(b: B, lm: Material, c: Vector3, r: float, code: float, segs: int) -> void:
	var uv := [Vector2(code, 0), Vector2(code, 0), Vector2(code, 0)]
	var tip := c + Vector3(0, 0, 0.014)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := c + Vector3(cos(a0) * r, sin(a0) * r, 0)
		var p1 := c + Vector3(cos(a1) * r, sin(a1) * r, 0)
		var n0 := Vector3(cos(a0) * 0.35, sin(a0) * 0.35, 1).normalized()
		var n1 := Vector3(cos(a1) * 0.35, sin(a1) * 0.35, 1).normalized()
		b.tri(lm, tip, p0, p1, Vector3(0, 0, 1), n0, n1, uv, [Vector2.ZERO, Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1))])


## Visera en arco (≈200°) con cara exterior e interior.
static func _visor(b: B, mat: Material, c: Vector3, r: float, length: float) -> void:
	var segs := 6
	var a_from := deg_to_rad(-12.0)
	var a_to := deg_to_rad(192.0)
	var t := 0.006
	for i in segs:
		var a0 := lerpf(a_from, a_to, float(i) / segs)
		var a1 := lerpf(a_from, a_to, float(i + 1) / segs)
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		var z1 := length
		var z0 := 0.0
		# el borde inferior de la visera es más corto (corte en bisel)
		var l0 := lerpf(length * 0.45, length, clampf(d0.y * 0.5 + 0.5, 0.0, 1.0))
		var l1 := lerpf(length * 0.45, length, clampf(d1.y * 0.5 + 0.5, 0.0, 1.0))
		b.quad(mat, c + d0 * (r + t), c + d1 * (r + t), c + d1 * (r + t) + Vector3(0, 0, l1), c + d0 * (r + t) + Vector3(0, 0, l0), (d0 + d1).normalized())
		b.quad(mat, c + d0 * r, c + d1 * r, c + d1 * r + Vector3(0, 0, l1), c + d0 * r + Vector3(0, 0, l0), -(d0 + d1).normalized())
		b.quad(mat, c + d0 * r + Vector3(0, 0, l0), c + d1 * r + Vector3(0, 0, l1), c + d1 * (r + t) + Vector3(0, 0, l1), c + d0 * (r + t) + Vector3(0, 0, l0), Vector3(0, 0, 1))


const ARM_Y := 5.7
const POLE_H := 6.3

## Poste galvanizado de semáforo con brazo en bandera (pie en el origen sobre el andén).
## Marco local: brazo hacia +X; los semáforos miran hacia -Z (hacia el tráfico que se acerca).
## Usar Basis(arm, UP, -face) en el mundo. reach: largo del brazo (m).
## Incluye ganchos para: cabeza colgada (signal_anchors), repetidor en el poste y 2 peatonales.
static func signal_pole(reach: float) -> ArrayMesh:
	var r := snappedf(reach, 0.5)
	return _cached("pole_%.1f" % r, func(b: B) -> void:
		var g := MatMetal.galvanized()
		var conc := _concrete()
		# dado de concreto
		b.box(conc, Transform3D(Basis.IDENTITY, Vector3(0, -0.05, 0)), Vector3(0.62, 0.16, 0.62), 0.03)
		# platina base con pernos y cartelas
		b.box(g, Transform3D(Basis.IDENTITY, Vector3(0, 0.045, 0)), Vector3(0.42, 0.025, 0.42), 0.006)
		_bolts(b, g, 0.058, 0.16)
		for i in 4:
			var bs := Basis(Vector3.UP, PI * 0.5 * i)
			b.box(g, Transform3D(bs, bs * Vector3(0.14, 0.13, 0)), Vector3(0.1, 0.16, 0.012))
		# fuste cónico
		b.cyl(g, Vector3(0, 0.05, 0), Vector3(0, POLE_H, 0), 0.115, 0.085, 10, false)
		b.cyl(g, Vector3(0, POLE_H, 0), Vector3(0, POLE_H + 0.05, 0), 0.095, 0.03, 10, false)
		# collar y brazo
		b.cyl(g, Vector3(0, ARM_Y - 0.18, 0), Vector3(0, ARM_Y + 0.18, 0), 0.105, 0.105, 8, false)
		b.cyl(g, Vector3(0.08, ARM_Y, 0), Vector3(r, ARM_Y, 0), 0.07, 0.05, 8, true)
		# tirante diagonal
		var t0 := Vector3(0.08, ARM_Y - 0.9, 0)
		var t1 := Vector3(minf(r * 0.45, 2.6), ARM_Y - 0.03, 0)
		b.cyl(g, t0, t1, 0.035, 0.035, 6, true)
		b.cyl(g, Vector3(0, ARM_Y - 0.98, 0), Vector3(0, ARM_Y - 0.82, 0), 0.1, 0.1, 8, false)
		# colgantes de las cabezas
		for hx in _hang_xs(r):
			b.cyl(g, Vector3(hx, ARM_Y - 0.03, 0), Vector3(hx, ARM_Y - 0.2, 0), 0.03, 0.03, 6, true)
			b.box(g, Transform3D(Basis.IDENTITY, Vector3(hx, ARM_Y, 0)), Vector3(0.12, 0.16, 0.16))
		# soportes del repetidor (hacia -Z) y de las peatonales (+X, +Z)
		for y in [REP_Y + 0.3, REP_Y - 0.3]:
			b.box(g, Transform3D(Basis.IDENTITY, Vector3(0, y, -0.15)), Vector3(0.06, 0.05, 0.22))
		for y in [PED_Y + 0.2, PED_Y - 0.2]:
			b.box(g, Transform3D(Basis.IDENTITY, Vector3(0.17, y, 0)), Vector3(0.16, 0.05, 0.05))
			b.box(g, Transform3D(Basis.IDENTITY, Vector3(0, y, 0.17)), Vector3(0.05, 0.05, 0.16))
		# caja de mando pequeña y abrazaderas
		b.box(g, Transform3D(Basis.IDENTITY, Vector3(-0.17, 1.35, 0)), Vector3(0.12, 0.4, 0.26), 0.015)
		b.cyl(g, Vector3(0, 1.05, 0), Vector3(0, 1.1, 0), 0.125, 0.125, 8, false)
		b.cyl(g, Vector3(0, 1.6, 0), Vector3(0, 1.65, 0), 0.122, 0.122, 8, false)
	)


const REP_Y := 3.0
const PED_Y := 2.3


static func _hang_xs(reach: float) -> Array:
	if reach > 5.5:
		return [reach - 0.25, reach * 0.5]
	return [reach - 0.25]


## Transformaciones (en el marco local de signal_pole) donde van las cabezas:
## {"heads": [Transform3D...] vehiculares, "rep": repetidor, "ped_arm": peatonal que mira hacia +X,
##  "ped_back": peatonal que mira hacia +Z}. Cabezas vehiculares miran a -Z.
static func signal_anchors(reach: float) -> Dictionary:
	var r := snappedf(reach, 0.5)
	var face := Basis(Vector3.UP, PI)   # +Z del modelo → -Z local
	var heads: Array = []
	for hx in _hang_xs(r):
		heads.append(Transform3D(face, Vector3(hx, ARM_Y - 0.2 - 0.62, 0)))
	return {
		"heads": heads,
		"rep": Transform3D(face.scaled(Vector3.ONE * 0.85), Vector3(0, REP_Y, -0.38)),
		"ped_arm": Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.36, PED_Y, 0)),
		"ped_back": Transform3D(Basis.IDENTITY, Vector3(0, PED_Y, 0.34)),
	}


## Nodo controlador del ciclo (colocar UNO en el mapa con place_node). Fases (s):
## A: verde 0-12, ámbar 12-15, rojo 15-32 · B: desfasado 16 s. Peatones: verde fijo 9 s + 3 s parpadeando.
class Cycle extends Node3D:
	const PERIOD := 32.0
	var t := 0.0

	func _ready() -> void:
		name = "CicloSemaforos"
		_apply()

	func _process(delta: float) -> void:
		t = fmod(t + delta, PERIOD)
		_apply()

	func _apply() -> void:
		_group(Traffic.lens_mat("A"), t)
		_group(Traffic.lens_mat("B"), fmod(t + PERIOD * 0.5, PERIOD))

	func _group(m: ShaderMaterial, tt: float) -> void:
		var green := 1.0 if tt < 12.0 else 0.0
		var amber := 1.0 if tt >= 12.0 and tt < 15.0 else 0.0
		var red := 1.0 - green - amber
		var walk := 1.0 if tt < 9.0 else (1.0 if tt < 12.0 and fmod(tt, 0.8) < 0.45 else 0.0)
		m.set_shader_parameter("l_green", green)
		m.set_shader_parameter("l_amber", amber)
		m.set_shader_parameter("l_red", red)
		m.set_shader_parameter("p_walk", walk)
		m.set_shader_parameter("p_red", 1.0 if tt >= 12.0 else 0.0)


# ================================================================== señales verticales

## Forma (contorno CCW en -0.5..0.5, y arriba) de la lámina de cada señal del atlas, ya escalada a `size`.
static func _sign_outline(idx: int, size: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var name := MatMetal.SIGNS[idx]
	var k := size
	match name:
		"pare":
			var r := 0.434 * k / cos(PI / 8.0)
			for i in 8:
				var a := PI / 8.0 + TAU * i / 8.0
				p.append(Vector2(cos(a), sin(a)) * r)
		"ceda_el_paso":
			# triángulo invertido: bbox y 0.102..0.953 (desde arriba)
			p.append(Vector2(0, (0.5 - 0.953) * k))
			p.append(Vector2(0.469 * k, (0.5 - 0.102) * k))
			p.append(Vector2(-0.469 * k, (0.5 - 0.102) * k))
		"no_parquear", "velocidad_30", "prohibido_girar":
			for i in 20:
				var a := TAU * i / 20.0
				p.append(Vector2(cos(a), sin(a)) * 0.466 * k)
		"peligro_curva", "paso_peatonal":
			var d := 0.466 * k
			p.append_array([Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)])
		"baje_en_2a":
			p.append_array(_rect(0.383 * k, 0.466 * k))
		_:
			p.append_array(_rect(0.466 * k, 0.24 * k))
	return p


static func _rect(hx: float, hy: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])


## Lámina de señal (frente del atlas + reverso galvanizado con pestaña de 1.5 cm) centrada en c,
## frente +Z. double: placa de nomenclatura impresa por ambas caras.
static func _sign_plate(b: B, idx: int, size: float, c: Vector3, double := false) -> void:
	var g := MatMetal.galvanized()
	var sm := MatMetal.sign(idx)
	var h := size * 0.5
	var uvq := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var pq := [c + Vector3(-h, -h, 0.004), c + Vector3(h, -h, 0.004), c + Vector3(h, h, 0.004), c + Vector3(-h, h, 0.004)]
	b.quad(sm, pq[0], pq[1], pq[2], pq[3], Vector3(0, 0, 1), uvq)
	var out := _sign_outline(idx, size * 0.985)
	b.prism(g, Transform3D(Basis.IDENTITY, c), out, -0.012, 0.0, not double, false)
	if double:
		var bq := [c + Vector3(h, -h, -0.016), c + Vector3(-h, -h, -0.016), c + Vector3(-h, h, -0.016), c + Vector3(h, h, -0.016)]
		b.quad(sm, bq[0], bq[1], bq[2], bq[3], Vector3(0, 0, -1), uvq)


## Señal completa en tubo galvanizado de 2": lámina + reverso + riel + 2 abrazaderas + tubo con tapa
## + dado de concreto. idx = índice en MatMetal.SIGNS (o usa sign_post_named). top: altura del borde
## superior de la lámina. Frente +Z. ~150-250 triángulos.
static func sign_post(idx: int, top := 2.6) -> ArrayMesh:
	return _cached("sign_%d_%.2f" % [idx, top], func(b: B) -> void:
		var g := MatMetal.galvanized()
		var size: float = MatMetal.SIGN_SIZE_M[idx]
		var out := _sign_outline(idx, size)
		var ymax := -1e9
		var ymin := 1e9
		for p in out:
			ymax = maxf(ymax, p.y)
			ymin = minf(ymin, p.y)
		var c := Vector3(0, top - ymax, 0.06)
		_sign_plate(b, idx, size, c)
		# tubo
		var tube_top := c.y + ymax - 0.04
		b.cyl(g, Vector3(0, -0.1, 0), Vector3(0, tube_top, 0), 0.03, 0.03, 8, false)
		b.cyl(g, Vector3(0, tube_top, 0), Vector3(0, tube_top + 0.012, 0), 0.034, 0.034, 8, true)
		# riel en omega detrás de la lámina y abrazaderas
		b.box(g, Transform3D(Basis.IDENTITY, Vector3(0, c.y, 0.034)), Vector3(0.05, (ymax - ymin) * 0.82, 0.02))
		for f in [0.28, -0.28]:
			var y: float = c.y + (ymax - ymin) * f
			b.cyl(g, Vector3(0, y - 0.022, 0), Vector3(0, y + 0.022, 0), 0.037, 0.037, 8, false)
			b.box(g, Transform3D(Basis.IDENTITY, Vector3(0, y, 0.035)), Vector3(0.09, 0.044, 0.012))
			for sx in [-0.035, 0.035]:
				b.cyl(g, Vector3(sx, y, 0.03), Vector3(sx, y, 0.05), 0.007, 0.007, 6, true)
		# dado
		b.cyl(_concrete(), Vector3(0, -0.06, 0), Vector3(0, 0.03, 0), 0.11, 0.1, 8, true)
	)


static func sign_post_named(sign_name: String, top := 2.6) -> ArrayMesh:
	return sign_post(maxi(MatMetal.SIGNS.find(sign_name), 0), top)


## Índice del atlas de la placa de nomenclatura para "C55", "K38", ... (-1 si no existe).
static func plate_index(street_id: String) -> int:
	var map := {"C55": "calle_55_peru", "K38": "carrera_38", "C54": "calle_54_caracas",
		"K39": "carrera_39", "C58": "calle_58_echeverri", "K43": "carrera_43_girardot"}
	if not map.has(street_id):
		return -1
	return MatMetal.SIGNS.find(map[street_id])


## Placa verde de nomenclatura (doble cara) con su pletina de fijación; centrada en el origen,
## frentes ±Z, ancho ~0.9 m. Para colgar de un poste: origen en el eje del poste.
static func street_plate(idx: int) -> ArrayMesh:
	return _cached("plate_%d" % idx, func(b: B) -> void:
		var g := MatMetal.galvanized()
		var size := 0.92
		_sign_plate(b, idx, size, Vector3(0, 0, 0.008), true)
		b.box(g, Transform3D(Basis.IDENTITY, Vector3(0, 0.235, 0)), Vector3(0.9, 0.025, 0.035), 0.004)
		b.box(g, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(0.05, 0.5, 0.05))
	)


## Poste de nomenclatura de esquina: tubo galvanizado de 3.4 m con dos placas cruzadas
## (calle arriba, carrera abajo). La placa de la calle queda en el plano XY local (frente ±Z).
## Si un índice es -1 se omite esa placa.
static func plate_post(calle_idx: int, carrera_idx: int) -> ArrayMesh:
	return _cached("platepost_%d_%d" % [calle_idx, carrera_idx], func(b: B) -> void:
		var g := MatMetal.galvanized()
		b.cyl(_concrete(), Vector3(0, -0.06, 0), Vector3(0, 0.03, 0), 0.12, 0.11, 8, true)
		b.cyl(g, Vector3(0, -0.1, 0), Vector3(0, 3.45, 0), 0.035, 0.035, 8, false)
		b.cyl(g, Vector3(0, 3.45, 0), Vector3(0, 3.5, 0), 0.04, 0.01, 8, false)
		if calle_idx >= 0:
			_merge_plate(b, calle_idx, Transform3D(Basis.IDENTITY, Vector3(0, 3.18, 0.04)))
		if carrera_idx >= 0:
			_merge_plate(b, carrera_idx, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.04, 2.78, 0)))
	)


static func _merge_plate(b: B, idx: int, xf: Transform3D) -> void:
	var g := MatMetal.galvanized()
	var size := 0.92
	var sm := MatMetal.sign(idx)
	var h := size * 0.5
	var nb := xf.basis
	var uvq := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for side in [1.0, -1.0]:
		var z: float = 0.006 * side
		var xs: float = 1.0 if side > 0.0 else -1.0
		b.quad(sm, xf * Vector3(-h * xs, -h, z), xf * Vector3(h * xs, -h, z), xf * Vector3(h * xs, h, z), xf * Vector3(-h * xs, h, z), nb * Vector3(0, 0, side), uvq)
	b.prism(g, xf, _rect(0.466 * size * 0.985, 0.24 * size * 0.985), -0.004, 0.004, false, false)
	b.box(g, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.235, 0)), Vector3(0.9, 0.022, 0.03), 0.004)
	b.box(g, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.0, -0.03)), Vector3(0.09, 0.12, 0.03), 0.006)


# ================================================================== mobiliario

## Bolardo de acero (pintura amarilla de tráfico) con dos bandas reflectivas y base con pernos.
## variant 0: cilíndrico con domo · 1: más bajo con tapa plana. ~200 triángulos.
static func bollard(variant := 0) -> ArrayMesh:
	return _cached("bollard_%d" % variant, func(b: B) -> void:
		var y := MatMetal.yellow_paint()
		var w := reflect_white()
		var g := MatMetal.galvanized()
		var h := 0.9 if variant == 0 else 0.75
		var r := 0.075 if variant == 0 else 0.09
		b.box(g, Transform3D(Basis.IDENTITY, Vector3(0, 0.008, 0)), Vector3(0.24, 0.016, 0.24), 0.004)
		_bolts(b, g, 0.016, 0.085, 0.009, 0.02)
		b.cyl(y, Vector3(0, 0.0, 0), Vector3(0, h, 0), r * 1.04, r, 10, false)
		if variant == 0:
			b.cyl(y, Vector3(0, h, 0), Vector3(0, h + 0.05, 0), r, r * 0.6, 10, false)
			b.cyl(y, Vector3(0, h + 0.05, 0), Vector3(0, h + 0.07, 0), r * 0.6, 0.0, 10, false)
		else:
			b.cyl(y, Vector3(0, h, 0), Vector3(0, h + 0.015, 0), r * 1.08, r * 1.08, 10, true)
		for by in [h - 0.12, h - 0.26]:
			b.cyl(w, Vector3(0, by, 0), Vector3(0, by + 0.07, 0), r + 0.003, r + 0.003, 10, false)
	)


## Caneca pública metálica de poste doble (pintura verde) con bolsa oscura, aro y pivote.
## Frente +Z. variant 0/1 (alto). ~500 triángulos.
static func bin(variant := 0) -> ArrayMesh:
	return _cached("bin_%d" % variant, func(b: B) -> void:
		var gp := MatMetal.green_paint()
		var g := MatMetal.galvanized()
		var dk := void_dark()
		var top := 1.0 if variant == 0 else 1.08
		var r := 0.24
		var hh := 0.62
		var by := top - hh
		# postes con base
		for sx in [-1.0, 1.0]:
			var px: float = sx * (r + 0.07)
			b.cyl(g, Vector3(px, -0.05, 0), Vector3(px, top + 0.06, 0), 0.03, 0.03, 8, false)
			b.cyl(g, Vector3(px, top + 0.06, 0), Vector3(px, top + 0.08, 0), 0.034, 0.0, 8, false)
			b.cyl(g, Vector3(px, 0, 0), Vector3(px, 0.02, 0), 0.07, 0.07, 8, true)
			# pivote
			b.cyl(g, Vector3(px, top - 0.18, 0), Vector3(sx * r * 0.96, top - 0.18, 0), 0.022, 0.022, 6, true)
		# cubeta: anillos con ribetes (cuerpo verde, borde enrollado)
		b.cyl(gp, Vector3(0, by, 0), Vector3(0, top, 0), r * 0.92, r, 12, false)
		b.cyl(gp, Vector3(0, by - 0.02, 0), Vector3(0, by, 0), r * 0.85, r * 0.92, 12, false)
		b.cyl(gp, Vector3(0, by - 0.02, 0), Vector3(0, by - 0.021, 0), 0.0, r * 0.85, 12, false)
		for ry in [by + 0.18, by + 0.4]:
			b.cyl(gp, Vector3(0, ry, 0), Vector3(0, ry + 0.035, 0), r * 0.97 + 0.01, r * 0.98 + 0.01, 12, false)
		b.cyl(gp, Vector3(0, top, 0), Vector3(0, top + 0.03, 0), r + 0.015, r + 0.015, 12, false)
		b.cyl(gp, Vector3(0, top + 0.03, 0), Vector3(0, top + 0.03, 0) + Vector3(0, 0.0005, 0), r + 0.015, r - 0.01, 12, false)
		# interior oscuro + bolsa asomando
		b.cyl(dk, Vector3(0, top - 0.02, 0), Vector3(0, by + 0.05, 0), r - 0.012, r * 0.85, 12, false)
		b.cyl(dk, Vector3(0, by + 0.25, 0), Vector3(0, by + 0.251, 0), r * 0.9, 0.0, 12, false)
		b.cyl(dk, Vector3(0, top + 0.03, 0), Vector3(0, top + 0.07, 0), r + 0.017, r + 0.005, 12, false, 0.3)
		# placa "Medellín limpia" (franja blanca)
		b.box(reflect_white(), Transform3D(Basis.IDENTITY, Vector3(0, by + 0.3, r * 0.97)), Vector3(0.18, 0.08, 0.008))
	)


## Hidrante tipo poste (cuerpo amarillo, bonete rojo, 2 bocas laterales y 1 frontal con tapas
## y cadenas), brida con pernos. Frente +Z. variant 0/1 (alto/proporción). ~700 triángulos.
static func hydrant(variant := 0) -> ArrayMesh:
	return _cached("hydrant_%d" % variant, func(b: B) -> void:
		var y := MatMetal.yellow_paint()
		var rd := hydrant_red()
		var g := MatMetal.galvanized()
		var h := 0.62 if variant == 0 else 0.7
		var r := 0.12 if variant == 0 else 0.11
		b.cyl(y, Vector3(0, -0.04, 0), Vector3(0, 0.05, 0), r + 0.07, r + 0.06, 12, true)
		b.cyl(y, Vector3(0, 0.05, 0), Vector3(0, 0.09, 0), r + 0.045, r + 0.03, 12, false)
		for i in 8:
			var a := TAU * i / 8.0
			var p := Vector3(cos(a) * (r + 0.045), 0.05, sin(a) * (r + 0.045))
			b.cyl(g, p, p + Vector3(0, 0.025, 0), 0.012, 0.012, 6, true)
		b.cyl(y, Vector3(0, 0.09, 0), Vector3(0, h, 0), r, r * 0.95, 12, false)
		b.cyl(y, Vector3(0, h * 0.72, 0), Vector3(0, h * 0.72 + 0.04, 0), r + 0.02, r + 0.02, 12, true)
		b.cyl(rd, Vector3(0, h, 0), Vector3(0, h + 0.03, 0), r + 0.03, r + 0.03, 12, true)
		b.cyl(rd, Vector3(0, h + 0.03, 0), Vector3(0, h + 0.13, 0), r * 0.95, r * 0.45, 12, false)
		b.cyl(rd, Vector3(0, h + 0.13, 0), Vector3(0, h + 0.17, 0), 0.03, 0.03, 5, true)
		# bocas
		var outs := [[Vector3(1, 0, 0), 0.05], [Vector3(-1, 0, 0), 0.05], [Vector3(0, 0, 1), 0.07]]
		for o in outs:
			var d: Vector3 = o[0]
			var rr: float = o[1]
			var oy := h * 0.52 if rr < 0.06 else h * 0.4
			var p0 := Vector3(0, oy, 0) + d * (r * 0.8)
			b.cyl(y, p0, p0 + d * (r * 0.4 + 0.06), rr + 0.012, rr + 0.012, 10, true)
			b.cyl(rd, p0 + d * (r * 0.4 + 0.06), p0 + d * (r * 0.4 + 0.1), rr, rr, 6, true, PI / 6.0)
			b.cyl(rd, p0 + d * (r * 0.4 + 0.1), p0 + d * (r * 0.4 + 0.125), 0.018, 0.018, 5, true)
			# cadena (tramo doblado hacia el cuerpo)
			var c0 := p0 + d * (r * 0.4 + 0.08) + Vector3(0, -rr - 0.01, 0)
			b.bent(g, [c0, c0 + Vector3(0, -0.06, 0) - d * 0.05, Vector3(0, h * 0.3, 0) + d * (r + 0.004)], 0.004, 3)
	)


## Tapa de alcantarilla de hierro (Ø 0.66 m) con aro, nervios radiales y anillos en relieve.
## Origen al ras de la calzada, plano XZ local (inclinar con la vía). ~180 triángulos.
static func manhole(variant := 0) -> ArrayMesh:
	return _cached("manhole_%d" % variant, func(b: B) -> void:
		var m := cast_iron()
		var r := 0.33
		b.cyl(m, Vector3(0, 0.0, 0), Vector3(0, 0.012, 0), r + 0.05, r + 0.045, 16, false)
		b.cyl(m, Vector3(0, 0.012, 0), Vector3(0, 0.0125, 0), r + 0.045, 0.0, 16, false)
		for rr in [0.26, 0.15]:
			b.cyl(m, Vector3(0, 0.012, 0), Vector3(0, 0.02, 0), rr + 0.015, rr + 0.012, 14, false)
			b.cyl(m, Vector3(0, 0.02, 0), Vector3(0, 0.0205, 0), rr + 0.012, rr - 0.012, 14, false)
		var n := 8 if variant == 0 else 6
		for i in n:
			var a := TAU * i / n + 0.2
			var d := Vector3(cos(a), 0, sin(a))
			var bs := Basis(Vector3.UP, -a)
			b.box(m, Transform3D(bs, d * 0.21 + Vector3(0, 0.017, 0)), Vector3(0.2, 0.01, 0.022))
		b.cyl(m, Vector3(0, 0.012, 0), Vector3(0, 0.022, 0), 0.06, 0.05, 8, false)
		# ojal de levante
		b.box(void_dark(), Transform3D(Basis.IDENTITY, Vector3(0.29, 0.0165, 0)), Vector3(0.06, 0.002, 0.022))
	)


## Rejilla de sumidero junto al sardinel: marco de hierro + barras + fondo oscuro.
## 0.9 m (X, a lo largo del sardinel) x 0.45 m (Z). Origen al ras de la calzada; +Z hacia el centro
## de la vía, el borde -Z toca el sardinel. ~150 triángulos.
static func drain_grate() -> ArrayMesh:
	return _cached("grate", func(b: B) -> void:
		var m := cast_iron()
		var dk := void_dark()
		var hx := 0.45
		var hz := 0.225
		var zc := hz
		b.box(dk, Transform3D(Basis.IDENTITY, Vector3(0, 0.003, zc)), Vector3(hx * 2.0 - 0.06, 0.004, hz * 2.0 - 0.06))
		var t := 0.045
		b.box(m, Transform3D(Basis.IDENTITY, Vector3(0, 0.01, zc - hz + t * 0.5)), Vector3(hx * 2.0, 0.02, t), 0.004)
		b.box(m, Transform3D(Basis.IDENTITY, Vector3(0, 0.01, zc + hz - t * 0.5)), Vector3(hx * 2.0, 0.02, t), 0.004)
		b.box(m, Transform3D(Basis.IDENTITY, Vector3(hx - t * 0.5, 0.01, zc)), Vector3(t, 0.02, hz * 2.0 - t * 2.0), 0.004)
		b.box(m, Transform3D(Basis.IDENTITY, Vector3(-hx + t * 0.5, 0.01, zc)), Vector3(t, 0.02, hz * 2.0 - t * 2.0), 0.004)
		var nb := 9
		for i in nb:
			var x := lerpf(-hx + t + 0.03, hx - t - 0.03, float(i) / (nb - 1))
			var z0 := zc - hz + t
			var z1 := zc + hz - t
			b.quad(m, Vector3(x - 0.011, 0.018, z0), Vector3(x + 0.011, 0.018, z0), Vector3(x + 0.011, 0.018, z1), Vector3(x - 0.011, 0.018, z1), Vector3.UP)
			for sx in [-0.011, 0.011]:
				b.quad(m, Vector3(x + sx, 0.0, z0), Vector3(x + sx, 0.018, z0), Vector3(x + sx, 0.018, z1), Vector3(x + sx, 0.0, z1), Vector3(signf(sx), 0, 0))
		b.box(m, Transform3D(Basis.IDENTITY, Vector3(0, 0.009, zc)), Vector3(hx * 2.0 - t * 2.0, 0.016, 0.025))
	)


# ================================================================== pintura vial

## Acumula decals de MatAsphalt.road_decals() en mallas fusionadas por trozo (1 draw call por trozo).
## Los vértices se ponen sobre el plano inclinado de la calzada: y = slope·x + base + lift.
class Decals:
	var slope := 0.04
	var base := -0.15
	var lift := 0.014
	var chunk := 160.0
	var _st := {}
	var count := 0

	func _t(p: Vector2) -> SurfaceTool:
		var k := Vector2i(floori(p.x / chunk), floori(p.y / chunk))
		if not _st.has(k):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_st[k] = st
		return _st[k]

	func _v(st: SurfaceTool, p: Vector2, uv: Vector2) -> void:
		st.set_normal(Vector3(-slope, 1.0, 0.0).normalized())
		st.set_uv(uv)
		st.add_vertex(Vector3(p.x, slope * p.x + base + lift, p.y))

	## Quad del atlas centrado en `c` (XZ), con el "adelante" (V=0 del atlas, sentido de lectura)
	## hacia `fwd` (XZ). size: (ancho, largo) en m. v_reps: repeticiones en V (líneas continuas).
	func add(name: String, c: Vector2, fwd: Vector2, size: Vector2 = Vector2.ZERO, v_reps := 1.0, flip_u := false) -> void:
		var r: Rect2 = MatAsphalt.DECAL_UV[name]
		var sz: Vector2 = size if size != Vector2.ZERO else MatAsphalt.DECAL_SIZE_M[name]
		var f := fwd.normalized()
		var right := Vector2(-f.y, f.x)   # derecha del conductor (en XZ: f=(0,-1) → (1,0))
		var hx := sz.x * 0.5
		var hz := sz.y * 0.5
		var u0 := r.position.x
		var u1 := r.end.x
		if flip_u:
			var tmp := u0
			u0 = u1
			u1 = tmp
		var v0 := r.position.y
		var v1 := r.position.y + r.size.y * v_reps
		var st := _t(c)
		var a := c - right * hx + f * hz
		var b := c + right * hx + f * hz
		var cc := c + right * hx - f * hz
		var d := c - right * hx - f * hz
		# horario visto desde arriba = frente (Godot)
		_v(st, a, Vector2(u0, v0))
		_v(st, b, Vector2(u1, v0))
		_v(st, cc, Vector2(u1, v1))
		_v(st, a, Vector2(u0, v0))
		_v(st, cc, Vector2(u1, v1))
		_v(st, d, Vector2(u0, v1))
		count += 1

	## Línea continua de p0 a p1 (tilea la textura cada 2.56 m).
	func line(name: String, p0: Vector2, p1: Vector2, width := 0.0) -> void:
		var L := p0.distance_to(p1)
		if L < 0.2:
			return
		var w: float = width if width > 0.0 else MatAsphalt.DECAL_SIZE_M[name].x
		add(name, (p0 + p1) * 0.5, p1 - p0, Vector2(w, L), L / 2.56)

	## Discontinua: trazos de `dash` m cada `period` m.
	func dashed(name: String, p0: Vector2, p1: Vector2, dash := 2.56, period := 6.0) -> void:
		var L := p0.distance_to(p1)
		var dir := (p1 - p0) / maxf(L, 0.001)
		var t := 0.0
		while t + dash <= L:
			add(name, p0 + dir * (t + dash * 0.5), dir, Vector2(MatAsphalt.DECAL_SIZE_M[name].x, dash), dash / 2.56 if name != "dash_white" else 1.0)
			t += period

	## Mallas finales: [[key, ArrayMesh], ...]
	func meshes(prefix: String) -> Array:
		var out: Array = []
		for k in _st:
			var st: SurfaceTool = _st[k]
			st.generate_tangents()
			var m := st.commit()
			m.surface_set_material(0, MatAsphalt.road_decals())
			out.append(["%s_%d_%d" % [prefix, k.x, k.y], m])
		return out

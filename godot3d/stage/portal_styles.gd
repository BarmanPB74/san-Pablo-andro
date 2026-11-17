class_name PortalStyles
extends RefCounted
## Marcos de los portales por etapa de la historia (todo por código, con cajas y esferas):
##   0 PIEDRA    — arco de arenisca desgastada con signos tallados y matas secas (ref. 84869)
##   1 CELESTIAL — arco de perla con filigrana dorada, columnas y una gema rosa en la clave (ref. 84870)
##   2 DORADO    — pilares de roca con vetas de oro, gran arco dorado y una escalera de luz en el piso (ref. 84871)
## `build` llena `frame` y devuelve {light, energy, spill} para la luz y la mancha del piso.

const STONE := 0
const CELESTIAL := 1
const GOLDEN := 2
const NAMES := ["Piedra", "Celestial", "Dorado"]


static func _mat(col: Color, rough := 0.9, metal := 0.0, emis := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = energy
	return m


static func _box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, collide := false, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		sb.position = pos
		sb.rotation = rot
		sb.add_child(cs)
		parent.add_child(sb)
	return mi


static func _sphere(parent: Node3D, pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Bloques a lo largo del semicírculo de radio interior `r_in`, centrado en (0, cy).
static func _arch(parent: Node3D, cy: float, r_in: float, thick: float, depth: float, n: int, mats: Array, rng: RandomNumberGenerator, jitter := 0.0) -> void:
	var r_mid := r_in + thick * 0.5
	var arc := PI * r_mid / float(n)
	for i in n:
		var a := PI * (float(i) + 0.5) / float(n)
		var th := thick * (1.0 + rng.randf_range(-jitter, jitter))
		var pos := Vector3(cos(a) * (r_in + th * 0.5), cy + sin(a) * (r_in + th * 0.5), rng.randf_range(-0.03, 0.03) * jitter * 10.0)
		_box(parent, pos, Vector3(arc * 1.06, th, depth), mats[rng.randi() % mats.size()], i == n / 2 or i == 0 or i == n - 1, Vector3(0, 0, a + PI * 0.5))


static func build(frame: Node3D, style: int, w: float, h: float) -> Dictionary:
	match style:
		CELESTIAL:
			return _celestial(frame, w, h)
		GOLDEN:
			return _golden(frame, w, h)
	return _stone(frame, w, h)


# ------------------------------------------------------------------ 0 piedra
static func _stone(frame: Node3D, w: float, h: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 84869
	var r := w * 0.5
	var thick := 0.5 * clampf(w / 2.6, 0.7, 1.0) + 0.1
	var depth := 0.55
	var mats := [_mat(Color(0.50, 0.36, 0.24), 1.0), _mat(Color(0.45, 0.32, 0.21), 1.0), _mat(Color(0.55, 0.40, 0.27), 1.0)]
	var carve := _mat(Color(0.16, 0.10, 0.07), 1.0)
	var moss := _mat(Color(0.42, 0.38, 0.17), 1.0)
	var straight := h - r
	# jambas: bloques apilados de alturas distintas
	for side in [-1.0, 1.0]:
		var x: float = side * (r + thick * 0.5)
		var y := 0.0
		while y < straight - 0.05:
			var bh := minf(rng.randf_range(0.7, 1.2), straight - y)
			var bw := thick * rng.randf_range(0.94, 1.06)
			_box(frame, Vector3(x + rng.randf_range(-0.03, 0.03), y + bh * 0.5, 0), Vector3(bw, bh, depth * rng.randf_range(0.92, 1.05)), mats[rng.randi() % 3], true)
			# signos tallados en la cara
			for k in rng.randi_range(2, 4):
				var gy := y + rng.randf_range(0.12, bh - 0.12)
				var gx: float = x + rng.randf_range(-thick * 0.25, thick * 0.25)
				var vertical := rng.randf() < 0.5
				var sz := Vector3(0.05, rng.randf_range(0.1, 0.24), 0.03) if vertical else Vector3(rng.randf_range(0.08, 0.2), 0.05, 0.03)
				_box(frame, Vector3(gx, gy, depth * 0.5 + 0.005), sz, carve)
			y += bh
	_arch(frame, straight, r, thick, depth, 13, mats, rng, 0.08)
	# matas secas en la base y sobre el arco
	for i in 14:
		var side := -1.0 if i % 2 == 0 else 1.0
		var gx := side * (r + thick * rng.randf_range(0.1, 0.9))
		_box(frame, Vector3(gx, 0.12, rng.randf_range(-0.2, 0.25)), Vector3(0.035, rng.randf_range(0.2, 0.4), 0.035), moss, false, Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)))
	for i in 9:
		var a := rng.randf_range(0.5, 2.6)
		_box(frame, Vector3(cos(a) * (r + thick * 0.8), straight + sin(a) * (r + thick * 0.8), 0.2), Vector3(0.035, rng.randf_range(0.2, 0.4), 0.035), moss, false, Vector3(0, 0, a - PI * 0.5 + rng.randf_range(-0.6, 0.6)))
	return {"light": Color(0.72, 0.82, 1.0), "energy": 2.2, "spill": Color(0.75, 0.85, 1.0)}


# ------------------------------------------------------------------ 1 celestial
static func _celestial(frame: Node3D, w: float, h: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 84870
	var r := w * 0.5
	var thick := 0.36
	var depth := 0.46
	var pearl := _mat(Color(0.94, 0.88, 0.9), 0.35, 0.1, Color(1.0, 0.85, 0.8), 0.18)
	var pearl2 := _mat(Color(0.88, 0.8, 0.84), 0.4, 0.1, Color(1.0, 0.8, 0.78), 0.15)
	var gold := _mat(Color(0.96, 0.78, 0.45), 0.3, 0.8, Color(1.0, 0.75, 0.4), 0.7)
	var peach := _mat(Color(1.0, 0.8, 0.62), 0.5, 0.0, Color(1.0, 0.7, 0.45), 1.4)
	var gem := _mat(Color(1.0, 0.2, 0.4), 0.2, 0.0, Color(1.0, 0.15, 0.4), 3.0)
	var straight := h - r
	for side in [-1.0, 1.0]:
		var x: float = side * (r + thick * 0.5)
		_box(frame, Vector3(x, straight * 0.5, 0), Vector3(thick, straight, depth), pearl, true)
		# columna exterior con capiteles y base
		_box(frame, Vector3(x + side * 0.16, straight * 0.5, 0.02), Vector3(0.16, straight, depth * 0.8), pearl2)
		for k in 4:
			var y := straight * (0.12 + 0.25 * k)
			_box(frame, Vector3(x + side * 0.08, y, depth * 0.5), Vector3(thick + 0.28, 0.1, 0.12), gold)
			_sphere(frame, Vector3(x + side * 0.08, y + 0.14, depth * 0.55), 0.07, gold)
		_box(frame, Vector3(x + side * 0.1, 0.12, 0), Vector3(thick + 0.4, 0.24, depth + 0.16), pearl2)
		# hojas de filigrana en el borde interior
		var y2 := 0.3
		while y2 < straight:
			_sphere(frame, Vector3(side * (r - 0.02), y2, 0.05), rng.randf_range(0.045, 0.08), peach)
			y2 += rng.randf_range(0.16, 0.26)
	_arch(frame, straight, r, thick, depth, 15, [pearl, pearl2], rng, 0.0)
	_arch(frame, straight, r + thick, 0.1, depth * 1.2, 15, [gold], rng, 0.0)
	for i in 26:
		var a := PI * (float(i) + 0.5) / 26.0
		_sphere(frame, Vector3(cos(a) * (r - 0.02), straight + sin(a) * (r - 0.02), 0.05), rng.randf_range(0.04, 0.075), peach)
	# corona: gema rosa con aro dorado y volutas
	var top := straight + r + thick + 0.1
	_sphere(frame, Vector3(0, top + 0.12, depth * 0.4), 0.15, gem)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.17
	tm.outer_radius = 0.26
	ring.mesh = tm
	ring.material_override = gold
	ring.position = Vector3(0, top + 0.12, depth * 0.4)
	ring.rotation = Vector3(PI * 0.5, 0, 0)
	frame.add_child(ring)
	_box(frame, Vector3(0, top - 0.05, 0), Vector3(0.5, 0.2, depth), pearl)
	for side in [-1.0, 1.0]:
		for k in 4:
			var a := 0.5 + 0.3 * k
			_box(frame, Vector3(side * (0.3 + 0.22 * k), top + 0.02 + 0.1 * sin(a * 2.0), depth * 0.35), Vector3(0.22, 0.05, 0.05), gold, false, Vector3(0, 0, side * (0.35 - 0.25 * k) * 0.8))
		_sphere(frame, Vector3(side * 1.15, top + 0.18, depth * 0.35), 0.06, gold)
	return {"light": Color(1.0, 0.86, 0.62), "energy": 2.6, "spill": Color(1.0, 0.88, 0.62)}


# ------------------------------------------------------------------ 2 dorado
static func _golden(frame: Node3D, w: float, h: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 84871
	var r := w * 0.5
	var thick := 0.34
	var depth := 0.62
	var rock := _mat(Color(0.30, 0.20, 0.09), 0.95, 0.0, Color(0.55, 0.36, 0.1), 0.25)
	var rock2 := _mat(Color(0.24, 0.16, 0.08), 0.95, 0.0, Color(0.5, 0.32, 0.08), 0.2)
	var gold := _mat(Color(0.95, 0.72, 0.28), 0.3, 0.9, Color(1.0, 0.68, 0.2), 0.9)
	var straight := h - r
	for side in [-1.0, 1.0]:
		# pilar de roca: tramos que se angostan hacia arriba, con bordes dorados
		var y := 0.0
		var n := 8
		for k in n:
			var seg := straight / float(n)
			var pw := (0.78 - 0.18 * float(k) / float(n)) * rng.randf_range(0.92, 1.12)
			var x: float = side * (r + thick + pw * 0.5 - 0.1)
			_box(frame, Vector3(x + rng.randf_range(-0.05, 0.05), y + seg * 0.5, 0), Vector3(pw, seg * 1.02, depth * rng.randf_range(0.9, 1.15)), rock if k % 2 == 0 else rock2, true)
			_box(frame, Vector3(x - side * pw * 0.45, y + seg * 0.5, depth * 0.5 + 0.01), Vector3(0.05, seg * 0.9, 0.04), gold)
			y += seg
		_box(frame, Vector3(side * (r + thick * 0.5), straight * 0.5, 0), Vector3(thick, straight, depth * 0.8), gold, true)
	_arch(frame, straight, r, thick, depth * 0.8, 15, [gold], rng, 0.0)
	_arch(frame, straight, r + thick, 0.16, depth, 15, [rock], rng, 0.1)
	# escalera de luz en el piso, hacia afuera
	var step := _mat(Color(1.0, 0.8, 0.35), 0.4, 0.6, Color(1.0, 0.75, 0.3), 1.8)
	for i in 8:
		_box(frame, Vector3(0, 0.02, depth * 0.5 + 0.2 + i * 0.42), Vector3(w * (0.95 - 0.04 * i), 0.04, 0.2), step)
	return {"light": Color(1.0, 0.8, 0.45), "energy": 2.8, "spill": Color(1.0, 0.8, 0.4)}

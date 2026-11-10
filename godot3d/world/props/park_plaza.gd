class_name ParkPlaza
extends RefCounted
## Fase 3 — detalles de la plaza central del Parque de Boston, según las fotos de referencia:
##  - Pila (fuente) con muro de cantos rodados, agua, columna con taza y verja verde alrededor, sobre laja hexagonal.
##  - Tarima redonda de dos niveles (peldaños de 0.25 m: el personaje sube sin saltar).
##  - León de piedra echado al pie del pedestal de la estatua.
## Marco local de cada pieza: origen = centro a nivel del andén; el terreno sube hacia +X con pendiente SLOPE,
## por eso los anillos se inclinan (y = SLOPE * x) y las colisiones se inclinan igual.

const SLOPE := 0.04

# Pila
const F_BASIN_R := 1.8      # radio exterior del muro de la pila
const F_BASIN_IN := 1.46    # radio interior
const F_RIM_Y := 0.56
const F_WATER_Y := 0.40
const F_FENCE_R := 2.6
const F_FENCE_H := 0.95
const F_PAVE_R := 3.2
# Tarima
const S_R1 := 3.0           # peldaño inferior
const S_H1 := 0.25
const S_R2 := 2.5           # plataforma
const S_H2 := 0.50

static var _fountain: ArrayMesh
static var _stage: ArrayMesh
static var _lion: ArrayMesh


# ------------------------------------------------------------------ utilidades
static func _ring(r: float, y: float, n := 44) -> PackedVector3Array:
	var row := PackedVector3Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		var x := cos(a) * r
		row.append(Vector3(x, SLOPE * x + y, sin(a) * r))
	return row


## Cara plana (anillo r0..r1 a altura y, siguiendo la pendiente), normal hacia arriba.
static func _flat(k: McKit, s: String, m: Material, r0: float, r1: float, y: float) -> void:
	var below := Vector3(0, -50, 0)
	k.grid(s, m, [_ring(maxf(r0, 0.02), y), _ring(r1, y)], true, false, [below, below])


## Pared cilíndrica de y0 a y1 (hacia afuera) o interior si inward.
static func _wall(k: McKit, s: String, m: Material, r: float, y0: float, y1: float, inward := false) -> void:
	k.grid(s, m, [_ring(r, y0), _ring(r, y1)], true, inward)


static func _water_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.27, 0.24, 0.9)
	m.roughness = 0.05
	m.metallic = 0.0
	m.metallic_specular = 0.9
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _jet_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	m.roughness = 0.1
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.5, 0.65, 0.7)
	m.emission_energy_multiplier = 0.25
	return m


# ------------------------------------------------------------------ pila
static func fountain() -> ArrayMesh:
	if _fountain:
		return _fountain
	var k := McKit.new()
	var hexm := MatPaving.hex_pavers()
	var rock := MatStone.canto_rodado()
	var gran := MatStone.granito()
	var green := MatMetal.green_paint()
	var water := _water_mat()
	# Laja hexagonal alrededor (como en la foto) con aro de ladrillo.
	_flat(k, "laja", hexm, 0.0, F_PAVE_R, 0.026)
	# Muro de cantos rodados, borde de granito, pared interior y fondo.
	_wall(k, "canto", rock, F_BASIN_R, -0.3, F_RIM_Y)
	_flat(k, "granito", gran, F_BASIN_IN, F_BASIN_R, F_RIM_Y)
	_wall(k, "canto_in", rock, F_BASIN_IN, 0.12, F_RIM_Y, true)
	_flat(k, "fondo", rock, 0.0, F_BASIN_IN, 0.12)
	_flat(k, "agua", water, 0.0, F_BASIN_IN - 0.02, F_WATER_Y)
	# Columna central con dos tazas y chorro.
	k.lathe("granito", gran, Transform3D.IDENTITY, [Vector2(0.34, 0.12), Vector2(0.24, 0.3), Vector2(0.15, 0.55),
		Vector2(0.14, 0.95), Vector2(0.22, 1.02), Vector2(0.62, 1.10), Vector2(0.70, 1.22), Vector2(0.64, 1.24)], 20)
	k.lathe("agua", water, Transform3D.IDENTITY, [Vector2(0.0, 1.2), Vector2(0.62, 1.2)], 20)
	k.lathe("granito", gran, Transform3D.IDENTITY, [Vector2(0.10, 1.2), Vector2(0.08, 1.45), Vector2(0.28, 1.55), Vector2(0.32, 1.62), Vector2(0.28, 1.64)], 16)
	k.cyl("chorro", _jet_mat(), Vector3(0, 1.6, 0), Vector3(0, 2.0, 0), 0.035, 0.012, 6, true)
	# Verja verde: dos pasamanos, barrotes y postes con remate (como la del monumento).
	var N := 36
	for ry: float in [F_FENCE_H, 0.16]:
		var pts: Array = []
		var rr: Array = []
		for i in N + 1:
			var a := TAU * float(i) / float(N)
			var x := cos(a) * F_FENCE_R
			pts.append(Vector3(x, SLOPE * x + ry, sin(a) * F_FENCE_R))
			rr.append(0.022 if ry > 0.5 else 0.016)
		k.tube("verja", green, pts, rr, 4, false, Vector3.UP)
	var nb := int(TAU * F_FENCE_R / 0.17)
	for i in nb:
		var a := TAU * float(i) / float(nb)
		var x := cos(a) * F_FENCE_R
		var z := sin(a) * F_FENCE_R
		var b := Vector3(x, SLOPE * x, z)
		if i % 8 == 0:
			var pb := Basis(Vector3.UP, -a)
			k.box("verja", green, Transform3D(pb, b + Vector3(0, F_FENCE_H * 0.5 + 0.03, 0)), Vector3(0.055, F_FENCE_H + 0.06, 0.055), 0.0, "xXzZy")
			k.lathe("verja", green, Transform3D(pb, b + Vector3(0, F_FENCE_H + 0.06, 0)), [Vector2(0.035, 0.0), Vector2(0.038, 0.03), Vector2(0.0, 0.08)], 4, PI * 0.25)
		else:
			k.cyl("verja", green, b + Vector3(0, -0.05, 0), b + Vector3(0, F_FENCE_H + 0.07, 0), 0.009, 0.009, 3, false)
			# punta de lanza
			k.lathe("verja", green, Transform3D(Basis.IDENTITY, b + Vector3(0, F_FENCE_H + 0.07, 0)), [Vector2(0.014, 0.0), Vector2(0.0, 0.05)], 3)
	_fountain = k.commit()
	return _fountain


# ------------------------------------------------------------------ tarima redonda
static func stage() -> ArrayMesh:
	if _stage:
		return _stage
	var k := McKit.new()
	var gran := MatStone.granito()
	var conc := MatPaving.sidewalk_concrete()
	var dark := MatMetal.green_paint()
	# Peldaño inferior (granito) y plataforma (concreto pulido con aro y borde de granito).
	_wall(k, "granito", gran, S_R1, -0.45, S_H1)
	_flat(k, "granito", gran, S_R2 + 0.02, S_R1, S_H1)
	_wall(k, "granito", gran, S_R2, -0.45, S_H2)
	_flat(k, "granito", gran, S_R2 - 0.16, S_R2, S_H2 + 0.004)
	_flat(k, "concreto", conc, 0.0, S_R2 - 0.16, S_H2 + 0.002)
	# Aro y cruz de juntas de dilatación (metal oscuro).
	_flat(k, "aro", dark, S_R2 - 0.62, S_R2 - 0.56, S_H2 + 0.007)
	for ang in [0.0, PI * 0.5]:
		var d := Vector3(cos(ang), 0.0, sin(ang))
		var p0 := d * (S_R2 - 0.62)
		var p1 := -d * (S_R2 - 0.62)
		var side := Vector3(-d.z, 0.0, d.x) * 0.015
		k.quad("aro", dark, Vector3(p0.x, SLOPE * p0.x + S_H2 + 0.007, p0.z) - side, Vector3(p1.x, SLOPE * p1.x + S_H2 + 0.007, p1.z) - side,
			Vector3(p1.x, SLOPE * p1.x + S_H2 + 0.007, p1.z) + side, Vector3(p0.x, SLOPE * p0.x + S_H2 + 0.007, p0.z) + side, Vector3.UP)
	_stage = k.commit()
	return _stage


# ------------------------------------------------------------------ león de piedra
## León echado, ~1.5 m de largo, mirando a +Z (frente sur del pedestal). Origen = apoyo, centro.
static func lion() -> ArrayMesh:
	if _lion:
		return _lion
	var k := McKit.new()
	var st := MatStone.marmol_sucio()
	var S := "leon"
	# Cuerpo, cuarto trasero y pecho.
	k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(0, 0.34, -0.18)), Vector3(0.30, 0.26, 0.55), 12, 8)
	k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(0, 0.30, -0.52)), Vector3(0.32, 0.28, 0.30), 12, 8)
	k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(0, 0.40, 0.22)), Vector3(0.27, 0.29, 0.30), 12, 8)
	# Melena y cabeza erguida.
	k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(0, 0.56, 0.36)), Vector3(0.34, 0.34, 0.26), 12, 8)
	k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0.50)), Vector3(0.20, 0.20, 0.20), 12, 8)
	k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0.66)), Vector3(0.11, 0.09, 0.13), 8, 6)
	for sx: float in [-1.0, 1.0]:
		k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(sx * 0.13, 0.74, 0.44)), Vector3(0.05, 0.05, 0.04), 6, 4)   # orejas
		# Patas delanteras estiradas y traseras recogidas.
		k.cyl(S, st, Vector3(sx * 0.14, 0.17, 0.30), Vector3(sx * 0.14, 0.05, 0.70), 0.075, 0.07, 8, true)
		k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(sx * 0.14, 0.05, 0.74)), Vector3(0.09, 0.05, 0.11), 8, 5)
		k.ellipsoid(S, st, Transform3D(Basis.IDENTITY, Vector3(sx * 0.27, 0.12, -0.50)), Vector3(0.10, 0.12, 0.22), 8, 6)
	# Cola enroscada junto al costado.
	k.tube(S, st, [Vector3(0.0, 0.25, -0.85), Vector3(0.22, 0.12, -0.95), Vector3(0.34, 0.08, -0.70), Vector3(0.30, 0.07, -0.45)],
		[0.045, 0.04, 0.04, 0.06], 6, true, Vector3.UP)
	_lion = k.commit()
	return _lion


# ------------------------------------------------------------------ colocación
## Colisión inclinada con el terreno (cilindro cuya cara superior sigue la pendiente).
static func _tilt() -> Basis:
	return Basis(Vector3(0, 0, 1), atan(SLOPE))


static func build_fountain(d: Node, p: Vector3) -> void:
	var xf := Transform3D(Basis.IDENTITY, p)
	d.place_mesh("p3_fountain", fountain(), xf, true)
	d.add_col_cyl_xf(Transform3D(_tilt(), p + Vector3(0, 0.45, 0)), F_FENCE_R + 0.05, 1.3)


static func build_stage(d: Node, p: Vector3) -> void:
	var xf := Transform3D(Basis.IDENTITY, p)
	d.place_mesh("p3_stage", stage(), xf, true)
	var t := _tilt()
	d.add_col_cyl_xf(Transform3D(t, p + t * Vector3(0, (S_H1 - 0.45) * 0.5, 0)), S_R1, S_H1 + 0.45)
	d.add_col_cyl_xf(Transform3D(t, p + t * Vector3(0, (S_H2 - 0.45) * 0.5, 0)), S_R2, S_H2 + 0.45)


static func build_lion(d: Node, p: Vector3, yaw := 0.0) -> void:
	d.place_mesh("p3_lion", lion(), Transform3D(Basis(Vector3.UP, yaw), p), true)

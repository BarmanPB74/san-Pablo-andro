class_name Monument
extends RefCounted
## Monumento a José María Córdova, Parque de Boston (refs. /tmp/refs/2 y 5).
## Figura DE PIE en bronce oscuro (militar de la Independencia: casaca larga con faldones, charreteras,
## cuello alto, botas altas, sable envainado al cinto, brazo derecho levantado señalando al frente)
## sobre pedestal alto de mármol blanco (base escalonada, dado con placa y molduras, cuerpo esbelto
## arriba), rodeado de un seto redondo bajo, bordillo de granito y reja baja verde.
## Figura genérica de época (no es un retrato). Marco local: origen = pie del pedestal (0,0,0 del mapa),
## la figura mira a +Z (sur, hacia el spawn del jugador).
## Mallas cacheadas en static var; ver build() para colocación y colisiones.

const PED_TOP := 4.28              # altura del tope del pedestal (m)
const FIG_H := 2.5                 # altura de la figura (m)
const FIG_S := FIG_H / 1.8         # la figura se modela con proporciones humanas de 1.8 m
const HEDGE_IN := 2.45
const HEDGE_OUT := 3.75
const CURB_R := 4.0
const FENCE_R := 4.15

static var _ped: ArrayMesh
static var _fig: ArrayMesh
static var _hedge: ArrayMesh
static var _fence: ArrayMesh


## Coloca todo el monumento con la API del distrito (place_mesh / place_node / colisiones).
static func build(d: Node) -> void:
	var o := Transform3D.IDENTITY
	d.place_mesh("p2mon_pedestal", pedestal(), o, true)
	d.place_mesh("p2mon_figure", figure(), Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * FIG_S), Vector3(0, PED_TOP, 0)), true)
	d.place_mesh("p2mon_hedge", hedge_ring(), o, true)
	d.place_mesh("p2mon_fence", fence(), o, false)
	d.place_node(plaque_label(), Transform3D(Basis.IDENTITY, Vector3(0, 1.72, 1.0 + 0.045)))
	# Colisiones: anillo (reja + seto) y pedestal alto.
	d.add_col_cyl(Vector3(0, 0.5, 0), FENCE_R + 0.05, 1.6)
	d.add_col_box(Transform3D(Basis.IDENTITY, Vector3(0, 2.1, 0)), Vector3(2.4, 4.4, 2.4))


## Bronce oscuro de la foto: misma textura de MatStone.bronce con tinte cálido oscuro (menos verdigrís).
static func bronze_dark() -> Material:
	return TexMat.pbr(MatStone.BASE + "bronce_patina", {"tile_m": 0.8, "tint": Color(0.5, 0.4, 0.33)})


static func _y(x: float) -> float:
	return 0.04 * x   # = BostonDistrict.walk_y(x) (sin dependencia para poder probar aislado)


# ------------------------------------------------------------------ pedestal de mármol
static func pedestal() -> ArrayMesh:
	if _ped:
		return _ped
	var k := McKit.new()
	var dirty := MatStone.marmol_sucio()
	var clean := MatStone.marmol()
	var brz := bronze_dark()
	var o := Transform3D.IDENTITY
	# Gradas + zócalo con moldura de base (mármol sucio: salpicado y roce).
	k.square_lathe("sucio", dirty, o, [
		Vector2(1.78, -0.5), Vector2(1.78, 0.18), Vector2(1.74, 0.22), Vector2(1.52, 0.22),
		Vector2(1.52, 0.40), Vector2(1.48, 0.43), Vector2(1.30, 0.43), Vector2(1.30, 0.62),
		Vector2(1.18, 0.62), Vector2(1.18, 0.74), Vector2(1.13, 0.79), Vector2(1.08, 0.86),
		Vector2(1.03, 0.90), Vector2(1.0, 0.94)], 0.035, false)
	# Dado, cornisa del dado, cuerpo superior esbelto y cornisa de remate.
	k.square_lathe("marmol", clean, o, [
		Vector2(1.0, 0.94), Vector2(1.0, 2.42), Vector2(1.04, 2.46), Vector2(1.08, 2.50),
		Vector2(1.12, 2.56), Vector2(1.15, 2.64), Vector2(1.15, 2.74), Vector2(0.88, 2.74),
		Vector2(0.88, 2.86), Vector2(0.82, 2.90), Vector2(0.76, 2.97), Vector2(0.68, 3.88),
		Vector2(0.72, 3.92), Vector2(0.78, 3.97), Vector2(0.84, 4.04), Vector2(0.88, 4.12),
		Vector2(0.88, 4.22), Vector2(0.84, PED_TOP)], 0.025, true)
	# Pilastras/listeles verticales en las esquinas del dado (dan sombra y lectura de "dado").
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.box("marmol", clean, Transform3D(Basis.IDENTITY, Vector3(sx * 0.93, 1.68, sz * 0.93)), Vector3(0.2, 1.48, 0.2), 0.02, "xXzZ")
	# Paneles rehundidos (marco) en las caras del cuerpo superior.
	for f in 4:
		var b := Basis(Vector3.UP, f * PI * 0.5)
		k.box("marmol", clean, Transform3D(b, b * Vector3(0, 3.42, 0.725)), Vector3(0.9, 0.06, 0.05), 0.015)
		k.box("marmol", clean, Transform3D(b, b * Vector3(0, 3.08, 0.745)), Vector3(1.05, 0.06, 0.05), 0.015)
	# Placa de bronce (frente sur) con marco y tornillos.
	var pz := 1.0
	k.box("bronce", brz, Transform3D(Basis.IDENTITY, Vector3(0, 1.72, pz + 0.012)), Vector3(1.22, 0.62, 0.025), 0.008)
	k.box("bronce", brz, Transform3D(Basis.IDENTITY, Vector3(0, 2.05, pz + 0.02)), Vector3(1.3, 0.045, 0.04), 0.01)
	k.box("bronce", brz, Transform3D(Basis.IDENTITY, Vector3(0, 1.39, pz + 0.02)), Vector3(1.3, 0.045, 0.04), 0.01)
	for sx: float in [-1.0, 1.0]:
		k.box("bronce", brz, Transform3D(Basis.IDENTITY, Vector3(sx * 0.63, 1.72, pz + 0.02)), Vector3(0.045, 0.62, 0.04), 0.01)
		for sy: float in [-1.0, 1.0]:
			k.cyl("bronce", brz, Vector3(sx * 0.55, 1.72 + sy * 0.26, pz + 0.02), Vector3(sx * 0.55, 1.72 + sy * 0.26, pz + 0.038), 0.018, 0.012, 6, true)
	# Coronas de laurel en bronce en las otras tres caras del dado.
	for f in [1, 2, 3]:
		var b := Basis(Vector3.UP, f * PI * 0.5)
		_wreath(k, brz, Transform3D(b, b * Vector3(0, 1.75, pz + 0.01)))
	_ped = k.commit()
	return _ped


static func _wreath(k: McKit, m: Material, xf: Transform3D) -> void:
	# Toro (anillo) + hojas (elipsoides aplanados) + cintas.
	var prof: Array = []
	for i in 7:
		var t := TAU * float(i) / 6.0
		prof.append(Vector2(0.27 + cos(t) * 0.035, sin(t) * 0.035))
	k.lathe("bronce", m, xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.035)), prof, 16)
	for i in 14:
		var a := PI * 0.15 + (PI * 1.7) * float(i) / 13.0
		var p := Vector3(cos(a) * 0.27, sin(a) * 0.27, 0.05)
		var tb := Basis(Vector3.BACK, a + (0.6 if i % 2 == 0 else -0.6))
		k.ellipsoid("bronce", m, xf * Transform3D(tb, p), Vector3(0.025, 0.06, 0.018), 5, 3)
	for s: float in [-1.0, 1.0]:
		k.box("bronce", m, xf * Transform3D(Basis(Vector3.BACK, s * 0.35), Vector3(s * 0.08, -0.36, 0.03)), Vector3(0.05, 0.22, 0.012), 0.004)


static func plaque_label() -> Label3D:
	var l := Label3D.new()
	l.text = "JOSÉ MARÍA CÓRDOVA\n1799 · 1829"
	l.font_size = 52
	l.pixel_size = 0.0024
	l.line_spacing = 6.0
	l.outline_size = 0
	l.modulate = Color(0.86, 0.74, 0.46)
	l.shaded = true
	l.double_sided = false
	l.visibility_range_end = 40.0
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


# ------------------------------------------------------------------ figura de bronce (1.8 m, mira a +Z)
## Secciones del torso: [y, rx, rz, cz].
const _TORSO := [[0.90, 0.165, 0.12, 0.0], [0.98, 0.158, 0.115, 0.0], [1.06, 0.152, 0.108, 0.005],
	[1.18, 0.168, 0.118, 0.015], [1.30, 0.183, 0.124, 0.02], [1.39, 0.198, 0.118, 0.01],
	[1.45, 0.185, 0.105, 0.0], [1.50, 0.12, 0.085, 0.0], [1.535, 0.062, 0.06, 0.005]]


static func _torso_front(y: float) -> float:
	for i in _TORSO.size() - 1:
		var a: Array = _TORSO[i]
		var b: Array = _TORSO[i + 1]
		if y >= a[0] and y <= b[0]:
			var t: float = (y - a[0]) / (b[0] - a[0])
			return lerpf(a[2] + a[3], b[2] + b[3], t)
	return 0.12


static func figure() -> ArrayMesh:
	if _fig:
		return _fig
	var k := McKit.new()
	var m := bronze_dark()
	var S := "bronce"
	# Peana de bronce con borde biselado y terreno irregular.
	k.box(S, m, Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0.02)), Vector3(0.78, 0.07, 0.66), 0.02)
	k.ellipsoid(S, m, Transform3D(Basis.IDENTITY, Vector3(0.12, 0.015, 0.12)), Vector3(0.2, 0.03, 0.16), 7, 3)
	# ---- Piernas (pantalón) y botas altas de montar.
	_leg(k, m, Vector3(-0.1, 0.92, -0.01), Vector3(-0.125, 0.5, -0.01), Vector3(-0.145, 0.085, -0.03), Vector3(-0.2, 0, 1))
	_leg(k, m, Vector3(0.1, 0.92, 0.0), Vector3(0.17, 0.51, 0.12), Vector3(0.2, 0.09, 0.08), Vector3(0.4, 0, 1))
	# ---- Torso (casaca ceñida) con hombros anchos.
	var rows: Array = []
	var cens: Array = []
	for s: Array in _TORSO:
		var row := PackedVector3Array()
		for j in 14:
			var a := TAU * float(j) / 14.0
			row.append(Vector3(cos(a) * s[1], s[0], sin(a) * s[2] + s[3]))
		rows.append(row)
		cens.append(Vector3(0, s[0], s[3]))
	k.grid(S, m, rows, true, false, cens)
	# Faldones (levita larga abierta adelante, pliegues hacia el ruedo; cara exterior e interior).
	_skirt(k, m)
	# Fajín/cinturón y hebilla.
	k.lathe(S, m, Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0.004)), [Vector2(0.150, 0.0), Vector2(0.162, 0.008), Vector2(0.162, 0.062), Vector2(0.150, 0.07)], 14, 0.0, 1.0, 0.74)
	k.box(S, m, Transform3D(Basis.IDENTITY, Vector3(0, 1.035, 0.126)), Vector3(0.06, 0.05, 0.02), 0.006)
	# Solapas cruzadas y doble botonadura.
	for sx: float in [-1.0, 1.0]:
		var lb := Basis(Vector3.BACK, sx * 0.22) * Basis(Vector3.RIGHT, -0.12)
		k.box(S, m, Transform3D(lb, Vector3(sx * 0.055, 1.33, _torso_front(1.33) + 0.004)), Vector3(0.075, 0.26, 0.016), 0.006)
		for i in 5:
			var y := 1.11 + 0.055 * i
			k.ellipsoid(S, m, Transform3D(Basis.IDENTITY, Vector3(sx * (0.045 + 0.006 * i), y, _torso_front(y) + 0.003)), Vector3(0.011, 0.011, 0.008), 5, 3)
	# Cuello alto militar y charreteras con fleco.
	k.lathe(S, m, Transform3D(Basis.IDENTITY, Vector3(0, 1.52, 0.004)), [Vector2(0.074, 0.0), Vector2(0.072, 0.075), Vector2(0.062, 0.082)], 12)
	for sx: float in [-1.0, 1.0]:
		var ep := Vector3(sx * 0.19, 1.455, 0.0)
		k.ellipsoid(S, m, Transform3D(Basis(Vector3.BACK, sx * 0.3), ep + Vector3(0, 0.018, 0)), Vector3(0.075, 0.022, 0.07), 9, 3)
		k.tube(S, m, [ep + Vector3(sx * 0.012, 0.0, 0), ep + Vector3(sx * 0.03, -0.055, 0)], [0.07, 0.08], 12, false, Vector3(0, 0, 1), 0.08, 9)
	# ---- Brazos. Izquierdo (+X) apoyado en la empuñadura del sable; derecho (-X) levantado señalando.
	var sc_top := Vector3(0.205, 0.93, 0.085)
	var sc_dir := Vector3(0.07, -0.74, -0.38).normalized()
	var grip_end := sc_top - sc_dir * 0.15
	var l_wrist := grip_end + Vector3(0.012, 0.035, -0.02)
	_arm(k, m, Vector3(0.195, 1.42, 0.0), Vector3(0.275, 1.17, -0.05), l_wrist, Vector3(0, 0, 1), false)
	_arm(k, m, Vector3(-0.195, 1.42, 0.01), Vector3(-0.31, 1.58, 0.17), Vector3(-0.4, 1.79, 0.37), Vector3(0, 0, 1), true)
	# Sable: vaina curva, guarda en cazoleta, empuñadura y pomo.
	var sc_pts: Array = []
	var sc_r: Array = []
	for i in 6:
		var t := float(i) / 5.0
		sc_pts.append(sc_top + sc_dir * (0.82 * t) + Vector3(0, 0, -0.05) * t * t)
		sc_r.append(Vector2(0.022, 0.012) * (1.0 - 0.25 * t))
	k.tube(S, m, sc_pts, sc_r, 6, true, Vector3(1, 0, 0))
	k.lathe(S, m, Transform3D(_basis_y(-sc_dir), sc_top), [Vector2(0.01, -0.005), Vector2(0.045, 0.0), Vector2(0.048, 0.012), Vector2(0.03, 0.03)], 8)
	k.tube(S, m, [sc_top - sc_dir * 0.025, grip_end], [0.013, 0.011], 6, true, Vector3(1, 0, 0))
	k.ellipsoid(S, m, Transform3D(Basis.IDENTITY, grip_end - sc_dir * 0.012), Vector3(0.017, 0.017, 0.017), 6, 3)
	# Tiros del tahalí (correas) del cinturón a la vaina.
	k.tube(S, m, [Vector3(0.15, 1.0, 0.04), sc_top + sc_dir * 0.12 + Vector3(0.02, 0, 0)], [0.006, 0.006], 4, false)
	k.tube(S, m, [Vector3(0.155, 1.0, -0.06), sc_top + sc_dir * 0.3 + Vector3(0.02, 0, 0)], [0.006, 0.006], 4, false)
	# ---- Cabeza (girada levemente hacia la mano que señala).
	_head(k, m, Transform3D((Basis(Vector3.UP, -0.28) * Basis(Vector3.RIGHT, -0.08)).scaled(Vector3.ONE * 1.13), Vector3(0, 1.585, 0.012)))
	_fig = k.commit()
	return _fig


static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.BACK)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())


static func _leg(k: McKit, m: Material, hip: Vector3, knee: Vector3, ankle: Vector3, toe_dir: Vector3) -> void:
	var S := "bronce"
	# Muslo y pantorrilla (pantalón ajustado de montar).
	k.tube(S, m, [hip, hip.lerp(knee, 0.5), knee], [0.1, 0.088, 0.066], 10, false, Vector3(0, 0, 1))
	# Bota alta: caña con boca acampanada bajo la rodilla, tobillo y pie con puntera y tacón.
	var top := knee + (ankle - knee) * 0.04
	var calf := knee.lerp(ankle, 0.35)
	k.tube(S, m, [top + (knee - ankle).normalized() * 0.05, top, calf, knee.lerp(ankle, 0.75), ankle], [0.08, 0.077, 0.071, 0.056, 0.05], 10, true, Vector3(0, 0, 1))
	var td := toe_dir.normalized()
	var heel := ankle + Vector3(0, -0.045, 0) - td * 0.06
	var toe := ankle + Vector3(0, -0.06, 0) + td * 0.17
	k.tube(S, m, [heel, ankle + Vector3(0, -0.035, 0) + td * 0.04, toe - td * 0.03, toe], [Vector2(0.042, 0.045), Vector2(0.048, 0.05), Vector2(0.042, 0.028), Vector2(0.018, 0.012)], 8, true, Vector3.UP)
	k.box(S, m, Transform3D(_basis_y(Vector3.UP) * Basis(Vector3.UP, atan2(td.x, td.z)), heel + Vector3(0, -0.025, 0)), Vector3(0.07, 0.04, 0.07), 0.008)


static func _skirt(k: McKit, m: Material) -> void:
	var S := "bronce"
	var outer: Array = []
	var inner: Array = []
	var cens: Array = []
	var n_rows := 6
	var n_cols := 15
	for i in n_rows + 1:
		var t := float(i) / float(n_rows)      # 0 = cintura, 1 = ruedo
		var y := lerpf(1.04, 0.56, t)
		var rx := lerpf(0.158, 0.29, pow(t, 0.8))
		var rz := lerpf(0.112, 0.21, pow(t, 0.8))
		var open := lerpf(0.30, 0.95, t)          # semiapertura frontal (rad), corte en diagonal
		var ro := PackedVector3Array()
		var ri := PackedVector3Array()
		for j in n_cols + 1:
			var u := float(j) / float(n_cols)
			var a := PI * 0.5 + open + (TAU - 2.0 * open) * u
			var fold := 1.0 + 0.07 * t * sin(u * TAU * 4.0 + 0.6)
			var back := 0.5 - 0.5 * sin(a)     # 1 atrás, 0 adelante: el faldón cae más atrás
			var yy := y - 0.06 * t * back + 0.03 * t * (1.0 - back)
			var p := Vector3(cos(a) * rx * fold, yy, sin(a) * rz * fold + 0.01)
			ro.append(p)
			ri.append(Vector3(cos(a) * (rx * fold - 0.014), yy, sin(a) * (rz * fold - 0.014) + 0.01))
		outer.append(ro)
		inner.append(ri)
		cens.append(Vector3(0, y, 0.01))
	k.grid(S, m, outer, false, false, cens)
	k.grid(S, m, inner, false, true, cens)
	# Ruedo y bordes del corte (cierran el grosor).
	var last_o: PackedVector3Array = outer[n_rows]
	var last_i: PackedVector3Array = inner[n_rows]
	for j in n_cols:
		k.quad(S, m, last_o[j], last_o[j + 1], last_i[j + 1], last_i[j], Vector3.DOWN)
	for i in n_rows:
		for e in [0, n_cols]:
			var a: Vector3 = outer[i][e]
			var b: Vector3 = outer[i + 1][e]
			var c: Vector3 = inner[i + 1][e]
			var d: Vector3 = inner[i][e]
			var mid := (a + b) * 0.5
			var nrm := (b - a).cross(d - a).normalized()
			if nrm.dot(Vector3(0, 0, 1)) < 0.0:
				nrm = -nrm
			k.quad(S, m, a, b, c, d, nrm if mid.z > -1.0 else -nrm)


static func _arm(k: McKit, m: Material, sh: Vector3, el: Vector3, wr: Vector3, hint: Vector3, pointing: bool) -> void:
	var S := "bronce"
	# Manga con pliegues en el codo y bocamanga (puño de la casaca).
	k.tube(S, m, [sh + Vector3(0, 0.02, 0), sh.lerp(el, 0.5), el, el.lerp(wr, 0.5), wr], [0.078, 0.072, 0.064, 0.056, 0.05], 9, true, hint, 0.05, 3)
	var fd := (wr - el).normalized()
	k.tube(S, m, [wr - fd * 0.06, wr + fd * 0.005], [0.056, 0.058], 9, false, hint)
	# Mano.
	if pointing:
		# Palma abierta hacia adelante-arriba, dedos juntos con el índice más largo.
		var hb := _basis_y(fd)
		var palm := wr + fd * 0.06
		k.ellipsoid(S, m, Transform3D(hb, palm), Vector3(0.042, 0.055, 0.02), 7, 4)
		k.tube(S, m, [palm + fd * 0.04 + hb.x * 0.01, palm + fd * 0.13 + hb.x * 0.012], [0.013, 0.01], 5, true, hint)
		for f in 3:
			var off := hb.x * (-0.012 - 0.013 * f)
			k.tube(S, m, [palm + fd * 0.04 + off, palm + fd * (0.1 - 0.012 * f) + off - hb.z * 0.01], [0.012, 0.009], 5, true, hint)
		k.tube(S, m, [palm + hb.x * 0.035 - fd * 0.01, palm + hb.x * 0.06 + fd * 0.04], [0.012, 0.01], 5, true, hint)
	else:
		k.ellipsoid(S, m, Transform3D(_basis_y(fd), wr + fd * 0.05 + Vector3(0, 0.0, 0.0)), Vector3(0.045, 0.06, 0.04), 7, 4)


static func _head(k: McKit, m: Material, hx: Transform3D) -> void:
	var S := "bronce"
	# Cuello.
	k.tube(S, m, [hx * Vector3(0, -0.04, -0.005), hx * Vector3(0, 0.05, 0.0)], [0.048, 0.046], 8, false, hx.basis.z)
	# Cráneo y cara (perfil con mentón y pómulos).
	var prof := [[0.03, 0.03, 0.035, 0.03], [0.045, 0.058, 0.06, 0.035], [0.075, 0.072, 0.085, 0.03],
		[0.105, 0.078, 0.095, 0.022], [0.14, 0.082, 0.1, 0.012], [0.17, 0.08, 0.098, 0.005],
		[0.2, 0.07, 0.085, 0.0], [0.225, 0.048, 0.06, -0.005], [0.238, 0.0, 0.0, -0.005]]
	var rows: Array = []
	var cens: Array = []
	for s: Array in prof:
		var row := PackedVector3Array()
		for j in 12:
			var a := TAU * float(j) / 12.0
			var fwd := sin(a)
			var rz: float = s[2] * (1.0 if fwd < 0.0 else 1.0 + 0.08 * fwd)   # la cara es más prominente
			row.append(hx * Vector3(cos(a) * s[1], s[0], sin(a) * rz + s[3]))
		rows.append(row)
		cens.append(hx * Vector3(0, s[0], s[3]))
	k.grid(S, m, rows, true, false, cens)
	# Nariz, cejas y orejas.
	k.tube(S, m, [hx * Vector3(0, 0.15, 0.104), hx * Vector3(0, 0.118, 0.13), hx * Vector3(0, 0.106, 0.122)], [0.012, 0.016, 0.012], 5, true, hx.basis.y)
	k.box(S, m, hx * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.162, 0.097)), Vector3(0.11, 0.016, 0.02), 0.006)
	for sx: float in [-1.0, 1.0]:
		k.ellipsoid(S, m, hx * Transform3D(Basis.IDENTITY, Vector3(sx * 0.081, 0.135, 0.0)), Vector3(0.012, 0.028, 0.02), 5, 3)
	# Cabello abundante peinado hacia adelante (época): casquete + mechones + patillas largas.
	k.ellipsoid(S, m, hx * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.19, -0.012)), Vector3(0.09, 0.062, 0.1), 10, 5)
	var tufts := [Vector3(0.0, 0.222, 0.055), Vector3(0.04, 0.215, 0.062), Vector3(-0.04, 0.215, 0.062),
		Vector3(0.058, 0.19, -0.035), Vector3(-0.058, 0.19, -0.035), Vector3(0.0, 0.16, -0.085), Vector3(0.042, 0.14, -0.072), Vector3(-0.042, 0.14, -0.072)]
	for i in tufts.size():
		var tp: Vector3 = tufts[i]
		k.ellipsoid(S, m, hx * Transform3D(Basis(Vector3.UP, i * 0.9) * Basis(Vector3.RIGHT, 0.5), tp), Vector3(0.03, 0.02, 0.038), 6, 3)
	for sx: float in [-1.0, 1.0]:
		k.ellipsoid(S, m, hx * Transform3D(Basis(Vector3.BACK, sx * 0.1), Vector3(sx * 0.078, 0.11, 0.035)), Vector3(0.012, 0.045, 0.022), 5, 3)


# ------------------------------------------------------------------ seto redondo, bordillo, cama de hiedra
static func hedge_ring() -> ArrayMesh:
	if _hedge:
		return _hedge
	var k := McKit.new()
	var hedge := MatFoliage.hedge(Color(0.72, 0.8, 0.66))
	var ivy := MatFoliage.ivy_ground()
	var gran := MatStone.granito()
	var N := 56
	# Seto: sección "caja recortada" redondeada, con bultos irregulares.
	var sec := [Vector2(0.0, -0.25), Vector2(0.02, 0.35), Vector2(0.06, 0.6), Vector2(0.16, 0.72), Vector2(0.5, 0.76),
		Vector2(0.84, 0.72), Vector2(0.94, 0.6), Vector2(0.98, 0.35), Vector2(1.0, -0.25)]
	var rows: Array = []
	var cens: Array = []
	var w := HEDGE_OUT - HEDGE_IN
	for i in N + 1:
		var a := TAU * float(i % N) / float(N)
		var dir := Vector3(cos(a), 0, sin(a))
		var row := PackedVector3Array()
		var bump := 0.04 * sin(a * 7.0) + 0.03 * sin(a * 13.0 + 1.3)
		for j in sec.size():
			var s: Vector2 = sec[j]
			var r := HEDGE_IN + s.x * w
			var hy := s.y
			if s.y > 0.3:
				hy += bump + 0.025 * sin(a * 23.0 + j)
				r += (bump * 0.6 if s.x > 0.5 else -bump * 0.6)
			var p := dir * r
			p.y = hy + _y(p.x)
			row.append(p)
		# El polígono de sección se cierra por abajo (bajo el piso).
		rows.append(row)
		var c := dir * (HEDGE_IN + w * 0.5)
		cens.append(Vector3(c.x, 0.2 + _y(c.x), c.z))
	# grid: filas = cortes angulares, columnas = sección (abierta).
	k.grid("seto", hedge, rows, false, false, cens)
	# Cama de hiedra entre el pedestal y el seto (disco), un poco elevada.
	for i in N:
		var a0 := TAU * float(i) / float(N)
		var a1 := TAU * float(i + 1) / float(N)
		var r0 := 1.5
		var r1 := HEDGE_IN + 0.05
		var P := func(r: float, a: float) -> Vector3:
			var x := cos(a) * r
			return Vector3(x, 0.14 + _y(x), sin(a) * r)
		k.quad("hiedra", ivy, P.call(r0, a0), P.call(r1, a0), P.call(r1, a1), P.call(r0, a1), Vector3.UP)
	# Bordillo de granito con chaflán (anillo).
	var cprof := [Vector2(HEDGE_OUT + 0.02, 0.1), Vector2(HEDGE_OUT + 0.02, 0.2), Vector2(HEDGE_OUT + 0.05, 0.23),
		Vector2(CURB_R - 0.03, 0.23), Vector2(CURB_R, 0.2), Vector2(CURB_R, -0.3)]
	for i in N:
		var a0 := TAU * float(i) / float(N)
		var a1 := TAU * float(i + 1) / float(N)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		for j in cprof.size() - 1:
			var p0: Vector2 = cprof[j]
			var p1: Vector2 = cprof[j + 1]
			var n2 := Vector2(p1.y - p0.y, -(p1.x - p0.x)).normalized()
			# Orientación: hacia afuera del perfil (centro del perfil en r medio, y bajo).
			var mid := (p0 + p1) * 0.5
			var pc := Vector2((HEDGE_OUT + CURB_R) * 0.5, 0.0)
			if n2.dot(mid - pc) < 0.0:
				n2 = -n2
			var dm := (d0 + d1).normalized()
			var nn := (dm * n2.x + Vector3.UP * n2.y).normalized()
			var Q := func(d: Vector3, p: Vector2) -> Vector3:
				var v := d * p.x
				v.y = p.y + _y(v.x)
				return v
			k.quad("granito", gran, Q.call(d0, p0), Q.call(d1, p0), Q.call(d1, p1), Q.call(d0, p1), nn)
	_hedge = k.commit()
	return _hedge


# ------------------------------------------------------------------ reja baja verde
static func fence() -> ArrayMesh:
	if _fence:
		return _fence
	var k := McKit.new()
	var g := MatMetal.green_paint()
	var S := "verde"
	var H := 0.62
	var N := 40
	# Pasamanos superior e inferior (tubos poligonales cerrados).
	for ry: float in [H, 0.14]:
		var pts: Array = []
		var rr: Array = []
		for i in N + 1:
			var a := TAU * float(i) / float(N)
			var x := cos(a) * FENCE_R
			pts.append(Vector3(x, ry + _y(x), sin(a) * FENCE_R))
			rr.append(0.02 if ry > 0.5 else 0.015)
		k.tube(S, g, pts, rr, 4, false, Vector3.UP)
	# Barrotes delgados (prisma triangular, sin tapas) y postes cuadrados con remate.
	var nb := int(TAU * FENCE_R / 0.19)
	for i in nb:
		var a := TAU * float(i) / float(nb)
		var x := cos(a) * FENCE_R
		var z := sin(a) * FENCE_R
		var b := Vector3(x, _y(x), z)
		if i % 8 == 0:
			var pb := Basis(Vector3.UP, -a)
			k.box(S, g, Transform3D(pb, b + Vector3(0, H * 0.5 + 0.02, 0)), Vector3(0.05, H + 0.04, 0.05), 0.0, "xXzZy")
			k.lathe(S, g, Transform3D(pb, b + Vector3(0, H + 0.04, 0)), [Vector2(0.032, 0.0), Vector2(0.035, 0.03), Vector2(0.0, 0.07)], 4, PI * 0.25)
		else:
			k.cyl(S, g, b + Vector3(0, -0.05, 0), b + Vector3(0, H + 0.06, 0), 0.009, 0.009, 3, false)
	_fence = k.commit()
	return _fence

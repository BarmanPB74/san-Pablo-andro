class_name AndroCloak
extends Node3D
## Andro (ref. 84070): una forma de tela negra SIN rasgos humanos (sin cabeza, cuello, hombros ni brazos).
## Diseño: una esfera mayor INVISIBLE (campo de fuerza) cubierta por una cúpula lisa de tela. De ella cae una capa
## interior larga (dobladillo en puntas) y, encima, un manto exterior abierto al frente (la abertura nace en la cúpula y se
## cierra hacia abajo) con ribetes ornamentados en los bordes y en el dobladillo. Nada puede tocar la tela: el campo de
## fuerza es la cápsula de colisión del jugador (Player.CAPSULE_RADIUS) y las esferas orbitan por fuera de él.
## Cinco esferas de cromo gris orbitan alrededor, cada una con su estela de vidrio.
## La tela se mueve con un resorte-amortiguador: al avanzar el borde se queda atrás, al frenar se adelanta
## y oscila, al girar se balancea; la capa interior y el manto se separan al moverse.
## API que usa Player: levitate, punch_t, punch_idx, animate(state, speed, delta).

const CLOAK_SHADER := preload("res://character/shaders/cloak.gdshader")
const ORB_SHADER := preload("res://character/shaders/orb.gdshader")
const TRAIL_SHADER := preload("res://character/shaders/orb_trail.gdshader")

const N_SEG := 44                       # puntos alrededor de la capa interior (cerrada)
const N_PANEL := 40                     # puntos alrededor del manto exterior (abierto al frente)
const N_DOME := 8                       # anillos de la cúpula (del punto más alto al ecuador)
const N_SKIRT := 12                     # anillos de la falda (del ecuador al dobladillo)
## Campo de fuerza (esfera invisible sobre la que cae la tela): centro y radio.
const FIELD_Y := 1.45
const FIELD_R := 0.56
const HEM_FLARE := 0.10                 # cuánto se abre la falda en el dobladillo
## Abertura del manto (semiángulo, rad): nace a ~32° del punto más alto, es ancha en el ecuador y se estrecha hacia abajo.
const GAP_START := 0.55
const GAP_EQUATOR := 0.80
const GAP_HEM := 0.24
## [escala, radio de órbita, altura, velocidad, fase, arrastre]. Todas orbitan FUERA del campo de fuerza.
const ORBS := [
	[0.16, 1.16, 1.65, 0.50, 0.0, 0.07],
	[0.10, 1.02, 1.15, -0.70, 1.7, 0.10],
	[0.13, 1.26, 1.45, 0.40, 3.2, 0.05],
	[0.08, 0.98, 2.00, -0.90, 4.4, 0.12],
	[0.11, 1.10, 0.90, 0.60, 5.6, 0.08],
]
## Distancia mínima (horizontal, desde el eje) a la que puede estar el centro de una esfera: borde del campo + su radio.
const ORB_CLEARANCE := 0.76
const TRAIL_ARC := 4.0                  # largo de la estela (rad)
const PUNCH_DUR := [0.34, 0.38, 0.5]

# --- API de Player
var levitate := true
var punch_t := 0.0
var punch_idx := 0

var _body: Node3D
var _cloak: MeshInstance3D
var _cloak_mat: ShaderMaterial
var _orb_mat: ShaderMaterial
var _orb_nodes: Array[MeshInstance3D] = []
var _trail_nodes: Array[MeshInstance3D] = []
var _trail_mat: ShaderMaterial
var _drift := Vector3.ZERO
var _drift_vel := Vector3.ZERO
var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _have_prev := false
var _vel_local := Vector3.ZERO
var _turn_f := 0.0
var _time := 0.0
var _lean := 0.0
var _roll := 0.0
var _crouch := 0.0
var _stretch := 0.0
var _pulse := 0.0
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_cloak = MeshInstance3D.new()
	_cloak.name = "Cloak"
	_cloak.mesh = build_cloak_mesh()
	_cloak_mat = ShaderMaterial.new()
	_cloak_mat.shader = CLOAK_SHADER
	_cloak.material_override = _cloak_mat
	_cloak_mat.set_shader_parameter("cloth_top", FIELD_Y)
	_body.add_child(_cloak)

	_orb_mat = ShaderMaterial.new()
	_orb_mat.shader = ORB_SHADER
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 12
	for i in ORBS.size():
		var mi := MeshInstance3D.new()
		mi.name = "Orb%d" % i
		mi.mesh = sm
		mi.material_override = _orb_mat
		mi.scale = Vector3.ONE * float(ORBS[i][0])
		add_child(mi)
		_orb_nodes.append(mi)
	_trail_mat = ShaderMaterial.new()
	_trail_mat.shader = TRAIL_SHADER
	var trail_mesh := build_trail_mesh()
	for i in ORBS.size():
		var tm := MeshInstance3D.new()
		tm.name = "Trail%d" % i
		tm.mesh = trail_mesh
		tm.material_override = _trail_mat
		tm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tm)
		_trail_nodes.append(tm)
	# luz de personaje: fría y suave, sin sombras; mantiene legible la tela en escenas oscuras
	var key := OmniLight3D.new()
	key.name = "CharacterLight"
	key.light_color = Color(0.78, 0.84, 1.0)
	key.light_energy = 0.9
	key.omni_range = 7.0
	key.shadow_enabled = false
	key.position = Vector3(0.9, 2.2, 2.4)
	add_child(key)
	_place_orbs(0.0)


## Radio base (capa interior) a la altura y: cúpula de la esfera invisible y falda que se abre hacia abajo.
## Sobre la cúpula devuelve 0. El contorno solo crece al bajar: no hay cuello ni cabeza.
static func base_radius(y: float) -> float:
	if y > FIELD_Y + FIELD_R:
		return 0.0
	if y >= FIELD_Y:
		return sqrt(maxf(FIELD_R * FIELD_R - pow(y - FIELD_Y, 2.0), 0.0))
	return FIELD_R + HEM_FLARE * pow(clampf((FIELD_Y - y) / (FIELD_Y - 0.45), 0.0, 1.3), 1.2)


## Punto (altura, radio) del anillo i de un manto con separación `off` de la esfera y dobladillo en `hem`.
static func _ring(i: int, off: float, hem_off: float, hem: float) -> Vector2:
	if i < N_DOME:
		var phi := (PI * 0.5) * float(i) / float(N_DOME - 1)
		var rr := FIELD_R + off
		return Vector2(FIELD_Y + rr * cos(phi), rr * sin(phi))
	var s := float(i - N_DOME + 1) / float(N_SKIRT)
	var y := lerpf(FIELD_Y, hem, s)
	var ft := clampf((FIELD_Y - y) / (FIELD_Y - 0.45), 0.0, 1.3)
	return Vector2(y, FIELD_R + off + hem_off * smoothstep(0.0, 1.0, s) + HEM_FLARE * pow(ft, 1.2))


## Semiángulo de la abertura del manto exterior en el anillo i.
static func _gap(i: int) -> float:
	if i < N_DOME:
		var phi := (PI * 0.5) * float(i) / float(N_DOME - 1)
		var g := clampf((phi - GAP_START) / (PI * 0.5 - GAP_START), 0.0, 1.0)
		return lerpf(0.02, GAP_EQUATOR, pow(g, 0.8))
	var s := float(i - N_DOME + 1) / float(N_SKIRT)
	return lerpf(GAP_EQUATOR, GAP_HEM, pow(s, 0.9))


## Una sola malla con las dos capas. Color de vértice: r = capa (0 interior, 1 manto), g = distancia al borde de la
## abertura (m × 2), b = distancia al dobladillo (m × 2), a = qué tan abierta está la abertura (0 cerrada, 1 abierta).
## UV = (distancia alrededor en m, altura en m) para el dibujo de los ribetes.
static func build_cloak_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n_ring := N_DOME + N_SKIRT
	# ---- capa 0: interior, cerrada (cúpula lisa + falda larga de puntas)
	for i in n_ring:
		for j in N_SEG:
			var th := TAU * float(j) / float(N_SEG)         # 0 = atrás (+Z)
			var saw := fposmod(th / TAU * 7.0 + 0.15, 1.0)
			var tri := absf(saw * 2.0 - 1.0)
			var hem := 0.28 + 0.20 * tri - 0.08 * (0.5 + 0.5 * cos(th))
			var yr := _ring(i, 0.012, 0.0, hem)
			var sk := clampf(float(i - N_DOME + 1) / float(N_SKIRT), 0.0, 1.0)
			var r := yr.y * (1.0 + 0.03 * sk * (sin(7.0 * th + 2.2 * yr.x) + 0.5 * sin(13.0 * th - 3.1 * yr.x)))
			verts.append(Vector3(sin(th) * r, yr.x, cos(th) * r))
			cols.append(Color(0.0, 1.0, 1.0, 0.0))
			uvs.append(Vector2(th * 0.7, yr.x))
	for i in n_ring - 1:
		for j in N_SEG:
			var j2 := (j + 1) % N_SEG
			var a := i * N_SEG + j
			var b := i * N_SEG + j2
			var c := (i + 1) * N_SEG + j
			var d := (i + 1) * N_SEG + j2
			idx.append_array([a, b, c, b, d, c])
	# ---- capa 1: manto exterior, abierto al frente (th = PI es el frente, -Z)
	var base := verts.size()
	for i in n_ring:
		var gap := _gap(i)
		for j in N_PANEL:
			var a_az := gap + (TAU - 2.0 * gap) * float(j) / float(N_PANEL - 1)   # 0 = frente
			var th := PI + a_az
			var hem := 0.36 + 0.05 * sin(5.0 * a_az + 0.6) + 0.04 * cos(a_az) \
					- 0.10 * exp(-(a_az - GAP_HEM) / 0.22) - 0.10 * exp(-(TAU - GAP_HEM - a_az) / 0.22)
			var yr := _ring(i, 0.04, 0.025, hem)
			var sk := clampf(float(i - N_DOME + 1) / float(N_SKIRT), 0.0, 1.0)
			var d_edge := minf(a_az - gap, TAU - gap - a_az) * maxf(yr.y, 0.05)
			var fold_fade := smoothstep(0.0, 0.22, d_edge)
			var amp := 0.04 * pow(sk, 1.2) * fold_fade
			var r := yr.y * (1.0 + amp * (sin(9.0 * th + 2.2 * yr.x) + 0.5 * sin(17.0 * th - 3.1 * yr.x)))
			r *= 1.0 + 0.03 * (0.5 + 0.5 * cos(th)) * sk
			verts.append(Vector3(sin(th) * r, yr.x, cos(th) * r))
			var hem_d := maxf(yr.x - hem, 0.0) if i >= N_DOME else 1.0
			cols.append(Color(1.0, clampf(d_edge * 2.0, 0.0, 1.0), clampf(hem_d * 2.0, 0.0, 1.0),
					clampf((gap - 0.02) / 0.3, 0.0, 1.0)))
			uvs.append(Vector2(a_az * 0.7, yr.x))
	for i in n_ring - 1:
		for j in N_PANEL - 1:
			var a := base + i * N_PANEL + j
			var b := a + 1
			var c := base + (i + 1) * N_PANEL + j
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# ---- normales suavizadas, siempre hacia afuera de la esfera
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	for k in range(0, idx.size(), 3):
		var p0 := verts[idx[k]]
		var p1 := verts[idx[k + 1]]
		var p2 := verts[idx[k + 2]]
		var fn := (p1 - p0).cross(p2 - p0)
		for q in 3:
			nrm[idx[k + q]] += fn
	for v in nrm.size():
		var nn := nrm[v].normalized() if nrm[v].length_squared() > 1e-12 else Vector3.UP
		var radial := Vector3(verts[v].x, verts[v].y - FIELD_Y, verts[v].z)
		if verts[v].y < FIELD_Y:
			radial.y = 0.0
		if radial.length_squared() > 1e-6 and nn.dot(radial) < 0.0:
			nn = -nn
		nrm[v] = nn
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Estela de una esfera: arco de tubo triangular (radio 1, en el plano XZ) que se adelgaza y se desvanece hacia atrás.
## El punto s = 0 está en +Z (donde está la esfera); el tubo se extiende hacia ángulos negativos.
static func build_trail_mesh() -> ArrayMesh:
	const SEG := 36
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for k in SEG + 1:
		var f := float(k) / float(SEG)
		var al := -f * TRAIL_ARC
		var radial := Vector3(sin(al), 0.0, cos(al))
		var rho := 0.018 * pow(1.0 - f, 0.6) + 0.002
		for q in 3:
			var ang := TAU * float(q) / 3.0
			verts.append(radial * (1.0 + cos(ang) * rho) + Vector3.UP * sin(ang) * rho)
			cols.append(Color(1, 1, 1, pow(1.0 - f, 1.5)))
	for k in SEG:
		for q in 3:
			var q2 := (q + 1) % 3
			var a := k * 3 + q
			var b := k * 3 + q2
			var c := (k + 1) * 3 + q
			var d := (k + 1) * 3 + q2
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _place_orbs(delta: float) -> void:
	var swell := _pulse
	for i in _orb_nodes.size():
		var o: Array = ORBS[i]
		var th: float = float(o[4]) + _time * float(o[3])
		var orbit_r: float = float(o[1]) * (1.0 - 0.35 * swell)
		var bob := sin(_time * 1.3 + float(i) * 1.9) * 0.07
		var p := Vector3(sin(th) * orbit_r, float(o[2]) + bob - _crouch * 0.3, cos(th) * orbit_r)
		# arrastre: las esferas se quedan atrás al moverse, cada una a su ritmo
		p -= _vel_local * float(o[5])
		# golpe telequinético: las esferas salen disparadas al frente
		var hit := 0.0
		match punch_idx:
			0:
				hit = 1.0 if i % 2 == 0 else 0.3
			1:
				hit = 1.0 if i % 2 == 1 else 0.3
			_:
				hit = 1.0
		p.z -= swell * 1.3 * hit
		# campo de fuerza: ninguna esfera puede entrar en él (se desliza por su borde)
		var min_h := ORB_CLEARANCE + float(o[0])
		var hxz := Vector2(p.x, p.z)
		if hxz.length() < min_h:
			hxz = hxz.normalized() * min_h if hxz.length() > 0.001 else Vector2(0.0, min_h)
			p.x = hxz.x
			p.z = hxz.y
		_orb_nodes[i].position = p
		# estela: un arco centrado en el cuerpo (con el mismo arrastre), con la esfera en su cabeza
		var c := Vector3(-_vel_local.x * float(o[5]), 0.0, -_vel_local.z * float(o[5]))
		var rel := Vector2(p.x - c.x, p.z - c.z)
		var rl := maxf(rel.length(), 0.05)
		var tr := _trail_nodes[i]
		tr.position = Vector3(c.x, p.y, c.z)
		tr.rotation.y = atan2(rel.x, rel.y)
		tr.scale = Vector3(rl if float(o[3]) >= 0.0 else -rl, 1.0, rl)
	if _orb_mat:
		_orb_mat.set_shader_parameter("glow", swell * 0.55)
	if _trail_mat:
		_trail_mat.set_shader_parameter("glow", swell)


func animate(state: String, speed: float, delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	_time += delta
	var gp := global_position
	var yaw := global_rotation.y
	if not _have_prev or gp.distance_squared_to(_prev_pos) > 25.0:
		_prev_pos = gp
		_prev_yaw = yaw
		_have_prev = true
		_drift = Vector3.ZERO
		_drift_vel = Vector3.ZERO
	var vel_w := (gp - _prev_pos) / delta
	_prev_pos = gp
	var dyaw := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	_turn_f = lerpf(_turn_f, clampf(dyaw, -8.0, 8.0), 1.0 - exp(-8.0 * delta))
	_vel_local = global_basis.inverse() * vel_w
	_vel_local.x = clampf(_vel_local.x, -9.0, 9.0)
	_vel_local.z = clampf(_vel_local.z, -9.0, 9.0)
	_vel_local.y = clampf(_vel_local.y, -6.0, 6.0)

	# --- resorte-amortiguador de la tela (integración semi-implícita, subpasos para ser estable)
	var target := Vector3(-_vel_local.x * 0.085, _vel_local.y * 0.05, -_vel_local.z * 0.085)
	target.x += _turn_f * 0.03
	var tl := Vector2(target.x, target.z).length()
	if tl > 0.5:
		target.x *= 0.5 / tl
		target.z *= 0.5 / tl
	var steps := maxi(1, ceili(delta / 0.008))
	var h := delta / float(steps)
	for s in steps:
		var acc := (target - _drift) * 58.0 - _drift_vel * 6.5
		_drift_vel += acc * h
		_drift += _drift_vel * h

	# --- pose del cuerpo según el estado
	var sp := clampf(speed / 7.0, 0.0, 1.0)
	var want_lean := sp * 0.2
	var want_roll := clampf(-_turn_f * 0.025, -0.16, 0.16)
	var want_crouch := 0.0
	var want_stretch := 0.0
	var want_pulse := 0.0
	var want_tilt := 0.0
	match state:
		"crouch", "crouch_walk":
			want_crouch = 1.0
		"jump":
			want_stretch = 1.0
		"fall":
			want_stretch = 0.6
		"land":
			want_crouch = 0.5
		"stumble":
			want_tilt = 0.32
			want_lean = 0.0
		"punch":
			var dur: float = PUNCH_DUR[clampi(punch_idx, 0, 2)]
			want_pulse = sin(clampf(punch_t / dur, 0.0, 1.0) * PI)
			want_lean += 0.1 * want_pulse
		"push":
			want_lean += 0.12
	_lean = lerpf(_lean, want_lean + want_tilt * -1.0, 1.0 - exp(-7.0 * delta))
	_roll = lerpf(_roll, want_roll, 1.0 - exp(-7.0 * delta))
	_crouch = lerpf(_crouch, want_crouch, 1.0 - exp(-9.0 * delta))
	_stretch = lerpf(_stretch, want_stretch, 1.0 - exp(-8.0 * delta))
	_pulse = lerpf(_pulse, want_pulse, 1.0 - exp(-18.0 * delta))

	var bob := sin(_time * 1.6) * 0.03 if levitate else 0.0
	_body.position = Vector3(0.0, bob - _crouch * 0.06, 0.0)
	_body.rotation = Vector3(-_lean, 0.0, _roll)
	_body.scale = Vector3(1.0 + _crouch * 0.1, 1.0 - _crouch * 0.18 + _stretch * 0.05, 1.0 + _crouch * 0.1)

	var idle := 0.016 if sp < 0.05 else 0.03
	_cloak_mat.set_shader_parameter("drift", _drift)
	_cloak_mat.set_shader_parameter("flutter", idle + sp * 0.035 + _pulse * 0.05)
	_cloak_mat.set_shader_parameter("flare", _pulse * 0.12 + _stretch * 0.05)
	_place_orbs(delta)

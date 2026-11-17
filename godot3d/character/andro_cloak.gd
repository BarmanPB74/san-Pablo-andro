class_name AndroCloak
extends Node3D
## Andro (ref. 84070): una forma de tela negra SIN rasgos humanos (sin cabeza, cuello, hombros ni brazos).
## Diseño: una esfera mayor INVISIBLE (campo de fuerza) cubierta por una cúpula lisa de tela. De ella cae una capa
## interior larga (dobladillo en puntas) y, encima, un manto exterior abierto al frente (la abertura nace en la cúpula y se
## cierra hacia abajo) con ribetes ornamentados en los bordes y en el dobladillo. Nada puede tocar la tela: el campo de
## fuerza es la cápsula de colisión del jugador (Player.CAPSULE_RADIUS) y las esferas orbitan por fuera de él.
## Cinco esferas de cromo gris orbitan alrededor, cada una por su cuenta y sin dejar rastro.
## La tela se mueve con un resorte-amortiguador: al avanzar el borde se queda atrás, al frenar se adelanta
## y oscila, al girar se balancea; la capa interior y el manto se separan al moverse.
## API que usa Player: levitate, punch_t, punch_idx, animate(state, speed, delta).
## API de poderes y nivel: level (0..MAX_LEVEL, enciende las runas EISEN-KERN del dobladillo), charge (0..1, aura de ki),
## flash_orb(i) (una esfera se adelanta y brilla al lanzar un hechizo), orb_toward(dir) y orb_global_position(i).

const CLOAK_SHADER := preload("res://character/shaders/cloak.gdshader")
const ORB_SHADER := preload("res://character/shaders/orb.gdshader")

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
	[0.16, 1.05, 1.55, 0.50, 0.0, 0.07],
	[0.10, 0.92, 1.00, -0.70, 1.7, 0.10],
	[0.13, 1.15, 1.30, 0.40, 3.2, 0.05],
	[0.08, 0.88, 1.85, -0.90, 4.4, 0.12],
	[0.11, 1.00, 0.75, 0.60, 5.6, 0.08],
]
## Distancia mínima (horizontal, desde el eje) a la que puede estar el centro de una esfera: borde del campo + su radio.
const ORB_CLEARANCE := 0.76
const PUNCH_DUR := [0.34, 0.38, 0.5]
const MAX_LEVEL := 33                   # niveles 0..33; en el 33 el dobladillo muestra completa la palabra EISEN-KERN
const FLASH_DUR := 0.42                 # lo que dura el adelantón de una esfera al lanzar un hechizo

# --- API de Player
var levitate := true
var punch_t := 0.0
var punch_idx := 0
## Nivel de Andro: cuanto más alto, más visibles las runas del ribete (ver cloak.gdshader).
var level := 0:
	set = set_level
## Carga de energía (0..1): aura en la tela y esferas encendidas y temblorosas.
var charge := 0.0
## Color de la carga (el del ki según su rango): tiñe el borde de la tela y el brillo de las esferas.
var charge_color := Color(0.85, 0.92, 1.0):
	set(c):
		charge_color = c
		if _cloak_mat:
			_cloak_mat.set_shader_parameter("charge_col", Vector3(c.r, c.g, c.b))
		if _orb_mat:
			_orb_mat.set_shader_parameter("glow_col", Vector3(c.r, c.g, c.b))

var _body: Node3D
var _cloak: MeshInstance3D
var _cloak_mat: ShaderMaterial
var _orb_mat: ShaderMaterial
var _orb_nodes: Array[MeshInstance3D] = []
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
var _flash := [0.0, 0.0, 0.0, 0.0, 0.0]    # por esfera: 1 recién lanzada .. 0 en reposo


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
	_cloak_mat.set_shader_parameter("rune_level", float(level))
	_cloak_mat.set_shader_parameter("charge_col", Vector3(charge_color.r, charge_color.g, charge_color.b))
	_body.add_child(_cloak)

	_orb_mat = ShaderMaterial.new()
	_orb_mat.shader = ORB_SHADER
	_orb_mat.set_shader_parameter("glow_col", Vector3(charge_color.r, charge_color.g, charge_color.b))
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
	# luz de personaje: fría y suave, sin sombras; mantiene legible la tela en escenas oscuras
	var key := OmniLight3D.new()
	key.name = "CharacterLight"
	key.light_color = Color(0.78, 0.84, 1.0)
	key.light_energy = 0.9
	key.omni_range = 7.0
	key.light_specular = 0.15         # sin reflejo fuerte en pisos pulidos (el Umbral)
	key.shadow_enabled = false
	key.position = Vector3(0.9, 2.2, 2.4)
	add_child(key)
	_place_orbs(0.0)


func set_level(l: int) -> void:
	level = clampi(l, 0, MAX_LEVEL)
	if _cloak_mat:
		_cloak_mat.set_shader_parameter("rune_level", float(level))


## Una esfera se adelanta y brilla un instante (la que va a disparar el hechizo).
func flash_orb(i: int) -> void:
	if i >= 0 and i < _flash.size():
		_flash[i] = 1.0


## Posición global de la esfera `i` (de ahí sale la bola de fuego).
func orb_global_position(i: int) -> Vector3:
	if not _built or i < 0 or i >= _orb_nodes.size():
		return global_position + Vector3(0.0, 1.5, 0.0)
	return _orb_nodes[i].global_position


## Índice de la esfera que más apunta hacia `dir` (en el mundo): la más natural para disparar hacia allá.
func orb_toward(dir: Vector3) -> int:
	var best := 0
	var best_d := -INF
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	for i in _orb_nodes.size():
		var v := _orb_nodes[i].global_position - global_position
		v.y = 0.0
		var k := v.normalized().dot(d) + 0.15 * float(_orb_nodes[i].scale.x)
		if k > best_d:
			best_d = k
			best = i
	return best


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


func _place_orbs(delta: float) -> void:
	var swell := _pulse
	for i in _orb_nodes.size():
		var o: Array = ORBS[i]
		# Movimiento natural e independiente: además de su órbita, cada esfera deriva por su cuenta (adelanta y
		# se retrasa, respira hacia adentro y afuera, sube y baja) con frecuencias que no coinciden entre sí,
		# así que nunca repiten el mismo recorrido ni se ven sobre un riel.
		var fi := float(i)
		var th: float = float(o[4]) + _time * float(o[3]) \
				+ 0.22 * sin(_time * (0.31 + 0.07 * fi) + fi * 2.1) + 0.10 * sin(_time * (0.79 + 0.11 * fi) + fi * 4.7)
		var breathe := 1.0 + 0.07 * sin(_time * (0.47 + 0.05 * fi) + fi * 1.3) + 0.04 * sin(_time * (1.05 + 0.09 * fi) + fi * 3.9)
		var orbit_r: float = float(o[1]) * breathe * (1.0 - 0.35 * swell - 0.12 * charge)
		var bob := sin(_time * 1.3 + fi * 1.9) * 0.07 \
				+ 0.10 * sin(_time * (0.43 + 0.06 * fi) + fi * 5.3) + 0.05 * sin(_time * (0.97 + 0.08 * fi) + fi * 0.9)
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
		# hechizo: la esfera elegida se adelanta; cargando, todas tiemblan
		var fl: float = _flash[i]
		p.z -= 0.55 * sin(clampf(fl, 0.0, 1.0) * PI)
		p += Vector3(sin(_time * 41.0 + fi * 3.0), sin(_time * 37.0 + fi * 5.0), sin(_time * 29.0 + fi)) * 0.012 * charge
		# campo de fuerza: ninguna esfera puede entrar en él (se desliza por su borde)
		var min_h := ORB_CLEARANCE + float(o[0])
		var hxz := Vector2(p.x, p.z)
		if hxz.length() < min_h:
			hxz = hxz.normalized() * min_h if hxz.length() > 0.001 else Vector2(0.0, min_h)
			p.x = hxz.x
			p.z = hxz.y
		_orb_nodes[i].position = p
		_orb_nodes[i].scale = Vector3.ONE * float(o[0]) * (1.0 + 0.5 * sin(clampf(fl, 0.0, 1.0) * PI) + 0.12 * charge)
	if _orb_mat:
		var fmax := 0.0
		for f in _flash:
			fmax = maxf(fmax, float(f))
		_orb_mat.set_shader_parameter("glow", swell * 0.55 + charge * (0.45 + 0.15 * sin(_time * 9.0)) + fmax * 0.8)


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
		"fly":
			want_stretch = 0.5
			want_lean += 0.1 + 0.2 * sp
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
	_cloak_mat.set_shader_parameter("flare", _pulse * 0.12 + _stretch * 0.05 + charge * 0.05)
	_cloak_mat.set_shader_parameter("charge", charge * (0.85 + 0.15 * sin(_time * 11.0)))
	for i in _flash.size():
		_flash[i] = maxf(0.0, float(_flash[i]) - delta / FLASH_DUR)
	_place_orbs(delta)

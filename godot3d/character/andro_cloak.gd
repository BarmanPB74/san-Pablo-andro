class_name AndroCloak
extends Node3D
## Andro (ref. 83527): una forma de tela negra SIN rasgos humanos (sin cabeza, cuello, hombros ni brazos).
## Diseño: una esfera mayor INVISIBLE (campo de fuerza, `FIELD_R`) y, sobre ella, tres capas de tela que
## la envuelven como mantos superpuestos: una capa interior larga con dobladillo en puntas, una intermedia y un
## manto exterior corto. Arriba la tela se recoge en una punta. Nada puede tocar la tela: el campo de fuerza
## es la cápsula de colisión del jugador (Player.CAPSULE_RADIUS) y las esferas orbitan por fuera de él.
## Cinco esferas de cromo gris orbitan alrededor.
## La tela se mueve con un resorte-amortiguador: al avanzar el borde se queda atrás, al frenar se adelanta
## y oscila, al girar se balancea; cada capa se mueve un poco distinto y se separan al moverse.
## API que usa Player: levitate, punch_t, punch_idx, animate(state, speed, delta).

const CLOAK_SHADER := preload("res://character/shaders/cloak.gdshader")
const ORB_SHADER := preload("res://character/shaders/orb.gdshader")

const N_SEG := 44
## Campo de fuerza (esfera invisible sobre la que cae la tela): centro y radio.
const FIELD_Y := 1.2
const FIELD_R := 0.56
const TOP_Y := 2.1                      # punta superior de la tela
const SPHERE_TOP_Y := 1.6               # hasta aquí la tela sigue la esfera; arriba se recoge en punta
## Capas de tela: [y_superior, rings, dobladillo_mín, amplitud_del_dobladillo, puntas, fase, separación_radial, pliegues]
const LAYERS := [
	[2.10, 22, 0.04, 0.34, 7, 0.15, 0.000, 7],
	[1.86, 15, 0.40, 0.30, 6, 0.55, 0.035, 9],
	[1.70, 10, 0.78, 0.26, 5, 0.85, 0.070, 6],
]
## [escala, radio de órbita, altura, velocidad, fase, arrastre]. Todas orbitan FUERA del campo de fuerza.
const ORBS := [
	[0.16, 1.05, 1.55, 0.50, 0.0, 0.07],
	[0.10, 0.92, 1.00, -0.70, 1.7, 0.10],
	[0.13, 1.15, 1.30, 0.40, 3.2, 0.05],
	[0.08, 0.88, 1.85, -0.90, 4.4, 0.12],
	[0.11, 1.00, 0.75, 0.60, 5.6, 0.08],
]
## Distancia mínima (horizontal, desde el eje) a la que puede estar el centro de una esfera: borde del campo + su radio.
const ORB_CLEARANCE := 0.78
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


## Radio base de la tela a la altura y: sigue la esfera invisible y arriba se recoge en punta;
## por debajo del ecuador cae casi recta y se abre un poco (campana).
static func base_radius(y: float) -> float:
	if y >= SPHERE_TOP_Y:
		var rt := sqrt(maxf(FIELD_R * FIELD_R - pow(SPHERE_TOP_Y - FIELD_Y, 2.0), 0.0))
		var t := clampf((TOP_Y - y) / (TOP_Y - SPHERE_TOP_Y), 0.0, 1.0)
		return rt * pow(t, 0.7)
	if y >= FIELD_Y:
		return sqrt(maxf(FIELD_R * FIELD_R - pow(y - FIELD_Y, 2.0), 0.0))
	return FIELD_R + 0.09 * clampf((FIELD_Y - y) / FIELD_Y, 0.0, 1.0)


## Malla de las tres capas (una sola superficie): cada capa es un loft de anillos con pliegues y dobladillo en
## puntas (más largo atrás). El color de vértice (r) guarda el número de capa (0, 0.5, 1) para el shader.
static func build_cloak_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for li in LAYERS.size():
		var L: Array = LAYERS[li]
		var top_y: float = L[0]
		var n_ring: int = L[1]
		var hem_lo: float = L[2]
		var hem_amp: float = L[3]
		var points: float = float(L[4])
		var phase: float = L[5]
		var off: float = L[6]
		var folds: float = float(L[7])
		var base := verts.size()
		for i in n_ring:
			var sn := float(i) / float(n_ring - 1)            # 0 arriba, 1 dobladillo
			for j in N_SEG:
				var th := TAU * float(j) / float(N_SEG)       # 0 = atrás (+Z)
				var saw := fposmod(th / TAU * points + phase, 1.0)
				var tri := absf(saw * 2.0 - 1.0)
				var hem := hem_lo + hem_amp * tri - 0.1 * (0.5 + 0.5 * cos(th))
				hem = maxf(hem, 0.03)
				var y := lerpf(top_y, hem, sn)
				var r := base_radius(y)
				if li > 0:
					r += off * minf(sn * 3.0, 1.0)      # cada manto un poco más separado de la esfera
				var amp := 0.01 + 0.055 * pow(sn, 1.3)
				if y > SPHERE_TOP_Y:
					amp *= 0.3
				r *= 1.0 + amp * (sin(folds * th + 2.2 * y) + 0.5 * sin((folds * 1.9 + 1.0) * th - 3.1 * y))
				r *= 1.0 + 0.06 * (0.5 + 0.5 * cos(th)) * sn
				verts.append(Vector3(sin(th) * r, y, cos(th) * r))
				cols.append(Color(float(li) * 0.5, 0.0, 0.0, 1.0))
		for i in n_ring - 1:
			for j in N_SEG:
				var j2 := (j + 1) % N_SEG
				var a := base + i * N_SEG + j
				var b := base + i * N_SEG + j2
				var c := base + (i + 1) * N_SEG + j
				var d := base + (i + 1) * N_SEG + j2
				idx.append_array([a, b, c, b, d, c])
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
		var radial := Vector3(verts[v].x, 0.0, verts[v].z)
		if radial.length_squared() > 1e-6 and nn.dot(radial) < 0.0:
			nn = -nn
		nrm[v] = nn
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
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
	if _orb_mat:
		_orb_mat.set_shader_parameter("glow", swell * 0.55)


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

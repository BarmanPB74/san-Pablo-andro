class_name PlayerModel
extends Node3D
## "Andro" — protagonista original paisa, construido 100 % por código con primitivas.
## Antihéroe urbano: chaqueta técnica corta gris carbón con vivos ámbar y franja
## reflectiva, buzo verde oscuro, pañoleta a rayas verde/blanco (Antioquia), cargo
## negro con rodilleras, tenis blancos de suela gruesa, guantes sin dedos y mochila
## cruzada. Altura ~1.78 m, pies en y = 0, mira hacia -Z.
##
## Jerarquía articulada (todos los pivotes rotan; las mallas cuelgan de ellos):
##   root (pies, para caídas) → hips → spine → chest → neck → head
##                                            chest → upper_arm_l/r → forearm → hand
##                                    hips → thigh_l/r → shin → foot
## Convención de rotación local (x): + adelanta una extremidad colgante,
## - la lleva atrás; en el tronco, x negativo = inclinarse hacia adelante.

# ---------------- Colores (todos pasan por Palette) ----------------
const C_JACKET := Color(0.165, 0.172, 0.182)
const C_JACKET_DARK := Color(0.095, 0.1, 0.108)
const C_AMBER := Color(0.95, 0.58, 0.14)
const C_HOODIE := Color(0.07, 0.2, 0.13)
const C_HOODIE_RIB := Color(0.05, 0.15, 0.1)
const C_SCARF_GREEN := Color(0.0, 0.43, 0.2)
const C_SCARF_WHITE := Color(0.92, 0.93, 0.9)
const C_PANTS := Color(0.055, 0.057, 0.062)
const C_KNEEPAD := Color(0.14, 0.145, 0.155)
const C_SHOE := Color(0.9, 0.9, 0.88)
const C_SOLE := Color(0.97, 0.96, 0.93)
const C_LACE := Color(0.55, 0.56, 0.58)
const C_GLOVE := Color(0.035, 0.035, 0.04)
const C_BAG := Color(0.1, 0.115, 0.1)
const C_STRAP := Color(0.03, 0.03, 0.035)
const C_HAIR := Color(0.045, 0.035, 0.03)
const C_EYE := Color(0.03, 0.02, 0.015)
const C_LIP := Color(0.42, 0.25, 0.2)
const SKIN_TONE := Color(0.66, 0.46, 0.34)      # mestizo cálido
const STUBBLE_TONE := Color(0.4, 0.29, 0.23)    # barba de pocos días

# Longitudes de los segmentos (m)
const THIGH_LEN := 0.43
const SHIN_LEN := 0.38
const HIPS_HEIGHT := 0.95

## Pivotes públicos (para otros sistemas: p. ej. apuntar, IK futura).
var root: Node3D
var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var upper_arm_l: Node3D
var forearm_l: Node3D
var hand_l: Node3D
var upper_arm_r: Node3D
var forearm_r: Node3D
var hand_r: Node3D
var thigh_l: Node3D
var shin_l: Node3D
var foot_l: Node3D
var thigh_r: Node3D
var shin_r: Node3D
var foot_r: Node3D

var _joints: Dictionary = {}       # nombre → Node3D
var _state := "idle"
var _time := 0.0
var _phase := 0.0
var _prev_speed := 0.0
var _accel_f := 0.0
var _prev_yaw := 0.0
var _turn_f := 0.0
var _land_t := 0.0
var _stumble_t := 0.0
var _enter_t := 0.0
var _air_t := 0.0
var _gait_g := 0.0                 # mezcla caminar→correr filtrada
var _gait_s := 0.0                 # mezcla correr→sprint filtrada
var _move_w := 0.0                 # peso de locomoción filtrado
var _hips_y := 0.0
var _built := false


func _ready() -> void:
	if not _built:
		_build()


# =====================================================================
#  CONSTRUCCIÓN
# =====================================================================

func _build() -> void:
	_built = true
	root = _pivot("root", self, Vector3.ZERO)
	hips = _pivot("hips", root, Vector3(0, HIPS_HEIGHT, 0))
	spine = _pivot("spine", hips, Vector3(0, 0.1, 0))
	chest = _pivot("chest", spine, Vector3(0, 0.2, 0))
	neck = _pivot("neck", chest, Vector3(0, 0.24, 0.005))
	head = _pivot("head", neck, Vector3(0, 0.065, -0.005))
	_build_pelvis()
	_build_torso()
	_build_head()
	for side in [-1, 1]:
		_build_arm(side)
		_build_leg(side)
	_prev_yaw = global_rotation.y if is_inside_tree() else 0.0


func _pivot(pname: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pname
	n.position = pos
	parent.add_child(n)
	_joints[pname] = n
	return n


## Crea una pieza de malla colgada de un pivote.
func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot := Vector3.ZERO, scl := Vector3.ONE, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, 2.0 * r + 0.001)
	m.radial_segments = 14
	m.rings = 5
	return m


func _sphere(r: float, segs := 14) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = 2.0 * r
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cyl(top: float, bottom: float, h: float, segs := 14) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


func _build_pelvis() -> void:
	var pants := Palette.cloth(C_PANTS, 0.85)
	# Pelvis / cadera del cargo
	_part(hips, _sphere(0.175), pants, Vector3(0, -0.04, 0.005), Vector3.ZERO, Vector3(1.0, 0.75, 0.8))
	# Cinturón (casi oculto por el buzo)
	_part(hips, _cyl(0.163, 0.165, 0.035), Palette.cloth(C_STRAP, 0.5), Vector3(0, 0.035, 0.005),
		Vector3.ZERO, Vector3(1.0, 1.0, 0.8), false)


func _build_torso() -> void:
	var jacket := Palette.cloth(C_JACKET, 0.7)
	var jacket_dark := Palette.cloth(C_JACKET_DARK, 0.75)
	var amber := Palette.cloth(C_AMBER, 0.5)
	var hoodie := Palette.cloth(C_HOODIE, 0.95)
	var rib := Palette.cloth(C_HOODIE_RIB, 0.95)
	var glow := Palette.neon(Color(1.0, 0.6, 0.18), 1.4)

	# --- Buzo verde (abdomen, asoma bajo la chaqueta corta) ---
	_part(spine, _capsule(0.148, 0.44), hoodie, Vector3(0, 0.07, 0.0), Vector3.ZERO, Vector3(1.04, 1.0, 0.8))
	_part(spine, _cyl(0.152, 0.156, 0.06), rib, Vector3(0, -0.105, 0.0), Vector3.ZERO, Vector3(1.04, 1.0, 0.82))

	# --- Chaqueta técnica corta ---
	_part(chest, _capsule(0.172, 0.5), jacket, Vector3(0, 0.05, 0.0), Vector3.ZERO, Vector3(1.12, 1.0, 0.78))
	# Bajo (dobladillo) de la chaqueta, más oscuro, a la altura de la cintura
	_part(chest, _cyl(0.19, 0.196, 0.055), jacket_dark, Vector3(0, -0.165, 0.0), Vector3.ZERO, Vector3(1.03, 1.0, 0.76))
	# Hombros (piezas solapadas para quitar el look de cápsula)
	for sx in [-1.0, 1.0]:
		_part(chest, _sphere(0.075), jacket, Vector3(0.17 * sx, 0.195, 0.005), Vector3(0, 0, -0.35 * sx),
			Vector3(1.15, 0.8, 1.0))
	# Abertura frontal: se ve el buzo verde
	_part(chest, _box(Vector3(0.07, 0.4, 0.03)), hoodie, Vector3(0, 0.03, -0.122), Vector3(0.06, 0, 0))
	# Vivos ámbar a cada lado de la cremallera + bolsillos de pecho
	for sx in [-1.0, 1.0]:
		_part(chest, _box(Vector3(0.01, 0.4, 0.014)), amber, Vector3(0.04 * sx, 0.03, -0.134),
			Vector3(0.06, 0, 0), Vector3.ONE, false)
		_part(chest, _box(Vector3(0.075, 0.012, 0.012)), amber, Vector3(0.115 * sx, 0.125, -0.122),
			Vector3(0, 0.45 * sx, 0), Vector3.ONE, false)
		# Bolsillos de mano (cremallera diagonal)
		_part(chest, _box(Vector3(0.012, 0.11, 0.012)), jacket_dark, Vector3(0.12 * sx, -0.08, -0.123),
			Vector3(0, 0.5 * sx, 0.35 * sx), Vector3.ONE, false)
	# Franja reflectiva en la espalda (brilla de noche con el glow)
	_part(chest, _box(Vector3(0.3, 0.024, 0.012)), glow, Vector3(0, 0.1, 0.131), Vector3.ZERO, Vector3.ONE, false)
	_part(chest, _box(Vector3(0.24, 0.012, 0.01)), amber, Vector3(0, -0.05, 0.13), Vector3.ZERO, Vector3.ONE, false)

	# --- Capucha baja sobre la espalda ---
	_part(chest, _sphere(0.13), jacket, Vector3(0, 0.235, 0.11), Vector3(0.35, 0, 0), Vector3(1.2, 0.62, 0.78))
	_part(chest, _cyl(0.1, 0.11, 0.012), amber, Vector3(0, 0.255, 0.075), Vector3(-1.0, 0, 0),
		Vector3(1.05, 1.0, 0.55), false)
	# Cuello alto de la chaqueta
	_part(chest, _cyl(0.088, 0.1, 0.075), jacket_dark, Vector3(0, 0.255, 0.005))

	# --- Pañoleta a rayas verde/blanco (colores de Antioquia) ---
	var sg := Palette.cloth(C_SCARF_GREEN, 0.95)
	var sw := Palette.cloth(C_SCARF_WHITE, 0.95)
	_part(chest, _cyl(0.094, 0.104, 0.03), sg, Vector3(0, 0.27, -0.005), Vector3(-0.15, 0, 0))
	_part(chest, _cyl(0.088, 0.096, 0.028), sw, Vector3(0, 0.297, -0.01), Vector3(-0.15, 0, 0))
	_part(chest, _cyl(0.08, 0.089, 0.026), sg, Vector3(0, 0.322, -0.015), Vector3(-0.15, 0, 0))
	# Nudo y punta colgando al frente (triángulo de pañoleta)
	_part(chest, _sphere(0.03, 10), sg, Vector3(0.03, 0.27, -0.098), Vector3.ZERO, Vector3(1.2, 0.8, 0.6))
	var tip := Node3D.new()
	tip.position = Vector3(0.03, 0.26, -0.11)
	tip.rotation = Vector3(0.12, 0, -0.12)
	chest.add_child(tip)
	_part(tip, _prism(Vector3(0.12, 0.12, 0.012)), sg, Vector3(0, -0.06, 0), Vector3(0, 0, PI))
	_part(tip, _prism(Vector3(0.075, 0.075, 0.014)), sw, Vector3(0, -0.085, -0.001), Vector3(0, 0, PI), Vector3.ONE, false)
	_part(tip, _prism(Vector3(0.035, 0.035, 0.016)), sg, Vector3(0, -0.105, -0.002), Vector3(0, 0, PI), Vector3.ONE, false)

	# --- Mochila pequeña cruzada (correa del hombro izq. a la cadera der.) ---
	var strap := Palette.cloth(C_STRAP, 0.6)
	var ang := 0.62
	_part(chest, _box(Vector3(0.04, 0.47, 0.03)), strap, Vector3(0.0, 0.02, -0.128), Vector3(-0.04, 0, ang),
		Vector3.ONE, false)
	_part(chest, _box(Vector3(0.04, 0.47, 0.03)), strap, Vector3(0.0, 0.02, 0.128), Vector3(0.04, 0, ang),
		Vector3.ONE, false)
	# Hebilla
	_part(chest, _box(Vector3(0.05, 0.03, 0.016)), Palette.metal_dark(), Vector3(-0.06, 0.1, -0.134),
		Vector3(0, 0, ang), Vector3.ONE, false)
	# Bolso a la espalda baja-derecha
	var bag := Palette.cloth(C_BAG, 0.8)
	_part(chest, _box(Vector3(0.25, 0.15, 0.075)), bag, Vector3(0.08, -0.13, 0.165), Vector3(0, 0, ang * 0.8))
	_part(chest, _capsule(0.04, 0.24), bag, Vector3(0.08, -0.13, 0.2), Vector3(0, 0, PI * 0.5 + ang * 0.8),
		Vector3(1.0, 1.0, 0.7))
	_part(chest, _box(Vector3(0.22, 0.008, 0.01)), amber, Vector3(0.085, -0.115, 0.226), Vector3(0, 0, ang * 0.8),
		Vector3.ONE, false)


func _build_head() -> void:
	var skin := Palette.skin(SKIN_TONE)
	var stubble := Palette.skin(STUBBLE_TONE)
	var hair := Palette.cloth(C_HAIR, 0.65)
	var dark := Palette.cloth(C_EYE, 0.4)

	_part(neck, _cyl(0.052, 0.058, 0.13), skin, Vector3(0, 0.03, 0))
	# Cráneo y cara
	_part(head, _sphere(0.104, 18), skin, Vector3(0, 0.11, 0.0), Vector3.ZERO, Vector3(0.86, 1.1, 1.0))
	# Mandíbula con barba de pocos días (la mitad superior queda dentro del cráneo)
	_part(head, _sphere(0.068, 14), stubble, Vector3(0, 0.05, -0.022), Vector3.ZERO, Vector3(1.0, 0.82, 1.0))
	_part(head, _box(Vector3(0.045, 0.01, 0.012)), stubble, Vector3(0, 0.07, -0.094), Vector3.ZERO, Vector3.ONE, false)
	# Boca
	_part(head, _box(Vector3(0.034, 0.007, 0.01)), Palette.cloth(C_LIP, 0.6), Vector3(0, 0.058, -0.087),
		Vector3.ZERO, Vector3.ONE, false)
	# Nariz
	_part(head, _box(Vector3(0.022, 0.045, 0.026)), skin, Vector3(0, 0.094, -0.096), Vector3(-0.32, 0, 0),
		Vector3.ONE, false)
	# Ojos y cejas
	for sx in [-1.0, 1.0]:
		_part(head, _sphere(0.013, 8), dark, Vector3(0.031 * sx, 0.121, -0.086), Vector3.ZERO,
			Vector3(1.3, 0.75, 0.5), false)
		_part(head, _box(Vector3(0.032, 0.007, 0.01)), hair, Vector3(0.032 * sx, 0.139, -0.09),
			Vector3(0, 0, -0.06 * sx), Vector3.ONE, false)
		# Orejas
		_part(head, _sphere(0.026, 8), skin, Vector3(0.088 * sx, 0.1, 0.008), Vector3.ZERO,
			Vector3(0.45, 1.0, 0.75), false)
	# Pelo corto oscuro: casquete + volumen arriba/adelante, laterales cortos
	_part(head, _sphere(0.11, 16), hair, Vector3(0, 0.178, 0.012), Vector3(-0.08, 0, 0), Vector3(0.9, 0.62, 1.0))
	_part(head, _sphere(0.1, 12), hair, Vector3(0, 0.14, 0.045), Vector3.ZERO, Vector3(0.9, 0.82, 0.8))
	var tufts := [Vector3(0.0, 0.222, -0.055), Vector3(0.042, 0.212, -0.04), Vector3(-0.04, 0.214, -0.035),
		Vector3(0.015, 0.232, 0.0), Vector3(-0.02, 0.222, 0.04)]
	for i in tufts.size():
		_part(head, _sphere(0.045, 10), hair, tufts[i], Vector3(0.3, 0.4 * i, 0.2), Vector3(1.0, 0.6, 1.1), false)


func _build_arm(side: int) -> void:
	var sx := float(side)
	var sfx := "l" if side < 0 else "r"
	var jacket := Palette.cloth(C_JACKET, 0.7)
	var jacket_dark := Palette.cloth(C_JACKET_DARK, 0.75)
	var amber := Palette.cloth(C_AMBER, 0.5)
	var glove := Palette.cloth(C_GLOVE, 0.55)
	var skin := Palette.skin(SKIN_TONE)

	var ua := _pivot("upper_arm_" + sfx, chest, Vector3(0.2 * sx, 0.175, 0.0))
	_part(ua, _capsule(0.064, 0.34), jacket, Vector3(0, -0.135, 0))
	_part(ua, _box(Vector3(0.01, 0.27, 0.012)), amber, Vector3(0.062 * sx, -0.14, 0.0), Vector3.ZERO, Vector3.ONE, false)
	# Banda reflectiva en el brazo
	_part(ua, _cyl(0.066, 0.066, 0.018, 12), Palette.neon(Color(1.0, 0.6, 0.18), 1.2), Vector3(0, -0.07, 0),
		Vector3.ZERO, Vector3.ONE, false)
	var fa := _pivot("forearm_" + sfx, ua, Vector3(0, -0.29, 0))
	_part(fa, _sphere(0.058, 10), jacket, Vector3(0, 0.0, 0.0))        # codo
	_part(fa, _capsule(0.055, 0.27), jacket, Vector3(0, -0.11, 0))
	_part(fa, _cyl(0.05, 0.048, 0.05, 12), jacket_dark, Vector3(0, -0.215, 0))   # puño
	var hd := _pivot("hand_" + sfx, fa, Vector3(0, -0.25, 0))
	_part(hd, _cyl(0.031, 0.034, 0.04, 10), skin, Vector3(0, -0.005, 0), Vector3.ZERO, Vector3.ONE, false)
	_part(hd, _box(Vector3(0.034, 0.085, 0.074)), glove, Vector3(0, -0.055, -0.002))
	_part(hd, _box(Vector3(0.028, 0.06, 0.068)), skin, Vector3(-0.003 * sx, -0.118, 0.0), Vector3(0, 0, 0.12 * sx),
		Vector3.ONE, false)
	_part(hd, _capsule(0.012, 0.06), skin, Vector3(-0.012 * sx, -0.065, -0.042), Vector3(0.5, 0, 0),
		Vector3.ONE, false)
	_part(hd, _box(Vector3(0.036, 0.012, 0.076)), glove, Vector3(0, -0.095, -0.002), Vector3.ZERO, Vector3.ONE, false)
	if side < 0:
		upper_arm_l = ua; forearm_l = fa; hand_l = hd
	else:
		upper_arm_r = ua; forearm_r = fa; hand_r = hd


func _build_leg(side: int) -> void:
	var sx := float(side)
	var sfx := "l" if side < 0 else "r"
	var pants := Palette.cloth(C_PANTS, 0.85)
	var pad := Palette.cloth(C_KNEEPAD, 0.6)
	var shoe := Palette.cloth(C_SHOE, 0.55)
	var sole := Palette.cloth(C_SOLE, 0.7)
	var lace := Palette.cloth(C_LACE, 0.8)

	var th := _pivot("thigh_" + sfx, hips, Vector3(0.09 * sx, -0.04, 0.0))
	_part(th, _capsule(0.095, 0.5), pants, Vector3(0, -0.19, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.05))
	# Bolsillo cargo lateral con solapa
	_part(th, _box(Vector3(0.03, 0.13, 0.11)), pants, Vector3(0.078 * sx, -0.25, 0.0), Vector3(0, 0, 0.04 * sx))
	_part(th, _box(Vector3(0.034, 0.022, 0.115)), pad, Vector3(0.081 * sx, -0.19, 0.0), Vector3.ZERO, Vector3.ONE, false)
	var sh := _pivot("shin_" + sfx, th, Vector3(0, -THIGH_LEN, 0))
	_part(sh, _sphere(0.072, 10), pants, Vector3.ZERO)                 # rodilla
	_part(sh, _capsule(0.07, 0.42), pants, Vector3(0, -0.18, 0))
	# Rodillera sutil
	_part(sh, _sphere(0.05, 10), pad, Vector3(0, -0.02, -0.052), Vector3.ZERO, Vector3(1.1, 1.3, 0.5))
	# Bota del pantalón recogida sobre el tenis
	_part(sh, _cyl(0.074, 0.07, 0.07), pants, Vector3(0, -0.33, 0))
	var ft := _pivot("foot_" + sfx, sh, Vector3(0, -SHIN_LEN, 0))
	# Tenis blanco de suela gruesa
	_part(ft, _cyl(0.058, 0.062, 0.06), shoe, Vector3(0, -0.02, 0.01))                      # caña
	_part(ft, _capsule(0.058, 0.27), shoe, Vector3(0, -0.045, -0.045), Vector3(PI * 0.5, 0, 0), Vector3(0.95, 1.0, 0.82))
	_part(ft, _box(Vector3(0.112, 0.042, 0.285)), sole, Vector3(0, -0.079, -0.045))
	_part(ft, _box(Vector3(0.114, 0.008, 0.287)), lace, Vector3(0, -0.062, -0.045), Vector3.ZERO, Vector3.ONE, false)
	for i in 3:
		_part(ft, _box(Vector3(0.05, 0.007, 0.012)), lace, Vector3(0, 0.003 - 0.008 * i, -0.04 - 0.032 * i),
			Vector3(0.25, 0, 0), Vector3.ONE, false)
	# Talón verde (guiño a Antioquia)
	_part(ft, _box(Vector3(0.04, 0.05, 0.012)), Palette.cloth(C_SCARF_GREEN, 0.6), Vector3(0, -0.03, 0.093),
		Vector3.ZERO, Vector3.ONE, false)
	if side < 0:
		thigh_l = th; shin_l = sh; foot_l = ft
	else:
		thigh_r = th; shin_r = sh; foot_r = ft


# =====================================================================
#  ANIMACIÓN PROCEDURAL
# =====================================================================

## state: idle | walk | run | sprint | jump | fall | land | stumble | enter_vehicle
## speed: velocidad horizontal real (m/s). delta: paso de tiempo.
func animate(state: String, speed: float, delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	_time += delta
	if state != _state:
		_on_state_change(_state, state)
		_state = state

	# Aceleración longitudinal y velocidad de giro filtradas (dan peso al cuerpo)
	var acc := (speed - _prev_speed) / delta
	_prev_speed = speed
	_accel_f = lerpf(_accel_f, clampf(acc, -14.0, 14.0), 1.0 - exp(-5.0 * delta))
	var yaw := global_rotation.y
	var dyaw := wrapf(yaw - _prev_yaw, -PI, PI) / delta
	_prev_yaw = yaw
	_turn_f = lerpf(_turn_f, clampf(dyaw, -8.0, 8.0), 1.0 - exp(-7.0 * delta))
	_land_t = maxf(0.0, _land_t - delta * 3.2)

	var t := {}
	for k in _joints:
		t[k] = Vector3.ZERO
	var rate := 14.0
	var plant := true             # ajustar cadera para que los pies pisen el suelo
	var plant_w := 1.0
	var root_rot := Vector3.ZERO
	var root_pos := Vector3.ZERO
	var hips_extra := 0.0

	match state:
		"jump", "fall":
			_air_t += delta
			rate = 7.0
			plant = false
			_pose_air(t, state == "jump", speed)
		"stumble":
			_stumble_t += delta
			rate = 10.0
			plant = false
			var r := _pose_stumble(t)
			root_rot = r[0]
			root_pos = r[1]
			hips_extra = r[2]
			plant_w = r[3]
		"enter_vehicle":
			_enter_t += delta
			rate = 9.0
			_pose_locomotion(t, 0.0, delta)
			_pose_enter(t)
		_:
			_air_t = 0.0
			_pose_locomotion(t, speed, delta)
			# Inclinación hacia la curva (todo el cuerpo pivota en los pies)
			var roll := clampf(_turn_f * speed * 0.03, -0.32, 0.32)
			root_rot.z = roll
	if _land_t > 0.0 and state != "stumble":
		_add_land(t, _land_t)

	# Aplicar con suavizado exponencial (inercia visual)
	var k := 1.0 - exp(-rate * delta)
	for jn in _joints:
		var node: Node3D = _joints[jn]
		if jn == "root":
			continue
		node.rotation = node.rotation.lerp(t[jn], k)
	root.rotation = root.rotation.lerp(root_rot, 1.0 - exp(-(rate * 0.8) * delta))
	root.position = root.position.lerp(root_pos, k)

	# Cadera: plantar el pie más bajo en el suelo (cinemática directa 2D)
	var target_y := hips_extra
	var dl := _leg_drop(thigh_l, shin_l)
	var dr := _leg_drop(thigh_r, shin_r)
	if plant:
		target_y += -minf(dl, dr) + _run_bob()
	elif state == "stumble":
		target_y += -minf(dl, dr) * plant_w
	_hips_y = lerpf(_hips_y, target_y, 1.0 - exp(-20.0 * delta))
	hips.position.y = HIPS_HEIGHT + _hips_y


func _on_state_change(prev: String, next: String) -> void:
	if next == "land" or ((prev == "fall" or prev == "jump") and next != "stumble"):
		_land_t = clampf(0.6 + _air_t * 0.8, 0.6, 1.0)
	if next == "stumble":
		_stumble_t = 0.0
	if next == "enter_vehicle":
		_enter_t = 0.0
	if next == "jump":
		_air_t = 0.0


## Cuánto baja el tobillo respecto a la pierna estirada (m), por cadera + rodilla.
func _leg_drop(th: Node3D, sh: Node3D) -> float:
	var a := th.rotation.x + hips.rotation.x
	var b := a + sh.rotation.x
	var vert := THIGH_LEN * cos(a) + SHIN_LEN * cos(b)
	return (THIGH_LEN + SHIN_LEN) - vert


func _run_bob() -> float:
	# Al correr hay fase de vuelo: el cuerpo sube cuando las piernas se abren
	return _move_w * _gait_g * (0.035 + 0.02 * _gait_s) * (-cos(2.0 * _phase))


func _pose_locomotion(t: Dictionary, speed: float, delta: float) -> void:
	var g_t := clampf((speed - 1.6) / 2.9, 0.0, 1.0)     # caminar → correr
	var s_t := clampf((speed - 4.5) / 2.5, 0.0, 1.0)     # correr → sprint
	var m_t := clampf(speed / 0.9, 0.0, 1.0)
	var kf := 1.0 - exp(-6.0 * delta)
	_gait_g = lerpf(_gait_g, g_t, kf)
	_gait_s = lerpf(_gait_s, s_t, kf)
	_move_w = lerpf(_move_w, m_t, 1.0 - exp(-8.0 * delta))
	var g := _gait_g
	var s := _gait_s
	var m := _move_w

	# Fase basada en la distancia recorrida (los pies no "patinan")
	var stride := lerpf(lerpf(1.4, 2.7, g), 3.7, s)      # metros por ciclo (2 pasos)
	_phase = fmod(_phase + speed * delta / stride * TAU, TAU)
	var pl := _phase
	var pr := _phase + PI

	# ---------- Reposo (respiración, peso en una pierna) ----------
	var breath := sin(_time * 1.55)
	var idle := 1.0 - m
	var accel_lean := clampf(_accel_f * 0.03, -0.3, 0.3)   # + acelera, - frena

	# ---------- Piernas ----------
	for side in [-1, 1]:
		var sfx := "l" if side < 0 else "r"
		var p: float = pl if side < 0 else pr
		var amp_t := lerpf(lerpf(0.36, 0.55, g), 0.72, s)
		var thigh := sin(p) * amp_t + lerpf(0.03, 0.28, g) + 0.08 * s
		# Balanceo: la rodilla se flexiona sobre todo al inicio (talón hacia el glúteo al correr)
		var swing := maxf(0.0, cos(p + lerpf(0.25, 0.6, g)))
		var knee_sw := lerpf(lerpf(0.8, 1.6, g), 2.0, s)
		var knee_st := lerpf(0.06, 0.3, g) * (0.5 + 0.5 * maxf(0.0, -cos(p)))
		var knee := -(knee_st + knee_sw * pow(swing, 1.3)) - 0.3 * g * maxf(0.0, sin(p))
		var foot_world := -0.32 * maxf(0.0, -sin(p)) * maxf(0.0, cos(p) + 0.3) + 0.12 * maxf(0.0, sin(p)) * (1.0 - g)
		var foot := foot_world - thigh - knee
		# reposo: pierna derecha relajada (peso en la izquierda)
		var it := 0.06 if side > 0 else -0.02
		var ik := -0.12 if side > 0 else -0.03
		t["thigh_" + sfx] = Vector3(thigh * m + it * idle, 0.0, 0.03 * side * idle - 0.02 * side * m)
		t["shin_" + sfx] = Vector3(knee * m + ik * idle, 0.0, 0.0)
		t["foot_" + sfx] = Vector3(foot * m - (it + ik) * idle, 0.0, -0.03 * side * idle)

	# ---------- Tronco ----------
	var lean := m * (0.03 + 0.08 * g + 0.16 * s) + accel_lean * (0.4 + 0.6 * m)
	var twist := m * lerpf(0.09, 0.16, g)
	t["hips"] = Vector3(-lean * 0.25, -twist * sin(pl), 0.045 * sin(pl) * m * (1.0 - g) + 0.03 * idle)
	t["spine"] = Vector3(-lean * 0.4 + 0.015 * breath * idle, twist * 0.6 * sin(pl), -0.02 * idle)
	t["chest"] = Vector3(-lean * 0.35 - 0.018 * breath * idle, twist * 0.75 * sin(pl), -0.01 * idle)
	t["neck"] = Vector3(lean * 0.35, -twist * 0.2 * sin(pl), 0.0)
	var look := sin(_time * 0.21) * 0.18 + sin(_time * 0.53) * 0.05
	t["head"] = Vector3(lean * 0.35 + 0.02 * breath * idle, look * idle - twist * 0.15 * sin(pl), -0.03 * idle)

	# ---------- Brazos (contrapeso a las piernas) ----------
	for side in [-1, 1]:
		var sfx := "l" if side < 0 else "r"
		var p: float = pl if side < 0 else pr
		var amp_a := lerpf(lerpf(0.32, 0.7, g), 1.05, s)
		var arm := -sin(p) * amp_a + 0.08 * g + 0.05 * s - accel_lean * 0.6
		var elbow := lerpf(lerpf(0.22, 1.35, g), 1.6, s) + 0.18 * maxf(0.0, -sin(p)) * m
		var out := 0.07 + 0.08 * g * m + 0.03 * breath * idle
		t["upper_arm_" + sfx] = Vector3(arm * m + 0.04 * idle, 0.0, side * out)
		t["forearm_" + sfx] = Vector3(elbow * m + 0.14 * idle, 0.0, 0.0)
		t["hand_" + sfx] = Vector3(0.1 + 0.25 * g * m, -side * 0.15, 0.0)


func _add_land(t: Dictionary, l: float) -> void:
	# Absorción del aterrizaje: rodillas, cadera baja, tronco hacia adelante
	var e := l * l * (3.0 - 2.0 * l)
	for sfx in ["l", "r"]:
		t["thigh_" + sfx] += Vector3(0.55 * e, 0, 0)
		t["shin_" + sfx] += Vector3(-1.05 * e, 0, 0)
		t["foot_" + sfx] += Vector3(0.5 * e, 0, 0)
		t["upper_arm_" + sfx] += Vector3(0.25 * e, 0, 0)
		t["forearm_" + sfx] += Vector3(0.4 * e, 0, 0)
	t["spine"] += Vector3(-0.22 * e, 0, 0)
	t["chest"] += Vector3(-0.12 * e, 0, 0)
	t["head"] += Vector3(0.2 * e, 0, 0)


func _pose_air(t: Dictionary, rising: bool, speed: float) -> void:
	var g := clampf(speed / 5.0, 0.0, 1.0)
	if rising:
		# Despegue: pierna de impulso recogida, brazos arriba
		t["thigh_l"] = Vector3(0.75 + 0.2 * g, 0, -0.03)
		t["shin_l"] = Vector3(-1.1, 0, 0)
		t["foot_l"] = Vector3(0.2, 0, 0)
		t["thigh_r"] = Vector3(-0.05 - 0.25 * g, 0, 0.03)
		t["shin_r"] = Vector3(-0.55, 0, 0)
		t["foot_r"] = Vector3(-0.35, 0, 0)
		t["upper_arm_l"] = Vector3(-0.5 * g + 0.3, 0, -0.35)
		t["upper_arm_r"] = Vector3(0.9, 0, 0.3)
		t["forearm_l"] = Vector3(0.7, 0, 0)
		t["forearm_r"] = Vector3(0.9, 0, 0)
		t["spine"] = Vector3(-0.1 - 0.1 * g, 0, 0)
		t["head"] = Vector3(0.1, 0, 0)
	else:
		# Caída: piernas buscando el suelo, brazos abiertos para equilibrio
		var w := sin(_time * 7.0) * 0.12
		t["thigh_l"] = Vector3(0.45, 0, -0.06)
		t["shin_l"] = Vector3(-0.7, 0, 0)
		t["foot_l"] = Vector3(0.15, 0, 0)
		t["thigh_r"] = Vector3(0.1, 0, 0.06)
		t["shin_r"] = Vector3(-0.45, 0, 0)
		t["foot_r"] = Vector3(0.1, 0, 0)
		t["upper_arm_l"] = Vector3(0.35 + w, 0, -0.75)
		t["upper_arm_r"] = Vector3(0.25 - w, 0, 0.8)
		t["forearm_l"] = Vector3(0.5, 0, 0)
		t["forearm_r"] = Vector3(0.6, 0, 0)
		t["spine"] = Vector3(-0.08, 0, 0)
		t["head"] = Vector3(0.12, 0, 0)


## Atropello: cae de espaldas, queda en el suelo, se incorpora a cuclillas y se
## levanta (≈1.7 s). Devuelve [rotación de root, posición de root, ajuste de cadera,
## peso de apoyo de pies].
func _pose_stumble(t: Dictionary) -> Array:
	var st := _stumble_t
	var fall := smoothstep(0.0, 0.42, st)
	var sit_up := smoothstep(0.85, 1.3, st)           # el tronco vuelve a vertical
	var crouch := smoothstep(0.8, 1.2, st) * (1.0 - smoothstep(1.3, 1.75, st))
	var down := fall * (1.0 - sit_up)
	var flail := sin(clampf(st / 0.5, 0.0, 1.0) * PI)
	var root_rot := Vector3(1.42 * down, 0.0, 0.25 * flail * (1.0 - sit_up))
	var root_pos := Vector3(0.0, 0.06 * down, 0.0)
	# Brazos: agitan al caer; en cuclillas se apoyan sobre las rodillas
	t["upper_arm_l"] = Vector3(1.6 * flail + 0.2 * down + 0.55 * crouch, 0, -0.5 * flail - 0.25 * down - 0.1 * crouch)
	t["upper_arm_r"] = Vector3(1.2 * flail + 0.3 * down + 0.45 * crouch, 0, 0.65 * flail + 0.3 * down + 0.1 * crouch)
	t["forearm_l"] = Vector3(0.9 * flail + 0.3 * down + 0.5 * crouch, 0, 0)
	t["forearm_r"] = Vector3(0.5 * flail + 0.4 * down + 0.6 * crouch, 0, 0)
	# Piernas: una se levanta con el golpe; luego cuclillas
	t["thigh_l"] = Vector3(0.7 * flail + 0.1 * down + 1.65 * crouch, 0, -0.08 * down - 0.08 * crouch)
	t["thigh_r"] = Vector3(0.25 * flail + 0.35 * down + 1.45 * crouch, 0, 0.12 * down + 0.08 * crouch)
	t["shin_l"] = Vector3(-0.6 * flail - 0.1 * down - 2.2 * crouch, 0, 0)
	t["shin_r"] = Vector3(-0.3 * flail - 0.6 * down - 1.95 * crouch, 0, 0)
	t["foot_l"] = Vector3(0.3 * down + 0.55 * crouch, 0, 0)
	t["foot_r"] = Vector3(0.3 * down + 0.5 * crouch, 0, 0)
	t["hips"] = Vector3(-0.25 * crouch, 0, 0)
	t["spine"] = Vector3(-0.35 * flail - 0.45 * crouch, 0, 0.1 * flail)
	t["chest"] = Vector3(-0.25 * crouch + 0.1 * down, 0, 0)
	t["neck"] = Vector3(0.25 * crouch, 0, 0)
	t["head"] = Vector3(-0.35 * down + 0.25 * crouch - 0.2 * flail, 0.3 * down, 0)
	return [root_rot, root_pos, 0.0, sit_up]


func _pose_enter(t: Dictionary) -> void:
	# Abre la puerta y se agacha para meterse al auto (≈0.5 s)
	var e := smoothstep(0.0, 0.35, _enter_t)
	t["upper_arm_l"] = Vector3(1.25 * e, 0, -0.2 * e)
	t["forearm_l"] = Vector3(0.35 * e, 0, 0)
	t["upper_arm_r"] = Vector3(0.5 * e, 0, 0.25 * e)
	t["forearm_r"] = Vector3(0.6 * e, 0, 0)
	t["thigh_r"] = Vector3(0.75 * e, 0, 0)
	t["shin_r"] = Vector3(-1.0 * e, 0, 0)
	t["thigh_l"] = Vector3(0.1 * e, 0, 0)
	t["shin_l"] = Vector3(-0.35 * e, 0, 0)
	t["spine"] = Vector3(-0.35 * e, -0.2 * e, 0)
	t["chest"] = Vector3(-0.15 * e, 0, 0)
	t["head"] = Vector3(0.25 * e, 0, 0)


## Fuerza una pose instantánea (útil al reaparecer o para retratos).
func snap_pose(state: String, speed: float, phase := 0.0) -> void:
	_phase = phase
	_gait_g = clampf((speed - 1.6) / 2.9, 0.0, 1.0)
	_gait_s = clampf((speed - 4.5) / 2.5, 0.0, 1.0)
	_move_w = clampf(speed / 0.9, 0.0, 1.0)
	_prev_speed = speed
	for i in 40:
		_phase = phase - speed * (1.0 / 60.0) / maxf(0.01, lerpf(lerpf(1.4, 2.7, _gait_g), 3.7, _gait_s)) * TAU
		animate(state, speed, 1.0 / 60.0)

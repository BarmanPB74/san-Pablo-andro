class_name VehicleFactory
extends RefCounted
## Construye vehículos por código (primitivas + Palette). Diseños genéricos, sin marcas.
## Uso: VehicleFactory.spawn("taxi", marker.global_transform, parent)
## El frente del auto queda hacia -Z del xform recibido (forward de Godot).
## La carrocería estática se fusiona en UNA ArrayMesh con una superficie por material
## (pocos draw calls en móvil) y se cachea por tipo+color.

const KINDS := ["taxi", "sedan", "pickup", "buseta"]

## Perfiles de física por tipo. Unidades SI. grip_* = wheel_friction_slip (~μ lateral).
const PROFILES := {
	"sedan": {
		"mass": 1250.0, "com": Vector3(0, 0.52, -0.15), "drive": "fwd",
		"torque": 148.0, "rpm_idle": 850.0, "rpm_peak": 4200.0, "rpm_max": 6300.0,
		"gears": [3.45, 2.05, 1.40, 1.07, 0.86], "final_drive": 3.95, "reverse": 3.3,
		"efficiency": 0.85, "shift_up": 5900.0, "shift_down": 2300.0, "shift_time": 0.3,
		"max_kmh": 152.0, "max_reverse_kmh": 28.0,
		"drag": 0.42, "rolling": 0.014, "brake": 36.0, "handbrake": 30.0, "handbrake_grip": 0.42,
		"engine_brake": 2.5,
		"steer_max": 0.58, "steer_min": 0.065, "steer_ref_kmh": 130.0, "steer_rate": 1.6,
		"grip_front": 0.86, "grip_rear": 0.98,
		"stiffness": 23.0, "rest": 0.30, "travel": 0.22, "damp_comp": 1.35, "damp_relax": 1.9,
		"roll_influence": 1.0, "horn_hz": 420.0,
	},
	"taxi": {
		"mass": 1080.0, "com": Vector3(0, 0.48, -0.15), "drive": "fwd",
		"torque": 118.0, "rpm_idle": 850.0, "rpm_peak": 4000.0, "rpm_max": 6200.0,
		"gears": [3.6, 2.1, 1.42, 1.08, 0.88], "final_drive": 4.1, "reverse": 3.4,
		"efficiency": 0.85, "shift_up": 5800.0, "shift_down": 2200.0, "shift_time": 0.3,
		"max_kmh": 145.0, "max_reverse_kmh": 26.0,
		"drag": 0.40, "rolling": 0.014, "brake": 31.0, "handbrake": 34.0, "handbrake_grip": 0.45,
		"engine_brake": 2.0,
		"steer_max": 0.62, "steer_min": 0.07, "steer_ref_kmh": 120.0, "steer_rate": 1.8,
		"grip_front": 0.85, "grip_rear": 0.96,
		"stiffness": 23.0, "rest": 0.30, "travel": 0.22, "damp_comp": 1.3, "damp_relax": 1.8,
		"roll_influence": 1.0, "horn_hz": 480.0,
	},
	"pickup": {
		"mass": 1850.0, "com": Vector3(0, 0.66, -0.1), "drive": "rwd",
		"torque": 285.0, "rpm_idle": 750.0, "rpm_peak": 2400.0, "rpm_max": 4300.0,
		"gears": [3.7, 2.2, 1.45, 1.0, 0.78], "final_drive": 3.73, "reverse": 3.6,
		"efficiency": 0.82, "shift_up": 3900.0, "shift_down": 1500.0, "shift_time": 0.35,
		"max_kmh": 150.0, "max_reverse_kmh": 25.0,
		"drag": 0.62, "rolling": 0.016, "brake": 50.0, "handbrake": 55.0, "handbrake_grip": 0.3,
		"engine_brake": 4.0,
		"steer_max": 0.55, "steer_min": 0.06, "steer_ref_kmh": 120.0, "steer_rate": 1.4,
		"grip_front": 0.84, "grip_rear": 0.95,
		"stiffness": 22.0, "rest": 0.36, "travel": 0.26, "damp_comp": 1.3, "damp_relax": 1.8,
		"roll_influence": 1.0, "horn_hz": 360.0,
	},
	"buseta": {
		"mass": 5000.0, "com": Vector3(0, 0.9, -0.3), "drive": "rwd",
		"torque": 470.0, "rpm_idle": 700.0, "rpm_peak": 1800.0, "rpm_max": 3200.0,
		"gears": [5.2, 2.9, 1.75, 1.18, 0.86], "final_drive": 4.3, "reverse": 5.0,
		"efficiency": 0.8, "shift_up": 2900.0, "shift_down": 1150.0, "shift_time": 0.55,
		"max_kmh": 92.0, "max_reverse_kmh": 18.0,
		"drag": 1.6, "rolling": 0.018, "brake": 125.0, "handbrake": 120.0, "handbrake_grip": 0.45,
		"engine_brake": 12.0,
		"steer_max": 0.6, "steer_min": 0.1, "steer_ref_kmh": 80.0, "steer_rate": 1.0,
		"grip_front": 0.78, "grip_rear": 0.86,
		"stiffness": 15.0, "rest": 0.42, "travel": 0.3, "damp_comp": 0.95, "damp_relax": 1.4,
		"roll_influence": 1.0, "horn_hz": 300.0,
	},
}

## Geometría por tipo (metros). fa/ra = z de ejes delantero/trasero (frente = -Z).
const SPECS := {
	"sedan": {"L": 4.40, "hw": 0.86, "r": 0.31, "tw": 0.20, "fa": -1.27, "ra": 1.33, "track": 1.48,
		"clear": 0.30, "belt": 0.80, "deck": 0.93, "hood_front": 0.86,
		"cab_b": [-0.82, 1.38], "cab_t": [-0.14, 0.96], "roof": 1.44, "cab_hw": [0.80, 0.66],
		"trunk": true, "bed": false},
	"taxi": {"L": 3.76, "hw": 0.82, "r": 0.29, "tw": 0.18, "fa": -1.19, "ra": 1.19, "track": 1.40,
		"clear": 0.29, "belt": 0.78, "deck": 0.90, "hood_front": 0.83,
		"cab_b": [-0.78, 1.84], "cab_t": [-0.08, 1.62], "roof": 1.48, "cab_hw": [0.77, 0.64],
		"trunk": false, "bed": false},
	"pickup": {"L": 5.25, "hw": 0.93, "r": 0.38, "tw": 0.26, "fa": -1.42, "ra": 1.68, "track": 1.60,
		"clear": 0.44, "belt": 1.06, "deck": 1.16, "hood_front": 1.10,
		"cab_b": [-0.92, 0.98], "cab_t": [-0.38, 0.94], "roof": 1.80, "cab_hw": [0.89, 0.76],
		"trunk": false, "bed": true},
	"buseta": {"L": 7.60, "hw": 1.15, "r": 0.46, "tw": 0.30, "fa": -2.55, "ra": 1.70, "track": 1.92,
		"clear": 0.46, "belt": 1.36, "roof": 2.82},
}

const URBAN_COLORS := [Color(0.42, 0.43, 0.45), Color(0.72, 0.73, 0.75), Color(0.42, 0.06, 0.09),
	Color(0.9, 0.9, 0.88), Color(0.08, 0.12, 0.25), Color(0.1, 0.1, 0.11)]
const BUSETA_COLORS := [[Color(0.95, 0.95, 0.92), Color(0.85, 0.1, 0.1)], [Color(0.2, 0.55, 0.85), Color(0.98, 0.8, 0.1)],
	[Color(0.15, 0.6, 0.3), Color(0.98, 0.95, 0.9)], [Color(0.98, 0.75, 0.1), Color(0.1, 0.35, 0.75)]]
const TAXI_YELLOW := Color(0.98, 0.78, 0.05)
const PLATE_YELLOW := Color(0.98, 0.8, 0.12)

static var _mesh_cache := {}


static func spawn(kind: String, xform: Transform3D, parent: Node) -> Vehicle:
	if not PROFILES.has(kind):
		push_warning("VehicleFactory: tipo desconocido '%s', uso sedan" % kind)
		kind = "sedan"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(xform.origin * 10.0)) ^ hash(kind)
	var spec: Dictionary = SPECS[kind]
	var prof: Dictionary = (PROFILES[kind] as Dictionary).duplicate(true)
	var v := Vehicle.new()
	v.name = kind.capitalize()
	v.kind = kind
	prof["wheel_radius"] = spec.r
	prof["half_width"] = spec.hw
	prof["half_length"] = spec.L * 0.5
	prof["height"] = spec.roof
	prof["door_z"] = -0.25 if kind != "buseta" else -2.9
	v.profile = prof

	# Física del cuerpo.
	v.mass = prof.mass
	v.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	v.center_of_mass = prof.com
	var h: float = spec.roof
	var w: float = spec.hw * 2.0
	var l: float = spec.L
	v.inertia = Vector3(h * h + l * l, w * w + l * l, w * w + h * h) * (v.mass / 12.0) * 0.85
	v.can_sleep = true
	# Sin amortiguación genérica de Godot: la resistencia la calcula Vehicle (aire + rodadura).
	v.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.linear_damp = 0.0
	v.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	v.angular_damp = 0.3
	v.continuous_cd = false

	# Carrocería.
	var paint := _pick_paint(kind, rng)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body_mesh(kind, paint)
	v.add_child(body)
	_add_dynamic_parts(v, kind, spec, paint, rng)
	_add_collision(v, kind, spec)
	_add_wheels(v, spec, prof)
	_add_markers(v, kind, spec)

	parent.add_child(v)
	v.global_transform = Transform3D(xform.basis.orthonormalized(), xform.origin + xform.basis.y * 0.05)
	return v


# ------------------------------------------------------------------ colores

static func _pick_paint(kind: String, rng: RandomNumberGenerator) -> Array:
	match kind:
		"taxi":
			return [TAXI_YELLOW, Color(0.05, 0.05, 0.05)]
		"buseta":
			return BUSETA_COLORS[rng.randi() % BUSETA_COLORS.size()]
	return [URBAN_COLORS[rng.randi() % URBAN_COLORS.size()], Color(0.05, 0.05, 0.05)]


static func _plate_text(rng: RandomNumberGenerator) -> String:
	var letters := "ABCDEFGHJKLMNPRSTUVWXYZ"
	var s := ""
	for i in 3:
		s += letters[rng.randi() % letters.length()]
	return "%s %03d" % [s, rng.randi() % 1000]


# ------------------------------------------------------------------ materiales propios

static var _mat_cache := {}


## Pintura con suciedad (MatActors.car_paint_dirty) que toma el color del VÉRTICE: así la pintura
## principal, franjas y acentos comparten UNA superficie. Triplanar en espacio de OBJETO (la suciedad
## no "nada" cuando el auto se mueve) y doble cara (el interior de la carrocería se ve por los vidrios).
static func paint_mat() -> Material:
	if _mat_cache.has("paint"):
		return _mat_cache["paint"]
	var m: StandardMaterial3D = (MatActors.car_paint_dirty(Color.WHITE, 0.55) as StandardMaterial3D).duplicate()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.uv1_world_triplanar = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.25
	m.roughness = 0.3
	m.clearcoat_enabled = true
	m.clearcoat = 0.45
	m.clearcoat_roughness = 0.12
	_mat_cache["paint"] = m
	return m


## Vidrio tintado con reflejo: casi negro, translúcido, especular alto (refleja cielo/reflection probe).
static func glass_mat() -> Material:
	if _mat_cache.has("glass"):
		return _mat_cache["glass"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.07, 0.08, 0.62)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.85
	m.metallic_specular = 0.9
	m.roughness = 0.04
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = false
	_mat_cache["glass"] = m
	return m


## Plástico negro texturizado (bumpers bajos, sellos, pasos de rueda, parrilla).
static func trim_mat() -> Material:
	if _mat_cache.has("trim"):
		return _mat_cache["trim"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.032, 0.035)
	m.roughness = 0.62
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache["trim"] = m
	return m


## Tela gris oscura de cojinería/tablero (UV en metros; tile 0.15 m).
static func interior_mat() -> Material:
	return MatActors.hoodie_knit(Color(0.32, 0.32, 0.34), Vector3(6.6, 6.6, 1.0))


static func chrome_mat() -> Material:
	return Palette.chrome()


# ------------------------------------------------------------------ malla de carrocería

static func _body_mesh(kind: String, paint: Array) -> ArrayMesh:
	var key := "%s_%s" % [kind, (paint[0] as Color).to_html()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var kit := Kit.new()
	if kind == "buseta":
		_build_buseta(kit, Shape.new(kind, SPECS[kind]), paint)
	else:
		_build_car(kit, Shape.new(kind, SPECS[kind]), paint)
	var m := kit.commit()
	_mesh_cache[key] = m
	return m


## Forma de la carrocería: secciones transversales (mitad derecha, de la línea central del piso a la
## línea central del techo/capó) en función de z. La malla se genera por "loft" de estas secciones.
class Shape:
	var kind: String
	var s: Dictionary
	var hl: float
	var hw: float
	var r: float
	var fa: float
	var ra: float
	var clear: float
	var belt: float
	var deck: float
	var roof: float
	var hood_front: float
	var cb0 := 0.0
	var cb1 := 0.0
	var ct0 := 0.0
	var ct1 := 0.0
	var chw0 := 0.0
	var chw1 := 0.0
	var ych: float        # línea de carácter
	var xw: float         # pared interna del paso de rueda
	var arch_r: float
	var crown := 0.035
	var rc_f := 0.34      # redondeo en planta (largo en z / entrada en x)
	var rcx_f := 0.22
	var rc_r := 0.26
	var rcx_r := 0.18
	var bed := false
	var bed_z0 := 0.0
	var rail := 0.0

	func _init(k: String, spec: Dictionary) -> void:
		kind = k
		s = spec
		hl = spec.L * 0.5
		hw = spec.hw
		r = spec.r
		fa = spec.fa
		ra = spec.ra
		clear = spec.clear
		belt = spec.belt
		roof = spec.roof
		deck = spec.get("deck", belt)
		hood_front = spec.get("hood_front", belt)
		xw = spec.track * 0.5 - spec.tw * 0.5 - 0.06
		arch_r = r + 0.075
		ych = belt - 0.06
		if k != "buseta":
			cb0 = spec.cab_b[0]
			cb1 = spec.cab_b[1]
			ct0 = spec.cab_t[0]
			ct1 = spec.cab_t[1]
			chw0 = spec.cab_hw[0]
			chw1 = spec.cab_hw[1]
		else:
			arch_r = r + 0.09
			rc_f = 0.30
			rcx_f = 0.16
			rc_r = 0.22
			rcx_r = 0.12
			crown = 0.03
		if k == "pickup":
			bed = true
			bed_z0 = cb1 + 0.04
			rail = belt + 0.32
			rc_f = 0.30
			rcx_f = 0.16
			rc_r = 0.10
			rcx_r = 0.06
		if k == "taxi":
			rc_r = 0.2
			rcx_r = 0.14

	## Media anchura en planta (esquinas redondeadas adelante y atrás).
	func w(z: float) -> float:
		var x := hw
		var df := z + hl
		var dr := hl - z
		if df < rc_f:
			var t := 1.0 - df / rc_f
			x -= rcx_f * (1.0 - sqrt(maxf(0.0, 1.0 - t * t)))
		if dr < rc_r:
			var t := 1.0 - dr / rc_r
			x -= rcx_r * (1.0 - sqrt(maxf(0.0, 1.0 - t * t)))
		# Guardabarros ensanchados sobre las ruedas.
		for a: float in [fa, ra]:
			var q := (z - a) / (arch_r + 0.3)
			if absf(q) < 1.0:
				x += 0.018 * (1.0 - q * q)
		return x

	## z de la superficie frontal (front) o trasera en planta para una x dada (para piezas que envuelven).
	func end_z(x: float, front: bool) -> float:
		var rc := rc_f if front else rc_r
		var rcx := rcx_f if front else rcx_r
		var q := clampf(1.0 - (hw - absf(x)) / rcx, 0.0, 0.999)
		var d := rc * (1.0 - sqrt(1.0 - q * q))
		return -hl + d if front else hl - d

	func top(z: float) -> float:
		var y: float
		if kind == "buseta":
			y = roof
		elif z < cb0:
			var t := clampf((z + hl) / (cb0 + hl), 0.0, 1.0)
			y = lerpf(hood_front, deck, 1.0 - pow(1.0 - t, 1.6))
		elif z <= cb1 or not bed:
			y = deck - (0.02 * clampf((z - cb1) / maxf(0.01, hl - cb1), 0.0, 1.0) if z > cb1 else 0.0)
		else:
			y = rail
		if bed and z > bed_z0:
			y = rail
		var df := z + hl
		var dr := hl - z
		if df < 0.12:
			y -= 0.06 * pow(1.0 - df / 0.12, 2.0)
		if dr < 0.10 and kind != "buseta":
			y -= 0.045 * pow(1.0 - dr / 0.10, 2.0)
		return y

	func bot(z: float) -> float:
		var y := clear + 0.01
		var df := z + hl
		var dr := hl - z
		if df < 0.45:
			y += 0.10 * pow(1.0 - df / 0.45, 2.0)
		if dr < 0.40:
			y += 0.08 * pow(1.0 - dr / 0.40, 2.0)
		for a: float in [fa, ra]:
			var dz := z - a
			if absf(dz) < arch_r:
				y = maxf(y, r + sqrt(arch_r * arch_r - dz * dz))
		return y

	## Sección de auto: 11 puntos. mode "b" = platón abierto (pickup).
	func section(z: float, mode := "n") -> PackedVector3Array:
		var W := w(z)
		var T := top(z)
		var B := bot(z)
		var F := minf(clear + 0.04, B)
		var cr := crown if not (bed and z > bed_z0) else 0.0
		var ysh := maxf(T - 0.07, ych + 0.03)
		var yc := minf(ych, ysh - 0.02)
		var y4 := clampf(B + 0.05, B, yc - 0.03)
		var y5 := clampf(maxf(B + 0.14, (B + yc) * 0.5), y4, yc - 0.015)
		var x1 := minf(xw, W - 0.1)
		var p := PackedVector3Array([Vector3(0, F, z), Vector3(x1, F, z), Vector3(x1, B, z),
			Vector3(W - 0.07, B, z), Vector3(W - 0.025, y4, z), Vector3(W - 0.004, y5, z), Vector3(W, yc, z)])
		if mode == "b":
			p.append_array([Vector3(W - 0.012, rail - 0.03, z), Vector3(W - 0.05, rail, z),
				Vector3(W - 0.075, belt, z), Vector3(0, belt, z)])
		else:
			p.append_array([Vector3(W - 0.025, ysh, z), Vector3(W - 0.085, T - 0.012, z),
				Vector3(W * 0.55, T + cr * 0.75, z), Vector3(0, T + cr, z)])
		return p

	## x de la superficie lateral a la altura y (para pegar molduras, franjas y manijas).
	func side_x(z: float, y: float) -> float:
		var p := section(z)
		for j in range(3, 7):
			if y >= p[j].y and y <= p[j + 1].y:
				return lerpf(p[j].x, p[j + 1].x, (y - p[j].y) / maxf(0.001, p[j + 1].y - p[j].y))
		return p[6].x

	# ---------- cabina (greenhouse)
	func gh_top(z: float) -> float:
		if z < ct0:
			var t := clampf((z - cb0) / (ct0 - cb0), 0.0, 1.0)
			return lerpf(deck, roof, t) + 0.025 * sin(PI * t)
		if z <= ct1:
			var t := (z - ct0) / maxf(0.01, ct1 - ct0)
			return roof + 0.02 * sin(PI * t)
		var t := clampf((z - ct1) / maxf(0.01, cb1 - ct1), 0.0, 1.0)
		return lerpf(roof, deck, t) + 0.02 * sin(PI * t)

	func gh_x(y: float) -> float:
		return lerpf(chw0, chw1, clampf((y - deck) / (roof - deck), 0.0, 1.0))

	func gh_section(z: float) -> PackedVector3Array:
		var yt := gh_top(z)
		var yb := deck - 0.04
		var y1 := deck + 0.03
		var y2 := maxf(y1, yt - 0.075)
		var y3 := maxf(y2, yt - 0.02)
		var cr := 0.04 * clampf((yt - deck) / (roof - deck), 0.0, 1.0)
		return PackedVector3Array([Vector3(gh_x(deck) + 0.01, yb, z), Vector3(gh_x(y1), y1, z),
			Vector3(gh_x(y2), y2, z), Vector3(gh_x(y3) - 0.018, y3, z),
			Vector3(maxf(0.0, gh_x(yt) - 0.075), yt, z), Vector3(0, yt + cr, z)])

	func b_pillar() -> float:
		return lerpf(cb0, cb1, 0.45) if kind != "pickup" else lerpf(cb0, cb1, 0.5)


## Estaciones a lo largo de z: base uniforme + densas en extremos y arcos + las que se pidan exactas.
static func _stations(sh: Shape, step: float, arch_n: int, exact: Array) -> Array:
	var zs: Array = []
	var z := -sh.hl
	while z < sh.hl:
		zs.append(z)
		z += step
	for d: float in [0.0, 0.015, 0.04, 0.075, 0.12, 0.18, 0.26]:
		zs.append(-sh.hl + d)
		zs.append(sh.hl - d)
	for a: float in [sh.fa, sh.ra]:
		for k in range(-arch_n, arch_n + 1):
			zs.append(a + sh.arch_r * float(k) / arch_n)
	zs.sort()
	var out: Array = []
	for q: float in zs:
		var keep := true
		for e: float in exact:
			if absf(q - e) < 0.03:
				keep = false
		if out.size() > 0 and q - (out[-1] as float) < 0.03:
			keep = false
		if keep and q >= -sh.hl - 0.001 and q <= sh.hl + 0.001:
			out.append(q)
	for e: float in exact:
		out.append(e)
	out.sort()
	return out


## Sedán / taxi (hatchback) / pickup.
static func _build_car(k: Kit, sh: Shape, paint: Array) -> void:
	var P := paint_mat()
	var G := glass_mat()
	var T := trim_mat()
	var C := chrome_mat()
	var I := interior_mat()
	var col: Color = paint[0]
	var kind := sh.kind
	var bz := sh.b_pillar()

	# ---- carrocería inferior
	var exact: Array = [sh.cb0, sh.cb1]
	if sh.bed:
		exact = [sh.cb0, sh.bed_z0, sh.hl - 0.07]
	var zs := _stations(sh, 0.13, 5, exact)
	var secs: Array = []
	var modes: Array = []
	for z: float in zs:
		if sh.bed and absf(z - sh.bed_z0) < 0.001:
			secs.append(sh.section(z, "n"))
			modes.append("n")
			secs.append(sh.section(z, "b"))
			modes.append("b")
		elif sh.bed and absf(z - (sh.hl - 0.07)) < 0.001:
			secs.append(sh.section(z, "b"))
			modes.append("b")
			secs.append(sh.section(z, "n"))
			modes.append("n")
		elif sh.bed and z > sh.bed_z0 and z < sh.hl - 0.07:
			secs.append(sh.section(z, "b"))
			modes.append("b")
		else:
			secs.append(sh.section(z))
			modes.append("n")
	var rocker_trim := kind == "pickup"
	var body_fn := func(i: int, j: int, _side: float) -> Array:
		var zm: float = ((secs[i] as PackedVector3Array)[0].z + (secs[i + 1] as PackedVector3Array)[0].z) * 0.5
		if j <= 2:
			return [T, Color.WHITE, 0]
		if j == 3 and rocker_trim:
			return [T, Color.WHITE, 0]
		if j >= 8 and zm > sh.cb0 and zm < sh.cb1:
			return []   # abertura de la cabina (se ve el interior por los vidrios)
		if j == 9 and modes[i] == "b" and modes[i + 1] == "b":
			return [T, Color.WHITE, 3]
		return [P, col, 1 if j <= 5 else 2]
	k.loft(secs, body_fn, 1.0, true)
	var cap_fn := func(j: int) -> Array:
		return [T, Color.WHITE] if j <= 2 else [P, col]
	k.ladder(secs[0], cap_fn, Vector3.FORWARD)
	k.ladder(secs[-1], cap_fn, Vector3.BACK)

	# ---- cabina
	var gz: Array = []
	for i in 6:
		gz.append(lerpf(sh.cb0, sh.ct0, i / 6.0))
	var n_roof := maxi(2, int((sh.ct1 - sh.ct0) / 0.16))
	for i in n_roof:
		gz.append(lerpf(sh.ct0, sh.ct1, float(i) / n_roof))
	for i in 5:
		gz.append(lerpf(sh.ct1, sh.cb1, i / 5.0))
	gz.append(sh.cb1)
	var side_end := sh.ct1 + (0.02 if kind == "sedan" else (-0.06 if kind == "taxi" else -0.07))
	for e: float in [bz - 0.045, bz + 0.045, side_end]:
		gz.append(e)
	gz.sort()
	var gsecs: Array = []
	var last := -INF
	for z: float in gz:
		if z - last > 0.01:
			gsecs.append(sh.gh_section(z))
			last = z
	var gh_fn := func(i: int, j: int, _side: float) -> Array:
		var zm: float = ((gsecs[i] as PackedVector3Array)[0].z + (gsecs[i + 1] as PackedVector3Array)[0].z) * 0.5
		var zone := 0 if zm < sh.ct0 else (1 if zm <= sh.ct1 else 2)
		match j:
			0:
				return [T, Color.WHITE, 0]
			1:
				if absf(zm - bz) < 0.045:
					return [T, Color.WHITE, 1]
				if zm > side_end:
					return [P, col, 1]
				return [G, Color.WHITE, 1]
			2, 3:
				return [P, col, 2]
		return [G if zone != 1 else P, Color.WHITE if zone != 1 else col, 3 + zone]
	k.loft(gsecs, gh_fn, 1.0, true)

	# ---- molduras laterales: juntas de puertas, manijas, espejos
	var door_edges: Array = [sh.cb0 + 0.06, bz, minf(sh.ct1 + 0.05, sh.ra - sh.arch_r - 0.02)]
	if kind == "taxi":
		door_edges[2] = minf(door_edges[2], sh.ra - sh.arch_r - 0.03)
	for sx: float in [-1.0, 1.0]:
		for dz: float in door_edges:
			_side_strip(k, sh, T, Color.WHITE, sx, dz - 0.006, dz + 0.006, sh.bot(dz) + 0.06, sh.ych + 0.1, 0.0025)
		for i in 2:
			var hz: float = door_edges[i + 1] - 0.16
			var hy := sh.ych - 0.035
			var hx := sh.side_x(hz, hy)
			k.col = col
			k.box(C if kind == "pickup" else P, Vector3(sx * (hx + 0.012), hy, hz), Vector3(0.022, 0.032, 0.15))
			k.col = Color.WHITE
			k.box(T, Vector3(sx * (hx + 0.002), hy, hz), Vector3(0.008, 0.05, 0.18))
		# Espejo: brazo negro + carcasa en color + luna.
		var mz := sh.cb0 + 0.13
		var my := sh.deck + 0.09
		var mx := sh.chw0 + 0.02
		k.strut(T, Vector3(sx * mx, sh.deck + 0.01, mz), Vector3(sx * (mx + 0.08), my, mz + 0.01), 0.03)
		k.col = col
		var mb := Basis(Vector3.UP, sx * -0.12)
		k.box(P, Vector3(sx * (mx + 0.13), my + 0.01, mz), Vector3(0.17, 0.1, 0.075), mb)
		k.col = Color.WHITE
		k.box(G, Vector3(sx * (mx + 0.13), my + 0.01, mz + 0.04), Vector3(0.15, 0.08, 0.008), mb)
		# Ceja negra del arco (pickup y taxi) o fina en el sedán.
		for a: float in [sh.fa, sh.ra]:
			_arch_lip(k, sh, T, sx, a, 0.05 if kind == "pickup" else 0.022)
	# Franja negra del taxi (pintura, sigue la superficie).
	if kind == "taxi":
		for sx: float in [-1.0, 1.0]:
			_side_strip(k, sh, P, Color(0.04, 0.04, 0.04), sx, sh.fa + sh.arch_r + 0.12, sh.ra - sh.arch_r - 0.12,
				sh.ych - 0.13, sh.ych - 0.08, 0.003, 12)
	# Estribos del pickup.
	if kind == "pickup":
		for sx: float in [-1.0, 1.0]:
			var x0 := sh.hw - 0.05
			k.box(T, Vector3(sx * (x0 + 0.07), sh.clear - 0.02, (sh.cb0 + sh.cb1) * 0.5),
				Vector3(0.15, 0.035, sh.cb1 - sh.cb0 - 0.2))
			for zz: float in [sh.cb0 + 0.25, sh.cb1 - 0.25]:
				k.box(T, Vector3(sx * (x0 + 0.03), sh.clear + 0.02, zz), Vector3(0.06, 0.06, 0.05))
		# Barras del platón y tapa del portón.
		k.box(C, Vector3(0, sh.rail - 0.18, sh.hl + 0.003), Vector3(0.22, 0.03, 0.01))

	# ---- limpiaparabrisas
	var wz := sh.cb0 + 0.07
	var wy := sh.gh_top(wz) + 0.012
	k.strut(T, Vector3(-sh.chw0 + 0.15, wy, wz), Vector3(-0.06, wy + 0.025, wz - 0.01 + 0.035), 0.016)
	k.strut(T, Vector3(0.0, wy, wz), Vector3(sh.chw0 - 0.2, wy + 0.025, wz + 0.035), 0.016)
	# Antena de techo (aleta).
	if kind != "taxi":
		var az := sh.ct1 - 0.12
		k.col = col
		k.prism(P, 0.02, 0.006, sh.gh_top(az) + 0.02, sh.gh_top(az) + 0.07, az - 0.09, az + 0.06, az - 0.02, az + 0.05)
		k.col = Color.WHITE

	# ---- frente: parrilla (las luces van en HeadLens, el bumper en BumperFront)
	var fz := -sh.hl - 0.004
	var ly := _head_y(sh)
	var gw: float = sh.hw - (0.5 if kind != "pickup" else 0.42)
	var gy0: float = sh.clear + 0.24
	var gy1: float = ly + (0.05 if kind != "pickup" else 0.09)
	k.quad(T, Vector3(-gw, gy0, fz), Vector3(gw, gy0, fz), Vector3(gw + 0.04, gy1, fz), Vector3(-gw - 0.04, gy1, fz), Vector3(0, gy0, 0))
	var bars := 2 if kind != "pickup" else 4
	for i in bars:
		var by := lerpf(gy0 + 0.03, gy1 - 0.03, (i + 0.5) / bars)
		k.box(C if kind == "pickup" else T, Vector3(0, by, fz - 0.008), Vector3(gw * 2.0, 0.018 if kind != "pickup" else 0.03, 0.012))
	k.box(C, Vector3(0, gy1 + 0.005, fz - 0.006), Vector3(gw * 2.0 + 0.1, 0.012, 0.012))
	# Emblema genérico (rombo cromado).
	k.box(C, Vector3(0, (gy0 + gy1) * 0.5, fz - 0.018), Vector3(0.07, 0.07, 0.01), Basis(Vector3.BACK, PI * 0.25))
	# Tapa de gasolina y escape.
	k.cyl(T, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(sh.hw * 0.55, sh.clear - 0.02, sh.hl + 0.03)), 0.03, 0.2, 8)

	# ---- bumper trasero (fijo)
	_bumper(k, sh, false, P if kind != "pickup" else C, col, T)

	# ---- interior
	_car_interior(k, sh, I, T)


static func _head_y(sh: Shape) -> float:
	return sh.top(-sh.hl + 0.02) - 0.11


static func _tail_y(sh: Shape) -> float:
	if sh.kind == "pickup":
		return sh.rail - 0.22
	return sh.top(sh.hl - 0.02) - 0.09


## Franja delgada pegada al costado (z0..z1, y0..y1), sigue la tumblehome.
static func _side_strip(k: Kit, sh: Shape, mat: Material, col: Color, sx: float, z0: float, z1: float,
		y0: float, y1: float, off: float, nz := 1) -> void:
	k.col = col
	var ny := 3
	for iz in nz:
		var za := lerpf(z0, z1, float(iz) / nz)
		var zb := lerpf(z0, z1, float(iz + 1) / nz)
		for iy in ny:
			var ya := lerpf(y0, y1, float(iy) / ny)
			var yb := lerpf(y0, y1, float(iy + 1) / ny)
			var a := Vector3(sx * (sh.side_x(za, ya) + off), ya, za)
			var b := Vector3(sx * (sh.side_x(zb, ya) + off), ya, zb)
			var c := Vector3(sx * (sh.side_x(zb, yb) + off), yb, zb)
			var d := Vector3(sx * (sh.side_x(za, yb) + off), yb, za)
			k.quad(mat, a, b, c, d, Vector3(0, (ya + yb) * 0.5, (za + zb) * 0.5))
	k.col = Color.WHITE


## Ceja del arco de rueda: banda que sigue el semicírculo, saliendo un poco del costado.
static func _arch_lip(k: Kit, sh: Shape, mat: Material, sx: float, a: float, wdt: float) -> void:
	var n := 10
	var R := sh.arch_r
	for i in n:
		var t0 := PI * float(i) / n
		var t1 := PI * float(i + 1) / n
		var pts := []
		for t: float in [t0, t1]:
			var z := a - cos(t) * R
			var y := sh.r + sin(t) * R
			var dir := Vector3(0, sin(t), -cos(t))
			var x := sh.w(z) + 0.004
			pts.append([Vector3(sx * x, y, z) + dir * -0.005, Vector3(sx * (x + 0.012), y, z) + dir * wdt])
		var c := Vector3(0, sh.r, a)
		k.quad(mat, pts[0][0], pts[0][1], pts[1][1], pts[1][0], c + Vector3(sx * 5.0, 0, 0))


## Bumper envolvente (loft a lo largo de x siguiendo la planta). front = true adelante.
static func _bumper(k: Kit, sh: Shape, front: bool, mat: Material, col: Color, lower: Material) -> void:
	var y0 := sh.clear - 0.03
	var y1 := sh.clear + 0.24
	var ys := [y0 + 0.02, y0, y0 + 0.05, y0 + 0.15, y1 - 0.03, y1, y1 + 0.01]
	var os := [-0.03, 0.015, 0.05, 0.06, 0.05, 0.012, -0.03]
	var xo := sh.hw - 0.012
	var n := 16
	var secs: Array = []
	for i in n + 1:
		var t := -1.0 + 2.0 * float(i) / n
		var x := signf(t) * xo * pow(absf(t), 0.7)
		var z := sh.end_z(x, front)
		var dx := 0.01
		var dzdx := (sh.end_z(x + dx, front) - sh.end_z(x - dx, front)) / (2.0 * dx)
		var nrm := Vector2(dzdx, -1.0).normalized() if front else Vector2(-dzdx, 1.0).normalized()
		var sec := PackedVector3Array()
		for j in ys.size():
			sec.append(Vector3(x + nrm.x * os[j], ys[j], z + nrm.y * os[j]))
		secs.append(sec)
	var fn := func(_i: int, j: int, _side: float) -> Array:
		if j <= 1:
			return [lower, Color.WHITE, 0]
		return [mat, col, 1]
	k.loft(secs, fn, 1.0 if front else -1.0, false)


static func _car_interior(k: Kit, sh: Shape, I: Material, T: Material) -> void:
	var fy := sh.clear + 0.1
	var ix := sh.chw0 - 0.04
	k.quad(I, Vector3(-ix, fy, sh.cb0), Vector3(ix, fy, sh.cb0), Vector3(ix, fy, sh.cb1), Vector3(-ix, fy, sh.cb1), Vector3(0, fy - 1.0, 0))
	# Tablero.
	var dz := sh.cb0 + 0.2
	k.prism(I, ix, ix - 0.02, sh.deck - 0.3, sh.deck - 0.01, dz - 0.2, dz + 0.22, dz - 0.18, dz + 0.1)
	k.box(T, Vector3(-0.36, sh.deck + 0.0, dz + 0.1), Vector3(0.36, 0.05, 0.14))
	# Volante (aro) y columna.
	var sw := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.45), Vector3(-0.37, sh.deck - 0.02, dz + 0.32))
	k.cyl(T, sw, 0.18, 0.03, 14, true)
	k.cyl(T, sw.translated_local(Vector3(0, 0.0, 0)), 0.05, 0.05, 8)
	k.strut(T, sw.origin, Vector3(-0.37, sh.deck - 0.1, dz + 0.1), 0.05)
	# Asientos delanteros.
	var sy := sh.clear + 0.25
	var sz := -0.1 if sh.kind != "pickup" else -0.2
	for sx: float in [-0.37, 0.37]:
		_seat(k, I, Vector3(sx, sy, sz), 0.48)
	# Banca trasera.
	var rz := minf(sz + 0.92, sh.cb1 - 0.32)
	if sh.kind == "pickup":
		rz = minf(rz, sh.cb1 - 0.36)
	_seat(k, I, Vector3(0, sy, rz), ix * 2.0 - 0.1)


static func _seat(k: Kit, I: Material, at: Vector3, wdt: float) -> void:
	k.box(I, at + Vector3(0, -0.06, 0), Vector3(wdt, 0.14, 0.5))
	var bb := Basis(Vector3.RIGHT, 0.22)
	k.box(I, at + Vector3(0, 0.3, 0.27), Vector3(wdt, 0.58, 0.12), bb)
	if wdt < 0.6:
		k.box(I, at + Vector3(0, 0.67, 0.35), Vector3(0.26, 0.16, 0.1), bb)


# ------------------------------------------------------------------ buseta

static func _bus_section(sh: Shape, z: float) -> PackedVector3Array:
	var W := sh.w(z)
	var B := sh.bot(z)
	var F := minf(sh.clear + 0.04, B)
	var x1 := minf(sh.xw, W - 0.1)
	var belt := sh.belt
	var wt := 2.28
	var R := sh.roof
	var ys := [1.07, 1.145, 1.215, 1.305]
	var p := PackedVector3Array([Vector3(0, F, z), Vector3(x1, F, z), Vector3(x1, B, z), Vector3(W - 0.06, B, z),
		Vector3(W - 0.01, minf(B + 0.06, 1.0), z)])
	for y: float in ys:
		p.append(Vector3(W, maxf(y, B + 0.07), z))
	p.append_array([Vector3(W, belt, z), Vector3(W - 0.035, belt + 0.03, z), Vector3(W - 0.035, wt - 0.02, z),
		Vector3(W, wt + 0.02, z), Vector3(W - 0.01, R - 0.16, z), Vector3(W - 0.09, R - 0.02, z),
		Vector3(W - 0.2, R, z), Vector3(0, R + 0.03, z)])
	# Frente inclinado: el parabrisas y la parte alta se recuestan hacia atrás.
	var f := clampf(1.0 - (z + sh.hl) / 0.6, 0.0, 1.0)
	for i in p.size():
		var q := p[i]
		if q.y > belt:
			q.z += 0.22 * (q.y - belt) / (R - belt) * f
			p[i] = q
	return p


static func _build_buseta(k: Kit, sh: Shape, paint: Array) -> void:
	var P := paint_mat()
	var G := glass_mat()
	var T := trim_mat()
	var C := chrome_mat()
	var I := interior_mat()
	var c1: Color = paint[0]
	var c2: Color = paint[1]
	var white := Color(0.95, 0.95, 0.93)
	var stripes := [Color(0.85, 0.1, 0.08), Color(0.98, 0.8, 0.1), Color(0.1, 0.6, 0.25)]
	var hl := sh.hl
	var hw := sh.hw
	var door0 := sh.fa + sh.r + 0.12 + 0.05
	var door1 := door0 + 0.86
	var pillars: Array = []
	var pz := -hl + 1.4
	while pz < hl - 0.3:
		pillars.append(pz)
		pz += 0.95
	var exact: Array = [door0, door1]
	for q: float in pillars:
		exact.append(q - 0.05)
		exact.append(q + 0.05)
	var zs := _stations(sh, 0.4, 4, exact)
	var secs: Array = []
	for z: float in zs:
		secs.append(_bus_section(sh, z))
	var in_pillar := func(zm: float) -> bool:
		for q: float in pillars:
			if absf(zm - q) < 0.05:
				return true
		return false
	var fn := func(i: int, j: int, side: float) -> Array:
		var zm: float = ((secs[i] as PackedVector3Array)[0].z + (secs[i + 1] as PackedVector3Array)[0].z) * 0.5
		var door := side > 0.0 and zm > door0 and zm < door1
		if j <= 2:
			return [T, Color.WHITE, 0]
		if door and j >= 3 and j <= 9:
			return [G, Color.WHITE, 4] if j >= 4 else [T, Color.WHITE, 0]
		match j:
			3, 4, 8:
				return [P, c1, 1]
			5, 6, 7:
				return [P, stripes[j - 5], 1]
			9, 11:
				return [T, Color.WHITE, 2]
			10:
				return [T, Color.WHITE, 2] if in_pillar.call(zm) or door else [G, Color.WHITE, 3]
			12:
				return [P, c2, 5]
		return [P, white, 6]
	k.loft(secs, fn, 1.0, true)
	var cap_fn := func(j: int) -> Array:
		if j <= 2:
			return [T, Color.WHITE]
		match j:
			3, 4, 8:
				return [P, c1]
			5, 6, 7:
				return [P, stripes[j - 5]]
			9, 11:
				return [T, Color.WHITE]
			10:
				return [G, Color.WHITE]
			12:
				return [P, c2]
		return [P, white]
	k.ladder(secs[0], cap_fn, Vector3.FORWARD)
	var rear_fn := func(j: int) -> Array:
		if j == 10:
			return [G, Color.WHITE]
		return cap_fn.call(j)
	k.ladder(secs[-1], rear_fn, Vector3.BACK)

	# Marco de puerta, estribo, parante central del parabrisas.
	var dx := sh.w((door0 + door1) * 0.5) + 0.006
	for zz: float in [door0, (door0 + door1) * 0.5, door1]:
		k.box(T, Vector3(dx, 1.35, zz), Vector3(0.012, 1.75, 0.04))
	k.box(T, Vector3(dx, 1.35, (door0 + door1) * 0.5), Vector3(0.012, 0.04, 0.86))
	k.box(T, Vector3(hw + 0.12, sh.clear + 0.02, (door0 + door1) * 0.5), Vector3(0.26, 0.05, 0.86))
	var fz0 := -hl - 0.01
	k.strut(T, Vector3(0, sh.belt + 0.03, fz0), Vector3(0, 2.26, fz0 + 0.22 * (2.26 - sh.belt) / (sh.roof - sh.belt)), 0.05)
	# Letrero de ruta (caja) y parrilla.
	k.box(T, Vector3(0, 2.46, -hl + 0.14), Vector3(1.5, 0.24, 0.06))
	k.box(T, Vector3(0, 0.84, -hl - 0.008), Vector3(1.1, 0.3, 0.02))
	for i in 4:
		k.box(C, Vector3(0, 0.73 + i * 0.075, -hl - 0.02), Vector3(1.1, 0.022, 0.012))
	# Escotilla de techo y A/C.
	k.prism(T, 0.5, 0.42, sh.roof + 0.02, sh.roof + 0.12, 0.1, 1.1, 0.18, 1.0)
	k.prism(P, 0.45, 0.4, sh.roof + 0.02, sh.roof + 0.09, -2.4, -1.6, -2.35, -1.65)
	# Espejos de brazo.
	for sx: float in [-1.0, 1.0]:
		k.strut(T, Vector3(sx * (hw - 0.05), 2.0, -hl + 0.12), Vector3(sx * (hw + 0.28), 2.05, -hl - 0.22), 0.035)
		k.strut(T, Vector3(sx * (hw + 0.28), 2.05, -hl - 0.22), Vector3(sx * (hw + 0.3), 1.62, -hl - 0.24), 0.03)
		k.box(T, Vector3(sx * (hw + 0.3), 1.8, -hl - 0.26), Vector3(0.12, 0.42, 0.06))
		k.box(G, Vector3(sx * (hw + 0.3), 1.8, -hl - 0.225), Vector3(0.1, 0.38, 0.01))
		for a: float in [sh.fa, sh.ra]:
			_arch_lip(k, sh, T, sx, a, 0.04)
	# Atrás: bumper, escalera.
	k.box(T, Vector3(0, 0.52, hl + 0.06), Vector3(hw * 2.0, 0.2, 0.14))
	for i in 5:
		k.box(C, Vector3(-hw + 0.3, 1.9 + i * 0.18, hl + 0.05), Vector3(0.3, 0.025, 0.025))
	for sx: float in [-1.0, 1.0]:
		k.box(C, Vector3(-hw + 0.3 + sx * 0.15, 2.25, hl + 0.04), Vector3(0.025, 0.85, 0.025))
	# Interior: piso, paredes bajas, techo, sillas, puesto del conductor.
	var fy := 0.92
	var ix := hw - 0.06
	k.quad(I, Vector3(-ix, fy, -hl + 0.2), Vector3(ix, fy, -hl + 0.2), Vector3(ix, fy, hl - 0.1), Vector3(-ix, fy, hl - 0.1), Vector3(0, -5, 0))
	k.quad(I, Vector3(-ix, sh.roof - 0.06, -hl + 0.3), Vector3(ix, sh.roof - 0.06, -hl + 0.3), Vector3(ix, sh.roof - 0.06, hl - 0.1),
		Vector3(-ix, sh.roof - 0.06, hl - 0.1), Vector3(0, 10, 0))
	for sx: float in [-1.0, 1.0]:
		k.quad(I, Vector3(sx * ix, fy, -hl + 0.2), Vector3(sx * ix, sh.belt + 0.03, -hl + 0.2), Vector3(sx * ix, sh.belt + 0.03, hl - 0.1),
			Vector3(sx * ix, fy, hl - 0.1), Vector3(sx * 10.0, 1, 0))
	var z := door1 + 0.25
	while z < hl - 0.5:
		for sx: float in [-1.0, 1.0]:
			_seat(k, I, Vector3(sx * 0.62, fy + 0.45, z), 0.85)
		z += 0.78
	_seat(k, I, Vector3(-0.6, fy + 0.4, -hl + 1.05), 0.48)
	var sw := Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(-0.6, 1.75, -hl + 0.62))
	k.cyl(T, sw, 0.22, 0.03, 14, true)
	k.prism(I, hw - 0.1, hw - 0.12, 1.2, 1.55, -hl + 0.15, -hl + 0.5, -hl + 0.22, -hl + 0.45)


# ------------------------------------------------------------------ piezas dinámicas

static func _add_dynamic_parts(v: Vehicle, kind: String, s: Dictionary, paint: Array, rng: RandomNumberGenerator) -> void:
	var sh := Shape.new(kind, s)
	var hl: float = s.L * 0.5
	var hw: float = s.hw
	var is_bus := kind == "buseta"
	var light_y: float = _head_y(sh) if not is_bus else 0.8
	var tail_y: float = _tail_y(sh) if not is_bus else 1.0

	# Faros: tiras con UV del atlas MatActors.headlight (Vehicle cambia la emisión con set_lights).
	var kh := Kit.new()
	var hm := MatActors.headlight(0.0)
	var hh := 0.15 if kind != "pickup" else 0.19
	if is_bus:
		hh = 0.2
	for sx: float in [-1.0, 1.0]:
		var xi: float = hw - (0.46 if not is_bus else 0.62)
		_lens_strip(kh, sh, hm, true, sx, xi, hw - 0.035, light_y, hh, Rect2(0, 0, 1, 1))
	v.head_lens = MeshInstance3D.new()
	v.head_lens.name = "HeadLens"
	v.head_lens.mesh = _cached_mesh("head_" + kind, kh)
	v.add_child(v.head_lens)

	# Stops: esquinas + barra LED horizontal (sedán/taxi), como los SUV modernos.
	var kt := Kit.new()
	var tm := MatActors.taillight(0.0)
	for sx: float in [-1.0, 1.0]:
		if kind == "pickup":
			_lens_vertical(kt, sh, tm, sx, tail_y, 0.42, 0.13)
		elif is_bus:
			_lens_strip(kt, sh, tm, false, sx, hw - 0.5, hw - 0.01, tail_y, 0.2, Rect2(0, 0, 1, 1))
		else:
			_lens_strip(kt, sh, tm, false, sx, hw - 0.42, hw - 0.02, tail_y, 0.12, Rect2(0, 0, 1, 1))
	if kind == "sedan" or kind == "taxi":
		_lens_strip(kt, sh, tm, false, 1.0, -(hw - 0.42), hw - 0.42, tail_y + 0.035, 0.024, Rect2(0.3, 0.25, 0.4, 0.03), 2)
	v.tail_lens = MeshInstance3D.new()
	v.tail_lens.name = "TailLens"
	v.tail_lens.mesh = _cached_mesh("tail_" + kind, kt)
	v.add_child(v.tail_lens)

	var spot := SpotLight3D.new()
	spot.name = "Headlights"
	spot.position = Vector3(0, light_y, -hl - 0.1)
	spot.rotation = Vector3(deg_to_rad(-6.0), 0, 0)
	spot.spot_range = 30.0
	spot.spot_angle = 38.0
	spot.light_energy = 3.0
	spot.light_color = Color(1.0, 0.95, 0.85)
	spot.shadow_enabled = false
	v.add_child(spot)
	v.head_spots.append(spot)

	# Placas del atlas (públicas = blancas en taxi y buseta).
	var seed_text := _plate_text(rng)
	var pidx := MatActors.plate_index(seed_text, kind == "taxi" or is_bus)
	var plate_text: String = MatActors.PLATE_TEXTS[pidx]

	# Bumper delantero (pieza que se deforma) + placa delantera dentro del mismo pivote.
	var bk := Kit.new()
	var bmat := paint_mat()
	if kind == "pickup":
		bmat = chrome_mat()
	elif is_bus:
		bmat = trim_mat()
	_bumper(bk, sh, true, bmat, paint[0], trim_mat())
	if not is_bus:
		# Exploradoras y toma de aire.
		for sx: float in [-1.0, 1.0]:
			var fx: float = sx * (hw - 0.22)
			var fz := sh.end_z(fx, true) - 0.06
			bk.box(trim_mat(), Vector3(fx, s.clear + 0.06, fz), Vector3(0.2, 0.07, 0.02))
			bk.box(chrome_mat(), Vector3(fx, s.clear + 0.06, fz - 0.011), Vector3(0.09, 0.035, 0.004))
	var bumper := MeshInstance3D.new()
	bumper.name = "BumperFront"
	bumper.mesh = _cached_mesh("bumper_%s_%s" % [kind, (paint[0] as Color).to_html()], bk)
	var pivot := Node3D.new()
	pivot.name = "BumperPivot"
	v.add_child(pivot)
	pivot.add_child(bumper)
	v.bumper_front = pivot
	var front_plate_y: float = s.clear + 0.11
	_add_plate(pivot, pidx, Vector3(0, front_plate_y, -hl - 0.075), true)
	var rear_plate_y: float = s.clear + 0.4
	var rear_plate_z := hl + 0.006
	if kind == "pickup":
		rear_plate_y = s.clear + 0.45
	elif is_bus:
		rear_plate_y = 0.86
	_add_plate(v, pidx, Vector3(0, rear_plate_y, rear_plate_z), false)

	if kind == "taxi":
		var sign_k := Kit.new()
		var cz: float = (s.cab_t[0] + s.cab_t[1]) * 0.5 - 0.15
		var ry := sh.gh_top(cz) + 0.03
		sign_k.col = Color(0.97, 0.97, 0.95)
		sign_k.prism(paint_mat(), 0.27, 0.25, ry + 0.03, ry + 0.19, cz - 0.1, cz + 0.1, cz - 0.075, cz + 0.075)
		sign_k.col = Color.WHITE
		sign_k.box(trim_mat(), Vector3(0, ry + 0.015, cz), Vector3(0.5, 0.03, 0.16))
		var sign_mi := MeshInstance3D.new()
		sign_mi.name = "TaxiSign"
		sign_mi.mesh = _cached_mesh("taxi_sign", sign_k)
		v.add_child(sign_mi)
		for dir: float in [-1.0, 1.0]:
			_add_label(v, "TAXI", Vector3(0, ry + 0.11, cz + dir * 0.092), PI if dir < 0 else 0.0, 40, 0.0028, Color.BLACK)
		var num := "%04d" % (rng.randi() % 10000)
		for sx: float in [-1.0, 1.0]:
			var ly := sh.ych - 0.2
			_add_label(v, num, Vector3(sx * (sh.side_x(s.ra - 0.75, ly) + 0.008), ly, s.ra - 0.75), sx * PI * 0.5, 44, 0.0026, Color.BLACK)
			_add_label(v, plate_text, Vector3(sx * (sh.side_x(-0.15, ly) + 0.008), ly, -0.15), sx * PI * 0.5, 30, 0.0026, Color.BLACK)
	elif is_bus:
		_add_label(v, "BOSTON · CENTRO", Vector3(0, 2.46, -hl + 0.105), PI, 40, 0.0028, Color(1.0, 0.62, 0.1))
		for sx: float in [-1.0, 1.0]:
			_add_label(v, "TRANSPORTES SAN PABLO", Vector3(sx * (hw + 0.03), 0.86, 0.4), sx * PI * 0.5, 40, 0.0035, Color(0.08, 0.1, 0.2))
			_add_label(v, "%03d" % (rng.randi() % 1000), Vector3(sx * (hw + 0.03), 2.5, -hl + 1.0), sx * PI * 0.5, 48, 0.004, Color(0.1, 0.1, 0.1))
		_add_label(v, "%03d" % (rng.randi() % 1000), Vector3(0, 2.0, hl + 0.01), 0.0, 64, 0.004, Color(0.95, 0.95, 0.9))

	# Humo de motor dañado.
	var sm := CPUParticles3D.new()
	sm.name = "Smoke"
	sm.emitting = false
	sm.amount = 18
	sm.lifetime = 1.6
	var puff := SphereMesh.new()
	puff.radius = 0.18
	puff.height = 0.36
	puff.radial_segments = 8
	puff.rings = 4
	puff.material = Palette.concrete()
	sm.mesh = puff
	sm.direction = Vector3.UP
	sm.spread = 25.0
	sm.initial_velocity_min = 0.6
	sm.initial_velocity_max = 1.2
	sm.gravity = Vector3(0, 0.8, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 0.0))
	sm.scale_amount_curve = curve
	sm.position = Vector3(0, (s.get("deck", s.belt) as float) + 0.1, -hl + 0.5) if not is_bus else Vector3(0, 1.0, -hl + 0.3)
	v.add_child(sm)
	v.smoke = sm

	# Pito.
	var hp := AudioStreamPlayer3D.new()
	hp.name = "Horn"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.15
	hp.stream = gen
	hp.unit_size = 12.0
	hp.position = Vector3(0, 0.6, -hl + 0.3)
	v.add_child(hp)
	v.horn_player = hp


## Tira de lente que envuelve la esquina en planta (x de xi a xo del lado sx), centrada en y, alto h.
## uv: sub-rectángulo de la mitad de atlas (u crece hacia afuera: el ámbar queda en la esquina).
static func _lens_strip(k: Kit, sh: Shape, mat: Material, front: bool, sx: float, xi: float, xo: float,
		y: float, h: float, uv: Rect2, segs := 5) -> void:
	var off := 0.006
	var prev := []
	for i in segs + 1:
		var t := float(i) / segs
		var x := lerpf(xi, xo, t)
		var dx := 0.01
		var dzdx := (sh.end_z(x + dx, front) - sh.end_z(x - dx, front)) / (2.0 * dx)
		var n := Vector2(dzdx, -1.0).normalized() if front else Vector2(-dzdx, 1.0).normalized()
		var z := sh.end_z(x, front)
		var px := (x + n.x * off) * sx
		var pz := z + n.y * off
		var u := uv.position.x + uv.size.x * t
		var cur := [Vector3(px, y + h * 0.5, pz), Vector3(px, y - h * 0.5, pz), u]
		if i > 0:
			var out := Vector3(0, 0, -1.0 if front else 1.0)
			k.quad_uv(mat, prev[0], cur[0], cur[1], prev[1],
				Vector2(prev[2], uv.position.y), Vector2(cur[2], uv.position.y),
				Vector2(cur[2], uv.end.y), Vector2(prev[2], uv.end.y), out)
		prev = cur


## Stop vertical (pickup): lente girada 90° en la esquina trasera.
static func _lens_vertical(k: Kit, sh: Shape, mat: Material, sx: float, y: float, h: float, wdt: float) -> void:
	var x0 := sh.hw - wdt - 0.01
	var x1 := sh.hw - 0.01
	var z0 := sh.end_z(x0, false) + 0.006
	var z1 := sh.end_z(x1, false) + 0.006
	var a := Vector3(sx * x0, y + h * 0.5, z0)
	var b := Vector3(sx * x1, y + h * 0.5, z1)
	var c := Vector3(sx * x1, y - h * 0.5, z1)
	var d := Vector3(sx * x0, y - h * 0.5, z0)
	# u del atlas a lo largo de la altura, v a lo ancho.
	k.quad_uv(mat, a, b, c, d, Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector3(0, 0, 1))


## Las mallas se cachean (y se comparten entre autos del mismo tipo).
static func _cached_mesh(key: String, kit: Kit) -> ArrayMesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = kit.commit()
	return _mesh_cache[key]


## Placa del atlas MatActors.plate (0.33 x 0.16 m) con marco negro.
static func _add_plate(parent: Node3D, idx: int, pos: Vector3, front: bool) -> void:
	var key := "plate_%d_%s" % [idx, front]
	if not _mesh_cache.has(key):
		var k := Kit.new()
		var dz := -1.0 if front else 1.0
		var hw := 0.165
		var hh := 0.08
		k.box(trim_mat(), Vector3(0, 0, -dz * 0.004), Vector3(0.35, 0.18, 0.008))
		var z := dz * 0.001
		var a := Vector3(-hw * dz * -1.0, hh, z)
		var b := Vector3(hw * dz * -1.0, hh, z)
		# Visto de frente (desde -Z) la izquierda del observador es +X.
		if front:
			a = Vector3(hw, hh, z)
			b = Vector3(-hw, hh, z)
		else:
			a = Vector3(-hw, hh, z)
			b = Vector3(hw, hh, z)
		var c := Vector3(b.x, -hh, z)
		var d := Vector3(a.x, -hh, z)
		k.quad_uv(MatActors.plate(idx), a, b, c, d, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector3(0, 0, dz))
		_mesh_cache[key] = k.commit()
	var mi := MeshInstance3D.new()
	mi.name = "PlateFront" if front else "PlateRear"
	mi.mesh = _mesh_cache[key]
	mi.position = pos
	parent.add_child(mi)


static func _add_label(v: Node3D, text: String, pos: Vector3, rot_y: float, size: int, px: float, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 0
	l.double_sided = false
	l.shaded = true
	l.position = pos
	l.rotation.y = rot_y
	v.add_child(l)
	return l


# ------------------------------------------------------------------ colisión, ruedas, marcadores

static func _add_collision(v: Vehicle, kind: String, s: Dictionary) -> void:
	var hl: float = s.L * 0.5
	var hw: float = s.hw
	if kind == "buseta":
		_box_shape(v, Vector3(0, (s.clear + s.roof) * 0.5, 0), Vector3(hw * 2.0, s.roof - s.clear, s.L))
		return
	_box_shape(v, Vector3(0, (s.clear + s.belt) * 0.5, 0), Vector3(hw * 2.0, s.belt - s.clear, s.L + 0.1))
	var cb: Array = s.cab_b
	var ct: Array = s.cab_t
	var z0: float = (cb[0] + ct[0]) * 0.5
	var z1: float = (cb[1] + ct[1]) * 0.5
	_box_shape(v, Vector3(0, (s.belt + s.roof) * 0.5, (z0 + z1) * 0.5), Vector3(s.cab_hw[0] * 2.0, s.roof - s.belt + 0.05, z1 - z0))
	if s.bed:
		_box_shape(v, Vector3(0, s.belt + 0.16, (cb[1] + hl) * 0.5 + 0.02), Vector3(hw * 2.0, 0.32, hl - cb[1]))


static func _box_shape(v: Vehicle, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	v.add_child(cs)


static func _add_wheels(v: Vehicle, s: Dictionary, prof: Dictionary) -> void:
	var r: float = s.r
	var k: float = prof.stiffness
	var rest: float = prof.rest
	var com_z: float = (prof.com as Vector3).z
	var wb: float = s.ra - s.fa
	var front_frac: float = (s.ra - com_z) / wb * 0.5   # fracción del peso por rueda delantera
	var rear_frac: float = 0.5 - front_frac
	for axle in [0, 1]:
		var z: float = s.fa if axle == 0 else s.ra
		var frac: float = front_frac if axle == 0 else rear_frac
		var sag := 9.81 * frac / k
		# Godot 4.3 lanza el rayo desde hardpoint+r y escala la distancia por (rest+r)/(rest+2r);
		# despejamos la altura del hardpoint para que el auto quede con el origen en el piso.
		var f := (rest + 2.0 * r) / (rest + r)
		var hp_y := (rest - sag + r) * f - r
		for sx: float in [-1.0, 1.0]:
			var w := VehicleWheel3D.new()
			w.name = ("Front" if axle == 0 else "Rear") + ("L" if sx < 0 else "R")
			w.position = Vector3(sx * s.track * 0.5, hp_y, z)
			w.rotation.y = PI   # así engine_force > 0 avanza hacia -Z
			w.wheel_radius = r
			w.wheel_rest_length = rest
			w.suspension_travel = prof.travel
			w.suspension_stiffness = k
			w.suspension_max_force = prof.mass * 9.81 * 1.5
			w.damping_compression = prof.damp_comp
			w.damping_relaxation = prof.damp_relax
			w.wheel_friction_slip = prof.grip_front if axle == 0 else prof.grip_rear
			w.wheel_roll_influence = prof.roll_influence
			w.use_as_steering = axle == 0
			var drive: String = prof.drive
			w.use_as_traction = drive == "awd" or (drive == "fwd" and axle == 0) or (drive == "rwd" and axle == 1)
			v.add_child(w)
			# Malla visual aparte (Vehicle corrige su altura: Godot 4.3 hunde la rueda en el piso).
			var vis := Node3D.new()
			vis.name = w.name + "Visual"
			vis.transform = w.transform
			var mi := MeshInstance3D.new()
			mi.mesh = _wheel_mesh(r, s.tw, s.L > 6.0)
			# La rueda está rotada 180°: el exterior local es +X para la izquierda y -X para la derecha.
			if sx > 0:
				mi.rotation.y = PI
			vis.add_child(mi)
			v.add_child(vis)
			v.wheel_visuals.append(vis)
			v.wheel_hardpoints.append(hp_y)
			v.all_wheels.append(w)
			if axle == 0:
				v.front_wheels.append(w)
			else:
				v.rear_wheels.append(w)



## Rueda: neumático torneado con perfil redondeado y UV para MatActors.tire() (banda de rodamiento en
## v 0..0.5, flancos con los discos del atlas), rin = quad con MatActors.rim() y fondo oscuro detrás.
## Eje = X local, rin hacia +X.
static func _wheel_mesh(r: float, tw: float, heavy: bool) -> ArrayMesh:
	var key := "wheel_%.2f_%.2f_%s" % [r, tw, heavy]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var k := Kit.new()
	var tire := MatActors.tire()
	var dark := trim_mat()
	var h := tw * 0.5
	var rim_r := r * (0.66 if not heavy else 0.6)
	# Perfil (radio, eje). kind: 0 = flanco interior, 1 = rodamiento, 2 = flanco exterior.
	var prof := [
		[rim_r + 0.01, -h * 0.82, 0], [r * 0.8, -h * 0.98, 0], [r * 0.93, -h * 0.96, 0], [r - 0.012, -h * 0.8, 0],
		[r - 0.002, -h * 0.5, 1], [r, 0.0, 1], [r - 0.002, h * 0.5, 1], [r - 0.012, h * 0.8, 2],
		[r * 0.93, h * 0.96, 2], [r * 0.8, h * 0.98, 2], [rim_r + 0.01, h * 0.82, 2]]
	var segs := 22
	var gid := k.new_group()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for j in prof.size() - 1:
			var p0: Array = prof[j]
			var p1: Array = prof[j + 1]
			var tread: bool = p0[2] == 1 or p1[2] == 1
			if (p0[2] as int) == 0 and (p1[2] as int) == 1:
				tread = true
			var pts := []
			var uvs := []
			for q in [[p0, a0], [p1, a0], [p1, a1], [p0, a1]]:
				var pr: Array = q[0]
				var ang: float = q[1]
				var rad: float = pr[0]
				var ax: float = pr[1]
				pts.append(Vector3(ax, cos(ang) * rad, sin(ang) * rad))
				if tread:
					uvs.append(Vector2(ang / TAU, clampf((ax + h * 0.8) / (h * 1.6), 0.0, 1.0) * 0.5))
				else:
					var cu := 0.25 if ax > 0.0 else 0.75
					var rr := rad / r * 0.245
					uvs.append(Vector2(cu + cos(ang) * rr, 0.75 + sin(ang) * rr))
			var mid: Vector3 = (pts[0] + pts[2]) * 0.5
			var out := Vector3(0, mid.y, mid.z).normalized() * 0.3 + Vector3(signf(mid.x) * (0.0 if tread else 1.0), 0, 0)
			k.col = Color.WHITE
			k.quad_uv(tire, pts[0], pts[1], pts[2], pts[3], uvs[0], uvs[1], uvs[2], uvs[3], out, gid)
	# Fondo del rin (barril oscuro + disco) y rin con alfa.
	var axis := Basis(Vector3.FORWARD, PI * 0.5)
	k.cyl(dark, Transform3D(axis, Vector3(h * 0.3, 0, 0)), rim_r + 0.012, h * 1.1, 14, true)
	k.cyl(dark, Transform3D(axis, Vector3(-h * 0.25, 0, 0)), rim_r + 0.012, 0.01, 14)
	var rx := h * 0.8
	var rr2 := rim_r * 1.02
	k.quad_uv(MatActors.rim(), Vector3(rx, rr2, -rr2), Vector3(rx, rr2, rr2), Vector3(rx, -rr2, rr2), Vector3(rx, -rr2, -rr2),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector3.RIGHT)
	var m := k.commit()
	_mesh_cache[key] = m
	return m


static func _add_markers(v: Vehicle, kind: String, s: Dictionary) -> void:
	var seat := Marker3D.new()
	seat.name = "Seat"
	if kind == "buseta":
		seat.position = Vector3(-0.6, 1.3, -s.L * 0.5 + 0.9)
	else:
		seat.position = Vector3(-0.38, s.clear + 0.25, -0.15)
	v.add_child(seat)
	v.seat = seat
	var anchor := Node3D.new()
	anchor.name = "CameraAnchor"
	anchor.position = Vector3(0, s.roof * 0.85, 0.3)
	v.add_child(anchor)
	v.camera_anchor = anchor



# ------------------------------------------------------------------ Kit de mallas

## Acumula geometría por material y la convierte en una ArrayMesh (1 superficie/material).
## Normales: SurfaceTool.generate_normals con grupos de suavizado (FLAT = cara plana).
## Cada vértice lleva color (`col`, usado por paint_mat) y UV (planar en metros si no se da).
class Kit:
	const FLAT := 4294967295
	var _surfaces := {}
	var _order: Array[Material] = []
	var col := Color.WHITE
	var tri_count := 0
	var _group := 0

	func new_group() -> int:
		_group += 16
		return _group

	func _st(mat: Material) -> SurfaceTool:
		if not _surfaces.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_surfaces[mat] = st
			_order.append(mat)
		return _surfaces[mat]

	## Triángulo orientado hacia `outward` (Godot: caras frontales en sentido horario).
	func tri_uv(mat: Material, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2,
			outward: Vector3, sg := FLAT) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			return
		if n.dot(outward) > 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		var st := _st(mat)
		st.set_smooth_group(sg)
		st.set_color(col)
		st.set_uv(ua)
		st.add_vertex(a)
		st.set_uv(ub)
		st.add_vertex(b)
		st.set_uv(uc)
		st.add_vertex(c)
		tri_count += 1

	func tri(mat: Material, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
		var n := (b - a).cross(c - a).abs()
		var f := func(p: Vector3) -> Vector2:
			if n.x >= n.y and n.x >= n.z:
				return Vector2(p.z, -p.y)
			if n.y >= n.z:
				return Vector2(p.x, p.z)
			return Vector2(p.x, -p.y)
		tri_uv(mat, a, b, c, f.call(a), f.call(b), f.call(c), outward)

	func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3) -> void:
		var out := (a + b + c + d) * 0.25 - center
		tri(mat, a, b, c, out)
		tri(mat, a, c, d, out)

	func quad_uv(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2,
			uc: Vector2, ud: Vector2, outward: Vector3, sg := FLAT) -> void:
		tri_uv(mat, a, b, c, ua, ub, uc, outward, sg)
		tri_uv(mat, a, c, d, ua, uc, ud, outward, sg)

	## Loft de secciones (mismo número de puntos). seg_fn(i, j, side) -> [mat, color, banda] o [] (hueco).
	## sign orienta las normales (+1: perfil de abajo hacia arriba en la mitad +X, estaciones hacia +Z).
	## mirror: duplica en -X. Bandas distintas = arista viva; tiras entre estaciones de igual z = planas.
	func loft(secs: Array, seg_fn: Callable, sign := 1.0, mirror := true) -> void:
		var gid := new_group()
		var n: int = (secs[0] as PackedVector3Array).size()
		var us: Array = []
		for s: PackedVector3Array in secs:
			var u := PackedFloat32Array()
			u.resize(n)
			var acc := 0.0
			for j in n:
				if j > 0:
					acc += s[j].distance_to(s[j - 1])
				u[j] = acc
			us.append(u)
		var sides := [1.0, -1.0] if mirror else [1.0]
		for i in secs.size() - 1:
			var s0: PackedVector3Array = secs[i]
			var s1: PackedVector3Array = secs[i + 1]
			var u0: PackedFloat32Array = us[i]
			var u1: PackedFloat32Array = us[i + 1]
			var flat_strip := mirror
			if mirror:
				for j in n:
					if absf(s0[j].z - s1[j].z) > 1e-4:
						flat_strip = false
						break
			for j in n - 1:
				for side: float in sides:
					var info: Array = seg_fn.call(i, j, side)
					if info.is_empty():
						continue
					var m := Vector3(side, 1, 1)
					var a := s0[j] * m
					var b := s0[j + 1] * m
					var c := s1[j + 1] * m
					var d := s1[j] * m
					var out := ((b - a) + (c - d)).cross((d - a) + (c - b)) * sign * side
					if out.length_squared() < 1e-14:
						out = Vector3(0, 0, 1)
					var sg: int = FLAT if flat_strip else gid + int(info[2])
					col = info[1]
					var va := (s0[j].z if mirror else s0[j].x)
					var vd := (s1[j].z if mirror else s1[j].x)
					quad_uv(info[0], a, b, c, d, Vector2(u0[j] * side, va), Vector2(u0[j + 1] * side, va),
						Vector2(u1[j + 1] * side, vd), Vector2(u1[j] * side, vd), out, sg)
		col = Color.WHITE

	## Tapa de una sección simétrica en bandas horizontales (permite material/color por banda).
	func ladder(sec: PackedVector3Array, band_fn: Callable, outward: Vector3) -> void:
		for j in sec.size() - 1:
			var info: Array = band_fn.call(j)
			if info.is_empty():
				continue
			var a := sec[j]
			var b := sec[j + 1]
			var c := Vector3(-b.x, b.y, b.z)
			var d := Vector3(-a.x, a.y, a.z)
			col = info[1]
			quad_uv(info[0], a, b, c, d, Vector2(a.x, -a.y), Vector2(b.x, -b.y), Vector2(c.x, -c.y), Vector2(d.x, -d.y), outward)
		col = Color.WHITE

	## 8 puntos: abajo [-x-z, +x-z, +x+z, -x+z], arriba en el mismo orden.
	func hull(mat: Material, p: Array) -> void:
		var c := Vector3.ZERO
		for q in p:
			c += q
		c /= 8.0
		quad(mat, p[0], p[1], p[2], p[3], c)
		quad(mat, p[4], p[5], p[6], p[7], c)
		quad(mat, p[0], p[1], p[5], p[4], c)
		quad(mat, p[3], p[2], p[6], p[7], c)
		quad(mat, p[0], p[3], p[7], p[4], c)
		quad(mat, p[1], p[2], p[6], p[5], c)

	## Prisma afinado: ancho medio abajo/arriba, z abajo [zb0,zb1], z arriba [zt0,zt1].
	func prism(mat: Material, hwb: float, hwt: float, y0: float, y1: float, zb0: float, zb1: float,
			zt0: float, zt1: float, y1f := -1.0, y1b := -1.0) -> void:
		var ya := y1 if y1f < 0.0 else y1f
		var yb := y1 if y1b < 0.0 else y1b
		hull(mat, [Vector3(-hwb, y0, zb0), Vector3(hwb, y0, zb0), Vector3(hwb, y0, zb1), Vector3(-hwb, y0, zb1),
			Vector3(-hwt, ya, zt0), Vector3(hwt, ya, zt0), Vector3(hwt, yb, zt1), Vector3(-hwt, yb, zt1)])

	func box(mat: Material, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
		var h := size * 0.5
		var pts := []
		for q in [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
				Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]:
			pts.append(center + basis * q)
		hull(mat, pts)

	## Barra cuadrada de grosor t entre a y b.
	func strut(mat: Material, a: Vector3, b: Vector3, t: float) -> void:
		var u := (b - a).normalized()
		var ref := Vector3.RIGHT if absf(u.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
		var s1 := u.cross(ref).normalized() * t * 0.5
		var s2 := u.cross(s1).normalized() * t * 0.5
		hull(mat, [a - s1 - s2, a + s1 - s2, b + s1 - s2, b - s1 - s2,
			a - s1 + s2, a + s1 + s2, b + s1 + s2, b - s1 + s2])

	## Cilindro a lo largo del eje Y del transform (lados suavizados).
	func cyl(mat: Material, xf: Transform3D, r: float, h: float, segs: int, ring_only := false) -> void:
		var gid := new_group()
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
			var b0 := xf * (p0 + Vector3(0, -h * 0.5, 0))
			var b1 := xf * (p1 + Vector3(0, -h * 0.5, 0))
			var t0 := xf * (p0 + Vector3(0, h * 0.5, 0))
			var t1 := xf * (p1 + Vector3(0, h * 0.5, 0))
			var out := xf.basis * ((p0 + p1) * 0.5)
			var u0 := float(i) / segs
			var u1 := float(i + 1) / segs
			quad_uv(mat, b0, b1, t1, t0, Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0), out, gid)
			if not ring_only:
				var up := xf.basis.y
				tri(mat, xf * Vector3(0, h * 0.5, 0), t0, t1, up)
				tri(mat, xf * Vector3(0, -h * 0.5, 0), b0, b1, -up)

	func commit() -> ArrayMesh:
		var m := ArrayMesh.new()
		for mat in _order:
			var st: SurfaceTool = _surfaces[mat]
			st.generate_normals()
			st.generate_tangents()
			st.commit(m)
			m.surface_set_material(m.get_surface_count() - 1, mat)
		return m

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


# ------------------------------------------------------------------ malla de carrocería

static func _body_mesh(kind: String, paint: Array) -> ArrayMesh:
	var key := "%s_%s" % [kind, (paint[0] as Color).to_html()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var kit := Kit.new()
	if kind == "buseta":
		_build_buseta(kit, SPECS[kind], paint)
	else:
		_build_car(kit, kind, SPECS[kind], paint)
	var m := kit.commit()
	_mesh_cache[key] = m
	return m


## Sedán / taxi (hatchback) / pickup: carrocería baja con arcos, capó, cabina de vidrio, techo.
static func _build_car(k: Kit, kind: String, s: Dictionary, paint: Array) -> void:
	var p := Palette.car_paint(paint[0])
	var glass := Palette.window_glass()
	var dark := Palette.tire()
	var trim := Palette.metal_dark()
	var chrome := Palette.chrome()
	var hl: float = s.L * 0.5
	var hw: float = s.hw
	var r: float = s.r
	var fa: float = s.fa
	var ra: float = s.ra
	var clear: float = s.clear
	var belt: float = s.belt
	var deck: float = s.deck
	var ah := r + 0.1
	var arch_top := r * 2.0 + 0.07
	var cb: Array = s.cab_b
	var ct: Array = s.cab_t
	var chw: Array = s.cab_hw
	var roof: float = s.roof

	# Carrocería inferior en segmentos, dejando los arcos de rueda abiertos.
	var tuck := 0.04
	k.prism(p, hw - tuck, hw, clear, belt, -hl + 0.06, fa - ah, -hl, fa - ah)
	k.prism(p, hw - tuck, hw, clear, belt, fa + ah, ra - ah, fa + ah, ra - ah)
	k.prism(p, hw - tuck, hw, clear, belt, ra + ah, hl - 0.05, ra + ah, hl)
	k.prism(p, hw - 0.01, hw, arch_top, belt, fa - ah, fa + ah, fa - ah, fa + ah)
	k.prism(p, hw - 0.01, hw, arch_top, belt, ra - ah, ra + ah, ra - ah, ra + ah)
	# Pasos de rueda oscuros (se ven a través del arco).
	for az: float in [fa, ra]:
		k.prism(dark, hw - 0.16, hw - 0.16, clear - 0.02, arch_top, az - ah, az + ah, az - ah, az + ah)
	# Bajos.
	k.box(dark, Vector3(0, clear - 0.04, 0), Vector3(hw * 2.0 - 0.3, 0.08, s.L - 0.7))
	# Molduras de puerta (umbral negro).
	for sx: float in [-1.0, 1.0]:
		k.box(dark, Vector3(sx * (hw - 0.005), clear + 0.03, (fa + ra) * 0.5), Vector3(0.03, 0.06, ra - fa - ah * 2.0))

	# Capó (inclinado hacia el frente).
	k.prism(p, hw, hw - 0.06, belt, -1.0, -hl, cb[0], -hl + 0.04, cb[0], s.hood_front, deck)
	# Cabina: vidrio + techo + parales.
	k.prism(glass, chw[0], chw[1], deck, roof, cb[0], cb[1], ct[0], ct[1])
	k.prism(p, chw[1] + 0.02, chw[1] - 0.04, roof - 0.02, roof + 0.05, ct[0] - 0.04, ct[1] + 0.04, ct[0] + 0.04, ct[1] - 0.03)
	for sx: float in [-1.0, 1.0]:
		var a0 := Vector3(sx * chw[0], deck, cb[0])
		var a1 := Vector3(sx * chw[1], roof, ct[0])
		k.strut(p, a0, a1, 0.065)
		var bz: float = lerpf(cb[0], cb[1], 0.45) if kind != "pickup" else lerpf(cb[0], cb[1], 0.5)
		var btz: float = clampf(bz, ct[0] + 0.1, ct[1] - 0.1)
		k.strut(p, Vector3(sx * (chw[0] + 0.005), deck, bz), Vector3(sx * (chw[1] + 0.005), roof, btz), 0.075)
		k.strut(p, Vector3(sx * chw[0], deck, cb[1]), Vector3(sx * chw[1], roof, ct[1]), 0.14 if kind == "sedan" else 0.09)
		# Línea de cintura bajo los vidrios.
		k.box(p, Vector3(sx * (chw[0] + 0.01), deck + 0.012, (cb[0] + cb[1]) * 0.5), Vector3(0.05, 0.03, cb[1] - cb[0]))
		# Espejos.
		var mz: float = cb[0] + 0.18
		k.box(p, Vector3(sx * (hw + 0.07), deck + 0.07, mz), Vector3(0.14, 0.1, 0.07))
		k.box(glass, Vector3(sx * (hw + 0.07), deck + 0.07, mz + 0.037), Vector3(0.11, 0.075, 0.01))
		k.box(dark, Vector3(sx * (hw + 0.01), deck + 0.05, mz), Vector3(0.05, 0.04, 0.05))
		# Juntas de puertas y manijas.
		var doors: Array = [cb[0] + 0.05, bz, cb[1] - (0.05 if kind != "taxi" else 0.35)]
		for dz: float in doors:
			k.box(trim, Vector3(sx * (hw + 0.002), (clear + belt) * 0.5 + 0.03, dz), Vector3(0.006, belt - clear - 0.08, 0.012))
		for i in 2:
			var hz: float = lerpf(doors[i], doors[i + 1], 0.75)
			k.box(chrome, Vector3(sx * (hw + 0.008), belt - 0.07, hz), Vector3(0.02, 0.03, 0.13))
		# Cejas de los arcos.
		for az: float in [fa, ra]:
			k.prism(dark if kind == "pickup" else p, hw - 0.02, hw + (0.04 if kind == "pickup" else 0.0), arch_top - 0.03, arch_top + 0.04,
				az - ah - 0.04, az + ah + 0.04, az - ah - 0.02, az + ah + 0.02)

	# Maletero / platón.
	if s.trunk:
		k.prism(p, hw, hw - 0.05, belt, -1.0, cb[1], hl, cb[1], hl - 0.07, deck, deck - 0.02)
	elif s.bed:
		var bz0: float = cb[1] + 0.04
		var top := belt + 0.32
		k.box(dark, Vector3(0, belt + 0.004, (bz0 + hl) * 0.5), Vector3(hw * 2.0 - 0.14, 0.01, hl - bz0 - 0.08))
		for sx: float in [-1.0, 1.0]:
			k.box(p, Vector3(sx * (hw - 0.035), (belt + top) * 0.5, (bz0 + hl) * 0.5), Vector3(0.07, top - belt, hl - bz0))
			k.box(dark, Vector3(sx * (hw - 0.035), top + 0.01, (bz0 + hl) * 0.5), Vector3(0.08, 0.02, hl - bz0))
		k.box(p, Vector3(0, (belt + top) * 0.5 + 0.06, bz0 + 0.035), Vector3(hw * 2.0, top - belt + 0.12, 0.07))
		k.box(p, Vector3(0, (belt + top) * 0.5, hl - 0.035), Vector3(hw * 2.0 - 0.02, top - belt, 0.07))
		k.box(chrome, Vector3(0, top - 0.06, hl + 0.001), Vector3(0.25, 0.04, 0.01))
		# Estribos laterales.
		for sx: float in [-1.0, 1.0]:
			k.box(trim, Vector3(sx * (hw + 0.06), clear - 0.02, (fa + ra) * 0.5 - 0.15), Vector3(0.14, 0.04, ra - fa - ah * 2.0 - 0.1))
	else:
		# Hatchback: portón trasero casi vertical con spoiler.
		k.box(p, Vector3(0, roof - 0.02, ct[1] + 0.02), Vector3(chw[1] * 2.0 - 0.02, 0.05, 0.16))

	# Frente: parrilla, faros apagados de respaldo y exploradoras.
	var grille_w := hw * (1.05 if kind == "pickup" else 0.95)
	var gy: float = (belt + s.hood_front) * 0.5 - (0.05 if kind != "pickup" else 0.12)
	var gh := 0.13 if kind != "pickup" else 0.28
	k.box(trim, Vector3(0, gy, -hl - 0.012), Vector3(grille_w, gh, 0.03))
	if kind == "pickup":
		for i in 3:
			k.box(chrome, Vector3(0, gy - gh * 0.5 + 0.05 + i * 0.09, -hl - 0.03), Vector3(grille_w, 0.025, 0.02))
	else:
		k.box(chrome, Vector3(0, gy + gh * 0.5 + 0.01, -hl - 0.03), Vector3(grille_w, 0.02, 0.02))
	# Bumper trasero (el delantero es pieza aparte para daño).
	k.prism(chrome if kind == "pickup" else p, hw - 0.02, hw - 0.03, clear - 0.04, clear + 0.22, hl - 0.05, hl + 0.09, hl - 0.05, hl + 0.07)
	k.box(dark, Vector3(0, clear - 0.02, hl + 0.095), Vector3(hw * 1.6, 0.06, 0.03))
	# Escape.
	k.cyl(trim, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(hw * 0.55, clear - 0.04, hl + 0.06)), 0.035, 0.18, 8)


static func _build_buseta(k: Kit, s: Dictionary, paint: Array) -> void:
	var p := Palette.car_paint(paint[0])
	var p2 := Palette.car_paint(paint[1])
	var white := Palette.car_paint(Color(0.95, 0.95, 0.93))
	var red := Palette.car_paint(Color(0.85, 0.1, 0.08))
	var yel := Palette.car_paint(Color(0.98, 0.8, 0.1))
	var grn := Palette.car_paint(Color(0.1, 0.6, 0.25))
	var glass := Palette.window_glass()
	var dark := Palette.tire()
	var trim := Palette.metal_dark()
	var chrome := Palette.chrome()
	var hl: float = s.L * 0.5
	var hw: float = s.hw
	var r: float = s.r
	var fa: float = s.fa
	var ra: float = s.ra
	var clear: float = s.clear
	var belt: float = s.belt
	var roof: float = s.roof
	var ah := r + 0.12
	var arch_top := r * 2.0 + 0.1
	var win_top := 2.28

	# Paneles bajos con arcos.
	k.prism(p, hw - 0.02, hw, clear, belt, -hl + 0.03, fa - ah, -hl, fa - ah)
	k.prism(p, hw - 0.02, hw, clear, belt, fa + ah, ra - ah, fa + ah, ra - ah)
	k.prism(p, hw - 0.02, hw, clear, belt, ra + ah, hl, ra + ah, hl)
	for az: float in [fa, ra]:
		k.prism(p, hw, hw, arch_top, belt, az - ah, az + ah, az - ah, az + ah)
		k.prism(dark, hw - 0.2, hw - 0.2, clear - 0.02, arch_top, az - ah, az + ah, az - ah, az + ah)
	k.box(dark, Vector3(0, clear - 0.05, 0), Vector3(hw * 2.0 - 0.4, 0.1, s.L - 0.8))
	# Banda de ventanas: vidrio continuo; parabrisas inclinado.
	k.prism(glass, hw - 0.015, hw - 0.015, belt, win_top, -hl, hl - 0.02, -hl + 0.2, hl - 0.02)
	# Franja superior y techo.
	k.prism(p2, hw, hw, win_top, roof - 0.1, -hl + 0.2, hl, -hl + 0.3, hl)
	k.prism(white, hw - 0.02, hw - 0.14, roof - 0.1, roof, -hl + 0.3, hl, -hl + 0.42, hl - 0.1)
	k.box(trim, Vector3(0, roof + 0.06, 0.6), Vector3(1.0, 0.12, 1.0))  # escotilla/ventilación
	# Parales entre ventanas y panel trasero.
	var z := -hl + 1.4
	while z < hl - 0.3:
		for sx: float in [-1.0, 1.0]:
			k.box(p2, Vector3(sx * (hw - 0.005), (belt + win_top) * 0.5, z), Vector3(0.03, win_top - belt, 0.09))
		z += 0.95
	for sx: float in [-1.0, 1.0]:
		k.strut(p2, Vector3(sx * (hw - 0.04), belt, -hl + 0.02), Vector3(sx * (hw - 0.04), win_top, -hl + 0.2), 0.1)
	k.box(p, Vector3(0, (belt + 1.95) * 0.5, hl - 0.01), Vector3(hw * 2.0 - 0.02, 1.95 - belt, 0.04))
	k.box(trim, Vector3(0, (win_top + belt) * 0.5, -hl + 0.1), Vector3(0.05, win_top - belt, 0.22))
	# Franjas de colores (buseta paisa).
	for sx: float in [-1.0, 1.0]:
		var x := sx * (hw + 0.004)
		k.box(red, Vector3(x, 1.11, 0), Vector3(0.01, 0.07, s.L - 0.1))
		k.box(yel, Vector3(x, 1.19, 0), Vector3(0.01, 0.05, s.L - 0.1))
		k.box(grn, Vector3(x, 1.27, 0), Vector3(0.01, 0.07, s.L - 0.1))
		k.box(p2, Vector3(x, win_top + 0.06, 0), Vector3(0.01, 0.05, s.L - 0.4))
		# "Swoosh" diagonal trasero.
		k.box(red, Vector3(x, 0.78, hl - 0.75), Vector3(0.01, 0.08, 0.9), Basis(Vector3.RIGHT, 0.45))
		k.box(yel, Vector3(x, 0.66, hl - 0.75), Vector3(0.01, 0.06, 0.9), Basis(Vector3.RIGHT, 0.45))
	for zz: float in [-hl - 0.004, hl + 0.004]:
		k.box(red, Vector3(0, 1.11, zz), Vector3(hw * 2.0, 0.07, 0.01))
		k.box(yel, Vector3(0, 1.19, zz), Vector3(hw * 2.0, 0.05, 0.01))
		k.box(grn, Vector3(0, 1.27, zz), Vector3(hw * 2.0, 0.07, 0.01))
	# Puerta de pasajeros (derecha, adelante).
	var dz0 := fa + ah + 0.05
	k.box(glass, Vector3(hw + 0.006, 1.35, dz0 + 0.45), Vector3(0.01, 1.7, 0.86))
	k.box(trim, Vector3(hw + 0.008, 1.35, dz0 + 0.45), Vector3(0.01, 1.74, 0.03))
	k.box(trim, Vector3(hw + 0.004, 1.35, dz0 + 0.02), Vector3(0.01, 1.76, 0.04))
	k.box(trim, Vector3(hw + 0.004, 1.35, dz0 + 0.88), Vector3(0.01, 1.76, 0.04))
	k.box(trim, Vector3(hw + 0.15, clear + 0.02, dz0 + 0.45), Vector3(0.3, 0.05, 0.86))  # estribo
	# Frente: parrilla, letrero de ruta, espejos de brazo.
	k.box(trim, Vector3(0, 0.82, -hl - 0.012), Vector3(1.1, 0.32, 0.03))
	for i in 4:
		k.box(chrome, Vector3(0, 0.7 + i * 0.08, -hl - 0.03), Vector3(1.1, 0.025, 0.02))
	k.box(dark, Vector3(0, 0.5, -hl - 0.1), Vector3(hw * 2.0 + 0.04, 0.22, 0.18))
	k.box(trim, Vector3(0, win_top + 0.16, -hl + 0.24), Vector3(1.5, 0.24, 0.05))
	for sx: float in [-1.0, 1.0]:
		k.strut(trim, Vector3(sx * (hw - 0.05), 2.0, -hl + 0.05), Vector3(sx * (hw + 0.28), 2.05, -hl - 0.25), 0.035)
		k.box(trim, Vector3(sx * (hw + 0.3), 1.8, -hl - 0.26), Vector3(0.1, 0.42, 0.05))
		k.box(glass, Vector3(sx * (hw + 0.3), 1.8, -hl - 0.23), Vector3(0.08, 0.38, 0.01))
	# Atrás: bumper y escalera al techo.
	k.box(dark, Vector3(0, 0.5, hl + 0.08), Vector3(hw * 2.0, 0.2, 0.14))
	for i in 5:
		k.box(chrome, Vector3(-hw + 0.3, 1.9 + i * 0.18, hl + 0.06), Vector3(0.3, 0.025, 0.025))


# ------------------------------------------------------------------ piezas dinámicas

static func _add_dynamic_parts(v: Vehicle, kind: String, s: Dictionary, paint: Array, rng: RandomNumberGenerator) -> void:
	var hl: float = s.L * 0.5
	var hw: float = s.hw
	var is_bus := kind == "buseta"
	var light_y: float = 0.72 if kind != "pickup" else 0.9
	if is_bus:
		light_y = 0.78
	var tail_y: float = light_y + 0.04 if kind != "taxi" else 0.95
	if is_bus:
		tail_y = 1.0
	if kind == "pickup":
		tail_y = 1.1

	# Faros (una malla para los dos, material intercambiable).
	var kh := Kit.new()
	var tmp := Palette.chrome()
	for sx: float in [-1.0, 1.0]:
		if is_bus:
			kh.box(tmp, Vector3(sx * (hw - 0.3), light_y, -hl - 0.02), Vector3(0.38, 0.16, 0.04))
		elif kind == "taxi":
			kh.box(tmp, Vector3(sx * (hw - 0.22), light_y, -hl - 0.012), Vector3(0.3, 0.12, 0.05))
		else:
			kh.box(tmp, Vector3(sx * (hw - 0.24), light_y + (0.05 if kind == "pickup" else 0.0), -hl - 0.012), Vector3(0.34, 0.11, 0.05))
	v.head_lens = MeshInstance3D.new()
	v.head_lens.name = "HeadLens"
	v.head_lens.mesh = _cached_mesh("head_" + kind, kh)
	v.add_child(v.head_lens)

	var kt := Kit.new()
	for sx: float in [-1.0, 1.0]:
		if kind == "taxi":
			kt.box(tmp, Vector3(sx * (hw - 0.08), tail_y, hl + 0.01), Vector3(0.14, 0.3, 0.04))
		elif kind == "pickup":
			kt.box(tmp, Vector3(sx * (hw - 0.04), tail_y + 0.05, hl + 0.01), Vector3(0.1, 0.32, 0.04))
		elif is_bus:
			kt.box(tmp, Vector3(sx * (hw - 0.15), tail_y, hl + 0.03), Vector3(0.2, 0.36, 0.04))
		else:
			kt.box(tmp, Vector3(sx * (hw - 0.2), tail_y, hl + 0.01), Vector3(0.36, 0.12, 0.04))
	if kind == "sedan":
		kt.box(tmp, Vector3(0, s.deck + 0.02, s.cab_b[1] - 0.05), Vector3(0.4, 0.03, 0.03))  # tercer stop
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

	# Bumper delantero (pieza que se deforma).
	var bk := Kit.new()
	var bp := Palette.car_paint(paint[0]) if not is_bus else Palette.tire()
	if kind == "pickup":
		bp = Palette.chrome()
	var by: float = s.clear
	if not is_bus:
		bk.prism(bp, hw - 0.02, hw - 0.03, by - 0.05, by + 0.22, -hl - 0.09, -hl + 0.05, -hl - 0.07, -hl + 0.05)
		bk.box(Palette.tire(), Vector3(0, by - 0.03, -hl - 0.095), Vector3(hw * 1.5, 0.06, 0.03))
		for sx: float in [-1.0, 1.0]:
			bk.box(Palette.metal_dark(), Vector3(sx * (hw - 0.25), by + 0.06, -hl - 0.1), Vector3(0.16, 0.06, 0.02))
	else:
		bk.box(Palette.metal_dark(), Vector3(0, 0.62, -hl - 0.03), Vector3(hw * 1.9, 0.05, 0.04))
	var bumper := MeshInstance3D.new()
	bumper.name = "BumperFront"
	bumper.mesh = _cached_mesh("bumper_%s_%s" % [kind, (paint[0] as Color).to_html()], bk)
	var pivot := Node3D.new()
	pivot.name = "BumperPivot"
	v.add_child(pivot)
	pivot.add_child(bumper)
	v.bumper_front = pivot

	# Placas amarillas (Colombia, texto inventado).
	var plate := _plate_text(rng)
	var plate_y_f: float = by + 0.08 if not is_bus else 0.5
	var plate_y_r: float = by + 0.38 if not is_bus else 0.85
	if kind == "pickup":
		plate_y_r = s.belt - 0.15
	_add_plate(v, plate, Vector3(0, plate_y_f, -hl - 0.11 if not is_bus else -hl - 0.2), true)
	_add_plate(v, plate, Vector3(0, plate_y_r, hl + 0.03 if not is_bus else hl + 0.03), false)

	if kind == "taxi":
		var sign_k := Kit.new()
		var cz: float = (s.cab_t[0] + s.cab_t[1]) * 0.5 - 0.15
		sign_k.prism(Palette.car_paint(Color(0.97, 0.97, 0.95)), 0.26, 0.24, s.roof + 0.05, s.roof + 0.2, cz - 0.1, cz + 0.1, cz - 0.08, cz + 0.08)
		sign_k.box(Palette.tire(), Vector3(0, s.roof + 0.06, cz), Vector3(0.2, 0.03, 0.12))
		var sign_mi := MeshInstance3D.new()
		sign_mi.name = "TaxiSign"
		sign_mi.mesh = _cached_mesh("taxi_sign", sign_k)
		v.add_child(sign_mi)
		for dir: float in [-1.0, 1.0]:
			_add_label(v, "TAXI", Vector3(0, s.roof + 0.125, cz + dir * 0.102), PI if dir < 0 else 0.0, 40, 0.0028, Color.BLACK)
		# Franja negra lateral y número de flota.
		var num := "%04d" % (rng.randi() % 10000)
		var stripe := Kit.new()
		for sx: float in [-1.0, 1.0]:
			stripe.box(Palette.tire(), Vector3(sx * (hw + 0.004), s.belt - 0.14, (s.fa + s.ra) * 0.5), Vector3(0.006, 0.05, s.ra - s.fa - 0.8))
			_add_label(v, num, Vector3(sx * (hw + 0.01), s.belt - 0.06, s.ra - 0.62), sx * PI * 0.5, 44, 0.0026, Color.BLACK)
			_add_label(v, "SPA " + plate.right(3), Vector3(sx * (hw + 0.01), s.belt - 0.06, -0.15), sx * PI * 0.5, 30, 0.0026, Color.BLACK)
		var smi := MeshInstance3D.new()
		smi.mesh = _cached_mesh("taxi_stripe", stripe)
		v.add_child(smi)
	elif kind == "buseta":
		_add_label(v, "BOSTON · CENTRO", Vector3(0, 2.44, -hl + 0.21), PI, 40, 0.0028, Color(1.0, 0.62, 0.1))
		for sx: float in [-1.0, 1.0]:
			_add_label(v, "TRANSPORTES SAN PABLO", Vector3(sx * (hw + 0.012), 0.9, 0.4), sx * PI * 0.5, 40, 0.0035, Color(0.08, 0.1, 0.2))
			_add_label(v, "%03d" % (rng.randi() % 1000), Vector3(sx * (hw + 0.012), 2.66, -hl + 0.8), sx * PI * 0.5, 48, 0.004, Color(0.1, 0.1, 0.1))

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


## Las mallas se cachean (y se comparten entre autos del mismo tipo).
static func _cached_mesh(key: String, kit: Kit) -> ArrayMesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = kit.commit()
	return _mesh_cache[key]


static func _add_plate(v: Vehicle, text: String, pos: Vector3, front: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.48, 0.15, 0.015)
	bm.material = Palette.car_paint(PLATE_YELLOW)
	mi.mesh = bm
	mi.position = pos
	v.add_child(mi)
	var dz := -0.009 if front else 0.009
	_add_label(v, text, pos + Vector3(0, 0.015, dz), PI if front else 0.0, 48, 0.0017, Color(0.05, 0.05, 0.05))
	_add_label(v, "MEDELLÍN", pos + Vector3(0, -0.05, dz), PI if front else 0.0, 18, 0.0017, Color(0.05, 0.05, 0.05))


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


## Llanta + rin con radios. Eje = X local, rin hacia +X.
static func _wheel_mesh(r: float, tw: float, heavy: bool) -> ArrayMesh:
	var key := "wheel_%.2f_%.2f_%s" % [r, tw, heavy]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var k := Kit.new()
	var tire := Palette.tire()
	var chrome := Palette.chrome()
	var dark := Palette.metal_dark()
	var axis := Basis(Vector3.FORWARD, PI * 0.5)  # eje Y del cilindro -> X
	k.cyl(tire, Transform3D(axis, Vector3.ZERO), r, tw, 18)
	k.cyl(tire, Transform3D(axis, Vector3(tw * 0.5, 0, 0)), r * 0.86, 0.02, 18)
	var rim_r := r * (0.62 if not heavy else 0.55)
	k.cyl(chrome, Transform3D(axis, Vector3(tw * 0.5 + 0.004, 0, 0)), rim_r, 0.012, 16)
	k.cyl(dark, Transform3D(axis, Vector3(tw * 0.5 + 0.008, 0, 0)), rim_r * 0.85, 0.012, 16)
	k.cyl(chrome, Transform3D(axis, Vector3(tw * 0.5 + 0.012, 0, 0)), rim_r * 0.3, 0.03, 10)
	var spokes := 5 if not heavy else 8
	for i in spokes:
		var ang := TAU * i / spokes
		var b := Basis(Vector3.RIGHT, ang)
		k.box(chrome, Vector3(tw * 0.5 + 0.014, 0, 0) + b * Vector3(0, rim_r * 0.55, 0), Vector3(0.016, rim_r * 0.8, rim_r * 0.22), b)
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
class Kit:
	var _surfaces := {}
	var _order: Array[Material] = []

	func _st(mat: Material) -> SurfaceTool:
		if not _surfaces.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_surfaces[mat] = st
			_order.append(mat)
		return _surfaces[mat]

	## Triángulo con normal plana orientada hacia `outward` (Godot: caras frontales en sentido horario).
	func tri(mat: Material, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		if n.dot(outward) > 0.0:
			var t := b
			b = c
			c = t
			n = -n
		var nn := -n.normalized()
		var st := _st(mat)
		for p in [a, b, c]:
			st.set_normal(nn)
			st.add_vertex(p)

	func quad(mat: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3) -> void:
		var out := (a + b + c + d) * 0.25 - center
		tri(mat, a, b, c, out)
		tri(mat, a, c, d, out)

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
	## Si y1f/y1b >= 0, la cara superior se inclina (frente y1f, atrás y1b).
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

	## Cilindro a lo largo del eje Y del transform.
	func cyl(mat: Material, xf: Transform3D, r: float, h: float, segs: int, ring_only := false) -> void:
		var c := xf.origin
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
			tri(mat, b0, b1, t1, out)
			tri(mat, b0, t1, t0, out)
			if not ring_only:
				var up := xf.basis.y
				tri(mat, xf * Vector3(0, h * 0.5, 0), t0, t1, up)
				tri(mat, xf * Vector3(0, -h * 0.5, 0), b0, b1, -up)

	func commit() -> ArrayMesh:
		var m := ArrayMesh.new()
		for mat in _order:
			var st: SurfaceTool = _surfaces[mat]
			st.commit(m)
			m.surface_set_material(m.get_surface_count() - 1, mat)
		return m

class_name Poles
extends RefCounted
## F2-03 — Red eléctrica y alumbrado de calle de Medellín (refs /tmp/refs/3, 6, 7).
## Poste de concreto centrifugado cónico (MatMetal.concrete_pole, UV cilíndricas), cruceta galvanizada
## con aisladores de porcelana (media tensión), percha de baja tensión, abrazaderas de telecomunicaciones,
## variantes con transformador / rollos de cable de reserva / cajas de empalme; luminaria LED de brazo;
## vanos de cable con catenaria (parábola) y acometidas a fachadas.
##
## MARCO LOCAL del poste y la luminaria: Y arriba, y = 0 al nivel del andén, +Z hacia la calzada,
## X a lo largo de la línea de postes. Base del poste en el origen.
## Colocar con Transform3D(Basis(along, UP, to_road), p) donde along = (to_road.z, 0, -to_road.x).
##
## VANOS (span): malla de todos los cables entre dos postes, en un marco donde X va del poste A (x=0)
## al poste B (x=L). Usar span_transform() para la colocación (cizalla para la pendiente).
##
## Todas las mallas se cachean (static var); cada variante se construye una sola vez.

const POLE_TOP := 11.0          # altura del poste sobre el andén (m)
const POLE_BURY := 0.3
const POLE_R0 := 0.2            # radio en la base
const POLE_R1 := 0.125          # radio en la punta
const LAMP_Y := 8.1             # altura de la abrazadera del brazo de la luminaria
## Posición local de la fuente de luz (bajo la cabeza de la luminaria).
const LAMP_LIGHT_POS := Vector3(0.0, 8.55, 2.3)
const VARIANTS := 4

## Cables de un vano: [y, z, radio, flecha (m) para 33 m, lados]. z se multiplica por el signo del vano.
const SPAN_CABLES := [
	# media tensión (sobre los aisladores de la cruceta)
	[10.63, -0.70, 0.009, 0.42, 3],
	[10.63, 0.25, 0.009, 0.42, 3],
	[10.63, 1.20, 0.009, 0.42, 3],
	# baja tensión (percha trasera): neutro, trenzado grueso, fase
	[9.10, -0.37, 0.011, 0.58, 3],
	[8.80, -0.37, 0.024, 0.72, 5],
	[8.50, -0.37, 0.011, 0.60, 3],
	# telecomunicaciones (amarrados al poste, más flojos)
	[6.95, -0.22, 0.010, 0.70, 3],
	[6.85, 0.24, 0.018, 0.85, 4],
	[6.60, -0.25, 0.030, 0.95, 5],
	[6.55, 0.27, 0.012, 1.05, 3],
]

## Puntos de amarre útiles para acometidas (local del poste).
const DROP_LV := Vector3(0.0, 8.80, -0.37)
const DROP_TEL := Vector3(0.0, 6.85, 0.24)

static var _meshes := {}
static var _mats := {}


# ================================================================ materiales propios
## Cable / plástico negro (cables, rollos, cajas de empalme, mangas).
static func cable_mat() -> Material:
	if not _mats.has("cable"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.035, 0.035, 0.04)
		m.roughness = 0.55
		_mats["cable"] = m
	return _mats["cable"]


## Porcelana esmaltada de aisladores (blanco hueso con brillo).
static func porcelain_mat() -> Material:
	if not _mats.has("porcelain"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.78, 0.77, 0.73)
		m.roughness = 0.22
		m.clearcoat_enabled = false
		_mats["porcelain"] = m
	return _mats["porcelain"]


## Carcasa de aluminio pintado gris de la luminaria LED.
static func housing_mat() -> Material:
	if not _mats.has("housing"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.44, 0.45)
		m.roughness = 0.42
		m.metallic = 0.45
		_mats["housing"] = m
	return _mats["housing"]


## Lente de la luminaria: emisión ámbar cálida. set_lamps_on() cambia su energía (día/noche).
static func lens_mat() -> StandardMaterial3D:
	if not _mats.has("lens"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.32, 0.31, 0.29)
		m.roughness = 0.12
		m.emission_enabled = true
		m.emission = Color(1.0, 0.72, 0.42)
		m.emission_energy_multiplier = 4.0
		_mats["lens"] = m
	return _mats["lens"]


static func set_lamps_on(on: bool) -> void:
	lens_mat().emission_energy_multiplier = 4.0 if on else 0.35


static func _concrete() -> Material:
	return MatMetal.concrete_pole(POLE_TOP + POLE_BURY)


static func _galv() -> Material:
	return MatMetal.galvanized()


# ================================================================ mallas públicas
## Poste completo. variant 0..3:
## 0 básico · 1 con transformador · 2 con rollos de telecom y caja de empalme · 3 con rollo, botella de
## empalme y caja de medidor.
static func pole(variant: int) -> ArrayMesh:
	variant = posmod(variant, VARIANTS)
	var key := "pole_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var b := _Builder.new()
	var conc := b.surf(_concrete())
	var galv := b.surf(_galv())
	var porc := b.surf(porcelain_mat())
	var blk := b.surf(cable_mat())
	# --- fuste cónico (U = vuelta, V 0..0.5 en toda la altura, como CylinderMesh)
	var hh := POLE_TOP + POLE_BURY
	var ys := [-POLE_BURY, 0.9, 5.5, POLE_TOP]
	for i in ys.size() - 1:
		var y0: float = ys[i]
		var y1: float = ys[i + 1]
		b.tube(conc, Vector3(0, y0, 0), Vector3(0, y1, 0), pole_r(y0), pole_r(y1), 12, false, false,
			0.5 - (y0 + POLE_BURY) / hh * 0.5, 0.5 - (y1 + POLE_BURY) / hh * 0.5)
	# punta biselada
	b.tube(conc, Vector3(0, POLE_TOP, 0), Vector3(0, POLE_TOP + 0.05, 0), POLE_R1, POLE_R1 * 0.7, 12, false, true, 0.0, 0.0)
	# collar de la base (concreto vaciado del andén) y anillo de suciedad
	b.tube(conc, Vector3(0, -0.05, 0), Vector3(0, 0.07, 0), 0.30, 0.26, 10, false, true, 0.49, 0.5)
	# --- cruceta galvanizada (a lo largo de Z, desplazada hacia la calle)
	var cy := 10.35
	b.prism(galv, Vector3(0, cy, -1.0), Vector3(0, cy, 1.5), 0.095, 0.1, 0.02)
	b.tube(galv, Vector3(0, cy - 0.06, 0), Vector3(0, cy + 0.06, 0), pole_r(cy) + 0.015, pole_r(cy) + 0.015, 6, false, false)
	# pie de amigo (diagonales) y abrazadera inferior
	var by := 9.65
	b.tube(galv, Vector3(0, by - 0.04, 0), Vector3(0, by + 0.04, 0), pole_r(by) + 0.015, pole_r(by) + 0.015, 6, false, false)
	for zz in [-0.75, 1.0]:
		b.prism(galv, Vector3(0, by, signf(zz) * pole_r(by)), Vector3(0, cy - 0.05, zz), 0.035, 0.012, 0.0)
	# tornillos pasantes
	for zz in [-0.9, 1.4]:
		b.tube(galv, Vector3(-0.07, cy, zz), Vector3(0.07, cy, zz), 0.012, 0.012, 4, false, false)
	# --- aisladores de pin (porcelana) sobre la cruceta
	for zi in [-0.70, 0.25, 1.20]:
		_pin_insulator(b, porc, galv, Vector3(0, cy + 0.05, zi))
	# --- percha de baja tensión (lado trasero, -Z)
	var rz := -(pole_r(8.8) + 0.02)
	b.prism(galv, Vector3(0, 8.35, rz), Vector3(0, 9.25, rz), 0.05, 0.012, 0.0)
	for yy in [8.5, 8.8, 9.1]:
		b.prism(galv, Vector3(0, yy + 0.06, rz), Vector3(0, yy + 0.06, -0.37), 0.04, 0.008, 0.0)
		b.tube(porc, Vector3(0, yy - 0.05, -0.37), Vector3(0, yy + 0.05, -0.37), 0.045, 0.045, 5, false, true)
	for yy in [8.4, 9.2]:
		b.tube(galv, Vector3(0, yy - 0.03, 0), Vector3(0, yy + 0.03, 0), pole_r(yy) + 0.012, pole_r(yy) + 0.012, 6, false, false)
	# --- abrazaderas y herrajes de telecomunicaciones
	for yy in [6.6, 6.9]:
		b.tube(galv, Vector3(0, yy - 0.025, 0), Vector3(0, yy + 0.025, 0), pole_r(yy) + 0.01, pole_r(yy) + 0.01, 6, false, false)
	b.prism(blk, Vector3(0, 6.85, 0.13), Vector3(0, 6.85, 0.27), 0.05, 0.05, 0.0)
	b.prism(blk, Vector3(0, 6.6, -0.13), Vector3(0, 6.6, -0.27), 0.06, 0.06, 0.0)
	# cable de bajada (puesta a tierra) pegado al fuste, con su tubo protector abajo
	var gz := pole_r(3.0) + 0.012
	b.tube(blk, Vector3(-0.01, 0.0, -gz - 0.02), Vector3(-0.01, 8.4, -(pole_r(8.4) + 0.012)), 0.008, 0.008, 3, false, false)
	b.tube(galv, Vector3(-0.01, -0.05, -(pole_r(0.0) + 0.02)), Vector3(-0.01, 2.6, -(pole_r(2.6) + 0.02)), 0.022, 0.022, 6, false, true)
	match variant:
		1:
			_transformer(b, galv, porc, blk)
		2:
			_coil(b, blk, Vector3(0.0, 5.95, 0.32), 0.34, 0.024, 2)
			_coil(b, blk, Vector3(0.0, 6.15, -0.33), 0.26, 0.03, 2)
			# caja de empalme negra colgada del cable de telecom
			b.prism(blk, Vector3(0.75, 6.42, 0.26), Vector3(0.75, 6.82, 0.26), 0.2, 0.14, 0.025)
		3:
			_coil(b, blk, Vector3(0.0, 6.05, 0.31), 0.3, 0.025, 3)
			# botella de empalme (cilindro negro sobre el cable)
			b.tube(blk, Vector3(1.1, 6.78, 0.24), Vector3(1.65, 6.76, 0.24), 0.075, 0.075, 6, false, false)
			b.tube(blk, Vector3(1.0, 6.78, 0.24), Vector3(1.1, 6.78, 0.24), 0.03, 0.075, 6, false, false)
			b.tube(blk, Vector3(1.65, 6.76, 0.24), Vector3(1.75, 6.76, 0.24), 0.075, 0.03, 6, false, false)
			# caja de medidor / tablero galvanizado a 2.6 m
			var mz := pole_r(2.7) + 0.09
			b.prism(galv, Vector3(0, 2.4, -mz), Vector3(0, 3.0, -mz), 0.32, 0.16, 0.025)
			b.tube(galv, Vector3(0, 3.0, -mz), Vector3(0, 6.5, -(pole_r(6.5) + 0.03)), 0.018, 0.018, 4, false, false)
	var mesh := b.commit()
	_meshes[key] = mesh
	return mesh


## Radio del fuste a la altura y (local).
static func pole_r(y: float) -> float:
	return lerpf(POLE_R0, POLE_R1, clampf((y + POLE_BURY) / (POLE_TOP + POLE_BURY), 0.0, 1.0))


## Luminaria LED de brazo (marco local del poste; la cabeza mira a +Z). 3 superficies.
static func luminaire() -> ArrayMesh:
	if _meshes.has("lum"):
		return _meshes["lum"]
	var b := _Builder.new()
	var galv := b.surf(_galv())
	var hous := b.surf(housing_mat())
	var lens := b.surf(lens_mat())
	var y := LAMP_Y
	# abrazaderas del brazo
	b.tube(galv, Vector3(0, y - 0.1, 0), Vector3(0, y + 0.1, 0), pole_r(y) + 0.018, pole_r(y) + 0.018, 6, false, false)
	b.tube(galv, Vector3(0, y + 0.45, 0), Vector3(0, y + 0.53, 0), pole_r(y + 0.5) + 0.016, pole_r(y + 0.5) + 0.016, 6, false, false)
	# brazo curvo (tubo de 2" con cuatro tramos) + tirante
	var pts := [Vector3(0, y, pole_r(y)), Vector3(0, y + 0.18, 0.45), Vector3(0, y + 0.42, 1.0),
		Vector3(0, y + 0.55, 1.55), Vector3(0, y + 0.6, 1.98)]
	for i in pts.size() - 1:
		b.tube(galv, pts[i], pts[i + 1], 0.032, 0.03, 6, false, false)
	b.tube(galv, Vector3(0, y + 0.49, pole_r(y + 0.5)), Vector3(0, y + 0.47, 0.95), 0.016, 0.016, 4, false, false)
	# cabeza LED: cuerpo achaflanado inclinado 5°, cuello y aletas de disipación
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-5.0))
	var hc := Vector3(0, y + 0.6, 2.3)
	var hx := Transform3D(tilt, hc)
	b.prism(hous, Vector3(0, y + 0.6, 1.9), Vector3(0, y + 0.6, 2.06), 0.12, 0.1, 0.02)
	b.prism(hous, hx * Vector3(0, 0, -0.28), hx * Vector3(0, 0, 0.34), 0.32, 0.1, 0.035)
	b.prism(hous, hx * Vector3(0, 0.06, -0.22), hx * Vector3(0, 0.06, 0.28), 0.22, 0.04, 0.015)
	for k in 4:
		var fx := -0.09 + k * 0.06
		b.prism(hous, hx * Vector3(fx, 0.09, -0.18), hx * Vector3(fx, 0.09, 0.24), 0.012, 0.05, 0.0)
	# lente (cara inferior emisiva)
	b.prism(lens, hx * Vector3(0, -0.055, -0.2), hx * Vector3(0, -0.055, 0.29), 0.25, 0.018, 0.006)
	var mesh := b.commit()
	_meshes["lum"] = mesh
	return mesh


## Haz de cables de un vano de longitud horizontal `length` (se redondea a 1 m; cachea por longitud).
## z_sign: +1 si (X del vano × Y) apunta hacia la calzada, -1 si no (ver span_transform()).
static func span(length: float, z_sign: float) -> ArrayMesh:
	var L := maxf(4.0, roundf(length))
	var zs := 1.0 if z_sign >= 0.0 else -1.0
	var key := "span_%d_%d" % [int(L), int(zs)]
	if _meshes.has(key):
		return _meshes[key]
	var b := _Builder.new()
	var s := b.surf(cable_mat())
	var segs := clampi(int(L / 5.5), 5, 10)
	var k := L / 33.0
	for c in SPAN_CABLES:
		var y: float = c[0]
		var z: float = float(c[1]) * zs
		var sag: float = float(c[3]) * k * k   # flecha ~ L² (misma tensión)
		b.catenary(s, Vector3(0, y, z), Vector3(L, y, z), sag, c[2], c[4], segs)
	var mesh := b.commit()
	_meshes[key] = mesh
	return mesh


## Transform de un vano entre las bases de dos postes a y b (mismos to_road). Devuelve
## [Transform3D, z_sign, length] — la base X lleva la diferencia de altura (cizalla de la pendiente).
static func span_transform(a: Vector3, b: Vector3, to_road: Vector3) -> Array:
	var d := b - a
	var h := Vector3(d.x, 0.0, d.z)
	var L := maxf(4.0, roundf(h.length()))
	var xh := h.normalized()
	var zs := xh.cross(Vector3.UP)
	var sgn := 1.0 if zs.dot(to_road) >= 0.0 else -1.0
	var basis := Basis(d / L, Vector3.UP, zs)
	return [Transform3D(basis, a), sgn, L]


## Retenida (viento) con varilla de anclaje y protector: sube de (-2.2, 0, 0) a (0, 7.2, 0).
## Colocar con la -X local apuntando hacia afuera de la línea. 2 superficies.
static func guy() -> ArrayMesh:
	if _meshes.has("guy"):
		return _meshes["guy"]
	var b := _Builder.new()
	var blk := b.surf(cable_mat())
	var galv := b.surf(_galv())
	var top := Vector3(-pole_r(7.2), 7.2, 0)
	var anchor := Vector3(-2.2, 0.0, 0)
	b.tube(galv, top + Vector3(0, -0.04, 0), top + Vector3(0, 0.04, 0), 0.02, 0.02, 4, false, false)
	b.tube(galv, Vector3(0, 7.16, 0), Vector3(0, 7.24, 0), pole_r(7.2) + 0.012, pole_r(7.2) + 0.012, 6, false, false)
	b.tube(blk, top, anchor + (top - anchor) * 0.27, 0.007, 0.007, 3, false, false)
	# protector amarillo->aquí galvanizado (2 m) y varilla de anclaje
	b.tube(galv, anchor + (top - anchor) * 0.02, anchor + (top - anchor) * 0.27, 0.028, 0.028, 6, true, true)
	b.tube(galv, anchor + Vector3(0, -0.2, 0), anchor + (top - anchor) * 0.02, 0.012, 0.012, 4, false, false)
	b.tube(galv, anchor + Vector3(0, -0.02, 0), anchor + Vector3(0, 0.03, 0), 0.08, 0.06, 6, false, true)
	var mesh := b.commit()
	_meshes["guy"] = mesh
	return mesh


## Añade a un SurfaceTool (solo normales) un cable colgado entre a y b (coordenadas de mundo).
## Para acometidas y cruces sueltos que se funden en los lotes del distrito.
static func append_cable(st: SurfaceTool, a: Vector3, b: Vector3, sag: float, r := 0.008, sides := 3, segs := 6) -> void:
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t) + Vector3(0, -4.0 * sag * t * (1.0 - t), 0)
		_Builder.raw_tube(st, prev, p, r, sides)
		prev = p


## Nodo que enciende/apaga las luces hijas según el preset de StreetLook (busca por duck typing un nodo
## con get_time_of_day()). Encendidas en "golden_hour" y "rainy_night"; apagadas en "overcast_day".
## Si no hay StreetLook en el árbol, quedan encendidas con energía moderada.
static func make_light_switch() -> Node3D:
	var n := LightSwitch.new()
	n.name = "AlumbradoPublico"
	return n


## Luz de una luminaria (SpotLight3D hacia abajo, sin sombra, rango 14 m, se desvanece a > 55 m).
static func make_lamp_light() -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.76, 0.5)
	l.light_energy = 4.0
	l.light_specular = 0.6
	l.spot_range = 14.0
	l.spot_angle = 62.0
	l.spot_angle_attenuation = 0.6
	l.spot_attenuation = 0.75
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 55.0
	l.distance_fade_length = 15.0
	return l


## Transform de la luz de la luminaria dado el transform del poste: bajo la cabeza, apuntando abajo e
## inclinada 18° hacia la calzada (SpotLight3D ilumina hacia su -Z).
static func lamp_light_xform(pole_xf: Transform3D) -> Transform3D:
	var dir := Vector3(0.0, -cos(deg_to_rad(18.0)), sin(deg_to_rad(18.0)))
	return pole_xf * Transform3D(Basis.looking_at(dir, Vector3(0, 0, 1)), LAMP_LIGHT_POS)


# ================================================================ piezas internas
static func _pin_insulator(b: _Builder, porc: int, galv: int, base: Vector3) -> void:
	b.tube(galv, base, base + Vector3(0, 0.05, 0), 0.016, 0.016, 4, false, false)
	var y := base.y + 0.05
	var prof := [[0.0, 0.035], [0.04, 0.078], [0.08, 0.042], [0.12, 0.064], [0.17, 0.028]]
	for i in prof.size() - 1:
		var a: Array = prof[i]
		var c: Array = prof[i + 1]
		b.tube(porc, Vector3(base.x, y + a[0], base.z), Vector3(base.x, y + c[0], base.z), a[1], c[1], 5, false, i == prof.size() - 2)


static func _transformer(b: _Builder, galv: int, porc: int, blk: int) -> void:
	var c := Vector3(0, 0, -0.58)
	var y0 := 7.55
	var y1 := 8.5
	b.tube(galv, Vector3(c.x, y0 - 0.06, c.z), Vector3(c.x, y0, c.z), 0.24, 0.29, 8, true, false)
	b.tube(galv, Vector3(c.x, y0, c.z), Vector3(c.x, y1, c.z), 0.29, 0.29, 8, false, false)
	b.tube(galv, Vector3(c.x, y1, c.z), Vector3(c.x, y1 + 0.04, c.z), 0.31, 0.31, 8, false, false)
	b.tube(galv, Vector3(c.x, y1 + 0.04, c.z), Vector3(c.x, y1 + 0.12, c.z), 0.31, 0.22, 8, false, true)
	# aletas de radiador
	for ang in [PI * 0.5, PI * 0.8, -PI * 0.8, -PI * 0.5]:
		var d := Vector3(sin(ang), 0, cos(ang))
		b.prism(galv, c + d * 0.31 + Vector3(0, y0 + 0.12, 0), c + d * 0.31 + Vector3(0, y1 - 0.1, 0), 0.025, 0.09, 0.0, d)
	# soportes al poste
	for yy in [7.75, 8.3]:
		b.prism(galv, Vector3(0, yy, -pole_r(yy)), Vector3(0, yy, c.z + 0.28), 0.14, 0.05, 0.01)
		b.tube(galv, Vector3(0, yy - 0.04, 0), Vector3(0, yy + 0.04, 0), pole_r(yy) + 0.014, pole_r(yy) + 0.014, 6, false, false)
	# bujes de alta en la tapa y cable de alimentación hacia la cruceta
	for bx in [-0.12, 0.12]:
		var bb := Vector3(bx, y1 + 0.1, c.z - 0.05)
		b.tube(porc, bb, bb + Vector3(0, 0.18, 0), 0.04, 0.025, 6, false, true)
		b.tube(blk, bb + Vector3(0, 0.18, 0), Vector3(bx * 0.5, 10.6, -0.7 if bx < 0 else 0.25), 0.006, 0.006, 3, false, false)
	# bujes de baja hacia la percha
	b.tube(porc, Vector3(0.2, y1 - 0.2, c.z - 0.22), Vector3(0.2, y1 - 0.2, c.z - 0.34), 0.03, 0.02, 6, false, true)
	b.tube(blk, Vector3(0.2, y1 - 0.2, c.z - 0.34), Vector3(0.0, 8.8, -0.37), 0.01, 0.01, 3, false, false)
	# cortacircuitos (fusibles) en la cruceta
	for zi in [-0.4, 0.6]:
		b.prism(porc, Vector3(0.0, 10.08, zi), Vector3(0.0, 10.3, zi), 0.04, 0.04, 0.008)


static func _coil(b: _Builder, s: int, center: Vector3, R: float, r: float, loops: int) -> void:
	for k in loops:
		var c := center + Vector3(0.0, (k - (loops - 1) * 0.5) * 0.015, (k - (loops - 1) * 0.5) * r * 1.6)
		b.torus(s, c, Vector3.RIGHT, Vector3.UP, R - k * 0.012, r, 8, 3)


# ================================================================ constructor de mallas
class _Builder:
	var _sts: Array[SurfaceTool] = []
	var _mats: Array[Material] = []

	func surf(m: Material) -> int:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sts.append(st)
		_mats.append(m)
		return _sts.size() - 1

	func st(i: int) -> SurfaceTool:
		return _sts[i]

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for i in _sts.size():
			var s := _sts[i]
			s.index()
			s.generate_tangents()
			s.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _mats[i])
		return mesh

	static func _frame(axis: Vector3) -> Array:
		var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var p1 := axis.cross(ref).normalized()
		var p2 := axis.cross(p1).normalized()
		return [p1, p2]

	func _v(s: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
		s.set_normal(n)
		s.set_uv(uv)
		s.add_vertex(p)

	## Tronco de cono suave a→b con UV (U alrededor, V de v0 a v1). Tapas opcionales.
	func tube(si: int, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, cap_a: bool, cap_b: bool, v0 := 0.0, v1 := -1.0) -> void:
		var s := _sts[si]
		var ax := b - a
		var len := ax.length()
		if len < 0.0001:
			return
		ax /= len
		if v1 < -0.5:
			v1 = v0 + len
		var f := _frame(ax)
		var p1: Vector3 = f[0]
		var p2: Vector3 = f[1]
		var slope := (ra - rb) / len
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := p1 * cos(a0) + p2 * sin(a0)
			var d1 := p1 * cos(a1) + p2 * sin(a1)
			var n0 := (d0 + ax * slope).normalized()
			var n1 := (d1 + ax * slope).normalized()
			var u0 := float(i) / sides
			var u1 := float(i + 1) / sides
			# frente horario visto desde fuera
			_v(s, a + d0 * ra, n0, Vector2(u0, v0))
			_v(s, b + d1 * rb, n1, Vector2(u1, v1))
			_v(s, a + d1 * ra, n1, Vector2(u1, v0))
			_v(s, a + d0 * ra, n0, Vector2(u0, v0))
			_v(s, b + d0 * rb, n0, Vector2(u0, v1))
			_v(s, b + d1 * rb, n1, Vector2(u1, v1))
			if cap_a and ra > 0.0005:
				_v(s, a, -ax, Vector2(0.5, 0.5))
				_v(s, a + d0 * ra, -ax, Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5))
				_v(s, a + d1 * ra, -ax, Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5))
			if cap_b and rb > 0.0005:
				_v(s, b, ax, Vector2(0.5, 0.5))
				_v(s, b + d1 * rb, ax, Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5))
				_v(s, b + d0 * rb, ax, Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5))

	## Prisma rectangular a→b (sección w × h, aristas achaflanadas c) con tapas. `up` orienta la altura h.
	func prism(si: int, a: Vector3, b: Vector3, w: float, h: float, c: float, up := Vector3.ZERO) -> void:
		var s := _sts[si]
		var ax := b - a
		var len := ax.length()
		if len < 0.0001:
			return
		ax /= len
		var vy: Vector3
		if up != Vector3.ZERO:
			vy = up.normalized()
			vy = (vy - ax * vy.dot(ax)).normalized()
		else:
			vy = Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.BACK
			vy = (vy - ax * vy.dot(ax)).normalized()
		var vx := vy.cross(ax).normalized()
		var hw := w * 0.5
		var hh := h * 0.5
		c = minf(c, minf(hw, hh) * 0.9)
		var prof: Array[Vector2] = []
		if c > 0.0005:
			prof = [Vector2(hw, -hh + c), Vector2(hw, hh - c), Vector2(hw - c, hh), Vector2(-hw + c, hh),
				Vector2(-hw, hh - c), Vector2(-hw, -hh + c), Vector2(-hw + c, -hh), Vector2(hw - c, -hh)]
		else:
			prof = [Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh), Vector2(-hw, -hh)]
		var n := prof.size()
		var u := 0.0
		for i in n:
			var q0 := prof[i]
			var q1 := prof[(i + 1) % n]
			var e := q1 - q0
			var nn := Vector2(e.y, -e.x).normalized()   # normal hacia fuera (perfil antihorario)
			var nrm := (vx * nn.x + vy * nn.y).normalized()
			var p0 := vx * q0.x + vy * q0.y
			var pp1 := vx * q1.x + vy * q1.y
			var u1 := u + e.length()
			_quad(s, a + p0, a + pp1, b + pp1, b + p0, nrm, Vector2(u, 0), Vector2(u1, len))
			u = u1
		# tapas
		for side in [0, 1]:
			var o: Vector3 = a if side == 0 else b
			var nrm2: Vector3 = -ax if side == 0 else ax
			for i in range(1, n - 1):
				var t0 := o + vx * prof[0].x + vy * prof[0].y
				var t1 := o + vx * prof[i].x + vy * prof[i].y
				var t2 := o + vx * prof[i + 1].x + vy * prof[i + 1].y
				_tri(s, t0, t1, t2, nrm2)

	func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv0: Vector2, uv1: Vector2) -> void:
		var verts := [[a, Vector2(uv0.x, uv0.y)], [b, Vector2(uv1.x, uv0.y)], [c, Vector2(uv1.x, uv1.y)], [d, Vector2(uv0.x, uv1.y)]]
		if (b - a).cross(c - a).dot(n) > 0.0:
			verts = [verts[0], verts[3], verts[2], verts[1]]
		for k in [0, 1, 2, 0, 2, 3]:
			_v(s, verts[k][0], n, verts[k][1])

	func _tri(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		_v(s, a, n, Vector2(a.x + a.z, a.y))
		_v(s, b, n, Vector2(b.x + b.z, b.y))
		_v(s, c, n, Vector2(c.x + c.z, c.y))

	## Toro (rollo de cable) en el plano (ua, ub) con centro c.
	func torus(si: int, c: Vector3, ua: Vector3, ub: Vector3, R: float, r: float, seg: int, sides: int) -> void:
		var s := _sts[si]
		var axis := ua.cross(ub).normalized()
		var ring: Array = []
		for i in seg + 1:
			var t := TAU * i / seg
			var dir := ua * cos(t) + ub * sin(t)
			var row: Array = []
			for j in sides + 1:
				var q := TAU * j / sides
				var nrm := dir * cos(q) + axis * sin(q)
				row.append([c + dir * R + nrm * r, nrm, Vector2(float(i) / seg, float(j) / sides)])
			ring.append(row)
		for i in seg:
			for j in sides:
				var A: Array = ring[i][j]
				var B: Array = ring[i + 1][j]
				var C: Array = ring[i + 1][j + 1]
				var D: Array = ring[i][j + 1]
				var quad := [A, B, C, A, C, D]
				var fn: Vector3 = (A[1] + C[1]).normalized()
				if (B[0] - A[0]).cross(C[0] - A[0]).dot(fn) > 0.0:
					quad = [A, C, B, A, D, C]
				for v in quad:
					_v(s, v[0], v[1], v[2])

	## Cable colgado (parábola) a→b con flecha `sag`.
	func catenary(si: int, a: Vector3, b: Vector3, sag: float, r: float, sides: int, segs: int) -> void:
		var prev := a
		for i in range(1, segs + 1):
			var t := float(i) / segs
			var p := a.lerp(b, t) + Vector3(0, -4.0 * sag * t * (1.0 - t), 0)
			tube(si, prev, p, r, r, sides, false, false)
			prev = p

	## Tubo plano sin UV (para lotes del distrito que solo llevan normales).
	static func raw_tube(s: SurfaceTool, a: Vector3, b: Vector3, r: float, sides: int) -> void:
		var ax := b - a
		var len := ax.length()
		if len < 0.0001:
			return
		ax /= len
		var f := _frame(ax)
		var p1: Vector3 = f[0]
		var p2: Vector3 = f[1]
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := p1 * cos(a0) + p2 * sin(a0)
			var d1 := p1 * cos(a1) + p2 * sin(a1)
			for v in [[a + d0 * r, d0], [b + d1 * r, d1], [a + d1 * r, d1], [a + d0 * r, d0], [b + d0 * r, d0], [b + d1 * r, d1]]:
				s.set_normal(v[1])
				s.add_vertex(v[0])


# ================================================================ interruptor del alumbrado
class LightSwitch extends Node3D:
	var _look: Node = null
	var _t := 0.0
	var _state := ""
	var _searched := 0

	func _ready() -> void:
		_t = 10.0   # evalúa en el primer frame

	func _process(delta: float) -> void:
		_t += delta
		if _t < 0.5:
			return
		_t = 0.0
		if _look == null or not is_instance_valid(_look):
			_look = null
			if _searched < 20:
				_searched += 1
				_look = _find_look(get_tree().root)
		var preset := "none"
		if _look != null:
			preset = str(_look.call("get_time_of_day"))
		if preset == _state:
			return
		_state = preset
		var on := preset != "overcast_day"
		var energy := 4.0
		if preset == "golden_hour":
			energy = 2.6
		elif preset == "none":
			energy = 2.2   # sin StreetLook: encendidas con energía moderada
		for c in get_children():
			if c is Light3D:
				(c as Light3D).visible = on
				(c as Light3D).light_energy = energy
		Poles.set_lamps_on(on)

	func _find_look(n: Node) -> Node:
		if n.has_method("get_time_of_day") and n.has_method("set_time_of_day"):
			return n
		for c in n.get_children():
			var r := _find_look(c)
			if r != null:
				return r
		return null

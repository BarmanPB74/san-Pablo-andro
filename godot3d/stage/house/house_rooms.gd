class_name HouseRooms
extends RefCounted
## Los diez cuartos de La Casa y cómo se conectan. La casa es un recuerdo: no tiene exterior. Se llega por un portal al
## vestíbulo y de ahí se pasa de cuarto en cuarto por arcos con velo de bruma; HouseScene tiene cargado UN solo cuarto.
## Estilo: palacio gótico sobrio, piedra gris fría, madera oscura, telas vino/morado apagadas, luz de velas. Poco mobiliario.
##
##                       ┌────────── patio ◄── sala ──┐
##    cocina ── comedor ─┤                            │
##                       └── vestíbulo ── galería ── baño
##                              ▲   (portal)      │ │ │ │
##                                             hab1 hab2 hab3 hab4   (1 y 2 al norte de la galería, 3 y 4 al sur)
##
## Cada cuarto ≤ 5 luces propias (el móvil admite 8 por objeto y el portal y Andro suman 2). Puertas: arcos de 3.2 m de luz.

const START := "vestibulo"
const MIN_CEILING := 6.5                    # techo más bajo de la casa: ahí caben el arco de las puertas y un portal

const DEFS := {
	"vestibulo": {"title": "Vestíbulo", "dim": Vector3(16, 11, 20), "doors": [
		{"side": "N", "at": 0.0, "to": "sala"},
		{"side": "E", "at": 0.0, "to": "galeria"},
		{"side": "W", "at": 0.0, "to": "comedor"}]},
	"sala": {"title": "Sala", "dim": Vector3(18, 9, 16), "doors": [
		{"side": "S", "at": 0.0, "to": "vestibulo"},
		{"side": "E", "at": 0.0, "to": "patio"}]},
	"comedor": {"title": "Comedor", "dim": Vector3(16, 8, 14), "doors": [
		{"side": "E", "at": 0.0, "to": "vestibulo"},
		{"side": "N", "at": -4.0, "to": "cocina"}]},
	"cocina": {"title": "Cocina", "dim": Vector3(14, 7.5, 12), "doors": [
		{"side": "S", "at": -4.0, "to": "comedor"}]},
	"patio": {"title": "Patio interior", "dim": Vector3(24, 14, 24), "doors": [
		{"side": "W", "at": 0.0, "to": "sala"}]},
	"galeria": {"title": "Galería", "dim": Vector3(34, 8, 9), "doors": [
		{"side": "W", "at": 0.0, "to": "vestibulo"},
		{"side": "E", "at": 0.0, "to": "bano"},
		{"side": "N", "at": -8.0, "to": "hab1"},
		{"side": "N", "at": 8.0, "to": "hab2"},
		{"side": "S", "at": -8.0, "to": "hab3"},
		{"side": "S", "at": 8.0, "to": "hab4"}]},
	"hab1": {"title": "Habitación 1", "dim": Vector3(12, 6.5, 12), "doors": [{"side": "S", "at": 0.0, "to": "galeria"}]},
	"hab2": {"title": "Habitación 2", "dim": Vector3(12, 6.5, 12), "doors": [{"side": "S", "at": 0.0, "to": "galeria"}]},
	"hab3": {"title": "Habitación 3", "dim": Vector3(12, 6.5, 12), "doors": [{"side": "N", "at": 0.0, "to": "galeria"}]},
	"hab4": {"title": "Habitación 4", "dim": Vector3(12, 6.5, 12), "doors": [{"side": "N", "at": 0.0, "to": "galeria"}]},
	"bano": {"title": "Baño", "dim": Vector3(10, 6.5, 12), "doors": [{"side": "W", "at": 0.0, "to": "galeria"}]},
}

const SPAWN_POS := Vector3(0, 0.1, 7.5)     # llegada desde el portal, en el vestíbulo, mirando al norte
const SPAWN_YAW := 0.0


static func ids() -> Array:
	return DEFS.keys()


## Dónde aparece Andro al entrar al cuarto `id` viniendo del cuarto `from_id`: {pos, yaw}.
static func arrival(id: String, from_id: String) -> Dictionary:
	var d: Dictionary = DEFS[id]
	for dd in d["doors"]:
		if dd["to"] == from_id:
			return HouseBuilder.arrival_for(d["dim"], dd)
	return {"pos": SPAWN_POS, "yaw": SPAWN_YAW}


## Construye (y cierra) el cuarto `id`. Devuelve el constructor; su `node` cuelga de quien lo pida.
static func make(id: String) -> HouseBuilder:
	var d: Dictionary = DEFS[id]
	var b := HouseBuilder.new(id, d["dim"], d["doors"])
	match id:
		"vestibulo": _vestibulo(b)
		"sala": _sala(b)
		"comedor": _comedor(b)
		"cocina": _cocina(b)
		"patio": _patio(b)
		"galeria": _galeria(b)
		"hab1": _habitacion(b, 1)
		"hab2": _habitacion(b, 2)
		"hab3": _habitacion(b, 3)
		"hab4": _habitacion(b, 4)
		"bano": _bano(b)
	b.finish()
	return b


# ------------------------------------------------------------------ mobiliario sobrio (piezas con orientación)

## Sofá o sillón de `len_m` de largo. dir: 0 mira a -Z, 1 mira a +Z, 2 mira a +X, 3 mira a -X.
static func sofa(b: HouseBuilder, x: float, z: float, len_m: float, dir: int, mkey := "burg") -> void:
	var along_x := dir < 2
	var sx := len_m if along_x else 1.0
	var sz := 1.0 if along_x else len_m
	b.f(x, z, sx, 0.5, sz, mkey)
	var off := Vector2.ZERO
	match dir:
		0: off = Vector2(0, 0.4)
		1: off = Vector2(0, -0.4)
		2: off = Vector2(-0.4, 0)
		_: off = Vector2(0.4, 0)
	b.f(x + off.x, z + off.y, len_m if along_x else 0.2, 0.55, 0.2 if along_x else len_m, mkey, 0.5, false)
	b.f(x, z, sx - 0.2, 0.12, sz - 0.2, "grayfab", 0.5, false)         # cojín


static func table(b: HouseBuilder, x: float, z: float, sx: float, sz: float, h := 0.8, mkey := "wood") -> void:
	b.vbox(Vector3(x, h - 0.06, z), Vector3(sx, 0.12, sz), mkey)
	for ix in [-1.0, 1.0]:
		for iz in [-1.0, 1.0]:
			b.vbox(Vector3(x + ix * (sx * 0.5 - 0.1), (h - 0.12) * 0.5, z + iz * (sz * 0.5 - 0.1)), Vector3(0.14, h - 0.12, 0.14), mkey)
	b.col(Vector3(x, h * 0.5, z), Vector3(sx, h, sz))


## Silla con el respaldo hacia el lado `back` ("N", "S", "E", "W").
static func chair(b: HouseBuilder, x: float, z: float, back: String) -> void:
	b.f(x, z, 0.5, 0.95, 0.5, "wood", 0.0, true)
	var o := Vector2.ZERO
	match back:
		"N": o = Vector2(0, -0.22)
		"S": o = Vector2(0, 0.22)
		"E": o = Vector2(0.22, 0)
		_: o = Vector2(-0.22, 0)
	b.f(x + o.x * 0.9, z + o.y * 0.9, 0.5 if o.x == 0.0 else 0.08, 0.5, 0.5 if o.y == 0.0 else 0.08, "wood", 0.95, false)
	b.f(x, z, 0.4, 0.06, 0.4, "burg", 0.45, false)


## Cama con la cabecera hacia `head_z` (-1 = norte, +1 = sur). w = ancho (x), l = largo (z).
static func bed(b: HouseBuilder, x: float, z: float, w: float, l: float, head_z: float, sheets := "grayfab") -> void:
	b.f(x, z, w + 0.1, 0.45, l + 0.1, "wood")
	b.f(x, z, w - 0.1, 0.25, l - 0.1, sheets, 0.45, false)
	b.f(x, z + head_z * (l * 0.5 - 0.1), w + 0.3, 1.6, 0.2, "wood")                            # cabecera
	for s in [-1.0, 1.0]:
		b.f(x + s * w * 0.25, z + head_z * (l * 0.5 - 0.5), w * 0.4, 0.14, 0.5, "candle", 0.7, false)
	b.f(x, z - head_z * (l * 0.5 - 0.7), w - 0.1, 0.06, 1.1, "burg", 0.7, false)                  # manta a los pies


## Caja contra un muro en su marco (x local, ancho, alto, fondo). Mueble sólido.
static func wall_box(b: HouseBuilder, side: String, x: float, w: float, h: float, depth: float, mkey := "wood") -> void:
	b.fbox(b.frame_of(side), x - w * 0.5, x + w * 0.5, 0.0, h, 0.0, depth, mkey)


## Estantería contra un muro, con hileras de libros en colores apagados.
static func bookshelf(b: HouseBuilder, side: String, x: float, w: float, h := 3.2) -> void:
	var fr := b.frame_of(side)
	wall_box(b, side, x, w, h, 0.5)
	var keys := ["burg", "purple", "grayfab", "blackfab"]
	var rows := int(h / 0.7)
	for r in rows:
		var y := 0.35 + float(r) * 0.7
		var i := 0
		var cx := x - w * 0.5 + 0.1
		while cx < x + w * 0.5 - 0.3:
			var bw := 0.18 + 0.05 * float((i * 7 + r * 3) % 4)
			b.fbox(fr, cx, cx + bw, y, y + 0.4 + 0.04 * float((i * 5) % 3), 0.5, 0.56, keys[(i + r) % 4], false)
			cx += bw + 0.02
			i += 1


## Marco vacío en la pared: un cuadro sin imagen (un recuerdo que aún no está).
static func empty_frame(b: HouseBuilder, side: String, x: float, y0 := 2.2, w := 1.5, h := 2.1) -> void:
	var fr := b.frame_of(side)
	b.fbox(fr, x - w * 0.5 - 0.15, x + w * 0.5 + 0.15, y0 - 0.15, y0 + h + 0.15, 0.0, 0.12, "bronze", false)
	b.fbox(fr, x - w * 0.5, x + w * 0.5, y0, y0 + h, 0.12, 0.14, "void", false)


static func urn(b: HouseBuilder, x: float, z: float, h := 1.0) -> void:
	b.vcyl(Vector3(x, 0.3, z), 0.3, 0.6, "trim")
	b.vcyl(Vector3(x, 0.6 + h * 0.3, z), 0.4, h * 0.6, "stone")
	b.vcyl(Vector3(x, 0.6 + h * 0.65, z), 0.25, h * 0.1, "trim")
	b.col_cyl(Vector3(x, (0.6 + h * 0.7) * 0.5, z), 0.4, 0.6 + h * 0.7)


## Armazón común: piso, techo con vigas, muros con puertas y paredes vestidas.
static func _shell(b: HouseBuilder, floor_main := "floor", floor_edge := "floor2", beam_gap := 4.5, windows := true) -> void:
	b.build_floor(1.4, floor_main, floor_edge)
	b.build_ceiling(beam_gap, b.dim.x < b.dim.z)
	b.build_walls()
	for side in ["N", "S", "E", "W"]:
		b.dress_wall(side, 7.0, windows)


# ------------------------------------------------------------------ los cuartos

static func _vestibulo(b: HouseBuilder) -> void:
	_shell(b, "floor", "floor2", 5.0)
	var h := b.dim.y
	for sx in [-4.5, 4.5]:
		for sz in [-5.0, 5.0]:
			b.column(sx, sz, 0.55, h)
	for sz in [-5.0, 5.0]:
		b.free_arch(Vector3(0, 0, sz), false, 9.0)                 # arcos entre columnas a lo ancho
	for sx in [-4.5, 4.5]:
		b.free_arch(Vector3(sx, 0, 0), true, 10.0)                 # y a lo largo
	b.rug(0, 0, 5.0, 16.0)
	b.vbox(Vector3(0, 0.045, 0), Vector3(4.2, 0.02, 15.2), "burg")
	b.chandelier(Vector3(0, 8.0, 0), 1.8, 1.0, 17.0)
	b.brazier(-3.2, -8.0)
	b.brazier(3.2, -8.0)
	b.candelabrum(-6.8, 8.6, 0.0, true)
	b.candelabrum(6.8, 8.6, 0.0, true)
	for sx in [-5.0, 5.0]:
		urn(b, sx, 8.6, 1.1)
	empty_frame(b, "S", -4.2, 3.2, 2.0, 3.0)
	empty_frame(b, "S", 4.2, 3.2, 2.0, 3.0)


static func _sala(b: HouseBuilder) -> void:
	b.hearth("N", 0.0, 2.6, 2.3)                # antes del armazón: reserva su tramo de muro (sin ventanas)
	_shell(b)
	b.rug(0, 0.5, 8.0, 5.5)
	sofa(b, 0, 1.8, 4.0, 0)
	sofa(b, -5.0, 1.5, 1.2, 2, "purple")
	sofa(b, 5.0, 2.2, 1.2, 3, "purple")
	table(b, 0, -1.3, 2.2, 1.0, 0.5)
	b.candle(Vector3(0, 0.62, -1.3), 0.3)
	bookshelf(b, "W", -4.5, 4.0)
	bookshelf(b, "W", 4.5, 4.0)
	b.chandelier(Vector3(0, 6.2, 0.5), 1.4, 0.9, 14.0)
	b.candelabrum(-8.2, -6.2, 0.0, true)
	b.candelabrum(-8.2, 6.2, 0.0, true)
	b.f(7.5, -6.5, 0.7, 2.2, 0.5, "wood")                                  # reloj de pie
	b.f(7.5, -6.5, 0.5, 0.3, 0.3, "bronze", 1.3, false)
	empty_frame(b, "E", -5.2, 3.0, 1.6, 2.2)


static func _comedor(b: HouseBuilder) -> void:
	b.hearth("W", 0.0, 2.6, 2.2)
	_shell(b)
	b.rug(-1, 0, 10.0, 4.4, "grayfab")
	table(b, -1, 0, 8.0, 1.4, 0.85, "wood")
	for i in 4:
		var cx := -4.2 + float(i) * 2.4
		chair(b, cx, -1.4, "N")
		chair(b, cx, 1.4, "S")
	chair(b, -5.8, 0, "W")
	chair(b, 3.8, 0, "E")
	b.candle(Vector3(-3, 0.85, 0), 0.4)
	b.candle(Vector3(-1, 0.85, 0), 0.4)
	b.candle(Vector3(1, 0.85, 0), 0.4)
	wall_box(b, "S", -3.5, 4.0, 1.1, 0.7)                                  # aparador
	wall_box(b, "S", 3.5, 4.0, 1.1, 0.7)
	empty_frame(b, "S", -3.5, 2.4, 2.4, 2.4)
	empty_frame(b, "S", 3.5, 2.4, 2.4, 2.4)
	b.chandelier(Vector3(-1, 5.6, 0), 1.6, 0.9, 14.0)
	b.candelabrum(6.8, 5.8, 0.0, true)
	b.candelabrum(-6.8, 5.8, 0.0, true)


static func _cocina(b: HouseBuilder) -> void:
	b.hearth("N", 2.0, 3.4, 2.4)
	_shell(b, "floor", "floor2", 4.5)
	wall_box(b, "W", 0.0, 7.0, 1.0, 0.9, "stone")                          # encimera de piedra (muro W: x local = -z del mundo)
	wall_box(b, "E", 0.0, 6.0, 1.0, 0.9, "stone")
	b.f(-3.0, -2.0, 0.9, 0.35, 0.9, "iron", 1.0, false)                    # olla
	table(b, 1.5, 0.8, 3.2, 1.4, 1.0, "stone")
	b.f(1.0, 0.8, 0.5, 0.35, 0.5, "iron", 1.0, false)
	for i in 3:
		b.f(-5.8 + float(i) * 0.1, -5.0 + float(i) * 0.8, 0.8, 0.9, 0.8, "wood")   # barriles
	b.f(5.5, -5.0, 0.8, 0.9, 0.8, "wood")
	bookshelf(b, "S", -3.5, 3.0, 2.8)                                      # alacena (en el muro S, x local = -x mundo: queda al este)
	b.chandelier(Vector3(0, 5.8, 0), 1.0, 0.8, 12.0)
	b.candelabrum(-6.2, 5.2, 0.0, true)


static func _patio(b: HouseBuilder) -> void:
	_shell(b, "floor", "floor2", 6.0, true)
	var h := b.dim.y
	# fuente seca al centro con agua negra
	b.cyl(0, 0, 3.0, 0.8, "stone")
	b.vcyl(Vector3(0, 0.76, 0), 2.6, 0.06, "water")
	b.cyl(0, 0, 0.5, 2.6, "trim")
	b.vcyl(Vector3(0, 2.8, 0), 1.0, 0.3, "trim")
	b.vcyl(Vector3(0, 0.03, 0), 4.4, 0.06, "floor2")
	# claustro: columnas alrededor
	for sx in [-8.0, 8.0]:
		for sz in [-8.0, 8.0]:
			b.column(sx, sz, 0.6, h)
	for sz in [-8.0, 8.0]:
		b.free_arch(Vector3(0, 0, sz), false, 16.0)
	for sx in [-8.0, 8.0]:
		b.free_arch(Vector3(sx, 0, 0), true, 16.0)
	# óculo: un disco de luz fría en el techo (no hay cielo: es luz de luna encerrada)
	b.vbox(Vector3(0, h - 0.04, 0), Vector3(8.0, 0.08, 8.0), "oculus")
	b.light(Vector3(0, h - 3.0, 0), 1.1, 20.0, Color(0.62, 0.68, 0.82))
	# bancas y urnas
	b.f(-5.0, 5.0, 3.0, 0.5, 0.8, "stone")
	b.f(5.0, 5.0, 3.0, 0.5, 0.8, "stone")
	b.f(-5.0, -5.0, 3.0, 0.5, 0.8, "stone")
	b.f(5.0, -5.0, 3.0, 0.5, 0.8, "stone")
	for u in [Vector2(-10.6, -10.6), Vector2(10.6, -10.6), Vector2(-10.6, 10.6), Vector2(10.6, 10.6)]:
		urn(b, u.x, u.y, 1.3)
	# árbol seco
	b.cyl(7.0, -1.0, 0.35, 3.4, "beam")
	b.vbox_t(Transform3D(Basis(Vector3(0, 0, 1), 0.7), Vector3(7.6, 3.9, -1.0)), Vector3(2.2, 0.2, 0.2), "beam")
	b.vbox_t(Transform3D(Basis(Vector3(0, 0, 1), -0.8), Vector3(6.3, 4.1, -1.0)), Vector3(2.0, 0.18, 0.18), "beam")
	b.brazier(-10.2, 6.0)
	b.brazier(10.2, 4.0)
	b.candelabrum(-4.5, -10.5, 0.0, true)


static func _galeria(b: HouseBuilder) -> void:
	_shell(b, "floor", "floor2", 6.0)
	b.rug(0, 0, 28.0, 2.2, "burg")
	for x in [-13.0, -4.0, 4.0, 13.0]:
		b.candelabrum(x, -3.6, 0.0, true)
	for x in [-13.0, 0.0, 13.0]:
		urn(b, x, 3.6, 1.0)
	for x in [-13.2, 0.0, 13.2]:
		empty_frame(b, "N", x, 2.4, 1.6, 2.4)
	for x in [-13.2, 0.0, 13.2]:
		empty_frame(b, "S", x, 2.4, 1.6, 2.4)


## Las cuatro habitaciones: misma planta, cada una con un par de piezas distintas (sin inventar aún su historia).
## La puerta está al sur (hab1, hab2) o al norte (hab3, hab4); la cama va contra el muro opuesto.
static func _habitacion(b: HouseBuilder, n: int) -> void:
	_shell(b, "floor", "floor2", 6.0)
	var south: bool = b.doors[0]["side"] == "S"
	var head := -1.0 if south else 1.0                       # hacia dónde mira la cabecera (-1 = norte, +1 = sur)
	var big := n == 2 or n == 4
	var bw := 2.4 if big else 1.4
	var bed_z := head * 3.9                                  # cama a 3.9 m del centro, contra el muro del fondo
	bed(b, 0.0, bed_z, bw, 3.2, head)
	b.rug(0, 0.0, 5.0, 4.0)
	for s in [-1.0, 1.0]:                                    # mesitas de noche
		b.f(s * (bw * 0.5 + 0.6), head * 5.2, 0.6, 0.55, 0.6, "wood")
	b.candle(Vector3(bw * 0.5 + 0.6, 0.55, head * 5.2), 0.3)
	# ropero y escritorio contra los muros E / W (alternan según la habitación)
	var wa := "E" if n % 2 == 1 else "W"
	var wb := "W" if n % 2 == 1 else "E"
	wall_box(b, wa, _local_along(wa, head * 3.0), 3.0, 2.6, 0.8)                    # ropero junto a la cama
	wall_box(b, wb, _local_along(wb, -head * 2.0), 2.2, 0.8, 0.8)                   # escritorio hacia la puerta
	var east := wb == "E"
	chair(b, 4.3 if east else -4.3, -head * 2.0, "W" if east else "E")
	if n == 4:
		bookshelf(b, wa, _local_along(wa, -head * 2.5), 3.0, 2.8)
	b.candelabrum(-(bw * 0.5 + 1.8), head * 5.4, 0.0, true)
	b.chandelier(Vector3(0, 4.4, 0), 0.9, 0.8, 11.0)


## Coordenada local (a lo largo del muro) de un punto del mundo con coordenada z = `z` junto a un muro E o W.
static func _local_along(side: String, z: float) -> float:
	return z if side == "E" else -z


static func _bano(b: HouseBuilder) -> void:
	b.reserve("N", 0.0, 1.2)                    # el espejo cubre ese tramo del muro: sin ventana
	_shell(b, "tile", "floor2", 6.0)
	# bañera de piedra exenta con agua negra
	b.f(2.6, -3.6, 1.1, 0.8, 2.4, "trim")
	b.f(2.6, -3.6, 0.8, 0.04, 2.1, "water", 0.78, false)
	# lavamanos de piedra con espejo de vidrio oscuro
	wall_box(b, "N", 0.0, 1.8, 0.95, 0.7, "stone")
	b.fbox(b.frame_of("N"), -1.0, 1.0, 1.9, 3.9, 0.0, 0.1, "bronze", false)
	b.fbox(b.frame_of("N"), -0.85, 0.85, 2.05, 3.75, 0.1, 0.12, "glass", false)
	b.f(-3.5, 4.6, 0.7, 0.45, 0.7, "stone")                                 # taburete
	b.rug(-1.5, 1.0, 3.0, 2.0, "grayfab")
	b.candelabrum(3.8, 4.8, 0.0, true)
	b.candelabrum(-3.8, -4.8, 0.0, true)
	b.chandelier(Vector3(0, 4.6, 0), 0.8, 0.7, 10.0)

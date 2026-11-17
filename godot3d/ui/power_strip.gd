class_name PowerStrip
extends Node
## Selector de poderes estilo GTA San Andreas: una tira horizontal de casillas arriba al centro con los poderes; el elegido
## se resalta con su nombre, rango y tope. Se abre con el icono del poder (táctil), T o el D-pad ↓. Tocar una casilla
## elige; ← → mueven, Enter/Espacio confirman, Esc/T cierran. Se cierra solo tras unos segundos sin tocarla.
## Hoy solo existe la bola de fuego; las casillas "???" son poderes por venir.

signal chosen(id: String)
signal opened
signal closed

const SLOTS := [
	{"id": "fireball", "name": "BOLA DE FUEGO"},
	{"id": "", "name": "???"},
	{"id": "", "name": "???"},
	{"id": "", "name": "???"},
]
const SLOT := 92.0
const GAP := 10.0
const IDLE_CLOSE := 4.0

var book: SpellBook
var caster: PowerCaster
var is_open := false
var index := 0
var _canvas: CanvasLayer
var _draw: Control
var _idle := 0.0


func setup(b: SpellBook, c: PowerCaster) -> void:
	book = b
	caster = c
	_canvas = CanvasLayer.new()
	_canvas.layer = 12
	add_child(_canvas)
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	_canvas.add_child(_draw)
	_canvas.visible = false


func open() -> void:
	if is_open or UiLock.blocked:
		return
	is_open = true
	_idle = 0.0
	for i in SLOTS.size():
		if SLOTS[i].id == caster.active:
			index = i
	_canvas.visible = true
	_draw.queue_redraw()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_canvas.visible = false
	closed.emit()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


## Casilla elegida: si el poder existe, queda activo.
func choose(i: int) -> void:
	i = clampi(i, 0, SLOTS.size() - 1)
	index = i
	var id: String = SLOTS[i].id
	if id != "":
		caster.active = id
		chosen.emit(id)
	_draw.queue_redraw()


func _slot_rect(i: int, vp: Vector2) -> Rect2:
	var total := SLOTS.size() * SLOT + (SLOTS.size() - 1) * GAP
	return Rect2(vp.x * 0.5 - total * 0.5 + i * (SLOT + GAP), 22.0, SLOT, SLOT)


func slot_at(pos: Vector2) -> int:
	var vp := _draw.get_viewport_rect().size
	for i in SLOTS.size():
		if _slot_rect(i, vp).grow(4.0).has_point(pos):
			return i
	return -1


func _process(delta: float) -> void:
	if caster == null:
		return
	if InputMap.has_action("power_panel") and Input.is_action_just_pressed("power_panel"):
		toggle()
	if is_open:
		_idle += delta
		if UiLock.blocked or _idle > IDLE_CLOSE:
			close()
		else:
			_draw.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	var press := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		press = true
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press = true
		pos = event.position
	if press:
		_idle = 0.0
		var i := slot_at(pos)
		if i >= 0:
			choose(i)
			if SLOTS[i].id != "":
				close()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_idle = 0.0
		match event.physical_keycode:
			KEY_LEFT:
				index = (index - 1 + SLOTS.size()) % SLOTS.size()
			KEY_RIGHT:
				index = (index + 1) % SLOTS.size()
			KEY_ENTER, KEY_SPACE:
				choose(index)
				if SLOTS[index].id != "":
					close()
			KEY_ESCAPE:
				close()
			_:
				return
		get_viewport().set_input_as_handled()


func _on_draw() -> void:
	if not is_open:
		return
	var vp := _draw.get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var amber := Color(1.0, 0.72, 0.3)
	var total := SLOTS.size() * SLOT + (SLOTS.size() - 1) * GAP
	_draw.draw_rect(Rect2(vp.x * 0.5 - total * 0.5 - 16, 6, total + 32, SLOT + 92), Color(0.02, 0.02, 0.04, 0.72))
	_draw.draw_rect(Rect2(vp.x * 0.5 - total * 0.5 - 16, 6, total + 32, SLOT + 92), Color(amber, 0.5), false, 2.0)
	for i in SLOTS.size():
		var r := _slot_rect(i, vp)
		var sel := i == index
		var id: String = SLOTS[i].id
		_draw.draw_rect(r, Color(0.08, 0.07, 0.1, 0.95))
		_draw.draw_rect(r, Color(amber, 1.0 if sel else 0.35), false, 4.0 if sel else 2.0)
		var c := r.get_center()
		if id != "":
			var tier := Abilities.tier(id, book.rank(id))
			_draw.draw_circle(c, 22, Color(tier.glow, 0.3))
			var pts := PackedVector2Array()
			for k in 20:
				var a := TAU * float(k) / 20.0
				pts.append(c + Vector2(cos(a) * 13.0, sin(a) * 13.0 * (1.0 + 0.6 * maxf(0.0, -sin(a)))))
			_draw.draw_colored_polygon(pts, Color(tier.edge if not tier.get("dark", false) else Color(0.12, 0, 0.2), 0.95))
			_draw.draw_circle(c + Vector2(0, 4), 7, Color(tier.core, 0.98))
		else:
			_draw.draw_string(font, c + Vector2(-14, 10), "???", HORIZONTAL_ALIGNMENT_CENTER, 40, 24, Color(1, 1, 1, 0.3))
	var cur: Dictionary = SLOTS[index]
	var line := "???  (aún no disponible)"
	if cur.id != "":
		var rk := book.rank(cur.id)
		line = "%s   ·   rango %d   ·   tope %d %%   ·   %s" % [cur.name, rk, int(round(book.cap(cur.id) * 100.0)), Abilities.tier(cur.id, rk).name]
	var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_draw.draw_string_outline(font, Vector2(vp.x * 0.5 - w * 0.5, SLOT + 56), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.9))
	_draw.draw_string(font, Vector2(vp.x * 0.5 - w * 0.5, SLOT + 56), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.96, 0.84, 0.56))

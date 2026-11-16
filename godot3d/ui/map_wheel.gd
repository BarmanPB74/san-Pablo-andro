class_name MapWheel
extends CanvasLayer
## Rueda circular de mapas (estilo GTA V). Se abre con el botón MAPAS (táctil), Tab/M (teclado) o Select (mando); el tiempo se
## ralentiza y Andro se queda quieto. Un toque (o soltar el dedo) sobre un sector conjura un portal hacia ese mapa desde
## donde esté Andro; los sectores sin desbloquear llevan candado. Los sectores y su orden salen de `MapCatalog`.
##
## Táctil/ratón: tocar o arrastrar resalta el sector, soltar sobre él lo elige; tocar el centro o fuera del aro cierra.
## Teclado: ← → (A/D) mueven la selección, Enter/Espacio elige, Esc cierra. Mando: palanca derecha apunta, A elige, B cierra.

signal opened
signal closed
signal chosen(map_id: String)

const SLOW := 0.2                            # escala de tiempo mientras está abierta
const GAP := 0.045                           # hueco entre sectores (rad)
const GOLD := Color(0.96, 0.84, 0.56)
const ICE := Color(0.62, 0.68, 0.86)

var story: Story
var is_open := false
var hover := -1                              # sector resaltado (-1 = ninguno)
var _t := 0.0                                # animación de apertura 0..1 (en tiempo real)
var _msg := ""
var _msg_t := 0.0
var _shake := 0.0
var _root: Control
var _touch := -1
var _press_inside := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_wheel)
	_root.visible = false
	add_child(_root)


func setup(p_story: Story) -> void:
	story = p_story


func _exit_tree() -> void:
	if is_open:
		Engine.time_scale = 1.0
		UiLock.blocked = false


# ------------------------------------------------------------------ geometría (pública para pruebas)

func wheel_center() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


func r_out() -> float:
	var s := get_viewport().get_visible_rect().size
	return minf(s.x, s.y) * 0.42


func r_in() -> float:
	return r_out() * 0.40


## Ángulo (rad, 0 = arriba, horario) del centro del sector i.
func slot_angle(i: int) -> float:
	return TAU * float(i) / float(MapCatalog.count())


## Posición en pantalla del centro del sector i (donde cae el dedo para elegirlo).
func slot_pos(i: int) -> Vector2:
	var a := slot_angle(i)
	return wheel_center() + Vector2(sin(a), -cos(a)) * (r_in() + r_out()) * 0.5


## Sector bajo un punto de pantalla, o -1 si está en el centro o fuera del aro.
func slot_at(pos: Vector2) -> int:
	var d := pos - wheel_center()
	var r := d.length()
	if r < r_in() or r > r_out():
		return -1
	return slot_from_dir(d)


func slot_from_dir(d: Vector2) -> int:
	var a := fposmod(atan2(d.x, -d.y), TAU)        # 0 = arriba, creciente en sentido horario
	var n := MapCatalog.count()
	return int(roundf(a / (TAU / float(n)))) % n


# ------------------------------------------------------------------ abrir / cerrar / elegir

func open() -> void:
	if is_open or story == null or not story.can_travel():
		return
	is_open = true
	_t = 0.0
	hover = -1
	_msg = ""
	_touch = -1
	UiLock.blocked = true
	Engine.time_scale = SLOW
	_root.visible = true
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiLock.blocked = false
	Engine.time_scale = 1.0
	_root.visible = false
	_touch = -1
	closed.emit()


## Elige el sector i: si se puede viajar cierra la rueda y conjura el portal; si no, avisa por qué (y sigue abierta).
func choose(i: int) -> bool:
	if story == null or i < 0:
		return false
	var slot := MapCatalog.slot(i)
	var id: String = slot["id"]
	var reason := story.travel_block_reason(id)
	if reason != "":
		_msg = reason
		_msg_t = 2.2
		_shake = 1.0
		return false
	close()
	if story.conjure_to(id):
		chosen.emit(id)
		return true
	return false


# ------------------------------------------------------------------ entrada

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)         # tiempo real aunque el juego vaya en cámara lenta
	if Input.is_action_just_pressed("map_wheel"):
		if is_open:
			close()
		else:
			open()
	if not is_open:
		return
	_t = minf(1.0, _t + real * 6.0)
	_msg_t = maxf(0.0, _msg_t - real)
	_shake = maxf(0.0, _shake - real * 4.0)
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.55:
		hover = slot_from_dir(stick)
	_root.queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch == -1:
			_touch = t.index
			press(t.position)
		elif not t.pressed and t.index == _touch:
			_touch = -1
			release(t.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch:
			hover = slot_at(d.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT:
			if m.pressed:
				press(m.position)
			else:
				release(m.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _touch == -1:
		hover = slot_at((event as InputEventMouseMotion).position)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		var n := MapCatalog.count()
		if k == KEY_LEFT or k == KEY_A:
			hover = posmod((hover if hover >= 0 else 0) - 1, n)
		elif k == KEY_RIGHT or k == KEY_D:
			hover = posmod((hover if hover >= 0 else n - 1) + 1, n)
		elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			choose(hover)
		elif k == KEY_ESCAPE:
			close()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_A:
			choose(hover)
		elif b == JOY_BUTTON_B:
			close()


## Dedo/clic abajo: resalta el sector que toca (o recuerda si empezó en el centro/fuera).
func press(pos: Vector2) -> void:
	hover = slot_at(pos)
	_press_inside = hover >= 0


## Dedo/clic arriba: sobre el mismo sector lo elige; en el centro o fuera del aro cierra.
func release(pos: Vector2) -> void:
	var i := slot_at(pos)
	if i >= 0 and i == hover:
		choose(i)
	elif i < 0 and not _press_inside:
		close()
	elif i < 0:
		hover = -1


# ------------------------------------------------------------------ dibujo

func _arc_points(r: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / float(steps))
		pts.append(Vector2(sin(a), -cos(a)) * r)
	return pts


func _draw_wheel() -> void:
	if not is_open:
		return
	var font := ThemeDB.fallback_font
	var ease_t := 1.0 - pow(1.0 - _t, 3.0)
	var size := get_viewport().get_visible_rect().size
	_root.draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.03, 0.66 * ease_t))
	var sc := lerpf(0.82, 1.0, ease_t)
	var off := Vector2(sin(_shake * 28.0) * 7.0 * _shake, 0.0)
	_root.draw_set_transform(wheel_center() + off, 0.0, Vector2(sc, sc))
	var ro := r_out()
	var ri := r_in()
	var n := MapCatalog.count()
	var half := TAU / float(n) * 0.5
	for i in n:
		var slot := MapCatalog.slot(i)
		var id: String = slot["id"]
		var unlocked := story.is_unlocked(id) and story.stage.has_scene(id)
		var here: bool = id == story.stage.current_id
		var ac := slot_angle(i)
		var pts := _arc_points(ro, ac - half + GAP, ac + half - GAP, 14)
		var inner := _arc_points(ri, ac + half - GAP, ac - half + GAP, 14)
		pts.append_array(inner)
		var fill := Color(0.075, 0.085, 0.13, 0.9)
		var edge := Color(ICE, 0.45)
		if not unlocked:
			fill = Color(0.035, 0.035, 0.05, 0.9)
			edge = Color(0.4, 0.42, 0.5, 0.25)
		if i == hover:
			fill = Color(0.2, 0.22, 0.34, 0.96) if unlocked else Color(0.09, 0.07, 0.09, 0.96)
			edge = Color(GOLD, 0.95) if unlocked else Color(0.75, 0.35, 0.35, 0.8)
		elif here:
			fill = Color(0.12, 0.13, 0.2, 0.92)
		_root.draw_colored_polygon(pts, fill)
		var loop := pts.duplicate()
		loop.append(pts[0])
		_root.draw_polyline(loop, edge, 3.0 if i == hover else 2.0, true)
		var mid := Vector2(sin(ac), -cos(ac)) * (ri + ro) * 0.5
		if unlocked:
			var label: String = slot["name"]
			var fs := 24
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			var at := mid + Vector2(-w * 0.5, fs * 0.35)
			_root.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, 6, Color(0, 0, 0, 0.9))
			_root.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, GOLD if i == hover else Color(0.9, 0.93, 1.0))
			if here:
				_root.draw_circle(Vector2(sin(ac), -cos(ac)) * (ri + 22.0), 6.0, GOLD)
		else:
			_draw_lock(mid + Vector2(0, -6))
			var q := "???"
			var qw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_CENTER, -1, 20).x
			_root.draw_string(font, mid + Vector2(-qw * 0.5, 34.0), q, HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(0.55, 0.57, 0.66, 0.8))
	# centro
	_root.draw_circle(Vector2.ZERO, ri - 10.0, Color(0.02, 0.025, 0.05, 0.93))
	_root.draw_arc(Vector2.ZERO, ri - 10.0, 0.0, TAU, 56, Color(ICE, 0.4), 2.0, true)
	var title := "MAPAS"
	var desc := "Toca un mapa para conjurar su portal"
	var state := "Toca aquí para cerrar"
	var tcol := GOLD
	if hover >= 0:
		var hs := MapCatalog.slot(hover)
		var hid: String = hs["id"]
		var hu := story.is_unlocked(hid) and story.stage.has_scene(hid)
		title = hs["title"] if (hu or hs["desc"] != "") else "???"
		desc = hs["desc"] if hu else ""
		if hid == story.stage.current_id:
			state = "Estás aquí"
		elif hu:
			state = "Suelta para viajar"
		elif story.stage.has_scene(hid):
			state = "Bloqueado: falta historia"
		else:
			state = "Aún no existe"
	if _msg_t > 0.0:
		state = _msg
		tcol = Color(1.0, 0.62, 0.55)
	var cw := ri * 1.6
	_draw_centered(font, title, -ri * 0.46, 20, tcol, cw, 2)
	if desc != "":
		_draw_centered(font, desc, -6.0, 14, Color(0.82, 0.86, 0.96, 0.92), cw, 3)
	_draw_centered(font, state, ri * 0.56, 15, Color(tcol, 0.9) if _msg_t > 0.0 else Color(ICE, 0.95), cw, 2)
	_root.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Texto centrado en x = 0 (multilínea, ancho `w`), con contorno oscuro para leerse sobre cualquier fondo.
func _draw_centered(font: Font, text: String, y: float, fs: int, col: Color, w: float, lines: int) -> void:
	var at := Vector2(-w * 0.5, y)
	_root.draw_multiline_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, lines, 5, Color(0, 0, 0, 0.9))
	_root.draw_multiline_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, lines, col)


## Candado simple: cuerpo y argolla.
func _draw_lock(c: Vector2) -> void:
	var col := Color(0.6, 0.62, 0.72, 0.85)
	_root.draw_arc(c + Vector2(0, -8), 9.0, PI, TAU, 14, col, 3.0, true)
	_root.draw_rect(Rect2(c + Vector2(-13, -8), Vector2(26, 20)), col)
	_root.draw_circle(c + Vector2(0, 1), 3.0, Color(0.05, 0.05, 0.08))

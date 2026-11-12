class_name TouchControls
extends CanvasLayer
## Controles táctiles para Android: joystick virtual a la izquierda,
## arrastre para cámara a la derecha y botones de acción.
## Dispara las mismas acciones del autoload Inputs, así el resto del juego
## no distingue entre teclado, mando o pantalla.

const STICK_RADIUS := 110.0
const DEADZONE := 0.15

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _buttons: Array[Dictionary] = []   # {action, rect, touch, label}
var _in_vehicle := false

var _draw_root: Control
# Modo plastilina: discos de piedra modelada con flechas y letras doradas (ui/clay/*.png).
var _clay := false
var _tex_disc: Texture2D
var _tex_dpad: Texture2D
var _tex_knob: Texture2D
var _stick_home := Vector2.ZERO
const GOLD := Color(0.96, 0.84, 0.56)
const GOLD_INK := Color(0.2, 0.12, 0.08)


func _ready() -> void:
	layer = 10
	_draw_root = Control.new()
	_draw_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_root.draw.connect(_on_draw)
	_clay = ClayStyle.enabled and ResourceLoader.exists("res://ui/clay/disc.png")
	if _clay:
		_tex_disc = load("res://ui/clay/disc.png")
		_tex_dpad = load("res://ui/clay/dpad.png")
		_tex_knob = load("res://ui/clay/knob.png")
	add_child(_draw_root)
	get_viewport().size_changed.connect(_layout)
	_layout()
	# En escritorio sin pantalla táctil se ocultan, salvo que se fuerce.
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
		or OS.get_environment("SPA_TOUCH") == "1"


func set_in_vehicle(v: bool) -> void:
	_in_vehicle = v
	_layout()


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var r := 70.0
	_buttons.clear()
	_stick_home = Vector2(180, s.y - 170)
	if _in_vehicle:
		_add_button("move_forward", Vector2(s.x - 110, s.y - 230), r, "GAS")
		_add_button("move_back", Vector2(s.x - 260, s.y - 120), r, "FRENO")
		_add_button("handbrake", Vector2(s.x - 110, s.y - 90), r * 0.8, "MANO")
		_add_button("horn", Vector2(s.x - 400, s.y - 90), r * 0.6, "PITO")
	else:
		_add_button("jump", Vector2(s.x - 110, s.y - 110), r, "SALTO")
		_add_button("sprint", Vector2(s.x - 250, s.y - 90), r * 0.8, "CORRER")
		_add_button("punch", Vector2(s.x - 250, s.y - 215), r * 0.75, "GOLPE")
		_add_button("crouch", Vector2(s.x - 395, s.y - 130), r * 0.65, "AGACHAR")
	_add_button("interact", Vector2(s.x - 110, s.y - 380), r * 0.75, "AUTO")
	_add_button("camera_toggle", Vector2(s.x - 70, 70), r * 0.5, "CAM")
	_draw_root.queue_redraw()


func _add_button(action: String, center: Vector2, radius: float, label: String) -> void:
	_buttons.append({"action": action, "center": center, "radius": radius, "touch": -1, "label": label})


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_press(t.index, t.position)
		else:
			_on_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			var v := (d.position - _stick_origin) / STICK_RADIUS
			_stick_vec = v.limit_length(1.0)
			_apply_stick()
		elif d.index == _look_touch:
			Inputs.touch_look += d.position - _look_last
			_look_last = d.position
		_draw_root.queue_redraw()


func _on_press(idx: int, pos: Vector2) -> void:
	for b in _buttons:
		if pos.distance_to(b.center) <= b.radius:
			b.touch = idx
			Input.action_press(b.action)
			_draw_root.queue_redraw()
			return
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if pos.x < half and _stick_touch == -1:
		_stick_touch = idx
		_stick_origin = pos
		# en plastilina la base es fija: si se toca cerca de ella, el centro es la base
		if _clay and pos.distance_to(_stick_home) < STICK_RADIUS * 1.6:
			_stick_origin = _stick_home
			_stick_vec = ((pos - _stick_home) / STICK_RADIUS).limit_length(1.0)
			_apply_stick()
			_draw_root.queue_redraw()
			return
		_stick_vec = Vector2.ZERO
	elif _look_touch == -1:
		_look_touch = idx
		_look_last = pos
	_draw_root.queue_redraw()


func _on_release(idx: int) -> void:
	for b in _buttons:
		if b.touch == idx:
			b.touch = -1
			Input.action_release(b.action)
	if idx == _stick_touch:
		_stick_touch = -1
		_stick_vec = Vector2.ZERO
		_apply_stick()
	if idx == _look_touch:
		_look_touch = -1
	_draw_root.queue_redraw()


func _apply_stick() -> void:
	var v := _stick_vec
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	# En auto el joystick solo dirige (izq/der); gas y freno son botones.
	var fwd := 0.0 if _in_vehicle else maxf(-v.y, 0.0)
	var back := 0.0 if _in_vehicle else maxf(v.y, 0.0)
	_set_strength("move_forward", fwd, true)
	_set_strength("move_back", back, true)
	_set_strength("move_left", maxf(-v.x, 0.0))
	_set_strength("move_right", maxf(v.x, 0.0))


func _set_strength(action: String, value: float, respect_button := false) -> void:
	if respect_button:
		for b in _buttons:
			if b.action == action and b.touch != -1:
				return
	if value > 0.0:
		Input.action_press(action, value)
	else:
		Input.action_release(action)


func _on_draw() -> void:
	if _clay:
		_draw_clay()
		return
	var font := ThemeDB.fallback_font
	var amber := Color(1.0, 0.72, 0.3)
	if _stick_touch != -1:
		_draw_root.draw_circle(_stick_origin, STICK_RADIUS, Color(0, 0, 0, 0.25))
		_draw_root.draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		_draw_root.draw_circle(_stick_origin + _stick_vec * STICK_RADIUS, 42, Color(amber, 0.7))
	else:
		var s := get_viewport().get_visible_rect().size
		var hint := Vector2(170, s.y - 170)
		_draw_root.draw_arc(hint, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.15), 2.0)
	for b in _buttons:
		var pressed: bool = b.touch != -1
		_draw_root.draw_circle(b.center, b.radius, Color(0.05, 0.08, 0.1, 0.55 if pressed else 0.35))
		_draw_root.draw_arc(b.center, b.radius, 0, TAU, 40, Color(amber, 0.9 if pressed else 0.5), 3.0)
		var fs := 18
		var w := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		_draw_root.draw_string(font, b.center + Vector2(-w * 0.5, fs * 0.35), b.label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.9))


func _draw_clay() -> void:
	var font := ThemeDB.fallback_font
	var base := _stick_origin if _stick_touch != -1 else _stick_home
	var br := STICK_RADIUS * 1.12
	_draw_root.draw_texture_rect(_tex_dpad, Rect2(base - Vector2(br, br), Vector2(br, br) * 2.0), false)
	var kr := STICK_RADIUS * 0.4
	var kp := base + _stick_vec * STICK_RADIUS * 0.45
	_draw_root.draw_texture_rect(_tex_knob, Rect2(kp - Vector2(kr, kr), Vector2(kr, kr) * 2.0), false)
	for b in _buttons:
		var pressed: bool = b.touch != -1
		var rr: float = b.radius * (0.94 if pressed else 1.0)
		var tint := Color(0.82, 0.78, 0.74) if pressed else Color.WHITE
		_draw_root.draw_texture_rect(_tex_disc, Rect2(b.center - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, tint)
		var fs := int(clampf(b.radius * 0.34, 14.0, 26.0))
		var w := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		var at: Vector2 = b.center + Vector2(-w * 0.5, fs * 0.36)
		_draw_root.draw_string_outline(font, at, b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, 5, Color(GOLD_INK, 0.85))
		_draw_root.draw_string(font, at, b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, GOLD)

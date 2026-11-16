class_name GameHUD
extends CanvasLayer
## HUD del viaje: título de la escena, subtítulos telepáticos con efecto de máquina de escribir,
## aviso del botón PUERTA y contador de FPS. Sin velocímetro: ya no hay autos en el juego.

var player: Node3D
var _title: Label
var _caption: Label
var _prompt: Label
var _fps: Label
var _cap_tween: Tween
var _title_tween: Tween


func _ready() -> void:
	layer = 5
	_title = _make_label(Vector2(24, 18), 22, Color(0.82, 0.86, 1.0))
	_title.modulate.a = 0.0
	_fps = _make_label(Vector2(24, 100), 14, Color(1, 1, 1, 0.45))

	_caption = _make_label(Vector2.ZERO, 24, Color(0.93, 0.95, 1.0))
	_caption.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.anchor_left = 0.12
	_caption.anchor_right = 0.88
	_caption.offset_left = 0.0
	_caption.offset_right = 0.0
	_caption.offset_top = -250.0
	_caption.offset_bottom = -150.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.visible_ratio = 0.0

	_prompt = _make_label(Vector2.ZERO, 20, Color(0.96, 0.84, 0.56))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.anchor_left = 0.2
	_prompt.anchor_right = 0.8
	_prompt.offset_left = 0.0
	_prompt.offset_right = 0.0
	_prompt.offset_top = -120.0
	_prompt.offset_bottom = -80.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false


func _make_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(_delta: float) -> void:
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	_prompt.modulate.a = 0.0 if UiLock.blocked else 1.0         # con la rueda de mapas abierta el aviso estorba


## Muestra el nombre de la escena y lo desvanece.
func show_title(text: String) -> void:
	_title.text = text
	if _title_tween:
		_title_tween.kill()
	_title.modulate.a = 0.0
	_title_tween = create_tween()
	_title_tween.tween_property(_title, "modulate:a", 1.0, 0.8)
	_title_tween.tween_interval(3.2)
	_title_tween.tween_property(_title, "modulate:a", 0.0, 1.6)


## Subtítulo telepático: aparece letra a letra. Devuelve la duración total en segundos.
func say(text: String) -> float:
	if _cap_tween:
		_cap_tween.kill()
	_caption.text = text
	_caption.visible_ratio = 0.0
	_caption.modulate.a = 1.0
	var type_time := clampf(float(text.length()) * 0.035, 0.6, 3.5)
	_cap_tween = create_tween()
	_cap_tween.tween_property(_caption, "visible_ratio", 1.0, type_time)
	return type_time


func fade_caption(duration := 1.0) -> void:
	if _cap_tween:
		_cap_tween.kill()
	_cap_tween = create_tween()
	_cap_tween.tween_property(_caption, "modulate:a", 0.0, duration)


func caption_text() -> String:
	return _caption.text


func set_prompt(text: String) -> void:
	_prompt.visible = text != ""
	_prompt.text = text

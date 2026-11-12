class_name GameHUD
extends CanvasLayer
## HUD mínimo: zona actual, velocímetro en auto y aviso para entrar a vehículos.

var player: Node3D
var _zone: Label
var _speed: Label
var _prompt: Label
var _fps: Label


func _ready() -> void:
	layer = 5
	_zone = _make_label(Vector2(24, 18), 22, Color(0.96, 0.84, 0.56) if ClayStyle.enabled else Color(1.0, 0.75, 0.35))
	_zone.text = "BOSTON · LA CANDELARIA · MEDELLÍN"
	_speed = _make_label(Vector2(24, 52), 34, Color(0.6, 0.95, 1.0))
	_prompt = _make_label(Vector2(0, 0), 22, Color(1, 1, 1))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-180, -150)
	_prompt.size = Vector2(360, 40)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps = _make_label(Vector2(24, 100), 14, Color(1, 1, 1, 0.5))


func _make_label(pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l


func _process(_delta: float) -> void:
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if player == null or not is_instance_valid(player):
		return
	var veh = player.get("current_vehicle")
	if veh != null and is_instance_valid(veh):
		_speed.visible = true
		_speed.text = "%3d km/h" % int(veh.get_speed_kmh())
		_prompt.text = "AUTO / F — bajarse"
		_prompt.visible = true
	else:
		_speed.visible = false
		var near := _nearest_free_vehicle()
		_prompt.visible = near != null
		_prompt.text = "AUTO / F — subirse"


func _nearest_free_vehicle() -> Node3D:
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.has_method("get_entry_point") and not v.is_occupied():
			if player.global_position.distance_to(v.get_entry_point()) <= 3.5:
				return v
	return null

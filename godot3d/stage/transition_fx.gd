class_name TransitionFX
extends CanvasLayer
## Efecto de viaje entre escenas: remolino de galaxia que cubre la pantalla y se abre en la escena nueva.
## Uso: await fx.cover(); ...cambiar escena...; await fx.uncover()

const SHADER := preload("res://stage/shaders/transition.gdshader")

var _rect: ColorRect
var _mat: ShaderMaterial
var _tween: Tween
var amount := 0.0


func _ready() -> void:
	layer = 50
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	add_child(_rect)
	_set_amount(0.0)


func _set_amount(a: float) -> void:
	amount = a
	_rect.visible = a > 0.001
	_mat.set_shader_parameter("amount", a)


## Cubre la pantalla; termina cuando ya está totalmente cubierta.
func cover(duration := 1.1) -> void:
	await _run(1.0, duration, Tween.EASE_IN)


## Abre la pantalla (la escena nueva ya está puesta).
func uncover(duration := 1.1) -> void:
	await _run(0.0, duration, Tween.EASE_OUT)


func _run(to: float, duration: float, ease_type: Tween.EaseType) -> void:
	if _tween:
		_tween.kill()
	if duration <= 0.0:
		_set_amount(to)
		return
	_tween = create_tween()
	_tween.tween_method(_set_amount, amount, to, duration).set_trans(Tween.TRANS_CUBIC).set_ease(ease_type)
	await _tween.finished

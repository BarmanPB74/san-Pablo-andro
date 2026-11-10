class_name PostFX
extends CanvasLayer
## Post-proceso de pantalla completa (viñeta, grano, aberración cromática).
## Capa 1: queda por debajo del HUD (5) y los controles táctiles (10).
## `enabled = false` lo quita del todo (ahorra una copia de pantalla + 1 pasada).

const SHADER := "res://look/post_fx.gdshader"

@export var enabled := true:
	set = set_enabled

var rect: ColorRect
var mat: ShaderMaterial


func _ready() -> void:
	layer = 1
	mat = ShaderMaterial.new()
	mat.shader = load(SHADER)
	rect = ColorRect.new()
	rect.name = "PostFXRect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	add_child(rect)
	set_enabled(enabled)


func set_enabled(v: bool) -> void:
	enabled = v
	visible = v
	if rect:
		rect.visible = v


## Ajuste fino por preset. Valores típicos: vignette 0.3–0.5, grain 0.02–0.05,
## aberration 0.001–0.004.
func set_params(vignette: float, grain: float, aberration: float,
		vignette_color := Color(0.0, 0.015, 0.02)) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("vignette_strength", vignette)
	mat.set_shader_parameter("grain_amount", grain)
	mat.set_shader_parameter("aberration", aberration)
	mat.set_shader_parameter("vignette_color", vignette_color)


## Estilo ilustrado "tinta y papel". ink = contornos (0–1), paper = duotono tinta/papel (0–1).
func set_ink(ink: float, paper: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("ink_amount", ink)
	mat.set_shader_parameter("paper_amount", paper)

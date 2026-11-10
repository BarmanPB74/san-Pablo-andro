extends Node
## Autoload "Inputs": registra todas las acciones de entrada por código,
## así no dependemos de editar el Input Map a mano desde el teléfono.
## Los controles táctiles (ui/touch_controls) disparan estas mismas acciones.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],          # a pie: saltar
	"handbrake": [KEY_SPACE],     # en auto: freno de mano
	"interact": [KEY_F, KEY_E],   # entrar / salir de vehículos
	"camera_toggle": [KEY_C],     # alternar distancia de cámara
	"horn": [KEY_H],
	"crouch": [KEY_CTRL, KEY_X],  # a pie: agacharse (alterna)
	"punch": [KEY_J, KEY_Q],      # a pie: golpear (combo de 3)
}

const PAD_BUTTONS := {
	"jump": JOY_BUTTON_A,
	"handbrake": JOY_BUTTON_A,
	"interact": JOY_BUTTON_Y,
	"sprint": JOY_BUTTON_LEFT_STICK,
	"camera_toggle": JOY_BUTTON_RIGHT_STICK,
	"horn": JOY_BUTTON_LEFT_SHOULDER,
	"crouch": JOY_BUTTON_B,
	"punch": JOY_BUTTON_X,
}

## Vector de cámara inyectado por el HUD táctil (arrastre con el dedo).
var touch_look := Vector2.ZERO


func _ready() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		if PAD_BUTTONS.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = PAD_BUTTONS[action]
			InputMap.action_add_event(action, jb)
	_add_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)


func _add_axis(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


## Vector de movimiento normalizado: x = derecha, y = adelante.
func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_back", "move_forward")


## Consume el delta de cámara táctil acumulado este frame.
func take_touch_look() -> Vector2:
	var v := touch_look
	touch_look = Vector2.ZERO
	return v

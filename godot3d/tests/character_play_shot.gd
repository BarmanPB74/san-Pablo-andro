extends "res://tests/character_test_scene.gd"
## Escena para capturas "en juego": usa la escena de prueba y simula entrada.
## CHAR_ACTION = idle | run | sprint | turn | vehicle   (por variable de entorno)

var _t := 0.0
var _action := "run"


func _ready() -> void:
	super._ready()
	_action = OS.get_environment("CHAR_ACTION")
	if _action == "":
		_action = "run"
	player.global_position = Vector3(30, 0.05, 40)
	if _action == "vehicle" and vehicle:
		player.global_position = vehicle.get_entry_point() + Vector3(1.5, 0.1, 1.0)


func _physics_process(delta: float) -> void:
	_t += delta
	match _action:
		"run":
			Input.action_press("move_forward")
		"sprint":
			Input.action_press("move_forward")
			Input.action_press("sprint")
		"turn":
			Input.action_press("move_forward")
			Input.action_press("sprint")
			if _t > 1.6:
				Input.action_press("move_left")
		"stairs":
			if _t < 0.1:
				player.global_position = Vector3(0, 0.05, -10)
			Input.action_press("move_forward")
		"vehicle":
			if is_equal_approx(snappedf(_t, 1.0 / 60.0), 0.5):
				Input.action_press("interact")
			elif _t > 0.55:
				Input.action_release("interact")
			if _t > 2.2 and _t < 3.2:
				Input.action_press("move_forward")
			else:
				Input.action_release("move_forward")

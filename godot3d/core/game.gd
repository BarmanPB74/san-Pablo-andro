extends Node3D
## Escena principal: Andro flota por el Umbral y viaja por sus recuerdos a través de puertas-portal.
## Ensambla Stage (escenarios), AndroCloak vía Player, cámara, HUD y controles táctiles.
## Se cargan por ruta (load) para que la escena no se rompa si un módulo falta.

@export var start_scene := "umbral"

var stage: Stage
var fx: TransitionFX
var camera_rig: Node3D
var player: Node3D
var touch: TouchControls
var hud: GameHUD
var story: Node
var wheel: MapWheel


func _ready() -> void:
	ClayStyle.enabled = false        # el estilo plastilina queda fuera: ahora la tela y la galaxia mandan
	camera_rig = _new_from("res://character/camera_rig.gd")
	camera_rig.name = "CameraRig"
	add_child(camera_rig)

	_spawn_player()

	fx = TransitionFX.new()
	add_child(fx)
	stage = Stage.new()
	stage.name = "Stage"
	add_child(stage)
	stage.setup(player, camera_rig, fx)

	hud = GameHUD.new()
	hud.player = player
	add_child(hud)
	touch = TouchControls.new()
	add_child(touch)

	if ResourceLoader.exists("res://story/story.gd"):
		story = _new_from("res://story/story.gd")
		story.name = "Story"
		add_child(story)
		story.call("setup", stage, player, hud, start_scene)
		wheel = MapWheel.new()
		wheel.name = "MapWheel"
		add_child(wheel)
		wheel.setup(story as Story)
		wheel.opened.connect(touch.cancel_all)
	else:
		stage.go(start_scene)


func _new_from(path: String) -> Node:
	if not ResourceLoader.exists(path):
		push_warning("Módulo no encontrado: " + path)
		return null
	var res = load(path)
	if res is PackedScene:
		return res.instantiate()
	return res.new()


func _spawn_player() -> void:
	if ResourceLoader.exists("res://character/player.tscn"):
		player = load("res://character/player.tscn").instantiate()
	else:
		player = _new_from("res://character/player.gd")
	if player == null:
		return
	player.name = "Player"
	player.position = Vector3(0, 0.2, 6)
	add_child(player)
	camera_rig.call("follow", player.get_camera_anchor(), "on_foot")

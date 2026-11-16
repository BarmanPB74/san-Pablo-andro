class_name Stage
extends Node3D
## Director de escenarios: guarda la escena activa y hace los viajes entre ellas con el remolino.
## El jugador y la cámara viven fuera (en Game) y se reubican en cada viaje.

signal scene_entered(id: String)
signal scene_leaving(id: String)
signal travel_started(target: String)

const SCENES := {
	"umbral": "res://stage/scenes/hub_scene.gd",
	"planetas": "res://stage/scenes/planets_scene.gd",
	"fuente": "res://stage/scenes/fountain_scene.gd",
	"anillos": "res://stage/scenes/rings_scene.gd",
	"cubo": "res://stage/scenes/cube_scene.gd",
}

var player: Node3D
var camera_rig: Node3D
var fx: TransitionFX
var current: StageScene
var current_id := ""
var busy := false
## Si es true los viajes son instantáneos (pruebas).
var instant := false


func setup(p_player: Node3D, p_camera_rig: Node3D, p_fx: TransitionFX) -> void:
	player = p_player
	camera_rig = p_camera_rig
	fx = p_fx


func has_scene(id: String) -> bool:
	return SCENES.has(id)


## Entra a una escena. Si ya hay una, hace el viaje con el remolino. Devuelve cuando terminó.
func go(id: String) -> void:
	if busy or not SCENES.has(id):
		return
	busy = true
	travel_started.emit(id)
	var had_previous := current != null
	if had_previous:
		scene_leaving.emit(current_id)
		if fx and not instant:
			await fx.cover()
	_swap(id)
	await get_tree().physics_frame      # que el piso nuevo ya exista antes de apoyar a Andro
	await get_tree().physics_frame
	_place_player()
	if fx and not instant and had_previous:
		await fx.uncover()
	busy = false
	scene_entered.emit(id)


func _swap(id: String) -> void:
	if current != null:
		current.queue_free()
		remove_child(current)
		current = null
	var script: GDScript = load(SCENES[id])
	var sc: StageScene = script.new()
	sc.id = id
	current = sc
	current_id = id
	add_child(sc)
	sc.portal_entered.connect(_on_portal_entered)


func _place_player() -> void:
	if player == null or current == null:
		return
	if player.has_method("teleport"):
		player.call("teleport", current.global_transform * current.spawn_pos, current.spawn_yaw)
	else:
		player.global_position = current.spawn_pos
	if camera_rig and camera_rig.has_method("snap_behind"):
		camera_rig.call("snap_behind", current.spawn_yaw, current.spawn_pitch)


func _on_portal_entered(target: String) -> void:
	go(target)


func _process(delta: float) -> void:
	if current != null and player != null and is_instance_valid(player):
		current.tick(delta, player)

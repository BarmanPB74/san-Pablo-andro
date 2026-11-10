extends Node3D
## Escena principal: ensambla los módulos de cada agente según CONTRACT.md.
## Se cargan por ruta (load) para que la escena no se rompa si un módulo falta.

@export var time_of_day := "overcast_day"   # overcast_day | golden_hour | rainy_night

var look: Node
var district: Node3D
var camera_rig: Node3D
var player: Node3D
var touch: TouchControls
var hud: GameHUD


func _ready() -> void:
	look = _new_from("res://look/second_son_environment.gd")
	if look:
		look.name = "StreetLook"
		add_child(look)
		if look.has_method("set_time_of_day"):
			look.set_time_of_day(time_of_day)

	district = _new_from("res://world/boston_district.gd")
	if district:
		district.name = "BostonDistrict"
		add_child(district)

	camera_rig = _new_from("res://character/camera_rig.gd")
	if camera_rig:
		camera_rig.name = "CameraRig"
		add_child(camera_rig)

	_spawn_vehicles()
	_spawn_player()

	hud = GameHUD.new()
	hud.player = player
	add_child(hud)
	touch = TouchControls.new()
	add_child(touch)


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
	# El transform se asigna ANTES de add_child: Player lee su orientación en _ready().
	var spawns := get_tree().get_nodes_in_group("spawn_player")
	if spawns.size() > 0:
		player.transform = (spawns[0] as Node3D).global_transform
	else:
		player.position = Vector3(0, 2, 8)
	add_child(player)


func _spawn_vehicles() -> void:
	if not ResourceLoader.exists("res://vehicles/vehicle_factory.gd"):
		return
	var factory = load("res://vehicles/vehicle_factory.gd")
	for m in get_tree().get_nodes_in_group("spawn_vehicle"):
		var kind: String = m.get_meta("kind", "sedan")
		var v: Node = factory.spawn(kind, (m as Node3D).global_transform, self)
		if v and v.has_signal("driver_entered"):
			v.driver_entered.connect(func(_d): touch.set_in_vehicle(true))
			v.driver_exited.connect(func(_d): touch.set_in_vehicle(false))
	# De noche los autos prenden faros y luces de posición.
	var vclass = load("res://vehicles/vehicle.gd")
	if time_of_day == "rainy_night":
		vclass.set_night(true, get_tree())

class_name HouseScene
extends StageScene
## La Casa: el recuerdo de cuando Andro era un niño humano. No tiene exterior: se llega por un portal y es un palacio
## gótico sobrio, gris y en sombras, repartido en diez cuartos enormes (ver HouseRooms). Solo existe UN cuarto a la vez:
## al cruzar el velo de bruma de una puerta se funde a gris, se libera el cuarto viejo, se construye el vecino y se
## reaparece en su puerta. Así el costo es el de un solo cuarto sin importar cuán grande sea la casa.
## Sin cielo, sol ni sombras: ambiente gris frío, niebla oscura, velas (Omni sin sombra) y un tono de color apagado.

signal room_changed(room_id: String, room_title: String)

const MIN_CEILING := HouseRooms.MIN_CEILING
const FLY_HEADROOM := 2.2                  # holgura bajo el techo al volar (m)

var room_id := ""
var room: HouseBuilder
var _swapping := false
var _cooldown := 0.0
var _player: Node3D
var _fade: ColorRect


func _init() -> void:
	title = "La Casa"
	spawn_pos = HouseRooms.SPAWN_POS
	spawn_yaw = HouseRooms.SPAWN_YAW
	spawn_pitch = -0.1
	portal_distance = 5.0
	portal_size = Vector2(2.4, 3.6)         # con el marco mide ~4.6 m: cabe bajo el techo más bajo (6.5 m)


func build() -> void:
	_make_environment()
	var layer := CanvasLayer.new()
	layer.name = "MemoryFade"
	layer.layer = 40
	_fade = ColorRect.new()
	_fade.color = Color(0.035, 0.035, 0.045, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	layer.add_child(_fade)
	add_child(layer)
	load_room(HouseRooms.START)


## Los portales viven dentro del cuarto actual: se liberan con él.
func portal_parent() -> Node:
	return room.node if room != null else self


func _make_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.012, 0.016)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.44, 0.45, 0.52)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.045, 0.045, 0.058)
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.72          # recuerdo: casi sin color
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


# ------------------------------------------------------------------ cuartos

## Libera el cuarto actual (si hay) y construye `id`. `from_id` solo se usa para el aviso.
func load_room(id: String, _from_id := "") -> void:
	if room != null:
		portals.clear()
		remove_child(room.node)
		room.node.queue_free()
		room = null
	room_id = id
	room = HouseRooms.make(id)
	add_child(room.node)
	room_changed.emit(id, HouseRooms.DEFS[id]["title"])


func tick(delta: float, player: Node3D) -> void:
	_player = player
	if room != null and "fly_ceiling" in player:
		# Techo de vuelo = altura de la sala menos lo que mide Andro (el origen está en los pies)
		var dim: Vector3 = HouseRooms.DEFS[room_id]["dim"]
		player.set("fly_ceiling", dim.y - FLY_HEADROOM)
	if _swapping or room == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0:
		return
	var door := door_crossed(player.global_position)
	if not door.is_empty():
		_go_room(door["to"], room_id)


## Puerta del cuarto actual que `pos` está cruzando (o {}): dentro del hueco y pegado al velo.
func door_crossed(pos: Vector3) -> Dictionary:
	if room == null:
		return {}
	var p := to_local(pos)
	for dd in room.doors:
		var side: String = dd["side"]
		var fr := HouseBuilder.frame_for(room.dim, side)
		var local := fr.affine_inverse() * p
		var lx := HouseBuilder.local_x_for(side, float(dd["at"]))
		if absf(local.x - lx) < HouseBuilder.DOOR_W * 0.5 and local.z < 0.55 and local.z > -HouseBuilder.T and local.y < 4.6:
			return dd
	return {}


func _go_room(to: String, from: String) -> void:
	_swapping = true
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	await tw.finished
	load_room(to, from)
	var arr := HouseRooms.arrival(to, from)
	if _player != null and is_instance_valid(_player):
		if _player.has_method("teleport"):
			_player.call("teleport", arr["pos"], arr["yaw"])
		var rig := get_tree().get_first_node_in_group("camera_rig")
		if rig != null and rig.has_method("snap_behind"):
			rig.call("snap_behind", arr["yaw"], spawn_pitch)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.5)
	await tw2.finished
	_fade.visible = false
	_cooldown = 0.6
	_swapping = false

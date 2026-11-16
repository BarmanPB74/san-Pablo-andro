extends SceneTree
## Prueba de La Casa (palacio de recuerdo, sin exterior, un cuarto cargado a la vez). Para cada cuarto:
## que se construya, que sus puertas tengan retorno, que quepa el portal bajo el techo, que cada cuarto tenga ≤ 5 luces
## y que con la MISMA cápsula de Andro (radio 0.66, alto 1.86) se llegue caminando a todas sus puertas sin escapar del cuarto.
## También prueba el cruce real de una puerta: se libera el cuarto viejo y Andro aparece en la puerta del vecino.
## Uso: godot --headless --fixed-fps 60 --path . -s res://tests/house_test.gd

const STEP := 0.3
const MAX_ROOM_LIGHTS := 5                 # el móvil admite 8 por objeto; portal (1) y luz de Andro (1) suman 2 → ≤ 6, con margen

var fails := 0
var space: PhysicsDirectSpaceState3D
var shape := CapsuleShape3D.new()
var stage: Stage
var story: Story
var player: Player
var house: HouseScene


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func free_at(x: float, z: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, 0.06 + Player.CAPSULE_H * 0.5, z))
	q.collision_mask = 1
	return space.intersect_shape(q, 1).is_empty()


## BFS de la cápsula en el cuarto actual desde `start`; devuelve {seen, out} (out = casillas fuera del cuarto).
func flood(start: Vector2, dim: Vector3) -> Dictionary:
	var x0 := -dim.x * 0.5 - 1.5
	var z0 := -dim.z * 0.5 - 1.5
	var nx := roundi((dim.x + 3.0) / STEP)
	var nz := roundi((dim.z + 3.0) / STEP)
	var s := Vector2i(roundi((start.x - x0) / STEP), roundi((start.y - z0) / STEP))
	var seen := {s: true}
	var queue: Array[Vector2i] = [s]
	var head := 0
	var out := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x > nx or n.y > nz or seen.has(n):
				continue
			var wx := x0 + float(n.x) * STEP
			var wz := z0 + float(n.y) * STEP
			if free_at(wx, wz):
				seen[n] = true
				queue.append(n)
				if absf(wx) > dim.x * 0.5 + 0.05 or absf(wz) > dim.z * 0.5 + 0.05:
					out += 1
	return {"seen": seen, "x0": x0, "z0": z0, "out": out}


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", "casa")
	root.add_child(main)
	await frames(60)
	stage = main.get("stage")
	story = main.get("story")
	stage.instant = true
	check(stage.current_id == "casa", "el juego arranca en La Casa (%s)" % stage.current.title)
	house = stage.current as HouseScene
	player = get_nodes_in_group("player")[0]
	space = root.get_world_3d().direct_space_state
	shape.radius = Player.CAPSULE_RADIUS
	shape.height = Player.CAPSULE_H
	check(house.room_id == HouseRooms.START, "empieza en el vestíbulo y solo hay un cuarto cargado")
	check(house.env != null and house.sun == null, "ambiente propio sin sol (no hay exterior)")
	check(player.is_on_floor(), "Andro aparece apoyado en el piso (y=%.2f)" % player.global_position.y)

	# --- el grafo de cuartos: cada puerta tiene retorno y todos los cuartos son alcanzables desde el vestíbulo
	var reach := {HouseRooms.START: true}
	var frontier := [HouseRooms.START]
	while not frontier.is_empty():
		var cur: String = frontier.pop_back()
		for dd in HouseRooms.DEFS[cur]["doors"]:
			var to: String = dd["to"]
			var back := false
			for d2 in HouseRooms.DEFS[to]["doors"]:
				if d2["to"] == cur:
					back = true
			check(back, "  %s → %s tiene puerta de regreso" % [cur, to])
			if not reach.has(to):
				reach[to] = true
				frontier.append(to)
	check(reach.size() == HouseRooms.DEFS.size(), "los %d cuartos están conectados (%d alcanzables)" % [HouseRooms.DEFS.size(), reach.size()])

	# --- cada cuarto, cargado de uno en uno
	for id in HouseRooms.ids():
		var def: Dictionary = HouseRooms.DEFS[id]
		var dim: Vector3 = def["dim"]
		print("[ %s %s ]" % [id, str(dim)])
		var first_from: String = def["doors"][0]["to"]
		var first := HouseRooms.arrival(id, first_from)
		player.call("teleport", first["pos"], first["yaw"])        # Andro entra por la primera puerta (si no, el cuarto nuevo lo vería junto al velo)
		house.load_room(id)
		await frames(3)
		var b := house.room
		check(get_node_count_of(house, "Room_") == 1, "  solo existe el cuarto %s" % id)
		check(dim.y >= HouseRooms.MIN_CEILING and dim.y >= HouseBuilder.DOOR_APEX + 1.5, "  techo %.1f m ≥ %.1f (cabe el arco y un portal)" % [dim.y, HouseRooms.MIN_CEILING])
		check(b.light_count <= MAX_ROOM_LIGHTS, "  %d luces (máx %d)" % [b.light_count, MAX_ROOM_LIGHTS])
		var starts: Array[Vector2] = []
		for dd in def["doors"]:
			var a := HouseRooms.arrival(id, dd["to"])
			starts.append(Vector2(a["pos"].x, a["pos"].z))
		if id == HouseRooms.START:
			starts.append(Vector2(HouseRooms.SPAWN_POS.x, HouseRooms.SPAWN_POS.z))
		for st in starts:
			check(free_at(st.x, st.y), "  el punto de llegada %s está libre" % str(st))
		var fl := flood(starts[0], dim)
		var seen: Dictionary = fl["seen"]
		check(seen.size() > 40, "  Andro recorre %d casillas de %.1f m" % [seen.size(), STEP])
		check(int(fl["out"]) == 0, "  no puede salir del cuarto (casillas fuera: %d)" % int(fl["out"]))
		for st in starts:
			var c := Vector2i(roundi((st.x - float(fl["x0"])) / STEP), roundi((st.y - float(fl["z0"])) / STEP))
			check(seen.has(c), "  desde la primera llegada se alcanza %s" % str(st))
		# ¿cabe por el hueco de cada puerta y se detecta el cruce?
		for dd in def["doors"]:
			var side: String = dd["side"]
			var fr := HouseBuilder.frame_for(dim, side)
			var lx := HouseBuilder.local_x_for(side, float(dd["at"]))
			var at_gate: Vector3 = fr * Vector3(lx, 0.1, 0.45)
			var in_room: Vector3 = fr * Vector3(lx, 0.1, 1.2)
			check(free_at(at_gate.x, at_gate.z), "  Andro cabe por el hueco de la puerta a %s" % dd["to"])
			check(house.door_crossed(in_room).is_empty(), "  a 1.2 m de la puerta aún no cruza")
			check(house.door_crossed(at_gate).get("to", "") == dd["to"], "  pegado al velo cruza hacia %s" % dd["to"])
		# el portal de Andro cabe en este cuarto, a la vista y no dentro de un mueble
		if id in ["vestibulo", "sala", "galeria", "hab1"]:
			var a0 := HouseRooms.arrival(id, def["doors"][0]["to"]) if id != HouseRooms.START else {"pos": HouseRooms.SPAWN_POS, "yaw": HouseRooms.SPAWN_YAW}
			story.skip()
			for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
				player.call("teleport", a0["pos"], yaw)
				await frames(8)
				Input.action_press("interact")
				await frames(3)
				Input.action_release("interact")
				await frames(3)
				var ps: Array = house.portals
				if ps.size() != 1:
					check(false, "  se conjura un portal mirando %.1f (n=%d, can=%s, door=%s, busy=%s)" % [yaw, ps.size(), str(story.can_conjure), str(story._door), str(stage.busy)])
					continue
				var p: Portal = ps[0]
				var d := Vector2(p.global_position.x - player.global_position.x, p.global_position.z - player.global_position.z).length()
				var rq := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 1.0, 0), p.global_position + Vector3(0, 1.0, 0), 1)
				var blocked := not root.get_world_3d().direct_space_state.intersect_ray(rq).is_empty()
				check(d >= 1.35 and d <= house.portal_distance + 0.05 and not blocked, "  portal a %.1f m, a la vista (mira %.1f)" % [d, yaw])
				house.clear_portals()
				story._door = null
				await frames(50)

	# --- cruce real: del vestíbulo a la sala por el velo
	house.load_room("vestibulo")
	await frames(3)
	var go := HouseBuilder.frame_for(HouseRooms.DEFS["vestibulo"]["dim"], "N") * Vector3(0, 0.1, 0.4)
	player.call("teleport", go, PI)
	var before := get_node_count_of(house, "Room_")
	await house._go_room("sala", "vestibulo")
	check(house.room_id == "sala" and get_node_count_of(house, "Room_") == 1 and before == 1, "al cruzar el velo se libera el vestíbulo y carga la sala")
	var arr := HouseRooms.arrival("sala", "vestibulo")
	check(player.global_position.distance_to(arr["pos"]) < 0.8, "Andro reaparece en la puerta de la sala (%s)" % str(player.global_position))

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(fails)


func get_node_count_of(parent: Node, prefix: String) -> int:
	var n := 0
	for c in parent.get_children():
		if (c as Node).name.begins_with(prefix):
			n += 1
	return n

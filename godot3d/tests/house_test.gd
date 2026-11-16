extends SceneTree
## Prueba de la casa: con la MISMA cápsula de colisión de Andro (radio 0.66, alto 1.86) recorre el lote en una
## rejilla y comprueba que Andro llega a cada cuarto y al patio por las puertas, y que no puede salir del lote.
## También mide cuántas luces ve cada malla (el móvil admite 8 por objeto) y que el portal cabe en cualquier cuarto.
## Uso: godot --headless --fixed-fps 60 --path . -s res://tests/house_test.gd

const STEP := 0.3
const X0 := -23.0
const X1 := 23.0
const Z0 := -15.0
const Z1 := 37.0
## El móvil admite 8 luces por objeto; el portal (1) y la luz de Andro (1) también cuentan, así que las de la casa deben ser ≤ 6.
const MAX_LIGHTS_PER_MESH := 6

var fails := 0
var space: PhysicsDirectSpaceState3D
var shape := CapsuleShape3D.new()
var stage: Stage
var story: Story
var player: Player


func check(cond: bool, msg: String) -> void:
	print(("  OK   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## ¿Cabe Andro (cápsula de colisión) con los pies a ras del piso en (x, z)?
func free_at(x: float, z: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, 0.06 + Player.CAPSULE_H * 0.5, z))
	q.collision_mask = 1
	return space.intersect_shape(q, 1).is_empty()


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(roundi((p.x - X0) / STEP), roundi((p.y - Z0) / STEP))


func world_of(c: Vector2i) -> Vector2:
	return Vector2(X0 + float(c.x) * STEP, Z0 + float(c.y) * STEP)


## Casillas a las que llega Andro caminando desde `start` (BFS en 4 direcciones).
func flood(start: Vector2) -> Dictionary:
	var seen := {}
	var s := cell_of(start)
	seen[s] = true
	var queue: Array[Vector2i] = [s]
	var head := 0
	var nx := roundi((X1 - X0) / STEP)
	var nz := roundi((Z1 - Z0) / STEP)
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x > nx or n.y > nz or seen.has(n):
				continue
			var w := world_of(n)
			if free_at(w.x, w.y):
				seen[n] = true
				queue.append(n)
	return seen


func _initialize() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	main.set("start_scene", "casa")
	root.add_child(main)
	await frames(60)
	stage = main.get("stage")
	story = main.get("story")
	stage.instant = true
	check(stage.current_id == "casa", "el juego arranca en La Casa (%s)" % stage.current.title)
	player = get_nodes_in_group("player")[0]
	check(player.is_on_floor(), "Andro aparece apoyado en el piso (y=%.2f)" % player.global_position.y)
	space = root.get_world_3d().direct_space_state
	shape.radius = Player.CAPSULE_RADIUS
	shape.height = Player.CAPSULE_H

	# --- sanidad de la prueba: el espacio libre es libre y un muro no lo es
	var sp := Vector2(player.global_position.x, player.global_position.z)
	check(free_at(sp.x, sp.y), "el punto de aparición está libre (no nace dentro de un mueble)")
	check(not free_at(-7.2, -5.0), "una división entre habitaciones bloquea a Andro")

	# --- pasos estrechos: el centro de cada puerta y abertura debe dejar pasar la cápsula
	var doors := {
		"puerta hab1": Vector2(-9.6, -2.2), "puerta hab2": Vector2(-4.8, -2.2), "puerta baño": Vector2(0.0, -2.2),
		"puerta hab3": Vector2(4.8, -2.2), "puerta hab4": Vector2(9.6, -2.2),
		"pasillo→sala": Vector2(-7.0, 0.8), "pasillo→comedor": Vector2(2.0, 0.8), "pasillo→cocina": Vector2(9.0, 0.8),
		"sala→comedor": Vector2(-2.0, 4.4), "comedor→cocina": Vector2(6.0, 4.4),
		"entrada": Vector2(-9.0, 8.0), "puerta grande al patio": Vector2(2.0, 8.0),
	}
	for k in doors:
		var d: Vector2 = doors[k]
		check(free_at(d.x, d.y), "Andro cabe por la %s" % k)

	# --- conectividad: desde la sala a todos los cuartos y al patio, y nunca fuera del lote
	var seen := flood(sp)
	check(seen.size() > 3000, "Andro recorre %d casillas de %.1f m" % [seen.size(), STEP])
	var targets := {
		"sala": Vector2(-6.5, 3.0), "comedor": Vector2(2.0, 6.7), "cocina": Vector2(9.0, 3.0), "pasillo": Vector2(0.0, -0.7),
		"habitación 1": Vector2(-9.6, -3.8), "habitación 2": Vector2(-4.8, -3.8), "baño": Vector2(0.0, -4.0),
		"habitación 3": Vector2(4.8, -3.8), "habitación 4": Vector2(9.6, -3.8),
		"terraza": Vector2(0.0, 10.5), "patio (centro)": Vector2(0.0, 26.0), "patio (esquina)": Vector2(18.0, 32.0),
		"patio (junto a la casa, este)": Vector2(17.0, 4.0), "patio (detrás de la casa)": Vector2(-17.0, -10.0),
	}
	for k in targets:
		var t: Vector2 = targets[k]
		check(free_at(t.x, t.y), "  hay espacio libre en la %s" % k)
		check(seen.has(cell_of(t)), "  Andro llega a la %s" % k)
	var out := 0
	for c in seen:
		var w := world_of(c)
		if absf(w.x) > 22.0 or w.y < -14.0 or w.y > 36.0:
			out += 1
	check(out == 0, "Andro no puede salir del lote (casillas fuera: %d)" % out)

	# --- luces: cada malla de la casa ve a lo sumo 8 luces (límite por objeto del móvil)
	var lights: Array[OmniLight3D] = []
	for n in stage.current.get_children():
		if n is OmniLight3D:
			lights.append(n)
	check(lights.size() >= 8, "la casa tiene %d luces de ambiente" % lights.size())
	var worst := 0
	var worst_name := ""
	for n in stage.current.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and n.name.begins_with("Casa_"):
			var mi: MeshInstance3D = n
			var box: AABB = mi.global_transform * mi.get_aabb()
			var cnt := 0
			for l in lights:
				if (l.light_cull_mask & mi.layers) == 0:
					continue
				var closest := l.global_position.clamp(box.position, box.end)
				if closest.distance_to(l.global_position) <= l.omni_range:
					cnt += 1
			if cnt > worst:
				worst = cnt
				worst_name = mi.name
	check(worst <= MAX_LIGHTS_PER_MESH, "ninguna malla ve más de %d luces (peor: %d en %s)" % [MAX_LIGHTS_PER_MESH, worst, worst_name])

	# --- el portal de la casa no se mete en las paredes, ni al conjurarlo de cara a un muro
	story.skip()
	var spots := [Vector3(-9.6, 0.1, -4.0), Vector3(0.0, 0.1, -4.0), Vector3(9.0, 0.1, 3.0), Vector3(-6.5, 0.1, 4.5)]
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
		for spot in spots:
			player.call("teleport", stage.current.global_transform * spot, yaw)
			await frames(8)
			Input.action_press("interact")
			await frames(3)
			Input.action_release("interact")
			await frames(3)
			var ps: Array = stage.current.portals
			if ps.size() != 1:
				check(false, "se conjura un portal en %s mirando %.1f" % [str(spot), yaw])
				continue
			var p: Portal = ps[0]
			var d := Vector2(p.global_position.x - spot.x, p.global_position.z - spot.z).length()
			var eye: Vector3 = player.global_position + Vector3(0, 1.0, 0)
			var rq := PhysicsRayQueryParameters3D.create(eye, p.global_position + Vector3(0, 1.0, 0), 1)
			var behind_wall := not root.get_world_3d().direct_space_state.intersect_ray(rq).is_empty()
			check(d >= 1.35 and d <= stage.current.portal_distance + 0.05 and not behind_wall,
				"  portal a %.1f m de Andro, a la vista, en %s (mira %.1f)" % [d, str(spot), yaw])
			stage.current.clear_portals()
			story._door = null
			await frames(50)

	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(fails)

class_name Story
extends Node
## Director de la historia: un hombre-demonio que levita viaja por sus recuerdos buscando al demonio
## que le enseñó su poder cuando era niño. Cada recuerdo es una escena a la que se entra por una
## puerta que Andro conjura con el botón PUERTA. Los subtítulos (telepatía) salen mientras camina.
##
## Cada capítulo: escena, líneas de entrada, objetivo (zona a la que hay que llegar), líneas de cierre
## y a dónde lleva la puerta. Antes de cumplir el objetivo la puerta "no responde".

const CHAPTERS := [
	{
		"scene": "umbral",
		"intro": [
			"He viajado por todas las realidades, ahora que sé que existe el demonio que me creó como un ser divino de la oscuridad.",
			"Ahora puedo usar este poder para descubrir mi origen y mis recuerdos humanos.",
		],
		"objective": "",
		"outro": [],
		"next": "casa",
		"hint": "Toca PUERTA para conjurar la primera",
	},
]

## La trama completa se escribe después de los mapas (decisión de Pablo, 16 nov): por ahora solo está el diálogo del Umbral.
const EPILOGUE: Array = []
## El botón PUERTA lleva, desde el Umbral, al siguiente mapa abierto de esta lista (rotación); desde cualquier otro mapa
## vuelve al Umbral. Para ir a un mapa concreto (desde cualquier mapa) está la rueda circular (`MapWheel` → `conjure_to`).
const MAPS := ["casa", "anillos", "dunas"]
## Partida guardada: mapas desbloqueados (se puede apagar en pruebas con `Story.save_enabled = false`).
const SAVE_PATH := "user://noctis.cfg"
static var save_enabled := true
signal map_unlocked(id: String)
signal stage_changed(index: int)

var stage: Stage
var player: Node3D
var hud: GameHUD
var chapter := 0                 # capítulo actual (índice en CHAPTERS), o CHAPTERS.size() = libre
var objective_done := false
var can_conjure := false
var free_index := 0
var unlocked: Array = MapCatalog.START_UNLOCKED.duplicate()
## Etapa de la historia: 0 principio (portales de piedra), 1 mitad (celestiales), 2 final (dorados). La trama aún no está
## escrita (F5): por ahora solo cambia con `set_stage` / `advance_stage` (y los atajos del panel de pausa).
var stage_index := 0

var _gen := 0                    # invalida corutinas viejas al cambiar de escena
var _door: Portal = null


func _ready() -> void:
	add_to_group("story")


## Fija la etapa de la historia y con ella el estilo de los portales nuevos (piedra, celestial, dorado).
func set_stage(n: int) -> void:
	stage_index = clampi(n, 0, 2)
	Portal.style_index = stage_index
	_save_progress()
	stage_changed.emit(stage_index)


func advance_stage() -> void:
	set_stage(stage_index + 1)


func setup(p_stage: Stage, p_player: Node3D, p_hud: GameHUD, start := "umbral") -> void:
	_load_progress()
	Portal.style_index = stage_index
	stage = p_stage
	player = p_player
	hud = p_hud
	stage.scene_entered.connect(_on_scene_entered)
	stage.scene_leaving.connect(_on_scene_leaving)
	# empezar en un capítulo concreto (continuar / pruebas); si no existe, modo libre
	chapter = CHAPTERS.size()
	for i in CHAPTERS.size():
		if CHAPTERS[i]["scene"] == start:
			chapter = i
			break
	stage.go(start)


## Salta los subtítulos en curso y habilita la puerta si ya se puede (también sirve en pruebas).
func skip() -> void:
	_gen += 1
	hud.fade_caption(0.3)
	if chapter >= CHAPTERS.size():
		_allow_conjure("Toca PUERTA para abrir un portal")
		return
	var ch: Dictionary = CHAPTERS[chapter]
	if (ch["objective"] as String) == "" or objective_done:
		_allow_conjure(ch["hint"])


func _on_scene_leaving(_id: String) -> void:
	_gen += 1
	can_conjure = false
	_door = null
	hud.set_prompt("")
	hud.fade_caption(0.5)


func _on_scene_entered(id: String) -> void:
	_gen += 1
	objective_done = false
	can_conjure = false
	_door = null
	hud.show_title(stage.current.title)
	if stage.current.has_signal("room_changed") and not stage.current.is_connected("room_changed", _on_room_changed):
		stage.current.connect("room_changed", _on_room_changed)
	if chapter >= CHAPTERS.size():
		_run_free(id, _gen)
		return
	var ch: Dictionary = CHAPTERS[chapter]
	if id != ch["scene"]:
		# Entró a una escena fuera de orden (p. ej. en pruebas): tratarla como modo libre.
		_run_free(id, _gen)
		return
	if (ch["objective"] as String) != "":
		stage.current.objective_reached.connect(_on_objective)
	_run_intro(ch, _gen)


## En la casa, cada cuarto nuevo muestra su nombre (el primero ya lo cubre el título de la escena).
func _on_room_changed(_room_id: String, room_title: String) -> void:
	if stage.current != null and stage.current.id == "casa" and hud != null and (stage.current.get("room") != null):
		hud.show_title(room_title)


func _run_intro(ch: Dictionary, gen: int) -> void:
	await get_tree().create_timer(1.2).timeout
	for line in ch["intro"]:
		if gen != _gen:
			return
		var t := hud.say(line)
		await get_tree().create_timer(t + 2.6).timeout
	if gen != _gen:
		return
	hud.fade_caption(1.0)
	if (ch["objective"] as String) == "":
		_allow_conjure(ch["hint"])


func _on_objective(name: String) -> void:
	if objective_done or chapter >= CHAPTERS.size():
		return
	var ch: Dictionary = CHAPTERS[chapter]
	if name != ch["objective"]:
		return
	objective_done = true
	_run_outro(ch, _gen)


func _run_outro(ch: Dictionary, gen: int) -> void:
	for line in ch["outro"]:
		if gen != _gen:
			return
		var t := hud.say(line)
		await get_tree().create_timer(t + 2.8).timeout
	if gen != _gen:
		return
	hud.fade_caption(1.0)
	_allow_conjure(ch["hint"])


func _run_free(id: String, gen: int) -> void:
	await get_tree().create_timer(1.2).timeout
	if gen != _gen:
		return
	if id == "umbral":
		for line in EPILOGUE:
			if gen != _gen:
				return
			var t := hud.say(line)
			await get_tree().create_timer(t + 2.6).timeout
		hud.fade_caption(1.0)
	_allow_conjure("Toca PUERTA para abrir un portal")


func _allow_conjure(hint: String) -> void:
	can_conjure = true
	hud.set_prompt(hint)


func _process(_delta: float) -> void:
	if stage == null or stage.busy or stage.current == null or UiLock.blocked:
		return
	if Input.is_action_just_pressed("interact"):
		_try_conjure()


## Destino al que lleva la próxima puerta: desde el Umbral, el siguiente mapa abierto; desde cualquier mapa, de vuelta al Umbral.
func next_target() -> String:
	if stage.current_id != "umbral":
		return "umbral"
	if chapter < CHAPTERS.size():
		return CHAPTERS[chapter]["next"]
	for i in MAPS.size():
		var id: String = MAPS[(free_index + i) % MAPS.size()]
		if is_unlocked(id):
			return id
	return MAPS[free_index % MAPS.size()]


# ------------------------------------------------------------------ mapas desbloqueados y rueda

func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


## Abre un mapa (la historia lo llama al pasar su parte). Se guarda en disco.
func unlock_map(id: String) -> void:
	if unlocked.has(id):
		return
	unlocked.append(id)
	_save_progress()
	map_unlocked.emit(id)


func _load_progress() -> void:
	if not save_enabled:
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	stage_index = clampi(int(cf.get_value("historia", "etapa", 0)), 0, 2)
	for id in cf.get_value("mapas", "desbloqueados", []):
		if not unlocked.has(id):
			unlocked.append(id)


func _save_progress() -> void:
	if not save_enabled:
		return
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("mapas", "desbloqueados", unlocked)
	cf.set_value("historia", "etapa", stage_index)
	cf.save(SAVE_PATH)


## ¿Se puede abrir la rueda y viajar ahora? (no durante un viaje, ni antes de que la historia dé la puerta)
func can_travel() -> bool:
	return can_conjure and stage != null and not stage.busy and stage.current != null


## Por qué no se puede ir a `id` ahora ("" = se puede). Mensaje listo para mostrar.
func travel_block_reason(id: String) -> String:
	if not stage.has_scene(id):
		return "Aún no existe esta dimensión."
	if not is_unlocked(id):
		return "Aún no. Hay que pasar la historia."
	if id == stage.current_id:
		return "Ya estás aquí."
	if not can_travel():
		return "Aún no."
	return ""


## Elegido en la rueda: conjura (o reemplaza) el portal hacia `id`, desde el mapa en que se esté. Devuelve si lo hizo.
func conjure_to(id: String) -> bool:
	if travel_block_reason(id) != "":
		return false
	if _door != null and is_instance_valid(_door):
		stage.current.clear_portals()
		_door = null
	_spawn_portal(id)
	return true


## A qué distancia delante de Andro aparece el portal: la que pide la escena, pero sin meterse en una pared.
func _portal_distance(fwd: Vector3) -> float:
	var d: float = stage.current.portal_distance
	var from: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * (d + 1.0), 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return d
	return clampf(from.distance_to(hit["position"]) - 1.0, minf(1.4, d), d)


func _try_conjure() -> void:
	if not can_conjure:
		if chapter < CHAPTERS.size() and not objective_done and (CHAPTERS[chapter]["objective"] as String) != "":
			hud.say("Aún no. Hay algo que ver aquí.")
			get_tree().create_timer(2.8).timeout.connect(hud.fade_caption.bind(1.0))
		return
	if _door != null and is_instance_valid(_door):
		return
	_spawn_portal(next_target())


func _spawn_portal(target: String) -> void:
	var f: float = player.call("get_facing")
	var fwd := Vector3(-sin(f), 0.0, -cos(f))
	var pos: Vector3 = player.global_position + fwd * _portal_distance(fwd)
	pos.y = player.global_position.y - 0.05
	_door = stage.current.conjure_portal(target, pos, f)
	hud.set_prompt("")
	# al cruzarla se avanza el capítulo
	_door.entered.connect(_on_door_crossed.bind(target), CONNECT_ONE_SHOT)


func _on_door_crossed(_p: Portal, _target: String) -> void:
	var from_umbral := stage.current_id == "umbral"
	if chapter < CHAPTERS.size():
		chapter += 1
	if from_umbral:
		free_index += 1

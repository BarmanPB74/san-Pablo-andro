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
		"next": "planetas",
		"hint": "Toca PUERTA para conjurar la primera",
	},
	{
		"scene": "planetas",
		"intro": [
			"Mi primera lección: ordenar el cielo como quien ordena juguetes.",
			"Camina hasta el último astro.",
		],
		"objective": "planeta_final",
		"outro": [
			"Una voz de niño contó los mundos conmigo. No recuerdo su rostro.",
		],
		"next": "fuente",
		"hint": "Toca PUERTA para seguir",
	},
	{
		"scene": "fuente",
		"intro": [
			"Este rostro nunca terminó de hablar.",
			"Acércate al agua. Escucha lo que dice.",
		],
		"objective": "estanque",
		"outro": [
			"Me enseñó a callar para oír el agua. Todavía la oigo.",
		],
		"next": "anillos",
		"hint": "Toca PUERTA para seguir",
	},
	{
		"scene": "anillos",
		"intro": [
			"Tres anillos enlazados. Así medía yo el tiempo.",
			"Sube hasta la luz.",
		],
		"objective": "altar",
		"outro": [
			"La luz me dijo que el poder no se gana: se presta.",
		],
		"next": "cubo",
		"hint": "Toca PUERTA para seguir",
	},
	{
		"scene": "cubo",
		"intro": [
			"El último recuerdo pesa más que todos.",
			"Cruza la orilla hasta quedar bajo el cubo.",
		],
		"objective": "orilla_cubo",
		"outro": [
			"Él no estaba. Solo el cubo… y su sombra sobre mí.",
		],
		"next": "umbral_final",
		"hint": "Toca PUERTA para volver",
	},
]

## Cuando ya se vio todo: el Umbral otra vez, con la puerta libre hacia cualquier recuerdo.
const EPILOGUE := [
	"Ya sé dónde empezar a buscarlo.",
	"Pero antes debo recordar un poco más.",
	"Fin del prólogo. Puedes seguir conjurando puertas.",
]
const FREE_ORDER := ["planetas", "fuente", "anillos", "cubo"]

var stage: Stage
var player: Node3D
var hud: GameHUD
var chapter := 0                 # capítulo actual (índice en CHAPTERS), o CHAPTERS.size() = libre
var objective_done := false
var can_conjure := false
var free_index := 0

var _gen := 0                    # invalida corutinas viejas al cambiar de escena
var _door: Portal = null


func setup(p_stage: Stage, p_player: Node3D, p_hud: GameHUD, start := "umbral") -> void:
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
		_allow_conjure("Toca PUERTA para conjurar otro recuerdo")
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
	_allow_conjure("Toca PUERTA para conjurar otro recuerdo")


func _allow_conjure(hint: String) -> void:
	can_conjure = true
	hud.set_prompt(hint)


func _process(_delta: float) -> void:
	if stage == null or stage.busy or stage.current == null:
		return
	if Input.is_action_just_pressed("interact"):
		_try_conjure()


## Destino al que lleva la próxima puerta.
func next_target() -> String:
	if chapter < CHAPTERS.size():
		var nxt: String = CHAPTERS[chapter]["next"]
		return "umbral" if nxt == "umbral_final" else nxt
	var t: String = FREE_ORDER[free_index % FREE_ORDER.size()]
	return t


func _try_conjure() -> void:
	if not can_conjure:
		if chapter < CHAPTERS.size() and not objective_done and (CHAPTERS[chapter]["objective"] as String) != "":
			hud.say("Aún no. Hay algo que ver aquí.")
			get_tree().create_timer(2.8).timeout.connect(hud.fade_caption.bind(1.0))
		return
	if _door != null and is_instance_valid(_door):
		return
	var f: float = player.call("get_facing")
	var fwd := Vector3(-sin(f), 0.0, -cos(f))
	var pos: Vector3 = player.global_position + fwd * 7.5
	pos.y = player.global_position.y - 0.05
	var target := next_target()
	_door = stage.current.conjure_portal(target, pos, f)
	hud.set_prompt("")
	# al cruzarla se avanza el capítulo
	_door.entered.connect(_on_door_crossed.bind(target), CONNECT_ONE_SHOT)


func _on_door_crossed(_p: Portal, _target: String) -> void:
	if chapter < CHAPTERS.size():
		chapter += 1
	else:
		free_index += 1

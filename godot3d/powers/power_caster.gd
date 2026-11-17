class_name PowerCaster
extends Node3D
## Controlador de poderes de Andro (hijo de Player). Lee las acciones "charge" (mantener: cargar ki), "cast" (lanzar la
## bola de fuego) y "upgrade" (gastar un punto en subir el tope de la barra), gasta/recarga la barra (SpellBook), enciende
## la aura (KiAura) y las esferas, y dispara la bola desde la esfera de poder que más apunta hacia donde mira la cámara.

const SPELL := "fireball"
const WIND_UP := 0.18                   # s entre que la esfera se adelanta y sale la bola
const NO_POWER_STATES := ["stumble", "enter_vehicle", "exit_vehicle", "in_vehicle", "punch"]

signal cast_started(orb: int)
signal fireball_launched(ball: Fireball)

var player: Player
var camera_rig: Node
var book: SpellBook
var progress: Progress
var aura: KiAura
var charging := false
var _pending := []                      # [{t, orb, dir}]
var _was_full := true


func setup(p: Player, cam: Node, b: SpellBook, prog: Progress) -> void:
	player = p
	camera_rig = cam
	book = b
	progress = prog
	name = "PowerCaster"
	aura = KiAura.new()
	add_child(aura)
	if progress:
		player.model.level = progress.level
		progress.level_changed.connect(func(l: int) -> void: player.model.level = l)
	book.filled.connect(func(_id: String) -> void: aura.pulse())


func _process(delta: float) -> void:
	if player == null or book == null:
		return
	var allowed := _allowed()
	var want_charge := allowed and player.is_on_floor() and _pressed("charge") and book.fill(SPELL) >= 0.0
	set_charging(want_charge)
	if allowed and _just("cast"):
		cast()
	if allowed and _just("upgrade"):
		book.upgrade(SPELL)
	# lanzamientos en espera (la esfera ya se adelantó)
	for c in _pending.duplicate():
		c.t -= delta
		if c.t <= 0.0:
			_pending.erase(c)
			_launch(c)
	# efectos: la aura sube con el flote y su fuerza sigue a la barra; la tela y las esferas se encienden
	aura.position = Vector3(0.0, player.model.position.y, 0.0)
	aura.set_state(charging, book.fill(SPELL))
	aura.update(delta)
	var cg := aura.power * 0.9
	player.model.charge = lerpf(player.model.charge, cg, 1.0 - exp(-10.0 * delta))


func set_charging(on: bool) -> void:
	charging = on
	book.charging = on
	player.charging = on


func _allowed() -> bool:
	if UiLock.blocked or player.current_vehicle != null or not player.visible:
		return false
	return not NO_POWER_STATES.has(player.state)


func _pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


## Dirección horizontal hacia donde mira la cámara (yaw 0 = -Z).
func aim_dir() -> Vector3:
	var yaw := player.get_facing()
	if camera_rig and camera_rig.has_method("get_yaw"):
		yaw = camera_rig.call("get_yaw")
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Lanza una bola de fuego si la barra alcanza. Devuelve true si salió.
func cast() -> bool:
	if not book.try_cast(SPELL):
		return false
	var dir := aim_dir()
	player.face_yaw(atan2(-dir.x, -dir.z))
	var orb := player.model.orb_toward(dir)
	player.model.flash_orb(orb)
	_pending.append({"t": WIND_UP, "orb": orb, "dir": dir})
	cast_started.emit(orb)
	return true


func _launch(c: Dictionary) -> void:
	var from: Vector3 = player.model.orb_global_position(c.orb)
	var parent := player.get_parent()
	if parent == null:
		return
	var ball := Fireball.launch(parent, from, Vector3(c.dir.x, 0.02, c.dir.z))
	fireball_launched.emit(ball)

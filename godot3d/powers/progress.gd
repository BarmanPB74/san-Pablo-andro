class_name Progress
extends Node
## Progreso de Andro: nivel (0..33), experiencia y puntos de mejora. Los guarda en user://noctis.cfg ([progreso]).
## Reglas provisionales (ajustables): cada hechizo lanzado da 1 de experiencia; subir de nivel pide `xp_needed(nivel)` y da
## 1 punto de mejora. La historia (Story) podrá dar experiencia o fijar el nivel con `add_xp` / `set_level`.
## El nivel enciende las runas EISEN-KERN del dobladillo (AndroCloak.level).

signal level_changed(level: int)
signal leveled_up(level: int)          # solo al ganar experiencia (da punto de mejora); set_level no la emite
signal xp_changed(xp: int, need: int)
signal points_changed(points: int)

const MAX_LEVEL := 33
const SAVE_PATH := "user://noctis.cfg"
## Se puede apagar en pruebas con `Progress.save_enabled = false`.
static var save_enabled := true

var level := 0
var xp := 0
var points := 0
var upgrades := {}         # id de hechizo -> mejoras compradas


func _ready() -> void:
	add_to_group("progress")
	load_progress()


## Experiencia necesaria para pasar de `l` a `l + 1`.
static func xp_needed(l: int) -> int:
	return 4 + l


func add_xp(n: int) -> void:
	if n <= 0 or level >= MAX_LEVEL:
		return
	xp += n
	while level < MAX_LEVEL and xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		points += 1
		level_changed.emit(level)
		leveled_up.emit(level)
		points_changed.emit(points)
	if level >= MAX_LEVEL:
		xp = 0
	xp_changed.emit(xp, xp_needed(mini(level, MAX_LEVEL - 1)))
	save_progress()


## Fija el nivel directamente (pruebas, historia). No da puntos.
func set_level(l: int) -> void:
	level = clampi(l, 0, MAX_LEVEL)
	xp = 0
	level_changed.emit(level)
	xp_changed.emit(xp, xp_needed(mini(level, MAX_LEVEL - 1)))
	save_progress()


func add_points(n: int) -> void:
	points = maxi(0, points + n)
	points_changed.emit(points)
	save_progress()


## Gasta un punto en mejorar el hechizo `id`. false si no hay puntos.
func spend_point(id: String) -> bool:
	if points <= 0:
		return false
	points -= 1
	upgrades[id] = upgrade_count(id) + 1
	points_changed.emit(points)
	save_progress()
	return true


func upgrade_count(id: String) -> int:
	return int(upgrades.get(id, 0))


func load_progress() -> void:
	if not save_enabled:
		return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	level = clampi(int(cf.get_value("progreso", "nivel", 0)), 0, MAX_LEVEL)
	xp = maxi(0, int(cf.get_value("progreso", "xp", 0)))
	points = maxi(0, int(cf.get_value("progreso", "puntos", 0)))
	upgrades = cf.get_value("progreso", "mejoras", {})


func save_progress() -> void:
	if not save_enabled:
		return
	var cf := ConfigFile.new()
	cf.load(SAVE_PATH)
	cf.set_value("progreso", "nivel", level)
	cf.set_value("progreso", "xp", xp)
	cf.set_value("progreso", "puntos", points)
	cf.set_value("progreso", "mejoras", upgrades)
	cf.save(SAVE_PATH)

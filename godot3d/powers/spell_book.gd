class_name SpellBook
extends Node
## Barras de magia, una por hechizo. Cada barra va de 0 a 1 (100 %), pero al principio solo se llena hasta el tope
## base (50 %); cada punto de mejora (Progress.spend_point) sube el tope 5 %. Se recarga sola y rápido; cargando energía
## (aura de ki) se llena mucho más rápido. Lanzar cuesta una fracción de la barra.

signal changed(id: String)
signal cast_done(id: String)
signal upgraded(id: String)
signal filled(id: String)

const SPELLS := {
	"fireball": {
		"name": "BOLA DE FUEGO",
		"cost": 0.10,           # fracción de la barra por lanzamiento
		"base_cap": 0.50,       # tope inicial (50 %)
		"cap_step": 0.05,       # lo que sube el tope con cada mejora
		"max_upgrades": 10,     # 0.50 + 10 × 0.05 = 100 %
		"cooldown": 0.35,       # s entre lanzamientos
		"xp": 1,                # experiencia por lanzamiento
	},
}
const REGEN_RATE := 0.12        # fracción de barra por segundo, sola: 0 → 50 % en ~4 s
const CHARGE_RATE := 0.55       # lo mismo cargando ki: 0 → 50 % en ~1 s

var progress: Progress
var charging := false
var values := {}
var _cd := {}


func _init() -> void:
	for id in SPELLS:
		values[id] = float(SPELLS[id].base_cap)      # empieza llena hasta el tope: se puede probar enseguida
		_cd[id] = 0.0


func setup(p: Progress) -> void:
	progress = p
	for id in SPELLS:
		values[id] = minf(float(values[id]), cap(id))


func spell_name(id: String) -> String:
	return String(SPELLS[id].name)


## Rango de mejora (0..Abilities.MAX_RANK) de una habilidad: "fireball" o "ki".
func rank(id: String) -> int:
	return progress.upgrade_count(id) if progress else 0


## Velocidad de carga con ki: sube con el rango del ki.
func charge_rate() -> float:
	return CHARGE_RATE * Abilities.ki_rate_mult(rank("ki"))


func cost(id: String) -> float:
	return float(SPELLS[id].cost)


func upgrades_of(id: String) -> int:
	return progress.upgrade_count(id) if progress else 0


## Tope actual de la barra (0..1).
func cap(id: String) -> float:
	var s: Dictionary = SPELLS[id]
	return minf(1.0, float(s.base_cap) + float(s.cap_step) * float(upgrades_of(id)))


func value(id: String) -> float:
	return float(values[id])


## Cuánto de lo que cabe ya está lleno (0..1).
func fill(id: String) -> float:
	return clampf(value(id) / maxf(cap(id), 0.001), 0.0, 1.0)


func can_cast(id: String) -> bool:
	return value(id) >= cost(id) - 0.0001 and float(_cd[id]) <= 0.0


## Gasta la barra y da experiencia. false si no alcanza o aún enfría.
func try_cast(id: String) -> bool:
	if not can_cast(id):
		return false
	values[id] = maxf(0.0, value(id) - cost(id))
	_cd[id] = float(SPELLS[id].cooldown)
	if progress:
		progress.add_xp(int(SPELLS[id].xp))
	changed.emit(id)
	cast_done.emit(id)
	return true


func can_upgrade(id: String) -> bool:
	return progress != null and progress.points >= Abilities.POINT_COST and rank(id) < Abilities.MAX_RANK


func upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	if not progress.spend_point(id):
		return false
	changed.emit("fireball")
	upgraded.emit(id)
	return true


func _process(delta: float) -> void:
	for id in SPELLS:
		_cd[id] = maxf(0.0, float(_cd[id]) - delta)
		var c := cap(id)
		var v := value(id)
		if v < c:
			var nv := minf(c, v + (charge_rate() if charging else REGEN_RATE) * delta)
			values[id] = nv
			changed.emit(id)
			if nv >= c and v < c and charging:
				filled.emit(id)

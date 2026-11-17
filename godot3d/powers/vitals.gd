class_name Vitals
extends Node
## Vida de Andro. Aún no hay enemigos ni peligros: la barra se ve en el panel y `take_damage` queda listo para cuando los haya.
## Se regenera sola despacio si pasan unos segundos sin recibir daño.

signal changed(hp: float, max_hp: float)
signal died

const REGEN_DELAY := 5.0         # s sin daño antes de regenerar
const REGEN_RATE := 4.0          # vida por segundo

var max_hp := 100.0
var hp := 100.0
var _since_hit := 99.0


func take_damage(amount: float) -> void:
	if amount <= 0.0 or hp <= 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_since_hit = 0.0
	changed.emit(hp, max_hp)
	if hp <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	changed.emit(hp, max_hp)


func fraction() -> float:
	return hp / max_hp


func _process(delta: float) -> void:
	_since_hit += delta
	if hp > 0.0 and hp < max_hp and _since_hit >= REGEN_DELAY:
		hp = minf(max_hp, hp + REGEN_RATE * delta)
		changed.emit(hp, max_hp)

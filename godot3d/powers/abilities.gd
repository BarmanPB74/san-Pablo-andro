class_name Abilities
extends RefCounted
## Datos de las habilidades mejorables: nombre, rango máximo, colores por etapa y números por rango.
## Cada punto de mejora sube 1 rango (0..MAX_RANK). El color cambia cada 2 rangos (5 etapas: rangos 0, 2, 4, 6 y 8).
## - Ki (carga): blanco → amarillo → rojo → morado → morado con negro; carga más rápido y el aura crece.
## - Bola de fuego: naranja → roja → azul → morada → morada con negro; más daño, explosión y empuje, más tope de magia.

const MAX_RANK := 10
const POINT_COST := 1
const IDS := ["fireball", "ki"]

const DATA := {
	"fireball": {
		"name": "BOLA DE FUEGO",
		"tiers": [
			{"name": "Naranja", "core": Color(1.0, 0.93, 0.66), "edge": Color(1.0, 0.32, 0.04), "glow": Color(1.0, 0.5, 0.12)},
			{"name": "Roja", "core": Color(1.0, 0.74, 0.55), "edge": Color(0.88, 0.05, 0.03), "glow": Color(1.0, 0.16, 0.08)},
			{"name": "Azul", "core": Color(0.86, 0.95, 1.0), "edge": Color(0.12, 0.38, 1.0), "glow": Color(0.25, 0.5, 1.0)},
			{"name": "Morada", "core": Color(0.96, 0.82, 1.0), "edge": Color(0.55, 0.1, 0.95), "glow": Color(0.62, 0.2, 1.0)},
			{"name": "Morada y negra", "core": Color(0.92, 0.6, 1.0), "edge": Color(0.03, 0.0, 0.07), "glow": Color(0.6, 0.15, 1.0), "dark": true},
		],
	},
	"ki": {
		"name": "KI",
		"tiers": [
			{"name": "Blanco", "core": Color(1.0, 1.0, 1.0), "edge": Color(0.78, 0.88, 1.0), "glow": Color(0.85, 0.92, 1.0)},
			{"name": "Amarillo", "core": Color(1.0, 0.97, 0.62), "edge": Color(1.0, 0.78, 0.15), "glow": Color(1.0, 0.82, 0.25)},
			{"name": "Rojo", "core": Color(1.0, 0.62, 0.48), "edge": Color(1.0, 0.12, 0.08), "glow": Color(1.0, 0.2, 0.12)},
			{"name": "Morado", "core": Color(0.92, 0.72, 1.0), "edge": Color(0.55, 0.1, 0.95), "glow": Color(0.62, 0.2, 1.0)},
			{"name": "Morado y negro", "core": Color(0.78, 0.45, 1.0), "edge": Color(0.38, 0.06, 0.7), "glow": Color(0.6, 0.15, 1.0), "dark": true},
		],
	},
}


static func ability_name(id: String) -> String:
	return String(DATA[id].name)


static func tier_of_rank(rank: int) -> int:
	return clampi(rank / 2, 0, 4)


static func tier(id: String, rank: int) -> Dictionary:
	return DATA[id].tiers[tier_of_rank(rank)]


static func tier_count(id: String) -> int:
	return (DATA[id].tiers as Array).size()


# ---- números por rango (bola de fuego)
static func fireball_damage(rank: int) -> float:
	return 20.0 + 6.0 * rank


static func fireball_radius(rank: int) -> float:
	return 1.6 + 0.25 * rank          # radio de la explosión (m)


static func fireball_push(rank: int) -> float:
	return 7.0 + 1.0 * rank           # velocidad (m/s) que recibe un objeto liviano


static func fireball_scale(rank: int) -> float:
	return 1.0 + 0.05 * rank


static func fireball_cap(rank: int) -> float:
	return minf(1.0, 0.5 + 0.05 * rank)


# ---- números por rango (ki)
static func ki_rate_mult(rank: int) -> float:
	return 1.0 + 0.2 * rank


static func ki_aura_scale(rank: int) -> float:
	return 1.0 + 0.03 * rank


## Filas [etiqueta, valor] para mostrar en el panel de pausa, en el rango `rank`.
static func stat_rows(id: String, rank: int) -> Array:
	var rows := []
	match id:
		"fireball":
			rows.append(["Daño", "%d" % int(fireball_damage(rank))])
			rows.append(["Explosión", "%.1f m" % fireball_radius(rank)])
			rows.append(["Empuje", "%d m/s" % int(fireball_push(rank))])
			rows.append(["Tope de magia", "%d %%" % int(round(fireball_cap(rank) * 100.0))])
		"ki":
			rows.append(["Velocidad de carga", "x%.1f" % ki_rate_mult(rank)])
			rows.append(["Tamaño del aura", "x%.2f" % ki_aura_scale(rank)])
	rows.append(["Color", String(tier(id, rank).name)])
	return rows

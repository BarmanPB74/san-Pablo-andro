class_name MapCatalog
extends RefCounted
## Catálogo de los mapas de Noctis tal como los muestra la rueda circular (estilo GTA V). El orden es el de la rueda:
## el sector 0 queda arriba y sigue en sentido horario. Los sectores sin escena todavía son dimensiones por crear (fase 4).
## Un mapa se desbloquea al pasar su parte de la historia (`Story.unlock_map(id)`); mientras tanto sale con candado.

const SLOTS := [
	{"id": "umbral", "name": "UMBRAL", "title": "El Umbral", "desc": "Centro de habilidades. Desde aquí se viaja a todo."},
	{"id": "casa", "name": "CASA", "title": "La Casa", "desc": "El recuerdo de cuando era un niño humano."},
	{"id": "anillos", "name": "ANILLOS", "title": "La Cámara de los Anillos", "desc": "Una escultura de anillos flotando en el vacío."},
	{"id": "dim4", "name": "???", "title": "Dimensión por descubrir", "desc": ""},
	{"id": "dim5", "name": "???", "title": "Dimensión por descubrir", "desc": ""},
	{"id": "dim6", "name": "???", "title": "Dimensión por descubrir", "desc": ""},
]

## Mapas que ya están abiertos al empezar una partida nueva. El Umbral siempre; casa y anillos están abiertos mientras
## no exista la trama que los desbloquea (editar esta lista cuando la historia los vaya cerrando).
const START_UNLOCKED := ["umbral", "casa", "anillos"]


static func count() -> int:
	return SLOTS.size()


static func slot(i: int) -> Dictionary:
	return SLOTS[posmod(i, SLOTS.size())]


static func index_of(id: String) -> int:
	for i in SLOTS.size():
		if SLOTS[i]["id"] == id:
			return i
	return -1

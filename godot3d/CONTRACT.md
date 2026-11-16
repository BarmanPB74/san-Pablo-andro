# Contrato técnico — Noctis (antes San Pablo Andro 3D) (Godot 4.x; objetivo: renderer Compatibility en el teléfono)

Este documento es la fuente de verdad entre los agentes. Si algo no está aquí, NO lo asumas de otro módulo.

## Convenciones globales
- 1 unidad = 1 metro. Y arriba. **-Z = Norte**, +X = Este.
- Cada escena tiene su propio origen: el piso está en y = 0 y Andro aparece en `spawn_pos` (cada `StageScene` lo define; yaw 0 = mira a -Z).
- Todo se construye **por código** (GDScript) con primitivas (BoxMesh, CylinderMesh, CapsuleMesh, PrismMesh, CSG prohibido por rendimiento móvil salvo en editor). No hay assets externos ni descargas.
- Materiales: shaders propios en `stage/shaders/` y `character/shaders/` (cielo, piso, roca, agua, galaxia…). `Palette` y `ClayStyle` pertenecen al juego anterior y no se usan (`ClayStyle.enabled = false`).
- Tipado estático en GDScript (`var x: float`), tabs para indentar, comentarios en español.
- Objetivo de rendimiento: teléfono Android gama alta (Poco F8 Pro). Pocos draw calls: usa MultiMeshInstance3D para elementos repetidos (ventanas, árboles, postes), sombras solo de la luz direccional, luces Omni con `shadow_enabled=false` y rango corto.

## Capas de física (collision_layer bits)
| capa | nombre | quién |
|---|---|---|
| 1 | world | suelo, edificios, sardineles, mobiliario estático |
| 2 | player | personaje |
| 3 | vehicles | VehicleBody3D |
| 4 | props | objetos dinámicos (canecas, conos) |
- Personaje: layer 2, mask 1|3|4.
- Vehículo: layer 3, mask 1|2|3|4.

## Grupos
- `"player"` — el CharacterBody3D del jugador.
- `"vehicle"` — cada vehículo conducible (módulo dormido).
- `"portal"` — cada `Portal` conjurado (Area3D que viaja al cruzarlo).
- `"camera_rig"` — la cámara. (`spawn_player`/`spawn_vehicle` del juego anterior ya no se usan.)

## Entradas (autoload `Inputs`, ya existe)
Acciones: `move_forward, move_back, move_left, move_right, sprint, jump, handbrake, interact, camera_toggle, horn, crouch, punch`. `interact` = **PUERTA** (conjura el portal hacia el siguiente recuerdo).
`Inputs.move_vector()` → Vector2 (x derecha, y adelante). `Inputs.take_touch_look()` → delta de cámara del dedo (píxeles) a sumar al mouse.
En auto: move_forward = acelerar, move_back = frenar/reversa, left/right = dirección, handbrake = freno de mano.

## API de vehículos (agente VEHICLES) — `res://vehicles/vehicle.gd`
```gdscript
class_name Vehicle extends VehicleBody3D
signal driver_entered(driver: Node3D)
signal driver_exited(driver: Node3D)
var driver: Node3D               # null si está vacío
func is_occupied() -> bool
func get_entry_point() -> Vector3   # global, puerta del conductor (lado izquierdo)
func enter(new_driver: Node3D) -> void   # empieza a leer Inputs
func exit() -> Vector3               # suelta el control, devuelve posición global segura para el jugador
func get_speed_kmh() -> float
func get_camera_anchor() -> Node3D  # punto que sigue la cámara
```
Fábrica: `VehicleFactory.spawn(kind: String, xform: Transform3D, parent: Node) -> Vehicle` en `res://vehicles/vehicle_factory.gd`.

## API del personaje (agente CHARACTER) — `res://character/player.gd`
```gdscript
class_name Player extends CharacterBody3D
var current_vehicle: Vehicle
func get_camera_anchor() -> Node3D
```
- Con `interact` busca el `Vehicle` más cercano (grupo "vehicle") a ≤ 3.5 m de su `get_entry_point()`; si está libre, entra: se oculta, desactiva colisión y física, y la cámara pasa a `vehicle.get_camera_anchor()`. Con `interact` dentro del auto: `vehicle.exit()` y reaparece en la posición devuelta.
- La cámara es `res://character/camera_rig.gd` (`class_name CameraRig extends Node3D`) con `func follow(target: Node3D, mode: String)` donde mode = "on_foot" | "vehicle". El Player crea/busca el CameraRig en el grupo `"camera_rig"`.
- Atropellos: si un Vehicle golpea al jugador a > 15 km/h, el jugador entra en estado `"stumble"` (cae, se levanta) — estilo GTA IV.

## Escenarios — `res://stage/`
- `Stage` (`stage.gd`): `go(id)` viaja a una escena (remolino de `TransitionFX`), `current`, `current_id`, señales `scene_entered/scene_leaving`. Ids: `umbral, casa, anillos` (tabla `Stage.SCENES`). La casa (`HouseScene`) tiene además `load_room(id)`, `room_id`, `door_crossed(pos)` y la señal `room_changed(id, título)`; sus cuartos están en `stage/house/` (`HouseRooms.DEFS`, `HouseBuilder`, `HouseMaterials`).
- `StageScene` (`stage_scene.gd`): base de cada escena. Define `title`, `spawn_pos`, `spawn_yaw`, `spawn_pitch`; rellena `build()`; es dueña de su `WorldEnvironment` y su luz. `portal_distance` y `portal_size` (distancia máxima y tamaño de los portales que se conjuran en la escena; en la casa son más chicos). Ayudantes: `make_environment`, `add_ground/box/cylinder/sphere`, `add_bounds_circle`, `add_trigger(objetivo, pos, tamaño)`, `conjure_portal(destino, pos, yaw)`, `portal_parent()` (de dónde cuelgan los portales; la casa los cuelga del cuarto actual). Señales `objective_reached(nombre)` y `portal_entered(destino)`.
- `Portal` (`portal.gd`): Area3D con marco de bronce y galaxia; `open()/close()`; emite `entered` al cruzarlo el jugador.
- Geometría procedural compartida: `Geo` (`geo.gd`: rejillas, columnas, riscos, rocas, superficies de revolución).

## Andro — `res://character/andro_cloak.gd`
`class_name AndroCloak extends Node3D`: cúpula + capa interior + manto abierto al frente con ribetes, sobre una esfera invisible (campo de fuerza = cápsula del jugador, `Player.CAPSULE_RADIUS` 0.66; shader con resorte-amortiguador) + 5 esferas de cromo gris que orbitan fuera del campo. Sin rasgos humanos. API que usa `Player`: `levitate`, `punch_t`, `punch_idx`, `animate(state, speed, delta)`.
- `MapWheel` (`ui/map_wheel.gd`): rueda circular de mapas; señales `opened/closed/chosen`, `open()/close()/choose(i)`. `MapCatalog` (`story/map_catalog.gd`): sectores y `START_UNLOCKED`. `Story`: `unlocked`, `is_unlocked`, `unlock_map(id)` (señal `map_unlocked`), `can_travel()`, `travel_block_reason(id)`, `conjure_to(id)`. `UiLock.blocked` (`core/ui_lock.gd`): true mientras la rueda está abierta. Acción de entrada nueva: `map_wheel` (Tab/M/Select; botón MAPAS).

`Player` conserva su física de caminar y suma `teleport(pos, yaw)`; el flote es solo visual (`HOVER_H`). `CameraRig` suma `snap_behind(yaw, pitch)`.

## Historia — `res://story/story.gd`
`class_name Story extends Node`: capítulos (`CHAPTERS`), subtítulos vía `GameHUD.say()`, objetivos por escena y puerta bloqueada hasta cumplirlos; `skip()` salta el diálogo; tras el último capítulo, modo libre.

## Escena principal — `res://main.tscn` (`core/game.gd`)
Instancia CameraRig, Player, TransitionFX, Stage, GameHUD, TouchControls y Story. `start_scene` exportado permite empezar en cualquier escena.

## Herramienta de validación
Godot headless: `godot --headless --path godot3d --import` y luego `godot --headless --fixed-fps 60 --path godot3d -s res://tests/stage_test.gd` (también `cloak_test.gd`, `character_logic_test.gd`).
Antes del primer uso corre una vez `--headless --editor --quit` para importar/registrar class_name.

# Contrato técnico — San Pablo Andro 3D (Godot 4.3, renderer Mobile)

Este documento es la fuente de verdad entre los agentes. Si algo no está aquí, NO lo asumas de otro módulo.

## Convenciones globales
- 1 unidad = 1 metro. Y arriba. **-Z = Norte**, +X = Este.
- Origen (0,0,0) = centro del Parque de Boston (pie de la estatua de José María Córdova), a nivel del andén del parque.
- Todo se construye **por código** (GDScript) con primitivas (BoxMesh, CylinderMesh, CapsuleMesh, PrismMesh, CSG prohibido por rendimiento móvil salvo en editor). No hay assets externos ni descargas.
- Materiales SIEMPRE desde `Palette` (`res://art/palette.gd`), p. ej. `Palette.asphalt()`. No crees materiales sueltos salvo shaders del agente LOOK.
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
- `"vehicle"` — cada vehículo conducible.
- `"spawn_player"` — Marker3D donde aparece el jugador (lo pone WORLD).
- `"spawn_vehicle"` — Marker3D donde aparecen autos estacionados (lo pone WORLD, con metadata `"kind"`: "taxi" | "sedan" | "pickup" | "buseta").

## Entradas (autoload `Inputs`, ya existe)
Acciones: `move_forward, move_back, move_left, move_right, sprint, jump, handbrake, interact, camera_toggle, horn`.
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

## Mundo (agente WORLD) — `res://world/boston_district.gd`
`class_name BostonDistrict extends Node3D` — construye en `_ready()` todo el barrio: terreno, calles, andenes, parque, iglesia, edificios, mobiliario, colisiones, spawns.

## Look (agente LOOK) — `res://look/`
- `res://look/second_son_environment.gd`: `class_name StreetLook extends Node` que en `_ready()` crea WorldEnvironment + DirectionalLight3D y expone `func set_time_of_day(preset: String)` con presets `"overcast_day" | "golden_hour" | "rainy_night"`.
- Dueño de `res://art/palette.gd` (puede mejorar el interior, no las firmas).

## Escena principal (integrador) — `res://main.tscn`
Instancia: StreetLook, BostonDistrict, CameraRig, Player en `spawn_player`, vehículos en cada `spawn_vehicle`, HUD táctil.

## Herramienta de validación
Godot headless: `/tmp/godot/Godot_v4.3-stable_linux.x86_64 --headless --path /home/claude/san-pablo-andro/godot3d ...`
Antes del primer uso corre una vez `--headless --editor --quit` para importar/registrar class_name.

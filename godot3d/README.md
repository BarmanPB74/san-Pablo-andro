# San Pablo Andro 3D — Fase 3D (Godot 4.3)

Mundo abierto en Medellín. Primer escenario: **Parque de Boston** (barrio Boston, La Candelaria).
Esta fase incluye solo **personaje, escenario y vehículos**. Todo está construido por código (sin assets externos), así se puede editar desde el teléfono.

## Abrir y jugar
1. Instala **Godot 4.3 o superior** (en Android: Godot Editor desde Play Store o la versión de godotengine.org).
2. Abre la carpeta `godot3d/` como proyecto (`project.godot`). Renderer: **Mobile**.
3. Ejecuta (F5 / ▶). La escena principal es `main.tscn`.

### Controles
| Acción | Teclado / mando | Táctil |
|---|---|---|
| Moverse / dirección | WASD · stick izq. | joystick (mitad izquierda) |
| Cámara | mouse (clic para capturar, Esc libera) · stick der. | arrastrar en la mitad derecha |
| Correr / sprint | Shift | CORRER |
| Saltar · freno de mano | Espacio · A | SALTO · MANO |
| Subir / bajar del auto | F o E · Y | AUTO |
| Acelerar · frenar/reversa (en auto) | W · S | GAS · FRENO |
| Pito | H | PITO |
| Distancia de cámara | C | CAM |

### Hora del día
Selecciona el nodo `Main` en `main.tscn` y cambia `time_of_day`: `overcast_day`, `golden_hour` o `rainy_night`.

## Estructura (un módulo por agente)
| Carpeta | Contenido |
|---|---|
| `character/` | **Andro**: modelo procedural, animación (idle, caminar, correr, sprint, salto, caída/atropello, subir al auto), movimiento con inercia tipo GTA IV, cámara al hombro |
| `world/` | Barrio Boston: Calles 52 (La Playa) a 58 (Echeverri), Carreras 36 a 43 (Girardot), parque con estatua de José María Córdova, iglesia del Sufragio, edificios, avisos, conos tumbables. Ver `world/README_mapa.md` (qué es real y qué es aproximado) |
| `vehicles/` | Taxi, sedán, pickup y buseta con física de suspensión blanda, balanceo, cabeceo, derrapes, cambios automáticos, daño y humo |
| `look/` | Dirección visual tipo "ciudad mojada": cielo nublado, sombras teal, luces ámbar, neones cian/magenta reflejados en charcos, bloom, neblina, lluvia, montañas del valle. Ver `look/README_look.md` |
| `art/palette.gd` | Biblioteca única de materiales |
| `core/`, `ui/` | Entradas, ensamblaje de la escena, HUD y controles táctiles |
| `CONTRACT.md` | Contrato técnico entre módulos (coordenadas, capas de física, APIs) |

## Pruebas automáticas
```bash
godot --headless --editor --quit                      # importar una vez
godot --headless --fixed-fps 60 -s res://tests/integration_test.gd      # caminar → auto → manejar → bajarse
godot --headless --fixed-fps 60 -s res://tests/all_spawns_drive_test.gd # los 10 autos del mapa arrancan
godot --headless --fixed-fps 60 -s res://tests/vehicle_physics_test.gd  # métricas de física por tipo
godot --headless --fixed-fps 60 -s res://tests/character_logic_test.gd
godot --headless --fixed-fps 60 -s res://tests/world_test.gd
```
En headless aparecen errores `Parameter "m" is null`: son del renderer vacío de Godot sin pantalla, no del juego.

## Pendiente (siguientes fases)
- Probar rendimiento real en el teléfono (solo se probó con render por software).
- Tráfico y peatones con IA, motos, semáforos funcionales.
- Fusionar las mallas del personaje para bajar draw calls.
- Conectar con las mecánicas del prototipo 2D (`index.html`): zonas, retenes, letreros de IA, SITVA.

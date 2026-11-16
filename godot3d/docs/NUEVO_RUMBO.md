# Nuevo rumbo — Andro de tela, base plana y puertas-portal (15 nov 2026)

Referencias visuales en `docs/refs/` (83527 Andro, 83528 portal, 83529 planetas, 83530 fuente, 83531 anillos, 83532 cubo).
Nota: `docs/` lleva `.gdignore`, así que Godot no importa esas imágenes.

## Cómo funciona
1. `core/game.gd` crea cámara, jugador, `TransitionFX`, `Stage`, HUD, controles y `Story`, y la historia entra a la primera escena.
2. Cada escena (`stage/scenes/*.gd`) hereda de `StageScene` y en `build()` crea su cielo, niebla, luz, piso, colisiones y un trigger de objetivo.
3. El botón **PUERTA** (`interact`, tecla F/E) conjura un `Portal` 7.5 m delante de Andro si la historia lo permite. Al cruzarlo, el remolino cubre la
   pantalla, el Stage libera la escena vieja, construye la nueva, coloca a Andro en `spawn_pos` y abre el remolino.
4. En cada recuerdo hay que llegar a su zona (objetivo); antes de eso la puerta "no responde" ("Aún no. Hay algo que ver aquí."). Al cumplirlo salen los
   subtítulos de cierre y se habilita la puerta al siguiente recuerdo. Al terminar el último, el Umbral queda en modo libre (la puerta rota por los recuerdos).
   El Umbral es un disco plano envuelto en **niebla gris** (densidad 0.034): el área jugable es de 34 m de radio y el muro invisible queda dentro de la niebla.

## Andro (`character/andro_cloak.gd`)
- **Forma sin rasgos humanos**: no hay cabeza, cuello, hombros ni brazos. Es una esfera mayor INVISIBLE (campo de fuerza, centro y = 1.2, radio 0.56) y, sobre ella,
  **tres capas de tela** superpuestas (interior larga, intermedia, manto exterior corto) que se recogen en una punta arriba. ≈3 900 triángulos, una sola malla;
  el color de vértice `r` guarda la capa (0 / 0.5 / 1) para que el shader las mueva y las oscurezca distinto.
- **Campo de fuerza**: es la cápsula de colisión del jugador (`CAPSULE_RADIUS` = 0.66, `CAPSULE_H_CROUCH` = 1.4) y el sensor de atropello es 0.1 m más ancho;
  las esferas orbitan siempre por fuera (`ORB_CLEARANCE`, se aplica después del golpe). Nada toca la tela. Shader `cloak.gdshader`:
  el peso de movimiento crece hacia el borde; recibe `drift` (arrastre), `flutter` (aleteo) y `flare` (falda abierta); cada capa se arrastra un poco distinto.
- Resorte-amortiguador en GDScript (k = 58, c = 6.5, subpasos de 8 ms): corre → el borde queda atrás (máx. 0.5 m); frena → rebota hacia adelante; gira → se ladea.
- 5 esferas de **cromo plateado en grises** (`orb.gdshader`: metálico, rugosidad 0.06, "estudio" procedural de grises además del reflejo del cielo), con arrastre propio;
  el golpe (`punch`) las dispara al frente y las hace brillar.
- Luz de personaje (Omni sin sombra) para que la tela se lea en escenas oscuras. La capa no recibe sombras (evita acné) pero sí las proyecta.
- `Player` mantiene la física de caminar (escalones, saltos, agacharse, golpear, empujar); el flote (`HOVER_H` = 0.42 m) es solo visual.

## Agregar una escena nueva
1. `stage/scenes/mi_escena.gd` con `class_name MiEscena extends StageScene`; en `_init()`: `title`, `spawn_pos`, `spawn_yaw`, `spawn_pitch`.
2. En `build()`: `make_environment(...)`, piso con `add_ground`, geometría, límites con `add_bounds_circle` o cajas invisibles y `add_trigger("mi_objetivo", pos, tamaño)`.
3. Registrar el id en `Stage.SCENES` y, si es parte de la historia, un capítulo en `Story.CHAPTERS` (intro, objetivo, cierre, `next`).
4. Agregar el punto de llegada a `OBJECTIVE_SPOT` en `tests/stage_test.gd` y correr las pruebas.

## Pruebas y capturas
- `godot --headless --fixed-fps 60 --path godot3d -s res://tests/stage_test.gd` — recorre todo el juego (≈ 75 comprobaciones).
- `... -s res://tests/cloak_test.gd` — malla, esferas, inercia de la tela y golpe (15 comprobaciones).
- Capturas (necesitan GL, p. ej. `xvfb-run`): `tests/stage_shot.gd -- <escena> <png absoluto> <follow|front|wide> [adelante:N | tp:x,y,z,yaw | portal]`, `tests/andro_cloak_shot.gd`, `tests/transition_shot.gd`.

## Límites conocidos
- FPS en el teléfono sin medir (aquí solo GL por software). Si alguna escena baja de 40 FPS, bajar primero: radiance del cielo (`Sky.RADIANCE_SIZE_512` → 256),
  sombras del foco de los anillos, `rings`/`radial_segments` de esferas y tori.
- Sin audio todavía. El rostro de la fuente y las arcadas de la cámara son aproximaciones procedurales, no copias de las imágenes.
- Los vehículos siguen en `vehicles/` pero ninguna escena los usa.

# Nuevo rumbo — Andro de tela, base plana y puertas-portal (15 nov 2026)

Referencias visuales en `docs/refs/` (83527 Andro, 83528 portal, 83531 anillos; 83529 planetas, 83530 fuente y 83532 cubo son de dimensiones que se eliminaron el 16 nov).

> **16 nov 2026:** el Umbral pasa a ser un *centro de habilidades* (viajar entre dimensiones). Se eliminaron Planetas, Fuente y Cubo; quedan el Umbral, la Cámara de los Anillos y la nueva **Casa**. Ver la sección *La Casa* abajo y `ESTADO.md`.
Nota: `docs/` lleva `.gdignore`, así que Godot no importa esas imágenes.

## Cómo funciona
1. `core/game.gd` crea cámara, jugador, `TransitionFX`, `Stage`, HUD, controles y `Story`, y la historia entra a la primera escena.
2. Cada escena (`stage/scenes/*.gd`) hereda de `StageScene` y en `build()` crea su cielo, luz, piso, colisiones y un trigger de objetivo.
3. El botón **PUERTA** (`interact`, tecla F/E) conjura un `Portal` 7.5 m delante de Andro si la historia lo permite. Al cruzarlo, el remolino cubre la
   pantalla, el Stage libera la escena vieja, construye la nueva, coloca a Andro en `spawn_pos` y abre el remolino.
4. Hoy (provisional, hasta la rueda de mapas de la fase 2): desde el Umbral el portal lleva al siguiente de `Story.MAPS` (casa, anillos, casa…) y desde cualquier mapa
   vuelve al Umbral. Los capítulos con objetivo siguen soportados por `Story` pero ya no se usan.
   **El Umbral** es una dimensión vacía: un suelo divino de mármol negro azulado, pulido, con incrustaciones de oro (`divine_floor.gdshader`: rosa de los vientos en el centro, anillos dobles,
   estrella de 12 puntas, rosetón, arcos, franja de signos y borde triple con marcas; más allá del borde los anillos y rayos dorados se desvanecen hacia el horizonte) bajo un
   cielo azul de amanecer con nubes (`umbral_sky.gdshader`: cúmulos y cirros rosados hacia donde amanece, **sin disco de sol**). **Sin niebla** (`fog_enabled = false`); el piso lejano se funde
   con el color del horizonte. La luz viene del cielo (el sol direccional está en energía 0 para que no deje un destello en el suelo pulido). Área jugable de 34 m (muro invisible dentro del borde dorado).
   **No hay objetos**: Andro creará lo que necesite (diseño pendiente). La puerta de prueba que se conjura al abrir el capítulo es provisional.

## Andro (`character/andro_cloak.gd`)
- **Forma sin rasgos humanos** (ref. `84070`): no hay cabeza, cuello, hombros ni brazos. Es una esfera mayor INVISIBLE (campo de fuerza, centro y = 1.45, radio 0.56)
  cubierta por una **cúpula lisa** de tela; de ella cae una **capa interior** larga (dobladillo en puntas) y encima un **manto exterior abierto al frente**:
  la abertura nace a ~32° del punto más alto, es ancha en el ecuador y se estrecha hacia abajo. Ribetes ornamentados (enredadera y hojas, procedurales en el shader)
  en los bordes de la abertura y en el dobladillo, y un brocado suave sobre el manto. ≈3 150 triángulos, una sola malla; color de vértice: r = capa, g = distancia al borde,
  b = distancia al dobladillo, a = apertura (el shader dibuja los ribetes con eso).
- **Campo de fuerza**: es la cápsula de colisión del jugador (`CAPSULE_RADIUS` = 0.66, `CAPSULE_H_CROUCH` = 1.4) y el sensor de atropello es 0.1 m más ancho;
  las esferas orbitan siempre por fuera (`ORB_CLEARANCE`, se aplica después del golpe). Nada toca la tela. (No subir el radio por encima de ~0.7: la parte baja de la cápsula
  es una esfera y deja de subir sardineles de 0.35 m; si hace falta más, cambiar la cápsula por un cilindro.)
- Resorte-amortiguador en GDScript (k = 58, c = 6.5, subpasos de 8 ms): corre → el borde queda atrás (máx. 0.5 m); frena → rebota hacia adelante; gira → se ladea.
- 5 esferas de **cromo plateado en grises** (`orb.gdshader`: metálico, rugosidad 0.06, "estudio" procedural de grises además del reflejo del cielo), con arrastre propio y deriva natural e independiente (cada una adelanta/se retrasa, respira y sube/baja con frecuencias distintas; sin estelas ni rieles);
  el golpe (`punch`) las dispara al frente y las hace brillar.
- Luz de personaje (Omni sin sombra) para que la tela se lea en escenas oscuras. La capa no recibe sombras (evita acné) pero sí las proyecta.
- `Player` mantiene la física de caminar (escalones, saltos, agacharse, golpear, empujar); el flote (`HOVER_H` = 0.42 m) es solo visual.

## Agregar una escena nueva
1. `stage/scenes/mi_escena.gd` con `class_name MiEscena extends StageScene`; en `_init()`: `title`, `spawn_pos`, `spawn_yaw`, `spawn_pitch`.
1b. Si la escena es cerrada, ajustar `portal_size` y `portal_distance` en `_init()` (el portal mide alto + 1.0 m con su marco).
2. En `build()`: `make_environment(...)`, piso con `add_ground`, geometría, límites con `add_bounds_circle` o cajas invisibles y `add_trigger("mi_objetivo", pos, tamaño)`.
3. Registrar el id en `Stage.SCENES` y, si es parte de la historia, un capítulo en `Story.CHAPTERS` (intro, objetivo, cierre, `next`).
4. Agregar el punto de llegada a `OBJECTIVE_SPOT` en `tests/stage_test.gd` y correr las pruebas.

## Pruebas y capturas
- `godot --headless --fixed-fps 60 --path godot3d -s res://tests/stage_test.gd` — recorre todo el juego (≈ 75 comprobaciones).
- `... -s res://tests/cloak_test.gd` — malla, esferas, inercia de la tela y golpe (25 comprobaciones).
- Capturas (necesitan GL, p. ej. `xvfb-run`): `tests/stage_shot.gd -- <escena> <png absoluto> <follow|front|wide> [adelante:N | tp:x,y,z,yaw | portal]`, `tests/andro_cloak_shot.gd`, `tests/transition_shot.gd`.

## Límites conocidos
- FPS en el teléfono sin medir (aquí solo GL por software). Si alguna escena baja de 40 FPS, bajar primero: radiance del cielo (`Sky.RADIANCE_SIZE_512` → 256),
  sombras del foco de los anillos, `rings`/`radial_segments` de esferas y tori.
- Sin audio todavía. Las arcadas de la cámara de anillos son una aproximación procedural, no una copia de la imagen.
- Los vehículos siguen en `vehicles/` pero ninguna escena los usa.

## La Casa (`stage/scenes/house_scene.gd` + `stage/house/`, id `casa`)
La casa de Andro cuando era un niño humano. **Es un recuerdo: no tiene exterior** (ni cielo, ni sol, ni patio abierto); se entra por un portal al vestíbulo y se recorre de cuarto en cuarto. Todo por código.
- **Estilo**: palacio gótico sobrio y poco decorado; piedra gris fría con juntas, vigas de madera oscura, arcos apuntados, ventanales ciegos (vidrio oscuro con un resplandor frío), pilastras, cornisas, candelabros y velas. Colores solo góticos: grises, negro, vino y morado muy apagados, bronce deslucido. Ambiente gris frío (`adjustment_saturation` 0.72, niebla oscura): "casi sin color, una sombra del recuerdo". Marcos de cuadro vacíos en las paredes (recuerdos que aún no están).
- **Plano** (cada cuarto es un espacio aparte; dimensiones x · alto · fondo en m): vestíbulo 16·11·20 (llegada del portal; 4 columnas con arcos, candelabro colgante, braseros) → **sala** 18·9·16 (chimenea, sofás, librerías) → **patio interior** 24·14·24 (claustro de columnas, fuente seca con agua negra, árbol seco, óculo de luz fría; es un atrio cerrado, sin cielo) · **comedor** 16·8·14 (mesa larga con 10 sillas, chimenea) → **cocina** 14·7.5·12 · **galería** 34·8·9 (alfombra, candelabros, 6 puertas) → **habitaciones 1–4** 12·6.5·12 (cama, mesillas, ropero, escritorio) y **baño** 10·6.5·12 (bañera de piedra, lavamanos, espejo). Las habitaciones son genéricas a propósito: la historia las llenará.
- **Un cuarto a la vez**: `HouseScene.load_room(id)` libera el cuarto actual y construye el siguiente. Cada puerta es un arco de 3.2 m de luz con un **velo de bruma** (`memory_veil.gdshader`, opaco y barato) que oculta el cuarto vecino; con un tope de colisión justo detrás. Al pegarse al velo (`door_crossed`), un fundido gris tapa la pantalla (0.25 s), se hace el cambio, Andro reaparece a 2.8 m de la puerta de regreso mirando hacia dentro y el fundido se abre (0.5 s); el HUD muestra el nombre del cuarto (`room_changed`). El plano y las puertas están en `HouseRooms.DEFS`; todas las puertas tienen retorno (lo comprueba `house_test`).
- **Medidas para Andro** (cápsula de 1.32 m de ancho y 1.86 m de alto, flota): puertas 3.2 m de luz y 4.4 m de alto, techo mínimo 6.5 m (`HouseRooms.MIN_CEILING`, cabe el portal de 2.4 × 3.6 m + marco), ningún paso de menos de 1.5 m entre muebles.
- **Rendimiento**: sin cielo, sol, sombras ni brillo; cada cuarto se funde en ≈10 mallas (una por material) y colisiones en un solo `StaticBody3D`; ≤ 5 luces Omni sin sombra por cuarto (el móvil admite 8 por objeto y el portal y la luz de Andro cuentan 2); texturas procedurales compartidas (se generan una vez). Las caras de arcos y ventanales se arman como `ArrayMesh` directo (`HouseBuilder._tri`/`quad`): con `SurfaceTool` quedaban negras.
- **Agregar un cuarto**: una entrada en `HouseRooms.DEFS` (dimensiones y puertas con su retorno), una función `_mi_cuarto(b)` en `house_rooms.gd` y una línea en `make()`. Las chimeneas (`hearth`) y `reserve()` se llaman antes de `_shell` para que no haya ventanas encima.
- Pruebas: `tests/house_test.gd`; capturas: `tests/house_room_shot.gd`.

## Pendiente (hoja de ruta, 16 nov)
- **F2** rueda circular de mapas (estilo GTA V; mapas bloqueados hasta pasar su historia) · **F3** poderes: carga de energía tipo ki, barra de magia por hechizo (empieza en 50 % mejorable con puntos, se recarga sola y rápido), bola de fuego que sale de las esferas de poder · **F4** ~5 dimensiones · **F5** historia.

## Pendiente de la versión anterior (sigue vigente)
- Cómo conjura Andro los portales (gesto, efecto, sonido) y cómo se eligen los destinos.
- Diálogos, historia, escenarios nuevos, y los objetos que Andro puede crear en el Umbral.
- Medir FPS en el teléfono (Compatibility): lo más caro del Umbral es el shader del piso dorado (muchas líneas por pixel); si hace falta, quitar la franja de signos o el rosetón en `divine_floor.gdshader`.
- `stage/sky_orbs.gd` y `stage/smoke_fx.gd` (esferas de energía y humo del Umbral anterior) quedan sin usar, por si se quieren en otra escena.

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

## La Casa (`stage/scenes/house_scene.gd`, id `casa`)
La casa de Andro cuando era un niño humano. Un piso, todo por código, plano rectangular (el plano en ASCII está en el encabezado del script):
- Casa x ±12, z ±8 (24 × 16 m; -Z = norte). Norte: habitación 1, habitación 2, baño, habitación 3, habitación 4 (4.8 × 5.8 m cada una). Centro: pasillo de 2.2 m con una puerta a cada cuarto.
  Sur: sala (10 m), comedor (8 m) y cocina (6 m), con puerta de entrada y puerta grande al **patio** (sur: lote de 44 × 50 m con muro perimetral, terraza y camino de piedra, 3 árboles y matas).
- **Medidas pensadas para Andro** (campo de fuerza = cápsula de 1.32 m de ancho y 1.86 m de alto, y flota): puertas 2.0 × 2.8 m, techo a 3.6 m, ningún paso de menos de 1.5 m entre muebles. Portales de 2.2 × 2.4 m (3.4 m con marco).
- Aparece en la sala (-6.5, 4.5) mirando al este. Ventanas con vidrio que bloquea (la cápsula no cabe por ellas). Mobiliario básico (sofá, mesa, camas, closets, cocina, baño); los objetos de la historia se agregan después.
- Aspecto: texturas procedurales (yeso, tablas, baldosas, pasto) con mapeo triplanar en el mundo; ambiente cálido, sol por el sureste con sombras y una luz cálida por cuarto.
- **Rendimiento**: la geometría estática se funde en una malla por (zona de 6 m × material) y las colisiones son cajas en un solo `StaticBody3D`. Las 10 luces Omni no tienen sombra y alcance corto;
  el móvil admite 8 luces por objeto y el portal y la luz de Andro también cuentan, por eso ninguna malla debe ver más de 6 (lo comprueba `house_test`). El techo y el tejado van en la capa visual 2 y las luces solo alumbran la capa 1.
- Pruebas: `tests/house_test.gd` (conectividad con la cápsula real, luces por malla, portales). Vista en planta sin techo: `tests/house_plan_shot.gd`.

## Pendiente (hoja de ruta, 16 nov)
- **F2** rueda circular de mapas (estilo GTA V; mapas bloqueados hasta pasar su historia) · **F3** poderes: carga de energía tipo ki, barra de magia por hechizo (empieza en 50 % mejorable con puntos, se recarga sola y rápido), bola de fuego que sale de las esferas de poder · **F4** ~5 dimensiones · **F5** historia.

## Pendiente de la versión anterior (sigue vigente)
- Cómo conjura Andro los portales (gesto, efecto, sonido) y cómo se eligen los destinos.
- Diálogos, historia, escenarios nuevos, y los objetos que Andro puede crear en el Umbral.
- Medir FPS en el teléfono (Compatibility): lo más caro del Umbral es el shader del piso dorado (muchas líneas por pixel); si hace falta, quitar la franja de signos o el rosetón en `divine_floor.gdshader`.
- `stage/sky_orbs.gd` y `stage/smoke_fx.gd` (esferas de energía y humo del Umbral anterior) quedan sin usar, por si se quieren en otra escena.

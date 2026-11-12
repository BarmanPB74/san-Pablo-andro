# ESTADO — San Pablo Andro 3D (leer esto primero)

Una sola página para empezar cada sesión sin releer todo el proyecto.
Actualiza la sección "Última sesión" al terminar cada paso del plan.

## Qué es
Juego 3D en Godot 4.3 (renderer Mobile), barrio Boston de Medellín. Todo se construye por código GDScript.
Reglas globales, capas de física, grupos y entradas: `CONTRACT.md` (71 líneas).
Plan gráfico anterior (fases 1-5): `PLAN_GRAFICOS.md`. El plan vigente está en Obsidian (fases 2.x a 10.x).

## Mapa de carpetas
- `core/` entradas y juego · `character/` jugador, modelo y cámara · `vehicles/` autos y fábrica
- `world/` mapa (`boston_district.gd`) y `world/props/` (árboles, postes, semáforos, edificios, mobiliario)
- `art/` paleta, materiales y texturas PBR · `look/` cielo, lluvia, post-proceso · `ui/` HUD y controles táctiles
- `tests/` pruebas headless y capturas (`integration_test.gd`, `character_logic_test.gd`, `vehicle_physics_test.gd`, `world_test.gd`)

## Estado (9 nov 2026)
- Hecho: texturas PBR (fase 1), modelos (fase 2), personaje que camina/corre/salta, entrar y manejar autos.
- Rendimiento medido en el editor del teléfono: ~51 FPS en el parque, ~78 FPS en la calle.
- Sin APK todavía (a propósito): se juega desde el editor de Godot en el teléfono.

## Última sesión (11 nov 2026) — Fase 4.2: personaje y barrio según las láminas "arcilla gótica"
- Pablo trajo 6 láminas de referencia (hoja de personaje, texturas, mapa gótico, calle, optimización móvil).
- Personaje (solo modo plastilina, `player_model.gd`): cabeza ×1.6, ojos redondos enormes con pupila pequeña, ojeras malva,
  cejas gruesas, orejas salidas, saco ciruela CERRADO (sin camisa blanca), pantalón más oscuro, pelo café-ciruela,
  zapatos gris-café, bandolera cruzada con bolso (`_clay_satchel`) y vivo ocre en el bolsillo.
- Barrio: calzadas de adoquín malva (`MatPaving.clay_cobble`), prado verde musgo, ventanas encendidas ámbar (se arregló la
  emisión con textura en `clay.gdshader`; 60 % de ventanas prendidas), ladrillo granate apagado con junta visible
  (`tex_blur` 0.35), postes/rejas de hierro oscuro, luz más neutra para que se lean verde y ladrillo, DOF más suave.
- Capturas nuevas: `tests/game_shot.gd` modos `vista` y `calle`; retrato `CLAY=1` (lineup/face).
- Pruebas PASS (integration, character_logic, gothic_clay_adapter). Sin probar en el teléfono.
- Falta frente a las láminas: edificios siguen siendo los de Boston (no casas góticas con torres/tejados de pizarra), faroles
  tipo linterna, cementerio, HUD de miedo/nivel, pelo en mechones más gruesos, nudo de la bufanda, peso de 8 000 tris/LOD.

## Sesión anterior (11 nov 2026) — Fase 4.1: adaptador "arcilla gótica" (port del script de Unity de Pablo)
- Pablo trajo `GothicClayCharacterAdapter.cs` (Unity/C#). No corre en Godot: se portó a `character/gothic_clay_adapter.gd`
  (`GothicClayAdapter`) con los mismos parámetros, colores, reglas por nombre y generadores de textura (normal de arcilla y
  bufanda a rayas). Se rige por rugosidad = 1 − smoothness (0.88 mate; ojos 0.55).
- Andro en modo plastilina lo usa solo: `player_model.gd` toma su paleta (piel 0.82/0.75/0.70, saco 0.11, pelo 0.08,
  bufanda verde 0.13/0.36/0.21 y crema, zapatos café) y agrega el nodo adaptador, que deja mate la ropa/piel y brillantes
  los ojos (nuevo material `_eye()`). El personaje no pasa por la gradación gris→rosa (camisa y bufanda quedan blancas).
- `replace_with_clay_glb()` listo para `personaje_arcilla_gotica.glb` (esconde mallas, mantiene física/animación, pega "Head"
  al pivote de la cabeza) pero SIN probar: el .glb no llegó. Ponerlo en `res://character/` y fijar `gothic_clay_model_path`.
- Prueba nueva: `tests/gothic_clay_adapter_test.gd` (PASS). integration y character_logic PASS.

## Sesión anterior (11 nov 2026) — Fase 4.0: estilo PLASTILINA (stop-motion)
- Pablo trajo una imagen propia (pueblo de plastilina de noche: iglesia de ladrillo, árboles retorcidos, rejas de lanza,
  faroles ámbar, cielo morado, muchacho con bufanda verde/blanca, botones de piedra) y pidió transformar todo el juego a ese estilo.
- Nuevo preset `plastilina` (ahora es el valor por defecto de `time_of_day` en `core/game.gd`). Para volver al look anterior:
  poner `rainy_night` / `overcast_day` en el nodo Main; todo lo de plastilina se apaga solo.
- `look/clay_style.gd` (`ClayStyle`): con `ClayStyle.enabled = true` (lo fija game.gd ANTES de construir) recorre el árbol y
  cambia cada material por `look/clay.gdshader`: mismo color/patrón difuminado + presiones de pulgar y huellas
  (`art/tex/clay/clay_detail.png`, generador `tools/texgen/clay.py`), brillo ceroso, y gradación de color (naranja→ladrillo
  frambuesa, grises→rosa ladrillo apagado, verdes→musgo). También convierte lo que se cree después (autos, conos), entibia
  las luces y pone una luz de relleno sin sombra que sigue a la cámara. Deja igual vidrios, letreros sin luz y cielo.
- Cambios de forma (solo en modo plastilina): árboles sin hojas con tronco torcido y ramas en rizo (`Trees._clay_tree`),
  rejas de hierro forjado con punta de lanza (`ParkFurniture._fence_segment_clay`), iglesia de ladrillo, senderos y
  plazoletas de ladrillo rojo (`MatPaving.hex/herringbone`, `MatStone.laja_plaza`), personaje con cabeza ×1.34, manos ×1.22,
  ojos saltones con párpado y cejas gruesas, piel beige y bufanda tejida a rayas con flecos (`player_model.gd`, `_clay_eye`,
  `_clay_scarf`).
- Controles táctiles: discos de piedra modelada con flechas y letras doradas (`ui/clay/*.png`, generador
  `tools/texgen/ui_clay.py`); joystick con base fija abajo a la izquierda. `SPA_TOUCH=1` los muestra en escritorio.
- Desenfoque de maqueta (DOF lejano suave) vía `CameraAttributesPractical` del WorldEnvironment (solo presets con `dof_far`).
- Pruebas: integration, character_logic, all_spawns_drive PASS. Capturas con lavapipe (`tests/game_shot.gd` modo `vista`).
- NO probado en el teléfono: medir FPS (el shader de arcilla hace 3 lecturas triplanares + HSV por píxel; el DOF cuesta).
  Si va lento: bajar `dof_amount` a 0 en el preset o `clay_bump`/`clay_cavity`.
- Pendiente del estilo: palmeras y follaje bajo aún con forma realista, ventanas de edificios poco cálidas, prado poco verde.

## Sesión anterior (10 nov 2026) — Fase 3.6: personaje nuevo (traje oscuro, alto y delgado)
- Pablo no quedó contento con Andro y pidió un personaje basado en una ilustración de referencia: hombre alto y delgado, saco
  negro abierto sobre camisa blanca, pantalón entubado, zapatos negros, pelo negro con copete y ojos grandes. Es una versión propia
  adaptada al estilo realista del juego, no un calco de la ilustración (sin cabeza ni cuello exagerados).
- Cambios en `character/player_model.gd`: piezas rehechas (saco con solapas/bolsillos/cuello, camisa con botones y cuello, cinturón,
  pantalón con raya, manos descubiertas, zapatos negros). Piernas +6 cm (`THIGH_LEN` 0.46, `SHIN_LEN` 0.41, `HIPS_HEIGHT` 1.01),
  brazos +10 % (`ARM_K`), cuello más largo, hombros/cintura más estrechos (helper `_sc`). Piel más clara. Ojos más grandes.
- Barba: `BEARD_ON = false` (el concepto va afeitado); poner `true` para recuperarla. El Andro anterior queda en git (commit f260803).
- `player.gd`: `CAPSULE_H` 1.78 → 1.86 y el centro de la cápsula ahora sale de `CAPSULE_H * 0.5` (antes 0.89 fijo; con otra altura
  la cápsula se hundía y fallaba subir sardineles).
- Pruebas: `character_logic_test`, `integration_test`, `all_spawns_drive_test` PASS. Sin probar en teléfono.

## Sesión anterior (10 nov 2026) — Fase 3.5: barba y estilo "tinta y papel"
- Barba completa en Andro: cáscara de pelo con volumen (`_beard_mask`, `BEARD_THICK`, `BEARD_CHIN` en `player_model.gd`):
  mejillas, patillas, bigote y mentón; los labios quedan libres. Ajustable cambiando esas constantes.
- Nuevo preset de ambiente `tinta_y_papel` (`look/second_son_environment.gd`): paleta apagada beige-oliva, sombras suaves,
  contorno de tinta por bordes de luminancia y duotono tinta/papel (shader `post_fx.gdshader`, uniforms `ink_amount`/`paper_amount`;
  en los otros presets valen 0 y no cuestan nada). Para usarlo: `time_of_day = "tinta_y_papel"` en el nodo Game (inspector).
- Referencia de arte: ilustración melancólica de tonos apagados que trajo Pablo; solo se tomó la "vibra" (paleta, tinta, papel).
  No se copió ningún personaje ni se cambiaron proporciones. No medido en teléfono (el post-fx añade 4 lecturas de pantalla).

## Sesión anterior (10 nov 2026) — Fase 3.4: fluidez y realismo del personaje
- Fluidez: la animación ya no corre a 60 Hz de física sino a cada fotograma de pantalla (`Player._process`). El modelo
  interpola posición, giro y velocidad entre los dos últimos ticks de física (`Engine.get_physics_interpolation_fraction`),
  así en 90/120 Hz no hay saltos. La animación es procedural (no hay "fotogramas" fijos): más fotogramas = evaluarla más seguido.
- Movimiento secundario (`_pose_locomotion`): cabeza y cuello reaccionan con retraso a aceleración y giro, la cabeza se
  estabiliza contra el balanceo del torso, hombros con contra-rotación y respiración al caminar.
- Texturas: piel v2 1024 px (poros a 2 escalas, red de pliegues, vellosidad, venitas, rubor y matices; normal_scale 0.85);
  cara con color de vértice (ojeras/cuencas, rubor de pómulo, nariz y orejas más cálidas, sombra bajo la mandíbula);
  ripstop con rejilla más fina y tenue + pliegues finos de uso (también en buzo y cargo); pantalón un poco más claro.
- Pruebas: `character_logic_test`, `integration_test`, `all_spawns_drive_test` PASS. No medido en teléfono (solo lavapipe).

## Sesión anterior (10 nov 2026) — Fase 3.3: personaje (agacharse, golpear, empujar, correr, subir/bajar del auto)
- Agacharse (`crouch`: Ctrl/X/B, botón AGACHAR): alterna; cápsula 1.78 → 1.2 m, cámara baja, velocidad 1.15 m/s,
  no se levanta si hay un techo encima (rayo); correr o saltar lo cancela. Estados nuevos: `crouch`, `crouch_walk`.
- Golpear (`punch`: J/Q/X, botón GOLPE): combo de 3 (jab, cruzado, patada) encadenando toques; asistencia de puntería hacia
  el objeto cercano; cápsula de impacto al frente: lanza conos (RigidBody del grupo `props`), llama `take_hit(dir, power,
  attacker)` en cualquier cuerpo que lo tenga (para peatones futuros) y emite la señal `punched`. No golpea vehículos.
- Empujar: avanzar contra un RigidBody (no vehículo) lo desplaza; si pesa >5 kg el jugador va a ≤1.5 m/s con pose `push`.
- Correr: braceo más amplio, codos más cerrados y más inclinación al trotar. Subir al auto: animación de 0.6 s; bajar: nueva
  animación `exit_vehicle` (0.4 s) en vez de aparecer de golpe.
- Gráficos: chaqueta y pantalón más claros (gris carbón) para que se lean las formas; poses nuevas en el retrato
  (`CHAR_SHOT=actions` en `tests/character_portrait.gd`). Sin cambios de malla.
- Pruebas: `character_logic_test.gd` sección [8] (agacharse, techo bajo, golpe que lanza un cono, combo, empujar caja de 20 kg).
- Sin probar en el teléfono. Falta: puerta del auto que se abre al entrar, golpes contra peatones (aún no existen),
  sonido de golpes, malla más detallada (manos, ropa).

## Sesión anterior (10 nov 2026) — Fase 3.2: colegio, figura del parque, fuente/tarima, texturas
- Colegio "El Sufragio" (`world/props/school.gd`, `_build_school()`): edificio de 4 pisos (39.5 × 13 m) pegado al sur de la
  iglesia, fachada sobre la Cra 39 (x = -51), pañete crema con molduras ocre, portal en arco con puerta de hierro, balcón
  corrido, reja con portón en el antejardín, 2 árboles. La iglesia no cambió. Se quitaron los árboles/bancas viejos de ese
  andén. `_rng.state` se fija al final de `_build_school()` para que el resto del barrio no cambie.
- Figura del parque: la manzana ya no es un cuadrado. Las 4 esquinas tienen **ochava** (`PARK_CUT = 7` m en la línea de
  jardineras; el borde de la manzana se corta en `PARK_OUT_K` y se rellena con andén de concreto + bordillo diagonal).
  Jardineras ahora son polígonos (`_p2park_l_poly` / `_p2park_planter`): tapa triangulada, muro, reja con inglete,
  pilares en esquinas oblicuas. Setos, hiedra, palmas y árboles se adaptaron a la ochava y a las plazoletas.
- Fuente y tarima movidas a **plazoletas circulares** (`PLZ_R = 7.5`, a `PLZ_C = 21` m de la estatua): fuente al OESTE
  (lado iglesia, Cra 39) en (-21, 0); tarima al NORTE (Calle 55) en (0, -21). Cada plazoleta abre una muesca circular en las
  jardineras vecinas, piso de laja irregular, bordillo en los arcos sobre el sendero, 4 bancas de granito en corro, 2 canecas.
  Si todavía se ven mal puestas: cambiar `PLZ_W` / `PLZ_N` / `PLZ_C` / `PLZ_R` / `PARK_CUT` (constantes al inicio de
  `boston_district.gd`); todo lo demás se recalcula.
- Texturas: nuevo set `stone/laja_irregular` (lajas grandes grises con juntas de tierra y pasto, `MatStone.laja_plaza()`);
  `pizarra_lajas` regenerada con lajas alargadas más irregulares y bordes despostillados. Generador: `tools/texgen/stone.py`
  (ahora con `course_layout()` por si se quiere cantería apilada).
- NO probado en el teléfono (Adreno): solo con lavapipe. El contorno exacto del parque real no se pudo verificar (sin acceso a
  mapas): la ochava y las posiciones de las plazoletas son mi mejor lectura de las fotos.
- Siguiente: más juego (peatones, tráfico, misiones) y 2.3 edificios del fondo.

## Sesión anterior (fase 3)
- Manchas negras del follaje: causa hallada = celda 3 del atlas (hoja ancha) casi negra × AO de vértice. Arreglo:
  `tools/texgen/foliage_lift.py` (gamma 0.62 en esa celda; correr después de foliage.py, es idempotente) + piso de albedo
  en `LEAF_SHADER` (`world/props/trees.gd`). Verificado con el renderer Mobile real por software (lavapipe, ver abajo).
  NO se pudo probar en Adreno: falta confirmar en el teléfono. Si siguen: `LEAF_DEBUG = 3/1/2/4` y mandar captura.
- Iglesia: ahora al oeste de la Cra 39 (centro x=-52, z=-20), fachada mirando al este, al parque (`_build_church`,
  `add_col_cyl_xf`). Color del pañete algo más rosado.
- Nuevo `world/props/park_plaza.gd`: fuente de piedra con reja verde y adoquín hexagonal, tarima redonda de dos
  escalones (con colisión inclinada para la pendiente) y león al pie del pedestal de Córdova.
- Técnica de captura barata: `tests/look_shots.gd` (varias cámaras) con
  `xvfb-run godot --rendering-method mobile --rendering-driver vulkan` + `mesa-vulkan-drivers` (lavapipe).
- Pendiente de esta zona: paraderos de bus en Cra 39/38, guadua, sombrillas de vendedores, grano del asfalto,
  auto blanco sin detalle, recuadros cian en avisos, noche sin ver en el teléfono. Siguiente: 2.3 edificios del fondo.

## Sesión anterior
- 2.2 confirmado en el teléfono: 65-83 FPS en calle y parque; luces del parque con `distance_fade`, tope 16;
  `look/contact_shadows.gd` dibuja la base de cada cilindro de colisión registrado.
- Semáforos: no necesitan arreglo (en el video se veían por detrás).

## Pendiente conocido
- Edificios del fondo son bloques (la neblina los disimula).
- Ciudad vacía: sin peatones, tráfico, policías ni ladrones.

## Cómo probar barato
- Pruebas: `godot --headless --path godot3d -s res://tests/integration_test.gd` (debe imprimir `RESULT: PASS`).
- Visual: 2-3 capturas del teléfono, no video.
- `Palette.USE_TEXTURES = false` devuelve el look sin texturas si algo se ve mal.

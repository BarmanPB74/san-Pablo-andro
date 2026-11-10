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

## Última sesión (10 nov 2026) — Fase 3.5: barba y estilo "tinta y papel"
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

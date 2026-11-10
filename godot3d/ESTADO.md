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

## Última sesión (10 nov 2026) — Fase 3: pulir parque y zona
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

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

## Última sesión
- 2.2 confirmado en el teléfono (capturas de día): 65-83 FPS en calle y parque. Las luces y sombras de contacto no
  costaron FPS. La noche aún no se vio en el teléfono, solo en capturas por software (luminancia 13→39).
  Detalle: luces del parque con `distance_fade`, tope 16; `look/contact_shadows.gd` (1 MultiMesh) dibuja la base de cada
  cilindro de colisión registrado en `boston_district.gd`.
- 2.1b (en prueba): las manchas negras del follaje SIGUEN en el teléfono (Mobile/Vulkan) y NO se reproducen en
  el renderer por software (opengl3). Meshes revisados: sin NaN (`tests/foliage_mesh_check.gd`). `LEAF_SHADER` en
  `world/props/trees.gd` reescrito a la defensiva: normal desde un varying (sin voltear cara trasera), sin mapa de
  normales, `shadows_disabled`, pisos de AO y color de vértice, descarta texels casi negros.
  Si SIGUEN: poner `LEAF_DEBUG = 3` (verde = frente, rojo = reverso), mirar una copa y mandar captura; luego 1, 2 y 4.
  Cada modo descarta una causa (reverso, color de vértice, AO, normal). Volver a 0 al terminar.
- Semáforos: no necesitan arreglo (en el video se veían por detrás).
- Visto en las capturas y pendiente: asfalto con grano muy ruidoso junto al sardinel (foto 2), auto blanco sin detalle
  (fase 4/5), recuadros cian en avisos pequeños (¿intencional?).

## Pendiente conocido
- Edificios del fondo son bloques (la neblina los disimula).
- Ciudad vacía: sin peatones, tráfico, policías ni ladrones.

## Cómo probar barato
- Pruebas: `godot --headless --path godot3d -s res://tests/integration_test.gd` (debe imprimir `RESULT: PASS`).
- Visual: 2-3 capturas del teléfono, no video.
- `Palette.USE_TEXTURES = false` devuelve el look sin texturas si algo se ve mal.

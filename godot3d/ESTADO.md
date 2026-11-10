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
- 2.2 (hecho, probado con capturas por software y `integration_test` PASS):
  - Noche (`rainy_night` en `look/second_son_environment.gd`): luna 0.12→0.35, ambiente 1.1→1.6 y más claro,
    niebla más clara, exposición 1.9→2.2. Luminancia media de la captura 13→39 (de 255).
  - Luz por zonas: luces del parque con `distance_fade` (45 m + 15 m), 16 luces máx. (antes 12), más energía.
    Las luminarias de calle y los locales ya tenían fade.
  - Sombras de contacto: `look/contact_shadows.gd` (1 MultiMesh, 1 draw call). `boston_district.gd` registra la base
    de cada cilindro de colisión (troncos, postes, faroles) y las dibuja al final de `_ready()`.
- 2.1: manchas negras del follaje. Texturas OK; se apagó el mapa de normales de la copa (`normal_depth = 0` en
  `LEAF_SHADER`, `world/props/trees.gd`). SIN VERIFICAR en el teléfono. Si siguen: probar `alpha_hash` o revisar
  `look/post_fx.gdshader`.
- Semáforos: no necesitan arreglo (carcasa, 3 lentes con visera, borde reflectivo; el video los mostraba por detrás).
- No medido en el teléfono: FPS tras 2.2 (+4 luces, +1 draw call). Si baja de ~40 FPS, quitar luces del parque primero.

## Pendiente conocido
- Edificios del fondo son bloques (la neblina los disimula).
- Ciudad vacía: sin peatones, tráfico, policías ni ladrones.

## Cómo probar barato
- Pruebas: `godot --headless --path godot3d -s res://tests/integration_test.gd` (debe imprimir `RESULT: PASS`).
- Visual: 2-3 capturas del teléfono, no video.
- `Palette.USE_TEXTURES = false` devuelve el look sin texturas si algo se ve mal.

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
- 2.1: manchas negras en copas de árboles. Las texturas del follaje están bien (alfa y AO revisados).
  Se apagó el mapa de normales de la copa (`normal_depth = 0` en `LEAF_SHADER`, `world/props/trees.gd`).
  SIN VERIFICAR en el teléfono. Si siguen las manchas, la causa es otra: probar `ALPHA_SCISSOR` → `alpha_hash`
  o revisar el post-proceso (`look/post_fx.gdshader`).
- Semáforos: no necesitan arreglo. Tienen carcasa, 3 lentes con visera y borde reflectivo; en el video se
  veían por detrás.

## Pendiente conocido
- Edificios del fondo son bloques (la neblina los disimula). Noche muy oscura.
- Ciudad vacía: sin peatones, tráfico, policías ni ladrones.

## Cómo probar barato
- Pruebas: `godot --headless --path godot3d -s res://tests/integration_test.gd` (debe imprimir `RESULT: PASS`).
- Visual: 2-3 capturas del teléfono, no video.
- `Palette.USE_TEXTURES = false` devuelve el look sin texturas si algo se ve mal.

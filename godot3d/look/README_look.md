# LOOK — "ciudad mojada" (teal + ámbar + neón)

## Archivos
| archivo | qué hace |
|---|---|
| `second_son_environment.gd` | `StreetLook`: WorldEnvironment, sol PSSM, LUT 3D, presets, ReflectionProbe que sigue a la cámara |
| `sky_clouds.gdshader` | cielo con nubes fbm, sin TIME (el radiance solo se recalcula al cambiar preset) |
| `valley_backdrop.gd` + `valley.gdshader` | `ValleyBackdrop`: 2 anillos de montañas low-poly (r=1100/1900 m), neblina propia, luces de laderas de noche |
| `wet_asphalt.gdshader` | piso mojado: charcos fbm, roughness 0.04 en charco, grano/normal, fresnel de cielo, ondas de lluvia, losas opcionales |
| `rain.gd` | `RainFX`: gotas + salpicaduras GPUParticles3D que siguen a la cámara |
| `post_fx.gd` + `post_fx.gdshader` | `PostFX`: viñeta, grano, aberración cromática (CanvasLayer 1, debajo del HUD) |

Prueba: `tests/scenes/look_test.tscn` (preset = 4º argumento de usuario, o teclas 1/2/3, P = post-fx).
Chequeo de Palette: `godot --headless -s res://tests/palette_check.gd`.

## Reglas para los otros agentes
- Cámara: `far >= 2400` para ver las montañas.
- Neones: `Palette.neon(Palette.NEON_CYAN | NEON_MAGENTA | NEON_AMBER, 4.0)`. Para que se reflejen en el piso
  pon una `OmniLight3D` del mismo color a ~1 m del letrero (energía 2–3, rango 8–10, sin sombra).
- Faroles: `Palette.lamp_bulb()` + OmniLight ámbar `Color(1,0.68,0.38)`, energía 3–4, rango 12–14.
- Pisos: `asphalt()`, `sidewalk()` y `plaza_tile()` son ShaderMaterial (no castear a StandardMaterial3D).
  Usan coordenadas de mundo: no necesitan UVs y no se ve repetición entre bloques.
- El clima de los pisos lo fija StreetLook con `Palette.set_weather()`; no lo llames desde otros módulos.

## Diferencias Compatibility (capturas con llvmpipe) vs Mobile (Vulkan, teléfono)
- **HDR / glow**: Compatibility trabaja en LDR, por eso StreetLook multiplica `glow_hdr_threshold` × 0.8 cuando no
  hay RenderingDevice. En Mobile el búfer es HDR de rango limitado (≈0–2 en 4.3): el bloom de neones será **más
  fuerte y más amplio** que en las capturas. Si satura, baja `glow` del preset (0.1–0.2) antes de tocar el umbral.
- **Tonemap**: se usa FILMIC (por canal). ACES se probó y blanquea los neones cian/magenta (cruce de canales).
- **Niebla**: el exponencial se ve casi igual; el height fog en Mobile es algo más denso cerca del piso.
- **Reflection probe**: se ve en ambos; en Mobile la resolución viene de
  `rendering/reflections/reflection_atlas/reflection_size` (256 por defecto, suficiente).
- **Partículas**: GPUParticles3D funciona en ambos; en el teléfono la lluvia se ve más nítida (MSAA/resolución).
- Sin SSR/SSAO/SSIL/SDFGI/volumetric fog: no existen en Mobile y no se usan.

## Valores clave por preset (ver `PRESETS` en second_son_environment.gd)
| | overcast_day | golden_hour | rainy_night |
|---|---|---|---|
| sol elev/az, energía | 52°/-35°, 1.0 | 8°/-100° (oeste), 1.7 ámbar | luna 38°, 0.12 azulada |
| exposición (Filmic) | 1.1 | 1.2 | 1.9 |
| glow intensidad / umbral | 0.55 / 1.0 | 0.7 / 0.95 | 1.25 / 0.85 |
| contraste / saturación | 1.18 / 1.0 | 1.2 / 1.1 | 1.18 / 1.15 |
| fog densidad | 0.0045 | 0.0035 (+sun scatter 0.4) | 0.010 + height 0.08 |
| wetness / rain | 0.7 / 0 | 0.5 / 0 | 1.0 / 1.0 |
| lluvia FX | 0 | 0 | 0.85 |
| viñeta / grano | 0.30 / 0.025 | 0.35 / 0.03 | 0.45 / 0.04 |

## Rendimiento móvil
- Sombras: 1 sola luz direccional, PSSM 2 cortes, 120 m, atlas 2048 de 16 bits, soft-low, sin blend de cortes.
- Cielo: radiance 128, sin TIME → costo cero por frame.
- LUT 3D 24³ generado una vez por preset (cacheado, ~30 ms la primera vez).
- ReflectionProbe UPDATE_ONCE: solo re-renderiza al moverse 40 m (snap). Si hay tirones al conducir rápido,
  sube `probe_snap` o pon `follow_reflection_probe = false` (los charcos quedan con reflejo de cielo/fresnel).
- Piso mojado: shader procedural (~12 lecturas de ruido por píxel, 0 texturas). Es el costo principal de fill-rate.
- Lluvia: 3500 gotas + 500 salpicaduras máx., `amount_ratio` según intensidad (no reinicia el sistema).
- Post-FX: 1 copia de pantalla + 3 lecturas por píxel. `set_post_fx_enabled(false)` o `set_low_quality(true)`.

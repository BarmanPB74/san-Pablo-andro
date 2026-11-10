# Mapa: Barrio Boston (Medellín) — `world/boston_district.gd`

`BostonDistrict` (Node3D) construye todo en `_ready()` (~0.6 s en escritorio, semilla fija `SEED = 1955`, determinista).

## Coordenadas
- Origen (0,0,0) = pie de la estatua de José María Córdova, a nivel del andén del parque. -Z = norte, +X = este.
- Pendiente: el terreno sube hacia el **este** 4 % (`SLOPE`). Andén: `walk_y(x) = 0.04·x`; calzada: `road_y(x) = walk_y(x) - 0.15`.
  Toda la calzada es un único plano inclinado (cruces planos, sin escalones); las manzanas son losas de 0.15 m encima (el borde es el sardinel).
- Cuadrícula con ejes cada 80 m (`BLOCK`):
  - Carrera n → `x = (38.5 - n)·80` · Cra 36 = +200, 37 = +120, **38 = +40**, **39 = -40**, 40 = -120, 41 = -200, 42 = -280, **43 Girardot = -360**
  - Calle n → `z = (54.5 - n)·80` · Cl 58 Echeverri = -280, 57 = -200, 56 = -120, **55 Perú = -40**, **54 Caracas = +40**, 53 = +120, **52 La Playa = +200**
- Vías normales: calzada 7 m (2 carriles), andén 2.5 m. Cra 43 y Cl 52: 2 calzadas de 7 m + separador verde de 4 m (cortado en cada cruce), andén 3 m.
- Límites: x ∈ [-410, 245], z ∈ [-325, 262]. Muros invisibles en los bordes + piso de seguridad en y = -40; las manzanas del borde tienen un volumen alto de cierre.
- Helpers estáticos públicos: `BostonDistrict.walk_y(x)`, `road_y(x)`, `carrera_x(n)`, `calle_z(n)`.

## Lugares
| Lugar | Posición |
|---|---|
| Parque de Boston | manzana x ∈ [-34, 34], z ∈ [-34, 34] (Cra 38–39, Cl 54–55). Plaza central 24×24 m, caminos en cruz, 4 jardineras en L elevadas 0.35 m con ochava en las esquinas y 2 plazoletas circulares (fuente al oeste en (-21, 0), tarima al norte en (0, -21)), ~36 árboles (incl. guayacanes amarillos/rosados), 16 bancas, 12 faroles (6 con OmniLight cálida sin sombra), 5 carritos de comida, placas de nomenclatura en las 4 esquinas. |
| Monumento a Córdova | (0,0,0), mira al sur (+Z). `world/props/monument.gd`: figura de pie en bronce oscuro (2.5 m, casaca con faldones, sable, brazo derecho alzado) sobre pedestal de mármol blanco hasta y = 4.28 (gradas, dado con placa "JOSÉ MARÍA CÓRDOVA", cuerpo esbelto), seto redondo (r 2.45–3.75), bordillo de granito y reja verde (r 4.15). Colisión: cilindro r 4.2 + caja del pedestal. |
| Iglesia del Sufragio | Cuadra entre Cra 39 y Cra 40, sobre la Cl 55: al oeste de la Cra 39, centro (x = -52, z = -20), fachada sobre la Cra 39 mirando al **este**, hacia el parque; nave larga hacia el oeste. Nave 18×42 m, dos torres de ~36 m con campanario y remate piramidal de piedra con pináculos, pórtico con arquivoltas sobre columnillas, rosetón con tracería, ajimeces, arquillos lombardos, reloj en la torre oriental, ábside con contrafuertes, escalinata de granito de 6 peldaños (mallas en `world/props/church.gd`; colisiones en `_build_church`). Sin plazuela propia: la escalinata da a la acera de la Cra 39. |
| Colegio El Sufragio | Pegado al sur de la iglesia, de cara a la Cra 39: x ∈ [-64, -51], z ∈ [-6, 33.5], 4 pisos (`world/props/school.gd`, `_build_school()`); antejardín con reja y portón de 4.6 m, balcón corrido sobre el portal, rótulo "COLEGIO EL SUFRAGIO". |
| Teatro (representa al Pablo Tobón Uribe) | Al sur de La Playa, junto a la Cra 40: x ∈ [-112, -60], z ∈ [222, 258], marquesina con aviso "TEATRO". |
| Obras con conos | Cl 55 frente a la cuadra de la iglesia (x -100…-89) y Cra 38 (z -70…-77). |

## Spawns
- `spawn_player`: (0, 0.1, 9) frente a la estatua (lado sur).
- `spawn_vehicle` (10), estacionados contra el sardinel, tráfico por la derecha, **frente = -Z local del Marker3D** (convención `look_at`); `get_meta("kind")`:
  taxi Cl55 (x -20, hacia el este) · sedan Cl55 (x 12, oeste) · taxi Cl54 (x 16, este) · pickup Cl54 (x -18, oeste) · sedan Cra38 (z 14, sur) · taxi Cra39 (z -14, norte) · pickup Cra39 (z 18, sur) · **buseta La Playa** (x -10, este) · **buseta Cra 43** (z 10, sur) · sedan Cl58 (x 20, este).
  La altura del marker es calzada + 0.3 m.

## Colisión (capa 1)
- Calzada: una sola `BoxShape3D` inclinada (sin juntas internas). Manzanas, sardineles, separadores y jardineras: un `ConcavePolygonShape3D`.
- Edificios: `BoxShape3D` por edificio. Postes, árboles, faroles, semáforos, canecas, hidrantes, bancas: cilindros/cajas simples.
- Conos: `RigidBody3D` capa 4 (máscara 1|2|3|4), grupo `"props"`, arrancan dormidos.

## Rendimiento
- Geometría estática fusionada con SurfaceTool por (trozo 2×2 del mapa, material). Sin sombras propias: cada trozo tiene un **proxy de sombra** (`SHADOWS_ONLY`) que junta todo lo que proyecta sombra → el pase de sombras cuesta ~4 draw calls por división.
- MultiMesh: ventanas (≈8 200 oscuras + ≈3 900 iluminadas), troncos, copas (verde/amarillo/rosado), bombillos.
- Label3D solo en ~33 avisos de vías comerciales cerca del parque + placas, con `visibility_range_end = 110`.
- Medido (xvfb, GL Compatibility, sol con sombras PSSM 4): **~120–250 draw calls** según la vista (calle de noche 117, parque 253, aérea 238); sin sombras ~190 en la vista más cargada. ~0.9–1.3 M primitivas por cuadro incluyendo sombras (~360 k sin sombras).

## Real vs. aproximado
**Basado en datos reales:** dirección del parque (Cra 38 #54-97) y su manzana entre Cl 54/55 y Cra 38/39; estatua de José María Córdova en el parque; Iglesia de Nuestra Señora del Sufragio, neorrománica, Calle 55 #39-61 (al lado del parque); nombres Caracas (Cl 54), Perú (Cl 55), Echeverri (Cl 58), La Playa (Cl 52, bulevar arborizado), Girardot (Cra 43, vía ancha); orientación de la nomenclatura de Medellín; el barrio sube hacia el oriente; tipologías (casas de 2 pisos con balcón y teja, edificios de ladrillo, locales con avisos, rejas, cables aéreos, guayacanes).

**Aproximado / inventado:** cuadrícula perfecta de 80 m (las cuadras reales son irregulares y no todas las carreras son continuas); pendiente uniforme 4 % solo en X; anchos de vía; disposición interna del parque, número de árboles; el monumento es una figura de pie sobre pedestal blanco según las fotos de referencia, pero la pose y la escultura son genéricas (no es un retrato); posición exacta de la iglesia (su fachada sí mira al parque, como en las fotos); forma y posición del teatro; los edificios son procedurales; todos los nombres de locales son inventados (ninguna marca real); ubicación de semáforos, postes, hidrantes y canecas.

## Pruebas
- `tests/world_test.gd` (headless): spawns, ~22 500 raycasts sobre todas las calzadas (sin huecos, altura exacta), rejilla de 5 m en todo el mapa, caja tipo auto bajando la Cl 55 y por la Cra 38 (sin frenazos en cruces), esfera que rueda sola cuesta abajo, conos en capa 4.
- `tests/world_stats.gd`: triángulos por material, instancias de MultiMesh, Label3D, shapes.
- `tests/world_shot.gd` + `tests/scenes/world_preview.tscn`: capturas con cámara por argumentos (`day|night`, fov, `noshadow`).

## Jardineras del parque
(F2-06, `_p2park_planters()` + `world/props/park_furniture.gd`.) La **huella no cambió**: por cuadrante (sx, sz = ±1)
dos rectángulos en L, en coordenadas `(x, z) · (sx, sz)`:
- A: x ∈ [12, 31], z ∈ [2.5, 31]
- B: x ∈ [2.5, 12], z ∈ [12, 31]

Tapa de pasto (`MatGround.pasto()`, con colisión) a `walk_y(x) + 0.35`. Muro perimetral enchapado en pizarra
(`MatStone.pizarra()`), **0.30 m de grosor hacia dentro** de la huella y 0.45 m de alto (asoma 0.10 sobre el pasto).
**Zona plantable** (sin muro) = la L encogida 0.30 m: A' x ∈ [12.3, 30.7], z ∈ [2.8, 30.7]; B' x ∈ [2.8, 12.3], z ∈ [12.3, 30.7]
(la esquina entrante (12,12) tiene un bloque de 0.30 × 0.30). Plantas a `walk_y(x) + 0.35`.
Reja baja verde (0.66 m sobre el muro) en los bordes que dan a senderos y al anillo perimetral (z = 2.5, x = 31, z = 31, x = 2.5);
los bordes hacia la plaza (z = 12 con x < 12, x = 12 con z < 12) son solo muro de pizarra.
Pisos: plaza |x|,|z| < 12 en espina de pescado; senderos en cruz (ancho 5 m) y anillo 31–34 en adoquín hexagonal,
con bordillo de concreto al pie de las rejas, en la boca de los senderos y en el borde con el andén (±34).
Bancas de granito en los senderos (x ≈ ±2.05, d = 17/25), de madera en la plaza; faroles a x ≈ −2.0 (d = 16/27) y en (±11.6, ±11.6).

### Fase 3.2: ochava y plazoletas
La huella de arriba es la de F2-06; en la fase 3.2 cambió así (constantes al inicio de `boston_district.gd`):
- Cada L se corta en la esquina exterior por la ochava `u + v = PARK_K` (`PARK_K = 62 - PARK_CUT`, `PARK_CUT = 7`), con el mismo
  corte en el borde de la manzana (`PARK_OUT_K`) relleno de concreto. Los setos siguen la ochava a 1.3 m hacia dentro.
- Plazoletas circulares de radio `PLZ_R = 7.5` centradas a `PLZ_C = 21` m de la estatua: oeste `PLZ_W = (-21, 0)` (fuente) y
  norte `PLZ_N = (0, -21)` (tarima). En los cuadrantes de ese lado la jardinera tiene una muesca circular (reja y muro siguen
  el arco). Nada se planta a menos de `PLZ_R + ~1.5` del centro. Piso de laja (`MatStone.laja_plaza()`).
- Los senderos oeste y norte no llevan bancas de granito/caneca a lo largo: van en corro (r = 5 m, ángulos 55/125/235/305°) en la plazoleta.
- Plantas: `_p2plants_park()` salta macizos, hiedra, palmas, agaves y pasto que caigan dentro de una plazoleta (`_p2park_in_plz`).

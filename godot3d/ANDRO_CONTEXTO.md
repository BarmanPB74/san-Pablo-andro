# ANDRO_CONTEXTO — Rediseño del personaje (arcilla gótica / stop-motion)

Versión 2.6 · 12-nov-2026 · F0 a F9 + ronda 2 de afinado · referencia principal: turnaround 68107 · Rama `fase-3d-godot` · Godot 4.3 · renderer Mobile
Alcance: SOLO Andro (`godot3d/character/`) y su movimiento. Nada del mapa, vehículos ni UI.

> Antes de empezar: leer `ESTADO.md` y `CONTRACT.md` (reglas del proyecto). De este documento, leer §0–§3 y §9 siempre, y de §8 solo la fase activa. Así cada sesión sale barata en tokens.

---

## 0. Reglas de trabajo para Claude

1. Respetar `CONTRACT.md`: todo por código (primitivas y `SurfaceTool`), tipado estático, tabs, comentarios en español, sin assets externos ni CSG, materiales vía `Palette`/`ClayStyle`.
2. Una parte por vez (mapa de partes en §1.2). No tocar otras partes ni el mundo. Efectos colaterales → §9.4, sin arreglarlos sin permiso.
3. No inventar. Verificar con `grep` antes de editar (los números de línea de §1.2 son del commit `cf014e4`).
4. Ciclo de cada fase: explicar en 2–3 líneas → construir → probar (§9.2) → mejorar. Siempre captura antes/después.
5. Cerrar cada fase con: capturas, tests en PASS, una entrada en §9.1 y la fila de §9.4 actualizada. Resumir también en `ESTADO.md` ("Última sesión").
6. No renombrar los pivotes (`root, hips, spine, chest, neck, head, upper_arm_l/r, forearm_*, hand_*, thigh_*, shin_*, foot_*`): los usan `player.gd` y los tests.
7. Móvil primero. Prohibido para el personaje: niebla volumétrica, SSS, SSAO/SSR/GI, reflejos en tiempo real, partículas.
8. Si cambias rugosidades, actualizar las aserciones (hoy 0.80 piel/tela, 0.25 ojos) de `tests/gothic_clay_adapter_test.gd`.
9. Si algo no es viable en el teléfono, decirlo y proponer la versión barata.
10. Si falta un dato: UNA pregunta concreta, o elegir un valor por defecto y anotarlo en §9.1.
11. No convertir esto en una lista infinita de ideas: cada fase termina en algo demostrable.

---

## 1. Qué es Andro hoy (verificado en F0)

### 1.1 Inventario
| Dato | Valor |
|---|---|
| Proyecto | `godot3d/` en la rama `fase-3d-godot` del repo `BarmanPB74/san-Pablo-andro` (la rama `main` solo tiene el prototipo web 2D) |
| Godot | `config/features` = 4.3. Pablo usa un editor 4.x más nuevo. Las pruebas de F0 se hicieron con 4.3.stable |
| Renderer | Mobile (`rendering_method="mobile"`), MSAA 3D = 1 |
| Construcción | 100 % por código. `PlayerModel` (`character/player_model.gd`, 1714 líneas) crea 16 pivotes `Node3D`; cada pivote lleva UNA `MeshInstance3D` llamada `Mesh` con una superficie por material. Helpers: `_grid`, `_loft`, `_tube`, `_ellip`. Color por vértice. Mallas cacheadas en `_mesh_cache` por clave |
| Modo plastilina | `ClayStyle.enabled = true` (lo fija `core/game.gd` antes de construir). Cabeza ×1.6 (`CLAY_HEAD_K`), manos ×1.22 (`CLAY_HAND_K`) |
| Materiales | `ClayStyle` convierte todo a `look/clay.gdshader`. `GothicClayAdapter` (nodo hijo) ajusta rugosidad/relieve y aplica sets `art/tex/clay/{piel,abrigo,pelo,lana,cuero}_{albedo,detail}.png`, generados por `tools/texgen/clay_sets.py` |
| Animación | Procedural. No hay AnimationPlayer, AnimationTree ni Skeleton3D. `PlayerModel.animate(state, speed, delta)` se llama cada fotograma desde `Player._process`; suaviza con `k = 1 - exp(-rate*delta)`. `snap_pose()` sirve para tests y capturas |
| Física | `Player` es `CharacterBody3D`, cápsula de 1.86 m (`CAPSULE_H`) |
| Tests base (F0) | `integration_test`, `character_logic_test`, `gothic_clay_adapter_test`: PASS |
| FPS de referencia | ~51 FPS en el parque y ~78 en la calle (editor del teléfono, 9-nov, según `ESTADO.md`). El FPS solo del personaje no está medido |

### 1.2 Mapa de partes (dónde editar) y triángulos medidos
| Parte | Función / línea | Tris |
|---|---|---|
| Pelvis | `_geo_pelvis` L578 | 420 |
| Columna | `_geo_spine` L602 | 336 |
| Pecho + bufanda + bolso | `_geo_chest` L650 → `_clay_scarf` L1567, `_clay_satchel` L1606 | 5 016 |
| Cuello | `_geo_neck` L707 | 160 |
| Cabeza: cara, orejas, nariz, labios, ojos, cejas y pelo | `_geo_head` L786: ojos L876 → `_clay_eye` L1542; orejas L899; nariz L906; labios L923; pelo L949 → `_clay_hair` L1640. Deformación en `_head_deform` L758 | 7 440 |
| Brazos (por lado) | `_geo_upper_arm` L975 + `_geo_forearm` L992 | 280 + 280 |
| Manos (por lado) | `_geo_hand` L1012 | 488 |
| Muslos / pantorrillas (por lado) | `_geo_thigh` L1063 / `_geo_shin` L1075 | 296 / 296 |
| Pies (por lado) | `_geo_foot` L1095 | 788 |
| **Total** | | **18 228** (22 superficies/materiales únicos ≈ 22 draw calls) |

El pelo, la bufanda y el bolso NO son nodos propios: están horneados dentro de las mallas de `head` y `chest`. Cualquier movimiento propio de pelo, cejas, boca o bufanda exige separarlos en piezas (ver F4–F7).

### 1.3 Dimensiones medidas (pose de reposo, modo plastilina)
- Altura total 2.138 m (incluye los mechones); la cápsula mide 1.86 m, así que la cabeza sobresale de ella.
- Cabeza con pelo: 0.429 ancho × 0.509 alto × 0.483 fondo (ya con el ×1.6). Figura total = **4.2 cabezas**; el turnaround de la lámina muestra ≈ 3.
- Pecho 0.447 × 0.662 × 0.295. Muslo 0.46 m, pantorrilla 0.41 m, cadera a 1.01 m.

---

## 2. Fuentes de verdad visual

| Archivo | Qué es | Autoridad para |
|---|---|---|
| **68107.jpg** (12-nov) | **Turnaround definitivo de Pablo**: frente, perfil, espalda y primer plano de la cara, fondo gris. Copia en `docs/andro/shots/REF_68107_turnaround.jpg` | **Todo el personaje** (manda sobre el video y las láminas) |
| **68105.mp4** (12-nov, 10 s) | **Video de Pablo: "cómo debe quedar el personaje"**. Andro en arcilla caminando, saltando un muro y hablando a cámara en un parque gótico de noche. Fotogramas en `docs/andro/shots/REF_video68105_*.jpg` | **Todo el personaje** (manda sobre las láminas) |
| 68017.jpg | Hoja "Rediseño de cabello gótico despeinado (Asset #044-B)" | Cabello: forma, capas, 4 variantes, paleta, medidas |
| 68015.jpg | Hoja "Bufanda gótica (Asset #042)" | Bufanda: nudo, rayas, variantes, paleta |
| 68014.jpg | Hoja "Rostro y expresión (arcilla gótica)" | Cráneo/cara, orejas, ojos, cejas, 5 bocas, paleta de rostro |
| 68009.jpg | Hoja turnaround (frente, perfil, espalda) + texturas | Proporciones, ropa, silueta |
| 68007.png | Captura anterior en Godot | NO es referencia. Es de antes del commit `cf014e4` (pelo "gorro" café); ya no representa el estado actual |

Capturas base de F0 (en `docs/andro/shots/`): `F0_plast_face.jpg`, `F0_plast_full.jpg` (luz plastilina), `F0_lineup.jpg` y `F0_luzprueba_face.jpg` (luz de prueba del portrait). Todas con GL Compatibility/llvmpipe: sirven de guía, no son idénticas al teléfono (Mobile/Vulkan, HDR).

**Prioridad si hay conflicto**: 1) lo que diga Pablo en el chat → 2) el turnaround 68107 → 2b) el video 68105 → 3) la hoja específica de la parte → 4) el turnaround 68009 → 5) el estado actual del código.

**Lo que muestra el video 68105 (leído en F8)**
- Abrigo gris carbón neutro casi negro (nada de morado), largo a medio muslo, una fila de ~6 botones negros pequeños, solapas cortas, 2 bolsillos con solapa abajo, ribete ocre en el pecho. Debajo, chaleco/camisa café oscuro en una franja estrecha y cuello alto negro. → **Hecho en F8.**
- Manos grandes y pálidas de dedos gruesos tipo plastilina. → **Hecho en F8** (más gruesas; se pueden engordar más).
- Sin bandolera ni bolso. → **F8 la apaga** (`SATCHEL_ON = false`).
- **Pelo distinto al #044-B**: bloque plano y cuadrado de arcilla oscura con surcos de dedo arriba (tipo "copete aplanado"), sin púas. → pendiente: decidir con Pablo si reemplaza al 044-B (F6 bis).
- **Bufanda**: verde más vivo (≈ #3F7A3A) con rayas blancas anchas y regulares, flecos verdes; más saturada que la lámina 042. → pendiente: recalibrar (F7 bis).
- Cara: ojos grandes redondos con iris gris verdoso claro y pupila pequeña, ojeras marcadas, cejas gruesas y oscuras, nariz larga, boca pequeña. Orejas medianas (más pequeñas que las de F3). → revisar en una pasada de cara.
- Proporción: cabeza grande (≈ 3.5 cabezas de alto), cuello largo y fino, piernas delgadas, zapatos negros. → F9.

**Erratas y decisiones**
- Las hojas son imágenes generadas con textos errados ("Un rocurcos…", "scoplamiento", "armaturo"…). Se ignora todo texto ilegible.
- Cabello: **decidido por Pablo (12-nov): el #044-B reemplaza al peinado anterior.** Ya está implementado en `_clay_hair` (no hace falta `Hair_Legacy`).
- Medidas de la hoja 044-B: ancho 5.2 cm (dos veces) vs 5.6 cm (recuadro). Se usa 5.2.
- Las medidas en cm son de la maqueta física. En Godot se usan proporciones: bloque de pelo ≈ 1.0 ancho · 0.92 alto · 1.06 fondo; bufanda ≈ 0.67 de ancho y 3.5 de largo desplegado, en unidades de "ancho de cabeza con pelo".
- La bandolera con bolso (lámina #043, sesión anterior) no sale en 68009 ni en el video 68105: desde F8 está apagada (`SATCHEL_ON = false` en `player_model.gd`).

---

## 3. Diagnóstico medido: referencia vs render actual

Método: color promedio/dominante de zonas recortadas. Incluyen iluminación y compresión; usar como guía (±5), no como albedo exacto. "Render 4.3" = captura F0 con el preset `plastilina` en GL Compatibility (sin LUT ni post-proceso; en el teléfono puede variar). El brillo de la piel está recortado (clipping), así que la diferencia real es mayor que la que se ve.

| Zona | Referencia (láminas) | 68007 (anterior) | Render 4.3 | Qué hacer |
|---|---|---|---|---|
| Piel | luz #CBBAB0, medio #AF9C95/#BAA79F | #EFDFD6 / #E7D5CA | #FEE8CD (clipeado) | Sobreexpuesta: ~50 niveles por encima. Bajar exposición/luz en F1 antes de tocar el albedo |
| Pelo | #1E1818 / #382F2E (hoja #1C1A1A) | #3F2D31 | #07040D | Ahora casi negro puro y sin lectura de arcilla. Levantar a #1C1A1A y dejar ver mechones #322E2E / polvo #78716C |
| Abrigo | #141114 a #292426 | #261A25 | #0B0416 | Negro-morado sin textura. Objetivo #1E191C con tela visible |
| Bufanda, verde | #3F553C (hoja #2B452B) | #2D652F | #417433 | **Causa hallada en F7**: `clay_grade` de `look/clay.gdshader` mezcla los verdes hacia `moss_tint` (musgo del mundo, `moss_amount` 0.6). El adaptador ahora pone `moss_amount = 0` en Andro. Albedos de bufanda: `SCARF_G` (0.095, 0.17, 0.10), `SCARF_W` (0.58, 0.585, 0.57), `SCARF_RUST` (0.4, 0.25, 0.18) |
| Bufanda, blanco | #8C9582 (hoja #B2ACA0) | #97B18E | #B8CE8A | Amarillo-verdoso. Debe ser blanco sucio cálido |
| Ojeras | #5B4653 | morado | #8F3E7C | Magenta saturado. Bajar saturación y oscurecer |

---

## 4. Por partes: hoy vs meta

### 4.1 Cabeza y cara (F2)
- Hoy: óvalo largo con mentón redondeado pesado, mejillas lisas y llenas, piel lisa con poros leves.
- Meta (68014): cráneo alto y alargado, pómulos marcados, sienes y mejillas hundidas, mandíbula estrecha, grietas/poros/huellas leves, marcas de herramienta.
- Dónde: `_geo_head`, `_head_deform`. Color en el bloque de color de vértice (ojeras, rubor).

### 4.2 Nariz y orejas (F3)
- Hoy: nariz larga con puente recto y punta redonda (va bien). Orejas con forma de hoja puntiaguda, planas.
- Meta: nariz legible en perfil y 3/4, punta redondeada algo hacia arriba. Orejas grandes con hélix, concha y lóbulo, y ligera asimetría.
- Dónde: `_geo_head` L899 (orejas) y L906 (nariz).

### 4.3 Ojos, párpados y cejas (F4)
- Hoy: ojos enormes con párpado superior de piel y ojera como rollito (`_clay_eye`); pupila minúscula; esclerótica casi blanca (0.93). Las cejas gruesas se funden con el flequillo.
- Meta: esferas brillantes ("sin vida") con un solo punto de luz, párpados gruesos de arcilla, ojera con volumen, cejas gruesas independientes y animables, esclerótica gris-blanca (≈ #CDC8C0, nada de blanco puro).
- Refactor necesario: ojos, párpados y cejas como piezas aparte (hijas del pivote `head`) para poder parpadear/mover cejas.

### 4.4 Boca (F5)
Cinco bocas intercambiables (68014), como piezas separadas que se activan una a la vez:

| Id | Nombre | Descripción |
|---|---|---|
| M1 | Neutro | Labios de arcilla, ligeramente bajos (hoy: línea rosada fina y recta) |
| M2 | Asombrado | "O" abierta, interior oscuro |
| M3 | Triste | Curva hacia abajo |
| M4 | Hablando | Abierta con dientes |
| M5 | Tenso | Dientes apretados (la hoja lo llama "tensión/esfuerzo" y "preocupado/suspiro"; se usa "Tenso") |

Colores: labio #863E3F (hoy C_LIP = #996666, más rosado).

### 4.5 Cabello #044-B (F6)
- Hoy: `_clay_hair`: casquete + ~60 mechones cónicos en 6 zonas (top, mid, fringe, side, back) + un mechón grande cruzando la frente; semilla fija 44. Se lee como "púas finas" con poco volumen; el flequillo es un bloque recto pegado a las cejas.
- Meta: 3 capas (frente, sienes, nuca), mechones más gruesos y aplanados, volumen asimétrico, remolino en la coronilla visto desde atrás, puntas con polvo #78716C, flequillo que deje respirar las cejas.
- Variantes por reemplazo (hoja): clásico, viento/acción, mojado/aplastado, extra caótico. Construir como piezas cacheadas y activar con `visible`.
- Colores: #1C1A1A base, #322E2E medios, #241F1C sombras, #78716C polvo.

### 4.6 Bufanda #042 (F7)
- Hoy: `_clay_scarf`: dos vueltas al cuello (tubos) + dos puntas planas con 5 flecos cada una, punto tejido en V. Sin nudo real, verde demasiado saturado, estática.
- Meta: nudo entrelazado, dos colas desiguales con flecos, rayas verde/blanco sucio de ancho irregular y desgaste, óxido #8C5A3E en las puntas.
- Movimiento: cada cola como cadena de 3–4 pivotes `Node3D` (mismo patrón que el resto del cuerpo) que reaccionan con retraso a `_accel_f` y `_turn_f`. La bufanda (≈ 45 g en la maqueta) es más lenta que el pelo (≈ 35 g).
- Variantes: clásica deshilachada, torcida, corta/rota, flecos largos.

### 4.7 Abrigo, camisa, torso, brazos y manos (F8)
- Hoy: saco cerrado color ciruela-carbón (`C_SUIT` = #382E30), camisa negra de cuello alto, botones café, bandolera.
- Meta (68009): abrigo largo recto de un solo pecho (a medio muslo), solapas, 3 botones café de 4 agujeros, 2 bolsillos con solapa, textil poroso con huellas; manos pálidas, largas y finas.
- Colores: #1E191C base, #322D2F luz.

### 4.8 Piernas, zapatos y proporciones (F9)
- Hoy: 4.2 cabezas de alto; pantalón oscuro y botines café.
- Meta: decidir proporciones (ver §11.1). Medir el color de zapatos en 68009.

---

## 5. Paleta

| Uso | Hex objetivo | En código hoy |
|---|---|---|
| Pelo, base / medio / sombra / polvo | #1C1A1A / #322E2E / #241F1C / #78716C | `C_HAIR` 0.27; `dark` 0.28 / `mid` 0.38 en `_clay_hair` (F1: subidos porque el render los aplastaba) |
| Bufanda: verde marchito, blanco sucio, gris, óxido | #2B452B / #B2ACA0 / #3D3B36 / #8C5A3E | `g` #335430, `w` #BDB5A8 en `_clay_scarf` (más claros) |
| Piel: hueso, sombra | #D1C3B8 / #8E8581 | `C_CLAY_SKIN` (0.64, 0.62, 0.59) tras F1: el hex de la hoja es el color RENDERIZADO, no el albedo |
| Ojeras | #5B4653 | (0.46, 0.40, 0.42) en `_clay_eye` tras F1 (rinde ≈ #663E5A) |
| Labio | #863E3F | `C_LIP` #996666 |
| Abrigo, luz de tela | #1E191C / #322D2F | `C_SUIT` (0.31, 0.29, 0.29), solapa 0.24/0.20/0.21, pantalón 0.22/0.20/0.21 tras F1 |
| Esclerótica | ≈ #CDC8C0 | `EYE` (0.62, 0.63, 0.66) tras F1 (rinde ≈ #C9B2B5) |

**Regla corregida en F1**: el hex de las hojas es lo que se VE (con luz, exposición 1.95 y filmic), no el albedo. Los colores oscuros se aplastan y los claros se recortan, así que el albedo de los vertex colors se calibra midiendo capturas (`sample.py`), no copiando el hex. Además los vertex colors se tratan como sRGB→linear y las texturas `*_albedo` (~#C8C8C8) multiplican ×0.8.

Criterio de la nota de Pablo: colores apagados con un acento (cielo morado, ladrillo rojizo, faroles amarillos; la bufanda es el acento verde del personaje). Evitar blancos puros.

---

## 6. Material "plastilina barata"

### 6.1 Reglas (nota de Pablo) y estado actual
- Rugosidad entre 0.6 y 0.85, metal en 0. Hecho en F1: `clay_smoothness` 0.2 → rugosidad 0.80; ojos 0.75 → rugosidad 0.25 (brillantes, como las cuentas de la hoja); pupila 0.8. Aserciones de `gothic_clay_adapter_test.gd` actualizadas.
- Huellas dactilares: ya vienen por código en los sets `art/tex/clay/*_detail.png` (normal en RG, altura en B) y en `clay_detail.png`. Se mantienen a baja intensidad (`normal_bump_scale` 0.65). Si se quisieran texturas CC0 externas (Poly Haven, Material Maker) habría que revisar la licencia y salir de la regla "sin assets externos" de `CONTRACT.md`. Por defecto se generan con `tools/texgen/clay_sets.py`.

### 6.2 "Boil" opcional (temblor de plastilina a 8–12 Hz)
Plantilla SIN PROBAR. Añadir a `look/clay.gdshader` con valor 0 por defecto (el mundo no cambia) y activarlo solo en las instancias del personaje (pelo, bufanda, abrigo; en la cara, la mitad):
```glsl
uniform float boil_amount = 0.0;   // metros; 0.002–0.006
uniform float boil_fps = 12.0;
float boil_hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
// dentro de vertex():
if (boil_amount > 0.0) {
	vec3 seed = vec3(VERTEX.xy * 40.0, floor(TIME * boil_fps));
	VERTEX += (vec3(boil_hash(seed), boil_hash(seed + 1.7), boil_hash(seed + 3.1)) - 0.5) * boil_amount;
}
```
(Verificar antes si `clay.gdshader` ya tiene `vertex()` y fusionar.)

### 6.3 Presupuesto
- Hoy: 18 228 tris, 22 superficies.
- La lámina de optimización pide 8 000 tris/LOD (pendiente en `ESTADO.md`).
- Presupuesto de trabajo: NO subir de 18 300 durante F2–F10. En F11 bajar a ≤ 14 000 (LOD cercano) y preparar un LOD ≈ 8 000 para lejos.

---

## 7. Técnicas de la nota de Pablo y cómo aplicarlas aquí

Texto de Pablo (12-nov), puntos relevantes al personaje:

> **1. Materiales: plastilina barata** — Rugosidad alta y sin metal: roughness entre 0,6 y 0,85 y metallic en 0. Huellas dactilares: un normal map suave con marcas de dedos. Colores apagados con un acento: cielo morado, ladrillo rojizo y faroles amarillos; evita blancos puros.
>
> **2. Luz de noche que cuesta poco** — Una DirectionalLight3D morada tenue como luna y pocas luces puntuales en los faroles. Activa sombras solo en las luces que se vean cerca; las demás, sin sombras. Niebla de profundidad simple en el Environment. Evita la niebla volumétrica en móvil.
>
> **3. Movimiento stop-motion** — En el AnimationPlayer, cambia la interpolación de las pistas a Nearest. Las poses saltan en vez de deslizarse. Combínalo con animaciones cortas de 8 a 12 poses por segundo.

(Los puntos 4 y 5 —rendimiento y FPS— están en §12.)

### 7.1 Luz (F1, solo en la escena de estudio)
- **Resultado F1**: modo `estudio` de `tests/andro_plastilina_shot.gd` (`... -- face ruta.png estudio`): luna (0.66, 0.60, 0.95) energía 0.55; farol Omni (1.0, 0.68, 0.38) energía 1.2, rango 7, pos (1.6, 2.4, 1.4), sin sombra; niebla `FOG_MODE_DEPTH` begin 6, end 40, densidad 0.7, color (0.17, 0.13, 0.25), sin volumétrica ni height fog. Da más relieve y piel más cálida que el preset. NO está en el preset global (pendiente del OK de Pablo).
- Preset `plastilina` hoy (`look/second_son_environment.gd`): sol (0.84, 0.86, 1.0), energía 0.62, elevación 34°, azimut 35°, ambiente (0.5, 0.5, 0.56) × 1.25, exposición 1.95, niebla exponencial (0.3, 0.25, 0.4) densidad 0.007 + height fog, DOF lejano.
- Prueba en el estudio: luna morada tenue (≈ (0.66, 0.6, 0.95), energía ~0.5) y un farol `OmniLight3D` ámbar (1, 0.68, 0.38), energía 3–4, rango 12–14, SIN sombra (regla de `CONTRACT.md`).
- "Sombras solo cerca": ya se cumple en gran parte (solo proyecta la direccional, con `directional_shadow_max_distance` 120 → 70 en baja calidad; luces del parque con `distance_fade`). No tocar el preset global sin permiso.
- Niebla: probar `Environment.FOG_MODE_DEPTH` (4.3+) en el estudio y comparar contra la exponencial. Sin volumétrica.

### 7.2 Stop-motion: "Nearest" aplicado a animación procedural (F10)
Como no hay `AnimationPlayer`, el equivalente a Nearest es muestrear y mantener la pose: actualizar el cuerpo solo cada 1/12 s y dejar los pivotes quietos entre actualizaciones. Plantilla SIN PROBAR para `PlayerModel.animate`:
```gdscript
@export var step_fps := 0.0        # 0 = suave (como hoy y en los tests); 12 = stop-motion
var _step_acc := 0.0

func animate(state: String, speed: float, delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	if step_fps > 0.0:
		_step_acc += delta
		if _step_acc < 1.0 / step_fps:
			return                 # mantiene la pose anterior (equivale a Nearest)
		delta = _step_acc          # los filtros usan el tiempo acumulado
		_step_acc = 0.0
	# ... resto igual
```
- `Player` activa `step_fps` (8, 10 o 12). Los tests dejan 0.
- El suavizado `k = 1 - exp(-rate*delta)` entre pasos da un efecto de "frenado". Evaluar en F10 si se sube `rate` para poses más limpias.
- `Player._process` interpola la posición del modelo en cada fotograma; en F10 decidir si también se discretiza para que todo se mueva a pasos.
- Reemplazo (boca, cejas, variantes de pelo/bufanda): alternar `visible` de piezas hijas en cada paso del reloj.
- Si algún día se importa un `.glb` con `AnimationPlayer`: `anim.track_set_interpolation_type(t, Animation.INTERPOLATION_NEAREST)` en cada pista, `playback_default_blend_time = 0.0` y keys alineadas a 1/12 s.

---

## 8. Plan por fases

Cada fase = una sesión corta = una captura demostrable. Orden mínimo si hay poco crédito: **F1 → F2+F3 → F4 → F7 → F10**.

### F0 · Inventario y línea base — HECHA
Resultado en §1, §3 y §9.1.

### F1 · Estudio de luz y material — HECHA (ver §9.1)
- Hacer: escena/script de estudio de Andro (partir de `tests/andro_plastilina_shot.gd`) con luna morada, farol sin sombra y niebla de profundidad; ajustar `GothicClayAdapter` (rugosidad 0.80, ojos 0.25, esclerótica gris-blanca); bajar la sobreexposición de la piel.
- Aceptación: piel cerca de #CBBAB0, pelo y abrigo con lectura de material, ojeras cerca de #5B4653; 3 vistas (face, full, side); tests PASS. FPS sin caída > 10 %.
- No tocar: mallas ni el preset global.

### F2 · Cabeza y cara — HECHA (ver §9.1)
- Hacer: §4.1 en `_geo_head` / `_head_deform`.
- Aceptación: perfil y 3/4 acordes a 68009; tris de cabeza ≤ 7 440.

### F3 · Nariz y orejas — HECHA (ver §9.1)
- Hacer: §4.2. Aceptación: legibles en perfil y 3/4.

### F4 · Ojos, párpados, ojeras, cejas — HECHA (ver §9.1)
- Hacer: §4.3; piezas aparte con pivotes para animarlas.
- Aceptación: parpadeo de 3 poses y mirada con pasos; un solo brillo en el ojo.

### F5 · Boca y expresiones — HECHA (ver §9.1)
- Hacer: M1–M5 como piezas cacheadas.
- Aceptación: las 5 bocas se alternan sin parpadeos de malla.

### F6 · Cabello 044-B — HECHA (ver §9.1)
- Hacer: §4.5 (volumen, capas, variantes como piezas).
- Aceptación: silueta desgreñada y asimétrica en 4 vistas, color de §5.

### F7 · Bufanda 042 — HECHA (ver §9.1)
- Hacer: §4.6 (nudo, color, colas con pivotes).
- Aceptación: colores #2B452B / #B2ACA0 en pantalla, colas con retraso en giros y aceleración.

### F8 · Abrigo, camisa, torso, brazos y manos — HECHA (ver §9.1)
- Hacer: §4.7. Aceptación: abrigo negro con tela visible, solapas, botones y bolsillos.

### F9 · Piernas, zapatos y proporciones finales — HECHA (ver §9.1; incluye F6 bis, F7 bis y pasada de cara)
- Hacer: §4.8 con la decisión de §11.1. Revisar que la cápsula y la entrada a autos no se rompan.

### F10 · Stop-motion
- Hacer: §7.2 (pasos a 8–12 pps, reemplazos, bufanda/pelo con pivotes) y probar el "boil" de §6.2.
- Aceptación: sin movimiento suave visible; `character_logic_test` PASS con `step_fps = 0`.

### F11 · Pulido y optimización móvil
- Hacer: presupuesto de §6.3, fusionar materiales, comprimir texturas, probar en el teléfono.

---

## 9. Protocolo anti-pérdida de contexto

### 9.1 Registro de cambios
Plantilla (una entrada por fase, la más nueva arriba):
```
### YYYY-MM-DD · Fxx · Parte
- Archivos tocados:
- Qué cambió:
- Capturas (docs/andro/shots/Fxx_*.jpg):
- Tris / FPS:
- Efectos colaterales:
- Decisiones por defecto tomadas:
- Siguiente paso:
```

### 2026-11-12 · F0 · Inventario y línea base
- Archivos tocados: ninguna malla ni material. Nuevos: `ANDRO_CONTEXTO.md`, `tests/andro_inventory.gd`, `tests/andro_plastilina_shot.gd`, `docs/andro/shots/F0_*.jpg`.
- Qué cambió: nada visual. Se midió el modelo y se capturó la línea base.
- Capturas: `F0_plast_face`, `F0_plast_full`, `F0_lineup`, `F0_luzprueba_face`.
- Tris / FPS: 18 228 tris, 22 superficies, 2.138 m, 4.2 cabezas. FPS del personaje sin medir (pendiente en teléfono).
- Efectos colaterales: ninguno.
- Decisiones por defecto: el #044-B reemplaza al pelo anterior (confirmado por Pablo); se mantiene la bandolera.
- Siguiente paso: F1.

### 2026-11-12 · F1 · Luz de estudio y material
- Archivos tocados: `character/gothic_clay_adapter.gd`, `character/player_model.gd` (solo constantes de color), `tests/gothic_clay_adapter_test.gd`, `tests/andro_plastilina_shot.gd` (modo `estudio`).
- Qué cambió: rugosidad piel/tela 0.80, ojos 0.25; albedos de piel, abrigo, pantalón, pelo, ojeras y esclerótica recalibrados midiendo capturas (piel de #FEE8CD recortado a ≈ #C9ADA5; abrigo de #0B0416 a ≈ #22152A; pelo de #07040D a ≈ #110717–#3D2941).
- Capturas: `F1_plast_face`, `F2_estudio_face`, `F2_estudio_full`.
- Tris / FPS: sin cambio. FPS sin medir.
- Efectos colaterales: el mundo no cambia (preset global intacto). Los colores del personaje también cambian en el juego normal, no solo en el estudio.
- Decisiones por defecto: se corrige la regla "hex = albedo" (§5). Bufanda lima (#417433 renderizado vs #335430 en código) sin resolver: va a F7. Boca rosada y orejas, a F5/F3.
- Siguiente paso: F2.

### 2026-11-12 · F2 · Cabeza y cara
- Archivos tocados: `character/player_model.gd` (`_head_keys`, `_head_deform`, `head_col`).
- Qué cambió: mentón y mandíbula más estrechos (cara más alargada), mejillas hundidas, pómulo y arco superciliar más marcados, cuencas más hondas, punta de mentón; menos rubor y sombra gris ceniza en las mejillas hundidas. No se tocaron las filas `y` de `_head_keys` (ojos, orejas, nariz y labios siguen en posiciones absolutas).
- Capturas: `F2_plast_face`, `F2_plast_full`, `F2_plast_side`, `F2_estudio_face`.
- Tris / FPS: 18 228 total, cabeza 7 440 (igual). FPS sin medir.
- Efectos colaterales: ninguno detectado; 3 tests PASS (el "Parameter m is null" ya existía antes).
- Decisiones por defecto: la cabeza sigue ×1.6.
- Siguiente paso: F3 (nariz y orejas) o la fase que indique Pablo.

### 2026-11-12 · F3 · Nariz y orejas
- Archivos tocados: `character/player_model.gd` (`_geo_head`: bloque de nariz y de orejas; nuevo `_clay_ear`).
- Qué cambió: nariz con más proyección (punta de 0.017 a 0.026 sobre la cara), más ancha en la base, punta redondeada y levantada, alas más grandes y fosas nasales oscuras. Orejas más grandes con concha oscura, hélix, antihélix y lóbulo; la izquierda es 7 % más grande y 3 mm más alta (asimetría).
- Capturas: `F3_perfil_antes/F3_perfil/F3_perfil_der`, `F3_tres_cuartos_antes/F3_tres_cuartos`.
- Tris / FPS: ver F4 (total 19 364). FPS sin medir.
- Efectos colaterales: el flequillo y las patillas del pelo 044-B tapan casi toda la oreja izquierda en perfil (se ve entera por el otro lado). Ajustar en F6.
- Siguiente paso: F4.

### 2026-11-12 · F4 · Ojos, párpados, ojeras y cejas
- Archivos tocados: `character/player_model.gd` (nuevos `_dress_piece`, `_bake`, `_build_face_pieces`, `_geo_eyeball`, `_geo_lid`, `_geo_brow`, `set_face`, `_clay_eye_bag`; `triangle_count` suma las piezas), `tests/andro_face_test.gd` (nuevo), `tests/andro_plastilina_shot.gd` (vistas `hperfil`, `hperfil2`, `h34` y variables de entorno de cara), `tests/andro_inventory.gd` sin cambios.
- Qué cambió: el globo ocular ya no sobresale tanto (radio z 0.017, antes 0.02); esclerótica gris-blanca, iris oscuro, pupila más grande y un solo brillo. Párpado superior grueso (borde a ≈ 68° desde la vertical, mirada cansada). Ojo, párpado y ceja son 6 piezas hijas de `head` (`eye_l/r`, `lid_l/r`, `brow_l/r`), cacheadas, con la misma escala de cabeza. La ojera sigue en la malla de la cabeza.
- API: `set_face(blink 0|1|2, gaze Vector2(x, y en rad), brow_l, brow_r en −1..1)`. Aún NO está conectada a `animate` ni al estado del jugador: eso es F10 (parpadeo aleatorio y mirada con `step_fps`).
- Capturas: `F4_cara`, `F4_estudio_cara`, `F4_pasos` (abierto / entrecerrado / cerrado / mirada+cejas).
- Tris / FPS: 19 364 total (+1 136 vs F2: cabeza 7 144, piezas de cara ≈ 1 400, orejas más detalladas). Se revisa en F11. FPS sin medir.
- Efectos colaterales: el hueco de la cabeza que antes ocupaban los ojos pasó de 3 a 2 superficies (piel y pelo); `GothicClayAdapter` estila las piezas sin cambios. Con el parpadeo cerrado el párpado queda algo abultado; se puede afinar en F10.
- Decisiones por defecto: el brillo del ojo va dentro de la pieza del globo (gira con la mirada); las cejas siguen en el material del pelo.
- Siguiente paso: F5 (boca y expresiones).

### 2026-11-12 · F5 · Boca y expresiones
- Archivos tocados: `character/player_model.gd` (`_geo_mouth`, `_lip`, `_mouth_cavity`, `_teeth_row`, `set_mouth`, `get_mouth`; `C_LIP` (0.42, 0.2, 0.2) en arcilla), `tests/andro_f5f7_test.gd` (nuevo).
- Qué cambió: los labios salieron de la malla de la cabeza. Hay 5 piezas hijas de `head` (`mouth_m1..m5`), cacheadas, una visible a la vez: M1 neutro, M2 asombrado (O con interior oscuro), M3 triste, M4 hablando (dientes superiores), M5 tenso (dientes apretados). `set_mouth(id)` solo cambia `visible`.
- Capturas: `F5_bocas`.
- Efectos colaterales: sin conectar aún a diálogo ni a `animate` (F10). En modo no arcilla se mantienen los labios antiguos.
- Siguiente paso: F6.

### 2026-11-12 · F6 · Cabello 044-B
- Archivos tocados: `character/player_model.gd` (`_geo_hair`, `set_hair_variant`, `get_hair_variant`, `_style_piece`; el casquete y los mechones salieron de `_geo_head` en arcilla), `character/gothic_clay_adapter.gd` (`apply_to(nodo)`).
- Qué cambió: el pelo es la pieza `hair` (hija de `head`, gira en `HAIR_ORIGIN`). Mechones más gruesos y aplanados, 3 capas (frente, sienes, nuca), volumen 35 % mayor a la derecha, remolino en la coronilla, sienes que suben sin tapar las orejas y puntas con polvo #78716C. 4 variantes por reemplazo: 0 clásico, 1 viento, 2 mojado, 3 caótico (4 056 tris en la clásica).
- Capturas: `F6_variantes_pelo`, `F6_perfil`, `F6_nuca`, `F6_tres_cuartos`.
- Efectos colaterales: las púas de arriba suben la altura total a 2.19 m (antes 2.14); el pelo está fuera del AABB de `head` (el inventario ya lo suma). Una pieza creada tras `_ready` debe pasar por `_style_piece` (ClayStyle convierte el material y luego el adaptador lo estila).
- Siguiente paso: F7.

### 2026-11-12 · F7 · Bufanda 042
- Archivos tocados: `character/player_model.gd` (`_clay_scarf` reescrita, `_stripe_col`, `_scarf_joints`, `_geo_scarf_seg`, `_build_scarf_tails`, `set_scarf_variant`, `_update_cloth` llamada desde `animate`), `character/gothic_clay_adapter.gd` (`moss_amount = 0`).
- Qué cambió: el verde lima era el filtro de musgo del mundo (`clay_grade`), no la textura ni la exposición. Con eso apagado, los albedos de la bufanda se calibraron midiendo (verde marchito, blanco sucio, óxido en las puntas). Rayas de ancho irregular con desgaste, nudo de dos bultos, dos vueltas al cuello. Las dos colas son cadenas de pivotes hijas de `chest` (`scarf_a1..a4`, `scarf_b1..b3`); `_update_cloth` las separa al acelerar/frenar/correr y las balancea al girar (más lentas que el pelo). 4 variantes: clásica, torcida, corta/rota, flecos largos.
- Capturas: `F7_bufanda`, `F7_variantes`, `F7_cara_completa`, `F7_estudio_cara`, `F7_cuerpo`.
- Tris / FPS: 19 360 total (chest 4 456, head 2 764, hair 4 056, mouth ≈ 190). FPS sin medir.
- Efectos colaterales: el filtro de musgo del mundo sigue activo para el resto del mapa (no se tocó). La bufanda en estudio y en preset se ve igual de apagada.
- Decisiones por defecto: la respiración de las colas usa `Time.get_ticks_msec` (F10 la pasará a pasos de `step_fps`).
- Siguiente paso: F8 (abrigo, torso, brazos y manos).

### 2026-11-12 · F8 · Abrigo, chaleco, brazos y manos (según video 68105)
- Archivos tocados: `character/player_model.gd` (colores de ropa, `_geo_chest`, `_clay_satchel` con `SATCHEL_ON`, `_geo_forearm` puños, `_geo_hand` dedos gruesos, `CLAY_HAND_K` 1.28, nuevos `SKIRT_ROWS`, `_skirt_pt`, `_geo_coat_skirt`, `_build_coat_skirt`; `_update_cloth` mueve los faldones), `tests/andro_f5f7_test.gd` (faldones), `tests/andro_plastilina_shot.gd` (vistas `torso`/`torso_back`, variable `ANDRO_POSE`).
- Qué cambió: abrigo gris carbón neutro (albedo algo amarillo para compensar la luz morada del preset). Baja a medio muslo con dos faldones (`coat_l`, `coat_r`, hijos de `hips`) que siguen a su muslo con factor 0.62. Así no atraviesan las piernas al caminar, correr ni agacharse. Son conchas con grosor, abertura trasera, dobladillo gastado y bolsillo con solapa. Franja de chaleco café como pieza propia con cantos del abrigo, 6 botones negros (4 en el pecho y 2 en el faldón derecho), solapas cortas, cuello alto negro y puños más oscuros. Manos un 5 % más grandes, dedos más cortos y gruesos, pulgar más grueso. Bandolera apagada.
- Medido (preset, mediana): abrigo ≈ #1E1721 (video #0E0F10, escena más oscura), chaleco ≈ #332324 (video #20201E).
- Capturas: `F8_torso`, `F8_torso_espalda`, `F8_estudio_torso`, `F8_cuerpo`, `F8_perfil`, `F8_poses` (correr ×2, caminar, agachado). Referencia: `REF_video68105_frente`, `REF_video68105_accion`.
- Tris / FPS: 20 048 total (+688: faldones 912, pecho −352 sin bandolera). FPS sin medir.
- Efectos colaterales: agachado, los faldones suben con el muslo y el de atrás se ve como una caja: aceptable por ahora, se puede afinar en F10. Pantalón aún con tinte morado por la luz del preset.
- Decisiones por defecto: bandolera fuera (el video no la tiene); el video manda sobre las láminas.
- Siguiente paso: F9 (piernas, zapatos negros y proporciones según el video) y decidir con Pablo el pelo y el verde de la bufanda del video.

### 2026-11-12 · F9 + F6 bis + F7 bis + cara · Según el turnaround 68107 (4 agentes en paralelo)
Método: 4 agentes editaron a la vez `player_model.gd`, cada uno solo en sus funciones (reglas en el brief común; solo `Edit`, sin reescribir el archivo). El coordinador integró, midió y ajustó la proporción.
- **A · Pelo (F6 bis)**: `_geo_hair` reescrita y nueva constante `HAIR_BLOCK` (0.41, 0.41, 0.38). Casquete calculado desde `_head_keys()`, con la línea de pelo recta en y 0.194. Tupé de 5 rollos cuadrados (`_tube` con n=4) de frente a coronilla, en dos pisos y con surcos oscuros. Nuca de 7 franjas en abanico. Lados con 3 cordones peinados hacia atrás y patilla corta; oreja libre. Variantes: 1 viento (rollos hacia atrás), 2 mojado (45 % de alto), 3 caótico (rollos desalineados, +2).
- **B · Cara**: ojos blancos sin iris (`C_CLAY_SCLERA`, `EYE_R` (0.0262, 0.0258, 0.0168), pupila r 0.0054, brillo arriba), centro hundido +0.0035. Párpado: casquete de 76° (reposo ≈ 56°); `set_face` gira [0, −0.62, −1.6] y estira en z [1, 1.12, 1.55]. Ojeras con `_eye_rim`/`_bag_ring` en 3 anillos (párpado inferior malva, banda gris morada, pliegue superior). Cejas casi negras en arco (`C_BROW`, `_brow_y`). Nariz recta de perfil, en cuña, con punta rosada. M1 con sonrisa suave y hoyuelos. Orejas 26 % más pequeñas.
- **C · Bufanda (F7 bis)**: `STRIPE_W` [0.026 verde, 0.019 blanco], con bordes de raya nítidos (`_stripe_ts`, filas dobles). `SCARF_G` (0.355, 0.462, 0.335) se ve #3C803A y `SCARF_W` (0.595, 0.615, 0.58) se ve #CFCCB7. Rollo grueso al cuello sin nudo. Colas paralelas (`a` larga en +X, `b` en −X) con 7 flecos verdes y blancos. Sin óxido salvo en la variante 2.
- **D · F9**: pantalón recto y holgado, con pliegue sobre el zapato (`C_TROUSER` (0.33, 0.328, 0.205), se ve #282024). Zapatos derby café de 0.27 m (`C_DRESS_SHOE` (0.36, 0.33, 0.10), se ven #3C2B28–#5D4B3D). Abrigo ABIERTO: `hw` de 0.064 a 0.082, suéter de punto `_knit()` café (`C_VEST` (0.42, 0.36, 0.215), se ve #4B332B) hasta y −0.33, y cuello alto café. Solapas con muesca hasta medio pecho, un solo botón a la cintura, faldones abiertos al frente (`a0` 0.42) y bolsillos a y −0.055. Largos: `THIGH_LEN` 0.43, `SHIN_LEN` 0.38, `HIPS_HEIGHT` 0.95; las alturas relativas coinciden con 68107 (entrepierna 0.50, borde del abrigo 0.41, dedos 0.39).
- **Coordinador**: `CLAY_HEAD_SY` 1.13 (`CLAY_HEAD_S`). La cabeza y sus piezas se estiran en y desde el mentón, porque en 68107 la cabeza es más alta que ancha. Altura 2.115 m; con pelo, 3.88 cabezas (antes 4.25; la referencia ≈ 3.7).
- Capturas: `F9_comparacion` (referencia arriba, Andro abajo), `F9_cuerpo`, `F9_perfil`, `F9_espalda`, `F9_cara`, `F9_tres_cuartos`, `F9_perfil_cabeza`, `F9_nuca`, `F9_bufanda`, `F9_torso`, `F9_estudio_cara`, `F9_estudio_cuerpo`, `F9_caminar`, `F9_ojos_cerrados`.
- Tris: 27 298 (antes 20 048). Sube por el pelo, las ojeras y las rayas nítidas de la bufanda. Se revisa en F11. Tests: 5 PASS.
- Pendiente / diferencias que quedan frente a 68107: los ojos se ven algo más pequeños y las ojeras como aros duros (en la referencia son un degradado suave). Falta el hoyuelo del mentón y las arrugas. El abrigo de la referencia es algo más ancho de hombros. El material del pelo es `hoodie_knit` (fibra) y no huella de arcilla. Las bocas M2–M5 siguen con `C_LIP` viejo. Los colores están calibrados con la luz morada del preset: si cambia la luz, hay que recalibrar (pantalón y pelo son muy sensibles).
- Siguiente paso: F10 (stop-motion: pasos a 8–12 pps, parpadeo y bocas en el juego), o una pasada fina de ojos/ojeras si Pablo lo pide.

### 2026-11-12 · Ronda 2 de afinado contra 68107 (4 agentes) · "la oreja flota"
- **A · Orejas y cabeza**: `_clay_ear` reescrita (recibe `keys` e `y0`). La raíz va calculada sobre la piel con `_skull_x` y hundida 2 mm, con un puente de piel detrás. Marco propio: la parte de atrás se separa 27° y la de arriba 12°. Lleva concha, hélix, antihélix, trago y lóbulo. Constantes `EAR_Y` 0.107, `EAR_ZF`, `EAR_OPEN`, `EAR_TILT`. **La oreja ya no flota.** Mandíbula más ancha y redonda (semiancho en y 0.033: 0.05 → 0.059), nuca más llena. `_nasolabial` añade el surco nasogeniano, más hoyuelo y mentón redondo. La patilla pintada termina delante de la oreja.
- **B · Ojos, ojeras, nariz, boca**: `EYE_R` (0.0293, 0.0293/`CLAY_HEAD_SY`, 0.0215), así el globo se ve redondo pese al estirado de la cabeza; pupila centrada. **Bug corregido en `set_face`**: el párpado perdía el estirado en y y el globo asomaba. Ahora escala desde `CLAY_HEAD_S`, con 3 poses que tapan del todo. Las ojeras son un degradado por color de vértice (`_eye_shade`, llamado desde `head_col`); se quitaron los aros (`_eye_rim`/`_bag_ring` quedan sin uso). Cejas más largas y gruesas. Nariz en medio óvalo con bulbo rosado, columela y aletas. M1 con sonrisa amplia. `C_LIP` = piel ×(1.03, 0.86, 0.84) en M1–M5.
- **C · Pelo y bufanda**: 5 rollos de la misma altura que siguen el perfil de `perfil_cabeza.jpg` (frente → coronilla → nuca), sin alero; surcos de peine en los laterales; bloque ancho por detrás. El "aspecto de fibra" venía del set de textura `pelo`: `GothicClayAdapter.ROLE_SET["hair"]` pasa a `"piel"` (arcilla con huellas; también afecta a las cejas). `HAIR_BLOCK` (0.4, 0.4, 0.365). Bufanda: colas más largas y anchas, 8 flecos de 0.062 y vuelta del cuello más gruesa.
- **D · Cuerpo**: pivote del brazo x 0.19 → 0.205, hombros cuadrados (0.212 → 0.242), torso recto, mangas más gruesas, faldón más ancho con pliegues, brazos algo más abiertos en `_pose_locomotion` (línea `out`). Costura central en la espalda. Solapas anchas con muesca (`_lapel_col`). Suéter con canalé y cuello alto doblado. `CLAY_HAND_K` 1.4 y dedos en abanico curvados. Bolsillos a la cadera. Se comprobó que antebrazo y mano no atraviesan los faldones al caminar ni al correr.
- **Coordinador**: patilla del pelo aplanada y hundida en la piel (antes era un palo colgando delante de la oreja).
- Capturas: `R2_comparacion` (referencia arriba, Andro abajo), `R2_cabeza_angulos`, `R2_cuerpo`, `R2_perfil`, `R2_espalda`, `R2_cara`, `R2_tres_cuartos`, `R2_torso`, `R2_bufanda`, `R2_estudio_*`, `R2_caminar`, `R2_ojos_cerrados`.
- Tris: **37 152** (antes 27 298; el pelo solo ya suma 11 728). Es mucho para móvil: F11 debe bajarlo (LOD, menos segmentos en los surcos y en el canalé). Tests: 5 PASS. Altura 2.10 m, 3.96 cabezas.
- Quedan: la nariz se lee como 3 bolitas (bulbo + aletas) en 3/4; la oreja muestra los aros del hélix y del antihélix demasiado marcados; las bocas M2–M5 son estrechas frente a M1; de espalda el bloque de pelo se ve algo alto y estrecho comparado con el cuello; la tapa del pelo queda clara con la luz morada.

### 9.2 Comandos (desde la raíz del repo; `godot` = 4.3)
```
# Importar la primera vez
godot --headless --path godot3d --editor --quit
# Tests (cada uno debe imprimir RESULT: PASS)
godot --headless --path godot3d -s res://tests/integration_test.gd
godot --headless --path godot3d -s res://tests/character_logic_test.gd
godot --headless --path godot3d -s res://tests/gothic_clay_adapter_test.gd
godot --headless --path godot3d -s res://tests/andro_face_test.gd
godot --headless --path godot3d -s res://tests/andro_f5f7_test.gd
# Cara por pasos en las capturas: variables ANDRO_BLINK=0|1|2, ANDRO_GAZE="x,y", ANDRO_BROW="izq,der", ANDRO_MOUTH=1..5, ANDRO_HAIR=0..3, ANDRO_SCARF=0..3, ANDRO_POSE="estado,velocidad,fase" (p. ej. run,5.0,1.6)
# Inventario: tris, medidas y materiales de Andro
godot --headless --path godot3d -s res://tests/andro_inventory.gd
# Captura con luz plastilina (llvmpipe; vistas: face, close, full, side, back, hperfil, hperfil2, h34, hback (cabeza), bufanda, torso, torso_back; ruta de salida ABSOLUTA; 3er argumento opcional: preset | estudio)
xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot3d --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/andro_plastilina_shot.gd -- face /ruta/absoluta/Fxx_face.png
```
Godot 4.3: `https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip`. En este entorno no hay Vulkan: las capturas son GL Compatibility; pedir a Pablo capturas del teléfono para confirmar color y brillo.

Checklist de cierre de fase:
- [ ] Silueta legible con el personaje a ~128 px de alto
- [ ] Tris y superficies dentro de §6.3
- [ ] Sin texturas estiradas ni caras negras
- [ ] Pivotes sin renombrar; `player.gd` y las animaciones previas funcionan
- [ ] 3 tests en PASS
- [ ] Capturas guardadas como `Fxx_vista.jpg` (JPG, ~100 KB) en `docs/andro/shots/`

### 9.3 Convenciones
Respetar los nombres existentes. Piezas nuevas sugeridas (hijas del pivote correspondiente): `Brow_L`, `Brow_R`, `Mouth_M1` … `Mouth_M5`, `Hair_Clasico`, `Hair_Viento`, `Hair_Mojado`, `Hair_Caotico`, `ScarfTail_A1..A4`, `ScarfTail_B1..B4`.

### 9.4 Estado
| Fase | Estado | Notas |
|---|---|---|
| F0 | [x] hecha | 12-nov |
| F1 | [x] hecha | 12-nov; falta confirmar color en el teléfono |
| F2 | [x] hecha | 12-nov; tris sin cambio (18 228) |
| F3 | [x] hecha | 12-nov; nariz proyecta en perfil, orejas con hélix/concha/lóbulo |
| F4 | [x] hecha | 12-nov; ojos, párpados y cejas son piezas con `set_face()`; falta conectarlo a `animate` (F10) |
| F5 | [x] hecha | 12-nov; 5 bocas como piezas, `set_mouth(1..5)` |
| F6 | [x] hecha | 12-nov; pelo = pieza `hair` con 4 variantes, `set_hair_variant()` |
| F7 | [x] hecha | 12-nov; colas con cadena de pivotes, lima corregida (filtro de musgo), `set_scarf_variant()` |
| F8 | [x] hecha | 12-nov; abrigo a medio muslo con faldones `coat_l/r`, chaleco, 6 botones, manos gruesas, sin bandolera |
| F9 | [x] hecha | 12-nov; con 4 agentes en paralelo según 68107: pelo en bloque, cara, bufanda, piernas/zapatos/abrigo abierto, cabeza ×1.13 en y (3.88 cabezas) |
| F10 | [ ] pendiente | |
| F11 | [ ] pendiente | |

Efectos colaterales pendientes: la cabeza sobresale de la cápsula (2.13 m vs 1.86 m); revisar techos bajos y entrada a autos si se cambian proporciones.

### 9.5 Retomar tras perder contexto
Leer `ESTADO.md`, §0, §9.4 y la última entrada de §9.1. Confirmar con Pablo en una línea en qué fase se estaba.

---

## 10. Prompts para pegar

**Plantilla**
```
Lee godot3d/ESTADO.md, godot3d/CONTRACT.md y godot3d/ANDRO_CONTEXTO.md (§0 a §3 y §9) y la fase [Fxx] de §8.
Trabaja solo [parte]. No toques el resto ni el mundo.
Ciclo: explica en 3 líneas → construye → captura → mejora.
Al final: 3 tests PASS, entrada en §9.1, fila de §9.4 y resumen en ESTADO.md.
Si falta un dato, haz una sola pregunta.
```
**Por fase (solo cambia la segunda línea)**
- F1: "Solo luz de estudio y material base (adaptador). Sin tocar mallas ni el preset global."
- F2: "Solo cabeza y cara. Sin ojos, boca ni pelo."
- F3: "Solo nariz y orejas."
- F4: "Solo ojos, párpados, ojeras y cejas."
- F5: "Solo las 5 bocas y su reemplazo."
- F6: "Solo el cabello 044-B y sus variantes."
- F7: "Solo la bufanda 042."
- F8: "Solo abrigo, camisa, torso, brazos y manos."
- F9: "Solo piernas, zapatos y proporciones finales."
- F10: "Solo animación stop-motion (pasos, reemplazos, boil)."
- F11: "Solo optimización y pruebas en el teléfono."

---

## 11. Decisiones abiertas
1. **Proporciones** (respondida por Pablo): enfocarse en todo el personaje. Hoy 4.2 cabezas; se mantiene el cuerpo y se revisa en F9.
2. **Presupuesto de triángulos** (respondida por Pablo): se decide en F11. Hasta entonces no se optimiza, pero tampoco se añaden triángulos a lo loco.
3. **Capturas del teléfono**: las de F0 son de llvmpipe. En F1 dejar una escena de estudio jugable en el editor del teléfono para confirmar color y brillo.
4. **Pelo**: el video 68105 muestra un bloque plano con surcos, no el 044-B con puntas. Preguntar a Pablo si se cambia (sería una variante nueva o el nuevo `clasico`).
5. **Bufanda**: el video tiene un verde más vivo que la lámina 042. Preguntar si se sube la saturación.

---

## 12. Notas de Pablo fuera del alcance del personaje (guardadas)
- Rendimiento: script en la escena del parque que recorre el grupo `decor` y fija `visibility_range_end = 60`, `visibility_range_end_margin = 10` y `VISIBILITY_RANGE_FADE_SELF`; usar `MultiMeshInstance3D` para árboles, faroles y postes repetidos.
- Medir antes de arreglar: contador de FPS en pantalla y cambiar una cosa a la vez; Perfetto para perfilar en Android.
- Próximos días: peatones con `NavigationAgent3D` y máquina de estados, física de autos con `VehicleBody3D`, cámara y botones táctiles de piedra, sonido ambiente de barrio.

# ANDRO_CONTEXTO — Rediseño del personaje (arcilla gótica / stop-motion)

Versión 2.0 · 12-nov-2026 · F0 hecha · Rama `fase-3d-godot` · Godot 4.3 · renderer Mobile
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
8. Si cambias rugosidades, actualizar las aserciones (0.88 / 0.55) de `tests/gothic_clay_adapter_test.gd`.
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
| 68017.jpg | Hoja "Rediseño de cabello gótico despeinado (Asset #044-B)" | Cabello: forma, capas, 4 variantes, paleta, medidas |
| 68015.jpg | Hoja "Bufanda gótica (Asset #042)" | Bufanda: nudo, rayas, variantes, paleta |
| 68014.jpg | Hoja "Rostro y expresión (arcilla gótica)" | Cráneo/cara, orejas, ojos, cejas, 5 bocas, paleta de rostro |
| 68009.jpg | Hoja turnaround (frente, perfil, espalda) + texturas | Proporciones, ropa, silueta |
| 68007.png | Captura anterior en Godot | NO es referencia. Es de antes del commit `cf014e4` (pelo "gorro" café); ya no representa el estado actual |

Capturas base de F0 (en `docs/andro/shots/`): `F0_plast_face.jpg`, `F0_plast_full.jpg` (luz plastilina), `F0_lineup.jpg` y `F0_luzprueba_face.jpg` (luz de prueba del portrait). Todas con GL Compatibility/llvmpipe: sirven de guía, no son idénticas al teléfono (Mobile/Vulkan, HDR).

**Prioridad si hay conflicto**: 1) lo que diga Pablo en el chat → 2) la hoja específica de la parte → 3) el turnaround 68009 → 4) el estado actual del código.

**Erratas y decisiones**
- Las hojas son imágenes generadas con textos errados ("Un rocurcos…", "scoplamiento", "armaturo"…). Se ignora todo texto ilegible.
- Cabello: **decidido por Pablo (12-nov): el #044-B reemplaza al peinado anterior.** Ya está implementado en `_clay_hair` (no hace falta `Hair_Legacy`).
- Medidas de la hoja 044-B: ancho 5.2 cm (dos veces) vs 5.6 cm (recuadro). Se usa 5.2.
- Las medidas en cm son de la maqueta física. En Godot se usan proporciones: bloque de pelo ≈ 1.0 ancho · 0.92 alto · 1.06 fondo; bufanda ≈ 0.67 de ancho y 3.5 de largo desplegado, en unidades de "ancho de cabeza con pelo".
- La bandolera con bolso (lámina #043, sesión anterior) no sale en 68009. Se mantiene.

---

## 3. Diagnóstico medido: referencia vs render actual

Método: color promedio/dominante de zonas recortadas. Incluyen iluminación y compresión; usar como guía (±5), no como albedo exacto. "Render 4.3" = captura F0 con el preset `plastilina` en GL Compatibility (sin LUT ni post-proceso; en el teléfono puede variar). El brillo de la piel está recortado (clipping), así que la diferencia real es mayor que la que se ve.

| Zona | Referencia (láminas) | 68007 (anterior) | Render 4.3 | Qué hacer |
|---|---|---|---|---|
| Piel | luz #CBBAB0, medio #AF9C95/#BAA79F | #EFDFD6 / #E7D5CA | #FEE8CD (clipeado) | Sobreexpuesta: ~50 niveles por encima. Bajar exposición/luz en F1 antes de tocar el albedo |
| Pelo | #1E1818 / #382F2E (hoja #1C1A1A) | #3F2D31 | #07040D | Ahora casi negro puro y sin lectura de arcilla. Levantar a #1C1A1A y dejar ver mechones #322E2E / polvo #78716C |
| Abrigo | #141114 a #292426 | #261A25 | #0B0416 | Negro-morado sin textura. Objetivo #1E191C con tela visible |
| Bufanda, verde | #3F553C (hoja #2B452B) | #2D652F | #417433 | Verde lima. En código es #335430, así que algo lo sube (¿textura `lana_albedo`, exposición, glow?): investigar en F7 |
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
| Pelo, base / medio / sombra / polvo | #1C1A1A / #322E2E / #241F1C / #78716C | `dark` 0.11 / `mid` 0.2 / `dust` 0.47 en `_clay_hair`: coincide |
| Bufanda: verde marchito, blanco sucio, gris, óxido | #2B452B / #B2ACA0 / #3D3B36 / #8C5A3E | `g` #335430, `w` #BDB5A8 en `_clay_scarf` (más claros) |
| Piel: hueso, sombra | #D1C3B8 / #8E8581 | `C_CLAY_SKIN` #D1C4B5 |
| Ojeras | #5B4653 | #856178 en `_clay_eye` |
| Labio | #863E3F | `C_LIP` #996666 |
| Abrigo, luz de tela | #1E191C / #322D2F | `C_SUIT` #382E30 |
| Esclerótica | ≈ #CDC8C0 | `EYE` #EDEBE3 (muy blanco) |

Criterio de la nota de Pablo: colores apagados con un acento (cielo morado, ladrillo rojizo, faroles amarillos; la bufanda es el acento verde del personaje). Evitar blancos puros.

---

## 6. Material "plastilina barata"

### 6.1 Reglas (nota de Pablo) y estado actual
- Rugosidad entre 0.6 y 0.85, metal en 0. Hoy: `clay_smoothness` 0.12 → rugosidad 0.88 (algo alta); ojos 0.55.
  - Propuesta F1: `clay_smoothness` 0.2 → rugosidad 0.80; ojos 0.75 → rugosidad 0.25 (brillantes, como las cuentas de la hoja). Actualizar `gothic_clay_adapter_test.gd`.
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

### F1 · Estudio de luz y material
- Hacer: escena/script de estudio de Andro (partir de `tests/andro_plastilina_shot.gd`) con luna morada, farol sin sombra y niebla de profundidad; ajustar `GothicClayAdapter` (rugosidad 0.80, ojos 0.25, esclerótica gris-blanca); bajar la sobreexposición de la piel.
- Aceptación: piel cerca de #CBBAB0, pelo y abrigo con lectura de material, ojeras cerca de #5B4653; 3 vistas (face, full, side); tests PASS. FPS sin caída > 10 %.
- No tocar: mallas ni el preset global.

### F2 · Cabeza y cara
- Hacer: §4.1 en `_geo_head` / `_head_deform`.
- Aceptación: perfil y 3/4 acordes a 68009; tris de cabeza ≤ 7 440.

### F3 · Nariz y orejas
- Hacer: §4.2. Aceptación: legibles en perfil y 3/4.

### F4 · Ojos, párpados, ojeras, cejas
- Hacer: §4.3; piezas aparte con pivotes para animarlas.
- Aceptación: parpadeo de 3 poses y mirada con pasos; un solo brillo en el ojo.

### F5 · Boca y expresiones
- Hacer: M1–M5 como piezas cacheadas.
- Aceptación: las 5 bocas se alternan sin parpadeos de malla.

### F6 · Cabello 044-B
- Hacer: §4.5 (volumen, capas, variantes como piezas).
- Aceptación: silueta desgreñada y asimétrica en 4 vistas, color de §5.

### F7 · Bufanda 042
- Hacer: §4.6 (nudo, color, colas con pivotes).
- Aceptación: colores #2B452B / #B2ACA0 en pantalla, colas con retraso en giros y aceleración.

### F8 · Abrigo, camisa, torso, brazos y manos
- Hacer: §4.7. Aceptación: abrigo negro con tela visible, solapas, botones y bolsillos.

### F9 · Piernas, zapatos y proporciones finales
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

### 9.2 Comandos (desde la raíz del repo; `godot` = 4.3)
```
# Importar la primera vez
godot --headless --path godot3d --editor --quit
# Tests (cada uno debe imprimir RESULT: PASS)
godot --headless --path godot3d -s res://tests/integration_test.gd
godot --headless --path godot3d -s res://tests/character_logic_test.gd
godot --headless --path godot3d -s res://tests/gothic_clay_adapter_test.gd
# Inventario: tris, medidas y materiales de Andro
godot --headless --path godot3d -s res://tests/andro_inventory.gd
# Captura con luz plastilina (llvmpipe; vistas: face, close, full, side, back; ruta de salida ABSOLUTA)
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
| F1 | [ ] pendiente | |
| F2 | [ ] pendiente | |
| F3 | [ ] pendiente | |
| F4 | [ ] pendiente | |
| F5 | [ ] pendiente | |
| F6 | [ ] pendiente | |
| F7 | [ ] pendiente | |
| F8 | [ ] pendiente | |
| F9 | [ ] pendiente | |
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
1. **Proporciones**: hoy 4.2 cabezas; la hoja ≈ 3. Por defecto se mantiene el cuerpo (cápsula 1.86 m) y, si Pablo quiere el look de la hoja, se agranda la cabeza (hoy ×1.6) en vez de acortar el cuerpo.
2. **Presupuesto de triángulos**: 18 228 hoy vs 8 000 de la lámina. Por defecto, F11 baja a ≤ 14 000 + LOD lejano.
3. **Capturas del teléfono**: las de F0 son de llvmpipe. En F1 dejar una escena de estudio jugable en el editor del teléfono para confirmar color y brillo.
4. **Pelo**: el 044-B actual se lee como "púas finas"; confirmar en F6 si se prefieren mechones más gruesos y aplanados como en la hoja.

---

## 12. Notas de Pablo fuera del alcance del personaje (guardadas)
- Rendimiento: script en la escena del parque que recorre el grupo `decor` y fija `visibility_range_end = 60`, `visibility_range_end_margin = 10` y `VISIBILITY_RANGE_FADE_SELF`; usar `MultiMeshInstance3D` para árboles, faroles y postes repetidos.
- Medir antes de arreglar: contador de FPS en pantalla y cambiar una cosa a la vez; Perfetto para perfilar en Android.
- Próximos días: peatones con `NavigationAgent3D` y máquina de estados, física de autos con `VehicleBody3D`, cámara y botones táctiles de piedra, sonido ambiente de barrio.

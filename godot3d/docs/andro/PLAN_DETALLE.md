# PLAN_DETALLE — Andro por bloques (rostro · cuerpo · ropa · zapatos)

Versión 1.0 · 15-nov-2026 · Referencia: turnaround 68107 (`docs/andro/shots/REF_68107_turnaround.jpg`)
Complementa `ANDRO_CONTEXTO.md` (F0–F9 ya hechas). Aquí solo hay trabajo de DETALLE: forma, textura, brillo, contorno y color.
Cada fase es una sesión corta e independiente. Se hace UNA por vez y se cierra con capturas + tests + una línea en `ANDRO_CONTEXTO.md §9.1`.

## 0. Cómo gastar pocos tokens
1. Leer solo: este archivo, `ANDRO_CONTEXTO.md` §0 y la última entrada de §9.1. No leer `player_model.gd` entero (2 763 líneas): ir con `grep -n` a la función de la fase (tabla de cada bloque).
2. Capturar solo las vistas de la fase (`face`, `torso`, `torso_back`, `full`, `side`); fusionarlas en UNA imagen de comparación con PIL y mirar esa sola imagen.
3. Cambiar pocas constantes por vez, recapturar, y parar cuando la comparación diga "listo". No abrir más agentes de los que pida la fase.
4. Tests: correr solo los 2 que toca la fase (indicados abajo) y los 5 completos únicamente al cerrar el bloque.

## 1. Diagnóstico comparativo (68107 vs. Andro en R2, 15-nov)

| Bloque | En la referencia | Andro hoy | Gravedad |
|---|---|---|---|
| **Ropa · abrigo** | Gris carbón neutro, arcilla satinada con brillos suaves y anchos; arrugas grandes en mangas y bajo el codo; hombros caídos y amplios; solapas gruesas; bolsillos con solapa de borde redondeado | Con luz de estudio sale **burdeos/marrón**; con luz morada, negro-violeta. Mate y con grano de tela; mangas rectas y delgadas; sin arrugas; hombros angostos | Alta |
| **Ropa · bufanda** | Rayas anchas (≈ 9 por cola), arcilla lisa y brillante, colas anchas y gordas, flecos como cilindros | Rayas finas (≈ 18) con trama de punto; se lee como tela tejida, no como arcilla; colas más delgadas | Media |
| **Ropa · suéter / pantalón** | Suéter café liso con solo el dobladillo acanalado; pantalón negro carbón con arrugas sobre el zapato | Suéter con canalé en todo el torso; pantalón marrón oscuro (albedo cálido compensando la luz morada); piernas delgadas y sin arrugas | Media |
| **Zapatos** | Derby café oscuro grandes y brillantes, punta redonda, suela visible, ojales | Pequeños (0.27 m), amarillo-café mate, sin brillo; se pierden en la silueta | Alta |
| **Cuerpo** | Hombros anchos, brazos con volumen, manos grandes de dedos gruesos, cuello largo | Hombros algo angostos, manos finas para el estilo, 3.96 cabezas (ref. ≈ 3.7) | Media |
| **Rostro** | Piel con degradado suave, ojeras difuminadas, nariz de una pieza, orejas medianas | Nariz = 3 bolitas en 3/4, aros del hélix muy marcados, bocas M2–M5 estrechas, piel con puntitos | Media |

**Causa raíz común (ropa):** los albedos de `C_SUIT`, `C_TROUSER`, `C_VEST`, `C_DRESS_SHOE` están compensados para la luz morada del preset `plastilina`. Cuando cambie el cielo (Pablo lo pidió gris de nubes), la ropa se verá de otro color. Primero se deja el color **neutro y correcto**, y el aspecto lo ponen la luz y el material.

## 2. Bloques y fases

### P · ROPA (prendas; se trabaja primero)
| Fase | Alcance | Dónde (grep) | Listo cuando |
|---|---|---|---|
| P1 Abrigo | Color neutro, brillo satinado, arrugas, hombros/mangas, solapas, bolsillos, contorno enrollado | `C_SUIT`, `_geo_chest`, `_geo_upper_arm`, `_geo_forearm`, `_geo_coat_skirt`, `ROLE_SET`/`_styled` en `gothic_clay_adapter.gd` | Comparación torso: mismo gris, mismos brillos y silueta de mangas |
| P2 Bufanda | Rayas anchas, superficie lisa de arcilla, colas gordas, flecos | `STRIPE_W`, `SCARF_G/W`, `_clay_scarf`, `_geo_scarf_seg` | Se lee como arcilla y no como punto |
| P3 Suéter y pantalón | Suéter liso con dobladillo acanalado; pantalón carbón con arrugas; piernas con más volumen | `C_VEST`, `_knit`, `C_TROUSER`, `_geo_thigh`, `_geo_shin`, `_geo_pelvis` | Color neutro en ambas luces |

### Z · ZAPATOS
| Fase | Alcance | Dónde | Listo cuando |
|---|---|---|---|
| Z1 Forma y color | Derby más grandes (≈ 0.30 m), punta redonda, suela visible, café oscuro real | `C_DRESS_SHOE`, `_geo_foot` | Silueta de pie legible a 128 px |
| Z2 Brillo y detalle | Brillo de cuero, ojales y lengüeta, borde de suela | `ROLE_SET["shoe"]`, `_styled` | Brillo cálido pequeño, sin espejo |

### C · CUERPO
| Fase | Alcance | Dónde | Listo cuando |
|---|---|---|---|
| C1 Hombros, brazos, manos | Hombros más anchos, brazos con volumen, manos más gruesas | `_geo_upper_arm`, `_geo_hand`, `CLAY_HAND_K` | Silueta frontal igual a 68107 |
| C2 Proporción y cuello | 3.96 → ≈ 3.7 cabezas sin romper la cápsula de 1.86 m | `CLAY_HEAD_S*`, `THIGH_LEN`, `SHIN_LEN`, `HIPS_HEIGHT`, `_geo_neck` | `player.gd` y tests siguen en PASS |

### R · ROSTRO
| Fase | Alcance | Dónde | Listo cuando |
|---|---|---|---|
| R1 Nariz y orejas | Nariz de una pieza, hélix suave | `_geo_head`, `_clay_ear` | Perfil y 3/4 sin "bolitas" |
| R2 Ojos, ojeras, piel | Ojeras en degradado, quitar puntitos de piel | `_clay_eye_bag`, `C_CLAY_SKIN`, set `piel` | Primer plano parecido a la lámina |
| R3 Bocas | M2–M5 con el mismo ancho que M1 | `_geo_mouth` | Las 5 bocas legibles |

## 3. Reglas fijas para todas las fases
- `CONTRACT.md`: todo por código, tipado estático, tabs, comentarios en español, sin assets externos.
- No renombrar pivotes. No sumar triángulos a lo loco: Andro ya está en 37 152 y F11 tiene que bajarlo; en cada fase de ropa, el total de triángulos no debe subir más de un 3 %.
- Capturas en `docs/andro/shots/<Fase>_<vista>.jpg` (~100 KB).
- Si algo no es viable en el teléfono, decirlo y proponer la versión barata.

## 4. Comandos de la fase
```
G=godot   # 4.3
$G --headless --path godot3d -s res://tests/gothic_clay_adapter_test.gd
$G --headless --path godot3d -s res://tests/andro_f5f7_test.gd
xvfb-run -a -s "-screen 0 1280x720x24" $G --path godot3d --rendering-driver opengl3 --rendering-method gl_compatibility \
  -s res://tests/andro_plastilina_shot.gd -- torso /ruta/absoluta/P1_torso.png      # vistas: torso, torso_back, full, side, bufanda
```

## 5. Estado
| Fase | Estado |
|---|---|
| P1 Abrigo | HECHA (15-nov); ver `ANDRO_CONTEXTO.md` §9.1 |
| P2 Bufanda | pendiente |
| P3 Suéter y pantalón | pendiente |
| Z1/Z2 Zapatos | pendiente |
| C1/C2 Cuerpo | pendiente |
| R1/R2/R3 Rostro | pendiente |

# Fase 1 — Texturas PBR (10 agentes). Brief común.

Proyecto: /home/claude/san-pablo-andro/godot3d (Godot 4.3, renderer Mobile, objetivo Xiaomi Poco F8 Pro).
Juego de mundo abierto en el barrio Boston de Medellín. Lee CONTRACT.md, art/palette.gd y look/README_look.md para contexto.
Dirección visual: realismo urbano colombiano (como las fotos de referencia) con gradación "ciudad mojada"
(sombras teal, luces ámbar, neones). Las texturas deben ser NATURALES y creíbles: la gradación la pone el post-proceso,
no las texturas (no las tiñas de teal).

FOTOS DE REFERENCIA (míralas con la herramienta Read): /tmp/refs/
  1_anden_tienda_arboles.jpg   andén de concreto con franja táctil amarilla, árboles con troncos cubiertos de musgo,
                               fachada con celosía metálica de corte láser, aviso redondo colgante, jardín tropical, banca de granito
  2_parque_boston_estatua.jpg  Parque de Boston: estatua de pie en bronce sobre pedestal BLANCO alto, seto redondo,
                               rejas bajas verdes, sendero de adoquín, árboles altos, palma
  3_calle_pendiente_palma.jpg  calle en pendiente: asfalto nuevo, línea amarilla central, "30" pintado, flechas, señal
                               "BAJE EN 2a", palma, edificio de vidrio, edificio de ladrillo, montañas
  4_parque_boston_plaza.jpg    plaza con adoquín de concreto gris, jardineras enchapadas en PIZARRA negra, árboles
  5_parque_boston_sendero.jpg  sendero de adoquín HEXAGONAL gris con bordillo, rejas verdes bajas, monumento blanco
  6_edificio_ladrillo_calle.jpg edificio de ladrillo naranja con balcones, andén de LADRILLO tolete, hiedra, bolardos amarillos
  7_anden_palmas_ladrillo.jpg  edificios altos de ladrillo, andén de concreto con piedra, jardineras de ladrillo, poste de
                               concreto con muchos cables, palmas, setos

REGLAS
- Solo Python con numpy + PIL + scipy. Usa tools/texgen/common.py (fbm, worley, warp, height_to_normal, save_pbr, preview,
  contact_sheet). NO modifiques common.py (es compartido); si necesitas más utilidades ponlas en tu propio script.
- Tu script: tools/texgen/<familia>.py, determinista (semillas fijas), regenerable con `python3 tools/texgen/<familia>.py`.
- Salida: art/tex/<familia>/<nombre>_albedo.png, _normal.png (OpenGL, Y+), _orm.png (R=AO, G=rugosidad, B=metal).
- TODAS las texturas de superficie deben tilear sin costuras (verifica con preview(), que muestra 2x2 tiles).
- Escala física: decide cuántos metros cubre 1 tile y documéntalo (ej. ladrillo 1024 px = 2 m).
- Presupuesto móvil: 1024 px solo para superficies grandes (asfalto, andenes, ladrillo de fachada); 512 px para el resto.
  Máximo ~6 sets por familia y ~12 MB de PNG por familia. Atlases con alpha (follaje, letreros) en RGBA: guarda tú mismo
  el albedo como RGBA PNG si necesitas alpha (save_pbr guarda RGB; escribe el _albedo con PIL "RGBA" después).
- Materiales Godot: crea art/mat/mat_<familia>.gd con `class_name Mat<Familia> extends RefCounted` y funciones estáticas
  que devuelvan Material usando `TexMat.pbr(base, opts)` (art/mat/tex_mat.gd; lee sus opciones). Documenta en un
  comentario de cada función: para qué superficie es y qué tile_m usa.
- NO edites archivos fuera de: tools/texgen/<familia>.py, art/tex/<familia>/, art/mat/mat_<familia>.gd y lo que tu brief
  individual diga explícitamente. NO toques palette.gd, world/, vehicles/, character/ (el integrador conecta todo después).
- Itera con los ojos: genera preview() y contact_sheet() en /tmp/f1_<familia>/ y míralos con Read. Compara contra las
  fotos. Repite hasta que se vean de calidad AAA móvil: variación a varias escalas (macro manchas, meso piezas, micro grano),
  bordes gastados, suciedad en juntas, AO en juntas, rugosidad variada (no un valor plano).
- Validación Godot (UNA vez al final, la máquina tiene solo 2 núcleos y hay 10 agentes): copia privada
  `rsync -a --delete --exclude .godot /home/claude/san-pablo-andro/godot3d/ /tmp/sb_<familia>/ && cd /tmp/sb_<familia> &&
   nice -n 10 /tmp/godot/Godot_v4.3-stable_linux.x86_64 --headless --editor --quit` (importa tus PNG), y un script
  headless (extends SceneTree) que llame a cada función de tu Mat<Familia> y verifique que devuelve Material con texturas
  no nulas. Opcional: una captura con
  `xvfb-run -a -s "-screen 0 1280x720x24" nice -n 10 /tmp/godot/Godot_v4.3-stable_linux.x86_64 --path /tmp/sb_<familia>
   --rendering-driver opengl3 -s res://tests/screenshot.gd -- <escena> /tmp/f1_<familia>/godot.png 30`.
- Copia tu mejor hoja de contacto a /tmp/entrega_f1/<familia>.png.
- AL TERMINAR responde (breve): archivos, lista de funciones Mat<Familia> con su tile_m y uso, tamaño total en MB,
  y qué superficies del juego deberían usar cada una.

# Fase 2 — Modelos y detalle geométrico (10 agentes). Brief común.

Proyecto: /home/claude/san-pablo-andro/godot3d (Godot 4.3, renderer Mobile, objetivo Xiaomi Poco F8 Pro).
Mundo abierto en el barrio Boston de Medellín. La Fase 1 ya creó texturas PBR reales en art/tex/ y
materiales en art/mat/ (MatAsphalt, MatPaving, MatBrick, MatPlaster, MatGround, MatFoliage, MatStone,
MatMetal, MatFacade, MatActors; LÉELOS: cada función documenta su uso, tile_m y si va con UV o triplanar).
art/palette.gd ya delega en ellos. Lee CONTRACT.md, look/README_look.md y world/README_mapa.md.

FOTOS DE REFERENCIA (míralas con Read): /tmp/refs/1..7 (andén con árboles musgosos y tienda con celosía,
Parque de Boston con estatua de pie sobre pedestal blanco, calle en pendiente con palma y señales, plaza del
parque con jardineras de pizarra, sendero hexagonal con rejas verdes, edificio de ladrillo con andén de ladrillo,
andén con palmas y edificios altos de ladrillo).
Captura actual del juego para ver de dónde partimos: /tmp/f1_final/*.png (míralas).

OBJETIVO: subir el nivel visual a "AAA móvil": siluetas creíbles, proporciones reales (metros), biseles
(chaflanes) en aristas visibles, piezas con grosor, variación entre instancias, detalles secundarios
(tornillos, juntas, desgaste, suciedad en bases), sin pasarse de polígonos.

REGLAS DE ARQUITECTURA
- Todo por código (GDScript), sin assets externos. Construye mallas con SurfaceTool/ArrayMesh
  (genera normales y UV correctas; tangentes con st.generate_tangents() si el material tiene normal map).
- Modelos de mundo: crea world/props/<tu_modulo>.gd con `class_name <Nombre> extends RefCounted` y funciones
  estáticas que devuelvan Mesh (ArrayMesh multi-superficie con material por superficie) CACHEADAS en
  `static var` (la misma variante se construye una sola vez). Varias variantes (semilla) por tipo.
- Colocación en el mapa: boston_district.gd tiene API nueva: `place_mesh(key, mesh, xf, shadow)` (agrupa en
  MultiMesh: 1 draw call por superficie por key), `place_node(node, xf)` (solo para luces/partículas/física),
  `add_col_box(xf, size)`, `add_col_cyl(center, r, h)`. Usa coordenadas y helpers del distrito (walk_y, road_y).
- PRESUPUESTO (móvil): cada variante de prop < ~3k triángulos (árbol grande < 6k), materiales por modelo ≤ 4,
  luces nuevas: OmniLight sin sombra, solo donde de verdad iluminan algo, rango ≤ 14 m.
- Materiales: usa los Mat* de la Fase 1 (o Palette). Si necesitas un material nuevo, créalo en tu propio
  archivo (p. ej. dentro de tu módulo como función estática), nunca edites art/mat/*.gd ni palette.gd salvo que
  tu brief lo diga.

EDICIÓN DE world/boston_district.gd (COMPARTIDO por varios agentes — cuidado)
- Solo puedes modificar las funciones que tu brief individual te asigna (y añadir funciones nuevas privadas
  con prefijo propio, p. ej. `_p2trees_...`). No toques ninguna otra función ni variables globales.
- Hazlo AL FINAL, cuando tu módulo ya esté validado, con ediciones pequeñas y atómicas (herramienta Edit, una
  función a la vez). Si Edit falla porque el archivo cambió, vuelve a leer y reintenta. Nunca reescribas el
  archivo entero ni uses sed/python sobre él.
- Mantén el mismo determinismo (_rng) y las mismas colisiones o mejores. No elimines spawns.

VALIDACIÓN (la máquina tiene 2 núcleos y 10 agentes; sé eficiente)
- Godot: /tmp/godot/Godot_v4.3-stable_linux.x86_64. Copia privada:
  `rsync -a --delete --exclude .godot /home/claude/san-pablo-andro/godot3d/ /tmp/sb_<tu_id>/ && cd /tmp/sb_<tu_id>
   && nice -n 10 /tmp/godot/Godot_v4.3-stable_linux.x86_64 --headless --editor --quit`
  (la primera importación de texturas tarda ~1 min; después solo cambia lo nuevo si no borras .godot:
  para re-sincronizar usa `rsync -a --exclude .godot` SIN --delete).
- Itera tu modelo en una escena pequeña de "estudio" propia (tests/scenes/p2_<tu_id>_studio.tscn + .gd):
  piso, StreetLook (res://look/second_son_environment.gd) en "overcast_day", cámara a distancia de juego
  (3-15 m) y de cerca. Captura:
  `xvfb-run -a -s "-screen 0 1280x720x24" nice -n 10 /tmp/godot/Godot_v4.3-stable_linux.x86_64 --path /tmp/sb_<tu_id>
   --rendering-driver opengl3 -s res://tests/screenshot.gd -- res://tests/scenes/<escena>.tscn /tmp/p2_<tu_id>/x.png 30`
  Mira las capturas con Read, compáralas con las fotos e itera (al menos 3 iteraciones visuales).
- Al final, después de conectar al mapa: captura del juego real con
  `... -s res://tests/view_shot.gd -- overcast_day <px,py,pz> <tx,ty,tz> /tmp/p2_<tu_id>/mapa.png 65`
  (cámara libre; coordenadas del mapa en world/README_mapa.md; el parque está en el origen) y corre
  `--headless --fixed-fps 60 -s res://tests/integration_test.gd` → debe dar RESULT: PASS.
- Copia tus 2-3 mejores capturas a /tmp/entrega_f2/<tu_id>_*.png.

AL TERMINAR responde (breve): archivos creados/modificados, funciones de boston_district que cambiaste,
triángulos aprox. por variante, draw calls añadidas, problemas conocidos.

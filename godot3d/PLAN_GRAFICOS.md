# Plan de mejora gráfica — 50 agentes en 5 fases

La máquina de trabajo tiene 2 núcleos, así que cada fase lanza 10 agentes en paralelo,
cada uno dueño de sus propios archivos. Al final de cada fase el integrador
conecta el trabajo, prueba el juego completo y toma capturas antes de seguir.

Referencias visuales: 7 fotos de Pablo (Parque de Boston, andenes, calles en pendiente,
edificios de ladrillo, vegetación tropical).

## Fase 1 — Texturas PBR (10 agentes)
Texturas reales tileables (albedo + normal + oclusión/rugosidad/metal), generadas por
código en `tools/texgen/` y materiales en `art/mat/`.
1. Asfalto y pintura vial (+ texturas dentro del shader de suelo mojado)
2. Andenes: losas de concreto, baldosa táctil amarilla, adoquín hexagonal, espina de pescado, ladrillo tolete, sardinel
3. Ladrillo de fachada medellinense (y celosía de ladrillo)
4. Estuco pintado, concreto, teja de barro, zócalos, eternit
5. Cortezas con musgo, troncos de palma, pasto, tierra, musgo
6. Atlas de follaje tropical (copas, palmas, crotón, helecho, heliconia, hiedra, seto)
7. Piedra: pizarra de jardineras, granito de bancas, mármol del pedestal, sillar de la iglesia, bronce
8. Metal y señales: rejas verdes, galvanizado, poste de concreto, celosía láser, atlas de señales colombianas
9. Ventanas, vitrinas de locales, letreros (nombres inventados) y neones
10. Vehículos (llantas, rines, placas, faros) y ropa/piel de Andro

## Fase 2 — Modelos y detalle geométrico (10 agentes)
Cada agente crea módulos nuevos en `world/props/` y similares, sin tocar el mapa base.
1. Árboles grandes (tronco ramificado, raíces, copa con tarjetas de follaje, musgo)
2. Palmas, arbustos, jardineras tropicales, setos y hiedra
3. Postes eléctricos de concreto, cableado denso, transformadores, luminarias
4. Semáforos, señales viales, bolardos, nomenclatura de calles
5. Monumento del parque: figura de pie en bronce sobre pedestal blanco alto con seto redondo (corrigiendo la versión ecuestre, según tus fotos)
6. Mobiliario del parque: rejas bajas verdes, bancas de granito, jardineras de pizarra, faroles, canecas
7. Fachadas comerciales: vitrinas, celosías, toldos, avisos colgantes y de neón
8. Edificios de ladrillo de altura con balcones, barandas y remates
9. Vehículos: carrocería con más detalle, interiores, rines, placas, suciedad
10. Personaje Andro: malla con más detalle, telas texturizadas, rostro

## Fase 3 — Integración por zonas (10 agentes)
Cada agente reconstruye una zona del mapa usando los módulos de las fases 1 y 2
(parque, iglesia, Calle 55, Calle 54, Cra 38, Cra 39, Cra 43, La Playa, Echeverri, manzanas interiores).

## Fase 4 — Iluminación, atmósfera y materiales vivos (10 agentes)
Luz por zonas, reflejos, sombras de contacto, viento en vegetación, charcos, suciedad,
decals de grafiti y desgaste, ciclo día/noche, LOD y distancia de dibujado.

## Fase 5 — Rendimiento y control de calidad (10 agentes)
Presupuesto de draw calls y memoria para el Poco F8 Pro, compresión de texturas,
LODs, oclusión, pruebas visuales comparativas con las fotos y corrección de errores.

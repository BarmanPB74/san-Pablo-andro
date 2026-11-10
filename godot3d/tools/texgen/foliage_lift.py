#!/usr/bin/env python3
"""Levanta la luminancia de la celda 3 (hojas anchas) del atlas de copas.
La celda salía casi negra (lum media 43/255, 16 % de texels < 30) y, multiplicada por la oclusión del
color de vértice, se veía como bloques negros en el teléfono. Idempotente: no vuelve a levantar si ya está.
Ejecutar DESPUÉS de foliage.py:  python3 tools/texgen/foliage_lift.py
"""
import numpy as np
from PIL import Image

PATH = "art/tex/foliage/canopy_atlas_albedo.png"
GAMMA = 0.62          # <1 aclara los oscuros sin quemar los claros
TARGET_MIN_MEAN = 70  # si la celda ya supera esto, no se toca

im = np.array(Image.open(PATH).convert("RGBA"))
cell = im[512:1024, 512:1024].astype(np.float32)
op = cell[..., 3] >= 128
mean = cell[..., :3].mean(2)[op].mean()
if mean >= TARGET_MIN_MEAN:
    print("celda 3 ya levantada (lum media %.0f), nada que hacer" % mean)
else:
    rgb = (cell[..., :3] / 255.0) ** GAMMA * 255.0
    # los texels transparentes también se levantan para que los mipmaps no los mezclen más oscuros
    cell[..., :3] = rgb
    im[512:1024, 512:1024] = np.clip(cell, 0, 255).astype(np.uint8)
    Image.fromarray(im, "RGBA").save(PATH, optimize=True)
    new = cell[..., :3].mean(2)[op].mean()
    print("celda 3: lum media %.0f -> %.0f" % (mean, new))

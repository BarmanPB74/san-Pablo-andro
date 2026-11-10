"""Familia ASPHALT (F1-01): asfalto nuevo, asfalto gastado y atlas de pintura vial.

Regenerar:  python3 tools/texgen/asphalt.py          (desde godot3d/)
Determinista (semillas fijas). Solo numpy + PIL + scipy.

Escalas físicas
  asphalt_new   1024 px = 4.0 m  (~3.9 mm/px)  agregado fino 3-12 mm, ligante oscuro, compactación de rodillo
  asphalt_worn  1024 px = 6.0 m  (~5.9 mm/px)  oxidado/gris, grietas finas en bloque y piel de cocodrilo,
                                               grietas selladas con brea, parches de reparación más oscuros,
                                               manchas de aceite
  road_decals   1024 px = 2.56 m (2.5 mm/px)   atlas RGBA (sin tileo, salvo tiras de línea en V); ver LAYOUT

Referencia: /tmp/refs/3_calle_pendiente_palma.jpg (asfalto nuevo de Medellín, línea amarilla, "30", flechas).
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (ROOT, blur_wrap, contact_sheet, fbm, height_to_normal, normalize,  # noqa: E402
                    preview, save_pbr, warp)

OUT = "art/tex/asphalt"
PREV = "/tmp/f1_asphalt"
S = 1024


# ============================================================ utilidades propias
def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    """Mezcla; solo expande t a 3 canales si a o b son de color."""
    a = np.asarray(a, dtype=np.float64); b = np.asarray(b, dtype=np.float64); t = np.asarray(t)
    if t.ndim == 2 and (a.ndim == 3 or (b.ndim >= 1 and b.shape[-1] == 3 and b.ndim != 2)):
        t = t[..., None]
    return a * (1 - t) + b * t


def srgb(v):
    return np.asarray(v, dtype=np.float64)


def stones(size, n, rmin, rmax, seed, flat=False):
    """Piedras de agregado: domos (altura) + tono por piedra. Tileable (dilatación en wrap).
    Devuelve (altura [0,1] con 0 = sin piedra, tono [0,1], máscara)."""
    rng = np.random.default_rng(seed)
    ys = rng.integers(0, size, n)
    xs = rng.integers(0, size, n)
    rad = rng.uniform(rmin, rmax, n)
    hgt = rng.uniform(0.55, 1.0, n)
    ton = rng.random(n)
    H = np.zeros((size, size))
    T = np.zeros((size, size))
    for R in np.unique(np.ceil(rad).astype(int)):
        sel = np.ceil(rad).astype(int) == R
        R = max(int(R), 1)
        yy, xx = np.mgrid[-R:R + 1, -R:R + 1]
        d = np.sqrt(yy ** 2 + xx ** 2) / (R + 0.5)
        foot = d <= 1.0
        dome = np.where(foot, np.sqrt(np.clip(1 - d ** 2, 0, 1)), 0.0)
        if flat:
            dome = np.where(foot, 0.85 + 0.15 * dome, 0.0)
        imp = np.full((size, size), -5.0)
        imp[ys[sel], xs[sel]] = hgt[sel]
        h = ndimage.grey_dilation(imp, footprint=foot, structure=dome - 1.0, mode="wrap") + 1.0
        h = np.clip(h, 0, None) * (h > 0.05)
        timp = np.full((size, size), -1.0)
        timp[ys[sel], xs[sel]] = ton[sel]
        t = ndimage.grey_dilation(timp, footprint=foot, mode="wrap")
        upd = h > H
        H = np.where(upd, h, H)
        T = np.where(upd, t, T)
    return H, np.clip(T, 0, 1), H > 0


def jitter_warp(a, size, strength, seed, cells=64):
    dx = fbm(size, cells, 3, seed=seed)
    dy = fbm(size, cells, 3, seed=seed + 1)
    return warp(a, dx, dy, strength)


def periodic_edges(size, n, seed, warp_px=0.0, warp_cells=4, fine_warp=0.0):
    """Distancia (px) al borde entre celdas de Voronoi (F2-F1) — red de grietas tileable."""
    rng = np.random.default_rng(seed)
    pts = rng.random((n, 2)) * size
    tree = cKDTree(pts, boxsize=size)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    if warp_px:
        yy = yy + (fbm(size, warp_cells, 5, seed=seed + 11) - 0.5) * warp_px
        xx = xx + (fbm(size, warp_cells, 5, seed=seed + 12) - 0.5) * warp_px
    if fine_warp:
        yy = yy + (fbm(size, 64, 3, seed=seed + 13) - 0.5) * fine_warp
        xx = xx + (fbm(size, 64, 3, seed=seed + 14) - 0.5) * fine_warp
    q = np.stack([yy.ravel() % size, xx.ravel() % size], -1)
    d, _ = tree.query(q, k=2)
    return (d[:, 1] - d[:, 0]).reshape(size, size) * 0.5


def wrap_dist(c, x, size):
    d = np.abs(x - c)
    return np.minimum(d, size - d)


def to_u8(a):
    return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)


def grey(v, warm=0.0):
    """Gris neutro sRGB con leve sesgo cálido (+) o frío (-)."""
    v = np.asarray(v)[..., None]
    return v * np.array([1.0 + warm, 1.0, 1.0 - warm])


# ============================================================ asfalto nuevo
def asphalt_new():
    s = S
    # agregado: piedras medianas (8-12 mm) + finas (3-6 mm) + arena (por píxel)
    h_big, t_big, m_big = stones(s, 7000, 1.6, 3.2, seed=101)
    h_sm, t_sm, m_sm = stones(s, 52000, 0.7, 1.7, seed=102)
    h_big = jitter_warp(h_big, s, 3.0, 110)
    t_big = jitter_warp(t_big, s, 3.0, 110)
    m_big = h_big > 0.05
    sand = np.random.default_rng(103).random((s, s))
    sand = 0.6 * sand + 0.4 * blur_wrap(sand, 0.8)
    macro = fbm(s, 3, 5, seed=104)
    meso = fbm(s, 16, 4, seed=105)
    # marcas de compactación del rodillo: bandas suaves en un eje (tileables: frecuencia entera)
    yy = np.arange(s)[:, None] / s
    roll = 0.5 + 0.5 * np.sin(2 * np.pi * 3 * yy + 2.0 * (fbm(s, 4, 3, seed=106) - 0.5)) * np.ones((1, s))

    stone_h = np.maximum(h_big, h_sm * 0.85)
    stone_t = np.where(h_big >= h_sm * 0.85, t_big, t_sm)
    is_stone = stone_h > 0.05
    binder_h = 0.18 + 0.14 * sand + 0.06 * meso
    # poros/vacíos entre piedras (puntos oscuros)
    pits = (np.random.default_rng(107).random((s, s)) > 0.985) & ~is_stone
    pits = ndimage.binary_dilation(pits, iterations=1) & ~is_stone
    height = np.where(is_stone, 0.32 + 0.6 * stone_h, binder_h)
    height = np.where(pits, 0.02, height)
    height = blur_wrap(height, 0.45)

    # color (sRGB): ligante casi negro, piedras grises recubiertas parcialmente de ligante
    binder_c = 0.125 + 0.025 * sand + 0.02 * (meso - 0.5)
    stone_v = 0.17 + 0.17 * stone_t                  # tono de la roca
    expo = np.clip(0.15 + 0.45 * stone_h * (0.6 + 0.6 * fbm(s, 32, 3, seed=108)), 0, 1)  # cuánto asoma
    stone_c = binder_c + (stone_v - binder_c) * expo
    v = np.where(is_stone, stone_c, binder_c)
    v = np.where(pits, 0.06, v)
    v *= 1.0 + 0.10 * (macro - 0.5) + 0.04 * (roll - 0.5)
    warm = np.where(is_stone, 0.04 * (stone_t - 0.4), 0.01)   # unas rocas algo ocres, otras frías
    alb = grey(v, 0) * 1.0
    alb[..., 0] *= 1 + warm
    alb[..., 2] *= 1 - warm
    # polvo muy leve en los huecos
    low = smoothstep(0.25, 0.1, height)
    alb = lerp(alb, np.array([0.30, 0.29, 0.27]), low * 0.12 * fbm(s, 8, 4, seed=109))

    rough = np.where(is_stone, 0.86 + 0.08 * stone_t, 0.74 + 0.08 * sand)
    rough = rough - 0.05 * (macro - 0.5) - 0.03 * (roll - 0.5)
    rough = np.clip(np.where(pits, 0.95, rough), 0, 1)
    ao = np.clip(1.0 - np.clip((blur_wrap(height, 2.0) - height) * 3.0, 0, 1) * 0.9, 0, 1)
    ao = np.minimum(ao, np.where(pits, 0.45, 1.0))
    nrm = height_to_normal(height, 3.2)
    paths = save_pbr(f"{OUT}/asphalt_new", alb, rough=rough, ao=ao, normal=nrm)
    return paths, height, stone_h


# ============================================================ asfalto gastado
def asphalt_worn():
    s = S
    rng = np.random.default_rng(200)
    # agregado a 5.9 mm/px: piedras más pequeñas en píxeles y MÁS expuestas (ligante erosionado)
    h_big, t_big, _ = stones(s, 9000, 1.1, 2.3, seed=201)
    h_sm, t_sm, _ = stones(s, 70000, 0.5, 1.2, seed=202)
    h_big = jitter_warp(h_big, s, 2.0, 210)
    t_big = jitter_warp(t_big, s, 2.0, 210)
    stone_h = np.maximum(h_big, h_sm * 0.85)
    stone_t = np.where(h_big >= h_sm * 0.85, t_big, t_sm)
    is_stone = stone_h > 0.05
    sand = rng.random((s, s))
    sand = 0.55 * sand + 0.45 * blur_wrap(sand, 0.9)
    macro = fbm(s, 2, 6, seed=203)
    meso = fbm(s, 12, 5, seed=204)
    blotch = fbm(s, 6, 5, seed=205)

    binder_h = 0.2 + 0.15 * sand
    height = np.where(is_stone, 0.3 + 0.55 * stone_h, binder_h)
    binder_c = 0.215 + 0.04 * sand + 0.05 * (meso - 0.5)        # ligante oxidado gris
    stone_c = binder_c + (0.27 + 0.17 * stone_t - binder_c) * np.clip(0.35 + 0.45 * stone_h, 0, 1)
    v = np.where(is_stone, stone_c, binder_c)
    v *= 1.0 + 0.16 * (macro - 0.5) + 0.08 * (blotch - 0.5)
    warm = np.where(is_stone, 0.05 * (stone_t - 0.4), 0.015)
    alb = grey(v)
    alb[..., 0] *= 1 + warm
    alb[..., 2] *= 1 - warm
    rough = np.where(is_stone, 0.88 + 0.07 * stone_t, 0.82 + 0.08 * sand)
    rough = rough - 0.06 * (blotch - 0.5)
    # polvo/arena clara en los huecos (zona seca de Medellín)
    low = smoothstep(0.3, 0.18, height)
    dust = fbm(s, 10, 4, seed=206)
    alb = lerp(alb, np.array([0.42, 0.40, 0.37]), low * (0.15 + 0.25 * dust))

    # ---------- parches de reparación (rectángulos de asfalto más nuevo, con junta sellada)
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float64)
    ej_y = (fbm(s, 32, 3, seed=220) - 0.5) * 5
    ej_x = (fbm(s, 32, 3, seed=221) - 0.5) * 5
    patch = np.zeros((s, s))
    seam = np.zeros((s, s))
    rects = [(190, 300, 105, 80), (700, 770, 150, 64), (900, 520, 46, 40)]
    for i, (cy, cx, hy, hx) in enumerate(rects):
        dy = wrap_dist(cy, yy + ej_y, s)
        dx = wrap_dist(cx, xx + ej_x, s)
        inside = np.maximum(dy / hy, dx / hx)                  # 1 = borde
        edge_px = np.minimum(hy - dy, hx - dx)                 # px al borde (positivo dentro)
        patch = np.maximum(patch, (inside < 1.0).astype(float))
        seam = np.maximum(seam, smoothstep(2.6, 0.6, np.abs(edge_px)) * (inside < 1.3)
                          * smoothstep(0.3, 0.55, fbm(s, 12, 3, seed=225 + i)))
    patch = blur_wrap(patch, 0.6)
    ph, pt, _ = stones(s, 60000, 0.6, 1.5, seed=230)
    p_is = ph > 0.05
    p_bind = 0.15 + 0.03 * sand
    p_v = np.where(p_is, p_bind + (0.20 + 0.12 * pt - p_bind) * (0.3 + 0.5 * ph), p_bind)
    p_v *= 1.0 + 0.06 * (fbm(s, 8, 4, seed=231) - 0.5)
    p_alb = grey(p_v, 0.01)
    p_h = np.where(p_is, 0.34 + 0.5 * ph, 0.22 + 0.12 * sand)
    p_r = np.where(p_is, 0.84, 0.70 + 0.06 * sand)
    alb = lerp(alb, p_alb, patch)
    height = lerp(height, p_h, patch)
    rough = lerp(rough, p_r, patch)

    # ---------- grietas: bloque (grandes) + piel de cocodrilo (zonas) + finas sueltas
    e_main = periodic_edges(s, 14, 240, warp_px=90, warp_cells=4, fine_warp=10)
    e_alli = periodic_edges(s, 160, 241, warp_px=30, warp_cells=8, fine_warp=6)
    e_fine = periodic_edges(s, 40, 242, warp_px=140, warp_cells=6, fine_warp=12)
    zone_main = smoothstep(0.38, 0.52, fbm(s, 3, 4, seed=243))
    zone_alli = smoothstep(0.62, 0.72, fbm(s, 4, 4, seed=244))
    zone_fine = smoothstep(0.45, 0.6, fbm(s, 5, 4, seed=245))
    breakup = smoothstep(0.32, 0.5, fbm(s, 24, 4, seed=246))   # grietas que se interrumpen
    width_mod = 0.7 + 0.8 * fbm(s, 16, 3, seed=247)
    c_main = smoothstep(1.3 * width_mod, 0.2, e_main) * zone_main
    c_alli = smoothstep(0.9 * width_mod, 0.1, e_alli) * zone_alli
    c_fine = smoothstep(0.8, 0.05, e_fine) * zone_fine * breakup
    crack = np.clip(np.maximum.reduce([c_main, c_alli, c_fine]), 0, 1) * (1 - patch)
    # sello de brea sobre algunas grietas principales (banda ancha, negra y brillante)
    seal_zone = smoothstep(0.55, 0.62, fbm(s, 4, 3, seed=248)) * zone_main
    seal = smoothstep(5.0, 2.5, e_main + (fbm(s, 48, 3, seed=249) - 0.5) * 2.0) * seal_zone * (1 - patch)
    seal = np.maximum(seal, seam)
    seal_c = grey(0.07 + 0.02 * sand)
    alb = lerp(alb, seal_c, seal * 0.8)
    height = lerp(height, 0.30 + 0.04 * sand, seal)
    rough = lerp(rough, 0.48 + 0.08 * sand, seal)
    # grieta: oscuro + bordes con polvo claro (desmoronados)
    crack_rim = np.clip(blur_wrap(crack, 2.2) * 2.0 - crack, 0, 1) * (1 - seal)
    alb = lerp(alb, np.array([0.40, 0.39, 0.36]), crack_rim * 0.25)
    crack_eff = crack * (1 - seal)
    alb = lerp(alb, grey(0.035), crack_eff * 0.9)
    height = height - crack_eff * 0.35
    rough = lerp(rough, 0.95, crack_eff)

    # ---------- manchas de aceite (con halo más oscuro y menos rugosas)
    oil = np.zeros((s, s))
    oil_w = fbm(s, 16, 4, seed=260)
    spots = [(420, 520, 40, 26), (450, 590, 26, 18), (820, 230, 55, 34), (120, 840, 30, 22), (300, 90, 20, 16)]
    for i, (cy, cx, ry, rx) in enumerate(spots):
        dy = wrap_dist(cy, yy + (oil_w - 0.5) * 30, s) / ry
        dx = wrap_dist(cx, xx + (fbm(s, 16, 4, seed=261 + i) - 0.5) * 30, s) / rx
        d = np.sqrt(dy * dy + dx * dx)
        o = smoothstep(1.15, 0.55, d) * (0.6 + 0.4 * fbm(s, 32, 3, seed=270 + i))
        oil = np.maximum(oil, o)
    oil_rim = np.clip(oil - blur_wrap(oil, 3.0), 0, 1) * 2.0
    drips = smoothstep(0.78, 0.86, fbm(s, 40, 3, seed=280)) * smoothstep(0.55, 0.7, fbm(s, 6, 3, seed=281))
    oil = np.clip(oil + drips * 0.6, 0, 1)
    alb = alb * (1 - 0.55 * oil[..., None]) * np.array([1.0, 0.98, 0.95]) ** oil[..., None]
    alb = alb * (1 - 0.25 * np.clip(oil_rim, 0, 1)[..., None])
    rough = lerp(rough, 0.42, oil * 0.85)

    # ---------- marcas de llanta / suciedad general (muy leve) y pulido
    tyre = smoothstep(0.55, 0.75, fbm(s, 8, 5, seed=290)) * 0.08
    alb = alb * (1 - tyre[..., None])
    rough = rough - tyre * 0.6

    height = blur_wrap(height, 0.4)
    ao = np.clip(1.0 - np.clip((blur_wrap(height, 2.5) - height) * 3.0, 0, 1), 0.25, 1.0)
    ao = np.minimum(ao, 1 - crack_eff * 0.6)
    nrm = height_to_normal(height, 3.0)
    return save_pbr(f"{OUT}/asphalt_worn", np.clip(alb, 0, 1), rough=np.clip(rough, 0, 1), ao=ao, normal=nrm)


# ============================================================ atlas de pintura vial
# Rectángulos en px (x0, y0, x1, y1) dentro del atlas 1024. 1 px = 2.5 mm.
# Convención: la dirección de la vía es el eje V (vertical de la imagen); flechas y textos se
# leen desde abajo (el conductor viene desde V=1 hacia V=0).
LAYOUT = {
    "line_yellow": (0, 0, 80, 1024),       # línea continua amarilla 12 cm, tilea en V (2.56 m)
    "dash_white": (80, 0, 160, 1024),      # un trazo de discontinua blanca 12 cm x 2.4 m
    "line_white": (160, 0, 240, 1024),     # línea continua blanca 12 cm (borde/pare), tilea en V
    "zebra_bar": (256, 0, 1024, 320),      # una franja de cebra 0.5 m x 1.8 m (largo en U)
    "arrow_straight": (256, 320, 448, 1024),
    "arrow_turn": (448, 320, 704, 1024),   # giro a la derecha (espejar U para izquierda)
    "num_30": (704, 320, 1024, 672),
    "text_pare": (704, 672, 1024, 1024),
}


def _poly_mask(size_xy, draw_fn, ss=4):
    w, h = size_xy
    im = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(im)
    draw_fn(d, ss)
    im = im.resize((w, h), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255


def _text_mask(text, w, h, box, font_path, ss=3):
    """Texto vial: glifos estirados en el sentido de la vía para leerse en perspectiva."""
    font = ImageFont.truetype(font_path, 400)
    tmp = Image.new("L", (400 * len(text) + 200, 600), 0)
    d = ImageDraw.Draw(tmp)
    d.text((50, 50), text, fill=255, font=font)
    bb = tmp.getbbox()
    g = tmp.crop(bb)
    x0, y0, x1, y1 = box
    g = g.resize(((x1 - x0) * ss, (y1 - y0) * ss), Image.LANCZOS)
    im = Image.new("L", (w * ss, h * ss), 0)
    im.paste(g, (x0 * ss, y0 * ss))
    im = im.resize((w, h), Image.LANCZOS)
    return np.asarray(im, dtype=np.float64) / 255


def road_decals(asph_height, asph_stone):
    s = S
    shape = np.zeros((s, s))
    paint = np.zeros((s, s, 3))
    wear_bias = np.zeros((s, s))        # desgaste extra (huellas de llanta)
    WHITE = np.array([0.86, 0.86, 0.83])
    YELLOW = np.array([0.90, 0.68, 0.13])
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float64)

    def region(name):
        x0, y0, x1, y1 = LAYOUT[name]
        return (slice(y0, y1), slice(x0, x1)), (x1 - x0, y1 - y0)

    # --- líneas
    sl, _ = region("line_yellow")
    m = ((xx >= 16) & (xx < 64)).astype(float)
    shape[sl] = np.maximum(shape[sl], m[sl])
    paint[sl] = YELLOW
    sl, _ = region("dash_white")
    m = ((xx >= 96) & (xx < 144) & (yy >= 32) & (yy < 992)).astype(float)
    shape[sl] = np.maximum(shape[sl], m[sl])
    paint[sl] = WHITE
    sl, _ = region("line_white")
    m = ((xx >= 176) & (xx < 224)).astype(float)
    shape[sl] = np.maximum(shape[sl], m[sl])
    paint[sl] = WHITE
    # huella de llanta que pasa sobre las líneas en tramos (bandas a lo ancho en V)
    for nm in ("line_yellow", "dash_white", "line_white"):
        sl, _ = region(nm)
        band = smoothstep(0.55, 0.75, fbm(s, 4, 3, seed=300 + len(nm)))[sl]
        wear_bias[sl] = np.maximum(wear_bias[sl], band * 0.25)

    # --- franja de cebra (0.5 m de ancho = 200 px, 1.8 m de largo = 720 px), largo a lo largo de U
    sl, (w, h) = region("zebra_bar")
    x0, y0 = LAYOUT["zebra_bar"][:2]
    m = ((xx >= x0 + 24) & (xx < x0 + 744) & (yy >= y0 + 60) & (yy < y0 + 260)).astype(float)
    shape[sl] = np.maximum(shape[sl], m[sl])
    paint[sl] = WHITE
    # una huella de llanta recorre la franja a lo largo (banda en V del rectángulo)
    track = smoothstep(70, 20, np.abs(yy - (y0 + 175))) * 0.45
    wear_bias[sl] = np.maximum(wear_bias[sl], track[sl])

    # --- flecha recta
    sl, (w, h) = region("arrow_straight")
    x0, y0 = LAYOUT["arrow_straight"][:2]

    def straight(d, ss):
        cx = w / 2
        d.polygon([(cx * ss, 24 * ss), ((cx + 84) * ss, 290 * ss), ((cx + 28) * ss, 270 * ss),
                   ((cx + 28) * ss, 680 * ss), ((cx - 28) * ss, 680 * ss), ((cx - 28) * ss, 270 * ss),
                   ((cx - 84) * ss, 290 * ss)], fill=255)
    m = _poly_mask((w, h), straight)
    shape[sl] = np.maximum(shape[sl], m)
    paint[sl] = WHITE

    # --- flecha de giro (derecha)
    sl, (w, h) = region("arrow_turn")

    def turn(d, ss):
        r = 28 * ss
        pts = [(68, 680 - t) for t in np.linspace(0, 330, 120)]
        cx, cy, R = 168, 350, 100
        for a in np.linspace(np.pi, 1.5 * np.pi, 80):
            pts.append((cx + R * np.cos(a), cy + R * np.sin(a)))
        pts += [(168 + t, 250) for t in np.linspace(0, 12, 6)]
        for (px, py) in pts:
            d.ellipse([px * ss - r, py * ss - r, px * ss + r, py * ss + r], fill=255)
        d.polygon([(176 * ss, 150 * ss), (248 * ss, 250 * ss), (176 * ss, 350 * ss), (190 * ss, 250 * ss)], fill=255)
        d.polygon([(176 * ss, 150 * ss), (248 * ss, 250 * ss), (176 * ss, 350 * ss)], fill=255)
    m = _poly_mask((w, h), turn)
    shape[sl] = np.maximum(shape[sl], m)
    paint[sl] = WHITE

    font = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
    if not os.path.exists(font):
        font = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
    # --- "30"
    sl, (w, h) = region("num_30")
    m = _text_mask("30", w, h, (30, 24, w - 30, h - 24), font)
    shape[sl] = np.maximum(shape[sl], m)
    paint[sl] = WHITE
    # --- "PARE"
    sl, (w, h) = region("text_pare")
    m = _text_mask("PARE", w, h, (16, 30, w - 16, h - 30), font)
    shape[sl] = np.maximum(shape[sl], m)
    paint[sl] = WHITE

    # ---------- desgaste: asfalto asomando por la pintura (cimas del agregado), descascarado, llantas
    stone = asph_stone                                   # mismo grano que asphalt_new (escala distinta, da igual)
    chips = fbm(s, 24, 5, seed=310)
    large = fbm(s, 6, 5, seed=311)
    speck = np.random.default_rng(312).random((s, s))
    integrity = 0.55 * chips + 0.45 * large - 0.22 * stone * (0.3 + 0.7 * (1 - large)) - 0.04 * speck
    thr = 0.10 + wear_bias * 1.1
    keep = smoothstep(thr - 0.03, thr + 0.05, integrity)
    # borde levemente irregular (pintura aplicada con máquina, overspray mínimo)
    edge_n = (fbm(s, 64, 3, seed=313) - 0.5) * 0.25
    shp = smoothstep(0.35, 0.65, shape + edge_n * (shape > 0.02) * (shape < 0.98))
    alpha = shp * (0.2 + 0.8 * keep)                         # pintura delgada pero presente
    alpha *= np.clip(1.0 - 0.6 * stone * smoothstep(0.35, 0.12, integrity), 0, 1)
    alpha = np.where(keep < 0.15, alpha * 0.25, alpha)

    # color: suciedad, marcas de llanta oscuras en zonas de desgaste, grano del asfalto bajo la pintura
    grime = fbm(s, 10, 5, seed=314)
    col = paint * (0.86 + 0.14 * grime[..., None])
    col = col * (1 - (0.25 * wear_bias + 0.10 * (1 - keep))[..., None])
    col = col * (1 - 0.12 * smoothstep(0.3, 0.9, asph_height)[..., None] * 0)  # (reservado)
    col = col * (0.93 + 0.07 * (1 - stone))[..., None]
    col = lerp(col, np.array([0.25, 0.24, 0.22]), np.clip((1 - keep) * 0.35, 0, 1))
    # sangrado de color: fuera de la forma conserva el color de la pintura (sin halos al hacer mipmaps)
    near = ndimage.binary_dilation(shp > 0.01, iterations=6)
    col = np.where(near[..., None], col, paint * 0.9)

    # alto: espesor de pintura + piedras del asfalto que se marcan a través
    ph = alpha * 0.35 + asph_height * 0.5
    nrm = height_to_normal(ph, 2.5)
    rough = np.clip(0.52 + 0.12 * grime + 0.18 * (1 - keep) + 0.1 * wear_bias, 0, 1)
    ao = np.clip(1 - 0.25 * (1 - asph_height), 0.6, 1)

    base = os.path.join(ROOT, OUT, "road_decals")
    os.makedirs(os.path.dirname(base), exist_ok=True)
    rgba = np.dstack([to_u8(col), to_u8(alpha)])
    Image.fromarray(rgba, "RGBA").save(base + "_albedo.png", optimize=True)
    # normal/ORM del atlas a 512 (detalle suave; ahorra memoria y disco). El albedo RGBA queda a 1024.
    Image.fromarray(to_u8(nrm), "RGB").resize((512, 512), Image.LANCZOS).save(base + "_normal.png", optimize=True)
    Image.fromarray(to_u8(np.stack([ao, rough, np.zeros_like(ao)], -1)), "RGB").resize(
        (512, 512), Image.LANCZOS).save(base + "_orm.png", optimize=True)
    return alpha, col


def decal_preview(alpha, col, under_png, out_png):
    """Compone el atlas sobre el asfalto nuevo para revisar."""
    under = np.asarray(Image.open(under_png).convert("RGB"), dtype=np.float64) / 255
    comp = under * (1 - alpha[..., None]) + col * alpha[..., None]
    Image.fromarray(to_u8(comp)).save(out_png)


def quantize_png(rel, step):
    """Cuantiza a múltiplos de `step` (invisible tras la compresión VRAM) para que el PNG pese menos."""
    path = os.path.join(ROOT, rel)
    im = Image.open(path)
    a = np.asarray(im).astype(np.int32)
    a = np.clip((a + step // 2) // step * step, 0, 255).astype(np.uint8)
    Image.fromarray(a, im.mode).save(path, optimize=True)


def main():
    os.makedirs(PREV, exist_ok=True)
    _, hnew, snew = asphalt_new()
    asphalt_worn()
    alpha, col = road_decals(hnew, snew)
    for n in ("asphalt_new", "asphalt_worn"):
        quantize_png(f"{OUT}/{n}_normal.png", 3)
        quantize_png(f"{OUT}/{n}_orm.png", 2)
    for n in ("asphalt_new", "asphalt_worn"):
        preview(f"{OUT}/{n}", f"{PREV}/{n}_preview.png")
    decal_preview(alpha, col, os.path.join(ROOT, OUT, "asphalt_new_albedo.png"), f"{PREV}/decals_on_asphalt.png")
    sheet = [f"{PREV}/asphalt_new_preview.png", f"{PREV}/asphalt_worn_preview.png",
             f"{PREV}/decals_on_asphalt.png", os.path.join(ROOT, OUT, "asphalt_worn_albedo.png")]
    contact_sheet(sheet, f"{PREV}/contact.png", cell=512)
    tot = sum(os.path.getsize(os.path.join(ROOT, OUT, f)) for f in os.listdir(os.path.join(ROOT, OUT))
              if f.endswith(".png"))
    print(f"OK  {tot / 1e6:.2f} MB en {OUT}")


if __name__ == "__main__":
    main()

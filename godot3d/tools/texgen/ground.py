"""Familia "ground" (Fase 1): cortezas, tierra, pasto y musgo.

Regenerar:  python3 tools/texgen/ground.py          (desde godot3d/)
Salida:     art/tex/ground/<nombre>_{albedo,normal,orm}.png
Previews:   /tmp/f1_ground/

Sets y escala física (1 tile):
  corteza_tropical   1024 px = 2 m x 2 m   corteza fisurada vertical + musgo + líquen (UV cilíndrica)
  corteza_lisa        512 px = 1 m x 1 m   corteza lisa clara (guayacán/urapán) con manchas de líquen (UV cilíndrica)
  palma               512 px = 1 m x 1 m   tronco de palma, anillos horizontales + cicatrices de hoja (UV cilíndrica)
  pasto              1024 px = 3 m x 3 m   pasto corto de jardinera con calvas de tierra (triplanar / suelo)
  mantillo            512 px = 2 m x 2 m   tierra de jardinera con hojarasca seca y piedritas
  musgo               512 px = 1 m x 1 m   musgo puro para mezclar en juntas/bordes

Las cortezas tilean en U (vuelta del tronco) y V (altura). En U el número de repeticiones
alrededor del tronco debe ser entero (lo calcula mat_ground.gd) para que no haya costura.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from common import (ROOT, ao_from_height, blur_wrap, contact_sheet, fbm, gradient_map,  # noqa: E402
                    height_to_normal, lerp, normalize, preview, save_pbr, warp)

OUT = "art/tex/ground"
PREV = "/tmp/f1_ground"


# ----------------------------------------------------------------- utilidades propias
def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def vnoise2(size: int, cy: int, cx: int, rng) -> np.ndarray:
    """Ruido de valor periódico anisotrópico (celdas cy filas x cx columnas)."""
    grid = rng.random((cy, cx))

    def axis(cells):
        c = np.arange(size) * cells / size
        i0 = np.floor(c).astype(int)
        f = c - i0
        f = f * f * f * (f * (f * 6 - 15) + 10)
        return i0 % cells, (i0 + 1) % cells, f

    y0, y1, fy = axis(cy)
    x0, x1, fx = axis(cx)
    fy = fy[:, None]
    fx = fx[None, :]
    a = grid[np.ix_(y0, x0)]; b = grid[np.ix_(y0, x1)]
    c = grid[np.ix_(y1, x0)]; d = grid[np.ix_(y1, x1)]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm2(size: int, cy: int, cx: int, octaves: int = 5, gain: float = 0.5, seed: int = 0) -> np.ndarray:
    """fBm anisotrópico tileable: cy, cx = celdas base por eje (enteros)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size)); amp = 1.0; tot = 0.0
    for _ in range(octaves):
        if cy > size or cx > size:
            break
        out += amp * vnoise2(size, cy, cx, rng)
        tot += amp; amp *= gain; cy *= 2; cx *= 2
    return normalize(out / tot)


def worley_aniso(size: int, points: int, seed: int, sy: float = 1.0, sx: float = 1.0,
                 coords=None):
    """Worley tileable con métrica anisotrópica. Devuelve F1, F2 (en px) e id de celda.
    coords: (yy, xx) opcional para muestrear en coordenadas deformadas (warp)."""
    rng = np.random.default_rng(seed)
    pts = rng.random((points, 2)) * size
    if coords is None:
        yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    else:
        yy, xx = coords
    f1 = np.full(yy.shape, np.inf, np.float32)
    f2 = np.full(yy.shape, np.inf, np.float32)
    ids = np.zeros(yy.shape, np.int32)
    for i, (py, px) in enumerate(pts):
        dy = np.abs(yy - py) % size; dy = np.minimum(dy, size - dy) * sy
        dx = np.abs(xx - px) % size; dx = np.minimum(dx, size - dx) * sx
        d = np.sqrt(dx * dx + dy * dy)
        c1 = d < f1
        f2 = np.where(c1, f1, np.minimum(f2, d))
        ids = np.where(c1, i, ids)
        f1 = np.where(c1, d, f1)
    return f1, f2, ids


def wrap_offsets(bbox, size):
    """Desplazamientos (dx,dy) necesarios para dibujar una figura de forma tileable."""
    x0, y0, x1, y1 = bbox
    offs = []
    for oy in (-size, 0, size):
        for ox in (-size, 0, size):
            if x1 + ox >= 0 and x0 + ox < size and y1 + oy >= 0 and y0 + oy < size:
                offs.append((ox, oy))
    return offs


def hsv_jitter(rgb, rng, amt=0.08):
    rgb = np.asarray(rgb, float)
    return np.clip(rgb * (1 + rng.normal(0, amt, 3)) * (1 + rng.normal(0, amt)), 0, 1)


def coords_warped(size, seed, strength, cells=3, cy=None, cx=None):
    if cy is None:
        dx = fbm(size, cells, 4, seed=seed); dy = fbm(size, cells, 4, seed=seed + 1)
    else:
        dx = fbm2(size, cy, cx, 4, seed=seed); dy = fbm2(size, cy, cx, 4, seed=seed + 1)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    return (yy + (dy - 0.5) * strength).astype(np.float32), (xx + (dx - 0.5) * strength).astype(np.float32)


# ----------------------------------------------------------------- capas compartidas
def moss_layer(size, seed, px_per_m):
    """Altura y color de musgo: grumos ~2.5 cm + pelusa fina + puntas claras. Sin celdas
    (el worley daba aspecto de escamas)."""
    clump = int(np.clip(size / max(4.0, px_per_m * 0.025), 8, size // 2))
    fuzz = int(np.clip(clump * 4, 16, size // 2))
    c = fbm(size, clump, 3, gain=0.5, seed=seed)
    c = warp(c, fbm(size, clump, 2, seed=seed + 1), fbm(size, clump, 2, seed=seed + 2), size / clump * 0.8)
    c = smoothstep(0.25, 0.8, c) ** 0.8                   # cojines redondeados
    f = fbm(size, fuzz, 2, seed=seed + 3)
    rng = np.random.default_rng(seed + 4)
    tips = blur_wrap(rng.random((size, size)), 0.6)
    tips = smoothstep(0.56, 0.66, tips)
    macro = fbm(size, 3, 4, seed=seed + 5)
    h = normalize(0.6 * c + 0.28 * f + 0.12 * macro)
    t = np.clip(0.55 * h + 0.45 * macro - 0.05, 0, 1)
    col = gradient_map(t, [
        (0.0, (0.06, 0.08, 0.025)),
        (0.3, (0.15, 0.21, 0.05)),
        (0.6, (0.27, 0.35, 0.09)),
        (0.85, (0.40, 0.46, 0.14)),
        (1.0, (0.50, 0.51, 0.21)),
    ])
    col = lerp(col, col * 1.45 + np.array([0.03, 0.03, 0.0]), tips * h * 0.8)
    return h, np.clip(col, 0, 1)


def lichen_layer(size, seed, cells, thr, light=(0.70, 0.72, 0.66), dark=(0.52, 0.56, 0.48)):
    """Líquen crustáceo: manchas irregulares (umbral de fBm deformado) con borde más oscuro
    y grano interno. cells = frecuencia base (más = manchas más pequeñas); thr = umbral (más = menos área)."""
    n = fbm(size, cells, 5, gain=0.55, seed=seed)
    n = warp(n, fbm(size, cells * 2, 3, seed=seed + 1), fbm(size, cells * 2, 3, seed=seed + 2), size / cells * 0.6)
    m = smoothstep(thr, thr + 0.025, n)
    core = smoothstep(thr + 0.03, thr + 0.12, n)
    grain = fbm(size, max(32, size // 6), 2, seed=seed + 6)
    ring = np.clip(m - core, 0, 1)
    m = m * (0.55 + 0.6 * grain)
    col = lerp(np.array(light), np.array(dark), np.clip(ring * 0.9 + 0.5 * (1 - grain), 0, 1))
    return np.clip(m, 0, 1), col


# ----------------------------------------------------------------- 1 corteza tropical
def corteza_tropical(size=1024):
    """1024 px = 2 m. Crestas verticales que se bifurcan, separadas por fisuras profundas; musgo y líquen."""
    S = size
    cw = coords_warped(S, 101, S * 0.06, cy=2, cx=5)

    def contour(cy, cx, seed, width):
        n = fbm2(S, cy, cx, 4, gain=0.45, seed=seed)
        n = warp(n, *[fbm(S, 4, 3, seed=seed + k) for k in (1, 2)], S * 0.02)
        d = np.abs(n - 0.5)                                 # 0 en la curva de nivel => fisura
        return d, n

    d1, n1 = contour(3, 16, 130, 0)                         # fisuras mayores (~12 cm entre crestas)
    d2, n2 = contour(5, 34, 140, 0)                         # fisuras menores
    fiss = np.maximum(1 - smoothstep(0.0, 0.05, d1), 0.6 * (1 - smoothstep(0.0, 0.02, d2)))
    fiss_w = np.maximum(1 - smoothstep(0.0, 0.15, d1), 0.5 * (1 - smoothstep(0.0, 0.06, d2)))
    # cortes horizontales ocasionales entre placas
    f1, f2, ids = worley_aniso(S, 90, 100, sy=0.3, sx=1.0, coords=cw)
    hcut = (1 - smoothstep(0.0, 4.0, f2 - f1)) * smoothstep(0.55, 0.75, fbm(S, 6, 3, seed=150))
    rng = np.random.default_rng(102)
    plate_h = rng.random(90)[ids]
    stri = fbm2(S, 4, 96, 4, seed=103)                      # estrías verticales finas
    micro = fbm(S, 96, 3, seed=104)
    macro = fbm(S, 2, 4, seed=105)
    flake = smoothstep(0.6, 0.75, fbm2(S, 24, 40, 3, seed=106))   # escamas que se desprenden
    h = (0.6 + 0.12 * plate_h + 0.12 * stri + 0.05 * micro + 0.04 * flake) * (1 - 0.75 * fiss_w ** 1.4) \
        - 0.3 * fiss - 0.15 * hcut
    h = normalize(h)

    # color base: marrón oscuro rojizo, topes de placa más grises (meteorizados)
    tone = np.clip(0.4 * plate_h + 0.3 * stri + 0.4 * macro - 0.05, 0, 1)
    bark = gradient_map(tone, [
        (0.0, (0.13, 0.095, 0.075)),
        (0.4, (0.21, 0.16, 0.125)),
        (0.7, (0.28, 0.22, 0.18)),
        (1.0, (0.36, 0.32, 0.28)),
    ])
    bark = bark * (0.85 + 0.25 * micro[..., None]) * (1 + 0.15 * flake[..., None])
    bark = lerp(bark, np.array([0.05, 0.038, 0.03]), np.clip(fiss_w ** 1.2 * 1.05 + hcut * 0.6, 0, 1))

    # musgo: parches macro (~30 % del área), se mete en fisuras alrededor de los parches
    mh, mcol = moss_layer(S, 110, S / 2)
    mcol = lerp(mcol, mcol.mean(-1, keepdims=True), 0.2) * 0.9
    mm_macro = fbm2(S, 2, 3, 5, seed=111)
    edge_n = fbm(S, 24, 3, seed=112) - 0.5
    mm = smoothstep(0.58, 0.68, mm_macro + 0.12 * fiss_w + 0.12 * edge_n)
    mm = np.clip(mm + 0.8 * fiss_w * smoothstep(0.45, 0.58, mm_macro + 0.1 * edge_n), 0, 1)
    # verdín (alga fina) que tiñe la corteza alrededor del musgo
    verdin = smoothstep(0.4, 0.6, mm_macro) * (1 - mm)
    # líquen gris en placas expuestas, menos donde hay musgo
    lm, lcol = lichen_layer(S, 120, 10, 0.66, light=(0.60, 0.62, 0.56), dark=(0.42, 0.45, 0.40))
    lm = lm * (1 - 0.8 * fiss_w) * (1 - mm) * 0.8

    alb = lerp(bark, bark * np.array([0.85, 1.05, 0.7]) + np.array([0.02, 0.04, 0.0]), verdin * 0.7)
    alb = lerp(alb, mcol, mm)
    alb = lerp(alb, lcol, lm)
    height = normalize(h + 0.12 * mm * mh + 0.03 * lm)
    rough = np.clip(0.80 + 0.12 * fiss_w + 0.06 * mm - 0.06 * flake + 0.05 * (micro - 0.5), 0, 1)
    ao = np.clip(ao_from_height(height, 8, 1.6) * (1 - 0.45 * fiss), 0, 1)
    nrm = height_to_normal(blur_wrap(height, 0.6), 7.0)
    return save_pbr(f"{OUT}/corteza_tropical", alb, height=height, rough=rough, ao=ao, normal=nrm)


# ----------------------------------------------------------------- 2 corteza lisa clara
def corteza_lisa(size=512):
    """512 px = 1 m. Corteza lisa gris-beige (guayacán/urapán) con lenticelas y líquen."""
    S = size
    macro = fbm2(S, 2, 3, 5, seed=201)
    stri = fbm2(S, 3, 40, 4, seed=202)                 # vetas verticales suaves
    micro = fbm(S, 48, 3, seed=203)
    base_t = np.clip(0.5 * macro + 0.25 * stri + 0.25 * micro, 0, 1)
    alb = gradient_map(base_t, [
        (0.0, (0.36, 0.34, 0.30)),
        (0.45, (0.50, 0.47, 0.41)),
        (0.8, (0.58, 0.55, 0.49)),
        (1.0, (0.64, 0.61, 0.55)),
    ])
    # pliegues horizontales leves (anillos de crecimiento de ramas) + lenticelas
    rng = np.random.default_rng(204)
    lent = np.zeros((S, S)); img = Image.new("L", (S, S), 0); d = ImageDraw.Draw(img)
    for _ in range(260):
        x, y = rng.random(2) * S
        w = rng.uniform(3, 9); hh = rng.uniform(0.8, 1.8)
        for ox, oy in wrap_offsets((x - w, y - hh, x + w, y + hh), S):
            d.ellipse((x - w + ox, y - hh + oy, x + w + ox, y + hh + oy), fill=int(rng.uniform(120, 255)))
    lent = blur_wrap(np.asarray(img, float) / 255, 1.0)
    folds = fbm2(S, 24, 3, 3, seed=205)
    fold = smoothstep(0.62, 0.8, folds) * smoothstep(0.4, 0.7, fbm(S, 4, 3, seed=206))
    alb = lerp(alb, np.array([0.34, 0.31, 0.27]), np.clip(lent * 0.45 + fold * 0.3, 0, 1))
    # manchas oscuras de humedad
    damp = smoothstep(0.55, 0.75, fbm2(S, 2, 4, 5, seed=207))
    alb = alb * (1 - 0.25 * damp[..., None])
    # líquen: blanco, verde-gris y algunas manchas anaranjadas
    l1, c1 = lichen_layer(S, 210, 6, 0.66, light=(0.76, 0.77, 0.73), dark=(0.60, 0.62, 0.57))
    l2, c2 = lichen_layer(S, 220, 8, 0.72, light=(0.60, 0.64, 0.54), dark=(0.47, 0.51, 0.42))
    l3, c3 = lichen_layer(S, 230, 12, 0.82, light=(0.70, 0.52, 0.30), dark=(0.56, 0.40, 0.24))
    alb = lerp(alb, c1, l1 * 0.9)
    alb = lerp(alb, c2, l2 * 0.85)
    alb = lerp(alb, c3, l3 * 0.6)
    h = normalize(0.5 * macro + 0.2 * stri + 0.12 * micro - 0.15 * lent - 0.2 * fold + 0.06 * (l1 + l2 + l3))
    rough = np.clip(0.62 + 0.15 * micro + 0.15 * (l1 + l2 + l3) + 0.08 * lent - 0.08 * damp, 0, 1)
    nrm = height_to_normal(h, 2.2)
    ao = np.clip(ao_from_height(h, 5, 1.0), 0, 1)
    return save_pbr(f"{OUT}/corteza_lisa", alb, height=h, rough=rough, ao=ao, normal=nrm)


# ----------------------------------------------------------------- 3 tronco de palma
def palma(size=512):
    """512 px = 1 m (alto). Anillos horizontales cada ~7-11 cm, cicatrices de hojas, grietas finas."""
    S = size
    rng = np.random.default_rng(301)
    # posiciones de anillos (debe sumar exactamente S para tilear en V)
    n = 11
    gaps = rng.uniform(0.75, 1.25, n); gaps = gaps / gaps.sum() * S
    ys = np.cumsum(gaps)
    wob = fbm2(S, 1, 5, 4, seed=302)                       # ondulación horizontal de anillos
    wob2 = fbm2(S, 1, 9, 3, seed=303)
    yy = np.mgrid[0:S, 0:S][0].astype(float)
    ring = np.zeros((S, S)); scar = np.zeros((S, S)); band_id = np.zeros((S, S))
    for i, y in enumerate(ys):
        yo = y + (wob - 0.5) * 10 + (wob2 - 0.5) * 4 + rng.uniform(-2, 2)
        d = (yy - yo + S / 2) % S - S / 2                   # distancia firmada con wrap
        w = rng.uniform(1.1, 2.2)
        ring = np.maximum(ring, np.exp(-(d / w) ** 2))
        # cicatriz: banda clara/oscura justo debajo del anillo (base de la hoja)
        sw = rng.uniform(7, 14)
        scar = np.maximum(scar, np.exp(-((d - sw * 0.6) / sw) ** 2) * (d > 0))
        band_id = np.where((d > 0) & (d < gaps[(i + 1) % n]), i, band_id)
    tone = rng.random(n)[band_id.astype(int)]
    vert = fbm2(S, 2, 48, 4, seed=304)                      # fibras/grietas verticales
    crack = smoothstep(0.72, 0.9, fbm2(S, 6, 70, 3, seed=305)) * (1 - ring)
    macro = fbm(S, 2, 4, seed=306)
    micro = fbm(S, 64, 3, seed=307)
    t = np.clip(0.35 * macro + 0.25 * tone + 0.25 * vert + 0.15 * micro, 0, 1)
    alb = gradient_map(t, [
        (0.0, (0.33, 0.32, 0.29)),
        (0.4, (0.46, 0.45, 0.41)),
        (0.75, (0.56, 0.55, 0.50)),
        (1.0, (0.63, 0.62, 0.57)),
    ])
    alb = lerp(alb, np.array([0.40, 0.33, 0.25]), scar * 0.35)           # cicatriz ligeramente parda
    lip = np.roll(ring, -3, axis=0)                         # labio claro sobre el anillo
    alb = lerp(alb, alb * 1.12, lip * 0.6)
    alb = lerp(alb, np.array([0.28, 0.27, 0.24]), np.clip(ring * 0.5 + crack * 0.4, 0, 1))
    # suciedad / algas verdosas en zonas macro (humedad de Medellín)
    alg = smoothstep(0.6, 0.8, fbm2(S, 2, 3, 5, seed=308))
    alb = lerp(alb, np.array([0.30, 0.34, 0.22]), alg * 0.45)
    lm, lc = lichen_layer(S, 310, 6, 0.72, light=(0.74, 0.75, 0.70), dark=(0.58, 0.60, 0.54))
    alb = lerp(alb, lc, lm * 0.7)
    h = normalize(0.6 - 0.25 * ring + 0.1 * lip + 0.12 * scar + 0.12 * vert + 0.05 * micro - 0.2 * crack)
    rough = np.clip(0.72 + 0.12 * vert + 0.1 * ring + 0.06 * alg, 0, 1)
    nrm = height_to_normal(h, 4.0)
    ao = np.clip(ao_from_height(h, 4, 0.7), 0, 1)
    return save_pbr(f"{OUT}/palma", alb, height=h, rough=rough, ao=ao, normal=nrm)


# ----------------------------------------------------------------- 4 pasto de jardinera
def soil_base(S, seed, px_per_m, wet=0.0):
    """Tierra oscura con grumos (~2-3 cm) y grano fino. Devuelve (color, altura, rough)."""
    macro = fbm(S, 3, 5, seed=seed)
    cl = int(np.clip(S / (px_per_m * 0.025), 8, S // 4))
    clod = fbm(S, cl, 3, gain=0.5, seed=seed + 1)
    clod = warp(clod, fbm(S, cl, 2, seed=seed + 4), fbm(S, cl, 2, seed=seed + 5), S / cl)
    clod = smoothstep(0.2, 0.85, clod)
    grain = fbm(S, max(16, S // 8), 3, seed=seed + 2)
    rng = np.random.default_rng(seed + 3)
    spk = blur_wrap(rng.random((S, S)), 0.5)
    t = np.clip(0.45 * macro + 0.3 * clod + 0.25 * grain, 0, 1)
    col = gradient_map(t, [
        (0.0, (0.085, 0.060, 0.045)),
        (0.45, (0.16, 0.115, 0.082)),
        (0.8, (0.25, 0.19, 0.14)),
        (1.0, (0.32, 0.26, 0.20)),
    ])
    col = col * (0.85 + 0.3 * spk[..., None]) * (1 - wet * 0.3)
    h = 0.5 * clod + 0.3 * grain + 0.1 * spk + 0.1 * macro
    rough = 0.92 - 0.2 * wet + 0.05 * (grain - 0.5)
    return col, h, rough


def draw_pebbles(S, rng, count, rmin, rmax, colA, colB):
    """Piedritas: devuelve (máscara, color, altura)."""
    cimg = Image.new("RGB", (S, S)); himg = Image.new("L", (S, S)); mimg = Image.new("L", (S, S))
    dc, dh, dm = ImageDraw.Draw(cimg), ImageDraw.Draw(himg), ImageDraw.Draw(mimg)
    for _ in range(count):
        x, y = rng.random(2) * S
        r = rng.uniform(rmin, rmax); ar = rng.uniform(0.6, 1.0); ang = rng.uniform(0, np.pi)
        k = rng.integers(6, 10)
        a = np.linspace(0, 2 * np.pi, k, endpoint=False) + rng.uniform(0, 1, k) * 0.4
        rr = r * rng.uniform(0.75, 1.1, k)
        px = rr * np.cos(a); py = rr * np.sin(a) * ar
        ca, sa = np.cos(ang), np.sin(ang)
        poly = np.stack([x + px * ca - py * sa, y + px * sa + py * ca], 1)
        c = np.clip(lerp(np.array(colA), np.array(colB), rng.random()) * rng.uniform(0.85, 1.12) * (1 + rng.normal(0, 0.02, 3)), 0, 1)
        for ox, oy in wrap_offsets((x - r, y - r, x + r, y + r), S):
            pts = [tuple(p) for p in poly + [ox, oy]]
            dc.polygon(pts, fill=tuple(int(v * 255) for v in c))
            dh.polygon(pts, fill=int(rng.uniform(170, 255)))
            dm.polygon(pts, fill=255)
    m = np.asarray(mimg, float) / 255
    h = blur_wrap(np.asarray(himg, float) / 255, max(1.0, rmin * 0.5)) * m
    return m, np.asarray(cimg, float) / 255, h


def pasto(size=1024):
    """1024 px = 3 m (~2.9 mm/px). Pasto corto (kikuyo) con hojas dibujadas, calvas de tierra."""
    S = size
    ppm = S / 3.0
    rng = np.random.default_rng(401)
    soil, sh, srough = soil_base(S, 410, ppm)
    # densidad: calvas grandes y pequeñas
    dens = np.clip(0.75 * fbm(S, 3, 5, seed=402) + 0.25 * fbm(S, 12, 3, seed=403), 0, 1)
    dens = smoothstep(0.22, 0.52, dens)
    # tono macro (parches más amarillos/secos y más oscuros/verdes)
    dry = fbm(S, 2, 5, seed=404)
    cimg = Image.new("RGB", (S, S)); cimg.paste(tuple(int(v * 255) for v in (0.12, 0.10, 0.06)), (0, 0, S, S))
    himg = Image.new("L", (S, S), 0); mimg = Image.new("L", (S, S), 0)
    dc, dh, dm = ImageDraw.Draw(cimg), ImageDraw.Draw(himg), ImageDraw.Draw(mimg)
    n_blades = 95000
    xs = rng.random(n_blades) * S; ys = rng.random(n_blades) * S
    keep = rng.random(n_blades) < dens[ys.astype(int), xs.astype(int)] ** 1.3
    xs, ys = xs[keep], ys[keep]
    hts = rng.random(len(xs))
    order = np.argsort(hts)                                 # bajas primero: las altas tapan
    green_dark = np.array([0.10, 0.17, 0.05]); green = np.array([0.22, 0.34, 0.09])
    green_light = np.array([0.36, 0.46, 0.14]); straw = np.array([0.50, 0.46, 0.25])
    for i in order:
        x, y, hgt = xs[i], ys[i], hts[i]
        L = rng.uniform(6, 18) * (0.6 + 0.6 * hgt)
        ang = rng.uniform(0, 2 * np.pi)
        bend = rng.uniform(-0.5, 0.5)
        dr = dry[int(y), int(x)]
        c = lerp(green_dark, green, hgt)
        c = lerp(c, green_light, max(0.0, hgt - 0.6) * 1.8)
        c = lerp(c, straw, np.clip((dr - 0.55) * 2.2 + rng.normal(0, 0.12), 0, 0.85))
        c = hsv_jitter(c, rng, 0.10)
        # hoja como 2 segmentos (curva leve)
        mx = x + np.cos(ang) * L * 0.5; my = y + np.sin(ang) * L * 0.5
        ex = mx + np.cos(ang + bend) * L * 0.5; ey = my + np.sin(ang + bend) * L * 0.5
        w = 2 if rng.random() < 0.55 else 1
        bb = (min(x, ex) - 3, min(y, ey) - 3, max(x, ex) + 3, max(y, ey) + 3)
        col = tuple(int(v * 255) for v in c); col2 = tuple(int(min(1, v * 1.15) * 255) for v in c)
        hv = int(90 + 165 * hgt)
        for ox, oy in wrap_offsets(bb, S):
            dc.line([(x + ox, y + oy), (mx + ox, my + oy)], fill=col, width=w)
            dc.line([(mx + ox, my + oy), (ex + ox, ey + oy)], fill=col2, width=1)
            dh.line([(x + ox, y + oy), (mx + ox, my + oy)], fill=int(hv * 0.8), width=w)
            dh.line([(mx + ox, my + oy), (ex + ox, ey + oy)], fill=hv, width=1)
            dm.line([(x + ox, y + oy), (ex + ox, ey + oy)], fill=255, width=w)
    gcol = np.asarray(cimg, float) / 255
    gh = np.asarray(himg, float) / 255
    gm = blur_wrap(np.asarray(mimg, float) / 255, 0.8)
    gm = np.clip(gm * 1.6, 0, 1)
    # piedritas sobre tierra en las calvas
    pm, pc, ph = draw_pebbles(S, rng, 260, 2, 6, (0.38, 0.36, 0.33), (0.55, 0.52, 0.47))
    pm = pm * (1 - gm)
    soil = lerp(soil, pc, pm)
    # hojas secas caídas (pocas)
    alb = lerp(soil, gcol, gm)
    shadow = blur_wrap(gm, 3.0)                              # sombra de contacto del pasto sobre tierra
    alb = alb * (1 - 0.35 * shadow * (1 - gm))[..., None]
    h = normalize(0.25 * sh * (1 - gm) + 0.3 * ph + gm * (0.35 + 0.65 * gh))
    rough = np.clip(srough * (1 - gm) + (0.78 - 0.1 * gh) * gm, 0, 1)
    ao = np.clip(ao_from_height(h, 3, 1.8) * (0.7 + 0.3 * gh * gm + 0.3 * (1 - gm)), 0, 1)
    nrm = height_to_normal(blur_wrap(h, 0.6), 4.0)
    return save_pbr(f"{OUT}/pasto", alb, height=h, rough=rough, ao=ao, normal=nrm)


# ----------------------------------------------------------------- 5 mantillo con hojarasca
def leaf_poly(rng, x, y, L):
    """Hoja elíptica/lanceolada con punta, rotada. Devuelve polígono y nervio central."""
    ang = rng.uniform(0, 2 * np.pi)
    w = L * rng.uniform(0.25, 0.5)
    t = np.linspace(0, np.pi, 9)
    up = np.stack([np.cos(t) * L / 2, np.sin(t) ** 1.2 * w / 2], 1)
    lo = up[::-1] * [1, -1]
    pts = np.concatenate([up, lo[1:-1]])
    pts[:, 1] *= rng.uniform(0.7, 1.0) * (1 + 0.2 * np.sin(np.linspace(0, 6, len(pts))))  # bordes rotos
    ca, sa = np.cos(ang), np.sin(ang)
    R = np.array([[ca, -sa], [sa, ca]])
    pts = pts @ R.T + [x, y]
    vein = np.array([[-L / 2, 0], [L / 2, 0]]) @ R.T + [x, y]
    return pts, vein


def mantillo(size=512):
    """512 px = 2 m (~3.9 mm/px). Tierra oscura, hojarasca seca (hojas 3-9 cm), ramitas y piedras."""
    S = size
    ppm = S / 2.0
    rng = np.random.default_rng(501)
    soil, sh, srough = soil_base(S, 510, ppm, wet=0.0)
    # mulch fino (corteza triturada)
    chips = fbm2(S, 40, 40, 2, seed=502)
    soil = soil * (0.8 + 0.35 * chips[..., None])
    cimg = Image.fromarray((np.clip(soil, 0, 1) * 255).astype(np.uint8), "RGB")
    himg = Image.fromarray((normalize(sh) * 110).astype(np.uint8), "L")
    mimg = Image.new("L", (S, S), 0)
    dc, dh, dm = ImageDraw.Draw(cimg), ImageDraw.Draw(himg), ImageDraw.Draw(mimg)
    # ramitas
    for _ in range(70):
        x, y = rng.random(2) * S; L = rng.uniform(10, 40); a = rng.uniform(0, np.pi * 2)
        ex, ey = x + np.cos(a) * L, y + np.sin(a) * L
        c = hsv_jitter((0.22, 0.16, 0.11), rng, 0.15)
        for ox, oy in wrap_offsets((min(x, ex), min(y, ey), max(x, ex), max(y, ey)), S):
            dc.line([(x + ox, y + oy), (ex + ox, ey + oy)], fill=tuple(int(v * 255) for v in c), width=2)
            dh.line([(x + ox, y + oy), (ex + ox, ey + oy)], fill=150, width=2)
    # hojas: capas, densidad por manchas macro
    cover = fbm(S, 3, 4, seed=503)
    leaf_cols = [(0.40, 0.29, 0.17), (0.50, 0.38, 0.22), (0.33, 0.23, 0.14), (0.56, 0.47, 0.30),
                 (0.27, 0.19, 0.12), (0.44, 0.40, 0.25), (0.55, 0.34, 0.18), (0.36, 0.34, 0.22)]
    placed = 0
    tries = 0
    while placed < 1300 and tries < 6000:
        tries += 1
        x, y = rng.random(2) * S
        if rng.random() > smoothstep(0.25, 0.7, cover[int(y), int(x)]) + 0.1:
            continue
        placed += 1
        L = rng.uniform(12, 34)
        poly, vein = leaf_poly(rng, x, y, L)
        c = np.clip(np.array(leaf_cols[rng.integers(len(leaf_cols))]) * rng.uniform(0.8, 1.15) * (1 + rng.normal(0, 0.04, 3)), 0, 1)
        if rng.random() < 0.25:                    # hojas viejas/oscuras, casi descompuestas
            c = c * 0.55
        bb = (poly[:, 0].min(), poly[:, 1].min(), poly[:, 0].max(), poly[:, 1].max())
        hv = int(120 + 135 * placed / 1300)
        for ox, oy in wrap_offsets(bb, S):
            p = [tuple(q) for q in poly + [ox, oy]]
            dc.polygon(p, fill=tuple(int(v * 255) for v in c))
            dc.line([tuple(q) for q in vein + [ox, oy]], fill=tuple(int(v * 255 * 0.7) for v in c), width=1)
            dh.polygon(p, fill=hv)
            dh.line([tuple(q) for q in vein + [ox, oy]], fill=min(255, hv + 25), width=1)
            dm.polygon(p, fill=255)
    alb = np.asarray(cimg, float) / 255
    lh = np.asarray(himg, float) / 255
    lm = np.asarray(mimg, float) / 255
    pm, pc, ph = draw_pebbles(S, rng, 140, 2.5, 7, (0.42, 0.40, 0.37), (0.62, 0.60, 0.55))
    pm = pm * (rng.random() * 0 + 1) * (1 - lm * 0.7)
    alb = lerp(alb, pc, pm)
    # textura de hoja (moteado) + sombra de contacto
    mott = fbm(S, 64, 3, seed=504)
    alb = alb * (1 - lm * 0.2 * (mott - 0.5))[..., None]
    sh2 = blur_wrap(lm, 2.0)
    alb = alb * (1 - 0.3 * np.clip(sh2 - lm, 0, 1))[..., None]
    h = normalize(blur_wrap(lh, 0.6) + 0.5 * ph)
    rough = np.clip(srough * (1 - lm) + (0.75 + 0.1 * mott) * lm - 0.15 * pm, 0, 1)
    ao = np.clip(ao_from_height(h, 4, 2.0), 0, 1)
    nrm = height_to_normal(h, 4.0)
    return save_pbr(f"{OUT}/mantillo", alb, height=h, rough=rough, ao=ao, normal=nrm)


# ----------------------------------------------------------------- 6 musgo puro
def musgo(size=512):
    """512 px = 1 m. Musgo puro (cojines + filamentos) para mezclar en juntas y bordes."""
    S = size
    h, col = moss_layer(S, 610, S)
    # filamentos/briznas finas
    fil = smoothstep(0.55, 0.8, fbm2(S, 64, 160, 2, seed=611))
    col = lerp(col, col * 1.2 + np.array([0.02, 0.03, 0.0]), fil * 0.35)
    # huecos oscuros entre cojines
    gap = 1 - smoothstep(0.08, 0.3, h)
    col = lerp(col, np.array([0.05, 0.06, 0.02]), gap * 0.7)
    hh = normalize(h + 0.15 * fil)
    rough = np.clip(0.88 + 0.08 * gap - 0.1 * fil, 0, 1)
    ao = np.clip(ao_from_height(hh, 4, 1.8) * (1 - 0.4 * gap), 0, 1)
    nrm = height_to_normal(blur_wrap(hh, 0.5), 4.0)
    return save_pbr(f"{OUT}/musgo", np.clip(col, 0, 1), height=hh, rough=rough, ao=ao, normal=nrm)


def shrink_orm(rel):
    """Cuantiza AO/rugosidad a 6 bits (invisible en ORM, ~30 % menos peso PNG)."""
    path = os.path.join(ROOT, rel + "_orm.png")
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.int32)
    a = np.clip((a // 4) * 4 + 2, 0, 255)
    a[..., 2] = 0
    Image.fromarray(a.astype(np.uint8), "RGB").save(path, optimize=True)


# ----------------------------------------------------------------- main
SETS = [("corteza_tropical", corteza_tropical), ("corteza_lisa", corteza_lisa), ("palma", palma),
        ("pasto", pasto), ("mantillo", mantillo), ("musgo", musgo)]

if __name__ == "__main__":
    only = sys.argv[1:]
    os.makedirs(PREV, exist_ok=True)
    for name, fn in SETS:
        if only and name not in only:
            continue
        print("generando", name, flush=True)
        fn()
        shrink_orm(f"{OUT}/{name}")
        preview(f"{OUT}/{name}", f"{PREV}/{name}_prev.png")
    pngs = [f"{PREV}/{n}_prev.png" for n, _ in SETS if os.path.exists(f"{PREV}/{n}_prev.png")]
    contact_sheet(pngs, f"{PREV}/contact.png", cell=512)
    tot = sum(os.path.getsize(os.path.join(ROOT, OUT, f)) for f in os.listdir(os.path.join(ROOT, OUT)))
    print(f"total {tot / 1e6:.2f} MB")

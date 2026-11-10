"""Familia "stone" (F1-07): piedras y esculturas del Parque de Boston y alrededores.

Regenerar:  python3 tools/texgen/stone.py
Salida:     art/tex/stone/<nombre>_{albedo,normal,orm}.png   (ORM: R=AO, G=rugosidad, B=metal)

Sets y escala física (metros que cubre 1 tile):
  pizarra_lajas    1024 px = 1.5 m  enchape de pizarra negra-gris en lajas irregulares con mortero claro (jardineras)
  granito_abujardado 512 px = 1.0 m granito gris claro moteado, acabado abujardado (bancas, bordes, bordillos)
  marmol_blanco    1024 px = 2.0 m  mármol blanco con vetas grises suaves + pátina urbana (escurrimientos verticales)
  sillar_arenisca  1024 px = 3.0 m  sillares de arenisca en hiladas (iglesia neorrománica)
  bronce_patina     512 px = 1.0 m  bronce de escultura: verdigrís en zonas expuestas, bronce oscuro pulido en zonas tocadas
  canto_rodado      512 px = 1.0 m  piedra de río incrustada en concreto
Convención vertical: en la imagen, ARRIBA = arriba del mundo (escurrimientos bajan hacia filas mayores).
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (ROOT, ao_from_height, blur_wrap, contact_sheet, fbm, gradient_map, height_to_normal,  # noqa: E402
                    lerp, normalize, preview, ridged, save_pbr, warp)

OUT = "art/tex/stone"
PREV = "/tmp/f1_stone"


# ============================================================ utilidades propias
def voronoi(size: int, cells: int, seed: int, jitter: float = 0.85,
            warp_px: float = 0.0, warp_seed: int = 0, aspect: float = 1.0):
    """Voronoi tileable sobre rejilla con jitter. Devuelve (F1, edge_dist, id) en píxeles.
    edge_dist = distancia exacta al bisector entre la 1ª y 2ª semilla (mortero de ancho constante).
    aspect > 1 estira las celdas en X."""
    rng = np.random.default_rng(seed)
    cy, cx = cells, max(1, int(round(cells / aspect)))
    pts = (rng.random((cy, cx, 2)) - 0.5) * jitter + 0.5  # en unidades de celda
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    if warp_px > 0:
        wx = fbm(size, 4, 5, seed=warp_seed)
        wy = fbm(size, 4, 5, seed=warp_seed + 1)
        yy = yy + (wy - 0.5) * warp_px
        xx = xx + (wx - 0.5) * warp_px
    sy, sx = size / cy, size / cx
    gy, gx = yy / sy, xx / sx
    iy, ix = np.floor(gy).astype(int), np.floor(gx).astype(int)
    d1 = np.full(yy.shape, np.inf); d2 = np.full(yy.shape, np.inf)
    p1 = np.zeros(yy.shape + (2,)); p2 = np.zeros(yy.shape + (2,))
    id1 = np.zeros(yy.shape, dtype=np.int64)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            ny, nx = iy + oy, ix + ox
            p = pts[ny % cy, nx % cx]
            py = (ny + p[..., 0]) * sy
            px = (nx + p[..., 1]) * sx
            d = np.hypot(yy - py, xx - px)
            cid = (ny % cy) * cx + (nx % cx)
            c1 = d < d1
            c2 = (~c1) & (d < d2)
            # desplaza 1 -> 2
            d2 = np.where(c1, d1, np.where(c2, d, d2))
            p2 = np.where(c1[..., None], p1, np.where(c2[..., None], np.stack([py, px], -1), p2))
            d1 = np.where(c1, d, d1)
            p1 = np.where(c1[..., None], np.stack([py, px], -1), p1)
            id1 = np.where(c1, cid, id1)
    ab = np.linalg.norm(p2 - p1, axis=-1) + 1e-6
    edge = (d2 ** 2 - d1 ** 2) / (2 * ab)
    return d1, edge, id1


def cell_rand(ids: np.ndarray, seed: int, n: int = 1) -> np.ndarray:
    """Valor aleatorio estable por id de celda, en [0,1]. Forma ids.shape (+ (n,) si n>1)."""
    rng = np.random.default_rng(seed)
    table = rng.random((int(ids.max()) + 1, n))
    v = table[ids]
    return v[..., 0] if n == 1 else v


def mix(a, b, t):
    """lerp para campos escalares 2D (common.lerp añade un eje de color)."""
    return a * (1 - t) + b * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def speckle(size: int, density: float, seed: int, blur: float = 0.6) -> np.ndarray:
    """Motas finas tileables (cristales): umbral de ruido blanco suavizado."""
    rng = np.random.default_rng(seed)
    n = blur_wrap(rng.random((size, size)), blur)
    thr = np.quantile(n, 1 - density)
    return smoothstep(thr, thr + (n.max() - thr) * 0.35, n)


def drips(size: int, count: int, seed: int, len_px=(80, 400), width_px=(2, 10)) -> np.ndarray:
    """Escurrimientos verticales tileables: arrancan en y0 y se desvanecen hacia abajo."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size))
    yy = np.arange(size)
    wob = fbm(size, 8, 4, seed=seed + 7)
    for _ in range(count):
        x0 = rng.random() * size
        y0 = rng.random() * size
        L = rng.uniform(*len_px)
        w = rng.uniform(*width_px)
        a = rng.uniform(0.3, 1.0)
        dy = (yy - y0) % size  # distancia hacia abajo con wrap
        prof = np.clip(1 - dy / L, 0, 1) ** 1.5 * smoothstep(0, 12, dy)
        rows = np.nonzero(prof > 0)[0]
        if rows.size == 0:
            continue
        xs = np.arange(size)
        for r in rows:
            cx = x0 + (wob[r, int(x0) % size] - 0.5) * 14
            dx = np.abs(xs - cx); dx = np.minimum(dx, size - dx)
            ww = w * (0.6 + 0.6 * prof[r])
            out[r] = np.maximum(out[r], a * prof[r] * np.exp(-(dx / ww) ** 2))
    return out


def stamp_pebbles(size: int, seed: int, r_px=(12, 24), tries=4000, gap=2.5):
    """Coloca cantos rodados elípticos sin solaparse (toroidal). Devuelve (altura, id, máscara)."""
    rng = np.random.default_rng(seed)
    placed = []
    h = np.zeros((size, size)); ids = np.full((size, size), -1, dtype=np.int64)
    for _ in range(tries):
        r = rng.uniform(*r_px)
        asp = rng.uniform(0.55, 1.0)
        ang = rng.uniform(0, np.pi)
        cy, cx = rng.random(2) * size
        ok = True
        for (py, px, pr) in placed:
            dy = abs(cy - py); dy = min(dy, size - dy)
            dx = abs(cx - px); dx = min(dx, size - dx)
            if np.hypot(dy, dx) < (r * (0.55 + 0.45 * asp) + pr) * 0.92 + gap:
                ok = False
                break
        if not ok:
            continue
        reff = r * (0.55 + 0.45 * asp)
        placed.append((cy, cx, reff))
        R = int(np.ceil(r)) + 2
        oy, ox = np.mgrid[-R:R + 1, -R:R + 1].astype(np.float64)
        fy = oy - (cy - np.floor(cy)); fx = ox - (cx - np.floor(cx))
        c, s = np.cos(ang), np.sin(ang)
        u = (fx * c + fy * s) / r
        v = (-fx * s + fy * c) / (r * asp)
        d2 = u * u + v * v
        dome = np.sqrt(np.clip(1 - d2, 0, 1)) ** 0.8
        Y = (oy.astype(int) + int(np.floor(cy))) % size
        X = (ox.astype(int) + int(np.floor(cx))) % size
        m = d2 < 1
        cur = h[Y[m], X[m]]
        newv = dome[m]
        upd = newv > cur
        h[Y[m][upd], X[m][upd]] = newv[upd]
        ids[Y[m][upd], X[m][upd]] = len(placed) - 1
    return h, ids, ids >= 0


def course_layout(size: int, seed: int, h_px=(34, 78), w_px=(70, 210), warp_px=14.0, warp_seed=0):
    """Hiladas horizontales de piezas rectangulares de ancho/alto variable (cantería apilada), con bordes
    ondulados por warp. Tileable. Devuelve (edge_dist_px, id): edge = distancia al borde de la pieza."""
    rng = np.random.default_rng(seed)
    S = size
    hs = []
    while sum(hs) < S:
        hs.append(rng.uniform(*h_px))
    hs = np.array(hs) * (S / np.sum(hs))
    ys = np.concatenate([[0.0], np.cumsum(hs)])
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    if warp_px > 0:
        yy = yy + (fbm(S, 4, 5, seed=warp_seed) - 0.5) * warp_px
        xx = xx + (fbm(S, 4, 5, seed=warp_seed + 1) - 0.5) * warp_px
    yw = np.mod(yy, S)
    ids = np.zeros((S, S), dtype=np.int64)
    edge = np.full((S, S), 1e9)
    pid = 0
    for r in range(len(hs)):
        y0, y1 = ys[r], ys[r + 1]
        rowm = (yw >= y0) & (yw < y1)
        ws = []
        while sum(ws) < S:
            ws.append(rng.uniform(*w_px))
        ws = np.array(ws) * (S / np.sum(ws))
        cum = np.concatenate([[0.0], np.cumsum(ws)])
        xl = np.mod(xx - rng.uniform(0, S), S)
        k = np.clip(np.searchsorted(cum, xl, side="right") - 1, 0, len(ws) - 1)
        e = np.minimum.reduce([xl - cum[k], cum[k + 1] - xl, yw - y0, y1 - yw])
        ids = np.where(rowm, pid + k, ids)
        edge = np.where(rowm, e, edge)
        pid += len(ws)
    return edge, ids


def save(name, albedo, height, rough, metal=0.0, ao=None, nstrength=4.0):
    paths = save_pbr(f"{OUT}/{name}", np.clip(albedo, 0, 1), height=height, rough=np.clip(rough, 0.02, 1),
                     metal=metal, ao=ao, normal_strength=nstrength)
    preview(f"{OUT}/{name}", f"{PREV}/{name}_preview.png")
    return paths


# ============================================================ 1. pizarra en lajas
def pizarra_lajas(S=1024):
    # 1.5 m (683 px/m): lajas irregulares algo alargadas en horizontal (~25 x 14 cm), asentadas en hiladas
    # sueltas como el enchape de las jardineras de la foto; bordes ondulados y despostillados.
    f1, edge, ids = voronoi(S, 11, seed=11, jitter=0.95, warp_px=34, warp_seed=21, aspect=1.9)
    edge = edge + 4.0 * (fbm(S, 24, 4, seed=22) - 0.5)
    # junta de mortero 0.8-1.6 cm (683 px/m -> ~5-11 px de ancho total)
    jw = 2.5 + 8.0 * fbm(S, 5, 4, seed=31) ** 1.6
    mort = 1 - smoothstep(jw * 0.55, jw, edge)
    # superficie de laja: clivaje en escalones (pizarra), por laja con orientación propia
    rnd = cell_rand(ids, 12, 4)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64) / S
    ang = rnd[..., 0] * np.pi
    n_cleave = fbm(S, 6, 6, seed=41)
    layer = (np.cos(ang) * xx + np.sin(ang) * yy) * 6 + n_cleave * 3
    steps = np.floor(layer * 3) / 3
    cleave = (steps - layer)  # sierra -> escalones
    micro = fbm(S, 64, 4, seed=42)
    # bisel: laja algo abombada y bordes gastados (cae cerca de la junta)
    bevel = smoothstep(jw * 0.6, jw * 2.6 + 6, edge)
    tilt = (rnd[..., 1] - 0.5) * 0.25 * (xx - 0.5) + (rnd[..., 2] - 0.5) * 0.25 * (yy - 0.5)
    h_slab = 0.55 + 0.05 * cleave + 0.05 * micro + 0.12 * rnd[..., 3] + tilt
    h_slab = h_slab * (0.55 + 0.45 * bevel)
    h_mort = 0.36 + 0.08 * fbm(S, 32, 4, seed=43)
    height = mix(h_slab, h_mort, mort)
    height = normalize(height)

    # color: lajas gris-negro azulado con variación por pieza, mortero gris claro sucio
    base_v = 0.10 + 0.13 * rnd[..., 0] ** 1.8
    mac = fbm(S, 4, 5, seed=44)
    v = base_v * (0.85 + 0.3 * mac) * (0.9 + 0.2 * micro)
    v += 0.05 * np.clip(-cleave, 0, 1)  # cantos de escalón claros
    slab_col = np.stack([v * 0.97, v * 1.0, v * 1.07], -1)
    # tono óxido/ocre en algunas lajas y eflorescencia blanquecina
    rust = smoothstep(0.62, 0.85, fbm(S, 8, 5, seed=45)) * (rnd[..., 2] > 0.6)
    slab_col = lerp(slab_col, np.array([0.24, 0.18, 0.12]), rust * 0.45)
    efflo = smoothstep(0.6, 0.85, fbm(S, 6, 6, seed=46)) * 0.35
    slab_col = lerp(slab_col, np.array([0.42, 0.42, 0.42]), efflo * (1 - bevel * 0.5))
    # restos de mortero/cal sobre el borde de la laja
    smear = smoothstep(0.55, 0.8, fbm(S, 16, 5, seed=47)) * (1 - bevel)
    slab_col = lerp(slab_col, np.array([0.48, 0.47, 0.45]), smear * 0.6)
    m_v = 0.50 + 0.16 * fbm(S, 12, 5, seed=48) - 0.14 * smoothstep(0.5, 0.9, mac)
    mort_col = np.stack([m_v, m_v * 0.985, m_v * 0.96], -1)
    alb = lerp(slab_col, mort_col, mort)
    # suciedad macro
    dirt = smoothstep(0.45, 0.85, fbm(S, 3, 5, seed=49))
    alb = alb * (1 - 0.18 * dirt[..., None])

    rough = mix(0.62 + 0.18 * micro + 0.1 * rnd[..., 1], 0.93, mort)
    rough = np.where(efflo > 0.1, np.maximum(rough, 0.8), rough)
    ao = ao_from_height(height, 5, 1.2) * (1 - 0.35 * mort)
    return save("pizarra_lajas", alb, height, rough, ao=np.clip(ao, 0, 1), nstrength=5.0)


# ============================================================ 2. granito abujardado
def granito_abujardado(S=512):
    # 1 m: 2 mm/px. Cristales negros (biotita) 1-3 px, feldespato blanco, cuarzo gris
    base = fbm(S, 8, 6, seed=101)
    mac = fbm(S, 3, 5, seed=102)
    blk = speckle(S, 0.07, 103, 0.7)
    blk2 = speckle(S, 0.03, 104, 1.4)
    wht = speckle(S, 0.12, 105, 0.9)
    v = 0.60 + 0.07 * (base - 0.5) + 0.05 * (mac - 0.5)
    alb = np.stack([v, v * 0.995, v * 0.985], -1)
    alb = lerp(alb, np.array([0.80, 0.79, 0.77]), wht * 0.7)
    alb = lerp(alb, np.array([0.47, 0.47, 0.48]), speckle(S, 0.2, 108, 1.0) * 0.5)  # cuarzo grisáceo
    alb = lerp(alb, np.array([0.10, 0.10, 0.11]), np.clip(blk + blk2 * 0.9, 0, 1))
    # abujardado: picado fino uniforme (puntos de impacto)
    rng = np.random.default_rng(106)
    pits = blur_wrap(rng.random((S, S)), 0.9)
    pits = normalize(pits)
    bush = fbm(S, 128, 3, seed=107)
    height = 0.5 + 0.35 * (pits - 0.5) + 0.25 * (bush - 0.5) + 0.08 * (base - 0.5)
    height = normalize(height)
    # suciedad urbana: manchas grises/negruzcas, chicle/grasa dispersos
    grime = smoothstep(0.4, 0.9, fbm(S, 4, 6, seed=109))
    alb = alb * (1 - 0.09 * grime[..., None])
    alb = lerp(alb, np.array([0.30, 0.29, 0.27]), smoothstep(0.82, 0.97, fbm(S, 12, 4, seed=110)) * 0.25)
    # pequeñas zonas pulidas por uso (más lisas, un poco más oscuras)
    polish = smoothstep(0.6, 0.85, fbm(S, 5, 5, seed=111))
    rough = 0.86 + 0.08 * (bush - 0.5) - 0.18 * polish - 0.1 * blk
    alb = alb * (1 - 0.06 * polish[..., None])
    ao = ao_from_height(height, 2.5, 0.8)
    return save("granito_abujardado", alb, height, rough, ao=ao, nstrength=2.2)


# ============================================================ 3. mármol blanco con pátina
def marmol_blanco(S=1024):
    # 2 m: mármol blanco (tipo Carrara local) con vetas grises suaves y pocas vetas finas oscuras.
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64) / S
    t1 = fbm(S, 3, 7, seed=201); t2 = fbm(S, 4, 7, seed=202); t3 = fbm(S, 6, 6, seed=203)
    # vetas anchas y difusas (1 ciclo diagonal -> tilea)
    f = (xx + yy) + (t1 - 0.5) * 1.8
    soft = 1 - smoothstep(0.0, 0.75, np.abs(np.sin(f * np.pi * 2)))
    # vetas finas: turbulencia fuerte, aparecen y desaparecen
    g = (xx * 2 - yy) + (t2 - 0.5) * 2.4 + (t3 - 0.5) * 0.5
    thin = 1 - smoothstep(0.0, 0.07, np.abs(np.sin(g * np.pi * 2)))
    thin *= smoothstep(0.45, 0.75, fbm(S, 3, 4, seed=204))
    g2 = (xx * 3 + yy * 2) + (t1 - 0.5) * 3.0 + (t3 - 0.5)
    hair = (1 - smoothstep(0.0, 0.03, np.abs(np.sin(g2 * np.pi * 2)))) * smoothstep(0.5, 0.8, t2)
    cloud = fbm(S, 4, 7, seed=205)
    thin = blur_wrap(thin, 0.8); hair = blur_wrap(hair, 0.6)
    v = 0.87 + 0.04 * (cloud - 0.5)
    alb = np.stack([v * 1.0, v * 0.993, v * 0.975], -1)
    alb = lerp(alb, np.array([0.70, 0.70, 0.71]), soft * (0.25 + 0.3 * cloud))
    alb = lerp(alb, np.array([0.48, 0.49, 0.51]), thin * 0.75)
    alb = lerp(alb, np.array([0.58, 0.58, 0.60]), hair * 0.5)
    veins = np.clip(soft * 0.3 + thin + hair * 0.5, 0, 1)
    # pátina urbana: velo gris en manchas, escurrimientos suaves que bajan y se ensanchan
    veil = smoothstep(0.4, 0.95, fbm(S, 3, 6, seed=206))
    dr = drips(S, 30, 207, len_px=(150, 700), width_px=(3, 14))
    dr = blur_wrap(dr, 2.5)
    dr2 = blur_wrap(drips(S, 40, 217, len_px=(40, 200), width_px=(1.5, 4)), 0.8)
    grime = np.clip(dr * 0.45 + dr2 * 0.3, 0, 0.6) * (0.6 + 0.6 * fbm(S, 16, 4, seed=208))
    alb = alb * (1 - 0.12 * veil[..., None])
    alb = lerp(alb, np.array([0.36, 0.35, 0.32]), np.clip(grime, 0, 0.6))
    micro = fbm(S, 128, 3, seed=209)
    pores = speckle(S, 0.006, 210, 0.7)
    alb = lerp(alb, np.array([0.55, 0.54, 0.52]), pores * 0.35)
    height = 0.5 + 0.05 * (micro - 0.5) - 0.02 * pores + 0.03 * (cloud - 0.5) - 0.04 * grime + 0.02 * veins
    height = normalize(height)
    # rugosidad: apomazado 0.35-0.45; vetas algo más lisas; sucio/escurrido 0.6-0.8
    rough = 0.38 + 0.08 * (micro - 0.5) + 0.55 * grime + 0.18 * veil - 0.05 * veins
    ao = ao_from_height(height, 3, 0.5)
    return save("marmol_blanco", alb, height, rough, ao=ao, nstrength=1.2)


# ============================================================ 4. sillar de arenisca en hiladas
def sillar_arenisca(S=1024):
    # 3 m -> 341 px/m. 9 hiladas de ~33 cm (alturas variadas), sillares 55-110 cm, junta ~1 cm.
    rng = np.random.default_rng(301)
    NR = 9
    heights = rng.uniform(0.85, 1.15, NR); heights = heights / heights.sum() * S
    row_edges = np.concatenate([[0], np.cumsum(heights)])
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    blk_id = np.zeros((S, S), dtype=np.int64)
    dist = np.zeros((S, S))
    v_loc = np.zeros((S, S))
    bid = 0
    for r in range(NR):
        y0, y1 = row_edges[r], row_edges[r + 1]
        lens = []
        while sum(lens) < S:
            lens.append(rng.uniform(0.55, 1.10) * 341)
        lens = np.array(lens) / sum(lens) * S
        off = rng.uniform(0, S)
        xe = np.concatenate([[0], np.cumsum(lens)]) + off
        ry = np.nonzero((yy[:, 0] >= y0) & (yy[:, 0] < y1))[0]
        for i in range(len(lens)):
            a, b = xe[i], xe[i + 1]
            xs = (xx[0] - a) % S
            cols = np.nonzero(xs < (b - a))[0]
            Y, X = np.meshgrid(ry, cols, indexing="ij")
            blk_id[Y, X] = bid
            dx = np.minimum(xs[X], (b - a) - xs[X])
            dy = np.minimum(Y - y0, y1 - 1 - Y)
            dist[Y, X] = np.minimum(dx, dy)
            v_loc[Y, X] = (Y - y0) / (y1 - y0)
            bid += 1
    edge_n = fbm(S, 24, 5, seed=302)
    chip = smoothstep(0.8, 0.93, fbm(S, 12, 5, seed=303))
    d = dist - (edge_n - 0.5) * 2.5 - chip * 3.5
    joint_w = 1.8
    joint = 1 - smoothstep(joint_w - 0.5, joint_w + 0.8, d)
    rnd = cell_rand(blk_id, 304, 4)
    round_e = smoothstep(joint_w, joint_w + 10, d)
    strata = fbm(S, 4, 5, seed=305)
    layers = np.sin((yy / S * 90 + strata * 4 + rnd[..., 0] * 10) * np.pi * 2)
    layers = layers * smoothstep(0.3, 0.8, fbm(S, 6, 4, seed=315)) * 0.6
    tool = fbm(S, 96, 3, seed=306)
    grain = fbm(S, 256, 2, seed=307)
    erosion = smoothstep(0.6, 0.85, fbm(S, 12, 6, seed=308))
    face = fbm(S, 8, 5, seed=318)
    h_blk = 0.6 + 0.10 * round_e + 0.06 * (face - 0.5) + 0.015 * layers + 0.06 * (tool - 0.5) + 0.05 * (grain - 0.5) \
        - 0.10 * erosion + 0.03 * (rnd[..., 1] - 0.5)
    h_blk = h_blk * (0.6 + 0.4 * round_e)
    h_j = 0.22 + 0.06 * fbm(S, 64, 3, seed=309)
    height = normalize(mix(h_blk, h_j, joint))

    # arenisca beige-ocre bastante homogénea; cada sillar varía poco (cantera única)
    c_a = np.array([0.70, 0.61, 0.47]); c_b = np.array([0.64, 0.53, 0.41])
    col = lerp(c_a, c_b, rnd[..., 2]) * (0.92 + 0.14 * rnd[..., 3])[..., None]
    mac = fbm(S, 5, 6, seed=316)
    col = col * (0.92 + 0.12 * mac[..., None]) * (0.94 + 0.1 * grain[..., None]) * (1 + 0.04 * layers[..., None])
    iron = smoothstep(0.6, 0.85, fbm(S, 8, 5, seed=317)) * (rnd[..., 0] > 0.55)
    col = lerp(col, np.array([0.62, 0.44, 0.30]), iron * 0.3)
    soot = smoothstep(0.5, 0.88, fbm(S, 3, 6, seed=310)) * (0.5 + 0.5 * v_loc)
    col = lerp(col, np.array([0.30, 0.28, 0.25]), soot * 0.4)
    bio = smoothstep(0.65, 0.9, fbm(S, 6, 6, seed=311)) * (1 - round_e * 0.4)
    col = lerp(col, np.array([0.38, 0.40, 0.32]), bio * 0.3)
    dr = blur_wrap(drips(S, 40, 312, len_px=(40, 260), width_px=(2, 8)), 1.2)
    col = lerp(col, np.array([0.34, 0.31, 0.27]), dr * 0.3)
    col = col * (1 - 0.12 * (1 - round_e)[..., None]) * (1 - 0.1 * erosion[..., None])
    jcol = np.array([0.60, 0.57, 0.51]) * (0.75 + 0.3 * fbm(S, 32, 4, seed=313))[..., None]
    alb = lerp(col, jcol, joint)
    rough = mix(0.86 + 0.08 * grain - 0.06 * soot, 0.95, joint)
    ao = ao_from_height(height, 4, 1.0) * (1 - 0.35 * joint)
    return save("sillar_arenisca", alb, height, rough, ao=np.clip(ao, 0, 1), nstrength=4.0)


# ============================================================ 5. bronce con pátina
def bronce_patina(S=512):
    # 1 m. Bronce oscuro (pátina marrón) dominante, verdigrís calcáreo en zonas expuestas
    # y escurrimientos verdes; manchas pulidas por roce (metal brillante).
    mac = fbm(S, 4, 6, seed=401)
    meso = fbm(S, 12, 5, seed=402)
    cast = fbm(S, 64, 4, seed=403)
    pits = speckle(S, 0.006, 404, 0.8)
    dr = blur_wrap(drips(S, 70, 405, len_px=(60, 380), width_px=(1.5, 7)), 0.9)
    # exposición: macro manchas + bandas verticales (la lluvia lava hacia abajo)
    vband = blur_wrap(np.tile(fbm(S, 16, 4, seed=407)[0:1, :], (S, 1)), 2.0)
    expo = smoothstep(0.58, 0.85, mac * 0.6 + meso * 0.25 + vband * 0.3)
    green = np.clip(expo * (0.45 + 0.7 * cast) + dr * 0.9, 0, 1)
    green = smoothstep(0.2, 0.9, green)
    thin_g = smoothstep(0.55, 0.8, meso) * 0.3 * (1 - green)   # velo verde ligero sobre el bronce
    touch = smoothstep(0.78, 0.9, fbm(S, 5, 5, seed=406)) * (1 - green)
    dark_bronze = lerp(np.array([0.16, 0.11, 0.075]), np.array([0.28, 0.19, 0.12]), meso * 0.7 + cast * 0.3)
    polished = np.array([0.58, 0.42, 0.26])
    verd = lerp(np.array([0.27, 0.42, 0.37]), np.array([0.44, 0.58, 0.51]), np.clip(cast * 0.7 + mac * 0.4, 0, 1))
    alb = lerp(dark_bronze, polished, touch * (0.75 + 0.25 * cast))
    alb = lerp(alb, np.array([0.24, 0.30, 0.24]), thin_g)
    alb = lerp(alb, verd, green * 0.9)
    rim = np.clip(smoothstep(0.08, 0.35, green) - smoothstep(0.45, 0.85, green), 0, 1)
    alb = lerp(alb, np.array([0.13, 0.11, 0.08]), rim * 0.45)
    alb = alb * (1 - 0.15 * pits[..., None])
    height = 0.5 + 0.08 * (cast - 0.5) + 0.06 * green * (meso - 0.3) - 0.12 * pits + 0.04 * (mac - 0.5)
    height = normalize(height)
    metal = np.clip(0.92 * (1 - green) - 0.25 * rim - 0.4 * thin_g, 0, 1)
    rough = 0.45 + 0.12 * (cast - 0.5) - 0.22 * touch + 0.42 * green + 0.15 * rim + 0.3 * thin_g
    ao = ao_from_height(height, 3, 0.8)
    print("  verdigris cobertura %.2f, pulido %.2f" % (green.mean(), touch.mean()))
    return save("bronce_patina", alb, height, rough, metal=metal, ao=ao, nstrength=2.0)


# ============================================================ 6. canto rodado en concreto
def canto_rodado(S=512):
    # 1 m: cantos de 2-5 cm de radio (10-24 px), muy apretados, colores de río antioqueño (grises, beige, blanco)
    h_p, ids, mask = stamp_pebbles(S, 501, r_px=(9, 24), tries=9000, gap=1.5)
    ids_c = np.where(mask, ids, 0)
    rnd = cell_rand(ids_c, 502, 4)
    grain = fbm(S, 128, 3, seed=503)
    sand = speckle(S, 0.15, 504, 0.7)
    conc_h = 0.18 + 0.05 * grain + 0.04 * sand
    height = np.where(mask, 0.25 + 0.6 * h_p * (0.7 + 0.3 * rnd[..., 0]) + 0.02 * grain, conc_h)
    height = blur_wrap(height, 0.8)
    pal = np.array([[0.50, 0.50, 0.50], [0.30, 0.30, 0.31], [0.55, 0.50, 0.43],
                    [0.72, 0.70, 0.66], [0.47, 0.41, 0.36], [0.40, 0.41, 0.40], [0.62, 0.60, 0.57],
                    [0.36, 0.35, 0.33]])
    k = (rnd[..., 1] * len(pal)).astype(int).clip(0, len(pal) - 1)
    pc = pal[k] * (0.88 + 0.24 * rnd[..., 2])[..., None]
    # textura interna: moteado de granito/arenisca + vetas finas de cuarzo en algunos
    mot = speckle(S, 0.12, 508, 0.6)
    pc = pc * (1 - 0.25 * mot[..., None] * (rnd[..., 3] < 0.5)[..., None])
    veinp = smoothstep(0.94, 0.985, ridged(S, 8, 5, seed=505)) * (rnd[..., 3] > 0.7)
    pc = lerp(pc, np.array([0.82, 0.80, 0.76]), veinp * 0.6)
    pc = pc * (0.92 + 0.16 * fbm(S, 32, 4, seed=506))[..., None] * (0.88 + 0.2 * h_p)[..., None]
    cv = 0.50 + 0.08 * (grain - 0.5)
    cc = np.stack([cv, cv * 0.99, cv * 0.96], -1)
    cc = lerp(cc, np.array([0.36, 0.35, 0.33]), sand * 0.5)
    near = blur_wrap(mask.astype(float), 3.0)
    cc = cc * (1 - 0.25 * near[..., None])
    dirt = smoothstep(0.45, 0.85, fbm(S, 4, 5, seed=507))
    alb = np.where(mask[..., None], pc, cc) * (1 - 0.2 * dirt[..., None])
    rough = np.where(mask, 0.58 - 0.18 * h_p + 0.1 * rnd[..., 0], 0.92 + 0.05 * grain)
    rough = rough + 0.1 * dirt
    ao = ao_from_height(height, 4, 1.5)
    return save("canto_rodado", alb, height, rough, ao=ao, nstrength=6.0)


# ============================================================ 7. laja irregular de plazoleta
def laja_irregular(S=1024):
    # 3.0 m (341 px/m): lajas grandes (40-80 cm) de piedra gris cálido, juntas de 2-4 cm con tierra y pasto ralo
    f1, edge, ids = voronoi(S, 5, seed=61, jitter=0.9, warp_px=46, warp_seed=71)
    jw = 4.0 + 8.0 * fbm(S, 6, 4, seed=72) ** 1.5
    joint = 1 - smoothstep(jw * 0.5, jw, edge)
    rnd = cell_rand(ids, 62, 4)
    micro = fbm(S, 48, 5, seed=73)
    grain = fbm(S, 160, 3, seed=74)
    bevel = smoothstep(jw * 0.6, jw * 3.0 + 8, edge)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64) / S
    tilt = (rnd[..., 1] - 0.5) * 0.4 * (xx - 0.5) + (rnd[..., 2] - 0.5) * 0.4 * (yy - 0.5)
    h_slab = 0.62 + 0.07 * micro + 0.025 * grain + 0.10 * rnd[..., 3] + tilt
    h_slab = h_slab * (0.62 + 0.38 * bevel)
    h_joint = 0.30 + 0.10 * fbm(S, 40, 4, seed=75)
    height = normalize(mix(h_slab, h_joint, joint))
    # color: gris cálido con variación fuerte por laja (beige, gris azulado, rosado), manchas y desgaste
    base = 0.40 + 0.20 * rnd[..., 0]
    mac = fbm(S, 3, 5, seed=76)
    v = base * (0.86 + 0.28 * mac) * (0.92 + 0.16 * micro) * (0.96 + 0.08 * grain)
    warm = (rnd[..., 1] - 0.5) * 0.10
    slab = np.stack([v * (1.0 + warm + 0.04), v * (1.0 + 0.5 * warm), v * (0.94 - warm)], -1)
    stain = smoothstep(0.55, 0.85, fbm(S, 7, 5, seed=77))
    slab = lerp(slab, slab * np.array([0.78, 0.80, 0.78]), stain[..., None] * 0.7)
    lichen = smoothstep(0.62, 0.9, fbm(S, 20, 5, seed=78)) * (1 - bevel * 0.6)
    slab = lerp(slab, np.array([0.34, 0.38, 0.22]), lichen[..., None] * 0.35)
    soil_v = 0.20 + 0.08 * fbm(S, 30, 4, seed=79)
    soil = np.stack([soil_v * 1.05, soil_v * 0.95, soil_v * 0.78], -1)
    grass = smoothstep(0.52, 0.8, fbm(S, 36, 5, seed=80)) * joint
    soil = lerp(soil, np.array([0.17, 0.26, 0.09]), grass[..., None] * 0.85)
    alb = lerp(slab, soil, joint[..., None])
    alb = alb * (1 - 0.16 * smoothstep(0.45, 0.85, fbm(S, 3, 5, seed=81))[..., None])
    rough = mix(0.74 + 0.16 * micro, 0.95, joint)
    ao = ao_from_height(height, 7, 1.3) * (1 - 0.35 * joint)
    return save("laja_irregular", alb, height, rough, ao=np.clip(ao, 0, 1), nstrength=5.5)


SETS = {
    "pizarra_lajas": pizarra_lajas,
    "granito_abujardado": granito_abujardado,
    "marmol_blanco": marmol_blanco,
    "sillar_arenisca": sillar_arenisca,
    "bronce_patina": bronce_patina,
    "canto_rodado": canto_rodado,
    "laja_irregular": laja_irregular,
}

if __name__ == "__main__":
    os.makedirs(PREV, exist_ok=True)
    which = sys.argv[1:] or list(SETS)
    for n in which:
        print("->", n)
        SETS[n]()
    prevs = [f"{PREV}/{n}_preview.png" for n in SETS if os.path.exists(f"{PREV}/{n}_preview.png")]
    contact_sheet(prevs, f"{PREV}/contact_stone.png", cell=512)
    tot = sum(os.path.getsize(os.path.join(ROOT, OUT, f)) for f in os.listdir(os.path.join(ROOT, OUT)))
    print(f"total {tot / 1e6:.2f} MB")

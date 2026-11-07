"""Familia "plaster": fachadas pintadas, concreto y techos (Fase 1, agente F1-04).

Regenerar:  python3 tools/texgen/plaster.py            (desde godot3d/)
Opcional:   python3 tools/texgen/plaster.py --preview  (previews en /tmp/f1_plaster/)

Sets (todos tileables, deterministas):
  stucco          1024 px = 3 m   estuco/pañete pintado CLARO y neutro (se tiñe con albedo_color).
                                  Alineado a pisos de 3 m: banda de humedad/salpicado abajo del tile
                                  (0-0.45 m), chorreaduras bajo alféizar de ventana (sill a 1.0 m, x 0.9-2.1 m),
                                  suciedad leve bajo la losa (arriba del tile).
  concrete_board  1024 px = 3 m   concreto a la vista con formaleta de tablas (20 tablas de 15 cm),
                                  agujeros de amarre (grid 0.6 x 0.75 m), poros, chorreaduras.
  concrete_smooth  512 px = 2 m   concreto pulido/liso de edificio moderno, junta de panel en el borde del tile.
  roof_clay        512 px = 2 m   teja de barro española: 6 pares canal/cobija (33 cm), 5 hileras de 40 cm.
                                  Pendiente hacia ABAJO de la imagen (+V). Musgo, líquen, suciedad.
  stone_base       512 px = 1 m   zócalo de enchape de piedra laja irregular (piedras ~15-25 cm) con mortero.
  fibrocement      512 px = 2 m   lámina de fibrocemento (eternit) ondulada, 11 ondas (18 cm), traslapo
                                  horizontal a 1.5 m, ganchos con óxido, manchas negras de líquen y musgo.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from scipy import ndimage
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (ROOT, ao_from_height, blur_wrap, fbm, height_to_normal, lerp,  # noqa: E402
                    normalize, ridged, save_pbr, warp, preview, contact_sheet)

OUT = "art/tex/plaster/"
PREV = "/tmp/f1_plaster/"


# ============================================================ utilidades propias
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def vnoise_aniso(size, cx, cy, seed):
    """Ruido de valor periódico con celdas distintas en x e y (vetas, rayas)."""
    rng = np.random.default_rng(seed)
    grid = rng.random((cy, cx))

    def axis(cells):
        c = np.arange(size) * cells / size
        i0 = np.floor(c).astype(int)
        f = c - i0
        f = f * f * f * (f * (f * 6 - 15) + 10)
        return i0 % cells, (i0 + 1) % cells, f

    y0, y1, fy = axis(cy)
    x0, x1, fx = axis(cx)
    a = grid[np.ix_(y0, x0)]; b = grid[np.ix_(y0, x1)]
    c = grid[np.ix_(y1, x0)]; d = grid[np.ix_(y1, x1)]
    fy = fy[:, None]; fx = fx[None, :]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm_aniso(size, cx, cy, octaves=5, gain=0.5, seed=0):
    out = np.zeros((size, size)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        if cx > size or cy > size:
            break
        out += amp * vnoise_aniso(size, cx, cy, seed + o * 101)
        tot += amp; amp *= gain; cx *= 2; cy *= 2
    return normalize(out / tot)


def worley2(size, n, seed, jitter_warp=None):
    """Worley periódico: F1, F2 (en píxeles) e id de celda. Usa KD-tree con 9 copias."""
    rng = np.random.default_rng(seed)
    pts = rng.random((n, 2)) * size
    offs = np.array([(dy, dx) for dy in (-size, 0, size) for dx in (-size, 0, size)], dtype=np.float64)
    allp = (pts[None, :, :] + offs[:, None, :]).reshape(-1, 2)
    tree = cKDTree(allp)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    if jitter_warp is not None:
        wy, wx, s = jitter_warp
        yy = yy + (wy - 0.5) * s
        xx = xx + (wx - 0.5) * s
    q = np.stack([yy.ravel(), xx.ravel()], -1)
    d, i = tree.query(q, k=2)
    f1 = d[:, 0].reshape(size, size); f2 = d[:, 1].reshape(size, size)
    ids = (i[:, 0] % n).reshape(size, size)
    return f1, f2, ids


def splats(size, pts, radii, values=None, profile="dome"):
    """Dibuja discos suaves periódicos (pits, manchas). Devuelve mapa max-combinado."""
    out = np.zeros((size, size))
    if values is None:
        values = np.ones(len(pts))
    for (py, px), r, v in zip(pts, radii, values):
        R = int(np.ceil(r * 1.6)) + 1
        ys = np.arange(int(py) - R, int(py) + R + 1)
        xs = np.arange(int(px) - R, int(px) + R + 1)
        dy = (ys - py)[:, None]; dx = (xs - px)[None, :]
        d = np.sqrt(dy * dy + dx * dx) / max(r, 1e-3)
        if profile == "dome":
            k = np.clip(1 - d * d, 0, 1)
        elif profile == "soft":
            k = np.exp(-d * d * 2.0)
        else:  # hard
            k = smoothstep(1.05, 0.85, d)
        sub = out[np.ix_(ys % size, xs % size)]
        out[np.ix_(ys % size, xs % size)] = np.maximum(sub, k * v)
    return out


def streaks(size, starts, lengths, widths, strengths, seed, wiggle=10.0):
    """Chorreaduras verticales hacia abajo (+y), periódicas. starts=(y,x)."""
    out = np.zeros((size, size))
    rng = np.random.default_rng(seed)
    yy = np.arange(size)
    for (y0, x0), L, w, s in zip(starts, lengths, widths, strengths):
        dy = (yy - y0) % size  # distancia hacia abajo con wrap
        prof_y = np.where(dy < L, np.exp(-dy / (L * 0.45)) * smoothstep(0, 3, dy), 0.0)
        # el ancho se adelgaza con la distancia
        R = int(w * 3) + 2
        xs = np.arange(int(x0) - R, int(x0) + R + 1)
        wy = w * (1.0 - 0.5 * np.clip(dy / max(L, 1), 0, 1))[:, None]
        dx = (xs - x0)[None, :]
        k = np.exp(-(dx * dx) / (2 * wy * wy + 1e-6)) * prof_y[:, None] * s
        cols = xs % size
        out[:, cols] = np.maximum(out[:, cols], k)
    # serpenteo horizontal y textura interna
    wx = fbm_aniso(size, 2, 16, 3, seed=seed + 7)
    out = warp(out, wx, np.full_like(out, 0.5), wiggle)
    grain = fbm_aniso(size, 48, 6, 3, seed=seed + 9)
    return np.clip(out * (0.65 + 0.7 * grain), 0, 1)


def cavity(h, sigma=2.0):
    return np.clip((blur_wrap(h, sigma) - h), 0, None)


def lum(c):
    return c[..., 0] * 0.2126 + c[..., 1] * 0.7152 + c[..., 2] * 0.0722


def finish_ao(h, radius, strength, extra=None):
    ao = ao_from_height(h, radius, strength)
    if extra is not None:
        ao = ao * extra
    return np.clip(ao, 0.25, 1)


# ============================================================ 1. estuco pintado
def gen_stucco():
    S = 1024; PX = S / 3.0  # px por metro
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    from_bottom = (S - yy) / PX  # metros desde el piso de este "piso" (tile)

    # --- relieve: llana (golpes de llana como planos inclinados) + arena + ondulación
    wy = fbm(S, 4, 4, seed=11); wx = fbm(S, 4, 4, seed=12)
    f1, f2, ids = worley2(S, 260, seed=13, jitter_warp=(wy, wx, 120))
    rng = np.random.default_rng(14)
    n = 260
    sl_y = rng.normal(0, 1, n); sl_x = rng.normal(0, 1, n); off = rng.normal(0, 1, n)
    # plano por celda (pendiente aleatoria) -> crestas en los bordes de cada pasada de llana
    trowel = (sl_y[ids] * np.sin(yy / S * 2 * np.pi * 3) * 0 + off[ids]) * 0.5
    local = (f1 / 40.0)
    trowel = trowel + local * (sl_x[ids] > 0) * 0.35
    trowel = blur_wrap(trowel, 6.0)
    ridge_edges = smoothstep(6, 0, f2 - f1) * 0.5  # rebordes donde se juntan pasadas
    sand = fbm(S, 128, 3, seed=15)
    sand2 = fbm(S, 256, 2, seed=16)
    macro = fbm(S, 3, 5, seed=17)
    h = 0.18 * normalize(trowel) + 0.025 * ridge_edges + 0.12 * sand + 0.05 * sand2 + 0.25 * macro

    # --- desconchado leve: pequeños parches de pintura levantada
    pm = fbm(S, 12, 6, seed=18)
    pmask_area = smoothstep(0.66, 0.72, fbm(S, 4, 3, seed=19))  # solo en algunas zonas
    peel = smoothstep(0.74, 0.755, pm) * pmask_area
    # más desconchado cerca de la base (humedad)
    peel = np.maximum(peel, smoothstep(0.70, 0.715, pm) * smoothstep(0.45, 0.1, from_bottom))
    peel = blur_wrap(peel, 0.6)
    lip = np.clip(blur_wrap(peel, 1.5) - peel, 0, 1) * 2.5  # reborde de la capa de pintura
    h = h - peel * 0.10 + lip * 0.05

    # grietas finas: pocas, por caminata aleatoria; diagonales desde las esquinas del alféizar
    rngc = np.random.default_rng(20)
    cpts = []
    seeds_c = [(S - 1.0 * PX, 0.9 * PX, 2.4), (S - 1.0 * PX, 2.1 * PX, 0.7),
               (S - 2.2 * PX, 0.9 * PX, -2.3), (S - 2.2 * PX, 2.1 * PX, -0.8)]
    seeds_c += [(rngc.uniform(0, S), rngc.uniform(0, S), rngc.uniform(-np.pi, np.pi)) for _ in range(4)]
    for (y, x, a) in seeds_c:
        L = int(rngc.uniform(60, 220))
        for _ in range(L):
            a += rngc.normal(0, 0.12)
            y += np.sin(a) * 1.5
            x += np.cos(a) * 1.5
            cpts.append((y, x))
            if rngc.random() < 0.01:  # ramita
                a += rngc.choice([-0.9, 0.9])
    cpts = np.array(cpts)
    crack = splats(S, cpts, rngc.uniform(0.9, 1.2, len(cpts)), rngc.uniform(0.6, 0.9, len(cpts)), profile="soft")
    crack = blur_wrap(crack, 0.4)
    h = h - crack * 0.10

    # --- albedo neutro claro (tintable)
    base = np.array([0.885, 0.880, 0.865])
    var = (macro - 0.5) * 0.05 + (normalize(trowel) - 0.5) * 0.025 + (sand - 0.5) * 0.03
    alb = base[None, None, :] * (1 + var[..., None])
    # suciedad en poros del grano
    cav = normalize(cavity(h, 1.5))
    alb *= (1 - 0.10 * cav[..., None])
    # capa expuesta bajo la pintura (revoque gris)
    under = np.array([0.78, 0.765, 0.73]) * (0.9 + 0.2 * sand2[..., None])
    alb = lerp(alb, under, peel * 0.85)
    alb = alb * (1 - 0.10 * lip[..., None])

    # --- humedad en la base del muro (zócalo): mancha irregular con línea de marea
    edge_n = fbm(S, 8, 5, seed=22)
    top_line = 0.22 + 0.28 * edge_n + 0.08 * fbm(S, 32, 3, seed=23)  # metros
    damp = smoothstep(top_line + 0.04, top_line - 0.06, from_bottom)
    tide = np.exp(-((from_bottom - top_line) / 0.025) ** 2) * 0.8
    # continuidad con el tile de arriba: la parte de arriba del tile es "bajo losa"
    under_slab = smoothstep(0.10, 0.0, yy / PX) * (0.25 + 0.3 * fbm(S, 16, 3, seed=24))
    # al borde inferior la mancha baja a la misma intensidad que bajo la losa (sin costura)
    damp = damp * (0.55 + 0.45 * smoothstep(0.0, 0.08, from_bottom))
    damp_col = np.array([0.66, 0.66, 0.62])
    alb = lerp(alb, alb * damp_col / base, damp * (0.35 + 0.35 * fbm(S, 12, 4, seed=25)))
    alb = alb * (1 - 0.12 * tide[..., None])
    # salpicado de lluvia (puntos oscuros) en los primeros 20 cm
    rng_s = np.random.default_rng(26)
    nsp = 1400
    sp_y = S - np.abs(rng_s.exponential(0.07, nsp)) * PX
    sp = np.stack([sp_y, rng_s.uniform(0, S, nsp)], -1)
    splash = splats(S, sp, rng_s.gamma(1.6, 0.6, nsp) + 0.35, rng_s.uniform(0.3, 1.0, nsp), profile="soft")
    splash = np.maximum(splash, smoothstep(0.6, 0.8, fbm(S, 64, 3, seed=126)) * smoothstep(0.18, 0.0, from_bottom) * 0.5)
    alb = lerp(alb, alb * np.array([0.60, 0.59, 0.57]), splash * 0.6)
    # eflorescencia blanquecina sobre la línea de marea
    eff = smoothstep(0.6, 0.8, fbm(S, 24, 4, seed=27)) * np.exp(-((from_bottom - top_line - 0.04) / 0.05) ** 2)
    alb = lerp(alb, np.array([0.93, 0.93, 0.91]), eff * 0.35)
    alb = alb * (1 - 0.18 * under_slab[..., None])

    # --- chorreaduras bajo alféizar (ventana centrada, x 0.9..2.1 m, sill a 1.0 m)
    rng = np.random.default_rng(28)
    sill_row = S - 1.0 * PX
    xs_win = np.concatenate([rng.uniform(0.92, 1.0, 4), rng.uniform(2.0, 2.08, 4), rng.uniform(1.0, 2.0, 9)]) * PX
    st = [(sill_row + rng.uniform(0, 6), x) for x in xs_win]
    Ls = np.concatenate([rng.uniform(0.45, 0.8, 8), rng.uniform(0.15, 0.5, 9)]) * PX
    ws = rng.uniform(2.0, 6.0, len(st))
    ss = np.concatenate([rng.uniform(0.6, 1.0, 8), rng.uniform(0.25, 0.6, 9)])
    drips_w = streaks(S, st, Ls, ws, ss, seed=29, wiggle=16)
    # chorreaduras débiles bajo la losa/cornisa a lo ancho
    st2 = [(rng.uniform(0, 8), rng.uniform(0, S)) for _ in range(26)]
    drips_c = streaks(S, st2, rng.uniform(0.2, 0.9, 26) * PX, rng.uniform(3, 10, 26),
                      rng.uniform(0.15, 0.4, 26), seed=30, wiggle=14)
    # línea de suciedad justo bajo el alféizar
    sill_dirt = np.exp(-((yy - sill_row - 3) / 4.0) ** 2) * smoothstep(0.85 * PX, 0.95 * PX, xx) \
        * smoothstep(2.15 * PX, 2.05 * PX, xx) * (0.5 + 0.5 * fbm(S, 32, 3, seed=31))
    drips = np.clip(drips_w * 0.75 + drips_c * 0.8 + sill_dirt * 0.6, 0, 1)
    drips = blur_wrap(drips, 1.2)
    alb = alb * (1 - 0.22 * drips[..., None])
    alb = lerp(alb, alb * np.array([0.97, 0.97, 0.94]), drips)  # leve tono terroso
    # sombra dentro de grietas
    alb = alb * (1 - 0.4 * crack[..., None])

    # --- rugosidad
    rough = 0.86 + 0.06 * (sand - 0.5) + 0.04 * peel - 0.06 * drips + 0.03 * damp + 0.04 * (macro - 0.5)
    ao = finish_ao(h, 4.0, 1.0, 1 - 0.5 * crack)
    paths = save_pbr(OUT + "stucco", np.clip(alb, 0, 1), height=h, rough=np.clip(rough, 0, 1),
                     ao=ao, normal_strength=5.0)
    return paths


# ============================================================ 2. concreto con formaleta
def gen_concrete_board():
    S = 1024; PX = S / 3.0
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    rows = 20; rh = S / rows
    rng = np.random.default_rng(40)
    row = np.floor(yy / rh).astype(int)
    ty = (yy - row * rh) / rh
    # juntas verticales: 1-2 por hilera
    joints = [np.sort(rng.uniform(0, S, rng.integers(1, 3))) for _ in range(rows)]
    board_id = np.zeros((S, S), dtype=int)
    dist_vj = np.full((S, S), 1e9)
    for r in range(rows):
        sl = row == r
        js = joints[r]
        x = xx[sl]
        k = np.searchsorted(js, x) % len(js)
        board_id[sl] = r * 4 + k
        d = np.min(np.abs(((x[:, None] - js[None, :]) + S / 2) % S - S / 2), axis=1)
        dist_vj[sl] = d
    nb = rows * 4
    b_h = rng.normal(0, 1, nb); b_tilt = rng.normal(0, 1, nb); b_tone = rng.normal(0, 1, nb)
    b_offy = rng.integers(0, S, nb); b_offx = rng.integers(0, S, nb)
    # veta de madera impresa, distinta por tabla
    G = fbm_aniso(S, 3, 48, 5, seed=41)
    G2 = fbm_aniso(S, 8, 160, 3, seed=42)
    gy = (yy.astype(int) + b_offy[board_id]) % S
    gx = (xx.astype(int) + b_offx[board_id]) % S
    grain = 0.7 * G[gy, gx] + 0.3 * G2[gy, gx]
    # nudos ocasionales
    dist_hj = np.minimum(ty, 1 - ty) * rh
    fin_h = np.exp(-(dist_hj / 1.0) ** 2)   # rebaba (aleta) en la junta
    fin_v = np.exp(-(dist_vj / 1.0) ** 2)
    step = b_h[board_id] * 0.08 + b_tilt[board_id] * (ty - 0.5) * 0.05
    macro = fbm(S, 4, 5, seed=43)
    fine = fbm(S, 128, 3, seed=44)
    h = 0.5 + step + 0.16 * grain + 0.10 * macro + 0.05 * fine
    h += 0.10 * fin_h * (0.5 + 0.5 * fbm(S, 64, 2, seed=45)) + 0.08 * fin_v
    # amarres (tie holes) grid 0.6 x 0.75 m
    holes_pts = [((j + 0.5) * 0.75 * PX + rng.normal(0, 2), (i + 0.5) * 0.6 * PX + rng.normal(0, 2))
                 for j in range(4) for i in range(5)]
    hole = splats(S, holes_pts, [5.0] * len(holes_pts), profile="hard")
    ring = splats(S, holes_pts, [9] * len(holes_pts), profile="hard") - hole
    h = h - hole * 0.35 + ring * 0.02
    # poros (bugholes)
    npits = 420
    # agrupados: más poros donde el concreto quedó mal vibrado
    clus = fbm(S, 6, 3, seed=146)
    cand = rng.random((npits * 4, 2)) * S
    keep = rng.random(npits * 4) < clus[cand[:, 0].astype(int), cand[:, 1].astype(int)] ** 2.5
    pp = cand[keep][:npits]
    npits = len(pp)
    pr = rng.gamma(1.6, 0.8, npits) + 0.5
    pits = splats(S, pp, pr, profile="dome")
    pits *= smoothstep(0.3, 0.6, fbm(S, 6, 3, seed=46)) * 0.6 + 0.4
    h = h - pits * 0.22
    # bordes desportillados de tablas
    chip = smoothstep(0.72, 0.8, fbm(S, 64, 3, seed=47)) * np.exp(-(dist_hj / 3.0) ** 2)
    h = h - chip * 0.12

    # --- albedo
    base = np.array([0.50, 0.50, 0.485])
    tone = b_tone[board_id] * 0.025 + (macro - 0.5) * 0.12 + (grain - 0.5) * 0.09 + (fine - 0.5) * 0.04
    alb = base * (1 + tone[..., None])
    warm = fbm(S, 5, 4, seed=48)
    alb = lerp(alb, alb * np.array([1.04, 1.0, 0.93]), smoothstep(0.55, 0.8, warm) * 0.8)
    # suciedad en juntas y poros
    cav = normalize(cavity(h, 2.0))
    alb = alb * (1 - 0.35 * cav[..., None])
    alb = alb * (1 - 0.55 * hole[..., None]) * (1 - 0.38 * pits[..., None])
    alb = alb * (1 - 0.12 * fin_h[..., None] * fbm(S, 32, 2, seed=49)[..., None])
    # chorreaduras oscuras y eflorescencia
    n_st = 26
    st = [(rng.uniform(0, S), rng.uniform(0, S)) for _ in range(n_st)]
    dr = streaks(S, st, rng.uniform(0.4, 1.8, n_st) * PX, rng.uniform(5, 16, n_st), rng.uniform(0.2, 0.6, n_st),
                 seed=50, wiggle=18)
    dr = blur_wrap(dr, 2.0)
    # también desde los amarres (óxido/agua)
    st_h = [(p[0] + 5, p[1]) for p in holes_pts]
    dr_h = streaks(S, st_h, rng.uniform(0.15, 0.5, len(st_h)) * PX, [3.0] * len(st_h),
                   rng.uniform(0.3, 0.8, len(st_h)), seed=51, wiggle=4)
    alb = alb * (1 - 0.35 * dr[..., None])
    alb = lerp(alb, alb * np.array([0.92, 0.82, 0.70]), dr_h * 0.8)
    alb = alb * (1 - 0.15 * dr_h[..., None])
    eff = streaks(S, [(rng.uniform(0, S), rng.uniform(0, S)) for _ in range(14)],
                  rng.uniform(0.2, 0.6, 14) * PX, rng.uniform(4, 10, 14), rng.uniform(0.3, 0.6, 14), seed=52)
    alb = lerp(alb, np.array([0.70, 0.70, 0.68]), eff * 0.5)
    # manchas verdosas de humedad (clima de Medellín)
    green = smoothstep(0.72, 0.85, fbm(S, 6, 5, seed=53)) * (0.4 + 0.6 * dr)
    alb = lerp(alb, alb * np.array([0.78, 0.86, 0.72]), green * 0.7)

    rough = 0.88 + 0.05 * (fine - 0.5) - 0.06 * dr + 0.06 * pits + 0.04 * (grain - 0.5) - 0.05 * eff
    ao = finish_ao(h, 5.0, 1.2, 1 - 0.4 * hole)
    return save_pbr(OUT + "concrete_board", np.clip(alb, 0, 1), height=h, rough=np.clip(rough, 0, 1),
                    ao=ao, normal_strength=6.0)


# ============================================================ 3. concreto liso / pulido
def gen_concrete_smooth():
    S = 512; PX = S / 2.0
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    rng = np.random.default_rng(60)
    macro = fbm(S, 3, 6, seed=61)
    cloud = fbm(S, 6, 6, seed=62)
    wy = fbm(S, 4, 3, seed=63); wx = fbm(S, 4, 3, seed=64)
    f1, f2, ids = worley2(S, 70, seed=65, jitter_warp=(wy, wx, 60))
    burn = blur_wrap(smoothstep(8, 0, f2 - f1), 3.0) * fbm(S, 8, 3, seed=69)  # marcas de llana de pulido
    fine = fbm(S, 128, 2, seed=66)
    # junta de panel en el borde del tile (2 m x 2 m)
    dxj = np.minimum(xx, S - 1 - xx); dyj = np.minimum(yy, S - 1 - yy)
    dj = np.minimum(dxj, dyj)
    groove = smoothstep(3.0, 1.5, dj)
    pp = rng.random((140, 2)) * S
    pits = splats(S, pp, rng.gamma(1.3, 0.5, 140) + 0.35, profile="dome")
    h = 0.5 + 0.06 * macro + 0.02 * fine + 0.02 * burn - 0.3 * groove - 0.12 * pits
    base = np.array([0.60, 0.60, 0.59])
    var = (cloud - 0.5) * 0.14 + (macro - 0.5) * 0.08 + (fine - 0.5) * 0.025 + burn * 0.02
    alb = base * (1 + var[..., None])
    alb = lerp(alb, alb * np.array([1.03, 1.0, 0.96]), smoothstep(0.6, 0.85, fbm(S, 4, 4, seed=67)) * 0.6)
    # manchas bajo la junta horizontal (agua que baja del panel de arriba)
    st = [(S - 4 + rng.uniform(-2, 2), rng.uniform(0, S)) for _ in range(20)]
    dr = streaks(S, st, rng.uniform(0.2, 1.2, 20) * PX, rng.uniform(2, 7, 20), rng.uniform(0.2, 0.6, 20), seed=68)
    alb = alb * (1 - 0.25 * dr[..., None])
    alb = alb * (1 - 0.55 * groove[..., None]) * (1 - 0.3 * pits[..., None])
    rough = 0.55 + 0.12 * (cloud - 0.5) * 2 * 0.5 - 0.06 * burn + 0.15 * groove + 0.08 * dr + 0.05 * (fine - 0.5)
    ao = finish_ao(h, 3.0, 1.0)
    return save_pbr(OUT + "concrete_smooth", np.clip(alb, 0, 1), height=h, rough=np.clip(rough, 0, 1),
                    ao=ao, normal_strength=4.0)


# ============================================================ 4. teja de barro española
def gen_roof_clay():
    S = 512; PX = S / 2.0
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    rng = np.random.default_rng(80)
    pairs = 6; pitch = S / pairs
    rows = 5; rh = S / rows
    row = np.floor(yy / rh).astype(int)
    t = (yy - row * rh) / rh                     # 0 arriba (bajo la teja de arriba) .. 1 = borde inferior
    # leve corrimiento lateral por hilera y por teja
    row_shift = rng.normal(0, 4.0, rows)
    xs = xx + row_shift[row]
    u = (xs / pitch) % 1.0
    col = np.floor(((xs / pitch) % pairs)).astype(int)
    jit = rng.normal(0, 0.025, (rows, pairs))
    u = (u + jit[row, col]) % 1.0
    # cobija centrada en u=0.5, se ensancha hacia abajo (teja cónica)
    half = 0.25 + 0.05 * t
    dc = (u - 0.5) / half
    cover = np.clip(1 - dc * dc, 0, 1)
    cover_h = np.sqrt(cover)
    is_cover = cover > 0
    # canal: cóncavo, centrado en u=0
    uc = np.minimum(u, 1 - u) / 0.5
    chan_h = 0.15 + 0.25 * uc * uc
    tile_tilt = 0.35 * t
    h_cover = 0.45 + 0.55 * cover_h + tile_tilt
    h_chan = chan_h + tile_tilt * 0.6
    h = np.where(is_cover, np.maximum(h_cover, h_chan), h_chan)
    # sombra/hendija bajo el borde de la cobija sobre el canal
    crev = np.exp(-((np.abs(dc) - 1.0) / 0.08) ** 2) * (np.abs(dc) > 0.9)
    h = h - crev * 0.08
    # ids por teja (cobija o canal)
    tid = row * pairs * 2 + col * 2 + is_cover.astype(int)
    ntid = rows * pairs * 2
    tone = rng.random(ntid); tb = rng.normal(0, 1, ntid)
    # borde inferior (labio) irregular con desportilladuras
    lip_n = fbm(S, 32, 3, seed=81)
    lip_end = 0.96 - 0.05 * smoothstep(0.65, 0.8, lip_n)
    over = t > lip_end
    # en la zona más allá del labio se ve el tope de la teja de la hilera siguiente, en sombra
    h = np.where(over, h * 0.25 + 0.05, h)
    # textura superficial
    fine = fbm(S, 128, 3, seed=82)
    mac = fbm(S, 4, 5, seed=83)
    h = h + 0.04 * fine + 0.03 * mac + tb[tid] * 0.02

    # --- color barro
    pal = np.array([[0.58, 0.30, 0.18], [0.50, 0.25, 0.15], [0.42, 0.22, 0.15], [0.62, 0.38, 0.26],
                    [0.47, 0.28, 0.19], [0.55, 0.33, 0.23], [0.36, 0.22, 0.16]])
    ci = (tone[tid] * len(pal)).astype(int) % len(pal)
    c_a = pal[ci]; c_b = pal[(ci + 1) % len(pal)]
    alb = lerp(c_a, c_b, fbm(S, 8, 4, seed=84) * 0.6)
    alb = alb * (0.88 + 0.24 * fine[..., None]) * (0.92 + 0.16 * mac[..., None])
    # quemado/más oscuro hacia el labio y cara de cocción
    alb = alb * (1 - 0.12 * smoothstep(0.6, 1.0, t)[..., None])
    # desvanecido por sol en la cresta de cobijas
    alb = lerp(alb, alb * np.array([1.12, 1.10, 1.08]), (cover_h * is_cover * 0.5)[..., None] * mac[..., None])
    # envejecimiento general (hollín/suciedad urbana)
    grime = smoothstep(0.4, 0.8, fbm(S, 5, 5, seed=92))
    alb = alb * (1 - 0.25 * grime[..., None])
    # suciedad que baja por los canales
    chan_mask = (~is_cover).astype(float) * smoothstep(0.7, 0.2, uc)
    dirt = chan_mask * (0.4 + 0.6 * fbm_aniso(S, 12, 3, 4, seed=85)) * (0.4 + 0.6 * t)
    alb = alb * (1 - 0.35 * dirt[..., None])
    # musgo: en canales, bajo labios y en la hendija
    low = 1 - normalize(blur_wrap(h, 3))
    m_n = fbm(S, 10, 6, seed=86)
    near_lip = np.exp(-(t / 0.12) ** 2) + over          # musgo crece en la sombra bajo el labio
    moss = smoothstep(0.72, 0.92, low * 0.35 + m_n * 0.6 + crev * 0.25 + near_lip * 0.3 + chan_mask * 0.1)
    moss *= smoothstep(0.4, 0.62, fbm(S, 3, 4, seed=87))
    moss_c = lerp(np.array([0.13, 0.17, 0.06]), np.array([0.30, 0.36, 0.11]), fbm(S, 64, 3, seed=88))
    moss_h = fbm(S, 96, 3, seed=89)
    alb = lerp(alb, moss_c, moss * 0.95)
    h = h + moss * moss_h * 0.05
    # líquen: manchas claras y amarillentas en cobijas
    lp = rng.random((140, 2)) * S
    lich = splats(S, lp, rng.gamma(2.0, 2.5, 140) + 1.5, profile="soft") * is_cover
    lich *= smoothstep(0.3, 0.6, fbm(S, 64, 2, seed=90))
    lich_c = lerp(np.array([0.70, 0.68, 0.58]), np.array([0.72, 0.62, 0.32]), fbm(S, 16, 2, seed=91))
    alb = lerp(alb, lich_c, lich * 0.8)
    # sombra fuerte bajo el labio + gradiente de oclusión al inicio de cada hilera
    alb = np.where(over[..., None], alb * 0.5, alb)
    top_shadow = 1 - 0.35 * (1 - smoothstep(0.0, 0.18, t)) * (0.6 + 0.4 * (~is_cover))
    alb = alb * top_shadow[..., None]
    # forma de barril: lados de la cobija y fondo del canal más ocluidos
    shape_ao = np.where(is_cover, 0.72 + 0.28 * cover_h, 0.78 + 0.12 * uc)
    alb = alb * shape_ao[..., None]

    rough = 0.74 + 0.08 * (fine - 0.5) + 0.2 * moss + 0.1 * lich + 0.06 * dirt
    ao_extra = (1 - 0.55 * over - 0.4 * crev) * top_shadow * (0.5 + 0.5 * shape_ao)
    ao = finish_ao(h, 4.0, 1.4, ao_extra)
    return save_pbr(OUT + "roof_clay", np.clip(alb, 0, 1), height=h, rough=np.clip(rough, 0, 1),
                    ao=ao, normal_strength=7.0)


# ============================================================ 5. zócalo de piedra laja
def gen_stone_base():
    S = 512; PX = S / 1.0
    rng = np.random.default_rng(100)
    wy = fbm(S, 6, 4, seed=101); wx = fbm(S, 6, 4, seed=102)
    n = 30
    f1, f2, ids = worley2(S, n, seed=103, jitter_warp=(wy, wx, 40))
    edge = f2 - f1
    jw = 3.2 + 1.5 * fbm(S, 16, 3, seed=104)  # ancho de junta variable
    stone = smoothstep(jw, jw + 3.0, edge)
    bevel = smoothstep(jw, jw + 14.0, edge)
    face = ridged(S, 8, 5, seed=105)
    face2 = fbm(S, 64, 3, seed=106)
    s_h = rng.normal(0, 1, n); s_tx = rng.normal(0, 1, n); s_ty = rng.normal(0, 1, n)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    plane = (s_tx[ids] * np.sin(xx / S * 2 * np.pi) + s_ty[ids] * np.sin(yy / S * 2 * np.pi)) * 0.02
    mortar_n = fbm(S, 96, 3, seed=107)
    h = (0.25 + 0.08 * mortar_n) * (1 - stone) + stone * (0.55 + 0.25 * bevel + 0.10 * face + 0.05 * face2
                                                          + s_h[ids] * 0.05 + plane)
    # desportilladuras en aristas
    chip = smoothstep(0.7, 0.8, fbm(S, 48, 3, seed=108)) * stone * (1 - bevel)
    h = h - chip * 0.1

    pal = np.array([[0.47, 0.45, 0.42], [0.56, 0.51, 0.43], [0.38, 0.37, 0.35], [0.60, 0.56, 0.49],
                    [0.49, 0.41, 0.33], [0.43, 0.42, 0.40], [0.53, 0.47, 0.38]])
    tone = rng.integers(0, len(pal), n)
    sc = pal[tone[ids]] * (1 + rng.normal(0, 0.06, n)[ids])[..., None]
    veins = smoothstep(0.88, 0.97, ridged(S, 6, 5, seed=109))
    speck = smoothstep(0.7, 0.9, fbm(S, 256, 2, seed=110))
    sc = sc * (0.85 + 0.25 * face2[..., None]) * (1 - 0.1 * veins[..., None]) * (1 + 0.15 * speck[..., None])
    # capas sedimentarias de la laja (bandas suaves)
    bands = fbm_aniso(S, 4, 24, 4, seed=111)
    sc = sc * (0.92 + 0.16 * bands[..., None])
    mortar = np.array([0.56, 0.54, 0.50]) * (0.85 + 0.3 * mortar_n[..., None])
    alb = lerp(mortar, sc, stone)
    # mugre en juntas y en bordes, humedad de abajo
    cav = normalize(cavity(h, 3.0))
    alb = alb * (1 - 0.35 * cav[..., None])
    damp = smoothstep(0.55, 0.8, fbm(S, 4, 5, seed=112))
    alb = alb * (1 - 0.18 * damp[..., None])
    musgo = smoothstep(0.75, 0.9, fbm(S, 12, 4, seed=113)) * (1 - stone)
    alb = lerp(alb, np.array([0.20, 0.25, 0.12]), musgo * 0.7)
    rough = 0.82 + 0.10 * (1 - stone) - 0.08 * damp * stone + 0.06 * (face - 0.5) + 0.04 * speck * -1
    ao = finish_ao(h, 4.0, 1.3)
    return save_pbr(OUT + "stone_base", np.clip(alb, 0, 1), height=h, rough=np.clip(rough, 0, 1),
                    ao=ao, normal_strength=6.0)


# ============================================================ 6. fibrocemento ondulado
def gen_fibrocement():
    S = 512; PX = S / 2.0
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    rng = np.random.default_rng(120)
    waves = 11; pitch = S / waves
    ph = xx / pitch * 2 * np.pi
    prof = 0.5 + 0.5 * np.cos(ph)          # crestas en x = k*pitch
    lap_y = 0.75 * S                        # traslapo horizontal (1.5 m)
    t = ((yy - lap_y) % S) / S              # 0 justo bajo el traslapo .. 1 en el borde de la lámina de arriba
    h = 0.15 + 0.6 * prof + 0.08 * t
    # traslapo: la lámina de arriba termina en lap_y con un pequeño escalón
    d_lap = (yy - lap_y)
    below = (d_lap >= 0) & (d_lap < 10)
    h = h - np.where(below, 0.12 * np.exp(-d_lap / 5.0), 0)
    edge = np.exp(-((d_lap + 1.0) / 1.2) ** 2)
    h = h + edge * 0.05
    # traslapo lateral (una onda más alta cada 5 ondas, borde de lámina)
    side_x = 5 * pitch
    dsx = np.abs(((xx - side_x + pitch * 0.5) + S / 2) % S - S / 2)
    side = smoothstep(pitch * 0.55, pitch * 0.45, dsx)
    h = h + side * 0.04
    fine = fbm(S, 128, 3, seed=121)
    mac = fbm(S, 4, 5, seed=122)
    fibers = fbm_aniso(S, 64, 8, 3, seed=123)  # fibra/textura del cemento
    h = h + 0.02 * fine + 0.015 * fibers + 0.01 * mac
    # ganchos/tornillos en crestas, sobre el traslapo, cada 2 ondas
    fast = [(lap_y - 14 + rng.normal(0, 1), (k * pitch) % S) for k in range(0, waves, 2)]
    cap = splats(S, fast, [3.2] * len(fast), profile="dome")
    h = h + cap * 0.08

    # --- albedo
    base = np.array([0.54, 0.54, 0.52])
    alb = base * (0.9 + 0.12 * mac[..., None] + 0.08 * fine[..., None] + 0.04 * fibers[..., None])
    # envejecimiento: mancha negra de líquen/hongo en manchones, más en los valles
    valley = 1 - prof
    blot_n = fbm(S, 8, 6, seed=124)
    blot = smoothstep(0.5, 0.8, blot_n * 0.8 + valley * 0.2 + t * 0.15)
    spots = smoothstep(0.66, 0.76, fbm(S, 32, 5, seed=125)) * smoothstep(0.45, 0.7, blot_n)
    spots = blur_wrap(spots, 0.8)
    black = np.clip(blot * 0.45 + spots * 0.55, 0, 1)
    alb = lerp(alb, np.array([0.22, 0.22, 0.21]) * (0.8 + 0.4 * fine[..., None]), black * 0.8)
    # líquen claro (anillos blancuzcos) en crestas
    lp = rng.random((90, 2)) * S
    lich = splats(S, lp, rng.gamma(2.0, 2.0, 90) + 1.5, profile="soft") * smoothstep(0.4, 0.8, prof)
    alb = lerp(alb, np.array([0.74, 0.73, 0.66]), lich * 0.6)
    # musgo en los valles cerca del traslapo
    moss = smoothstep(0.7, 0.88, valley * 0.45 + fbm(S, 16, 4, seed=126) * 0.6 + smoothstep(30, 0, np.abs(d_lap)) * 0.3)
    moss *= smoothstep(0.45, 0.65, fbm(S, 4, 3, seed=127))
    alb = lerp(alb, lerp(np.array([0.12, 0.15, 0.07]), np.array([0.24, 0.28, 0.11]), fine), moss * 0.85)
    h = h + moss * fine * 0.03
    # óxido que chorrea desde los ganchos
    rust_st = streaks(S, [(p[0] + 2, p[1]) for p in fast], rng.uniform(0.15, 0.5, len(fast)) * PX,
                      [2.5] * len(fast), rng.uniform(0.6, 1.0, len(fast)), seed=128, wiggle=3)
    rust_c = np.array([0.45, 0.24, 0.12])
    alb = lerp(alb, rust_c, np.clip(rust_st * 0.8 + cap * 0.9, 0, 1))
    # suciedad bajo el traslapo y chorreaduras
    alb = alb * (1 - 0.45 * np.where(below, np.exp(-d_lap / 6.0), 0)[..., None])
    dr = streaks(S, [(rng.uniform(0, S), (rng.integers(0, waves) + 0.5) * pitch + rng.normal(0, 3))
                     for _ in range(30)], rng.uniform(0.2, 1.0, 30) * PX, rng.uniform(2, 5, 30),
                 rng.uniform(0.3, 0.8, 30), seed=129, wiggle=4)
    alb = alb * (1 - 0.3 * dr[..., None])

    rough = 0.86 + 0.06 * (fine - 0.5) + 0.06 * moss + 0.04 * black - 0.15 * cap + 0.04 * lich
    metal = cap * 0.0
    ao_extra = 1 - 0.5 * np.where(below, np.exp(-d_lap / 5.0), 0)
    ao = finish_ao(h, 5.0, 1.2, ao_extra)
    return save_pbr(OUT + "fibrocement", np.clip(alb, 0, 1), height=h, rough=np.clip(rough, 0, 1),
                    metal=metal, ao=ao, normal_strength=6.0)


SETS = {
    "stucco": gen_stucco,
    "concrete_board": gen_concrete_board,
    "concrete_smooth": gen_concrete_smooth,
    "roof_clay": gen_roof_clay,
    "stone_base": gen_stone_base,
    "fibrocement": gen_fibrocement,
}


def tinted_stucco_sheet(out_png):
    """Muestra el estuco con los 6 tintes de las casas (mismo cálculo que albedo_color en Godot)."""
    from PIL import Image
    alb = np.asarray(Image.open(os.path.join(ROOT, OUT + "stucco_albedo.png")).convert("RGB"),
                     dtype=np.float64) / 255
    tiles = []
    for c in HOUSE_TINTS:
        lin = (alb ** 2.2) * (np.array(c) ** 2.2)  # Godot multiplica en lineal
        tiles.append((np.clip(lin, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8))
    row1 = np.concatenate(tiles[:3], 1); row2 = np.concatenate(tiles[3:], 1)
    Image.fromarray(np.concatenate([row1, row2], 0)).resize((1536, 1024)).save(out_png)


# Mismos 6 tonos que usa palette.gd para stucco(variant) (copiados aquí, no se edita palette.gd).
HOUSE_TINTS = [(0.78, 0.74, 0.64), (0.66, 0.45, 0.36), (0.42, 0.55, 0.6),
               (0.8, 0.64, 0.36), (0.5, 0.6, 0.48), (0.72, 0.72, 0.7)]


def main():
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    do_prev = "--preview" in sys.argv
    os.makedirs(os.path.join(ROOT, OUT), exist_ok=True)
    for name, fn in SETS.items():
        if only and name not in only:
            continue
        fn()
        print("ok", name)
        if do_prev:
            preview(OUT + name, PREV + name + "_prev.png")
    if do_prev:
        contact_sheet([PREV + n + "_prev.png" for n in SETS if os.path.exists(PREV + n + "_prev.png")],
                      PREV + "sheet.png", cell=512)
        if os.path.exists(os.path.join(ROOT, OUT + "stucco_albedo.png")):
            tinted_stucco_sheet(PREV + "stucco_tints.png")


if __name__ == "__main__":
    main()

"""F1-02 — familia "paving": andenes, adoquines, baldosa táctil y sardinel.

Regenerar:  python3 tools/texgen/paving.py          (todo)
            python3 tools/texgen/paving.py hex      (un set; nombres: ver SETS al final)

Escalas físicas (1 tile =):
  anden_concreto   1024 px = 2.0 m   losas 1 x 1 m con borde bruñado, juntas, grietas, chicles, parches
  tactil_guia       512 px = 0.4 m   2x2 baldosas táctiles amarillas de 20 cm, 3 barras por baldosa (barras a lo largo de V)
  tactil_alerta     512 px = 0.4 m   2x2 baldosas táctiles amarillas de 20 cm, 3x3 botones por baldosa
  adoquin_hex       1024 px = 2.0 m  adoquín hexagonal gris (~28.6 cm entre caras), musgo y humedad en juntas
  adoquin_espina    1024 px = 2.0 m  adoquín 20x10 cm en espina de pescado a 90°
  anden_ladrillo    1024 px = 2.0 m  ladrillo tolete 24.5x12 cm (+1 cm junta) en hiladas trabadas (soga)
  sardinel          512 px = 1.0 m   bordillo prefabricado: junta entre piezas en u=0, desportillado junto a la junta

Todo determinista (semillas fijas) y tileable (todas las operaciones usan wrap).
Alturas se trabajan en METROS y se convierten a normal con el tamaño físico del píxel.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (ROOT, blur_wrap, fbm, gradient_map, height_to_normal, hex2rgb,  # noqa: E402
                    lerp, normalize, preview, save_pbr, warp)

OUT = "art/tex/paving"
PREV = "/tmp/f1_paving"


# =================================================================== utilidades propias
def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def ihash(a, b, seed=0):
    """Hash entero -> [0,1) vectorizado (estable entre ejecuciones)."""
    a = np.asarray(a, dtype=np.int64) & 0xFFFF
    b = np.asarray(b, dtype=np.int64) & 0xFFFF
    h = (a * 374761393 + b * 668265263 + (seed + 1) * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return h.astype(np.float64) / 4294967296.0


def grid(S):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    return xx + 0.5, yy + 0.5


def normal_m(h_m, px_m, k=1.0):
    """Normal OpenGL desde altura en metros (pendiente física, k exagera)."""
    return height_to_normal(h_m / px_m, strength=k)


def ao_m(h_m, px_m, radius_m=0.02, depth_m=0.004, k=1.0):
    r = max(radius_m / px_m, 1.0)
    local = blur_wrap(h_m, r)
    return np.clip(1.0 - np.clip((local - h_m) / depth_m, 0, 1) * k, 0, 1)


def wrap_draw(S, draw_fn, mode="L"):
    """Dibuja con PIL en un lienzo SxS repitiendo en las 9 copias desplazadas (tileable)."""
    im = Image.new(mode, (S, S), 0)
    d = ImageDraw.Draw(im)
    for oy in (-S, 0, S):
        for ox in (-S, 0, S):
            draw_fn(d, ox, oy)
    return np.asarray(im, dtype=np.float64) / 255.0


def cracks(S, n, seed, length=(150, 400), width=(1, 3), step=6.0, jitter=0.5):
    """Grietas finas por caminata aleatoria (tileable). Devuelve máscara [0,1]."""
    rng = np.random.default_rng(seed)
    lines = []
    for _ in range(n):
        p = rng.random(2) * S
        ang = rng.random() * np.pi * 2
        pts = [p.copy()]
        L = rng.uniform(*length)
        w = int(rng.integers(width[0], width[1] + 1))
        t = 0.0
        while t < L:
            ang += rng.normal(0, jitter)
            p = p + step * np.array([np.cos(ang), np.sin(ang)])
            pts.append(p.copy())
            t += step
            if rng.random() < 0.04:   # ramita
                q, a2 = p.copy(), ang + rng.choice([-1, 1]) * rng.uniform(0.6, 1.2)
                br = [q.copy()]
                for _k in range(int(rng.integers(3, 10))):
                    a2 += rng.normal(0, jitter)
                    q = q + step * np.array([np.cos(a2), np.sin(a2)])
                    br.append(q.copy())
                lines.append((br, max(1, w - 1)))
        lines.append((pts, w))

    def fn(d, ox, oy):
        for pts, w in lines:
            d.line([(x + ox, y + oy) for x, y in pts], fill=255, width=w, joint="curve")
    m = wrap_draw(S, fn)
    return np.clip(blur_wrap(m, 0.6), 0, 1)


def spots(S, n, seed, r=(2, 6), soft=1.0):
    """Manchas circulares (chicles, goterones) tileables. Devuelve máscara e intensidad aleatoria."""
    rng = np.random.default_rng(seed)
    items = [(rng.random() * S, rng.random() * S, rng.uniform(*r), rng.uniform(0.5, 1.0), rng.uniform(0.7, 1.0))
             for _ in range(n)]

    def fn(d, ox, oy):
        for x, y, rr, v, asp in items:
            d.ellipse([x + ox - rr, y + oy - rr * asp, x + ox + rr, y + oy + rr * asp], fill=int(255 * v))
    m = wrap_draw(S, fn)
    return blur_wrap(m, soft) if soft > 0 else m


def hsv_shift(rgb, dh=0.0, ds=1.0, dv=1.0):
    """Ajuste simple de saturación/valor por píxel (dh ignorado, se usa mezcla de tonos)."""
    lum = (rgb * np.array([0.299, 0.587, 0.114])).sum(-1, keepdims=True)
    out = lum + (rgb - lum) * (ds if np.ndim(ds) < 2 else ds[..., None])
    return out * (dv if np.ndim(dv) < 2 else dv[..., None])


def specks(S, cells, seed):
    """Celular rápido (1 punto con jitter por celda, busca 3x3). Devuelve (dist F1 en px, id). Tileable."""
    rng = np.random.default_rng(seed)
    jit = rng.random((cells, cells, 2))
    c = S / cells
    x, y = grid(S)
    gx = np.floor(x / c).astype(int); gy = np.floor(y / c).astype(int)
    best = np.full((S, S), np.inf); bid = np.zeros((S, S), np.int64)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            cx = gx + ox; cy = gy + oy
            j = jit[np.mod(cy, cells), np.mod(cx, cells)]
            px_ = (cx + j[..., 0]) * c; py_ = (cy + j[..., 1]) * c
            d = (x - px_) ** 2 + (y - py_) ** 2
            m = d < best
            best = np.where(m, d, best)
            bid = np.where(m, np.mod(cy, cells) * cells + np.mod(cx, cells), bid)
    return np.sqrt(best), bid


# =================================================================== layouts (todas periódicas)
def layout_grid(S, cw, ch, row_offset=0.0):
    """Piezas rectangulares cw x ch px; cada fila desplazada row_offset*cw. S/cw y S/ch enteros."""
    x, y = grid(S)
    row = np.floor(y / ch)
    xs = x + row * row_offset * cw
    col = np.floor(xs / cw)
    lx = xs - col * cw
    ly = y - row * ch
    ed = np.minimum(np.minimum(lx, cw - lx), np.minimum(ly, ch - ly))
    ncol = int(round(S / cw)); nrow = int(round(S / ch))
    pid = (np.mod(col, ncol) * 1000 + np.mod(row, nrow)).astype(np.int64)
    return dict(pid=pid, ed=ed, dx=lx - cw / 2, dy=ly - ch / 2, w=cw, h=ch,
                vertical=np.zeros_like(x, dtype=bool))


def layout_herringbone(S, u):
    """Espina de pescado 90° con adoquines 2u x u (periodo 4u). S/(4u) entero."""
    x, y = grid(S)
    X, Y = x / u, y / u
    cx, cy = np.floor(X), np.floor(Y)
    d = cy - cx
    k = np.floor((d + 1) / 4)
    cyb = cy - 4 * k            # trasladar a la banda base (d' en -1..2)
    db = cyb - cx
    ox = np.where(db == 0, cx, np.where(db == -1, cyb, cx))
    oy = np.where(db == 0, cx, np.where(db == -1, cyb, cx + 1))
    vert = db >= 1
    oy = oy + 4 * k
    bw = np.where(vert, 1.0, 2.0)
    bh = np.where(vert, 2.0, 1.0)
    lx = (X - ox) * u
    ly = (Y - oy) * u
    W, H = bw * u, bh * u
    ed = np.minimum(np.minimum(lx, W - lx), np.minimum(ly, H - ly))
    n = int(round(S / u))
    pid = (np.mod(ox, n) * 1000 + np.mod(oy, n) + vert * 500000).astype(np.int64)
    return dict(pid=pid, ed=ed, dx=lx - W / 2, dy=ly - H / 2, w=u, h=u, vertical=vert)


def layout_hex(S, ncol, nrow):
    """Hexágonos (punta arriba) en retícula escalonada; nrow par. Voronoi exacto con wrap."""
    x, y = grid(S)
    w = S / ncol
    rh = S / nrow
    centers = []
    for r in range(nrow):
        for c in range(ncol):
            centers.append(((c + 0.5 * (r % 2) + 0.25) * w, (r + 0.5) * rh))
    best1 = np.full((S, S), np.inf); best2 = np.full((S, S), np.inf)
    ids = np.zeros((S, S), np.int64); bdx = np.zeros((S, S)); bdy = np.zeros((S, S))
    for i, (px, py) in enumerate(centers):
        ddx = (x - px + S / 2) % S - S / 2
        ddy = (y - py + S / 2) % S - S / 2
        dd = ddx * ddx + ddy * ddy
        c1 = dd < best1
        c2 = (~c1) & (dd < best2)
        best2 = np.where(c1, best1, np.where(c2, dd, best2))
        best1 = np.where(c1, dd, best1)
        ids = np.where(c1, i, ids)
        bdx = np.where(c1, ddx, bdx); bdy = np.where(c1, ddy, bdy)
    ed = (best2 - best1) / (2 * w)       # distancia al bisector (vecinos a distancia ~w)
    return dict(pid=ids, ed=ed, dx=bdx, dy=bdy, w=w, h=w, vertical=np.zeros_like(x, dtype=bool))


# =================================================================== núcleo común de adoquín
def pavers(S, px_m, L, seed, *, joint_m, joint_depth_m, bevel_m, bevel_depth_m, tilt_m, bulge_m=0.0,
           chip_amount=0.5, chip_m=0.012):
    """Altura (m) de piezas con junta, bisel, inclinación por pieza, bombeo y desportillado."""
    pid, ed = L["pid"], L["ed"]
    ed_m = ed * px_m
    r1 = ihash(pid, 1, seed); r2 = ihash(pid, 2, seed); r3 = ihash(pid, 3, seed)
    # inclinación y asentamiento por pieza
    tilt = ((r1 - 0.5) * L["dx"] + (r2 - 0.5) * L["dy"]) * px_m / max(L["w"] * px_m, 1e-6) * tilt_m
    settle = (r3 - 0.5) * tilt_m * 0.8
    # bisel redondeado
    bev = sstep(0, bevel_m, ed_m)
    h = -bevel_depth_m * (1 - bev) ** 1.5 + tilt + settle
    # bombeo leve (piezas un poco abombadas)
    if bulge_m > 0:
        rad = np.sqrt((L["dx"] / (L["w"] * 0.6)) ** 2 + (L["dy"] / (L["h"] * 0.6)) ** 2)
        h += bulge_m * np.clip(1 - rad ** 2, 0, 1)
    # desportillado: mordiscos en el borde según ruido
    n = fbm(S, base_cells=int(S * px_m * 12), octaves=3, seed=seed + 7)
    chip_zone = 1 - sstep(chip_m * 0.3, chip_m, ed_m)
    chips = sstep(1 - chip_amount * 0.45, 1 - chip_amount * 0.45 + 0.08, n) * chip_zone
    h -= chips * bevel_depth_m * 1.6
    # junta
    jw = joint_m * 0.5
    joint = 1 - sstep(jw * 0.6, jw * 1.15, ed_m)
    sand = fbm(S, base_cells=int(S * px_m * 40), octaves=3, seed=seed + 11)
    jh = -joint_depth_m + (sand - 0.5) * joint_depth_m * 0.5
    h = h * (1 - joint) + jh * joint
    return h, joint, chips, dict(r1=r1, r2=r2, r3=r3)


def finish(S, px_m, h, albedo, rough, *, ao_r=0.02, ao_d=0.004, nk=1.0, micro=None, micro_m=0.0004):
    """Añade micro-grano a la altura, calcula normal y AO."""
    if micro is not None:
        h = h + (micro - 0.5) * micro_m
    nrm = normal_m(h, px_m, nk)
    ao = ao_m(h, px_m, ao_r, ao_d) * ao_m(h, px_m, ao_r * 0.25, ao_d * 0.5, 0.6)
    ao = 0.25 + 0.75 * ao
    return nrm, ao


def save(name, albedo, nrm, rough, ao):
    save_pbr(f"{OUT}/{name}", np.clip(albedo, 0, 1), rough=np.clip(rough, 0.03, 1), ao=ao, normal=nrm)
    # presupuesto (~12 MB/familia): cuantización leve con dither de ruido -> PNG ~25% más pequeños, invisible
    rng = np.random.default_rng(len(name))
    for suf, q in (("albedo", 2), ("normal", 2), ("orm", 4)):
        f = os.path.join(ROOT, OUT, f"{name}_{suf}.png")
        a = np.asarray(Image.open(f), dtype=np.float64)
        d = rng.random(a.shape[:2])[..., None] if a.ndim == 3 else rng.random(a.shape)
        a = np.clip(np.floor(a / q + d * 0.5 + 0.25) * q, 0, 255)
        Image.fromarray(a.astype(np.uint8)).save(f, optimize=True)
    preview(f"{OUT}/{name}", f"{PREV}/{name}_prev.png")
    print("ok", name)


def grain(S, seed, cells=None):
    cells = cells or S // 4
    return fbm(S, base_cells=cells, octaves=2, seed=seed)


def macro_stains(S, seed, scale_cells=3):
    a = fbm(S, base_cells=scale_cells, octaves=5, seed=seed)
    b = fbm(S, base_cells=scale_cells * 2, octaves=4, seed=seed + 1)
    return warp(a, b, fbm(S, scale_cells * 2, 4, seed=seed + 2), S * 0.08)


# =================================================================== 1. andén de concreto
def anden_concreto():
    S, tile = 1024, 2.0
    px = tile / S
    L = layout_grid(S, 512, 512)
    # junta aserrada fina 8 mm, borde bruñado redondeado
    h, joint, chips, rr = pavers(S, px, L, 101, joint_m=0.009, joint_depth_m=0.006, bevel_m=0.008,
                                 bevel_depth_m=0.002, tilt_m=0.004, chip_amount=0.45, chip_m=0.02)
    ed_m = L["ed"] * px
    # franja bruñada (llana) de 4 cm junto a la junta: más lisa y algo más oscura, con surco de herramienta
    border = 1 - sstep(0.038, 0.044, ed_m)
    tool_line = np.exp(-((ed_m - 0.041) / 0.002) ** 2)
    h -= tool_line * 0.0012
    # textura escobillada leve (líneas finas en una dirección por losa)
    x, y = grid(S)
    broom_dir = ihash(L["pid"], 9, 101) > 0.5
    coord = np.where(broom_dir, x, y)
    bn = fbm(S, base_cells=8, octaves=3, seed=120)
    broom = np.sin((coord + bn * 40) * 2 * np.pi / 5.0) * 0.5 + 0.5
    broom = broom * (fbm(S, 64, 3, seed=121) * 0.6 + 0.4)
    h += (broom - 0.5) * 0.00025 * (1 - border)

    # micro y meso del concreto
    micro = fbm(S, base_cells=256, octaves=2, seed=130)
    meso = fbm(S, base_cells=24, octaves=4, seed=131)
    pores = spots(S, 900, 132, r=(0.6, 1.8), soft=0.4)
    h -= pores * 0.0012

    # agregado (piedrita) expuesta en zonas gastadas, como el andén de la ref 7
    wear = macro_stains(S, 140, 3)
    aggr_d, aggr_id = specks(S, 52, 141)
    aggr_r = 1.2 + 2.5 * ihash(aggr_id, 3, 141)
    aggr = (1 - sstep(aggr_r * 0.7, aggr_r, aggr_d)) * sstep(0.62, 0.8, wear) * (1 - border)
    aggr_col = gradient_map(ihash(aggr_id, 0, 5), [(0, hex2rgb("6d6760")), (0.5, hex2rgb("a49c90")),
                                                    (1, hex2rgb("4d4a47"))])
    h += aggr * 0.0006

    # grietas y parche reparado
    cr = cracks(S, 3, 150, length=(160, 420), width=(1, 1), jitter=0.22) * 0.8
    h -= cr * 0.002
    patch_m = np.zeros((S, S))
    pm_noise = fbm(S, 16, 4, seed=151)
    # parche irregular en una losa
    blob = np.exp(-(((x - 300) / 120) ** 2 + ((y - 760) / 70) ** 2))
    patch_m = sstep(0.5, 0.56, blob + (pm_noise - 0.5) * 0.5)
    h += patch_m * 0.0008

    # -------- color
    base = np.array(hex2rgb("9d9a93"))
    slab_tone = 0.93 + 0.12 * rr["r1"]
    warmth = rr["r2"] * 0.03
    col = base * slab_tone[..., None]
    col = col + np.stack([warmth, warmth * 0.3, -warmth], -1)
    col *= (0.9 + 0.2 * meso)[..., None]
    col *= (0.94 + 0.12 * micro)[..., None]
    # manchas grandes de humedad/suciedad (ciudad tropical)
    st = macro_stains(S, 160, 2)
    dirt = sstep(0.45, 0.85, st)
    col = lerp(col, col * np.array([0.7, 0.69, 0.67]), dirt * 0.5)
    col *= (0.94 + 0.12 * fbm(S, 12, 5, seed=161))[..., None]
    # zonas de tráfico más limpias/pulidas en el centro de las losas
    col *= (1 - border * 0.06)[..., None]
    # suciedad acumulada junto a juntas y grietas
    near_j = np.exp(-ed_m / 0.012)
    col = lerp(col, np.array(hex2rgb("4a463f")), np.clip(near_j * 0.45 + joint * 0.8, 0, 1))
    col = lerp(col, np.array(hex2rgb("4a463f")), cr * 0.7)
    col = lerp(col, aggr_col, aggr * 0.8)
    # poros
    col *= (1 - pores * 0.35)[..., None]
    # parche más nuevo y frío
    col = lerp(col, col * np.array([1.1, 1.1, 1.12]) * (0.95 + 0.1 * micro)[..., None], patch_m * 0.8)
    # chicles (puntos planos gris oscuro, muy típicos del andén)
    gum = spots(S, 28, 170, r=(2.5, 5.5), soft=0.8)
    col = lerp(col, np.array(hex2rgb("4a4846")), np.clip(gum, 0, 1) * 0.6)
    h += np.clip(gum, 0, 1) * 0.0005
    # óxido / hojas descompuestas (manchas cafés tenues)
    rust = sstep(0.72, 0.9, fbm(S, 6, 5, seed=171)) * sstep(0.4, 0.7, fbm(S, 40, 3, seed=172))
    col = lerp(col, np.array(hex2rgb("6e5a43")), rust * 0.45)
    # bordes desportillados más claros (concreto fresco expuesto)
    col = lerp(col, np.array(hex2rgb("b4afa6")), chips * 0.5)

    # -------- rugosidad
    rough = 0.82 + 0.08 * (micro - 0.5) + 0.06 * (meso - 0.5)
    rough -= border * 0.12              # franja llaneada más lisa
    rough -= (1 - sstep(0.3, 0.7, st)) * 0.04
    rough += joint * 0.1 + cr * 0.1 + pores * 0.08
    rough -= gum * 0.25                # chicle brilla
    rough -= patch_m * 0.05
    nrm, ao = finish(S, px, h, col, rough, micro=micro, micro_m=0.0005, nk=1.3, ao_r=0.015, ao_d=0.003)
    ao *= (1 - cr * 0.3)
    save("anden_concreto", col, nrm, rough, ao)


# =================================================================== 2/3. baldosa táctil
def tactil(kind):
    S, tile = 512, 0.4
    px = tile / S
    L = layout_grid(S, 256, 256)      # baldosas de 20 cm
    h, joint, chips, rr = pavers(S, px, L, 201 if kind == "guia" else 202, joint_m=0.004, joint_depth_m=0.004,
                                 bevel_m=0.003, bevel_depth_m=0.0015, tilt_m=0.0015, chip_amount=0.35,
                                 chip_m=0.006)
    lx = L["dx"] * px; ly = L["dy"] * px      # m desde el centro de la baldosa
    if kind == "guia":
        # 3 barras a lo largo de V (eje y de la imagen), 66 mm entre ejes, 25 mm de ancho arriba, 170 mm de largo
        off = np.round(lx / 0.066) * 0.066
        ax = np.abs(lx - off)
        ay = np.maximum(np.abs(ly) - 0.085 + 0.0125, 0)
        d = np.sqrt(np.maximum(ax - 0.0, 0) ** 2 + ay ** 2)       # cápsula
        valid = np.abs(off) <= 0.067
        prof = 1 - sstep(0.0125 - 0.003, 0.0125 + 0.003, d)     # flanco con talud
        relief = prof * valid
    else:
        # 3x3 botones truncados: 25 mm arriba, 35 mm base, 66 mm entre ejes
        ox = np.round(lx / 0.066) * 0.066; oy = np.round(ly / 0.066) * 0.066
        d = np.sqrt((lx - ox) ** 2 + (ly - oy) ** 2)
        valid = (np.abs(ox) <= 0.067) & (np.abs(oy) <= 0.067)
        prof = 1 - sstep(0.0125, 0.0175, d)
        relief = prof * valid
    relief_h = relief * 0.005
    # desgaste: cimas redondeadas y algo rebajadas
    wear = fbm(S, 8, 4, seed=210)
    relief_h *= (0.85 + 0.15 * wear)
    h += relief_h
    micro = fbm(S, 128, 2, seed=211)
    meso = fbm(S, 12, 4, seed=212)
    pores = spots(S, 160, 213, r=(0.5, 1.2), soft=0.5) * 0.6
    h -= pores * 0.0003

    # color: amarillo tráfico de concreto pigmentado, gastado y sucio (ref 1: ocre sucio)
    base = np.array(hex2rgb("c99a2e"))
    tone = 0.9 + 0.15 * rr["r1"]
    col = base * tone[..., None]
    col *= (0.88 + 0.22 * meso)[..., None] * (0.95 + 0.1 * micro)[..., None]
    # cimas pulidas por el paso: más claras y desaturadas
    top = sstep(0.6, 1.0, relief) * (0.4 + 0.6 * wear)
    col = lerp(col, np.array(hex2rgb("d9c08a")), top * 0.45)
    # mugre en los valles entre relieves y en juntas
    valley = (1 - relief) * sstep(0.35, 0.8, macro_stains(S, 220, 3))
    col = lerp(col, np.array(hex2rgb("6c5530")), valley * 0.55)
    col = lerp(col, np.array(hex2rgb("3d362b")), np.clip(joint * 0.9 + np.exp(-L["ed"] * px / 0.004) * 0.3, 0, 1))
    # pintura/pigmento saltado: se ve el concreto gris
    chipped = sstep(0.8, 0.86, fbm(S, 24, 4, seed=230)) * (0.3 + 0.7 * top)
    col = lerp(col, np.array(hex2rgb("8f8a80")), np.clip(chipped + chips * 0.6, 0, 1) * 0.7)
    gum = spots(S, 6, 231, r=(4, 7), soft=0.6)
    col = lerp(col, np.array(hex2rgb("2d2a26")), np.clip(gum, 0, 1) * 0.7)
    col *= (1 - pores * 0.3)[..., None]

    rough = 0.72 + 0.08 * (micro - 0.5) - top * 0.16 + valley * 0.1 + joint * 0.15 - gum * 0.2
    nrm, ao = finish(S, px, h, col, rough, micro=micro, micro_m=0.0002, nk=1.0, ao_r=0.008, ao_d=0.003)
    save(f"tactil_{kind}", col, nrm, rough, ao)


# =================================================================== 4. adoquín hexagonal (Parque de Boston)
def moss_in_joints(S, joint, seed, amount=0.6):
    m = macro_stains(S, seed, 3)
    patch = sstep(1 - amount, 1 - amount + 0.25, m)
    fine = fbm(S, 96, 3, seed=seed + 5)
    spread = blur_wrap(joint, 3.0)
    return np.clip((joint * 1.2 + spread * 1.5) * patch * (0.5 + fine), 0, 1)


def adoquin_hex():
    S, tile = 1024, 2.0
    px = tile / S
    L = layout_hex(S, 7, 8)
    h, joint, chips, rr = pavers(S, px, L, 301, joint_m=0.007, joint_depth_m=0.007, bevel_m=0.009,
                                 bevel_depth_m=0.004, tilt_m=0.004, bulge_m=0.0006, chip_amount=0.55,
                                 chip_m=0.018)
    micro = fbm(S, 256, 2, seed=310)
    meso = fbm(S, 32, 4, seed=311)
    pores = spots(S, 1400, 312, r=(0.5, 1.6), soft=0.4)
    h -= pores * 0.0009
    # superficie de adoquín vibrocompactado: árido fino visible
    sand_d, sand_id = specks(S, 64, 313)
    speck = (1 - sstep(1.0, 2.2, sand_d)) * (ihash(sand_id, 2, 313) > 0.3)
    speck_col = gradient_map(ihash(sand_id, 1, 9), [(0, hex2rgb("5b5753")), (0.6, hex2rgb("8e8780")),
                                                    (1, hex2rgb("bdb6ad"))])

    # color: gris cálido claro (ref 5), piezas con leve variación rosada/gris
    base = np.array(hex2rgb("96918b"))
    tone = 0.95 + 0.09 * rr["r1"]
    tint = np.stack([1 + (rr["r2"] - 0.5) * 0.03, np.ones_like(tone), 1 - (rr["r2"] - 0.5) * 0.03], -1)
    col = base * tone[..., None] * tint
    col *= (0.9 + 0.2 * meso)[..., None] * (0.93 + 0.14 * micro)[..., None]
    col = lerp(col, speck_col, speck * 0.35)
    # humedad: manchas grandes oscuras que siguen las juntas (agua retenida en la arena)
    st = macro_stains(S, 320, 2)
    near_j = np.exp(-L["ed"] * px / 0.03)
    damp = np.clip(sstep(0.45, 0.8, st) * (0.4 + 0.6 * near_j), 0, 1)
    col = lerp(col, col * np.array([0.58, 0.6, 0.6]), damp * 0.7)
    # algunas piezas manchadas enteras (más viejas/oscuras)
    old = (rr["r3"] > 0.9).astype(float)
    col *= (1 - old * 0.12)[..., None]
    # líquen negro y puntitos (muy típico bajo árboles)
    lichen = spots(S, 260, 330, r=(1.5, 4.5), soft=0.8) * sstep(0.4, 0.7, fbm(S, 5, 4, seed=331))
    col = lerp(col, np.array(hex2rgb("3a3a35")), np.clip(lichen, 0, 1) * 0.55)
    # juntas: arena oscura + musgo
    jdirt = np.clip(joint + np.exp(-L["ed"] * px / 0.006) * 0.4, 0, 1)
    col = lerp(col, np.array(hex2rgb("4b463e")), jdirt * 0.8)
    moss = moss_in_joints(S, joint, 340, 0.45)
    moss_col = gradient_map(fbm(S, 64, 3, seed=341), [(0, hex2rgb("2f3a1c")), (0.5, hex2rgb("4b5a26")),
                                                      (1, hex2rgb("6d7a35"))])
    col = lerp(col, moss_col, moss * 0.9)
    h += moss * 0.003 * fbm(S, 128, 2, seed=342)
    col = lerp(col, np.array(hex2rgb("b5afa6")), chips * 0.45)
    col *= (1 - pores * 0.3)[..., None]

    rough = 0.86 + 0.07 * (micro - 0.5) + 0.05 * (meso - 0.5) - damp * 0.15 + moss * 0.06 - lichen * 0.05
    rough -= 0.06 * (1 - sstep(0.0, 0.5, np.sqrt(L["dx"] ** 2 + L["dy"] ** 2) / (L["w"] * 0.5)))  # centro pulido
    nrm, ao = finish(S, px, h, col, rough, micro=micro, micro_m=0.0006, nk=1.3, ao_r=0.02, ao_d=0.004)
    save("adoquin_hex", col, nrm, rough, ao)


# =================================================================== 5. adoquín en espina de pescado
def adoquin_espina():
    S, tile = 1024, 2.0
    px = tile / S
    L = layout_herringbone(S, 51.2)       # 10 cm
    h, joint, chips, rr = pavers(S, px, L, 401, joint_m=0.005, joint_depth_m=0.006, bevel_m=0.007,
                                 bevel_depth_m=0.0035, tilt_m=0.003, bulge_m=0.0004, chip_amount=0.5,
                                 chip_m=0.015)
    micro = fbm(S, 256, 2, seed=410)
    meso = fbm(S, 32, 4, seed=411)
    pores = spots(S, 1500, 412, r=(0.5, 1.5), soft=0.4)
    h -= pores * 0.0008
    # gris de plaza (ref 4): piezas más claras y más oscuras mezcladas
    pal = [(0.0, hex2rgb("8a8783")), (0.4, hex2rgb("9c9893")), (0.8, hex2rgb("aaa59e")), (1.0, hex2rgb("a0968e"))]
    col = gradient_map(rr["r1"], pal)
    col *= (0.9 + 0.2 * meso)[..., None] * (0.93 + 0.14 * micro)[..., None]
    # suciedad direccional sobre cada pieza (borde de arrastre)
    edge_dirt = np.exp(-L["ed"] * px / 0.01)
    st = macro_stains(S, 420, 2)
    grime = sstep(0.4, 0.85, st)
    col = lerp(col, col * 0.72, grime * 0.45)
    col = lerp(col, np.array(hex2rgb("47423b")), np.clip(joint * 0.85 + edge_dirt * 0.3, 0, 1))
    moss = moss_in_joints(S, joint, 430, 0.25)
    col = lerp(col, np.array(hex2rgb("3f4a22")), moss * 0.8)
    lichen = spots(S, 140, 431, r=(1.5, 4), soft=0.7) * sstep(0.45, 0.75, fbm(S, 5, 4, seed=432))
    col = lerp(col, np.array(hex2rgb("35342f")), np.clip(lichen, 0, 1) * 0.5)
    gum = spots(S, 25, 433, r=(3, 6), soft=0.6)
    col = lerp(col, np.array(hex2rgb("2c2a28")), np.clip(gum, 0, 1) * 0.7)
    col = lerp(col, np.array(hex2rgb("b0aaa1")), chips * 0.45)
    col *= (1 - pores * 0.3)[..., None]
    rough = 0.85 + 0.07 * (micro - 0.5) - grime * 0.1 + joint * 0.08 - gum * 0.2
    nrm, ao = finish(S, px, h, col, rough, micro=micro, micro_m=0.0005, nk=1.3, ao_r=0.018, ao_d=0.004)
    save("adoquin_espina", col, nrm, rough, ao)


# =================================================================== 6. andén de ladrillo tolete
def anden_ladrillo():
    S, tile = 1024, 2.0
    px = tile / S
    L = layout_grid(S, 128, 64, row_offset=0.5)    # módulo 25 x 12.5 cm
    h, joint, chips, rr = pavers(S, px, L, 501, joint_m=0.009, joint_depth_m=0.005, bevel_m=0.006,
                                 bevel_depth_m=0.003, tilt_m=0.003, bulge_m=0.0005, chip_amount=0.6,
                                 chip_m=0.016)
    micro = fbm(S, 256, 2, seed=510)
    meso = fbm(S, 48, 4, seed=511)
    pits = spots(S, 900, 512, r=(0.8, 2.5), soft=0.5)
    h -= pits * 0.0012
    # arcilla cocida: tonos naranja, rojo, quemado (ref 6)
    pal = [(0.0, hex2rgb("7e3b25")), (0.25, hex2rgb("9a4a2c")), (0.55, hex2rgb("ad5733")),
           (0.85, hex2rgb("bb6a3e")), (1.0, hex2rgb("a6603f"))]
    col = gradient_map(rr["r1"] * 0.85 + 0.15 * rr["r2"], pal)
    # ladrillos "flameados" con una cara más oscura
    flame = (rr["r3"] > 0.82) * sstep(-0.3, 0.6, (L["dx"] / L["w"]) * np.sign(rr["r2"] - 0.5) * 2)
    col *= (1 - flame * 0.3)[..., None]
    col *= (0.88 + 0.24 * meso)[..., None] * (0.92 + 0.16 * micro)[..., None]
    # pátina gris de pisadas (desgaste) y ensuciado general
    traffic = sstep(0.35, 0.8, macro_stains(S, 520, 2))
    col = lerp(col, np.array(hex2rgb("6e5a50")), traffic * 0.35)
    # eflorescencia blanquecina leve en algunos bordes
    effl = sstep(0.72, 0.9, fbm(S, 10, 4, seed=521)) * np.exp(-L["ed"] * px / 0.02)
    col = lerp(col, np.array(hex2rgb("b8aa98")), effl * 0.4)
    # mortero gris arenoso sucio y musgo
    mort = gradient_map(fbm(S, 128, 3, seed=530), [(0, hex2rgb("57524b")), (1, hex2rgb("8a847a"))])
    col = lerp(col, mort, joint * 0.92)
    col = lerp(col, col * 0.7, np.exp(-L["ed"] * px / 0.006)[..., None] * 0.5 * (1 - joint)[..., None])
    moss = moss_in_joints(S, joint, 540, 0.3)
    col = lerp(col, np.array(hex2rgb("3c4a20")), moss * 0.85)
    col = lerp(col, np.array(hex2rgb("c27a4f")), chips * 0.5)
    col *= (1 - pits * 0.3)[..., None]
    rough = 0.8 + 0.08 * (micro - 0.5) - traffic * 0.12 + joint * 0.12 + moss * 0.05
    nrm, ao = finish(S, px, h, col, rough, micro=micro, micro_m=0.0006, nk=1.3, ao_r=0.016, ao_d=0.004)
    save("anden_ladrillo", col, nrm, rough, ao)


# =================================================================== 7. sardinel prefabricado
def sardinel():
    S, tile = 512, 1.0
    px = tile / S
    x, y = grid(S)
    # una pieza por tile horizontal; la junta vertical queda en u=0
    ed = np.minimum(x, S - x)
    ed_m = ed * px
    micro = fbm(S, 128, 2, seed=610)
    meso = fbm(S, 16, 4, seed=611)
    # desportillado grande junto a la junta (concreto roto) y menudo en todo el canto
    n = warp(fbm(S, 12, 5, seed=612), fbm(S, 8, 3, seed=613), fbm(S, 8, 3, seed=614), 40)
    chip_w = 0.015 + 0.05 * sstep(0.45, 0.85, n)
    chipped = 1 - sstep(chip_w * 0.6, chip_w, ed_m)
    chip_depth = 0.006 + 0.01 * fbm(S, 32, 3, seed=615)
    h = -chipped * chip_depth
    joint = 1 - sstep(0.004, 0.007, ed_m)
    h = h * (1 - joint) - joint * 0.012
    # poros de vaciado (bugholes) y marcas de formaleta horizontales
    bug = spots(S, 110, 616, r=(0.7, 2.2), soft=0.5)
    h -= bug * 0.002
    form = np.sin(y * 2 * np.pi / (S / 4)) * 0.5 + 0.5
    h += (sstep(0.97, 1.0, form)) * 0.0004
    # golpes/raspones en todo el canto
    scuff = sstep(0.78, 0.85, fbm(S, 20, 5, seed=617))
    h -= scuff * 0.002

    base = np.array(hex2rgb("a6a39c"))
    col = base * (0.88 + 0.2 * meso)[..., None] * (0.93 + 0.14 * micro)[..., None]
    st = macro_stains(S, 620, 2)
    col = lerp(col, col * np.array([0.6, 0.6, 0.58]), sstep(0.45, 0.85, st) * 0.6)
    # salpicaduras de agua sucia (manchas verticales, escurridos)
    drip = normalize(ndimage.gaussian_filter(fbm(S, 48, 3, seed=622), (14, 0.8), mode="wrap"))
    col = lerp(col, np.array(hex2rgb("57534c")), sstep(0.55, 0.85, drip) * 0.5)
    # marcas negras de llanta
    # concreto expuesto en desportillados: más claro con árido
    aggr = fbm(S, 160, 2, seed=624)
    col = lerp(col, gradient_map(aggr, [(0, hex2rgb("8d877e")), (1, hex2rgb("c4beb3"))]), chipped * 0.75)
    col = lerp(col, np.array(hex2rgb("3e3a33")), joint * 0.9)
    col = lerp(col, np.array(hex2rgb("3e4b24")), moss_in_joints(S, joint, 630, 0.4) * 0.6)
    col *= (1 - bug * 0.3)[..., None]
    rough = 0.83 + 0.08 * (micro - 0.5) + chipped * 0.08 + bug * 0.1 
    nrm, ao = finish(S, px, h, col, rough, micro=micro, micro_m=0.0006, nk=1.2, ao_r=0.012, ao_d=0.004)
    save("sardinel", col, nrm, rough, ao)


SETS = {
    "anden": anden_concreto,
    "guia": lambda: tactil("guia"),
    "alerta": lambda: tactil("alerta"),
    "hex": adoquin_hex,
    "espina": adoquin_espina,
    "ladrillo": anden_ladrillo,
    "sardinel": sardinel,
}

NAMES = ["anden_concreto", "tactil_guia", "tactil_alerta", "adoquin_hex", "adoquin_espina", "anden_ladrillo",
         "sardinel"]

if __name__ == "__main__":
    os.makedirs(PREV, exist_ok=True)
    which = sys.argv[1:] or list(SETS)
    for k in which:
        SETS[k]()
    pngs = []
    for n in NAMES:
        p = os.path.join(ROOT, OUT, n + "_albedo.png")
        if os.path.exists(p):
            pngs += [f"{PREV}/{n}_prev.png"]
    if pngs:   # hoja propia: previews 2:1 en 2 columnas (contact_sheet usa celdas cuadradas)
        W, H = 768, 384
        cols = 2; rows = (len(pngs) + 1) // 2
        sheet = Image.new("RGB", (W * cols, H * rows), (20, 20, 20))
        for i, pth in enumerate(pngs):
            sheet.paste(Image.open(pth).convert("RGB").resize((W, H)), ((i % cols) * W, (i // cols) * H))
        sheet.save(f"{PREV}/sheet.png")

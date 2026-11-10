"""Familia BRICK — ladrillo de fachada medellinense (Fase 1, agente F1-03).

Regenerar:  python3 tools/texgen/brick.py
Salida:     art/tex/brick/<set>_{albedo,normal,orm}.png   (+ previews en /tmp/f1_brick/)

ESCALA FÍSICA (1 tile = cuadrado de tile_m x tile_m metros; triplanar en mundo):
  fachada_naranja   1024 px = 1.95 m  -> 26 hiladas de 7.5 cm (ladrillo 6.5 cm + junta 1.0 cm),
                    8 ladrillos por hilada (paso 24.4 cm: soga 23.4 cm + junta 1.0 cm), aparejo de soga
                    (trabado a media pieza). ~0.19 cm/px; junta ≈ 5 px.
  fachada_vieja     igual geometría que fachada_naranja (1.95 m), más oscura/rojiza, eflorescencias y
                    chorreaduras verticales de lluvia.
  petaco            512 px = 0.975 m -> 13 ladrillos parados (canto 6.5 cm + junta 1 cm = 7.5 cm) x
                    4 filas de 24.4 cm (sardinel / dintel / remate, aparejo apilado).
  calado            512 px = 0.90 m  -> 12 hiladas de 7.5 cm, 3 ladrillos por hilada (paso 30 cm:
                    ladrillo 22 cm + hueco 8 cm), trabado a medio paso. RGBA: alpha=0 en los huecos.
  losa_entrepiso    512 px = 1.0 m   -> pañete/concreto gris de placa de entrepiso con marcas de formaleta,
                    goterón (ranura horizontal) a 0.88 m del borde superior del tile y chorreaduras debajo.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (ROOT, blur_wrap, contact_sheet, fbm, gradient_map, hex2rgb, height_to_normal,  # noqa: E402
                    lerp, normalize, preview, save_pbr, warp, worley, ao_from_height)

OUT = "art/tex/brick"
PREV = "/tmp/f1_brick"


# ------------------------------------------------------------------ utilidades propias
def aniso_noise(size: int, cx: int, cy: int, seed: int, octaves: int = 4) -> np.ndarray:
    """Ruido de valor periódico anisótropo (cx celdas en x, cy en y) con octavas. [0,1]."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for _ in range(octaves):
        g = rng.random((cy, cx))
        # interpolación cúbica periódica usando zoom sobre grid envuelto
        gy = np.arange(size) * cy / size
        gx = np.arange(size) * cx / size
        iy0 = np.floor(gy).astype(int); fy = gy - iy0
        ix0 = np.floor(gx).astype(int); fx = gx - ix0
        fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
        iy1 = (iy0 + 1) % cy; ix1 = (ix0 + 1) % cx
        iy0 %= cy; ix0 %= cx
        a = g[np.ix_(iy0, ix0)]; b = g[np.ix_(iy0, ix1)]
        c = g[np.ix_(iy1, ix0)]; d = g[np.ix_(iy1, ix1)]
        fyc = fy[:, None]; fxc = fx[None, :]
        out += amp * ((a * (1 - fxc) + b * fxc) * (1 - fyc) + (c * (1 - fxc) + d * fxc) * fyc)
        tot += amp
        amp *= 0.5
        cx = min(cx * 2, size); cy = min(cy * 2, size)
    return normalize(out / tot)


def dots(size: int, count: int, seed: int, radius: float = 1.2) -> np.ndarray:
    """Puntos suaves tileables (poros, moteado). Rápido: splat + blur en wrap. [0,1]."""
    rng = np.random.default_rng(seed)
    g = np.zeros((size, size))
    ys = rng.integers(0, size, count); xs = rng.integers(0, size, count)
    np.add.at(g, (ys, xs), 0.5 + rng.random(count))
    g = blur_wrap(g, radius)
    return np.clip(g / (g.max() * 0.35 + 1e-9), 0, 1)


def smear_down(a: np.ndarray, length: int, decay: float = 0.93, step: int = 2) -> np.ndarray:
    """Arrastra un mapa hacia abajo (lavado de lluvia), tileable."""
    out = a.copy()
    w = 1.0
    for k in range(step, length, step):
        w *= decay
        out = np.maximum(out, np.roll(a, k, axis=0) * w)
    return out


def per_cell_sample(tex: np.ndarray, ids: np.ndarray, seed: int) -> np.ndarray:
    """Muestrea `tex` (tileable) con un desplazamiento aleatorio por pieza: la textura no cruza
    de un ladrillo al vecino y sigue tileando (los ids envuelven)."""
    S = tex.shape[0]
    rng = np.random.default_rng(seed)
    n = int(ids.max()) + 1
    oy = rng.integers(0, S, n); ox = rng.integers(0, S, n)
    yy, xx = np.mgrid[0:S, 0:S]
    return tex[(yy + oy[ids]) % S, (xx + ox[ids]) % S]


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def bond_layout(size: int, rows: int, per_row: int, piece_frac: float, joint_frac: float,
                offset: float = 0.5, seed: int = 0, jitter: float = 0.0):
    """Layout de aparejo. Ejes: x = a lo largo de la hilada, y = a través.
    piece_frac: largo de la pieza / paso horizontal;  joint_frac: junta de lecho / alto de hilada.
    offset: desplazamiento de hiladas alternas (fracción de paso). jitter: irregularidad de colocación (px).
    Devuelve dict con id, u, v (px locales), lu, lv (tamaño pieza en px), mortar(bool), edge dist (px)."""
    rng = np.random.default_rng(seed)
    ch = size / rows
    pw = size / per_row
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    # leve ondulación de hiladas (manufactura artesanal), periódica
    wob = (aniso_noise(size, 8, 2, seed + 11, 2) - 0.5) * jitter
    yw = (yy + wob) % size
    r = np.floor(yw / ch).astype(int) % rows
    xs = (xx + (r % 2) * offset * pw) % size
    c = np.floor(xs / pw).astype(int) % per_row
    ids = r * per_row + c
    # variación del largo de cada pieza y de la junta (±)
    n = rows * per_row
    lenv = 1.0 + (rng.random(n) - 0.5) * 0.03
    hv = 1.0 + (rng.random(n) - 0.5) * 0.04
    u = xs - np.floor(xs / pw) * pw
    v = yw - np.floor(yw / ch) * ch
    lu = pw * piece_frac * lenv[ids]
    lv = ch * (1 - joint_frac) * hv[ids]
    # centrar la pieza en su celda (junta repartida a ambos lados)
    u0 = (pw - lu) * 0.5
    v0 = (ch - lv) * 0.5
    lu_ = u - u0
    lv_ = v - v0
    inside = (lu_ >= 0) & (lu_ < lu) & (lv_ >= 0) & (lv_ < lv)
    ed = np.minimum(np.minimum(lu_, lu - lu_), np.minimum(lv_, lv - lv_))
    return dict(id=ids, row=r, col=c, u=lu_, v=lv_, lu=lu, lv=lv, inside=inside, edge=ed, ch=ch, pw=pw)


# ------------------------------------------------------------------ paletas
BRICK_BASE = [  # naranja-terracota medellinense (fotos 6 y 7)
    hex2rgb("c4673d"), hex2rgb("cf7444"), hex2rgb("b95e38"), hex2rgb("d4804f"),
    hex2rgb("bf6a43"), hex2rgb("c97b52"), hex2rgb("b35633"), hex2rgb("d88a5a"),
]
BRICK_BURNT = [hex2rgb("9a4a2d"), hex2rgb("86412a"), hex2rgb("a45233"), hex2rgb("7c3c28")]
BRICK_OLD = [  # más rojizo y apagado
    hex2rgb("a04a31"), hex2rgb("94432d"), hex2rgb("ad5537"), hex2rgb("8a3f2b"),
    hex2rgb("b25e40"), hex2rgb("9a4a33"), hex2rgb("7d3a29"),
]
MORTAR = hex2rgb("b9b4aa")
MORTAR_DIRTY = hex2rgb("8e8a82")


def brick_pieces(L, size, seed, palette, burnt_palette, burnt_p=0.09, sat_var=0.08):
    """Albedo base por pieza + máscara de piezas quemadas + valor aleatorio por pieza."""
    rng = np.random.default_rng(seed)
    n = int(L["id"].max()) + 1
    pal = np.array(palette); bpal = np.array(burnt_palette)
    base = pal[rng.integers(0, len(pal), n)]
    burnt = rng.random(n) < burnt_p
    base[burnt] = bpal[rng.integers(0, len(bpal), burnt.sum())]
    # ligera variación continua de brillo/saturación
    br = 1.0 + (rng.random(n) - 0.5) * 0.14
    base = base * br[:, None]
    grey = base.mean(1, keepdims=True)
    base = grey + (base - grey) * (1.0 + (rng.random(n)[:, None] - 0.5) * 2 * sat_var)
    rnd = rng.random(n)
    # degradado interno de quemado: un extremo de la pieza más oscuro (flash del horno)
    flash = rng.random(n) < 0.35
    return base[L["id"]], burnt[L["id"]], rnd[L["id"]], flash[L["id"]]


def brick_surface(L, size, seed, palette, burnt_palette, burnt_p=0.09, chip=1.0, scale_px=1.0):
    """Construye albedo/altura/rugosidad del ladrillo + mortero para un layout dado."""
    S = size
    col, burnt, rnd, flash = brick_pieces(L, S, seed, palette, burnt_palette, burnt_p)
    inside = L["inside"]
    ed = L["edge"]

    # ---- texturas de grano reutilizadas (desplazadas por pieza)
    g_fine = fbm(S, base_cells=64, octaves=4, seed=seed + 1)
    g_mid = fbm(S, base_cells=16, octaves=5, seed=seed + 2)
    pits = dots(S, int(2500 * (S / 1024) ** 2) + 100, seed + 3, radius=1.3)  # poros/burbujas
    streak = aniso_noise(S, 48, 6, seed + 4, 3)  # vetas de extrusión a lo largo de la pieza
    micro0 = fbm(S, base_cells=min(S, 256), octaves=2, seed=seed + 19)
    pf = per_cell_sample(g_fine, L["id"], seed + 5)
    pm = per_cell_sample(g_mid, L["id"], seed + 6)
    pp = per_cell_sample(pits, L["id"], seed + 7)
    ps = per_cell_sample(streak, L["id"], seed + 8)

    # ---- bordes gastados: la distancia al borde se perturba con ruido -> despuntes
    chipn = per_cell_sample(fbm(S, base_cells=32, octaves=4, seed=seed + 9), L["id"], seed + 10)
    bevel_w = 1.6 * scale_px
    ed_n = ed - (chipn - 0.45) * 3.2 * chip * scale_px
    face = smoothstep(0.0, bevel_w, ed_n)
    # desportilladuras grandes ocasionales en esquinas
    big = per_cell_sample(fbm(S, base_cells=8, octaves=3, seed=seed + 12), L["id"], seed + 13)
    face *= smoothstep(-0.5, 0.5, ed_n - np.clip((big - 0.72) * 30, 0, 5) * scale_px)
    face *= inside

    # ---- mortero: rehundido, granulado
    m_noise = fbm(S, base_cells=128, octaves=3, seed=seed + 14)
    m_macro = fbm(S, base_cells=8, octaves=4, seed=seed + 15)

    # altura: mortero 0.0-0.12, ladrillo 0.55-0.75
    h_brick = 0.62 + (pm - 0.5) * 0.06 + (pf - 0.5) * 0.03 - pp * 0.05 + (micro0 - 0.5) * 0.012 + (ps - 0.5) * 0.015
    h_mortar = 0.06 + (m_noise - 0.5) * 0.06 + (m_macro - 0.5) * 0.04
    height = h_mortar * (1 - face) + h_brick * face

    # ---- albedo ladrillo
    a = col.copy()
    tone = 1.0 + (pm - 0.5) * 0.16 + (pf - 0.5) * 0.10 - pp * 0.12
    a = a * tone[..., None]
    # vetas finas más claras/oscuras
    a = a * (1.0 + (ps - 0.5) * 0.08)[..., None]
    # flash de horno: un extremo de la pieza más oscuro
    t_along = np.clip(L["u"] / np.maximum(L["lu"], 1), 0, 1)
    side = np.where(rnd > 0.5, t_along, 1 - t_along)
    a = a * (1 - (flash * smoothstep(0.55, 1.0, side) * 0.22))[..., None]
    # moteado de manganeso (puntitos oscuros)
    spk = per_cell_sample(dots(S, int(4000 * (S / 1024) ** 2) + 100, seed + 16, radius=0.9), L["id"], seed + 17)
    a = a * (1 - spk * 0.22)[..., None]
    # micro grano de arena en la arcilla
    micro = fbm(S, base_cells=min(S, 512), octaves=1, seed=seed + 18)
    a = a * (1.0 + (micro - 0.5) * 0.12)[..., None]
    # canto despuntado = arcilla interior más clara y polvorienta
    wear = np.clip(1 - face, 0, 1) * inside
    a = lerp(a, a * 1.06 + 0.02, wear * 0.35)

    # ---- albedo mortero
    mcol = lerp(np.array(MORTAR), np.array(MORTAR_DIRTY), np.clip(m_macro * 0.8 + (1 - m_noise) * 0.4 - 0.3, 0, 1))
    mcol = mcol * (0.92 + m_noise[..., None] * 0.14)
    albedo = mcol * (1 - face[..., None]) + a * face[..., None]

    # ---- rugosidad
    rough = 0.78 + (pf - 0.5) * 0.10 + pp * 0.08 - (1 - burnt) * 0.0 - burnt * 0.06
    rough = rough * face + (0.93 + (m_noise - 0.5) * 0.06) * (1 - face)
    return dict(albedo=albedo, height=height, rough=rough, face=face, burnt=burnt)


def joint_dirt(face, S, seed, amount=0.35, radius=3.0):
    """Suciedad/oscurecimiento en juntas y bordes de piezas (AO pintado + mugre)."""
    j = 1 - face
    jb = blur_wrap(j, radius)
    n = fbm(S, base_cells=16, octaves=4, seed=seed)
    return np.clip(jb * (0.6 + n * 0.8), 0, 1) * amount


def macro_stains(S, seed, strength=0.10):
    """Variación macro de tono (manchas grandes, sol/lluvia desigual)."""
    m = fbm(S, base_cells=3, octaves=5, seed=seed)
    return 1.0 + (m - 0.5) * strength * 2


def rain_streaks(S, seed, density=0.5, length_cells=3):
    """Chorreaduras verticales tileables (oscuras = humedad/hollín). [0,1]."""
    cols = aniso_noise(S, 96, length_cells, seed, 3)
    cols2 = aniso_noise(S, 40, 2, seed + 1, 2)
    st = smoothstep(1 - density * 0.6, 1.0, cols * 0.65 + cols2 * 0.35)
    # moduladas de forma suave en vertical (comienzan bajo "balcones" y se desvanecen)
    fade = aniso_noise(S, 6, 2, seed + 2, 2)
    st = st * smoothstep(0.25, 0.75, fade)
    return blur_wrap(st, 1.0)


def finish(rel, albedo, height, rough, face, S, nstrength, ao_extra=None, metal=0.0):
    ao = ao_from_height(height, radius=4.0 * S / 1024 + 1.5, strength=1.0)
    ao2 = ao_from_height(height, radius=14.0 * S / 1024 + 2, strength=0.6)
    ao = np.clip(ao * (0.6 + 0.4 * ao2), 0, 1)
    ao = 0.5 + 0.5 * ao
    if ao_extra is not None:
        ao = ao * ao_extra
    return save_pbr(rel, np.clip(albedo, 0, 1), height=height, rough=np.clip(rough, 0.05, 1), ao=np.clip(ao, 0, 1),
                    metal=metal, normal_strength=nstrength)


# ------------------------------------------------------------------ sets
def set_fachada(name, seed, old=False):
    S = 1024
    L = bond_layout(S, rows=26, per_row=8, piece_frac=23.4 / 24.4, joint_frac=1.0 / 7.5,
                    offset=0.5, seed=seed, jitter=1.2)
    pal = BRICK_OLD if old else BRICK_BASE
    B = brick_surface(L, S, seed, pal, BRICK_BURNT, burnt_p=0.14 if old else 0.08, chip=1.6 if old else 1.0)
    albedo, height, rough, face = B["albedo"], B["height"], B["rough"], B["face"]

    dirt = joint_dirt(face, S, seed + 30, amount=0.45 if old else 0.30, radius=2.5)
    albedo = albedo * (1 - dirt[..., None] * 0.55)
    albedo = albedo * macro_stains(S, seed + 31, 0.07 if not old else 0.10)[..., None]

    st = rain_streaks(S, seed + 32, density=0.75 if old else 0.35, length_cells=3)
    albedo = albedo * (1 - st[..., None] * (0.38 if old else 0.18))
    rough = rough - st * 0.10

    if old:
        # tono general más rojizo/oscuro y algo desaturado
        g = albedo.mean(-1, keepdims=True)
        albedo = (g + (albedo - g) * 0.85) * 0.92
        # eflorescencias: sales blancas que nacen en las juntas y bajan por la pieza
        jn = blur_wrap(1 - face, 3.0)
        drip = blur_wrap(np.roll(1 - face, 3, axis=0), 2.0)  # salen por debajo de la junta de lecho
        patch = smoothstep(0.55, 0.85, fbm(S, base_cells=6, octaves=5, seed=seed + 33))
        vert = aniso_noise(S, 64, 4, seed + 34, 3)
        eff = np.clip((jn * 0.9 + drip * 0.6) * patch * (0.6 + vert * 0.8), 0, 1)
        eff = smoothstep(0.08, 0.6, eff)
        # las sales se lavan hacia abajo formando lagrimeo
        tear = aniso_noise(S, 160, 3, seed + 38, 2)
        eff = np.maximum(eff, smear_down(eff, 70, 0.95, 2) * smoothstep(0.5, 0.8, tear) * 0.8)
        # velo blanquecino irregular
        veil = smoothstep(0.62, 0.95, fbm(S, base_cells=4, octaves=6, seed=seed + 35)) * 0.35
        eff = np.clip(eff + veil * patch, 0, 1)
        salt = np.array(hex2rgb("e6e2d8"))
        fine = fbm(S, base_cells=128, octaves=2, seed=seed + 36)
        eff = eff * (0.65 + 0.35 * fine)
        albedo = lerp(albedo, salt, eff * 0.75)
        rough = rough * (1 - eff) + 0.95 * eff
        height = height + eff * 0.01
        # verdín/moho leve en la parte baja de las juntas
        moss = smoothstep(0.7, 0.9, fbm(S, base_cells=5, octaves=5, seed=seed + 37)) * (1 - face)
        albedo = lerp(albedo, np.array(hex2rgb("4d5a3a")), moss * 0.45)

    return finish(f"{OUT}/{name}", albedo, height, rough, face, S, nstrength=5.0)


def set_petaco(seed=301):
    """Ladrillo parado (sardinel) — se genera como soga apilada y se transpone."""
    S = 512
    # x' (a lo largo de la fila) = vertical en la imagen final.  13 piezas de canto por tile en horizontal.
    L = bond_layout(S, rows=13, per_row=4, piece_frac=23.4 / 24.4, joint_frac=1.0 / 7.5,
                    offset=0.0, seed=seed, jitter=0.8)
    B = brick_surface(L, S, seed, BRICK_BASE, BRICK_BURNT, burnt_p=0.12, chip=1.2, scale_px=1.0)
    albedo, height, rough, face = B["albedo"], B["height"], B["rough"], B["face"]
    dirt = joint_dirt(face, S, seed + 30, amount=0.35, radius=2.0)
    albedo = albedo * (1 - dirt[..., None] * 0.55)
    albedo = albedo * macro_stains(S, seed + 31, 0.08)[..., None]
    # transponer: filas -> columnas (ladrillos de pie)
    T = lambda a: np.swapaxes(a, 0, 1).copy()
    albedo, height, rough, face = T(albedo), T(height), T(rough), T(face)
    # chorreaduras verticales (después de transponer, para que vayan hacia abajo)
    st = rain_streaks(S, seed + 32, density=0.45, length_cells=2)
    albedo = albedo * (1 - st[..., None] * 0.18)
    return finish(f"{OUT}/petaco", albedo, height, rough, face, S, nstrength=4.0)


def set_calado(seed=401):
    """Celosía de ladrillo: hiladas de soga con huecos, trabadas a medio paso. RGBA."""
    S = 512
    rows, per_row = 12, 3
    L = bond_layout(S, rows=rows, per_row=per_row, piece_frac=22.0 / 30.0, joint_frac=1.0 / 7.5,
                    offset=0.5, seed=seed, jitter=0.5)
    B = brick_surface(L, S, seed, BRICK_BASE, BRICK_BURNT, burnt_p=0.10, chip=1.0)
    albedo, height, rough, face = B["albedo"], B["height"], B["rough"], B["face"]

    # mortero solo donde la pieza de arriba y la de abajo se solapan
    ch, pw = L["ch"], L["pw"]
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    brick_len = pw * 22.0 / 30.0
    hole_w = pw - brick_len

    def in_brick_x(x, r):
        xs = (x + (r % 2) * 0.5 * pw) % S
        u = xs - np.floor(xs / pw) * pw
        return (u >= hole_w * 0.5) & (u < hole_w * 0.5 + brick_len)

    r = np.floor(yy / ch).astype(int) % rows
    v = yy - np.floor(yy / ch) * ch
    in_row = in_brick_x(xx, r)
    # junta de lecho: mitad superior pertenece al límite con hilada r-1, inferior con r+1
    upper = v < ch * 0.5
    r_nb = np.where(upper, (r - 1) % rows, (r + 1) % rows)
    in_nb = in_brick_x(xx, r_nb)
    # en zona de junta, solo es sólido si hay pieza propia Y pieza vecina (mortero de lecho bajo solape)
    bed = ~L["inside"] & in_row & in_nb
    solid = (L["inside"] | bed)
    # bordes del hueco irregulares (mortero rebabado)
    rough_edge = fbm(S, base_cells=64, octaves=3, seed=seed + 50)
    sd = ndimage.distance_transform_edt(np.tile(solid, (3, 3)))[S:2 * S, S:2 * S]
    hd = ndimage.distance_transform_edt(np.tile(~solid, (3, 3)))[S:2 * S, S:2 * S]
    signed = sd - hd  # >0 sólido
    alpha = (signed + (rough_edge - 0.5) * 1.6 > 0.0).astype(np.float64)

    # oscurecer/ensuciar el canto que da al hueco (polvo y sombra de profundidad)
    edge_dark = smoothstep(6.0, 0.0, sd) * (alpha > 0)
    albedo = albedo * (1 - edge_dark[..., None] * 0.25)
    dirt = joint_dirt(face, S, seed + 30, amount=0.30, radius=2.0)
    albedo = albedo * (1 - dirt[..., None] * 0.5)
    albedo = albedo * macro_stains(S, seed + 31, 0.08)[..., None]
    st = rain_streaks(S, seed + 32, density=0.4, length_cells=2)
    albedo = albedo * (1 - st[..., None] * 0.15)
    height = height * alpha  # bajar a 0 en huecos para que el normal marque el canto
    ao_extra = 1 - edge_dark * 0.35
    out = finish(f"{OUT}/calado", albedo, height, rough, face, S, nstrength=4.0, ao_extra=ao_extra)
    # reescribir albedo como RGBA; los huecos rellenos con color promedio del borde (evita halos en mips)
    rgb = np.clip(albedo, 0, 1)
    fill = blur_wrap(rgb * alpha[..., None], 6) / (blur_wrap(alpha, 6)[..., None] + 1e-4)
    rgb = np.where(alpha[..., None] > 0, rgb, np.clip(fill, 0, 1))
    rgba = np.dstack([rgb, alpha])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(
        os.path.join(ROOT, OUT, "calado_albedo.png"), optimize=True)
    return out


def set_losa(seed=501):
    """Franja de placa de concreto de entrepiso: pañete gris, marcas de formaleta, goterón, chorreaduras."""
    S = 512  # 1.0 m
    px = S / 1.0  # px por metro
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    base = fbm(S, base_cells=4, octaves=6, seed=seed)
    fine = fbm(S, base_cells=96, octaves=3, seed=seed + 1)
    pores = dots(S, 500, seed + 2, radius=0.9)
    # marcas de formaleta (tablas horizontales de ~10 cm, juntas finas)
    board_h = 0.10 * px
    by = (yy + (aniso_noise(S, 4, 1, seed + 3, 2) - 0.5) * 2) % board_h
    seam = smoothstep(1.4, 0.0, np.minimum(by, board_h - by))
    seam *= smoothstep(0.35, 0.6, aniso_noise(S, 6, 10, seed + 4, 2))  # interrumpidas
    board_id = np.floor(yy / board_h).astype(int)
    rng = np.random.default_rng(seed + 5)
    btone = (rng.random(int(S / board_h) + 2) - 0.5) * 0.06
    # veta de madera transferida al concreto
    grain = aniso_noise(S, 4, 80, seed + 6, 3)
    grain = np.swapaxes(grain, 0, 1)  # vetas horizontales

    # goterón: ranura horizontal a 0.88 m (en px desde arriba)
    gy = 0.88 * px
    dgy = np.abs(yy - gy)
    groove = smoothstep(5.0, 2.0, dgy)

    height = 0.5 + (base - 0.5) * 0.10 + (fine - 0.5) * 0.06 - pores * 0.10 - seam * 0.05 + (grain - 0.5) * 0.02
    height = height - groove * 0.35

    gray = gradient_map(base * 0.7 + fine * 0.3, [(0.0, hex2rgb("7f7d78")), (0.5, hex2rgb("a3a19b")),
                                                   (1.0, hex2rgb("bbb8b1"))])
    gray = gray * (1 + btone[board_id % len(btone)])[..., None]
    gray = gray * (1 - pores[..., None] * 0.15) * (1 - seam[..., None] * 0.15)
    gray = gray * (1 + (grain - 0.5) * 0.05)[..., None]

    # chorreaduras: desde el goterón hacia abajo (envuelve al inicio del tile) y suciedad sobre la arista
    dist_below = (yy - gy) % S  # 0 justo bajo el goterón
    streak_cols = aniso_noise(S, 72, 1, seed + 7, 3)
    streak = smoothstep(0.45, 0.85, streak_cols) * np.exp(-dist_below / (0.45 * px))
    streak += smoothstep(0.7, 0.95, aniso_noise(S, 40, 3, seed + 8, 3)) * 0.35
    streak = np.clip(blur_wrap(streak, 1.0), 0, 1)
    # mugre acumulada justo encima del goterón (agua retenida)
    above = np.exp(-np.clip(gy - yy, 0, None) / 6.0) * (yy <= gy)
    grime = np.clip(streak * 0.8 + above * 0.4 + groove * 0.5, 0, 1)
    dirt_col = np.array(hex2rgb("4a4842"))
    albedo = lerp(gray, dirt_col, grime * 0.6)
    # sales/eflorescencia leve
    eff = smoothstep(0.78, 0.95, fbm(S, base_cells=5, octaves=5, seed=seed + 9))
    albedo = lerp(albedo, np.array(hex2rgb("d7d5cf")), eff * 0.3)

    rough = 0.88 + (fine - 0.5) * 0.08 + pores * 0.05 - streak * 0.12
    ao_extra = 1 - groove * 0.5
    return finish(f"{OUT}/losa_entrepiso", albedo, height, rough, np.ones((S, S)), S, nstrength=3.0,
                  ao_extra=ao_extra)


def main():
    os.makedirs(PREV, exist_ok=True)
    sets = {
        "fachada_naranja": lambda: set_fachada("fachada_naranja", 101, old=False),
        "fachada_vieja": lambda: set_fachada("fachada_vieja", 201, old=True),
        "petaco": set_petaco,
        "calado": set_calado,
        "losa_entrepiso": set_losa,
    }
    only = sys.argv[1:]
    pngs = []
    for name, fn in sets.items():
        if only and name not in only:
            continue
        fn()
        p = f"{PREV}/{name}.png"
        preview(f"{OUT}/{name}", p)
        pngs.append(p)
        print("ok", name)
    if not only:
        contact_sheet(pngs, f"{PREV}/sheet.png", cell=512)


if __name__ == "__main__":
    main()

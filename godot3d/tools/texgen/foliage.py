"""Familia FOLIAGE — atlases de follaje RGBA (tarjetas / quads cruzados) + tiles de hiedra y seto.

Regenerar:  python3 tools/texgen/foliage.py   (determinista, semillas fijas)

Salida en art/tex/foliage/:
  canopy_atlas_*    1024x1024 RGBA, atlas 2x2 de ramilletes para copa de árbol grande
                    (A samán denso, B samán colgante ralo, C samán al sol amarillento, D hoja ovalada oscura).
                    Cada celda = 512 px ~ 1.2 m de ramillete. Pensado para quads de 1-1.5 m.
  palm_frond_*      512x1024 RGBA (ancho x alto), fronda plumosa completa vista superior; la base del
                    raquis está ABAJO al centro (v=1), la punta arriba (v=0). Quad ~1.2 m x 2.4 m.
  garden_atlas_*    1024x1024 RGBA, atlas 2x2 de plantas vistas de lado, base abajo al centro de cada celda:
                    arriba-izq crotón moteado, arriba-der helecho, abajo-izq heliconia / hoja ancha,
                    abajo-der planta de hoja morada. Celda 512 px ~ 1 m de planta.
  ivy_ground_*      512 RGB tileable, hiedra/cobertura vista superior. 1 tile = 1 m.
  hedge_*           512 RGB tileable, seto denso recortado (cajas de seto). 1 tile = 1 m.
Mapas: _albedo (RGBA en atlases), _normal (OpenGL Y+), _orm (R=AO, G=rugosidad, B=metal).

Motor: "estampado" de hojas analíticas (perfil de ancho, vena central, venas laterales, pliegue en V,
curvatura) compuestas de atrás hacia delante; cada hoja proyecta una sombra suave (AO) sobre las de
abajo. El color se extiende (dilata) bajo el alpha para que los mipmaps no hagan halos oscuros.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from common import ROOT, fbm, blur_wrap, worley, hex2rgb, lerp, contact_sheet  # noqa: E402

OUT = "art/tex/foliage"
_NZ = None


def noise_tex():
    """Ruido global 512 (micro variación de color dentro de cada hoja) y mapa de motas (crotón)."""
    global _NZ
    if _NZ is None:
        n = fbm(512, 16, 5, seed=901)
        d, ids = worley(512, 900, seed=902)
        r = np.random.default_rng(903).random(900)
        spots = np.clip((0.05 + 0.09 * r[ids] - d) * 30, 0, 1) * (r[ids] > 0.2)
        _NZ = (n, spots)
    return _NZ


def sample(tex, xx, yy):
    return tex[yy.astype(int) % tex.shape[0], xx.astype(int) % tex.shape[1]]
PREV = "/tmp/f1_foliage"


def srgb(h):
    return np.array(hex2rgb(h))


# ===================================================================== lienzo
class Canvas:
    def __init__(self, h, w, wrap=False, bg=None):
        self.h, self.w, self.wrap = h, w, wrap
        self.col = np.zeros((h, w, 3)) if bg is None else bg.copy()
        self.a = np.zeros((h, w)) if bg is None else np.ones((h, w))
        self.n = np.zeros((h, w, 3)); self.n[..., 2] = 1
        self.rough = np.ones((h, w)) * 0.9
        self.ao = np.ones((h, w))

    def idx(self, y0, x0, ph, pw):
        ys = np.arange(y0, y0 + ph); xs = np.arange(x0, x0 + pw)
        if self.wrap:
            return np.ix_(ys % self.h, xs % self.w), None
        vy = (ys >= 0) & (ys < self.h); vx = (xs >= 0) & (xs < self.w)
        if not vy.any() or not vx.any():
            return None, None
        return np.ix_(ys[vy], xs[vx]), (vy, vx)


# perfiles de ancho (t 0..1 a lo largo, devuelve 0..1)
def prof_ellipse(t):
    return np.sqrt(np.clip(t * (1 - t) * 4, 0, 1)) * (1 - 0.15 * t)

def prof_oval(t):  # base redondeada, punta aguda
    return np.clip(np.sin(np.pi * np.clip(t, 0, 1) ** 0.8), 0, 1) ** 0.85

def prof_lance(t):  # lanceolada
    return np.clip(np.sin(np.pi * np.clip(t, 0, 1) ** 0.55), 0, 1) ** 1.1

def prof_strap(t):  # foliolo de palma: largo y casi paralelo
    return np.clip(np.minimum(t / 0.06, 1) * np.minimum((1 - t) / 0.35, 1), 0, 1) ** 0.8

def prof_leaflet(t):  # foliolo de samán: oblongo asimétrico
    return np.clip(np.sin(np.pi * np.clip(t, 0, 1) ** 0.75), 0, 1) ** 0.6

def prof_ivy(t):  # hiedra: lóbulos laterales anchos, base con escotadura
    t = np.clip(t, 0, 1)
    body = np.sin(np.pi * t ** 0.7) ** 0.5
    lobe = 0.35 * np.exp(-((t - 0.28) / 0.1) ** 2) - 0.25 * np.exp(-((t - 0.55) / 0.07) ** 2)
    return np.clip(body + lobe, 0, 1.2) * np.clip(t / 0.08, 0, 1)

def prof_stem(t):
    return np.ones_like(t)


def stamp(cv: Canvas, x, y, ang, L, W, prof, color, rng, *, bend=0.0, fold=0.35, dome=0.5,
          rib=1.0, veins=8, vein_slant=1.2, vein_amt=0.25, rough=0.55, tilt=(0.0, 0.0),
          shadow=0.55, shadow_off=(4.0, 6.0), base_ao=0.25, mottle=None, tear=0, edge_light=0.12,
          rib_col=None, back=False, nstr=1.0, backside=False):
    """Estampa una hoja con base en (x,y), dirección `ang` (rad, 0 = +x, imagen y hacia abajo)."""
    R = int(L + W + abs(bend) * L + max(abs(shadow_off[0]), abs(shadow_off[1])) + 6)
    x0, y0 = int(x) - R, int(y) - R
    ph = pw = 2 * R
    sel, valid = cv.idx(y0, x0, ph, pw)
    if sel is None:
        return
    yy, xx = np.mgrid[y0:y0 + ph, x0:x0 + pw].astype(np.float64)
    ca, sa = np.cos(ang), np.sin(ang)

    def frame(ox=0.0, oy=0.0):
        dx = xx - x - ox; dy = yy - y - oy
        u = dx * ca + dy * sa
        v = -dx * sa + dy * ca
        t = u / L
        tc = np.clip(t, 0, 1)
        v = v - bend * L * tc * tc
        hw = 0.5 * W * prof(tc)
        inside = (t >= 0) & (t <= 1)
        d = np.where(inside, hw - np.abs(v), -5.0)
        # extremos: distancia a lo largo
        d = np.minimum(d, np.minimum(u, L - u) * 1.0 + 0.5 * W * 0)
        alpha = np.clip(d + 0.5, 0, 1)
        return t, tc, v, hw, alpha

    t, tc, v, hw, alpha = frame()
    if tear:
        # rasgaduras tipo heliconia/plátano: cortes finos perpendiculares a la vena
        for _ in range(tear):
            tp = rng.uniform(0.15, 0.9); side = rng.choice([-1, 1]); depth = rng.uniform(0.4, 0.95)
            cut = (np.abs(t - tp - 0.04 * np.abs(v) / (W * 0.5)) < 0.6 / L * 1.6) & (side * v > (1 - depth) * hw)
            alpha = np.where(cut, 0.0, alpha)
    if alpha.max() <= 0:
        return
    s = np.clip(v / np.maximum(hw, 1e-3), -1, 1)
    # altura local (px): domo + pliegue en V + vena central + venas laterales
    h = dome * np.sqrt(np.clip(1 - s * s, 0, 1)) * hw * 0.5
    h += fold * (1 - np.abs(s)) * hw * 0.5 * (1 if fold >= 0 else -1)
    ribm = np.exp(-(v / max(0.9, W * 0.025)) ** 2) * (tc < 0.97)
    h -= 0.6 * rib * ribm
    vp = 0.5 + 0.5 * np.cos(2 * np.pi * (tc * veins - np.abs(s) * vein_slant))
    vm = vp ** 10 * (np.abs(s) > 0.08) * (1 - np.abs(s)) ** 0.5
    h -= vein_amt * vm * 1.5
    gy, gx = np.gradient(h)
    nx = -gx * nstr + tilt[0] + 0.15 * s * 0
    ny = gy * nstr + tilt[1]
    nz = np.ones_like(h)
    nrm = np.stack([nx, ny, nz], -1); nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)

    # color
    c = color(tc, s, x, y, xx, yy, rng) if callable(color) else np.broadcast_to(np.asarray(color, float), h.shape + (3,)).copy()
    nz = sample(noise_tex()[0], xx * 1.7 + x * 3, yy * 1.7 + y * 3)
    c = c * (0.9 + 0.2 * nz)[..., None]
    if backside:  # envés: más claro y desaturado
        lum = c.mean(-1, keepdims=True)
        c = lerp(c, lum * np.array([0.95, 1.1, 0.85]) * 1.45, 0.45)
    if mottle is not None:
        c = mottle(c, tc, s, xx, yy)
    rc = rib_col if rib_col is not None else np.clip(c * 1.35 + 0.04, 0, 1)
    c = lerp(c, rc, np.clip(ribm * rib * 0.9, 0, 1))
    c = lerp(c, np.clip(c * 1.18 + 0.02, 0, 1), vm * vein_amt * 1.6)
    c = c * (1 + edge_light * np.abs(s) ** 4)[..., None]
    lit = np.clip(0.5 + 0.5 * (nrm[..., 0] * -0.4 + nrm[..., 1] * 0.6), 0, 1)  # ligera iluminación horneada
    c = c * (0.9 + 0.2 * lit)[..., None]
    ao_leaf = 1 - base_ao * (1 - tc) ** 3

    # sombra de esta hoja sobre lo existente
    if shadow > 0:
        _, _, _, _, sa_ = frame(shadow_off[0], shadow_off[1])
        sh = ndimage.gaussian_filter(sa_, max(1.0, 0.35 * (abs(shadow_off[0]) + abs(shadow_off[1]))))
    if valid is not None:
        vy, vx = valid
        cut = np.ix_(vy, vx)
        alpha = alpha[cut]; c = c[cut]; nrm = nrm[cut]; ao_leaf = ao_leaf[cut]
        if shadow > 0:
            sh = sh[cut]
    a_old = cv.a[sel]
    if shadow > 0:
        cv.ao[sel] = cv.ao[sel] * (1 - shadow * sh * a_old)
    A = alpha[..., None]
    cv.col[sel] = cv.col[sel] * (1 - A) + c * A
    cv.n[sel] = cv.n[sel] * (1 - A) + nrm * A
    cv.ao[sel] = cv.ao[sel] * (1 - alpha) + ao_leaf * alpha
    r = rough if np.isscalar(rough) else rough
    cv.rough[sel] = cv.rough[sel] * (1 - alpha) + r * alpha
    cv.a[sel] = np.maximum(a_old, alpha) if not back else cv.a[sel]


def stem(cv, pts, w0, w1, col, rng, rough=0.8, shadow=0.4):
    """Tallo/raquis como cadena de segmentos (pts lista de (x,y))."""
    n = len(pts) - 1
    for i in range(n):
        (xa, ya), (xb, yb) = pts[i], pts[i + 1]
        L = max(1.0, np.hypot(xb - xa, yb - ya))
        w = w0 + (w1 - w0) * i / max(1, n)
        stamp(cv, xa, ya, np.arctan2(yb - ya, xb - xa), L + w * 0.6, w, prof_stem, col, rng,
              fold=0.0, dome=0.9, rib=0, veins=0, vein_amt=0, rough=rough, shadow=shadow if i == 0 else shadow * 0.25,
              shadow_off=(2, 3), base_ao=0.0, edge_light=0.0)


def curve(x0, y0, ang, length, curl, n=24, droop=0.0):
    """Polilínea curva desde (x0,y0): curl = cambio total de ángulo, droop = gravedad (+y)."""
    pts = [(x0, y0)]; a = ang; seg = length / n
    for i in range(n):
        a += curl / n
        dx, dy = np.cos(a), np.sin(a) + droop * (i / n)
        k = np.hypot(dx, dy)
        pts.append((pts[-1][0] + seg * dx / k, pts[-1][1] + seg * dy / k))
    return pts


# ===================================================================== finalización
def dilate_color(col, a, iters=6):
    """Extiende color hacia zonas transparentes (evita halos en mipmaps)."""
    c = col * a[..., None]; w = a.copy()
    out = col.copy()
    for k in range(iters):
        s = 2 ** k
        cb = np.stack([ndimage.gaussian_filter(c[..., i], s) for i in range(3)], -1)
        wb = ndimage.gaussian_filter(w, s)
        fill = cb / np.maximum(wb[..., None], 1e-6)
        m = (wb > 1e-4) & (a < 0.5)
        out[m & (out.sum(-1) == 0)] = fill[m & (out.sum(-1) == 0)]
    mask = a < 0.5
    out[mask & (out.sum(-1) == 0)] = col[a > 0.5].mean(0) if (a > 0.5).any() else 0
    # todo lo transparente toma el color difuso
    cb = np.stack([ndimage.gaussian_filter(c[..., i], 6) for i in range(3)], -1)
    wb = ndimage.gaussian_filter(w, 6)
    fill = cb / np.maximum(wb[..., None], 1e-6)
    far = ndimage.gaussian_filter(c, (40, 40, 0)) / np.maximum(ndimage.gaussian_filter(w, 40)[..., None], 1e-6)
    fill = np.where((wb > 0.02)[..., None], fill, far)
    return np.where(mask[..., None], fill, col)


def save_set(name, cv: Canvas, rgba=True, extra_ao=None):
    base = os.path.join(ROOT, OUT, name)
    os.makedirs(os.path.dirname(base), exist_ok=True)
    a = np.clip(cv.a, 0, 1)
    col = np.clip(cv.col, 0, 1)
    if rgba:
        col = dilate_color(col, a)
    n = cv.n / np.linalg.norm(cv.n, axis=-1, keepdims=True)
    ao = np.clip(cv.ao, 0, 1)
    if extra_ao is not None:
        ao = ao * extra_ao
    rough = np.clip(cv.rough, 0, 1)
    if rgba:
        flat = a < 0.02
        n[flat] = (0, 0, 1); ao = np.where(flat, 1.0, ao); rough = np.where(flat, 1.0, rough)
    # el AO también oscurece levemente el albedo (sombras internas visibles sin luz directa)
    col = col * (0.55 + 0.45 * ao)[..., None]
    u8 = lambda z: (np.clip(z, 0, 1) * 255 + 0.5).astype(np.uint8)
    if rgba:
        Image.fromarray(np.dstack([u8(col), u8(a)]), "RGBA").save(base + "_albedo.png", optimize=True)
    else:
        Image.fromarray(u8(col), "RGB").save(base + "_albedo.png", optimize=True)
    Image.fromarray(u8(n * 0.5 + 0.5), "RGB").save(base + "_normal.png", optimize=True)
    Image.fromarray(u8(np.stack([ao, rough, np.zeros_like(ao)], -1)), "RGB").save(base + "_orm.png", optimize=True)
    return base


# ===================================================================== colores
def leaf_color(base, tip, var=0.08, back=None):
    base = np.asarray(base); tip = np.asarray(tip)

    def f(tc, s, x, y, xx, yy, rng):
        j = rng.normal(0, var, 3) * np.array([0.25, 0.35, 0.2]) + rng.normal(0, var)
        b = np.clip(base * (1 + j), 0, 1)
        tt = np.clip(tip * (1 + j), 0, 1)
        return lerp(b, tt, tc ** 1.5)
    return f


# ===================================================================== 1) copa de árbol (atlas 2x2)
def blob_mask_fn(rng, cx, cy, rx, ry):
    k = rng.uniform(0, 2 * np.pi, 5); amp = rng.uniform(0.05, 0.16, 5)

    def inside(px, py):
        ang = np.arctan2(py - cy, px - cx)
        r = 1 + sum(amp[i] * np.sin((i + 2) * ang + k[i]) for i in range(5))
        return ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 < r * r
    return inside


def saman_pinna(cv, x, y, ang, length, rng, depth, sunny, droop):
    """Pinna de samán / leguminosa: raquis fino con foliolos pequeños casi perpendiculares."""
    pts = curve(x, y, ang, length, rng.uniform(-0.5, 0.5), n=8, droop=droop)
    dark = 0.5 + 0.5 * depth
    g0 = lerp(srgb("#3b6420"), srgb("#86a43c"), sunny) * dark
    g1 = lerp(srgb("#5d8a2c"), srgb("#b9c95a"), sunny) * dark
    stem(cv, pts, 1.4, 1.0, srgb("#56552f") * dark, rng, shadow=0.15)
    lf = rng.uniform(7.5, 10.0)
    n = len(pts)
    for i in range(n - 1):
        (xa, ya), (xb, yb) = pts[i], pts[i + 1]
        ta = np.arctan2(yb - ya, xb - xa)
        seg = np.hypot(xb - xa, yb - ya)
        k_n = max(1, int(seg / 4.2))
        for k in range(k_n):
            fx = xa + (xb - xa) * k / k_n; fy = ya + (yb - ya) * k / k_n
            sz = lf * (1.0 - 0.3 * (i / n)) * rng.uniform(0.85, 1.1)
            for side in (-1, 1):
                if rng.random() < 0.06:
                    continue  # foliolos caídos: huecos de luz
                stamp(cv, fx, fy, ta + side * rng.uniform(1.15, 1.45), sz, sz * 0.5, prof_leaflet,
                      leaf_color(g0, g1, 0.05), rng, bend=side * 0.08, fold=0.2, dome=0.4, rib=0.4,
                      veins=0, vein_amt=0, rough=0.55 + rng.uniform(-0.05, 0.1), shadow=0.4,
                      shadow_off=(1.5, 2.5), base_ao=0.15, edge_light=0.0, backside=rng.random() < 0.07,
                      tilt=(rng.normal(0, 0.25), rng.normal(0.1, 0.25)))
    (xa, ya), (xb, yb) = pts[-2], pts[-1]
    stamp(cv, xb, yb, np.arctan2(yb - ya, xb - xa), lf * 0.7, lf * 0.35, prof_leaflet,
          leaf_color(g0, g1, 0.05), rng, fold=0.2, veins=0, vein_amt=0, shadow=0.3, shadow_off=(1.5, 2.5))


def canopy_cell(S, variant, seed):
    rng = np.random.default_rng(seed)
    cv = Canvas(S, S)
    cx, cy = S * 0.5, S * 0.47
    rx, ry = S * 0.34, S * 0.32
    inside = blob_mask_fn(rng, cx, cy, rx, ry)
    # ramas leñosas internas (salen por abajo: el atlas puede pegarse a una rama)
    for _ in range(4):
        a = -np.pi / 2 + rng.uniform(-1.0, 1.0)
        pts = curve(cx + rng.uniform(-25, 25), S * 0.93, a, S * rng.uniform(0.35, 0.5), rng.uniform(-0.8, 0.8), n=12)
        pts = [p for p in pts if inside(*p) or p[1] > cy]
        if len(pts) > 2:
            stem(cv, pts, 8, 3, srgb("#3d3428"), rng, shadow=0.3)

    def pick():
        for _ in range(60):
            px, py = rng.uniform(0, S, 2)
            if inside(px, py):
                return px, py
        return cx, cy

    if variant == "D":
        # árbol de hoja ovalada oscura (tipo ref. 6): hojas medianas en ramitas
        n_tw = 110
        for i in range(n_tw):
            depth = i / n_tw
            px, py = pick()
            ang = np.arctan2(py - cy, px - cx) + rng.normal(0, 0.6)
            pts = curve(px, py, ang, rng.uniform(35, 60), rng.uniform(-0.7, 0.7), n=5, droop=0.3)
            pts = [p for p in pts if inside(*p)]
            if len(pts) < 2:
                continue
            dark = 0.5 + 0.5 * depth
            stem(cv, pts, 2.0, 1.0, srgb("#3a3326") * dark, rng, shadow=0.2)
            for j, (qx, qy) in enumerate(pts[1:]):
                for _k in range(2):
                    a = ang + rng.normal(0, 0.9)
                    L = rng.uniform(24, 34)
                    stamp(cv, qx, qy, a, L, L * 0.5, prof_oval,
                          leaf_color(srgb("#24401c") * dark, srgb("#3d6526") * dark, 0.06), rng,
                          bend=rng.normal(0, 0.12), fold=0.35, veins=6, vein_amt=0.2, rough=0.45,
                          shadow=0.5, shadow_off=(3, 4), backside=rng.random() < 0.1,
                          tilt=(rng.normal(0, 0.3), rng.normal(0.1, 0.3)))
        return finish_cell(cv, inside, S)
    sunny = {"A": 0.15, "B": 0.05, "C": 0.55}[variant]
    n_p = {"A": 260, "B": 150, "C": 230}[variant]
    droop = {"A": 0.2, "B": 0.8, "C": 0.25}[variant]
    for i in range(n_p):
        depth = i / n_p
        px, py = pick()
        ang = np.arctan2(py - cy, px - cx) + rng.normal(0, 0.7)
        L = rng.uniform(35, 65) * (1.3 if variant == "B" else 1.0)
        ex, ey = px + L * np.cos(ang), py + L * np.sin(ang) + droop * L * 0.5
        if not (22 < ex < S - 22 and 22 < ey < S - 22):
            ang = np.arctan2(cy - py, cx - px) + rng.normal(0, 0.5)  # que apunte hacia dentro
        sun = np.clip(sunny + (1 - py / S) * 0.45 * depth, 0, 1)
        saman_pinna(cv, px, py, ang, L, rng, depth, sun, droop)
    return finish_cell(cv, inside, S)


def finish_cell(cv, inside, S):
    """Recorte de seguridad: nada a menos de 3 px del borde de la celda (sin sangrado entre celdas)."""
    m = np.zeros((S, S)); m[3:-3, 3:-3] = 1
    cv.a *= m
    return cv


def make_canopy():
    S = 512
    cells = [canopy_cell(S, v, 100 + i) for i, v in enumerate("ABCD")]
    big = Canvas(2 * S, 2 * S)
    for i, c in enumerate(cells):
        oy, ox = (i // 2) * S, (i % 2) * S
        for attr in ("col", "a", "n", "rough", "ao"):
            getattr(big, attr)[oy:oy + S, ox:ox + S] = getattr(c, attr)
    return save_set("canopy_atlas", big)


# ===================================================================== 2) fronda de palma plumosa
def make_palm():
    H, W = 1024, 512
    rng = np.random.default_rng(7)
    cv = Canvas(H, W)
    # raquis: de abajo (base) hacia arriba con leve curva
    pts = curve(W * 0.5, H - 8, -np.pi / 2, H * 0.97, 0.18, n=46)
    leaflets = []
    n = len(pts)
    for i in range(3, n - 1):
        (xa, ya), (xb, yb) = pts[i], pts[i + 1]
        ta = np.arctan2(yb - ya, xb - xa)
        f = i / n
        Lmax = 255 * np.sin(np.pi * np.clip(0.12 + f * 0.95, 0, 1)) ** 0.7 * (1 - 0.55 * f ** 2)
        for side in (-1, 1):
            for k in range(1):
                fx, fy = xa, ya
                L = max(30, Lmax * rng.uniform(0.88, 1.05))
                a = ta + side * (0.8 + 0.3 * (1 - f) + rng.normal(0, 0.08))
                leaflets.append((fx, fy, a, L, side, f))
    # back-to-front: foliolos de un lado ligeramente por debajo
    rng.shuffle(leaflets)
    leaflets.sort(key=lambda q: q[4])
    for fx, fy, a, L, side, f in leaflets:
        c0 = lerp(srgb("#4f7a26"), srgb("#3c6420"), rng.random())
        c1 = lerp(srgb("#88a83a"), srgb("#6f9430"), rng.random())
        if rng.random() < 0.08:  # puntas secas
            c1 = srgb("#9c8a45")
        stamp(cv, fx, fy, a, L, rng.uniform(12, 15) * (1 - 0.3 * f), prof_strap, leaf_color(c0, c1, 0.05), rng,
              bend=-side * rng.uniform(0.1, 0.22), fold=0.6, dome=0.2, rib=1.2, veins=0, vein_amt=0,
              rough=0.5, shadow=0.5, shadow_off=(3, 5), base_ao=0.35, edge_light=0.0,
              tilt=(side * 0.25, 0.1), tear=0)
    stem(cv, pts, 12, 2.5, srgb("#8a8a45"), rng, rough=0.6, shadow=0.5)
    return save_set("palm_frond", cv)


# ===================================================================== 3) plantas de jardín (atlas 2x2)
def croton_mottle(c, tc, s, xx, yy):
    spots = sample(noise_tex()[1], xx * 0.9, yy * 0.9)
    # más motas hacia la punta y cerca de la vena
    dens = np.clip(0.55 + 0.6 * tc - 0.3 * np.abs(s), 0, 1)
    yel = np.array([0.80, 0.72, 0.16])
    return lerp(c, yel, spots * dens * 0.95)


def plant_croton(S, rng):
    cv = Canvas(S, S)
    bx, by = S * 0.5, S - 4
    stems = []
    for _ in range(7):
        a = -np.pi / 2 + rng.uniform(-0.75, 0.75)
        pts = curve(bx + rng.uniform(-20, 20), by, a, S * rng.uniform(0.4, 0.72), rng.uniform(-0.4, 0.4), n=14)
        stems.append(pts)
        stem(cv, pts, 6, 3, srgb("#5a4a30"), rng)
    leaves = []
    for pts in stems:
        for j in range(3, len(pts), 2):
            for side in (-1, 1):
                leaves.append((pts[j], side, j / len(pts)))
    rng.shuffle(leaves)
    leaves.sort(key=lambda q: -q[0][1])  # de abajo (atrás) hacia arriba
    for (qx, qy), side, f in leaves:
        a = -np.pi / 2 + side * rng.uniform(0.6, 2.0)
        L = rng.uniform(80, 120) * (1 - 0.3 * f)
        dark = 0.7 + 0.3 * f
        stamp(cv, qx, qy, a, L, L * rng.uniform(0.36, 0.46), prof_oval,
              leaf_color(srgb("#2c5a1c") * dark, srgb("#3d7224") * dark, 0.12), rng,
              bend=side * rng.uniform(0.1, 0.35), backside=rng.random() < 0.12, fold=0.4, dome=0.5, rib=1.3, veins=9, vein_slant=1.0,
              vein_amt=0.35, rough=0.38, shadow=0.55, shadow_off=(5, 8), mottle=croton_mottle,
              rib_col=srgb("#d4c24a"), tilt=(rng.normal(0, 0.25), rng.normal(0, 0.25)))
    return cv


def plant_fern(S, rng):
    cv = Canvas(S, S)
    bx, by = S * 0.5, S - 10
    fronds = sorted([rng.uniform(-1.35, 1.35) for _ in range(11)], key=lambda q: -abs(q))
    for k, off in enumerate(fronds):
        a = -np.pi / 2 + off
        length = S * rng.uniform(0.42, 0.56) * (1 - 0.2 * abs(off))
        curl = np.sign(off) * rng.uniform(0.6, 1.2)
        pts = curve(bx + rng.uniform(-12, 12), by, a, length, curl, n=34, droop=0.15)
        dark = 0.7 + 0.3 * k / len(fronds)
        g0 = srgb("#3f6e24") * dark; g1 = srgb("#79a23c") * dark
        n = len(pts)
        for i in range(2, n - 1):
            (xa, ya), (xb, yb) = pts[i], pts[i + 1]
            ta = np.arctan2(yb - ya, xb - xa)
            f = i / n
            L = 38 * np.sin(np.pi * np.clip(0.15 + f * 0.9, 0, 1)) ** 0.6 * (1 - 0.5 * f) + 5
            for side in (-1, 1):
                stamp(cv, xa, ya, ta + side * rng.uniform(1.05, 1.3), L, L * 0.32, prof_lance,
                      leaf_color(g0, g1, 0.08), rng, bend=side * -0.12, fold=0.3, dome=0.4, rib=0.6,
                      veins=int(L / 4), vein_slant=0.0, vein_amt=0.35, rough=0.7, shadow=0.4,
                      shadow_off=(2, 3), base_ao=0.2, tilt=(0, 0.15), edge_light=0.0)
        stem(cv, pts, 3.5, 1.2, srgb("#4c5e2a") * dark, rng, shadow=0.25)
    return cv


def plant_heliconia(S, rng):
    cv = Canvas(S, S)
    bx, by = S * 0.5, S - 4
    order = sorted([rng.uniform(-0.55, 0.55) for _ in range(6)], key=lambda q: -abs(q))
    for k, off in enumerate(order):
        a = -np.pi / 2 + off
        plen = S * rng.uniform(0.18, 0.32)
        pts = curve(bx + rng.uniform(-20, 20), by, a, plen, off * 0.2, n=8)
        stem(cv, pts, 9, 7, srgb("#4f6a2a"), rng)
        ex, ey = pts[-1]
        ang = a + off * 0.5
        L = S * rng.uniform(0.4, 0.5)
        # que la hoja no se salga de la celda
        for _ in range(20):
            tx, ty = ex + L * np.cos(ang), ey + L * np.sin(ang)
            if 30 < tx < S - 30 and ty > 20:
                break
            L *= 0.92
        dark = 0.75 + 0.25 * k / len(order)
        stamp(cv, ex, ey, ang, L, L * rng.uniform(0.32, 0.4), prof_oval,
              leaf_color(srgb("#2f5e20") * dark, srgb("#44792a") * dark, 0.08), rng,
              bend=np.sign(off + 1e-3) * rng.uniform(0.04, 0.12), fold=0.25, dome=0.6, rib=2.2, veins=26,
              vein_slant=2.8, vein_amt=0.3, rough=0.45, shadow=0.6, shadow_off=(8, 12), base_ao=0.2,
              tear=int(rng.integers(2, 6)), rib_col=srgb("#a7bf63"), tilt=(rng.normal(0, 0.2), 0.1))
    return cv


def plant_purple(S, rng):
    cv = Canvas(S, S)
    bx, by = S * 0.5, S - 6
    leaves = sorted([rng.uniform(-1.3, 1.3) for _ in range(24)], key=lambda q: -abs(q))
    for k, off in enumerate(leaves):
        a = -np.pi / 2 + off
        L = S * rng.uniform(0.34, 0.5) * (1 - 0.25 * abs(off))
        dark = 0.65 + 0.35 * k / len(leaves)

        def col(tc, s, x, y, xx, yy, r, dark=dark):
            j = r.normal(0, 0.08)
            base = srgb("#3a1430") * (1 + j) * dark
            mid = srgb("#6b2048") * (1 + j) * dark
            edge = srgb("#b0406a") * dark
            c = lerp(base, mid, tc ** 0.7)
            return lerp(c, edge, np.clip((np.abs(s) - 0.82) * 6, 0, 1) * 0.8)
        stamp(cv, bx + rng.uniform(-10, 10), by, a, L, L * rng.uniform(0.26, 0.32), prof_oval, col, rng,
              bend=np.sign(off) * rng.uniform(0.25, 0.6), backside=rng.random() < 0.1, fold=0.5, dome=0.4, rib=1.2, veins=0, vein_amt=0,
              rough=0.42, shadow=0.55, shadow_off=(4, 6), base_ao=0.35, rib_col=srgb("#8e2c55") * dark,
              tilt=(np.sign(off) * 0.2, 0.1), edge_light=0.0)
    return cv


def make_garden():
    S = 512
    fns = [plant_croton, plant_fern, plant_heliconia, plant_purple]
    big = Canvas(2 * S, 2 * S)
    for i, fn in enumerate(fns):
        c = fn(S, np.random.default_rng(300 + i))
        oy, ox = (i // 2) * S, (i % 2) * S
        for attr in ("col", "a", "n", "rough", "ao"):
            getattr(big, attr)[oy:oy + S, ox:ox + S] = getattr(c, attr)
    return save_set("garden_atlas", big)


# ===================================================================== 4) hiedra / cobertura (tileable)
def make_ivy():
    S = 512
    rng = np.random.default_rng(41)
    soil_n = fbm(S, 8, 6, seed=42)
    soil = lerp(srgb("#2a2117"), srgb("#4a3a28"), soil_n)
    # hojarasca
    lit, _ = worley(S, 220, seed=43)
    soil = lerp(soil, srgb("#5e4a30"), np.clip((0.12 - lit) * 6, 0, 1) * 0.6)
    cv = Canvas(S, S, wrap=True, bg=soil)
    cv.a[:] = 0; cv.rough[:] = 0.95
    macro = fbm(S, 3, 4, seed=44)
    # rastreros
    for _ in range(14):
        pts = curve(*rng.uniform(0, S, 2), rng.uniform(0, 2 * np.pi), rng.uniform(250, 500), rng.uniform(-2, 2), n=40)
        pts = [(px % S + 0 * S, py % S) if False else (px, py) for px, py in pts]
        stem(cv, pts, 2.5, 1.5, srgb("#5a4632"), rng, shadow=0.3)
    for layer in range(3):
        n = [260, 230, 170][layer]
        dark = [0.6, 0.8, 1.0][layer]
        for _ in range(n):
            px, py = rng.uniform(0, S, 2)
            m = macro[int(py) % S, int(px) % S]
            L = rng.uniform(26, 40)
            g0 = lerp(srgb("#1f3d16"), srgb("#3c6424"), m) * dark
            g1 = lerp(srgb("#2d5220"), srgb("#5d8a32"), m) * dark
            stamp(cv, px, py, rng.uniform(0, 2 * np.pi), L, L * 0.95, prof_ivy, leaf_color(g0, g1, 0.12), rng,
                  fold=0.15, dome=0.6, rib=0.8, veins=4, vein_slant=1.4, vein_amt=0.3, rough=0.5,
                  shadow=0.6, shadow_off=(4, 6), base_ao=0.2, rib_col=lerp(g1, srgb("#a7b48a"), 0.3),
                  tilt=(rng.normal(0, 0.3), rng.normal(0, 0.3)))
    cv.a = np.ones_like(cv.a)
    return save_set("ivy_ground", cv, rgba=False)


# ===================================================================== 5) seto recortado (tileable)
def make_hedge():
    S = 512
    rng = np.random.default_rng(51)
    deep = srgb("#0f1d0c")
    cv = Canvas(S, S, wrap=True, bg=np.broadcast_to(deep, (S, S, 3)).copy())
    cv.ao[:] = 0.35; cv.rough[:] = 0.9
    macro = fbm(S, 4, 5, seed=52)
    macro2 = fbm(S, 2, 3, seed=53)
    # ramitas internas visibles en los huecos
    for _ in range(40):
        pts = curve(*rng.uniform(0, S, 2), rng.uniform(0, 2 * np.pi), rng.uniform(30, 80), rng.uniform(-1, 1), n=6)
        stem(cv, pts, 2, 1, srgb("#2b2418"), rng, shadow=0.2)
    layers = 5
    for layer in range(layers):
        n = [600, 600, 550, 500, 420][layer]
        dark = 0.45 + 0.6 * (layer / (layers - 1)) ** 0.7
        for _ in range(n):
            px, py = rng.uniform(0, S, 2)
            m = macro[int(py) % S, int(px) % S]
            m2 = macro2[int(py) % S, int(px) % S]
            # zonas superiores más llenas (seto recortado) -> menos huecos en macro alto
            if layer == layers - 1 and m < 0.35:
                continue
            L = rng.uniform(17, 25)
            g0 = lerp(srgb("#2f5420"), srgb("#5a8a2a"), m) * dark
            g1 = lerp(srgb("#4a7a26"), srgb("#a2bc45"), np.clip(m * (0.5 + 0.8 * m2), 0, 1)) * dark
            stamp(cv, px, py, rng.uniform(0, 2 * np.pi), L, L * 0.55, prof_oval, leaf_color(g0, g1, 0.08), rng,
                  fold=0.3, backside=rng.random() < 0.06, dome=0.5, rib=0.6, veins=0, vein_amt=0, rough=0.55 + 0.1 * rng.random(),
                  shadow=0.5, shadow_off=(2.5, 3.5), base_ao=0.15, edge_light=0.0,
                  tilt=(rng.normal(0, 0.35), rng.normal(0, 0.35)))
    cv.a = np.ones_like(cv.a)
    return save_set("hedge", cv, rgba=False)


# ===================================================================== previews
def preview_card(base, out_png, bg=(0.55, 0.68, 0.78)):
    """Composita el atlas RGBA sobre cielo con alpha scissor 0.5 + iluminación simple con la normal."""
    alb = np.asarray(Image.open(base + "_albedo.png").convert("RGBA"), float) / 255
    nor = np.asarray(Image.open(base + "_normal.png"), float) / 255 * 2 - 1
    orm = np.asarray(Image.open(base + "_orm.png"), float) / 255
    L = np.array([-0.4, 0.5, 0.75]); L /= np.linalg.norm(L)
    ndl = np.clip((nor * L).sum(-1), 0, 1)
    lin = alb[..., :3] ** 2.2
    c = lin * (0.35 + 0.8 * ndl[..., None]) * orm[..., 0:1]
    c = c ** (1 / 2.2)
    m = (alb[..., 3] >= 0.5)[..., None]
    out = np.where(m, c, np.array(bg))
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(out_png)


def preview_tile(base, out_png):
    from common import preview
    preview(os.path.relpath(base, ROOT), out_png)


def main():
    os.makedirs(PREV, exist_ok=True)
    only = sys.argv[1:] or ["canopy", "palm", "garden", "ivy", "hedge"]
    outs = []
    if "canopy" in only:
        b = make_canopy(); preview_card(b, f"{PREV}/canopy.png"); outs.append(f"{PREV}/canopy.png")
    if "palm" in only:
        b = make_palm(); preview_card(b, f"{PREV}/palm.png"); outs.append(f"{PREV}/palm.png")
    if "garden" in only:
        b = make_garden(); preview_card(b, f"{PREV}/garden.png"); outs.append(f"{PREV}/garden.png")
    if "ivy" in only:
        b = make_ivy(); preview_tile(b, f"{PREV}/ivy.png"); outs.append(f"{PREV}/ivy.png")
    if "hedge" in only:
        b = make_hedge(); preview_tile(b, f"{PREV}/hedge.png"); outs.append(f"{PREV}/hedge.png")
    if len(only) == 5:
        contact_sheet(outs, f"{PREV}/contact.png", cell=512)
    print("ok", outs)


if __name__ == "__main__":
    main()

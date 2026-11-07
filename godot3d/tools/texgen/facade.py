"""Familia FACADE: ventanas residenciales, vitrinas de locales, letreros y toldos.

Regenerar:  python3 tools/texgen/facade.py
Salida en art/tex/facade/ :
  windows_*     atlas 4x4 de 1024 px (RGBA), celda 256 px = ventana de ~1.4 x 1.4 m (~180 px/m).
                Celdas "iluminadas" de noche (LIT_WINDOWS) tienen interior cálido en windows_emission.png.
  shopfronts_*  atlas 2x2 de 1024 px, celda 512 px = vitrina completa de ~3.2 x 3.2 m (~160 px/m):
                0 café, 1 panadería, 2 droguería, 3 tienda de barrio. Emisión = interior encendido.
  signs_*       atlas 4x4 de 1024 px (RGBA, alpha scissor), celda 256 px. Celdas 0-9 y 15 son letreros
                de banda 2:1 (256x128 centrados en la celda); 10-14 son cuadrados (avisos redondos y neones).
  awning_stripes_*, awning_plain_*  lona de toldo 512 px = 1.5 m, tilea en ambos ejes.
Todos los nombres comerciales son inventados.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (ROOT, fbm, blur_wrap, lerp, hex2rgb,  # noqa: E402
                    ao_from_height, save_pbr, preview, contact_sheet)

OUT = "art/tex/facade"
TMP = "/tmp/f1_facade"
os.makedirs(TMP, exist_ok=True)

FONTS = {
    "script": "/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyrechorus-mediumitalic.otf",
    "lora": "/usr/share/fonts/truetype/google-fonts/Lora-Variable.ttf",
    "lora_i": "/usr/share/fonts/truetype/google-fonts/Lora-Italic-Variable.ttf",
    "poppins_b": "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf",
    "poppins_m": "/usr/share/fonts/truetype/google-fonts/Poppins-Medium.ttf",
    "poppins_l": "/usr/share/fonts/truetype/google-fonts/Poppins-Light.ttf",
    "heros_cn": "/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyreheroscn-bold.otf",
    "schola_b": "/usr/share/texmf/fonts/opentype/public/tex-gyre/texgyreschola-bold.otf",
}


# ============================================================ utilidades propias
def C(h):
    return np.array(hex2rgb(h))


def noise(h, w, cells=4, octaves=5, seed=0):
    """fbm recortado a (h, w) (no necesita tilear: celdas de atlas)."""
    s = max(h, w)
    s2 = 1 << int(np.ceil(np.log2(s)))
    return fbm(s2, base_cells=cells, octaves=octaves, seed=seed)[:h, :w]


def blur(a, s):
    if s <= 0:
        return a
    if a.ndim == 3:
        return np.stack([ndimage.gaussian_filter(a[..., c], s, mode="nearest") for c in range(a.shape[2])], -1)
    return ndimage.gaussian_filter(a, s, mode="nearest")


def rect_mask(h, w, x0, y0, x1, y1, soft=0.0):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    if soft <= 0:
        return ((xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)).astype(np.float64)
    m = np.clip((xx - x0) / soft, 0, 1) * np.clip((x1 - xx) / soft, 0, 1)
    m *= np.clip((yy - y0) / soft, 0, 1) * np.clip((y1 - yy) / soft, 0, 1)
    return m.astype(np.float64)


def font(name, size):
    return ImageFont.truetype(FONTS[name], int(size))


def text_mask(w, h, text, fname, max_size, box=None, ss=3):
    """Máscara [0,1] (h,w) con el texto ajustado y centrado dentro de box=(x0,y0,x1,y1)."""
    if box is None:
        box = (0, 0, w, h)
    bw, bh = box[2] - box[0], box[3] - box[1]
    size = max_size
    while size > 6:
        f = font(fname, size * ss)
        bb = f.getbbox(text)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        if tw <= bw * ss and th <= bh * ss:
            break
        size -= 1
    img = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(img)
    cx = (box[0] + box[2]) / 2 * ss
    cy = (box[1] + box[3]) / 2 * ss
    # centrar por la caja real de tinta (no por la métrica de la fuente)
    d.text((0, 0), text, font=f, fill=255)
    bb = f.getbbox(text)
    img = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(img)
    d.text((cx - (bb[0] + bb[2]) / 2, cy - (bb[1] + bb[3]) / 2), text, font=f, fill=255)
    img = img.resize((w, h), Image.LANCZOS)
    return np.asarray(img, dtype=np.float64) / 255.0


def draw_layer(w, h, fn, ss=3):
    """Dibuja con PIL a ss× y devuelve máscara [0,1]. fn(draw, ss)."""
    img = Image.new("L", (w * ss, h * ss), 0)
    fn(ImageDraw.Draw(img), ss)
    return np.asarray(img.resize((w, h), Image.LANCZOS), dtype=np.float64) / 255.0


def over(dst, col, m):
    """Compone color (3,) o (h,w,3) sobre dst con máscara m (h,w)."""
    return dst * (1 - m[..., None]) + np.asarray(col) * m[..., None]


def sky_reflection(h, w, seed, bright=1.0, buildings=True, bop=0.75):
    """Reflejo de cielo nublado + silueta de edificios/árboles de enfrente, para vidrios."""
    rng = np.random.default_rng(seed)
    yy = np.linspace(0, 1, h)[:, None] * np.ones((1, w))
    xx = np.ones((h, 1)) * np.linspace(0, 1, w)[None, :]
    sky = lerp(C("#bcc8d2"), C("#76879a"), yy ** 0.8)
    cl = noise(h, w, cells=3, octaves=5, seed=seed)
    sky = lerp(sky, C("#e0e4e7"), np.clip((cl - 0.45) * 2.2, 0, 1) * (1 - yy) * 0.8)
    sky = sky * bright
    if buildings:
        horizon = 0.35 + rng.random() * 0.35
        x = 0
        while x < w:
            bw = int(w * (0.12 + rng.random() * 0.35))
            top = int(h * (horizon - rng.random() * 0.25))
            col = lerp(C("#3b3a3a"), C("#7a5546"), rng.random() * 0.8) * (0.55 + rng.random() * 0.3)
            sky = over(sky, col, rect_mask(h, w, x, top, x + bw, h) * bop)
            step_y = max(8, int(h * 0.055))
            step_x = max(7, int(w * 0.047))
            for wy in range(top + step_y // 2, h, step_y):
                for wx in range(x + 4, x + bw - step_x // 2, step_x):
                    if rng.random() < 0.6:
                        sky = over(sky, col * 0.6 + C("#8fa0ad") * 0.25,
                                   rect_mask(h, w, wx, wy, wx + step_x // 2, wy + step_y // 2) * 0.5 * bop)
            x += bw
        tr = noise(h, w, cells=6, octaves=5, seed=seed + 9)
        tree_line = horizon + 0.1 + 0.15 * np.sin(xx * 6 + rng.random() * 6)
        tm = np.clip((yy - tree_line + (tr - 0.5) * 0.35) * 18, 0, 1) * float(rng.random() < 0.7)
        sky = over(sky, lerp(C("#25301f"), C("#46553a"), tr), tm * 0.9 * bop)
    ang = rng.uniform(0.6, 1.2)
    band = np.sin((xx * np.cos(ang) + yy * np.sin(ang)) * rng.uniform(5, 9) + rng.random() * 6)
    sky = sky + (np.clip(band - 0.8, 0, 1) * 0.35)[..., None]
    return np.clip(sky, 0, 1)


def _rgba(rel, rgb, alpha):
    a = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(ROOT, rel), optimize=True)


# ============================================================ interior falso 3D
class Room:
    """Habitación detrás del vidrio por 'interior mapping', ojo en el andén.
    Vidrio en z=0 (x∈[-hw,hw], y∈[y0,y1] m); ojo E (z<0); cuarto x∈[-RW,RW], y∈[floor,ceil], z∈[0,depth]."""

    def __init__(self, w, h, hw, y0, y1, depth, eye, room_w, floor=0.0, ceil=3.0):
        self.w, self.h = w, h
        xs = np.linspace(-hw, hw, w)
        ys = np.linspace(y1, y0, h)
        self.px = xs[None, :] * np.ones((h, 1))
        self.py = ys[:, None] * np.ones((1, w))
        self.E = np.array(eye, dtype=np.float64)
        self.dx = self.px - self.E[0]
        self.dy = self.py - self.E[1]
        self.dz = -self.E[2] * np.ones_like(self.px)
        RW = room_w
        with np.errstate(divide="ignore", invalid="ignore"):
            tx = np.where(self.dx > 0, (RW - self.E[0]) / self.dx, (-RW - self.E[0]) / self.dx)
            ty = np.where(self.dy > 0, (ceil - self.E[1]) / self.dy, (floor - self.E[1]) / self.dy)
            tz = (depth - self.E[2]) / self.dz
        tx = np.where(np.isfinite(tx) & (tx > 0), tx, 1e9)
        ty = np.where(np.isfinite(ty) & (ty > 0), ty, 1e9)
        t = np.minimum(np.minimum(tx, ty), tz)
        self.X = self.E[0] + t * self.dx
        self.Y = self.E[1] + t * self.dy
        self.Z = self.E[2] + t * self.dz
        surf = np.zeros((h, w), dtype=int)  # 0 fondo
        surf[(t == tx) & (self.dx < 0)] = 1  # pared izq
        surf[(t == tx) & (self.dx > 0)] = 2  # pared der
        surf[(t == ty) & (self.dy < 0)] = 3  # piso
        surf[(t == ty) & (self.dy > 0)] = 4  # techo
        self.surf = surf
        self.col = np.zeros((h, w, 3))
        self.zbuf = self.Z.copy()

    def point_at(self, z):
        t = (z - self.E[2]) / self.dz
        return self.E[0] + t * self.dx, self.E[1] + t * self.dy

    def billboard(self, z, x0, x1, y0, y1, colfn):
        """Rectángulo paralelo al vidrio a profundidad z. colfn(u,v)->(rgb,alpha), u,v∈[0,1] (v=0 abajo)."""
        X, Y = self.point_at(z)
        m = (X >= x0) & (X <= x1) & (Y >= y0) & (Y <= y1) & (z < self.zbuf)
        if not m.any():
            return
        u = (X - x0) / (x1 - x0)
        v = (Y - y0) / (y1 - y0)
        rgb, a = colfn(u, v)
        a = np.where(m, a, 0.0)
        self.col = over(self.col, rgb, a)
        self.zbuf = np.where(a > 0.5, z, self.zbuf)

    def light(self, lamps, amb=0.35, falloff=0.08):
        """Factor de luz: ambiente + lámparas (x,y,z,k) con atenuación suave."""
        L = np.full((self.h, self.w), amb)
        for (lx, ly, lz, k) in lamps:
            X, Y = self.X, self.Y
            d2 = (X - lx) ** 2 + (Y - ly) ** 2 + (self.zbuf - lz) ** 2
            L = L + k / (1 + d2 * 1.2)
        return L * np.exp(-np.maximum(self.zbuf, 0) * falloff)


def planks(u, v, scale, seed, base, var=0.15):
    """Tablas de madera (u = coordenada a lo ancho de las tablas, en metros)."""
    rng = np.random.default_rng(seed)
    idx = np.floor(u * scale).astype(int)
    tone = rng.random(512)[idx % 512]
    grain = np.sin((v * 40 + np.sin(u * 13) * 2 + tone * 30)) * 0.5 + 0.5
    col = np.asarray(base) * (1 - var + tone[..., None] * var * 2) * (0.9 + grain[..., None] * 0.12)
    fr = (u * scale) % 1.0
    seam = (fr < 0.04) | (fr > 0.96)
    return np.where(seam[..., None], col * 0.55, col)


def person_fn(skin, shirt, hair="#1c1612", cap=None):
    def f(u, v):
        head = ((u - 0.5) / 0.2) ** 2 + ((v - 0.87) / 0.11) ** 2 < 1
        neck = (np.abs(u - 0.5) < 0.07) & (v > 0.72) & (v < 0.8)
        body = (np.abs(u - 0.5) < 0.42 - np.clip(v - 0.62, 0, 1) * 0.8) & (v < 0.76)
        c = np.where((head | neck)[..., None], C(skin), C(shirt))
        top = head & (v > 0.92)
        c = np.where(top[..., None], C(cap) if cap else C(hair), c)
        return c, (head | body | neck).astype(float)
    return f


def plant_fn(sd):
    def f(u, v):
        r = np.random.default_rng(sd)
        a = np.zeros(u.shape, dtype=bool)
        c = np.zeros(u.shape + (3,))
        for _ in range(34):
            cx, cy = r.uniform(0.12, 0.88), r.uniform(0.35, 1.0)
            ang = r.uniform(0, np.pi)
            du, dv = u - cx, v - cy
            ru = du * np.cos(ang) + dv * np.sin(ang)
            rv = -du * np.sin(ang) + dv * np.cos(ang)
            leaf = (ru / 0.17) ** 2 + (rv / 0.05) ** 2 < 1
            g = lerp(C("#2a4420"), C("#74963f"), r.random()) * (0.8 + 0.4 * np.clip(rv / 0.05 + 0.5, 0, 1))[..., None]
            c = np.where(leaf[..., None], g, c)
            a |= leaf
        pot = (np.abs(u - 0.5) < 0.25 - (0.3 - v) * 0.2) & (v < 0.3)
        c = np.where(pot[..., None], C("#b8b2a6") * (0.8 + 0.3 * u)[..., None], c)
        return c, (a | pot).astype(float)
    return f


def solid(col):
    return lambda u, v: (np.ones(u.shape + (3,)) * C(col), np.ones(u.shape))


# ============================================================ VENTANAS RESIDENCIALES
WIN_CELL = 256
LIT_WINDOWS = [0, 2, 5, 7, 8, 10, 13, 15]

FRAMES = {  # color, rugosidad, metal
    "alu": (C("#a9adb0"), 0.32, 0.9),
    "black": (C("#1d1e20"), 0.42, 0.55),
    "white": (C("#dedcd5"), 0.5, 0.0),
    "bronze": (C("#4a3b2e"), 0.38, 0.75),
}

# marco, despiece, interior, reja, color cortina/persiana, cobertura
WINDOW_SPECS = [
    ("alu", "2v", "curtain", None, "#d8cfbd", 0.65),
    ("black", "3v", "blinds", None, "#e8e6e0", 0.45),
    ("alu", "2v_top", "sheer", "bars", "#efece4", 1.0),
    ("bronze", "2v", "dark", None, None, 0.0),
    ("white", "4grid", "curtain", "diamond", "#9c4b3c", 0.4),
    ("alu", "2v", "blinds", "bars", "#b89a72", 0.7),
    ("black", "2v_top", "curtain", None, "#5d6b74", 0.3),
    ("alu", "3v", "room", None, None, 0.0),
    ("black", "2v", "sheer", "grid", "#f2efe8", 1.0),
    ("alu", "4grid", "dark", "bars", None, 0.0),
    ("bronze", "2v_top", "curtain", None, "#c9b37e", 0.8),
    ("alu", "2v", "curtain", "diamond", "#e2ddd2", 0.5),
    ("white", "3v", "blinds", None, "#f0eee8", 0.25),
    ("black", "2v", "room", "bars", None, 0.0),
    ("alu", "2v_top", "dark", None, None, 0.0),
    ("bronze", "3v", "sheer", "grid", "#efe7d6", 1.0),
]


def window_cell(i, spec):
    S = WIN_CELL
    rng = np.random.default_rng(100 + i)
    frame, layout, interior, reja, ccol, openf = spec
    fcol, frough, fmetal = FRAMES[frame]
    lit = i in LIT_WINDOWS
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)

    b = 11
    if layout == "2v":
        mid = S // 2
        panes = [(b, b, mid - 3, S - b), (mid + 3, b, S - b, S - b)]
    elif layout == "3v":
        t1, t2 = S // 3, 2 * S // 3
        panes = [(b, b, t1 - 3, S - b), (t1 + 3, b, t2 - 3, S - b), (t2 + 3, b, S - b, S - b)]
    elif layout == "2v_top":
        top, mid = int(S * 0.3), S // 2
        panes = [(b, b, S - b, top - 3), (b, top + 3, mid - 3, S - b), (mid + 3, top + 3, S - b, S - b)]
    else:  # 4grid
        mid = S // 2
        panes = [(b, b, mid - 3, mid - 3), (mid + 3, b, S - b, mid - 3),
                 (b, mid + 3, mid - 3, S - b), (mid + 3, mid + 3, S - b, S - b)]
    glass = np.zeros((S, S))
    for p in panes:
        glass = np.maximum(glass, rect_mask(S, S, *p))
    frame_m = 1 - glass

    warm = C("#ffb867")
    n1 = noise(S, S, cells=4, octaves=4, seed=200 + i)
    room = lerp(C("#2a2622"), C("#141312"), yy / S)
    room_light = np.exp(-(((xx - S * rng.uniform(0.3, 0.7)) / (S * 0.45)) ** 2 + ((yy - S * 0.15) / (S * 0.6)) ** 2))
    inter = room * (0.8 + 0.3 * n1[..., None])
    emis_room = warm * (0.25 + 0.75 * room_light)[..., None] * 0.55
    emis = emis_room
    if interior == "room":
        sh = rect_mask(S, S, S * 0.12, S * 0.62, S * 0.55, S * 0.95, soft=3)
        inter = over(inter, C("#3a2d22"), sh)
        art = rect_mask(S, S, S * 0.6, S * 0.25, S * 0.82, S * 0.48, soft=2)
        inter = over(inter, C("#6c5a3d"), art)
        lamp = np.exp(-(((xx - S * 0.35) / 10) ** 2 + ((yy - S * 0.2) / 7) ** 2))
        inter = inter + C("#c9a476") * lamp[..., None] * 0.5
        emis = emis_room * (1 - sh[..., None] * 0.7) + warm * lamp[..., None] * 1.5 + C("#ffe0b0") * art[..., None] * 0.15
    elif interior == "dark":
        emis = emis_room * 0.6
    elif interior in ("curtain", "sheer"):
        sheer = interior == "sheer"
        cc = C(ccol)
        k = rng.uniform(9, 13) if not sheer else rng.uniform(16, 22)
        gather = 1 + 0.6 * np.clip(np.abs(xx - S / 2) / (S / 2), 0, 1)
        folds = (0.5 + 0.5 * np.sin(2 * np.pi * xx / S * k * gather + n1 * 1.5 + yy / S * 0.6)) ** 1.3
        gap = (1 - openf) * 0.5 * S
        cov = np.clip((np.abs(xx - S / 2) - gap) / 6, 0, 1) if openf < 0.99 else np.ones((S, S))
        shade = 0.72 + 0.35 * folds
        cimg = cc[None, None, :] * shade[..., None] * (0.92 + 0.12 * n1[..., None])
        a = cov * (0.75 if sheer else 1.0)
        hem = 1 - 0.25 * rect_mask(S, S, 0, S - b - 10, S, S - b - 6)
        inter = over(inter, cimg * hem[..., None], a)
        trans = (0.65 if sheer else 0.28) * (0.75 + 0.35 * folds)
        e_cur = warm * np.sqrt(cc)[None, None, :] * trans[..., None] * (0.6 + 0.6 * room_light[..., None])
        emis = emis_room * (1 - a[..., None]) + e_cur * a[..., None]
    elif interior == "blinds":
        bc = C(ccol)
        pitch = 7.0
        slat = (yy % pitch) / pitch
        raised = b + S * (1 - openf) * 0.6
        cov = (yy > raised).astype(np.float64)
        prof = 0.75 + 0.3 * np.sin(slat * np.pi)
        gaps = (slat > 0.86).astype(np.float64)
        bl = bc[None, None, :] * prof[..., None] * (0.95 + 0.08 * n1[..., None])
        inter = over(inter, bl, cov * (1 - gaps * 0.8))
        # paquete recogido arriba
        pack = rect_mask(S, S, 0, raised - 9, S, raised)
        inter = over(inter, bc * 0.9 * (0.8 + 0.2 * ((yy % 3) > 1))[..., None], pack)
        for cx in (S * 0.25, S * 0.75):
            inter = over(inter, bc * 0.8, rect_mask(S, S, cx - 1, 0, cx + 1, S) * cov * 0.6)
        emis = emis_room * (1 - cov[..., None]) + warm * (cov * (gaps * 0.9 + (1 - gaps) * 0.22))[..., None] * \
            (0.6 + 0.6 * room_light[..., None])
        emis = emis * (1 - pack[..., None] * 0.8)
    # vidrio: reflejo + transmisión
    refl0 = sky_reflection(S, S, seed=300 + i, bright=0.95, bop=0.55)
    refl = np.zeros_like(refl0)
    for k, p in enumerate(panes):  # hojas corredizas en planos distintos: reflejo desfasado
        pm = rect_mask(S, S, *p)
        refl = refl + np.roll(refl0, (k % 2) * 9, axis=1) * pm[..., None]
    refl = refl + refl0 * (1 - glass)[..., None]
    fres = 0.3 + 0.2 * (1 - yy / S)
    gl = inter * (1 - fres[..., None]) * 1.05 + refl * fres[..., None] * 0.8
    dust = np.clip(noise(S, S, cells=8, octaves=5, seed=400 + i) - 0.3, 0, 1) * (yy / S) ** 2
    gl = lerp(gl, C("#9a9184"), dust * 0.35)
    # marco con bisel (claro arriba-izq del perfil, oscuro abajo)
    fn = noise(S, S, cells=16, octaves=4, seed=500 + i)
    fimg = fcol[None, None, :] * (0.92 + 0.12 * fn[..., None])
    gb = blur(glass, 1.5)
    gdy = np.gradient(gb, axis=0)
    gdx = np.gradient(gb, axis=1)
    fimg = fimg * (1 + np.clip(gdy * 3 + gdx * 1.5, -0.35, 0.35)[..., None])
    grime = blur((glass > 0.5).astype(float), 4) * frame_m * np.clip((yy % (S / 2)) / (S / 2), 0, 1)
    albedo = gl * glass[..., None] + fimg * frame_m[..., None]
    albedo = lerp(albedo, C("#3d362d"), grime * 0.4)
    ring = ((blur(glass, 1.5) > 0.05) & (glass < 0.5)).astype(float)
    albedo = over(albedo, C("#141414"), ring * 0.8)
    # chorreón bajo el marco inferior (sobre el propio perfil)
    height = blur(0.55 * frame_m + 0.15 * glass, 0.8)
    rough = glass * 0.06 + frame_m * frough + dust * 0.4 * glass
    metal = frame_m * fmetal
    rough = rough * (1 - ring) + 0.8 * ring
    metal = metal * (1 - ring)
    emis = emis * glass[..., None] * (1 - fres[..., None] * 0.35)

    if reja:
        if reja == "bars":
            pitch = 22
            bars = (np.abs((xx - 8) % pitch - pitch / 2) < 1.6).astype(float)
            for yb in (S * 0.33, S * 0.66):
                bars = np.maximum(bars, rect_mask(S, S, 0, yb - 2.5, S, yb + 2.5))
        elif reja == "grid":
            pitch = 32
            bars = ((np.abs(xx % pitch - pitch / 2) < 1.4) | (np.abs(yy % pitch - pitch / 2) < 1.4)).astype(float)
        else:  # diamond
            pitch = 40
            u = (xx + yy) % pitch
            v = (xx - yy) % pitch
            bars = ((np.abs(u - pitch / 2) < 1.6) | (np.abs(v - pitch / 2) < 1.6)).astype(float)
        bars = np.maximum(bars, (1 - rect_mask(S, S, 5, 5, S - 5, S - 5)))
        bars = blur(bars, 0.6)
        rcol = C("#1b1c1b") if (i % 3) else C("#dcdad3")
        rust = np.clip(noise(S, S, cells=12, octaves=4, seed=600 + i) - 0.62, 0, 1) * 1.5
        bcol = lerp(rcol[None, None, :] * np.ones((S, S, 1)), C("#6b3b22"), rust * 0.6)
        bcol = bcol * (0.85 + 0.3 * np.clip(-np.gradient(blur(bars, 1), axis=1) * 2, -0.5, 0.5) + 0.15)[..., None]
        shadow = np.roll(np.roll(bars, 4, axis=0), 3, axis=1)
        albedo = albedo * (1 - shadow[..., None] * 0.35)
        albedo = over(albedo, bcol, bars)
        height = np.maximum(height, bars * 1.0)
        rough = rough * (1 - bars) + bars * (0.55 + rust * 0.3)
        metal = metal * (1 - bars) + bars * 0.25
        emis = emis * (1 - bars[..., None])
    emis = np.clip(emis * 1.6, 0, 1)
    if not lit:
        emis = emis * 0.0
    return albedo, height, rough, metal, emis


def build_windows():
    S = WIN_CELL
    N = 4 * S
    A = np.zeros((N, N, 3)); H = np.zeros((N, N)); R = np.zeros((N, N)); M = np.zeros((N, N))
    E = np.zeros((N, N, 3))
    for i, spec in enumerate(WINDOW_SPECS):
        r, c = divmod(i, 4)
        a, h, ro, me, em = window_cell(i, spec)
        sl = (slice(r * S, (r + 1) * S), slice(c * S, (c + 1) * S))
        A[sl] = a; H[sl] = h; R[sl] = ro; M[sl] = me; E[sl] = em
    ao = ao_from_height(H, radius=5, strength=1.5)
    save_pbr(OUT + "/windows", np.clip(A, 0, 1), height=H, rough=np.clip(R, 0, 1), metal=np.clip(M, 0, 1), ao=ao,
             normal_strength=6.0, emission=np.clip(E, 0, 1))
    _rgba(OUT + "/windows_albedo.png", A, np.ones((N, N)))


# ============================================================ VITRINAS
SHOP_CELL = 512
SHOP_KINDS = ["cafe", "panaderia", "drogueria", "tienda"]


def shop_cell(kind, seed):
    S = SHOP_CELL
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    top_h = int(S * 0.11)
    zoc = int(S * 0.88)
    gx0, gx1 = 14, S - 14
    gy0, gy1 = top_h + 10, zoc - 6
    gw, gh = gx1 - gx0, gy1 - gy0
    hw = 1.5
    m_per_px = 2 * hw / gw
    yb = 0.45
    yt = yb + gh * m_per_px
    eye = (rng.uniform(-0.6, 0.6), 1.6, -4.0)
    room = Room(gw, gh, hw, yb, yt, depth=5.0, eye=eye, room_w=2.3, floor=0.0, ceil=3.2)
    X, Y, Z, s = room.X, room.Y, room.Z, room.surf
    n = noise(gh, gw, cells=6, octaves=4, seed=seed + 1)
    emis_tint = C("#ffd29a")

    if kind == "cafe":
        wood = C("#8a5a35")
        col = np.where((s == 0)[..., None], planks(X, Y, 6, seed, wood), planks(Z, Y, 6, seed + 1, wood * 0.9))
        col = np.where((s == 4)[..., None], planks(X, Z, 5, seed + 2, C("#a06b40")), col)
        col = np.where((s == 3)[..., None], lerp(C("#3b3632"), C("#55504a"), n), col)
        room.col = col
        lamps = [(-0.8, 2.7, 1.5, 1.6), (0.7, 2.7, 2.6, 1.6), (0.0, 2.7, 4.0, 1.2)]

        def poster(u, v):
            c = np.ones(u.shape + (3,)) * C("#e9dfc9")
            leaf = np.exp(-((u - 0.5) ** 2 / 0.05 + (v - 0.5) ** 2 / 0.12))
            vein = (np.abs(np.sin((u - 0.5) * 30 + v * 4)) > 0.6) * 1.0
            c = over(c, C("#4e6b3a") * (0.8 + 0.2 * vein[..., None]), np.clip(leaf * 2 - 0.5, 0, 1))
            return c, np.ones(u.shape)
        room.billboard(4.95, 0.4, 1.4, 1.1, 2.3, poster)
        room.billboard(4.9, -2.0, -0.4, 1.6, 2.4, lambda u, v: (lerp(C("#1d1b19"), C("#2c2925"), v) * np.ones(u.shape + (1,)), np.ones(u.shape)))  # tablero menú
        room.billboard(3.7, -1.4, -0.8, 1.08, 1.5, lambda u, v: (lerp(C("#3c3f42"), C("#a7adb1"), (v > 0.3) * 1.0), np.ones(u.shape)))
        room.billboard(3.9, -1.1, -0.5, 0.6, 1.8, person_fn("#a7745a", "#2d2d2f"))
        room.billboard(3.6, -2.2, 0.6, 0.0, 1.05, lambda u, v: (planks(u * 3, v, 8, 7, C("#6b4127")) * (0.7 + 0.3 * v[..., None]), np.ones(u.shape)))
        room.billboard(3.55, -2.2, 0.6, 1.02, 1.08, solid("#2b2420"))
        room.billboard(1.6, 0.3, 0.75, 0.3, 1.35, person_fn("#7d5640", "#7b4a3a"))
        room.billboard(1.5, -0.1, 1.3, 0.72, 0.78, solid("#5a3a22"))
        room.billboard(1.52, 0.56, 0.64, 0.0, 0.72, solid("#222222"))
        room.billboard(2.4, 1.0, 2.0, 0.0, 1.8, plant_fn(3))
        room.billboard(0.6, -2.0, -0.9, 0.0, 1.3, plant_fn(5))
        for (lx, ly, lz, k) in lamps:
            room.billboard(lz, lx - 0.18, lx + 0.18, ly - 0.16, ly + 0.5,
                           lambda u, v: (np.where((v > 0.35)[..., None], C("#111111"), C("#1a1a1a")) * np.ones(u.shape + (1,)),
                                         ((((u - 0.5) ** 2 / 0.25 + (v / 0.35) ** 2 < 1) & (v < 0.35)) |
                                          ((np.abs(u - 0.5) < 0.03) & (v >= 0.3))).astype(float)))
        light = room.light(lamps, amb=0.45, falloff=0.06)
    elif kind == "panaderia":
        wall = lerp(C("#e6d7b8"), C("#d4c19c"), n)
        chk = ((np.floor(X * 3) + np.floor(Z * 3)) % 2)
        col = np.where((s == 3)[..., None], lerp(C("#9c4a33"), C("#c27a5c"), chk[..., None] * 0.6), wall)
        col = np.where((s == 4)[..., None], C("#efe9dd"), col)
        room.col = col
        lamps = [(-0.8, 3.0, 1.5, 1.4), (0.8, 3.0, 2.5, 1.4), (0, 3.0, 4.2, 1.3)]

        def bread_shelf(u, v):
            r = np.random.default_rng(11)
            c = planks(u * 6, v, 4, 11, C("#7a4e2c")) * 0.7
            rows = 4
            vr = (v * rows) % 1.0
            ri = np.clip(np.floor(v * rows).astype(int), 0, rows)
            board = vr < 0.08
            cnt = 9
            ui = (u * cnt) % 1.0
            ci = np.clip(np.floor(u * cnt).astype(int), 0, cnt)
            tone = r.random((rows + 1, cnt + 1))[ri, ci]
            loaf = ((ui - 0.5) / 0.45) ** 2 + ((vr - 0.3) / (0.2 + tone * 0.08)) ** 2 < 1
            hi = np.clip(1 - np.abs(vr - 0.4) * 4, 0, 1)
            bc = lerp(C("#d29a4a"), C("#8a4f20"), tone) * (0.75 + 0.45 * hi)[..., None]
            c = np.where((loaf & ~board)[..., None], bc, c)
            c = np.where(board[..., None], C("#9a6a3c"), c)
            return c, np.ones(u.shape)
        room.billboard(4.9, -2.3, 2.3, 0.3, 2.4, bread_shelf)

        def counter(u, v):
            c = np.ones(u.shape + (3,)) * C("#e8e3d9")
            gz = (v > 0.45) & (v < 0.95)
            c = np.where(gz[..., None], lerp(C("#cfc3a8"), C("#e6dccb"), v[..., None]), c)
            it1 = gz & (((u * 14) % 1 - 0.5) ** 2 / 0.16 + ((v - 0.6) / 0.09) ** 2 < 1)
            it2 = gz & (((u * 11 + 0.5) % 1 - 0.5) ** 2 / 0.16 + ((v - 0.8) / 0.07) ** 2 < 1)
            c = np.where(it1[..., None], C("#d9a85a"), c)
            c = np.where(it2[..., None], C("#b06a32"), c)
            c = np.where((v > 0.95)[..., None], C("#bfc2c3"), c)
            return c, np.ones(u.shape)
        room.billboard(3.5, 0.1, 0.7, 0.2, 1.78, person_fn("#9a6a50", "#f1eee8", cap="#f8f8f6"))
        room.billboard(2.6, -1.9, 1.3, 0.0, 1.1, counter)
        room.billboard(1.4, 1.2, 2.0, 0.0, 1.2, plant_fn(9))
        light = room.light(lamps, amb=0.55, falloff=0.05)
    elif kind == "drogueria":
        tiles = 0.85 + 0.15 * (((np.floor(X * 2.5) + np.floor(Z * 2.5)) % 2))
        col = np.where((s == 3)[..., None], C("#d8d9d6") * tiles[..., None], np.ones(X.shape + (3,)) * C("#eef0ee"))
        col = np.where((s == 4)[..., None], C("#f5f6f5"), col)
        room.col = col
        lamps = [(-1.0, 3.1, 1.5, 1.8), (1.0, 3.1, 1.5, 1.8), (0, 3.1, 3.5, 1.8)]

        def shelf(u, v):
            r = np.random.default_rng(21)
            rows = 6
            vr = (v * rows) % 1.0
            ri = np.clip(np.floor(v * rows).astype(int), 0, rows)
            c = np.ones(u.shape + (3,)) * C("#f4f4f2")
            board = vr < 0.07
            cnt = 22
            ci = np.clip(np.floor(u * cnt).astype(int), 0, cnt)
            ui = (u * cnt) % 1.0
            pal = np.array([hex2rgb(h) for h in ["#ffffff", "#e9eef5", "#2f6db5", "#d33d3d", "#f0c330",
                                                 "#3fa067", "#f6f6f6", "#8bb7e0", "#f08a3a", "#ececec"]])
            pick = r.integers(0, len(pal), (rows + 1, cnt + 1))
            hgt = r.uniform(0.45, 0.85, (rows + 1, cnt + 1))
            box = (ui > 0.08) & (ui < 0.92) & (vr > 0.07) & (vr < 0.07 + hgt[ri, ci])
            bc = pal[pick[ri, ci]]
            band = (vr > 0.25) & (vr < 0.35)
            bc = np.where(band[..., None], bc * 0.75, bc)
            c = np.where(box[..., None], bc, c)
            c = np.where(board[..., None], C("#d9dad8"), c)
            return c, np.ones(u.shape)
        room.billboard(4.9, -2.3, 2.3, 0.0, 2.3, shelf)

        def cross(u, v):
            cr = ((np.abs(u - 0.5) < 0.17) & (np.abs(v - 0.5) < 0.45)) | ((np.abs(v - 0.5) < 0.17) & (np.abs(u - 0.5) < 0.45))
            return np.ones(u.shape + (3,)) * C("#1fae4f"), cr.astype(float)
        room.billboard(4.85, -0.35, 0.35, 2.35, 3.05, cross)
        room.billboard(3.2, -0.9, -0.3, 0.2, 1.75, person_fn("#b68166", "#fafafa", hair="#2a1d16"))
        room.billboard(2.4, -1.7, 1.7, 0.0, 1.0, lambda u, v: (lerp(C("#f2f2f0"), C("#b9bcbe"), (v > 0.92) * 1.0) * np.ones(u.shape + (1,)), np.ones(u.shape)))
        light = room.light(lamps, amb=0.7, falloff=0.03)
        emis_tint = C("#f1f6ff")
    else:  # tienda de barrio
        wall = lerp(C("#d9cf9a"), C("#c7b97c"), n)
        col = np.where((s == 3)[..., None], lerp(C("#6e6a63"), C("#8a857c"), n), wall)
        col = np.where((s == 4)[..., None], C("#e4dfcf"), col)
        room.col = col
        lamps = [(-0.6, 3.0, 2.0, 1.5), (0.8, 3.0, 3.5, 1.3)]

        def shelf(u, v):
            r = np.random.default_rng(31)
            rows = 5
            vr = (v * rows) % 1.0
            ri = np.clip(np.floor(v * rows).astype(int), 0, rows)
            c = np.ones(u.shape + (3,)) * C("#6d5a44")
            board = vr < 0.08
            cnt = 16
            ci = np.clip(np.floor(u * cnt).astype(int), 0, cnt)
            ui = (u * cnt) % 1.0
            pal = np.array([hex2rgb(h) for h in ["#d8262b", "#f5c400", "#1f5fb8", "#2d9a3f", "#f07c18",
                                                 "#7a2a8a", "#ffffff", "#c81e5a", "#1aa3c7", "#e8d26a", "#5b3a1e"]])
            pick = r.integers(0, len(pal), (rows + 1, cnt + 1))
            hgt = r.uniform(0.5, 0.88, (rows + 1, cnt + 1))
            wid = np.where(r.integers(0, 2, (rows + 1, cnt + 1))[ri, ci] == 0, 0.42, 0.3)
            box = (np.abs(ui - 0.5) < wid) & (vr > 0.08) & (vr < 0.08 + hgt[ri, ci])
            bc = pal[pick[ri, ci]]
            lab = (vr > 0.3) & (vr < 0.5)
            bc = np.where(lab[..., None], lerp(bc, np.ones(3), 0.45), bc)
            c = np.where(box[..., None], bc * (0.85 + 0.25 * (np.abs(ui - 0.5) < wid * 0.4))[..., None], c)
            c = np.where(board[..., None], C("#8b7457"), c)
            return c, np.ones(u.shape)
        room.billboard(4.9, -2.3, 2.3, 0.0, 2.6, shelf)

        def fridge(u, v):
            c = np.ones(u.shape + (3,)) * C("#c62b2b")
            door = (u > 0.08) & (u < 0.92) & (v > 0.12) & (v < 0.9)
            bottles = door & (((u * 8) % 1) > 0.25) & (((v * 5) % 1) < 0.7)
            c = np.where(door[..., None], C("#cfe3ea"), c)
            bp = lerp(C("#7a3a1e"), C("#2f7a3a"), (np.floor(u * 8) % 3 == 0) * 1.0)
            c = np.where(bottles[..., None], bp, c)
            return c, np.ones(u.shape)
        room.billboard(3.2, 1.2, 2.1, 0.0, 2.0, fridge)
        room.billboard(3.6, -0.6, -0.1, 0.2, 1.72, person_fn("#8d5d43", "#2f5d8a"))
        room.billboard(2.2, -2.0, 0.6, 0.0, 1.0, lambda u, v: (lerp(C("#7a5b3a"), C("#c8c5bd"), (v > 0.5) * 1.0) * np.ones(u.shape + (1,)), np.ones(u.shape)))

        def strips(u, v):
            cnt = 12
            ci = np.clip(np.floor(u * cnt).astype(int), 0, cnt)
            ui = (u * cnt) % 1.0
            on = (np.abs(ui - 0.5) < 0.16) & (v > 0.15 + 0.5 * ((ci * 7) % 5) / 5)
            pal = np.array([hex2rgb(h) for h in ["#f2b01e", "#e0322c", "#2f8f3f", "#f37321", "#1c62b0", "#c9a0dc", "#e44a8c", "#f2b01e"]])
            seg = ((v * 6) % 1.0) > 0.12
            cc = pal[ci % len(pal)] * (0.8 + 0.3 * ((v * 6) % 1.0))[..., None]
            return cc, (on & seg).astype(float)
        room.billboard(1.2, -1.8, 1.8, 1.9, 2.8, strips)
        room.billboard(1.0, -2.1, -1.2, 0.0, 0.55, lambda u, v: (C("#d8cdb0") * (0.85 + 0.15 * np.sin(u * 20))[..., None], np.ones(u.shape)))
        light = room.light(lamps, amb=0.5, falloff=0.05)

    inter = blur(room.col, 1.1)
    light = blur(light, 2)
    inter_day = inter * np.clip(light, 0, 1.4)[..., None] * 0.62
    inter_night = inter * np.clip(light, 0, 2.2)[..., None] * emis_tint * 0.75
    if kind == "drogueria":
        crossm = np.all(np.abs(room.col - C("#1fae4f")) < 0.02, axis=-1).astype(float)
        inter_night = inter_night + C("#20ff70") * blur(crossm, 1.5)[..., None] * 1.2

    full = np.zeros((S, S, 3))
    emis = np.zeros((S, S, 3))
    refl = blur(sky_reflection(gh, gw, seed + 50, bright=1.0, bop=0.35), 1.0)
    gyy = np.linspace(0, 1, gh)[:, None]
    fres = 0.22 + 0.18 * (1 - gyy)
    full[gy0:gy1, gx0:gx1] = inter_day * (1 - fres[..., None]) + refl * fres[..., None] * 0.7
    emis[gy0:gy1, gx0:gx1] = inter_night * (1 - fres[..., None] * 0.5)
    glass = rect_mask(S, S, gx0, gy0, gx1, gy1)
    door_left = rng.random() < 0.5
    door_x = gx0 + int(gw * (0.32 if door_left else 0.68))
    # vinilo en el vidrio grande (lado opuesto a la puerta)
    vin_txt = {"cafe": "café de origen", "panaderia": "pan caliente", "drogueria": "domicilios 24h",
               "tienda": "minutos · recargas"}[kind]
    vx0, vx1 = (door_x + 20, gx1 - 20) if door_left else (gx0 + 20, door_x - 20)
    vin = text_mask(S, S, vin_txt, "lora_i" if kind == "cafe" else "poppins_m", 30, box=(vx0, gy1 - 58, vx1, gy1 - 22))
    full = over(full, C("#f2f2ee"), vin * 0.85)
    emis = emis * (1 - vin[..., None] * 0.7)
    fcol = C("#1e1f21") if kind in ("cafe", "drogueria") else C("#9fa3a6")
    mull = rect_mask(S, S, door_x - 5, gy0, door_x + 5, gy1)
    ty = gy0 + int(gh * 0.12)
    trans = rect_mask(S, S, gx0, ty - 4, gx1, ty + 4)
    frame_m = np.clip((1 - glass) + mull + trans, 0, 1)
    shutter = rect_mask(S, S, 0, 0, S, top_h)
    ribs = 0.8 + 0.2 * (np.sin(yy * 2 * np.pi / 6) > 0)
    sn = noise(S, S, cells=8, octaves=5, seed=seed + 9)
    shut_col = C("#8c9092")[None, None, :] * ribs[..., None] * (0.85 + 0.25 * sn[..., None])
    rust = np.clip(sn - 0.6, 0, 1) * 2
    shut_col = lerp(shut_col, C("#6a5240"), rust * 0.3)
    zocalo = rect_mask(S, S, 0, zoc, S, S)
    gran = noise(S, S, cells=64, octaves=3, seed=seed + 13)
    zcol = lerp(C("#2b2b2c"), C("#5e5e62"), gran ** 1.5)
    zcol = zcol * (1 - 0.3 * ((xx % 128) < 2))[..., None]
    framecol = fcol[None, None, :] * (0.95 + 0.1 * sn[..., None])
    prof = frame_m * (1 - shutter) * (1 - zocalo)
    full = over(full, framecol, prof)
    full = over(full, shut_col, shutter)
    full = over(full, zcol, zocalo)
    # sombra bajo la caja de la cortina
    full = full * (1 - 0.35 * np.exp(-np.maximum(yy - top_h, 0) / 10) * (yy > top_h))[..., None]
    hx = door_x + 12 if door_left else door_x - 17
    handle = rect_mask(S, S, hx, gy0 + gh * 0.4, hx + 5, gy0 + gh * 0.68, soft=1)
    full = over(full, C("#b9bcbe"), handle)
    splash = np.clip(noise(S, S, cells=16, octaves=5, seed=seed + 17) - 0.35, 0, 1) * np.clip((yy - S * 0.75) / (S * 0.25), 0, 1)
    full = lerp(full, C("#6b6255"), splash * 0.5)
    drip_src = noise(S, S, cells=32, octaves=3, seed=seed + 19)
    drip_cols = np.clip(blur(drip_src, 1)[top_h:top_h + 1, :] - 0.5, 0, 1) * 4
    drip = drip_cols * np.exp(-np.maximum(yy - zoc, 0) / 25) * (yy > zoc)
    full = lerp(full, C("#3c3a36"), np.clip(drip, 0, 1) * 0.4)
    emis = emis * glass[..., None] * (1 - np.clip(mull + trans, 0, 1))[..., None]
    height = 0.2 * glass + 0.6 * prof + shutter * (0.7 + 0.08 * ribs) + zocalo * 0.65
    height = blur(height, 0.8) + handle * 0.3
    rough = glass * (0.05 + splash * 0.4) + prof * 0.4 + shutter * (0.5 + rust * 0.4) + zocalo * (0.25 + splash * 0.3)
    rough = rough * (1 - vin) + vin * 0.6
    metal = prof * 0.7 + shutter * (0.85 - rust * 0.7) + handle * 0.9
    return full, height, rough, metal, emis


def build_shopfronts():
    S = SHOP_CELL
    N = 2 * S
    A = np.zeros((N, N, 3)); H = np.zeros((N, N)); R = np.zeros((N, N)); M = np.zeros((N, N)); E = np.zeros((N, N, 3))
    for i, k in enumerate(SHOP_KINDS):
        r, c = divmod(i, 2)
        a, h, ro, me, em = shop_cell(k, 1000 + i * 37)
        sl = (slice(r * S, (r + 1) * S), slice(c * S, (c + 1) * S))
        A[sl] = a; H[sl] = h; R[sl] = ro; M[sl] = me; E[sl] = em
    ao = ao_from_height(H, radius=6, strength=1.3)
    save_pbr(OUT + "/shopfronts", np.clip(A, 0, 1), height=H, rough=np.clip(R, 0.03, 1), metal=np.clip(M, 0, 1), ao=ao,
             normal_strength=5.0, emission=np.clip(E, 0, 1))


# ============================================================ LETREROS
SIGN_CELL = 256
SIGN_BAND = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15]  # banda 2:1; el resto cuadradas


def rounded_rect(w, h, x0, y0, x1, y1, r):
    return draw_layer(w, h, lambda d, s: d.rounded_rectangle((x0 * s, y0 * s, x1 * s, y1 * s), r * s, fill=255))


def wear_mask(h, w, seed, amount=0.3, cells=16):
    """Desconchado de pintura: 1 = pintura perdida."""
    n = noise(h, w, cells=cells, octaves=5, seed=seed)
    n2 = noise(h, w, cells=cells * 4, octaves=3, seed=seed + 1)
    return np.clip((n * 0.7 + n2 * 0.3 - (1 - amount)) * 8, 0, 1)


def sign_band(kind, seed):
    """(rgb, alpha, height, rough, metal, emis) de 128x256."""
    W, Hh = 256, 128
    yy, xx = np.mgrid[0:Hh, 0:W].astype(np.float64)
    n = noise(Hh, W, cells=8, octaves=5, seed=seed)
    emis = np.zeros((Hh, W, 3))
    metal = np.zeros((Hh, W))
    style = kind["style"]
    if style == "painted":  # tabla de madera pintada a mano
        board = rounded_rect(W, Hh, 2, 6, W - 2, Hh - 6, 6)
        alpha = board
        grain = np.sin(yy * 0.9 + n * 12) * 0.5 + 0.5
        rgb = C(kind["bg"])[None, None, :] * (0.88 + 0.1 * grain[..., None] + 0.08 * n[..., None])
        inner = rounded_rect(W, Hh, 9, 13, W - 9, Hh - 13, 4)
        inner2 = rounded_rect(W, Hh, 12, 16, W - 12, Hh - 16, 3)
        rgb = over(rgb, C(kind["fg2"]), np.clip(inner - inner2, 0, 1))
        t1 = text_mask(W, Hh, kind["line1"], "poppins_b", 30, box=(26, 22, W - 26, 44))
        t2 = text_mask(W, Hh, kind["line2"], "script", 80, box=(20, 48, W - 20, 108))
        jit = noise(Hh, W, cells=32, octaves=3, seed=seed + 5)
        t1 = np.clip((t1 - 0.5 + (jit - 0.5) * 0.4) * 3 + 0.5, 0, 1)
        t2 = np.clip((t2 - 0.5 + (jit - 0.5) * 0.4) * 3 + 0.5, 0, 1)
        sh = np.roll(np.roll(t2, 2, 0), 2, 1)
        rgb = over(rgb, C("#1a1410"), sh * 0.5)
        rgb = over(rgb, C(kind["fg"]), t2)
        rgb = over(rgb, C(kind["fg2"]), t1)
        w = wear_mask(Hh, W, seed + 3, 0.28)
        rgb = lerp(rgb, C("#6b5136") * (0.8 + 0.3 * grain[..., None]), w * 0.85)
        dirt = np.clip(n - 0.5, 0, 1) * np.clip(yy / Hh, 0, 1)
        rgb = lerp(rgb, C("#3d3428"), dirt * 0.5)
        hgt = board * (0.5 + 0.05 * grain) + (t1 + t2) * 0.03 - w * 0.04
        rough = 0.75 - (t1 + t2) * 0.1 + w * 0.1
    elif style == "plate":  # placa metálica esmaltada con remaches
        board = rounded_rect(W, Hh, 3, 8, W - 3, Hh - 8, 3)
        alpha = board
        rgb = C(kind["bg"])[None, None, :] * (0.92 + 0.12 * n[..., None]) * np.ones((Hh, W, 1))
        edge = np.clip(board - rounded_rect(W, Hh, 8, 13, W - 8, Hh - 13, 2), 0, 1)
        rgb = over(rgb, C(kind["fg2"]), edge)
        t1 = text_mask(W, Hh, kind["line1"], "heros_cn", 30, box=(30, 20, W - 30, 46))
        t2 = text_mask(W, Hh, kind["line2"], "heros_cn", 56, box=(26, 52, W - 26, 106))
        rgb = over(rgb, C(kind["fg"]), np.clip(t1 + t2, 0, 1))
        riv = np.zeros((Hh, W))
        for (rx, ry) in [(16, 20), (W - 16, 20), (16, Hh - 20), (W - 16, Hh - 20)]:
            riv = np.maximum(riv, np.clip(1 - np.hypot(xx - rx, yy - ry) / 4.0, 0, 1))
        rivm = (riv > 0.05).astype(float)
        rgb = over(rgb, C("#b8b8b0") * (0.7 + 0.5 * riv)[..., None], rivm)
        rust = np.clip(noise(Hh, W, cells=24, octaves=5, seed=seed + 7) - 0.62, 0, 1) * 3
        streak = np.zeros((Hh, W))
        for rx in (16, W - 16):
            streak += np.exp(-((xx - rx) / 2.5) ** 2) * np.clip((yy - 20) / 70, 0, 1) * (yy > 20)
        rgb = lerp(rgb, C("#7a3f1d"), np.clip(rust + streak * 0.5, 0, 1) * 0.7)
        chip = wear_mask(Hh, W, seed + 9, 0.18, cells=24)
        rgb = lerp(rgb, C("#9a9a96"), chip * 0.8)
        hgt = board * 0.5 + edge * 0.1 + riv * 0.4 + (t1 + t2) * 0.02
        rough = 0.35 + rust * 0.5 + chip * 0.1
        metal = chip * 0.9 + rivm * 0.8
    elif style == "lightbox":  # caja de luz acrílica con marco de aluminio
        board = rounded_rect(W, Hh, 1, 6, W - 1, Hh - 6, 4)
        alpha = board
        face = rounded_rect(W, Hh, 7, 12, W - 7, Hh - 12, 2)
        frame = np.clip(board - face, 0, 1)
        glow = np.exp(-((yy - Hh / 2) / 50) ** 2) * 0.12
        rgb = C(kind["bg"])[None, None, :] * (0.95 + glow[..., None]) * np.ones((Hh, W, 1))
        rgb = over(rgb, C("#b5b8ba") * (0.9 + 0.15 * n[..., None]), frame)
        x_text = 18
        if kind.get("cross"):
            cr = ((np.abs(xx - 42) < 7) & (np.abs(yy - Hh / 2) < 24)) | ((np.abs(yy - Hh / 2) < 7) & (np.abs(xx - 42) < 24))
            rgb = over(rgb, C(kind["fg2"]), blur(cr.astype(float), 0.6))
            x_text = 74
        t1 = text_mask(W, Hh, kind["line1"], "poppins_b", 40, box=(x_text, 22, W - 16, 62))
        t2 = text_mask(W, Hh, kind["line2"], "poppins_m", 34, box=(x_text, 66, W - 16, 106))
        rgb = over(rgb, C(kind["fg"]), t1)
        rgb = over(rgb, C(kind["fg2"]), t2)
        dirt = np.clip((yy - Hh * 0.6) / (Hh * 0.4), 0, 1) * np.clip(n - 0.3, 0, 1)
        rgb = lerp(rgb, C("#6d6658"), dirt * 0.18)
        hgt = board * 0.4 + frame * 0.25
        rough = face * 0.22 + frame * 0.45
        metal = frame * 0.85
        emis = rgb * face[..., None] * (1 - dirt[..., None] * 0.3) * (0.8 + glow[..., None] * 2)
    elif style == "letters":  # placa oscura con letras de bronce retroiluminadas
        board = rounded_rect(W, Hh, 4, 10, W - 4, Hh - 10, 2)
        alpha = board
        rgb = C(kind["bg"])[None, None, :] * (0.9 + 0.15 * n[..., None]) * np.ones((Hh, W, 1))
        t1 = text_mask(W, Hh, kind["line1"], "lora", 56, box=(16, 20, W - 16, 78))
        t2 = text_mask(W, Hh, kind["line2"], "poppins_l", 16, box=(36, 86, W - 36, 104))
        halo = blur(t1, 5)
        rgb = over(rgb, C("#5a4630"), np.clip(halo * 1.3 - t1, 0, 1) * 0.4)
        brass = lerp(C("#a07a3c"), C("#d7b46a"), np.clip(1 - (yy - 30) / 40, 0, 1))
        rgb = over(rgb, brass, t1)
        rgb = over(rgb, C("#cdb886"), t2)
        hgt = board * 0.4 + t1 * 0.5 + t2 * 0.05
        rough = 0.6 - t1 * 0.35
        metal = t1 * 0.95
        emis = C("#ffb35a")[None, None, :] * np.clip(halo * 1.6 - t1, 0, 1)[..., None] * 0.9 + C("#cdb886") * t2[..., None] * 0.2
    else:  # barber
        board = rounded_rect(W, Hh, 2, 8, W - 2, Hh - 8, 10)
        alpha = board
        rgb = C("#111214")[None, None, :] * (0.9 + 0.15 * n[..., None]) * np.ones((Hh, W, 1))
        poles = np.zeros((Hh, W))
        for x0 in (12, W - 34):
            pole = rect_mask(Hh, W, x0, 18, x0 + 22, Hh - 18, soft=1)
            stripes = ((xx + yy * 0.8) % 18) < 9
            sc = np.where(stripes[..., None], C("#c42a2a"), C("#f2f2f2"))
            sc = np.where((((xx + yy * 0.8) % 36) < 9)[..., None], C("#244c9a"), sc)
            cyl = 0.7 + 0.45 * np.sin(np.clip((xx - x0) / 22, 0, 1) * np.pi)
            rgb = over(rgb, sc * cyl[..., None], pole)
            poles = np.maximum(poles, pole)
        t1 = text_mask(W, Hh, "BARBERÍA", "poppins_l", 22, box=(44, 22, W - 44, 42))
        t2 = text_mask(W, Hh, "Andro", "schola_b", 64, box=(44, 46, W - 44, 106))
        rgb = over(rgb, C("#e9e4d8"), t1)
        rgb = over(rgb, C("#d6ae5c"), t2)
        hgt = board * 0.4 + t2 * 0.05 + poles * 0.3
        rough = 0.45 - t2 * 0.2 - poles * 0.25
        metal = t2 * 0.8
        emis = C("#ffffff") * t1[..., None] * 0.6 + C("#ffcf80") * t2[..., None] * 0.5 + rgb * poles[..., None] * 0.6
    return rgb, alpha, hgt, rough, metal, emis


SIGN_KINDS = [
    {"style": "painted", "bg": "#5b3a22", "fg": "#f4e3b5", "fg2": "#e3a63d", "line1": "PANADERÍA", "line2": "La Esquina"},
    {"style": "lightbox", "bg": "#fbfbf8", "fg": "#1b7f3c", "fg2": "#1fae4f", "line1": "DROGUERÍA", "line2": "Boston", "cross": True},
    {"style": "plate", "bg": "#c8201f", "fg": "#ffd21c", "fg2": "#f4f1e8", "line1": "TIENDA", "line2": "DON CHEPE"},
    {"style": "letters", "bg": "#1f1b18", "line1": "Café Capiro", "line2": "CAFÉS ESPECIALES · BOSTON"},
    {"style": "plate", "bg": "#1d4f91", "fg": "#ffd21c", "fg2": "#f4f1e8", "line1": "FERRETERÍA", "line2": "EL TORNILLO"},
    {"style": "painted", "bg": "#f1e6d0", "fg": "#a3242e", "fg2": "#2f5a35", "line1": "RESTAURANTE", "line2": "Doña Rosa"},
    {"style": "barber"},
    {"style": "lightbox", "bg": "#b51d24", "fg": "#ffffff", "fg2": "#ffd34a", "line1": "LICORERA", "line2": "La 55"},
    {"style": "lightbox", "bg": "#f5f7fb", "fg": "#1d4f91", "fg2": "#d23a2a", "line1": "PAPELERÍA", "line2": "Córdova"},
    {"style": "painted", "bg": "#f6c9d3", "fg": "#c21f6b", "fg2": "#c7861a", "line1": "HELADERÍA", "line2": "Guayacán"},
]


def round_sign(seed, bg, fg, mono, sub, fmono="lora"):
    S = SIGN_CELL
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    cx, cy, R = S / 2, S / 2 + 12, 108
    disc = draw_layer(S, S, lambda d, s: d.ellipse(((cx - R) * s, (cy - R) * s, (cx + R) * s, (cy + R) * s), fill=255))
    inner = draw_layer(S, S, lambda d, s: d.ellipse(((cx - R + 5) * s, (cy - R + 5) * s, (cx + R - 5) * s, (cy + R - 5) * s), fill=255))
    rim = np.clip(disc - inner, 0, 1)
    ring = draw_layer(S, S, lambda d, s: d.ellipse(((cx - R + 16) * s, (cy - R + 16) * s, (cx + R - 16) * s, (cy + R - 16) * s), outline=255, width=int(2 * s)))
    hook = draw_layer(S, S, lambda d, s: d.ellipse(((cx - 9) * s, (cy - R - 14) * s, (cx + 9) * s, (cy - R + 4) * s), outline=255, width=int(3 * s)))
    n = noise(S, S, cells=8, octaves=5, seed=seed)
    rgb = C(bg)[None, None, :] * (0.93 + 0.1 * n[..., None]) * np.ones((S, S, 1))
    rgb = over(rgb, C("#8a8d90"), rim)
    rgb = over(rgb, C(fg), ring)
    tm = text_mask(S, S, mono, fmono, 96, box=(cx - 66, cy - 56, cx + 66, cy + 26))
    ts = text_mask(S, S, sub, "poppins_m", 14, box=(cx - 58, cy + 36, cx + 58, cy + 54))
    rgb = over(rgb, C(fg), np.clip(tm + ts, 0, 1))
    rgb = over(rgb, C("#5d6063"), hook)
    dirt = np.clip(n - 0.45, 0, 1) * np.clip(1 - (yy - (cy - R)) / (2 * R), 0, 1)
    streak = np.exp(-((xx - cx) / 5) ** 2) * np.clip(1 - (yy - (cy - R)) / 80, 0, 1) * (yy > cy - R)
    rgb = lerp(rgb, C("#6b6457"), np.clip(dirt * 0.6 + streak * 0.25, 0, 1))
    alpha = np.clip(disc + hook, 0, 1)
    hgt = disc * 0.5 + rim * 0.15 + (tm + ts) * 0.02
    rough = 0.5 * disc + 0.4 * rim + hook * 0.4
    metal = rim * 0.8 + hook * 0.8
    return rgb, alpha, hgt, rough, metal, np.zeros((S, S, 3))


def neon_sign(seed, text, col, fname="poppins_l", icon=None, band=False, border=False, col2=None):
    S = SIGN_CELL
    W, Hh = S, (128 if band else S)
    yy, xx = np.mgrid[0:Hh, 0:W].astype(np.float64)
    n = noise(Hh, W, cells=8, octaves=4, seed=seed)
    plate = rounded_rect(W, Hh, 4, 4, W - 4, Hh - 4, 14)
    rgb = C("#121315")[None, None, :] * (0.9 + 0.2 * n[..., None]) * np.ones((Hh, W, 1))
    sep = np.zeros((Hh, W))
    for (sx, sy) in [(16, 16), (W - 16, 16), (16, Hh - 16), (W - 16, Hh - 16)]:
        sep = np.maximum(sep, np.clip(1 - np.hypot(xx - sx, yy - sy) / 5, 0, 1))
    tube2 = np.zeros((Hh, W))
    if band:
        tube = text_mask(W, Hh, text, fname, 64, box=(28, 26, W - 28, Hh - 26))
    else:
        tube = text_mask(W, Hh, text, fname, 84, box=(26, 146, W - 26, 226) if icon else (24, 70, W - 24, 186))
    lw = lambda s: int(4 * s)  # noqa: E731
    if icon == "cup":
        tube2 = draw_layer(W, Hh, lambda d, s: (
            d.rounded_rectangle((84 * s, 66 * s, 160 * s, 128 * s), 14 * s, outline=255, width=lw(s)),
            d.arc((146 * s, 78 * s, 182 * s, 112 * s), -90, 90, fill=255, width=lw(s)),
            d.arc((100 * s, 26 * s, 120 * s, 58 * s), 90, 270, fill=255, width=lw(s)),
            d.arc((124 * s, 26 * s, 144 * s, 58 * s), 90, 270, fill=255, width=lw(s))))
    elif icon == "cocktail":
        tube2 = draw_layer(W, Hh, lambda d, s: (
            d.line([(72 * s, 36 * s), (184 * s, 36 * s), (128 * s, 96 * s), (72 * s, 36 * s)], fill=255, width=lw(s), joint="curve"),
            d.line([(128 * s, 96 * s), (128 * s, 128 * s)], fill=255, width=lw(s)),
            d.line([(102 * s, 130 * s), (154 * s, 130 * s)], fill=255, width=lw(s)),
            d.ellipse((140 * s, 44 * s, 156 * s, 60 * s), outline=255, width=int(3 * s)),
            d.line([(156 * s, 18 * s), (118 * s, 72 * s)], fill=255, width=int(3 * s))))
    if border:
        bd = draw_layer(W, Hh, lambda d, s: d.rounded_rectangle((14 * s, 12 * s, (W - 14) * s, (Hh - 12) * s), 10 * s, outline=255, width=int(3 * s)))
        tube2 = np.maximum(tube2, bd)
    c1 = C(col)
    c2 = C(col2) if col2 else c1
    glow1 = blur(tube, 4) * 0.7 + blur(tube, 10) * 0.6
    glow2 = blur(tube2, 4) * 0.7 + blur(tube2, 10) * 0.6
    rgb = rgb + (c1 * glow1[..., None] + c2 * glow2[..., None]) * 0.06
    rgb = over(rgb, lerp(np.ones(3) * 0.85, c2, 0.45), tube2)
    rgb = over(rgb, lerp(np.ones(3) * 0.85, c1, 0.45), tube)
    sepm = (sep > 0.05).astype(float)
    rgb = over(rgb, C("#9b9ea2") * (0.7 + 0.5 * sep)[..., None], sepm)
    alltube = np.clip(tube + tube2, 0, 1)
    hgt = plate * 0.3 + alltube * 0.6 + sep * 0.5
    rough = np.where(alltube > 0.3, 0.1, 0.25 * plate)
    metal = sepm * 0.9
    emis = lerp(c1, np.ones(3), 0.55) * tube[..., None] + c1 * np.clip(glow1, 0, 1)[..., None] * 0.9
    emis = emis + lerp(c2, np.ones(3), 0.55) * tube2[..., None] + c2 * np.clip(glow2, 0, 1)[..., None] * 0.9
    emis = np.clip(emis, 0, 1) * plate[..., None]
    return rgb, plate, hgt, rough, metal, emis


def build_signs():
    S = SIGN_CELL
    N = 4 * S
    A = np.zeros((N, N, 3)); AL = np.zeros((N, N)); H = np.zeros((N, N)); R = np.full((N, N), 0.8)
    M = np.zeros((N, N)); E = np.zeros((N, N, 3))
    cells = {}
    for i, k in enumerate(SIGN_KINDS):
        cells[i] = ("band",) + sign_band(k, 2000 + i * 13)
    cells[10] = ("full",) + round_sign(2101, "#f7f6f2", "#1c1c1c", "Ak", "· PASTELERÍA ·", "lora")
    cells[11] = ("full",) + round_sign(2102, "#1d1f1c", "#d3b16b", "Mz", "MERCADO · ZONA", "schola_b")
    cells[12] = ("full",) + neon_sign(2103, "Café", "#2ee6ff", fname="script", icon="cup")
    cells[13] = ("full",) + neon_sign(2104, "Bar", "#ff2ebd", fname="script", icon="cocktail")
    cells[14] = ("full",) + neon_sign(2105, "24 H", "#ffae2e", fname="poppins_l", border=True)
    cells[15] = ("band",) + neon_sign(2106, "ABIERTO", "#ff2a2a", fname="poppins_m", band=True, border=True, col2="#2a7dff")
    for i, (mode, rgb, al, h, ro, me, em) in cells.items():
        r, c = divmod(i, 4)
        y0 = r * S + (64 if mode == "band" else 0)
        hh = rgb.shape[0]
        sl = (slice(y0, y0 + hh), slice(c * S, (c + 1) * S))
        A[sl] = rgb; AL[sl] = al; H[sl] = h * al; R[sl] = np.where(al > 0, ro, 0.8)
        M[sl] = me * al; E[sl] = em * al[..., None]
    # dilatar color bajo alpha=0 para evitar halos oscuros en los mipmaps
    filled = AL > 0.5
    idx = ndimage.distance_transform_edt(~filled, return_distances=False, return_indices=True)
    A = A[idx[0], idx[1]]
    ao = ao_from_height(H, radius=4, strength=1.2)
    save_pbr(OUT + "/signs", np.clip(A, 0, 1), height=H, rough=np.clip(R, 0.05, 1), metal=np.clip(M, 0, 1), ao=ao,
             normal_strength=4.0, emission=np.clip(E, 0, 1))
    _rgba(OUT + "/signs_albedo.png", A, AL)


# ============================================================ TOLDOS (tileables)
def awning(name, stripes, seed):
    S = 512  # = 1.5 m
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    weave = (np.sin(xx * np.pi / 2.0) * np.sin(yy * np.pi / 2.0)) * 0.5 + 0.5
    n_macro = fbm(S, base_cells=2, octaves=5, seed=seed)
    n_meso = fbm(S, base_cells=8, octaves=5, seed=seed + 1)
    n_micro = fbm(S, base_cells=64, octaves=2, seed=seed + 2)
    if stripes:
        # 8 franjas por tile (18.75 cm), a lo largo de la caída del toldo (eje V)
        k = (xx / S * 8) % 2
        fr = (xx / S * 8) % 1
        soft = np.clip(1 - np.minimum(fr, 1 - fr) * 120, 0, 1)
        c1, c2 = C("#1f5e3c"), C("#ece6d6")
        base = np.where((k < 1)[..., None], c1, c2)
        base = lerp(base, (c1 + c2) / 2, soft * 0.6)
    else:
        base = np.ones((S, S, 3)) * C("#d9d2c2")  # ecru claro: tintar con "tint" en Godot
    faded = lerp(base, C("#e2ddd0"), np.clip(n_macro - 0.35, 0, 1) * 0.55)
    stains = np.clip(fbm(S, base_cells=6, octaves=6, seed=seed + 3) - 0.62, 0, 1) * 4
    stains = blur_wrap(stains, 3)
    ring = np.clip(1 - np.abs(stains - 0.3) * 6, 0, 1) * (stains > 0.05)
    col = faded * (0.9 + 0.12 * n_meso[..., None]) * (0.96 + 0.05 * weave[..., None]) * (0.96 + 0.06 * n_micro[..., None])
    col = lerp(col, C("#5e584c"), np.clip(stains, 0, 1) * 0.12 + ring * 0.06)
    # escurrimientos verticales (tileable: perfil por columna periódico x modulación fbm)
    sv = fbm(S, base_cells=4, octaves=4, seed=seed + 4)
    streak_src = fbm(S, base_cells=32, octaves=2, seed=seed + 5)
    prof = np.clip(np.mean(streak_src, axis=0, keepdims=True) - 0.5, 0, 1) * 10
    streaks = blur_wrap(prof * np.ones((S, 1)) * (0.4 + 0.6 * sv), 1.5)
    col = lerp(col, C("#4a463d"), np.clip(streaks, 0, 1) * 0.3)
    seam = blur_wrap((np.abs(xx - S / 2) < 1.5).astype(float), 1.0)  # costura de paños (cada 1.5 m)
    col = col * (1 - seam[..., None] * 0.15)
    height = weave * 0.15 + n_meso * 0.25 + n_macro * 0.4 - seam * 0.3
    rough = 0.82 + 0.1 * n_micro - np.clip(stains, 0, 1) * 0.05
    save_pbr(OUT + "/" + name, np.clip(col, 0, 1), height=height, rough=np.clip(rough, 0, 1), metal=0.0,
             normal_strength=2.5)


# ============================================================ main
def main():
    only = sys.argv[1:] or ["windows", "shopfronts", "signs", "awnings"]
    if "windows" in only:
        build_windows()
    if "shopfronts" in only:
        build_shopfronts()
    if "signs" in only:
        build_signs()
    if "awnings" in only:
        awning("awning_stripes", True, 3001)
        awning("awning_plain", False, 3002)
    for nm in ["windows", "shopfronts", "signs", "awning_stripes", "awning_plain"]:
        if os.path.exists(os.path.join(ROOT, OUT, nm + "_albedo.png")):
            preview(OUT + "/" + nm, f"{TMP}/{nm}_preview.png")
    base = os.path.join(ROOT, OUT)
    sheet = [f"{base}/windows_albedo.png", f"{base}/windows_emission.png", f"{base}/shopfronts_albedo.png",
             f"{base}/shopfronts_emission.png", f"{base}/signs_albedo.png", f"{base}/signs_emission.png",
             f"{TMP}/awning_stripes_preview.png", f"{TMP}/awning_plain_preview.png"]
    if all(os.path.exists(p) for p in sheet):
        contact_sheet(sheet, f"{TMP}/contact.png", cell=512)


if __name__ == "__main__":
    main()

"""Botones táctiles de piedra/plastilina para el modo plastilina (ui/clay/*.png).

disc.png  botón redondo: borde levantado, centro algo hundido, piedra moteada cálida.
dpad.png  base del joystick: disco grande con cuenca central y 4 flechas doradas.
knob.png  perilla del joystick (se dibuja encima y se mueve con el dedo).
Uso:  python3 -I tools/texgen/ui_clay.py  (desde godot3d/)
"""
import os
import numpy as np
from PIL import Image

rng = np.random.default_rng(42)
S = 512
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
cx = cy = (S - 1) / 2
dx, dy = (xx - cx) / (S * 0.5), (yy - cy) / (S * 0.5)
R = np.sqrt(dx * dx + dy * dy)
ANG = np.arctan2(dy, dx)
L = np.array([-0.55, -0.65, 0.52])
L /= np.linalg.norm(L)


def blur_noise(scale, octaves=3):
    out = np.zeros((S, S), np.float32)
    for o in range(octaves):
        n = rng.standard_normal((S // (scale >> o) + 2, S // (scale >> o) + 2)).astype(np.float32)
        im = Image.fromarray(((n - n.min()) / (np.ptp(n) + 1e-6) * 255).astype(np.uint8))
        im = im.resize((S, S), Image.BICUBIC)
        out += (np.asarray(im, np.float32) / 255 - 0.5) / (2 ** o)
    return out


def shade(h, k=6.0):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * k * S / 64
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * k * S / 64
    nz = 1 / np.sqrt(gx * gx + gy * gy + 1)
    n = np.stack([-gx * nz, -gy * nz, nz], -1)
    return np.clip(n @ L, 0, 1)


def stone_base(r_out=0.92):
    mott = blur_noise(64) * 0.6 + blur_noise(16) * 0.25
    base = np.stack([0.52 + 0.06 * mott, 0.45 + 0.05 * mott, 0.36 + 0.045 * mott], -1)
    speck = (rng.random((S, S)) < 0.004).astype(np.float32)
    base -= speck[..., None] * 0.12
    # altura: domo suave + borde levantado + centro hundido + grumos de amasado
    h = np.clip(1 - (R / r_out) ** 6, 0, 1) * 0.6
    h += 0.25 * np.exp(-((R - r_out * 0.86) ** 2) / 0.004)
    h -= 0.12 * np.clip(1 - (R / (r_out * 0.72)) ** 4, 0, 1)
    h += 0.03 * blur_noise(32)
    return base, h


def finish(rgb, h, r_out, alpha_extra=None):
    lit = 0.55 + 0.75 * shade(h)
    col = np.clip(rgb * lit[..., None], 0, 1)
    edge = np.clip((r_out - R) * S * 0.5, 0, 1)
    # contorno oscuro y sombra suave debajo
    rim = np.exp(-((R - r_out) ** 2) / 0.0004)
    col = col * (1 - 0.6 * rim[..., None]) + np.array([0.12, 0.08, 0.07]) * 0.6 * rim[..., None]
    shadow = np.clip(1 - (np.sqrt(dx * dx + (dy - 0.04) ** 2) - r_out) / 0.07, 0, 1) * 0.45
    a = np.maximum(edge, shadow * (1 - edge))
    col = col * edge[..., None]
    out = np.concatenate([col / np.maximum(a, 1e-4)[..., None], a[..., None]], -1)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def tri_mask(cxr, cyr, ang, size):
    """Triángulo equilátero apuntando hacia afuera (ang), centro en (cxr, cyr)."""
    px, py = dx - cxr, dy - cyr
    ca, sa = np.cos(ang), np.sin(ang)
    u = px * ca + py * sa            # hacia la punta
    v = -px * sa + py * ca
    inside = (u > -size * 0.5) & (np.abs(v) < (size * 0.62 - u) * 0.62)
    dist = np.minimum.reduce([u + size * 0.5, (size * 0.62 - u) * 0.62 - np.abs(v)])
    return inside, dist


os.makedirs("ui/clay", exist_ok=True)

# botón
base, h = stone_base(0.92)
finish(base, h, 0.92).save("ui/clay/disc.png")

# base del joystick con flechas doradas
base, h = stone_base(0.94)
h -= 0.22 * np.clip(1 - (R / 0.46) ** 6, 0, 1)            # cuenca para la perilla
h += 0.08 * np.exp(-((R - 0.47) ** 2) / 0.0012)
gold = np.array([0.93, 0.78, 0.47])
for k, ang in enumerate([-np.pi / 2, 0, np.pi / 2, np.pi]):
    m, dist = tri_mask(0.7 * np.cos(ang), 0.7 * np.sin(ang), ang, 0.2)
    bevel = np.clip(dist / 0.03, 0, 1)
    h += m * (0.1 * bevel)
    out_line = (~m) & (np.abs(dist) < 0.016)
    base = np.where(m[..., None], gold * (0.85 + 0.15 * bevel[..., None]), base)
    base = np.where(out_line[..., None], base * 0.45, base)
finish(base, h, 0.94).save("ui/clay/dpad.png")

# perilla
base, h = stone_base(0.9)
h = np.clip(1 - (R / 0.9) ** 2, 0, 1) ** 0.5 * 0.9 + 0.03 * blur_noise(32)
h -= 0.08 * np.exp(-(R ** 2) / 0.12)
finish(base * 1.05, h, 0.9).save("ui/clay/knob.png")
print("ok")

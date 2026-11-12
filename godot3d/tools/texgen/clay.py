"""Textura de plastilina (estilo stop-motion) para el modo "plastilina".

Genera art/tex/clay/clay_detail.png (1024², repetible):
  R, G = normal tangente XY codificada 0..1 (Y+, OpenGL)
  B    = altura 0..1 (0.5 = plano). El shader la usa para oscurecer surcos.
Contenido: grumos grandes de amasado, presiones de pulgar (hundimiento con borde
levantado), huellas dactilares (crestas concéntricas dentro de algunas presiones),
marcas de espátula y un grano fino de poro. Todo envuelve (toroidal): sin costuras.

Uso:  python3 -I tools/texgen/clay.py  (desde godot3d/)
"""
import os
import numpy as np
from PIL import Image

N = 1024
rng = np.random.default_rng(1974)
yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)


def band_noise(lo, hi, power=1.0):
    """Ruido periódico filtrado en frecuencia (lo..hi ciclos por tile)."""
    w = rng.standard_normal((N, N)).astype(np.float32)
    f = np.fft.fft2(w)
    fy = np.fft.fftfreq(N)[:, None] * N
    fx = np.fft.fftfreq(N)[None, :] * N
    r = np.sqrt(fx * fx + fy * fy) + 1e-6
    mask = np.exp(-((np.log(r) - np.log((lo + hi) * 0.5)) ** 2) / (2 * 0.45 ** 2)) / r ** power
    out = np.real(np.fft.ifft2(f * mask)).astype(np.float32)
    out -= out.mean()
    return out / (np.abs(out).max() + 1e-6)


def wrap_d(a, c):
    d = a - c
    return (d + N / 2) % N - N / 2


h = np.zeros((N, N), np.float32)
# 1) grumos de amasado (baja frecuencia) + ondulación media
h += 0.55 * band_noise(2, 5, 0.3)
h += 0.25 * band_noise(8, 16, 0.2)

# 2) presiones de pulgar: elipses hundidas con borde levantado
for i in range(70):
    cx, cy = rng.uniform(0, N, 2)
    rx = rng.uniform(28, 70)
    ry = rx * rng.uniform(0.55, 0.9)
    ang = rng.uniform(0, np.pi)
    dx, dy = wrap_d(xx, cx), wrap_d(yy, cy)
    u = (dx * np.cos(ang) + dy * np.sin(ang)) / rx
    v = (-dx * np.sin(ang) + dy * np.cos(ang)) / ry
    d = np.sqrt(u * u + v * v)
    depth = rng.uniform(0.25, 0.6)
    dent = -depth * np.exp(-(d ** 2) * 1.6) + 0.35 * depth * np.exp(-((d - 1.05) ** 2) / 0.04)
    h += dent
    # 3) huella dactilar en ~40 % de las presiones: crestas elípticas concéntricas
    if rng.random() < 0.4:
        ridges = np.sin(d * rng.uniform(26, 34) + rng.uniform(0, 6.28) + 0.8 * np.sin(u * 3.0))
        h += 0.03 * ridges * np.exp(-(d ** 2) * 2.2) * np.clip((d - 0.25) / 0.3, 0, 1)

# 4) marcas de espátula: trazos rectos finos hundidos
for i in range(8):
    cx, cy = rng.uniform(0, N, 2)
    ang = rng.uniform(0, np.pi)
    length = rng.uniform(60, 180)
    dx, dy = wrap_d(xx, cx), wrap_d(yy, cy)
    along = dx * np.cos(ang) + dy * np.sin(ang)
    across = -dx * np.sin(ang) + dy * np.cos(ang)
    m = np.exp(-(across ** 2) / 30.0) * np.clip(1 - np.abs(along) / length, 0, 1) ** 0.5
    h -= 0.12 * m

# 5) poro fino
h += 0.035 * band_noise(90, 200, 0.0)

h = (h - h.min()) / (h.max() - h.min())

# normales desde la altura (gradiente periódico)
strength = 9.0
gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
nz = 1.0 / np.sqrt(gx * gx + gy * gy + 1.0)
nx = -gx * nz
ny = gy * nz          # Y+ (OpenGL): v crece hacia abajo en la imagen

img = np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, h], axis=-1)
img = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
out_dir = os.path.join("art", "tex", "clay")
os.makedirs(out_dir, exist_ok=True)
Image.fromarray(img, "RGB").save(os.path.join(out_dir, "clay_detail.png"), optimize=True)
print("ok", os.path.join(out_dir, "clay_detail.png"))

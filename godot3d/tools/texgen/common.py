"""Utilidades compartidas para generar texturas PBR procedurales y TILEABLES.

Solo numpy + PIL + scipy. Todas las funciones son deterministas con `seed`.
Convenciones de salida (Godot 4):
  <nombre>_albedo.png  sRGB, RGB
  <nombre>_normal.png  normal tangente, convención OpenGL (Y+ arriba), como espera Godot
  <nombre>_orm.png     R = oclusión (AO), G = rugosidad, B = metalicidad  (ORMMaterial3D)
  opcional <nombre>_emission.png
Ejemplo:
  from common import *
  h = fbm(1024, octaves=6, seed=3)
  save_pbr("art/tex/stone/granito", albedo, height=h, rough=r)
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))  # .../godot3d


# ----------------------------------------------------------------- ruido tileable
def _periodic_value_noise(size: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    """Ruido de valor periódico (tilea perfecto) con interpolación suave."""
    grid = rng.random((cells, cells))
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int)
    f = coords - i0
    f = f * f * f * (f * (f * 6 - 15) + 10)  # quintic
    i1 = (i0 + 1) % cells
    i0 = i0 % cells
    a = grid[np.ix_(i0, i0)]
    b = grid[np.ix_(i0, i1)]
    c = grid[np.ix_(i1, i0)]
    d = grid[np.ix_(i1, i1)]
    fy = f[:, None]
    fx = f[None, :]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size: int, base_cells: int = 4, octaves: int = 6, gain: float = 0.5,
        lacunarity: int = 2, seed: int = 0) -> np.ndarray:
    """Fractal Brownian motion tileable en [0,1]."""
    rng = np.random.default_rng(seed)
    out = np.zeros((size, size))
    amp, total, cells = 1.0, 0.0, base_cells
    for _ in range(octaves):
        if cells > size:
            break
        out += amp * _periodic_value_noise(size, cells, rng)
        total += amp
        amp *= gain
        cells *= lacunarity
    return normalize(out / total)


def ridged(size: int, base_cells: int = 4, octaves: int = 5, seed: int = 0) -> np.ndarray:
    n = fbm(size, base_cells, octaves, seed=seed)
    return normalize(1.0 - np.abs(n * 2 - 1))


def worley(size: int, points: int = 32, seed: int = 0, k: int = 1) -> tuple[np.ndarray, np.ndarray]:
    """Ruido celular tileable. Devuelve (distancia al k-ésimo punto normalizada, id de celda)."""
    rng = np.random.default_rng(seed)
    pts = rng.random((points, 2)) * size
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    best = np.full((k + 1, size, size), np.inf, dtype=np.float32)
    ids = np.zeros((size, size), dtype=np.int32)
    for idx, (py, px) in enumerate(pts):
        dy = np.abs(yy - py); dy = np.minimum(dy, size - dy)
        dx = np.abs(xx - px); dx = np.minimum(dx, size - dx)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < best[0]
        ids[closer] = idx
        stack = np.concatenate([best, d[None]], axis=0)
        stack.sort(axis=0)
        best = stack[: k + 1]
    return normalize(best[k - 1]), ids


def normalize(a: np.ndarray) -> np.ndarray:
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / (hi - lo + 1e-9)


def blur_wrap(a: np.ndarray, sigma: float) -> np.ndarray:
    """Desenfoque gaussiano que respeta el tileo."""
    if a.ndim == 3:
        return np.stack([ndimage.gaussian_filter(a[..., c], sigma, mode="wrap") for c in range(a.shape[2])], -1)
    return ndimage.gaussian_filter(a, sigma, mode="wrap")


def warp(a: np.ndarray, dx: np.ndarray, dy: np.ndarray, strength: float) -> np.ndarray:
    """Domain warp tileable: desplaza `a` según campos dx, dy en [0,1]."""
    size = a.shape[0]
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    sy = (yy + (dy - 0.5) * strength) % size
    sx = (xx + (dx - 0.5) * strength) % size
    if a.ndim == 3:
        return np.stack([ndimage.map_coordinates(a[..., c], [sy, sx], order=1, mode="grid-wrap") for c in range(a.shape[2])], -1)
    return ndimage.map_coordinates(a, [sy, sx], order=1, mode="grid-wrap")


# ----------------------------------------------------------------- color
def lerp(a, b, t):
    t = np.asarray(t)
    if t.ndim == 2:
        t = t[..., None]
    return np.asarray(a) * (1 - t) + np.asarray(b) * t


def gradient_map(t: np.ndarray, stops: list[tuple[float, tuple[float, float, float]]]) -> np.ndarray:
    """Mapa de gradiente: stops = [(pos, (r,g,b) en 0..1), ...] ordenados por pos."""
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=np.float64)
    out = np.stack([np.interp(t, pos, cols[:, c]) for c in range(3)], -1)
    return out


def hex2rgb(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# ----------------------------------------------------------------- mapas derivados
def height_to_normal(h: np.ndarray, strength: float = 4.0) -> np.ndarray:
    """Normal tangente OpenGL (Y+) desde altura [0,1], con bordes en wrap. Devuelve RGB [0,1]."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength          # OpenGL: +Y hacia arriba en la imagen
    nz = np.ones_like(h)
    n = np.stack([nx, ny, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def ao_from_height(h: np.ndarray, radius: float = 6.0, strength: float = 1.2) -> np.ndarray:
    """Oclusión aproximada: zonas más bajas que su entorno se oscurecen."""
    local = blur_wrap(h, radius)
    ao = 1.0 - np.clip((local - h) * strength * 4.0, 0, 1)
    return np.clip(ao, 0, 1)


# ----------------------------------------------------------------- guardar
def _to_img(a: np.ndarray) -> Image.Image:
    a = np.clip(a, 0, 1)
    if a.ndim == 2:
        return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "L")
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGB")


def save_pbr(rel_path: str, albedo: np.ndarray, height: np.ndarray | None = None,
             rough: np.ndarray | float = 0.8, metal: np.ndarray | float = 0.0,
             ao: np.ndarray | None = None, normal: np.ndarray | None = None,
             normal_strength: float = 4.0, emission: np.ndarray | None = None) -> dict:
    """Guarda el set PBR bajo godot3d/<rel_path>_*.png. Devuelve rutas res://."""
    base = os.path.join(ROOT, rel_path)
    os.makedirs(os.path.dirname(base), exist_ok=True)
    size = albedo.shape[0]
    if normal is None:
        normal = height_to_normal(height, normal_strength) if height is not None else np.dstack(
            [np.full((size, size), 0.5)] * 2 + [np.ones((size, size))])
    if ao is None:
        ao = ao_from_height(height) if height is not None else np.ones((size, size))
    r = np.broadcast_to(np.asarray(rough, dtype=np.float64), (size, size))
    m = np.broadcast_to(np.asarray(metal, dtype=np.float64), (size, size))
    _to_img(albedo).save(base + "_albedo.png", optimize=True)
    _to_img(normal).save(base + "_normal.png", optimize=True)
    _to_img(np.stack([ao, r, m], -1)).save(base + "_orm.png", optimize=True)
    out = {k: "res://" + rel_path + f"_{k}.png" for k in ("albedo", "normal", "orm")}
    if emission is not None:
        _to_img(emission).save(base + "_emission.png", optimize=True)
        out["emission"] = "res://" + rel_path + "_emission.png"
    return out


# ----------------------------------------------------------------- vista previa sin Godot
def preview(rel_path: str, out_png: str, tiles: int = 2, light=(-0.5, 0.6, 0.62)) -> None:
    """Render rápido: plano 2x2 tiles (prueba de costuras) + esfera con iluminación
    Lambert+especular usando albedo/normal/orm. Útil para iterar sin abrir Godot."""
    base = os.path.join(ROOT, rel_path)
    alb = np.asarray(Image.open(base + "_albedo.png").convert("RGB"), dtype=np.float64) / 255
    nor = np.asarray(Image.open(base + "_normal.png").convert("RGB"), dtype=np.float64) / 255 * 2 - 1
    orm = np.asarray(Image.open(base + "_orm.png").convert("RGB"), dtype=np.float64) / 255
    L = np.array(light, dtype=np.float64); L /= np.linalg.norm(L)
    alb_lin = alb ** 2.2

    def shade(a, n, o):
        ndl = np.clip((n * L).sum(-1), 0, 1)
        H = L + np.array([0, 0, 1.0]); H /= np.linalg.norm(H)
        spec = np.clip((n * H).sum(-1), 0, 1) ** (2 + (1 - o[..., 1]) * 120) * (1 - o[..., 1]) * 0.8
        c = a * (0.25 + 0.85 * ndl[..., None]) * o[..., 0:1] + spec[..., None]
        return np.clip(c, 0, 1) ** (1 / 2.2)

    flat = shade(np.tile(alb_lin, (tiles, tiles, 1)), np.tile(nor, (tiles, tiles, 1)), np.tile(orm, (tiles, tiles, 1)))
    S = flat.shape[0]
    flat_img = Image.fromarray((flat * 255).astype(np.uint8)).resize((768, 768))
    # esfera
    R = 384
    yy, xx = np.mgrid[-1:1:R * 2j, -1:1:R * 2j]
    mask = xx ** 2 + yy ** 2 <= 1
    zz = np.sqrt(np.clip(1 - xx ** 2 - yy ** 2, 0, 1))
    u = ((np.arctan2(xx, zz) / np.pi + 1) * 0.5 * 2 * alb.shape[1]).astype(int) % alb.shape[1]
    v = ((-yy * 0.5 + 0.5) * alb.shape[0]).astype(int) % alb.shape[0]
    a = alb_lin[v, u]; nt = nor[v, u]; o = orm[v, u]
    Nn = np.stack([xx, -yy, zz], -1)
    T = np.stack([zz, np.zeros_like(zz), -xx], -1); T /= np.linalg.norm(T, axis=-1, keepdims=True) + 1e-9
    B = np.cross(Nn, T)
    n_world = T * nt[..., 0:1] + B * nt[..., 1:2] * -1 + Nn * nt[..., 2:3]
    n_world = n_world * np.array([1, -1, 1])
    n_world /= np.linalg.norm(n_world, axis=-1, keepdims=True) + 1e-9
    sph = shade(a, n_world, o)
    sph[~mask] = 0.12
    canvas = Image.new("RGB", (768 * 2, 768), (30, 30, 30))
    canvas.paste(flat_img, (0, 0))
    canvas.paste(Image.fromarray((sph * 255).astype(np.uint8)), (768, 0))
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    canvas.save(out_png)


def contact_sheet(pngs: list[str], out_png: str, cell: int = 384) -> None:
    """Junta varias imágenes en una hoja de contacto (para revisar con la herramienta Read)."""
    imgs = [Image.open(p).convert("RGB") for p in pngs]
    cols = min(4, len(imgs))
    rows = (len(imgs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * cell), (20, 20, 20))
    for i, im in enumerate(imgs):
        im.thumbnail((cell, cell))
        sheet.paste(im, ((i % cols) * cell, (i // cols) * cell))
    sheet.save(out_png)

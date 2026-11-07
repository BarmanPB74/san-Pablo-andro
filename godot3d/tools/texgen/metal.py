"""Familia METAL (F1-08): metales, postes y señales.

Regenerar:  python3 tools/texgen/metal.py
Salida:     art/tex/metal/<nombre>_{albedo,normal,orm}.png

Sets y escala física:
  pintura_verde      512  tile 1 m   esmalte verde sobre hierro, gastado, con óxido (rejas del parque)
  galvanizado        512  tile 1 m   acero galvanizado de postes/semáforos/soportes de señal
  poste_concreto     512  UV cilíndrica: U = vuelta completa (~0.9 m de perímetro), V = 1.8 m de alto
  celosia            1024 tile 2 m   lámina de corte láser RGBA (alpha = metal), patrón geométrico-floral
  senales            1024 atlas 4x4 RGBA (celdas de 256 px), ver SIGNS más abajo
  pintura_amarilla   512  tile 1 m   pintura amarilla de tráfico sobre metal (bolardos)
  amarilla_rayado    512  tile 1 m   igual pero con rayado negro-amarillo a 45° (obstáculos)
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (ROOT, ao_from_height, blur_wrap, contact_sheet, fbm, gradient_map, height_to_normal,  # noqa: E402
                    hex2rgb, lerp, normalize, preview, save_pbr, warp, worley)

OUT = "art/tex/metal/"
DBG = "/tmp/f1_metal/"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
FONT_LB = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"


# ======================================================================= utilidades propias
def streak_down(mask: np.ndarray, length: int, decay: float = 0.93) -> np.ndarray:
    """Chorreado vertical tileable: cada píxel arrastra su valor hacia abajo (eje +fila)."""
    out = mask.copy()
    acc = mask.copy()
    for _ in range(length):
        acc = np.roll(acc, 1, axis=0) * decay
        out = np.maximum(out, acc)
    return out


def edt_wrap(mask: np.ndarray) -> np.ndarray:
    """Distancia euclídea (px) al borde de `mask` (True) respetando tileo."""
    big = np.tile(mask, (3, 3))
    d = ndimage.distance_transform_edt(big)
    s = mask.shape[0]
    return d[s:2 * s, s:2 * s]


def scratches(size: int, n: int, seed: int, max_len: float = 0.25, width: int = 1,
              vertical_bias: float = 0.0) -> np.ndarray:
    """Rayones finos tileables (dibujados en lienzo 3x y plegados)."""
    rng = np.random.default_rng(seed)
    big = Image.new("L", (size * 3, size * 3), 0)
    d = ImageDraw.Draw(big)
    for _ in range(n):
        x0, y0 = rng.random(2) * size + size
        ang = rng.random() * np.pi
        if vertical_bias > 0 and rng.random() < vertical_bias:
            ang = np.pi / 2 + rng.normal(0, 0.15)
        ln = rng.random() * max_len * size
        segs = 5
        pts = []
        for k in range(segs + 1):
            t = k / segs
            pts.append((x0 + np.cos(ang) * ln * t + rng.normal(0, 1.2),
                        y0 + np.sin(ang) * ln * t + rng.normal(0, 1.2)))
        d.line(pts, fill=int(120 + rng.random() * 135), width=width)
    a = np.asarray(big, dtype=np.float64) / 255
    out = np.zeros((size, size))
    for i in range(3):
        for j in range(3):
            out = np.maximum(out, a[i * size:(i + 1) * size, j * size:(j + 1) * size])
    return out


def mix(a, b, t):
    """lerp escalar para mapas 2D (common.lerp expande t a 3 canales)."""
    return a * (1 - t) + b * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def rust_colors(t: np.ndarray) -> np.ndarray:
    return gradient_map(t, [(0.0, hex2rgb("3a1f12")), (0.35, hex2rgb("6b3519")), (0.6, hex2rgb("8f4a1f")),
                            (0.85, hex2rgb("a8642c")), (1.0, hex2rgb("c08048"))])


def dilate_rgb(rgb: np.ndarray, alpha: np.ndarray, iters: int = 24) -> np.ndarray:
    """Rellena los píxeles transparentes con el color del borde (evita halos negros en mipmaps)."""
    rgb = rgb.copy()
    known = alpha > 0.5
    for _ in range(iters):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(known.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * k[..., None]
            cnt += k
        grow = (~known) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        known = known | grow
    rgb[~known] = rgb[known].mean(0)
    return rgb


def save_rgba_albedo(rel: str, rgb: np.ndarray, alpha: np.ndarray) -> None:
    a = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(ROOT, rel + "_albedo.png"),
                                                                   optimize=True)


# ======================================================================= 1. pintura verde
def pintura_verde() -> str:
    S = 512
    name = OUT + "pintura_verde"
    # campos base
    macro = fbm(S, 2, 5, seed=101)
    meso = fbm(S, 8, 5, seed=102)
    micro = fbm(S, 64, 3, seed=103)
    wx, wy = fbm(S, 4, 4, seed=104), fbm(S, 4, 4, seed=105)
    # desconchado: pocas manchas grandes deformadas + muchas chispas pequeñas irregulares
    chip_f = warp(fbm(S, 6, 6, seed=106), wx, wy, 80)
    chip_big = smoothstep(0.74, 0.76, chip_f * 0.75 + macro * 0.3)
    wd, _ = worley(S, 140, seed=107)
    wd = warp(wd, fbm(S, 32, 3, seed=114), fbm(S, 32, 3, seed=115), 14)
    chip_small = smoothstep(0.055, 0.035, wd) * (fbm(S, 16, 3, seed=108) > 0.5)
    chips = np.clip(chip_big + chip_small, 0, 1)
    # raspones lineales (golpes) donde asoma la imprimación sin llegar al hierro
    sc = scratches(S, 70, 116, 0.12, 2)
    sc = np.clip(sc * (fbm(S, 6, 3, seed=117) > 0.5), 0, 1)
    # halo de imprimación anticorrosiva (minio) alrededor de los desconchones
    halo = np.clip(blur_wrap(chips, 1.5) * 2.0, 0, 1) * (1 - chips)
    # óxido que chorrea desde los desconchones
    run = streak_down(blur_wrap(chips, 1.2), 90, 0.97) * (0.4 + 0.6 * fbm(S, 32, 3, seed=109))
    run = ndimage.gaussian_filter(np.clip(run - chips, 0, 1), (1, 2.5), mode="wrap") * 0.45
    # color de pintura: verde reja, levemente desvaído al sol
    paint = gradient_map(np.clip(meso * 0.6 + macro * 0.4, 0, 1),
                         [(0.0, hex2rgb("17361f")), (0.5, hex2rgb("1e4428")), (1.0, hex2rgb("2a5232"))])
    fade = smoothstep(0.45, 0.9, macro) * 0.22
    paint = lerp(paint, hex2rgb("587459"), fade)          # entizado (pintura vieja sobre-expuesta)
    paint *= (0.94 + 0.12 * micro)[..., None]
    rust = gradient_map(np.clip(fbm(S, 16, 5, seed=110) * 0.8 + micro * 0.3, 0, 1),
                        [(0.0, hex2rgb("2e1a10")), (0.4, hex2rgb("4f2a16")), (0.75, hex2rgb("6e3a1c")),
                         (1.0, hex2rgb("8a5530"))])
    iron = gradient_map(micro, [(0, hex2rgb("2b2a28")), (1, hex2rgb("4a4743"))])
    bare = lerp(rust, iron, smoothstep(0.75, 0.9, fbm(S, 24, 3, seed=111)) * 0.5)
    primer = np.array(hex2rgb("7a3a24"))
    alb = lerp(paint, primer, halo * 0.35)
    alb = lerp(alb, hex2rgb("5a4a32"), sc * 0.6)
    alb = lerp(alb, hex2rgb("5b331b"), run)
    alb = lerp(alb, bare, chips)
    # polvo/mugre
    dirt = smoothstep(0.55, 0.85, fbm(S, 4, 6, seed=112)) * 0.3
    alb = lerp(alb, hex2rgb("5a5244"), dirt)
    # altura: la película de pintura es delgada -> desniveles pequeños
    h = 0.6 + 0.015 * micro + 0.03 * meso + 0.008 * fbm(S, 128, 2, seed=118)
    h = h - ndimage.gaussian_filter(chips, 0.8, mode="wrap") * 0.08 + halo * 0.015 \
        - chips * fbm(S, 48, 3, seed=113) * 0.05 - sc * 0.03
    h = normalize(h)
    rough = 0.30 + 0.12 * meso + 0.18 * fade + 0.3 * dirt + 0.3 * sc
    rough = np.where(chips > 0.5, 0.8 + 0.12 * micro, rough)
    rough = mix(rough, 0.75, run)
    metal = chips * smoothstep(0.75, 0.9, fbm(S, 24, 3, seed=111)) * 0.5
    ao = np.clip(ao_from_height(h, 3, 0.8) * (1 - 0.15 * dirt), 0, 1)
    save_pbr(name, alb, height=h, rough=rough, metal=metal, ao=ao, normal_strength=7)
    return name


# ======================================================================= 2. galvanizado
def galvanizado() -> str:
    S = 512
    name = OUT + "galvanizado"
    macro = fbm(S, 2, 5, seed=201)
    micro = fbm(S, 96, 2, seed=202)
    # lentejuelas (spangle) del zinc: celdas con brillo distinto y textura dendrítica
    d, ids = worley(S, 260, seed=203)
    rng = np.random.default_rng(204)
    cell_v = rng.random(ids.max() + 1)[ids]
    dendr = fbm(S, 32, 4, seed=205)
    spangle = 0.5 + 0.3 * cell_v + 0.1 * (dendr - 0.5) - 0.08 * smoothstep(0.05, 0.0, d)
    base = gradient_map(np.clip(spangle * 0.85 + macro * 0.2, 0, 1),
                        [(0, hex2rgb("6e7375")), (0.5, hex2rgb("989d9f")), (1, hex2rgb("b9bdbe"))])
    # óxido blanco (corrosión del zinc) y pátina gris oscura
    white = smoothstep(0.68, 0.85, warp(fbm(S, 8, 6, seed=206), macro, fbm(S, 2, 4, seed=207), 50))
    white *= 0.4 + 0.6 * fbm(S, 64, 3, seed=213)
    patina = smoothstep(0.4, 0.85, fbm(S, 3, 6, seed=208))
    alb = lerp(base, base * 0.72, patina * 0.55)
    alb = lerp(alb, hex2rgb("c4c3bb"), white * 0.55)
    # chorreados de mugre vertical, finos y desiguales
    src = smoothstep(0.7, 0.8, fbm(S, 32, 3, seed=209)) * np.random.default_rng(214).random((S, S))
    streak = streak_down(src * 0.6, 160, 0.988)
    streak = ndimage.gaussian_filter(streak, (6, 1.0), mode="wrap")
    streak = np.clip(streak * 1.6, 0, 1) * (0.5 + 0.5 * fbm(S, 4, 3, seed=215))
    alb = lerp(alb, hex2rgb("57544c"), streak * 0.35)
    # puntos de óxido rojo (pocos)
    rd, _ = worley(S, 25, seed=210)
    rust = smoothstep(0.03, 0.005, rd) * (fbm(S, 8, 3, seed=211) > 0.62)
    rust_run = ndimage.gaussian_filter(streak_down(rust * 0.6, 50, 0.955), (2, 1), mode="wrap")
    alb = lerp(alb, rust_colors(np.full((S, S), 0.45)), np.clip(rust_run, 0, 1) * 0.5)
    # rayones
    sc = scratches(S, 35, 212, 0.15, 1)
    alb = lerp(alb, hex2rgb("c9cccd"), sc * 0.35)
    h = normalize(0.5 + 0.03 * dendr + 0.03 * cell_v + white * 0.08 - sc * 0.05 + 0.02 * micro)
    rough = 0.36 + 0.16 * cell_v + 0.15 * patina + 0.35 * white + 0.2 * streak
    rough = np.clip(rough - sc * 0.15, 0.2, 1)
    metal = np.clip(0.95 - 0.7 * white - 0.3 * np.clip(streak, 0, 1) - 0.8 * np.clip(rust_run, 0, 1), 0, 1)
    save_pbr(name, alb, height=h, rough=rough, metal=metal, normal_strength=2.5,
             ao=np.clip(1 - 0.15 * patina - 0.2 * np.clip(streak, 0, 1), 0, 1))
    return name


# ======================================================================= 3. poste de concreto
POSTERS = [
    # (texto en líneas, color papel, color tinta)
    (["SE", "ARRIENDA", "APTO", "300 555 0142"], "e9e2c8", "c0262b"),
    (["CLASES DE", "INGLÉS", "y FRANCÉS", "llame ya"], "f2d23a", "1b1b1b"),
    (["GRAN", "VERBENA", "SÁBADO", "BOSTON"], "e35d8f", "1d1d40"),
    (["COMPRO", "CHATARRA", "NEVERAS", "321 555 0177"], "ffffff", "1f3e8a"),
]


def _poster(w: int, h: int, lines, paper, ink, seed) -> tuple[np.ndarray, np.ndarray]:
    """Afiche impreso viejo: devuelve (rgb, alpha) con bordes rasgados."""
    rng = np.random.default_rng(seed)
    im = Image.new("RGB", (w, h), "#" + paper)
    d = ImageDraw.Draw(im)
    y = 6
    for i, ln in enumerate(lines):
        fs = int(h / (len(lines) + 0.6) * (1.0 if i in (1,) else 0.7))
        f = ImageFont.truetype(FONT_B, max(8, fs))
        bb = d.textbbox((0, 0), ln, font=f)
        tw = bb[2] - bb[0]
        if tw > w - 8:
            f = ImageFont.truetype(FONT_B, max(8, int(fs * (w - 8) / tw)))
            bb = d.textbbox((0, 0), ln, font=f)
            tw = bb[2] - bb[0]
        d.text(((w - tw) / 2, y - bb[1]), ln, fill="#" + ink, font=f)
        y += bb[3] - bb[1] + 6
    rgb = np.asarray(im, dtype=np.float64) / 255
    # bordes rasgados + parches arrancados
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float64)
    n = ndimage.gaussian_filter(rng.random((h, w)), 3)
    n = normalize(n)
    alpha = (edge + n * 14 > 9).astype(np.float64)
    tear = normalize(ndimage.gaussian_filter(rng.random((h, w)), 9))
    alpha *= (tear < 0.72 + 0.1 * rng.random())
    return rgb, alpha


def poste_concreto() -> str:
    S = 512
    name = OUT + "poste_concreto"
    # V (filas) = 1.8 m, U (columnas) = 0.9 m -> píxeles 2:1 en vertical; dibujamos afiches con alto/2.
    macro = fbm(S, 2, 6, seed=301)
    meso = fbm(S, 12, 4, seed=302)
    micro = fbm(S, 128, 2, seed=303)
    # concreto centrifugado: liso, con poros y vetas longitudinales suaves
    vet = ndimage.gaussian_filter(np.random.default_rng(304).random((S, S)), (40, 1.5), mode="wrap")
    vet = normalize(vet)
    pd, _ = worley(S, 700, seed=305)
    pores = smoothstep(0.03, 0.0, pd) * (np.random.default_rng(306).random((S, S)) > 0.5)
    pores = ndimage.gaussian_filter(pores, 0.6, mode="wrap")
    conc = gradient_map(np.clip(macro * 0.5 + meso * 0.3 + vet * 0.2, 0, 1),
                        [(0, hex2rgb("6f6d68")), (0.5, hex2rgb("8e8c86")), (1, hex2rgb("a7a49c"))])
    conc *= (0.95 + 0.08 * micro)[..., None]
    conc = lerp(conc, hex2rgb("5a5852"), pores * 0.4)
    # chorreados de lluvia/hollín
    src = (fbm(S, 16, 3, seed=307) > 0.7).astype(np.float64)
    st = ndimage.gaussian_filter(streak_down(src * 0.7, 160, 0.988), (2, 2), mode="wrap")
    conc = lerp(conc, hex2rgb("3f3d38"), np.clip(st, 0, 1) * 0.35)
    # moho verdoso leve
    moss = smoothstep(0.7, 0.9, fbm(S, 4, 5, seed=308)) * 0.3
    conc = lerp(conc, hex2rgb("4c5638"), moss)
    alb = conc.copy()
    h = 0.6 + 0.02 * meso + 0.02 * vet - 0.06 * pores
    rough = 0.82 + 0.08 * meso - 0.1 * np.clip(st, 0, 1)
    rng = np.random.default_rng(309)
    # restos de papel de afiches viejos arrancados (blanquecino, borde superior recto, abajo rasgado)
    for (rx, ry, rw, rh) in ((300, 40, 150, 70), (20, 210, 120, 60), (210, 380, 170, 50)):
        ys = (np.arange(rh) + ry) % S; xs = (np.arange(rw) + rx) % S
        yy_, xx_ = np.mgrid[0:rh, 0:rw]
        n = normalize(ndimage.gaussian_filter(rng.random((rh, rw)), (2, 5)))
        keep = (yy_ < rh * (0.25 + 0.6 * n)) & (n > 0.3)            # sólo queda la franja de arriba
        keep = keep.astype(np.float64) * (0.55 + 0.3 * n)
        paper = lerp(np.array(hex2rgb("c9c2ad")), np.array(hex2rgb("9e9a8c")), n)
        alb[np.ix_(ys, xs)] = lerp(alb[np.ix_(ys, xs)], paper, keep)
        h[np.ix_(ys, xs)] += keep * 0.02
        rough[np.ix_(ys, xs)] = mix(rough[np.ix_(ys, xs)], 0.92, keep)
    # afiches enteros (algo rasgados), pre-aplastados 2:1 porque V cubre 1.8 m y U 0.9 m
    canvas = np.zeros((S, S, 3)); cov = np.zeros((S, S))
    placements = [(40, 280, 0), (250, 90, 1), (330, 300, 2)]
    for (cx, cy, pi) in placements:
        lines, paper, ink = POSTERS[pi]
        pw, ph = 140 + rng.integers(-10, 15), 95 + rng.integers(-8, 10)
        prgb, pal = _poster(pw * 2, ph * 4, lines, paper, ink, 310 + pi)
        prgb = np.asarray(Image.fromarray((prgb * 255).astype(np.uint8)).resize((pw, ph), Image.LANCZOS),
                          dtype=np.float64) / 255
        pal = np.asarray(Image.fromarray((pal * 255).astype(np.uint8)).resize((pw, ph), Image.BILINEAR),
                         dtype=np.float64) / 255
        age = 0.25 + 0.3 * rng.random()
        prgb = lerp(prgb, np.array(hex2rgb("d8cfb4")), age)            # desvaído y amarillento
        wn = normalize(ndimage.gaussian_filter(rng.random((ph, pw)), 8))
        prgb *= (0.85 + 0.18 * wn)[..., None]
        # manchas de agua/mugre que bajan
        drip = ndimage.gaussian_filter((rng.random((ph, pw)) > 0.995).astype(float), (0.5, 0.5))
        for _ in range(20):
            drip = np.maximum(drip, np.roll(drip, 1, 0) * 0.96)
        prgb = lerp(prgb, np.array(hex2rgb("6d6655")), np.clip(drip * 3, 0, 0.5))
        ys = (np.arange(ph) + cy) % S; xs = (np.arange(pw) + cx) % S
        canvas[np.ix_(ys, xs)] = lerp(canvas[np.ix_(ys, xs)], prgb, pal)
        cov[np.ix_(ys, xs)] = np.maximum(cov[np.ix_(ys, xs)], pal)
    alb = lerp(alb, canvas, cov)
    h = h + ndimage.gaussian_filter(cov, 0.7, mode="wrap") * 0.04
    rough = mix(rough, 0.88, cov)
    # grafitis: tags en aerosol (letra contorneada + relleno) y un garabato
    gcol = np.zeros((S, S, 3)); gmask = np.zeros((S, S))
    FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-BoldOblique.ttf"
    tags = [("BSTN", (120, 440), "1c1c1c", None, 70), ("KZ", (430, 180), "2b44a6", "e8e4da", 60),
            ("roe", (40, 30), "1c1c1c", None, 44)]
    for txt, (x0, y0), col, fill, fs in tags:
        layer = Image.new("L", (S * 3, S * 3), 0)
        fl = Image.new("L", (S * 3, S * 3), 0)
        f = ImageFont.truetype(FB, fs)
        ImageDraw.Draw(layer).text((x0 + S, y0 + S), txt, font=f, fill=0, stroke_width=3, stroke_fill=255)
        if fill:
            ImageDraw.Draw(fl).text((x0 + S, y0 + S), txt, font=f, fill=255)
        layer = layer.resize((S * 3, S * 3))
        # aplastar 2:1 (V cubre el doble de metros)
        def fold(img):
            a = np.asarray(img.filter(ImageFilter.GaussianBlur(1.0)), dtype=np.float64) / 255
            a = sum(a[i * S:(i + 1) * S, j * S:(j + 1) * S] for i in range(3) for j in range(3))
            a = np.clip(a, 0, 1)
            a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((S, S // 2)), dtype=np.float64) / 255
            out = np.zeros((S, S)); out[:S // 2] = a
            return np.roll(out, y0 - y0 // 2, 0)   # el tag vuelve a quedar en la fila y0
        a = fold(layer)
        # chorreo de pintura
        a = np.maximum(a, ndimage.gaussian_filter(streak_down(a * (rng.random((S, S)) > 0.985), 25, 0.97), 0.6)
                       * 0.9)
        over = ndimage.gaussian_filter(a, 4, mode="wrap") * 0.25
        a = np.clip(a + over, 0, 1)
        if fill:
            fa = fold(fl)
            gcol = lerp(gcol, hex2rgb(fill), fa * 0.85); gmask = np.maximum(gmask, fa * 0.85)
        gcol = lerp(gcol, hex2rgb(col), a)
        gmask = np.maximum(gmask, a)
    alb = lerp(alb, gcol, gmask * 0.8)
    rough = mix(rough, 0.6, gmask * 0.5)
    h = normalize(h)
    ao = np.clip(ao_from_height(h, 3, 1.0) * (1 - 0.25 * pores), 0, 1)
    save_pbr(name, alb, height=h, rough=rough, metal=0.0, ao=ao, normal_strength=3)
    return name


# ======================================================================= 4. celosía corte láser
def celosia() -> str:
    S = 1024                 # 2 m -> 8 módulos de 25 cm por tile
    name = OUT + "celosia"
    N = 8
    c = S / N                # 128 px por módulo
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64) + 0.5
    lx = (xx % c) / c - 0.5  # coords locales del módulo [-0.5,0.5]
    ly = (yy % c) / c - 0.5
    mi = (xx // c).astype(int); mj = (yy // c).astype(int)
    r = np.sqrt(lx * lx + ly * ly)
    th = np.arctan2(ly, lx)
    lw = 0.04                  # medio ancho de la lámina (≈1 cm)
    # 1) círculos entrelazados centrados en esquinas y centros (flores de 4 pétalos)
    def circ(cx, cy, R):
        return np.abs(np.sqrt((lx - cx) ** 2 + (ly - cy) ** 2) - R)
    lines = np.full((S, S), 9.0)
    for cx, cy in ((-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5), (0, 0)):
        lines = np.minimum(lines, circ(cx, cy, 0.5))
    # 2) rosetón de 8 pétalos en módulos alternos, anillo y botón central
    alt = ((mi + mj) % 2 == 0)
    petal = np.abs(r - (0.17 + 0.07 * np.cos(8 * th)))
    ring = np.abs(r - 0.32)
    lines = np.where(alt, np.minimum(lines, np.minimum(petal, ring)), lines)
    bud = r < 0.055
    # 3) en los otros módulos: cuadrado girado (rombo) con hojas
    diamond = np.abs(np.abs(lx) + np.abs(ly) - 0.3)
    leaf = np.abs(np.abs(lx * 0.7071 + ly * 0.7071) * 0 + r - 0.12)
    lines = np.where(~alt, np.minimum(lines, np.minimum(diamond, leaf)), lines)
    # 4) marco estructural cada 2 módulos (bandas más gruesas)
    fx = np.abs(((xx / (2 * c)) % 1) - 0.0); fx = np.minimum(fx, 1 - fx) * 2
    fy = np.abs(((yy / (2 * c)) % 1) - 0.0); fy = np.minimum(fy, 1 - fy) * 2
    frame = np.minimum(fx, fy)
    # nervadura de hoja en las lentes (vesicas) que quedan sobre las diagonales
    vein = np.minimum(np.abs(lx - ly), np.abs(lx + ly)) * 0.7071
    in_lens = np.abs(r - 0.354) < 0.12
    metal = (lines < lw) | bud | (frame < 0.03) | ((vein < lw * 0.55) & in_lens)
    # botones en cruces de círculos
    for px, py in ((0, -0.5), (0, 0.5), (-0.5, 0), (0.5, 0)):
        metal |= np.sqrt((lx - px) ** 2 + (ly - py) ** 2) < 0.06
    # suavizar el borde (antialias) por supermuestreo barato
    m = metal.astype(np.float64)
    alpha = np.clip(ndimage.gaussian_filter(m, 0.7, mode="wrap") * 1.0, 0, 1)
    # bisel desde distancia al borde
    dist = edt_wrap(metal)
    bevel = np.clip(dist / 4.0, 0, 1)
    macro = fbm(S, 4, 5, seed=401)
    micro = fbm(S, 128, 2, seed=402)
    h = bevel ** 0.6 * 0.8 + 0.03 * micro
    # color: pintura electrostática negra-bronce, con polvo y óxido en bordes
    paint = gradient_map(np.clip(macro * 0.7 + micro * 0.3, 0, 1),
                         [(0, hex2rgb("16130f")), (0.5, hex2rgb("231e18")), (1, hex2rgb("332b22"))])
    edge = np.clip(1 - dist / 3.0, 0, 1) * metal
    rustn = fbm(S, 32, 4, seed=403)
    rust = edge * smoothstep(0.68, 0.85, rustn) * 0.6 + smoothstep(0.86, 0.96, rustn * 0.6 + macro * 0.5) * 0.4
    rust = np.clip(rust, 0, 1)
    alb = lerp(paint, rust_colors(rustn * 0.6), rust * 0.75)
    dust = smoothstep(0.5, 0.85, fbm(S, 6, 5, seed=404)) * 0.25
    alb = lerp(alb, hex2rgb("6a6357"), dust)
    alb = lerp(alb, hex2rgb("4c463e"), edge * 0.25 * (1 - rust))   # canto pulido/claro
    rough = np.clip(0.48 + 0.15 * macro + 0.35 * rust + 0.2 * dust, 0, 1)
    metl = np.clip(0.15 + 0.3 * edge * (1 - rust), 0, 1)
    ao = np.clip(0.75 + 0.25 * bevel, 0, 1)
    alb = dilate_rgb(alb, alpha, 30)
    save_pbr(name, alb, height=h, rough=rough, metal=metl, ao=ao, normal_strength=6)
    save_rgba_albedo(name, alb, alpha)
    return name


# ======================================================================= 5. atlas de señales
SIGNS = [
    "pare", "ceda_el_paso", "no_parquear", "velocidad_30",
    "baje_en_2a", "peligro_curva", "paso_peatonal", "una_via",
    "doble_sentido", "prohibido_girar", "calle_55_peru", "carrera_38",
    "calle_54_caracas", "carrera_39", "calle_58_echeverri", "carrera_43_girardot",
]
RED = "#c4161c"; YEL = "#f6c400"; WHT = "#f4f4f0"; BLK = "#151515"; GRN = "#0b6b3a"
CELL = 256
SS = 4  # supersampling para dibujar


def _font(sz, path=FONT_B):
    return ImageFont.truetype(path, int(sz))


def _ctext(d, cx, cy, txt, sz, fill, path=FONT_B, max_w=None):
    f = _font(sz, path)
    bb = d.textbbox((0, 0), txt, font=f)
    w = bb[2] - bb[0]
    if max_w and w > max_w:
        f = _font(sz * max_w / w, path)
        bb = d.textbbox((0, 0), txt, font=f)
        w = bb[2] - bb[0]
    hh = bb[3] - bb[1]
    d.text((cx - w / 2 - bb[0], cy - hh / 2 - bb[1]), txt, fill=fill, font=f)


def _regpoly(cx, cy, r, n, rot):
    return [(cx + r * np.cos(rot + 2 * np.pi * k / n), cy + r * np.sin(rot + 2 * np.pi * k / n)) for k in range(n)]


def _arrow(d, pts_shaft, head, w, fill):
    d.line(pts_shaft, fill=fill, width=int(w), joint="curve")
    d.polygon(head, fill=fill)


def _draw_sign(kind: str) -> tuple[Image.Image, Image.Image, Image.Image]:
    """Dibuja una señal (supersampleada). Devuelve (color RGB, alpha L, máscara 'borde laminado' L)."""
    Z = CELL * SS
    im = Image.new("RGB", (Z, Z), (0, 0, 0))
    al = Image.new("L", (Z, Z), 0)
    d = ImageDraw.Draw(im); da = ImageDraw.Draw(al)
    c = Z / 2
    P = 8 * SS                       # margen para no sangrar entre celdas en mipmaps
    R = c - P
    s = SS
    if kind == "pare":
        oc = _regpoly(c, c, R, 8, np.pi / 8)
        d.polygon(oc, fill=WHT); da.polygon(oc, fill=255)
        d.polygon(_regpoly(c, c, R - 9 * s, 8, np.pi / 8), fill=RED)
        _ctext(d, c, c, "PARE", 78 * s, WHT, FONT_LB, max_w=190 * s)
    elif kind == "ceda_el_paso":
        tri = [(P, P + 18 * s), (Z - P, P + 18 * s), (c, Z - P - 4 * s)]
        d.polygon(tri, fill=RED); da.polygon(tri, fill=255)
        inner = [(P + 44 * s, P + 42 * s), (Z - P - 44 * s, P + 42 * s), (c, Z - P - 54 * s)]
        d.polygon(inner, fill=WHT)
        _ctext(d, c, P + 78 * s, "CEDA EL", 22 * s, BLK, max_w=110 * s)
        _ctext(d, c, P + 104 * s, "PASO", 22 * s, BLK, max_w=80 * s)
    elif kind in ("no_parquear", "velocidad_30", "prohibido_girar"):
        d.ellipse([P, P, Z - P, Z - P], fill=WHT); da.ellipse([P, P, Z - P, Z - P], fill=255)
        rw = 26 * s
        d.ellipse([P + 3 * s, P + 3 * s, Z - P - 3 * s, Z - P - 3 * s], fill=RED)
        d.ellipse([P + rw, P + rw, Z - P - rw, Z - P - rw], fill=WHT)
        if kind == "no_parquear":
            _ctext(d, c, c + 4 * s, "P", 150 * s, BLK, FONT_LB)
        elif kind == "velocidad_30":
            _ctext(d, c, c - 6 * s, "30", 112 * s, BLK, FONT_LB)
            _ctext(d, c, c + 62 * s, "km/h", 22 * s, BLK)
        else:
            # flecha girando a la izquierda: sube y dobla
            w = 20 * s
            _arrow(d, [(c + 18 * s, c + 70 * s), (c + 18 * s, c - 10 * s), (c + 8 * s, c - 30 * s),
                       (c - 10 * s, c - 34 * s), (c - 30 * s, c - 34 * s)],
                   [(c - 70 * s, c - 34 * s), (c - 28 * s, c - 66 * s), (c - 28 * s, c - 2 * s)], w, BLK)
        if kind != "velocidad_30":
            # diagonal roja (de arriba-izq a abajo-der) por encima del pictograma
            rr = R - rw / 2
            a = np.deg2rad(45)
            d.line([(c - rr * np.cos(a), c - rr * np.sin(a)), (c + rr * np.cos(a), c + rr * np.sin(a))],
                   fill=RED, width=int(24 * s))
    elif kind == "baje_en_2a":
        x0, y0, x1, y1 = P + 22 * s, P, Z - P - 22 * s, Z - P
        d.rounded_rectangle([x0, y0, x1, y1], 14 * s, fill=BLK); da.rounded_rectangle([x0, y0, x1, y1], 14 * s, fill=255)
        d.rounded_rectangle([x0 + 5 * s, y0 + 5 * s, x1 - 5 * s, y1 - 5 * s], 10 * s, fill=WHT)
        d.rounded_rectangle([x0 + 9 * s, y0 + 9 * s, x1 - 9 * s, y1 - 9 * s], 8 * s, outline=BLK, width=3 * s)
        _ctext(d, c, c - 46 * s, "BAJE", 70 * s, BLK, FONT_LB, max_w=160 * s)
        _ctext(d, c - 16 * s, c + 46 * s, "EN 2", 70 * s, BLK, FONT_LB, max_w=130 * s)
        _ctext(d, c + 64 * s, c + 26 * s, "a", 38 * s, BLK, FONT_LB)
        d.line([(c + 52 * s, c + 50 * s), (c + 77 * s, c + 50 * s)], fill=BLK, width=4 * s)
    elif kind in ("peligro_curva", "paso_peatonal"):
        dm = [(c, P), (Z - P, c), (c, Z - P), (P, c)]
        d.polygon(dm, fill=BLK); da.polygon(dm, fill=255)
        k = 9 * s
        d.polygon([(c, P + k * 1.41), (Z - P - k * 1.41, c), (c, Z - P - k * 1.41), (P + k * 1.41, c)], fill=YEL)
        k2 = 15 * s
        d.polygon([(c, P + k2 * 1.41), (Z - P - k2 * 1.41, c), (c, Z - P - k2 * 1.41), (P + k2 * 1.41, c)],
                  outline=BLK, width=3 * s)
        if kind == "peligro_curva":
            w = 18 * s
            # curva a la derecha: sube, dobla a la derecha
            pts = [(c - 22 * s, c + 70 * s), (c - 22 * s, c + 10 * s), (c - 16 * s, c - 14 * s),
                   (c, c - 30 * s), (c + 22 * s, c - 36 * s)]
            _arrow(d, pts, [(c + 62 * s, c - 38 * s), (c + 18 * s, c - 68 * s), (c + 20 * s, c - 6 * s)], w, BLK)
        else:
            # peatón caminando sobre cebra
            for i in range(5):
                xL = c - 70 * s + i * 30 * s
                d.polygon([(xL, c + 58 * s), (xL + 18 * s, c + 58 * s), (xL + 12 * s, c + 72 * s),
                           (xL - 6 * s, c + 72 * s)], fill=BLK)
            d.ellipse([c - 2 * s, c - 76 * s, c + 22 * s, c - 52 * s], fill=BLK)
            lw = 15 * s
            d.line([(c + 6 * s, c - 46 * s), (c - 2 * s, c + 2 * s)], fill=BLK, width=lw + 4 * s)  # torso
            d.line([(c - 2 * s, c + 2 * s), (c - 26 * s, c + 50 * s)], fill=BLK, width=lw)         # pierna atrás
            d.line([(c - 2 * s, c + 2 * s), (c + 18 * s, c + 22 * s), (c + 22 * s, c + 52 * s)], fill=BLK, width=lw)
            d.line([(c + 6 * s, c - 38 * s), (c - 22 * s, c - 12 * s)], fill=BLK, width=lw - 3 * s)  # brazos
            d.line([(c + 6 * s, c - 38 * s), (c + 30 * s, c - 16 * s)], fill=BLK, width=lw - 3 * s)
    elif kind in ("una_via", "doble_sentido"):
        x0, x1 = P, Z - P
        y0, y1 = c - 66 * s, c + 66 * s
        d.rounded_rectangle([x0, y0, x1, y1], 10 * s, fill=BLK); da.rounded_rectangle([x0, y0, x1, y1], 10 * s, fill=255)
        d.rounded_rectangle([x0 + 6 * s, y0 + 6 * s, x1 - 6 * s, y1 - 6 * s], 7 * s, fill=WHT)
        if kind == "una_via":
            d.rectangle([x0 + 30 * s, c - 16 * s, x1 - 80 * s, c + 16 * s], fill=BLK)
            d.polygon([(x1 - 24 * s, c), (x1 - 86 * s, c - 44 * s), (x1 - 86 * s, c + 44 * s)], fill=BLK)
            _ctext(d, c - 20 * s, c - 44 * s, "UNA VÍA", 22 * s, BLK)
        else:
            for sgn, yc in ((1, c - 30 * s), (-1, c + 30 * s)):
                if sgn > 0:
                    d.rectangle([x0 + 28 * s, yc - 10 * s, x1 - 70 * s, yc + 10 * s], fill=BLK)
                    d.polygon([(x1 - 24 * s, yc), (x1 - 72 * s, yc - 28 * s), (x1 - 72 * s, yc + 28 * s)], fill=BLK)
                else:
                    d.rectangle([x0 + 70 * s, yc - 10 * s, x1 - 28 * s, yc + 10 * s], fill=BLK)
                    d.polygon([(x0 + 24 * s, yc), (x0 + 72 * s, yc - 28 * s), (x0 + 72 * s, yc + 28 * s)], fill=BLK)
    else:  # placas de nomenclatura
        names = {
            "calle_55_peru": ("CALLE", "55", "PERÚ"), "carrera_38": ("CARRERA", "38", ""),
            "calle_54_caracas": ("CALLE", "54", "CARACAS"), "carrera_39": ("CARRERA", "39", ""),
            "calle_58_echeverri": ("CALLE", "58", "ECHEVERRI"), "carrera_43_girardot": ("CARRERA", "43", "GIRARDOT"),
        }
        via, num, nom = names[kind]
        x0, x1 = P, Z - P
        y0, y1 = c - 62 * s, c + 62 * s
        d.rounded_rectangle([x0, y0, x1, y1], 12 * s, fill=GRN); da.rounded_rectangle([x0, y0, x1, y1], 12 * s, fill=255)
        d.rounded_rectangle([x0 + 6 * s, y0 + 6 * s, x1 - 6 * s, y1 - 6 * s], 8 * s, outline=WHT, width=4 * s)
        if nom:
            _ctext(d, c, c - 30 * s, f"{via} {num}", 50 * s, WHT, FONT_LB, max_w=200 * s)
            d.line([(x0 + 22 * s, c + 2 * s), (x1 - 22 * s, c + 2 * s)], fill=WHT, width=2 * s)
            _ctext(d, c, c + 30 * s, nom, 38 * s, WHT, FONT_B, max_w=200 * s)
        else:
            _ctext(d, c - 44 * s, c, via, 30 * s, WHT, FONT_B, max_w=110 * s)
            _ctext(d, c + 62 * s, c + 2 * s, num, 84 * s, WHT, FONT_LB, max_w=100 * s)
    return im, al


def senales() -> str:
    name = OUT + "senales"
    A = CELL * 4
    alb = np.zeros((A, A, 3)); alpha = np.zeros((A, A)); h = np.zeros((A, A))
    rough = np.ones((A, A)); metal = np.zeros((A, A)); ao = np.ones((A, A))
    # microprisma de lámina reflectiva (patrón hexagonal fino) — común a todas
    yy, xx = np.mgrid[0:CELL, 0:CELL].astype(np.float64)
    hexp = (np.cos(xx * 2 * np.pi / 5.0) + np.cos((xx * 0.5 + yy * 0.866) * 2 * np.pi / 5.0)
            + np.cos((xx * 0.5 - yy * 0.866) * 2 * np.pi / 5.0)) / 3
    for idx, kind in enumerate(SIGNS):
        rng = np.random.default_rng(500 + idx)
        im, al = _draw_sign(kind)
        im = im.resize((CELL, CELL), Image.LANCZOS)
        al = al.resize((CELL, CELL), Image.LANCZOS)
        col = np.asarray(im, dtype=np.float64) / 255
        a = np.asarray(al, dtype=np.float64) / 255
        inside = a > 0.5
        dist = ndimage.distance_transform_edt(inside)
        rim = np.clip(1 - dist / 5.0, 0, 1) * inside           # pestaña doblada del aluminio
        # ---- desgaste
        n1 = normalize(ndimage.gaussian_filter(rng.random((CELL, CELL)), 18))
        n2 = normalize(ndimage.gaussian_filter(rng.random((CELL, CELL)), 4))
        n3 = normalize(ndimage.gaussian_filter(rng.random((CELL, CELL)), 1))
        # decoloración UV: el rojo vira a rosado/naranja, todo pierde saturación
        fade = 0.12 + 0.25 * rng.random() + 0.15 * n1
        lum = col.mean(-1, keepdims=True)
        col = col * (1 - fade[..., None] * 0.6) + (lum * 0.9 + 0.1) * fade[..., None] * 0.6
        col = lerp(col, np.array([0.92, 0.88, 0.80]), fade * 0.18)
        # mugre: más abajo y en la pestaña
        grad = np.clip(yy / CELL, 0, 1) ** 2
        wear = rng.random()
        dirt = np.clip(grad * (0.35 + 0.6 * wear) * n1 + rim * 0.4 + smoothstep(0.6, 0.9, n2) * (0.15 + 0.3 * wear)
                       + smoothstep(0.55, 0.8, n1) * 0.25 * wear, 0, 1)
        col = lerp(col, np.array(hex2rgb("4f4a3e")), dirt * 0.5)
        # lámina reflectiva cuarteada/levantada en señales muy viejas
        crack = smoothstep(0.78, 0.82, n2 * 0.7 + n1 * 0.4) * (wear > 0.6) * inside
        col = lerp(col, np.array(hex2rgb("8d8c86")), crack * 0.6)
        # rayones
        sc = scratches(CELL, int(8 + rng.integers(0, 14)), 600 + idx, 0.35, 1)
        col = lerp(col, np.array([0.80, 0.80, 0.78]), sc * 0.55)
        # desportilladuras en el borde -> aluminio desnudo
        chip = (rim > 0.3) & (n2 > 0.72)
        chip = ndimage.binary_dilation(chip, iterations=1) & inside
        col[chip] = mix(np.array(hex2rgb("a9adad")), np.array(hex2rgb("7f8282")), n3[chip][:, None])
        # stickers (1-2) en algunas señales
        stick = np.zeros((CELL, CELL))
        if rng.random() < 0.6:
            for _ in range(rng.integers(1, 3)):
                for _try in range(20):
                    sw, sh = rng.integers(14, 34), rng.integers(10, 24)
                    sx, sy = rng.integers(30, CELL - 30 - sw), rng.integers(40, CELL - 30 - sh)
                    reg = col[sy - 3:sy + sh + 3, sx - 3:sx + sw + 3]
                    if inside[sy:sy + sh, sx:sx + sw].all() and reg.std(axis=(0, 1)).max() < 0.06:
                        break
                else:
                    continue
                scol = [hex2rgb("f3f1ea"), hex2rgb("2d6cc4"), hex2rgb("e8d23c"), hex2rgb("e04f8a")][rng.integers(0, 4)]
                patch = np.zeros((CELL, CELL)); patch[sy:sy + sh, sx:sx + sw] = 1
                patch *= (n3 * 0.5 + 0.7 > 0.55)                      # medio arrancado
                patch = ndimage.gaussian_filter(patch, 0.5)
                pc = np.full((CELL, CELL, 3), scol)
                # "texto" del sticker: rayitas
                for li in range(2):
                    ly0 = sy + 3 + li * (sh // 2)
                    pc[ly0:ly0 + 2, sx + 3:sx + sw - 3] = 0.15
                col = lerp(col, pc, patch * 0.95)
                stick = np.maximum(stick, patch)
        # ---- altura/rugosidad
        hh = inside * 0.4 + rim * 0.35 + stick * 0.08 + hexp * 0.012 * inside - sc * 0.03
        r = 0.30 + 0.25 * dirt + 0.15 * n1 + 0.4 * stick * 0.5
        r = np.where(chip, 0.45, r) + crack * 0.3
        mtl = np.where(chip, 0.9, 0.0) + sc * 0.3
        oc = np.clip(1 - dirt * 0.25, 0, 1)
        row, colm = divmod(idx, 4)
        sl = (slice(row * CELL, (row + 1) * CELL), slice(colm * CELL, (colm + 1) * CELL))
        col = dilate_rgb(col, a, 12)
        alb[sl] = col; alpha[sl] = a; h[sl] = hh; rough[sl] = np.clip(r, 0.15, 1)
        metal[sl] = np.clip(mtl, 0, 1); ao[sl] = oc
    h = ndimage.gaussian_filter(h, 0.6)
    save_pbr(name, alb, height=h, rough=rough, metal=metal, ao=ao, normal_strength=3)
    save_rgba_albedo(name, alb, alpha)
    return name


# ======================================================================= 6. pintura amarilla
def _amarilla(stripes: bool) -> str:
    S = 512
    name = OUT + ("amarilla_rayado" if stripes else "pintura_amarilla")
    macro = fbm(S, 2, 5, seed=701)
    meso = fbm(S, 8, 5, seed=702)
    micro = fbm(S, 96, 2, seed=703)
    wx, wy = fbm(S, 4, 4, seed=704), fbm(S, 4, 4, seed=705)
    yel = gradient_map(np.clip(meso * 0.6 + macro * 0.4, 0, 1),
                       [(0, hex2rgb("c99a06")), (0.5, hex2rgb("e2b00c")), (1, hex2rgb("efc229"))])
    paint = yel.copy()
    stripe = np.zeros((S, S))
    if stripes:
        yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
        P = 128                                    # 25 cm de período, franjas de 12.5 cm a 45°
        t = ((xx + yy + 3 * (wx - 0.5)) % P) / P
        stripe = smoothstep(0.49, 0.505, t) * (1 - smoothstep(0.985, 1.0, t))
        blk = gradient_map(meso, [(0, hex2rgb("141414")), (1, hex2rgb("26241f"))])
        # el negro se desvaneció a gris en zonas soleadas
        blk = lerp(blk, hex2rgb("4a4842"), smoothstep(0.6, 0.9, macro) * 0.5)
        paint = lerp(paint, blk, stripe)
    # desvaído y polvo
    fade = smoothstep(0.5, 0.9, macro) * 0.25
    paint = lerp(paint, hex2rgb("d8c79a"), fade * (1 - stripe))
    paint *= (0.95 + 0.09 * micro)[..., None]
    # golpes y raspones (bolardos reciben golpes de parachoques y bicicletas)
    chip_f = warp(fbm(S, 8, 6, seed=706), wx, wy, 40)
    chips = smoothstep(0.76, 0.79, chip_f * 0.8 + macro * 0.25)
    sc = scratches(S, 45, 707, 0.15, 2)
    sc = np.clip(sc * (fbm(S, 4, 3, seed=708) > 0.45), 0, 1)
    under = rust_colors(np.clip(fbm(S, 24, 4, seed=709), 0, 1))
    grey = gradient_map(micro, [(0, hex2rgb("55534f")), (1, hex2rgb("77746e"))])
    under = lerp(under, grey, smoothstep(0.45, 0.6, fbm(S, 12, 3, seed=710)))
    run = np.clip(streak_down(blur_wrap(chips, 1.5) * 0.7, 50, 0.96) - chips, 0, 1) * 0.5
    alb = lerp(paint, rust_colors(np.full((S, S), 0.4)), run)
    alb = lerp(alb, under, chips)
    alb = lerp(alb, hex2rgb("3b3833"), sc * 0.4)     # marcas de caucho negro
    dirt = smoothstep(0.55, 0.85, fbm(S, 4, 6, seed=711)) * 0.3
    alb = lerp(alb, hex2rgb("6b6150"), dirt)
    h = normalize(0.6 + 0.012 * micro + 0.03 * meso - ndimage.gaussian_filter(chips, 0.8, mode="wrap") * 0.07
                  - sc * 0.015 + 0.006 * fbm(S, 128, 2, seed=712))
    rough = 0.42 + 0.12 * meso + 0.2 * fade + 0.25 * dirt + 0.05 * stripe
    rough = np.where(chips > 0.5, 0.8, rough)
    metal = chips * smoothstep(0.45, 0.6, fbm(S, 12, 3, seed=710)) * 0.7
    save_pbr(name, alb, height=h, rough=np.clip(rough, 0, 1), metal=metal,
             ao=np.clip(ao_from_height(h, 3, 0.8) * (1 - 0.1 * dirt), 0, 1), normal_strength=4.5)
    return name


# ======================================================================= main
def main():
    os.makedirs(os.path.join(ROOT, OUT), exist_ok=True)
    os.makedirs(DBG, exist_ok=True)
    only = set(sys.argv[1:])
    jobs = [("pintura_verde", pintura_verde), ("galvanizado", galvanizado), ("poste_concreto", poste_concreto),
            ("celosia", celosia), ("senales", senales), ("pintura_amarilla", lambda: _amarilla(False)),
            ("amarilla_rayado", lambda: _amarilla(True))]
    previews = []
    for nm, fn in jobs:
        if only and nm not in only:
            continue
        print("->", nm, flush=True)
        rel = fn()
        p = DBG + nm + "_preview.png"
        preview(rel, p)
        previews.append(p)
    if not only:
        contact_sheet(previews + [os.path.join(ROOT, OUT + "senales_albedo.png")], DBG + "metal_sheet.png", 512)


if __name__ == "__main__":
    main()

"""Familia "actors": texturas de vehículos y del personaje Andro (original).

Regenerar:  python3 tools/texgen/actors.py          (todo)
            python3 tools/texgen/actors.py tire rim  (solo algunos sets)

Escalas / layout (documentado también en art/mat/mat_actors.gd):
  veh_dirt      512, tileable, 1 tile = 1.0 m. RGBA: rgb = color de polvo/barro, A = máscara de suciedad.
  veh_tire      512, layout de CylinderMesh de Godot 4.3 (eje = altura del cilindro):
                  v 0..0.5  banda lateral -> banda de rodamiento (u = circunferencia, tilea en u, 40 tacos)
                  v 0.5..1  tapas: discos de radio 0.25 en (0.25,0.75) y (0.75,0.75) -> flancos con letras
                  "URBANA" / "185/65 R15 88H" (marca inventada). Radio del rin ~0.62 r.
  veh_rim       512 RGBA, vista frontal de rin de aleación de 5 rayos partidos; A=0 entre rayos.
                  Para QuadMesh / disco frente a la llanta.
  veh_plate     512 RGBA, atlas 2 columnas x 4 filas (celda 256x128 = placa 33x16 cm).
                  Índice i -> columna i%2, fila i/2. 0..5 amarillas particulares, 6..7 blancas servicio público.
  veh_lights    512 RGBA + _emission. Mitad superior (v 0..0.5) faro delantero, mitad inferior stop trasero.
  cloth_ripstop 512, tileable, 1 tile = 0.30 m. Tela técnica de chaqueta, neutra para tintar.
  cloth_knit    512, tileable, 1 tile = 0.15 m. Punto jersey de algodón (buzo), neutro.
  cloth_twill   512, tileable, 1 tile = 0.25 m. Sarga gruesa (cargo), neutra.
  skin          512, tileable, 1 tile = 0.12 m. Poros y variación, tono neutro cálido claro (se tinta).
  sneaker       512, tileable en u, 1 tile = 0.25 m. v 0..0.64 cuero sintético perforado, costura,
                  v 0.66..1 goma de suela con estrías. Neutro casi blanco.
  scarf         512, tileable, 1 tile = 0.16 m. Algodón a rayas verde/blanco (Antioquia), 4 franjas de 4 cm.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from common import (ROOT, ao_from_height, blur_wrap, contact_sheet, fbm, gradient_map, hex2rgb,  # noqa: E402
                    height_to_normal, lerp, normalize, preview, save_pbr, warp, worley)

FAM = "art/tex/actors"
PREV = "/tmp/f1_actors"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
FONT_R = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


# ------------------------------------------------------------------ utilidades propias
def srgb(*c):
    return np.array(c, dtype=np.float64) / 255.0


def down2(a: np.ndarray, f: int = 2) -> np.ndarray:
    """Reduce por promedio de bloques f x f (anti-aliasing de lo dibujado a 2x)."""
    h, w = a.shape[:2]
    if a.ndim == 2:
        return a.reshape(h // f, f, w // f, f).mean((1, 3))
    return a.reshape(h // f, f, w // f, f, a.shape[2]).mean((1, 3))


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def stretched_noise(size, sy, sx, seed):
    """Ruido blanco desenfocado anisotrópicamente (tileable): vetas, hilos, chorreaduras."""
    rng = np.random.default_rng(seed)
    n = rng.random((size, size))
    return normalize(ndimage.gaussian_filter(n, (sy, sx), mode="wrap"))


def text_mask(text, font_path, px, pad=4):
    f = ImageFont.truetype(font_path, px)
    l, t, r, b = f.getbbox(text)
    im = Image.new("L", (r - l + pad * 2, b - t + pad * 2), 0)
    ImageDraw.Draw(im).text((pad - l, pad - t), text, font=f, fill=255)
    return np.asarray(im, dtype=np.float64) / 255.0


def paste_max(dst, src, y, x):
    h, w = src.shape
    dst[y:y + h, x:x + w] = np.maximum(dst[y:y + h, x:x + w], src)


def fast_worley(S, points, seed):
    """F1 celular tileable rápido (EDT sobre mosaico 3x3). Devuelve distancia normalizada."""
    rng = np.random.default_rng(seed)
    m = np.ones((S, S), bool)
    pts = rng.integers(0, S, (points, 2))
    m[pts[:, 0], pts[:, 1]] = False
    big = np.tile(m, (3, 3))
    d = ndimage.distance_transform_edt(big)[S:2 * S, S:2 * S]
    return normalize(d)


def save_rgba(rel, rgba):
    path = os.path.join(ROOT, rel + "_albedo.png")
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)


def edge_bevel(mask, width):
    """Altura con bisel: 0 fuera, sube a 1 en `width` px hacia dentro (no-wrap)."""
    d = ndimage.distance_transform_edt(mask > 0.5)
    return np.clip(d / width, 0, 1)


def sat(c, s):
    g = c.mean(-1, keepdims=True)
    return np.clip(g + (c - g) * s, 0, 1)


# ================================================================== VEHÍCULOS
def gen_dirt(S=512):
    """Polvo/barro sobre carrocería. 1 tile = 1 m."""
    macro = fbm(S, 3, 5, seed=101)
    meso = fbm(S, 8, 5, seed=102)
    w1, w2 = fbm(S, 4, 4, seed=103), fbm(S, 4, 4, seed=104)
    macro = warp(macro, w1, w2, 60)
    # chorreaduras verticales de lluvia sobre el polvo
    streak = stretched_noise(S, 22, 1.2, 105)
    streak = smooth(0.52, 0.75, streak)
    # salpicaduras de barro (puntos y manchitas)
    rng = np.random.default_rng(106)
    spl = np.zeros((S, S))
    for _ in range(420):
        y, x = rng.integers(0, S, 2)
        spl[y, x] = rng.random() ** 0.5
    spl = ndimage.gaussian_filter(spl, 1.1, mode="wrap") * 9
    spl += ndimage.gaussian_filter(spl, 3.0, mode="wrap") * 2.0
    spl = np.clip(spl, 0, 1)
    film = smooth(0.25, 0.85, macro * 0.65 + meso * 0.35)
    mask = np.clip(film * 0.5 + streak * 0.18 * (0.3 + film) + spl * 0.4, 0, 1)
    # lavado por chorreaduras: líneas limpias dentro del polvo
    clean = smooth(0.6, 0.85, stretched_noise(S, 30, 0.8, 107))
    mask = np.clip(mask - clean * 0.25, 0, 1) ** 1.2 * 0.75   # tope ~0.75: polvo de uso diario
    tone = fbm(S, 6, 5, seed=108)
    col = gradient_map(tone, [(0, srgb(92, 82, 68)), (0.5, srgb(128, 116, 98)), (1, srgb(156, 146, 128))])
    col = lerp(col, srgb(70, 58, 44), np.clip(spl * 1.2, 0, 1))  # barro más oscuro
    height = mask * 0.4 + spl * 0.8 + fbm(S, 32, 3, seed=109) * 0.1
    rough = 0.82 + 0.15 * mask - 0.1 * spl
    ao = 1 - spl * 0.25
    out = save_pbr(f"{FAM}/veh_dirt", col, height=height, rough=rough, ao=ao, normal_strength=3)
    save_rgba(f"{FAM}/veh_dirt", np.dstack([col, mask]))
    return out


def gen_tire(S=512):
    """Llanta para CylinderMesh (ver layout arriba)."""
    H = S // 2
    # ---------------- banda de rodamiento (512 x 256), tilea en x
    yy, xx = np.mgrid[0:H, 0:S].astype(np.float64)
    v = yy / H                       # 0..1 a lo ancho
    n_pitch = 40
    ph = (xx / S * n_pitch)          # fase circunferencial
    h = np.ones((H, S))
    # hombros redondeados (caída de altura a los bordes)
    shoulder = smooth(0.0, 0.12, v) * smooth(1.0, 0.88, v)
    # 3 ranuras circunferenciales
    for c in (0.33, 0.5, 0.67):
        h -= smooth(0.028, 0.018, np.abs(v - c)) * 0.9
    # ranuras laterales inclinadas en los hombros (tacos)
    slant = ph + v * 1.6
    lat = np.abs(((slant + 0.5) % 1.0) - 0.5)
    lat_m = smooth(0.09, 0.05, lat) * (smooth(0.31, 0.29, v) + smooth(0.69, 0.71, v))
    h -= lat_m * 0.8
    # laminillas (sipes) finas en las costillas centrales, desfasadas
    slant2 = ph * 2 - v * 3 + 0.25
    sipe = smooth(0.06, 0.02, np.abs(((slant2 + 0.5) % 1.0) - 0.5))
    sipe *= ((v > 0.36) & (v < 0.47)) | ((v > 0.53) & (v < 0.64))
    h -= sipe * 0.35
    # indicadores de desgaste dentro de las ranuras
    h = np.clip(h, 0, 1)
    h = h * (0.35 + 0.65 * shoulder)
    grain = fbm(S, 32, 3, seed=201)[:H]  # fbm tilea en ambos ejes; recorte vale porque solo tilea en x
    grain = normalize(ndimage.gaussian_filter(np.random.default_rng(202).random((H, S)), 0.8, mode="wrap"))
    groove = 1 - np.clip(h / 0.6, 0, 1)
    tread_h = h + grain * 0.04
    rubber = srgb(36, 36, 38)
    tread_col = lerp(np.broadcast_to(rubber, (H, S, 3)), srgb(19, 19, 20), groove)
    # polvo café en ranuras y desgaste más claro en la superficie de contacto
    dust = fbm(S, 8, 4, seed=203)[:H]
    tread_col = lerp(tread_col, srgb(74, 66, 56), groove * smooth(0.4, 0.8, dust) * 0.55)
    contact = smooth(0.15, 0.3, v) * smooth(0.85, 0.7, v) * (h > 0.6)
    tread_col = lerp(tread_col, srgb(44, 44, 45), contact * 0.5)
    tread_col *= (0.92 + 0.12 * grain)[..., None]
    tread_r = 0.9 - contact * 0.18 + groove * 0.06

    # ---------------- flancos (1024 x 512 a 2x, dos discos)
    F = 2
    SW = S * F
    HB = H * F
    yb, xb = np.mgrid[0:HB, 0:SW].astype(np.float64)
    side_h = np.zeros((HB, SW))
    side_txt = np.zeros((HB, SW))
    R = HB / 2.0                     # radio de la tapa = radio exterior de la llanta
    # tira de texto (se envuelve en coordenadas polares)
    strip_w, strip_h = 3800, 96
    strip = np.zeros((strip_h, strip_w))
    big = text_mask("URBANA", FONT_B, 84)
    small = text_mask("185/65 R15  88H", FONT_B, 60)
    tiny = text_mask("TUBELESS · RADIAL", FONT_B, 36)
    for k in range(2):
        o = k * strip_w // 2
        paste_max(strip, big[:strip_h], (strip_h - big.shape[0]) // 2, o + 40)
        paste_max(strip, small[:strip_h], (strip_h - small.shape[0]) // 2, o + 40 + big.shape[1] + 80)
        paste_max(strip, tiny[:strip_h], (strip_h - tiny.shape[0]) // 2, o + 40 + big.shape[1] + small.shape[1] + 200)
    for cx in (R, 3 * R):
        dx, dy = xb - cx, yb - R
        rho = np.sqrt(dx * dx + dy * dy) / R           # 0..1
        th = (np.arctan2(dy, dx) / (2 * np.pi)) % 1.0
        inside = rho <= 1.0
        # perfil del flanco: abultado entre rin (0.62) y banda (0.95)
        prof = np.sin(np.clip((rho - 0.6) / 0.38, 0, 1) * np.pi) * 0.5
        bead = smooth(0.6, 0.64, rho) * smooth(0.7, 0.66, rho) * 0.3       # pestaña junto al rin
        ribs = smooth(0.006, 0.0, np.abs(rho - 0.73)) * 0.25 + smooth(0.006, 0.0, np.abs(rho - 0.91)) * 0.25
        # texto curvo: banda entre 0.76 y 0.89
        tv = (0.93 - rho) / 0.17
        sx = (th * strip_w).astype(int) % strip_w
        sy = np.clip((tv * strip_h).astype(int), 0, strip_h - 1)
        txt = strip[sy, sx] * ((tv >= 0) & (tv <= 1))
        hh = prof + bead + ribs + txt * 0.35
        hh = np.where(rho > 0.97, 0.5 - (rho - 0.97) * 8, hh)      # hombro hacia la banda
        hh = np.where(rho < 0.6, 0.0, hh)
        side_h = np.where(inside, hh, side_h)
        side_txt = np.where(inside, txt, side_txt)
    side_h = down2(side_h, F)
    side_txt = down2(side_txt, F)
    yy2, xx2 = np.mgrid[0:H, 0:S].astype(np.float64)
    rho_l = np.minimum(np.hypot(xx2 - H / 2, yy2 - H / 2), np.hypot(xx2 - 1.5 * H, yy2 - H / 2)) / (H / 2)
    sgrain = normalize(ndimage.gaussian_filter(np.random.default_rng(204).random((H, S)), 0.7))
    side_col = np.broadcast_to(srgb(33, 33, 35), (H, S, 3)).copy()
    side_col *= (0.9 + 0.15 * sgrain)[..., None]
    side_col = lerp(side_col, srgb(78, 78, 78), side_txt * 0.85)          # letras gastadas, más claras
    sdust = smooth(0.5, 0.9, fbm(S, 8, 4, seed=205)[:H])
    side_col = lerp(side_col, srgb(88, 80, 68), sdust * 0.25 * smooth(0.8, 1.0, rho_l))
    side_col = np.where((rho_l < 0.6)[..., None], srgb(12, 12, 13), side_col)  # interior (tapado por el rin)
    side_r = 0.86 - side_txt * 0.12 + sdust * 0.08

    albedo = np.concatenate([tread_col, side_col], 0)
    height = np.concatenate([tread_h, side_h + sgrain * 0.02], 0)
    rough = np.concatenate([tread_r, side_r], 0)
    ao = np.concatenate([1 - groove * 0.45, np.where(rho_l < 0.62, 0.5, 1.0) - side_txt * 0.0], 0)
    return save_pbr(f"{FAM}/veh_tire", albedo, height=height, rough=rough, ao=ao, normal_strength=5)


def gen_rim(S=512):
    """Rin de aleación de 5 rayos partidos, vista frontal (RGBA)."""
    F = 2
    N = S * F
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    c = N / 2
    dx, dy = (xx - c) / (N / 2 * 0.985), (yy - c) / (N / 2 * 0.985)
    rho = np.hypot(dx, dy)
    th = np.arctan2(dy, dx) + np.pi / 2  # rayo apuntando hacia arriba
    k = 5
    dth = (th + np.pi / k) % (2 * np.pi / k) - np.pi / k
    perp = rho * np.sin(dth)
    along = rho * np.cos(dth)
    halfw = 0.075 + 0.075 * np.clip((rho - 0.22) / 0.65, 0, 1)
    spoke = (np.abs(perp) < halfw) & (along > 0) & (rho > 0.18) & (rho < 0.93)
    slot = (np.abs(perp) < 0.008 + 0.028 * np.clip((rho - 0.5) / 0.35, 0, 1)) & (rho > 0.52) & (rho < 0.85)
    spoke &= ~slot
    lip = (rho > 0.915) & (rho <= 1.0)
    barrel = (rho > 0.87) & (rho <= 0.92)
    hub = rho < 0.27
    solid = spoke | lip | hub | barrel
    alpha = solid.astype(np.float64)

    # alturas: bisel en bordes de rayos (distance transform), labio alto, hub con tapa
    bev = edge_bevel(spoke | hub, 10.0)
    h = np.zeros((N, N))
    h = np.where(spoke | hub, 0.45 + 0.35 * bev, h)
    # canal central sobre el rayo (cara mecanizada vs lados pintados)
    face = (np.abs(perp) < halfw * 0.78) & spoke
    h = np.where(face, h + 0.08, h)
    lip_prof = np.sin(np.clip((rho - 0.915) / 0.085, 0, 1) * np.pi)
    h = np.where(lip, 0.6 + 0.4 * lip_prof, h)
    h = np.where(barrel & ~spoke & ~lip, 0.1, h)
    cap = rho < 0.15
    h = np.where(cap, 0.9 + 0.1 * np.cos(np.clip(rho / 0.15, 0, 1) * np.pi / 2), h)
    # tuercas
    nuts = np.zeros((N, N), bool)
    for i in range(k):
        a = (i + 0.5) * 2 * np.pi / k - np.pi / 2
        nx, ny = np.cos(a) * 0.21, np.sin(a) * 0.21
        dn = np.hypot(dx - nx, dy - ny)
        hexd = np.maximum(np.abs(dx - nx), np.abs(dy - ny))
        nuts |= dn < 0.035
        h = np.where(dn < 0.05, h - 0.12 * smooth(0.05, 0.04, dn), h)        # asiento hundido
        h = np.where(dn < 0.03, 0.95 - hexd * 2, h)
    # emblema inventado: anillo + triángulo
    ring = (np.abs(rho - 0.09) < 0.008)
    tri = (dy > -0.05) & (dy < 0.035) & (np.abs(dx) < (0.035 - dy) * 0.6)
    emblem = ring | tri
    h = np.where(emblem, h + 0.05, h)

    # color: plata con cepillado radial; caras mecanizadas más brillantes; lados gris grafito
    brushed = normalize(ndimage.gaussian_filter(np.random.default_rng(301).random((N, N)), 0.6))
    rad = (th * 600).astype(int) % 600
    radial = np.random.default_rng(302).random(600)[rad]
    silver = srgb(188, 190, 194)
    graphite = srgb(70, 72, 76)
    col = np.broadcast_to(graphite, (N, N, 3)).copy()
    col = np.where((~solid)[..., None], srgb(30, 30, 32), col)
    col = np.where((face | lip | cap)[..., None], silver, col)
    col = np.where(barrel[..., None] & ~(spoke | lip)[..., None], srgb(38, 38, 40), col)
    col *= (0.93 + 0.07 * brushed + 0.04 * radial * face)[..., None]
    col = np.where(nuts[..., None], srgb(160, 162, 166), col)
    col = np.where(emblem[..., None], srgb(30, 30, 32), col)
    # polvo de freno: marrón grisáceo en bordes y hacia el centro
    bdust = fbm(N, 6, 5, seed=303) * smooth(0.6, 0.2, rho) * (1 - bev * 0.6)
    edge_d = (1 - bev) * (spoke | hub)
    dust = np.clip(bdust * 0.7 + edge_d * 0.4, 0, 1)
    col = lerp(col, srgb(68, 58, 48), dust * 0.6)
    rough = np.where(face | lip, 0.22, 0.38) + dust * 0.4
    metal = np.where(emblem, 0.0, 1.0) * (1 - dust * 0.6)
    metal = np.where(face | lip | nuts | cap, metal, metal * 0.55)  # lados pintados: menos metálicos
    ao = 1 - (1 - bev) * 0.35 * (spoke | hub) - smooth(0.3, 0.6, 1 - h) * 0.0
    ao = np.where(barrel & ~spoke, 0.45, ao)

    col, h, rough, metal, ao, alpha = (down2(a, F) for a in (col, h, rough, metal, ao, alpha))
    nrm = height_to_normal(ndimage.gaussian_filter(h, 0.7), 6)
    out = save_pbr(f"{FAM}/veh_rim", col, normal=nrm, rough=rough, metal=metal, ao=ao)
    save_rgba(f"{FAM}/veh_rim", np.dstack([col, alpha]))
    return out


PLATES = ["SPA 742", "BOS 155", "MED 038", "ANT 516", "PBL 204", "CAF 873",  # amarillas (particular)
          "TXS 418", "BUS 307"]                                               # blancas (servicio público)


def gen_plates(S=512):
    """Atlas 2x4 de placas colombianas inventadas (RGBA)."""
    F = 2
    N = S * F
    cw, ch = N // 2, N // 4
    col = np.zeros((N, N, 3))
    alpha = np.zeros((N, N))
    h = np.zeros((N, N))
    rough = np.full((N, N), 0.45)
    yl = srgb(246, 196, 24)
    wh = srgb(236, 236, 230)
    ink = srgb(22, 22, 22)
    rng = np.random.default_rng(401)
    for i, txt in enumerate(PLATES):
        cx0, cy0 = (i % 2) * cw, (i // 2) * ch
        yy, xx = np.mgrid[0:ch, 0:cw].astype(np.float64)
        m = 10                                     # margen a la celda
        rr = 22                                    # radio esquinas
        qx = np.clip(np.maximum(m + rr - xx, xx - (cw - m - rr)), 0, None)
        qy = np.clip(np.maximum(m + rr - yy, yy - (ch - m - rr)), 0, None)
        sd = np.hypot(qx, qy) - rr                 # <0 dentro del rect redondeado
        inside = np.clip(-sd + 0.5, 0, 1)
        dist_in = -sd
        border = (dist_in > 7) & (dist_in < 14)    # filete negro estampado
        emb = smooth(0, 5, dist_in) * 0.3          # pestaña doblada
        # texto
        f = ImageFont.truetype(FONT_B, 150)
        im = Image.new("L", (cw, ch), 0)
        d = ImageDraw.Draw(im)
        l, t, r, b = d.textbbox((0, 0), txt, font=f)
        tw, th = r - l, b - t
        sxs = min(1.0, (cw - 70) / tw)
        big = Image.new("L", (tw + 8, th + 8), 0)
        ImageDraw.Draw(big).text((4 - l, 4 - t), txt, font=f, fill=255)
        big = big.resize((int((tw + 8) * sxs), int((th + 8) * 0.95)), Image.LANCZOS)
        im.paste(big, ((cw - big.width) // 2, 30))
        f2 = ImageFont.truetype(FONT_B, 34)
        l2, t2, r2, b2 = d.textbbox((0, 0), "MEDELLIN", font=f2)
        d.text(((cw - (r2 - l2)) // 2 - l2, ch - 62 - t2), "MEDELLIN", font=f2, fill=255)
        letters = np.asarray(im, dtype=np.float64) / 255.0
        letters = np.maximum(letters, border.astype(np.float64))
        # tornillos
        screws = np.zeros((ch, cw))
        for sxp in (0.28, 0.72):
            ds = np.hypot(xx - cw * sxp, yy - 22)
            screws = np.maximum(screws, smooth(9, 7, ds))
        base = yl if i < 6 else wh
        # suciedad, rayones y desgaste
        grime = smooth(0.45, 0.9, fbm(cw, 4, 5, seed=410 + i)[:ch, :cw])
        grime = np.clip(grime * 0.5 + smooth(ch * 0.6, ch, yy) * 0.35 + smooth(6, 0, dist_in) * 0.5, 0, 1)
        scratch = np.zeros((ch, cw))
        for _ in range(14):
            x0, y0 = rng.random() * cw, rng.random() * ch
            ang = rng.random() * np.pi
            ln = 20 + rng.random() * 70
            t_ = np.clip(((xx - x0) * np.cos(ang) + (yy - y0) * np.sin(ang)) / ln, 0, 1)
            px = x0 + t_ * ln * np.cos(ang)
            py = y0 + t_ * ln * np.sin(ang)
            scratch = np.maximum(scratch, smooth(1.4, 0.3, np.hypot(xx - px, yy - py)) * rng.random())
        c = np.broadcast_to(base, (ch, cw, 3)).copy()
        c *= (0.96 + 0.06 * fbm(cw, 16, 3, seed=420 + i)[:ch, :cw])[..., None]
        c = lerp(c, ink, letters)
        c = lerp(c, srgb(96, 86, 70), grime * 0.45)
        c = lerp(c, srgb(200, 200, 196), scratch * 0.5)
        c = lerp(c, srgb(120, 120, 124), screws)
        sl = (slice(cy0, cy0 + ch), slice(cx0, cx0 + cw))
        col[sl] = c
        alpha[sl] = inside
        h[sl] = (emb + letters * 0.5 + screws * 0.6 - scratch * 0.05) * inside
        rough[sl] = 0.42 + grime * 0.4 - letters * 0.05 + scratch * 0.2
    col, alpha, h, rough = (down2(a, F) for a in (col, alpha, h, rough))
    nrm = height_to_normal(ndimage.gaussian_filter(h, 0.6), 5)
    ao = 1 - np.clip(ndimage.gaussian_filter(h, 3) - h, 0, 1) * 1.5
    out = save_pbr(f"{FAM}/veh_plate", col, normal=nrm, rough=rough, ao=ao)
    save_rgba(f"{FAM}/veh_plate", np.dstack([col, alpha]))
    return out


def _rrect_sd(xx, yy, x0, y0, x1, y1, r):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx = np.abs(xx - cx) - hx
    qy = np.abs(yy - cy) - hy
    return np.hypot(np.clip(qx, 0, None), np.clip(qy, 0, None)) + np.minimum(np.maximum(qx, qy), 0) - r


def gen_lights(S=512):
    """Atlas: faro delantero (v 0..0.5) + stop trasero (v 0.5..1). RGBA + emisión."""
    F = 2
    N = S * F
    Hh = N // 2
    col = np.zeros((N, N, 3))
    alpha = np.zeros((N, N))
    h = np.zeros((N, N))
    rough = np.full((N, N), 0.1)
    metal = np.zeros((N, N))
    emi = np.zeros((N, N, 3))
    yy, xx = np.mgrid[0:Hh, 0:N].astype(np.float64)
    lens_ribs = 0.5 + 0.5 * np.sin(xx / 7.0)
    micro = normalize(ndimage.gaussian_filter(np.random.default_rng(501).random((Hh, N)), 1.0))

    # ---------------- faro (housing con esquina interior barrida)
    sd = _rrect_sd(xx, yy, 24, 40, N - 24, Hh - 40, 70)
    sweep = (yy - 40) - (xx - (N - 300)) * 0.9                 # recorte diagonal en el extremo interior
    sd = np.maximum(sd, -sweep * 0.7)
    inside = np.clip(-sd + 0.5, 0, 1)
    c = np.broadcast_to(srgb(28, 30, 33), (Hh, N, 3)).copy()     # fondo carcasa gris oscuro
    r_ = np.full((Hh, N), 0.45)
    m_ = np.zeros((Hh, N))
    hh = np.zeros((Hh, N))
    e = np.zeros((Hh, N, 3))
    # dos reflectores cromados con proyector
    for (px, py, R) in ((250, 270, 150), (590, 270, 125)):
        d = np.hypot(xx - px, yy - py)
        bowl = d < R
        facets = 0.5 + 0.5 * np.cos(np.arctan2(yy - py, xx - px) * 12)
        shade = 0.55 + 0.45 * (d / R) + 0.1 * facets
        c = np.where(bowl[..., None], srgb(205, 208, 212) * np.clip(shade, 0, 1.1)[..., None], c)
        m_ = np.where(bowl, 1.0, m_)
        r_ = np.where(bowl, 0.08 + 0.06 * facets, r_)
        hh = np.where(bowl, 0.4 - 0.3 * (1 - d / R) ** 2, hh)
        ring = (d > R * 0.42) & (d < R * 0.5)
        c = np.where(ring[..., None], srgb(20, 20, 22), c)
        m_ = np.where(ring, 0.0, m_)
        lens = d < R * 0.42
        lg = np.clip(1 - d / (R * 0.42), 0, 1)
        c = np.where(lens[..., None], lerp(srgb(120, 128, 140), srgb(235, 240, 248), lg ** 2), c)
        m_ = np.where(lens, 0.3, m_)
        r_ = np.where(lens, 0.04, r_)
        hh = np.where(lens, 0.5 + 0.3 * lg, hh)
        e = np.where(lens[..., None], srgb(255, 248, 232) * (0.6 + 0.4 * lg)[..., None], e)
    # DRL: tira LED en L sobre el borde superior y bajando por el exterior
    drl = ((np.abs(yy - 92) < 12) & (xx > 70) & (xx < 760)) | ((np.abs(xx - 70) < 12) & (yy > 92) & (yy < 380))
    drl = ndimage.gaussian_filter(drl.astype(float), 1.5)
    c = lerp(c, srgb(240, 244, 250), drl)
    e += drl[..., None] * srgb(255, 255, 255)
    # direccional ámbar en el extremo interior
    amb = (_rrect_sd(xx, yy, 790, 140, 900, 400, 20) < 0) & (inside > 0.5)
    amb_ribs = 0.5 + 0.5 * np.sin(yy / 5.0)
    c = np.where(amb[..., None], srgb(232, 138, 30) * (0.75 + 0.25 * amb_ribs)[..., None], c)
    m_ = np.where(amb, 0.0, m_)
    r_ = np.where(amb, 0.2, r_)
    # mica: brillo del vidrio, nervaduras finas, ligeros amarillamiento/polvo en los bordes
    edge = smooth(30, 0, -sd)
    c = lerp(c, srgb(150, 150, 140), edge * 0.35)
    r_ = r_ * 0.6 + 0.04 + edge * 0.25 + micro * 0.04
    hh += lens_ribs * 0.03 + smooth(10, 0, -sd) * 0.4
    sl = slice(0, Hh)
    col[sl], alpha[sl], h[sl], rough[sl], metal[sl], emi[sl] = c, inside, hh * inside, r_, m_, e * inside[..., None]

    # ---------------- stop trasero
    sd = _rrect_sd(xx, yy, 24, 60, N - 24, Hh - 60, 50)
    sweep = (Hh - 60 - yy) - (xx - (N - 260)) * 0.6
    sd = np.maximum(sd, -sweep * 0.7)
    inside = np.clip(-sd + 0.5, 0, 1)
    smoke = srgb(70, 8, 12)
    c = np.broadcast_to(smoke, (Hh, N, 3)).copy()
    hh = np.zeros((Hh, N))
    e = np.zeros((Hh, N, 3))
    r_ = np.full((Hh, N), 0.08)
    m_ = np.zeros((Hh, N))
    # reflector interior rojo con celdas tipo panal (visible bajo la mica)
    cell = (0.5 + 0.5 * np.cos(xx / 9.0)) * (0.5 + 0.5 * np.cos(yy / 9.0))
    c = c * (0.85 + 0.3 * cell)[..., None]
    # barra LED principal (forma de C) y bloque de stop
    bar = ((np.abs(yy - 150) < 16) & (xx > 70) & (xx < 860)) | ((np.abs(yy - 370) < 16) & (xx > 70) & (xx < 640)) | \
          ((np.abs(xx - 80) < 16) & (yy > 150) & (yy < 370))
    bar = ndimage.gaussian_filter(bar.astype(float), 2.0)
    brake = (_rrect_sd(xx, yy, 140, 200, 560, 320, 18) < 0).astype(float)
    brake = ndimage.gaussian_filter(brake, 1.5)
    red = srgb(205, 22, 26)
    c = lerp(c, red, np.clip(brake * 0.85 + bar, 0, 1))
    leds = (0.5 + 0.5 * np.cos(xx / 6.0)) ** 4 * brake
    c = lerp(c, srgb(255, 70, 60), leds * 0.4)
    e += (bar[..., None] * srgb(255, 40, 30) + brake[..., None] * srgb(230, 20, 18) * (0.7 + 0.3 * leds)[..., None])
    # luz de reversa (blanca, no emite con el stop) y direccional ámbar
    rev = (_rrect_sd(xx, yy, 620, 200, 760, 320, 14) < 0)
    c = np.where(rev[..., None], srgb(222, 224, 228) * (0.85 + 0.15 * cell)[..., None], c)
    turn = (_rrect_sd(xx, yy, 790, 200, 880, 320, 14) < 0)
    c = np.where(turn[..., None], srgb(222, 120, 28) * (0.85 + 0.15 * cell)[..., None], c)
    edge = smooth(24, 0, -sd)
    c = lerp(c, srgb(40, 40, 42), edge * 0.6)
    r_ = 0.05 + micro * 0.05 + edge * 0.25
    hh = cell * 0.05 + smooth(10, 0, -sd) * 0.4 + bar * 0.1
    sl = slice(Hh, N)
    col[sl], alpha[sl], h[sl], rough[sl], metal[sl], emi[sl] = c, inside, hh * inside, r_, m_, e * inside[..., None]

    col, alpha, h, rough, metal, emi = (down2(a, F) for a in (col, alpha, h, rough, metal, emi))
    nrm = height_to_normal(ndimage.gaussian_filter(h, 0.6), 4)
    ao = np.clip(1 - np.clip(ndimage.gaussian_filter(h, 4) - h, 0, 1) * 2, 0.4, 1)
    out = save_pbr(f"{FAM}/veh_lights", col, normal=nrm, rough=rough, metal=metal, ao=ao, emission=np.clip(emi, 0, 1))
    save_rgba(f"{FAM}/veh_lights", np.dstack([col, alpha]))
    return out


# ================================================================== PERSONAJE
def wrinkles(S, seed, amount=1.0):
    """Arrugas suaves de tela (macro), tileable."""
    a = ridged(S, 3, seed)
    b = fbm(S, 2, 4, seed=seed + 1)
    return normalize(a * 0.6 + b * 0.4) * amount


def ridged(S, cells, seed):
    n = fbm(S, cells, 5, seed=seed)
    w1, w2 = fbm(S, 2, 3, seed=seed + 7), fbm(S, 2, 3, seed=seed + 8)
    n = warp(n, w1, w2, 80)
    return normalize(1 - np.abs(n * 2 - 1)) ** 2


def stitches_line(S, axis_pos, axis, stitch_len=10, gap=5, width=1.6, seed=0):
    """Pespunte: línea discontinua tileable. axis=0 -> línea vertical en x=axis_pos."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    along = yy if axis == 0 else xx
    across = xx if axis == 0 else yy
    period = stitch_len + gap
    ph = along % period
    on = smooth(0, 1.5, ph) * smooth(stitch_len, stitch_len - 1.5, ph)
    d = np.abs(((across - axis_pos) + S / 2) % S - S / 2)
    return on * smooth(width, width * 0.3, d)


def gen_ripstop(S=512):
    """Tela técnica de nylon ripstop. 1 tile = 0.30 m (0.59 mm/px). Neutra (tintar)."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    # tejido tafetán fino (periodo 4 px)
    warp_y = 0.5 + 0.5 * np.cos(xx * np.pi / 2)
    weft_x = 0.5 + 0.5 * np.cos(yy * np.pi / 2)
    check = ((xx // 2 + yy // 2) % 2)
    weave = np.where(check > 0, warp_y, weft_x) * 0.6 + 0.4
    # rejilla ripstop cada 16 px (9.4 mm), hilos dobles
    gx = np.minimum(xx % 16, 16 - xx % 16)
    gy = np.minimum(yy % 16, 16 - yy % 16)
    grid = np.maximum(smooth(1.6, 0.4, gx), smooth(1.6, 0.4, gy))
    slub = stretched_noise(S, 0.6, 18, 601) * 0.5 + stretched_noise(S, 18, 0.6, 602) * 0.5
    # costura: dos pespuntes paralelos y pliegue de la unión (vertical, en x=256)
    seam_fold = np.exp(-(((xx - 256 + S / 2) % S - S / 2) / 5.0) ** 2)
    seam_st = stitches_line(S, 246, 0, 9, 4, 1.5) + stitches_line(S, 266, 0, 9, 4, 1.5)
    wr = wrinkles(S, 603)
    height = weave * 0.1 + grid * 0.08 + slub * 0.06 + wr * 0.55 - seam_fold * 0.35 + seam_st * 0.2
    base = 0.80
    tone = base * (0.94 + 0.06 * weave) * (1 - grid * 0.03) * (0.96 + 0.06 * slub)
    tone *= (0.94 + 0.08 * wr) * (1 - seam_fold * 0.18)
    tone = tone * (1 - seam_st * 0.1)
    albedo = np.dstack([tone * 1.0, tone * 1.0, tone * 1.01])
    # leve desgaste/polvo de uso
    use = smooth(0.55, 0.85, fbm(S, 4, 5, seed=604))
    albedo = lerp(albedo, albedo * srgb(250, 244, 232), use * 0.4)
    rough = 0.52 + 0.1 * (1 - weave) + grid * 0.06 + use * 0.1 + seam_st * 0.2
    ao = 1 - seam_fold * 0.35 - (1 - wr) * 0.08
    return save_pbr(f"{FAM}/cloth_ripstop", albedo, height=height, rough=rough, ao=ao, normal_strength=3.5)


def gen_knit(S=512):
    """Punto jersey de algodón (buzo). 1 tile = 0.15 m, 64 columnas x 64 filas de puntos (2.3 mm)."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    cw = 8
    u = (xx % cw) / cw          # 0..1 en la columna
    v = (yy % cw) / cw
    # cada punto = "V": dos lóbulos inclinados
    def lobe(cx, ang):
        x = (u - cx)
        y = (v - 0.5)
        ca, sa = np.cos(ang), np.sin(ang)
        xr = x * ca - y * sa
        yr = x * sa + y * ca
        return np.exp(-((xr / 0.2) ** 2 + (yr / 0.55) ** 2))
    h = np.maximum(lobe(0.27, 0.45), lobe(0.73, -0.45))
    # irregularidad del hilo por fila/columna
    rng = np.random.default_rng(701)
    rowj = rng.random(S // cw)[(yy // cw).astype(int)]
    colj = rng.random(S // cw)[(xx // cw).astype(int)]
    fuzz = normalize(ndimage.gaussian_filter(rng.random((S, S)), 0.7, mode="wrap"))
    pill = smooth(0.82, 0.95, fbm(S, 32, 3, seed=702)) * smooth(0.5, 0.8, fbm(S, 4, 4, seed=703))
    wr = wrinkles(S, 704)
    height = h * 0.45 + fuzz * 0.1 + pill * 0.25 + wr * 0.5 + rowj * 0.04
    tone = 0.80 * (0.8 + 0.2 * h) * (0.96 + 0.05 * rowj + 0.03 * colj) * (0.95 + 0.06 * fuzz) * (0.94 + 0.08 * wr)
    tone = tone * (1 + pill * 0.06)
    albedo = np.dstack([tone, tone, tone])
    rough = 0.92 - h * 0.06 + pill * 0.06
    ao = 1 - (1 - h) * 0.22
    return save_pbr(f"{FAM}/cloth_knit", albedo, height=height, rough=rough, ao=ao, normal_strength=3.0)


def gen_twill(S=512):
    """Sarga gruesa de algodón (pantalón cargo). 1 tile = 0.25 m; wale diagonal de 8 px (3.9 mm)."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    d = (xx + yy) % 8
    ridge = 0.5 + 0.5 * np.cos(d / 8 * 2 * np.pi)
    # hilos de trama finos perpendiculares
    cross = 0.5 + 0.5 * np.cos((xx - yy) % 4 / 4 * 2 * np.pi)
    # slub a lo largo de la diagonal: ruido desenfocado y rotado 45° (tileable por construcción)
    n = np.random.default_rng(801).random((S, S))
    slub = np.zeros((S, S))
    for k in range(-12, 13):
        slub += np.roll(np.roll(n, k, 0), -k, 1)
    slub = normalize(ndimage.gaussian_filter(slub, 0.8, mode="wrap"))
    fade = smooth(0.45, 0.9, fbm(S, 3, 5, seed=802))      # desteñido por uso
    wr = wrinkles(S, 803)
    height = ridge * 0.35 + cross * 0.06 + slub * 0.1 + wr * 0.55
    tone = 0.78 * (0.82 + 0.2 * ridge) * (0.95 + 0.07 * slub) * (0.94 + 0.08 * wr)
    tone = tone + fade * 0.04 * ridge
    albedo = np.dstack([tone, tone * 1.0, tone * 1.005])
    rough = 0.86 + 0.06 * (1 - ridge) + fade * 0.04
    ao = 1 - (1 - ridge) * 0.18
    return save_pbr(f"{FAM}/cloth_twill", albedo, height=height, rough=rough, ao=ao, normal_strength=3.5)


def gen_skin(S=512):
    """Piel con poros sutiles. 1 tile = 0.12 m (0.23 mm/px). Neutro cálido claro (tintar con el tono)."""
    rng = np.random.default_rng(901)
    pores = np.zeros((S, S))
    for _ in range(5200):
        y, x = rng.integers(0, S, 2)
        pores[y, x] = 0.6 + 0.4 * rng.random()
    pores = np.clip(ndimage.gaussian_filter(pores, 0.9, mode="wrap") * 5, 0, 1)
    # micro arrugas cruzadas (dos direcciones)
    l1 = stretched_noise(S, 0.7, 10, 902)
    l2 = stretched_noise(S, 10, 0.7, 903)
    lines = smooth(0.6, 0.8, np.maximum(l1, l2))
    cells = fast_worley(S, 260, 904)
    blot = fbm(S, 3, 5, seed=905)
    red = smooth(0.5, 0.85, fbm(S, 6, 4, seed=906))
    freckle = smooth(0.86, 0.95, fbm(S, 48, 2, seed=907)) * 0.6
    height = 0.6 + cells * 0.12 - pores * 0.2 - lines * 0.08 + fbm(S, 64, 2, seed=908) * 0.05
    base = srgb(236, 214, 200)
    albedo = np.broadcast_to(base, (S, S, 3)).copy()
    albedo *= (0.95 + 0.06 * blot)[..., None]
    albedo = lerp(albedo, albedo * srgb(255, 236, 230), red * 0.35)     # rubor/capilares
    albedo = lerp(albedo, albedo * srgb(224, 204, 190), freckle * 0.4)
    albedo *= (1 - pores * 0.08)[..., None]
    rough = 0.5 + 0.12 * fbm(S, 4, 4, seed=909) + pores * 0.15 + lines * 0.05
    ao = 1 - pores * 0.25
    return save_pbr(f"{FAM}/skin", albedo, height=height, rough=rough, ao=ao, normal_strength=2.0)


def gen_sneaker(S=512):
    """Tenis: cuero sintético perforado (v 0..0.64) + costura + goma (v 0.66..1). Tilea en u; 1 tile = 0.25 m."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    v = yy / S
    # grano del cuero: celdas worley pequeñas
    cells = fast_worley(S, 1400, 1001)
    grain = normalize(ndimage.gaussian_filter(cells, 0.6, mode="wrap"))
    leather_h = 0.6 + grain * 0.12
    # perforaciones en la franja media del cuero (rejilla escalonada, periodo 16 px = 7.8 mm)
    row = np.floor(yy / 16)
    px = (xx + (row % 2) * 8) % 16 - 8
    py = yy % 16 - 8
    hole_d = np.hypot(px, py)
    perf_zone = smooth(0.1, 0.14, v) * smooth(0.46, 0.42, v)
    hole = smooth(3.2, 2.2, hole_d) * perf_zone
    rim = smooth(4.5, 3.4, hole_d) * perf_zone - hole
    # pespuntes: borde del panel perforado y unión cuero/suela
    st = stitches_line(S, 0.06 * S, 1, 8, 4, 1.4) + stitches_line(S, 0.5 * S, 1, 8, 4, 1.4) + \
        stitches_line(S, 0.61 * S, 1, 8, 4, 1.4)
    panel_edge = smooth(2, 0, np.abs(yy - 0.53 * S)) * 0.0
    leather = v < 0.64
    # goma: estrías verticales finas en el canto + textura granulada, línea del canto superior
    ribs = 0.5 + 0.5 * np.cos(xx / 4 * np.pi)
    rubber_tex = normalize(ndimage.gaussian_filter(np.random.default_rng(1002).random((S, S)), 1.0, mode="wrap"))
    sole_h = 0.45 + ribs * 0.12 * smooth(0.72, 0.76, v) * smooth(0.95, 0.91, v) + rubber_tex * 0.05
    sole_h = sole_h + smooth(0.665, 0.68, v) * smooth(0.705, 0.69, v) * 0.25      # filete de la entresuela
    transition = smooth(0.635, 0.66, v)
    height = (leather_h - hole * 0.6 + rim * 0.08 - st * 0.15) * (1 - transition) + sole_h * transition
    # arrugas de flexión en la puntera del cuero
    crease = stretched_noise(S, 1.0, 14, 1003)
    crease = smooth(0.62, 0.78, crease) * smooth(0.45, 0.2, v)
    height = height - crease * 0.15 * (1 - transition)
    lc = 0.9 * (0.97 + 0.04 * grain) * (1 - crease * 0.05)
    leather_col = np.dstack([lc, lc, lc * 0.99])
    leather_col = lerp(leather_col, srgb(40, 40, 42), hole)                 # fondo de las perforaciones
    leather_col = lerp(leather_col, srgb(150, 150, 152), st * 0.6)
    sc = 0.92 * (0.96 + 0.05 * rubber_tex)
    sole_col = np.dstack([sc, sc * 0.985, sc * 0.95])                       # goma ligeramente cremosa
    # suciedad: más abajo en la suela, algo en pliegues
    dirt = smooth(0.5, 0.9, fbm(S, 6, 5, seed=1004))
    sole_dirt = np.clip(smooth(0.8, 1.0, v) * 0.7 + dirt * 0.4 * smooth(0.7, 1.0, v), 0, 1)
    sole_col = lerp(sole_col, srgb(120, 108, 92), sole_dirt * 0.6)
    leather_col = lerp(leather_col, srgb(170, 162, 150), crease * 0.3 + dirt * 0.12)
    albedo = lerp(leather_col, sole_col, transition)
    rough = (0.48 + grain * 0.1 + crease * 0.1) * (1 - transition) + (0.82 + sole_dirt * 0.1) * transition + hole * 0.3
    ao = 1 - hole * 0.6 - st * 0.1 - smooth(0.62, 0.64, v) * smooth(0.67, 0.65, v) * 0.35
    return save_pbr(f"{FAM}/sneaker", albedo, height=height, rough=rough, ao=ao, normal_strength=3.5)


def gen_scarf(S=512):
    """Pañoleta de algodón a rayas verde/blanco (Antioquia). 1 tile = 0.16 m, 4 franjas de 4 cm."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    # tejido tafetán (periodo 4 px = 1.25 mm)
    warp_y = 0.5 + 0.5 * np.cos(xx * np.pi / 2)
    weft_x = 0.5 + 0.5 * np.cos(yy * np.pi / 2)
    check = ((xx // 2 + yy // 2) % 2)
    weave = np.where(check > 0, warp_y, weft_x)
    # franjas: borde algo irregular por los hilos teñidos
    jitter = (stretched_noise(S, 0.5, 3, 1101) - 0.5) * 2.5
    band = ((yy + jitter) % 256) / 256
    green = smooth(0.0, 0.012, band) * smooth(0.5, 0.488, band)
    green = np.clip(green + smooth(1.0, 0.988, band) * 0, 0, 1)
    # línea fina blanca dentro del verde y fina verde dentro del blanco (detalle de tejido)
    thin = smooth(3, 1.5, np.abs(((yy % 256) - 64))) + smooth(3, 1.5, np.abs(((yy % 256) - 192)))
    green = np.clip(np.where(band < 0.5, green - smooth(3, 1.5, np.abs((yy % 256) - 64)), green +
                             smooth(3, 1.5, np.abs((yy % 256) - 192))), 0, 1)
    slub = stretched_noise(S, 0.6, 16, 1102) * 0.5 + stretched_noise(S, 16, 0.6, 1103) * 0.5
    wr = wrinkles(S, 1104)
    g_col = srgb(0, 112, 54)
    w_col = srgb(232, 234, 226)
    albedo = lerp(np.broadcast_to(w_col, (S, S, 3)), g_col, green)
    albedo *= ((0.9 + 0.1 * weave) * (0.95 + 0.07 * slub) * (0.93 + 0.09 * wr))[..., None]
    fade = smooth(0.5, 0.9, fbm(S, 4, 5, seed=1105))
    albedo = lerp(albedo, sat(albedo, 0.75) * 1.05, fade * 0.4)
    height = weave * 0.2 + slub * 0.08 + wr * 0.6
    rough = 0.9 - weave * 0.04
    ao = 1 - (1 - wr) * 0.12
    return save_pbr(f"{FAM}/scarf", albedo, height=height, rough=rough, ao=ao, normal_strength=3.0)


SETS = {
    "dirt": ("veh_dirt", gen_dirt),
    "tire": ("veh_tire", gen_tire),
    "rim": ("veh_rim", gen_rim),
    "plate": ("veh_plate", gen_plates),
    "lights": ("veh_lights", gen_lights),
    "ripstop": ("cloth_ripstop", gen_ripstop),
    "knit": ("cloth_knit", gen_knit),
    "twill": ("cloth_twill", gen_twill),
    "skin": ("skin", gen_skin),
    "sneaker": ("sneaker", gen_sneaker),
    "scarf": ("scarf", gen_scarf),
}


def main(argv):
    os.makedirs(PREV, exist_ok=True)
    keys = argv or list(SETS)
    for k in keys:
        name, fn = SETS[k]
        fn()
        preview(f"{FAM}/{name}", f"{PREV}/prev_{name}.png")
        print("ok", name)
    base = os.path.join(ROOT, FAM)
    names = [SETS[k][0] for k in SETS]
    alb = [os.path.join(base, n + "_albedo.png") for n in names if os.path.exists(os.path.join(base, n + "_albedo.png"))]
    contact_sheet(alb, f"{PREV}/sheet_albedo.png", 320)
    prevs = [f"{PREV}/prev_{n}.png" for n in names if os.path.exists(f"{PREV}/prev_{n}.png")]
    contact_sheet(prevs, f"{PREV}/sheet_prev.png", 480)


if __name__ == "__main__":
    main(sys.argv[1:])

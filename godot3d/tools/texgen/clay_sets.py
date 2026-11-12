"""Sets de textura de arcilla gótica (láminas de referencia de Pablo, nov 2026).

Cada set genera dos PNG repetibles en art/tex/clay/:
  <set>_albedo.png  color (sRGB)
  <set>_detail.png  R,G = normal XY (perturbación a lo largo de +u/+v de la textura), B = altura 0..1
El shader look/clay.gdshader los usa con la MISMA proyección (detail_matched), así el relieve
coincide con el dibujo (juntas de ladrillo, grietas, puntadas).

Personaje (512 px; el albedo es gris ~0.8 y el color viene del color de vértice):
  piel    arcilla pálida: grumos, presiones de pulgar con huella, poros/agujeritos, marcas de espátula
  abrigo  textil de arcilla: poros, fibras, rayones y desgaste
  pelo    bloque de arcilla con surcos largos de espátula (mechones)
  lana    tejido de punto (V) con pelusa, para la bufanda
  cuero   cuero de arcilla envejecido: grietas, rayones, poros (bolso y zapatos)
Mapa (1024 px; el albedo lleva su propio color o un gris que tiñe el material original):
  ladrillo  ladrillos hechos a mano, juntas hondas, grietas, parches de pintura morada
  panete    pañete/fachada lisa con untadas de espátula y grietas finas
  asfalto   calzada de arcilla negra y gris con huellas de dedos y de zapato
  acera     losas de arcilla gris con bordes redondeados y grietas
Cielo: sky_clay.png (2048x1024 equirectangular) remolinos de arcilla púrpura y azul.

Uso:  python3 -I tools/texgen/clay_sets.py   (desde godot3d/)
"""
import os
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, map_coordinates

OUT = os.path.join("art", "tex", "clay")
os.makedirs(OUT, exist_ok=True)


# ------------------------------------------------------------------ utilidades
class Canvas:
    def __init__(self, n, seed):
        self.n = n
        self.rng = np.random.default_rng(seed)
        self.yy, self.xx = np.mgrid[0:n, 0:n].astype(np.float32)

    def noise(self, lo, hi, aniso=(1.0, 1.0)):
        """Ruido periódico de banda (lo..hi ciclos por tile). aniso estira x/y."""
        n = self.n
        w = self.rng.standard_normal((n, n)).astype(np.float32)
        f = np.fft.fft2(w)
        fy = np.fft.fftfreq(n)[:, None] * n * aniso[1]
        fx = np.fft.fftfreq(n)[None, :] * n * aniso[0]
        r = np.sqrt(fx * fx + fy * fy) + 1e-6
        mid = (lo + hi) * 0.5
        mask = np.exp(-((np.log(r) - np.log(mid)) ** 2) / (2 * 0.5 ** 2))
        out = np.real(np.fft.ifft2(f * mask)).astype(np.float32)
        out -= out.mean()
        return out / (np.abs(out).max() + 1e-6)

    def wd(self, a, c):
        d = a - c
        return (d + self.n / 2) % self.n - self.n / 2

    def presses(self, count, rmin, rmax, depth=(0.25, 0.6), prints=0.4, mask=None):
        """Presiones de pulgar: hundimiento elíptico con borde levantado y, a veces, huella."""
        h = np.zeros((self.n, self.n), np.float32)
        for _ in range(count):
            cx, cy = self.rng.uniform(0, self.n, 2)
            rx = self.rng.uniform(rmin, rmax)
            ry = rx * self.rng.uniform(0.55, 0.85)
            a = self.rng.uniform(0, np.pi)
            dx, dy = self.wd(self.xx, cx), self.wd(self.yy, cy)
            u = (dx * np.cos(a) + dy * np.sin(a)) / rx
            v = (-dx * np.sin(a) + dy * np.cos(a)) / ry
            d = np.sqrt(u * u + v * v)
            dp = self.rng.uniform(*depth)
            h += -dp * np.exp(-(d ** 2) * 1.8) + 0.3 * dp * np.exp(-((d - 1.05) ** 2) / 0.05)
            if self.rng.random() < prints:
                ridges = np.sin(d * self.rng.uniform(24, 32) + 0.7 * np.sin(u * 2.5 + v))
                h += 0.05 * ridges * np.exp(-(d ** 2) * 2.0) * np.clip((d - 0.15) / 0.3, 0, 1)
        if mask is not None:
            h *= mask
        return h

    def pits(self, count, rmin, rmax):
        """Agujeritos/poros (alturas negativas)."""
        h = np.zeros((self.n, self.n), np.float32)
        xs = self.rng.uniform(0, self.n, count)
        ys = self.rng.uniform(0, self.n, count)
        rs = self.rng.uniform(rmin, rmax, count)
        img = Image.new("F", (self.n, self.n), 0.0)
        dr = ImageDraw.Draw(img)
        for x, y, r in zip(xs, ys, rs):
            for ox in (-self.n, 0, self.n):
                for oy in (-self.n, 0, self.n):
                    dr.ellipse([x + ox - r, y + oy - r, x + ox + r, y + oy + r], fill=1.0)
        m = gaussian_filter(np.asarray(img, np.float32), max(rmin * 0.5, 0.6), mode="wrap")
        return -m

    def lines(self, count, length, width, wobble=0.25, angle=None, angle_jit=np.pi, steps=8):
        """Trazos (grietas, rayones, fibras): devuelve máscara 0..1 suavizada."""
        img = Image.new("F", (self.n, self.n), 0.0)
        dr = ImageDraw.Draw(img)
        for _ in range(count):
            x, y = self.rng.uniform(0, self.n, 2)
            a = self.rng.uniform(0, 2 * np.pi) if angle is None else angle + self.rng.uniform(-angle_jit, angle_jit)
            L = self.rng.uniform(*length) if isinstance(length, tuple) else length
            pts = [(x, y)]
            for _ in range(steps):
                a += self.rng.normal(0, wobble)
                x += np.cos(a) * L / steps
                y += np.sin(a) * L / steps
                pts.append((x, y))
            w = self.rng.uniform(*width) if isinstance(width, tuple) else width
            for ox in (-self.n, 0, self.n):
                for oy in (-self.n, 0, self.n):
                    dr.line([(px + ox, py + oy) for px, py in pts], fill=1.0, width=max(1, int(round(w))))
        return gaussian_filter(np.asarray(img, np.float32), 0.8, mode="wrap")


def norm01(h):
    return (h - h.min()) / (h.max() - h.min() + 1e-6)


def save_set(name, albedo, height, strength):
    """albedo: (n,n,3) lineal-ish 0..1 (se guarda tal cual como sRGB); height: (n,n)."""
    h = norm01(height)
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = 1.0 / np.sqrt(gx * gx + gy * gy + 1.0)
    det = np.stack([-gx * nz * 0.5 + 0.5, -gy * nz * 0.5 + 0.5, h], -1)
    Image.fromarray((np.clip(det, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(OUT, name + "_detail.png"), optimize=True)
    Image.fromarray((np.clip(albedo, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(OUT, name + "_albedo.png"), optimize=True)
    print("ok", name, albedo.shape[0], "mean", np.round(albedo.reshape(-1, 3).mean(0), 3))


def grey(v):
    return np.stack([v, v, v], -1)


# ------------------------------------------------------------------ personaje
def piel():
    c = Canvas(512, 11)
    h = 0.5 * c.noise(2, 4) + 0.2 * c.noise(6, 12)
    h += c.presses(26, 22, 55, depth=(0.2, 0.45), prints=0.6)
    h += 0.5 * c.pits(160, 0.8, 2.2)
    h -= 0.25 * c.lines(10, (40, 110), (1, 2), wobble=0.12)
    h += 0.03 * c.noise(80, 160)
    v = 0.8 + 0.035 * c.noise(3, 8) + 0.015 * c.noise(30, 60)
    alb = grey(v)
    low = np.clip((0.45 - norm01(h)) / 0.2, 0, 1)
    alb *= (1 - 0.18 * low)[..., None]
    alb *= np.array([1.0, 0.985, 0.99])        # gris ceniza muy leve en lo hundido
    save_set("piel", alb, h, 7.0)


def abrigo():
    c = Canvas(512, 21)
    h = 0.45 * c.noise(2, 5) + 0.15 * c.noise(10, 20)
    h += 0.7 * c.pits(1400, 0.7, 1.8)                     # poros del textil
    fib = c.lines(500, (6, 18), (1, 1), wobble=0.5, steps=3)
    h += 0.25 * fib
    h -= 0.5 * c.lines(7, (60, 160), (1, 3), wobble=0.1)  # rayones de espátula
    h += c.presses(12, 30, 70, depth=(0.15, 0.35), prints=0.3)
    v = 0.78 + 0.05 * c.noise(2, 6) + 0.03 * c.noise(20, 40)
    v += 0.16 * np.clip(fib, 0, 1)                         # fibras claras (polvo)
    low = np.clip((0.42 - norm01(h)) / 0.25, 0, 1)
    v *= 1 - 0.25 * low
    save_set("abrigo", grey(v), h, 6.0)


def pelo():
    c = Canvas(512, 31)
    h = 0.3 * c.noise(2, 5, aniso=(1.0, 0.25))
    grooves = c.lines(70, (80, 260), (4, 9), wobble=0.06, angle=np.pi / 2, angle_jit=0.35, steps=6)
    fine = c.lines(160, (30, 120), (1, 2), wobble=0.08, angle=np.pi / 2, angle_jit=0.3, steps=4)
    h -= 0.9 * gaussian_filter(grooves, 1.5, mode="wrap") + 0.35 * fine
    h += 0.25 * c.noise(20, 40, aniso=(1.0, 0.2))
    h += c.presses(6, 25, 50, depth=(0.15, 0.3), prints=0.5)
    hn = norm01(h)
    v = 0.62 + 0.36 * hn ** 1.4                             # crestas claras (polvo mate), surcos oscuros
    save_set("pelo", grey(v), h, 8.0)


def lana():
    c = Canvas(512, 41)
    cols, rows = 10, 16
    cw, rh = 512 / cols, 512 / rows
    h = np.zeros((512, 512), np.float32)
    # cada punto de tejido = dos "piernas" inclinadas formando una V
    jx = c.noise(4, 8) * 3.0
    jy = c.noise(4, 8) * 3.0
    X = (c.xx + jx) % 512
    Y = (c.yy + jy) % 512
    col = np.floor(X / cw)
    row = np.floor(Y / rh)
    lx = X - (col + 0.5) * cw
    ly = Y - (row + 0.5) * rh
    for s in (-1, 1):
        cx = s * cw * 0.22
        u = lx - cx
        a = s * 0.55
        uu = (u * np.cos(a) + ly * np.sin(a)) / (cw * 0.26)
        vv = (-u * np.sin(a) + ly * np.cos(a)) / (rh * 0.62)
        d = uu * uu + vv * vv
        h = np.maximum(h, np.clip(1 - d, 0, 1) ** 0.6)
    fuzz = c.lines(900, (4, 10), (1, 1), wobble=0.8, steps=3)
    h += 0.12 * fuzz + 0.06 * c.noise(40, 90)
    hn = norm01(h)
    v = 0.6 + 0.32 * hn + 0.1 * np.clip(fuzz, 0, 1)
    save_set("lana", grey(v), h, 9.0)


def cuero():
    c = Canvas(512, 51)
    h = 0.45 * c.noise(2, 5) + 0.15 * c.noise(8, 16)
    cracks = c.lines(40, (20, 70), (1, 2), wobble=0.5, steps=6)
    h -= 0.6 * cracks
    h -= 0.4 * c.lines(8, (60, 140), (1, 3), wobble=0.1)
    h += 0.5 * c.pits(300, 0.6, 1.5)
    h += c.presses(10, 25, 60, depth=(0.15, 0.3), prints=0.4)
    worn = np.clip(c.noise(2, 5) * 1.5, 0, 1)
    v = 0.8 + 0.06 * c.noise(3, 8) + 0.12 * worn - 0.3 * np.clip(cracks, 0, 1)
    save_set("cuero", grey(v), h, 6.0)


# ------------------------------------------------------------------ mapa
def ladrillo():
    n = 1024
    c = Canvas(n, 61)
    rows, cols = 10, 4
    rh, bw = n / rows, n / cols
    wx = c.noise(3, 8) * 7.0
    wy = c.noise(3, 8) * 5.0
    X = c.xx + wx
    Y = c.yy + wy
    row = np.floor(Y / rh) % rows
    rowj = c.rng.uniform(-0.18, 0.18, rows)
    Xs = X + (row % 2) * bw * 0.5 + rowj[row.astype(int)] * bw
    col = np.floor(Xs / bw) % cols
    lx = np.mod(Xs, bw)
    ly = np.mod(Y, rh)
    mort = 7.0
    edge = np.minimum(np.minimum(lx, bw - lx), np.minimum(ly, rh - ly)) - mort
    pillow = np.clip(edge / 16.0, 0, 1)
    pillow = pillow * pillow * (3 - 2 * pillow)
    bid = (row * cols + col).astype(int)
    rnd = c.rng.random((rows * cols, 4))
    h = pillow * (0.75 + 0.2 * rnd[bid, 0])
    h += (pillow > 0) * ((lx / bw - 0.5) * (rnd[bid, 1] - 0.5) * 0.15 + (ly / rh - 0.5) * (rnd[bid, 2] - 0.5) * 0.15)
    h += 0.06 * c.noise(6, 14) + 0.03 * c.noise(40, 80)
    h += 0.6 * c.presses(40, 18, 40, depth=(0.12, 0.3), prints=0.45, mask=pillow)
    cracks = c.lines(22, (60, 220), (2, 3), wobble=0.45, steps=9)
    h -= 0.35 * cracks * pillow
    h += 0.4 * c.pits(500, 0.8, 2.0) * pillow
    # color: terracota → rosa polvoso → café, parches de pintura morada (lámina "adobe / ladrillo")
    terra = np.array([0.6, 0.31, 0.24])
    rose = np.array([0.62, 0.38, 0.34])
    brown = np.array([0.45, 0.25, 0.2])
    k1, k2 = rnd[bid, 3][..., None], rnd[bid, 0][..., None]
    base = terra * (1 - k1) + rose * k1
    base = base * (1 - 0.35 * k2) + brown * 0.35 * k2
    purple = np.array([0.42, 0.26, 0.42])
    pm = np.clip((c.noise(1.5, 3) + 0.05) * 3.0, 0, 1)
    pm = pm * np.clip(0.6 + 0.6 * c.noise(20, 50), 0, 1)
    base = base * (1 - pm[..., None]) + purple * pm[..., None]
    base *= (0.92 + 0.08 * c.noise(10, 30))[..., None]
    mortar = np.array([0.32, 0.27, 0.27]) * (0.9 + 0.1 * c.noise(20, 40))[..., None]
    alb = base * pillow[..., None] ** 0.35 + mortar * (1 - pillow[..., None] ** 0.35)
    alb *= (1 - 0.35 * np.clip(cracks, 0, 1))[..., None]
    save_set("ladrillo", alb, h, 10.0)


def panete():
    n = 1024
    c = Canvas(n, 71)
    h = 0.45 * c.noise(2, 5) + 0.18 * c.noise(6, 14)
    # untadas de espátula: parches alargados con borde levantado
    for _ in range(60):
        cx, cy = c.rng.uniform(0, n, 2)
        L, W = c.rng.uniform(60, 180), c.rng.uniform(18, 45)
        a = c.rng.uniform(0, np.pi)
        dx, dy = c.wd(c.xx, cx), c.wd(c.yy, cy)
        u = (dx * np.cos(a) + dy * np.sin(a)) / L
        v = (-dx * np.sin(a) + dy * np.cos(a)) / W
        d = np.sqrt(u * u + v * v)
        s = c.rng.uniform(0.1, 0.25)
        h += s * np.clip(1 - d, 0, 1) ** 0.4 * (0.6 + 0.4 * np.clip(u + 0.5, 0, 1)) - 0.5 * s * np.exp(-((d - 1.0) ** 2) / 0.01)
    h += c.presses(30, 25, 70, depth=(0.1, 0.25), prints=0.35)
    cracks = c.lines(14, (80, 260), (1, 2), wobble=0.5, steps=10)
    h -= 0.3 * cracks
    h -= 0.25 * c.lines(10, (60, 180), (1, 2), wobble=0.08)
    v = 0.8 + 0.05 * c.noise(2, 6) + 0.02 * c.noise(20, 50) - 0.25 * np.clip(cracks, 0, 1)
    save_set("panete", grey(v), h, 7.0)


def asfalto():
    n = 1024
    c = Canvas(n, 81)
    h = 0.5 * c.noise(2, 5) + 0.25 * c.noise(6, 14)
    smear = c.noise(4, 10, aniso=(1.0, 0.3))
    h += 0.15 * smear
    h += c.presses(60, 22, 60, depth=(0.15, 0.35), prints=0.55)
    h += 0.5 * c.pits(900, 0.8, 2.5)
    h -= 0.3 * c.lines(16, (40, 140), (1, 2), wobble=0.5, steps=8)
    # huellas de zapato (suela con rayas)
    for _ in range(4):
        cx, cy = c.rng.uniform(0, n, 2)
        a = c.rng.uniform(0, np.pi)
        dx, dy = c.wd(c.xx, cx), c.wd(c.yy, cy)
        u = (dx * np.cos(a) + dy * np.sin(a)) / 70.0
        v = (-dx * np.sin(a) + dy * np.cos(a)) / 26.0
        sole = np.clip(1 - (u * u + v * v * (1.0 + 0.4 * u)), 0, 1)
        tread = 0.5 + 0.5 * np.sin(u * 40.0)
        h -= 0.25 * (sole > 0) * (0.6 + 0.4 * tread) * np.clip(sole * 6, 0, 1)
    v = 0.15 + 0.035 * c.noise(3, 8) + 0.05 * np.clip(smear, 0, 1) + 0.015 * c.noise(40, 90)
    alb = np.stack([v * 0.97, v * 0.95, v * 1.02], -1)
    save_set("asfalto", alb, h, 7.0)


def acera():
    n = 1024
    c = Canvas(n, 91)
    slabs = 2
    sw = n / slabs
    X = c.xx + c.noise(3, 6) * 6
    Y = c.yy + c.noise(3, 6) * 6
    lx, ly = np.mod(X, sw), np.mod(Y, sw)
    edge = np.minimum(np.minimum(lx, sw - lx), np.minimum(ly, sw - ly)) - 6.0
    pillow = np.clip(edge / 30.0, 0, 1)
    pillow = pillow * pillow * (3 - 2 * pillow)
    sid = (np.floor(X / sw) % slabs * slabs + np.floor(Y / sw) % slabs).astype(int)
    rnd = c.rng.random((slabs * slabs, 2))
    h = pillow * (0.8 + 0.1 * rnd[sid, 0]) + 0.08 * c.noise(3, 8) + 0.03 * c.noise(30, 60)
    h += 0.7 * c.presses(30, 25, 60, depth=(0.1, 0.25), prints=0.4, mask=pillow)
    cracks = c.lines(10, (120, 380), (2, 3), wobble=0.45, steps=12)
    h -= 0.35 * cracks * pillow
    h += 0.3 * c.pits(300, 0.8, 2.0)
    v = 0.56 + 0.04 * (rnd[sid, 1] - 0.5) + 0.035 * c.noise(2, 6) + 0.015 * c.noise(30, 60)
    v *= 1 - 0.35 * (1 - pillow) - 0.3 * np.clip(cracks, 0, 1)
    save_set("acera", grey(v), h, 8.0)


# ------------------------------------------------------------------ cielo
def cielo():
    """Panorama equirectangular de remolinos de arcilla púrpura y azul con relieve."""
    W, H = 2048, 1024
    rng = np.random.default_rng(101)

    def per_noise(lo, hi):
        w = rng.standard_normal((H, W)).astype(np.float32)
        f = np.fft.fft2(w)
        fy = np.fft.fftfreq(H)[:, None] * H
        fx = np.fft.fftfreq(W)[None, :] * W
        r = np.sqrt(fx * fx + fy * fy) + 1e-6
        mid = (lo + hi) * 0.5
        m = np.exp(-((np.log(r) - np.log(mid)) ** 2) / (2 * 0.5 ** 2))
        o = np.real(np.fft.ifft2(f * m)).astype(np.float32)
        return o / (np.abs(o).max() + 1e-6)

    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # remolinos: varias pasadas de deformación del dominio (como arcilla amasada)
    t = per_noise(1.5, 4)
    for k in range(4):
        a = per_noise(1.5, 4) * 2 * np.pi
        dx = np.cos(a + t * 2.5) * 70
        dy = np.sin(a + t * 2.5) * 35
        t = map_coordinates(t, [(yy + dy) % H, (xx + dx) % W], order=1, mode="wrap")
        t += 0.15 * per_noise(3, 6)
    t = gaussian_filter(t, 2.0, mode="wrap")
    bands = np.sin(t * 7.0)                        # rollos de arcilla
    hgt = 0.5 + 0.5 * np.sign(bands) * np.abs(bands) ** 0.6
    hgt = gaussian_filter(hgt, 2.5, mode="wrap")
    # colores: índigo, púrpura, azul y lavanda
    cols = np.array([[0.12, 0.08, 0.25], [0.3, 0.18, 0.46], [0.2, 0.26, 0.52], [0.4, 0.33, 0.6]])
    s = (np.sin(t * 2.6 + 1.0) * 0.5 + 0.5)
    idx = s * (len(cols) - 1)
    i0 = np.floor(idx).astype(int).clip(0, len(cols) - 2)
    f = (idx - i0)[..., None]
    col = cols[i0] * (1 - f) + cols[i0 + 1] * f
    # relieve (luz desde arriba) y sombra en los surcos
    gy = np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)
    gx = np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)
    lit = np.clip(0.85 - gy * 9.0 + gx * 3.0, 0.55, 1.12)
    col = col * lit[..., None] * (0.75 + 0.35 * hgt[..., None])
    # degradado: cenit oscuro, horizonte más claro y neblinoso, suelo oscuro
    lat = 1.0 - yy / (H - 1) * 2.0               # 1 arriba, 0 horizonte, -1 abajo
    up = np.clip(lat, 0, 1)[..., None]
    col = col * (1.0 - 0.45 * up ** 1.5)
    # cerca del cenit el panorama se estira: se funde a un índigo liso
    pole = np.clip((lat - 0.55) / 0.35, 0, 1)[..., None] ** 1.5
    col = col * (1 - pole) + np.array([0.1, 0.07, 0.2]) * pole
    haze = np.array([0.42, 0.33, 0.55])
    hz = np.exp(-(np.abs(lat) / 0.08) ** 1.2)[..., None]
    col = col * (1 - 0.55 * hz) + haze * 0.55 * hz
    below = np.clip(-lat * 6, 0, 1)[..., None]
    col = col * (1 - below) + np.array([0.08, 0.06, 0.1]) * below
    Image.fromarray((np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(OUT, "sky_clay.png"), optimize=True)
    print("ok cielo")


if __name__ == "__main__":
    import sys
    todo = sys.argv[1:] or ["piel", "abrigo", "pelo", "lana", "cuero", "ladrillo", "panete", "asfalto", "acera", "cielo"]
    for name in todo:
        globals()[name]()

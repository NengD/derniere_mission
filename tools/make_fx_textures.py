"""Textures d'effets dessinées par script (aucune ressource externe).

Usage : python tools/make_fx_textures.py
Sorties (assets/fx/) :
  sang_eclaboussure.png  éclaboussure de sang pour les murs et le sol (décalque)
  sang_flaque.png        flaque
  tag_cercle.png         tag peint à la bombe du cartel « El Círculo de Cobre »
  flash_canon.png        étoile de flash de bouche
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "assets", "fx")


def splatter(seed, size=1024):
    rnd = random.Random(seed)
    a = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(a)
    c = size / 2
    # cœur
    for _ in range(40):
        r = rnd.uniform(0.04, 0.13) * size
        x = c + rnd.gauss(0, 0.05) * size
        y = c + rnd.gauss(0, 0.05) * size
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    # projections dans une direction dominante
    ang0 = rnd.uniform(0, math.tau)
    for _ in range(260):
        ang = ang0 + rnd.gauss(0, 0.7)
        dist = abs(rnd.gauss(0, 0.22)) * size
        r = max(1.5, rnd.uniform(0.002, 0.022) * size * (1 - dist / size))
        x = c + math.cos(ang) * dist
        y = c + math.sin(ang) * dist
        d.ellipse((x - r, y - r * rnd.uniform(0.5, 1), x + r, y + r), fill=255)
    # coulures vers le bas
    for _ in range(14):
        x = c + rnd.gauss(0, 0.09) * size
        y0 = c + rnd.uniform(-0.05, 0.08) * size
        ln = rnd.uniform(0.08, 0.38) * size
        w = rnd.uniform(3, 9)
        d.line((x, y0, x + rnd.uniform(-4, 4), y0 + ln), fill=255, width=int(w))
        d.ellipse((x - w, y0 + ln - w, x + w, y0 + ln + w), fill=255)
    a = a.filter(ImageFilter.GaussianBlur(1.2))
    rgba = Image.new("RGBA", (size, size))
    px = rgba.load()
    ap = a.load()
    for y in range(size):
        for x in range(size):
            v = ap[x, y]
            if v:
                k = rnd.uniform(0.85, 1.0)
                px[x, y] = (int(92 * k), int(6 * k), int(8 * k), min(255, int(v * 1.1)))
    return rgba


def puddle(seed, size=512):
    rnd = random.Random(seed)
    a = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(a)
    c = size / 2
    for _ in range(26):
        r = rnd.uniform(0.08, 0.2) * size
        x = c + rnd.gauss(0, 0.09) * size
        y = c + rnd.gauss(0, 0.09) * size
        d.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=255)
    a = a.filter(ImageFilter.GaussianBlur(4)).point(lambda v: 255 if v > 120 else int(v * 1.5))
    rgba = Image.merge("RGBA", (Image.new("L", a.size, 60), Image.new("L", a.size, 3), Image.new("L", a.size, 4), a))
    return rgba


def tag(size=1024):
    """Logo du cartel : un anneau de cuivre ouvert, barré d'un trait vertical, et ses initiales."""
    rnd = random.Random(7)
    a = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(a)
    c = size / 2
    r = size * 0.3
    # anneau ouvert en haut à droite (peinture à la bombe = beaucoup de petits points)
    for _ in range(60000):
        ang = rnd.uniform(math.radians(-50), math.radians(250))
        rr = r + rnd.gauss(0, size * 0.018)
        x = c + math.cos(ang) * rr
        y = c - math.sin(ang) * rr
        d.point((x, y), fill=255)
    for _ in range(26000):
        x = c + rnd.gauss(0, size * 0.014)
        y = rnd.uniform(c - r * 1.25, c + r * 1.25)
        d.point((x, y), fill=255)
    # coulures
    for _ in range(9):
        x = c + rnd.uniform(-r, r)
        y0 = c + rnd.uniform(0, r)
        d.line((x, y0, x, y0 + rnd.uniform(40, 160)), fill=200, width=4)
    a = a.filter(ImageFilter.GaussianBlur(2.2)).point(lambda v: min(255, v * 2))
    rgba = Image.merge("RGBA", (Image.new("L", a.size, 150), Image.new("L", a.size, 62), Image.new("L", a.size, 30), a))
    return rgba


def flash(size=256):
    a = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(a)
    c = size / 2
    rnd = random.Random(3)
    for i in range(5):
        ang = i * math.tau / 5 + rnd.uniform(-0.2, 0.2)
        ln = size * rnd.uniform(0.35, 0.48)
        w = size * 0.05
        pts = [(c + math.cos(ang + 1.57) * w, c + math.sin(ang + 1.57) * w),
               (c + math.cos(ang) * ln, c + math.sin(ang) * ln),
               (c + math.cos(ang - 1.57) * w, c + math.sin(ang - 1.57) * w)]
        d.polygon(pts, fill=255)
    d.ellipse((c - size * 0.13, c - size * 0.13, c + size * 0.13, c + size * 0.13), fill=255)
    a = a.filter(ImageFilter.GaussianBlur(5))
    return Image.merge("RGBA", (Image.new("L", a.size, 255), Image.new("L", a.size, 190), Image.new("L", a.size, 110), a))


def main():
    os.makedirs(OUT, exist_ok=True)
    splatter(11).save(os.path.join(OUT, "sang_eclaboussure.png"))
    puddle(5).save(os.path.join(OUT, "sang_flaque.png"))
    tag().save(os.path.join(OUT, "tag_cercle.png"))
    flash().save(os.path.join(OUT, "flash_canon.png"))
    print("ok", os.listdir(OUT))


if __name__ == "__main__":
    main()

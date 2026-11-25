"""Textures d'effets dessinées par script (aucune ressource externe).

Usage : python tools/make_fx_textures.py
Sorties (assets/fx/) :
  sang_eclaboussure.png  éclaboussure de sang pour les murs et le sol (décalque)
  sang_flaque.png        flaque
  tag_cercle.png         tag peint à la bombe du cartel « El Círculo de Cobre »
  flash_canon.png        étoile de flash de bouche
  impact_balle.png       trou de balle dans le béton (décalque : trou, éclats, auréole de poussière)
  fumee.png              bouffée de fumée douce (particules : canon, poussière d'impact)

Usage partiel : python tools/make_fx_textures.py impact_balle fumee
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


def bullet_hole(size=256):
    """Trou de balle : centre noir, cratère d'éclats irrégulier, fissures fines, auréole claire de poussière."""
    rnd = random.Random(21)
    c = size / 2
    alpha = Image.new("L", (size, size), 0)
    col = Image.new("L", (size, size), 0)
    da = ImageDraw.Draw(alpha)
    dc = ImageDraw.Draw(col)
    # auréole de poussière (claire, très transparente)
    halo = Image.new("L", (size, size), 0)
    dh = ImageDraw.Draw(halo)
    for _ in range(60):
        ang = rnd.uniform(0, math.tau)
        r = rnd.uniform(0.05, 0.36) * size
        x, y = c + math.cos(ang) * r * 0.6, c + math.sin(ang) * r * 0.6
        rr = rnd.uniform(0.02, 0.07) * size
        dh.ellipse((x - rr, y - rr, x + rr, y + rr), fill=rnd.randint(30, 80))
    halo = halo.filter(ImageFilter.GaussianBlur(size * 0.03))
    # cratère : polygone irrégulier (éclats de béton arrachés)
    pts = []
    n = 22
    for i in range(n):
        ang = i * math.tau / n
        r = size * rnd.uniform(0.11, 0.2)
        pts.append((c + math.cos(ang) * r, c + math.sin(ang) * r))
    da.polygon(pts, fill=235)
    dc.polygon(pts, fill=95)
    # fissures
    for _ in range(7):
        ang = rnd.uniform(0, math.tau)
        x, y = c, c
        r0 = size * 0.12
        x += math.cos(ang) * r0
        y += math.sin(ang) * r0
        for _ in range(4):
            ang += rnd.uniform(-0.5, 0.5)
            ln = size * rnd.uniform(0.03, 0.07)
            x2, y2 = x + math.cos(ang) * ln, y + math.sin(ang) * ln
            da.line((x, y, x2, y2), fill=200, width=2)
            dc.line((x, y, x2, y2), fill=40, width=2)
            x, y = x2, y2
    # fond du trou, noir
    r = size * 0.055
    da.ellipse((c - r, c - r, c + r, c + r), fill=255)
    dc.ellipse((c - r, c - r, c + r, c + r), fill=8)
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.2))
    col = col.filter(ImageFilter.GaussianBlur(1.5))
    # composition : le halo clair là où il n'y a pas de cratère
    hal_rgb = Image.new("L", (size, size), 175)
    v = Image.composite(col, hal_rgb, alpha.point(lambda p: 255 if p > 20 else 0))
    alpha = Image.composite(alpha, halo, alpha.point(lambda p: 255 if p > 20 else 0))
    return Image.merge("RGBA", (v, v, Image.eval(v, lambda p: int(p * 0.95)), alpha))


def smoke(size=256):
    """Bouffée de fumée : bruit doux dans un disque flou."""
    rnd = random.Random(8)
    a = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(a)
    c = size / 2
    for _ in range(70):
        ang = rnd.uniform(0, math.tau)
        r = abs(rnd.gauss(0, 0.16)) * size
        x, y = c + math.cos(ang) * r, c + math.sin(ang) * r
        rr = rnd.uniform(0.05, 0.14) * size
        d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=rnd.randint(25, 70))
    a = a.filter(ImageFilter.GaussianBlur(size * 0.045))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((size * 0.08, size * 0.08, size * 0.92, size * 0.92), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(size * 0.12))
    a = Image.composite(a, Image.new("L", a.size, 0), mask)
    a = a.point(lambda p: min(255, int(p * 2.4)))
    return Image.merge("RGBA", (Image.new("L", a.size, 220), Image.new("L", a.size, 220), Image.new("L", a.size, 220), a))


SORTIES = {
    "sang_eclaboussure": lambda: splatter(11),
    "sang_flaque": lambda: puddle(5),
    "tag_cercle": tag,
    "flash_canon": flash,
    "impact_balle": bullet_hole,
    "fumee": smoke,
}


def main():
    import sys
    os.makedirs(OUT, exist_ok=True)
    noms = sys.argv[1:] or list(SORTIES)
    for n in noms:
        SORTIES[n]().save(os.path.join(OUT, n + ".png"))
    print("ok", noms)


if __name__ == "__main__":
    main()

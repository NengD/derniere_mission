"""Textures d'effets dessinées par script (aucune ressource externe).

Usage : python tools/make_fx_textures.py
Sorties (assets/fx/) :
  sang_eclaboussure.png  éclaboussure de sang pour les murs et le sol (décalque)
  sang_flaque.png        flaque
  tag_cercle.png         tag peint à la bombe du cartel « El Círculo de Cobre »
  flash_canon.png        flamme de bouche vue de face : 4 variantes (atlas 2 × 2), fleur de gaz chauds sans branches
  flamme_bouche.png      flamme de bouche vue de côté : 4 variantes empilées (atlas 1 × 4), bouche à gauche
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


def _couleur_flamme(a):
    """Intensité → flamme : cœur blanc-jaune, bords orange puis rouge sombre (canal alpha = intensité)."""
    r = a.point(lambda v: min(255, int(v * 1.9)))
    g = a.point(lambda v: min(255, int(255 * (v / 255.0) ** 1.35 * 1.35)))
    b = a.point(lambda v: min(255, int(255 * (v / 255.0) ** 3.2 * 1.2)))
    return Image.merge("RGBA", (r, g, b, a))


def _flamme_cote(rnd, w, h):
    """Bouffée de gaz vue de côté : jet étroit à la bouche (x = 0), qui s'ouvre en boule irrégulière,
    quelques langues latérales. Pas d'étoile ni de traits nets."""
    a = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(a)
    cy = h / 2
    long = rnd.uniform(0.62, 0.92) * w
    # jet : chapelet d'ellipses de plus en plus larges
    n = 28
    for i in range(n):
        u = i / (n - 1)
        x = u * long * 0.55
        r = h * (0.05 + 0.16 * u) * rnd.uniform(0.8, 1.15)
        y = cy + rnd.gauss(0, h * 0.02)
        d.ellipse((x - r * 1.4, y - r, x + r * 1.4, y + r), fill=int(140 + 115 * (1 - u) ** 2))
    # boule de gaz (zone de détente), irrégulière
    bx = long * rnd.uniform(0.5, 0.62)
    for _ in range(26):
        r = h * rnd.uniform(0.07, 0.2)
        x = min(long * 0.85, bx + rnd.gauss(0, long * 0.08))
        y = cy + rnd.gauss(0, h * 0.09)
        d.ellipse((x - r, y - r, x + r, y + r), fill=rnd.randint(90, 190))
    # langues latérales (gaz qui s'échappent en biais), douces
    for _ in range(rnd.randint(2, 4)):
        ang = rnd.choice((-1, 1)) * rnd.uniform(0.35, 0.8)
        ln = long * rnd.uniform(0.25, 0.45)
        x0 = long * rnd.uniform(0.05, 0.2)
        for k in range(10):
            u = k / 9
            x = x0 + math.cos(ang) * ln * u
            y = cy + math.sin(ang) * ln * u * (h / w) * 3.0
            r = h * (0.03 + 0.06 * u)
            d.ellipse((x - r, y - r, x + r, y + r), fill=int(120 * (1 - 0.6 * u)))
    a = a.filter(ImageFilter.GaussianBlur(h * 0.05))
    # bords fondus (aucune coupure nette sur le quad)
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse((-w * 0.1, h * 0.04, w * 0.98, h * 0.96), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(h * 0.08))
    return Image.composite(a, Image.new("L", (w, h), 0), m)


def flamme_bouche(w=512, h=128):
    out = Image.new("RGBA", (w, h * 4), (0, 0, 0, 0))
    for i in range(4):
        out.paste(_couleur_flamme(_flamme_cote(random.Random(40 + i), w, h)), (0, i * h))
    return out


def _flamme_face(rnd, size):
    """Bouffée vue de face : disque chaud irrégulier, 4 à 6 lobes doux (pas de branches d'étoile)."""
    a = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(a)
    c = size / 2
    r0 = size * 0.12
    d.ellipse((c - r0, c - r0, c + r0, c + r0), fill=235)
    n = rnd.randint(6, 9)
    a0 = rnd.uniform(0, math.tau)
    for i in range(n):
        ang = a0 + i * math.tau / n + rnd.uniform(-0.35, 0.35)
        for k in range(6):
            u = k / 5
            dist = size * (0.05 + 0.13 * u) * rnd.uniform(0.8, 1.15)
            r = size * (0.08 - 0.03 * u) * rnd.uniform(0.8, 1.2)
            x, y = c + math.cos(ang) * dist, c + math.sin(ang) * dist
            d.ellipse((x - r, y - r, x + r, y + r), fill=int(170 * (1 - 0.55 * u)))
    for _ in range(30):
        ang = rnd.uniform(0, math.tau)
        dist = abs(rnd.gauss(0, 0.13)) * size
        r = size * rnd.uniform(0.04, 0.09)
        x, y = c + math.cos(ang) * dist, c + math.sin(ang) * dist
        d.ellipse((x - r, y - r, x + r, y + r), fill=rnd.randint(60, 140))
    a = a.filter(ImageFilter.GaussianBlur(size * 0.04))
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).ellipse((size * 0.06, size * 0.06, size * 0.94, size * 0.94), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(size * 0.08))
    return Image.composite(a, Image.new("L", (size, size), 0), m)


def flash(size=256):
    out = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    for i in range(4):
        out.paste(_couleur_flamme(_flamme_face(random.Random(20 + i), size)), ((i % 2) * size, (i // 2) * size))
    return out


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
    "flamme_bouche": flamme_bouche,
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

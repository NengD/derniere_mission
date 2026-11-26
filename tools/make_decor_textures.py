"""Textures du kit de décor dessinées par script (aucune ressource externe sauf les polices
système pour peindre les textes des affiches : seule l'image produite est gardée).

Usage : python tools/make_decor_textures.py [nom ...]
Sorties (assets/decor/gen/) :
  macro_bruit.png          bruit raccordable 3 octaves (R grand, G moyen, B fin) : anti-répétition
  poussiere_1..3.png       plaques de poussière au sol (décalques)
  crasse_coin.png          crasse verticale dans les coins et derrière les objets
  crasse_sol_mur.png       bande de saleté au pied des murs (décalque au sol, le long du mur)
  tache_humidite_1..2.png  auréoles d'humidité brunes avec moisissures (plafond, murs)
  coulure_rouille.png      coulure de rouille sous un tuyau ou une gaine
  mouille_1..3.png         halo humide (sol assombri) autour des flaques
  flaque_1..3.png          flaque : eau sombre, alpha = masque (seuil) ; flaque_nor.png vaguelettes
  papier_1..4.png          papiers au sol : feuille froissée, ticket, journal, carton aplati
  megots.png               mégots et cendres écrasés (décalque)
  traces_pas.png           traces de semelles poussiéreuses
  affiche_recherche.png    avis de recherche de la police (espagnol fictif)
  affiche_pub.png          publicité locale (radio-taxi fictif)
  affiche_securite.png     consignes de sécurité de l'aéroport de fret (fictif)
  panneau_fumer.png        « PROHIBIDO FUMAR »
  affiche_lambeaux.png     restes d'une vieille affiche arrachée
  tag_cartel_2.png         « AQUÍ MANDA EL CÍRCULO » + anneau « C°C »
  tag_cartel_3.png         « C°C 13 » au pochoir, coulures
  eraflures.png            traces de caoutchouc et éraflures au bas des murs
  grillage_cables.png      fond de chemin de câbles en fil (alpha à seuil)
  *_nor.png                normales (papier froissé, affiches) à partir du relief
"""
import math
import os
import random
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "assets", "decor", "gen")
FONTS = "C:/Windows/Fonts/" if os.name == "nt" else "/usr/share/fonts/truetype/"


def font(name, size):
    for n in (name, "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(FONTS + n, size)
        except OSError:
            continue
    return ImageFont.load_default()


# ---------------------------------------------------------------- bruits

def noise_tile(size, cells, seed, blur=0.0):
    """Bruit de valeur raccordable : petite grille aléatoire agrandie en bicubique (avec bord replié)."""
    rnd = random.Random(seed)
    small = Image.new("L", (cells, cells))
    small.putdata([rnd.randint(0, 255) for _ in range(cells * cells)])
    big = Image.new("L", (cells * 3, cells * 3))
    for i in range(3):
        for j in range(3):
            big.paste(small, (i * cells, j * cells))
    big = big.resize((size * 3, size * 3), Image.BICUBIC)
    out = big.crop((size, size, size * 2, size * 2))
    if blur:
        out = out.filter(ImageFilter.GaussianBlur(blur))
    return out


def fbm(size, seed, base=4, octaves=5, persist=0.55):
    acc = Image.new("F", (size, size), 0.0)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = noise_tile(size, base * 2 ** o, seed * 31 + o)
        acc = _addf(acc, n, amp)
        tot += amp
        amp *= persist
    return _normf(acc, tot)


def _addf(acc, n, amp):
    a = list(acc.getdata())
    b = n.getdata()
    acc.putdata([x + y * amp for x, y in zip(a, b)])
    return acc


def _normf(acc, tot):
    d = list(acc.getdata())
    lo, hi = min(d), max(d)
    k = 255.0 / max(1e-3, hi - lo)
    out = Image.new("L", acc.size)
    out.putdata([int((v - lo) * k) for v in d])
    return out


def contrast(img, lo, hi):
    """Remappe [lo, hi] → [0, 255] (niveaux)."""
    return img.point(lambda v: 0 if v <= lo else 255 if v >= hi else int((v - lo) * 255 / (hi - lo)))


def radial(size, power=1.6, squash=1.0):
    g = Image.new("L", (size, size))
    c = size / 2
    g.putdata([max(0, int(255 * (1 - min(1, math.hypot((x - c) / c, (y - c) / c / squash)) ** power)))
               for y in range(size) for x in range(size)])
    return g


def normal_from_height(h, strength=2.0):
    h = h.convert("L")
    dx = h.filter(ImageFilter.Kernel((3, 3), [-1, 0, 1, -2, 0, 2, -1, 0, 1], scale=8 / strength, offset=128))
    dy = h.filter(ImageFilter.Kernel((3, 3), [1, 2, 1, 0, 0, 0, -1, -2, -1], scale=8 / strength, offset=128))
    # dx = pente vers la droite ; normale OpenGL : R = -dh/dx, G = +dh/dy (haut de l'image)
    r = ImageOps.invert(dx)
    g = ImageOps.invert(dy)
    b = Image.new("L", h.size, 255)
    return Image.merge("RGB", (r, g, b))


def rgba(color_img, alpha):
    c = color_img.convert("RGB")
    return Image.merge("RGBA", (*c.split(), alpha))


def tint(gray, c0, c1):
    """Dégradé de deux couleurs piloté par un niveau de gris."""
    return Image.merge("RGB", [gray.point(lambda v, a=c0[i], b=c1[i]: int(a + (b - a) * v / 255)) for i in range(3)])


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    print("  ", name, img.size)


# ---------------------------------------------------------------- textures

def macro_bruit():
    r = fbm(512, 11, base=2, octaves=4)
    g = fbm(512, 23, base=6, octaves=4)
    b = fbm(512, 37, base=16, octaves=3)
    save(Image.merge("RGB", (r, g, b)), "macro_bruit.png")


def poussiere(i):
    s = 512
    n = fbm(s, 100 + i, base=3, octaves=5)
    m = ImageChops.multiply(radial(s, 1.2, 0.55 + 0.25 * i), contrast(n, 60, 200))
    m = m.point(lambda v: int(v * 0.85))
    col = tint(fbm(s, 140 + i, base=8, octaves=3), (70, 62, 52), (120, 110, 95))
    save(rgba(col, m.filter(ImageFilter.GaussianBlur(2))), "poussiere_%d.png" % i)


def crasse_coin():
    w, h = 256, 1024
    n = fbm(1024, 210, base=4, octaves=5).resize((w, h))
    g = Image.new("L", (w, h))
    g.putdata([int(255 * max(0, 1 - abs(x - w / 2) / (w / 2)) ** 1.5 * (0.35 + 0.65 * (y / h) ** 1.4))
               for y in range(h) for x in range(w)])
    a = ImageChops.multiply(g, contrast(n, 40, 220))
    save(rgba(tint(n, (25, 22, 18), (60, 52, 40)), a), "crasse_coin.png")


def crasse_sol_mur():
    w, h = 1024, 256
    n = fbm(1024, 230, base=6, octaves=5).resize((w, h))
    g = Image.new("L", (w, h))
    # mur en haut de l'image : saleté dense contre le mur, qui s'efface vers le milieu de la pièce
    g.putdata([int(255 * (1 - y / h) ** 1.8 * min(1, min(x, w - x) / 120)) for y in range(h) for x in range(w)])
    a = ImageChops.multiply(g, contrast(n, 30, 230))
    save(rgba(tint(n, (40, 35, 28), (85, 76, 62)), a), "crasse_sol_mur.png")


def tache_humidite(i):
    s = 1024
    rnd = random.Random(300 + i)
    n = fbm(s, 300 + i, base=3, octaves=6)
    base = ImageChops.multiply(radial(s, 0.9, 0.8 + 0.3 * i), n)
    # auréoles : lignes de niveau du bruit (dépôts bruns concentriques)
    rings = base.point(lambda v: int(255 * max(0, 1 - abs(((v / 255.0 * 5.0) % 1.0) - 0.5) * 8)) if v > 40 else 0)
    inner = contrast(base, 50, 150)
    alpha = ImageChops.lighter(inner.point(lambda v: int(v * 0.55)), rings.filter(ImageFilter.GaussianBlur(1.5)))
    col = tint(rings, (78, 66, 44), (60, 42, 20))
    # moisissures noires piquées
    d = ImageDraw.Draw(alpha)
    dc = ImageDraw.Draw(col)
    for _ in range(900):
        x, y = rnd.gauss(s / 2, s * 0.18), rnd.gauss(s / 2, s * 0.18)
        if base.getpixel((int(min(s - 1, max(0, x))), int(min(s - 1, max(0, y))))) < 70:
            continue
        r = rnd.uniform(0.6, 3.2)
        d.ellipse((x - r, y - r, x + r, y + r), fill=230)
        dc.ellipse((x - r, y - r, x + r, y + r), fill=(18, 20, 14))
    save(rgba(col, alpha.filter(ImageFilter.GaussianBlur(0.8))), "tache_humidite_%d.png" % i)


def coulure_rouille():
    w, h = 256, 1024
    rnd = random.Random(410)
    a = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(a)
    for _ in range(26):
        x = rnd.gauss(w / 2, w * 0.12)
        ln = rnd.uniform(0.2, 1.0) * h
        wd = rnd.uniform(2, 14)
        for y in range(0, int(ln), 4):
            k = 1 - y / ln
            x += rnd.gauss(0, 0.6)
            d.ellipse((x - wd * k, y, x + wd * k, y + 6), fill=int(150 * k + 60))
    a = a.filter(ImageFilter.GaussianBlur(3))
    n = fbm(1024, 411, base=8, octaves=4).resize((w, h))
    save(rgba(tint(n, (70, 32, 12), (125, 62, 24)), ImageChops.multiply(a, contrast(n, 20, 200))), "coulure_rouille.png")


def mouille(i):
    s = 512
    n = fbm(s, 500 + i, base=3, octaves=5)
    m = ImageChops.multiply(radial(s, 0.8, 0.6 + 0.2 * i), n)
    a = contrast(m, 30, 120)
    save(rgba(Image.new("RGB", (s, s), (14, 12, 10)), a.point(lambda v: int(v * 0.75))), "mouille_%d.png" % i)


def flaque(i):
    s = 512
    n = fbm(s, 600 + i, base=3, octaves=5)
    m = ImageChops.multiply(radial(s, 0.7, 0.55 + 0.2 * i), n)
    a = contrast(m, 38, 70).filter(ImageFilter.GaussianBlur(1.5))
    # eau sombre (béton mouillé dessous) ; alpha = masque de l'eau (seuil dans le moteur)
    col = tint(fbm(s, 650 + i, base=8, octaves=3), (16, 15, 13), (34, 31, 27))
    save(rgba(col, a), "flaque_%d.png" % i)
    if i == 1:
        # vaguelettes et poussière flottante très faibles : le reflet n'est pas un miroir parfait
        save(normal_from_height(fbm(s, 660, base=12, octaves=3), 0.35), "flaque_nor.png")


def froisse(s, seed, plis=40):
    """Relief de papier froissé : facettes (droites aléatoires) + bruit fin."""
    rnd = random.Random(seed)
    h = Image.new("L", (s, s), 128)
    for _ in range(plis):
        x0, y0 = rnd.uniform(0, s), rnd.uniform(0, s)
        ang = rnd.uniform(0, math.pi)
        dx, dy = math.cos(ang), math.sin(ang)
        m = Image.new("L", (s, s), 0)
        ImageDraw.Draw(m).polygon([(x0 - dx * 2 * s, y0 - dy * 2 * s), (x0 + dx * 2 * s, y0 + dy * 2 * s),
                                   (x0 + dx * 2 * s - dy * 3 * s, y0 + dy * 2 * s + dx * 3 * s),
                                   (x0 - dx * 2 * s - dy * 3 * s, y0 - dy * 2 * s + dx * 3 * s)], fill=rnd.randint(4, 12))
        h = ImageChops.add(h, m) if rnd.random() < 0.5 else ImageChops.subtract(h, m)
    return h.filter(ImageFilter.GaussianBlur(1.2))


def contour_dechire(w, h, seed, marge=0.06, rugosite=0.035, trous=0):
    """Masque d'une feuille aux bords déchirés (et coins arrachés)."""
    rnd = random.Random(seed)
    pts = []
    n = 60
    for side in range(4):
        for k in range(n):
            t = k / n
            j = rnd.gauss(0, rugosite) * min(w, h)
            if side == 0:
                pts.append((marge * w + t * (1 - 2 * marge) * w, marge * h + j))
            elif side == 1:
                pts.append(((1 - marge) * w + j, marge * h + t * (1 - 2 * marge) * h))
            elif side == 2:
                pts.append(((1 - marge) * w - t * (1 - 2 * marge) * w, (1 - marge) * h + j))
            else:
                pts.append((marge * w + j, (1 - marge) * h - t * (1 - 2 * marge) * h))
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.polygon(pts, fill=255)
    # coins et lambeaux arrachés
    for _ in range(trous):
        cx, cy = rnd.choice([(0, 0), (w, 0), (w, h), (0, h), (rnd.uniform(0, w), h), (w, rnd.uniform(0, h))])
        r = rnd.uniform(0.12, 0.35) * min(w, h)
        poly = [(cx + math.cos(a) * r * rnd.uniform(0.6, 1.3), cy + math.sin(a) * r * rnd.uniform(0.6, 1.3))
                for a in [i * math.tau / 24 for i in range(24)]]
        d.polygon(poly, fill=0)
    return m.filter(ImageFilter.GaussianBlur(0.7))


def vieillir(img, seed, jaunir=0.25, sale=0.35):
    """Papier exposé : jauni, décoloré, taches et traces de scotch, grain de photocopie."""
    w, h = img.size
    n = fbm(256, seed, base=3, octaves=5).resize((w, h), Image.BICUBIC)
    jaune = Image.new("RGB", (w, h), (196, 178, 130))
    img = Image.blend(img.convert("RGB"), jaune, jaunir)
    sal = tint(n, (90, 78, 58), (235, 225, 200))
    img = ImageChops.multiply(img, Image.blend(Image.new("RGB", (w, h), (255, 255, 255)), sal, sale))
    grain = Image.effect_noise((w, h), 18).convert("RGB")
    img = Image.blend(img, ImageChops.multiply(img, ImageOps.autocontrast(grain)), 0.12)
    return img


def scotch(img, alpha, seed):
    rnd = random.Random(seed)
    w, h = img.size
    d = ImageDraw.Draw(img)
    da = ImageDraw.Draw(alpha)
    for (cx, cy) in [(0.08, 0.06), (0.92, 0.06), (0.1, 0.94), (0.9, 0.93)]:
        if rnd.random() < 0.3:
            continue
        x, y = cx * w, cy * h
        tw, th = w * 0.12, h * 0.035
        ang = rnd.uniform(-0.6, 0.6) + (0.78 if cx < 0.5 else -0.78)
        poly = [(x + math.cos(ang) * a - math.sin(ang) * b, y + math.sin(ang) * a + math.cos(ang) * b)
                for a, b in [(-tw, -th), (tw, -th), (tw, th), (-tw, th)]]
        d.polygon(poly, fill=(168, 150, 98))
        da.polygon(poly, fill=235)


def portrait(w, h, seed):
    """Photo de visage photocopiée (formes simples, trame et contraste : illisible de près comme en vrai)."""
    rnd = random.Random(seed)
    im = Image.new("L", (w, h), 170)
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, w, h), fill=150)
    d.ellipse((w * 0.08, h * 0.72, w * 0.92, h * 1.5), fill=55)                  # épaules
    d.rectangle((w * 0.38, h * 0.55, w * 0.62, h * 0.8), fill=95)               # cou
    d.ellipse((w * 0.26, h * 0.14, w * 0.74, h * 0.7), fill=118)                # visage
    d.chord((w * 0.24, h * 0.06, w * 0.76, h * 0.5), 180, 360, fill=35)         # cheveux
    d.rectangle((w * 0.33, h * 0.36, w * 0.45, h * 0.40), fill=40)              # yeux / sourcils
    d.rectangle((w * 0.55, h * 0.36, w * 0.67, h * 0.40), fill=40)
    d.line((w * 0.5, h * 0.4, w * 0.47, h * 0.52), fill=80, width=3)
    d.ellipse((w * 0.32, h * 0.52, w * 0.68, h * 0.7), fill=70)                 # barbe
    d.rectangle((w * 0.42, h * 0.58, w * 0.58, h * 0.6), fill=30)
    im = im.filter(ImageFilter.GaussianBlur(w * 0.02))
    im = Image.blend(im, Image.effect_noise((w, h), 40), 0.25)
    return contrast(im, 60, 190).convert("1", dither=Image.FLOYDSTEINBERG).convert("L").filter(ImageFilter.GaussianBlur(0.6))


def centre(d, y, txt, f, w, fill):
    bb = d.textbbox((0, 0), txt, font=f)
    d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], y), txt, font=f, fill=fill)


def affiche_recherche():
    w, h = 512, 720
    im = Image.new("RGB", (w, h), (236, 232, 220))
    d = ImageDraw.Draw(im)
    d.rectangle((14, 14, w - 14, h - 14), outline=(20, 20, 20), width=4)
    centre(d, 26, "POLICÍA NACIONAL DE CALIMAR", font("arialbd.ttf", 26), w, (20, 20, 20))
    centre(d, 58, "SE BUSCA", font("impact.ttf", 104), w, (150, 18, 14))
    im.paste(Image.merge("RGB", [portrait(300, 330, 7)] * 3), (106, 186))
    d.rectangle((106, 186, 406, 516), outline=(10, 10, 10), width=3)
    centre(d, 528, "RAMIRO QUIÑONES «EL CHATO»", font("arialbd.ttf", 27), w, (15, 15, 15))
    f = font("arial.ttf", 18)
    centre(d, 566, "Homicidio · Secuestro · Tráfico de armas", f, w, (25, 25, 25))
    centre(d, 590, "Visto por última vez en el puerto de carga", f, w, (25, 25, 25))
    centre(d, 622, "RECOMPENSA  $ 50.000", font("impact.ttf", 46), w, (150, 18, 14))
    centre(d, 676, "Línea anónima 800-555-0199", font("arialbd.ttf", 19), w, (20, 20, 20))
    return im


def affiche_pub():
    w, h = 512, 720
    im = Image.new("RGB", (w, h), (250, 196, 30))
    d = ImageDraw.Draw(im)
    d.polygon([(0, 0), (w, 0), (w, 260), (0, 380)], fill=(22, 22, 22))
    centre(d, 40, "RADIO", font("impact.ttf", 90), w, (250, 196, 30))
    centre(d, 140, "TAXI EL FARO", font("impact.ttf", 76), w, (245, 245, 240))
    # damier de taxi et phare stylisé
    for i in range(16):
        d.rectangle((i * 32, 400 + (i % 2) * 22, i * 32 + 32, 422 + (i % 2) * 22), fill=(20, 20, 20))
    d.polygon([(256, 260), (236, 380), (276, 380)], fill=(245, 245, 240))
    centre(d, 470, "24 HORAS", font("impact.ttf", 64), w, (22, 22, 22))
    centre(d, 548, "Puerto · Aeropuerto · Centro", font("arialbd.ttf", 26), w, (22, 22, 22))
    centre(d, 598, "555 - 01 - 42", font("impact.ttf", 72), w, (180, 20, 16))
    return im


def pictogramme_gilet(d, x, y, s, c):
    d.polygon([(x + s * 0.25, y), (x + s * 0.45, y), (x + s * 0.5, y + s * 0.15), (x + s * 0.55, y), (x + s * 0.75, y),
               (x + s * 0.85, y + s * 0.3), (x + s * 0.8, y + s), (x + s * 0.2, y + s), (x + s * 0.15, y + s * 0.3)], fill=c)
    d.rectangle((x + s * 0.2, y + s * 0.55, x + s * 0.8, y + s * 0.62), fill=(250, 250, 250))


def affiche_securite():
    w, h = 560, 760
    im = Image.new("RGB", (w, h), (240, 240, 236))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, w, 120), fill=(20, 60, 140))
    centre(d, 14, "AEROPUERTO INTERNACIONAL", font("arialbd.ttf", 30), w, (255, 255, 255))
    centre(d, 54, "DE CARGA PUERTO CENIZA", font("arialbd.ttf", 34), w, (255, 255, 255))
    d.rectangle((0, 130, w, 230), fill=(230, 180, 20))
    centre(d, 140, "ZONA RESTRINGIDA", font("impact.ttf", 72), w, (20, 20, 20))
    f = font("arialbd.ttf", 23)
    lignes = [("Solo personal autorizado", None), ("Credencial visible en todo momento", None),
              ("Uso obligatorio de chaleco", "gilet"), ("Prohibido fumar en hangares", "fumer"),
              ("Vehículos a 10 km/h máximo", "vitesse")]
    y = 260
    for txt, p in lignes:
        d.rectangle((24, y, 104, y + 80), fill=(20, 60, 140))
        if p == "gilet":
            pictogramme_gilet(d, 34, y + 8, 62, (250, 250, 250))
        elif p == "fumer":
            d.ellipse((30, y + 6, 98, y + 74), outline=(220, 30, 20), width=8)
            d.rectangle((40, y + 36, 88, y + 46), fill=(250, 250, 250))
            d.line((38, y + 66, 90, y + 14), fill=(220, 30, 20), width=8)
        elif p == "vitesse":
            d.ellipse((30, y + 6, 98, y + 74), fill=(250, 250, 250), outline=(220, 30, 20), width=8)
            centre(d, y + 18, "10", font("arialbd.ttf", 34), 128, (20, 20, 20))
        else:
            d.ellipse((50, y + 10, 78, y + 38), fill=(250, 250, 250))
            d.rectangle((46, y + 40, 82, y + 74), fill=(250, 250, 250))
        d.text((122, y + 24), txt, font=f, fill=(20, 20, 20))
        y += 92
    d.rectangle((0, h - 70, w, h), fill=(20, 60, 140))
    centre(d, h - 56, "Administración Aeroportuaria de Calimar · Ref. SEG-04", font("arial.ttf", 18), w, (255, 255, 255))
    return im


def panneau_fumer():
    w, h = 512, 512
    im = Image.new("RGB", (w, h), (245, 245, 240))
    d = ImageDraw.Draw(im)
    d.ellipse((96, 30, 416, 350), outline=(210, 26, 20), width=36)
    d.rectangle((150, 175, 350, 205), fill=(30, 30, 30))
    d.rectangle((350, 175, 380, 205), fill=(230, 120, 40))
    for k in range(3):
        d.arc((350 + k * 6, 110 - k * 12, 390 + k * 6, 170 - k * 12), 200, 340, fill=(90, 90, 90), width=5)
    d.line((140, 300, 372, 80), fill=(210, 26, 20), width=36)
    centre(d, 380, "PROHIBIDO", font("impact.ttf", 70), w, (20, 20, 20))
    centre(d, 448, "FUMAR", font("impact.ttf", 54), w, (20, 20, 20))
    return im


def finir_affiche(im, nom, seed, trous=1, rugosite=0.012, jaunir=0.25, sale=0.4):
    w, h = im.size
    im = vieillir(im, seed, jaunir, sale)
    a = contour_dechire(w, h, seed, 0.02, rugosite, trous)
    scotch(im, a, seed)
    relief = froisse(max(w, h), seed + 1, 18).crop((0, 0, w, h))
    # pli vertical et horizontal (affiche pliée en quatre)
    dr = ImageDraw.Draw(relief)
    dr.line((w / 2, 0, w / 2, h), fill=150, width=3)
    dr.line((0, h / 2, w, h / 2), fill=110, width=3)
    relief = relief.filter(ImageFilter.GaussianBlur(1.5))
    shade = relief.point(lambda v: int(min(255, max(0, 128 + (v - 128) * 2.2))))
    im = ImageChops.multiply(im, Image.merge("RGB", [shade.point(lambda v: int(200 + v * 55 / 255))] * 3))
    save(rgba(im, a), nom + ".png")
    save(normal_from_height(relief, 3.0), nom + "_nor.png")


def affiche_lambeaux():
    # vieille affiche arrachée : il reste des bandes et des coins sous le scotch
    base = vieillir(affiche_pub().resize((512, 720)), 77, 0.45, 0.6)
    w, h = base.size
    rnd = random.Random(78)
    a = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(a)
    for _ in range(9):
        x0 = rnd.uniform(0, w)
        y0 = rnd.choice([rnd.uniform(0, h * 0.25), rnd.uniform(h * 0.7, h)])
        pts = [(x0 + rnd.gauss(0, 60) + math.cos(t) * rnd.uniform(30, 110), y0 + math.sin(t) * rnd.uniform(15, 70))
               for t in [i * math.tau / 14 for i in range(14)]]
        d.polygon(pts, fill=255)
    d.rectangle((0, 0, w * 0.16, h * 0.08), fill=255)
    d.rectangle((w * 0.82, h * 0.9, w, h), fill=255)
    a = ImageChops.multiply(a, contour_dechire(w, h, 79, 0.0, 0.02, 0))
    # le papier blanc du dos reste collé par endroits
    blanc = Image.new("RGB", (w, h), (205, 198, 175))
    m = contrast(fbm(256, 80, 4, 4).resize((w, h)), 120, 170)
    base = Image.composite(blanc, base, m)
    save(rgba(base, a.filter(ImageFilter.GaussianBlur(0.8))), "affiche_lambeaux.png")


def papier(i):
    s = 512
    rnd = random.Random(700 + i)
    if i == 1:     # feuille froissée
        w, h = s, s
        im = vieillir(Image.new("RGB", (w, h), (232, 230, 222)), 701, 0.2, 0.6)
        d = ImageDraw.Draw(im)
        for k in range(14):
            d.line((60, 80 + k * 26, 420 - rnd.uniform(0, 140), 80 + k * 26), fill=(120, 120, 130), width=3)
        a = contour_dechire(w, h, 702, 0.08, 0.012, 1)
        relief = froisse(s, 703, 70)
    elif i == 2:   # ticket de caisse
        w, h = s, s
        im = Image.new("RGB", (w, h), (238, 236, 228))
        d = ImageDraw.Draw(im)
        for k in range(18):
            d.line((200, 70 + k * 21, 300 - rnd.uniform(0, 40), 70 + k * 21), fill=(110, 110, 115), width=2)
        a = Image.new("L", (w, h), 0)
        ImageDraw.Draw(a).rectangle((185, 50, 325, 470), fill=255)
        a = ImageChops.multiply(a, contour_dechire(w, h, 704, 0.0, 0.02, 0))
        im = vieillir(im, 705, 0.15, 0.4)
        relief = froisse(s, 706, 30)
    elif i == 3:   # page de journal
        w, h = s, s
        im = Image.new("RGB", (w, h), (205, 200, 185))
        d = ImageDraw.Draw(im)
        d.text((60, 60), "EL DIARIO DE CENIZA", font=font("timesbd.ttf", 34), fill=(30, 30, 30))
        for col in range(3):
            for k in range(22):
                d.line((60 + col * 135, 120 + k * 15, 175 + col * 135, 120 + k * 15), fill=(95, 95, 95), width=2)
        d.rectangle((195, 300, 450, 440), fill=(80, 80, 80))
        im = vieillir(im, 707, 0.3, 0.7)
        a = contour_dechire(w, h, 708, 0.06, 0.03, 2)
        relief = froisse(s, 709, 50)
    else:          # carton aplati
        w, h = s, s
        im = tint(fbm(256, 710, 4, 4).resize((w, h)), (120, 88, 52), (165, 125, 80))
        d = ImageDraw.Draw(im)
        d.line((0, 250, w, 262), fill=(100, 72, 40), width=6)
        d.text((120, 300), "FRÁGIL", font=font("arialbd.ttf", 50), fill=(60, 30, 20))
        im = vieillir(im, 711, 0.0, 0.7)
        a = contour_dechire(w, h, 712, 0.05, 0.02, 2)
        relief = froisse(s, 713, 12)
    shade = relief.point(lambda v: int(min(255, max(0, 128 + (v - 128) * 3))))
    im = ImageChops.multiply(im, Image.merge("RGB", [shade.point(lambda v: int(170 + v * 85 / 255))] * 3))
    save(rgba(im, a), "papier_%d.png" % i)
    save(normal_from_height(relief, 4.0), "papier_%d_nor.png" % i)


def megots():
    s = 512
    rnd = random.Random(800)
    im = Image.new("RGB", (s, s), (60, 58, 55))
    a = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(im)
    da = ImageDraw.Draw(a)
    # cendre écrasée
    for _ in range(500):
        x, y = rnd.gauss(s / 2, s * 0.17), rnd.gauss(s / 2, s * 0.17)
        r = rnd.uniform(1, 6)
        g = rnd.randint(55, 120)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(g, g - 2, g - 6))
        da.ellipse((x - r, y - r, x + r, y + r), fill=rnd.randint(60, 160))
    for _ in range(9):
        x, y = rnd.gauss(s / 2, s * 0.2), rnd.gauss(s / 2, s * 0.2)
        ang = rnd.uniform(0, math.pi)
        ln = rnd.uniform(26, 44)
        wd = 9
        dx, dy = math.cos(ang), math.sin(ang)
        filt = 0.55 * ln
        x1, y1 = x + dx * filt, y + dy * filt
        d.line((x, y, x1, y1), fill=(200, 130, 60), width=wd)                         # filtre
        d.line((x1, y1, x + dx * ln, y + dy * ln), fill=(215, 210, 198), width=wd)    # papier
        d.ellipse((x + dx * ln - 4, y + dy * ln - 4, x + dx * ln + 4, y + dy * ln + 4), fill=(45, 40, 35))
        da.line((x, y, x + dx * ln, y + dy * ln), fill=255, width=wd)
    save(rgba(im.filter(ImageFilter.GaussianBlur(0.6)), a.filter(ImageFilter.GaussianBlur(0.8))), "megots.png")


def traces_pas():
    w, h = 512, 1024
    rnd = random.Random(900)
    a = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(a)
    for k in range(6):
        x = w / 2 + (70 if k % 2 else -70) + rnd.gauss(0, 8)
        y = h - 120 - k * 170
        semelle = Image.new("L", (110, 280), 0)
        ds = ImageDraw.Draw(semelle)
        ds.ellipse((5, 0, 105, 170), fill=255)
        ds.ellipse((15, 190, 95, 280), fill=255)
        for j in range(16):   # crampons
            ds.line((10, 10 + j * 17, 100, 10 + j * 17), fill=0, width=5)
        semelle = semelle.rotate(rnd.uniform(-8, 8), expand=False)
        a.paste(ImageChops.multiply(semelle, contrast(fbm(256, 901 + k, 6, 4).resize((110, 280)), 80, 200))
                .point(lambda v, kk=k: int(min(255, v * (1.4 - kk * 0.15)))), (int(x - 55), int(y - 140)), None)
    save(rgba(Image.new("RGB", (w, h), (92, 84, 70)), a.filter(ImageFilter.GaussianBlur(1.2))), "traces_pas.png")


def bombe(d, pts, largeur, couleur, rnd, alpha_d=None):
    for i in range(len(pts) - 1):
        d.line((pts[i], pts[i + 1]), fill=couleur, width=largeur, joint="curve")
        if alpha_d:
            alpha_d.line((pts[i], pts[i + 1]), fill=255, width=largeur, joint="curve")


def tag_cartel_2():
    w, h = 1024, 512
    rnd = random.Random(1000)
    a = Image.new("L", (w, h), 0)
    da = ImageDraw.Draw(a)
    f = font("impact.ttf", 92)
    da.text((40, 40), "AQUÍ MANDA", font=f, fill=255)
    da.text((80, 150), "EL CÍRCULO", font=f, fill=255)
    # anneau C°C
    da.ellipse((640, 60, 960, 380), outline=255, width=28)
    da.text((688, 150), "C°C", font=font("impact.ttf", 120), fill=255)
    # coulures
    for _ in range(40):
        x = rnd.uniform(40, 960)
        y0 = rnd.uniform(120, 400)
        if a.getpixel((int(x), int(y0))) < 128:
            continue
        ln = rnd.expovariate(1 / 40)
        da.line((x, y0, x, y0 + ln), fill=230, width=rnd.choice([2, 3, 4]))
    a = a.rotate(-4, resample=Image.BICUBIC, expand=False)
    # bombe : bord diffus + surpulvérisation
    halo = a.filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.35))
    a = ImageChops.lighter(a.filter(ImageFilter.GaussianBlur(1.3)), halo)
    a = ImageChops.multiply(a, contrast(fbm(512, 1001, 8, 4).resize((w, h)), 20, 160))
    save(rgba(Image.new("RGB", (w, h), (24, 22, 22)), a), "tag_cartel_2.png")


def tag_cartel_3():
    w, h = 1024, 512
    rnd = random.Random(1100)
    a = Image.new("L", (w, h), 0)
    da = ImageDraw.Draw(a)
    da.text((80, 60), "C°C 13", font=font("STENCIL.TTF", 230), fill=255)
    for _ in range(60):
        x = rnd.uniform(80, 940)
        y0 = rnd.uniform(200, 330)
        if a.getpixel((int(x), int(y0))) < 128:
            continue
        ln = rnd.expovariate(1 / 55)
        da.line((x, y0, x + rnd.uniform(-1, 1), y0 + ln), fill=220, width=rnd.choice([2, 3, 5]))
    halo = a.filter(ImageFilter.GaussianBlur(8)).point(lambda v: int(v * 0.3))
    a = ImageChops.lighter(a.filter(ImageFilter.GaussianBlur(1.0)), halo)
    a = ImageChops.multiply(a, contrast(fbm(512, 1101, 6, 4).resize((w, h)), 10, 150))
    # cuivre terni (couleur du cartel)
    save(rgba(tint(fbm(512, 1102, 4, 3).resize((w, h)), (120, 58, 28), (170, 92, 44)), a), "tag_cartel_3.png")


def grillage_cables():
    s = 256
    a = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(a)
    # fil d'acier soudé : maille 5 × 10 cm (la texture couvre 0,5 m)
    for k in range(0, s + 1, s // 5):
        d.line((k, 0, k, s), fill=255, width=4)
    for k in range(0, s + 1, s // 10):
        d.line((0, k, s, k), fill=255, width=3)
    col = Image.new("RGB", (s, s), (150, 152, 150))
    save(rgba(col, a), "grillage_cables.png")


def eraflures():
    """Traces noires de caoutchouc et éraflures laissées par les chariots et les semelles (bas des murs)."""
    w, h = 1024, 256
    rnd = random.Random(1600)
    a = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(a)
    for _ in range(70):
        x = rnd.uniform(-100, w)
        y = rnd.gauss(h * 0.55, h * 0.18)
        ln = rnd.expovariate(1 / 120) + 20
        pente = rnd.gauss(0, 0.06)
        d.line((x, y, x + ln, y + ln * pente), fill=rnd.randint(70, 230), width=rnd.choice([1, 2, 2, 3, 5]))
    a = a.filter(ImageFilter.GaussianBlur(1.0))
    halo = a.filter(ImageFilter.GaussianBlur(10)).point(lambda v: int(v * 0.6))
    a = ImageChops.lighter(a, halo)
    fade = Image.new("L", (w, h))
    fade.putdata([int(255 * min(1, min(x, w - x) / 150)) for y in range(h) for x in range(w)])
    a = ImageChops.multiply(a, fade)
    save(rgba(Image.new("RGB", (w, h), (20, 18, 16)), a), "eraflures.png")


TOUT = {
    "eraflures": eraflures,
    "macro_bruit": macro_bruit,
    "poussiere": lambda: [poussiere(i) for i in (1, 2, 3)],
    "crasse_coin": crasse_coin,
    "crasse_sol_mur": crasse_sol_mur,
    "tache_humidite": lambda: [tache_humidite(i) for i in (1, 2)],
    "coulure_rouille": coulure_rouille,
    "mouille": lambda: [mouille(i) for i in (1, 2, 3)],
    "flaque": lambda: [flaque(i) for i in (1, 2, 3)],
    "papier": lambda: [papier(i) for i in (1, 2, 3, 4)],
    "megots": megots,
    "traces_pas": traces_pas,
    "affiche_recherche": lambda: finir_affiche(affiche_recherche(), "affiche_recherche", 1200, 1),
    "affiche_pub": lambda: finir_affiche(affiche_pub(), "affiche_pub", 1300, 2, 0.015, 0.3, 0.5),
    "affiche_securite": lambda: finir_affiche(affiche_securite(), "affiche_securite", 1400, 0, 0.006, 0.15, 0.3),
    "panneau_fumer": lambda: finir_affiche(panneau_fumer(), "panneau_fumer", 1500, 0, 0.004, 0.1, 0.25),
    "affiche_lambeaux": affiche_lambeaux,
    "tag_cartel_2": tag_cartel_2,
    "tag_cartel_3": tag_cartel_3,
    "grillage_cables": grillage_cables,
}

if __name__ == "__main__":
    noms = sys.argv[1:] or list(TOUT)
    for n in noms:
        print(n)
        TOUT[n]()

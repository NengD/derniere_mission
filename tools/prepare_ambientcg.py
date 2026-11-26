"""Prépare les décalques ambientCG (CC0) pour le kit de décor : RGBA 1024 max, normales à part.

Usage : python tools/prepare_ambientcg.py   (après python tools/fetch_ambientcg.py ...)
Entrée : _sources/ambientcg/<id>/   Sortie : assets/decor/acg/
  humidite_a/b.png (+_nor)  coulures d'eau (Leaking004, Leaking008)
  traces_eau_1..3.png       traînées claires (Leaking012A/016A/018A : alpha = assombrissement)
  graffiti_1..6.png         tags isolés de GraffitiSet001 (grille 4 × 4)
  fissure_1..4.png (+_nor)  fissures du sol (bandes de AsphaltDamageSet001)
  chewing_gum.png           taches de chewing-gum (ChewingGum001)
"""
import os
from PIL import Image, ImageChops, ImageOps

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "_sources", "ambientcg")
OUT = os.path.join(ROOT, "assets", "decor", "acg")


def f(asset, suffix):
    for ext in ("jpg", "png"):
        for var in ("2K-JPG", "2K-PNG"):
            p = os.path.join(SRC, asset, "%s_%s_%s.%s" % (asset, var, suffix, ext))
            if os.path.exists(p):
                return Image.open(p)
    return None


def save(img, name, maxi=1024):
    img = img.copy()
    img.thumbnail((maxi, maxi), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    print("  ", name, img.size)


def decal(asset, name, box=None, maxi=1024, alpha_gain=1.0):
    col = f(asset, "Color").convert("RGB")
    op = f(asset, "Opacity").convert("L")
    nor = f(asset, "NormalGL")
    if box:
        col, op = col.crop(box), op.crop(box)
        nor = nor.crop(box) if nor else None
    if alpha_gain != 1.0:
        op = op.point(lambda v: int(min(255, v * alpha_gain)))
    save(Image.merge("RGBA", (*col.split(), op)), name + ".png", maxi)
    if nor:
        save(nor.convert("RGB"), name + "_nor.png", maxi)
    return col, op


def traces(asset, name):
    col = f(asset, "Color").convert("L")
    a = ImageOps.autocontrast(ImageOps.invert(col), cutoff=1).point(lambda v: int(v * 0.8))
    rgb = Image.merge("RGB", [Image.new("L", col.size, v) for v in (52, 46, 38)])
    save(Image.merge("RGBA", (*rgb.split(), a)), name + ".png", 1024)


if __name__ == "__main__":
    decal("Leaking004", "humidite_a")
    decal("Leaking008", "humidite_b")
    for i, a in enumerate(("Leaking012A", "Leaking016A", "Leaking018A")):
        traces(a, "traces_eau_%d" % (i + 1))
    # GraffitiSet001 : grille 4 × 4 de 512 px
    for i, (cx, cy) in enumerate([(0, 0), (1, 0), (3, 0), (0, 2), (2, 2), (3, 3)]):
        decal("GraffitiSet001", "graffiti_%d" % (i + 1), (cx * 512, cy * 512, cx * 512 + 512, cy * 512 + 512), 512)
    # AsphaltDamageSet001 : quatre bandes horizontales
    for i in range(4):
        decal("AsphaltDamageSet001", "fissure_%d" % (i + 1), (0, i * 512, 2048, i * 512 + 512), 1024, 1.3)
    decal("ChewingGum001", "chewing_gum", None, 512)

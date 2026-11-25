"""Teinte les tissus Poly Haven (CC0) pour les tenues des personnages.

Usage : python tools/make_cloth_textures.py   -> assets/characters/tex/*.jpg
"""
import os
from PIL import Image, ImageOps

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(ROOT, "_sources", "polyhaven")
OUT = os.path.join(ROOT, "assets", "characters", "tex")

# nom de sortie : (texture source, couleur sombre, couleur claire)
TINTS = {
    "cagoule": ("knitted_fleece", (8, 8, 9), (46, 44, 42)),
    "tshirt_olive": ("cotton_jersey", (42, 46, 30), (122, 126, 92)),
    "jean_sombre": ("denim_fabric_04", (28, 34, 48), (108, 116, 134)),
    "gilet_toile": ("hessian_230", (40, 40, 28), (128, 122, 90)),
    "veste_marc": ("cotton_jersey", (14, 15, 17), (58, 60, 64)),
    "gants_cuir": ("brown_leather", (8, 8, 8), (44, 40, 36)),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (src, dark, light) in TINTS.items():
        d = os.path.join(SRC, src)
        diff = [f for f in os.listdir(d) if "_diff_" in f][0]
        im = ImageOps.grayscale(Image.open(os.path.join(d, diff)))
        im = ImageOps.autocontrast(im, cutoff=1)
        ImageOps.colorize(im, dark, light).save(os.path.join(OUT, name + "_diff.jpg"), quality=90)
        for kind in ("nor_gl", "rough"):
            f = [f for f in os.listdir(d) if "_%s_" % kind in f]
            if f:
                Image.open(os.path.join(d, f[0])).convert("RGB").save(os.path.join(OUT, "%s_%s.jpg" % (name, kind)), quality=90)
        print(name)


if __name__ == "__main__":
    main()

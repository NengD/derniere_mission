"""Télécharge des ressources ambientCG (toutes CC0, sans compte) dans _sources/ambientcg/<id>/.

Usage : python tools/fetch_ambientcg.py <id>[:<variante>] ...
  variante par défaut : 2K-JPG (ex. 1K-PNG, 2K-PNG)
Exemple : python tools/fetch_ambientcg.py Leaking004 Door001 GraffitiSet001:2K-PNG
Chaque archive est extraite dans son propre dossier ; seuls les fichiers image et les fichiers
texte sont gardés (aucun exécutable).
"""
import io
import os
import sys
import urllib.request
import zipfile

UA = "Mozilla/5.0 fetch-ambientcg/1.0"
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_sources", "ambientcg"))
OK = (".jpg", ".jpeg", ".png", ".txt", ".usda", ".mtlx")


def fetch(asset, variant):
    out = os.path.join(ROOT, asset)
    if os.path.isdir(out) and os.listdir(out):
        return
    url = "https://ambientcg.com/get?file=%s_%s.zip" % (asset, variant)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    data = urllib.request.urlopen(req, timeout=180).read()
    os.makedirs(out, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for n in z.namelist():
            base = os.path.basename(n)
            if base and base.lower().endswith(OK):
                with open(os.path.join(out, base), "wb") as f:
                    f.write(z.read(n))
    print(asset, variant, len(data) // 1024, "Ko")


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        parts = arg.split(":")
        fetch(parts[0], parts[1] if len(parts) > 1 else "2K-JPG")

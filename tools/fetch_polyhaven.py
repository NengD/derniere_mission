"""Télécharge des ressources Poly Haven (toutes CC0) dans _sources/polyhaven/<id>/.

Usage : python tools/fetch_polyhaven.py <type>:<id>[:<résolution>] ...
  type = hdri | tex | model      résolution par défaut : 2k (1k pour les modèles)
Exemple : python tools/fetch_polyhaven.py hdri:kloofendal_48d_partly_cloudy_puresky:2k tex:dirt_floor model:antique_estoc
"""
import json
import os
import sys
import urllib.request

UA = "Mozilla/5.0 fetch-polyhaven/1.0"
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_sources", "polyhaven"))


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return urllib.request.urlopen(req, timeout=120).read()


def save(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(get(url))
    print("  ", os.path.relpath(dest, ROOT))


def fetch(kind, asset, res):
    files = json.loads(get("https://api.polyhaven.com/files/" + asset))
    out = os.path.join(ROOT, asset)
    print(kind, asset, res)
    if kind == "hdri":
        save(files["hdri"][res]["hdr"]["url"], os.path.join(out, asset + "_" + res + ".hdr"))
    elif kind == "tex":
        for key, short in (("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("arm", "arm"), ("Rough", "rough"), ("Displacement", "disp")):
            if key in files and res in files[key]:
                fmt = "jpg" if "jpg" in files[key][res] else "png"
                save(files[key][res][fmt]["url"], os.path.join(out, "%s_%s_%s.%s" % (asset, short, res, fmt)))
    elif kind == "model":
        g = files["gltf"][res]["gltf"]
        save(g["url"], os.path.join(out, asset + ".gltf"))
        for rel, inc in g.get("include", {}).items():
            save(inc["url"], os.path.join(out, rel))


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        parts = arg.split(":")
        kind, asset = parts[0], parts[1]
        res = parts[2] if len(parts) > 2 else ("1k" if kind == "model" else "2k")
        fetch(kind, asset, res)

"""Recherche et téléchargement de modèles Sketchfab (API v3).

Jeton : variable d'environnement SKETCHFAB_TOKEN ou fichier .secrets/sketchfab_token
(ignoré par git). Le jeton n'est jamais affiché ni écrit : il part seulement dans
l'en-tête « Authorization: Token … ».

  python -I tools/fetch_sketchfab.py search "<requête>" [nb]
  python -I tools/fetch_sketchfab.py info <uid>
  python -I tools/fetch_sketchfab.py download <uid> [--glb]  # → _sources/sketchfab/<uid>/ (glTF par défaut)

Seules les licences CC0 (cc0) et CC-BY (by) sont acceptées au téléchargement.
"""
import json

import os
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
API = "https://api.sketchfab.com/v3"
LICENCES_OK = {"cc0", "by"}
sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def _jeton() -> str:
    j = os.environ.get("SKETCHFAB_TOKEN", "").strip()
    if not j:
        f = RACINE / ".secrets" / "sketchfab_token"
        if f.exists():
            j = f.read_text(encoding="utf-8").strip()
    if not j:
        sys.exit("Jeton Sketchfab introuvable (SKETCHFAB_TOKEN ou .secrets/sketchfab_token).")
    return j


def _get(url: str, auth: bool = True) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "derniere-mission-outils/1.0"})
    if auth:
        req.add_header("Authorization", "Token " + _jeton())
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def _licence(m: dict) -> str:
    lic = m.get("license") or {}
    return lic.get("slug") or lic.get("label") or "?"


def search(q: str, nb: int = 24) -> None:
    params = {"type": "models", "downloadable": "true", "q": q, "count": str(nb)}
    if len(sys.argv) > 4:
        params["license"] = sys.argv[4]
    d = _get(API + "/search?" + urllib.parse.urlencode(params), auth=False)
    for m in d.get("results", []):
        print("%s | %-6s | %7s f | %4s likes | %s | %s" % (
            m["uid"], _licence(m), m.get("faceCount"), m.get("likeCount"),
            m.get("name"), (m.get("user") or {}).get("username")))


def info(uid: str) -> dict:
    m = _get(API + "/models/" + uid, auth=False)
    print(json.dumps({k: m.get(k) for k in ("name", "uid", "viewerUrl", "faceCount", "vertexCount",
                                            "isDownloadable", "createdAt", "staffpickedAt")},
                     ensure_ascii=False))
    print("licence:", json.dumps(m.get("license"), ensure_ascii=False))
    print("auteur:", (m.get("user") or {}).get("displayName"), "/", (m.get("user") or {}).get("username"),
          (m.get("user") or {}).get("profileUrl"))
    print("tags:", [t.get("name") for t in m.get("tags", [])])
    print("description:", (m.get("description") or "")[:400].replace("\n", " "))
    return m


def download(uid: str) -> None:
    m = _get(API + "/models/" + uid, auth=False)
    lic = _licence(m)
    if lic not in LICENCES_OK:
        sys.exit("Licence refusée : %s" % lic)
    d = _get(API + "/models/%s/download" % uid)
    # glTF (archive) de préférence : textures d'origine (le glb converti par Sketchfab les réduit à 1K)
    fmt = "gltf" if "gltf" in d and "--glb" not in sys.argv else "glb"
    url = d[fmt]["url"]
    dossier = RACINE / "_sources" / "sketchfab" / uid
    dossier.mkdir(parents=True, exist_ok=True)
    nom = dossier / ("modele.glb" if fmt == "glb" else "archive.zip")
    req = urllib.request.Request(url, headers={"User-Agent": "derniere-mission-outils/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r, open(nom, "wb") as f:
        while True:
            b = r.read(1 << 20)
            if not b:
                break
            f.write(b)
    if fmt == "gltf":
        with zipfile.ZipFile(nom) as z:
            for n in z.namelist():
                cible = (dossier / n).resolve()
                if not str(cible).startswith(str(dossier.resolve())):
                    sys.exit("Archive suspecte : " + n)
            z.extractall(dossier)
    (dossier / "fiche.json").write_text(json.dumps({
        "name": m.get("name"), "uid": uid, "url": m.get("viewerUrl"), "licence": m.get("license"),
        "auteur": (m.get("user") or {}).get("displayName"),
        "auteur_url": (m.get("user") or {}).get("profileUrl"),
        "faceCount": m.get("faceCount")}, ensure_ascii=False, indent=1), encoding="utf-8")
    print("OK", uid, fmt, nom.stat().st_size // 1024, "Ko →", dossier)


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "search":
        search(a[1], int(a[2]) if len(a) > 2 else 24)
    elif a[0] == "info":
        info(a[1])
    elif a[0] == "download":
        download(a[1])
    else:
        sys.exit(__doc__)

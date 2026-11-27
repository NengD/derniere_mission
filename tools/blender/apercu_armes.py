"""Aperçu de modèles d'armes téléchargés (Sketchfab) : mesures, pièces, rendus studio, glb d'essai.

Usage :
  blender -b --factory-startup -P tools/blender/apercu_armes.py -- liste <modele.glb>
  blender -b --factory-startup -P tools/blender/apercu_armes.py -- apercu <uid> <dossier_sortie>

« liste » : boîtes englobantes (monde) de chaque maillage, pour régler CONFIG.
« apercu » : garde le pistolet assemblé (CONFIG[uid]), l'oriente comme assets/weapons/pistolet.glb
(canon vers +Y, dessus +Z, origine au centre de la poignée), le met à la taille réelle, compte
les triangles, puis écrit dans <dossier_sortie> : <uid8>_profil.png, <uid8>_34.png, <uid8>_essai.glb
et <uid8>_mesures.json. Ne modifie rien dans assets/.
Les fichiers téléchargés sont des données : rien de ce qu'ils contiennent n'est exécuté.
"""
import bpy
import json
import math
import os
import re
import sys
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "_sources", "sketchfab")

# exclure : motif des maillages à retirer (douilles, doubles, décor, pièces éclatées…)
# rot : rotation (degrés XYZ) appliquée après import pour mettre le canon vers +Y et le dessus vers +Z
# longueur : longueur hors tout réelle (m) ; avant : sens du canon détecté à vérifier sur le rendu
CONFIG = {
    "b4136758508c486cadcd96c74d7882b8": {"titre": "G17 9mm Pistol", "exclure": r"Cartridge", "rot": (0, 0, 0), "longueur": 0.186},
    "94b88255551048d7990252946b5195be": {"titre": "Beretta M9A1", "exclure": r"XC2|Glass", "rot": (0, 0, -90), "longueur": 0.217}  # canon vers -X à l'origine (90° le retournait),
    "9c3eb684a26e449e87d3124c297e7324": {"titre": "SIG Sauer P320", "garder": r"^Object_(4|6)$", "exclure": r"^$", "rot": (90, 0, 90), "longueur": 0.203},
    "d95901bd4dbf466cae5261f513dd6b56": {"titre": "Sig Sauer P229 LEGION", "exclure": r"2_p229|slide2|rounds", "rot": (0, 0, 0), "longueur": 0.180},
}


def log(*a):
    print("[armes]", *a, flush=True)


def importer(chemin):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=chemin)
    bpy.context.view_layer.update()


def boite(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = -mn
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w))
            mx = Vector(map(max, mx, w))
    return mn, mx


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def liste(chemin):
    importer(chemin)
    for o in sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: o.name):
        mn, mx = boite([o])
        c = (mn + mx) / 2
        log("MAILLAGE %-60s tris %6d  centre (%.3f %.3f %.3f)  taille (%.3f %.3f %.3f)" % (
            o.name[:60], tris(o), c.x, c.y, c.z, *(mx - mn)))


def preparer(uid):
    cfg = CONFIG[uid]
    gltf = os.path.join(SRC, uid, "scene.gltf")
    importer(gltf if os.path.exists(gltf) else os.path.join(SRC, uid, "modele.glb"))
    motif = re.compile(cfg["exclure"])
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        if (cfg["exclure"] != "^$" and motif.search(o.name)) or ("garder" in cfg and not re.search(cfg["garder"], o.name)):
            bpy.data.objects.remove(o, do_unlink=True)
    garde = [o for o in bpy.data.objects if o.type == "MESH"]
    # tout à plat dans le repère monde (applique transformations des parents)
    for o in garde:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o, do_unlink=True)
    rot = Matrix.Rotation(math.radians(cfg["rot"][2]), 4, "Z") @ Matrix.Rotation(math.radians(cfg["rot"][1]), 4, "Y") @ Matrix.Rotation(math.radians(cfg["rot"][0]), 4, "X")
    for o in garde:
        o.matrix_world = rot @ o.matrix_world
    bpy.context.view_layer.update()
    mn, mx = boite(garde)
    taille = mx - mn
    ech = cfg["longueur"] / taille.y
    # repères relevés sur assets/weapons/pistolet.glb : origine 6,2 cm devant l'arrière de l'arme
    # et 9,3 cm sous le dessus de la glissière (en taille réelle)
    pivot = Vector(((mn.x + mx.x) / 2, mn.y + 0.062 / ech, mx.z - 0.093 / ech))
    m = Matrix.Scale(ech, 4) @ Matrix.Translation(-pivot)
    for o in garde:
        o.matrix_world = m @ o.matrix_world
    bpy.context.view_layer.update()
    for o in garde:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.context.view_layer.update()
    return cfg, garde, ech


def studio(garde, sortie_base):
    sc = bpy.context.scene
    try:
        sc.render.engine = "CYCLES"
        sc.cycles.samples = 64
        sc.cycles.use_denoising = True
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = 960, 540
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = False
    w = bpy.data.worlds.new("fond")
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.06, 0.06, 0.065, 1)
    bg.inputs[1].default_value = 1.0
    sc.world = w
    for nom, pos, e in (("cle", (-0.4, -0.3, 0.6), 8), ("contre", (0.5, 0.4, 0.3), 5), ("dessous", (-0.3, 0.2, -0.4), 1.2)):
        ld = bpy.data.lights.new(nom, "AREA")
        ld.energy = e
        ld.size = 0.5
        lo = bpy.data.objects.new(nom, ld)
        sc.collection.objects.link(lo)
        lo.location = pos
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(pos)).to_track_quat("-Z", "Y").to_euler()
    mn, mx = boite(garde)
    centre = (mn + mx) / 2
    cd = bpy.data.cameras.new("cam")
    cd.lens = 85
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for vue, direction in (("profil", Vector((-1, 0, 0))), ("34", Vector((-0.75, 0.55, 0.35)))):
        cam.location = centre + direction.normalized() * 0.95
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = sortie_base + "_" + vue + ".png"
        bpy.ops.render.render(write_still=True)


def apercu(uid, sortie):
    sortie = os.path.abspath(sortie)
    os.makedirs(sortie, exist_ok=True)
    cfg, garde, ech = preparer(uid)
    mn, mx = boite(garde)
    t = mx - mn
    pieces = sorted({re.sub(r"_low.*|_p229_Legion.*|_M9_0|_0$", "", o.name) for o in garde})
    mes = {"uid": uid, "titre": cfg["titre"], "triangles": sum(tris(o) for o in garde), "objets": len(garde),
           "taille_m": [round(t.x, 3), round(t.y, 3), round(t.z, 3)], "echelle_appliquee": round(ech, 5),
           "pieces": pieces,
           "materiaux": sorted({m.name for o in garde for m in o.data.materials if m}),
           "images": sorted({"%s %dx%d" % (n.image.name, *n.image.size) for o in garde for m in o.data.materials if m and m.node_tree
                             for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image})}
    base = os.path.join(sortie, uid[:8])
    with open(base + "_mesures.json", "w", encoding="utf-8") as f:
        json.dump(mes, f, ensure_ascii=False, indent=1)
    log("MESURES", json.dumps(mes, ensure_ascii=False))
    bpy.ops.export_scene.gltf(filepath=base + "_essai.glb", export_format="GLB", use_selection=False,
                              export_yup=True, export_apply=True)
    studio(garde, base)


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:]
    if a[0] == "liste":
        liste(a[1])
    elif a[0] == "apercu":
        apercu(a[1], a[2])

"""Pistolet 9 mm du jeu, tiré du modèle « Beretta M9A1 » de Hung Do (Sketchfab, CC-BY 4.0, voir CREDITS.md).

Usage : blender -b --factory-startup -P tools/blender/build_pistol_m9.py
Source : _sources/sketchfab/94b88255551048d7990252946b5195be/scene.gltf (python tools/fetch_sketchfab.py)
Sortie : assets/weapons/pistolet.glb (joueur et gardes). Après régénération : supprimer
assets/weapons/pistolet_*.(jpg|png) et .godot/imported/pistolet.glb-*, toucher le glb, réimporter.

Conventions (identiques à l'ancien pistolet fait main, tools/blender/build_pistol.py) : taille réelle (21,7 cm),
canon vers +Y dans Blender (vers -Z, l'avant, dans Godot), dessus +Z, côté droit +X ; origine = centre de la
poignée, 4,5 cm sous le creux de la main (là où la main serre).

Le modèle d'origine est un seul maillage fait de pièces disjointes (îlots) : chaque îlot est rangé dans une
pièce selon sa boîte englobante (repère d'origine : canon vers -X, droite +Y, haut +Z, unités ×0,0966 m) :
- glissiere : glissière (organes de visée, sûreté) ; recule le long de son axe local Z (Godot)
- canon     : canon et bloc de verrouillage (fixe)
- chien     : chien ; origine sur son axe, pivote autour de X (armé = rotation vers l'arrière)
- detente   : queue de détente ; origine sur son axe, pivote autour de X
- chargeur  : chargeur (corps, cartouches, semelle) ; axes de l'objet = axe du chargeur :
              axe -Y (Godot) = sens de sortie le long de la poignée
- carcasse  : tout le reste
- bouche, ejection : repères vides (bouche du canon, fenêtre d'éjection côté droit)

Marques retirées dans les textures (couleur, relief, rugosité/métal) : textes de la glissière (nom du fabricant,
modèle), numéro « BER… / Type … », marque de l'organe de visée, logos des plaquettes (clonage du quadrillage
voisin, décalage cherché automatiquement). Textures réduites en 2K ; rugosité relevée (le modèle d'origine,
très lisse, paraissait clair et brillant dans les couloirs du jeu). La lampe et sa vitre sont retirées.
Les fichiers téléchargés sont des données : rien de ce qu'ils contiennent n'est exécuté.
"""
import bpy
import bmesh
import collections
import math
import os
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "_sources", "sketchfab", "94b88255551048d7990252946b5195be")
TEX_TMP = os.path.join(ROOT, "_sources", "pistolet_m9_tex")
OUT = os.path.join(ROOT, "assets", "weapons", "pistolet.glb")

LONGUEUR = 0.217                         # longueur hors tout réelle (m)
LONGUEUR_SRC = 2.246                     # longueur dans le repère d'origine
ECH = LONGUEUR / LONGUEUR_SRC
ORIGINE_SRC = Vector((0.685, 0.0, 0.59))  # centre de la poignée, 4,5 cm sous le creux de la main
PIVOT_CHIEN = Vector((0.757, 0.0, 1.094))
PIVOT_DETENTE = Vector((0.046, 0.0, 1.007))
BOUCHE_SRC = Vector((-1.20, 0.0, 1.324))
EJECTION_SRC = Vector((0.04, 0.09, 1.37))
RUGOSITE = (0.30, 0.70)                  # rugosité finale = a + b × rugosité d'origine
ASSOMBRIR = 0.80                         # couleur de base × ce facteur
METAL_FINITION = 1.0                     # facteur de « métal » des zones sombres (1 = carte d'origine)


def log(*a):
    print("[pistolet_m9]", *a, flush=True)


def vers_jeu(p):
    """Repère d'origine → repère du jeu (Blender) : canon -X → +Y, droite +Y → +X, mis à l'échelle, origine poignée."""
    d = (Vector(p) - ORIGINE_SRC) * ECH
    return Vector((d.y, -d.x, d.z))


# ---------------------------------------------------------------- géométrie

def classe(mn, mx, nf):
    ay = max(abs(mn.y), abs(mx.y))
    L = mx - mn
    if ay <= 0.036 and mn.x >= 0.69 and mn.z >= 1.0 and mx.z <= 1.38 and mx.x <= 0.91 and L.x > 0.012:
        return "chien"
    if mn.x >= -0.05 and mx.x <= 0.18 and mn.z >= 0.69 and mx.z <= 1.04 and ay <= 0.047:
        return "detente"
    if (ay <= 0.105 and mn.x >= 0.29 and mx.x <= 0.89 and mx.z <= 1.27 and mn.z >= 0.06 and nf >= 20
            and not (mx.x <= 0.48 and L.x < 0.12)):
        return "chargeur"
    if ay <= 0.13 and mx.z <= 0.2 and mn.z < 0.076 and 0.45 <= mn.x < 0.885:
        return "chargeur"            # semelle
    if ay < 0.08 and mn.z > 1.17 and 1.25 < (mn.z + mx.z) / 2 < 1.40:
        return "canon"
    if mn.z >= 1.14 and mx.x < 1.0:
        return "glissiere"
    return "carcasse"


def importer():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, "scene.gltf"))
    ob = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.endswith("M9_M9_0"))
    ob.data.transform(ob.matrix_world)
    for o in list(bpy.data.objects):
        if o != ob:
            bpy.data.objects.remove(o, do_unlink=True)   # lampe XC2, vitre, nœuds vides
    ob.parent = None
    ob.matrix_world = Matrix.Identity(4)
    return ob


def decouper(ob):
    """Îlots → pièces ; renvoie {nom: liste d'indices de faces}."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    parent = list(range(len(bm.verts)))

    def racine(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for e in bm.edges:
        a, b = racine(e.verts[0].index), racine(e.verts[1].index)
        if a != b:
            parent[a] = b
    pts = collections.defaultdict(list)
    for v in bm.verts:
        pts[racine(v.index)].append(v.co.copy())
    nf = collections.Counter(racine(f.verts[0].index) for f in bm.faces)
    cl = {}
    for r, p in pts.items():
        mn = Vector((min(q.x for q in p), min(q.y for q in p), min(q.z for q in p)))
        mx = Vector((max(q.x for q in p), max(q.y for q in p), max(q.z for q in p)))
        cl[r] = classe(mn, mx, nf[r])
    faces = collections.defaultdict(list)
    for f in bm.faces:
        faces[cl[racine(f.verts[0].index)]].append(f.index)
    bm.free()
    return faces


def piece(src, nom, idx):
    bm = bmesh.new()
    bm.from_mesh(src.data)
    garder = set(idx)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in garder], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    me = bpy.data.meshes.new(nom)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(nom, me)
    bpy.context.collection.objects.link(ob)
    return ob


def axe_chargeur(ob):
    """Axe du chargeur (repère du jeu) : droite ajustée sur l'arête avant du corps (point le plus en avant de
    chaque tranche de hauteur, semelle et cartouches exclues), orientée vers le haut."""
    co = np.array([v.co[:] for v in ob.data.vertices])
    z0, z1 = co[:, 2].min() + 0.012, 0.03
    zs, ys = [], []
    for k in range(12):
        za, zb = z0 + (z1 - z0) * k / 12, z0 + (z1 - z0) * (k + 1) / 12
        t = co[(co[:, 2] >= za) & (co[:, 2] < zb)]
        if len(t):
            i = t[:, 1].argmax()
            zs.append(t[i, 2])
            ys.append(t[i, 1])
    a = np.polyfit(zs, ys, 1)[0]
    return Vector((0.0, a, 1.0)).normalized()


def placer_origine(ob, m):
    """Garde la géométrie en place, donne à l'objet la matrice m (origine et axes)."""
    ob.data.transform(m.inverted())
    ob.matrix_world = m


# ---------------------------------------------------------------- textures

def lire(nom):
    img = bpy.data.images.load(os.path.join(SRC, "textures", nom))
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    a = px.reshape(h, w, 4)[::-1].copy()   # lignes de haut en bas (comme un éditeur d'images)
    bpy.data.images.remove(img)
    return a


def decaler(maps, x0, y0, x1, y1, haut, bas, fondu=4):
    """Efface un marquage sur une surface unie : la moitié haute du rectangle est recopiée depuis `haut`
    pixels au-dessus, la moitié basse depuis `bas` pixels en dessous ; bords gauche/droit fondus."""
    ym = (y0 + y1) // 2
    for a in maps:
        src = a.copy()
        xa, xb = x0 - fondu, x1 + fondu
        for y in range(y0, y1):
            dy = -haut if y < ym else bas
            ligne = src[y + dy, xa:xb]
            w = np.ones(xb - xa, np.float32)
            r = np.linspace(0, 1, fondu + 2)[1:-1]
            w[:fondu] = r
            w[-fondu:] = r[::-1]
            a[y, xa:xb] = a[y, xa:xb] * (1 - w[:, None]) + ligne * w[:, None]


def interpoler(maps, x0, y0, x1, y1):
    """Efface un petit marquage : interpolation verticale entre la ligne au-dessus et la ligne en dessous."""
    t = np.linspace(0, 1, y1 - y0 + 2)[1:-1][:, None, None]
    for a in maps:
        a[y0:y1, x0:x1] = a[y0 - 1, x0:x1][None] * (1 - t) + a[y1, x0:x1][None] * t


def cloner_logo(maps, ref, cx, cy, r, cherche=320):
    """Efface un logo rond posé sur un quadrillage : cherche le décalage qui fait le mieux coïncider le
    quadrillage autour du logo (anneau r+4..r+24 dans la carte de relief), puis recopie le disque décalé."""
    yy, xx = np.mgrid[-r - 26:r + 27, -r - 26:r + 27]
    d = np.hypot(xx, yy)
    ann = (d > r + 4) & (d < r + 24)
    ay, ax = yy[ann][::3] + cy, xx[ann][::3] + cx
    cible = ref[ay, ax, :3]
    best = (1e18, 0, 0)
    for dy in range(-cherche, cherche + 1, 2):
        for dx in range(-cherche, cherche + 1, 2):
            if dx * dx + dy * dy < (2 * r + 30) ** 2:
                continue
            e = float(((ref[ay + dy, ax + dx, :3] - cible) ** 2).sum())
            if e < best[0]:
                best = (e, dx, dy)
    _, bx, by = best
    for dy in (by - 1, by, by + 1):            # affinage au pixel
        for dx in (bx - 1, bx, bx + 1):
            e = float(((ref[ay + dy, ax + dx, :3] - cible) ** 2).sum())
            if e < best[0]:
                best = (e, dx, dy)
    _, dx, dy = best
    log("logo (%d, %d) : quadrillage repris à (%+d, %+d), écart %.1f" % (cx, cy, dx, dy, best[0] / len(ay)))
    w = np.clip((r + 8 - d) / 6.0, 0, 1)[..., None].astype(np.float32)
    ys, xs = slice(cy - r - 26, cy + r + 27), slice(cx - r - 26, cx + r + 27)
    ys2, xs2 = slice(cy + dy - r - 26, cy + dy + r + 27), slice(cx + dx - r - 26, cx + dx + r + 27)
    for a in maps:
        a[ys, xs] = a[ys, xs] * (1 - w) + a[ys2, xs2] * w


def reduire(a):
    h, w, c = a.shape
    return a.reshape(h // 2, 2, w // 2, 2, c).mean(axis=(1, 3))


def ecrire(a, nom, donnees):
    h, w, _ = a.shape
    img = bpy.data.images.new(nom, w, h, alpha=False)
    if donnees:
        img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.ascontiguousarray(a[::-1]).ravel())
    os.makedirs(TEX_TMP, exist_ok=True)
    img.filepath_raw = os.path.join(TEX_TMP, nom + ".png")
    img.file_format = "PNG"
    img.save()
    return img


def textures():
    log("lecture des textures 4K")
    coul = lire("material_baseColor.png")
    rel = lire("material_normal.png")
    mr = lire("material_metallicRoughness.png")
    maps = (coul, rel, mr)
    # textes de la glissière (côté gauche : modèle et calibre ; côté droit : fabricant et logo)
    decaler(maps, 1005, 3392, 1880, 3440, 27, 27)
    decaler(maps, 2120, 3530, 3095, 3577, 27, 27)
    # « BER… » et « Type … »
    decaler(maps, 2540, 2243, 2935, 2282, 19, 20)
    # marque de l'organe de visée (deux exemplaires)
    interpoler(maps, 3946, 1983, 4070, 2058)
    interpoler(maps, 3796, 3972, 3870, 4072)
    # logos des plaquettes
    cloner_logo(maps, rel, 1948, 749, 108)
    cloner_logo(maps, rel, 1674, 1585, 108)
    log("réduction en 2K")
    coul2 = reduire(coul)
    coul2[..., :3] *= ASSOMBRIR
    rel2 = reduire(rel)
    n = rel2[..., :3] * 2.0 - 1.0
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)
    rel2[..., :3] = n * 0.5 + 0.5
    mr2 = reduire(mr)
    orm = np.ones_like(mr2)
    orm[..., 1] = np.clip(RUGOSITE[0] + RUGOSITE[1] * mr2[..., 1], 0, 1)
    # métal : on garde la carte d'origine (METAL_FINITION = 1). Essai fait : une finition presque diélectrique
    # paraît gris clair dans les couloirs (exposition automatique très haute) ; un métal sombre rugueux reste noir.
    lum = (coul[..., 0] * 0.3 + coul[..., 1] * 0.59 + coul[..., 2] * 0.11)
    lum = reduire(lum[..., None])[..., 0]
    usure = np.clip((lum - 0.30) / 0.25, 0, 1)
    orm[..., 2] = mr2[..., 2] * (METAL_FINITION + (1 - METAL_FINITION) * usure)
    return ecrire(coul2, "couleur", False), ecrire(rel2, "relief", True), ecrire(orm, "orm", True)


def materiau(ic, ir, io):
    m = bpy.data.materials.new("pistolet_9mm")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = ic
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    tr = nt.nodes.new("ShaderNodeTexImage")
    tr.image = ir
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tr.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    to = nt.nodes.new("ShaderNodeTexImage")
    to.image = io
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    return m


# ---------------------------------------------------------------- assemblage

def main():
    src = importer()
    faces = decouper(src)
    for k, v in sorted(faces.items()):
        log("pièce %-10s %5d faces" % (k, len(v)))
    m = materiau(*textures())
    pieces = {nom: piece(src, nom, faces[nom]) for nom in ("carcasse", "glissiere", "canon", "chien", "detente", "chargeur")}
    bpy.data.objects.remove(src, do_unlink=True)
    # repère du jeu
    rot = Matrix(((0, 1, 0), (-1, 0, 0), (0, 0, 1))).to_4x4()
    tr = rot @ Matrix.Scale(ECH, 4) @ Matrix.Translation(-ORIGINE_SRC)
    tris = 0
    for nom, ob in pieces.items():
        ob.data.transform(tr)
        ob.data.materials.clear()
        ob.data.materials.append(m)
        tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
    # pivots et axes
    placer_origine(pieces["chien"], Matrix.Translation(vers_jeu(PIVOT_CHIEN)))
    placer_origine(pieces["detente"], Matrix.Translation(vers_jeu(PIVOT_DETENTE)))
    g = pieces["glissiere"]
    c = sum((Vector(b) for b in g.bound_box), Vector()) / 8
    placer_origine(g, Matrix.Translation(c))
    ch = pieces["chargeur"]
    z = axe_chargeur(ch)
    x = Vector((1, 0, 0))
    y = z.cross(x)
    co = [v.co for v in ch.data.vertices]
    haut = max(co, key=lambda v: v.dot(z) if v.z < 0.045 else -1e9)   # sommet du corps (sous les cartouches)
    bas = min(co, key=lambda v: v.dot(z))
    centre = sum(co, Vector()) / len(co)
    o = centre + z * (haut.dot(z) - centre.dot(z))
    placer_origine(ch, Matrix.Translation(o) @ Matrix((x, y, z)).transposed().to_4x4())
    log("chargeur : axe (%.3f %.3f %.3f), origine (%.4f %.4f %.4f), longueur %.3f m" % (*z, *o, haut.dot(z) - bas.dot(z)))
    for nom, p in (("bouche", BOUCHE_SRC), ("ejection", EJECTION_SRC)):
        e = bpy.data.objects.new(nom, None)
        bpy.context.collection.objects.link(e)
        e.location = vers_jeu(p)
    # contrôle des dimensions
    mn = Vector((1e9,) * 3)
    mx = -mn
    for ob in pieces.values():
        for b in ob.bound_box:
            w = ob.matrix_world @ Vector(b)
            mn = Vector(map(min, mn, w))
            mx = Vector(map(max, mx, w))
    log("dimensions (m) : largeur %.3f longueur %.3f hauteur %.3f ; Y %.3f..%.3f Z %.3f..%.3f" % (*(mx - mn), mn.y, mx.y, mn.z, mx.z))
    bpy.ops.object.select_all(action="SELECT")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=92, export_vertex_color="NONE",
                              export_extras=False)
    log("EXPORT", OUT, os.path.getsize(OUT) // 1024, "ko,", tris, "triangles")


main()

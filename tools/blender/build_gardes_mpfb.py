"""Fabrique les gardes du cartel « El Círculo de Cobre » avec MPFB 2 (MakeHuman pour Blender, CC0)
et les branche sur les animations de la « Universal Animation Library » 1 de Quaternius (CC0).

Usage : blender -b --factory-startup -P tools/blender/build_gardes_mpfb.py [-- garde_1 garde_3 ...]
Sortie : assets/characters/gardes/garde_N.glb (squelette au nommage UE de Quaternius, maillages, animations)

Prérequis (une seule fois, voir tools/blender/install_mpfb_packs.py) :
- extension MPFB installée dans Blender ;
- paquets officiels de ressources MakeHuman installés dans les données de MPFB.

Principe du branchement sur les animations :
- MPFB crée le corps (phénotype, peau, vêtements) avec son squelette « game_engine », dont les os ont
  les mêmes noms que ceux de Quaternius (pelvis, spine_01…, hand_r, middle_01_r…) : on garde les poids
  de MPFB tels quels.
- Le squelette exporté est celui de Quaternius (mêmes os, même hiérarchie, os « leaf » compris) mais
  ses articulations sont placées sur celles du corps MPFB (pose de repos en A de MakeHuman).
- Pour chaque os, une rotation de correspondance C relie le membre MPFB au membre Quaternius
  (bras : direction + axe du coude ; main : direction + plan de la paume ; doigts et jambes : direction).
  Repos du nouvel os = C⁻¹ · repos Quaternius. Les animations sont recalculées image par image pour que
  chaque os ait EXACTEMENT la même orientation dans le monde que chez Quaternius : le code du jeu
  (BoneAttachment3D sur hand_r, scripts/finger_curl.gd, _calibrate_grips) fonctionne sans changement.
"""
import bpy
import addon_utils
import glob
import importlib
import math
import os
import sys
import time
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import retarget_cmu  # noqa: E402
import vieillir_gardes  # noqa: E402
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
Q_DIR = os.path.join(ROOT, "_sources", "quaternius")
TEX_PROJET = os.path.join(ROOT, "assets", "characters", "tex")
TEX_TMP = os.path.join(ROOT, "_sources", "mpfb", "textures_gardes")   # textures retouchées (ignoré par git)
OUT_DIR = os.path.join(ROOT, "assets", "characters", "gardes")
MODULE = "bl_ext.user_default.mpfb"

# mêmes animations (et mêmes noms) que assets/characters/garde.glb
ANIMS = ["Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Crouch_Idle_Loop", "Crouch_Fwd_Loop",
         "Pistol_Idle_Loop", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Pistol_Shoot",
         "Pistol_Reload", "Hit_Chest", "Hit_Head", "Death01", "Idle_Talking_Loop"]

# ---------------------------------------------------------------- les gardes
# âge MakeHuman : 0,5 = 25 ans ; au-dessus, +1 an pour 0,5/65 ; en dessous, 11 ans à 0,1875.
# race : mélange MakeHuman (afro / asiatique-amérindien / européen) -> traits latino-américains variés.
# vêtements : (fichier .mhclo, retouche de couleur) ; retouches :
#   None                   texture d'origine
#   ("mul", (r, g, b))     texture multipliée par une teinte
#   ("grad", sombre, clair) texture passée en niveaux de gris puis recolorée (couleurs 0-1, sRGB)
#   ("tissu", nom, échelle, sombre, clair) tissu tuilé du projet (assets/characters/tex/<nom>_*.jpg)
GARDES = {
    "garde_1": dict(
        desc="« El Flaco » : 22 ans, mince, métis clair ; casquette camouflage, bandana noir, t-shirt gris délavé, jean, baskets",
        pheno=dict(gender=1.0, age=0.43, muscle=0.45, weight=0.28, height=0.56, proportions=0.6,
                   race=dict(african=0.1, asian=0.35, caucasian=0.55)),
        peau=("young_caucasian_male.mhmat", ("mul", (0.93, 0.80, 0.66))),
        yeux="brown.mhmat", sourcils=("eyebrow001.mhclo", ("mul", (0.25, 0.2, 0.18))),
        cheveux=("short01.mhclo", ("mul", (0.5, 0.45, 0.42))),
        vetements=[
            ("elvs_crude_t-shirt_male.mhclo", ("grad", (0.07, 0.08, 0.09), (0.42, 0.44, 0.45))),
            ("punkduck_male_classic_jeans.mhclo", None),
            ("culturalibre_sneakers.mhclo", ("grad", (0.03, 0.03, 0.03), (0.42, 0.42, 0.4))),
            ("mindfront_patrol_cap.mhclo", ("mul", (0.8, 0.8, 0.75))),
        ],
        masque=("bandana", (0.03, 0.03, 0.034))),
    "garde_2": dict(
        desc="35 ans, carrure moyenne, métis amérindien ; cagoule noire, t-shirt camouflage, gilet tactique olive, cargo noir, rangers",
        pheno=dict(gender=1.0, age=0.577, muscle=0.62, weight=0.5, height=0.48, proportions=0.55,
                   race=dict(african=0.1, asian=0.55, caucasian=0.35)),
        peau=("young_asian_male.mhmat", ("mul", (0.86, 0.72, 0.6))),
        yeux="brown.mhmat", sourcils=("eyebrow003.mhclo", ("mul", (0.2, 0.17, 0.15))),
        cheveux=None,
        vetements=[
            ("drednicolson_short-tail_camo_tee.mhclo", None),
            ("cortu_cargo_pants.mhclo", ("grad", (0.02, 0.02, 0.02), (0.2, 0.2, 0.19))),
            ("mindfront_tactical_vest_male.mhclo", None),
            ("culturalibre_male_boots.mhclo", ("grad", (0.012, 0.011, 0.01), (0.2, 0.18, 0.16))),
        ],
        couvre=("cagoule", None, None)),
    "garde_3": dict(
        desc="« El Gordo » : 48 ans, en surpoids, afro-latino, cheveux ras grisonnants ; cache-cou gris remonté sur le nez, chemise kaki, jean, bottines",
        pheno=dict(gender=1.0, age=0.677, muscle=0.35, weight=1.0, height=0.45, proportions=0.4,
                   race=dict(african=0.55, asian=0.15, caucasian=0.3)),
        cibles=[("stomach-pregnant-incr", 0.75), ("measure-waist-circ-incr", 0.7), ("measure-hips-circ-incr", 0.3)],
        peau=("middleage_african_male.mhmat", ("mul", (1.08, 1.0, 0.95))),
        yeux="brown.mhmat", sourcils=("eyebrow006.mhclo", ("mul", (0.3, 0.29, 0.28))),
        cheveux=("short01.mhclo", ("grad", (0.04, 0.04, 0.04), (0.3, 0.29, 0.28))),
        vetements=[
            ("elvs_male_shirt_untucked_bd1.mhclo", ("grad", (0.09, 0.085, 0.06), (0.52, 0.48, 0.36))),
            ("elvs_jeans_straight_leg.mhclo", None),
            ("toigo_ankle_boots_male.mhclo", ("mul", (0.75, 0.7, 0.65))),
        ],
        masque=("cachecou", (0.11, 0.115, 0.12))),
    "garde_4": dict(
        desc="30 ans, costaud, métis ; capuche olive + bandana kaki, polo noir, gilet tactique noir, cargo olive, baskets montantes",
        pheno=dict(gender=1.0, age=0.54, muscle=0.85, weight=0.62, height=0.6, proportions=0.6,
                   race=dict(african=0.15, asian=0.25, caucasian=0.6)),
        peau=("toigo_light_skin_male_bronze.mhmat", ("mul", (0.9, 0.8, 0.7))),
        yeux="brownlight.mhmat", sourcils=("eyebrow002.mhclo", ("mul", (0.22, 0.18, 0.16))),
        cheveux=None,
        vetements=[
            ("namuhekam_male_polo_shirt.mhclo", ("grad", (0.012, 0.012, 0.014), (0.16, 0.16, 0.17))),
            ("cortu_cargo_pants.mhclo", ("grad", (0.05, 0.05, 0.03), (0.4, 0.39, 0.27))),
            ("mindfront_tactical_vest_male.mhclo", ("grad", (0.01, 0.01, 0.01), (0.22, 0.22, 0.21))),
            ("shoes02.mhclo", ("mul", (0.6, 0.6, 0.58))),
            ("culturalibre_hero-heroine_hood_1.mhclo", ("tissu", "cagoule", 6.0, (0.03, 0.035, 0.02), (0.3, 0.31, 0.2))),
        ],
        masque=("bandana", (0.2, 0.18, 0.12))),
}

# os dont la rotation de correspondance est l'identité (tronc, cou, tête, clavicules : déjà alignés)
IDENT = {"root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "clavicle_r"}
COQUILLE_ECHELLE = 14.0
CUIRE = "--sans-cuisson" not in sys.argv      # cuisson Cycles des tenues et de la peau (~1 à 2 min par garde)   # répétition du tricot sur les UV de la peau
FINGERS = ["thumb", "index", "middle", "ring", "pinky"]
MPFB_NAME = {"Head": "head", "root": "Root"}   # Quaternius -> MPFB


def log(*a):
    print("[gardes]", *a, flush=True)


def activer_mpfb():
    """--factory-startup désactive les extensions : on réactive MPFB pour cette session seulement."""
    if not addon_utils.check(MODULE)[1]:
        bpy.ops.preferences.addon_enable(module=MODULE)
    return importlib.import_module(MODULE)


# ---------------------------------------------------------------- textures

def prep_tex(src, out_name, size, retouche=None, non_color=False, alpha=False):
    """Réduit (et recolore) une texture ; l'enregistre dans TEX_TMP ; renvoie l'image Blender."""
    out = os.path.join(TEX_TMP, out_name + (".png" if alpha else ".jpg"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img = bpy.data.images.load(src, check_existing=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    w, h = img.size
    if max(w, h) > size:
        img.scale(size, max(1, int(h * size / w)))
        w, h = img.size
    if retouche:
        px = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(-1, 4)
        rgb = px[:, :3]
        if retouche[0] == "mul":
            rgb *= np.array(retouche[1], np.float32)
        elif retouche[0] == "grad":
            lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
            mask = px[:, 3] > 0.5 if alpha else np.ones(len(lum), bool)
            lo, hi = np.percentile(lum[mask], [2, 98]) if mask.any() else (0.0, 1.0)
            t = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 1)[:, None]
            c0 = np.array(retouche[1], np.float32)
            c1 = np.array(retouche[2], np.float32)
            rgb[:] = c0 + (c1 - c0) * t
        px[:, :3] = np.clip(rgb, 0, 1)
        img.pixels.foreach_set(px.ravel())
    img.filepath_raw = out
    img.file_format = "PNG" if alpha else "JPEG"
    try:
        img.save(filepath=out, quality=88)
    except TypeError:
        img.save()
    bpy.data.images.remove(img)
    im = bpy.data.images.load(out, check_existing=True)
    if non_color:
        im.colorspace_settings.name = "Non-Color"
    return im


def read_mhmat(path):
    """Lit un fichier .mhmat : textures (chemins absolus) et quelques réglages."""
    d = {}
    base = os.path.dirname(path)
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line or line.startswith(("#", "//")):
            continue
        parts = line.split(None, 1)
        if len(parts) == 2:
            k, v = parts
            if k.endswith("Texture"):
                p = v if os.path.isabs(v) else os.path.join(base, os.path.basename(v))
                if os.path.exists(p):
                    d[k] = p
            else:
                d[k] = v
    return d


def make_mat(name, diff, nor=None, rough=0.85, alpha=False, scale=None, metal=0.0, nor_strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    vec = None
    if scale:
        uv = nt.nodes.new("ShaderNodeTexCoord")
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (scale, scale, 1)
        nt.links.new(uv.outputs["UV"], mp.inputs["Vector"])
        vec = mp.outputs["Vector"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = diff
    if vec:
        nt.links.new(vec, t.inputs["Vector"])
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        # alpha découpé (glTF « MASK ») : arrondi de l'alpha
        r = nt.nodes.new("ShaderNodeMath")
        r.operation = "ROUND"
        nt.links.new(t.outputs["Alpha"], r.inputs[0])
        nt.links.new(r.outputs[0], bsdf.inputs["Alpha"])
        try:
            m.blend_method = "CLIP"
        except Exception:
            pass
    if nor is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = nor
        if vec:
            nt.links.new(vec, tn.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = nor_strength
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


ROUGH = {"jeans": 0.9, "boots": 0.55, "sneakers": 0.7, "vest": 0.8, "cap": 0.85, "bandana": 0.9}


def rough_for(asset):
    for k, v in ROUGH.items():
        if k in asset:
            return v
    return 0.88


A_CUIRE = {}      # objet -> (genre, image de base, normal map, couleur unie, préfixe) : cuisson Cycles


def habiller(ob, kind, asset_file, retouche, data_dir, nom):
    """Remplace le matériau MakeHuman d'un objet par un matériau simple exportable en glTF."""
    asset = os.path.splitext(asset_file)[0]
    if kind == "skin":
        mh = read_mhmat(glob.glob(os.path.join(data_dir, "skins", asset, "*.mhmat"))[0])
    elif kind == "eyes":
        mh = read_mhmat(os.path.join(data_dir, "eyes", "materials", asset_file))
    else:
        sub = {"eyebrows": "eyebrows", "hair": "hair"}.get(kind, "clothes")
        mh = read_mhmat(glob.glob(os.path.join(data_dir, sub, asset, "*.mhmat"))[0])
    alpha = kind in ("eyebrows", "hair")
    tag = os.path.join(nom, asset.replace("-", "_").replace(".", "_"))   # textures : TEX_TMP/<garde>/<objet>_diff.jpg
    if retouche and retouche[0] == "tissu":
        _, tissu, scale, c0, c1 = retouche
        rt = ("grad", c0, c1) if c0 else None
        diff = prep_tex(os.path.join(TEX_PROJET, tissu + "_diff.jpg"), tag + "_diff", 1024, rt)
        nor = prep_tex(os.path.join(TEX_PROJET, tissu + "_nor_gl.jpg"), tag + "_nor", 1024, None, True)
        mat = make_mat(os.path.basename(tag), diff, nor, 0.95, scale=scale, nor_strength=0.9)
        moy = tuple((a + b) / 2 for a, b in zip(c0, c1)) if c0 else (0.3, 0.3, 0.3)
        A_CUIRE[ob] = (kind, None, None, moy, tag)
    else:
        size = {"skin": 2048, "eyes": 512, "eyebrows": 512, "hair": 1024}.get(kind, 1024)
        if "tactical_vest" in asset:
            size = 2048
        diff = prep_tex(mh["diffuseTexture"], tag + "_diff", size, retouche, alpha=alpha)
        nor = None
        if "normalmapTexture" in mh:
            nor = prep_tex(mh["normalmapTexture"], tag + "_nor", min(size, 1024), None, True)
        rough = {"skin": 0.55, "eyes": 0.15, "eyebrows": 0.9, "hair": 0.8}.get(kind, rough_for(asset))
        mat = make_mat(os.path.basename(tag), diff, nor, rough, alpha=alpha)
        if kind in ("skin", "clothes"):
            A_CUIRE[ob] = (kind, diff, nor, None, tag)
    ob.data.materials.clear()
    ob.data.materials.append(mat)


# ---------------------------------------------------------------- construction MPFB

def creer_humain(spec, mpfb):
    from bl_ext.user_default.mpfb.services import HumanService
    info = HumanService._create_default_human_info_dict()
    ph = dict(spec["pheno"])
    race = ph.pop("race")
    info["phenotype"].update(ph)
    info["phenotype"]["race"] = race
    info["rig"] = "game_engine"
    info["eyes"] = "low-poly.mhclo"
    info["eyebrows"] = spec["sourcils"][0]
    info["hair"] = spec["cheveux"][0] if spec["cheveux"] else ""
    info["skin_mhmat"] = ""
    info["skin_material_type"] = "NONE"
    info["clothes"] = [v[0] for v in spec["vetements"]]
    info["targets"] = [{"target": t, "value": v} for t, v in spec.get("cibles", [])]   # ventre, tour de taille…
    s = HumanService.get_default_deserialization_settings()
    s["subdiv_levels"] = 0
    body = HumanService.deserialize_from_dict(info, s)
    return body, body.parent


def preparer_maillages(body, rig):
    """Fige les formes (cibles MakeHuman), supprime les aides et la peau cachée sous les vêtements."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for ob in meshes:
        for m in list(ob.modifiers):
            if m.type == "ARMATURE":
                ob.modifiers.remove(m)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in meshes:
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        if ob.data.shape_keys:
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
        for m in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
        # objets très détaillés (gilet : 20 000 sommets, rangers : 15 000) : allégés pour le jeu
        if ob != body and len(ob.data.vertices) > 7000:
            dec = ob.modifiers.new("allege", "DECIMATE")
            dec.ratio = 6000.0 / len(ob.data.vertices)
            bpy.ops.object.modifier_apply(modifier="allege")
        # vêtements très légers (pantalon cargo : 211 sommets) : une subdivision pour des plis ronds
        if ob != body and len(ob.data.vertices) < 1000 and "low-poly" not in ob.name and "eyebrow" not in ob.name:
            sub = ob.modifiers.new("lisse", "SUBSURF")
            sub.levels = 1
            sub.render_levels = 1
            bpy.ops.object.modifier_apply(modifier="lisse")
        for p in ob.data.polygons:
            p.use_smooth = True
        ob.select_set(False)
    return meshes


COUVRANTS = ("pants", "jeans", "shirt", "tee", "polo", "boots", "sneakers", "shoes")


def masquer_peau(body, meshes, garder_cou=False):
    """Supprime la peau entièrement cachée sous les pantalons, hauts et chaussures (évite qu'elle
    traverse le tissu pendant les animations)."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    trees = []
    for ob in meshes:
        if ob != body and any(k in ob.name.lower() for k in COUVRANTS):
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bm.transform(ob.matrix_world)
            bm.normal_update()
            trees.append(BVHTree.FromBMesh(bm))
            bm.free()
    mw = body.matrix_world
    hidden = []
    z_cou = None
    if garder_cou:   # la cagoule sera taillée dans cette peau jusque sous le col : on la garde ici
        gi = body.vertex_groups.get("neck_01")
        zs = [(mw @ v.co).z for v in body.data.vertices if gi and any(g.group == gi.index and g.weight > 0.5 for g in v.groups)]
        z_cou = (min(zs) - 0.17) if zs else None
    for v in body.data.vertices:
        w = mw @ v.co
        cov = False
        if z_cou is not None and w.z > z_cou and abs(w.x) < 0.08:
            hidden.append(False)
            continue
        for t in trees:
            loc, nor, _, dist = t.find_nearest(w, 0.04)
            if loc is not None and (w - loc).dot(nor) < 0.006:
                cov = True
                break
        hidden.append(cov)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    kill = [f for f in bm.faces if all(hidden[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(body.data)
    bm.free()
    log("peau cachée supprimée :", len(kill), "faces")


def dominant_groups(ob, bones):
    # seuls les groupes d'os comptent (MPFB ajoute « body », « scalp », « helper-… » à poids 1)
    names = {g.index: g.name for g in ob.vertex_groups if g.name in bones}
    out = []
    for v in ob.data.vertices:
        g = max((g for g in v.groups if g.group in names), key=lambda g: g.weight, default=None)
        out.append(names.get(g.group, "") if g else "")
    return out


def coquille(body, eyes, kind, mat, bones):
    """Cagoule (fente pour les yeux) ou cache-cou (remonté sous les yeux), taillés dans la peau de la
    tête et du cou, lissés puis décollés de quelques millimètres. Les poids de la peau sont gardés."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    ew = [eyes.matrix_world @ Vector(c) for c in eyes.bound_box]
    exmin, exmax = min(v.x for v in ew), max(v.x for v in ew)
    ezc = sum(v.z for v in ew) / 8.0
    eyc = sum(v.y for v in ew) / 8.0
    dom = dominant_groups(body, bones)
    sh = body.copy()
    sh.data = body.data.copy()
    sh.name = "Cagoule" if kind == "cagoule" else "Cache_cou"
    bpy.context.collection.objects.link(sh)
    bm = bmesh.new()
    bm.from_mesh(sh.data)
    bm.verts.ensure_lookup_table()
    src = bmesh.new()
    src.from_mesh(body.data)
    src.normal_update()
    tree = BVHTree.FromBMesh(src)
    neck = [bm.verts[i].co.z for i, g in enumerate(dom) if g == "neck_01"]
    neck_z = min(neck) if neck else 1.4
    cou_y = sum(bm.verts[i].co.y for i, g in enumerate(dom) if g == "neck_01") / max(1, len(neck))
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        n_ok = sum(1 for v in f.verts if dom[v.index] in ("head", "Head", "neck_01"))
        keep = n_ok >= 2
        if kind == "cagoule":
            # le bas de la cagoule descend sous le col du t-shirt (plus d'anneau de peau visible)
            # (choix géométrique : tout le tour du cou jusqu'à 7 cm sous sa base, sans les épaules)
            keep = keep or (c.z > neck_z - 0.17 and abs(c.x) < 0.075 and abs(c.y - cou_y) < 0.13)
        else:
            keep = keep and ezc - 0.005 > c.z > neck_z - 0.03
        if not keep:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    if kind == "cagoule":
        # fente des yeux : deux coupes horizontales, puis on retire la bande entre elles devant les yeux
        for zc in (ezc + 0.017, ezc - 0.015):
            g = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=g, dist=0.0001, plane_co=Vector((0, 0, zc)), plane_no=Vector((0, 0, 1)))
        slit = [f for f in bm.faces
                if ezc - 0.015 < f.calc_center_median().z < ezc + 0.017
                and exmin - 0.024 < f.calc_center_median().x < exmax + 0.024
                and f.calc_center_median().y < eyc + 0.03]
        bmesh.ops.delete(bm, geom=slit, context="FACES")
        g = bm.verts[:] + bm.edges[:] + bm.faces[:]   # bas : bord net, rentré sous le col
        bmesh.ops.bisect_plane(bm, geom=g, dist=0.0001, plane_co=Vector((0, cou_y, neck_z - 0.05)),
                               plane_no=Vector((0, -1.6, 1)).normalized(), clear_inner=True)   # plus bas devant (encolure en V)
    if kind == "cachecou":
        # bord supérieur net, juste sous les yeux, un peu plus haut derrière la tête
        g = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=g, dist=0.0001, plane_co=Vector((0, eyc, ezc - 0.03)),
                               plane_no=Vector((0, 0.3, 1)).normalized(), clear_outer=True)
        g = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=g, dist=0.0001, plane_co=Vector((0, eyc, neck_z)),
                               plane_no=Vector((0, -0.35, 1)).normalized(), clear_inner=True)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # bords (fente des yeux, haut du cache-cou) : on adoucit l'escalier laissé par la découpe
    edge = [v for v in bm.verts if v.is_boundary]
    for _ in range(6):
        bmesh.ops.smooth_vert(bm, verts=edge, factor=0.5, use_axis_x=False, use_axis_y=False, use_axis_z=True)
    inner = [v for v in bm.verts if not v.is_boundary]
    it, fac, off = (1, 0.4, 0.0035) if kind == "cagoule" else (5, 0.5, 0.006)
    for _ in range(it):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=fac, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # décollement : chaque sommet repoussé au moins à « off » au-dessus de la peau
    for v in bm.verts:
        loc, nor, _, _ = tree.find_nearest(v.co)
        if loc is not None:
            d = (v.co - loc).dot(nor)
            o = off
            if kind == "cagoule" and v.co.z < neck_z + 0.01:     # partie rentrée sous le col : plaquée
                o = 0.0018
            if d < o:
                v.co += nor * (o - d)
    bm.to_mesh(sh.data)
    bm.free()
    src.free()
    sh.data.materials.clear()
    sh.data.materials.append(mat)
    sol = sh.modifiers.new("epaisseur", "SOLIDIFY")
    sol.thickness = 0.0025
    sol.offset = 1.0
    bpy.context.view_layer.objects.active = sh
    bpy.ops.object.select_all(action="DESELECT")
    sh.select_set(True)
    bpy.ops.object.modifier_apply(modifier="epaisseur")
    for p in sh.data.polygons:
        p.use_smooth = True
    log(sh.name, len(sh.data.vertices), "sommets")
    if kind == "cagoule":
        # peau cachée sous la cagoule supprimée (sinon la gorge la traverse quand le cou se plie),
        # sauf autour de la fente des yeux
        cm = bmesh.new()
        cm.from_mesh(sh.data)
        cm.normal_update()
        ct = BVHTree.FromBMesh(cm)
        cm.free()
        cache = []
        for v in body.data.vertices:
            loc, nor, _, dist = ct.find_nearest(v.co, 0.015)
            oeil = v.co.y < eyc + 0.07 and abs(v.co.z - ezc) < 0.04
            cache.append(loc is not None and not oeil)
        bb = bmesh.new()
        bb.from_mesh(body.data)
        bb.verts.ensure_lookup_table()
        kill = [f for f in bb.faces if all(cache[v.index] for v in f.verts)]
        bmesh.ops.delete(bb, geom=kill, context="FACES")
        bb.to_mesh(body.data)
        bb.free()
        log("peau sous la cagoule supprimée :", len(kill), "faces")
    return sh


def reperes(body, eyes, bones):
    """Hauteur et profondeur des yeux, du menton, du cou ; axes de la tête et du cou (repère monde)."""
    ew = [eyes.matrix_world @ Vector(c) for c in eyes.bound_box]
    ez = sum(v.z for v in ew) / 8.0
    ey = sum(v.y for v in ew) / 8.0
    dom = dominant_groups(body, bones)
    mw = body.matrix_world
    pts = [(mw @ v.co, dom[v.index]) for v in body.data.vertices]
    menton = min((p.z for p, g in pts if g in ("head", "Head") and abs(p.x) < 0.012 and p.y < ey + 0.01 and p.z < ez - 0.05),
                 default=ez - 0.12)
    cou = [p for p, g in pts if g == "neck_01"]
    return {"yeux_z": ez, "yeux_y": ey, "menton_z": menton, "cou_z": min(p.z for p in cou),
            "tete_y": ey + 0.075, "cou_y": sum(p.y for p in cou) / len(cou)}


# ---------------------------------------------------------------- squelette et animations

def heads(arm):
    mw = arm.matrix_world
    return {b.name: mw @ b.head_local for b in arm.data.bones}, {b.name: mw @ b.tail_local for b in arm.data.bones}


def rest_world(arm):
    return {b.name: arm.matrix_world @ b.matrix_local for b in arm.data.bones}


def frame3(d, n):
    d = d.normalized()
    n = (n - d * n.dot(d)).normalized()
    return Matrix((d, n, d.cross(n))).transposed()


def rotdiff(a, b):
    return a.normalized().rotation_difference(b.normalized()).to_matrix()


def import_ual():
    ual = glob.glob(os.path.join(Q_DIR, "u1", "**", "Unreal-Godot", "UAL1_Standard.glb"), recursive=True)[0]
    before = set(bpy.data.objects)
    before_act = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=ual)
    new = [o for o in bpy.data.objects if o not in before]
    q = next(o for o in new if o.type == "ARMATURE")
    for o in new:
        if o != q:
            bpy.data.objects.remove(o, do_unlink=True)
    acts = {}
    for name in ANIMS:
        a = bpy.data.actions.get(name) or next((a for a in bpy.data.actions if a not in before_act and a.name.startswith(name)), None)
        if a is None:
            log("ANIM MANQUANTE", name)
            continue
        acts[name] = a
    if q.animation_data is None:
        q.animation_data_create()
    for t in list(q.animation_data.nla_tracks):
        q.animation_data.nla_tracks.remove(t)
    return q, acts


def set_action(ob, act):
    ob.animation_data.action = act
    try:
        if act.slots:
            ob.animation_data.action_slot = act.slots[0]
    except Exception:
        pass


def hinge_axes(q, acts):
    """Axe du coude de Quaternius (dans le repère de repos du bras) : pris dans l'image où le coude
    est le plus plié, parmi quelques animations au pistolet."""
    rw = rest_world(q)
    best = {}
    sc = bpy.context.scene
    for name in ("Pistol_Idle_Loop", "Pistol_Aim_Neutral", "Pistol_Reload", "Idle_Loop"):
        if name not in acts:
            continue
        set_action(q, acts[name])
        r = acts[name].frame_range
        for f in range(int(r[0]), int(r[1]) + 1, 4):
            sc.frame_set(f)
            for s in "lr":
                pb = q.pose.bones
                hu = q.matrix_world @ pb["upperarm_" + s].head
                hl = q.matrix_world @ pb["lowerarm_" + s].head
                hh = q.matrix_world @ pb["hand_" + s].head
                du, dl = (hl - hu).normalized(), (hh - hl).normalized()
                ang = du.angle(dl)
                if ang > best.get(s, (0,))[0]:
                    n = du.cross(dl).normalized()
                    pw = (q.matrix_world @ pb["upperarm_" + s].matrix).to_3x3().normalized()
                    n_rest = rw["upperarm_" + s].to_3x3().normalized() @ pw.inverted() @ n
                    best[s] = (ang, n_rest)
    for s in best:
        log("coude", s, "pli max %.0f°" % math.degrees(best[s][0]))
    return {s: best[s][1] for s in best}


def correspondances(q, rig, hinge):
    """Rotation C (monde) qui amène chaque membre MPFB (pose A) sur le membre Quaternius (pose T)."""
    hT, tT = heads(q)
    hA, tA = heads(rig)
    C = {}
    for b in q.data.bones:
        if b.name in IDENT:
            C[b.name] = Matrix.Identity(3)
    for s in "lr":
        ua, la, ha = "upperarm_" + s, "lowerarm_" + s, "hand_" + s
        dA, lA = hA[la] - hA[ua], hA[ha] - hA[la]
        nA = dA.cross(lA)
        dT, lT = hT[la] - hT[ua], hT[ha] - hT[la]
        nT = hinge[s]
        C[ua] = frame3(dT, nT) @ frame3(dA, nA).inverted()
        C[la] = frame3(lT, nT) @ frame3(lA, nA).inverted()
        m = "middle_01_" + s
        latA = hA["index_01_" + s] - hA["pinky_01_" + s]
        latT = hT["index_01_" + s] - hT["pinky_01_" + s]
        C[ha] = frame3(hT[m] - hT[ha], latT) @ frame3(hA[m] - hA[ha], latA).inverted()
        for f in FINGERS:
            par = ha
            for k in ("01", "02", "03"):
                n = "%s_%s_%s" % (f, k, s)
                nxt = "%s_%02d_%s" % (f, int(k) + 1, s)
                segA = (hA[nxt] - hA[n]) if nxt in hA else (tA[n] - hA[n])
                leaf = "%s_04_leaf_%s" % (f, s)
                segT = (hT[nxt] - hT[n]) if nxt in hT else (hT[leaf] - hT[n])
                C[n] = rotdiff(C[par] @ segA, segT) @ C[par]
                par = n
            C["%s_04_leaf_%s" % (f, s)] = C[par]
        chain = [("thigh_", "calf_"), ("calf_", "foot_"), ("foot_", "ball_")]
        par = "pelvis"
        for a, bn in chain:
            a, bn = a + s, bn + s
            C[a] = rotdiff(C[par] @ (hA[bn] - hA[a]), hT[bn] - hT[a]) @ C[par]
            par = a
        bl = "ball_" + s
        C[bl] = rotdiff(C[par] @ (tA[bl] - hA[bl]), hT["ball_leaf_" + s] - hT[bl]) @ C[par]
        C["ball_leaf_" + s] = C[bl]
    for b in q.data.bones:
        if b.name not in C:
            log("os sans correspondance (identité)", b.name)
            C[b.name] = Matrix.Identity(3)
    return C


def construire_squelette(q, rig, C):
    """Copie du squelette Quaternius, articulations placées sur le corps MPFB, repos = C⁻¹ · repos Q."""
    hA, tA = heads(rig)
    rT = rest_world(q)
    n = q.copy()
    n.data = q.data.copy()
    n.name = n.data.name = "Garde"
    n.animation_data_clear()
    bpy.context.collection.objects.link(n)
    n.matrix_world = Matrix.Identity(4)
    pos = {}
    for b in q.data.bones:
        mp = MPFB_NAME.get(b.name, b.name)
        if mp in hA:
            pos[b.name] = hA[mp].copy()
        elif "_04_leaf_" in b.name:
            pos[b.name] = tA[b.parent.name].copy()
        elif b.name.startswith("ball_leaf_"):
            pos[b.name] = tA[b.parent.name].copy()
        else:
            pos[b.name] = Vector((0, 0, 0))
            log("os placé à l'origine", b.name)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = n
    n.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for eb in n.data.edit_bones:
        eb.use_connect = False
    for eb in n.data.edit_bones:
        rot = C[eb.name].inverted() @ rT[eb.name].to_3x3().normalized()
        kids = list(q.data.bones[eb.name].children)
        length = q.data.bones[eb.name].length
        if kids:
            length = max(0.01, min((pos[c.name] - pos[eb.name]).length for c in kids))
        mtx = Matrix.Translation(pos[eb.name]) @ rot.to_4x4()
        eb.matrix = mtx
        eb.length = max(length, 0.008)
    bpy.ops.object.mode_set(mode="OBJECT")
    return n


def bake_animations(q, n, acts):
    """Recalcule chaque animation pour le nouveau squelette : même orientation monde, os par os."""
    sc = bpy.context.scene
    rT = rest_world(q)
    rN = rest_world(n)
    rN_inv = {k: v.inverted() for k, v in rN.items()}
    bones = []                                        # ordre parent avant enfant
    pile = [b for b in n.data.bones if b.parent is None]
    while pile:
        b = pile.pop(0)
        bones.append(b.name)
        pile.extend(b.children)
    parent = {b.name: (b.parent.name if b.parent else None) for b in n.data.bones}
    s_h = rN["pelvis"].translation.z / rT["pelvis"].translation.z
    if n.animation_data is None:
        n.animation_data_create()
    for pb in n.pose.bones:
        pb.rotation_mode = "QUATERNION"
    new = {}
    for name, act in acts.items():
        set_action(q, act)
        na = bpy.data.actions.new("tmp_" + name)
        n.animation_data.action = na
        r = act.frame_range
        prev = {}
        for f in range(int(r[0]), int(r[1]) + 1):
            sc.frame_set(f)
            W = {}
            for b in bones:
                P = q.matrix_world @ q.pose.bones[b].matrix
                rot = P.to_3x3().normalized()
                p = parent[b]
                if p is None or b == "pelvis":
                    if b == "pelvis":
                        pos = rN[b].translation + (P.translation - rT[b].translation) * s_h
                    else:
                        pos = rN[b].translation + (P.translation - rT[b].translation)
                else:
                    pos = (W[p] @ rN_inv[p] @ rN[b]).translation
                W[b] = Matrix.Translation(pos) @ rot.to_4x4()
                if p is None:
                    basis = rN_inv[b] @ W[b]
                else:
                    basis = (rN_inv[b] @ rN[p]) @ W[p].inverted() @ W[b]
                loc, qr, _ = basis.decompose()
                if b in prev:
                    qr.make_compatible(prev[b])
                prev[b] = qr
                pb = n.pose.bones[b]
                pb.rotation_quaternion = qr
                pb.location = loc
                pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
                pb.keyframe_insert("location", frame=f, group=b)
        new[name] = na
        log("animation", name, int(r[1] - r[0] + 1), "images")
    n.animation_data.action = None
    for pb in n.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    return new


# ---------------------------------------------------------------- assemblage

def construire(nom, spec, mpfb, data_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    activer_mpfb()
    body, rig = creer_humain(spec, mpfb)
    log(nom, "corps MPFB créé :", body.name, rig.name)
    meshes = preparer_maillages(body, rig)
    masquer_peau(body, meshes, garder_cou=bool(spec.get("couvre")) and spec["couvre"][0] == "cagoule")

    # matériaux
    habiller(body, "skin", spec["peau"][0], spec["peau"][1], data_dir, nom)
    for ob in meshes:
        if ob == body:
            continue
        low = ob.name.lower()
        if "low-poly" in low:
            habiller(ob, "eyes", spec["yeux"], None, data_dir, nom)
            ob.name = "Yeux"
        elif "eyebrow" in low:
            habiller(ob, "eyebrows", spec["sourcils"][0], spec["sourcils"][1], data_dir, nom)
            ob.name = "Sourcils"
        elif spec["cheveux"] and os.path.splitext(spec["cheveux"][0])[0] in ob.name:
            habiller(ob, "hair", spec["cheveux"][0], spec["cheveux"][1], data_dir, nom)
            ob.name = "Cheveux"
        else:
            v = next((v for v in spec["vetements"] if os.path.splitext(v[0])[0] in ob.name), None)
            if v is None:
                log("objet inattendu supprimé", ob.name)
                bpy.data.objects.remove(ob, do_unlink=True)
                continue
            habiller(ob, "clothes", v[0], v[1], data_dir, nom)
            ob.name = os.path.splitext(v[0])[0].replace("-", "_")
    body.name = "Corps"
    if spec.get("couvre"):
        kind, c0, c1 = spec["couvre"]
        rt = ("grad", c0, c1) if c0 else None
        diff = prep_tex(os.path.join(TEX_PROJET, "cagoule_diff.jpg"), os.path.join(nom, kind + "_diff"), 1024, rt)
        nor = prep_tex(os.path.join(TEX_PROJET, "cagoule_nor_gl.jpg"), os.path.join(nom, kind + "_nor"), 1024, None, True)
        mat = make_mat(kind, diff, nor, 0.95, scale=COQUILLE_ECHELLE, nor_strength=1.0)
        coquille(body, bpy.data.objects["Yeux"], kind, mat, {b.name for b in rig.data.bones})
    if spec.get("masque"):
        kind, coul = spec["masque"]
        rep = reperes(body, bpy.data.objects["Yeux"], {b.name for b in rig.data.bones})
        log("repères du visage", {k: round(v, 3) for k, v in rep.items()})
        obst = [o for o in bpy.data.objects if o.type == "MESH" and o != body and
                any(k in o.name.lower() for k in ("shirt", "tee", "polo", "vest", "cheveux"))]
        mk, _ = vieillir_gardes.masque_tissu(kind, body, obst, rep, "Bandana" if kind == "bandana" else "Cache_cou")
        mz = rep["menton_z"]
        ref = (lambda p: Vector((p.x, p.y, max(p.z, mz + 0.012)))) if kind == "bandana" else None
        vieillir_gardes.copier_poids(mk, body, ref)
        A_CUIRE[mk] = ("clothes", None, None, coul, os.path.join(nom, kind))
    if CUIRE:
        t0 = time.time()
        vieillir_gardes.preparer_cycles()
        for ob, (kind, diff, nor, coul, tag) in A_CUIRE.items():
            low = ob.name.lower()
            if kind == "skin":
                mat = vieillir_gardes.cuire_peau(ob, diff, TEX_TMP, tag + "_peau", 2048, rides=spec.get("rides", 0.5))
            else:
                grand = any(k in low for k in ("shirt", "tee", "polo", "jeans", "pants", "vest"))
                haut = any(k in low for k in ("shirt", "tee", "polo"))
                mat = vieillir_gardes.cuire_vetement(
                    ob, diff, nor, TEX_TMP, tag + "_v", 2048 if grand else 1024, couleur=coul,
                    salete=spec.get("salete", 1.0), sueur=1.0 if haut else 0.0)
            ob.data.materials.clear()
            ob.data.materials.append(mat)
            log("cuit", ob.name, "%.0f s" % (time.time() - t0))
        A_CUIRE.clear()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]

    # squelette Quaternius + animations
    q, acts = import_ual()
    hinge = hinge_axes(q, acts)
    acts.update(retarget_cmu.creer_actions(q, acts, set_action))   # captures CMU + composites vivants
    C = correspondances(q, rig, hinge)
    n = construire_squelette(q, rig, C)
    new = bake_animations(q, n, acts)

    # liaison des maillages au nouveau squelette (poids MPFB, os renommés)
    names = {b.name for b in n.data.bones}
    for ob in meshes:
        for vg in list(ob.vertex_groups):
            if vg.name == "head":
                vg.name = "Head"
            elif vg.name == "Root":
                vg.name = "root"
            elif vg.name not in names:
                ob.vertex_groups.remove(vg)
        mw = ob.matrix_world.copy()
        ob.parent = n
        ob.matrix_world = mw
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = n
    bpy.data.objects.remove(rig, do_unlink=True)
    bpy.data.objects.remove(q, do_unlink=True)
    for a in list(bpy.data.actions):
        if a not in new.values():
            bpy.data.actions.remove(a)
    for name, a in new.items():
        a.name = name
        tr = n.animation_data.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, int(a.frame_range[0]), a)
        try:
            st.action_slot = a.slots[0]
        except Exception:
            pass
        tr.mute = True

    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
    out = os.path.join(OUT_DIR, nom + ".glb")
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = n
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_yup=True, export_skins=True, export_reset_pose_bones=True,
                              export_image_format="AUTO", export_jpeg_quality=88)
    log("EXPORT", out, os.path.getsize(out) // 1024, "ko,", len(new), "animations,", tris, "triangles")


def main():
    argv = [a for a in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []) if not a.startswith("--")]
    noms = argv or list(GARDES)
    activer_mpfb()
    from bl_ext.user_default.mpfb.services import LocationService
    data_dir = LocationService.get_user_data()
    for nom in noms:
        construire(nom, GARDES[nom], None, data_dir)


main()

"""Corps de Marc Delmas (joueur, vu par la caméra-piéton) fait avec MPFB 2 (MakeHuman pour Blender, CC0),
branché sur les animations UAL1 de Quaternius exactement comme les gardes.

Usage : blender -b --factory-startup -P tools/blender/build_marc_mpfb.py
Sortie : assets/characters/marc.glb (remplace l'ancien corps Quaternius de build_characters.py)

- 48 ans, carrure d'ancien commando, européen ; mains à la taille réelle (MakeHuman) ;
- veste de travail sombre usée (« male_casualsuit05 », CC0, recolorée et vieillie), jean, rangers ;
- gants tactiques en cuir noir : coquille taillée dans la peau des mains (mêmes poids, doigts articulés),
  décollée de 1,3 mm, avec poignet, coutures, plis aux articulations et usure cuits par Cycles ;
- tête et cou retirés (la caméra est à leur place).

Réutilise les fonctions de tools/blender/build_gardes_mpfb.py (squelette Quaternius, correspondances,
recalcul des animations) : même nommage d'os UE (hand_r, index_01_r…) pour scripts/joueur/bras_ik.gd.
"""
import bpy
import bmesh
import math
import os
import sys
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ICI = os.path.dirname(os.path.abspath(__file__))
G = {"__name__": "gardes_mpfb", "__file__": os.path.join(ICI, "build_gardes_mpfb.py")}
_src = open(G["__file__"], encoding="utf-8").read()
_src = _src[:_src.rstrip().rfind("\nmain()")]          # fonctions seulement, sans lancer la fabrication des gardes
exec(compile(_src, G["__file__"], "exec"), G)
G["COUVRANTS"] = G["COUVRANTS"] + ("suit",)

ROOT = G["ROOT"]
TEX_PROJET = G["TEX_PROJET"]
TEX_TMP = os.path.join(ROOT, "_sources", "mpfb", "textures_marc")
G["TEX_TMP"] = TEX_TMP
OUT = os.path.join(ROOT, "assets", "characters", "marc.glb")
log = G["log"]

MARC = dict(
    desc="Marc Delmas, 48 ans, ancien commando, européen ; veste sombre usée, jean, rangers, gants de cuir",
    pheno=dict(gender=1.0, age=0.677, muscle=0.68, weight=0.55, height=0.56, proportions=0.62,
               race=dict(african=0.03, asian=0.04, caucasian=0.93)),
    peau=("middleage_caucasian_male.mhmat", ("mul", (0.95, 0.86, 0.8))),
    yeux="brown.mhmat", sourcils=("eyebrow001.mhclo", None), cheveux=None,
    vetements=[
        ("male_casualsuit05.mhclo", "veste"),
        ("culturalibre_male_boots.mhclo", ("grad", (0.012, 0.011, 0.01), (0.2, 0.17, 0.14))),
    ])

MAINS = ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_")


# ---------------------------------------------------------------- veste usée

def bruit(w, h, cellule, rng):
    """Bruit de valeur lissé (0-1), taille de cellule en pixels."""
    gw, gh = max(2, w // cellule + 2), max(2, h // cellule + 2)
    g = rng.random((gh, gw)).astype(np.float32)
    ys = np.linspace(0, gh - 1.001, h)
    xs = np.linspace(0, gw - 1.001, w)
    y0, x0 = ys.astype(int), xs.astype(int)
    fy, fx = (ys - y0)[:, None], (xs - x0)[None, :]
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy


def veste_usee(src, out, taille):
    """Veste « male_casualsuit05 » : tissu recoloré en gris anthracite chaud, grain de toile du projet,
    zones délavées et salissures ; chemise rayée assombrie ; jean gardé mais terni."""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img = bpy.data.images.load(src, check_existing=False)
    if img.size[0] > taille:
        img.scale(taille, taille)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    rgb = px[:, :, :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    jean = (rgb[:, :, 2] > rgb[:, :, 0] * 1.25) & (rgb[:, :, 2] > 0.08)
    rouge = (rgb[:, :, 0] > rgb[:, :, 1] * 1.6) & (rgb[:, :, 0] > 0.08)
    # grain de toile tuilé (texture du projet), répété 6 fois
    tis = bpy.data.images.load(os.path.join(TEX_PROJET, "veste_marc_diff.jpg"), check_existing=False)
    tw, th = tis.size
    tp = np.empty(tw * th * 4, np.float32)
    tis.pixels.foreach_get(tp)
    tl = (tp.reshape(th, tw, 4)[:, :, :3] @ np.array([0.299, 0.587, 0.114], np.float32))
    tl = tl / max(tl.mean(), 1e-4)
    yy = (np.arange(h) * 6 * th // h) % th
    xx = (np.arange(w) * 6 * tw // w) % tw
    grain = tl[yy][:, xx]
    bpy.data.images.remove(tis)
    rng = np.random.default_rng(48)
    delave = bruit(w, h, 90, rng) * 0.6 + bruit(w, h, 23, rng) * 0.4
    tache = bruit(w, h, 40, rng)
    m = np.clip((lum - 0.05) / 0.3, 0, 1)
    sombre, clair = np.array([0.016, 0.0155, 0.015], np.float32), np.array([0.085, 0.08, 0.072], np.float32)
    veste = sombre + (clair - sombre) * m[:, :, None]
    veste *= (0.55 + 0.45 * grain)[:, :, None]
    veste *= (0.7 + 1.1 * np.clip(delave - 0.32, 0, 1))[:, :, None]            # délavé par endroits
    veste *= (1.0 - 0.35 * np.clip((tache - 0.62) * 4, 0, 1))[:, :, None]      # taches sombres
    chemise = (0.03 + 0.06 * lum)[:, :, None] * np.array([1.0, 0.95, 0.9], np.float32)
    jeans = rgb * np.array([0.55, 0.6, 0.65], np.float32) * (0.85 + 0.15 * grain)[:, :, None]
    res = np.where(jean[:, :, None], jeans, np.where(rouge[:, :, None], chemise, veste))
    px[:, :, :3] = np.clip(res, 0, 1)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = out
    img.file_format = "JPEG"
    img.save(filepath=out, quality=88)
    bpy.data.images.remove(img)
    return bpy.data.images.load(out, check_existing=True)


def charger_px(path, taille=None):
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = "Non-Color"
    if taille and img.size[0] != taille:
        img.scale(taille, taille)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)


def normale_veste(src, out, taille):
    """Normale MakeHuman (plis cousus) + trame de toile du projet répétée 10 fois (mélange « UDN »)."""
    n1 = charger_px(src, taille)
    t = charger_px(os.path.join(TEX_PROJET, "veste_marc_nor_gl.jpg"))
    th, tw = t.shape[:2]
    yy = (np.arange(taille) * 10 * th // taille) % th
    xx = (np.arange(taille) * 10 * tw // taille) % tw
    n2 = t[yy][:, xx]
    a = n1[:, :, :3] * 2 - 1
    b = n2[:, :, :3] * 2 - 1
    r = np.dstack([a[:, :, 0] + b[:, :, 0] * 1.4, a[:, :, 1] + b[:, :, 1] * 1.4, a[:, :, 2]])
    r /= np.linalg.norm(r, axis=2, keepdims=True) + 1e-6
    n1[:, :, :3] = r * 0.5 + 0.5
    img = bpy.data.images.new("veste_nor", taille, taille, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(n1.ravel())
    img.filepath_raw = out
    img.file_format = "JPEG"
    img.save(filepath=out, quality=90)
    return img


def habiller_veste(ob, data_dir):
    import glob
    d = os.path.join(data_dir, "clothes", "male_casualsuit05")
    diff = veste_usee(glob.glob(os.path.join(d, "*_diffuse.png"))[0], os.path.join(TEX_TMP, "veste_diff.jpg"), 2048)
    nor = normale_veste(glob.glob(os.path.join(d, "*_normal.png"))[0], os.path.join(TEX_TMP, "veste_nor.jpg"), 2048)
    mat = G["make_mat"]("veste_marc", diff, nor, 0.9, nor_strength=1.3)
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def _sur_bras(w, segs):
    """Point le plus proche sur la ligne épaule → coude → poignet : (abscisse depuis l'épaule, point, axe)."""
    meilleur = None
    cumul = 0.0
    for p0, p1 in segs:
        ax = p1 - p0
        L = ax.length
        u = max(0.0, min(L, (w - p0).dot(ax / L)))
        q = p0 + ax / L * u
        dd = (w - q).length
        if meilleur is None or dd < meilleur[0]:
            meilleur = (dd, cumul + u, q, ax / L)
        cumul += L
    return meilleur


# rayon voulu de la manche (m) le long du bras, abscisse relative (0 = épaule, 1 = poignet) :
# bras 6,2 cm, coude 5,2 cm, avant-bras 4,6 cm, poignet 4 cm (avant-bras d'homme ≈ 28 cm de tour + tissu)
PROFIL_MANCHE = ((0.25, 0.062), (0.5, 0.055), (0.62, 0.052), (0.8, 0.046), (1.0, 0.04))


def _profil(x):
    if x <= PROFIL_MANCHE[0][0]:
        return PROFIL_MANCHE[0][1]
    for (x0, r0), (x1, r1) in zip(PROFIL_MANCHE, PROFIL_MANCHE[1:]):
        if x <= x1:
            return r0 + (r1 - r0) * (x - x0) / (x1 - x0)
    return PROFIL_MANCHE[-1][1]


def resserrer_manches(veste, rig):
    """Manches de veste amincies à la forme d'un avant-bras (la veste MakeHuman est un costume ample :
    deux gros cylindres en bas de l'image), raccourcies de 3,5 cm au poignet (la manchette du gant dépasse),
    avec plis : accordéon au poignet, plis de flexion au creux du coude, ondulations légères ailleurs.
    Les manches sont d'abord subdivisées une fois (plis ronds)."""
    mw = rig.matrix_world
    mwi = veste.matrix_world.inverted()
    bras = {}
    for c in "lr":
        e = mw @ rig.data.bones["upperarm_" + c].head_local
        k = mw @ rig.data.bones["lowerarm_" + c].head_local
        p = mw @ rig.data.bones["hand_" + c].head_local
        bras[c] = ([(e, k), (k, p)], (k - e).length + (p - k).length, (k - e).length, e)
    # 1. subdivision des faces de manche (au-delà de l'aisselle)
    bm = bmesh.new()
    bm.from_mesh(veste.data)

    def classe(w):
        for c, (segs, long, lu, e) in bras.items():
            if (w.x - e.x) * (1 if e.x > 0 else -1) < 0.02:
                continue
            m = _sur_bras(w, segs)
            if m[0] < 0.16 and m[1] > lu * 0.3:
                return c, m
        return None, None
    sel = [ed for ed in bm.edges if all(classe(veste.matrix_world @ v.co)[0] for v in ed.verts)]
    bmesh.ops.subdivide_edges(bm, edges=sel, cuts=1, use_grid_fill=True, smooth=0.6)
    bm.to_mesh(veste.data)
    bm.free()
    # 2. classement des sommets par bras et par tranche
    info = {}
    for v in veste.data.vertices:
        w = veste.matrix_world @ v.co
        c, m = classe(w)
        if c:
            info[v.index] = (c, w, m)
    tranches = {}
    for i, (c, w, m) in info.items():
        tranches.setdefault((c, int(m[1] / 0.02)), []).append(i)
    centre = {}
    rmax = {}
    for key, ids in tranches.items():
        cen = sum((info[i][1] for i in ids), Vector()) / len(ids)
        ax = info[ids[0]][2][3]
        rs = sorted(((info[i][1] - cen) - ax * (info[i][1] - cen).dot(ax)).length for i in ids)
        centre[key] = cen
        rmax[key] = rs[int(len(rs) * 0.9)] if rs else 0.05
    # 3. amincissement, plis, raccourcissement
    for i, (c, w, m) in info.items():
        segs, long, lu, e = bras[c]
        key = (c, int(m[1] / 0.02))
        x = m[1] / long
        ax = m[3]
        cen = centre[key]
        r = (w - cen) - ax * (w - cen).dot(ax)
        rl = r.length
        if rl < 1e-5:
            continue
        f = min(1.0, _profil(x) / max(rmax[key], 1e-4))
        # transition douce depuis l'aisselle (le haut du bras garde la forme de la veste)
        t_h = max(0.0, min(1.0, (m[1] - lu * 0.3) / (lu * 0.35)))
        f = 1.0 + (f - 1.0) * t_h
        # angle autour du bras (0 = dessus) pour orienter les plis
        haut = Vector((0, 0, 1)) - ax * ax.z
        haut = haut.normalized() if haut.length > 1e-4 else Vector((1, 0, 0))
        cote = ax.cross(haut)
        th = math.atan2(r.dot(cote), r.dot(haut))
        ph = 1.7 if c == "r" else 4.1
        d_coude = (m[1] - lu) / 0.06
        pli = 0.012 * math.sin(m[1] / 0.055 * math.tau + 2.2 * math.sin(th + ph))
        # creux du coude (dessous / intérieur) : plis de flexion marqués
        pli += 0.06 * math.exp(-d_coude * d_coude) * max(0.0, -math.cos(th)) * math.sin(m[1] / 0.022 * math.tau + th)
        # poignet : manche tassée en accordéon sur 7 cm
        acc = max(0.0, min(1.0, (m[1] - (long - 0.07)) / 0.07))
        pli += 0.05 * acc * math.sin(m[1] / 0.018 * math.tau + 1.5 * math.sin(2.0 * th + ph))
        nr = r * (f * (1.0 + pli))
        # raccourcie : les 8 derniers centimètres reculent jusqu'à 3,5 cm (manchette du gant visible)
        recul = 0.035 * max(0.0, min(1.0, (m[1] - (long - 0.08)) / 0.08))
        nw = cen + ax * (w - cen).dot(ax) + nr - ax * recul
        veste.data.vertices[i].co = mwi @ nw
    log("manches amincies avec plis :", len(info), "sommets")


# ---------------------------------------------------------------- gants

def gants(body, rig):
    """Coquille des deux mains taillée dans la peau : faces des mains et du poignet, lissée (plus d'ongles),
    décollée de 1,3 mm, épaisse de 0,8 mm. Les faces de peau recouvertes sont retirées du corps."""
    bones = {b.name for b in rig.data.bones}
    dom = G["dominant_groups"](body, bones)
    mw = rig.matrix_world
    poignets = [mw @ rig.data.bones["hand_" + c].head_local for c in "lr"]
    coudes = [mw @ rig.data.bones["lowerarm_" + c].head_local for c in "lr"]

    def poids(i, v):
        w = body.matrix_world @ v.co
        if dom[i].startswith(MAINS):
            return 1
        # manchette : 5 cm d'avant-bras au-dessus du poignet
        for p, c in zip(poignets, coudes):
            axe = (p - c).normalized()
            if -0.055 < (w - p).dot(axe) < 0.0 and (w - p).length < 0.08:
                return 2
        return 0
    zone = [poids(i, v) for i, v in enumerate(body.data.vertices)]
    sh = body.copy()
    sh.data = body.data.copy()
    sh.name = "Gants"
    bpy.context.collection.objects.link(sh)
    bm = bmesh.new()
    bm.from_mesh(sh.data)
    bm.verts.ensure_lookup_table()
    orig = bm.verts.layers.int.new("orig")
    for v in bm.verts:
        v[orig] = v.index
    src = bmesh.new()
    src.from_mesh(body.data)
    src.transform(body.matrix_world)
    src.normal_update()
    tree = BVHTree.FromBMesh(src)
    kill = [f for f in bm.faces if sum(1 for v in f.verts if zone[v[orig]]) < 3]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    inner = [v for v in bm.verts if not v.is_boundary]
    for _ in range(2):
        bmesh.ops.smooth_vert(bm, verts=inner, factor=0.35, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    mwi = body.matrix_world.inverted()
    for v in bm.verts:
        wco = body.matrix_world @ v.co
        loc, nor, _, _ = tree.find_nearest(wco)
        if loc is None:
            continue
        man = zone[v[orig]] == 2
        off = 0.0032 if man else 0.0013
        d = (wco - loc).dot(nor)
        if d < off:
            v.co = mwi @ (wco + nor * (off - d))
    # manchette : le bord ouvert du gant (au poignet) est prolongé de 5 cm sur l'avant-bras, un peu évasé
    # (la peau de l'avant-bras, cachée par la manche, a déjà été retirée : on ne peut pas la tailler dedans)
    dl = bm.verts.layers.deform.verify()
    for c, p, e in zip("lr", poignets, coudes):
        axe = (p - e).normalized()
        bord = [ed for ed in bm.edges if ed.is_boundary
                and (body.matrix_world @ ed.verts[0].co - p).length < 0.09
                and (body.matrix_world @ ed.verts[0].co - p).dot(axe) < 0.04]
        if not bord:
            continue
        vb = {v for ed in bord for v in ed.verts}
        centre = sum((body.matrix_world @ v.co for v in vb), Vector()) / len(vb)
        base = {v: body.matrix_world @ v.co for v in vb}
        g_bras = sh.vertex_groups["lowerarm_" + c].index
        g_main = sh.vertex_groups["hand_" + c].index
        prev, prev_set = bord, vb
        for k, (recul, evase) in enumerate(((0.01, 0.001), (0.025, 0.002), (0.045, 0.0026))):
            r = bmesh.ops.extrude_edge_only(bm, edges=prev)
            nv = [x for x in r["geom"] if isinstance(x, bmesh.types.BMVert)]
            ne = [x for x in r["geom"] if isinstance(x, bmesh.types.BMEdge)]
            nb = {}
            for v in nv:
                s0 = next((ed.other_vert(v) for ed in v.link_edges if ed.other_vert(v) in prev_set), None)
                if s0 is None:
                    continue
                w0 = base[s0]
                base_v = w0
                rad = (w0 - centre) - axe * (w0 - centre).dot(axe)
                rad = rad.normalized() if rad.length > 1e-5 else Vector()
                w = w0 - axe * recul + rad * evase
                v.co = mwi @ w
                nb[v] = base_v
                dv = v[dl]
                dv.clear()
                if k == 0:
                    dv[g_main] = 0.5
                    dv[g_bras] = 0.5
                else:
                    dv[g_bras] = 1.0
            prev = [ed for ed in ne if all(v in nb for v in ed.verts)]
            prev_set = set(nb)
            base.update(nb)          # chaque anneau garde la position d'origine du bord (reculs non cumulés)
    bm.normal_update()
    bm.verts.layers.int.remove(orig)
    bm.to_mesh(sh.data)
    bm.free()
    src.free()
    sol = sh.modifiers.new("epaisseur", "SOLIDIFY")
    sol.thickness = 0.0008
    sol.offset = -1.0
    bpy.context.view_layer.objects.active = sh
    bpy.ops.object.select_all(action="DESELECT")
    sh.select_set(True)
    bpy.ops.object.modifier_apply(modifier="epaisseur")
    for p in sh.data.polygons:
        p.use_smooth = True
    # peau de la main retirée (cachée sous le gant)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    kill = [f for f in bm.faces if all(zone[v.index] == 1 for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(body.data)
    bm.free()
    log("gants", len(sh.data.vertices), "sommets ;", len(kill), "faces de peau retirées")
    return sh


def attribut_gant(sh, rig):
    """Attribut « masque » par sommet pour la cuisson : R couture (flancs des doigts), G pli d'articulation,
    B manchette (poignet élastique / scratch)."""
    me = sh.data
    bones = {b.name for b in rig.data.bones}
    dom = G["dominant_groups"](sh, bones)
    mw = rig.matrix_world
    tetes = {b.name: mw @ b.head_local for b in rig.data.bones}
    mains = {c: mw.to_3x3() @ rig.data.bones["hand_" + c].matrix_local.to_3x3() for c in "lr"}
    if "masque" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["masque"])
    a = me.color_attributes.new("masque", "FLOAT_COLOR", "POINT")
    comptes = [0, 0, 0]
    for v in me.vertices:
        g = dom[v.index]
        w = sh.matrix_world @ v.co
        n = (sh.matrix_world.to_3x3() @ v.normal).normalized()
        r = gg = b = 0.0
        if g.startswith(MAINS) and not g.startswith("hand_"):
            c = g[-1]
            # dos de la main : axe local de l'os de la main (convention MakeHuman : Z vers le dos ?) -> on
            # prend la normale moyenne du dos via l'axe X de l'os (direction de la paume variable) : la couture
            # court là où la normale est perpendiculaire au plan de la paume
            pal = (mains[c] @ Vector((0, 0, 1))).normalized()
            r = max(0.0, 1.0 - abs(n.dot(pal)) / 0.18) if not g.startswith("thumb_") else 0.0
            # pli : près de la tête de l'os de phalange (articulation)
            bo = rig.data.bones[g]
            dr = (mw.to_3x3() @ (bo.tail_local - bo.head_local)).normalized()
            gg = max(0.0, 1.0 - abs((w - tetes[g]).dot(dr)) / 0.005)
        # manchette : tout ce qui est en arrière du poignet (bord ouvert compris)
        c = "l" if (w - tetes["hand_l"]).length < (w - tetes["hand_r"]).length else "r"
        axe = (tetes["hand_" + c] - tetes["lowerarm_" + c]).normalized()
        if not g.startswith(MAINS) or (w - tetes["hand_" + c]).dot(axe) < 0.012:
            b = 1.0
            r = gg = 0.0
        a.data[v.index].color = (r, gg, b, 1.0)
        comptes[0] += r > 0.5
        comptes[1] += gg > 0.5
        comptes[2] += b > 0.5
    log("masque des gants : couture", comptes[0], "pli", comptes[1], "manchette", comptes[2], "sur", len(me.vertices))


def cuire_gants(sh):
    """Cuisson Cycles des gants (UV propres) : cuir noir à grain (texture du projet), coutures, plis,
    usure claire des arêtes (phalanges, bout des doigts), poignet en toile."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16
    bpy.context.view_layer.objects.active = sh
    bpy.ops.object.select_all(action="DESELECT")
    sh.select_set(True)
    uv = sh.data.uv_layers.new(name="gant")
    sh.data.uv_layers.active = uv
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    for l in list(sh.data.uv_layers):
        if l.name != "gant":
            sh.data.uv_layers.remove(l)
    m = bpy.data.materials.new("gants_proc")
    m.use_nodes = True
    nt = m.node_tree
    L = nt.links
    N = G["noeud"] if "noeud" in G else None

    def nd(t, **kw):
        n = nt.nodes.new(t)
        for k, v in kw.items():
            if k in n.inputs:
                n.inputs[k].default_value = v
            else:
                setattr(n, k, v)
        return n
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    tc = nd("ShaderNodeTexCoord")
    geo = nd("ShaderNodeNewGeometry")
    att = nd("ShaderNodeAttribute", attribute_name="masque")
    sep = nd("ShaderNodeSeparateColor")
    L.new(att.outputs["Color"], sep.inputs["Color"])
    # grain du cuir : texture du projet en projection boîte (coordonnées objet)
    mp = nd("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (9.0, 9.0, 9.0)
    L.new(tc.outputs["Object"], mp.inputs["Vector"])
    imd = bpy.data.images.load(os.path.join(TEX_PROJET, "gants_cuir_diff.jpg"), check_existing=True)
    tx = nd("ShaderNodeTexImage", projection="BOX", projection_blend=0.3)
    tx.image = imd
    L.new(mp.outputs["Vector"], tx.inputs["Vector"])
    lum = nd("ShaderNodeRGBToBW")
    L.new(tx.outputs["Color"], lum.inputs["Color"])
    # arêtes (usure claire et lisse)
    bev = nd("ShaderNodeBevel", samples=8)
    bev.inputs["Radius"].default_value = 0.003
    dot = nd("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    L.new(bev.outputs["Normal"], dot.inputs[0])
    L.new(geo.outputs["Normal"], dot.inputs[1])
    ar = nd("ShaderNodeMapRange", clamp=True)
    ar.inputs["From Min"].default_value = 0.985
    ar.inputs["From Max"].default_value = 0.88
    L.new(dot.outputs["Value"], ar.inputs["Value"])
    nz = nd("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 260.0
    nz.inputs["Detail"].default_value = 6.0
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    nk = nd("ShaderNodeMapRange", clamp=True)
    nk.inputs["From Min"].default_value = 0.4
    nk.inputs["From Max"].default_value = 0.62
    L.new(nz.outputs["Fac"], nk.inputs["Value"])
    us0 = nd("ShaderNodeMath", operation="MULTIPLY", use_clamp=True)
    L.new(ar.outputs["Result"], us0.inputs[0])
    L.new(nk.outputs["Result"], us0.inputs[1])
    inv_b = nd("ShaderNodeMath", operation="SUBTRACT", use_clamp=True)   # pas d'usure sur la manchette
    inv_b.inputs[0].default_value = 1.0
    L.new(sep.outputs["Blue"], inv_b.inputs[1])
    us = nd("ShaderNodeMath", operation="MULTIPLY", use_clamp=True)
    L.new(us0.outputs[0], us.inputs[0])
    L.new(inv_b.outputs[0], us.inputs[1])
    # couleur : noir chaud, usure brun-gris, couture plus sombre, poignet en toile gris foncé
    c0 = nd("ShaderNodeMapRange")
    c0.inputs["To Min"].default_value = 0.012
    c0.inputs["To Max"].default_value = 0.04
    L.new(lum.outputs["Val"], c0.inputs["Value"])
    base = nd("ShaderNodeCombineColor")
    for i, k in enumerate((1.0, 0.93, 0.85)):
        mm = nd("ShaderNodeMath", operation="MULTIPLY")
        L.new(c0.outputs["Result"], mm.inputs[0])
        mm.inputs[1].default_value = k
        L.new(mm.outputs[0], base.inputs[i])
    mx1 = nd("ShaderNodeMix", data_type="RGBA")
    mx1.inputs["B"].default_value = (0.11, 0.095, 0.08, 1)
    L.new(us.outputs[0], mx1.inputs["Factor"])
    L.new(base.outputs["Color"], mx1.inputs["A"])
    cou = nd("ShaderNodeMapRange", clamp=True)
    cou.inputs["From Min"].default_value = 0.55
    cou.inputs["From Max"].default_value = 0.8
    L.new(sep.outputs["Red"], cou.inputs["Value"])
    mx2 = nd("ShaderNodeMix", data_type="RGBA")
    mx2.inputs["B"].default_value = (0.004, 0.004, 0.004, 1)
    L.new(cou.outputs["Result"], mx2.inputs["Factor"])
    L.new(mx1.outputs["Result"], mx2.inputs["A"])
    mx3 = nd("ShaderNodeMix", data_type="RGBA")
    mx3.inputs["B"].default_value = (0.018, 0.018, 0.017, 1)
    L.new(sep.outputs["Blue"], mx3.inputs["Factor"])
    L.new(mx2.outputs["Result"], mx3.inputs["A"])
    couleur = mx3.outputs["Result"]
    # rugosité : cuir 0,55, usure 0,35, toile 0,9
    r0 = nd("ShaderNodeMapRange", clamp=True)
    r0.inputs["To Min"].default_value = 0.6
    r0.inputs["To Max"].default_value = 0.38
    L.new(us.outputs[0], r0.inputs["Value"])
    r1 = nd("ShaderNodeMix", data_type="FLOAT")
    r1.inputs["B"].default_value = 0.92
    L.new(sep.outputs["Blue"], r1.inputs["Factor"])
    L.new(r0.outputs["Result"], r1.inputs["A"])
    rg = nd("ShaderNodeMath", operation="MULTIPLY_ADD", use_clamp=True)
    L.new(lum.outputs["Val"], rg.inputs[0])
    rg.inputs[1].default_value = 0.25
    L.new(r1.outputs["Result"], rg.inputs[2])
    rugosite = rg.outputs[0]
    # relief : grain + couture (sillon et points de piqûre) + plis aux articulations (rides)
    pli = nd("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
    pli.inputs["Scale"].default_value = 900.0
    pli.inputs["Distortion"].default_value = 4.0
    pli.inputs["Detail"].default_value = 2.0
    L.new(tc.outputs["Object"], pli.inputs["Vector"])
    plim = nd("ShaderNodeMath", operation="MULTIPLY")
    L.new(pli.outputs["Fac"], plim.inputs[0])
    L.new(sep.outputs["Green"], plim.inputs[1])
    piq = nd("ShaderNodeTexWave", wave_type="RINGS")
    piq.inputs["Scale"].default_value = 2600.0
    L.new(tc.outputs["Object"], piq.inputs["Vector"])
    piqm = nd("ShaderNodeMath", operation="MULTIPLY")
    L.new(piq.outputs["Fac"], piqm.inputs[0])
    L.new(cou.outputs["Result"], piqm.inputs[1])
    toile = nd("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Z")
    toile.inputs["Scale"].default_value = 1600.0
    L.new(tc.outputs["Object"], toile.inputs["Vector"])
    toim = nd("ShaderNodeMath", operation="MULTIPLY")
    L.new(toile.outputs["Fac"], toim.inputs[0])
    L.new(sep.outputs["Blue"], toim.inputs[1])
    h1 = nd("ShaderNodeMath", operation="MULTIPLY_ADD")
    L.new(cou.outputs["Result"], h1.inputs[0])
    h1.inputs[1].default_value = -0.6
    L.new(lum.outputs["Val"], h1.inputs[2])
    h2 = nd("ShaderNodeMath", operation="MULTIPLY_ADD")
    L.new(plim.outputs[0], h2.inputs[0])
    h2.inputs[1].default_value = 0.9
    L.new(h1.outputs[0], h2.inputs[2])
    h3 = nd("ShaderNodeMath", operation="MULTIPLY_ADD")
    L.new(piqm.outputs[0], h3.inputs[0])
    h3.inputs[1].default_value = 0.3
    L.new(h2.outputs[0], h3.inputs[2])
    h4 = nd("ShaderNodeMath", operation="MULTIPLY_ADD")
    L.new(toim.outputs[0], h4.inputs[0])
    h4.inputs[1].default_value = 0.5
    L.new(h3.outputs[0], h4.inputs[2])
    bump = nd("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.7
    bump.inputs["Distance"].default_value = 0.0006
    L.new(h4.outputs[0], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    L.new(couleur, bsdf.inputs["Base Color"])
    em = nd("ShaderNodeEmission")
    sh.data.materials.clear()
    sh.data.materials.append(m)
    imgs = {}
    os.makedirs(TEX_TMP, exist_ok=True)
    for canal in ("couleur", "rugosite", "relief"):
        img = bpy.data.images.new("gants_" + canal, 1024, 1024, alpha=False)
        if canal != "couleur":
            img.colorspace_settings.name = "Non-Color"
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        for n in nt.nodes:
            n.select = False
        tn.select = True
        nt.nodes.active = tn
        if canal == "relief":
            L.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=4)
        else:
            L.new(couleur if canal == "couleur" else rugosite, em.inputs["Color"])
            L.new(em.outputs["Emission"], out.inputs["Surface"])
            bpy.ops.object.bake(type="EMIT", margin=4)
        p = os.path.join(TEX_TMP, "gants_%s.png" % canal)
        img.filepath_raw = p
        img.file_format = "PNG"
        img.save()
        nt.nodes.remove(tn)
        imgs[canal] = img
    f = bpy.data.materials.new("gants")
    f.use_nodes = True
    ft = f.node_tree
    b = next(n for n in ft.nodes if n.type == "BSDF_PRINCIPLED")
    t1 = ft.nodes.new("ShaderNodeTexImage")
    t1.image = imgs["couleur"]
    ft.links.new(t1.outputs["Color"], b.inputs["Base Color"])
    t2 = ft.nodes.new("ShaderNodeTexImage")
    t2.image = imgs["rugosite"]
    ft.links.new(t2.outputs["Color"], b.inputs["Roughness"])
    t3 = ft.nodes.new("ShaderNodeTexImage")
    t3.image = imgs["relief"]
    nm = ft.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = 1.0
    ft.links.new(t3.outputs["Color"], nm.inputs["Color"])
    ft.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    sh.data.materials.clear()
    sh.data.materials.append(f)
    sh.data.color_attributes.remove(sh.data.color_attributes["masque"])
    log("gants cuits")


# ---------------------------------------------------------------- assemblage

def retirer_tete(body, rig):
    bones = {b.name for b in rig.data.bones}
    dom = G["dominant_groups"](body, bones)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    # tête et cou (caméra) ; bras et buste entièrement sous la veste (sinon la peau perce les manches)
    cache = ("head", "Head", "neck_01", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
             "clavicle_l", "clavicle_r", "spine_02", "spine_03")
    kill = [f for f in bm.faces if sum(1 for v in f.verts if dom[v.index] in cache) >= 2]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    log("tête, bras et buste (sous la veste) retirés :", len(kill), "faces")


def main():
    import glob
    bpy.ops.wm.read_factory_settings(use_empty=True)
    G["activer_mpfb"]()
    from bl_ext.user_default.mpfb.services import LocationService
    data_dir = LocationService.get_user_data()
    spec = MARC
    body, rig = G["creer_humain"](spec, None)
    meshes = G["preparer_maillages"](body, rig)
    G["masquer_peau"](body, meshes)
    G["habiller"](body, "skin", spec["peau"][0], spec["peau"][1], data_dir, "marc")
    for ob in list(meshes):
        if ob == body:
            continue
        low = ob.name.lower()
        if "low-poly" in low or "eyebrow" in low:
            bpy.data.objects.remove(ob, do_unlink=True)
            continue
        v = next((v for v in spec["vetements"] if os.path.splitext(v[0])[0] in ob.name), None)
        if v is None:
            bpy.data.objects.remove(ob, do_unlink=True)
            continue
        if v[1] == "veste":
            habiller_veste(ob, data_dir)
            ob.name = "Veste"
            resserrer_manches(ob, rig)
        else:
            G["habiller"](ob, "clothes", v[0], v[1], data_dir, "marc")
            ob.name = os.path.splitext(v[0])[0].replace("-", "_")
    body.name = "Corps"
    gt = gants(body, rig)
    retirer_tete(body, rig)
    attribut_gant(gt, rig)
    cuire_gants(gt)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]

    q, acts = G["import_ual"]()
    hinge = G["hinge_axes"](q, acts)
    C = G["correspondances"](q, rig, hinge)
    n = G["construire_squelette"](q, rig, C)
    new = G["bake_animations"](q, n, acts)
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
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = n
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_yup=True, export_skins=True, export_reset_pose_bones=True,
                              export_image_format="JPEG", export_jpeg_quality=88, export_vertex_color="NONE")
    log("EXPORT", OUT, os.path.getsize(OUT) // 1024, "ko,", len(new), "animations,", tris, "triangles")


main()

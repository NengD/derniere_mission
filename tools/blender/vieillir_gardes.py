"""Vieillissement des tenues et de la peau des gardes, et masques en tissu (bandana, cache-cou).

Appelé par build_gardes_mpfb.py. Tout est cuit par Cycles (en -b) dans les UV de chaque objet, pour
que le glTF n'emporte que trois images simples par matériau (couleur, rugosité, relief) :
- couleur : texture MakeHuman retouchée + trame du tissu (Poly Haven, CC0) + crasse dans les creux
  (occlusion), poussière vers le bas des jambes, taches grasses, sueur aux aisselles et au col,
  usure claire des arêtes, décoloration irrégulière ;
- relief : normal map d'origine + trame du tissu (hauteur Poly Haven) + plis (ondes déformées,
  plus nombreux aux coudes, genoux, taille) ;
- rugosité : tissu mat, taches plus brillantes, crasse plus mate ;
- peau : pores (cellules de Voronoï), grain fin, rougeurs et marbrures, zone T plus brillante.
"""
import math
import os

import bpy
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PH = os.path.join(ROOT, "_sources", "polyhaven")

# tissu Poly Haven (hauteur + couleur tuilées), période en mètres, force du relief, rugosité de base
TISSUS = {
    "jean": ("denim_fabric_04", 0.10, 0.8, 0.9),
    "coton": ("cotton_jersey", 0.07, 0.6, 0.92),
    "toile": ("hessian_230", 0.05, 0.5, 0.85),
    "cargo": ("denim_fabric_04", 0.13, 0.6, 0.9),
    "cuir": ("brown_leather", 0.16, 0.6, 0.55),
    "tricot": ("knitted_fleece", 0.08, 1.0, 0.95),
}


def genre(nom):
    n = nom.lower()
    for k, v in (("jeans", "jean"), ("cargo", "cargo"), ("vest", "toile"), ("cap", "toile"),
                 ("boots", "cuir"), ("sneakers", "cuir"), ("shoes", "cuir"), ("hood", "tricot"),
                 ("bandana", "coton"), ("cache", "tricot"), ("shirt", "coton"), ("tee", "coton"),
                 ("polo", "coton")):
        if k in n:
            return v
    return "coton"


def _ph(tissu, canal):
    return os.path.join(PH, tissu, "%s_%s_1k.jpg" % (tissu, canal))


def densite(ob):
    """Mètres par unité d'UV (moyenne de l'objet)."""
    me = ob.data
    uv = me.uv_layers.active.data
    a3 = auv = 0.0
    for p in me.polygons:
        a3 += p.area
        co = [uv[i].uv for i in p.loop_indices]
        s = 0.0
        for k in range(1, len(co) - 1):
            e1, e2 = co[k] - co[0], co[k + 1] - co[0]
            s += abs(e1.x * e2.y - e1.y * e2.x) / 2
        auv += s
    return math.sqrt(a3 / max(auv, 1e-9))


class Noeuds:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.L = self.nt.links

    def n(self, t, **kw):
        nd = self.nt.nodes.new(t)
        for k, v in kw.items():
            if k in nd.inputs:
                nd.inputs[k].default_value = v
            else:
                setattr(nd, k, v)
        return nd

    def lien(self, a, b):
        self.L.new(a, b)

    def math(self, op, a, b=None, c=None, clamp=False):
        m = self.n("ShaderNodeMath", operation=op)
        m.use_clamp = clamp
        for i, x in enumerate((a, b, c)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                m.inputs[i].default_value = x
            else:
                self.lien(x, m.inputs[i])
        return m.outputs[0]

    def mix(self, a, b, fac, mode="MIX"):
        m = self.n("ShaderNodeMix", data_type="RGBA", blend_type=mode)
        for sock, x in ((m.inputs[0], fac), (m.inputs[6], a), (m.inputs[7], b)):
            if isinstance(x, (int, float)):
                sock.default_value = x
            elif isinstance(x, tuple):
                sock.default_value = x
            else:
                self.lien(x, sock)
        return m.outputs[2]

    def bruit(self, vec, scale, detail=4.0, rough=0.55, dist=0.0):
        t = self.n("ShaderNodeTexNoise", noise_dimensions="3D")
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = rough
        t.inputs["Distortion"].default_value = dist
        self.lien(vec, t.inputs["Vector"])
        return t.outputs["Fac"]

    def rampe(self, x, a, b):
        """smoothstep(a, b, x)"""
        m = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        m.inputs["From Min"].default_value = a
        m.inputs["From Max"].default_value = b
        self.lien(x, m.inputs["Value"])
        return m.outputs["Result"]

    def image(self, img, vec=None, non_color=False):
        t = self.n("ShaderNodeTexImage")
        t.image = img
        if vec is not None:
            self.lien(vec, t.inputs["Vector"])
        return t


def _charger(path, non_color=False):
    im = bpy.data.images.load(path, check_existing=True)
    if non_color:
        im.colorspace_settings.name = "Non-Color"
    return im


def preparer_cycles(samples=12):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.render.bake.margin = 6
    sc.render.bake.use_clear = True
    try:
        sc.cycles.use_denoising = False
    except Exception:
        pass


def _cuire(ob, nt, sortie, canal, img, type_bake, samples):
    sc = bpy.context.scene
    sc.cycles.samples = samples
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = img
    for n in nt.nodes:
        n.select = False
    tn.select = True
    nt.nodes.active = tn
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    if type_bake == "NORMAL":
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
    else:
        bpy.ops.object.bake(type="EMIT")
    nt.nodes.remove(tn)


def _sauver(img, path, qualite=86):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.filepath_raw = path
    img.file_format = "JPEG"
    try:
        img.save(filepath=path, quality=qualite)
    except TypeError:
        img.save()
    nc = img.colorspace_settings.name == "Non-Color"
    bpy.data.images.remove(img)
    return _charger(path, nc)


def cuire_vetement(ob, diff, nor, tex_dir, tag, taille=2048, couleur=None, salete=1.0, rough=None,
                   sueur=0.0, poussiere_bas=1.0, plis=1.0):
    """Cuit couleur / relief / rugosité d'un vêtement ; remplace son matériau. « diff » : image de base
    (ou None et « couleur » (r, g, b) unie) ; « nor » : normal map d'origine (ou None)."""
    g = genre(ob.name)
    tissu, periode, f_relief, r0 = TISSUS[g]
    if rough is not None:
        r0 = rough
    ech = densite(ob) / periode
    m = bpy.data.materials.new("cuisson_" + ob.name)
    m.use_nodes = True
    N = Noeuds(m)
    nt = N.nt
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = N.n("ShaderNodeOutputMaterial")
    bsdf = N.n("ShaderNodeBsdfPrincipled")
    tc = N.n("ShaderNodeTexCoord")
    obj = tc.outputs["Object"]
    mp = N.n("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (ech, ech, 1)
    N.lien(tc.outputs["UV"], mp.inputs["Vector"])
    tuile = mp.outputs["Vector"]
    # couleur de base
    if diff is not None:
        base = N.image(diff, tc.outputs["UV"]).outputs["Color"]
    else:
        rgb = N.n("ShaderNodeRGB")
        rgb.outputs[0].default_value = tuple(couleur) + (1.0,)
        base = rgb.outputs[0]
    # trame du tissu : luminance de la couleur Poly Haven, centrée
    tcol = N.image(_charger(_ph(tissu, "diff")), tuile)
    bw = N.n("ShaderNodeRGBToBW")
    N.lien(tcol.outputs["Color"], bw.inputs["Color"])
    trame = N.math("MULTIPLY_ADD", bw.outputs["Val"], 0.9, 0.62)        # ~1 en moyenne
    c = N.mix(base, trame, 1.0, "MULTIPLY") if False else None
    tr_rgb = N.n("ShaderNodeCombineColor")
    for i in range(3):
        N.lien(trame, tr_rgb.inputs[i])
    c = N.mix(base, tr_rgb.outputs[0], 0.55 if diff is not None else 0.9, "MULTIPLY")
    # décoloration irrégulière (soleil, lavages)
    fade = N.bruit(obj, 2.2, 3.0)
    fade_m = N.rampe(fade, 0.45, 0.75)
    c = N.mix(c, (0.55, 0.53, 0.5, 1.0), N.math("MULTIPLY", fade_m, 0.07), "SCREEN")
    # occlusion : crasse dans les creux et les plis
    ao = N.n("ShaderNodeAmbientOcclusion", only_local=False)
    ao.inputs["Distance"].default_value = 0.06
    ao.samples = 8
    creux = N.math("SUBTRACT", 1.0, ao.outputs["AO"], clamp=True)
    sale = (0.10, 0.085, 0.065, 1.0)
    c = N.mix(c, sale, N.math("MULTIPLY", N.rampe(creux, 0.15, 0.85), 0.55 * salete), "MULTIPLY")
    # poussière / boue vers le bas des jambes (z objet en mètres, pieds à 0)
    sep = N.n("ShaderNodeSeparateXYZ")
    N.lien(obj, sep.inputs["Vector"])
    bas = N.rampe(N.math("SUBTRACT", 0.0, sep.outputs["Z"]), -0.62, -0.12)
    nd = N.bruit(obj, 9.0, 6.0, 0.6)
    pous = N.math("MULTIPLY", N.rampe(nd, 0.38, 0.62), bas)
    c = N.mix(c, (0.2, 0.17, 0.13, 1.0), N.math("MULTIPLY", pous, 0.4 * salete * poussiere_bas))
    # salissures générales en nuages
    n2 = N.bruit(obj, 5.0, 8.0, 0.65)
    nuage = N.rampe(n2, 0.5, 0.75)
    c = N.mix(c, sale, N.math("MULTIPLY", nuage, 0.35 * salete))
    # taches grasses sombres (petites, rares)
    n3 = N.bruit(obj, 16.0, 3.0, 0.5, 0.4)
    tache = N.rampe(n3, 0.68, 0.74)
    c = N.mix(c, (0.05, 0.045, 0.035, 1.0), N.math("MULTIPLY", tache, 0.6 * salete))
    # sueur : auréoles sous les bras / au col (vêtements du haut)
    if sueur > 0:
        x_abs = N.math("ABSOLUTE", sep.outputs["X"])
        aisselle = N.math("MULTIPLY", N.rampe(x_abs, 0.09, 0.15), N.rampe(x_abs, 0.24, 0.18))
        hz = N.math("MULTIPLY", N.rampe(sep.outputs["Z"], 1.18, 1.26), N.rampe(sep.outputs["Z"], 1.42, 1.34))
        aur = N.math("MULTIPLY", N.math("MULTIPLY", aisselle, hz), N.rampe(N.bruit(obj, 14.0, 4.0), 0.35, 0.6))
        c = N.mix(c, (0.42, 0.38, 0.3, 1.0), N.math("MULTIPLY", aur, 0.45 * sueur), "MULTIPLY")
    # usure claire des arêtes (coutures, bords, plis saillants)
    geo = N.n("ShaderNodeNewGeometry")
    arete = N.rampe(geo.outputs["Pointiness"], 0.53, 0.62)
    usure = N.math("MULTIPLY", arete, N.rampe(N.bruit(obj, 30.0, 4.0), 0.4, 0.7))
    c = N.mix(c, (0.5, 0.48, 0.45, 1.0), N.math("MULTIPLY", usure, 0.22), "SCREEN")
    # ---------------------------------------------------------------- relief
    h_tr = N.image(_charger(_ph(tissu, "disp"), True), tuile)
    nrm = None
    if nor is not None:
        nm = N.n("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 1.0
        N.lien(N.image(nor, tc.outputs["UV"]).outputs["Color"], nm.inputs["Color"])
        nrm = nm.outputs["Normal"]
    b1 = N.n("ShaderNodeBump")
    b1.inputs["Strength"].default_value = 0.55 * f_relief
    b1.inputs["Distance"].default_value = 0.0015
    N.lien(h_tr.outputs["Color"], b1.inputs["Height"])
    if nrm is not None:
        N.lien(nrm, b1.inputs["Normal"])
    # plis : ondes horizontales déformées (manches, jambes), présentes par zones
    w = N.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Z", wave_profile="SIN")
    w.inputs["Scale"].default_value = 7.0
    w.inputs["Distortion"].default_value = 9.0
    w.inputs["Detail"].default_value = 3.0
    w.inputs["Detail Scale"].default_value = 1.5
    N.lien(obj, w.inputs["Vector"])
    zone = N.rampe(N.bruit(obj, 3.5, 2.0), 0.42, 0.62)
    pl = N.math("MULTIPLY", w.outputs["Fac"], zone)
    ond = N.bruit(obj, 11.0, 3.0, 0.5, 0.6)          # froissé doux
    hpl = N.math("MULTIPLY_ADD", ond, 0.5, pl)
    b2 = N.n("ShaderNodeBump")
    b2.inputs["Strength"].default_value = 0.45 * plis
    b2.inputs["Distance"].default_value = 0.004
    N.lien(hpl, b2.inputs["Height"])
    N.lien(b1.outputs["Normal"], b2.inputs["Normal"])
    # plis aussi assombris un peu dans la couleur (ombre portée cuite très légère)
    c = N.mix(c, (0.75, 0.75, 0.75, 1.0), N.math("MULTIPLY", N.math("SUBTRACT", 1.0, hpl, clamp=True), 0.18 * plis), "MULTIPLY")
    N.lien(b2.outputs["Normal"], bsdf.inputs["Normal"])
    # ---------------------------------------------------------------- rugosité
    r = N.math("MULTIPLY_ADD", N.bruit(obj, 20.0, 3.0), 0.12, r0 - 0.06)
    r = N.math("SUBTRACT", r, N.math("MULTIPLY", tache, 0.3))
    r = N.math("ADD", r, N.math("MULTIPLY", nuage, 0.05), clamp=True)
    em = N.n("ShaderNodeEmission")
    N.lien(c, bsdf.inputs["Base Color"])
    ob.data.materials.clear()
    ob.data.materials.append(m)
    res = {}
    for canal, tb, smp, sz in (("couleur", "EMIT", 10, taille), ("relief", "NORMAL", 2, taille),
                               ("rugosite", "EMIT", 1, max(512, taille // 2))):
        img = bpy.data.images.new("%s_%s" % (tag, canal), sz, sz, alpha=False)
        if canal != "couleur":
            img.colorspace_settings.name = "Non-Color"
        for l in list(out.inputs["Surface"].links):
            nt.links.remove(l)
        if canal == "relief":
            N.lien(bsdf.outputs["BSDF"], out.inputs["Surface"])
        else:
            for l in list(em.inputs["Color"].links):
                nt.links.remove(l)
            if canal == "couleur":
                N.lien(c, em.inputs["Color"])
            else:
                N.lien(r, em.inputs["Color"])
            N.lien(em.outputs["Emission"], out.inputs["Surface"])
        _cuire(ob, nt, out, canal, img, tb, smp)
        res[canal] = _sauver(img, os.path.join(tex_dir, "%s_%s.jpg" % (tag, canal)))
    return materiau_final(os.path.basename(tag), res)


def materiau_final(nom, res, alpha_img=None):
    f = bpy.data.materials.new(nom)
    f.use_nodes = True
    ft = f.node_tree
    b = next(n for n in ft.nodes if n.type == "BSDF_PRINCIPLED")
    t1 = ft.nodes.new("ShaderNodeTexImage")
    t1.image = res["couleur"]
    ft.links.new(t1.outputs["Color"], b.inputs["Base Color"])
    t2 = ft.nodes.new("ShaderNodeTexImage")
    t2.image = res["rugosite"]
    ft.links.new(t2.outputs["Color"], b.inputs["Roughness"])
    b.inputs["Metallic"].default_value = 0.0
    t3 = ft.nodes.new("ShaderNodeTexImage")
    t3.image = res["relief"]
    nm = ft.nodes.new("ShaderNodeNormalMap")
    ft.links.new(t3.outputs["Color"], nm.inputs["Color"])
    ft.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return f


def cuire_peau(ob, diff, tex_dir, tag, taille=2048, rides=0.5):
    """Peau : pores, grain, marbrures et rougeurs, brillance de la zone T ; cuite dans les UV MakeHuman."""
    m = bpy.data.materials.new("cuisson_peau")
    m.use_nodes = True
    N = Noeuds(m)
    nt = N.nt
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = N.n("ShaderNodeOutputMaterial")
    bsdf = N.n("ShaderNodeBsdfPrincipled")
    tc = N.n("ShaderNodeTexCoord")
    obj = tc.outputs["Object"]
    base = N.image(diff, tc.outputs["UV"]).outputs["Color"]
    # marbrures, rougeurs (joues, nez, jointures), teint inégal
    marb = N.bruit(obj, 28.0, 6.0, 0.6)
    c = N.mix(base, (0.55, 0.32, 0.28, 1.0), N.math("MULTIPLY", N.rampe(marb, 0.5, 0.8), 0.18), "MULTIPLY")
    tache = N.bruit(obj, 70.0, 3.0, 0.5)
    c = N.mix(c, (0.62, 0.5, 0.42, 1.0), N.math("MULTIPLY", N.rampe(tache, 0.62, 0.72), 0.25), "MULTIPLY")
    ao = N.n("ShaderNodeAmbientOcclusion", only_local=True)
    ao.inputs["Distance"].default_value = 0.02
    ao.samples = 8
    c = N.mix(c, (0.6, 0.45, 0.4, 1.0), N.math("MULTIPLY", N.math("SUBTRACT", 1.0, ao.outputs["AO"], clamp=True), 0.6), "MULTIPLY")
    # pores et grain
    vor = N.n("ShaderNodeTexVoronoi", feature="F1", distance="EUCLIDEAN")
    vor.inputs["Scale"].default_value = 650.0
    vor.inputs["Randomness"].default_value = 1.0
    N.lien(obj, vor.inputs["Vector"])
    pore = N.rampe(vor.outputs["Distance"], 0.0, 0.32)
    grain = N.bruit(obj, 260.0, 4.0, 0.6)
    h = N.math("MULTIPLY_ADD", grain, 0.35, pore)
    # rides fines (front, coin des yeux) : ondes horizontales légères
    w = N.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Z")
    w.inputs["Scale"].default_value = 45.0
    w.inputs["Distortion"].default_value = 6.0
    N.lien(obj, w.inputs["Vector"])
    h = N.math("MULTIPLY_ADD", w.outputs["Fac"], 0.25 * rides, h)
    bp = N.n("ShaderNodeBump")
    bp.inputs["Strength"].default_value = 0.35
    bp.inputs["Distance"].default_value = 0.0005
    N.lien(h, bp.inputs["Height"])
    N.lien(bp.outputs["Normal"], bsdf.inputs["Normal"])
    # rugosité : peau grasse (visage) plus brillante, pores plus mats
    sep = N.n("ShaderNodeSeparateXYZ")
    N.lien(obj, sep.inputs["Vector"])
    visage = N.rampe(sep.outputs["Z"], 1.5, 1.6)
    r = N.math("MULTIPLY_ADD", N.bruit(obj, 18.0, 3.0), 0.14, 0.5)
    r = N.math("SUBTRACT", r, N.math("MULTIPLY", visage, 0.12))
    r = N.math("ADD", r, N.math("MULTIPLY", pore, 0.08), clamp=True)
    em = N.n("ShaderNodeEmission")
    ob.data.materials.clear()
    ob.data.materials.append(m)
    res = {}
    for canal, tb, smp, sz in (("couleur", "EMIT", 6, taille), ("relief", "NORMAL", 2, taille),
                               ("rugosite", "EMIT", 1, taille // 2)):
        img = bpy.data.images.new("%s_%s" % (tag, canal), sz, sz, alpha=False)
        if canal != "couleur":
            img.colorspace_settings.name = "Non-Color"
        for l in list(out.inputs["Surface"].links):
            nt.links.remove(l)
        if canal == "relief":
            N.lien(bsdf.outputs["BSDF"], out.inputs["Surface"])
        else:
            for l in list(em.inputs["Color"].links):
                nt.links.remove(l)
            N.lien(c if canal == "couleur" else r, em.inputs["Color"])
            N.lien(em.outputs["Emission"], out.inputs["Surface"])
        _cuire(ob, nt, out, canal, img, tb, smp)
        res[canal] = _sauver(img, os.path.join(tex_dir, "%s_%s.jpg" % (tag, canal)))
    return materiau_final(os.path.basename(tag), res)


# ---------------------------------------------------------------- masques en tissu

def _enveloppe_haute(z, r):
    """Enveloppe convexe supérieure de la courbe r(z) (z croissant) : le tissu passe en pont sur les creux."""
    pts = list(zip(z, r))
    hull = []
    for p in pts:
        while len(hull) >= 2:
            (x1, y1), (x2, y2) = hull[-2], hull[-1]
            if (x2 - x1) * (p[1] - y1) - (y2 - y1) * (p[0] - x1) >= 0:   # virage à gauche : on retire
                hull.pop()
            else:
                break
        hull.append(p)
    hz = np.array([h[0] for h in hull])
    hr = np.array([h[1] for h in hull])
    return np.interp(z, hz, hr)


def _convexe_2d(th, r):
    """Rayon de l'enveloppe convexe (dans le plan) d'un contour polaire fermé r(θ)."""
    x, y = r * np.sin(th), -r * np.cos(th)
    pts = sorted(zip(x, y))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    hull = lo[:-1] + up[:-1]
    # rayon de l'enveloppe dans chaque direction θ (intersection rayon / polygone)
    out = np.array(r, dtype=float)
    for i, t in enumerate(th):
        d = np.array([math.sin(t), -math.cos(t)])
        best = 0.0
        for k in range(len(hull)):
            a = np.array(hull[k])
            b = np.array(hull[(k + 1) % len(hull)])
            e = b - a
            den = d[0] * (-e[1]) - d[1] * (-e[0])
            if abs(den) < 1e-12:
                continue
            s = (a[0] * (-e[1]) - a[1] * (-e[0])) / den
            u = (d[0] * a[1] - d[1] * a[0]) / den
            if s > 0 and -1e-6 <= u <= 1 + 1e-6:
                best = max(best, s)
        if best > 0:
            out[i] = max(out[i], best)
    return out


def masque_tissu(kind, body, obstacles, reperes, nom):
    """Bandana (triangle noué derrière la tête, pointe qui pend sous le menton) ou cache-cou (tube
    remonté sur le nez) : surface paramétrée autour de l'axe tête-cou, tendue en pont sur le nez, le
    menton et les creux (jamais moulée sur les lèvres), plis, épaisseur. Renvoie l'objet (sans poids)."""
    import bmesh
    ez, ey, chin_z, neck_z, cy_tete, cy_cou = (reperes[k] for k in ("yeux_z", "yeux_y", "menton_z", "cou_z", "tete_y", "cou_y"))
    # arbre de collision : peau + hauts (le tissu passe par-dessus le col)
    bm = bmesh.new()
    for o in [body] + obstacles:
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        tmp.transform(o.matrix_world)
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        tmp.free()
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    NT = 96
    th = np.linspace(-math.pi, math.pi, NT, endpoint=False)    # 0 = devant (-Y), > 0 vers +X (gauche du garde)
    ath = np.abs(th)

    def axe_y(z):
        t = min(1.0, max(0.0, (chin_z - z) / max(chin_z - neck_z, 0.02)))
        return cy_tete * (1 - t) + cy_cou * t

    if kind == "bandana":
        T_TRI, T_DOS = math.radians(70), math.radians(128)
        z_top = np.where(ath < T_TRI, ez - 0.024, ez - 0.024 + 0.02 * np.clip((ath - T_TRI) / (T_DOS - T_TRI), 0, 1))
        pointe = 0.17
        zb_av = chin_z - 0.012 - pointe * np.clip(1 - ath / T_TRI, 0, 1) ** 1.25
        zb_dos = z_top - 0.05
        f = np.clip((ath - T_TRI) / (T_DOS - T_TRI), 0, 1)
        f = f * f * (3 - 2 * f)
        z_bot = np.where(ath < T_TRI, zb_av, (chin_z - 0.012) * (1 - f) + zb_dos * f)
        NV = 40
    else:
        z_top = ez - 0.03 + 0.03 * (1 - np.cos(th)) / 2 * 0.8      # sous les yeux devant, plus haut derrière
        z_bot = np.full(NT, neck_z - 0.012) - 0.01 * (1 + np.cos(th)) / 2
        obstacles = []                 # le tube serre le cou : seule la peau compte
        NV = 44
    if kind == "cachecou":
        bm = bmesh.new()
        bm.from_mesh(body.data)
        bm.transform(body.matrix_world)
        tree = BVHTree.FromBMesh(bm)
        bm.free()
    v = np.linspace(0, 1, NV)
    Z = z_top[None, :] + (z_bot - z_top)[None, :] * v[:, None]       # (NV, NT)
    R = np.zeros_like(Z)
    for i in range(NV):
        for j in range(NT):
            z = Z[i, j]
            c = Vector((0.0, axe_y(z), z))
            d = Vector((math.sin(th[j]), -math.cos(th[j]), 0.0))
            hit = tree.ray_cast(c + d * 0.35, -d, 0.35)
            R[i, j] = (0.35 - hit[3]) if hit[0] is not None else 0.05
    # pont sur les creux : enveloppe verticale par colonne (sur une grille z régulière commune), puis
    # enveloppe convexe dans chaque rangée ; deux passes
    zs = np.linspace(Z.min() - 0.001, Z.max() + 0.001, 90)
    for _ in range(2):
        for j in range(NT):
            zz, rr = Z[::-1, j], R[::-1, j]               # z croissant
            R[::-1, j] = _enveloppe_haute(zz, rr) if kind == "cachecou" or True else rr
        for i in range(NV):
            R[i] = _convexe_2d(th, R[i])
    if kind == "cachecou":
        # sous le menton, le tube serre le cou : jamais plus large que la mâchoire
        for j in range(NT):
            rc = np.interp(chin_z + 0.01, Z[::-1, j], R[::-1, j])
            sous = Z[:, j] < chin_z
            R[sous, j] = np.minimum(R[sous, j], rc + 0.006)
    # tissu détaché de la peau, plus lâche vers le bas ; bandana : rideau qui tombe sous le menton
    off = 0.004 + 0.006 * v[:, None]
    R = R + off
    if kind == "bandana":
        # sous le menton : le tissu tombe presque à la verticale depuis la ligne du menton
        for j in range(NT):
            rc = np.interp(chin_z, Z[::-1, j], R[::-1, j])
            sous = Z[:, j] < chin_z
            prof = chin_z - Z[:, j]
            R[sous, j] = np.maximum(R[sous, j], rc - 0.05 * prof[sous])
        # plis verticaux qui s'ouvrent vers la pointe, petites ondulations horizontales
        pend = np.clip((chin_z + 0.03 - Z) / 0.16, 0, 1) * (ath[None, :] < T_DOS)
        R += 0.008 * pend * np.sin(th[None, :] * 9 + 0.7) + 0.004 * pend * np.sin(th[None, :] * 21 + 2.1)
        # plis en éventail qui partent du nœud vers l'avant (tissu tiré par le nœud)
        tire = np.clip((ath[None, :] - 0.6) / 1.6, 0, 1) * (1 - np.clip((ath[None, :] - 2.4) / 0.4, 0, 1))
        R += 0.0035 * tire * np.sin(Z * 180 - ath[None, :] * 7)
        R += 0.0012 * np.sin(Z * 260 + th[None, :] * 3)
        # nœud derrière : léger renflement
        R += 0.008 * np.exp(-((ath[None, :] - math.pi) / 0.18) ** 2) * np.exp(-((v[:, None] - 0.5) / 0.3) ** 2)
    else:
        # bord supérieur roulé, plis horizontaux de tissu tassé sur le cou
        R += 0.003 * np.exp(-((v[:, None] - 0.03) / 0.05) ** 2)
        tasse = np.clip((v[:, None] - 0.35) / 0.65, 0, 1)
        R += 0.0035 * tasse * (0.5 + 0.5 * np.sin(Z * 210 + 1.3 * np.sin(th[None, :] * 3)))
        R += 0.0015 * np.sin(th[None, :] * 9) * tasse
    # maillage
    me = bpy.data.meshes.new(nom)
    verts = []
    for i in range(NV):
        for j in range(NT):
            z = Z[i, j]
            verts.append((R[i, j] * math.sin(th[j]), axe_y(z) - R[i, j] * math.cos(th[j]), z))
    faces = []
    for i in range(NV - 1):
        for j in range(NT):
            a, b = i * NT + j, i * NT + (j + 1) % NT
            faces.append((a, b, b + NT, a + NT))
    me.from_pydata(verts, [], faces)
    me.update()
    # UV : u = longueur d'arc (m), v = hauteur (m) ; normalisées à [0, 1] pour la cuisson
    uv = me.uv_layers.new(name="UVMap")
    circ = 2 * math.pi * float(np.mean(R))
    H = float(np.max(z_top - z_bot)) + 1e-3
    for p in me.polygons:
        for li in p.loop_indices:
            vi = me.loops[li].vertex_index
            i, j = divmod(vi, NT)
            jj = j
            if p.vertices[0] % NT == NT - 1 and j == 0:
                jj = NT                                     # couture : dernière colonne
            u = (jj / NT) * circ
            vv = (Z[0, j] - Z[i, j])
            s = max(circ, H)
            uv.data[li].uv = (u / s, 1 - vv / s)
    ob = bpy.data.objects.new(nom, me)
    bpy.context.collection.objects.link(ob)
    # normales vers l'extérieur
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        cf = f.calc_center_median()
        radial = Vector((cf.x, cf.y - axe_y(cf.z), 0))
        if f.normal.dot(radial) < 0:
            f.normal_flip()
    bm.to_mesh(me)
    bm.free()
    sol = ob.modifiers.new("epaisseur", "SOLIDIFY")
    sol.thickness = 0.0022
    sol.offset = -1.0
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="epaisseur")
    for p in me.polygons:
        p.use_smooth = True
    return ob, {"chin_z": chin_z}


def copier_poids(dst, body, ref_fn=None, k=4):
    """Poids de la peau la plus proche (pondérés par la distance). ref_fn(co) -> point de référence."""
    kd = KDTree(len(body.data.vertices))
    mw = body.matrix_world
    for v in body.data.vertices:
        kd.insert(mw @ v.co, v.index)
    kd.balance()
    names = {g.index: g.name for g in body.vertex_groups}
    groupes = {}
    for v in dst.data.vertices:
        p = dst.matrix_world @ v.co
        if ref_fn:
            p = ref_fn(p)
        acc = {}
        tot = 0.0
        for co, idx, dist in kd.find_n(p, k):
            w = 1.0 / max(dist, 1e-4)
            tot += w
            for g in body.data.vertices[idx].groups:
                acc[names[g.group]] = acc.get(names[g.group], 0.0) + g.weight * w
        for n, wt in acc.items():
            if wt / tot > 0.01:
                groupes.setdefault(n, []).append((v.index, wt / tot))
    for n, lst in groupes.items():
        vg = dst.vertex_groups.get(n) or dst.vertex_groups.new(name=n)
        for i, wt in lst:
            vg.add([i], wt, "REPLACE")

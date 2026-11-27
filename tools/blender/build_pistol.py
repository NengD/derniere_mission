"""Pistolet semi-automatique générique 9 × 19 (modelé de zéro, aucune marque réelle).

ANCIEN pistolet (remplacé dans le jeu par tools/blender/build_pistol_m9.py le 27/11/2026).
Usage : blender -b --factory-startup -P tools/blender/build_pistol.py [-- <sortie.glb>]
Sortie par défaut : _sources/pistolet_maison.glb (n'écrase plus assets/weapons/pistolet.glb) — origine = centre de la poignée (là où la main serre),
canon vers +Y dans Blender (donc vers -Z, l'avant, dans Godot).

Pièces séparées (nœuds du glb, animées par scripts/joueur/joueur.gd) :
- carcasse  : carcasse polymère (poignée granitée, pontet, rail, arrêtoir, bouton de chargeur, numéro de série)
- glissiere : glissière acier (rainures avant/arrière, fenêtre d'éjection, hausse et guidon à points blancs,
              marquages gravés) ; recule de 3,4 cm au tir, reste bloquée en arrière quand l'arme est vide
- canon     : canon et bloc de culasse visibles dans la fenêtre d'éjection et à la bouche
- chargeur  : chargeur amovible (corps acier, semelle polymère, cartouche du dessus) ; repère local :
              axe -Y (Godot) = sens de sortie le long de la poignée
- detente   : queue de détente avec sa sécurité centrale

Textures PBR (couleur, rugosité, relief) cuites par Cycles à partir de matériaux procéduraux :
usure des arêtes (nœud Biseau), rayures, crasse dans les creux (occlusion), granité de la poignée,
gravures. Aucune ressource externe.
"""
import bpy
import bmesh
import math
import os
from mathutils import Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TEX_TMP = os.path.join(ROOT, "_sources", "pistolet_tex")
import sys
OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv[:-1] else os.path.join(ROOT, "_sources", "pistolet_maison.glb")

GRIP_ANGLE = math.radians(18.0)          # poignée inclinée vers l'arrière
GRIP_TOP = Vector((0.0, -0.008, 0.045))   # centre du haut de la poignée
GRIP_D = Vector((0.0, -math.sin(GRIP_ANGLE), -math.cos(GRIP_ANGLE)))   # vers le bas de la poignée
GRIP_F = Vector((0.0, math.cos(GRIP_ANGLE), -math.sin(GRIP_ANGLE)))    # vers l'avant de la poignée


def log(*a):
    print("[pistolet]", *a, flush=True)


# ---------------------------------------------------------------- géométrie

def objet(nom, bm):
    me = bpy.data.meshes.new(nom)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(nom, me)
    bpy.context.collection.objects.link(ob)
    return ob


def boite(nom, taille, centre, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix.Diagonal((*taille, 1.0))
    if rot is not None:
        m = rot.to_4x4() @ m
    bmesh.ops.transform(bm, matrix=Matrix.Translation(centre) @ m, verts=bm.verts)
    return objet(nom, bm)


def prisme(nom, pts_yz, x0, x1):
    """Profil latéral (y, z) extrudé selon X (polygone simple, concave accepté)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x0, y, z)) for y, z in pts_yz]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(x1 - x0, 0, 0), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    return objet(nom, bm)


def cylindre(nom, r, longueur, centre, axe="Y", seg=20):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=longueur)
    rot = {"Y": Matrix.Rotation(math.pi / 2, 4, "X"), "X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Z": Matrix.Identity(4)}[axe]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(centre) @ rot, verts=bm.verts)
    return objet(nom, bm)


def appliquer(ob):
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def biseau(ob, largeur, seg=2, angle=40):
    b = ob.modifiers.new("biseau", "BEVEL")
    b.width = largeur
    b.segments = seg
    b.limit_method = "ANGLE"
    b.angle_limit = math.radians(angle)
    b.harden_normals = False
    appliquer(ob)


def soustraire(ob, outils, solveur="EXACT"):
    for o in outils:
        m = ob.modifiers.new("trou", "BOOLEAN")
        m.operation = "DIFFERENCE"
        m.object = o
        m.solver = solveur
        appliquer(ob)
        bpy.data.objects.remove(o, do_unlink=True)


def unir(ob, autres):
    """Réunit des maillages (sans booléen : les parties se chevauchent, faces internes invisibles)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in autres:
        o.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    return ob


def masque(ob, canal, valeur=1.0, faces=None):
    """Attribut de couleur « masque » (R gravure, G granité / polymère, B point blanc), par coin de face."""
    me = ob.data
    if "masque" not in me.color_attributes:
        me.color_attributes.new("masque", "BYTE_COLOR", "CORNER")
        a = me.color_attributes["masque"]
        for d in a.data:
            d.color = (0, 0, 0, 1)
    a = me.color_attributes["masque"]
    idx = {"R": 0, "G": 1, "B": 2}[canal]
    for p in me.polygons:
        if faces is None or faces(p):
            for li in p.loop_indices:
                c = list(a.data[li].color)
                c[idx] = valeur
                a.data[li].color = c


def texte(nom, chaine, taille, centre, cote):
    """Marquage gravé : texte en relief de 0,12 mm posé sur une face latérale (cote = +1 droite, -1 gauche)."""
    cu = bpy.data.curves.new(nom, "FONT")
    cu.body = chaine
    cu.size = taille
    cu.extrude = 0.00006
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new(nom, cu)
    bpy.context.collection.objects.link(ob)
    x = Vector((0, cote, 0))
    y = Vector((0, 0, 1))
    z = Vector((cote, 0, 0))
    m = Matrix((x, y, z)).transposed().to_4x4()
    ob.matrix_world = Matrix.Translation(centre) @ m
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.active_object
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    masque(ob, "R")
    return ob


def glissiere():
    # corps : profil latéral avec chanfrein avant
    pts = [(-0.038, 0.058), (0.150, 0.058), (0.150, 0.083), (0.142, 0.090), (-0.036, 0.090), (-0.038, 0.087)]
    g = prisme("glissiere", pts, -0.0125, 0.0125)
    biseau(g, 0.0016, 2)
    trous = []
    # dessus arrondi : chanfreins longitudinaux
    for s in (-1, 1):
        trous.append(boite("ch", (0.01, 0.30, 0.01), Vector((s * 0.0158, 0.05, 0.0938)), Matrix.Rotation(math.radians(45), 3, "Y")))
    # fenêtre d'éjection (dessus + flanc droit)
    trous.append(boite("ej", (0.0135, 0.040, 0.03), Vector((0.0068, 0.056, 0.084))))
    # rainures de préhension arrière (inclinées) et avant, deux flancs
    for s in (-1, 1):
        for i in range(8):
            trous.append(boite("r", (0.0022, 0.0013, 0.026), Vector((s * 0.0128, -0.032 + i * 0.0036, 0.073)), Matrix.Rotation(math.radians(-8), 3, "X")))
        for i in range(5):
            trous.append(boite("r", (0.0022, 0.0013, 0.022), Vector((s * 0.0128, 0.112 + i * 0.0036, 0.072)), Matrix.Rotation(math.radians(-8), 3, "X")))
    # bouche : logement du canon
    trous.append(cylindre("bo", 0.0072, 0.04, Vector((0, 0.15, 0.072)), "Y", 24))
    # dessous creux (rail de la carcasse)
    trous.append(boite("dessous", (0.019, 0.186, 0.012), Vector((0, 0.061, 0.059))))   # plaque arrière gardée
    soustraire(g, trous)
    # hausse (cran) et guidon
    h = boite("hausse", (0.019, 0.0065, 0.0055), Vector((0, -0.030, 0.0925)))
    biseau(h, 0.0008, 1)
    soustraire(h, [boite("cran", (0.0036, 0.02, 0.004), Vector((0, -0.03, 0.0957)))])
    gu = boite("guidon", (0.0034, 0.005, 0.0052), Vector((0, 0.139, 0.0922)))
    biseau(gu, 0.0006, 1)
    points = []
    for x, y, z in ((-0.0062, -0.0334, 0.0935), (0.0062, -0.0334, 0.0935), (0, 0.1364, 0.0935)):
        p = cylindre("point", 0.00095, 0.0006, Vector((x, y, z)), "Y", 10)
        masque(p, "B")
        points.append(p)
    marques = [texte("m1", "DM-17   9x19", 0.0036, Vector((-0.01262, 0.075, 0.074)), -1),
               texte("m2", "CAL. 9mm PARA", 0.0026, Vector((0.01262, 0.103, 0.067)), 1),
               texte("m3", "PC-04718", 0.0024, Vector((0.01262, -0.012, 0.0645)), 1)]
    masque(g, "R", 0.0)
    for o in (h, gu):
        masque(o, "R", 0.0)
    return unir(g, [h, gu] + points + marques)


def canon():
    c = cylindre("canon", 0.0068, 0.112, Vector((0, 0.094, 0.072)), "Y", 24)
    soustraire(c, [cylindre("ame", 0.0046, 0.05, Vector((0, 0.15, 0.072)), "Y", 16)])
    bloc = boite("bloc", (0.0118, 0.044, 0.0165), Vector((0, 0.056, 0.0745)))
    biseau(bloc, 0.0008, 1)
    # rampe d'alimentation et chambre : petite encoche à l'arrière
    soustraire(bloc, [cylindre("ch", 0.0048, 0.01, Vector((0, 0.033, 0.072)), "Y", 16)])
    masque(c, "R", 0.0)
    masque(bloc, "R", 0.0)
    gp = cylindre("guide", 0.0032, 0.10, Vector((0, 0.098, 0.0565)), "Y", 12)   # guide de ressort
    masque(gp, "R", 0.0)
    return unir(c, [bloc, gp])


def carcasse():
    # haut de carcasse + cache-poussière (avec rail)
    haut = prisme("carcasse", [(-0.037, 0.0595), (0.141, 0.0595), (0.141, 0.043), (0.134, 0.040), (0.020, 0.040),
                               (0.012, 0.046), (-0.030, 0.046), (-0.037, 0.050)], -0.0112, 0.0112)
    biseau(haut, 0.0018, 2)
    rail = [boite("rail", (0.0245, 0.0045, 0.006), Vector((0, 0.092 + i * 0.010, 0.0405))) for i in range(4)]
    soustraire(haut, rail)
    # poignée inclinée, avec bosse dorsale (« queue de castor ») et festons des doigts
    ht = 0.107
    top = GRIP_TOP
    f, d = GRIP_F, GRIP_D

    def p(u, v):            # u : vers l'avant (0 = axe), v : vers le bas
        q = top + f * u + d * v
        return (q.y, q.z)
    av = [p(0.0255, 0.004)]
    for k, (v, bosse) in enumerate([(0.03, 0.0), (0.045, 0.0022), (0.06, 0.0), (0.075, 0.0022), (0.09, 0.0)]):
        av.append(p(0.0255 + bosse, v))
    pts = av + [p(0.0255, ht), p(-0.0250, ht), p(-0.0262, 0.03), p(-0.0272, 0.008), (-0.047, 0.0485), (-0.0455, 0.053), (-0.034, 0.0515), (-0.020, 0.048), (0.012, 0.043)]
    poignee = prisme("poignee", pts, -0.0148, 0.0148)
    biseau(poignee, 0.0085, 4, angle=50)
    # puits du chargeur (le chargeur glisse dedans) : ouverture en bas
    puits = boite("puits", (0.0222, 0.0335, 0.06), top + d * (ht + 0.002), rot=Matrix.Rotation(-GRIP_ANGLE, 3, "X"))
    soustraire(poignee, [puits])
    masque(poignee, "G", 1.0, faces=lambda pl: abs(pl.normal.x) > 0.55 or pl.normal.dot(Vector((0, f.y, f.z))) > 0.6 or pl.normal.dot(Vector((0, -f.y, -f.z))) > 0.6)
    # pontet : profil en U, réuni à la carcasse et à la poignée
    pontet = prisme("pontet", [(0.010, 0.042), (0.011, 0.015), (0.016, 0.0105), (0.056, 0.0105), (0.066, 0.016), (0.070, 0.041),
                               (0.0655, 0.041), (0.0615, 0.0195), (0.055, 0.0145), (0.018, 0.0145), (0.015, 0.0175), (0.014, 0.042)],
                    -0.0048, 0.0048)
    biseau(pontet, 0.0016, 2)
    # arrêtoir de glissière (gauche), bouton de chargeur, levier de démontage
    arr = boite("arretoir", (0.0016, 0.016, 0.0036), Vector((-0.0118, 0.022, 0.0535)))
    biseau(arr, 0.0005, 1)
    bouton = boite("bouton", (0.0018, 0.0075, 0.0065), Vector((-0.0145, 0.0075, 0.0365)), Matrix.Rotation(-GRIP_ANGLE, 3, "X"))
    biseau(bouton, 0.0007, 1)
    dem = [boite("dem", (0.0012, 0.0075, 0.0026), Vector((s * 0.0115, 0.064, 0.0525))) for s in (-1, 1)]
    for o in dem:
        biseau(o, 0.0004, 1)
    serie = texte("serie", "CDM 04718", 0.0024, Vector((0.01125, 0.105, 0.0485)), 1)
    for o in (haut, pontet, arr, bouton) + tuple(dem):
        masque(o, "R", 0.0)
    for o in (haut, pontet, arr, bouton) + tuple(dem) + (serie,):
        masque(o, "G", 0.35)       # polymère lisse (G = 0,35), granité (G = 1)
    return unir(haut, [poignee, pontet, arr, bouton, serie] + dem)


def detente():
    pts = [(0.0355, 0.040), (0.040, 0.034), (0.0405, 0.027), (0.038, 0.0215), (0.0345, 0.0185), (0.0325, 0.020),
           (0.035, 0.024), (0.0355, 0.030), (0.0325, 0.036), (0.0315, 0.040)]
    t = prisme("detente", pts, -0.0032, 0.0032)
    biseau(t, 0.0007, 2)
    s = prisme("securite", [(0.0352, 0.031), (0.0372, 0.026), (0.036, 0.0225), (0.0345, 0.024), (0.0350, 0.028)], -0.0011, 0.0011)
    s.location.x = 0.0
    masque(t, "G", 0.35)
    masque(s, "G", 0.35)
    return unir(t, [s])


def chargeur():
    """Chargeur dans son repère : origine = position au repos, axes tournés comme la poignée."""
    rot = Matrix.Rotation(-GRIP_ANGLE, 3, "X")
    longueur = 0.118
    centre = GRIP_TOP + GRIP_D * (0.107 + 0.004 - longueur / 2.0)
    corps = boite("chargeur", (0.0215, 0.0315, longueur), centre, rot)
    biseau(corps, 0.002, 2)
    semelle = boite("semelle", (0.0275, 0.0395, 0.0075), GRIP_TOP + GRIP_D * (0.107 + 0.0065) + GRIP_F * 0.0005, rot)
    biseau(semelle, 0.0022, 2)
    masque(semelle, "G", 0.35)
    # cartouche du dessus (laiton + ogive cuivrée), visible quand le chargeur est sorti
    haut = GRIP_TOP + GRIP_D * (0.107 + 0.004 - longueur)
    cart = cylindre("cartouche", 0.0049, 0.019, haut - GRIP_D * 0.0045 + GRIP_F * 0.001, "Y", 14)
    ogive = cylindre("ogive", 0.0043, 0.010, haut - GRIP_D * 0.0045 + GRIP_F * 0.0145, "Y", 14)
    masque(cart, "B", 0.5)
    masque(ogive, "B", 0.25)
    for o in (corps, cart, ogive):
        masque(o, "G", 0.0)
    ob = unir(corps, [semelle, cart, ogive])
    # origine au point de repos, axes = poignée (rotation gardée dans l'objet)
    inv = Matrix.Translation(GRIP_TOP) @ rot.to_4x4()
    ob.data.transform(inv.inverted())
    ob.matrix_world = inv
    return ob


# ---------------------------------------------------------------- matériaux procéduraux et cuisson

PROFILS = {
    #             couleur base           couleur usure        rugosité, rug. usure, métal, granité
    "glissiere": ((0.030, 0.030, 0.032), (0.30, 0.30, 0.31), 0.52, 0.28, 1.0, 0.0),
    "canon":     ((0.090, 0.088, 0.085), (0.35, 0.34, 0.32), 0.30, 0.20, 1.0, 0.0),
    "carcasse":  ((0.016, 0.016, 0.017), (0.060, 0.060, 0.062), 0.66, 0.45, 0.0, 1.0),
    "detente":   ((0.016, 0.016, 0.017), (0.060, 0.060, 0.062), 0.55, 0.40, 0.0, 0.0),
    "chargeur":  ((0.028, 0.028, 0.030), (0.28, 0.28, 0.29), 0.45, 0.25, 1.0, 0.0),
}
TAILLES = {"glissiere": 1024, "carcasse": 1024, "canon": 512, "detente": 256, "chargeur": 512}


def noeud(nt, t, **kw):
    n = nt.nodes.new(t)
    for k, v in kw.items():
        if k in n.inputs:
            n.inputs[k].default_value = v
        else:
            setattr(n, k, v)
    return n


def materiau_cuisson(nom):
    """Matériau procédural : sorties « couleur », « rugosite » (pour la cuisson par émission) et normale (relief)."""
    base, usure, rough, rough_u, metal, granite = PROFILS[nom]
    m = bpy.data.materials.new(nom + "_proc")
    m.use_nodes = True
    nt = m.node_tree
    L = nt.links
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    tc = noeud(nt, "ShaderNodeTexCoord")
    geo = noeud(nt, "ShaderNodeNewGeometry")
    attr = noeud(nt, "ShaderNodeVertexColor", layer_name="masque")
    sep = noeud(nt, "ShaderNodeSeparateColor")
    L.new(attr.outputs["Color"], sep.inputs["Color"])
    # arêtes : écart entre normale biseautée et normale réelle
    bev = noeud(nt, "ShaderNodeBevel", samples=8)
    bev.inputs["Radius"].default_value = 0.0012
    dot = noeud(nt, "ShaderNodeVectorMath", operation="DOT_PRODUCT")
    L.new(bev.outputs["Normal"], dot.inputs[0])
    L.new(geo.outputs["Normal"], dot.inputs[1])
    arete = noeud(nt, "ShaderNodeMapRange", clamp=True)
    arete.inputs["From Min"].default_value = 0.995
    arete.inputs["From Max"].default_value = 0.95
    L.new(dot.outputs["Value"], arete.inputs["Value"])
    # irrégularité de l'usure
    br = noeud(nt, "ShaderNodeTexNoise")
    br.inputs["Scale"].default_value = 900.0
    br.inputs["Detail"].default_value = 6.0
    L.new(tc.outputs["Object"], br.inputs["Vector"])
    usure_m = noeud(nt, "ShaderNodeMath", operation="MULTIPLY", use_clamp=True)
    k = noeud(nt, "ShaderNodeMapRange", clamp=True)
    k.inputs["From Min"].default_value = 0.35
    k.inputs["From Max"].default_value = 0.6
    L.new(br.outputs["Fac"], k.inputs["Value"])
    L.new(arete.outputs["Result"], usure_m.inputs[0])
    L.new(k.outputs["Result"], usure_m.inputs[1])
    # rayures fines (deux directions) : bruit très étiré puis seuil
    rayures = []
    for ang, sc in ((0.0, (5200.0, 90.0, 5200.0)), (0.7, (90.0, 4200.0, 4200.0))):
        mp = noeud(nt, "ShaderNodeMapping")
        mp.inputs["Rotation"].default_value = (ang, ang * 0.5, ang)
        mp.inputs["Scale"].default_value = sc
        L.new(tc.outputs["Object"], mp.inputs["Vector"])
        nz = noeud(nt, "ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 1.0
        nz.inputs["Detail"].default_value = 2.0
        L.new(mp.outputs["Vector"], nz.inputs["Vector"])
        th = noeud(nt, "ShaderNodeMapRange", clamp=True)
        th.inputs["From Min"].default_value = 0.70
        th.inputs["From Max"].default_value = 0.78
        L.new(nz.outputs["Fac"], th.inputs["Value"])
        # rayures par endroits seulement
        zone = noeud(nt, "ShaderNodeTexNoise")
        zone.inputs["Scale"].default_value = 60.0
        L.new(tc.outputs["Object"], zone.inputs["Vector"])
        zk = noeud(nt, "ShaderNodeMapRange", clamp=True)
        zk.inputs["From Min"].default_value = 0.5
        zk.inputs["From Max"].default_value = 0.62
        L.new(zone.outputs["Fac"], zk.inputs["Value"])
        mm = noeud(nt, "ShaderNodeMath", operation="MULTIPLY")
        L.new(th.outputs["Result"], mm.inputs[0])
        L.new(zk.outputs["Result"], mm.inputs[1])
        rayures.append(mm)
    ray = noeud(nt, "ShaderNodeMath", operation="ADD", use_clamp=True)
    L.new(rayures[0].outputs[0], ray.inputs[0])
    L.new(rayures[1].outputs[0], ray.inputs[1])
    ray_f = noeud(nt, "ShaderNodeMath", operation="MULTIPLY", use_clamp=True)
    L.new(ray.outputs[0], ray_f.inputs[0])
    ray_f.inputs[1].default_value = 0.6 if metal > 0.5 else 0.35
    # crasse dans les creux
    ao = noeud(nt, "ShaderNodeAmbientOcclusion", samples=16, only_local=True)
    ao.inputs["Distance"].default_value = 0.004
    crasse = noeud(nt, "ShaderNodeMapRange", clamp=True)
    crasse.inputs["From Min"].default_value = 0.9
    crasse.inputs["From Max"].default_value = 0.4
    L.new(ao.outputs["AO"], crasse.inputs["Value"])
    # usure totale = arêtes + rayures
    us = noeud(nt, "ShaderNodeMath", operation="MAXIMUM")
    L.new(usure_m.outputs[0], us.inputs[0])
    L.new(ray_f.outputs[0], us.inputs[1])
    # couleur
    c1 = noeud(nt, "ShaderNodeMix", data_type="RGBA")
    c1.inputs["A"].default_value = (*base, 1)
    c1.inputs["B"].default_value = (*usure, 1)
    L.new(us.outputs[0], c1.inputs["Factor"])
    # variations de teinte (grandes taches, traces de doigts)
    tache = noeud(nt, "ShaderNodeTexNoise")
    tache.inputs["Scale"].default_value = 35.0
    tache.inputs["Detail"].default_value = 4.0
    L.new(tc.outputs["Object"], tache.inputs["Vector"])
    tk = noeud(nt, "ShaderNodeMapRange", clamp=True)
    tk.inputs["From Min"].default_value = 0.3
    tk.inputs["From Max"].default_value = 0.7
    tk.inputs["To Min"].default_value = 0.85
    tk.inputs["To Max"].default_value = 1.15
    L.new(tache.outputs["Fac"], tk.inputs["Value"])
    c2 = noeud(nt, "ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
    c2.inputs["Factor"].default_value = 1.0
    L.new(c1.outputs["Result"], c2.inputs["A"])
    cc = noeud(nt, "ShaderNodeCombineColor")
    for i in range(3):
        L.new(tk.outputs["Result"], cc.inputs[i])
    L.new(cc.outputs["Color"], c2.inputs["B"])
    # crasse grise claire (poussière, huile sèche)
    c3 = noeud(nt, "ShaderNodeMix", data_type="RGBA")
    c3.inputs["B"].default_value = (0.07, 0.065, 0.06, 1)
    cr = noeud(nt, "ShaderNodeMath", operation="MULTIPLY")
    L.new(crasse.outputs["Result"], cr.inputs[0])
    cr.inputs[1].default_value = 0.4
    L.new(cr.outputs[0], c3.inputs["Factor"])
    L.new(c2.outputs["Result"], c3.inputs["A"])
    # gravures (R) : creux sombres et mats ; points blancs / laiton (B)
    c4 = noeud(nt, "ShaderNodeMix", data_type="RGBA")
    c4.inputs["B"].default_value = (0.006, 0.006, 0.006, 1)
    L.new(sep.outputs["Red"], c4.inputs["Factor"])
    L.new(c3.outputs["Result"], c4.inputs["A"])
    # B : 1 = point blanc, 0,5 = laiton, 0,25 = cuivre
    rampe = noeud(nt, "ShaderNodeValToRGB")
    cr_ = rampe.color_ramp
    cr_.interpolation = "CONSTANT"
    cr_.elements[0].position = 0.0
    cr_.elements[0].color = (0, 0, 0, 0)
    e = cr_.elements.new(0.2)
    e.color = (0.45, 0.22, 0.10, 1)
    e = cr_.elements.new(0.4)
    e.color = (0.62, 0.42, 0.16, 1)
    cr_.elements[-1].position = 0.9
    cr_.elements[-1].color = (0.85, 0.85, 0.80, 1)
    L.new(sep.outputs["Blue"], rampe.inputs["Fac"])
    c5 = noeud(nt, "ShaderNodeMix", data_type="RGBA")
    L.new(rampe.outputs["Alpha"], c5.inputs["Factor"])
    L.new(c4.outputs["Result"], c5.inputs["A"])
    L.new(rampe.outputs["Color"], c5.inputs["B"])
    couleur = c5.outputs["Result"]
    # rugosité
    r1 = noeud(nt, "ShaderNodeMapRange", clamp=True)
    r1.inputs["To Min"].default_value = rough
    r1.inputs["To Max"].default_value = rough_u
    L.new(us.outputs[0], r1.inputs["Value"])
    rg = noeud(nt, "ShaderNodeMath", operation="ADD", use_clamp=True)
    L.new(r1.outputs["Result"], rg.inputs[0])
    gr_r = noeud(nt, "ShaderNodeMath", operation="MULTIPLY")
    L.new(sep.outputs["Green"], gr_r.inputs[0])
    gr_r.inputs[1].default_value = 0.18 * granite
    L.new(gr_r.outputs[0], rg.inputs[1])
    rg2 = noeud(nt, "ShaderNodeMath", operation="ADD", use_clamp=True)
    L.new(rg.outputs[0], rg2.inputs[0])
    gv = noeud(nt, "ShaderNodeMath", operation="MULTIPLY")
    L.new(sep.outputs["Red"], gv.inputs[0])
    gv.inputs[1].default_value = 0.35
    L.new(gv.outputs[0], rg2.inputs[1])
    rg3 = noeud(nt, "ShaderNodeMath", operation="MULTIPLY_ADD", use_clamp=True)   # traces de doigts
    L.new(tk.outputs["Result"], rg3.inputs[0])
    rg3.inputs[1].default_value = 0.25
    rg3.inputs[2].default_value = -0.25
    rg4 = noeud(nt, "ShaderNodeMath", operation="ADD", use_clamp=True)
    L.new(rg2.outputs[0], rg4.inputs[0])
    L.new(rg3.outputs[0], rg4.inputs[1])
    rugosite = rg4.outputs[0]
    # relief : granité (voronoï) sur la poignée, rayures en creux, grain fin
    vor = noeud(nt, "ShaderNodeTexVoronoi", feature="F1")
    vor.inputs["Scale"].default_value = 1400.0
    L.new(tc.outputs["Object"], vor.inputs["Vector"])
    gmask = noeud(nt, "ShaderNodeMapRange", clamp=True)
    gmask.inputs["From Min"].default_value = 0.7
    gmask.inputs["From Max"].default_value = 0.95
    L.new(sep.outputs["Green"], gmask.inputs["Value"])
    gh = noeud(nt, "ShaderNodeMath", operation="MULTIPLY")
    L.new(vor.outputs["Distance"], gh.inputs[0])
    L.new(gmask.outputs["Result"], gh.inputs[1])
    grain = noeud(nt, "ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 4000.0
    L.new(tc.outputs["Object"], grain.inputs["Vector"])
    hh = noeud(nt, "ShaderNodeMath", operation="MULTIPLY_ADD")
    L.new(grain.outputs["Fac"], hh.inputs[0])
    hh.inputs[1].default_value = 0.08
    L.new(gh.outputs[0], hh.inputs[2])
    hr = noeud(nt, "ShaderNodeMath", operation="MULTIPLY_ADD")
    L.new(ray_f.outputs[0], hr.inputs[0])
    hr.inputs[1].default_value = -0.15
    L.new(hh.outputs[0], hr.inputs[2])
    bump = noeud(nt, "ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    bump.inputs["Distance"].default_value = 0.0004
    L.new(hr.outputs[0], bump.inputs["Height"])
    L.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    L.new(couleur, bsdf.inputs["Base Color"])
    L.new(rugosite, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    em = noeud(nt, "ShaderNodeEmission")
    return m, {"couleur": couleur, "rugosite": rugosite, "bsdf": bsdf.outputs["BSDF"], "em": em, "out": out}


def cuire(ob, nom):
    taille = TAILLES[nom]
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.008, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    mat, s = materiau_cuisson(nom)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    nt = mat.node_tree
    L = nt.links
    imgs = {}
    os.makedirs(TEX_TMP, exist_ok=True)
    for canal in ("couleur", "rugosite", "relief"):
        img = bpy.data.images.new("%s_%s" % (nom, canal), taille, taille, alpha=False)
        if canal != "couleur":
            img.colorspace_settings.name = "Non-Color"
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img
        for n in nt.nodes:
            n.select = False
        tn.select = True
        nt.nodes.active = tn
        if canal == "relief":
            L.new(s["bsdf"], s["out"].inputs["Surface"])
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=4)
        else:
            L.new(s[canal], s["em"].inputs["Color"])
            L.new(s["em"].outputs["Emission"], s["out"].inputs["Surface"])
            bpy.ops.object.bake(type="EMIT", margin=4)
        p = os.path.join(TEX_TMP, "%s_%s.png" % (nom, canal))
        img.filepath_raw = p
        img.file_format = "PNG"
        img.save()
        nt.nodes.remove(tn)
        imgs[canal] = img
    # matériau final exportable
    metal = PROFILS[nom][4]
    f = bpy.data.materials.new(nom)
    f.use_nodes = True
    f.use_backface_culling = True      # pièces fermées : glTF « simple face »
    ft = f.node_tree
    b = next(n for n in ft.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Metallic"].default_value = metal
    tc = ft.nodes.new("ShaderNodeTexImage")
    tc.image = imgs["couleur"]
    ft.links.new(tc.outputs["Color"], b.inputs["Base Color"])
    tr = ft.nodes.new("ShaderNodeTexImage")
    tr.image = imgs["rugosite"]
    ft.links.new(tr.outputs["Color"], b.inputs["Roughness"])
    tnm = ft.nodes.new("ShaderNodeTexImage")
    tnm.image = imgs["relief"]
    nm = ft.nodes.new("ShaderNodeNormalMap")
    ft.links.new(tnm.outputs["Color"], nm.inputs["Color"])
    ft.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    ob.data.materials.clear()
    ob.data.materials.append(f)
    ob.data.color_attributes.remove(ob.data.color_attributes["masque"])
    log("cuit", nom, taille, "px")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.render.bake.margin = 4
    pieces = {"glissiere": glissiere(), "canon": canon(), "carcasse": carcasse(), "detente": detente(), "chargeur": chargeur()}
    tris = 0
    for nom, ob in pieces.items():
        ob.name = nom
        for p in ob.data.polygons:
            p.use_smooth = True
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
        appliquer(ob)
        cuire(ob, nom)
        tris += sum(len(p.vertices) - 2 for p in ob.data.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in pieces.values():
        ob.select_set(True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=90, export_vertex_color="NONE")
    log("EXPORT", OUT, os.path.getsize(OUT) // 1024, "ko,", tris, "triangles")


main()

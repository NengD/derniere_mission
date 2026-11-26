"""Porte de service métallique abîmée (huisserie + battant cabossé), modelée de zéro.

Usage : blender -b --factory-startup -P tools/blender/build_porte.py
Sortie : assets/decor/models/porte_metal/porte_metal.glb

Repère (Godot) : origine au sol, sur l'axe des gonds (côté gauche vu de face, face avant vers +Z) ;
la porte occupe x ∈ [0 ; 0,92], y ∈ [0 ; 2,04]. Nœuds :
- huisserie : cadre en acier plié (montants et traverse), butée
- battant   : vantail creux 4,5 cm, origine sur l'axe des gonds (le faire tourner autour de Y pour
              l'entrouvrir) ; enfoncements (coups de pied en bas, coup d'épaule près de la serrure,
              pli d'un chariot à mi-hauteur), bord inférieur tordu, grille de ventilation basse,
              plaque de propreté, béquille, serrure, trois paumelles
Matériaux (remplacés dans Godot par le kit) : « peinture » (vantail, huisserie), « acier » (béquille,
paumelles, plaque), « grille ». UV en projection cubique, 1 unité = 1 m.
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "decor", "models", "porte_metal", "porte_metal.glb")

LW, LH, LT = 0.92, 2.04, 0.045       # vantail
JEU = 0.004


def mat(nom, couleur):
    m = bpy.data.materials.get(nom) or bpy.data.materials.new(nom)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs[0].default_value = couleur
    return m


def boite(nom, centre, taille, materiau, parent=None, biseau=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
    o = bpy.context.active_object
    o.name = nom
    o.scale = taille
    bpy.ops.object.transform_apply(scale=True)
    if biseau:
        b = o.modifiers.new("biseau", "BEVEL")
        b.width = biseau
        b.segments = 2
        bpy.ops.object.modifier_apply(modifier="biseau")
    o.data.materials.append(materiau)
    if parent:
        o.parent = parent
    return o


def cylindre(nom, centre, rayon, longueur, axe, materiau, verts=16):
    rot = {"x": (0, math.pi / 2, 0), "y": (math.pi / 2, 0, 0), "z": (0, 0, 0)}[axe]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=rayon, depth=longueur, location=centre, rotation=rot)
    o = bpy.context.active_object
    o.name = nom
    o.data.materials.append(materiau)
    return o


def uv_cube(o):
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=1.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    o.select_set(False)


def joindre(objs, nom):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = nom
    return o


def enfoncer(o, centre, rayon, profondeur, etirement=(1.0, 1.0)):
    """Enfonce le vantail (vers -Y Blender = vers l'arrière) avec une cloche gaussienne ; la face
    arrière suit à moitié (tôle emboutie)."""
    for v in o.data.vertices:
        dx = (v.co.x - centre[0]) / (rayon * etirement[0])
        dz = (v.co.z - centre[1]) / (rayon * etirement[1])
        k = math.exp(-(dx * dx + dz * dz) * 2.0)
        if k < 0.01:
            continue
        av = v.co.y < 0     # Blender : face avant de la porte vers -Y (devient +Z dans Godot)
        v.co.y += profondeur * k * (1.0 if av else 0.5)


def construire():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    peinture = mat("peinture", (0.16, 0.25, 0.2, 1))
    acier = mat("acier", (0.5, 0.5, 0.5, 1))
    grille = mat("grille", (0.08, 0.08, 0.08, 1))
    rnd = random.Random(4)

    # --- huisserie (profil 5 × 10 cm, feuillure) : dans le plan du mur, autour du vantail
    ep = 0.05
    h = [
        boite("m_g", (-ep / 2 - JEU, 0, (LH + ep) / 2), (ep, 0.1, LH + ep), peinture, biseau=0.004),
        boite("m_d", (LW + ep / 2 + JEU, 0, (LH + ep) / 2), (ep, 0.1, LH + ep), peinture, biseau=0.004),
        boite("tr", (LW / 2, 0, LH + JEU + ep / 2), (LW + 2 * ep + 2 * JEU, 0.1, ep), peinture, biseau=0.004),
        boite("butee", (LW / 2, 0.035, LH + JEU - 0.01), (LW, 0.02, 0.02), peinture),
    ]
    huisserie = joindre(h, "huisserie")
    uv_cube(huisserie)

    # --- vantail subdivisé (déformable)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(LW / 2, 0, LH / 2 + 0.008))
    b = bpy.context.active_object
    b.name = "battant_tole"
    b.scale = (LW, LT, LH - 0.012)
    bpy.ops.object.transform_apply(scale=True)
    sd = b.modifiers.new("grille", "SUBSURF")
    sd.subdivision_type = "SIMPLE"
    sd.levels = 5
    sd.render_levels = 5
    bpy.ops.object.modifier_apply(modifier="grille")
    b.data.materials.append(peinture)
    # coups : pieds en bas, épaule près de la serrure, chariot à mi-hauteur, coin bas tordu
    enfoncer(b, (0.62, 0.28), 0.10, 0.032)
    enfoncer(b, (0.45, 0.22), 0.08, 0.024)
    enfoncer(b, (0.78, 0.40), 0.06, 0.012)
    enfoncer(b, (0.72, 1.25), 0.17, 0.03, (1.2, 0.8))
    enfoncer(b, (0.35, 0.95), 0.30, 0.016, (2.2, 0.25))
    for _ in range(10):
        enfoncer(b, (rnd.uniform(0.1, 0.85), rnd.uniform(0.1, 1.9)), rnd.uniform(0.02, 0.05), rnd.uniform(0.002, 0.006))
    for v in b.data.vertices:
        if v.co.z < 0.12 and v.co.x > LW * 0.6:     # coin bas côté serrure tordu vers l'extérieur
            k = ((0.12 - v.co.z) / 0.12) * ((v.co.x - LW * 0.6) / (LW * 0.4))
            v.co.y -= 0.025 * k * k
    uv_cube(b)

    pieces = [b]
    # grille de ventilation basse (lames inclinées dans un cadre)
    pieces.append(boite("cadre_g", (LW / 2, -LT / 2 - 0.003, 0.30), (0.46, 0.006, 0.26), acier, biseau=0.002))
    for i in range(9):
        lame = boite("lame%d" % i, (LW / 2, -LT / 2 - 0.006, 0.19 + i * 0.025), (0.42, 0.004, 0.02), grille)
        lame.rotation_euler.x = math.radians(40)
        pieces.append(lame)
    # plaque de propreté (acier rayé), béquille, rosace, serrure
    pieces.append(boite("plaque", (LW / 2, -LT / 2 - 0.002, 0.08), (LW - 0.06, 0.003, 0.15), acier))
    pieces.append(boite("rosace", (LW - 0.08, -LT / 2 - 0.006, 1.02), (0.05, 0.012, 0.2), acier, biseau=0.003))
    pieces.append(cylindre("axe_bequille", (LW - 0.08, -LT / 2 - 0.03, 1.07), 0.009, 0.05, "y", acier))
    beq = boite("bequille", (LW - 0.14, -LT / 2 - 0.055, 1.07), (0.13, 0.018, 0.022), acier, biseau=0.006)
    beq.rotation_euler.y = math.radians(-6)      # béquille faussée, qui pend un peu
    pieces.append(beq)
    pieces.append(cylindre("cylindre_serrure", (LW - 0.08, -LT / 2 - 0.012, 0.95), 0.013, 0.02, "y", acier))
    # versant arrière : béquille seulement
    pieces.append(boite("rosace_ar", (LW - 0.08, LT / 2 + 0.006, 1.02), (0.05, 0.012, 0.2), acier, biseau=0.003))
    beq2 = boite("bequille_ar", (LW - 0.14, LT / 2 + 0.05, 1.07), (0.13, 0.018, 0.022), acier, biseau=0.006)
    pieces.append(beq2)
    pieces.append(cylindre("axe_ar", (LW - 0.08, LT / 2 + 0.025, 1.07), 0.009, 0.05, "y", acier))
    for z in (0.25, 1.05, 1.85):
        pieces.append(cylindre("paumelle", (-0.003, -LT / 2 + 0.008, z), 0.011, 0.11, "z", acier))
    battant = joindre(pieces, "battant")
    for o in [battant]:
        uv_cube(o)
    # origine du vantail sur l'axe des gonds
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.context.view_layer.objects.active = battant
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    for o in (huisserie, battant):
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
        o.select_set(False)

    # Blender : porte face avant vers -Y → Godot (+Y haut, export_yup) : avant vers +Z
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="PLACEHOLDER")
    print("[porte] exporté", OUT, sum(len(o.data.polygons) for o in (huisserie, battant)), "faces", flush=True)


construire()

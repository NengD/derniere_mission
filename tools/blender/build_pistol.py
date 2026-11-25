"""Pistolet semi-automatique générique (modelé de zéro, aucune marque réelle).

Usage : blender -b --factory-startup -P tools/blender/build_pistol.py
Sortie : assets/weapons/pistolet.glb — origine = centre de la poignée (là où la main serre),
canon vers +Y dans Blender (donc vers -Z, l'avant, dans Godot).
"""
import bpy
import math
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def mat(name, color, rough, metal):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def box(name, size, loc, m, bevel=0.002, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    if rot:
        o.rotation_euler = rot
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    if bevel:
        b = o.modifiers.new("b", "BEVEL")
        b.width = bevel
        b.segments = 2
    o.data.materials.append(m)
    return o


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    steel = mat("acier_noir", (0.025, 0.025, 0.027), 0.38, 0.85)
    poly = mat("polymere", (0.03, 0.03, 0.032), 0.62, 0.0)
    parts = []
    # culasse (slide) : 19 cm, au-dessus de la main
    parts.append(box("culasse", (0.026, 0.19, 0.032), (0, 0.055, 0.075), steel, 0.003))
    # stries de culasse à l'arrière
    for i in range(7):
        parts.append(box("strie%d" % i, (0.0275, 0.0025, 0.022), (0, -0.025 + i * 0.006, 0.077), steel, 0))
    # fenêtre d'éjection
    parts.append(box("ejection", (0.0275, 0.035, 0.012), (0.0005, 0.07, 0.084), mat("sombre", (0.005, 0.005, 0.005), 0.5, 0.5), 0))
    # bouche du canon
    bpy.ops.mesh.primitive_cylinder_add(radius=0.0065, depth=0.01, location=(0, 0.151, 0.072), rotation=(math.pi / 2, 0, 0))
    c = bpy.context.active_object
    c.data.materials.append(mat("ame", (0.0, 0.0, 0.0), 0.9, 0.0))
    parts.append(c)
    # carcasse / rail
    parts.append(box("carcasse", (0.024, 0.15, 0.022), (0, 0.045, 0.049), poly, 0.003))
    # poignée inclinée (~18°)
    parts.append(box("poignee", (0.028, 0.048, 0.11), (0, -0.012, -0.005), poly, 0.006, rot=(math.radians(-18), 0, 0)))
    # chargeur (fond)
    parts.append(box("fond_chargeur", (0.03, 0.05, 0.012), (0, -0.03, -0.058), poly, 0.003, rot=(math.radians(-18), 0, 0)))
    # pontet
    bpy.ops.mesh.primitive_torus_add(major_radius=0.022, minor_radius=0.0035, location=(0, 0.038, 0.03), rotation=(0, math.pi / 2, 0))
    t = bpy.context.active_object
    t.scale = (1, 1, 0.7)
    t.data.materials.append(poly)
    parts.append(t)
    # détente
    parts.append(box("detente", (0.006, 0.006, 0.02), (0, 0.032, 0.03), steel, 0.001, rot=(math.radians(15), 0, 0)))
    # organes de visée
    parts.append(box("guidon", (0.004, 0.006, 0.006), (0, 0.14, 0.094), steel, 0.001))
    parts.append(box("hausse", (0.02, 0.008, 0.007), (0, -0.03, 0.094), steel, 0.001))
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    g = bpy.context.active_object
    g.name = "pistolet"
    bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    out = os.path.join(ROOT, "assets", "weapons", "pistolet.glb")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("EXPORT", out, os.path.getsize(out) // 1024, "ko")


main()

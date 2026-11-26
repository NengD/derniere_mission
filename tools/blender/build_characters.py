"""Fabrique les personnages à partir du « Universal Base Characters » de Quaternius (CC0)
et des animations de la « Universal Animation Library » 1 (CC0).

Usage : blender -b --factory-startup -P tools/blender/build_characters.py -- garde|marc
Sortie : assets/characters/<nom>.glb (squelette, maillages, animations en pistes NLA)

- garde : membre du cartel, cagoule (seule une fente pour les yeux), t-shirt olive, gilet de toile,
          jean sombre, rangers ; mains nues.
- marc  : ancien corps du joueur (remplacé par tools/blender/build_marc_mpfb.py : ne plus utiliser « marc » ici).
"""
import bpy
import bmesh
import os
import sys
import glob
from mathutils import Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
Q = os.path.join(ROOT, "_sources", "quaternius")
TEX = os.path.join(ROOT, "assets", "characters", "tex")

ANIMS = ["Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Crouch_Idle_Loop", "Crouch_Fwd_Loop",
         "Pistol_Idle_Loop", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Aim_Down", "Pistol_Shoot",
         "Pistol_Reload", "Hit_Chest", "Hit_Head", "Death01", "Idle_Talking_Loop"]

HEAD = {"Head", "neck_01"}
TORSO = {"spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"}
ARMS = {"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"}
FEET = {"foot_l", "foot_r", "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r"}


def part_of(bone):
    if bone in HEAD:
        return "head"
    if bone in TORSO:
        return "torso"
    if bone in ARMS:
        return "arms"
    if bone.startswith(("hand_", "index_", "middle_", "ring_", "pinky_", "thumb_")):
        return "hands"
    if bone in FEET:
        return "feet"
    return "legs"


def cloth(name, scale, rough=0.9):
    """Matériau de tissu tuilé (texture teintée de tools/make_cloth_textures.py)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    uv = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, 1)
    nt.links.new(uv.outputs["UV"], mp.inputs["Vector"])

    def img(kind, non_color=False):
        p = os.path.join(TEX, "%s_%s.jpg" % (name, kind))
        if not os.path.exists(p):
            return None
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(p)
        if non_color:
            n.image.colorspace_settings.name = "Non-Color"
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
        return n

    d = img("diff")
    nt.links.new(d.outputs["Color"], bsdf.inputs["Base Color"])
    r = img("rough", True)
    if r:
        nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Roughness"].default_value = rough
    n = img("nor_gl", True)
    if n:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 0.8
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def flat(name, color, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def face_parts(ob):
    """Partie du corps de chaque face (groupe de sommets dominant)."""
    names = {g.index: g.name for g in ob.vertex_groups}
    vpart = []
    for v in ob.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        vpart.append(part_of(names[best.group]) if best else "legs")
    out = []
    for p in ob.data.polygons:
        cnt = {}
        for vi in p.vertices:
            cnt[vpart[vi]] = cnt.get(vpart[vi], 0) + 1
        out.append(max(cnt, key=cnt.get))
    return out


def make_vest(body, mat):
    """Gilet : copie du buste, gonflée le long des normales."""
    vest = body.copy()
    vest.data = body.data.copy()
    vest.name = "Gilet"
    bpy.context.collection.objects.link(vest)
    parts = face_parts(vest)
    bm = bmesh.new()
    bm.from_mesh(vest.data)
    bm.faces.ensure_lookup_table()
    kill = []
    for f, part in zip(bm.faces, parts):
        c = f.calc_center_median()
        if part != "torso" or not (0.98 < c.z < 1.47) or abs(c.x) > 0.21:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * 0.022
    bm.to_mesh(vest.data)
    bm.free()
    vest.data.materials.clear()
    vest.data.materials.append(mat)
    sol = vest.modifiers.new("epaisseur", "SOLIDIFY")
    sol.thickness = 0.012
    sol.offset = 1.0
    # le solidify doit passer avant l'armature
    while vest.modifiers[0].name != "epaisseur":
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = vest
        bpy.ops.object.modifier_move_up(modifier="epaisseur")
    return vest


def add_pouches(arm, mat):
    """Poches du gilet (cubes attachés à l'os spine_02)."""
    out = []
    for i, x in enumerate((-0.11, -0.04, 0.04, 0.11)):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, -0.175, 1.13))
        p = bpy.context.active_object
        p.name = "Poche%d" % i
        p.scale = (0.06, 0.035, 0.09)
        bpy.ops.object.transform_apply(scale=True)
        bev = p.modifiers.new("b", "BEVEL")
        bev.width = 0.008
        bev.segments = 2
        p.data.materials.append(mat)
        mw = p.matrix_world.copy()
        p.parent = arm
        p.parent_type = "BONE"
        p.parent_bone = "spine_02"
        p.matrix_world = mw
        out.append(p)
    return out


def main():
    who = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "garde"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    src = glob.glob(os.path.join(Q, "ubc", "**", "Godot - UE", "Superhero_Male_FullBody.gltf"), recursive=True)[0]
    bpy.ops.import_scene.gltf(filepath=src)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = bpy.data.objects["SuperHero_Male"]
    eyes = bpy.data.objects["Eyes"]
    for n in ("Icosphere", "Eyebrows"):
        if n in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
    skin = body.data.materials[0]

    parts = face_parts(body)
    ew = [eyes.matrix_world @ Vector(c) for c in eyes.bound_box]
    emin = Vector((min(v.x for v in ew), min(v.y for v in ew), min(v.z for v in ew)))
    emax = Vector((max(v.x for v in ew), max(v.y for v in ew), max(v.z for v in ew)))
    front_sign = -1 if (emin.y + emax.y) / 2 < 0 else 1

    if who == "garde":
        mats = {"head": cloth("cagoule", 5), "torso": cloth("tshirt_olive", 5), "arms": cloth("tshirt_olive", 5),
                "hands": skin, "legs": cloth("jean_sombre", 5), "feet": flat("rangers", (0.02, 0.02, 0.02), 0.45)}
    else:
        mats = {"head": skin, "torso": cloth("veste_marc", 5), "arms": cloth("veste_marc", 5),
                "hands": flat("gants", (0.025, 0.024, 0.023), 0.55), "legs": cloth("jean_sombre", 5), "feet": flat("rangers", (0.03, 0.025, 0.02), 0.5)}
    order = ["skin", "head", "torso", "arms", "hands", "legs", "feet"]
    body.data.materials.clear()
    for k in order:
        body.data.materials.append(skin if k == "skin" else mats[k])
    idx = {k: i for i, k in enumerate(order)}
    for p, part in zip(body.data.polygons, parts):
        c = body.matrix_world @ p.center
        slot = idx[part]
        if who == "garde" and part == "head":
            in_slit = (emin.x - 0.03 < c.x < emax.x + 0.03 and emin.z - 0.012 < c.z < emax.z + 0.017
                       and (c.y - (emin.y + emax.y) / 2) * front_sign > -0.03)
            if in_slit:
                slot = idx["skin"]
        p.material_index = slot

    if who == "garde":
        vest_mat = cloth("gilet_toile", 4)
        make_vest(body, vest_mat)
        add_pouches(arm, vest_mat)
    else:
        # corps du joueur : on retire la tête (la caméra est au niveau du torse)
        bm = bmesh.new()
        bm.from_mesh(body.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f, part in zip(bm.faces, parts) if part == "head"], context="FACES")
        bm.to_mesh(body.data)
        bm.free()
        bpy.data.objects.remove(eyes, do_unlink=True)

    # animations UAL1 -> pistes NLA
    ual = glob.glob(os.path.join(Q, "u1", "**", "Unreal-Godot", "UAL1_Standard.glb"), recursive=True)[0]
    before = set(bpy.data.objects)
    before_act = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=ual)
    for o in [o for o in bpy.data.objects if o not in before]:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a in before_act:
            bpy.data.actions.remove(a)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = None
    found = 0
    for name in ANIMS:
        act = bpy.data.actions.get(name)
        if act is None:
            act = next((a for a in bpy.data.actions if a.name.startswith(name)), None)
        if act is None:
            print("ANIM MANQUANTE", name)
            continue
        act.name = name
        tr = arm.animation_data.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, int(act.frame_range[0]), act)
        try:
            st.action_slot = act.slots[0]
        except Exception as e:
            print("slot", e)
        tr.mute = True
        found += 1

    out = os.path.join(ROOT, "assets", "characters", who + ".glb")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_yup=True, export_skins=True, export_reset_pose_bones=True,
                              export_image_format="JPEG", export_jpeg_quality=88)
    print("EXPORT", out, os.path.getsize(out) // 1024, "ko,", found, "animations")


main()

import bpy, sys
a = sys.argv[sys.argv.index("--")+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
for p in a:
    if p.endswith(".gltf") or p.endswith(".glb"): bpy.ops.import_scene.gltf(filepath=p)
for o in bpy.data.objects:
    print("OBJ", o.name, o.type, tuple(round(x,2) for x in o.dimensions), [m.name for m in getattr(o.data,'materials',[]) or []] if o.type=='MESH' else '', len(o.data.vertices) if o.type=='MESH' else '')
    if o.type=='ARMATURE': print("BONES", [b.name for b in o.data.bones])
    if o.type=='MESH': print("VG", [g.name for g in o.vertex_groups][:80])
for m in bpy.data.materials:
    print("MAT", m.name, [n.image.name for n in m.node_tree.nodes if n.type=='TEX_IMAGE'] if m.node_tree else '')

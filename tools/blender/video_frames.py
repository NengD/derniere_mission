"""Extrait des images d'une vidéo pour le contrôle qualité. Usage : blender -b --factory-startup -P video_frames.py -- video dossier pas [debut fin]"""
import bpy, sys, os
a = sys.argv[sys.argv.index("--") + 1:]
src, out, step = a[0], a[1], int(a[2])
sc = bpy.context.scene
sc.view_settings.view_transform = "Standard"
sc.sequence_editor_create()
se = sc.sequence_editor
strips = se.strips if hasattr(se, "strips") else se.sequences
st = strips.new_movie("v", src, 1, 1)
f0 = int(a[3]) if len(a) > 3 else 1
f1 = int(a[4]) if len(a) > 4 else st.frame_final_duration
el = st.elements[0]
sc.render.resolution_x, sc.render.resolution_y = el.orig_width, el.orig_height
sc.render.resolution_percentage = 50
sc.render.image_settings.file_format = "JPEG"
os.makedirs(out, exist_ok=True)
for f in range(f0, f1 + 1, step):
    sc.frame_set(f)
    sc.render.filepath = os.path.join(out, "f_%04d.jpg" % f)
    bpy.ops.render.render(write_still=True)
print("OK")

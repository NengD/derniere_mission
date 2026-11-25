"""Convertit une vidéo (AVI de Godot --write-movie) en MP4 H.264 avec le montage de Blender (pas de ffmpeg sur ce PC).

Usage : blender -b --factory-startup -P tools/blender/avi_to_mp4.py -- entree.avi sortie.mp4 [fps]
"""
import bpy
import sys

a = sys.argv[sys.argv.index("--") + 1:]
src, dst = a[0], a[1]
fps = int(a[2]) if len(a) > 2 else 30
sc = bpy.context.scene
sc.view_settings.view_transform = "Standard"
sc.sequence_editor_create()
se = sc.sequence_editor
strips = se.strips if hasattr(se, "strips") else se.sequences
st = strips.new_movie("v", src, 1, 1)
try:
    strips.new_sound("a", src, 2, 1)
except Exception as e:
    print("pas de son :", e)
sc.frame_start = 1
sc.frame_end = st.frame_final_duration
el = st.elements[0]
sc.render.resolution_x, sc.render.resolution_y = el.orig_width, el.orig_height
sc.render.resolution_percentage = 100
sc.render.fps = fps
try:
    sc.render.image_settings.media_type = "VIDEO"
except Exception:
    pass
sc.render.image_settings.file_format = "FFMPEG"
sc.render.ffmpeg.format = "MPEG4"
sc.render.ffmpeg.codec = "H264"
sc.render.ffmpeg.constant_rate_factor = "MEDIUM"
sc.render.ffmpeg.audio_codec = "AAC"
sc.render.filepath = dst
sc.render.use_file_extension = False
bpy.ops.render.render(animation=True)
print("MP4", dst, st.frame_final_duration, "images")

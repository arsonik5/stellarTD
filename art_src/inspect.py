"""Close-up inspection renders of one .blend from many angles (Workbench + Eevee) to check geometry.
blender -b <file.blend> -P art_src/inspect.py -- <outdir> <prefix> [dist]"""
import sys, math, os
import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT, PREFIX = ARGS[0], ARGS[1]
DIST = float(ARGS[2]) if len(ARGS) > 2 else 1.6
sc = bpy.context.scene
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
ctr = sum(pts, Vector()) / len(pts)
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_cavity = True; sh.cavity_type = 'BOTH'
sh.show_object_outline = False
sc.render.resolution_x, sc.render.resolution_y = 900, 700
sc.view_settings.view_transform = 'Standard'
w = bpy.data.worlds.new("W"); sc.world = w
cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = 50
cam = bpy.data.objects.new("Cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
tgt = bpy.data.objects.new("T", None); sc.collection.objects.link(tgt); tgt.location = ctr
tc = cam.constraints.new('TRACK_TO'); tc.target = tgt; tc.track_axis = 'TRACK_NEGATIVE_Z'; tc.up_axis = 'UP_Y'
views = {
    "front": (0, 1, 0.15), "back": (0, -1, 0.15), "left": (-1, 0, 0.15), "right": (1, 0, 0.15),
    "fl": (-0.7, 0.7, 0.5), "fr": (0.7, 0.7, 0.5), "bl": (-0.7, -0.7, 0.5), "br": (0.7, -0.7, 0.5),
    "top": (0.05, 0.05, 1), "low": (0.6, -0.6, -0.15),
}
for name, d in views.items():
    v = Vector(d).normalized()
    cam.location = ctr + v * DIST
    sc.render.filepath = os.path.join(OUT, f"{PREFIX}_{name}.png")
    bpy.ops.render.render(write_still=True)
print("INSPECT DONE")

"""Close render of one skid corner (review helper)."""
import sys, os, math, bpy
from mathutils import Vector
A = sys.argv[sys.argv.index("--") + 1:]
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "render_building.py")).read().split("eye = 1.7")[0].replace("ARGS = sys.argv[sys.argv.index(\"--\") + 1:]", "ARGS = A"))
cam.location = Vector((lo.x - 0.55, lo.y - 0.75, 0.42)); tgt.location = Vector((lo.x + 0.12, lo.y + 0.12, 0.1)); cam_d.lens = 50
sc.render.filepath = os.path.join(A[0], A[1] + "_corner.png"); bpy.ops.render.render(write_still=True)

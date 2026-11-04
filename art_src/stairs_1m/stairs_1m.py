"""Stairs 1 m (scenes/stairs_1m.tscn) - 2 x 2 m, rise 1 m toward Blender +Y (Godot -Z), origin at the CENTRE of its
2 x 1 x 2 box. Two side stringers, five treads (rise 0.2, run 0.4) welded between them, a handrail on posts each
side. Faces on +/-1 so it tiles with the foundations; the handrails stand above the block."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector

kit.begin(kit.out_dir())
HW, ST = 1.0, 0.03
xs = HW - ST / 2
# stringer: a band under the nosing line z = -0.3 + 0.5 (y + 1), clipped to the block
U0 = -0.28                                    # upper line at y = -1 (nosing + 2 cm)
pts = [(-1.0, -0.5), (-0.84, -0.5), (1.0, 0.42), (1.0, 0.5), (0.56, 0.5), (-1.0, U0)]
for s in (-1, 1):
    profile(f"Stringer{s}", pts, (s * xs, 0, 0), (1, 0, 0), ST, SEC, up=(0, 0, 1), bevel=0.003)
part("Stringer", "stringer: carries the treads, butts the next foundation", "ground", "ground")
IW = 2 * (HW - ST)
for k in range(5):
    zt = -0.5 + 0.2 * (k + 1)
    tr = box(f"Tread{k}", (IW, 0.4, 0.04), (0, -1.0 + 0.4 * k + 0.2, zt - 0.02), PRI, bevel=0.004)
    for s in (-1, 1):
        box_weld(f"TreadWeld{k}{s}_", tr, bpy.data.objects[f"Stringer{s}"])
    box(f"Nosing{k}", (IW - 0.02, 0.03, 0.01), (0, -1.0 + 0.4 * k + 0.02, zt - 0.003), HAZ, bevel=0.0)
part("Tread", "tread: what you step on", "Stringer", "welded")
part("Nosing", "nosing strip: shows the step edge", "Tread", "inset")
# handrail: posts welded to the treads near each stringer, a rail through their tops along the slope
for s in (-1, 1):
    x = s * (HW - ST - 0.05)
    tops = []
    for k in (0, 2, 4):
        zt = -0.5 + 0.2 * (k + 1)
        y = -1.0 + 0.4 * k + 0.2
        cyl(f"RailPost{s}{k}", 0.02, 0.9, (x, y, zt + 0.45), BARE, seg=12, bevel=0.0)
        weld_ring(f"RailPostWeld{s}{k}", (x, y, zt + WELD_R * 0.5), 0.02 + WELD_R * 0.4)
        tops.append(Vector((x, y, zt + 0.9)))
    d = (tops[-1] - tops[0]).normalized()
    pipe(f"Rail{s}", [tuple(tops[0] - d * 0.08), tuple(tops[-1] + d * 0.08)], 0.022, BARE, fillet=0.0)
part("RailPost", "handrail post", "Tread", "welded")
part("Rail", "handrail", "RailPost", "inset")
kit.finish("SM_Stairs1m")

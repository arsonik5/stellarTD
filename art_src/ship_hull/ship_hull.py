"""Ship Hull (scenes/ship_hull.tscn) - 2 m armour block, origin at the CENTRE. A welded frame (edge beams between
corner nodes) with one armour panel set into each of its six openings, bolted round its edge. Outer faces sit on
+/-1.0 (the frame's corner nodes) so blocks butt together cleanly; the panels sit 2 cm in."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Matrix, Vector

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.15
H, B = 1.0, 0.16
ship_frame(H, B)
O = 2 * (H - B / 2 - (B - 0.04) / 2)              # frame opening between the beams
T = 0.04                                           # armour panel thickness
for ax in range(3):
    for sgn in (-1, 1):
        n = [0.0, 0.0, 0.0]; n[ax] = sgn
        up = (0, 0, 1) if ax != 2 else (0, 1, 0)
        c = [0.0, 0.0, 0.0]; c[ax] = sgn * (H - 0.02 - T)
        # corners clipped so the panel stops at the corner nodes instead of running into them
        plate(f"Armour{ax}{sgn}", tuple(c), tuple(n), O, O, t=T, clip=0.045, up=up, bolts_on=False, bevel=0.006)
        M = Matrix.Translation(Vector(c)) @ basis(Vector(n), up)
        k = 0
        for side in range(4):                      # bolts round the edge, into the beams' inner flanges
            for i in range(5):
                t_ = -O / 2 + 0.12 + (O - 0.24) * i / 4
                u, v = {0: (t_, -O / 2 + 0.035), 1: (t_, O / 2 - 0.035), 2: (-O / 2 + 0.035, t_), 3: (O / 2 - 0.035, t_)}[side]
                if side >= 2 and i in (0, 4):
                    continue
                p = M @ Vector((u, v, T + 0.007))
                cyl(f"ArmourBolt{ax}{sgn}_{k}", 0.012, 0.014, (0, 0, 0), BARE, seg=6, bevel=0.0,
                    rot=Matrix.Translation(p) @ basis(Vector(n), up))
                k += 1
part("Armour", "armour panel: the hull block's skin, set into the frame opening", "FrameBeam", "bolted")
kit.finish("SM_ShipHull")

"""Ramp 1 m (scenes/ramp_1m.tscn) - 2 x 2 m, rises 1 m toward Blender +Y (Godot -Z), origin at the CENTRE of its
2 x 1 x 2 box: low edge at y=-1, z=-0.5, high edge at y=+1, z=+0.5. Two triangular side stringers carry a sloped
deck with anti-slip cleats; a back plate closes the high end. Tiles with the foundations (faces on +/-1)."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Matrix

kit.begin(kit.out_dir())
HW, ST, DT = 1.0, 0.12, 0.03                 # half width, stringer thickness, deck thickness
xs = HW - ST / 2
for s in (-1, 1):
    profile(f"Stringer{s}", [(-1.0, -0.5), (1.0, -0.5), (1.0, 0.5)], (s * xs, 0, 0), (1, 0, 0), ST, SEC, up=(0, 0, 1), bevel=0.006)
part("Stringer", "side stringer: carries the deck, butts the next foundation", "ground", "ground")
IW = 2 * (HW - ST)                           # between the stringers
slope = math.atan2(1.0, 2.0)
dz = DT / math.cos(slope)
profile("Deck", [(-1.0, -0.5), (1.0, 0.5), (1.0, 0.5 - dz), (-1.0 + 2 * dz, -0.5)], (0, 0, 0), (1, 0, 0), IW, PRI, up=(0, 0, 1), bevel=0.004)
part("Deck", "ramp deck: what you walk and drive up", "Stringer", "inset")
back = box("Back", (IW, 0.03, 1.0 - dz), (0, 1.0 - 0.015, -0.5 + (1.0 - dz) / 2), SEC, bevel=0.004)
for s in (-1, 1):
    box_weld(f"BackWeld{s}_", back, bpy.data.objects[f"Stringer{s}"])
part("Back", "back plate: closes the high end, stiffens the stringers", "Stringer", "welded", joins=("Deck",))
# anti-slip cleats across the deck, set into it
for i in range(7):
    t = (i + 0.5) / 7
    y, z = -1.0 + 2.0 * t, -0.5 + 1.0 * t
    box(f"Cleat{i}", (IW - 0.1, 0.03, 0.012), (0, y, z), SEC, bevel=0.0, rot=Matrix.Rotation(slope, 4, 'X'))
part("Cleat", "anti-slip cleat", "Deck", "inset")
kit.finish("SM_Ramp1m")

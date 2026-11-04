"""Frame Foundation 2 m (scenes/frame_2m.tscn) - 2.0 x 2.0 x 2.0 open steel frame, origin at its CENTRE, outer faces on
+/-1.0 so it tiles with every foundation. Four columns on bolted base plates, I-beams round the top carrying a deck,
one diagonal brace per side bolted to gusset plates welded to the columns. The cosmetic 'beams' piece."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector, Matrix

kit.begin(kit.out_dir())
HW, Z0, Z1 = 1.0, -1.0, 1.0
C = 0.12                                   # column size
CC = HW - C / 2                            # column centre
BT = 0.14                                  # top beam height
PT = 0.02                                  # base plate thickness
for sx in (-1, 1):
    for sy in (-1, 1):
        plate(f"Base_{sx}_{sy}", (sx * (HW - 0.1), sy * (HW - 0.1), Z0), (0, 0, 1), 0.2, 0.2, t=PT, clip=0.03, mat=SEC,
              up=(0, 1, 0), bolts_on=False)
        for k, (u, v) in enumerate(((0.835, 0.835), (0.835, 0.94), (0.94, 0.835))):
            cyl(f"BaseBolt_{sx}_{sy}_{k}", 0.011, 0.012, (sx * u, sy * v, Z0 + PT + 0.006), BARE, seg=6, bevel=0.0)
        col = box(f"Column_{sx}_{sy}", (C, C, Z1 - BT - Z0 - PT), (sx * CC, sy * CC, (Z0 + PT + Z1 - BT) / 2), SEC, bevel=0.006)
        box_weld(f"ColumnWeld_{sx}_{sy}_", col, bpy.data.objects[f"Base_{sx}_{sy}"])
part("Base", "column base plate: bolted to the ground or the block below", "ground", "ground")
part("Column", "column: carries the top beams", "Base", "welded")
# top I-beams: X beams run the full width over the columns, Y beams between them
def ibeam(name, length, axis, centre):
    w, fl, wb = C, 0.014, 0.012
    pts = [(-w / 2, -BT / 2), (w / 2, -BT / 2), (w / 2, -BT / 2 + fl), (wb / 2, -BT / 2 + fl), (wb / 2, BT / 2 - fl),
           (w / 2, BT / 2 - fl), (w / 2, BT / 2), (-w / 2, BT / 2), (-w / 2, BT / 2 - fl), (-wb / 2, BT / 2 - fl),
           (-wb / 2, -BT / 2 + fl), (-w / 2, -BT / 2 + fl)]
    n = (1, 0, 0) if axis == 'X' else (0, 1, 0)
    return profile(name, pts, centre, n, length, SEC, up=(0, 0, 1), bevel=0.003)
ZB = Z1 - BT / 2
for s in (-1, 1):
    bx = ibeam(f"BeamX{s}", 2.0, 'X', (0, s * CC, ZB))
    for t in (-1, 1):
        box_weld(f"BeamXWeld{s}{t}_", bpy.data.objects[f"Column_{t}_{s}"], bx)
for s in (-1, 1):
    by = ibeam(f"BeamY{s}", 2.0 - 2 * C - 0.024, 'Y', (s * CC, 0, ZB))   # stops at its end plates
part("BeamX", "top beam: spans the columns, carries the deck", "Column", "welded")
part("BeamY", "top beam: ties the X beams, carries the deck", "BeamYEnd", "welded")
for s in (-1, 1):                          # Y beams bolted to the X beams' webs through end plates
    for t in (-1, 1):
        y = t * (CC - C / 2 - 0.006)
        box(f"BeamYEnd{s}{t}", (C, 0.012, BT - 0.03), (s * CC, y, ZB), SEC, bevel=0.0)
        for dz in (-0.035, 0.035):
            cyl(f"BeamYEndBolt{s}{t}{dz}", 0.01, 0.012, (s * CC + 0.03, y - t * 0.012, ZB + dz), BARE, seg=6,
                axis=('-Y' if t > 0 else 'Y'), bevel=0.0)
part("BeamYEnd", "end plate: welded on the Y beam, bolted to the X beam", "BeamX", "bolted")
for s in (-1, 1):
    for t in (-1, 1):
        weld(f"BeamYEndWeld{s}{t}", [(s * CC - 0.006 - WELD_R * 0.6, t * (CC - C / 2 - 0.012 - WELD_R * 0.6), ZB - 0.05),
                                     (s * CC - 0.006 - WELD_R * 0.6, t * (CC - C / 2 - 0.012 - WELD_R * 0.6), ZB + 0.05)])
deck_plate("Deck", 2.0 - 2 * C, 2.0 - 2 * C, Z1, tread=True)
part("Deck", "grating deck: what you walk and build on", "BeamX", "inset", joins=("BeamY", "BeamYEnd"))
# side braces: gusset plates welded to the columns, a flat bar bolted across them, one per side
G = 0.12
for side, (ax, s) in enumerate(((0, -1), (0, 1), (1, -1), (1, 1))):
    flip = 1 if side % 2 == 0 else -1
    ends = []
    for k, (t, zg) in enumerate(((-1, Z0 + PT + 0.12), (1, Z1 - BT - 0.12))):
        t *= flip
        if ax == 0:                         # side at x = s * CC, gussets on the columns' inner faces along Y
            gp = Vector((s * CC, t * (CC - C / 2 - G / 2), zg))
            size = (0.012, G, G)
        else:
            gp = Vector((t * (CC - C / 2 - G / 2), s * CC, zg))
            size = (G, 0.012, G)
        g = box(f"Gusset{side}{k}", size, tuple(gp), SEC, bevel=0.0)
        col = bpy.data.objects[f"Column_{t if ax == 1 else s}_{s if ax == 1 else t}"]
        box_weld(f"GussetWeld{side}{k}_", g, col)
        ends.append(gp)
    out = Vector((s, 0, 0)) if ax == 0 else Vector((0, s, 0))
    a, b = ends[0] + out * 0.012, ends[1] + out * 0.012
    d = b - a
    rot = d.to_track_quat('Z', 'X' if ax == 1 else 'Y').to_matrix().to_4x4()
    box(f"Brace{side}", (0.012 if ax == 0 else 0.07, 0.07 if ax == 0 else 0.012, d.length + 0.08), (0, 0, 0), SEC,
        bevel=0.0, rot=Matrix.Translation((a + b) / 2) @ rot)
    for k, e in enumerate(ends):
        p = e + out * 0.018 + out * 0.006
        cyl(f"BraceBolt{side}{k}", 0.01, 0.012, tuple(p), BARE, seg=6, axis=(('+' if s > 0 else '-') + ('X' if ax == 0 else 'Y')),
            bevel=0.0)
part("Gusset", "gusset plate: the brace bolts to it", "Column", "welded")
part("Brace", "diagonal brace: keeps the frame square", "Gusset", "bolted")
kit.finish("SM_Frame2m")

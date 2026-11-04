"""Ship Core (scenes/ship_core.tscn) - 2 m block, origin at the CENTRE. The reactor cell: the same welded frame as
the hull, end plates top and bottom carry the reactor column between their mounts, four tie rods hold the mounts
together, the containment rings spin round the glowing column. Each side has two armour panels with a glass slot
between them so you see the reactor. Faces stay within +/-1.0."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Matrix, Vector

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.15
H, B = 1.0, 0.16
ship_frame(H, B)
O = 2 * (H - B / 2 - (B - 0.04) / 2)             # frame opening between the beams (1.72)
T = 0.04
# end plates (top/bottom) and side panels with a glass slot
for sz in (-1, 1):
    plate(f"EndPlate{sz}", (0, 0, sz * (H - 0.02 - T)), (0, 0, sz), O, O, t=T, clip=0.045, up=(0, 1, 0), bolts_on=False)
    for i in range(8):
        a = math.pi / 8 + i * math.pi / 4
        p = Vector((math.cos(a) * 0.78, math.sin(a) * 0.78, sz * (H - 0.02 + 0.007)))
        cyl(f"EndPlateBolt{sz}{i}", 0.012, 0.014, (0, 0, 0), BARE, seg=6, bevel=0.0,
            rot=Matrix.Translation(p) @ basis(Vector((0, 0, sz))))
part("EndPlate", "end plate: closes the cell, carries a reactor mount", "FrameBeam", "bolted")
SW = 0.34                                        # glass slot width
PW = (O - SW) / 2
for a, sgn in ((0, -1), (0, 1), (1, -1), (1, 1)):
    n = [0.0, 0.0, 0.0]; n[a] = sgn
    o = 1 - a
    for u in (-1, 1):
        c = [0.0, 0.0, 0.0]; c[a] = sgn * (H - 0.02 - T); c[o] = u * (SW / 2 + PW / 2)
        plate(f"Side{a}{sgn}{u}", tuple(c), tuple(n), PW, O, t=T, clip=0.045, bolt_inset=0.06)
    size = [0.0, 0.0, O]; size[a] = 0.02; size[o] = SW
    c = [0.0, 0.0, 0.0]; c[a] = sgn * (H - 0.02 - T / 2)
    box(f"Slot{a}{sgn}", tuple(size), tuple(c), GLASS, bevel=0.0)
part("Side", "side armour panel", "FrameBeam", "bolted")
part("Slot", "glass slot: you see the reactor through it", "Side", "inset", joins=("FrameBeam", "EndPlate"))
# reactor: mounts on the end plates, the column between them, tie rods, the spinning containment rings
MI = H - 0.02 - T                               # inner face of the end plates
for sz in (-1, 1):
    cyl(f"CoreMount{sz}", 0.42, 0.08, (0, 0, sz * (MI - 0.04)), SEC, seg=32)
part("CoreMount", "reactor mount: holds the column's end", "EndPlate", "bolted")
for sz in (-1, 1):
    for i in range(8):
        a = math.pi / 8 + i * math.pi / 4
        cyl(f"CoreMountBolt{sz}{i}", 0.011, 0.012, (math.cos(a) * 0.3, math.sin(a) * 0.3, sz * (MI - 0.08 - 0.006)),
            BARE, seg=6, axis=('-Z' if sz > 0 else 'Z'), bevel=0.0)
CL = 2 * (MI - 0.08)
cyl("Core", 0.26, CL, (0, 0, 0), HEAT, seg=24, bevel=0.0)
part("Core", "reactor column: the glow is the reaction", "CoreMount", "inset")
for z in (-0.5, -0.17, 0.17, 0.5):
    cyl(f"Ring{z}", 0.33, 0.06, (0, 0, z), BARE, seg=32, bevel=0.006)
part("Ring", "containment ring: spins round the column", "Core", "pivot")
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    x, y = math.cos(a) * 0.38, math.sin(a) * 0.38
    cyl(f"Strut{k}", 0.03, CL, (x, y, 0), SEC, seg=10)
    for sz in (-1, 1):                                                    # tie rods nutted against the mounts
        cyl(f"StrutNut{k}{sz}", 0.05, 0.035, (x, y, sz * (MI - 0.08 - 0.0175)), BARE, seg=6,
            axis=('-Z' if sz > 0 else 'Z'), bevel=0.003)
part("Strut", "tie rod: holds the two mounts together against the reactor's push", "CoreMount", "inset")
assign("Rings", "Ring")
kit.finish("SM_ShipCore", anims=[spin("Rings", 2, seconds=3.0)])

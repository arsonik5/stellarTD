"""Ship Thruster (scenes/ship_thruster.tscn) - origin at the CENTRE, 1.6 m long along Blender Y.
Mount plate at +Y (Godot -Z, toward the ship), nozzle bell opens to -Y (Godot +Z): exhaust goes backward.
Chamber flanged and bolted to the mount plate; four fuel lines come through the mount from the ship and run down to the
injector manifold at the throat; the bell is welded to the throat, cooling channels run down it to the lip.
Bell is a thick-walled lathe so the glowing throat is visible inside."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from mathutils import Matrix, Vector
from kit import *

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.15
# mount: square plate + bolts (attaches to the ship grid)
box("Mount", (1.3, 0.1, 1.3), (0, 0.75, 0), SEC, bevel=0.012)
part("Mount", "mount plate: bolts the thruster to the ship's grid", "ground", "ground")
for sx in (-1, 1):
    for sz in (-1, 1):
        cyl(f"MountBolt{sx}{sz}", 0.04, 0.03, (sx * 0.55, 0.685, sz * 0.55), BARE, seg=6, axis='-Y', bevel=0.0)
# chamber: flanged and bolted to the mount
cyl("ChamberFlange", 0.56, 0.03, (0, 0.685, 0), SEC, seg=40, axis='Y')
part("ChamberFlange", "chamber flange: bolts the chamber to the mount plate", "Mount", "bolted")
bolts("ChamberFlangeBolt", (0, 0.67, 0), '-Y', 0.525, 12, r=0.011, h=0.012, start=math.pi / 12)
C0, C1 = 0.2, 0.67
cyl("Chamber", 0.48, C1 - C0, (0, (C0 + C1) / 2, 0), PRI, seg=32, axis='Y', bevel=0.012)
part("Chamber", "combustion chamber", "ChamberFlange", "welded")
weld_ring("ChamberWeld", (0, C1 - WELD_R * 0.5, 0), 0.48 + WELD_R * 0.4, 'Y')
for y in (0.3, 0.6):
    cyl(f"ChamberBand{y}", 0.5, 0.05, (0, y, 0), SEC, seg=32, axis='Y', bevel=0.006)
part("ChamberBand", "reinforcing band round the chamber", "Chamber", "inset")
# throat, injector manifold, bell
T0 = 0.09
cyl("Throat", 0.36, C0 - T0, (0, (C0 + T0) / 2, 0), SEC, seg=32, axis='Y')
part("Throat", "nozzle throat", "Chamber", "welded")
weld_ring("ThroatWeld", (0, C0 - WELD_R * 0.5, 0), 0.36 + WELD_R * 0.4, 'Y')
MY = 0.1
torus("Manifold", 0.39, 0.03, (0, MY, 0), BARE, Matrix.Rotation(math.pi / 2, 4, 'X'), major=40, minor=8)
part("Manifold", "injector manifold: feeds fuel in at the throat and down the bell's cooling channels", "Throat", "clamped")
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    c, s_ = math.cos(a), math.sin(a)
    pipe(f"FuelLine{k}", [(c * 0.53, 0.72, s_ * 0.53), (c * 0.53, 0.19, s_ * 0.53), (c * 0.415, MY, s_ * 0.415)], 0.025, BARE, fillet=0.05)
part("FuelLine", "fuel line: from the ship, through the mount, down to the injector manifold", "Mount", "through",
     joins=("Manifold", "ChamberFlange"))
lathe("Bell", [(0.34, 0.0), (0.6, -0.6), (0.6, -0.64), (0.54, -0.64), (0.29, -0.04), (0.29, 0.0)],
      (0, T0, 0), BARE, seg=40, axis='Y', mats=[BARE, BARE, BARE, HEAT, HEAT, BARE])
part("Bell", "exhaust bell", "Throat", "welded")
weld_ring("BellWeld", (0, T0 - WELD_R * 0.5, 0), 0.34 + WELD_R * 0.4, 'Y')
cyl("Glow", 0.29, 0.02, (0, T0 - 0.01, 0), HEAT, seg=32, axis='Y', bevel=0.0)
part("Glow", "hot throat (glow)", "Bell", "inset", joins=("Throat",))
tube("BellLip", 0.62, 0.56, 0.04, (0, T0 - 0.62, 0), SEC, seg=40, axis='Y', bevel=0.004)
part("BellLip", "bell lip: stiffens the bell's mouth", "Bell", "inset")
nr = Vector((0.917, 0.398))                                  # outward normal of the bell's outer line in (r, y)
for k in range(12):
    a = k * math.pi / 6
    r0, y0 = 0.34 + 0.26 * 0.06 + nr.x * 0.0125, T0 - 0.6 * 0.06 + nr.y * 0.0125   # starts just below the weld
    r1, y1 = 0.6 + nr.x * 0.0125, T0 - 0.6 + nr.y * 0.0125
    p0 = Vector((math.cos(a) * r0, y0, math.sin(a) * r0))
    p1 = Vector((math.cos(a) * r1, y1, math.sin(a) * r1))
    d = p1 - p0
    rot = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    box(f"Rib{k}", (0.025, 0.025, d.length), (0, 0, 0), SEC, bevel=0.0, rot=Matrix.Translation((p0 + p1) / 2) @ rot)
part("Rib", "cooling channel down the bell", "Bell", "inset", joins=("Manifold", "BellLip"))
kit.finish("SM_ShipThruster")

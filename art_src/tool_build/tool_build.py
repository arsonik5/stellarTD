"""Build Tool (first-person viewmodel) - the construction projector. Origin = the hand on the grip, Blender +Y forward.
A body on the grip carries a projector barrel bolted to its nose; three alignment rings run on the barrel and turn
(at different speeds, the outer one the other way) while you are building ('Working' loop); the lens at the front
projects the placement grid. A side screen shows the selected building."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector, Matrix

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.15
kit.WEAR_SCALE = 0.12                                      # wear at tool size (see kit.WEAR_SCALE)
grip = [(-0.017, -0.11), (0.017, -0.11), (0.02, 0.0), (0.016, 0.03), (-0.024, 0.03), (-0.026, 0.0)]
profile("Grip", grip, (0, 0, 0), (1, 0, 0), 0.034, RUB, up=(0, 0, 1), bevel=0.003)
part("Grip", "grip: the hand holds the tool here", "ground", "ground")
MZ = 0.06
body = [yring(squircle(0.032, 0.035, 3.0), -0.08, MZ), yring(squircle(0.04, 0.042, 3.8), -0.04, MZ),
        yring(squircle(0.04, 0.042, 3.8), 0.06, MZ), yring(squircle(0.034, 0.036, 2.4), 0.09, MZ)]
loft("Body", body, PRI, bevel=0.003)
part("Body", "tool body: power cell and projector driver inside", "Grip", "inset")
box("SideScreen", (0.004, 0.06, 0.035), (-0.04 - 0.001, 0.0, MZ), STAT, bevel=0.0)
part("SideScreen", "side screen: shows the selected building", "Body", "inset")
box("TopRail", (0.014, 0.1, 0.008), (0, 0.0, MZ + 0.042 + 0.003), SEC, bevel=0.002)
part("TopRail", "top rail: sight line for aiming the projector", "Body", "inset")
cyl("Barrel", 0.024, 0.082, (0, 0.098 + 0.041, MZ), SEC, seg=24, axis="Y", bevel=0.002)
part("Barrel", "projector barrel", "BarrelFlange", "welded")
cyl("BarrelFlange", 0.032, 0.008, (0, 0.09 + 0.004, MZ), BARE, seg=24, axis='Y', bevel=0.0)
part("BarrelFlange", "barrel flange: bolts the barrel to the body's nose", "Body", "bolted")
bolts("BarrelFlangeBolt", (0, 0.098, MZ), '+Y', 0.028, 4, r=0.003, h=0.003, start=math.pi / 4)
weld_ring("BarrelWeld", (0, 0.098 + WELD_R * 0.3, MZ), 0.024 + WELD_R * 0.3, 'Y', r=0.002)
for k, (y, r) in enumerate(((0.12, 0.036), (0.145, 0.042), (0.17, 0.036))):
    with group(f"Ring{k}"):
        tube(f"Ring{k}Band", r, 0.024, 0.012, (0, y, MZ), SEC, seg=32, axis='Y', bevel=0.0)
        tube(f"Ring{k}Light", r + 0.0005, r - 0.004, 0.003, (0, y, MZ), STAT, seg=32, axis='Y', bevel=0.0)
        box(f"Ring{k}Lug", (0.006, 0.008, 0.006), (r + 0.002, y, MZ), HAZ, bevel=0.0)
    part(f"Ring{k}Band", "alignment ring: turns on the barrel while projecting", "Barrel", "pivot")
    part(f"Ring{k}Light", "ring light", f"Ring{k}Band", "inset")
    part(f"Ring{k}Lug", "index lug: shows the ring turning", f"Ring{k}Band", "inset")
cyl("Lens", 0.02, 0.006, (0, 0.18 + 0.003, MZ), GLASS, seg=24, axis='Y', bevel=0.0)
part("Lens", "projector lens", "Barrel", "inset")
cyl("LensGlow", 0.014, 0.002, (0, 0.18 - 0.0005, MZ), STAT, seg=24, axis='Y', bevel=0.0)
part("LensGlow", "emitter behind the lens", "Barrel", "inset", joins=("Lens",))
kit.finish("SM_BuildTool", pivots={f"Ring{k}": (0, y, MZ) for k, y in enumerate((0.12, 0.145, 0.17))}, bake_res=2048,
           anims=[spin("Ring0", 1, seconds=2.0), spin("Ring1", 1, seconds=2.0, turns=-1.0), spin("Ring2", 1, seconds=1.0)])

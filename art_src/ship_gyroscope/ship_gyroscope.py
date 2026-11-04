"""Ship Gyroscope (scenes/ship_gyroscope.tscn, sphere r 0.8) - origin at the CENTRE.
A gimbal: cradle frame, two nested rings, a glowing core. Rings are separate groups so code can spin them later."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Matrix

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.15
# cradle: base plate + two pylons holding the outer ring on the X axis
box("Base", (1.6, 0.7, 0.1), (0, 0, -0.75), SEC, bevel=0.012)
box("BaseTop", (1.58, 0.6, 0.04), (0, 0, -0.68), PRI, bevel=0.006)
for s in (-1, 1):
    # pylon: wide foot narrowing to a rounded head around the bearing; welded and bolted to the base
    prof = [(-0.2, -0.66), (0.2, -0.66), (0.11, -0.08), (0.1, 0.0), (0.07, 0.07), (0.0, 0.1), (-0.07, 0.07), (-0.1, 0.0), (-0.11, -0.08)]
    profile(f"Pylon{s}", prof, (s * 0.74, 0, 0), (1, 0, 0), 0.08, SEC, up=(0, 0, 1), bevel=0.01)
    for sd in (-1, 1):
        weld(f"PylonWeld{s}{sd}", [(s * 0.74 + sd * (0.04 + WELD_R * 0.6), -0.19, -0.66 + WELD_R), (s * 0.74 + sd * (0.04 + WELD_R * 0.6), 0.19, -0.66 + WELD_R)])
    for sy in (-1, 1):
        cyl(f"PylonBolt{s}{sy}", 0.012, 0.014, (s * 0.74, sy * 0.25, -0.653), BARE, seg=6, bevel=0.0)
    bolts(f"BearingBolt{s}", (s * 0.76, 0, 0), ('+X' if s > 0 else '-X'), 0.075, 4, r=0.01, h=0.012, start=math.pi / 4)
    cyl(f"Bearing{s}", 0.1, 0.1, (s * 0.71, 0, 0.0), BARE, seg=16, axis='X')
with group("RingOuter"):
    # outer ring in the XZ plane, pinned to the pylons on the X axis
    torus("Outer", 0.6, 0.05, (0, 0, 0), PRI, Matrix.Rotation(math.pi / 2, 4, 'X'), major=40, minor=8)
    for s in (-1, 1):
        cyl(f"OuterPin{s}", 0.045, 0.12, (s * 0.65, 0, 0), BARE, seg=12, axis='X')
        cyl(f"InnerBearing{s}", 0.055, 0.05, (0, 0, s * 0.555), SEC, seg=12)
with group("RingInner"):
    # inner ring in the YZ plane, pinned to the outer ring on the Z axis; the core spins inside it
    torus("Inner", 0.48, 0.04, (0, 0, 0), BARE, Matrix.Rotation(math.pi / 2, 4, 'Y'), major=36, minor=8)
    for s in (-1, 1):
        cyl(f"Axle{s}", 0.03, 0.315, (0, 0, s * 0.3875), SEC, seg=10)
    prof = [(0.0, -0.24)] + [(math.cos(a) * 0.25, math.sin(a) * 0.24) for a in [math.radians(d) for d in range(-75, 76, 15)]] + [(0.0, 0.24)]
    mats = []
    for i in range(len(prof)):
        mid = (prof[i][1] + prof[(i + 1) % len(prof)][1]) / 2
        mats.append(HEAT if abs(mid) < 0.07 else SEC)
    lathe("Core", prof, (0, 0, 0), SEC, seg=24, mats=mats)
    tube("CoreBand", 0.255, 0.2, 0.03, (0, 0, 0.085), BARE, seg=24, bevel=0.0)
    tube("CoreBand2", 0.255, 0.2, 0.03, (0, 0, -0.085), BARE, seg=24, bevel=0.0)
part("Base", "base plate: mounts the gyro to the ship deck", "ground", "ground")
part("BaseTop", "top plate of the base: the pylons are welded to it", "Base", "inset")
part("Pylon", "pylon: carries the outer ring's bearing", "BaseTop", "welded")
part("Bearing", "outer bearing: the outer ring's pins turn in it", "Pylon", "inset")
part("Outer", "outer gimbal ring", "OuterPin", "inset")
part("OuterPin", "outer ring pin: turns in the pylon bearing", "Bearing", "pivot", joins=("Pylon",))
part("InnerBearing", "inner bearing on the outer ring: the inner ring's axles turn in it", "Outer", "inset")
part("Inner", "inner gimbal ring", "Axle", "inset")
part("Axle", "inner ring axle: turns in the outer ring's bearing, carries the rotor", "InnerBearing", "pivot", joins=("Core",))
part("Core", "rotor: the spinning mass that holds the ship steady", "Axle", "inset")
part("CoreBand", "rotor band", "Core", "inset")
kit.finish("SM_ShipGyroscope", parents={"RingInner": "RingOuter"},
           anims=[spin("RingOuter", 0, seconds=6.0), spin("RingInner", 2, seconds=2.0)])

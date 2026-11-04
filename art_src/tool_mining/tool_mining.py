"""Mining Tool (first-person viewmodel, scripts/player/player.gd ToolHolder) - a cordless rock drill.
Origin = the hand on the grip. Blender +Y = forward (Godot -Z, the camera's look direction), Z up. Real size (~0.45 m).
A lofted motor housing sits on the grip; the battery slides onto the grip's foot; the motor drives the chuck through
the front bearing; the auger bit is held in the chuck and spins with it ('Working' loop, the _Bit mesh).
Vent slots over the motor, a charge strip on top, the trigger in front of the grip."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector, Matrix

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.2
# grip: angled handle, the hand holds it (origin)
GA = math.radians(14)                                      # rake of the grip (top leans forward)
grip = [(-0.017, -0.11), (0.017, -0.11), (0.02, 0.0), (0.016, 0.03), (-0.024, 0.03), (-0.026, 0.0)]
profile("Grip", [(y, z) for y, z in grip], (0, 0, 0), (1, 0, 0), 0.034, RUB, up=(0, 0, 1), bevel=0.003)
part("Grip", "grip: the hand holds the drill here", "ground", "ground")
# battery: slides onto the grip's foot, latched
box("Battery", (0.05, 0.085, 0.04), (0, 0.0, -0.11 - 0.02), SEC, bevel=0.004)
part("Battery", "battery pack: powers the motor, slides onto the grip", "Grip", "seated")
box("BatteryLatch", (0.02, 0.012, 0.012), (0, -0.0425 - 0.006, -0.12), BARE, bevel=0.0)
part("BatteryLatch", "battery latch: press to slide the pack off", "Battery", "inset")
box("BatteryGauge", (0.03, 0.004, 0.006), (0, 0.0425 + 0.002, -0.125), STAT, bevel=0.0)
part("BatteryGauge", "charge gauge on the battery", "Battery", "inset")
# motor housing: lofted along +Y over the grip
MZ = 0.065                                                 # housing axis height
rings = [yring(squircle(0.03, 0.035, 3.0), -0.07, MZ), yring(squircle(0.04, 0.045, 3.6), -0.03, MZ),
         yring(squircle(0.04, 0.045, 3.6), 0.07, MZ), yring(squircle(0.034, 0.036, 2.6), 0.11, MZ)]
loft("Housing", rings, PRI, bevel=0.003)
part("Housing", "motor housing: the motor and gearbox are inside", "Grip", "inset")
for side in (-1, 1):
    for k in range(4):
        box(f"Vent{side}{k}", (0.004, 0.02, 0.006), (side * 0.04, -0.02 + k * 0.022, MZ + 0.01), RUB, bevel=0.0)
part("Vent", "cooling slot: the motor breathes through it", "Housing", "inset")
box("ChargeStrip", (0.012, 0.06, 0.004), (0, 0.02, MZ + 0.045 - 0.001), STAT, bevel=0.0)
part("ChargeStrip", "charge / running light", "Housing", "inset")
box("Trigger", (0.012, 0.012, 0.03), (0, 0.025, 0.012), BARE, bevel=0.002, rot=Matrix.Rotation(-GA, 4, 'X'))
part("Trigger", "trigger: runs the motor", "Housing", "pivot", joins=("Grip",))
# front bearing housing, bolted to the housing's nose
cyl("Bearing", 0.03, 0.02, (0, 0.11 + 0.01, MZ), BARE, seg=24, axis='Y', bevel=0.002)
part("Bearing", "front bearing: carries the spindle", "Housing", "bolted")
bolts("BearingBolt", (0, 0.13, MZ), '+Y', 0.022, 4, r=0.003, h=0.003, start=math.pi / 4)
# spinning group: chuck and auger bit
with group("Bit"):
    cyl("Chuck", 0.022, 0.04, (0, 0.13 + 0.02, MZ), SEC, seg=24, axis='Y', bevel=0.002)
    for k in range(3):
        a = k * 2 * math.pi / 3
        box(f"ChuckJaw{k}", (0.006, 0.03, 0.003), (math.cos(a) * 0.0215, 0.15, MZ + math.sin(a) * 0.0215), RUB,
            bevel=0.0, rot=Matrix.Translation((0, 0, 0)) @ Matrix.Rotation(-a, 4, 'Y'))
    cyl("BitShank", 0.008, 0.2, (0, 0.17 + 0.1, MZ), BARE, seg=12, axis='Y', bevel=0.0)
    pts = []
    for i in range(61):                                     # one flute: a helix round the shank
        t = i / 60
        a = t * 2 * math.pi * 4
        pts.append((math.cos(a) * 0.011, 0.19 + t * 0.15, MZ + math.sin(a) * 0.011))
    pipe("BitFlute", pts, 0.0045, BARE, fillet=0.0, seg=6, bevel=0.0)
    cyl("BitTip", 0.01, 0.025, (0, 0.37 + 0.0125, MZ), BARE, seg=12, axis='Y', r2=0.0, bevel=0.0)
part("Chuck", "chuck: grips the bit, turned by the spindle", "Bearing", "pivot")
part("ChuckJaw", "chuck jaw groove", "Chuck", "inset")
part("BitShank", "bit shank: held in the chuck", "Chuck", "inset")
part("BitFlute", "auger flute: cuts and lifts the rock out of the bore", "BitShank", "inset")
part("BitTip", "carbide tip: the cutting point", "BitShank", "inset")
kit.finish("SM_MiningTool", pivots={"Bit": (0, 0.13, MZ)}, bake_res=512,
           anims=[spin("Bit", 1, seconds=0.25)])

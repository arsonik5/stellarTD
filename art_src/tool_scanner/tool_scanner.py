"""Scanner Tool (first-person viewmodel) - a handheld ore scanner. Origin = the hand on the grip, Blender +Y forward.
A flat body on the grip carries the screen (the scan result) on top; at the front a bearing carries the sensor dish,
which spins while scanning ('Working' loop, the _Dish mesh) with the probe at its centre; a comms antenna sends the
result to the HUD."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector, Matrix

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.2
grip = [(-0.017, -0.11), (0.017, -0.11), (0.02, 0.0), (0.016, 0.03), (-0.024, 0.03), (-0.026, 0.0)]
profile("Grip", grip, (0, 0, 0), (1, 0, 0), 0.034, RUB, up=(0, 0, 1), bevel=0.003)
part("Grip", "grip: the hand holds the scanner here", "ground", "ground")
MZ = 0.055
body = [yring(squircle(0.04, 0.026, 4.0), -0.07, MZ), yring(squircle(0.05, 0.03, 4.4), -0.03, MZ),
        yring(squircle(0.05, 0.03, 4.4), 0.08, MZ), yring(squircle(0.038, 0.026, 3.0), 0.11, MZ)]
loft("Body", body, PRI, bevel=0.003)
part("Body", "scanner body: the sensor electronics are inside", "Grip", "inset")
box("ScreenBezel", (0.07, 0.08, 0.006), (0, -0.02, MZ + 0.03 + 0.002), SEC, bevel=0.002)
part("ScreenBezel", "screen bezel", "Body", "inset")
box("Screen", (0.058, 0.066, 0.004), (0, -0.02, MZ + 0.03 + 0.005), STAT, bevel=0.0)
part("Screen", "screen: shows what the scan found", "ScreenBezel", "inset")
for k, x in enumerate((-0.02, 0.0, 0.02)):
    cyl(f"Button{k}", 0.005, 0.004, (x, 0.045, MZ + 0.03), (BARE, HAZ, BARE)[k], seg=10, bevel=0.0)
part("Button", "mode button", "Body", "inset")
cyl("Bearing", 0.026, 0.02, (0, 0.11 + 0.01, MZ), BARE, seg=24, axis='Y', bevel=0.002)
part("Bearing", "dish bearing", "Body", "bolted")
bolts("BearingBolt", (0, 0.13, MZ), '+Y', 0.019, 4, r=0.003, h=0.003, start=math.pi / 4)
with group("Dish"):
    cyl("DishHub", 0.016, 0.02, (0, 0.13 + 0.01, MZ), SEC, seg=16, axis='Y', bevel=0.0)
    prof = [(0.016, 0.0), (0.07, 0.03), (0.072, 0.036), (0.066, 0.036), (0.014, 0.007), (0.014, 0.0)]
    lathe("DishBowl", prof, (0, 0.15, MZ), PRI, seg=32, axis='Y')
    cyl("Probe", 0.004, 0.05, (0, 0.15 + 0.025, MZ), BARE, seg=8, axis='Y', bevel=0.0)
    cyl("ProbeTip", 0.007, 0.01, (0, 0.2 + 0.005, MZ), STAT, seg=10, axis='Y', bevel=0.0)
part("DishHub", "dish hub: turns in the bearing", "Bearing", "pivot")
part("DishBowl", "sensor dish: sweeps the ground for ore", "DishHub", "inset")
part("Probe", "probe: the sensor at the dish's focus", "DishHub", "inset")
part("ProbeTip", "probe head (lit while scanning)", "Probe", "inset")
# comms antenna: base on the body's top-left, whip angled back
cyl("AntennaBase", 0.008, 0.012, (0.03, 0.06, MZ + 0.0292 + 0.006), SEC, seg=12, bevel=0.0)
part("AntennaBase", "antenna base, screwed into the body", "Body", "inset")
pipe("Antenna", [(0.03, 0.06, MZ + 0.04), (0.03, 0.02, MZ + 0.12)], 0.0025, BARE, fillet=0.0)
part("Antenna", "comms antenna: sends the scan to the HUD", "AntennaBase", "inset")
kit.finish("SM_ScannerTool", pivots={"Dish": (0, 0.13, MZ)}, bake_res=512, anims=[spin("Dish", 1, seconds=1.2)])

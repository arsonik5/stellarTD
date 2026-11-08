"""Mining Tool (first-person viewmodel, scripts/player/player.gd ViewmodelTool) - a hand-held rock drill.
Origin = the hand on the grip. Blender +Y = forward (Godot -Z, the camera's look direction), Z up. Real size (~0.4 m).

What it does: the battery in the grip's foot powers the motor in the housing; the gearbox in the nose turns the
spindle, which turns the chuck and the long auger bit. The carbide tip breaks the rock, the flutes carry the cuttings
back out. The fins shed the heat of boring; the display on the rear cap faces the player (charge). In game the drill
pushes forward into the face while it bores (scripts/player/mining_tool_fx.gd): chips, dust, sparks on hard rock.
Chain: battery -> grip -> housing (motor) -> nose (gearbox) -> bearing -> chuck -> bit (core, flutes, tip).
Moving group 'Bit' spins about the nose axis ('Working' loop). Wear is baked at tool scale (kit.WEAR_SCALE)."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector, Matrix

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.15
kit.WEAR_SCALE = 0.12
MZ = 0.075                                                 # barrel / housing axis height above the hand

# --- grip: raked handle, rubber over-mould; the hand holds it (origin) -----------------------------------------
grip = [(-0.019, -0.13), (0.019, -0.13), (0.024, 0.0), (0.021, 0.045), (-0.03, 0.045), (-0.032, 0.0)]
profile("Grip", [(y, z) for y, z in grip], (0, 0, 0), (1, 0, 0), 0.036, RUB, up=(0, 0, 1), bevel=0.003)
part("Grip", "grip: the hand holds the cutter here", "ground", "ground")
box("Trigger", (0.012, 0.012, 0.03), (0, 0.027, 0.014), BARE, bevel=0.002, rot=Matrix.Rotation(-math.radians(14), 4, 'X'))
part("Trigger", "trigger: runs the motor and the emitter", "Housing", "pivot", joins=("Grip",))

# --- battery: slides onto the grip's foot, latched ---------------------------------------------------------------
BZ = -0.13 - 0.024
box("Battery", (0.058, 0.1, 0.048), (0, -0.004, BZ), SEC, bevel=0.005)
part("Battery", "battery pack: powers motor and emitter, slides onto the grip", "Grip", "seated")
for k in range(3):
    box(f"BatteryRib{k}", (0.062, 0.006, 0.03), (0, -0.034 + k * 0.03, BZ), SEC, bevel=0.0015)
part("BatteryRib", "grip rib: lets a gloved hand pull the pack off", "Battery", "inset")
box("BatteryLatch", (0.024, 0.008, 0.014), (0, -0.054 - 0.004, BZ + 0.008), BARE, bevel=0.002)
part("BatteryLatch", "battery latch: press to slide the pack off", "Battery", "seated")
box("BatteryGauge", (0.03, 0.003, 0.005), (0, -0.054 - 0.0012, BZ - 0.012), STAT, bevel=0.0)
part("BatteryGauge", "charge gauge on the battery", "Battery", "inset")

# --- housing: lofted motor body over the grip ---------------------------------------------------------------------
YR, YF = -0.13, 0.12                                       # rear face, front face
rings = [yring(squircle(0.031, 0.035, 2.8, seg=96), YR, MZ), yring(squircle(0.042, 0.048, 3.4, seg=96), -0.1, MZ),
         yring(squircle(0.044, 0.05, 3.6, seg=96), -0.06, MZ), yring(squircle(0.044, 0.05, 3.6, seg=96), 0.06, MZ),
         yring(squircle(0.038, 0.042, 3.0, seg=96), YF, MZ)]
loft("Housing", rings, PRI, bevel=0.002)
part("Housing", "motor housing: motor and gearbox inside, carries the barrel", "Grip", "inset")
for side in (-1, 1):
    for k in range(4):
        box(f"Vent{side}{k}", (0.004, 0.022, 0.006), (side * 0.044, -0.03 + k * 0.024, MZ + 0.01), RUB, bevel=0.0)
part("Vent", "cooling slot: the motor breathes through it", "Housing", "inset")
for k in range(5):
    box(f"TopFin{k}", (0.003, 0.09, 0.012), (-0.016 + k * 0.008, -0.01, MZ + 0.049 + 0.006 - 0.001), BARE, bevel=0.0)
part("TopFin", "motor heat sink: fins over the motor", "Housing", "inset")

# --- rear cap with the display the player looks at -----------------------------------------------------------------
box("RearCap", (0.05, 0.008, 0.054), (0, YR - 0.004, MZ), SEC, bevel=0.002)
part("RearCap", "rear cap: closes the housing, carries the display", "Housing", "bolted")
bolts("RearCapBolt", (0, YR - 0.008, MZ), '-Y', 0.029, 4, r=0.0028, h=0.003, start=math.pi / 4)
box("Display", (0.034, 0.002, 0.024), (0, YR - 0.008 - 0.0005, MZ + 0.002), STAT, bevel=0.0)
part("Display", "display: charge and emitter heat, faces the user", "RearCap", "inset")

# --- gearbox nose, heat-sink fins, front bearing ------------------------------------------------------------------
NR, NY0, NY1 = 0.03, YF, 0.19
cyl("Nose", NR, NY1 - NY0, (0, (NY0 + NY1) / 2, MZ), SEC, seg=48, axis='Y', bevel=0.002)
part("Nose", "gearbox nose: the reduction gears to the spindle are inside", "Housing", "welded")
weld_ring("NoseWeld", (0, NY0, MZ), NR, axis='Y')
for k in range(4):
    tube(f"Fin{k}", 0.044, NR + 0.0002, 0.004, (0, 0.132 + k * 0.014, MZ), BARE, seg=48, axis='Y', bevel=0.0008)
part("Fin", "gearbox heat sink: sheds the heat of boring rock", "Nose", "seated")
cyl("Bearing", 0.025, 0.012, (0, NY1 + 0.006 - 0.003, MZ), BARE, seg=48, axis='Y', bevel=0.001)
part("Bearing", "front bearing: carries the spindle, pressed into the nose", "Nose", "inset")

# --- spinning chuck and auger bit ------------------------------------------------------------------------------------
BY = NY1 + 0.009                                           # chuck back face (on the bearing)
with group("Bit"):
    cyl("Chuck", 0.022, 0.045, (0, BY + 0.0225, MZ), BARE, seg=32, axis='Y', r2=0.018, bevel=0.0015)
    for k in range(3):
        a = k * 2 * math.pi / 3
        box(f"ChuckJaw{k}", (0.006, 0.03, 0.004), (math.cos(a) * 0.0195, BY + 0.03, MZ + math.sin(a) * 0.0195), RUB,
            bevel=0.0, rot=Matrix.Rotation(-a, 4, 'Y'))
    CY0, CY1 = BY + 0.03, 0.53
    cyl("BitCore", 0.011, CY1 - CY0, (0, (CY0 + CY1) / 2, MZ), BARE, seg=16, axis='Y', bevel=0.0)
    for f in range(2):
        pts = []
        for i in range(161):                                # two flutes: helices round the core, half a turn apart
            t = i / 160
            a = t * 2 * math.pi * 6 + f * math.pi
            pts.append((math.cos(a) * 0.0165, 0.27 + t * 0.245, MZ + math.sin(a) * 0.0165))
        pipe(f"BitFlute{f}", pts, 0.0072, BARE, fillet=0.0, seg=6, bevel=0.0)
    cyl("BitTip", 0.017, 0.04, (0, CY1 + 0.02 - 0.004, MZ), BARE, seg=16, axis='Y', r2=0.0, bevel=0.0)
part("Chuck", "chuck: grips the bit, turned by the spindle", "Bearing", "pivot")
part("ChuckJaw", "chuck jaw: clamps the bit's shank", "Chuck", "inset")
part("BitCore", "bit core: the shank and spine of the auger", "Chuck", "inset")
part("BitFlute", "auger flute: carries the cuttings out of the bore", "BitCore", "inset")
part("BitTip", "carbide tip: breaks the rock at the bottom of the bore", "BitCore", "inset")

kit.finish("SM_MiningTool", pivots={"Bit": (0, BY, MZ)}, bake_res=2048,
           anims=[spin("Bit", 1, seconds=0.24)])

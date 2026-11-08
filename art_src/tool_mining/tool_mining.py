"""Mining Tool (first-person viewmodel, scripts/player/player.gd ViewmodelTool) - a hand-held rock cutter.
Origin = the hand on the grip. Blender +Y = forward (Godot -Z, the camera's look direction), Z up. Real size (~0.4 m).

What it does: the battery in the grip's foot powers a motor in the housing. The motor spins the cutter crown on the
front of the emitter barrel; the emitter behind the crown's lens throws the bore field that cuts the rock up to 6 m
away (the beam, chips, dust and heat glow are drawn in game: scripts/player/mining_tool_fx.gd). The coil band at the
barrel's mouth glows as the emitter heats; the fins behind it shed that heat. The display on the rear cap faces the
player: charge and heat.
Chain: battery -> grip -> housing (motor) -> barrel (emitter) -> crown hub (spindle) -> crown ring + teeth.
Moving group 'Crown' spins about the barrel axis ('Working' loop). Wear is baked at tool scale (kit.WEAR_SCALE)."""
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

# --- emitter barrel, heat-sink fins, coil ----------------------------------------------------------------------------
BR, BY0, BY1 = 0.03, YF, 0.22
cyl("Barrel", BR, BY1 - BY0, (0, (BY0 + BY1) / 2, MZ), SEC, seg=48, axis='Y', bevel=0.002)
part("Barrel", "emitter barrel: the bore emitter sits inside", "Housing", "welded")
weld_ring("BarrelWeld", (0, BY0, MZ), BR, axis='Y')
for k in range(5):
    tube(f"Fin{k}", 0.047, BR + 0.0002, 0.004, (0, 0.134 + k * 0.014, MZ), BARE, seg=48, axis='Y', bevel=0.0008)
part("Fin", "emitter heat sink: sheds the emitter's heat", "Barrel", "seated")
cyl("Coil", BR + 0.003, 0.012, (0, 0.207, MZ), HEAT, seg=48, axis='Y', bevel=0.001)
part("Coil", "emitter coil: glows as the emitter heats", "Barrel", "inset")
cyl("Lens", 0.0165, 0.016, (0, BY1 + 0.006, MZ), HEAT, seg=32, axis='Y', r2=0.011, bevel=0.0)
part("Lens", "emitter lens: the bore field leaves here", "Barrel", "inset")

# --- spinning cutter crown -------------------------------------------------------------------------------------------
with group("Crown"):
    tube("CrownHub", 0.024, 0.0175, 0.012, (0, BY1 + 0.006, MZ), BARE, seg=48, axis='Y', bevel=0.0008)
    tube("CrownRing", 0.045, 0.036, 0.018, (0, BY1 + 0.012 + 0.009 - 0.003, MZ), BARE, seg=48, axis='Y', bevel=0.001)
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 6
        box(f"CrownSpoke{k}", (0.016, 0.008, 0.006), (math.cos(a) * 0.0302, BY1 + 0.008, MZ + math.sin(a) * 0.0302), BARE,
            bevel=0.0, rot=Matrix.Rotation(-a, 4, 'Y'))
    RF = BY1 + 0.012 + 0.018 - 0.003                       # crown ring front face
    for k in range(8):
        a = k * 2 * math.pi / 8
        box(f"Tooth{k}", (0.007, 0.012, 0.005), (math.cos(a) * 0.0405, RF + 0.004, MZ + math.sin(a) * 0.0405), BARE,
            bevel=0.0005, rot=Matrix.Rotation(-a, 4, 'Y'))
part("CrownHub", "crown hub: on the spindle, turns the crown", "Barrel", "pivot")
part("CrownRing", "crown ring: carries the teeth round the lens", "CrownSpoke", "inset", joins=("CrownHub",))
part("CrownSpoke", "spoke: joins the ring to the hub, leaves the lens clear", "CrownHub", "inset", joins=("CrownRing",))
part("Tooth", "carbide tooth: chips the rock face the field has loosened", "CrownRing", "inset")

kit.finish("SM_MiningTool", pivots={"Crown": (0, BY1, MZ)}, bake_res=2048,
           anims=[spin("Crown", 1, seconds=0.3)])

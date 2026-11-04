"""Player vehicle 2: buggy - BLOCKOUT. Origin on the ground under the chassis centre, Blender +Y forward.
~3.7 m long, 2.1 m wide, 1.8 m to the roll cage. A welded tube space frame: two floor rails, a roll cage over the
two seats, a front A-frame carrying the steering, an engine cradle at the back. Long-travel double wishbones with
coil-over shocks to shock towers on the frame, four big wheels. Battery pack behind the seats, light bar on the cage.
Detail pass comes after Michael approves this blockout."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector

kit.begin(kit.out_dir())
T = 0.03                                         # frame tube radius
FZ = 0.5                                         # floor rail height
def tube_(name, pts):
    pipe(name, pts, T, SEC, fillet=0.12, seg=12, bevel=0.0)
# space frame: floor rails, cross members, roll cage, front A-frame, rear cradle
for s in (-1, 1):
    tube_(f"FrameRail{s}", [(s * 0.45, -1.45, FZ), (s * 0.45, 1.3, FZ), (s * 0.3, 1.75, FZ + 0.15)])
    tube_(f"FrameHoopSide{s}", [(s * 0.45, -0.55, FZ), (s * 0.5, -0.5, 1.55)])
    tube_(f"FrameAPillar{s}", [(s * 0.45, 0.55, FZ), (s * 0.4, 0.05, 1.5)])
    tube_(f"FrameRoof{s}", [(s * 0.4, 0.05, 1.5), (s * 0.48, -0.5, 1.55)])
    tube_(f"FrameRearStay{s}", [(s * 0.48, -0.5, 1.5), (s * 0.4, -1.45, FZ + 0.05)])
for k, (y, z) in enumerate(((-1.4, FZ), (-0.55, FZ), (0.55, FZ), (1.3, FZ))):
    tube_(f"FrameCross{k}", [(-0.45, y, z), (0.45, y, z)])
tube_("FrameHoopTop", [(-0.5, -0.5, 1.55), (0.5, -0.5, 1.55)])
tube_("FrameRoofFront", [(-0.4, 0.05, 1.5), (0.4, 0.05, 1.5)])
tube_("FrameBumper", [(-0.3, 1.75, FZ + 0.15), (0.3, 1.75, FZ + 0.15)])
part("Frame", "space frame tube: the welded chassis and roll cage", "ground", "ground", joins=("Frame",))
# floor pan, seats, steering, battery, engine
box("Floor", (0.84, 2.0, 0.02), (0, 0.05, FZ - 0.01), SEC, bevel=0.0)
part("Floor", "floor pan", "FrameRail", "inset", joins=("FrameCross",))
for s in (-1, 1):
    box(f"Seat{s}", (0.4, 0.45, 0.12), (s * 0.22, -0.2, FZ + 0.06), PRI, bevel=0.02)
    box(f"SeatBack{s}", (0.4, 0.1, 0.55), (s * 0.22, -0.43, FZ + 0.12 + 0.27), PRI, bevel=0.02)
part("Seat", "seat", "Floor", "bolted")
part("SeatBack", "seat back", "Seat", "inset")
for s in (-1, 1):
    for k, y in enumerate((-0.05, -0.35)):
        cyl(f"SeatBolt{s}{k}", 0.008, 0.008, (s * 0.22 + 0.16, y, FZ + 0.004), BARE, seg=6, bevel=0.0)
cyl("SteeringColumn", 0.02, 0.5, (0.22, 0.42, FZ + 0.25), BARE, seg=8, bevel=0.0)
part("SteeringColumn", "steering column", "Floor", "inset")
cyl("SteeringWheel", 0.16, 0.03, (0.22, 0.42, FZ + 0.5 + 0.015), RUB, seg=24, bevel=0.0)
part("SteeringWheel", "steering wheel", "SteeringColumn", "pivot")
box("Battery", (0.8, 0.3, 0.35), (0, -0.8, FZ + 0.175), SEC, bevel=0.02)
part("Battery", "battery pack: powers the wheel motors", "Floor", "bolted", joins=("FrameCross",))
for s in (-1, 1):
    cyl(f"BatteryBolt{s}", 0.01, 0.01, (s * 0.3, -0.98, FZ + 0.005), BARE, seg=6, bevel=0.0)
box("Motor", (0.55, 0.35, 0.3), (0, -1.4 + T + 0.175, FZ + 0.15), BARE, bevel=0.02)
part("Motor", "rear drive motor + diff", "FrameCross0", "bolted", joins=("Floor", "Battery", "FrameRail"))
for s in (-1, 1):
    cyl(f"MotorBolt{s}", 0.01, 0.01, (s * 0.2, -1.4, FZ + 0.035), BARE, seg=6, bevel=0.0)
box("LightBar", (0.9, 0.08, 0.06), (0, -0.5, 1.55 + T + 0.03), SEC, bevel=0.01)
part("LightBar", "light bar on the roll hoop", "FrameHoopTop", "bolted")
for s in (-1, 1):
    cyl(f"LightBarBolt{s}", 0.008, 0.008, (s * 0.42, -0.5, 1.55 + T + 0.06 + 0.004), BARE, seg=6, bevel=0.0)
# suspension and wheels: wishbones from the frame rails to the hub, coil-over to a shock tower, wheel on the hub
WR, WW, WX = 0.45, 0.32, 0.92
for s in (-1, 1):
    for k, y in enumerate((-1.15, 1.2)):
        hub = Vector((s * (WX - WW / 2 - 0.05), y, WR))
        cyl(f"Hub{s}{k}", 0.08, 0.1, tuple(hub), BARE, seg=16, axis='X', bevel=0.005)
        tube_(f"FrameTower{s}{k}", [(s * 0.45, y, FZ), (s * 0.58, y, FZ + 0.58)])     # shock tower
        tube_(f"ArmLow{s}{k}", [(s * 0.45, y - 0.15, FZ - T), tuple(hub - Vector((0, 0, 0.06))), (s * 0.45, y + 0.15, FZ - T)])
        a0 = Vector((s * (0.45 + 0.13 * 0.15 / 0.58), y, FZ + 0.15))                 # on the tower
        a1 = hub + Vector((0, 0, 0.07))
        pipe(f"ArmUp{s}{k}", [tuple(a0), tuple(a1)], T, SEC, fillet=0.0, seg=12, bevel=0.0)
        sb = a0.lerp(a1, (0.6 - abs(a0.x)) / (abs(a1.x) - abs(a0.x)))
        pipe(f"Shock{s}{k}", [tuple(sb), (s * 0.58, y, FZ + 0.58)], 0.035, RUB, fillet=0.0, seg=12, bevel=0.0)
        cyl(f"Wheel{s}{k}", WR, WW, (s * WX, y, WR), RUB, seg=32, axis='X', bevel=0.02)
part("ArmLow", "lower wishbone: carries the hub, pivots on the frame rail", "FrameRail", "pivot", joins=("Hub",))
part("ArmUp", "upper arm: pivots on the shock tower, carries the hub top", "FrameTower", "pivot", joins=("Hub", "Shock"))
part("Shock", "coil-over shock: from the upper wishbone up to the frame", "ArmUp", "pivot", joins=("Frame",))
part("Hub", "hub: the wheel turns on it, steering knuckle at the front", "ArmLow", "pivot")
part("Wheel", "wheel: hub motor drive", "Hub", "pivot")
kit.finish("SM_VehicleBuggy")

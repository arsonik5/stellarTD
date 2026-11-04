"""Stellar TD - Smelter (induction smelter). Built from the shared kit (art_src/kit.py).
Run: sh art_src/build.sh smelter. 1 unit = 1 m, origin bottom-centre, front = Blender -Y. Footprint 2.0 x 2.0.
Ore comes in through the back port into a hopper in the housing, a lift line carries it up into the crucible, the
water-cooled induction coil bands melt it, ingots leave through the front port. Radiators on both sides cool the coil
water (supply + return line each side). Fumes go up through the hood and the finned stack, pulled by the stack fan."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector, Matrix

kit.begin(kit.out_dir())

# ------------------------------------------------------------------ base, housing, ports
skid(2.0)
shape = housing(1.6, 0.12, 1.30, chamfer=0.22, belt=0.74, taper=1.0, name="Housing", panels={
    '-Y1': ('cover', "inspection cover: the melt window and the status light are set in it"),
    '+Y1': ('cover', "hopper lid: the lift line leaves the hopper through it"),
})
wall = shape.hw(0.45)
machine_port("Out", '-Y', wall, 1.0, light=True, job="output port: ingots leave here into the pipe")
machine_port("In", '+Y', wall, 1.0, job="input port: ore arrives here into the hopper")
TOP = 1.35                                                    # top of the housing's top rim

# ------------------------------------------------------------------ crucible
# cowl: the rounded-square housing top blends into the round crucible (one lofted part, not a disc on a deck)
CF = 0.016                                                    # cowl base flange thickness
loft("Cowl", [zring(squircle(0.82, 0.82, 4.2, 48), TOP), zring(squircle(0.82, 0.82, 4.2, 48), TOP + CF),
              zring(squircle(0.76, 0.76, 4.2, 48), TOP + CF), zring(squircle(0.72, 0.72, 3.4, 48), TOP + 0.04),
              zring(squircle(0.66, 0.66, 2.4, 48), TOP + 0.08), zring(squircle(0.62, 0.62, 2.0, 48), 1.47)], SEC, bevel=0.01)
part("Cowl", "cowl: carries the crucible on the housing and closes the top", "HousingTrimHigh", "bolted")
for k, (x, y) in enumerate(squircle(0.79, 0.79, 4.2, seg=16)):                # base flange bolted down onto the top rim
    cyl(f"CowlBolt{k}", 0.012, 0.014, (x, y, TOP + CF + 0.007), BARE, seg=6, bevel=0.0)
CZ0, CZ1 = 1.45, 1.99
cyl("CrucibleCore", 0.53, CZ1 - CZ0, (0, 0, (CZ0 + CZ1) / 2), HEAT, seg=32, bevel=0.0)
part("CrucibleCore", "the crucible: the melt glows through the gaps between the coil bands", "Cowl", "through")
weld_ring("CrucibleWeld", (0, 0, 1.47 + WELD_R * 0.5), 0.53 + WELD_R * 0.4)        # crucible welded into the cowl
BANDS = ((1.47, 1.61), (1.645, 1.795), (1.83, 1.99))
for i, (z0, z1) in enumerate(BANDS):
    cyl(f"CrucibleBand{i}", 0.56, z1 - z0, (0, 0, (z0 + z1) / 2), PRI, seg=48, bevel=0.01)
part("CrucibleBand", "water-cooled induction coil band: heats the melt", "CrucibleCore", "inset")
cyl("CrucibleLip", 0.64, 0.05, (0, 0, CZ1 + 0.025), BARE, seg=40)
part("CrucibleLip", "lip flange on the crucible: the hood bolts to it", "CrucibleCore", "welded")
weld_ring("CrucibleLipWeld", (0, 0, CZ1 + WELD_R * 0.5), 0.53 + WELD_R * 0.4)

# hood (with its own flange, bolted to the lip) + finned exhaust stack with its fan
HZ = CZ1 + 0.05
cyl("HoodFlange", 0.64, 0.02, (0, 0, HZ + 0.01), SEC, seg=40, bevel=0.003)
part("HoodFlange", "hood flange: bolts the hood down on the crucible lip", "CrucibleLip", "bolted")
bolts("LipBolt", (0, 0, HZ + 0.02), '+Z', 0.615, 16, r=0.012, h=0.014)
cyl("Hood", 0.58, 0.17, (0, 0, HZ + 0.02 + 0.085), SEC, seg=32, r2=0.33, bevel=0.01)
part("Hood", "hood: catches the fumes over the melt", "HoodFlange", "welded")
weld_ring("HoodWeld", (0, 0, HZ + 0.02 + WELD_R * 0.5), 0.58 + WELD_R * 0.2)
EZ = HZ + 0.19                                                # top of the hood
cyl("ExhaustCollar", 0.33, 0.06, (0, 0, EZ + 0.03), BARE, seg=24)
part("ExhaustCollar", "exhaust collar: the stack bolts to the hood through it", "Hood", "bolted")
bolts("CollarBolt", (0, 0, EZ + 0.06), '+Z', 0.3, 10, r=0.011, h=0.012, start=math.pi / 10)  # between the fins
SZ0, SZ1 = EZ + 0.06, EZ + 0.30
cyl("ExhaustCore", 0.2, SZ1 - SZ0, (0, 0, (SZ0 + SZ1) / 2), SEC, seg=24)
part("ExhaustCore", "exhaust stack: the fumes go up through it", "ExhaustCollar", "welded")
weld_ring("ExhaustCoreWeld", (0, 0, SZ0 + WELD_R * 0.5), 0.2 + WELD_R * 0.4)
for i in range(10):
    a = 2 * math.pi * i / 10
    box(f"Fin{i}", (0.12, 0.018, 0.2), (math.cos(a) * 0.26, math.sin(a) * 0.26, SZ0 + 0.13), BARE,
        bevel=0.003, rot=Matrix.Rotation(a, 4, 'Z'))
    for sd in (-1, 1):                                                                 # fins welded to the stack
        o = Vector((-math.sin(a), math.cos(a), 0)) * sd * (0.009 + WELD_R * 0.6)
        r0 = Vector((math.cos(a) * (0.2 + WELD_R * 0.6), math.sin(a) * (0.2 + WELD_R * 0.6), 0))
        weld(f"FinWeld{i}{sd}", [r0 + o + Vector((0, 0, SZ0 + 0.03)), r0 + o + Vector((0, 0, SZ0 + 0.23))])
part("Fin", "heat-sink fin: sheds the exhaust heat", "ExhaustCore", "welded")
cyl("ExhaustRim", 0.23, 0.035, (0, 0, SZ1 + 0.0175), BARE, seg=24)
part("ExhaustRim", "stack rim: stiffens the top of the stack, the fan bearing sits in it", "ExhaustCore", "welded")
weld_ring("ExhaustRimWeld", (0, 0, SZ1 - WELD_R * 0.5), 0.2 + WELD_R * 0.4)
RZ = SZ1 + 0.035
cyl("ExhaustHole", 0.17, 0.004, (0, 0, RZ + 0.002), RUB, seg=24, bevel=0.0)
part("ExhaustHole", "the stack's open bore (dark)", "ExhaustRim", "inset")
FZ = RZ + 0.004
cyl("ExhaustBarHub", 0.035, 0.05, (0, 0, FZ + 0.025), SEC, seg=12, bevel=0.0)
part("ExhaustBarHub", "fan hub: spins on the stack's bearing, carries the blades", "ExhaustHole", "pivot")
box("ExhaustBarA", (0.32, 0.022, 0.012), (0, 0, FZ + 0.015), BARE, bevel=0.0)
part("ExhaustBarA", "fan blade", "ExhaustBarHub", "inset")
box("ExhaustBarB", (0.022, 0.32, 0.012), (0, 0, FZ + 0.027), BARE, bevel=0.0)
part("ExhaustBarB", "fan blade", "ExhaustBarHub", "inset", joins=("ExhaustBarA",))

# ------------------------------------------------------------------ front: inspection window + status light
def on_panel(face, u, z, off=0.0):
    """a point `off` out from the front of the panel (0.022 thick) at (u, z), and the wall normal there"""
    p, n = shape.at(face, u, z)
    return p + n * (0.022 + off), n
wp, wn = on_panel('-Y', 0, 1.0)
WR = basis(wn, (0, 0, 1))
def on_win(off):
    return Matrix.Translation(wp + wn * off) @ WR
cyl("WindowBezel", 0.17, 0.04, (0, 0, 0), BARE, seg=24, rot=on_win(0.02))
part("WindowBezel", "window frame: holds the glass in the cover", "HousingPanel-Y1", "bolted")
cyl("WindowGlass", 0.125, 0.01, (0, 0, 0), HEAT, seg=24, bevel=0.0, rot=on_win(0.041))
part("WindowGlass", "heat glass: you see the melt through it", "WindowBezel", "inset")
for k in (-1, 0, 1):
    box(f"WinBar{k}", (0.018, 0.25, 0.012), (k * 0.055, 0, 0), BARE, bevel=0.0, rot=on_win(0.046))
part("WinBar", "guard bar: keeps tools off the glass", "WindowBezel", "inset", joins=("WindowGlass",))
bolt_ring("WinBolt", wp + wn * 0.04, wn, 0.15, 8, start=math.pi / 8)
sp, sn = on_panel('-Y', 0, 1.2)
status_strip("Status", sp.y, 1.2, on="HousingPanel-Y1")

# ------------------------------------------------------------------ back: lift line from the hopper to the crucible
op, on_ = on_panel('+Y', 0, 0.98)
cyl("FeedOutlet", 0.09, 0.025, (0, 0, 0), SEC, seg=24, rot=Matrix.Translation(op + on_ * 0.0125) @ basis(on_))
part("FeedOutlet", "outlet flange: the lift line leaves the hopper here", "HousingPanel+Y1", "bolted")
bolt_ring("FeedOutletBolt", op + on_ * 0.025, on_, 0.072, 6)
LR = 0.045                                                    # lift line radius
NZ = 0.5 * (BANDS[1][0] + BANDS[1][1])                       # it feeds the crucible through the middle coil band
pipe("FeedLine", [(0.0, op.y + 0.02, 0.98), (0.0, 0.93, 0.98), (0.0, 0.93, NZ), (0.0, 0.68, NZ)], LR, BARE, fillet=0.08)
part("FeedLine", "lift line: carries ore from the hopper up into the crucible", "FeedOutlet", "through",
     joins=("FeedNozzleFlange",))
# nozzle: a stub welded into the coil band, with a flange the lift line's end is bolted to
tube("FeedNozzle", LR + 0.008, LR - 0.004, 0.66 - 0.5, (0, 0.5 + 0.08, NZ), BARE, seg=24, axis='Y', bevel=0.003)
part("FeedNozzle", "feed nozzle: welded into the crucible, ore drops in through it", "CrucibleBand1", "through",
     joins=("CrucibleCore",))
saddle_weld("FeedNozzleWeld", '+Y', LR + 0.008 + WELD_R * 0.4, 0.56, z0=NZ)
cyl("FeedNozzleFlange", 0.075, 0.02, (0, 0.66 + 0.01, NZ), SEC, seg=24, axis='Y')
part("FeedNozzleFlange", "nozzle flange: the lift line bolts on here", "FeedNozzle", "welded")
weld_ring("FeedNozzleFlangeWeld", (0, 0.66 - WELD_R * 0.5, NZ), LR + 0.008 + WELD_R * 0.4, 'Y')
bolts("FeedNozzleBolt", (0, 0.68, NZ), '+Y', 0.06, 6, r=0.009, h=0.011)
cz = 1.1
cp, cn = on_panel('+Y', 0, cz)
clamp("FeedClamp", (0.0, 0.93, cz), (0, 0, 1), LR, tuple(-cn), foot_len=(0.93 - LR - cp.y) / abs(cn.y))
part("FeedClamp", "clamp: holds the lift line to the hopper lid", "HousingPanel+Y1", "bolted")
part("FeedClampBand", "band that grips the lift line", "FeedClampTab", "inset", joins=("FeedLine",))

# ------------------------------------------------------------------ sides: radiators on brackets + coolant to the coils
RX = 0.865                                                    # radiator inner plane: clear of the housing belt
Z0, Z1 = 0.33, 1.19
for sx in (-1, 1):
    face = '+X' if sx > 0 else '-X'
    post_y = {}
    for sy in (-1, 1):
        ends = []
        for z in (0.45, 1.07):
            u = sy * 0.41 * (1 if sx > 0 else -1)            # lateral offset on that face (its own left-right)
            wp_, wn_ = shape.at(face, u, z)
            ends.append(wall_bracket(f"RadBracket_{sx}_{sy}_{z}", wp_, wn_, (RX - abs(wp_.x)) / abs(wn_.x)))
        post_y[sy] = sum(e.y for e in ends) / 2
        box(f"RadPost_{sx}_{sy}", (0.06, 0.06, Z1 - Z0), (sx * (RX + 0.03), post_y[sy], (Z0 + Z1) / 2), SEC, bevel=0.006)
    span = post_y[1] - post_y[-1] - 0.06
    for k, z in enumerate((Z0 + 0.025, Z1 - 0.025)):
        h = box(f"RadHeader{k}_{sx}", (0.06, span, 0.05), (sx * (RX + 0.03), (post_y[1] + post_y[-1]) / 2, z), SEC, bevel=0.006)
        for sy in (-1, 1):
            box_weld(f"RadHeaderWeld{k}_{sx}_{sy}_", h, bpy.data.objects[f"RadPost_{sx}_{sy}"])
    for i in range(7):
        y = -0.33 + 0.11 * i
        f = box(f"RadFin_{sx}_{i}", (0.13, 0.022, Z1 - Z0 - 0.1), (sx * (RX + 0.065), y, (Z0 + Z1) / 2), BARE, bevel=0.003)
        for k in (0, 1):
            box_weld(f"RadFinWeld_{sx}_{i}_{k}_", f, bpy.data.objects[f"RadHeader{k}_{sx}"])
    # coolant: supply + return from the top header up and radially into the bottom coil band
    for j, sy in enumerate((1, -1)):
        y = sy * 0.3
        bx = math.sqrt(0.56 ** 2 - y ** 2)                   # where the line meets the band, radially
        rad = Vector((bx, y, 0)).normalized()
        bz = 0.5 * (BANDS[0][0] + BANDS[0][1])
        end = Vector((sx * bx, y, bz))
        d = Vector((sx * rad.x, rad.y, 0))
        hx = sx * (RX + 0.03)
        pipe(f"Coolant{j}_{sx}", [(hx, y, Z1), (hx, y, bz), tuple(end + d * 0.12), tuple(end)], 0.025, BARE, fillet=0.06)
        fitting(f"CoolFitRad_{sx}_{j}", (hx, y, Z1 + 0.0225), (0, 0, 1), 0.025)
        fitting(f"CoolFitCoil_{sx}_{j}", tuple(end + d * 0.0225), tuple(d), 0.025)
part("RadBracket", "radiator bracket: holds the fin bank off the housing wall", "Housing", "bolted")
part("RadPost", "radiator post: carries the fin bank, sits on the brackets", "RadBracket", "welded")
part("RadHeader", "radiator header: the coolant runs through it into the fins", "RadPost", "welded")
part("RadFin", "radiator fin: sheds the coil water's heat", "RadHeader", "welded")
part("Coolant", "coolant line: supply and return between the radiator and the coil band", "RadHeader", "through",
     joins=("CrucibleBand0",))

assign("Fan", "ExhaustBar")
kit.finish("SM_Smelter", pivots={"Fan": (0, 0, FZ + 0.025)}, anims=[spin("Fan", 2, seconds=1.0)])

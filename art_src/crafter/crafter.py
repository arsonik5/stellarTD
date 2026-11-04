"""Crafter (BasicCrafter, scenes/processor.tscn) - assembly cell: a housing with the arm's drives, a glass work cell
on top where a robot arm assembles the part held in a jig, a roof fan pulling the fumes out.
Footprint 1.5 x 1.5 (matches the scene's collision box), origin bottom-centre, front (output) = Blender -Y.
Items come in at the back (+Y) and leave at the front (-Y), both through round pipe ports at 0.45 m."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Matrix, Vector

kit.begin(kit.out_dir())

# ---------------------------------------------------------------- base: skid, housing, ports
skid(1.5)
shape = housing(1.24, 0.12, 0.92, chamfer=0.16, belt=None, panels={
    '+X0': ('vent', "vent: cools the arm's servo drives inside"),
    '-X0': ('door', "service door to the arm controller and servo drives"),
})
wall = shape.hw(0.45)
machine_port("Out", '-Y', wall, 0.75, light=True, job="output port: finished parts leave here into the pipe")
machine_port("In", '+Y', wall, 0.75, job="input port: parts to assemble arrive here from the pipe")
status_strip("Status", -shape.hw(0.8), 0.8)

# ---------------------------------------------------------------- work cell
CZ0 = 0.97                     # top of the housing's top rim
B = CZ0 + 0.05                 # top of the bed plate
CZ1, CW, P = 1.6, 0.86, 0.06   # roof height, post centre spacing, post size
box("Bed", (1.06, 1.06, 0.05), (0, 0, CZ0 + 0.025), BARE, bevel=0.006)
part("Bed", "bed plate: the work cell and the arm stand on it", "HousingTrimHigh", "bolted")
for sx in (-1, 1):                                        # bed bolted down into the housing's top rim
    for sy in (-1, 1):
        cyl(f"BedBolt{sx}{sy}", 0.012, 0.012, (sx * 0.33, sy * 0.33, B + 0.006), BARE, seg=6, bevel=0.0)

post_h = CZ1 - (B + 0.012)
for sx in (-1, 1):
    for sy in (-1, 1):
        base_plate(f"CellFoot_{sx}_{sy}", (sx * CW / 2, sy * CW / 2, B), 0.18, 0.18, t=0.012, bolt_inset=0.03)
        post = box(f"CellPost_{sx}_{sy}", (P, P, post_h), (sx * CW / 2, sy * CW / 2, B + 0.012 + post_h / 2), SEC, bevel=0.006)
        box_weld(f"CellPostWeld_{sx}_{sy}_", post, bpy.data.objects[f"CellFoot_{sx}_{sy}"])
part("CellFoot", "post foot plate, bolted to the bed", "Bed", "bolted")
part("CellPost", "cell corner post: carries the roof and holds the glass", "CellFoot", "welded")

span = CW - P                   # clear distance between two posts
for sy in (-1, 1):
    r = box(f"CellRailY_{sy}", (span, P, 0.05), (0, sy * CW / 2, CZ1 - 0.025), SEC, bevel=0.005)
    s = box(f"CellSillY_{sy}", (CW - 0.18, 0.05, 0.05), (0, sy * CW / 2, B + 0.025), SEC, bevel=0.005)
    for sx in (-1, 1):
        box_weld(f"CellRailWeldY_{sy}_{sx}_", r, bpy.data.objects[f"CellPost_{sx}_{sy}"])
    box_weld(f"CellSillWeldY_{sy}_", s, bpy.data.objects["Bed"])
for sx in (-1, 1):
    r = box(f"CellRailX_{sx}", (P, span, 0.05), (sx * CW / 2, 0, CZ1 - 0.025), SEC, bevel=0.005)
    s = box(f"CellSillX_{sx}", (0.05, CW - 0.18, 0.05), (sx * CW / 2, 0, B + 0.025), SEC, bevel=0.005)
    for sy in (-1, 1):
        box_weld(f"CellRailWeldX_{sx}_{sy}_", r, bpy.data.objects[f"CellPost_{sx}_{sy}"])
    box_weld(f"CellSillWeldX_{sx}_", s, bpy.data.objects["Bed"])
part("CellRail", "top rail: ties the posts together, the roof sits on it", "CellPost", "welded")
part("CellSill", "bottom sill between the post feet: the glass stands in it", "Bed", "welded", joins=("CellFoot",))

gz0, gz1 = B + 0.05, CZ1 - 0.05
for sy in (-1, 1):
    box(f"GlassY_{sy}", (span, 0.012, gz1 - gz0), (0, sy * CW / 2, (gz0 + gz1) / 2), GLASS, bevel=0.0)
for sx in (-1, 1):
    box(f"GlassX_{sx}", (0.012, span, gz1 - gz0), (sx * CW / 2, 0, (gz0 + gz1) / 2), GLASS, bevel=0.0)
part("Glass", "glass wall: closes the cell, you watch the arm through it", "CellSill", "inset", joins=("CellRail", "CellPost"))

_rs = squircle(0.52, 0.52, 6.0)
loft("Roof", [zring(_rs, CZ1), zring(_rs, CZ1 + 0.04), zring(_rs, CZ1 + 0.075, 0.9, 0.9)], SEC, bevel=0.008)
part("Roof", "roof: closes the cell, carries the fume fan", "CellRail", "bolted", joins=("CellPost",))
RT = CZ1 + 0.075               # roof top
for i, (x, y) in enumerate([(sx * 0.2, sy * CW / 2) for sx in (-1, 1) for sy in (-1, 1)] +
                           [(sx * CW / 2, sy * 0.2) for sx in (-1, 1) for sy in (-1, 1)]):
    cyl(f"RoofBolt{i}", 0.011, 0.012, (x, y, RT + 0.006), BARE, seg=6, bevel=0.0)    # roof bolted down onto the rails

# fume fan: flanged shroud bolted to the roof, a spider across it carries the motor, the rotor spins on the motor
tube("FanFlange", 0.25, 0.17, 0.012, (0, 0, RT + 0.006), SEC, seg=40, bevel=0.002)
part("FanFlange", "shroud flange: bolts the fan to the roof", "Roof", "bolted")
bolts("FanFlangeBolt", (0, 0, RT + 0.012), '+Z', 0.225, 8, r=0.009, h=0.01, start=math.pi / 8)
tube("FanShroud", 0.2, 0.17, 0.1, (0, 0, RT + 0.012 + 0.05), SEC, seg=40, bevel=0.003)
part("FanShroud", "fan shroud: ducts the air out of the cell", "FanFlange", "welded")
weld_ring("FanShroudWeld", (0, 0, RT + 0.012 + WELD_R * 0.5), 0.2 + WELD_R * 0.4)
cyl("FanHole", 0.17, 0.004, (0, 0, RT + 0.002), RUB, seg=40, bevel=0.0)
part("FanHole", "the duct opening in the roof (dark)", "Roof", "inset", joins=("FanFlange",))
SZ = RT + 0.035
for k, rot in enumerate((rotz(0), rotz(90))):
    box(f"FanSpider{k}", (0.34, 0.018, 0.012), (0, 0, SZ + (0.006 if k else -0.006)), BARE, bevel=0.0, rot=rot)
part("FanSpider0", "spider bar: spans the shroud, carries the motor", "FanShroud", "inset")
part("FanSpider1", "spider bar: spans the shroud, carries the motor", "FanSpider0", "seated", joins=("FanShroud",))
cyl("FanMotor", 0.045, 0.035, (0, 0, SZ + 0.012 + 0.0175), SEC, seg=24, bevel=0.003)
part("FanMotor", "fan motor", "FanSpider1", "clamped")
cyl("FanRotor", 0.028, 0.02, (0, 0, SZ + 0.047 + 0.01), BARE, seg=20, bevel=0.002)
part("FanRotor", "rotor hub: the blades are fixed to it", "FanMotor", "pivot")
for k, a in enumerate((0, 120, 240)):
    p = rotz(a) @ Vector((0.022 + 0.065, 0, SZ + 0.057))
    box(f"FanBlade{k}", (0.13, 0.035, 0.006), tuple(p), BARE, bevel=0.0, rot=rotz(a) @ Matrix.Rotation(math.radians(20), 4, 'X'))
part("FanBlade", "fan blade: pulls the fumes out", "FanRotor", "inset")

# ---------------------------------------------------------------- robot arm (base back-left, reaching over the jig)
ax, ay = -0.18, 0.18
cyl("ArmBase", 0.11, 0.07, (ax, ay, B + 0.035), SEC, seg=24)
part("ArmBase", "arm base: holds the waist motor, bolted to the bed", "Bed", "bolted")
bolts("ArmBaseBolt", (ax, ay, B + 0.07), '+Z', 0.095, 6, r=0.009, h=0.01)
cyl("ArmTurn", 0.075, 0.04, (ax, ay, B + 0.09), BARE, seg=24)
part("ArmTurn", "turntable: the arm swings on it", "ArmBase", "pivot")
TT = B + 0.11                                              # turntable top
SH = Vector((ax, ay, TT + 0.07))                          # shoulder axis
cyl("Shoulder", 0.05, 0.1, tuple(SH), SEC, seg=20, axis='X')
part("Shoulder", "shoulder joint: the upper arm pivots on it", "ShoulderCheek", "inset")
for s in (-1, 1):                                         # clevis cheeks welded to the turntable carry the shoulder
    ck = box(f"ShoulderCheek{s}", (0.02, 0.09, 0.12), (ax + s * 0.06, ay, TT + 0.06), SEC, bevel=0.004)
    box_weld(f"ShoulderCheekWeld{s}_", ck, bpy.data.objects["ArmTurn"])
part("ShoulderCheek", "clevis cheek: holds the shoulder axle", "ArmTurn", "welded")
up_rot = Matrix.Rotation(math.radians(25), 4, 'X')         # leans toward -Y (the jig)
up_dir = up_rot @ Vector((0, 0, 1))
EL = SH + up_dir * 0.3
box("UpperArm", (0.07, 0.07, 0.3), tuple(SH + up_dir * 0.15), PRI, bevel=0.008, rot=up_rot)
part("UpperArm", "upper arm link", "Shoulder", "pivot")
cyl("Elbow", 0.045, 0.09, tuple(EL), SEC, seg=20, axis='X')
part("Elbow", "elbow joint housing at the end of the upper arm", "UpperArm", "inset")
fo_rot = Matrix.Rotation(math.radians(115), 4, 'X')        # forearm reaches forward and down to the jig
fo_dir = fo_rot @ Vector((0, 0, 1))
WR = EL + fo_dir * 0.26
box("Forearm", (0.06, 0.06, 0.24), tuple(EL + fo_dir * 0.12), PRI, bevel=0.008, rot=fo_rot)
part("Forearm", "forearm link", "Elbow", "pivot", joins=("UpperArm",))
cyl("Wrist", 0.035, 0.05, tuple(WR), BARE, seg=16, rot=fo_rot)
part("Wrist", "wrist: turns the gripper", "Forearm", "pivot")
for s in (-1, 1):
    box(f"Finger{s}", (0.015, 0.03, 0.07), tuple(WR + fo_dir * 0.05 + Vector((s * 0.022, 0, 0))), BARE, bevel=0.0, rot=fo_rot)
part("Finger", "gripper finger", "Wrist", "pivot")

# the part being assembled, clamped in its jig
box("WorkJig", (0.24, 0.2, 0.025), (0.1, -0.12, B + 0.0125), SEC, bevel=0.004)
part("WorkJig", "jig: holds the part while the arm works on it", "Bed", "bolted")
for sx in (-1, 1):
    for sy in (-1, 1):
        cyl(f"JigBolt{sx}{sy}", 0.008, 0.008, (0.1 + sx * 0.1, -0.12 + sy * 0.08, B + 0.025 + 0.004), BARE, seg=6, bevel=0.0)
box("Workpiece", (0.16, 0.12, 0.06), (0.1, -0.12, B + 0.025 + 0.03), BARE, bevel=0.006)
part("Workpiece", "the part being assembled", "WorkJig", "seated")

assign("Fan", "FanRotor", "FanBlade")
assign("Arm", "ArmTurn", "Shoulder", "UpperArm", "Elbow", "Forearm", "Wrist", "Finger")
kit.finish("SM_Crafter", pivots={"Fan": (0, 0, SZ + 0.057), "Arm": (ax, ay, B + 0.09)},
           anims=[spin("Fan", 2, seconds=0.8),
                  swing("Arm", 2, [(0.0, 0.0), (1.0, -0.6), (1.6, -0.6), (2.6, 0.45), (3.2, 0.45), (4.0, 0.0)])])

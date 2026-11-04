"""Constructor (scenes/constructor.tscn) - hydraulic forming press: low housing with the hydraulic power unit inside,
a bed with the die on top, two columns carrying the crosshead, the cylinder hanging from it drives the ram down on
two guide rods. Pressure lines run from the power unit up the back into the crosshead.
Footprint 1.5 x 1.5, origin bottom-centre, front = Blender -Y. Input port left (-X), output port front (-Y)."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector, Matrix

kit.begin(kit.out_dir())

skid(1.5)
shape = housing(1.24, 0.12, 0.84, chamfer=0.16, belt=None, panels={
    '+X0': ('vent', "vent: cools the hydraulic power unit inside"),
    '+Y0': ('cover', "access cover to the hydraulic power unit; the pressure lines leave through it"),
})
wall = shape.hw(0.45)
machine_port("Out", '-Y', wall, 0.75, light=True, job="output port: pressed parts leave here into the pipe")
machine_port("In", '-X', wall, 0.75, job="input port: blanks arrive here from the pipe")
HT = 0.89                                                    # top of the housing's top rim

# ---------------------------------------------------------------- bed, die, blank
BT = HT + 0.07
box("Bed", (0.8, 0.7, 0.07), (0, -0.04, HT + 0.035), SEC, bevel=0.01)
part("Bed", "press bed: takes the press force, the die sits on it", "HousingTrimHigh", "bolted")
for sx in (-1, 1):
    for sy in (-1, 1):
        cyl(f"BedBolt{sx}{sy}", 0.012, 0.012, (sx * 0.37, -0.04 + sy * 0.32, BT + 0.006), BARE, seg=6, bevel=0.0)
box("Die", (0.5, 0.42, 0.06), (0, -0.04, BT + 0.03), BARE, bevel=0.008)
part("Die", "die: the shape the blank is pressed into", "Bed", "bolted")
for sx in (-1, 1):                                           # die clamped to the bed
    for sy in (-1, 1):
        cyl(f"DieBolt{sx}{sy}", 0.012, 0.012, (sx * 0.21, -0.04 + sy * 0.17, BT + 0.06 + 0.006), BARE, seg=6, bevel=0.0)
box("Blank", (0.3, 0.26, 0.03), (0, -0.04, BT + 0.06 + 0.015), HEAT, bevel=0.004)
part("Blank", "hot blank being pressed", "Die", "seated")

# ---------------------------------------------------------------- columns, crosshead
CX, CY = 0.5, 0.05
CB, CT = 1.77, 2.07                                          # crosshead bottom / top
FT = HT + 0.025                                              # top of the column feet
for sx in (-1, 1):
    foot = plate(f"ColumnFoot{sx}", (sx * CX, CY, HT), (0, 0, 1), 0.2, 0.62, t=0.025, clip=0.04, mat=SEC, up=(0, 1, 0),
                 bolts_on=False)
    for y in (CY - 0.295, CY + 0.295):
        for dx in (-0.06, 0.06):
            cyl(f"ColumnFootBolt{sx}{y:.2f}{dx}", 0.012, 0.014, (sx * CX + dx, y, FT + 0.007), BARE, seg=6, bevel=0.0)
    col = box(f"Column{sx}", (0.18, 0.34, CB - FT), (sx * CX, CY, (FT + CB) / 2), SEC, bevel=0.012)
    box_weld(f"ColumnWeld{sx}_", col, bpy.data.objects[f"ColumnFoot{sx}"])
    box(f"ColumnHaz{sx}", (0.13, 0.006, 0.36), (sx * CX, CY - 0.17 - 0.003, FT + 0.27 + 0.18), HAZ, bevel=0.0)
    for sy in (-1, 1):                                       # gussets front and back carry the column on its foot
        gusset(f"ColGusset{sx}{sy}", (sx * CX, CY + sy * 0.17, FT), (0, sy), 0.1, 0.24, t=0.05)
part("ColumnFoot", "column foot: spreads the press load into the housing rim", "HousingTrimHigh", "bolted")
part("Column", "press column: carries the crosshead, takes the press force", "ColumnFoot", "welded")
part("ColumnHaz", "pinch-zone warning on the column face", "Column", "inset")
part("ColGusset", "gusset: braces the column on its foot", "ColumnFoot", "welded", joins=("Column",))
box("Crosshead", (1.26, 0.46, CT - CB), (0, CY, (CB + CT) / 2), PRI, bevel=0.014)
part("Crosshead", "crosshead: holds the cylinder above the bed", "Column", "bolted")
for sx in (-1, 1):                                           # tie-rod nuts: the crosshead is bolted down on the columns
    for sy in (-1, 1):
        cyl(f"TieNut{sx}{sy}", 0.04, 0.04, (sx * CX, CY + sy * 0.1, CT + 0.02), BARE, seg=6, bevel=0.003)
plate("CrossheadFront", (0, CY - 0.23, (CB + CT) / 2), (0, -1, 0), 1.0, 0.2, t=0.02, clip=0.05)
part("CrossheadFront", "valve block cover: the press valves are behind it, the status light is set in it", "Crosshead", "bolted")
status_strip("Status", CY - 0.25, (CB + CT) / 2, on="CrossheadFront")
plate("CrossheadBack", (0, CY + 0.23, (CB + CT) / 2), (0, 1, 0), 1.0, 0.2, t=0.02, clip=0.05)
part("CrossheadBack", "manifold plate: the pressure lines connect to the valve block through it", "Crosshead", "bolted")

# ---------------------------------------------------------------- cylinder, piston, ram on guide rods
cyl("CylinderFlange", 0.22, 0.03, (0, CY, CB - 0.015), SEC, seg=32)
part("CylinderFlange", "cylinder flange: bolts the cylinder up under the crosshead", "Crosshead", "bolted")
bolts("CylinderBolt", (0, CY, CB - 0.03), '-Z', 0.2, 8, r=0.011, h=0.012, start=math.pi / 8)
cyl("CylinderHousing", 0.17, 0.2, (0, CY, CB - 0.03 - 0.1), SEC, seg=24)
part("CylinderHousing", "hydraulic cylinder: pushes the piston down", "CylinderFlange", "welded")
weld_ring("CylinderWeld", (0, CY, CB - 0.03 - WELD_R * 0.5), 0.17 + WELD_R * 0.4)
RZ = 1.30                                                     # ram centre (top of stroke)
RT = RZ + 0.05
cyl("RamPistonFlange", 0.14, 0.03, (0, CY, RT + 0.015), SEC, seg=24)
part("RamPistonFlange", "piston flange: the rod is screwed into it, it is bolted to the ram", "Piston", "inset")
bolts("RamFlangeBolt", (0, CY, RT + 0.03), '+Z', 0.115, 6, r=0.01, h=0.012)
pz0, pz1 = RT + 0.03, CB - 0.03 - 0.12                       # rod from the flange up into the cylinder
cyl("Piston", 0.09, pz1 - pz0 + 0.1, (0, CY, (pz0 + pz1 + 0.1) / 2), BARE, seg=20)
part("Piston", "piston rod: slides out of the cylinder and pushes the ram", "CylinderHousing", "pivot",
     joins=("RamPistonFlange",))
box("Ram", (0.5, 0.5, 0.1), (0, -0.04, RZ), SEC, bevel=0.01)
part("Ram", "ram: carries the punch, hangs on the piston, guided by the rods", "RamPistonFlange", "bolted")
box("RamFace", (0.5, 0.42, 0.04), (0, -0.04, RZ - 0.05 - 0.02), BARE, bevel=0.006)
part("RamFace", "punch: presses the blank into the die", "Ram", "bolted")
for sx in (-1, 1):
    for sy in (-1, 1):
        cyl(f"RamFaceBolt{sx}{sy}", 0.01, 0.012, (sx * 0.22, -0.04 + sy * 0.18, RZ - 0.05 - 0.04 - 0.006), BARE, seg=6,
            axis='-Z', bevel=0.0)
for sx in (-1, 1):
    cyl(f"Guide{sx}", 0.028, CB - BT, (sx * 0.32, CY, (BT + CB) / 2), BARE, seg=12)
    cyl(f"GuideNutLow{sx}", 0.045, 0.035, (sx * 0.32, CY, BT + 0.0175), BARE, seg=6, bevel=0.003)
    cyl(f"GuideNutHigh{sx}", 0.045, 0.035, (sx * 0.32, CY, CB - 0.0175), BARE, seg=6, axis='-Z', bevel=0.003)
    cyl(f"GuideBush{sx}", 0.05, 0.12, (sx * 0.32, CY, RZ), BARE, seg=16)
    arm = box(f"RamArm{sx}", (0.04, 0.08, 0.06), (sx * 0.268, CY, RZ), SEC, bevel=0.005)
part("Guide", "guide rod: keeps the ram square to the die", "Bed", "bolted", joins=("Crosshead",))
part("GuideNut", "guide rod nut: clamps the rod to the bed and the crosshead", "Guide", "inset")
part("GuideBush", "guide bush: slides on the rod", "Guide", "pivot")
part("RamArm", "ram arm: ties the ram to its guide bush", "Ram", "inset", joins=("GuideBush",))

# ---------------------------------------------------------------- pressure lines: power unit -> crosshead
for i, u in enumerate((-0.12, 0.12)):
    p, n = shape.at('+Y', -u, 0.5)                           # on the access cover (its own left-right)
    p = p + n * 0.022
    top = Vector((u, CY + 0.25 + 0.06, CB + 0.15))
    pipe(f"HydLine{i}", [tuple(p), tuple(p + n * 0.07), (u, p.y + n.y * 0.07, 0.95), (u, top.y, 1.25), tuple(top),
                         (u, CY + 0.25, top.z)], 0.025, RUB, fillet=0.08)
    fitting(f"HydFitUnit{i}", tuple(p + n * 0.0225), tuple(n), 0.025)
    fitting(f"HydFitHead{i}", (u, CY + 0.25 + 0.0225, top.z), (0, 1, 0), 0.025)
part("HydLine", "pressure line: power unit to the press valves (supply and return)", "HousingPanel+Y0", "through",
     joins=("CrossheadBack",))

assign("Ram", "Piston", "RamPiston", "Ram", "GuideBush")
kit.finish("SM_Constructor", pivots={"Ram": (0, CY, RZ)},
           anims=[swing("Ram", 2, [(0.0, 0.0), (0.7, -0.16), (1.0, -0.16), (2.0, 0.0)], path="location")])

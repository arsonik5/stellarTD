"""Splitter (scenes/pipe_splitter.tscn, replaces the 0.9 m 'Body' box). Origin = Body centre.
Input: back (-Y). Outputs: front (+Y = Godot -Z), left, right.
A round drum with a rotary distributor inside, turned by a pancake motor on top; the four connectors (kit.pipe_port)
grow out of the drum and end exactly on the cell edge with the same collar as the pipe. Three lit outlets read as
'one into many'."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector

kit.begin(kit.out_dir())
R, DH = 0.37, 0.56
G = -0.45
base_plate("Base", (0, 0, G), 0.34, 0.34, t=0.02, bolt_inset=0.035)
part("Base", "base plate: bolted to the ground", "ground", "ground")
post_len = -DH / 2 - (G + 0.02)
cyl("Post", 0.08, post_len, (0, 0, G + 0.02 + post_len / 2), SEC, seg=24, bevel=0.004)
part("Post", "post: carries the drum at pipe height", "Base", "welded")
weld_ring("PostWeldBase", (0, 0, G + 0.02 + WELD_R * 0.5), 0.08 + WELD_R * 0.4)
cyl("Drum", R, DH, (0, 0, 0), PRI, seg=48, bevel=0.012)
part("Drum", "drum: the distributor inside sends each item to the next outlet", "Post", "welded")
weld_ring("PostWeldTop", (0, 0, -DH / 2 - WELD_R * 0.5), 0.08 + WELD_R * 0.4)
for z in (-0.265, 0.265):
    cyl(f"DrumRim{z}", R + 0.008, 0.03, (0, 0, z), SEC, seg=48, bevel=0.005)
part("DrumRim", "stiffening ring round the drum", "Drum", "inset")
TZ = DH / 2
cyl("Turntable", 0.33, 0.05, (0, 0, TZ + 0.025), SEC, seg=48, bevel=0.008)
part("Turntable", "bearing housing: the distributor shaft runs in it", "Drum", "bolted")
bolts("TurntableBolt", (0, 0, TZ + 0.05), '+Z', 0.305, 12, r=0.011, h=0.012, start=math.pi / 12)
tube("TurnRing", 0.262, 0.245, 0.012, (0, 0, TZ + 0.05 + 0.006), STAT, seg=48, bevel=0.0)
part("TurnRing", "status ring: lit while the splitter runs", "Turntable", "inset")
MZ = TZ + 0.05                                  # top of the bearing housing
# drive: a pancake motor on three struts turns the distributor through a coupling; the coupling turns
with group("Rotor"):
    cyl("Coupling", 0.12, 0.025, (0, 0, MZ + 0.0125), BARE, seg=32, bevel=0.005)
    bolts("CouplingBolt", (0, 0, MZ + 0.025), '+Z', 0.085, 6, r=0.011, h=0.012)
    box("IndexLug", (0.03, 0.03, 0.02), (0.12 + 0.012, 0, MZ + 0.0125), HAZ, bevel=0.0)
part("Coupling", "coupling: the motor turns the distributor shaft through it", "Turntable", "pivot")
part("IndexLug", "index lug: shows the distributor's position", "Coupling", "inset")
MB = MZ + 0.07                                  # motor plate underside
for k in range(3):                              # three upright struts welded to the bearing housing and the plate
    a = math.radians(30 + k * 120)
    x, y = math.cos(a) * 0.165, math.sin(a) * 0.165
    cyl(f"Strut{k}", 0.012, MB - MZ, (x, y, (MZ + MB) / 2), SEC, seg=12, bevel=0.0)
    weld_ring(f"StrutWeldLow{k}", (x, y, MZ + WELD_R * 0.5), 0.012 + WELD_R * 0.4)
    weld_ring(f"StrutWeldHigh{k}", (x, y, MB - WELD_R * 0.5), 0.012 + WELD_R * 0.4)
part("Strut", "strut: holds the motor plate over the coupling", "Turntable", "welded", joins=("MotorPlate",))
cyl("MotorPlate", 0.19, 0.012, (0, 0, MB + 0.006), SEC, seg=40, bevel=0.002)
part("MotorPlate", "motor plate: the motor is bolted on it", "Strut", "welded")
MP = MB + 0.012
cyl("Motor", 0.11, 0.05, (0, 0, MP + 0.025), SEC, seg=32, bevel=0.008)
part("Motor", "pancake gear motor: turns the distributor", "MotorPlate", "bolted")
bolts("MotorBolt", (0, 0, MP), '+Z', 0.15, 6, r=0.009, h=0.01, start=math.pi / 6)
cyl("MotorFoot", 0.135, 0.008, (0, 0, MP + 0.004), SEC, seg=32, bevel=0.0)
part("MotorFoot", "motor foot flange", "Motor", "inset")
cyl("MotorCap", 0.07, 0.012, (0, 0, MP + 0.05 + 0.006), BARE, seg=24, bevel=0.0)
part("MotorCap", "motor end cap", "Motor", "bolted")
bolts("MotorCapBolt", (0, 0, MP + 0.062), '+Z', 0.05, 4, r=0.007, h=0.008, start=math.pi / 4)
part("In", "input port", "Drum", "through")
part("InThroat", "dark bore into the drum", "InNeck", "inset", joins=("Drum",))
pipe_port("In", '-Y', R, flange=False, neck_from=0.26, drum_r=R)
for name, ax in (("OutF", '+Y'), ("OutL", '-X'), ("OutR", '+X')):
    pipe_port(name, ax, R, flange=False, neck_from=0.26, drum_r=R, light=True)
    part(name, "output port: lit collar", "Drum", "through")
    part(name + "Throat", "dark bore into the drum", name + "Neck", "inset", joins=("Drum",))

kit.finish("SM_Splitter", pivots={"Rotor": (0, 0, MZ)}, anims=[spin("Rotor", 2, seconds=1.5)])

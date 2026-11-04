"""Merger (scenes/pipe_merger.tscn, replaces the 0.9 m 'Body' box). Origin = Body centre.
Inputs: back (-Y), left, right. Output: front (+Y = Godot -Z).
A round drum (same family as the splitter, all pipe parts are round) with four identical pipe connectors
(kit.pipe_port) growing out of it and ending exactly on the cell edge, so pipes mate flush. The bolted round lid
is the jam-clearing access; the lit collar marks the single output."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *

kit.begin(kit.out_dir())
R, DH = 0.37, 0.56
G = -0.45                                       # ground
# stand: a bolted base plate on the ground, a post welded on it, the drum welded on top
base_plate("Base", (0, 0, G), 0.34, 0.34, t=0.02, bolt_inset=0.035)
part("Base", "base plate: bolted to the ground", "ground", "ground")
post_len = -DH / 2 - (G + 0.02)
cyl("Post", 0.08, post_len, (0, 0, G + 0.02 + post_len / 2), SEC, seg=24, bevel=0.004)
part("Post", "post: carries the drum at pipe height", "Base", "welded")
weld_ring("PostWeldBase", (0, 0, G + 0.02 + WELD_R * 0.5), 0.08 + WELD_R * 0.4)
cyl("Drum", R, DH, (0, 0, 0), PRI, seg=48, bevel=0.012)
part("Drum", "drum: the items from the three inputs meet in it", "Post", "welded")
weld_ring("PostWeldTop", (0, 0, -DH / 2 - WELD_R * 0.5), 0.08 + WELD_R * 0.4)
for z in (-0.265, 0.265):                      # rims above/below the necks, never through them
    cyl(f"DrumRim{z}", R + 0.008, 0.03, (0, 0, z), SEC, seg=48, bevel=0.005)
part("DrumRim", "stiffening ring round the drum", "Drum", "inset")
# inspection lid: unbolt to clear a jam inside the drum; the handle is how you lift it
LZ = DH / 2
cyl("Lid", 0.25, 0.03, (0, 0, LZ + 0.015), SEC, seg=48, bevel=0.006)
part("Lid", "inspection lid: unbolt it to clear a jam", "Drum", "bolted")
bolts("LidBolt", (0, 0, LZ + 0.03), '+Z', 0.22, 10, r=0.011, h=0.012, start=math.pi / 10)
for s in (-1, 1):
    f = box(f"LidHandleFoot{s}", (0.022, 0.022, 0.03), (s * 0.06, 0.0, LZ + 0.03 + 0.015), BARE, bevel=0.0)
    box_weld(f"LidHandleFootWeld{s}_", f, bpy.data.objects["Lid"])
box("LidHandle", (0.144, 0.022, 0.022), (0, 0.0, LZ + 0.06 + 0.011), BARE, bevel=0.004)
part("LidHandleFoot", "handle foot", "Lid", "welded")
part("LidHandle", "lift handle", "LidHandleFoot", "inset")
for n, ax, job in (("InBack", '-Y', "input port (back)"), ("InL", '-X', "input port (left)"),
                   ("InR", '+X', "input port (right)"), ("Out", '+Y', "output port: the lit collar")):
    pipe_port(n, ax, R, flange=False, neck_from=0.26, drum_r=R, light=(n == "Out"))
    part(n, job, "Drum", "through")
    part(n + "Throat", "dark bore into the drum", n + "Neck", "inset", joins=("Drum",))

kit.finish("SM_Merger")

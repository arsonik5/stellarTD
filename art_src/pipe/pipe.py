"""Vacuum Pipe (scenes/pipe_segment.tscn 'Body'), MODULAR: the game lays the parts out for any length, nothing that has
a fixed size is ever stretched (scripts/world/pipe_segment.gd set_span()).
Origin = pipe centreline (Godot y 0.45 in the scene). Blender +Y = Godot -Z = the flow / forward direction.
  SM_VacuumPipe              the tube: glass + four guide rails, exactly 1 m long, centred; the game scales ONLY this,
                             along its length, to span - 2 collars (its cross-section never changes)
  SM_VacuumPipe_EndIn        input collar, origin on its mating face (game: +span/2)
  SM_VacuumPipe_EndOut       output collar, origin on its mating face (game: -span/2)
  SM_VacuumPipe_SupportHead  cradle + strap round the rails (repeated along long runs)
  SM_VacuumPipe_SupportPost  the post, origin at its top, exactly 1 m in Blender preview length: the game scales it
                             to reach the ground
  SM_VacuumPipe_SupportBase  bolted base plate, origin on its top face: the game puts it on the ground
Blender lays them out as one module with collars on a stand 0.45 m above ground so the audit checks the real joints."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector

kit.begin(kit.out_dir())
TL = 1.0                            # tube module length (scaled by the game)
G = -0.45                           # ground under a pipe at the default height
GR = 0.25                           # glass outer radius
RAIL_R = 0.012
RR = GR + RAIL_R                    # rails rest on the glass
EF = TL / 2 + COLLAR_W              # collar mating faces in the preview (the glass butts the collars' backs)
# tube: 1 m module. The glass stands in the collars; the rails run collar to collar on top of the glass
tube("Glass", GR, 0.235, TL, (0, 0, 0), GLASS, seg=32, axis='Y', bevel=0.0)
part("Glass", "glass tube: items are pulled through it by vacuum, you see them pass", "EndInCollar", "inset",
     joins=("EndOutCollar",))
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    cyl(f"Rail{k}", RAIL_R, TL, (math.cos(a) * RR, 0, math.sin(a) * RR), BARE, seg=8, axis='Y', bevel=0.0)
part("Rail", "guide rail: carries the glass between the collars, takes the support's load", "Glass", "seated",
     joins=("EndInCollar", "EndOutCollar"))
with group("EndIn"):
    pipe_collar("EndIn", '-Y', EF)
with group("EndOut"):
    pipe_collar("EndOut", '+Y', EF)
part("EndIn", "input collar: bolts to the previous pipe, knee or port", "Glass", "inset", joins=("Rail",))
part("EndOut", "output collar: bolts to the next pipe, knee or port", "Glass", "inset", joins=("Rail",))
# support: a pipe clamp. A rubber liner grips the glass all round (the rails run through it); the cradle's lower
# half-band and a bolted top strap both sit on the liner, so nothing hangs off the pipe. Post down to a base plate.
CR = RR + RAIL_R + 0.004             # liner outer radius = clamp bore (the liner covers the rails)
LW = 0.07                            # liner width (wider than the clamp bands, so its edge shows)
ear = CR + 0.065
zb = -(CR + 0.06)
with group("SupportHead"):
    tube("SupportLiner", CR, GR, LW, (0, 0, 0), RUB, seg=32, axis='Y', bevel=0.0)
    lower = [(math.cos(t) * CR, math.sin(t) * CR) for t in [math.pi + math.pi * k / 20 for k in range(21)]]
    cradle = [(-ear, 0.0)] + lower + [(ear, 0.0), (ear, -0.025), (CR * 0.6, zb), (-CR * 0.6, zb), (-ear, -0.025)]
    profile("SupportCradle", cradle, (0, 0, 0), (0, 1, 0), 0.05, SEC, up=(0, 0, 1), bevel=0.004)
    ro = CR + 0.012
    upper = [(math.cos(t) * ro, math.sin(t) * ro) for t in [math.pi * k / 20 for k in range(21)]]
    inner = [(math.cos(t) * CR, math.sin(t) * CR) for t in [math.pi * (20 - k) / 20 for k in range(21)]]
    # top strap: half-band with flat flanges that lie on the cradle ears
    strap = [(ear, 0.012), (ro, 0.012)] + upper[1:-1] + [(-ro, 0.012), (-ear, 0.012), (-ear, 0.0)] + inner + [(ear, 0.0)]
    profile("SupportStrap", strap, (0, 0, 0), (0, 1, 0), 0.05, BARE, up=(0, 0, 1), bevel=0.0)
    for s in (-1, 1):
        for dy in (-0.012, 0.012):
            cyl(f"SupportStrapBolt{s}{dy}", 0.008, 0.01, (s * (CR + 0.035), dy, 0.012 + 0.005), BARE, seg=6, bevel=0.0)
part("SupportLiner", "rubber liner: grips the glass, the rails run through it", "Glass", "clamped", joins=("Rail",))
part("SupportCradle", "cradle: lower half of the clamp, on the post", "SupportPost", "welded", joins=("SupportLiner",))
part("SupportStrap", "top strap: upper half of the clamp, its flanges bolted to the cradle ears", "SupportCradle", "bolted",
     joins=("SupportLiner",))
PT = zb                              # post top (under the cradle)
PB = G + 0.018                       # post bottom (on the base plate)
with group("SupportPost"):
    cyl("SupportPost", 0.035, PT - PB, (0, 0, (PT + PB) / 2), SEC, seg=16, bevel=0.0)
    weld_ring("SupportPostWeldTop", (0, 0, PT - WELD_R * 0.5), 0.035 + WELD_R * 0.4)
part("SupportPost", "post: carries the cradle, stretched by the game down to the ground", "SupportBase", "welded")
with group("SupportBase"):
    base_plate("SupportBase", (0, 0, G), 0.2, 0.14, t=0.018, bolt_inset=0.025)
    weld_ring("SupportPostWeldBase", (0, 0, PB + WELD_R * 0.5), 0.035 + WELD_R * 0.4)
part("SupportBase", "base plate: bolted to the ground or a foundation", "ground", "ground")

print("REPORT pipe layout: post preview length %.4f m (scale = wanted / this)" % (PT - PB))
kit.finish("SM_VacuumPipe", pivots={"EndIn": (0, -EF, 0), "EndOut": (0, EF, 0),
                                    "SupportHead": (0, 0, 0), "SupportPost": (0, 0, PT), "SupportBase": (0, 0, G)})

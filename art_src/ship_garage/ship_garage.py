"""Ship Garage (scenes/ship_garage.tscn) - 3.0 x 1.5 x 3.0, origin bottom-centre. Assembly pad: a raised deck on a
skid with hazard edges and a landing mark, two gantry towers at the back, each with a crane arm on a slew bearing
reaching over the pad; a trolley runs along each arm and lowers its welding tool on a cable.
The middle stays open - ships are built above the deck (scene marker at 1.55 m)."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Matrix

kit.begin(kit.out_dir())
W, DZ = 3.0, 0.28
skid(W, z1=0.16, casting=0.3)
octo("Deck", W - 0.16, W - 0.16, 0.3, 0.16, DZ, PRI, bevel=0.01)
part("Deck", "pad deck: ships are assembled on it", "SkidBeam", "seated", joins=("SkidDeck",))
for s in (-1, 1):                                            # deck bolted down along its edges
    for k in range(5):
        t = -1.0 + k * 0.5
        if not (s > 0 and abs(t) > 0.9):                   # not under the tower feet
            cyl(f"DeckBoltX{s}{k}", 0.014, 0.016, (t, s * (W / 2 - 0.13), DZ + 0.008), BARE, seg=6, bevel=0.0)
        if t < 0.9:
            cyl(f"DeckBoltY{s}{k}", 0.014, 0.016, (s * (W / 2 - 0.13), t, DZ + 0.008), BARE, seg=6, bevel=0.0)
# markings, set into the deck
for s in (-1, 1):
    box(f"HazX{s}", (W - 0.6, 0.16, 0.012), (0, s * (W / 2 - 0.25), DZ - 0.004), HAZ, bevel=0.0)
    box(f"HazY{s}", (0.16, W - 0.92, 0.012), (s * (W / 2 - 0.25), 0, DZ - 0.004), HAZ, bevel=0.0)
part("Haz", "hazard edge: keep clear of the pad while a ship is built", "Deck", "inset")
tube("PadRing", 0.95, 0.85, 0.012, (0, 0, DZ - 0.004), BARE, seg=48, bevel=0.0)
part("PadRing", "landing ring marking", "Deck", "inset")
for a in (0, 90):
    box(f"PadCross{a}", (1.2, 0.06, 0.012), (0, 0, DZ - 0.004 + (0.001 if a else 0)), SEC, bevel=0.0, rot=rotz(a))
part("PadCross", "centre mark", "Deck", "inset", joins=("PadCross",))
for k in range(8):
    a = math.radians(k * 45)
    cyl(f"PadLight{k}", 0.035, 0.02, (math.cos(a) * 1.08, math.sin(a) * 1.08, DZ - 0.002), STAT, seg=10, bevel=0.0)
part("PadLight", "pad light: lit while the garage works", "Deck", "inset")

# gantry towers (back corners), slew bearing on top, crane arm over the pad, trolley + cable + tool
FT = DZ + 0.022                                              # top of the tower feet
TT = FT + 1.2                                                # top of the towers
AZ = TT + 0.06 + 0.09                                        # arm centre height (over the slew bearing)
anims = []
for s in (-1, 1):
    x = s * 1.2
    base_plate(f"TowerFoot{s}", (x, 1.2, DZ), 0.5, 0.5, t=0.022, bolt_inset=0.04)
    tw = box(f"Tower{s}", (0.24, 0.24, 1.2), (x, 1.2, FT + 0.6), SEC, bevel=0.012, taper=0.85)
    box_weld(f"TowerWeld{s}_", tw, bpy.data.objects[f"TowerFoot{s}"])
    for gd in ((1, 0), (-1, 0), (0, -1)):
        gusset(f"TowerGusset{s}{gd}", (x + gd[0] * 0.12, 1.2 + gd[1] * 0.12, FT), gd, 0.11, 0.3, t=0.045)
    cyl(f"Slew{s}", 0.1, 0.06, (x, 1.2, TT + 0.03), BARE, seg=20)
    box(f"ArmCap{s}", (0.18, 0.22, 0.18), (x, 1.2, AZ), SEC, bevel=0.01)
    arm = box(f"Arm{s}", (0.14, 1.7, 0.14), (x, 1.2 - 0.11 - 0.85, AZ), PRI, bevel=0.01)
    box_weld(f"ArmWeld{s}_", arm, bpy.data.objects[f"ArmCap{s}"])
    TZ = AZ - 0.07 - 0.05                                    # trolley centre: hangs under the arm
    with group(f"Crane{s}"):
        box(f"Trolley{s}", (0.2, 0.2, 0.1), (x, 0.3, TZ), SEC, bevel=0.008)
        cyl(f"Cable{s}", 0.012, 0.3, (x, 0.3, TZ - 0.05 - 0.15), BARE, seg=8, bevel=0.0)
        box(f"Tool{s}", (0.12, 0.12, 0.12), (x, 0.3, TZ - 0.05 - 0.3 - 0.06 + 0.005), BARE, bevel=0.008)
        cyl(f"ToolTip{s}", 0.03, 0.06, (x, 0.3, TZ - 0.05 - 0.3 - 0.12 - 0.03 + 0.01), HEAT, seg=8, bevel=0.0)
    anims += [swing(f"Crane{s}", 1, [(0.0, 0.0), (1.5, -0.55 if s < 0 else 0.4), (2.5, -0.55 if s < 0 else 0.4), (4.0, 0.0)], path="location"),
              swing(f"Crane{s}", 2, [(0.0, 0.0), (1.7, -0.12), (2.3, -0.12), (2.6, 0.0), (4.0, 0.0)], path="location")]
part("TowerFoot", "tower foot: bolted to the deck", "Deck", "bolted")
part("Tower", "gantry tower: carries the crane", "TowerFoot", "welded")
part("TowerGusset", "gusset: braces the tower on its foot", "TowerFoot", "welded", joins=("Tower",))
part("Slew", "slew bearing: the crane arm swings on it", "Tower", "bolted")
for s in (-1, 1):
    bolts(f"SlewBolt{s}", (s * 1.2, 1.2, TT), '+Z', 0.105, 6, r=0.009, h=0.01)
part("ArmCap", "arm head: sits on the slew bearing, the arm is welded into it", "Slew", "pivot")
part("Arm", "crane arm: the trolley runs along under it", "ArmCap", "welded")
part("Trolley", "trolley: runs along the arm", "Arm", "pivot")
part("Cable", "hoist cable", "Trolley", "inset")
part("Tool", "welding head on the cable", "Cable", "inset")
part("ToolTip", "welding tip (hot)", "Tool", "inset")
kit.finish("SM_ShipGarage", pivots={"Crane-1": (-1.2, 0.3, TZ), "Crane1": (1.2, 0.3, TZ)}, anims=anims)

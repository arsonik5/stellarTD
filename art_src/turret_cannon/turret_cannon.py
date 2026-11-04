"""Cannon (scenes/turret_cannon.tscn) - slow, heavy splash: one thick barrel, big muzzle brake, shell rack.
Exports SM_TurretCannon (base) and the moving meshes _Head (yaw, origin = Head pivot, Godot (0,1.5,0)), _Cradle (pitch,
on the trunnion axis) and _Barrel (recoil). Barrel points Blender +Y (Godot -Z). Muzzle 0.9 m ahead of the pivot,
0.15 m up (the scene's Muzzle marker). Shells stand in a rack on the deck; a chute carries them into the pedestal and up
its middle to the breech (the rotating head is fed from the centre)."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Matrix, Vector

kit.begin(kit.out_dir())
PZ = 1.5
BZ = PZ + 0.15
TZ = BZ - 0.06

# ---- base: wider, heavier pedestal and its slew ring
skid(1.5)
shape = housing(1.16, 0.12, 1.0, chamfer=0.24, belt=0.6, taper=0.88, posts=True, name="Pedestal", panels={
    '-X0': ('door', "service door to the slew drive motor")})
part("Pedestal", "pedestal: carries the slew ring at aiming height, the slew drive is inside", "Skid", "bolted")
RT = 1.05
tube("SlewRing", 0.48, 0.36, 0.06, (0, 0, RT + 0.03), BARE, seg=48, bevel=0.004)
part("SlewRing", "slew bearing outer race: bolted to the pedestal, the head turns in it", "PedestalTrimHigh", "bolted")
bolts("SlewBolt", (0, 0, RT + 0.06), '+Z', 0.42, 18, r=0.011, h=0.012, start=math.pi / 18)

# ---- shell rack on the deck (+X side), chute into the pedestal
HX0, HX1 = 0.63, 0.74
HZ1 = 0.78                                                 # rack top
plate("RackBase", ((HX0 + HX1) / 2, 0.0, 0.12), (0, 0, 1), HX1 - HX0 + 0.01, 0.66, t=0.016, clip=0.02, mat=SEC, up=(0, 1, 0), bolts_on=False)
for sy in (-1, 1):
    cyl(f"RackBaseBolt{sy}", 0.012, 0.014, ((HX0 + HX1) / 2, sy * 0.3, 0.136 + 0.007), BARE, seg=6, bevel=0.0)
part("RackBase", "rack base plate: bolted to the deck", "SkidDeck", "bolted", joins=("SkidBeam",))
rack = box("Rack", (HX1 - HX0, 0.52, HZ1 - 0.136), ((HX0 + HX1) / 2, 0.0, (0.136 + HZ1) / 2), SEC, bevel=0.01)
box_weld("RackWeld_", rack, bpy.data.objects["RackBase"])
part("Rack", "shell rack: holds the shells upright", "RackBase", "welded")
box("RackFloor", (HX1 - HX0 - 0.03, 0.48, 0.006), ((HX0 + HX1) / 2, 0.0, HZ1 - 0.003), RUB, bevel=0.0)
part("RackFloor", "rack opening (dark): the shells stand in it", "Rack", "inset")
for i in range(4):
    y = -0.18 + i * 0.12
    cyl(f"Shell{i}", 0.045, 0.14, ((HX0 + HX1) / 2, y, HZ1 - 0.02 + 0.07), BARE, seg=12)
    cyl(f"ShellTip{i}", 0.045, 0.045, ((HX0 + HX1) / 2, y, HZ1 + 0.05 + 0.0225), SEC, seg=12, r2=0.018, bevel=0.0)
part("Shell", "shell case, standing in the rack", "RackFloor", "inset", joins=("Rack",))
part("ShellTip", "shell head", "Shell", "inset")
box("RackHaz", (0.006, 0.36, 0.06), (HX1 + 0.003, 0.0, 0.45), HAZ, bevel=0.0)
part("RackHaz", "explosives warning band", "Rack", "inset")
fz = 0.82
wp, wn = shape.at('+X', -0.33, fz)
p0 = Vector(((HX0 + HX1) / 2, -0.26, 0.45))
pipe("Feed", [tuple(p0), tuple(p0 + Vector((0, -0.08, 0))), ((HX0 + HX1) / 2, -0.34, fz - 0.12), tuple(wp + wn * 0.14), tuple(wp)],
     0.055, RUB, fillet=0.1)
part("Feed", "shell chute: carries the shells from the rack into the pedestal", "Rack", "through", joins=("Pedestal",))
fitting("FeedFitRack", tuple(p0 + Vector((0, -0.0495, 0))), (0, -1, 0), 0.055)
fitting("FeedFitWall", tuple(wp + wn * 0.0495), tuple(wn), 0.055)

# ---- head: turntable in the slew ring, a deck, a yaw fork carrying the pitching cradle; the barrel recoils.
# In game: rotate _Head about Y (yaw), _Cradle about its local X (pitch), play Fire on _Barrel.
with group("Head"):
    cyl("Turntable", 0.36, 0.08, (0, 0, RT + 0.04), SEC, seg=48, bevel=0.006)
    part("Turntable", "inner race: turns in the slew ring, carries the head deck", "SlewRing", "pivot")
    DZ = RT + 0.08
    cyl("HeadDeck", 0.58, 0.05, (0, 0, DZ + 0.025), SEC, seg=56, bevel=0.008)
    part("HeadDeck", "head deck: the fork stands on it", "Turntable", "bolted")
    bolts("HeadDeckBolt", (0, 0, DZ + 0.05), '+Z', 0.26, 10, r=0.012, h=0.013, start=math.pi / 10)
    D1 = DZ + 0.05
    for s in (-1, 1):
        prof = [(-0.26, 0.0), (0.26, 0.0), (0.14, TZ - D1 - 0.03), (0.1, TZ - D1 + 0.08),
                (0.0, TZ - D1 + 0.12), (-0.1, TZ - D1 + 0.08), (-0.14, TZ - D1 - 0.03)]
        profile(f"ForkArm{s}", prof, (s * 0.415, -0.1, D1), (1, 0, 0), 0.07, SEC, up=(0, 0, 1), bevel=0.01)
        for sd in (-1, 1):
            xw = s * 0.415 + sd * (0.035 + WELD_R * 0.6)
            weld(f"ForkWeld{s}{sd}", [(xw, -0.35, D1 + WELD_R * 0.6), (xw, 0.15, D1 + WELD_R * 0.6)])
        cyl(f"Bearing{s}", 0.1, 0.1, (s * 0.415, -0.1, TZ), BARE, seg=24, axis='X', bevel=0.006)
        bolts(f"BearingBolt{s}", (s * 0.465, -0.1, TZ), ('+X' if s > 0 else '-X'), 0.075, 6, r=0.011, h=0.012, start=math.pi / 6)
    part("ForkArm", "fork arm: carries the cradle's trunnion bearing", "HeadDeck", "welded")
    part("Bearing", "trunnion bearing: pressed into the fork arm, held by its bolts", "ForkArm", "inset")

with group("Cradle"):
    front = yring(squircle(0.3, 0.15, 3.0), 0.26, TZ + 0.05)
    loft("Body", [yring(squircle(0.3, 0.16, 3.0), -0.56, TZ), yring(squircle(0.36, 0.21, 3.6), -0.32, TZ),
                  yring(squircle(0.36, 0.21, 3.6), 0.02, TZ), front], PRI, bevel=0.014)
    part("Body", "cradle: holds the breech, pitches on the trunnions", "Trunnion", "inset")
    for s in (-1, 1):
        cyl(f"Trunnion{s}", 0.06, 0.07, (s * 0.37, -0.1, TZ), BARE, seg=16, axis='X', bevel=0.004)
    part("Trunnion", "trunnion pin: the cradle's pitch axle, turns in the fork bearing", "Bearing", "pivot",
         joins=("ForkArm", "Body"))
    plate("Rear", (0, -0.56, TZ), (0, -1, 0), 0.4, 0.18, t=0.018, clip=0.05)
    part("Rear", "breech cover: open it to clear a jammed shell", "Body", "bolted")
    MY = 0.26
    box("Mantlet", (0.66, 0.06, 0.36), (0, MY + 0.03, TZ + 0.05), SEC, bevel=0.01)
    part("Mantlet", "mantlet: front plate the gun comes out through", "Body", "welded")
    weld_loop("MantletWeld", [Vector(p) + Vector((p[0], 0, p[2] - TZ - 0.05)).normalized() * WELD_R * 0.6
                              - Vector((0, WELD_R * 0.6, 0)) for p in front])
    SY0 = MY + 0.06
    cyl("RecoilSleeve", 0.15, 0.3, (0, SY0 + 0.15, BZ), PRI, seg=32, axis='Y')
    part("RecoilSleeve", "recoil sleeve: the barrel slides back into it", "Mantlet", "welded")
    weld_ring("RecoilSleeveWeld", (0, SY0 + WELD_R * 0.5, BZ), 0.15 + WELD_R * 0.4, 'Y')
    sight = box("Periscope", (0.14, 0.14, 0.1), (0.0, -0.15, TZ + 0.21 + 0.05), SEC, bevel=0.006)
    box_weld("PeriscopeWeld_", sight, bpy.data.objects["Body"])
    part("Periscope", "gunner's sight: rides on the cradle", "Body", "welded")
    box("PeriscopeGlass", (0.1, 0.012, 0.045), (0.0, -0.15 + 0.07 + 0.004, TZ + 0.26), STAT, bevel=0.0)
    part("PeriscopeGlass", "sight glass", "Periscope", "inset")

with group("Barrel"):
    cyl("Barrel", 0.1, 0.9 - 0.52, (0, (0.52 + 0.9) / 2, BZ), BARE, seg=24, axis='Y')
    part("Barrel", "barrel: recoils into the sleeve", "RecoilSleeve", "pivot")
    tube("BarrelHaz", 0.105, 0.09, 0.04, (0, 0.72, BZ), HAZ, seg=24, axis='Y', bevel=0.0)
    part("BarrelHaz", "muzzle danger band", "Barrel", "inset")
    box("Brake", (0.3, 0.1, 0.18), (0, 0.85, BZ), SEC, bevel=0.01)
    part("Brake", "muzzle brake: vents the blast sideways", "Barrel", "inset")
    for s in (-1, 1):
        box(f"BrakePort{s}", (0.006, 0.07, 0.1), (s * 0.149, 0.85, BZ), RUB, bevel=0.0)
    part("BrakePort", "brake vent port (dark)", "Brake", "inset")
    cyl("Bore", 0.085, 0.006, (0, 0.9 - 0.003, BZ), RUB, seg=24, axis='Y', bevel=0.0)
    part("Bore", "bore (dark)", "Brake", "inset", joins=("Barrel",))

kit.finish("SM_TurretCannon", pivots={"Head": (0, 0, PZ), "Cradle": (0, -0.1, TZ), "Barrel": (0, 0, BZ)},
           parents={"Cradle": "Head", "Barrel": "Cradle"},
           anims=[swing("Barrel", 1, [(0.0, 0.0), (0.05, -0.16), (0.7, 0.0)], path="location", track="Fire")])

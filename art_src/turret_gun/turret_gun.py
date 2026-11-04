"""Gun Turret (scenes/turret_gun.tscn) - fast, light: slim twin guns.
Exports SM_TurretGun (base, origin 0) plus the moving meshes _Head (yaw, origin = Head pivot, Godot (0,1.5,0)),
_Cradle (pitch, on the trunnion axis) and _Barrels (recoil). Barrels point Blender +Y (Godot -Z, the Head's forward).
Muzzle 1.2 m ahead of the pivot, 0.15 m up (the scene's Muzzle marker).
The pedestal holds the slew drive; the head turns on the slew ring; ammo comes from the magazine on the deck through
a flexible chute into the pedestal and up its middle (the rotating head is fed from the centre)."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Matrix, Vector

kit.begin(kit.out_dir())
PZ = 1.5          # head pivot height
BZ = PZ + 0.15    # barrel axis height
TZ = BZ - 0.05    # trunnion (pitch) axis height

# ---- base: skid, pedestal, slew ring
skid(1.5)
shape = housing(1.0, 0.12, 1.02, chamfer=0.22, taper=0.8, posts=True, name="Pedestal", panels={
    '+X0': ('door', "service door to the slew drive motor")})
part("Pedestal", "pedestal: carries the slew ring at aiming height, the slew drive is inside", "Skid", "bolted")
RT = 1.07                                                       # top of the pedestal rim
tube("SlewRing", 0.4, 0.3, 0.06, (0, 0, RT + 0.03), BARE, seg=48, bevel=0.004)
part("SlewRing", "slew bearing outer race: bolted to the pedestal, the head turns in it", "PedestalTrimHigh", "bolted")
bolts("SlewBolt", (0, 0, RT + 0.06), '+Z', 0.35, 16, r=0.01, h=0.012, start=math.pi / 16)

# ---- magazine on the deck, chute into the pedestal
MX = -0.65
base_plate("MagBase", (MX, 0.0, 0.12), 0.2, 0.64, t=0.016, bolt_inset=0.03)
part("MagBase", "magazine base plate: bolted to the deck", "SkidDeck", "bolted", joins=("SkidBeam",))
MZ0 = 0.136
mag = box("Mag", (0.2, 0.5, 0.46), (MX, 0.0, MZ0 + 0.23), SEC, bevel=0.012)
box_weld("MagWeld_", mag, bpy.data.objects["MagBase"])
part("Mag", "ammo magazine: holds the belt", "MagBase", "welded")
box("MagLid", (0.2, 0.5, 0.03), (MX, 0.0, MZ0 + 0.46 + 0.015), PRI, bevel=0.006)
part("MagLid", "magazine lid: lifts off to reload", "Mag", "hinged")
for i in range(3):
    box(f"MagRib{i}", (0.21, 0.025, 0.42), (MX, -0.18 + i * 0.18, MZ0 + 0.23), SEC, bevel=0.003)
part("MagRib", "stiffening band round the magazine", "Mag", "inset")
# chute: out of the magazine's front, up, and into the pedestal wall square to it
fz = 0.85
wp, wn = shape.at('-X', 0.33, fz)
p0 = Vector((MX, -0.25, 0.45))
pipe("Feed", [tuple(p0), tuple(p0 + Vector((0, -0.08, 0))), (MX, -0.33, fz - 0.12), tuple(wp + wn * 0.14), tuple(wp)],
     0.045, RUB, fillet=0.1)
part("Feed", "ammo chute: carries the belt from the magazine into the pedestal", "Mag", "through", joins=("Pedestal",))
fitting("FeedFitMag", tuple(p0 + Vector((0, -0.0405, 0))), (0, -1, 0), 0.045)
fitting("FeedFitWall", tuple(wp + wn * 0.0405), tuple(wn), 0.045)

# ---- head: a turntable in the slew ring, a deck on it, a yaw fork carrying the pitching cradle on trunnions.
# In game: rotate _Head about Y (yaw), _Cradle about its local X (pitch), play Fire on _Barrels.
with group("Head"):
    cyl("Turntable", 0.3, 0.08, (0, 0, RT + 0.04), SEC, seg=40, bevel=0.006)
    part("Turntable", "inner race: turns in the slew ring, carries the head deck", "SlewRing", "pivot")
    DZ = RT + 0.08                                              # deck underside (clear of the slew bolts)
    cyl("HeadDeck", 0.4, 0.04, (0, 0, DZ + 0.02), SEC, seg=48, bevel=0.006)
    part("HeadDeck", "head deck: the fork stands on it", "Turntable", "bolted")
    bolts("HeadDeckBolt", (0, 0, DZ + 0.04), '+Z', 0.2, 8, r=0.011, h=0.012, start=math.pi / 8)
    D1 = DZ + 0.04
    for s in (-1, 1):
        # fork arm: wide at the deck, narrowing to the bearing, rounded top (profile seen from the side)
        prof = [(-0.2, 0.0), (0.2, 0.0), (0.11, TZ - D1 - 0.02), (0.08, TZ - D1 + 0.06),
                (0.0, TZ - D1 + 0.09), (-0.08, TZ - D1 + 0.06), (-0.11, TZ - D1 - 0.02)]
        profile(f"ForkArm{s}", prof, (s * 0.31, 0, D1), (1, 0, 0), 0.06, SEC, up=(0, 0, 1), bevel=0.008)
        for sd in (-1, 1):                                # arm welded to the deck, both sides
            xw = s * 0.31 + sd * (0.03 + WELD_R * 0.6)
            weld(f"ForkWeld{s}{sd}", [(xw, -0.19, D1 + WELD_R * 0.6), (xw, 0.19, D1 + WELD_R * 0.6)])
        cyl(f"Bearing{s}", 0.075, 0.09, (s * 0.31, 0, TZ), BARE, seg=24, axis='X', bevel=0.006)
        bolts(f"BearingBolt{s}", (s * 0.355, 0, TZ), ('+X' if s > 0 else '-X'), 0.055, 4, r=0.01, h=0.012, start=math.pi / 4)
    part("ForkArm", "fork arm: carries the cradle's trunnion bearing", "HeadDeck", "welded")
    part("Bearing", "trunnion bearing: pressed into the fork arm, held by its bolts", "ForkArm", "inset")

with group("Cradle"):
    ring_front = yring(squircle(0.17, 0.11, 3.0), 0.27, TZ + 0.03)
    loft("Body", [yring(squircle(0.19, 0.11, 3.2), -0.32, TZ), yring(squircle(0.24, 0.15, 3.6), -0.12, TZ),
                  yring(squircle(0.24, 0.15, 3.6), 0.1, TZ), ring_front], PRI, bevel=0.012)
    part("Body", "cradle: holds the guns' breeches, pitches on the trunnions", "Trunnion", "inset")
    for s in (-1, 1):
        cyl(f"Trunnion{s}", 0.045, 0.07, (s * 0.255, 0, TZ), BARE, seg=16, axis='X', bevel=0.004)
    part("Trunnion", "trunnion pin: the cradle's pitch axle, turns in the fork bearing", "Bearing", "pivot",
         joins=("ForkArm", "Body"))
    MY = 0.27                                                   # front of the cradle body
    box("Mantlet", (0.4, 0.05, 0.26), (0, MY + 0.025, TZ + 0.03), SEC, bevel=0.008)
    part("Mantlet", "mantlet: front plate the guns come out through", "Body", "welded")
    weld_loop("MantletWeld", [Vector(p) + Vector((p[0], 0, p[2] - TZ - 0.03)).normalized() * WELD_R * 0.6
                              - Vector((0, WELD_R * 0.6, 0)) for p in ring_front])
    sensor = box("Sensor", (0.12, 0.12, 0.08), (0.0, -0.05, TZ + 0.15 + 0.04), SEC, bevel=0.006)
    box_weld("SensorWeld_", sensor, bpy.data.objects["Body"])
    part("Sensor", "targeting sensor: on the cradle, so it looks where the guns point", "Body", "welded")
    cyl("SensorLens", 0.03, 0.012, (0.0, 0.01 + 0.006, TZ + 0.19), STAT, seg=12, axis='Y', bevel=0.0)
    part("SensorLens", "sensor lens", "Sensor", "inset")
    SY0, SY1 = MY + 0.05, MY + 0.05 + 0.42
    for s in (-1, 1):
        x = s * 0.09
        cyl(f"Shroud{s}", 0.055, SY1 - SY0, (x, (SY0 + SY1) / 2, BZ), SEC, seg=16, axis='Y')
        weld_ring(f"ShroudWeld{s}", (x, SY0 + WELD_R * 0.5, BZ), 0.055 + WELD_R * 0.4, 'Y')
        for k in range(4):
            box(f"ShroudVent{s}{k}", (0.03, 0.05, 0.012), (x, SY0 + 0.08 + k * 0.08, BZ + 0.055 - 0.002), RUB, bevel=0.0)
    part("Shroud", "barrel shroud: the barrel slides in it when it recoils", "Mantlet", "welded")
    part("ShroudVent", "cooling slot in the shroud", "Shroud", "inset")

with group("Barrels"):
    for s in (-1, 1):
        x = s * 0.09
        cyl(f"Barrel{s}", 0.03, 0.55, (x, 0.95, BZ), BARE, seg=12, axis='Y')
        cyl(f"Brake{s}", 0.045, 0.08, (x, 1.16, BZ), SEC, seg=12, axis='Y')
        tube(f"MuzzleHaz{s}", 0.048, 0.028, 0.03, (x, 1.105, BZ), HAZ, seg=12, axis='Y', bevel=0.0)
        cyl(f"Bore{s}", 0.022, 0.006, (x, 1.2 - 0.003, BZ), RUB, seg=12, axis='Y', bevel=0.0)
    part("Barrel", "barrel: recoils into the shroud", "Shroud", "pivot")
    part("Brake", "muzzle brake", "Barrel", "inset")
    part("MuzzleHaz", "muzzle danger band", "Barrel", "inset", joins=("Brake",))
    part("Bore", "bore (dark)", "Brake", "inset")

kit.finish("SM_TurretGun", pivots={"Head": (0, 0, PZ), "Cradle": (0, 0, TZ), "Barrels": (0, 0, BZ)},
           parents={"Cradle": "Head", "Barrels": "Cradle"},
           anims=[swing("Barrels", 1, [(0.0, 0.0), (0.03, -0.07), (0.2, 0.0)], path="location", track="Fire")])

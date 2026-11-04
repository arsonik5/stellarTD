"""Chest (scenes/chest.tscn) - storage: a mini cargo container on a skid. Corner posts, rails and top castings are the
frame, the corrugated shell is welded into it, twin doors on the front hang on hinges and lock with turning bars.
A round pipe port on each side wall (chests feed and get pulled from either side).
Footprint 1.5 x 1.5, origin bottom-centre, doors = front = Blender -Y."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *

kit.begin(kit.out_dir())

skid(1.5, z1=0.1, casting=0.2)
Z0, Z1, W = 0.1, 1.1, 1.36
H = W / 2
PS = 0.1                                   # post size
ZT = Z1 - 0.08                             # top of the posts (castings above)
# frame: corner posts on the skid, castings on top, bottom + top rails between the posts
for sx in (-1, 1):
    for sy in (-1, 1):
        p = box(f"Post_{sx}_{sy}", (PS, PS, ZT - Z0), (sx * (H - PS / 2), sy * (H - PS / 2), (Z0 + ZT) / 2), SEC, bevel=0.008)
        c = box(f"TopCast_{sx}_{sy}", (0.12, 0.12, Z1 - ZT), (sx * (H - PS / 2), sy * (H - PS / 2), (ZT + Z1) / 2), SEC, bevel=0.008)
        box_weld(f"TopCastWeld_{sx}_{sy}_", p, c)
part("Post", "corner post: the container frame's upright", "SkidCasting", "welded")
for sx in (-1, 1):                                           # posts welded onto the skid's corner castings
    for sy in (-1, 1):
        box_weld(f"PostWeld_{sx}_{sy}_", bpy.data.objects[f"Post_{sx}_{sy}"], bpy.data.objects[f"SkidCasting_{sx}_{sy}"])
part("TopCast", "top corner casting: lifting and stacking point", "Post", "welded")
L = W - 2 * PS
for k, (z0, z1) in enumerate(((Z0, Z0 + 0.08), (ZT - 0.08, ZT))):
    for sy in (-1, 1):
        r = box(f"RailX{k}_{sy}", (L, 0.08, z1 - z0), (0, sy * (H - 0.04), (z0 + z1) / 2), SEC, bevel=0.008)
        for sx in (-1, 1):
            box_weld(f"RailXWeld{k}_{sy}_{sx}_", r, bpy.data.objects[f"Post_{sx}_{sy}"])
    for sx in (-1, 1):
        r = box(f"RailY{k}_{sx}", (0.08, L, z1 - z0), (sx * (H - 0.04), 0, (z0 + z1) / 2), SEC, bevel=0.008)
        for sy in (-1, 1):
            box_weld(f"RailYWeld{k}_{sx}_{sy}_", r, bpy.data.objects[f"Post_{sx}_{sy}"])
part("Rail", "side rail: ties the posts together, the shell is welded into it", "Post", "welded")

# shell: the box the goods sit in, welded into the frame; corrugation stiffens the walls
box("Body", (W - 0.16, W - 0.16, ZT - Z0), (0, 0, (Z0 + ZT) / 2), PRI, bevel=0.01)
part("Body", "container shell: holds the goods", "Rail", "inset", joins=("Post",))
n, span = 7, W - 0.24
for i in range(n):
    t = -span / 2 + span * (i + 0.5) / n
    for sx in (-1, 1):
        if abs(t) < 0.3:          # side walls are flat where the pipe ports go through
            continue
        box(f"RibX_{sx}_{i}", (0.035, 0.09, ZT - Z0 - 0.16), (sx * (H - 0.08 + 0.0125), t, (Z0 + ZT) / 2), PRI, bevel=0.006)
    box(f"RibB_{i}", (0.09, 0.035, ZT - Z0 - 0.16), (t, H - 0.08 + 0.0125, (Z0 + ZT) / 2), PRI, bevel=0.006)
part("Rib", "corrugation rib: stiffens the wall", "Body", "inset")

# doors: hinged on the front posts, locked by turning bars in cams
DF = -H                                    # front plane of the frame
DZ0, DZ1 = Z0 + 0.08, ZT - 0.08
DW = (L - 0.01) / 2
for sx in (-1, 1):
    xc = sx * (0.005 + DW / 2)
    box(f"Door{sx}", (DW, 0.04, DZ1 - DZ0), (xc, DF + 0.02, (DZ0 + DZ1) / 2), PRI, bevel=0.008)
    for k in (-1, 1):
        x = xc + k * 0.1
        for j, z in enumerate((DZ0 + 0.1, DZ1 - 0.1)):
            box(f"Cam_{sx}_{k}_{j}", (0.05, 0.04, 0.05), (x, DF - 0.02, z), BARE, bevel=0.004)
        cyl(f"LockBar_{sx}_{k}", 0.018, DZ1 - DZ0 - 0.1, (x, DF - 0.02, (DZ0 + DZ1) / 2), BARE, seg=12)
        box(f"Handle_{sx}_{k}", (0.12, 0.03, 0.025), (x + 0.06 * k, DF - 0.045, DZ0 + 0.35), BARE, bevel=0.003)
    for j, z in enumerate((DZ0 + 0.18, DZ1 - 0.18)):         # hinge: knuckle at the door edge, leaves on door and post
        ex = sx * (0.005 + DW)
        cyl(f"HingeKnuckle_{sx}_{j}", 0.015, 0.08, (ex, DF - 0.015, z), BARE, seg=12, bevel=0.0)
        box(f"HingeLeafPost_{sx}_{j}", (0.06, 0.006, 0.06), (ex + sx * 0.03, DF - 0.003, z), SEC, bevel=0.0)
        box(f"HingeLeafDoor_{sx}_{j}", (0.06, 0.006, 0.06), (ex - sx * 0.03, DF - 0.003, z), SEC, bevel=0.0)
part("Door", "door leaf: closes the front", "HingeKnuckle", "hinged", joins=("Body",))
part("HingeKnuckle", "hinge knuckle: the door swings on its pin", "HingeLeafPost", "pivot", joins=("HingeLeafDoor", "Door"))
part("HingeLeafPost", "hinge leaf on the post", "Post", "welded")
part("HingeLeafDoor", "hinge leaf on the door", "Door", "welded")
part("Cam", "cam keeper: holds the lock bar on the door", "Door", "welded")
part("LockBar", "lock bar: turned by its handle, its cams lock the door shut", "Cam", "pivot")
part("Handle", "lock bar handle", "LockBar", "inset")
for sx in (-1, 1):
    for j in (0, 1):
        z = (DZ0 + 0.18, DZ1 - 0.18)[j]
        ex = sx * (0.005 + DW)
        for nm, xc in ((f"HingeLeafPost_{sx}_{j}", ex + sx * 0.03), (f"HingeLeafDoor_{sx}_{j}", ex - sx * 0.03)):
            weld(f"{nm}W", [(xc - 0.03, DF - 0.0045, z - 0.03 - WELD_R * 0.5), (xc + 0.03, DF - 0.0045, z - 0.03 - WELD_R * 0.5)])
    for k in (-1, 1):
        for j, z in enumerate((DZ0 + 0.1, DZ1 - 0.1)):
            x = sx * (0.005 + DW / 2) + k * 0.1
            weld(f"Cam_{sx}_{k}_{j}W", [(x - 0.025, DF - WELD_R * 0.6, z - 0.025 - WELD_R * 0.6),
                                        (x + 0.025, DF - WELD_R * 0.6, z - 0.025 - WELD_R * 0.6)])
# fill-level light on the front top rail
status_strip("FillBar", DF, ZT - 0.04, w=0.5, on="RailX1_-1")

# pipe ports through both side walls (chests feed and get pulled from either side)
machine_port("PortL", "-X", H - 0.08, 0.75, job="pipe port: items in or out", body="Body")
machine_port("PortR", "+X", H - 0.08, 0.75, job="pipe port: items in or out", body="Body")

kit.finish("SM_Chest")

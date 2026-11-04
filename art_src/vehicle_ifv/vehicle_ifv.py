"""Player vehicle 1: space IFV (infantry fighting vehicle) - BLOCKOUT. Origin on the ground under the hull centre,
Blender +Y forward (Godot -Z). ~6.1 m long, 3.1 m wide, 2.9 m to the sensor.
Layout: driver front-left behind the vision block, engine front-right under the deck grille (it shields the crew),
crew/troop bay behind them, out through the rear ramp. Faceted armour hull: narrow belly between the wheels,
sponsons over the wheels, sloped upper armour, upper + lower glacis. Six wheels (hub motors) on suspension arms
tucked under the sponsons. One-man turret on a ring: autocannon in a mantlet, sensor mast, commander's hatch.
Detail pass comes after Michael approves this blockout."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
from mathutils import Vector, Matrix

kit.begin(kit.out_dir())

def hull_ring(y, zb, zbelly, zsp0, zsp1, ztop, wb, wsp, wt):
    """Faceted section, counter-clockwise seen from +Y: belly, sponson underside, sponson edge, sloped upper armour."""
    half = [(wb, zb), (wb, zbelly), (wsp, zsp0), (wsp, zsp1), (wt, ztop)]
    pts = half + [(-x, z) for x, z in reversed(half)]
    return [(x, y, z) for x, z in pts]

rings = [hull_ring(-3.0, 0.55, 1.16, 1.2, 1.4, 1.85, 0.9, 1.55, 1.05),
         hull_ring(1.6, 0.55, 1.16, 1.2, 1.4, 1.85, 0.9, 1.55, 1.05),       # full section to the glacis
         hull_ring(2.55, 0.62, 1.16, 1.2, 1.38, 1.55, 0.88, 1.5, 0.98),     # upper glacis slopes down
         hull_ring(3.05, 0.9, 1.12, 1.16, 1.22, 1.27, 0.8, 1.25, 0.9)]     # nose
loft("Hull", rings, PRI, bevel=0.02)
part("Hull", "armoured hull: driver, engine and troop bay inside; sponsons cover the wheels", "Axle", "seated")
WR, WW, WX, WZ = 0.55, 0.42, 1.24, 0.55
for sx in (-1, 1):
    for k, y in enumerate((-2.1, -0.55, 1.0)):
        cyl(f"Wheel{sx}{k}", WR, WW, (sx * WX, y, WZ), RUB, seg=32, axis='X', bevel=0.02)
        cyl(f"Axle{sx}{k}", 0.09, WX - 0.9, (sx * (0.9 + (WX - 0.9) / 2), y, WZ), SEC, seg=16, axis='X', bevel=0.005)
part("Wheel", "wheel: drives the vehicle (hub motor)", "Axle", "pivot")
part("Axle", "suspension arm + half-shaft: carries the wheel off the belly", "ground", "ground", joins=("Hull",))
# driver vision block on the upper glacis, engine deck grille, rear ramp
gl = Vector((0, 2.55 - 1.6, 1.55 - 1.85)).normalized()            # upper glacis direction (down the slope)
nrm = Vector((0, -gl.z, gl.y))                                     # its outward normal
p = Vector((-0.45, 2.1, 1.85 + (2.1 - 1.6) / (2.55 - 1.6) * (1.55 - 1.85)))
box("VisionBlock", (0.45, 0.14, 0.03), tuple(p + nrm * 0.0), GLASS, bevel=0.0,
    rot=Matrix.Translation((0, 0, 0)) @ Matrix.Rotation(math.atan2(-gl.z, gl.y), 4, 'X'))
part("VisionBlock", "driver's vision block", "Hull", "inset")
q = Vector((0.45, 2.1, p.z))
box("EngineGrille", (0.7, 0.5, 0.02), tuple(q), RUB, bevel=0.0, rot=Matrix.Rotation(math.atan2(-gl.z, gl.y), 4, 'X'))
part("EngineGrille", "engine deck grille: the engine breathes through it", "Hull", "inset")
box("Ramp", (1.5, 0.08, 1.0), (0, -3.0 - 0.04, 1.22), SEC, bevel=0.01)
part("Ramp", "rear ramp: lowers for the troops to get in and out", "Hull", "hinged")
# turret
TZ = 1.85
cyl("TurretRing", 0.72, 0.08, (0, -0.5, TZ + 0.04), BARE, seg=48, bevel=0.005)
part("TurretRing", "turret ring: the turret turns on it", "Hull", "bolted")
def tring(y, w, wt, z0, z1):
    half = [(w, z0), (w, z0 + (z1 - z0) * 0.45), (wt, z1)]
    pts = half + [(-x, z) for x, z in reversed(half)]
    return [(x, y, z) for x, z in pts]
T0 = TZ + 0.08
loft("Turret", [tring(-1.15, 0.6, 0.45, T0, T0 + 0.42), tring(-0.75, 0.82, 0.6, T0, T0 + 0.5),
                tring(0.05, 0.82, 0.6, T0, T0 + 0.5), tring(0.45, 0.5, 0.36, T0 + 0.04, T0 + 0.4)], PRI, bevel=0.015)
part("Turret", "one-man turret: the gunner sits under it", "TurretRing", "pivot")
box("Mantlet", (0.44, 0.12, 0.3), (0.0, 0.45 + 0.06, T0 + 0.22), SEC, bevel=0.01)
part("Mantlet", "gun mantlet: the cannon pitches in it", "Turret", "welded")
cyl("Cannon", 0.06, 1.7, (0.0, 0.57 + 0.85, T0 + 0.22), BARE, seg=16, axis='Y', bevel=0.004)
part("Cannon", "autocannon barrel", "Mantlet", "pivot")
cyl("Muzzle", 0.09, 0.18, (0.0, 2.27 + 0.09, T0 + 0.22), SEC, seg=16, axis='Y', bevel=0.004)
part("Muzzle", "muzzle brake", "Cannon", "inset")
cyl("Mast", 0.04, 0.5, (-0.4, -0.7, T0 + 0.5 + 0.25), SEC, seg=12, bevel=0.0)
part("Mast", "sensor mast", "Turret", "bolted")
box("Sensor", (0.24, 0.16, 0.14), (-0.4, -0.7, T0 + 1.0 + 0.07), SEC, bevel=0.01)
part("Sensor", "sensor head: thermal + radar, sees for the gunner", "Mast", "welded")
cyl("Hatch", 0.26, 0.05, (0.3, -0.45, T0 + 0.5 + 0.025), SEC, seg=24, bevel=0.005)
part("Hatch", "commander's hatch", "Turret", "hinged")
kit.finish("SM_VehicleIFV")

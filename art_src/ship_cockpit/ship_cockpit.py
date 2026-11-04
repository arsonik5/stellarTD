"""Ship Cockpit (scenes/ship_cockpit.tscn) - 2.0 x 1.6 x 2.0 block, origin at the CENTRE, forward = Blender +Y
(Godot -Z). The CockpitCamera sits at Godot (0, 0.3, 0.2) = Blender (0, -0.2, 0.3): glass wraps the view forward,
sides and up, so the pilot sees out. Lower tub is armour, canopy has a strut frame."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kit
from kit import *
import bmesh
from mathutils import Matrix, Vector

kit.begin(kit.out_dir())
kit.DUST_AMT = 0.15
HW, HD, HH = 1.0, 1.0, 0.8
SILL = -0.05                      # canopy starts here
# lower tub
# tub: side silhouette with a raked nose and chin, extruded across the block
profile("Tub", [(-HD + 0.025, -HH), (HD - 0.32, -HH), (HD - 0.025, -HH + 0.3), (HD - 0.025, SILL), (-HD + 0.025, SILL)],
        (0, 0, 0), (1, 0, 0), 2 * HW - 0.05, SEC, bevel=0.014)
for s in (-1, 1):
    plate(f"TubSide{s}", (s * (HW - 0.025), 0.1, (SILL - HH) / 2 - 0.01), (s, 0, 0), 1.5, 0.58, t=0.022, clip=0.1, bolt_inset=0.06)
plate("TubBack", (0, -(HD - 0.025), (SILL - HH) / 2 - 0.05), (0, -1, 0), 1.5, 0.5, t=0.022, clip=0.1, bolt_inset=0.06)
for s in (-1, 1):
    box(f"SillRail{s}", (0.1, 2 * HD - 0.1, 0.08), (s * (HW - 0.08), 0, SILL + 0.04), SEC, bevel=0.012)
box("TubBand", (2 * HW - 0.02, 2 * HD - 0.02, 0.08), (0, 0, SILL - 0.04), SEC, bevel=0.006)
box("BackWall", (2 * HW, 0.12, HH - SILL), (0, -HD + 0.06, (HH + SILL) / 2), PRI, bevel=0.012)
# canopy glass: a wedge (front slope, roof, sides)
F0, F1 = HD, 0.15            # front glass runs from the nose (y=HD at sill) back to y=F1 at the roof
R = -HD + 0.12               # roof ends at the back wall
def quad(name, pts, mat):
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    face = bm.faces.new(vs)
    face.normal_update()
    n = face.normal.copy()
    # thicken into a closed slab
    res = bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]:
        v.co -= n * 0.02
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    set_mat(bm, mat)
    return make_obj(name, bm, 0.0)
quad("GlassFront", [(-HW + 0.06, F0 - 0.02, SILL), (HW - 0.06, F0 - 0.02, SILL), (HW - 0.085, F1, HH - 0.02), (-HW + 0.085, F1, HH - 0.02)], GLASS)
quad("GlassRoof", [(-HW + 0.085, F1, HH - 0.02), (HW - 0.085, F1, HH - 0.02), (HW - 0.085, R, HH - 0.02), (-HW + 0.085, R, HH - 0.02)], GLASS)
for s in (-1, 1):
    x = s * (HW - 0.04)
    pts = [(x, R, SILL), (x, F0 - 0.02, SILL), (x, F1, HH - 0.02), (x, R, HH - 0.02)]
    quad(f"GlassSide{s}", pts if s > 0 else list(reversed(pts)), GLASS)
# canopy struts (frame)
def strut(name, a, b, t=0.07):
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    box(name, (t, t, d.length), (0, 0, 0), SEC, bevel=0.008, rot=Matrix.Translation((a + b) / 2) @ rot)
for s in (-1, 1):
    x = s * (HW - 0.05)
    strut(f"Pillar{s}", (x, F0 - 0.1, SILL + 0.08), (x, F1, HH - 0.04))
    strut(f"RoofRail{s}", (x, F1, HH - 0.04), (x, R, HH - 0.04))
    strut(f"Rear{s}", (x, R + 0.04, SILL + 0.08), (x, R + 0.04, HH - 0.04))
    for yy in (F0 - 0.2, R + 0.12):                                               # pillar feet bolted to the sill rail
        cyl(f"PillarBolt{s}{yy:.2f}", 0.01, 0.012, (x - s * 0.05, yy, SILL + 0.086), BARE, seg=6, bevel=0.0)
strut("CentreBar", (0, F0 - 0.08, SILL), (0, F1, HH - 0.04), t=0.05)
strut("RoofBow", (-HW + 0.085, F1, HH - 0.04), (HW - 0.085, F1, HH - 0.04))
strut("RoofBow2", (-HW + 0.085, -0.45, HH - 0.04), (HW - 0.085, -0.45, HH - 0.04), t=0.05)
# interior: seat + console under the camera, visible through the glass
box("SeatBase", (0.5, 0.5, 0.25), (0, -0.35, SILL + 0.125), SEC, bevel=0.01)
box("SeatBack", (0.5, 0.12, 0.6), (0, -0.62, SILL + 0.45), SEC, bevel=0.012, rot=None)
box("Dash", (1.3, 0.3, 0.2), (0, 0.55, SILL + 0.1), SEC, bevel=0.01, taper=0.9)
box("DashScreen", (0.9, 0.02, 0.12), (0, 0.4, SILL + 0.17), STAT, bevel=0.0, rot=Matrix.Rotation(math.radians(-25), 4, 'X'))
for s in (-1, 1):
    box(f"Stick{s}", (0.04, 0.04, 0.22), (s * 0.32, -0.15, SILL + 0.11), BARE, bevel=0.004)
part("Tub", "armoured tub: the pilot sits in it, everything else is built on it", "ground", "ground")
part("TubSide", "side armour on the tub", "Tub", "bolted")
part("TubBack", "back armour on the tub", "Tub", "bolted")
part("TubBand", "rim band round the tub top: the canopy sill sits on it", "Tub", "inset")
part("SillRail", "sill rail: the canopy frame is bolted to it", "TubBand", "seated")
part("BackWall", "bulkhead behind the pilot: closes the canopy at the back", "TubBand", "seated", joins=("SillRail",))
part("GlassFront", "windscreen", "Pillar", "inset", joins=("CentreBar", "TubBand", "RoofBow", "Tub", "GlassSide", "GlassRoof", "SillRail"))
part("GlassRoof", "roof glass", "RoofRail", "inset", joins=("RoofBow", "Pillar", "BackWall", "GlassSide", "CentreBar"))
part("GlassSide", "side glass", "Pillar", "inset", joins=("RoofRail", "Rear", "SillRail", "BackWall", "TubBand"))
part("Pillar", "canopy pillar: carries the roof, its foot sits in a socket on the sill rail", "SillRail", "inset")
part("RoofRail", "roof rail: canopy frame", "Pillar", "inset")
part("Rear", "rear post: canopy frame", "SillRail", "inset", joins=("RoofRail", "BackWall"))
part("CentreBar", "centre bar: splits the windscreen, stiffens it", "TubBand", "inset", joins=("RoofBow", "Tub"))
part("RoofBow", "roof bow: ties the two roof rails", "RoofRail", "inset", joins=("Pillar",))
part("SeatBase", "seat base", "TubBand", "seated")
part("SeatBack", "seat back", "SeatBase", "inset")
part("Dash", "dashboard: holds the flight screen", "TubBand", "seated")
part("DashScreen", "flight screen", "Dash", "inset")
part("Stick", "control stick", "TubBand", "seated")
kit.finish("SM_ShipCockpit")

"""Ship / vehicle parts on the shared 0.5 m grid - BLOCKOUTS (sh art_src/build.sh part_<id> --blockout exports them
unbaked so they can be played). One function per part; art_src/part_<id>/part_<id>.py just calls build('<id>').

Conventions: origin at the block CENTRE; Blender +Y = Godot forward (-Z); Blender Z = Godot up. A block of
size_cells (x, y, z) in Godot is (x, z, y) cells here, 0.5 m each. Every part fills its cells exactly, so blocks
butt together face to face. Mount faces: wheels and landing gear bolt on with their mount plate (wheel: -X side,
gear: top); everything else sits on its own base or fills its box.
The game behaviour of each part is in scripts/world/ship_*.gd; the list is scripts/data/ship_parts.gd."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit
from kit import *
from mathutils import Vector, Matrix

C = 0.5                                       # one cell


def _finish(name, **kw):
    kit.finish(name, bake_res=512, **kw)


# ---------------------------------------------------------------- chassis (Crossout-style frame building)
def beam(n):
    """Square-tube beam n cells long (along forward), a bolting end plate at each end, lightening holes."""
    L = n * C
    box("Tube", (0.3, L - 0.04, 0.3), (0, 0, 0), SEC, bevel=0.01)
    part("Tube", f"beam: {L:.1f} m of square tube, the frame you build vehicles on", "ground", "ground")
    for s in (-1, 1):
        box(f"EndPlate{s}", (0.48, 0.02, 0.48), (0, s * (L / 2 - 0.01), 0), SEC, bevel=0.004)
    part("EndPlate", "end plate: bolts the beam face to face to the next block", "Tube", "welded")
    for k in range(n):
        y = -L / 2 + C * (k + 0.5)
        for sx in (-1, 1):
            box(f"Hole{k}{sx}", (0.006, 0.14, 0.14), (sx * 0.149, y, 0), RUB, bevel=0.0)
        for sz in (-1, 1):
            box(f"HoleV{k}{sz}", (0.14, 0.14, 0.006), (0, y, sz * 0.149), RUB, bevel=0.0)
    part("Hole", "lightening hole / bolt access", "Tube", "inset")
    _finish(f"SM_PartBeam{n}")


def frame_cube():
    """Open cube of edge tubes welded into corner nodes: the light way to fill space in a frame."""
    ship_frame(0.25, 0.08, name="Frame")
    _finish("SM_PartFrameCube")


def frame_corner():
    """Joint node: a solid node with a bolting plate on every face - joins beams in any direction."""
    box("Node", (0.46, 0.46, 0.46), (0, 0, 0), SEC, bevel=0.012)
    part("Node", "joint node: beams bolt to it from any side", "ground", "ground")
    for ax in range(3):
        for s in (-1, 1):
            c = [0, 0, 0]; c[ax] = s * (0.25 - 0.01)
            size = [0.44, 0.44, 0.44]; size[ax] = 0.02
            box(f"FacePlate{ax}{s}", tuple(size), tuple(c), BARE, bevel=0.003)
    part("FacePlate", "face plate: the bolting face", "Node", "welded")
    _finish("SM_PartFrameCorner")


def plate():
    """1 x 1 m armour/deck plate, 5 cm thick, lying on the bottom of its cell layer."""
    plate_ = kit.plate
    plate_("Plate", (0, 0, -0.25), (0, 0, 1), 1.0, 1.0, t=0.05, clip=0.08, mat=PRI, up=(0, 1, 0), bolt_inset=0.05)
    part("Plate", "plate: floor, wall or armour on a frame", "ground", "ground")
    _finish("SM_PartPlate")


def wedge():
    """1 m armour wedge, rising toward forward: noses, ramps, deflectors."""
    profile("Wedge", [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5)], (0, 0, 0), (1, 0, 0), 1.0, PRI, up=(0, 0, 1), bevel=0.01)
    part("Wedge", "armour wedge: a sloped face that deflects hits", "ground", "ground")
    for s in (-1, 1):
        profile(f"Rib{s}", [(-0.45, -0.5), (0.45, -0.5), (0.45, 0.4)], (s * (0.5 - 0.015), 0, 0), (1, 0, 0), 0.03, SEC,
                up=(0, 0, 1), bevel=0.0)
    part("Rib", "side rib: stiffens the wedge", "Wedge", "inset")
    _finish("SM_PartWedge")


def hull_small():
    """0.5 m armour cube: a small welded frame with an armour panel in each face."""
    H, B = 0.25, 0.06
    ship_frame(H, B)
    O = 2 * (H - B / 2 - (B - 0.04) / 2)
    T = 0.02
    for ax in range(3):
        for sgn in (-1, 1):
            n = [0.0, 0.0, 0.0]; n[ax] = sgn
            up = (0, 0, 1) if ax != 2 else (0, 1, 0)
            c = [0.0, 0.0, 0.0]; c[ax] = sgn * (H - 0.01 - T)
            kit.plate(f"Armour{ax}{sgn}", tuple(c), tuple(n), O, O, t=T, clip=0.045, up=up, bolts_on=False, bevel=0.003)
    part("Armour", "armour panel set into the frame", "FrameBeam", "bolted")
    _finish("SM_PartHullSmall")


# ---------------------------------------------------------------- control, power, life support
def _floor(name="Floor", w=0.96, d=0.96, z=-0.5, t=0.03):
    box(name, (w, d, t), (0, 0, z + t / 2), SEC, bevel=0.004)
    part(name, "floor plate: the part stands on it, bolted to the block below", "ground", "ground")
    return z + t


def driver_seat():
    """Open driver seat: no canopy, no air - the driver breathes from the suit. Steering wheel, pedals, roll hoop."""
    F = _floor()
    box("Pedestal", (0.3, 0.3, 0.18), (0, -0.05, F + 0.09), SEC, bevel=0.01)
    part("Pedestal", "seat pedestal", "Floor", "welded")
    box("SeatPan", (0.44, 0.44, 0.08), (0, -0.05, F + 0.18 + 0.04), PRI, bevel=0.02)
    part("SeatPan", "seat", "Pedestal", "bolted")
    box("SeatBack", (0.44, 0.08, 0.5), (0, -0.05 - 0.22 - 0.04, F + 0.26 + 0.25), PRI, bevel=0.02)
    part("SeatBack", "seat back", "SeatPan", "bolted", joins=("Pedestal",))
    pipe("Column", [(0, 0.38, F), (0, 0.3, F + 0.45)], 0.025, BARE, fillet=0.0)
    part("Column", "steering column, socketed into the floor", "Floor", "inset")
    cyl("SteeringWheel", 0.16, 0.03, (0, 0.295, F + 0.465), RUB, seg=24, bevel=0.0,
        rot=Matrix.Rotation(math.radians(-60), 4, 'X'))
    part("SteeringWheel", "steering wheel", "Column", "pivot")
    for s in (-1, 1):
        box(f"Pedal{s}", (0.08, 0.12, 0.03), (s * 0.12, 0.38, F + 0.043), BARE, bevel=0.0,
            rot=Matrix.Rotation(math.radians(30), 4, 'X'))
    part("Pedal", "pedal: throttle / brake", "Floor", "pivot")
    pipe("RollHoop", [(-0.42, -0.42, F), (-0.42, -0.42, 0.42), (0.42, -0.42, 0.42), (0.42, -0.42, F)], 0.03, SEC, fillet=0.12)
    part("RollHoop", "roll hoop: protects the driver in a rollover", "Floor", "welded")
    _finish("SM_PartDriverSeat")


def vehicle_core():
    """1 m vehicle core: the critical block a vehicle is built around (power + control computer)."""
    ship_frame(0.5, 0.1, name="CoreFrame")
    for s in (-1, 1):
        box(f"CorePlate{s}", (0.84, 0.84, 0.03), (0, 0, s * (0.42 + 0.015)), SEC, bevel=0.003)
    part("CorePlate", "end plate: carries the core", "CoreFrameBeam", "inset", joins=("CoreFrameNode",))
    cyl("Core", 0.2, 0.84, (0, 0, 0), HEAT, seg=24, bevel=0.0)
    part("Core", "power core (glows while running)", "CorePlate", "inset")
    for z in (-0.25, 0.0, 0.25):
        tube(f"CoreBand{z}", 0.23, 0.2, 0.05, (0, 0, z), BARE, seg=24, bevel=0.0)
    part("CoreBand", "core clamp band", "Core", "clamped")
    _finish("SM_PartVehicleCore")


def battery():
    """Battery pack, 1 x 0.5 x 0.5 m: stores power for engines and systems."""
    F = _floor(w=0.96, d=0.46, z=-0.25, t=0.02)
    box("Case", (0.9, 0.42, 0.36), (0, 0, F + 0.18), PRI, bevel=0.02)
    part("Case", "battery case: the cells are inside", "Floor", "bolted")
    for s in (-1, 1):
        cyl(f"Terminal{s}", 0.03, 0.04, (s * 0.3, 0, F + 0.36 + 0.02), (HAZ if s > 0 else RUB), seg=12, bevel=0.0)
    part("Terminal", "power terminal (+ / -)", "Case", "inset")
    box("Gauge", (0.3, 0.006, 0.05), (0, -0.21 - 0.002, F + 0.24), STAT, bevel=0.0)
    part("Gauge", "charge gauge", "Case", "inset")
    _finish("SM_PartBattery")


def o2_tank():
    """Oxygen tank: two pressure bottles in cradles. Feeds the sealed cockpits on the same ship / vehicle."""
    F = _floor()
    for s in (-1, 1):
        box(f"Cradle{s}", (0.8, 0.08, 0.12), (0, s * 0.3, F + 0.06), SEC, bevel=0.004)
    part("Cradle", "cradle: the bottles rest in it", "Floor", "welded")
    for s in (-1, 1):
        x = s * 0.22
        cyl(f"Bottle{s}", 0.17, 0.86, (x, 0, F + 0.12 + 0.17), PRI, seg=24, axis='Y', bevel=0.02)
        for t in (-1, 1):
            tube(f"Strap{s}{t}", 0.18, 0.17, 0.05, (x, t * 0.3, F + 0.12 + 0.17), BARE, seg=24, axis='Y', bevel=0.0)
        cyl(f"Valve{s}", 0.03, 0.08, (x, 0.0, F + 0.12 + 0.34 + 0.04), BARE, seg=12, bevel=0.0)
    part("Bottle", "oxygen bottle", "Cradle", "seated")
    part("Strap", "strap: holds the bottle in its cradle", "Bottle", "clamped", joins=("Cradle",))
    part("Valve", "bottle valve", "Bottle", "inset")
    pipe("Manifold", [(-0.22, 0.0, F + 0.12 + 0.42), (0.22, 0.0, F + 0.12 + 0.42)], 0.015, BARE, fillet=0.0)
    part("Manifold", "manifold: joins the bottles to the ship's air line", "Valve", "inset")
    _finish("SM_PartO2Tank")


def engine():
    """Engine: an electric drive motor and gearbox. Without one, wheels only roll - engines drive them."""
    F = _floor()
    for s in (-1, 1):
        box(f"Foot{s}", (0.4, 0.08, 0.1), (0, -0.1 + s * 0.2, F + 0.05), SEC, bevel=0.004)
    part("Foot", "motor foot: bolted to the floor", "Floor", "bolted")
    MZ = F + 0.1 + 0.25
    cyl("Motor", 0.25, 0.55, (0, -0.1, MZ), PRI, seg=24, axis='Y', bevel=0.02)
    part("Motor", "drive motor", "Foot", "seated")
    for y in (-0.2, -0.1, 0.0):
        tube(f"Fin{y}", 0.28, 0.25, 0.03, (0, y, MZ), SEC, seg=24, axis='Y', bevel=0.0)
    part("Fin", "cooling fin", "Motor", "inset")
    box("Gearbox", (0.5, 0.25, 0.4), (0, 0.175 + 0.125, F + 0.2), SEC, bevel=0.02)
    part("Gearbox", "gearbox: splits the drive to the wheels", "Floor", "bolted", joins=("Motor",))
    for s in (-1, 1):
        cyl(f"Output{s}", 0.07, 0.2, (s * 0.35, 0.3, F + 0.2), BARE, seg=16, axis='X', bevel=0.004)
    part("Output", "output flange: half-shafts to the wheels", "Gearbox", "pivot")
    _finish("SM_PartEngine")


def rcs():
    """RCS block (0.5 m): small thrusters on five faces - fine translation and turning, weak but in every direction."""
    F = _floor(w=0.46, d=0.46, z=-0.25, t=0.02)
    box("Body", (0.3, 0.3, 0.3), (0, 0, F + 0.15), SEC, bevel=0.02)
    part("Body", "RCS valve block: feeds the five nozzles", "Floor", "bolted")
    dirs = [((1, 0, 0), 'X'), ((-1, 0, 0), '-X'), ((0, 1, 0), 'Y'), ((0, -1, 0), '-Y'), ((0, 0, 1), 'Z')]
    for k, (d, ax) in enumerate(dirs):
        c = Vector((0, 0, F + 0.15)) + Vector(d) * (0.15 + 0.035)
        cyl(f"Nozzle{k}", 0.035, 0.07, tuple(c), BARE, seg=12, axis=ax, r2=0.055, bevel=0.0)
    part("Nozzle", "RCS nozzle", "Body", "inset")
    _finish("SM_PartRCS")


# ---------------------------------------------------------------- wheels and landing gear
def wheel(s, name):
    """Wheel module, s = 1 (1 m, 2 cells) or 2 (2 m, 4 cells). Mount plate on the block's -X face (it bolts to the
    ship there), torsion-bar housing at the hinge behind the wheel, trailing arm to the hub, wheel on the hub.
    _Arm swings and _Wheel moves / spins / steers in game (ship_wheel.gd)."""
    H = 0.5 * s                                         # half block
    box("Mount", (0.03 * s, 0.9 * s, 0.4 * s), (-H + 0.015 * s, 0, 0.15 * s), SEC, bevel=0.004)
    part("Mount", "mount plate: bolts the wheel module to the ship", "ground", "ground")
    hinge = Vector((-0.2 * s, -0.35 * s, 0.15 * s))
    cyl("Torsion", 0.07 * s, H - 0.03 * s - 0.2 * s + 0.07 * s, ((-H + 0.03 * s + hinge.x + 0.07 * s) / 2, hinge.y, hinge.z),
        BARE, seg=16, axis='X', bevel=0.004)
    part("Torsion", "torsion-bar housing: the spring the arm twists", "Mount", "welded")
    hub = Vector((-0.2 * s, 0.0, 0.0))
    with group("Arm"):
        d = hub - hinge
        rot = d.to_track_quat('Z', 'X').to_matrix().to_4x4()
        box("Arm", (0.08 * s, 0.06 * s, d.length), (0, 0, 0), SEC, bevel=0.006,
            rot=Matrix.Translation((hinge + hub) / 2) @ rot)
        cyl("Stub", 0.05 * s, 0.145 * s, (-0.2 * s + 0.0725 * s, 0, 0), BARE, seg=16, axis="X", bevel=0.0)
    part("Arm", "trailing arm: swings up and down on the torsion bar", "Torsion", "pivot")
    part("Stub", "stub axle", "Arm", "inset")
    with group("Wheel"):
        cyl("Tyre", 0.42 * s, 0.26 * s, (0.08 * s, 0, 0), RUB, seg=32, axis='X', bevel=0.03 * s)
        cyl("Rim", 0.27 * s, 0.27 * s, (0.08 * s, 0, 0), BARE, seg=24, axis='X', bevel=0.004)
        cyl("HubCap", 0.08 * s, 0.03 * s, (0.08 * s + 0.135 * s + 0.015 * s, 0, 0), SEC, seg=16, axis='X', bevel=0.0)
    part("Tyre", "tyre", "Rim", "inset")
    part("Rim", "rim: turns on the stub axle", "Stub", "pivot")
    part("HubCap", "hub cap", "Rim", "inset")
    _finish(name, pivots={"Arm": tuple(hinge), "Wheel": (0.08 * s, 0, 0)})


def landing_gear():
    """Landing gear: a sprung leg on a hinge under its top mount plate. Holds a parked ship or vehicle still, no
    drive. Retracts (the leg swings up) for flight. _Leg rotates, _Foot slides with the spring (ship_landing_gear.gd)."""
    box("Mount", (0.9, 0.9, 0.03), (0, 0, 0.5 - 0.015), SEC, bevel=0.004)
    part("Mount", "mount plate: bolts the gear under the ship", "ground", "ground")
    HZ = 0.32
    for s in (-1, 1):
        box(f"Lug{s}", (0.05, 0.16, 0.5 - 0.03 - HZ + 0.06), (s * 0.12, 0, (HZ - 0.06 + 0.47) / 2), SEC, bevel=0.003)
    part("Lug", "hinge lug: carries the leg's pivot", "Mount", "welded")
    with group("Leg"):
        cyl("LegPivot", 0.05, 0.19, (0, 0, HZ), BARE, seg=16, axis='X', bevel=0.0)
        cyl("Strut", 0.06, 0.45, (0, 0, HZ - 0.225), PRI, seg=16, bevel=0.004)
    part("LegPivot", "leg pivot pin", "Lug", "pivot")
    part("Strut", "oleo strut: the spring and damper", "LegPivot", "inset")
    with group("Foot"):
        cyl("Piston", 0.04, 0.42, (0, 0, -0.24), BARE, seg=16, bevel=0.0)
        cyl("Pad", 0.18, 0.05, (0, 0, -0.5 + 0.025), SEC, seg=24, bevel=0.01)
    part("Piston", "piston: slides in the strut", "Strut", "pivot")
    part("Pad", "foot pad", "Piston", "inset")
    _finish("SM_PartLandingGear", pivots={"Leg": (0, 0, HZ), "Foot": (0, 0, HZ)}, parents={"Foot": "Leg"})


# ---------------------------------------------------------------- weapons
RP_COLS, RP_ROWS, RP_PITCH, RP_ZC = 16, 10, 0.08, -0.04     # must match scripts/world/ship_rocket_pod.gd


def rocket_pod():
    """Rocket pod, 1.5 x 2.5 x 1.0 m (3 x 5 x 2 cells): 160 unguided 70 mm rockets in a 16 x 10 bank of launch tubes.
    Hangs from its top mount plate (bolts to the block above it, like a wing pylon). Strongback: the spine that
    carries the casing and the firing circuit. Casing: holds the tube bank, open at the front, blow-out cover at the
    back (rocket exhaust leaves through it). Fires one tube at a time (ship_rocket_pod.gd)."""
    box("Mount", (1.0, 1.7, 0.03), (0, 0, 0.5 - 0.015 - 0.015), SEC, bevel=0.004)
    part("Mount", "mount plate: bolts the pod to the ship above it", "ground", "ground")
    MB = 0.5 - 0.03 - 0.015                                   # mount underside
    A, B, N = 0.72, 0.44, 8.0
    top = RP_ZC + B
    FT = 0.02
    box("Strongback", (0.22, 1.8, MB - FT - top), (0, 0, (MB - FT + top) / 2), PRI, bevel=0.006)
    box("StrongbackFlange", (0.4, 1.8, FT), (0, 0, MB - FT / 2), PRI, bevel=0.004)
    part("Strongback", "strongback: the spine that carries the casing and the firing circuit", "StrongbackFlange", "welded")
    part("StrongbackFlange", "bolting flange: bolts the strongback up into the mount plate", "Mount", "bolted",
         joins=("Strongback",))
    for s in (-1, 1):
        bolt_line(f"FlangeBolt{s}", (s * 0.16, -0.8, MB - FT), (s * 0.16, 0.8, MB - FT), 6, (0, 0, -1))
        weld(f"SpineWeld{s}", [(s * 0.11, -0.9, MB - FT), (s * 0.11, 0.9, MB - FT)])
    def ring(y, k=1.0):
        return [(u * k, y, RP_ZC + v * k) for (u, v) in squircle(A, B, N, seg=64)]
    loft("Casing", [ring(-1.2, 0.85), ring(-1.0), ring(1.0)], PRI, bevel=0.01)
    part("Casing", "casing: holds the tube bank, takes the blast of each launch", "Strongback", "welded")
    for s in (-1, 1):
        weld(f"CasingWeld{s}", [(s * 0.11, -0.88, top), (s * 0.11, 0.88, top)])
    kit.plate("RearCover", (0, -1.2, RP_ZC), (0, -1, 0), 0.95, 0.55, t=0.02, clip=0.06, mat=SEC, up=(0, 0, 1), slots=6)
    part("RearCover", "blow-out cover: the rocket exhaust leaves through its slots", "Casing", "bolted")
    for r in range(RP_ROWS):
        for c in range(RP_COLS):
            x = (c - (RP_COLS - 1) / 2) * RP_PITCH
            z = RP_ZC + (r - (RP_ROWS - 1) / 2) * RP_PITCH
            cyl(f"Tube{r:02d}{c:02d}", 0.036, 0.06, (x, 1.0, z), BARE, seg=12, axis='Y', bevel=0.0)
            cyl(f"Bore{r:02d}{c:02d}", 0.029, 0.004, (x, 1.03 + 0.002, z), RUB, seg=12, axis='Y', bevel=0.0)
    part("Tube", "launch tube: one rocket each, through the front bulkhead", "Casing", "through")
    part("Bore", "tube mouth (the rocket's nose sits behind it)", "Tube", "inset")
    box("FiringPlug", (0.1, 0.08, 0.05), (0, 0.9 + 0.04, top + 0.025), BARE, bevel=0.004)
    part("FiringPlug", "firing plug: the ship's trigger circuit reaches the tubes through it", "Strongback", "inset")
    _finish("SM_PartRocketPod")


BUILD = {
    "rocket_pod": rocket_pod,
    "beam_1": lambda: beam(1), "beam_2": lambda: beam(2), "beam_4": lambda: beam(4),
    "frame_cube": frame_cube, "frame_corner": frame_corner, "plate": plate, "wedge": wedge, "hull_small": hull_small,
    "driver_seat": driver_seat, "vehicle_core": vehicle_core, "battery": battery, "o2_tank": o2_tank,
    "engine": engine, "rcs": rcs, "wheel_small": lambda: wheel(1, "SM_PartWheelSmall"),
    "wheel_large": lambda: wheel(2, "SM_PartWheelLarge"), "landing_gear": landing_gear,
}


def build(pid):
    kit.begin(kit.out_dir())
    kit.DUST_AMT = 0.15
    BUILD[pid]()

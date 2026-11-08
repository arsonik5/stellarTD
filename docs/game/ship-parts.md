# Ship and vehicle parts (one grid, one system)

Decided 2026-11-04 with Michael: ships and ground vehicles are the same thing - a `Ship` (RigidBody3D) built from
blocks. There is one build grid: **0.5 m cells**. The classic 2 m blocks fill 4 x 4 x 4 cells and snap to the 2 m
lattice; small parts fill 1 or 2 cells per side and go anywhere next to them, so big and small blocks mix freely.
Anything can be placed anywhere; each part just behaves differently.

Controls are the same for everything you pilot: W/S drive or thrust forward/back, A/D steer or strafe, Space/Ctrl
lift, Q/R roll, G landing gear, V camera, X dampeners, E exit.

| Part | Size (cells) | What it does / quirks | Script |
|---|---|---|---|
| Ship Core | 4x4x4 | Critical: a ship must keep one, everything connects back to it | `ship_block` |
| Vehicle Core 1 m | 2x2x2 | Same job, small - for buggies and light builds | `ship_block` (critical) |
| Cockpit | 4x4x4 | **Sealed**: the pilot breathes ship air and the suit refills from the Oxygen Tanks | `ship_cockpit` (sealed) |
| Driver Seat (open) | 2x2x2 | **Open**: no air - the driver lives on the suit. Light and cheap | `ship_cockpit` (sealed = false) |
| Oxygen Tank | 2x2x2 | 1200 s of air for the sealed cockpits on the same ship | `ship_o2_tank` |
| Battery | 2x1x1 | Stored power (capacity summed; power is not simulated yet) | `ship_battery` |
| Engine | 2x2x2 | Drives the wheels: its force is shared over every driven wheel. No engine = wheels only roll | `ship_engine` |
| Wheel 1 m / Wheel 2 m | 2x2x2 / 4x4x4 | Raycast suspension sized from the real load on that wheel, drive from the engines, steering if ahead of the centre of mass, grip, brakes. Bolts on with its mount facing the block it sits on; the arm and wheel move with the real spring travel | `ship_wheel` |
| Landing Gear | 2x2x2 | Sprung leg, mount on top - goes under the ship. Never drives, grips hard (parks). G retracts it for flight | `ship_landing_gear` |
| Thruster | 4x4x4 | Pushes along its axis | `ship_thruster` |
| RCS Thruster | 1x1x1 | Weak, but pushes any direction asked for, and adds a little turning | `ship_rcs` |
| Rocket Pod | 3x2x5 | 160 unguided 70 mm rockets (16 x 10 tubes), mount plate on top - hangs under the ship. Fired by the weapon control system (see gameplay-systems.md "Ship weapons") | `ship_rocket_pod` |
| Gyroscope | 4x4x4 | Turning authority | `ship_gyroscope` |
| Beam 0.5 / 1 / 2 m | 1x1x1 / 1x1x2 / 1x1x4 | Crossout-style frame building: square tube with bolting end plates | `ship_block` |
| Frame Cube | 1x1x1 | Open tube cube: light filler in a frame | `ship_block` |
| Frame Joint | 1x1x1 | Node with a bolting face on every side: joins beams in any direction | `ship_block` |
| Plate 1 x 1 m | 2x1x2 (thin) | Floor, wall or armour on a frame; collides only as a 5 cm plate | `ship_block` |
| Armour Wedge 1 m | 2x2x2 | Sloped armour | `ship_block` |
| Hull 0.5 m / Ship Hull 2 m | 1x1x1 / 4x4x4 | Armour cubes | `ship_block` |

Suit oxygen (player): 300 s of air. It drains outside, refills near a Ship Garage (base life support) and in a
sealed cockpit (from that ship's tanks). Out of air you move at 40% speed.

Where things are:
- Models: `art_src/parts_lib.py` (all the small parts are blockouts for now). Registry: `scripts/data/ship_parts.gd`.
- Crafted in the Constructor and the Ship Garage. Tests: `scenes/dev/vehicle_test.tscn` builds a buggy (drives,
  turns, brakes) and a lander (settles on its gear, retracts it), and checks the oxygen tank.
- Old saves are converted on load (whole 2 m cells -> 0.5 m cells).

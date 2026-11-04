# Every part has a job

The rule: a part goes on a model only if you can say what it does mechanically. No decorative wedges, no bolts that
fasten nothing, no hinges without a door, no glow where nothing is hot or signalling. When adding a part, add its
line here. When a part has no line here, delete it.

Since 2026-11-03 this is enforced in code: every generator declares each part with `kit.part(prefix, job, on, joint)`
and `audit.py` fails the build on undeclared, floating, overlapping or unfastened parts. The full, current
part-by-part list for each model is generated into `art_src/<name>/parts.md` on every build; this file keeps the
shared joint vocabulary and the design story per building.

Joint helpers added with the audit: `box_weld` (beads on every exposed edge where two square parts meet),
`weld_loop` (closed bead round any outline), `bolt_ring` (bolt circle on any face), `wall_bracket` (bolted foot +
welded arm to stand something off a wall), `housing_panel` (cover / vent / hinged door that follows a curved wall),
`ship_frame`, `foundation_block`, `deck_plate`. The pipe clamp is a rubber liner on the glass with a lower band on
the cradle and a bolted top strap (a bare strap ring floating off the glass was rejected).

## Every part is mounted, and belongs to its neighbours

A part may not just touch or sit inside another part. Every joint shows how it is held, and parts take their size
and position from the structure they join (a corner casting is the node where two frame beams meet, the same
height as the beams, not a cube set on a slab).

| Joint | How it is shown | Kit helper |
|---|---|---|
| Bolted flange / plate | hex bolt heads on the flange or plate corners | `plate`, `bolts`, `bolt_line`, `base_plate` |
| Welded seam | painted weld bead in the inside corner (never across a flush butt joint) | `weld`, `weld_ring`, `saddle_weld` |
| Brace under load | gusset welded along both edges (standing or hanging) | `gusset` |
| Pipe / hose end | hex union fitting | `fitting` |
| Pipe run | clamp band with a bolted tab | `clamp` |
| Pipe on the ground | cradle shaped to the pipe, bolted strap, post welded to a bolted base plate | `pipe_support` |
| Column / post / tower | bolted base plate (+ gussets if it carries a moment) | `base_plate` |
| Rod through plates | nuts at both ends | (hex `cyl`) |

## Shared kit parts

| Part | Job |
|---|---|
| Skid | Welded transport frame: four channel-steel side beams + deck plate |
| Corner castings | The frame's corner nodes (beams welded into them), oval twist-lock apertures = crane / lock points |
| Housing (lofted body) | Encloses the machine |
| Base flange + its bolts | Holds the housing down on the skid |
| Armour plates + corner bolts | Removable service panels, bolted at the corners |
| Vent slots on a plate | Cooling air for motors/electronics behind that panel (only where something heats up) |
| Belt / top trim | Stiffening band and top rim of the housing shell |
| Status strip | The machine's on/fault light, same place on every building |
| Pipe collar (`pipe_collar`) | The one pipe-end joint: mating face on the cell edge, bolts on the back face, steel seal |
| Pipe port (`pipe_port`) | Junction outlet: hollow neck out of the round drum (saddle weld), collar, dark throat |
| Machine port (`machine_port`) | Item input/output of a machine: round neck through the housing wall at 0.45 m, welded all round, pipe collar on the footprint edge; lit collar = output |
| Hazard stripes | Only at real pinch/heat points: press columns, muzzles, shell feed, pad edge |

## Per building

**Smelter**: crucible with induction bands (glow = the melt heating); radiators shed coil heat, two coolant lines each
(supply + return) into the crucible collar; ore comes in through the back port into the hopper in the housing, and
the lift line carries it from the hopper up into the crucible; window with guard bars to watch the melt; ingots leave
through the front port; hood + exhaust with heat-sink fins and an exhaust fan.

**Crafter**: glass work cell (sealed assembly), robot arm assembling the part on the jig, roof fume-extraction fan,
vent slots for the drive electronics, output port front, input port back.

**Constructor**: hydraulic press. Pump + motor on the back, two hydraulic lines (supply/return) up to the cylinder in
the crosshead; piston drives the ram; ram arms run on two guide rods; die on the bed, hot blank being forged; column
gussets carry the press load; hazard stripes on the columns at the pinch zone; output port under the bed, input
port on the left; status light on the crosshead front plate.

**Chest**: cargo container: corner posts and rails are the frame, corrugation stiffens the walls, lock bars + cams
+ handles lock the doors, hinges hang them, fill-level light, a pipe port on each side (the side walls are flat,
no corrugation, where the ports go through).

**Vacuum pipe**: glass tube (items visible), four guide rails carry the glass, collars join segments, centre band +
saddle + leg + foot hold it up.

**Merger**: round drum (like the splitter) with three input ports and one lit output port; bolted round lid with a
lift handle to clear jams.

**Splitter**: drum with one input and three lit outputs; pancake gear motor on three struts turns the internal
distributor through a coupling (the coupling, with its bolts and index lug, is the part you see turning).

**Foundation**: perimeter beams carry the deck; deck plates with anti-slip treads; flush tie-down points at corners.

**Gun turret / Cannon**: pedestal on the skid; slew ring = yaw bearing; turntable + two fork arms with trunnion
bearings (yaw, `_Head`); cradle with trunnion pins pitches between them (`_Cradle`) and carries the shell, mantlet,
shrouds and the sight (it must look where the gun points); barrels recoil inside the cradle (`_Barrels`/`_Barrel`).
Ammunition: gun = belt magazine with a feed chute up through the slew ring; cannon = shell hopper with a feed chute.

**Ship hull**: armour block, bolted plates, nothing else (no vents: it is passive).
**Ship core**: frame with corner connectors, reactor column held by top/bottom mounts and four tie rods, containment
rings, armoured sides with viewing slots.
**Cockpit**: armoured tub with raked nose, framed canopy, seat, dash with screen, two control sticks.
**Gyroscope**: cradle with pylons and bearings; outer ring on X, inner ring on Z (nested), spinning core.
**Thruster**: bolted mount plate; four fuel lines from the ship through the plate down to the injector manifold at
the throat; the manifold feeds the cooling channels down the bell; chamber bands; glowing throat.
**Ship garage**: liftable pad with hazard edge and landing mark + guide lights; two jib cranes (tower, slew bearing,
arm, trolley, cable, welding tool) with gussets carrying the arm moment.

## In-game wiring this implies

Turrets: rotate `_Head` about Y for yaw and `_Cradle` about its local X for pitch (not one look_at on Head), and
put the Muzzle marker under `_Cradle`.

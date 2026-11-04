# 02 - Core mechanics (layer 1)

The mechanics the game IS. Remove any one and it becomes a different game. Each entry: what it is, why it is
core, the loop it creates, current state in code, and what is missing. Status words: **built** (works and is
tested), **partial** (exists, gaps listed), **missing**.

## The loop

```
          +-------------------------- Directives / Research --------------------------+
          |                                                                           v
 SURVEY -> EXTRACT -> PROCESS -> BUILD / ASSEMBLE -> DELIVER (uplink) -> UNLOCK -> REACH FURTHER
             |            |              |                                         |
             +------------+------ raises SIGNATURE ------> THREAT -> DEFEND -------+
```

- **Minute loop:** find ore, drill it, feed a machine, place something. Every step answers back (pillar 5).
- **Hour loop:** fulfil a Directive, unlock a tier, extend the base or reach a new deposit, survive the
  consequences of the noise you made.
- **Arc loop:** change *how* you play (hand -> machine -> vehicle -> ship -> robot), see `01-vision.md`.

## C1. Survey - built (scanner), partial (planet worth surveying)

- **What:** read the world. Eyes first (surface ore stains, biome, landmarks), then the scanner pulse (aim^6 x
  proximity^2, ore colour, no distance - see `architecture/gameplay-systems.md`).
- **Why core:** pillar 1. If finding things is trivial the planet is a backdrop.
- **Missing:** things worth finding *besides* ore - landmarks, wrecks, Continuance probes, crystal formations
  (`05-planets.md`); a **waypoint/marker** the player places themselves when they find something (minor M7).

## C2. Extract - partial

- **Hand drill: built.** SE-style bore, pays for removed volume, per-material hardness.
- **Automated extraction: MISSING - the biggest gap in the factory half.** A factory game where every ore
  is hand-dug never reaches pillar 2. Design:
  - **Deposit Drill** (building): placed on the ground over a deposit, it really bores the voxel terrain
    (same `TerrainDrill` bite code, slower, deeper), producing a visible shaft and paying ore by removed
    volume into its output, which pipes collect. Throughput set by tier and power, not by a node's purity.
  - Deposits are large but finite in a region; a drill that exhausts its reach must be moved (or extended
    with a deeper head tier). That keeps expansion (arc 3) motivated without Satisfactory-style infinite nodes.
  - Stone output is real: it either goes to a **crusher** (stone -> gravel -> concrete, a construction
    material) or to a **void/backfill** port. Stone must never jam the player into frustration.
- **Robot extraction (arc 5):** robots carrying drill heads (C8).

## C3. Process & logistics - partial

- **Built:** processor, smelter, constructor, chest; vacuum pipes with merger/splitter; per-building
  auto-recipes; multi-input recipes.
- **Missing:**
  - **Pipe orientation on the sphere** - pipe/merger/splitter math is still world-Y based (known boundary).
    Must be body-local before bases spread around the planet.
  - **Throughput model:** `input_capacity`/`output_capacity` are placeholders. Define items/minute per pipe
    tier and per machine; show it in the UI. Without numbers, optimisation (the long-tail fun) does not exist.
  - **Recipe graph with purpose:** silica, sulfur and carbon dead-end or nearly so today (see `07-roadmap.md`
    economy table). Every refined good must feed something.
  - **Storage logistics:** chests that pipes fill and drain; a "requester" later for robots.

## C4. Build - partial

- **Built:** first-person build tool, foundations with snapping, ramps/stairs/frames, ship block grid with
  0.5 m cells and 2 m blocks mixing freely.
- **Missing:** **deconstruct with refund**, building **health/repair**, **hotbar + pick-what-I-look-at**,
  copy/paste and blueprints (minor), paint tool (decided, not built).

### The three nested grids (decision 2026-11-04)

One lattice family, each grid an exact subdivision of the one above, so everything still fits together:

| Grid | Cell | Used for |
|---|---|---|
| Structure | 2 m | foundations, buildings, classic ship blocks |
| Part | 0.5 m | ship/vehicle parts (wheels, seats, beams, plates, RCS) - built |
| **Mechanism** | **0.25 m** | **Scrap Mechanic-style small mechanics: bearings, hinges, pistons, motors, sensors, logic, grippers** - new |

The 0.25 m grid is SE2's unified block size, so a 2 m block is 8 mechanism cells and a 0.5 m part is 2 - any
mechanism part can sit flush on any face. It lives on the same `ShipGrid` (cell size becomes 0.25 m
internally; existing 0.5 m data converts on load exactly as 2 m -> 0.5 m did).

## C5. Mechanisms & robots - missing (new core, decided 2026-11-04)

Michael: "add even smaller grid with smaller mechanical stuff like Scrap Mechanic so you can build your own
robots too". This is where pillar 2 ends up: **the robots that run the colony are ones you designed.**

- **Moving joints = sub-grids.** A bearing, hinge or piston splits a construct into two rigid bodies joined by
  a Jolt joint (`HingeJoint3D` / `SliderJoint3D` / `Generic6DOFJoint3D` with motors). This is the one large
  engine change: `Ship` today is one `RigidBody3D`. It becomes a **Construct** = a tree of grids connected by
  joint parts; each grid is still a `Ship`-style body, mass and centre of mass computed per grid.
- **Parts (mechanism grid):** bearing (free / motorised), hinge, piston (2 lengths), suspension, motor, gear
  ratio box, gripper/magnet, drill head, cargo bay, battery, solar cell, sensor (distance, ore, item, enemy),
  light, speaker.
- **Logic:** Scrap Mechanic's model, deliberately simple - **logic gates and timers wired between parts**, plus
  one **Controller** part that maps inputs (seat keys, sensors) to joint targets. Wires are part-to-part links
  drawn with a connect tool, not a programming language. Visual, debuggable (wires glow when signal is on).
- **Robots:** a construct with a **Robot Core** instead of a cockpit runs a **behaviour card** slotted into it
  (Haul A->B, Mine here, Patrol, Build blueprint, Repair). Cards are crafted/researched; the body is yours. This
  is how arc 5 automation is delivered without a scripting language, and why a robot you built badly will
  tip over on a slope.
- **Order:** joints first (they make vehicles better too: steering racks, cranes, doors, landing legs), then
  logic, then robot cores. Each step is playable alone.

## C6. Signature, threat & defence - partial (scope 1 built)

- **Signature** (`RadiationSignature`): today only crystal held. Becomes a sum of sources with decay:
  crystal held/stored (persistent), reactors and big machines running (persistent while on), drilling crystal
  and launches (spikes). Containment blocks subtract. Shown on the HUD as a single gauge with its tier edges.
- **Threat tiers - mixed by tier (decision 2026-11-04):**

| Tier | Trigger | What comes | What it does to you |
|---|---|---|---|
| Quiet | ~0 | nothing | - |
| Noticed | low | **Scout** (built) | scans, flees; escaping = escalation (built) |
| Hunted | reported / medium | **Gunship raids** | strafing runs on buildings and the player, from the air |
| Contested | high | **Dropships** + raids | land drone squads that walk to machines and cut them apart |
| Siege | very high, sustained | **Bombardment** from orbit, spotted by a **Spotter** ship | craters terrain and bases; kill the spotter to stop it |

- Raids arrive as **waves with warning** (uplink alert + direction + ETA), never by surprise; the player
  must be able to prepare (pillar 3). Between waves there is always calm.
- **Defence:** turrets (built: gun + cannon) fed by pipes, later shields, flak, point defence, walls that
  actually block drones, player weapons (late), player-built gunships (ships are "both", decision 2026-11-04).
- **Needs before any of this works (all missing):** player health/death/respawn, building health and
  destruction, a damage contract shared by everything (`06-architecture.md` A4), wreck salvage.
- **Reward:** killed ships drop **wrecks** - salvage (rare alloys) and **alien tech data** for research. Threat
  is not only a cost; it is the source of the late-game tech tree.

## C7. Directives, research & progression - partial (7-quest tutorial built)

- **Directives** (the contract): the Continuance asks for goods delivered through an **Uplink** (a building
  that consumes items and "launches" them - a spectacle and a signature spike). Directives give **Continuance
  credit** (spent on supply drops: blueprints, rare parts, cosmetics) and unlock the next arc when a milestone
  Directive is met.
  - Hand-authored **milestone Directives** form the spine of each arc.
  - Procedural **standing Directives** keep the endless game going: "deliver N of X within M hours", scaled to
    current production, rotating.
- **Research:** data points come from *doing*: scanning a new ore, sampling a new biome, analysing a wreck,
  running a machine for the first time. Research nodes unlock buildings, parts and upgrades. Two currencies on
  purpose: credit says "Earth is pleased", research says "you learned something".
- **Today:** `QuestManager` + 7 quest resources is the seed of the tutorial Directives. It becomes the
  milestone-Directive engine (same data-driven objective types), not a parallel system.

## C8. Travel: vehicles & ships - built (physics), missing (purpose)

- **Built:** one Construct system for buggies and ships, wheels, thrust, gyros, landing gear, oxygen.
- **Role (decision: both):** early **haulers** (cargo parts, a buggy that carries ore from a remote drill),
  later **ships** to reach moons/asteroids/planets, later still **armed ships** that fight raids.
- **Missing:** fuel/power on constructs, cargo parts that interact with pipes (dock connector), map/waypoints,
  a reason to go (remote deposits richer than home ones; biome-locked resources), wreck salvage.

## C9. Survival layer - partial

- **Built:** suit oxygen (300 s), refilled at the garage or in sealed cockpits; 40% speed when empty.
- **Missing:** **health**, damage from falls, threats and hazards; death and respawn at a **Respawn Beacon**
  (a building; first one is the landing pod) with a dropped-inventory marker; biome hazards (cold, heat, toxic,
  radiation near crystal) answered by suit modules. Survival exists so the world and the threat have teeth;
  it is never a chore (no hunger, no thirst).

## C10. Power - missing (deferred in Slice 1, required by arc 2)

Deposit drills, turrets, containment, robots and uplinks all need it, so it is core even though it is not built.
- **Model:** grids by connection - **power poles/relays** with a link radius; buildings connect to the nearest
  pole. One shared pool per connected grid; demand vs supply; brownout slows every consumer proportionally
  (readable, not punishing). Batteries buffer.
- **Sources by arc:** burner generator (coal/carbon), solar (depends on star irradiance - already computed by
  `StarBody`, so dark side / distance matter), **crystal reactor** (huge output, **big signature** - the
  central risk/reward choice of the mid game).

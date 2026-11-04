# 07 - Roadmap from the design pass

Ordered by dependency and by what proves the game fastest. Two tracks run side by side: **Gameplay** (the
loop) and **World** (planets). Every milestone ends playable and tested; each pulls its own small things from
`04-small-things.md` instead of deferring them.

## Economy audit (2026-11-04, from `data/recipes`)

| Item | Recipes that consume it | Problem |
|---|---|---|
| iron ore / iron ingot (`ore_a` / `refined_material`) | 10 / 33 | carries the whole game; everything is iron |
| copper ore / ingot (`ore_b` / `refined_copper_ingot`) | 2 / 9 | ok |
| coal / carbon | 2 / 1 | carbon only feeds the cannon turret |
| silica / refined silica | 2 / **0** | **dead end** - refine it and nothing uses it |
| sulfur | 1 (gunpowder) | ok but narrow |
| crystal (`ore_crystal`) | **0** | **the game's central resource has no recipe** - only raises signature |
| stone | **0** | dead end, clogs inventory (known) |
| placeable block | 0 | fine (it is placed, not consumed) |

Target economy (tiered, every good has a sink):
- **T1:** iron ingot, copper wire (from ingot), concrete (stone + ... -> gravel -> concrete).
- **T2:** steel (iron + carbon), glass (silica), circuits (copper + silica), explosives (sulfur + carbon).
- **T3:** crystal cell (crystal + glass + steel) -> reactor fuel, shield cores, Directive goods; alloys from
  wreck salvage -> T3 ship and robot parts.
- Directives consume mostly T2/T3 goods, so the factory exists to feed the uplink.

## Milestones

### G1 - Foundations for everything (no new content, unblocks all of it)
- `GameEvents` bus; quests subscribe to it (no behaviour change).
- `Health` component + one damage contract; player health, death, respawn at landing pod.
- `FactoryClock` replaces per-building timers (measure: identical output in `pipe_test`).
- Deconstruct with refund; hotbar 1-9 + pick-what-I-look-at.
- Save `version` + migration table.
- `tools/run_tests.sh` (all driven tests under xvfb).

### G2 - The factory loop closes
- Deposit Drill (automated, real voxel bore) + crusher (stone sink).
- Economy T1-T2 recipes (above); silica and crystal get sinks.
- Throughput numbers + idle reasons in machine panels.
- Pipes body-local (fix the world-Y boundary).
- Uplink + first milestone Directives replacing the tutorial quest chain end; research points from first-time
  actions.

### G3 - Power
- Poles, burner generator, solar (irradiance), batteries; brownout; drills/turrets/uplink consume.
- Crystal reactor (signature source).

### G4 - Threat that bites
- Signature as sum of sources; HUD gauge.
- Gunship raids with warnings (wave specs), building damage/repair, wrecks + salvage + xeno research.
- Then dropships + ground drones (base-local nav grid), walls, then spotter + bombardment.

### G5 - Mechanisms & robots (Scrap Mechanic layer)
- 0.25 m mechanism grid + migration.
- Constructs as grid trees: bearing, hinge, piston (motorised).
- Logic: wires, gates, timer, controller, sensors.
- Robot Core + behaviour cards (Haul, Mine, Build).

### G6 - Reach further
- Cargo + dock connector (haulers close the loop), fuel, jetpack, waypoints + planet map.
- Day/night spin.

### W1-W6 - World track (see `05-planets.md` "Order of work")
W1 recipe extraction -> W2 slope/altitude erosion -> W3 landforms (terraces, canyons, spires) -> W4 archetypes
+ palette harmony (moon becomes Frozen) -> W5 scatter rules + POIs -> W6 floating origin + second planet.

## Suggested order across both tracks

G1 -> (G2 || W1-W2) -> (G3 || W3) -> (G4 || W4-W5) -> G5 -> (G6 || W6)

## Decisions still open (Michael)

1. Working names: Severance / Continuance / Voyager - keep or rename?
2. Deposit finiteness: finite-per-region (proposed) or infinite like Satisfactory nodes?
3. Death penalty: drop backpack at death spot (proposed) or lose nothing?
4. Logic depth for robots: gates + cards (proposed) or also a small visual script later?
5. Does the home planet stay 20 km radius, or drop to 8 km (faster streaming) until floating origin lands?

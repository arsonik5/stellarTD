# 03 - Minor mechanics (layer 2)

Systems that make the core mechanics pleasant, deep or legible. The game works without any single one of them,
but not without most of them. Grouped by the core mechanic they serve. Status: built / partial / missing.

## Serving Extract & Process (C2, C3)

| # | Mechanic | Status | Design |
|---|---|---|---|
| M1 | Stone & overburden | partial | Stone yields from every bore. Crusher: stone -> gravel -> concrete (foundation tier 2). Trash/void port for excess. Inventory full = HUD warning + drill stops paying (see tier-2 drill feedback). |
| M2 | Drill tiers | missing | Hand drill mk1-3 (speed/reach, SE numbers 1.0/1.2/1.4), excavate mode on RMB (big hole, destroys yield). Deposit drill heads mk1-3 (depth reach). |
| M3 | Machine tiers & modifiers | partial | `modifier_slots` + `compatible_modifiers` exist on `Building` but no modifiers are defined. Define 3: speed (+power), yield (+signature for crystal machines), efficiency (-power). |
| M4 | Throughput numbers | missing | Every machine and pipe shows items/min in its panel; a machine shows why it is idle (no input / output full / no power). |
| M5 | Pipe tiers & filters | partial | Vacuum pipe mk1/mk2 speeds; a filtered splitter (send item X left). Body-local orientation fix first. |
| M6 | Storage | partial | Chest exists. Add pipe-in/pipe-out ports and a "keep N" limit; large silo for ore. |

## Serving Survey & Travel (C1, C8)

| # | Mechanic | Status | Design |
|---|---|---|---|
| M7 | Waypoints & map | missing | Player-placed beacons (item + building) visible as HUD markers; a planet map screen (orthographic globe from the generator's coarse fields, explored areas revealed). |
| M8 | Landmarks / POIs | missing | Crash sites, Continuance probes (lore + research), alien wrecks (from threat), crystal spires, caves. Placed by a sphere-spots field per planet; see `05-planets.md`. |
| M9 | Fuel & construct power | missing | Hydrogen/ fuel tank parts, fuel from processing (ice -> hydrogen on cold worlds); batteries charge from the base grid via a dock connector. |
| M10 | Cargo & docking | missing | Cargo part (inventory), a dock connector that pipes can push/pull through when a construct parks on a pad. Lets haulers close the logistics loop. |
| M11 | Day/night | missing | Bodies rotate (`CelestialBody.rotation_period`); solar output, visibility and raid timing (raids prefer night) follow. Needs the star to move relative to the surface - no world-Y assumptions. |
| M12 | Weather | designed | Dust storms (visibility, solar down), cold snaps; see `architecture/atmosphere-weather.md`. Hazards hook into suit modules (M15). |

## Serving Build & Mechanisms (C4, C5)

| # | Mechanic | Status | Design |
|---|---|---|---|
| M13 | Deconstruct & refund | missing | Hold-to-dismantle with full refund (Satisfactory rule: experimentation must be free). Contents go to inventory or drop as a crate. |
| M14 | Blueprints | missing | Save a selection (buildings or a construct) as a blueprint; place as a ghost; materials pulled from inventory; robots with a Build card fill ghosts (arc 5). |
| M15 | Paint tool | decided | Grey by default, paint per part (art-direction decision 2026-11-03). |
| M16 | Wiring & logic tool | missing | Connect tool for logic wires between mechanism parts; signal shown as glowing wire; gates AND/OR/NOT/XOR, timer, counter, comparator. |
| M17 | Joint motors & settings | missing | Every bearing/piston/hinge panel: speed, limits, torque, inverted, bound to a controller key or a logic input. |
| M18 | Behaviour cards | missing | Robot Core slot; cards: Haul, Mine, Patrol, Build, Repair, Follow. Card settings set by pointing (pick source, pick destination). |

## Serving Threat & Defence (C6)

| # | Mechanic | Status | Design |
|---|---|---|---|
| M19 | Health & repair | missing | One `Health` component on player, buildings, construct blocks, enemies. Repair by tool (consumes material) or by a repair robot. |
| M20 | Turret ammo logistics | built | Pipe-fed ammo, per-ammo enable toggle. Add: turret range ring in build ghost, target priority setting (air/ground/nearest/strongest). |
| M21 | Walls & shields | missing | Walls matter only against dropship drones (ground pathing). Shield generator (designed `ShieldComponent`), power-hungry. |
| M22 | Containment | designed | Scope 5: powered dampers that subtract signature in a radius - the "stay quiet but still mine crystal" path. |
| M23 | Wave warning | missing | Uplink alert with bearing + ETA + composition; HUD compass marker; calm timer between waves. |
| M24 | Salvage | missing | Wrecks yield alloys + alien data; salvage takes time with the drill (wrecks are voxel-ish / block constructs). |
| M25 | Player weapon | missing | Arc 4+: one sidearm and one rifle, physical projectiles (existing `Projectile`). Not the main answer to threats. |

## Serving Progression & Survival (C7, C9)

| # | Mechanic | Status | Design |
|---|---|---|---|
| M26 | Uplink | missing | Building that consumes Directive goods; launch animation + signature spike; shows active Directives. |
| M27 | Research tree | partial | Journal tech-tree UI exists (quest diamond). Becomes the research tree: nodes cost data points by category (geology, engineering, xeno). |
| M28 | Standing Directives | missing | Generated contracts scaled to measured production; 3 offered at a time; reroll costs credit. |
| M29 | Supply drops | missing | Spend credit: a pod lands near the base (spectacle, physical, can land badly). |
| M30 | Respawn beacon | missing | Landing pod is beacon #1; buildable later. Death drops a backpack marker. |
| M31 | Suit modules | missing | Thermal, toxic filter, radiation shield, jetpack (arc 3, SE-style - essential on big planets), extra O2. |
| M32 | Logs & lore | missing | Uplink messages, probe logs, wreck data fragments. All text, all optional. |

## Cross-cutting

| # | Mechanic | Status | Design |
|---|---|---|---|
| M33 | Audio (world) | missing | Drill, machines, pipes, turrets, ships, weather; attenuated by air density, silent in vacuum (except through your suit - contact sound). UI audio built. |
| M34 | Save versioning | partial | Save works; add a `version` field and migrations (already did 2 m -> 0.5 m conversion ad hoc). |
| M35 | Settings & accessibility | partial | Settings panel built; add key rebinding, colour-blind check, subtitles for uplink voice (if any). |
| M36 | Statistics | missing | Production graphs per item (also feeds standing-Directive scaling). |

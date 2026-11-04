# 06 - Game architecture (whole-game technical shape)

How the code should be organised so the mechanics in 02-04 can be built without rewrites. Each section: today,
target, migration. Engineering patterns that already work stay in `architecture/engineering.md`.

## A0. Invariants (unchanged, restated because everything depends on them)

- Radial gravity, multiple bodies: no world-Y-up outside strictly local code. Every new system takes "up" from
  `PlanetPhysics`. Known violator: pipe/merger/splitter cardinal math (fix in A6).
- Every system is modular and toggleable; joins the save via `save_state()/load_state()`.
- Data in `Resource`s, behaviour in scripts, no per-item code paths.
- Deterministic where it can be (projectiles, factory ticks) - keeps co-op possible later.

## A1. Layers

```
 data/          Resources: Item, Recipe, OreType, Biome, CelestialBody, AmmoType, Quest
                + NEW: Directive, ResearchNode, PlanetArchetype, TerrainRecipe, ScatterSet, PoiSpec,
                       EnemySpec, WaveSpec, PowerSpec, PartSpec (mechanism parts), BehaviourCard
 services/      autoloads (one per cross-cutting concern, see A2)
 world/         scene nodes: Planet, Building, Construct(Ship), Turret, Projectile, Enemy*
 player/        controller, tools, feel
 ui/            screens on the one UI kit (ux-bible)
 save/          SaveManager + migrations
```

## A2. Services (autoloads)

| Service | Today | Target |
|---|---|---|
| `GameEvents` | **missing** | **Signal bus**: `item_gained`, `item_crafted`, `building_placed/removed`, `damage_dealt`, `entity_destroyed`, `scanned`, `wave_started/ended`, `directive_completed`... Quests, research, stats, audio and HUD subscribe; producers never call consumers directly. Replaces `QuestManager.notify_*` calls. |
| `Inventory` | built | unchanged API; gains `changed_item(id, delta)` emitted through `GameEvents`. |
| `PipeNetwork` | built | per-body, body-local orientation (A6). |
| `PowerNetwork` | missing | graph of poles; per-grid supply/demand; `satisfaction` 0..1 per grid that consumers read. |
| `FactoryClock` | missing (each Building owns a `Timer`) | one fixed-rate tick (10 Hz) driving all machines and pipes. Deterministic, cheaper than N timers, needed for power brownout and throughput numbers. Migrate by making `Building` register with the clock instead of creating a `Timer`. |
| `RadiationSignature` | crystal count only | sum of `SignatureSource` contributions with decay; containment subtracts. |
| `ThreatDirector` | scene node, scout only | service + per-body director: tier -> `WaveSpec` schedule, warnings, spawn. |
| `Progression` | `QuestManager` | Directives + research + credit; quests become milestone Directives (same objective types). |
| `SaveManager` | built | + `version` + migration table (M34). |
| `UiState`, `GameSettings`, `UiSound` | built | unchanged. |

## A3. Entities: composition over inheritance

Today `Building` holds inventory, recipes, modifiers, timer and highlight in one class; turrets, garages and
chests extend it. Keep the class (it works) but new capabilities arrive as **child components** discovered by
type, the same way `Ship` gathers block capabilities:

- `Health` (A4), `PowerConsumer` / `PowerProducer`, `SignatureSource`, `PipePort`, `LogicPort` (C5),
  `Targetable` (threat AI picks targets through it).

A building or a construct block is then "a model + a set of components" and new mechanics never edit
`building.gd`.

## A4. One damage contract

Today: enemies use `take_damage(amount)`, ship blocks `apply_damage(amount)`, projectiles look for the group
`enemy`. Target: a `Health` component with `apply_damage(amount, type, position, source) -> float applied`,
signals `damaged`, `destroyed`. Player, buildings, construct blocks, enemies all carry one. Projectiles,
explosions, falls and hazards all call the same method; armour/resistances are data. Factions decide who
shoots whom (`player`, `alien`), not groups named after one enemy.

## A5. Constructs (ships, vehicles, robots)

- Today: `Ship` = one `RigidBody3D`, 0.5 m `ShipGrid`, capabilities gathered from blocks. Good base.
- Target: **Construct = tree of grids joined by joint parts** (C5). Each grid is a body; joints are Jolt
  constraints with motors; mass/COM per grid; connectivity flood-fill already exists and extends across joints.
- Grid cell 0.25 m (mechanism grid). Data migration 0.5 -> 0.25 like the earlier 2 -> 0.5 conversion.
- Control flows: input (pilot keys / sensors) -> **logic graph** (gates, timers) -> joint targets & thrusters.
  The logic graph is evaluated on `FactoryClock` ticks so it is deterministic and cheap.
- Robots: Construct + `RobotCore` component that runs a `BehaviourCard` (state machine resource) issuing the
  same control signals a pilot would. The AI never moves the body directly - it drives the parts, so a badly
  built robot fails physically.
- Enemy ships keep using `Ship` (already migrated) - one physics for player, AI and robots.

## A6. World placement on a sphere

- Every placed thing stores body + body-local transform (needed for spin/day-night M11 and floating origin).
- Pipes: replace cardinal world-axis math with directions in the foundation's (or local tangent) basis;
  `PipeNetwork` keys cells in body-local grid space.
- Foundations: keep linear scan until >500 per base, then a body-local spatial hash.

## A7. Threat AI

- `WaveSpec` (composition, approach bearing, timing) from tier + signature; `EnemySpec` per type (scout,
  gunship, dropship, drone, spotter).
- Air units: steering on `Ship` controller (exists). Ground drones: pathing on the voxel surface - a coarse
  navigation grid built per base area (radius ~200 m) from foundations + terrain samples, rebuilt on edits;
  never a planet-wide navmesh.
- Bombardment: shells are ordinary `Projectile`s from altitude with a terrain-damage payload (voxel sphere
  edit) - craters persist via the existing save path.

## A8. Performance budget (targets, to measure against)

- 60 fps on the dev GTX-class 6 GB GPU at 1080p with a 200-building base, 300 items in pipes, 40 projectiles.
- Factory tick <= 2 ms; logic graph <= 0.5 ms for 20 constructs; projectile pool (data-oriented) once live
  shells > 100 (engineering doc's known gap).

## A9. Testing

- Keep driven headless scenes per mechanic (`scenes/dev/*_test.tscn`), printing `PASS/FAIL` lines and a
  `DONE fails=N` summary (build_fp_test pattern). Add one per new service.
- `tools/run_tests.sh` runs them all under `xvfb-run` so the mouse-capture check works too (headless mode
  cannot capture the mouse - that is the 1 fail seen in a pure `--headless` run, not a bug).

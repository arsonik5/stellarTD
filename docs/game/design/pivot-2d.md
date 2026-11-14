# Pivot to 2D: the direction change plan

Decided by Michael 2026-11-14. This file replaces the 3D-specific parts of `01`-`07` in this folder until those
files are rewritten (step P0.6). Where this file and an older design file disagree, this file wins.

Status (2026-11-14): defaults accepted, P0 under way on `pivot/2d`. Done: tech spike (P0.2), sprite + lit tool
(P0.3), branch + `last-3d` tag (P0.4), services (P0.5), lit sprite test. Waiting: Michael's style pick (P0.1).

References: `docs/game/reference/pivot-2026-11-14-references.md` (Garbage Country for mood, pixelfx for effects).
Gameplay read: Mindustry and Factorio (Michael 2026-11-14: "more like Factorio, with height"). Look: Astroneer. Ship building read: Cosmoteer (top-down block ships).

---

## 1. What changes, in one paragraph

Stellar TD stops being a first-person 3D game on voxel spheres and becomes a **top-down 2.5D pixel-art game drawn
with 2D sprites**, read like Mindustry: you see your base from above, walls and buildings show a front face, tall
things overlap what is behind them. The game itself stays: land alone, survey, mine, automate, research, deliver
to Earth, raise your signature, defend against waves, build ships, go to other worlds. **Height stays** as real
elevation levels with cliffs. **Worlds become flat, finite maps**, one per planet, loaded one at a time. Ships fly
over the map; climbing high enough leaves for a small **space scene** where you pick the next world. Art comes from
Qwen-Image 2.1 on furryass (RGBA sprites and tiles), effects from pixelfx (MIT).

## 2. What does NOT change

- **The vision** (`01-vision.md`): premise, tone, the fantasy line, the five arcs, the scope guards (not survival
  chores, not an FPS, no fauna in 1.0). Pillar wording changes only where it says "voxel" or "sphere" (P0.6).
- **The loop**: survey -> extract -> process -> build -> deliver -> unlock -> reach further, with signature ->
  threat -> defend running beside it.
- **The pillars, re-read for 2D:**
  1. *The world is the resource*: big maps worth exploring, ore you find with eyes and scanner, ground you dig down.
  2. *Build it once, then automate it*: hand -> machine -> network -> robot. Unchanged.
  3. *Success has a price*: signature draws threat. Unchanged.
  4. *Everything is physical*: items visibly ride conveyors, projectiles fly and can miss, ships have mass and
     inertia, dug ground stays dug. Unchanged in spirit; no 3D rigid-body physics needed to honour it.
  5. *Every action answers back*: unchanged, and easier to do well in 2D (pixelfx, screen shake, flashes).
- **Data**: 89 items, 79 recipes, research nodes, directives, quests, ore types, ammo, traits, biomes,
  archetypes. Kept as Resources; only fields that describe 3D models or materials get replaced by sprite refs.
- **The UI kit and ux-bible rules**: menus, HUD, inventory, journal are already 2D Control nodes.
- **Engine**: Godot 4.7, GDScript, same repo, same test style (driven scenes printing PASS/FAIL).

## 3. Mechanic by mechanic: from 3D to 2D

Status column: **keep** (logic ports as is), **adapt** (same idea, new 2D implementation), **new**, **cut/defer**.

### Core (from `02-core-mechanics.md`)

| # | Mechanic | 2D version | Status |
|---|---|---|---|
| C1 | Survey | Fog of war that clears around the player and buildings. Ore shows on the surface as coloured tiles (Mindustry). Deep ore needs the scanner: same radar minigame, reveals hidden deposits as tile overlays. POIs visible from a distance as tall sprites. | adapt |
| C2 | Extract (hand) | Hold LMB on a tile within reach: the drill bites, chips fly, the tile cracks over N hits, then pays and **drops one elevation level** (or breaks a rock wall). Hardness per material, as today. | adapt |
| C2 | Extract (drill building) | Deposit Drill is a 2x2 or 3x3 building on ore tiles; output rate from ore tiles under it x tier x power. Ore is **finite per tile** (amount field), so drills deplete and must move. Deep drill heads mine deeper levels. | adapt |
| C3 | Process | Smelter, processor, constructor, crusher, chest: same recipes, same Building logic, new sprites. | keep |
| C3 | Logistics | **Conveyors** carry items tile to tile (visible items), with junctions, routers/splitters, mergers, filters (sorters), bridges over other belts and up/down a cliff via a lift. **Pipes** carry fluids (water, hydrogen, fuel). Replaces "vacuum pipes carry items". | adapt |
| C4 | Build | Grid placement with a ghost under the cursor, R to rotate, drag to place belts and walls in lines, hold to dismantle (full refund, design rule kept), pick (MMB), hotbar 1-9, copy/paste areas, blueprints. Foundations become **floor tiles** (needed on soft ground and to build on rough levels). | adapt |
| C4 | Three nested grids | One build grid (1 tile). Ship/robot parts use their own grid (see C5/C8). The 2 m / 0.5 m / 0.25 m lattice is retired. | cut |
| C5 | Mechanisms & robots | **Robots = units you design**: a chassis grid (Cosmoteer-style) with modules (drill head, cargo, gun, legs/wheels/thrusters, battery) plus a **behaviour card** (Haul, Mine, Patrol, Build, Repair, Follow). Scrap Mechanic joints and logic gates are **deferred** past 1.0 (see decision D6). | adapt + defer |
| C6 | Signature, threat, defence | Same tiers (quiet -> noticed -> hunted -> contested -> siege). Ground drones walk on a **flow field** over the tile grid (respects cliffs, ramps, walls). Air units fly straight, cast shadows, ignore walls. Bombardment craters lower tiles. Turrets fed by conveyors. Walls finally matter. Wrecks drop as salvageable tile objects. | adapt |
| C7 | Directives, research, progression | Unchanged logic (Progression, QuestManager, uplink). Uplink launch is a big 2D spectacle. | keep |
| C8 | Vehicles & ships | **Top-down block-built ships** (Cosmoteer read): build in a dock on a grid, fly over the map with momentum. **Altitude** is a number: higher = bigger shadow offset, slight zoom-out, ignore cliffs; land only on flat ground. Climb past the ceiling -> **space scene**. Ground vehicles (haulers) are the same system with wheels. | adapt |
| C9 | Survival | Health, falls (dropping off a cliff more than N levels hurts), suit O2, death and respawn at a beacon, backpack marker. Hazards per biome tile. | keep |
| C10 | Power | Poles with link radius drawn as lines, grids, brownout, batteries; burner, solar (day/night), crystal reactor. Logic of `PowerNetwork` kept, positions become 2D. | keep |

### Minor (from `03-minor-mechanics.md`)

| # | Mechanic | 2D version |
|---|---|---|
| M1 | Stone & overburden | Digging pays stone; crusher -> gravel -> concrete floor tiles. Void/trash building. |
| M2 | Drill tiers | Hand drill mk1-3 (bite speed, reach in tiles), drill heads mk1-3 (deeper levels). |
| M3-M4 | Machine tiers, throughput | Unchanged; items/min shown in panels. Conveyor tiers have exact items/s. |
| M5 | Pipe tiers & filters | Become conveyor tiers + sorter/overflow gate (Mindustry set). |
| M6 | Storage | Chest, silo, "keep N" limits; conveyors in and out. |
| M7 | Waypoints & map | Full-map screen (the map IS the world, so this is cheap); player pins. |
| M8 | POIs | Crash sites, probes, wrecks, crystal spires as multi-tile objects placed with spacing. |
| M9-M10 | Fuel, cargo, docking | Ship fuel tank, cargo module; landing pad with conveyor ports loads/unloads a parked ship. |
| M11 | Day/night | 2D lighting: `CanvasModulate` tint over the day, lights on buildings at night, solar output follows. |
| M12 | Weather | Dust storms (screen haze, solar down), snow on cold worlds as particles + tint. |
| M13-M14 | Dismantle, blueprints | Grid makes both much easier than in 3D. Blueprints in P2, not P5. |
| M15 | Paint tool | Palette-swap per building (shader). |
| M16-M18 | Wiring, joints, cards | Cards kept (robots). Wiring and joints deferred (D6). |
| M19-M25 | Health, turrets, walls, shields, containment, wave warning, salvage, weapon | All kept. Wave warning = edge-of-screen arrow + ETA. Player sidearm = twin-stick aim with the mouse. |
| M26-M32 | Uplink, research tree, standing directives, supply drops, beacon, suit modules, logs | All kept as they are. Supply drop is a pod sprite falling with a shadow. |
| M33 | World audio | Kept; positional 2D audio. No vacuum muffling rules beyond a per-world flag. |
| M34-M36 | Save versions, settings, stats | Kept. Save format v2 (tile world). |

### What is retired (deleted once replaced)

Voxel terrain (godot_voxel, VoxelLodTerrain, graph generator, erosion baker GPU path, terrain shader, near
scatter, VoxelInstancer), sphere physics (`PlanetPhysics` radial gravity), first-person controller and feel, 3D
ship physics (Jolt rigid bodies, block grids in 3D), atmosphere renderer, Blender kit pipeline for in-game models,
3D foundations/pipes/knees. Roughly: most of `scripts/world` (75 files), `scripts/player/player.gd`, `shaders/`,
`art_src/` model generators. The ideas in them (traits, strata, craters, erosion) are carried into the 2D generator.

## 4. The 2D world

### 4.1 Map, tiles, scale

- **1 tile = 1 metre = 32 px** at 1x zoom. Camera zoom 1x-4x (pixel-perfect steps) plus a zoomed-out map view.
- **World size by archetype**: home 1024 x 1024 tiles (1 km square), moons 512 x 512, big late worlds up to
  2048 x 2048. Edges are cliffs/ocean, not invisible walls.
- **Chunks of 64 x 64 tiles**: generated, rendered, simulated and saved per chunk. Only chunks near the player and
  near buildings render; simulation runs everywhere there are buildings.
- **Per-tile data** (packed arrays per chunk, not nodes): elevation (int8), ground type, ore type, ore amount,
  wall/rock flag, floor (built), fluid (water/ice/lava), light/explored bits. A 1024^2 world is ~1 M tiles x
  ~8 bytes = ~8 MB raw, a few MB compressed in the save.

### 4.2 Height

- **Elevation levels -4 .. +20** (25 levels, see 4.3). Level 0 is the "plain". Mountains, mesas, crater rims go up; pits,
  canyons, river beds and anything you dig go down. Bedrock stops digging at -4 (deeper with drill tiers later).
- **Drawing (the 2.5D trick):** each level draws its tiles shifted up by 8 px per level, and the drop between two
  levels draws a **cliff face** strip (strata shows there, like the Garbage Country frames). Things on higher ground
  sort above things behind them (Y-sort by tile row, then level).
- **Rules:** you walk freely on one level, cross levels only by **ramps** (natural slopes or built). Falling off
  more than 2 levels hurts. Buildings need all their tiles on one level (or a floor tile on top). Turrets on high
  ground get +range. Ground enemies path around cliffs; air units ignore them. Water fills the lowest levels.
- **Digging changes height**: a dug tile drops one level, so a quarry is a stair of pits, exactly "holes stay dug".

### 4.3 Generator: the same planet methodology, drawn as a flat map

Michael, 2026-11-14: planets keep "the same methodology and mountains and everything we built so far ... the same
variety of planets and terrain heights, ridges, overhangs, mountains, etc. Just in the new direction."

So this is a **port, not a new generator**. Same chain as `architecture/planet-surfaces.md`:
**archetype -> traits -> palette -> landforms -> erosion -> ground rules -> ore -> scatter -> POIs**, same data and
mostly the same code, sampled on a flat plane instead of a sphere:

| Today (sphere) | 2D map | Reuse |
|---|---|---|
| `PlanetArchetype`, `TerrainRecipe`, `PlanetTrait`, `TraitMixer`, `PaletteBuilder` | unchanged data and mixing | code as is |
| Landform layers in the voxel graph: continents, ridged mountains, terraces/mesas, canyons, spires, dunes | same formulas evaluated per tile on (x, y) | port formulas from `planet_graph_generator.gd` |
| `CraterField` (craters, rims, rays, ejecta) | same list, placed on the plane | code mostly as is (drop the sphere projection) |
| Erosion compute shaders (droplet, thermal, slope, deposition, talus, wear masks) | run on the flat heightmap; no seam, no projection | shaders re-pointed, `sphere_uv` dropped |
| Strata, ledges, cracks, lava tubes (stage 4b) | strata = bands on cliff faces; ledges = intermediate levels; tubes and caves = overhang tiles (below) | rules ported |
| Ground rules, ore deposits, `ScatterEngine` asset lines, `PoiField` spacing | per tile / per sprite | logic as is |
| Biomes, climate, archetype palettes | per tile | as is |

**Height range for mountains:** levels **-4 .. +20** (25 levels, still one byte). Plains sit around 0-2, mesas and
crater rims at 4-8, ridged mountain ranges up to 20 (a 20-level face is 320 px tall at 1x: mountains are walls you
build around, tunnel through or climb by ramps). Quantising the eroded heightfield: steep slopes become cliffs,
gentle slopes become ramps (natural slope tiles, walkable), so the erosion still decides where you can walk.

**Overhangs, arches, caves, lava tubes:** a tile can carry a **roof**: a second level above its floor. The floor is
walkable underneath; the roof is drawn as its own layer (cliff top + lit underside edge) and fades out when the
player or the camera focus is under it (Rimworld-style). That gives overhangs on cliff faces, natural arches,
cave mouths into mountains and the stage-4b lava tubes, without a 3D world.

**Variety check (same as today's census):** every archetype's map is measured on generation: level histogram,
cliff share, walkable share, ramp count, ore coverage, POI spacing. Each archetype has a target band, enforced by
a test, so planets stay as varied as the 3D ones were.

**Generation speed (Michael 2026-11-14: "2 minutes to generate a planet is just horrendous").** Hard budget,
enforced by a test that fails the build:

| Step | Budget (1024^2 home map, dev laptop) |
|---|---|
| Heightfield + landforms (FastNoiseLite images in C++, landform math on packed arrays) | < 1.0 s |
| Erosion (GPU compute, flat map; CPU fallback only for headless tests at reduced size) | < 1.5 s |
| Quantise, ramps, ground rules, ore, scatter, POIs | < 1.0 s |
| **New game to walking** | **< 5 s total**, with a progress bar that shows the real step |
| Load a saved world | < 2 s (tiles are stored, nothing is regenerated) |

How: no per-tile GDScript loops over the whole map where an Image/compute pass can do it; per-tile rules that
must run in script run per chunk on a worker thread, nearest chunks first, so the player can start walking while
far chunks finish; the finished map is cached by seed + archetype + generator version (a few MB), so a second
new game on the same seed is instant. If GDScript is still too slow for a step, that step moves to a GDExtension
(C++), not to a longer loading screen. The spike already generates a 1024^2 heightfield in 0.3 s.

1. **Determinism**: same seed -> same map, tested by a hash like today's `planet_hash_baseline`.
2. **Edges**: map borders are ocean, cliff walls or haze-out, chosen by archetype.

Archetypes for 1.0 stay the six from `05-planets.md`: Barren (home), Frozen (moon), Sulfur, Crystal, Mesa, Exotic.

### 4.4 Worlds and space

- A **world** = one map + its save (tiles delta, buildings, conveyors, entities). Only one world is loaded.
- **Star system scene** (2D, small): your ship flies among planet sprites with momentum; parked ships, stations
  and wrecks later. Flying into a planet's ring opens "land here?" -> pick a landing zone on that world's map ->
  load the world with the ship descending. Leaving: climb above the ceiling -> fade to the system scene.
- Things left on other worlds **keep running in a cheap mode**: when you leave, the world stores its machine rates;
  on return it fast-forwards production for the time away (capped, no combat simulated while away; raids only
  happen where you are, or are resolved by a defence-strength check, decision D7).
- Interplanet logistics (arc 4): cargo ships on routes between worlds' landing pads, resolved as transfers.

## 5. Technical plan

### 5.1 Architecture

```
 data/        Resources (kept) + new: TileSetDef, GroundType, SpriteSet, ShipPartSpec, UnitSpec, WorldSave
 services/    GameEvents, FactoryClock, Inventory, Progression, QuestManager, PowerNetwork,
              RadiationSignature, SaveManager, UiState, GameSettings, UiSound, WorldFx(2D)        (kept/ported)
              + WorldGrid (tile data, chunk access), ConveyorSystem, FlowField, WorldManager (load/switch worlds)
 world2d/     WorldMap (chunk renderer), Building2D, Turret2D, Unit (enemy/robot), Ship2D, Projectile2D,
              Pickup, Poi
 player/      PlayerTopDown (move, aim, tools, hand rule), PlayerVitals (kept)
 ui/          kit + screens (kept), new: map screen, ship editor, space HUD
 legacy/      3D code during the move, deleted per phase
```

### 5.2 Performance rules (Mindustry-scale bases)

- **Tiles are data, not nodes.** Rendering: one `TileMapLayer` per chunk per layer (ground, cliff faces, ore
  overlay, floors), or MultiMesh if TileMapLayer is too slow at the measured size (spike in P0.2).
- **Conveyors and items are data.** `ConveyorSystem` steps all belts on `FactoryClock` (10 Hz logic, items
  interpolated per frame), draws items with one MultiMesh per chunk. Target: 20 000 belt tiles, 10 000 items.
- **Buildings** stay Nodes (Building logic is already written for that) up to ~3 000; above that, move the hot
  ones (belts already, then drills/smelters) to data.
- **Enemies** move on a shared **flow field** per target group, recomputed when walls/buildings change.
- **Budget**: 60 fps at 1080p on the dev GPU with 2 000 buildings, 10 000 items moving, 200 enemies, 300
  projectiles. Factory tick <= 2 ms.

### 5.3 What ports and how

| Code | Today | Port |
|---|---|---|
| Inventory, Progression, QuestManager, FactoryClock, GameEvents, Settings, UiState | no 3D | as is |
| PowerNetwork | 2 Vector3 uses | positions -> Vector2i tiles |
| RadiationSignature | no 3D | as is |
| Building | StaticBody3D, 478 lines | logic split out into a 2D-agnostic core (`BuildingCore`: inventory, recipes, modifiers, idle reason, power), thin `Building2D` node on top |
| Turret, ThreatDirector, PlayerVitals | 3D math | rewrite the movement/targeting parts, keep tier/wave/health rules |
| SaveManager | 16 Vector3 uses | new world format v2; game-level data (inventory, research, directives) unchanged |
| UI (journal, inventory, build menu, HUD) | 2D | keep; build menu cards get sprite icons |
| Tests | driven scenes | keep pattern; new suites per phase (section 7) |

### 5.4 Branching

Branch `pivot/2d` from master. The 3D game keeps running on master until P1 is playable in 2D; then `pivot/2d`
merges, the 3D scenes move to `legacy/`, and each later phase deletes the legacy parts it replaced. The last
3D build is tagged `last-3d` so it can always be run again.

## 6. Art plan

### 6.1 Style rules (locked in P0.1, written into `art-direction.md`)

Michael, 2026-11-14: "more like Factorio, but with height"; "futuristic space art direction, more like Astroneer,
rather than this industrial raw gritty style"; "still keeping detail, like dirt accumulating from use and
explosions - MANY small details like that"; "all 2D sprites and art should be lit, normal mapped and all, to give
a 3D illusion of shadows".

- **Read:** Factorio's projection and density of detail, **Astroneer's look**: rounded chunky shapes, clean
  painted panels, white/light-grey bodies with bright accent colours (orange, teal, yellow) and soft forms. Worlds
  carry the Garbage Country mood (warm haze, layered cliffs, foam on water). NOT raw/rusty/gritty industrial.
- **Not retro pixel art.** Detailed rendered-looking sprites at **64 px per tile** (Factorio's HR density), shown
  at 1x zoom = 32 px per tile and sharp up to 2x. No palette quantise, no 1 px outline (those were pixel-art rules).
- **Projection:** top-down with a 3/4 tilt: roofs seen from above, a short south face visible.
- **Everything is lit (D11).** Every sprite and tile is an albedo + **normal map** (+ emissive mask where it glows)
  as a `CanvasTexture`. One `DirectionalLight2D` sun (angle and colour follow day/night), `PointLight2D` for
  lamps, furnaces, muzzle flashes, explosions. Shadows: each building/unit casts a soft shadow sprite projected
  along the sun direction from its height; cliffs cast onto lower ground the same way.
- **Wear and small details (D12): the world shows what happened in it.** All runtime, all persistent in the save:
  - grime on machines that grows with run time (shader blends a dirt mask by a per-building wear value);
  - scorch marks, craters and debris from explosions on ground and buildings; bullet pocks on walls;
  - ore spill and dust around drills, oil stains under machines, worn paths where the player and units walk,
    tyre and landing-skid marks, footprints that fade;
  - damage states (3 per building), sparks and smoke from damaged machines;
  - dust settling on idle machines, cleaned when they run (or by a repair bot later).
  Ground marks go into a per-chunk **decal layer** (a texture painted into, cheap and persistent); building wear is
  per-building shader parameters.

### 6.2 Pipeline (tool: `tools/sprite_pipeline.py`)

1. **Prompt** Qwen-Image 2.1 (`qwen-image` skill, `--rgba`) with a fixed style preamble + the object, at 1024 px.
2. **Downscale** to 64 px per tile footprint (+ the south face height), area filter, premultiplied alpha.
3. **Normal map** made by the tool: a bevel height from the alpha shape (distance to the edge) + fine detail from
   the albedo's luminance, Sobel -> tangent-space normal. Optional per-sprite hand-painted height for key parts.
   Emissive mask from bright saturated pixels (windows, lights, furnace mouths).
4. **Shadow shape** from the alpha, projected in engine by the sun direction.
5. **Moving parts** as separate sprites the engine animates (drill head spin, fans, pistons, belt scroll shader),
   because image models cannot draw consistent animation frames.
6. **Tiles:** Qwen draws a seamless top-down texture per ground type (+ its normal map via step 3); the tool builds
   dual-grid transition sets (16 tiles per pair), plus lit cliff-face strips with strata per level.
7. **Wear masks:** a dirt/scorch overlay per building made by the tool from the shape (edges and bottom get dirty
   first), blended at runtime.
8. **Effects:** pixelfx sheets (MIT, licence file in `art_src/licences/`), lit as unshaded additive where they glow.
9. **Review:** every batch lands in a contact sheet for Michael; rejects are re-prompted.
10. **Licence note:** Qwen-Image is research/non-commercial. Fine as long as Stellar TD stays non-commercial (D9).

### 6.3 Asset list for P1 (first batch)

Player (4 directions + tool in hand), ground tiles x3 types, cliff faces, ramp, ore overlays x5 (iron, copper,
coal, silica, sulfur) + crystal, rock wall, boulders x3, landing pod, deposit drill, conveyor (straight, turn,
junction, router), smelter, constructor, chest, power pole, burner generator, HUD icons for the P1 items.
About 40 sprites + 3 tile sets.

## 7. Phases

Each phase ends playable, with its own tests green and a short video/screenshot set for Michael.

### P0 - Ground work (no gameplay yet)

- **P0.1 Style lock**: Qwen draws the same small scene (ground, cliff, ore, drill, belt, smelter, player) in
  Astroneer-style variants; Michael picks one; then one machine goes through the full lit pipeline (albedo +
  normal + emissive + wear) in engine with a moving sun, so the lit look is judged in motion, not on a still.
- **P0.2 Tech spike**: 1024^2 map of noise tiles with 9 levels, cliff faces, Y-sort, 20 000 belts with 10 000
  items, camera zoom. Measure fps and memory; choose TileMapLayer vs MultiMesh.
- **P0.3 Sprite pipeline tool** with the P1 asset list run through it.
- **P0.4 Branch + legacy move plan**, `last-3d` tag, project settings for the 2D renderer (2D lights and
  shadows, linear filtering with mipmaps for the 64 px art, 2D physics).
- **P0.5 Port the pure services** (Inventory, Progression, FactoryClock, GameEvents, Power core) with their
  existing tests green. *Done 2026-11-14: they have no 3D code and pass in this project as they are.* The
  `BuildingCore` split moves to the start of P1: 20 machine types override `Building` hooks (idle_reason,
  output_ids, can_accept_input, save_state...), so the split is done together with `Building2D`, tested against it.
- **P0.6 Rewrite design docs** `01`-`07` for 2D (this file then shrinks to a pointer).

Done when: Michael has picked a style, the spike hits the budget, services pass their tests in the 2D project.

### P1 - Landfall (the feel loop, again)

World generator v1 (Barren home: levels, ramps, ground types, ore, rocks), fog of war, top-down player (WASD,
mouse aim, LMB/RMB hand rule, suit O2), hand drill on tiles (crack, pay, lower level), inventory and hand
crafting, build mode on the grid (ghost, rotate, drag lines, dismantle, pick, hotbar), deposit drill, conveyors
(straight/turn/junction/router/bridge), smelter, constructor, chest, landing pod, save/load (world v2), HUD,
main menu, sounds and pixelfx feedback for every action.

Done when: new game -> walk -> mine -> drill -> belt -> ingots in a chest -> save -> load, under 10 s to
playable, `playthrough2d` test green.

### P2 - Outpost

Power (poles, burner, solar, batteries, brownout), research tree and directives (port), uplink + launch,
scanner minigame, POIs, day/night with 2D lights, map screen + pins, blueprints and copy/paste, crusher/stone
loop, standing directives, supply drops.

Done when: arc 1-2 of the old game is fully playable in 2D, all old `systems` tests ported and green.

### P3 - Threat

Health contract, building damage and repair, signature sources, flow-field pathing, enemy units (scout, gunship,
dropship drones, spotter + bombardment), wave warnings, turrets (gun, cannon, flak) fed by belts, walls, shield
generator, containment, wrecks and salvage, player sidearm.

Done when: a full raid on a test base plays out with every tier, 200 enemies at budget fps.

### P4 - Ships and other worlds

Ship editor (grid, parts: hull, cockpit, thrusters, fuel, cargo, guns, landing gear), local flight and altitude,
landing pads with belt ports, star-system scene, moon (Frozen archetype) as world #2, leave/return with offline
production, interplanet cargo routes, armed ships vs air raids.

Done when: build a ship, fly to the moon, set up a drill there, ship ore home on a route.

### P5 - Colony and breadth

Robots (chassis + modules + behaviour cards), remaining archetypes (Sulfur, Crystal, Mesa, Exotic), weather,
suit modules, logs/lore, statistics, polish pass, retire the last legacy code.

## 8. Risks and how we handle them

| Risk | Why it matters | Answer |
|---|---|---|
| AI sprites look inconsistent | Mixed styles kill a pixel game fast | Style lock first, one preamble, palette quantise + tool-made outline/shadow, contact-sheet review, re-prompt rejects |
| Qwen can't do animation | Machines would look dead | Animate in engine with separate moving parts, shaders, pixelfx |
| Height in 2D reads badly | Core feature Michael wants | Spike it in P0.2 with real cliff faces before anything else is built on it |
| Performance with big bases | Mindustry-scale is the point | Data-oriented tiles/belts from day one, measured in the spike |
| The rewrite never "finishes" | 3D game stops being playable meanwhile | Master stays playable until P1 is done in 2D; each phase ends playable |
| Losing work that was good | Months of 3D systems | Logic ports (section 5.3); `last-3d` tag keeps the 3D game runnable |
| Qwen licence | Non-commercial | Fine now; D9 if that changes |
| Furryass availability | Her PC, GPU shared | Batch art jobs in the background; the pipeline caches every generated image |

## 9. Open decisions (Michael)

Defaults are what happens if you say "go".

| # | Question | Default |
|---|---|---|
| D1 | Tile size | 64 px art per 1 m tile (Factorio HR), 1x zoom shows it at 32 px |
| D2 | View | Top-down with 3/4 tilt (front faces), not pure top-down and not isometric |
| D3 | Height range | 25 levels (-4..+20) for real mountains, ramps and natural slopes between, roofs for overhangs/caves, digging lowers by 1 |
| D4 | World size | 1024^2 home, 512^2 moons, up to 2048^2 later |
| D5 | Items on belts | Conveyors for items, pipes for fluids (Mindustry) |
| D6 | Scrap Mechanic layer (joints, logic gates) | Deferred past 1.0; robots are module-built units with behaviour cards |
| D7 | Worlds you are not on | Production fast-forwards on return; raids only where you are |
| D8 | Player character | Small astronaut sprite, twin-stick aim, tools in two hands |
| D9 | Art licence | Qwen assets accepted as non-commercial; revisit if the game is ever sold |
| D11 | Lighting | Every sprite lit: albedo + normal map + emissive, sun + point lights, projected shadows (Michael 2026-11-14) |
| D12 | Look | Futuristic space, Astroneer-like, with many small wear details (dirt from use, scorch, spills); not gritty industrial (Michael 2026-11-14) |
| D10 | Branch strategy | `pivot/2d` branch, 3D master playable until P1 lands, `last-3d` tag |

# 2D pivot: progress and to-do

Working log for the 2D rebuild. Updated after every step. The plan itself is `docs/game/design/pivot-2d.md`;
references are in `docs/game/reference/pivot-2026-11-14-references.md`. Branch: `pivot/2d`. Last 3D build: tag
`last-3d` (master still runs the 3D game).

## Where we are (2026-11-14)

**Phase P1 (Landfall in 2D), systems first. Art is placeholder** (Michael: "we can always change sprites but all
systems need rebuilding"). Look direction for later: shrunk Qwen for atmosphere ("felt like a different planet"),
Mindustry-spirit pixel art, Unfallen camera (straight down, things lean by height), everything lit.

## Decisions so far (details in pivot-2d.md section 9)

- 2D, top-down, straight-down follow camera, perspective lean on raised things (Unfallen).
- 32 px pixel tiles; 1 tile = 1 m; 25 height levels (-4..+20); ramps between levels; cliffs elsewhere.
- Conveyors carry items, pipes carry fluids. Grid building. Same items/recipes/research data as 3D.
- Lit sprites (normal maps), dark nights with light pools, lots of wear details (later).
- Art production: code-drawn REJECTED ("feels AI, vibe-coded"). Qwen (shrunk/snapped, maybe a pixel LoRA) for
  now; asset packs or an artist are fallbacks. pixelfx (MIT) for effects.
- World generation budget: < 5 s new game to walking, < 2 s load (tested).

## Done

| Step | What | Where | Proof |
|---|---|---|---|
| P0 | Plan, references, branch, `last-3d` tag | docs/game/design/pivot-2d.md | - |
| P0 | Tech spike: 1024^2 map, 2 000 buildings, 20 000 belts / 10 000 items | scripts/dev/spike2d.gd | 1 150+ fps, tick 0.3-0.45 ms |
| P0 | Sprite tool: fit, palette, textures, dual-grid, cliff strips, normal maps, glow, snap-to-grid | tools/sprite_pipeline.py | `selftest` passes |
| P0 | Lighting + lean proof (straight-down camera, roof lean with walls, shadows, night) | scripts/dev/lean_test.gd | screenshots sent |
| P1.1 | **World data v2**: 25 levels, ground, ore + amount, flags (ramp/floor/explored), step rules, compressed save | scripts/world2d/world_grid.gd | world2d test |
| P1.6 | **Factory core**: `Building2D` (logic ported line for line from the 3D Building: slots, recipes on FactoryClock, auto, modules, power hooks, idle reasons, save/load; plus footprint, rotation, placeholder drawing that leans); machines smelter (2x2), chest (1x1), constructor (3x3), deposit drill (2x2, mines `ore_amount` under it, faster with more ore tiles); `BuildGrid2D` (occupancy, placement rules, pay with carried copy first then build recipe, dismantle with full refund incl. contents, Mindustry dump of outputs onto belts pointing away, save/load); `BeltSystem2D` (per-tile belts, 4 items/tile, 4 tiles/s, hand-off to belts/buildings, side-loading, drawn per level with lean + moving chevrons); new item + recipe `conveyor_belt` (1 refined_material -> 2) | scripts/world2d/building_2d.gd, machines/, build_grid_2d.gd, belt_system_2d.gd, data/items/conveyor_belt.tres, data/recipes/build_conveyor_belt.tres | factory2d test 15/15: 24 ingots reach the chest in 40 s |
| P1.5 | **Mining**: hold LMB on a tile in reach (2.6 tiles) -> cracks over hardness x 0.7 s -> pays 2 stone (+4 ore while the deposit lasts, `ore_amount` counts down) into `Inventory`, emits `item_mined`, tile drops one level and becomes rubble (ramp) so shallow pits are walkable, deep shafts are real holes; cliff faces can be cut back; refusals (on it, out of reach, bedrock, too far down, built floor). Cursor overlay with lean + cracks; mouse picks the LEANED tile under it; HUD shows the bag | scripts/world2d/mining_2d.gd, player_2d.gd, cursor_overlay_2d.gd | player2d test 11/11 |
| P1.4 | **Player**: top-down astronaut (placeholder drawing), WASD + mouse aim, tile collision via `can_step` (cliffs block, ramps carry, no diagonal squeeze), leans with its level, follow camera, zoom 1-4x; playable scene `scenes/world2d.tscn` (class `GameWorld2D`; `World2D` is a Godot built-in name) with a debug HUD; spawn on open plains near the centre | scripts/world2d/player_2d.gd, player_body_2d.gd, world_2d.gd | player2d test 5/5; `world2d.tscn -- --shot` screenshot, ~1 900 fps |
| P1.3 | **Renderer v2** (straight-down camera): per-vertex height + lean shader, one mesh per level per chunk (z by level), cliff walls with strata bands, slope shading, ore clumps, ramp marks; generator now terraces (flats 3 levels apart, cliffs where steep, ramps where gentle) | scripts/world2d/world_view.gd, shaders/world2d/lean.gdshader | world_view_test screenshots: walls lean and swap sides with the camera; 650-3000 fps; chunk build ~27 ms |
| P1.2 | **Generator v1**: continents, ridged ranges, canyons, mesas, detail; ramps on gentle slopes; ground rules; ore from data/ore_types | scripts/world2d/world_gen.gd | world2d test: 1.8 s for 1024^2, 25 levels, ramps 30%, cliffs 4%, all 6 ores, centre connects to 200k+ tiles, save 493 KB |

## Next (in order)

1. **Build mode in the game**: build menu (the 5 buildables), ghost under the cursor with lean, R rotate, drag to lay
   belt lines, refusal reason shown, X/hold to dismantle, hotbar 1-9, machine panel on click (recipes, auto, contents).
2. **More belt pieces**: junction, router/splitter, bridge, belt lift between levels (ramps).
3. **Save/load v2** (world bytes + buildings + belts + game state), main menu wiring.
4. Then P2 (power, research, uplink...) per the plan.

## Open problems / notes

- Decision (2026-11-14): no `BuildingCore` split of the 3D Building. `Building2D` carries the ported logic; machines
  are ported one by one as P1/P2 need them (smelter, chest, constructor, drill done); the 3D Building and its 20
  subclasses go with the 3D code. Power for 2D machines comes in P2 (PowerNetwork still looks at 3D buildings).

- Mining is on LMB always for now; the hand rule (tool in left/right hand, `Inventory.has_tool_equipped`) comes
  back with the build tool. No chip/dust effects yet (pixelfx later), sounds are the 3D game's UiSound ones.

- Run the 2D game: `godot --path . res://scenes/world2d.tscn` (add `-- --seed=N`). It is not the main scene yet
  (main menu still starts the 3D game).

- Qwen pixel-art test is queued (`art_src/qwen_px/run.sh`); it refuses while someone is at furryass - rerun later.
  Pixel LoRAs found (prithivMLmods Qwen-Image-2512 Pixel-Art, PixelArtRedmond); compatibility with Qwen-Image 2.1
  and licences NOT checked yet.
- Generator v1 is a first port: erosion bake, craters (CraterField), trait ground rules, scatter, POIs and
  roofs/caves/overhangs still to port (plan 4.3). Ramps cover 30% of tiles - may be too gentle a world; tune when
  we can walk it.
- Generation hot loops are GDScript (1.8 s). If more layers push it toward 5 s, move them to a GDExtension.
- Renderer: chunk build is ~27 ms in GDScript (2 per frame while panning = small hitches). Move mesh building to a
  worker thread or GDExtension before P1 ends. Colours are placeholders until the Qwen terrain textures exist.
- Terrain lean constants: LEVEL_HEIGHT 12 px per level, CAM_HEIGHT 360 px (world_view.gd). Tune by feel when
  walking.
- `scripts/dev/spike2d.gd` uses the old 3/4 renderer; it stays as the P0 record until renderer v2 replaces it.

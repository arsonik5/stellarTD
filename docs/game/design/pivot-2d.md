# Pivot to 2D (decided 2026-11-14)

Michael, 2026-11-14: Stellar TD becomes a **2.5D top-down pixel-art game drawn as true 2D sprites** (Mindustry is the
reference for how it reads and plays). Mechanics stay the same or close. Height stays. Worlds are flat and instanced;
ships fly locally, climbing high enough takes you to a small 2.5D space scene, which is mostly for show and is how
you pick another world. Art: Qwen-Image 2.1 on furryass (RGBA sprites), pixelfx (MIT) for effects.
He chose true 2D over a 3D pixel render (references: `docs/game/reference/pivot-2026-11-14-references.md`).

Status: plan proposed, defaults below wait for Michael's yes.

## What carries over (engine-agnostic, keep)

- Data: items (89), recipes (79), research, directives, quests, ore types, ammo, traits, biomes as data.
- Systems (autoloads): Inventory, Progression/research, FactoryClock, PowerNetwork, QuestManager, GameEvents,
  Settings, SaveManager pattern (slots, world state). Building logic (inputs/outputs, modifiers, idle reasons),
  ThreatDirector waves, turret targeting rules, PlayerVitals (health, O2, death/respawn).
- Terrain generator IDEAS: traits -> palette -> ground rules -> scatter, erosion, craters, strata, POIs. The code is
  sphere/voxel-specific and gets rewritten for a flat 2D tile map.
- UI kit and UX rules (ux-bible) mostly hold; HUD/menus are already 2D Control nodes.

## What is rebuilt

- World: VoxelLodTerrain sphere -> flat 2D tile map per world (TileMapLayer chunks), generated from a seed.
- Player: first-person 3D -> top-down character, WASD, mouse aim, tools on LMB/RMB (same hand rule).
- Building: 3D ghost on terrain -> grid placement with rotation, Mindustry-style.
- Logistics: 3D pipe routes -> tile conveyors/pipes, mergers, splitters on the grid.
- Ships: 3D block builder -> 2D top-down ship, local flight over the map; "climb" = altitude value with a
  zoom-out/shadow; above a threshold, switch to the space scene.
- Art: Blender kit, terrain shader, atmosphere -> sprites, tiles, pixelfx effects, 2D lighting.
- Everything in scripts/world tied to voxels, spheres, radial gravity: retired, not ported.

## Defaults (Michael to confirm or change)

1. **Where:** same repo, new branch `pivot/2d`; 3D code moves to `legacy/` and is deleted once each part is
   replaced. Godot 4.7 stays.
2. **Grid:** 1 tile = 1 m = 32 px sprites, buildings are N x N tiles (Mindustry-like), camera zooms 1x-4x.
3. **View:** top-down with a slight 3/4 tilt (front faces of walls and buildings visible), drop shadows.
4. **Height:** discrete elevation levels (about 5), cliffs between levels as their own tiles, ramps to move between
   them. Digging lowers a tile's level and pays ore/stone; walls of rock are tiles you mine out.
5. **Logistics:** conveyors carry items (Mindustry), pipes carry fluids. Replaces the current "pipe carries items".
6. **Space:** one small 2D space scene per star system: your ship, planets as big sprites, fly to one to land.
7. **First milestone (P1, the feel loop again):** one flat world, character walks, mines ore tiles, places a drill,
   conveyor and smelter, saves and loads. Then P2 power + research + waves, P3 ships + space, P4 more worlds.

## Art pipeline (to set up in P1)

- Style lock first: one test scene (ground, cliff, ore, drill, conveyor, smelter, character) drawn by Qwen in a few
  variants, Michael picks one, its palette and pixel scale become the rules in art-direction.md.
- Sprites: Qwen RGBA at 1024 px -> downscale to target pixel size -> palette quantise -> hand fix list.
- Tiles: seamless tile sets per ground type with edge/transition variants (autotile).
- Effects: pixelfx sheets, recoloured to the palette.

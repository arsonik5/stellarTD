# Terrain lab: materials and planet shapes (2026-11-07)

An isolated sandbox for the ground, so materials and generation are judged before anything goes into the game.
Nothing here changes the game except two shader changes (top-two weight fix, optional anti-tiling), listed at the end.

Run it:

    godot --headless --path . --script res://scripts/dev/terrain_lab/lab_bake.gd          # CC0 sets -> lab textures
    godot --path . res://scenes/dev/terrain_lab.tscn -- look=lo antitile=1 scale=4 tag=x   # 4 x 4 material grid
    godot --path . res://scenes/dev/terrain_lab.tscn -- look=lo antitile=1 scale=4 biome=ice tag=x   # shape prototype

Shots land in `art_src/terrain_lab/shots/`. Raw textures: `art_src/terrain_lab/cc0/` (20 CC0 sets from ambientCG,
fetch with `fetch.py`, not committed). Per-pixel lighting needs `override.cfg` with
`shading/overrides/force_vertex_shading=false` (the game itself still forces vertex shading).

## What was measured

### 1. A shader bug: the wrong two materials were drawn
The terrain shader reads only two of the four material slots per vertex and assumed the mesher puts the strongest
two first. It doesn't. In the lab every tile whose material sat in slot 0 rendered as slot 1's material. Fixed in
`voxel_terrain_material.gdshader`: it now picks the two strongest weights. This was live in the game too: any
material that did not happen to land in the first two slots (bedrock, cliff rock, ore) could be invisible or
replaced. Worth re-checking ore visibility in game after this.

### 2. Lighting: per-vertex lighting is what makes the ground look cheap
The game forces per-vertex lighting (PS2 decision, 2026-11-04). Under it a normal map and roughness do almost nothing,
so a ground texture shows only its flat colour. Compared on the same 16 tiles:

| look | lighting | result |
|---|---|---|
| `pbr` 512 px | per-vertex | flat, plastic, relief gone |
| `ps2` 512 px, light painted into the albedo | per-vertex | relief readable, but static, no sheen, tiles obvious |
| `lo` 256 px PBR (normal + roughness kept) | **per-pixel** | best by far: relief, roughness, ice sheen, still low-res texels |

Michael's call (2026-11-07): low-res textures + modern lighting. That needs the vertex-shading override off (at
least for the terrain). It is a project-wide switch, so it also changes how the models are lit; the models were
textured with light painted in for vertex lighting, so they would look double-lit and need a check.
Option if only the ground should change: keep the override off and add `render_mode vertex_lighting` to the model
materials that should stay PS2. (Godot can do vertex lighting per material; the global switch is what blocks per-pixel.)

### 3. Tiling: the repeat is the other "cheap" tell
At a 2.5 m tile the repeat reads as a grid from 20 m up. Two fixes, both measured:
- **Bigger tile (4-6 m)**: removes most of it on flat ground, makes close-up texels bigger (fits low-res anyway).
- **Anti-tiling (`antitile=1`)**: each material sampled a second time at another scale and rotation, mixed by a slow
  world-space mask. The grid disappears in the overview shot. Cost: twice the texture fetches. Frame rate in the lab
  stayed in the hundreds either way on the RTX 4050 (measurements were noisy, warm-up dominated; re-measure in game).

Recommended: 256 px maps, 4 m tile, `antitile=1`.

### 4. Blending between materials
Hard edges (one material per voxel) look clean but cut-out. A 4 m cross-fade with the current height-aware blend
looks smudged and blocky at the edges (the 4-bit weights and the mesher's per-vertex indices step). What reads best
in reference games is a **narrow, noisy edge**: transition over ~1 m, broken up by the height map. Not built yet;
it is a shader change (sharper `height_blend`, noise on the transition) plus generator rules that keep fewer than
three materials per spot (the four-slot limit, see terrain-generator.md "weight-slot problem").

### 5. The 16-material limit
Material ids are 4 bits, so **16 materials per planet**, not 16 in the game. The palette is per planet already
(`SurfacePalette`), so the library can be large (rocks, sands, ices, ores...) and each planet picks its 16. A planet
should use far fewer at once anyway: one ground + its rock + cliff + a few ores reads as a real place.

### 6. Materials themselves
Good as they are (CC0, ambientCG): Ground091 regolith, Ground097/080 sand, Ground102 dry crust, Gravel040 scree,
Rocks022 pebbles, Rock030/058/062 grey rock, Rock035 basalt, Rock061 sandstone, Snow010A/015 snow.
Wrong for this game: Rock051 (green moss - no plants on barren planets), Ice002 (a frozen lake seen from above, reads
as green crazing on walls; glacier ice needs a blue, layered, slightly clear texture). Ores are not in the set: an ore
should be its host rock with coloured veins/specks (same family colours as OrePalette), which is a good job for an
image model once one is running.

## Shape prototypes (planet types)

Built from processes, not more noise bands (`lab_terrain_gen.gd`). Materials follow simple geology: loose top layer
(dust, sand, snow), rock showing past ~35 degrees, and a cut exposing the layer at that depth.

| type | what's in it | verdict |
|---|---|---|
| moon | regolith, craters (bowl + raised rim, 6 sizes) | reads right; needs many more small craters |
| desert | wind dunes (gentle windward, steep lee, meandering), a mesa with two benches of hard rock | best of the five |
| volcanic | cones with vents, fissures, ash flats over basalt | reads right; fissures too uniform |
| ice | crevasses (slots along stretched noise), penitente field (ice spikes) | crevasses too dense (maze), spikes too small |
| mountain | ridged peaks, scree, cliffs, a noise cave | peaks ok; the noise cave makes shredded geometry |

Lessons:
- Carving must be a real signed distance combined with `max()`. The first version used a sentinel and produced
  shards everywhere.
- Caves from a 3D noise threshold are shredded at 1 m voxels. Caves need to be **designed tunnels** (a path of
  spheres/capsules from an entrance, SE2-style placed storage), not a noise level set.
- Landforms that read best are the ones with one clear process (wind -> dunes, impacts -> craters, hard layers ->
  mesa benches). Matches the 2026-09-11 lesson: "terrain should read as landforms, not noise".

## Planet design: how 20-30 generated planets stay logical

Proposed, not built. A planet is described by physical inputs, and everything else is derived from them, so a cold
planet gets ice and crevasses because it is cold, not because a dice roll said "ice biome":

    inputs:  star distance + star type -> temperature;  mass/radius -> gravity;  atmosphere (none/thin/thick);
             water/volatiles;  volcanism;  age
    derived: processes on/off and their strength:
               impacts      strong when no atmosphere and old        -> craters
               wind         needs atmosphere                         -> dunes, yardangs, smoothing
               water/ice    temperature + volatiles                  -> glaciers, crevasses, penitentes, canyons
               volcanism    young/active                             -> cones, lava plains, fissures
               erosion      atmosphere + water                       -> valleys, mesas from rock layers
             material palette (<=16): ground, rock, cliff, special ground, ores weighted by planet type
             relief budget limited by gravity (low gravity -> taller peaks)

Each process is one module (like the prototypes above) with a strength from 0 to 1. The generator sums or carves them
in a fixed order. This is how No Man's Sky stays varied with a finite feature set, and how Space Engineers 2 places
overhangs and boulders as separate pieces instead of more noise.

## Decisions for Michael
1. Lighting: drop the vertex-shading override for the terrain (and decide for models).
2. Textures: 256 px PBR, 4 m tile, anti-tiling on.
3. Next lab step: narrow noisy blending, ore materials, a glacier ice texture, designed caves, and the planet-input
   model above on 2-3 planet types, before anything goes into the game.
4. Image model: Qwen-Image 2.1 on furryass is blocked: furryass C: has 5.4 GB free, it needs ~11 GB plus headroom,
   and its licence is research-only (outputs in a commercial game need a paid licence from Qwen).

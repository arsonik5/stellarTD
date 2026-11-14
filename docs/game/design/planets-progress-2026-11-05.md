# Planets world pass - progress 2026-11-05

Branch `planets/world-pass` (from `design/whole-game-pass` @ ad29272). Work order: design/05-planets.md W1-W5.
Technical detail and every measurement: architecture/terrain-generator.md "World pass - 2026-11-05".

## What changed for the player

- **Home reads as one Barren world with places in it**: mesa highlands (terraced plateaus with cliff risers)
  over about a third of the planet, canyon systems through another third, spire fields in a few regions, and a
  point of interest roughly every 1.5 km - a transmitting Continuance probe, a crashed cargo pod, or a glowing
  crystal outcrop.
- **The moon is now a different place**: a Frozen world - frozen crust only, heavily cratered, crossed by narrow
  sheer crevasses, cold-tinted ground and shadows, sparse pale boulders, probes and crash sites.
- **Boulders gather where rock breaks** (foot of slopes, broken edges, in clusters) instead of a random sprinkle.
- **The rock detail now sits where it was designed to**: a long-standing sampling bug made the terrain's own
  slope/dust masks wrong at real ground height; fixed (see below).

## Built

| Step | What | Proof |
|---|---|---|
| W1 | `TerrainRecipe` - every band/gate as data; `legacy()` = old generator | surface hash identical before/after on both bodies |
| W2 | slope + altitude erosion on the outcrop bands; flat-detail slope damping | landform_ab: flats calmer, steep unchanged |
| fix | erosion masks sampled on the radius-shell (`mask_on_shell`) | mask fix alone moves 183/400 home directions |
| W3 | terraces / mesas, canyons, spires | recipe_probe: terraces 359/400 move (+-19 m), canyons to -48 m, spires to +58 m |
| W4 | `PlanetArchetype` (recipe, biomes, palette, scatter, POIs, hazards); Barren home, Frozen moon; ground tint + ambient from the palette | census: home stone 100%, moon frozen 100%; moon 2 m slope p99 71 deg (crevasse walls) |
| W5 | `ScatterSet` boulder rules; POI sites (guaranteed spacing) + `PoiField` streaming + 3 blockout POIs | planet_test: spacing, determinism, stream in/out, on-ground, radial-up |
| item 6 | scanner range (fixed earlier) validated | 27-32 deposits at each of 5 points |

`scenes/dev/planet_test.tscn`: **49 checks, 0 fails**. Generation cost per 16^3 surface block: home 6.7 -> 11.6 ms,
moon 6.4 -> 13.0 ms on the CPU container (budget 30 ms); the landform layers and the shell lookups are the cost.
Time to ready planets from the erosion cache: unchanged (cache hit; the bake is not touched by recipe defaults).

## Decisions made on Michael's behalf

1. **Home keeps its single regolith biome** and gets identity from landforms + POIs, not from more biomes
   (NMS: coherence within a planet).
2. **Moon = Frozen archetype** (the design's archetype list): frozen biome only, no crystal POIs.
3. **W2 strength is modest** (slope 0.7, altitude 0.4) - measured on a coarse map; raise only after judging on
   the full map.
4. **POI spacing 1.5 km** on home (something on the horizon from most spots), 0.9 km on the small moon.
5. **The mask sampling fix changes the existing terrain** (it is a bug fix, not a style change). The legacy recipe
   keeps the old behaviour for the hash test only.
6. **POI looting state is not saved here** - `PoiField.consumed` exists for gameplay to own.

## SE2 look pass (new direction 03:30 UTC: "EXACTLY like SE2 / No Man's Sky", PS2 assets + modern rendering)

Rig: `scenes/dev/planet_look.tscn -- --body=home|moon --tag=rN` - eye level noon / low sun (8 deg) / night, 50 m,
500 m, 5 km, orbit, a fly-down LOD count, a freshly dug hole, and the generator-found cliff, plain, canyon, mesa
edge and crater on each body. Renderer for every number below: Vulkan Forward+ on **lavapipe (CPU, llvmpipe)**,
4 cores shared with another agent's test runs - frame times are relative, not GPU numbers.

Changes going into round 1 (on top of W1-W5):
- Rendering: per-pixel lighting, PCSS sun (0.53 deg), 4 cascades over 0-2 km, 8k shadow map, SSAO + SSIL, AgX,
  grade (contrast 1.06, saturation 0.9), glow with a faint bloom.
- Terrain shader: body-local camera-snapped triplanar coordinates (open item 3), per-pixel rock on steep faces
  (open item 4), radial-height strata on rock, two-scale triplanar macro variation (tiling).
- Palettes: SE2-neutral (home grey-brown, moon frost-grey).

ROUNDS_PLACEHOLDER

## Images to look at first (user://, i.e. ~/.local/share/godot/app_userdata/StellarTD/ on the machine that ran them)

Captured on the CPU container with a 2048-wide erosion map (coarser landforms than the real 12.3 m map) and
software rendering - judge shapes and placement, not shading quality.

IMAGES_PLACEHOLDER

## Known gaps / next

- Judge everything on the full-resolution map on a GPU machine: `godot --path . res://scenes/dev/landform_look.tscn
  -- --tag=full` and `terrain_look.tscn -- --tag=after` vs `-- --tag=before --legacy-world`.
- Sky tint from the palette (atmosphere pass) - not built.
- Spire / canyon walls take biome stone, not cliff rock (the cliff material is driven by the coarse slope mask).
- More ScatterSets (crystal clusters, ice shards) as flora-equivalents.
- Second planet: needs floating origin (W6).

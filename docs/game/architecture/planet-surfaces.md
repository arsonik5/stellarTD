# Planet surfaces: traits, materials, scatter (2026-11-09)

The plan and the research behind it: `reports/AAA voxel terrain fidelity.md` (stages 0-7). North star: a save's seed
makes a cluster of star systems; every planet procedurally generated yet render-quality; planet types are blendable
traits; never lower the bar. This file is what exists now and how it fits together.

## Data flow

```
seed + body facts (radius, air, temperature, activity)
  -> TraitMixer.mix            weighted trait mix: one dominant, <=2 secondaries, one accent      scripts/world/gen/trait_mixer.gd
  -> PaletteBuilder.build      16 MIXEL4 slots by ROLE + OKLCH harmony report                      scripts/world/gen/palette_builder.gd
  -> SurfacePalette.build      BC7 Texture2DArrays + pal_* uniforms                                scripts/world/surface_palette.gd
  -> PlanetGraphGenerator      ground rules write the same roles per voxel                          _build_trait_materials
  -> voxel_terrain_material    biplanar, 4-layer height blend, distance ladder, far colour           scripts/world/voxel_terrain_material.gdshader
  -> ScatterEngine / NearScatter  the traits' asset lines on the ground                             scripts/world/gen/scatter_engine.gd, scripts/world/near_scatter.gd
```

A body opts in with `CelestialBody.generate_traits` (from its seed) or `trait_override` ({"airless": 0.7,
"crystalline": 0.3}). Home generates (rocky + volcanic); the test moon is a crystal moon. Bodies without traits keep
their hand-authored biomes.

## Traits (data/traits, written by tools/gen_trait_library.py)

airless, rocky, icy, volcanic, crystalline, desert, sulfur, life. Each: when it occurs (temperature / air / radius
bands, required facts), excludes / affinity, spatial mode (global, regional, lowland, highland, crater_floor, polar,
fault, cold_trap), material mode (replace / overlay / modulate), a material per ground role, OKLCH hue + chroma budget
+ accent / emissive flags, asset lines, landmarks. Rule: at most one accent (saturated or glowing) trait per planet.
Check: `godot --headless --path . --script res://scripts/dev/trait_lab.gd` (100 planets, harmony failures must be 0;
`-- body=res://data/celestial_bodies/<x>.tres` for one body).

## Ground roles (palette slots)

| slot | role | rule (generator) |
|---|---|---|
| 0 | fine surface | where fines settle (deposition) |
| 8 | worked ground | open ground between |
| 9, 14 | secondary traits | regions by the trait's spatial mode, coverage ~ its weight |
| 10 | scree | talus aprons (talus mask) |
| 11 | cliff rock | steep faces (baked slope mask) |
| 12 / 13 | bedrock / strata | below 2.5 m topsoil: warped bands 2.5-6.5 m thick, alternating |
| 15 | fresh cut | painted by the drill on bore walls at 45% (TerrainDrill._paint_fresh_cut) |
| 1,2,4-7 / 3 | ores / construction block | unchanged |

## Materials (data/surfaces/library, CC0 scans)

27 photoscans (ambientCG + Poly Haven) with their own normal / roughness / AO / height, packed at 2048 by
`tools/pack_surface_set.py`, BC7-compressed by `scripts/dev/compress_surfaces.gd` (5.6 MiB a map). Per material:
tint, saturation (grey regolith from sandy scans), roughness scale, specular, normal strength, tile metres, height
blend scale / offset; the far colour comes from the scan's mean. The scans, packed maps, BC7 layers and rock models are
git-ignored (~1 GB, fully reproducible): **on a fresh clone run `sh tools/setup_surfaces.sh`.**

## Shader (stage 2)

All four vertex materials (skip < 2%), biplanar with true gradients and sign-corrected whiteout normals, height blend
(max-minus-transition) with wandering edges, SE1 distance ladder (x4 tile per x4 distance from 32 m, cross-faded)
ending in each material's far colour, per-material saturation, specular occlusion + horizon fade. Radial-safe and
precision-safe everywhere (block-relative uv).

## Scatter (stage 4a)

`data/asset_lines` (tools/gen_asset_lines.py): boulder_fields (talus), ejecta_blocks (wear), talus_aprons, and the
near-field lines pebbles, gravel_patches, regolith_clods. Instancer lines: per variant x ground role, filtered to the
dominant material, shaded to that ground (scatter_rock.gdshader: colour match, burial blend into the terrain array,
dust), max 3 variants each (draw calls). Near-field lines: 12 m chunks within 30 m at 1-3 stones / m2, placed on the
physics surface, ground role and colour from the generator, rebuilt around drill bites. Rock models: 18 CC0 Poly
Haven scans split + decimated in Blender (`tools/decimate_rocks.py`: boulder 6k, rock 2.5k, stone 1.2k tris + LOD1).

## Checks

- `res://scenes/dev/ground_shots.tscn -- tag=X [only=eye2] [noscatter=1] [sun=25]`: the same views every run (eye 1.7 m,
  10 m, 50 m, 500 m, orbit, top 40 m, close), GPU ms, draw calls, primitives, scatter census. Baseline s0 5.4-7.0 ms;
  now ~7.5 ms with all of the above (measure with and without scatter in the same session: other GPU load swings it).
- `res://scenes/dev/dig_reel.tscn`: the drill in the real world.

## Not there yet (against the north star)

Terrain features (crater rims as SDF, outcrops, strata ledges, lava tubes), generator kits per trait (crystals, ice,
basalt columns, desert forms), life, landmarks, density AO / parallax / micro-shadows, distance normalmaps, then the
seeded universe (cluster -> systems -> 20 mixed seeds). Godot 4 limits to engineer around: no tessellation, no dynamic
GI on edited voxels (dug caves read flatter than SE2).

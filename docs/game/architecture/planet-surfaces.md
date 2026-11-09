# Planet surfaces: traits, materials, scatter (2026-11-09)

The plan and the research behind it: `reports/AAA voxel terrain fidelity.md` (stages 0-7). North star: a save's seed
makes a cluster of star systems; every planet procedurally generated yet render-quality; planet types are blendable
traits; never lower the bar. This file is what exists now and how it fits together.

## Data flow

```
seed + body facts (radius, air, temperature, activity)
  -> TraitMixer.mix            weighted trait mix: one dominant, <=2 secondaries, one accent      scripts/world/gen/trait_mixer.gd
  -> CraterField.build         seeded crater list (power-law sizes, morphometry, age)             scripts/world/gen/crater_field.gd
  -> ErosionBaker              base -> old craters -> erosion -> young craters -> masks,         scripts/world/erosion_baker.gd
                               reprojected into the voxel node's projection (SphereUV)
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

`data/asset_lines` (tools/gen_asset_lines.py): boulder_fields (talus), ejecta_blocks (crater "fresh"), talus_aprons, and the
near-field lines pebbles, gravel_patches, regolith_clods. Instancer lines: per variant x ground role, filtered to the
dominant material, shaded to that ground (scatter_rock.gdshader: colour match, burial blend into the terrain array,
dust), max 3 variants each (draw calls). Near-field lines: 12 m chunks within 30 m at 1-3 stones / m2, placed on the
physics surface, ground role and colour from the generator, rebuilt around drill bites. Rock models: 18 CC0 Poly
Haven scans split + decimated in Blender (`tools/decimate_rocks.py`: boulder 6k, rock 2.5k, stone 1.2k tris + LOD1).

## Map projection (read this before touching any planet-wide map)

Every planet-wide map (height, flow, wear, deposition, talus, slope, fresh, crater_floor) is stored in the projection
godot_voxel's SdfSphereHeightmap node reads, because that node reads them per voxel: `u = 0.5 - atan2(z, x) / TAU`,
`v = 0.5 - (y^3 + y) / 4` (a cubic stand-in for asin), bilinear at pixel corners. `SphereUV` (scripts/world/gen/
sphere_uv.gd) is the one copy in GDScript; reproject.glsl and the terrain shader carry the same formula. The bake
itself runs on a plain equirectangular grid (the erosion's metric needs it) and ErosionBaker reprojects at the end.
Until 2026-11-09 the maps went in unconverted: the planet was mirrored east-west and stretched ~27% north-south.

Masks are read in the graph with `PlanetGraphGenerator.sample_mask_on_sphere`: the voxel direction put on a 1000 m
sphere. Fed the real voxel position, the node's early-out (more than ~2 m off its radius) returned plain distance
and every mask read 0 almost everywhere; that was why slope, dust and talus rules did nothing before 2026-11-09.

## Landforms (stage 4b)

Per-trait numbers in PlanetTrait "Landforms", mixed by weight in `TraitMixer.landform(body)`: crater density, ray
strength (air erases rays: x 1 / (1 + 10 air)), ledge strength, lava tubes. Crack size is a MATERIAL property.
- **Craters**: CraterField, baked by shaders/erosion/craters.glsl (tile-binned). Simple (parabolic, depth 0.2 D, rim
  0.04 D, ejecta ~ r^-3), complex above D_t (flat floor, terraced walls) and with a central peak above 1.6 D_t;
  irregular outlines. Age > 0.45 goes in before erosion (worn, filled); younger after it, then 6 talus passes.
  Masks: `fresh` (young walls, ejecta blanket, rays; 4096 wide) drives the terrain shader's brighter immature
  regolith and the ejecta_blocks line; `crater_floor` places crater-floor traits (the crystal moon's crystal fields).
  The graph's cellular craters stay for sizes under the map's resolution.
- **Strata**: one bed function, `PlanetGraphGenerator.strata_params` / `_strata`: level beds on the true radius,
  cycle 8-18 m with +-35% thickness wobble, hard bed = lower 34% of a cycle. The generator uses it for the ledges
  (sawtooth radial offset on faces with slope01 0.6-0.85, capped so the field never folds) and for the beds
  underground (STRATA_A / bedrock). Exposed cliff faces are ONE voxel material (cliff rock); the terrain shader draws
  the beds on them per pixel from the same function (`strata_*` uniforms, set by Planet): hard beds in the strata
  scan, each bed its own thickness and tone, plus laminae and partings. As voxel weights the beds aliased into
  blotches and dashes at LOD 1-2; per pixel they stay continuous at any distance and still meet the ledges and what
  a dig exposes.
- **Lava tubes** (volcanic, in its region): warped Voronoi edge network (F2 - F1) at 13 m depth, ~12 m wide, 8 m high,
  in segments; roof collapses (skylights, trenches) on ~15% of the length. Cave and tube walls take the material of
  their depth (materials measure depth from the ground before any carving). Measured: scripts/dev/tube_probe.gd.
- **Cracks**: `SurfaceStyle.crack_cell_m` (pal_grade.w), only on ground that really cracks and whose scan doesn't
  already show it: frozen ground, permafrost polygons of 9 m. Exact-edge Voronoi in the shader: V-shaped trough with
  wandering width, lighter rim, normals tilted into the trough so the light shapes it; near only, anti-aliased.
  Checked in `res://scenes/dev/surface_lab.tscn -- mix=icy:0.8,rocky:0.2 slot=0` (the real shader on a flat patch).

## Rock burial (scatter)

Each rock is sunk by `burial` x its OWN height, baked into the instancer item's mesh (ScatterEngine._sunk) so it
scales per instance; near-field stones the same per stone. The rock shader's ground band is a share of the rock's
height from its bottom (mesh_height / mesh_bottom). Before 2026-11-09 the sink was burial x the line's mean size for
every instance, which put small rocks wholly underground.

## Checks

- `res://scenes/dev/ground_shots.tscn -- tag=X [only=eye2] [noscatter=1] [sun=25]`: the same views every run (eye 1.7 m,
  10 m, 50 m, 500 m, orbit, top 40 m, close), GPU ms, draw calls, primitives, scatter census. Baseline s0 5.4-7.0 ms;
  now ~7.5 ms with all of the above (measure with and without scatter in the same session: other GPU load swings it).
- `res://scenes/dev/dig_reel.tscn`: the drill in the real world.
- `ground_shots ... only=cliff`: the steepest landform within 1.2 km, lit from the camera side, plus the generator's
  slots there and the slope mask read both ways (CPU and node): they must agree. `only=flat`: the flattest ground
  within 300 m. `planet=TestMoon [at=1.6]`: shoot another body, next to its biggest young crater (at = crater radii
  from its centre). `rockshadow=0`, `lods=0`, `plainrocks=1`: scatter diagnostics.
- Headless (from the erosion cache): `crater_preview.gd -- tag=x [crop=x,y,w,h]` (hillshade + crater masks),
  `crater_round_check.gd`, `tube_probe.gd`, `gen_cost_probe.gd`, `mat_lightness.gd` (OKLCH of every material).

## Not there yet (against the north star)

Generator kits per trait (crystals, ice,
basalt columns, desert forms), life, landmarks, density AO / parallax / micro-shadows, distance normalmaps, then the
seeded universe (cluster -> systems -> 20 mixed seeds). Open from stage 4b: after the player is moved to another body
(planet= shots), groups of scattered rocks are culled from the camera but still cast shadows (orphan shadow blobs);
not seen on home from its own spawn. Pebbles near spawn blend into the gravel texture (2000 placed, few read). Godot 4 limits to engineer around: no tessellation, no dynamic
GI on edited voxels (dug caves read flatter than SE2).

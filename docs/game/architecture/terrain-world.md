# Terrain system

## Systems Reference

### Terrain System â€” Scope 1 Â· Alpha (minimal) â†’ Beta (full)

**Current State:** Spherical voxel planet with hand-written `VoxelGeneratorScript` generator. Ores placed in depth bands with noise thresholds. Performance: ~18 seconds to first playable collision on boot (was >60s before per-voxel cost reductions).

**Known Issues**
1. ~~**Ore in shells not veins**~~ â€” **FIXED 2026-09-07**, see below.
2. **Spiky/wedge artifacts at block seams** â€” hand-rolled culling writes uniform per-block SDF when a block is entirely air/solid, breaking Transvoxel's seam interpolation. Graph's automatic range analysis fixes this. **Still open.**
3. ~~**Flat-color output**~~ â€” **FIXED 2026-09-07**, see below.

**Reworked 2026-09-07 â€” material blending + ore model.** Done in the existing
`VoxelGeneratorScript` rather than waiting on the graph port, because both are
*design* changes (surface rules, ore model) that carry over to the graph
verbatim, and the graph port wants editor authoring first.

*Material blending.* `TEXTURES_SINGLE_S4` carries one material index per
Transvoxel cell, so every material boundary is a hard cell-shaped square by
construction â€” that is the squares on the surface and the blocky steps in a dug
wall. Now `TEXTURES_MIXEL4_S4`: four 4-bit indices packed in the 16-bit indices
channel, four 4-bit weights in the weights channel, blended per vertex.

> **Naming:** the constant is `TEXTURES_MIXEL4_S4` (not `MIXED4`). `TEXTURES_BLEND_4_OVER_16` is an alias for the same value (1).
>
> **Format:** indices must be **16-bit** for this mode (8-bit is what `SINGLE_S4` wanted); weights only accept 16-bit and error otherwise, so leave weights at default.
>
> **Mesher contract:** indices arrive in `CUSTOM1.x`, weights in `CUSTOM1.y` (`/255.0`), both via `floatBitsToUint` + byte unpack. Indices are per-cell identities so they stay `flat`; the weights interpolate, and that is what softens the seam.
>
> **The four indices in a voxel must be UNIQUE**, including zero-weight slots â€” hence the filler indices 13-15, which are never real materials.

Slots are: biome ground / cliff rock (slope rule) / bedrock (depth rule) / ore.
`VoxelMaterials` gained `CLIFF_ROCK = 11`, `BEDROCK = 12`, `MAX_INDEX = 15`.
4 bits per slot means **no material index may exceed 15** â€” a 17th material
needs a different texturing mode, not another constant.

*Ore model.* Replaced one-noise-per-ore-plus-depth-gate with two fields: a
low-frequency **cellular** deposit field (`RETURN_CELL_VALUE`) where each
Voronoi cell is one deposit body holding one ore type, and a vein field where
`|noise| < VEIN_WIDTH` marks the vein. Depth is a soft `smoothstep` weight, not
a hard gate â€” the hard gate was the banding, since a depth test is a function
of radius and therefore draws spherical shells. Also two noise samples per
solid voxel instead of six.

> **Why cellular and not simplex:** simplex drifts continuously (no region edges) *and* is bell-distributed, so feeding it through a uniform rarity CDF piles every deposit into the middle entries. Measured with simplex: iron, the ore meant to be commonest, came out at 2% of deposits while coal took 47% â€” exactly inverted. Cellular cell values are uniform across cells, which is what makes the rarity table mean anything.

*Digging.* `player.gd`'s `_dig()` read `CHANNEL_INDICES` raw, which under the
new mode returns the packed 4-index word and silently matches no ore at all.
Now unpacks and takes the highest-weighted slot (`_dominant_material_at`).
`_build()`'s `MODE_TEXTURE_PAINT` path needed no change and works properly for
the first time â€” it was always the right API for this mode.

*Measured, before â†’ after (400-point and 1170-voxel samples):*

| | before | after |
|---|---|---|
| ore share of subsurface rock | 34.9% | **2.6%** |
| ore per depth | spikes at fixed depths | **smooth, no shells** |
| directions containing ore | 56 / 60 | **14 / 60** (clustered) |
| commonest ore | coal (iron 2%) | **iron**, as designed |
| surface reading as cliff | 73% at first-tried mult 3.0 | **~15%** at calibrated 7.0 |

Knobs if it needs retuning: `VEIN_WIDTH` (vein thickness â†’ ore abundance),
`ORE_REGION_SHARE` (how many deposit regions are barren), `CLIFF_SLOPE_MULT`.

**Follow-up 2026-09-07 â€” residual banding was in the SHADER, not the terrain.**

First measured whether the generated surface was actually stepped: walked the
exact SDF isosurface crossing along a strip at LOD 0-3 and took first
differences. 32 distinct step values out of 39 samples at every LOD, varying
smoothly â€” **the geometry is smooth and the generator was not the cause.**
Worth doing before touching anything; the obvious suspects (SDF quantization,
LOD coarsening) were both wrong.

The real cause was the terrain shader's noise hash:
`fract(p.x*p.y*p.z*(p.x+p.y+p.z))` over **world-space** coordinates. On a 200 m
planet with the detail octave's 3.5x scale, that product reaches ~2.5e5, where
float32's 24-bit mantissa has a ULP near 0.03 â€” so `fract` could only return
~30 distinct values, in a structured pattern. A moire generator, not noise,
which is why it showed worst on materials.

> **General rule: never build a hash out of float products of world-space
> coordinates.** It works at the origin and degrades with distance, so it
> looks fine in a test scene and bands on a real planet. Hash the integer
> lattice cell with bit-mixing instead â€” no magnitude-dependent precision loss.

Also fixed in the same pass:
- ~~The detail octave had 0.29 m cells against 0.4 m voxels, beating against
  the mesh's vertex spacing.~~ **This reasoning was wrong** â€” the noise is
  evaluated per *fragment* from world position, so it cannot alias against
  vertex spacing at all. The banding was entirely the hash. Backing the
  octaves off to 0.9 m on this false premise traded moirÃ© for visible
  chunkiness, and was reverted in the next pass (see below).
- **`render_mode cull_disabled` removed.** It drew the inside of the surface
  too, and Transvoxel's LOD transition cells produce thin near-coincident
  slivers whose back faces z-fight their own front faces â€” the dark cell
  outlines that flickered with camera movement.

**Shader compilation IS verifiable headless**, contrary to the note this
replaces: Godot's dummy renderer still parses shaders and reports
`Shader compilation failed`. Confirmed by deliberately breaking the shader and
seeing the error, then confirming the real one compiles clean. What headless
still cannot check is appearance.

**Deliberately not changed:** `lod_distance` (64 local units â‰ˆ 26 m, so the
first LOD transition is close). Raising it is the obvious next lever for
transition popping, but LOD was measured *not* to be causing the stepping, and
the generator is already the load-time bottleneck â€” doubling it roughly
quadruples LOD-0 area. Change it only if popping is still visible after this.

**Follow-up 2026-09-07 (b) â€” surface detail rewritten as proper fBm.** With the
hash fixed, what was left read as low-res/pixelated: two octaves of value noise
at 4 m and 0.9 m cells, on 0.4 m voxels. Two compounding causes:

1. **Only two octaves.** A material needs detail at every scale; two octaves an
   octave apart is a blob field, not a surface. Now six octaves from ~6.7 m
   down to ~0.21 m.
2. **Every octave axis-aligned.** Value noise sits on a cubic lattice, so
   stacking octaves keeps them all aligned to the same world axes, and a
   curved surface slicing that shows square patches. Each octave now gets a
   rotation (`OCTAVE_ROT`) to decorrelate them and break the grid.

Finest octaves are now deliberately *finer* than a voxel, which is correct â€”
per-fragment noise cannot alias against vertex spacing (see the corrected note
above). What it *can* alias against is screen pixels at distance, since
procedural noise has no mipmaps, so octaves are shed with view distance
(`active_octaves`, roughly one per doubling, from `length(VERTEX)` which is
view-space in `fragment()`), plus a close-range-only grain layer that fades out
by 12 m.

> **Rule of thumb this cost two passes to land on:** procedural surface detail
> wants *many* octaves spanning a wide scale range with rotation between them,
> and a distance-based octave budget. Tuning the frequency of a two-octave
> field just moves the artifact around â€” coarse reads as pixelated, fine reads
> as fizz.

*Not addressed, inherent to the mode:* material indices are `flat` (per-cell
identities), so where two neighbouring cells carry different index sets the
blend steps at the triangle edge. In practice the set is
`[biome stone, cliff, bedrock, ore-or-filler]` and only slots 0 and 3 vary, so
this shows only at biome borders. The deep uniform-fill blocks use a different
set (`[12,13,14,15]`) but resolve to the same bedrock colour, so that boundary
is invisible.

**Core Voxel Data & Generation**
- Modular Terrain API â€” strict interface (`TerrainManager`) handling all external queries so dependent systems survive if the voxel engine is disabled.
- **Current implementation:** Spherical voxel planet generated via custom `VoxelGeneratorScript` sampling noise on unit-sphere directions (seamless, no pole pinch). Ores placed via noise thresholds with `depth_below_surface` band checks.
- **Hybrid "Crust" Generation** â€” costly 3D volumetric noise restricted to narrow band; outer/inner shells filled uniformly. **Future**: migrate to `VoxelGeneratorGraph` for automatic range optimization + better visual quality.
- Delta Save/Load Database â€” `VoxelStreamSQLite` designed in but not yet wired (Alpha scope deferred). Saves only edited blocks; terrain regenerates base from generator each load.

> **Implementation notes:** `VoxelStreamSQLite` is ready to use â€” set `stream = VoxelStreamSQLite.new()` on `VoxelTerrain`, set `database_path`, call `save_modified_blocks()` periodically. The stream stores deltas only; base terrain regenerates from generator. There's also `set_key_cache_enabled()` for sparse-edit optimization. 
> 
> Current generator is `VoxelGeneratorScript` (CPU, per-block). `VoxelGeneratorGraph` (node-based, visual editing, ~20-50x speedup from removing interpreter overhead, auto range-analysis for block culling) is the recommended next step. Graph supports domain warping, ridged noise, splines for terrain shape, `NODE_SPOTS_3D` for scattered ore deposits, `NODE_SDF_SPHERE_HEIGHTMAP` for baked base layers (rung C). Hand-author one graph in the editor first (tuning work is the bulk of quality), then port to code-generated graphs driven by `CelestialBody` fields.

**Biome System** *(Beta)*

Source: detailed design in `biome-system-design.md`. **Current state: designed, not built.**

**Data model:**
- `OreType` (`Resource`): `id`, `material_index`, `depth_min/max`, `base_threshold`, `noise_frequency`. Replaces hardcoded ore constants. Allows per-ore depth tiers.
- `Biome` (`Resource`): `temperature_min/max`, `roughness_min/max`, `stone_material_index`, `ore_bias` (multiplier on ore thresholds, never a hard gate). Starter set: Regolith Plains (baseline), Frozen Wastes, Sulfur Flats, Crystal Fields.
- `CelestialBody` gets `ore_types: Array[OreType]`, `biomes: Array[Biome]`, `climate_bias: Vector2` (shifts temperature/roughness center for "mostly ice" vs. "mostly volcanic" planets).

**Region assignment** â€” 2 axes (climate space):
- **Temperature** = latitude term (`abs(dir.y)` on unit sphere) + altitude lapse (higher = colder) + `climate_bias.x` + low-freq wobble
- **Roughness** = independent low-freq noise (replaces humidity) blended with local slope steepness + `climate_bias.y`
- Biome pick: nearest in climate space; fallback to nearest-by-distance if no exact match

**Ore generation** â€” rarest-first priority:
1. Filter ores by `depth in [depth_min, depth_max]`
2. Sort by `base_threshold` (descending) so crystal (rare) wins over iron (common)
3. For each: `effective_threshold = base_threshold / biome.ore_bias.get(id, 1.0)`; sample noise; first one clearing threshold wins
4. None clear â†’ `biome.stone_material_index`

**Rendering & Shaders** *(Beta polish; Alpha gets basic triplanar only)*

Current state: `voxel_debug_material.gdshader` (two-octave hash-noise albedo/roughness, planet-latitude tint). No real textures or blending yet.

**Beta target:**
- Triplanar Splatmap Shader â€” project textures along X/Y/Z axes to eliminate UV stretching
- Texture Array Mapping â€” pack biome-specific textures into `Sampler2DArray`, use material index as Z
- `TEXTURES_MIXED4_S4` for 4-way blended material indices per vertex (soft seams at biome boundaries)
- Dynamic Normal Overrides â€” rock texture on surfaces >45Â° slope regardless of biome
- Distance-Based Interpolation â€” blend high-frequency detail into low-frequency macro-color for orbital visibility

**Surface rules** (from biome):
- **Slope** â€” rock on steep, soil/sand on flat (highest impact for realism)
- **Depth below surface** â€” topsoil / subsoil / bedrock banding
- **Elevation + climate** â€” snowline, aridity

**Physics, Scale & Scatter**
- Floating Origin / Large-World Coordinate System â€” *see dedicated section below (1.0 Release scope)*
- Asynchronous LOD & Collision *(Beta)* â€” mesh generation on background threads (native to module). Deferred collision queue (custom scheduling) to stagger mesh swaps and avoid frame spikes.
- Data-Driven Foliage Scatter *(Beta)* â€” spawn/despawn via `VoxelInstancer` + `VoxelInstanceLibrary` (built into module). Mark items `persistent` for SQLite persistence.

**Terrain Status Notes:**
- Current `mesh_block_size = 16`, `lod_count = 5`, `lod_distance = 64` sufficient for 200m radius. Scaling to 2km needs `lod_count ~10`; 60km needs ~15-16.
- Hand-rolled shell optimization in current generator (skip noise outside thin shell) works well at current scale but won't generalize past a few km.
- Generator speed is GDScript-limited; `VoxelGeneratorGraph` is the next optimization lever before considering language switch or engine rebuild.

---


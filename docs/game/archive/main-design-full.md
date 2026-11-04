# Stellar TD — Game Design Doc

**Core pillars:** Satisfactory-style factory/logistics + Mindustry-style tower defense + Space Engineers-style deformable voxel mining/terrain, in a persistent world of procedural planets/asteroids, defending against alien attack waves.

**Guiding principle:** every system is standalone and modular — able to be toggled off without breaking anything else. Research best practices before building; no shortcuts.

**Tech stack:** Godot 4.7 + Zylann's voxel module (1.7), Gaea for terrain generation, Blender for 3D assets (glTF export), Claude Code for all development work.

---

## Current Implementation Status (as of 2026-09-07)

This section tracks what's actually been built vs. what's planned, to distinguish design intent from current state.

### Shipping / Validated (Ready for playtest)
- **Slice 1 mining/building loop** — dig, place blocks, build structures on a spherical voxel planet (40m world radius)
- **Radial gravity and spherical terrain** — player moves all the way around the planet, gravity pulls toward center
- **Ore generation** — 6 ore types embedded procedurally with per-ore depth tiers
- **Refining chain** — ore → processor/smelter → ingot → placeable block
- **Conveyor system** — tick-based pipe network with merger/splitter logic, grid-cell lookup
- **Building placement** — grid-snapped via Metal Foundations, free-placement as fallback, both orient tangent to terrain
- **Sky/atmosphere/fog per-planet** — data-driven `PlanetAtmosphere` resource, swappable per body
- **Multi-body physics foundation** — `CelestialBody` (data), `Planet` (scene), `PlanetPhysics` (registry); proven with two simultaneous planets
- **Projectile physics** — real ballistic flight with gravity + atmospheric drag, swept raycasts for collision
- **Turret buildings** — two variants (gun: fast/single-target; cannon: slow/splash), targeting via group + duck-type, ammo system with per-type compatibility
- **Scout ship threat** — crystal ore drives radiation signature; scout ship spawns at Low tier, targetable by turrets; kills before escape prevent escalation
- **Ship physics** — `Ship` RigidBody3D with thruster/gyro allocation, shared controller for player + AI
- **Quest system** — 7-quest tutorial chain with tech-tree UI, data-driven objective types
- **HUD + UI state management** — compact HUD auto-hides during modals, centralized `UiState` registry

### Ahead of Schedule (Built before Alpha scope called for)
- **Ship system** — full `Ship` RigidBody3D physics with mass/inertia from grid blocks, thruster/gyro allocation (originally 1.0 Release scope, now Alpha-validated)
- **Volumetric projectiles** — real ballistics instead of hitscan (Beta scope, now in use)
- **Radiation threat foundation** — crystal ore + signature tiers + scout mechanics (not in original roadmap; added as Slice 2 foundation)
- **Multi-body planetary physics** — `CelestialBody`/`Planet`/`PlanetPhysics` (1.0 Release scope, Phase 1 now shipped)

### In Progress / Known Gaps

**Terrain generation**
- Current generator is GDScript-based and has known visual bugs: spiky surfaces at block seams, flat-color output
- Fix requires rewriting via `VoxelGeneratorGraph` (not yet started) to use `NODE_SPOTS_3D` for ore placement and proper surface rules
- Scale is currently 500 voxels radius (200m world), small enough that mesh LOD limit (5 levels) covers it. Cannot safely scale past 2km without either floating-origin or double-precision build (see Scale Ladder section below)

**Fixed 2026-09-07 — concentric ring banding on the starter planet.** Two
independent causes, both measured before and after rather than assumed:

1. *Climate was latitude-locked.* `temperature` used `1.0 - abs(dir.y)` at
   weight 1.0 against a wobble noise at weight 0.15 — measured 6x to 112x
   weaker than the term it was supposed to break up. Biome borders therefore
   fell on lines of constant latitude, i.e. concentric rings around the world
   Y axis, which is why the planet read as layered along one axis rather than
   spherical. Now a 3D climate field (noise 0.65 / latitude 0.35) so latitude
   is a trend, not geometry.
2. *Climate noise frequency was wrong for its input domain.* Both climate
   noises ran at `frequency = 0.5` but are sampled on the **unit-sphere
   direction**, whose whole domain is only 2 units across — that is about
   three features over an entire planet. Raised to 2.0 / 2.6. **This is the
   general gotcha: a frequency tuned for world-space sampling is meaningless
   when the input is a normalized direction.** The height/detail noises were
   already correct (1.8 / 9.0); only the climate pair was wrong.

Also fixed alongside: the roughness `slope` term saturated at ~0.9 everywhere
(a `* 0.5` where the height noise's own gradient is ~1.8), pinning roughness
into its top half and starving every low-roughness biome — `regolith_plains`
never appeared at all. And all six ores had `depth_min` of 0.5-1.0, so ore
occupied the *topmost* voxel and speckled the visible crust; raised to 3.0
(crystal already 8.0).

Verified by sampling 240 Fibonacci-sphere directions: ore visible on surface
0 (was non-zero), all four biomes present at 44.6/21.3/19.6/14.6%, and every
latitude band now carries 3-4 mixed materials instead of one. Still open and
*not* addressed by this: hard per-cell material edges when digging, which need
`TEXTURES_BLEND_4_OVER_16` + a weights channel, and the block-seam spikes.

**Save system**
- **Critical gap**: no save/persistence built yet. Terrain edit deltas have the SQLite infrastructure wired but not enabled. Building state, inventory, player position not saved.
- `VoxelStreamSQLite` is built into godot_voxel and ready to use; just needs wiring at scale rung B

**Biome system**
- Designed in detail (see Biome System section below) but not implemented
- Requires generator rewrite (noted above) as prerequisite

**Atmosphere visuals** — **BUILT 2026-09-07**, see the Atmosphere System section
- Raymarched single-scattering pass covers ground sky, aerial perspective, orbital limb and the fade on leaving the atmosphere in one integral
- Proxy spheres and `Environment` fog both deleted; `PhysicalSkyMaterial` was evaluated and rejected (world-Y-locked horizon, unusable on a sphere)
- Still missing: volumetric clouds, re-entry heat shimmer — both blocked on the Weather system's dynamic-pressure/Mach inputs

**Asset pipeline**
- No parametric Blender generator built yet; still using placeholder blocks
- Pipeline design exists; implementation blocked on Blender headless glTF testing

**Player rigging**
- No character model; currently capsule placeholder
- Full Rigify workflow designed but deferred to Beta

**Enemy AI / Wave system**
- `EnemyDummy` is stationary test scaffold only
- `EnemyScoutShip` has specific lore/mechanics but not a general enemy spawner
- Real wave spawning and scaling tied to threat/power not yet built

---

## Roadmap (Updated)

### Alpha 1.0 — core loop only
**Current state:** Most combat loop shipped; critical gaps are save/biomes/proper terrain generation.

Goal: prove the loop is fun before investing in any large-scope system.

1. ✅ Single-planet voxel terrain (spherical, radial gravity) — **SHIPPED** but with known visual bugs awaiting generator rewrite
2. ✅ Mining/building loop — **SHIPPED**
3. ✅ Basic factory/logistics chain (5 ores, refining, conveyor) — **SHIPPED**
4. ⚠️ Basic combat (personal guns not built; one turret variant, scout ship, projectiles) — **PARTIAL** (ships/projectiles built; wave scaling not)
5. ❌ Save/load — **NOT STARTED** (infrastructure ready, not wired)

Explicitly deferred past alpha: floating origin/interplanetary flight, full atmosphere/weather, ore injectors, foliage scatter, high-tier radiation, underground, full biome matrix, asset-generation pipeline. Build their *interfaces* now so nothing is architecturally blocked later; implement the guts post-alpha.

### Beta — fill out systems, still single-solar-system-local
- Full terrain system: VoxelGeneratorGraph rewrite, biomes via surface rules, proper shader polish
- Foliage scatter system (via `VoxelInstancer`)
- Full atmosphere system (raymarched orbital limb + re-entry effects, not just skybox)
- Weather system (scale-height density model, Mach-driven effects)
- Blender + agent building-generation pipeline (replace placeholder blocks)
- Expanded factory/logistics (more resource types, more building tiers)
- Expanded combat (personal weapons, enemy variety, wave spawning tied to crystal/power)
- Player character rigging (Rigify + Mixamo locomotion)

### 1.0 Full Release — large-scope systems
- Floating origin / large-world coordinate system, full solar-system-scale continuous flight
- Precision decision gate: floating-origin vs. double-precision build (must decide at rung B/C, see Scale Ladder below)
- Underground system
- Multiplayer networking (deterministic projectiles already built for this; terrain sync research needed)
- Anything else surfaced during beta as needed for full release

---

## Scale Ladder (Critical Gate Before Large Expansion)

**Rung A+ ATTEMPTED and REVERTED 2026-09-09.** A 2 km planet was built,
measured, and rolled back. It does not work with the current GDScript
generator, and the reason is throughput, not configuration.

**The hard number:** at 2 km, terrain collision under the player does not
arrive within **170 seconds**, even with the spawn timeout raised 10x.
Mesh-block throughput is ~4.5x lower than at 200 m (219 blocks at 20 s versus
978), because a far larger share of blocks near the viewer are full-shell and
take the expensive per-voxel path. At 200 m the player lands in 12.5 s.

**km-scale is therefore gated on the `VoxelGeneratorGraph` port**, not on
`lod_count`, `lod_distance`, relief, or voxel size. Every one of those was
tried and none of them is the constraint.

What WAS validated at 2 km before the revert, and can be restored verbatim
once the generator is fast enough:

| | value that worked |
|---|---|
| Planet / moon radius | 2000 m / 1200 m |
| Planet -> moon | 11000 m |
| Star radius / distance | 800 m @ 20000 m (4.58 deg disc) |
| Relief | 200 vox = 80 m = 4% of radius |
| `lod_count` / `lod_distance` | 11 / 256 |
| `REFERENCE_RADIUS_WORLD` | 2000 (holds surface gravity at 1.2 m/s^2) |
| Star `luminosity` / `surface_gravity` | 1.3e12 / 3.75 |

Physics and lighting all verified clean at that scale: surface gravity 1.1997
aligned 0.99999, star pull 0.500%, irradiance inverse-square, sun disc 4.58
degrees.

**Generation cost is flat per voxel in radius** (4.2-4.7 us at 500 or 5000
voxels). Scaling up does not make voxels more expensive - it increases how
many of them sit in the expensive full-shell path near the viewer.

> **METHODOLOGY FAILURE worth recording, it cost most of a session.** The
> investigation ran on a test that identified terrain colliders with
> `collider is StaticBody3D`. **godot_voxel registers collision through the
> PhysicsServer, not as StaticBody3D child nodes**, so that check is never
> true - the test reported "no collision" at *every* scale including the
> known-good 200 m config. Four wrong mechanisms were diagnosed and acted on
> before a control run at the known-good config exposed it.
>
> **Rule: before diagnosing a failure, run the instrument against a
> configuration known to succeed.** If it cannot detect success, it cannot
> diagnose failure. A second, replacement test then also produced a false
> positive by checking the player's radius against a threshold - a capsule
> held motionless by the spawn re-park loop satisfies it. Use `is_on_floor()`
> or an actual state change, never a position range.

**Scale-dependent constants found (a recurring class of bug).** Anything that
assumes the surface sits at `radius_world()` breaks once relief is a
meaningful fraction of radius:
- `SPAWN_HOVER_HEIGHT` / `SPAWN_PROBE_DEPTH` - **fixed**, spawn now locates
  the real surface by reading voxel DATA (which streams far ahead of
  colliders) via `Planet.max_relief_world()` and `_find_data_surface()`,
  rather than guessing from nominal radius. Correct at any relief.
- `VoxelViewer.view_distance = 1024` voxels = 410 m - **still open.** Fine at
  200 m where it covers the whole planet; at km-scale it caps view range
  independently of `lod_count`, so a planet would not render from orbit no
  matter how deep the LOD chain is. Must be raised whenever scale-up is
  retried.

**Precision status:** at the reverted 200 m scale the furthest occupied point
is the star at 4.4 km, comfortably inside float32. The 2 km layout put the
star at 20 km (~2 mm quantum), which was still fine - precision was never the
blocker.

---

## Systems Reference

### Terrain System — Scope 1 · Alpha (minimal) → Beta (full)

**Current State:** Spherical voxel planet with hand-written `VoxelGeneratorScript` generator. Ores placed in depth bands with noise thresholds. Performance: ~18 seconds to first playable collision on boot (was >60s before per-voxel cost reductions).

**Known Issues**
1. ~~**Ore in shells not veins**~~ — **FIXED 2026-09-07**, see below.
2. **Spiky/wedge artifacts at block seams** — hand-rolled culling writes uniform per-block SDF when a block is entirely air/solid, breaking Transvoxel's seam interpolation. Graph's automatic range analysis fixes this. **Still open.**
3. ~~**Flat-color output**~~ — **FIXED 2026-09-07**, see below.

**Reworked 2026-09-07 — material blending + ore model.** Done in the existing
`VoxelGeneratorScript` rather than waiting on the graph port, because both are
*design* changes (surface rules, ore model) that carry over to the graph
verbatim, and the graph port wants editor authoring first.

*Material blending.* `TEXTURES_SINGLE_S4` carries one material index per
Transvoxel cell, so every material boundary is a hard cell-shaped square by
construction — that is the squares on the surface and the blocky steps in a dug
wall. Now `TEXTURES_MIXEL4_S4`: four 4-bit indices packed in the 16-bit indices
channel, four 4-bit weights in the weights channel, blended per vertex.

> **Naming:** the constant is `TEXTURES_MIXEL4_S4` (not `MIXED4`). `TEXTURES_BLEND_4_OVER_16` is an alias for the same value (1).
>
> **Format:** indices must be **16-bit** for this mode (8-bit is what `SINGLE_S4` wanted); weights only accept 16-bit and error otherwise, so leave weights at default.
>
> **Mesher contract:** indices arrive in `CUSTOM1.x`, weights in `CUSTOM1.y` (`/255.0`), both via `floatBitsToUint` + byte unpack. Indices are per-cell identities so they stay `flat`; the weights interpolate, and that is what softens the seam.
>
> **The four indices in a voxel must be UNIQUE**, including zero-weight slots — hence the filler indices 13-15, which are never real materials.

Slots are: biome ground / cliff rock (slope rule) / bedrock (depth rule) / ore.
`VoxelMaterials` gained `CLIFF_ROCK = 11`, `BEDROCK = 12`, `MAX_INDEX = 15`.
4 bits per slot means **no material index may exceed 15** — a 17th material
needs a different texturing mode, not another constant.

*Ore model.* Replaced one-noise-per-ore-plus-depth-gate with two fields: a
low-frequency **cellular** deposit field (`RETURN_CELL_VALUE`) where each
Voronoi cell is one deposit body holding one ore type, and a vein field where
`|noise| < VEIN_WIDTH` marks the vein. Depth is a soft `smoothstep` weight, not
a hard gate — the hard gate was the banding, since a depth test is a function
of radius and therefore draws spherical shells. Also two noise samples per
solid voxel instead of six.

> **Why cellular and not simplex:** simplex drifts continuously (no region edges) *and* is bell-distributed, so feeding it through a uniform rarity CDF piles every deposit into the middle entries. Measured with simplex: iron, the ore meant to be commonest, came out at 2% of deposits while coal took 47% — exactly inverted. Cellular cell values are uniform across cells, which is what makes the rarity table mean anything.

*Digging.* `player.gd`'s `_dig()` read `CHANNEL_INDICES` raw, which under the
new mode returns the packed 4-index word and silently matches no ore at all.
Now unpacks and takes the highest-weighted slot (`_dominant_material_at`).
`_build()`'s `MODE_TEXTURE_PAINT` path needed no change and works properly for
the first time — it was always the right API for this mode.

*Measured, before → after (400-point and 1170-voxel samples):*

| | before | after |
|---|---|---|
| ore share of subsurface rock | 34.9% | **2.6%** |
| ore per depth | spikes at fixed depths | **smooth, no shells** |
| directions containing ore | 56 / 60 | **14 / 60** (clustered) |
| commonest ore | coal (iron 2%) | **iron**, as designed |
| surface reading as cliff | 73% at first-tried mult 3.0 | **~15%** at calibrated 7.0 |

Knobs if it needs retuning: `VEIN_WIDTH` (vein thickness → ore abundance),
`ORE_REGION_SHARE` (how many deposit regions are barren), `CLIFF_SLOPE_MULT`.

**Follow-up 2026-09-07 — residual banding was in the SHADER, not the terrain.**

First measured whether the generated surface was actually stepped: walked the
exact SDF isosurface crossing along a strip at LOD 0-3 and took first
differences. 32 distinct step values out of 39 samples at every LOD, varying
smoothly — **the geometry is smooth and the generator was not the cause.**
Worth doing before touching anything; the obvious suspects (SDF quantization,
LOD coarsening) were both wrong.

The real cause was the terrain shader's noise hash:
`fract(p.x*p.y*p.z*(p.x+p.y+p.z))` over **world-space** coordinates. On a 200 m
planet with the detail octave's 3.5x scale, that product reaches ~2.5e5, where
float32's 24-bit mantissa has a ULP near 0.03 — so `fract` could only return
~30 distinct values, in a structured pattern. A moire generator, not noise,
which is why it showed worst on materials.

> **General rule: never build a hash out of float products of world-space
> coordinates.** It works at the origin and degrades with distance, so it
> looks fine in a test scene and bands on a real planet. Hash the integer
> lattice cell with bit-mixing instead — no magnitude-dependent precision loss.

Also fixed in the same pass:
- ~~The detail octave had 0.29 m cells against 0.4 m voxels, beating against
  the mesh's vertex spacing.~~ **This reasoning was wrong** — the noise is
  evaluated per *fragment* from world position, so it cannot alias against
  vertex spacing at all. The banding was entirely the hash. Backing the
  octaves off to 0.9 m on this false premise traded moiré for visible
  chunkiness, and was reverted in the next pass (see below).
- **`render_mode cull_disabled` removed.** It drew the inside of the surface
  too, and Transvoxel's LOD transition cells produce thin near-coincident
  slivers whose back faces z-fight their own front faces — the dark cell
  outlines that flickered with camera movement.

**Shader compilation IS verifiable headless**, contrary to the note this
replaces: Godot's dummy renderer still parses shaders and reports
`Shader compilation failed`. Confirmed by deliberately breaking the shader and
seeing the error, then confirming the real one compiles clean. What headless
still cannot check is appearance.

**Deliberately not changed:** `lod_distance` (64 local units ≈ 26 m, so the
first LOD transition is close). Raising it is the obvious next lever for
transition popping, but LOD was measured *not* to be causing the stepping, and
the generator is already the load-time bottleneck — doubling it roughly
quadruples LOD-0 area. Change it only if popping is still visible after this.

**Follow-up 2026-09-07 (b) — surface detail rewritten as proper fBm.** With the
hash fixed, what was left read as low-res/pixelated: two octaves of value noise
at 4 m and 0.9 m cells, on 0.4 m voxels. Two compounding causes:

1. **Only two octaves.** A material needs detail at every scale; two octaves an
   octave apart is a blob field, not a surface. Now six octaves from ~6.7 m
   down to ~0.21 m.
2. **Every octave axis-aligned.** Value noise sits on a cubic lattice, so
   stacking octaves keeps them all aligned to the same world axes, and a
   curved surface slicing that shows square patches. Each octave now gets a
   rotation (`OCTAVE_ROT`) to decorrelate them and break the grid.

Finest octaves are now deliberately *finer* than a voxel, which is correct —
per-fragment noise cannot alias against vertex spacing (see the corrected note
above). What it *can* alias against is screen pixels at distance, since
procedural noise has no mipmaps, so octaves are shed with view distance
(`active_octaves`, roughly one per doubling, from `length(VERTEX)` which is
view-space in `fragment()`), plus a close-range-only grain layer that fades out
by 12 m.

> **Rule of thumb this cost two passes to land on:** procedural surface detail
> wants *many* octaves spanning a wide scale range with rotation between them,
> and a distance-based octave budget. Tuning the frequency of a two-octave
> field just moves the artifact around — coarse reads as pixelated, fine reads
> as fizz.

*Not addressed, inherent to the mode:* material indices are `flat` (per-cell
identities), so where two neighbouring cells carry different index sets the
blend steps at the triangle edge. In practice the set is
`[biome stone, cliff, bedrock, ore-or-filler]` and only slots 0 and 3 vary, so
this shows only at biome borders. The deep uniform-fill blocks use a different
set (`[12,13,14,15]`) but resolve to the same bedrock colour, so that boundary
is invisible.

**Core Voxel Data & Generation**
- Modular Terrain API — strict interface (`TerrainManager`) handling all external queries so dependent systems survive if the voxel engine is disabled.
- **Current implementation:** Spherical voxel planet generated via custom `VoxelGeneratorScript` sampling noise on unit-sphere directions (seamless, no pole pinch). Ores placed via noise thresholds with `depth_below_surface` band checks.
- **Hybrid "Crust" Generation** — costly 3D volumetric noise restricted to narrow band; outer/inner shells filled uniformly. **Future**: migrate to `VoxelGeneratorGraph` for automatic range optimization + better visual quality.
- Delta Save/Load Database — `VoxelStreamSQLite` designed in but not yet wired (Alpha scope deferred). Saves only edited blocks; terrain regenerates base from generator each load.

> **Implementation notes:** `VoxelStreamSQLite` is ready to use — set `stream = VoxelStreamSQLite.new()` on `VoxelTerrain`, set `database_path`, call `save_modified_blocks()` periodically. The stream stores deltas only; base terrain regenerates from generator. There's also `set_key_cache_enabled()` for sparse-edit optimization. 
> 
> Current generator is `VoxelGeneratorScript` (CPU, per-block). `VoxelGeneratorGraph` (node-based, visual editing, ~20-50x speedup from removing interpreter overhead, auto range-analysis for block culling) is the recommended next step. Graph supports domain warping, ridged noise, splines for terrain shape, `NODE_SPOTS_3D` for scattered ore deposits, `NODE_SDF_SPHERE_HEIGHTMAP` for baked base layers (rung C). Hand-author one graph in the editor first (tuning work is the bulk of quality), then port to code-generated graphs driven by `CelestialBody` fields.

**Biome System** *(Beta)*

Source: detailed design in `biome-system-design.md`. **Current state: designed, not built.**

**Data model:**
- `OreType` (`Resource`): `id`, `material_index`, `depth_min/max`, `base_threshold`, `noise_frequency`. Replaces hardcoded ore constants. Allows per-ore depth tiers.
- `Biome` (`Resource`): `temperature_min/max`, `roughness_min/max`, `stone_material_index`, `ore_bias` (multiplier on ore thresholds, never a hard gate). Starter set: Regolith Plains (baseline), Frozen Wastes, Sulfur Flats, Crystal Fields.
- `CelestialBody` gets `ore_types: Array[OreType]`, `biomes: Array[Biome]`, `climate_bias: Vector2` (shifts temperature/roughness center for "mostly ice" vs. "mostly volcanic" planets).

**Region assignment** — 2 axes (climate space):
- **Temperature** = latitude term (`abs(dir.y)` on unit sphere) + altitude lapse (higher = colder) + `climate_bias.x` + low-freq wobble
- **Roughness** = independent low-freq noise (replaces humidity) blended with local slope steepness + `climate_bias.y`
- Biome pick: nearest in climate space; fallback to nearest-by-distance if no exact match

**Ore generation** — rarest-first priority:
1. Filter ores by `depth in [depth_min, depth_max]`
2. Sort by `base_threshold` (descending) so crystal (rare) wins over iron (common)
3. For each: `effective_threshold = base_threshold / biome.ore_bias.get(id, 1.0)`; sample noise; first one clearing threshold wins
4. None clear → `biome.stone_material_index`

**Rendering & Shaders** *(Beta polish; Alpha gets basic triplanar only)*

Current state: `voxel_debug_material.gdshader` (two-octave hash-noise albedo/roughness, planet-latitude tint). No real textures or blending yet.

**Beta target:**
- Triplanar Splatmap Shader — project textures along X/Y/Z axes to eliminate UV stretching
- Texture Array Mapping — pack biome-specific textures into `Sampler2DArray`, use material index as Z
- `TEXTURES_MIXED4_S4` for 4-way blended material indices per vertex (soft seams at biome boundaries)
- Dynamic Normal Overrides — rock texture on surfaces >45° slope regardless of biome
- Distance-Based Interpolation — blend high-frequency detail into low-frequency macro-color for orbital visibility

**Surface rules** (from biome):
- **Slope** — rock on steep, soil/sand on flat (highest impact for realism)
- **Depth below surface** — topsoil / subsoil / bedrock banding
- **Elevation + climate** — snowline, aridity

**Physics, Scale & Scatter**
- Floating Origin / Large-World Coordinate System — *see dedicated section below (1.0 Release scope)*
- Asynchronous LOD & Collision *(Beta)* — mesh generation on background threads (native to module). Deferred collision queue (custom scheduling) to stagger mesh swaps and avoid frame spikes.
- Data-Driven Foliage Scatter *(Beta)* — spawn/despawn via `VoxelInstancer` + `VoxelInstanceLibrary` (built into module). Mark items `persistent` for SQLite persistence.

**Terrain Status Notes:**
- Current `mesh_block_size = 16`, `lod_count = 5`, `lod_distance = 64` sufficient for 200m radius. Scaling to 2km needs `lod_count ~10`; 60km needs ~15-16.
- Hand-rolled shell optimization in current generator (skip noise outside thin shell) works well at current scale but won't generalize past a few km.
- Generator speed is GDScript-limited; `VoxelGeneratorGraph` is the next optimization lever before considering language switch or engine rebuild.

---

### Star System & Gravity — BUILT 2026-09-09

**Current State:** the star is a real body, not a light. Gravity is summed
over every body. Was: a `DirectionalLight3D` at a hardcoded rotation, plus a
disc painted into the sky shader at a constant angular size — nothing existed
at any position, so it could not be approached, could not occlude, and both
planets were lit as though the sun were in the same direction for each.

**Shared base type.** `CelestialBodyNode` now owns position, radius, surface
gravity, gravitational parameter, influence radius, atmosphere geometry,
irradiance and terrain access. `Planet` and `Star` both extend it, and
`PlanetPhysics` registers and queries through it rather than through `Planet`.
This is the build-once rule applied: a star *is* a celestial body, and giving
it a parallel implementation is exactly the drift that rule exists to stop.

**`StarBody` resource** — physical, not art-directed, same discipline as
`PlanetAtmosphere`. Radius, effective temperature, luminosity, surface
gravity, limb darkening, visual brightness. **Colour is derived from
temperature** via the standard blackbody approximation, normalized so
temperature changes hue without changing apparent brightness — a red dwarf and
a blue giant fall out of one number instead of needing hand-matched tints.

**Rendering.** `star_surface.gdshader` on a real sphere: unshaded, emissive,
limb-darkened (a real disc is dimmer at the edge; without it a star reads as a
flat cartoon ball), with slow convection granulation. Because it is geometry
it occludes, grows on approach, and is flyable-into. The painted sun disc was
removed from `starfield.gdshader` — it would double-draw, and being at
infinity it would show *through* the real star. The halo comes from
`Environment` glow rather than a fake corona shell, so the atmosphere limb and
any other emissive surface get it too.

**Light is derived, not authored.** `Star.gd` re-aims the `DirectionalLight3D`
from the star toward the player every frame and scales energy by inverse
square. A directional light is still right — clean parallel shadows, good
atlas behaviour — but its direction cannot be a constant once more than one
body exists.

**Scattering now takes a star *position*.** `atmosphere_scatter.gdshader`
derives sun direction and brightness per body inside its existing loop, using
the same `(reference/actual)^2` convention `Star.gd` uses for light energy, so
lit terrain and lit sky brighten and dim together. The single global
`sun_direction` uniform it replaced was wrong the moment two planets sat on
opposite sides of a star.

> **BUG, fixed 2026-09-09: the star rendered as a black sphere.**
> `star_surface.gdshader` uses `render_mode unshaded` and wrote its colour to
> `EMISSION`, leaving `ALBEDO = vec3(0.0)`. **Under `unshaded` Godot outputs
> ALBEDO directly and never runs the lighting pass, so EMISSION is never
> read.** The star was drawn perfectly - correct size, position and limb
> darkening - in pure black against black space. Any glow that appeared was
> the atmosphere's Mie forward-scatter, not the star.
>
> **Rule: with `render_mode unshaded`, write ALBEDO. EMISSION does nothing.**
> Values above 1.0 in ALBEDO are what the Environment's glow picks up as
> bloom, so HDR values there are what produce the halo.
>
> **Method note that mattered more than the fix:** five headless diagnostics
> confirmed the mesh existed, was `visible_in_tree`, sat inside the frustum at
> 4.65 degrees, and was well within the far plane - all true, and all useless,
> because "does it exist" and "is it visible" are different questions.
> Rendering real frames to PNG (`get_viewport().get_texture().get_image()`)
> and toggling one system between two captures found it immediately.
> **Headless cannot answer rendering questions; capture frames instead.**

#### Gravity: summed, not nearest-wins (decided 2026-09-09)

`PlanetPhysics.get_gravity_accel()` sums inverse-square pull from **every**
registered body. The old model took the nearest body inside its influence
radius, at a fixed magnitude with no falloff, and exactly zero outside.

Why the change: a star's pull must reach across the system while "which
surface am I standing on" must not, so the two questions had to stop sharing
one answer. Summing also deletes the special case entirely — the zero-g void
between planets still happens, because 1/d² from distant bodies is negligible
rather than artificially clamped.

`get_up()` deliberately still resolves against the **nearest** body, not the
summed gravity vector. Orienting to net gravity would tilt the player, their
buildings and the build grid slightly toward the star. "Up" is a surface-frame
question; gravity is not.

> **Consequence to know: gravity now falls off with altitude.** Measured on
> the home planet: 1.20 m/s² at the surface, 0.77 at +50 m. The old model was
> flat at 1.20 everywhere inside the influence radius. This changes jump and
> jetpack feel with altitude and is worth a deliberate playtest.

> **CALIBRATION TRAP, hit and fixed during this work.** A star mass that
> *sounds* plausible wrecks surface play. At `surface_gravity = 14.0` the star
> contributed **0.60 m/s² against the home planet's 1.2** — half of surface
> gravity — tilting local "down" by about 30°, measured as a 0.87 dot product
> against the local radial. At 0.15 it contributes ~0.006 m/s² (~0.5%),
> comparable to the Sun's real 0.06%-of-Earth-g influence, and the dot is
> 0.99999. **Rule: a star's pull at any planet must stay well under 1% of that
> planet's own surface gravity.** Check with
> `surface_gravity * radius² / distance²`. This is a consequence of the system
> being spatially compressed (star ~4.4 km from the home planet, not 150 Gm)
> and will need rechecking whenever bodies are moved.

#### Heat interface (built now, damage later)

`CelestialBodyNode.irradiance_at()` and `PlanetPhysics.get_irradiance()` /
`get_dominant_star()` exist and are verified inverse-square. Nothing consumes
them for damage yet — that is the deliberate "build the interface, defer the
guts" pattern, so adding heat damage later is not an architectural change.

#### Scale caveat

Realistic proportions would put the star ~109× planet radius and ~4.7 million
metres away, far past the 10 km jitter threshold in the scale ladder. The
current layout is compressed but self-consistent, and every derived number is
a function of `luminosity`, `radius` and `reference_distance`, so rescaling
later is data rather than code. True 1:1 still needs the floating-origin work
below.

**Verified headless:** 3 bodies register; surface gravity 1.1997 m/s² aligned
0.99999 with local down; midway between planets 0.129 m/s² pointing home; deep
void 0.0023 m/s²; irradiance ratio at 2r vs 4r = 4.000 exactly; dominant star
resolves correctly; blackbody colour at 5772 K = (1.00, 0.95, 0.90); all four
shaders compile; smoke test clean. **Not verifiable headless:** how the star
actually looks, glow tuning, and whether `visual_brightness`/`luminosity` are
in a good range.

---

## GOAL: Slice 1 Foundation, Architecturally Matched to SE2 (plan, 2026-09-09)

**Goal statement:** get Slice 1's terrain foundation as close to Space
Engineers 2 as is reachable for this project, before building more gameplay on
top of it. Not SE2's *scale* - SE2's *architecture*, so scale becomes a tuning
problem later instead of a rewrite.

**The one insight this plan turns on.** SE2 is **heightmap-first**. VRAGE3 is
marketed on escaping SE1's 2.5D heightmap, and it still keeps a heightmap at
its core (1 px / 8 voxels, plus a detail heightmap reaching 1 px / 1 voxel),
with 3D voxel detail layered on top for overhangs and boulders. Our pure-3D-
noise SDF is the thing that does not scale - not merely the fact that it is
written in GDScript.

That also resolves a storage problem that would otherwise sink "generate once,
persist it": a 2 km planet at 1 m voxels is ~5e9 shell voxels, far too many to
store. **A heightmap is ~32 MB.** So the persistent artifact is the baked
heightmap, not the voxels - which is exactly what SE2 does, and it makes
quality, speed and storage the same decision.

---

### Phase 0 — Align units — **DONE 2026-09-09**

**Result: a 2.5x larger planet for identical generation cost, loading slightly
faster.** Cost scales with voxel COUNT, not world size, so moving to SE2's 1 m
voxels while keeping the same 500-voxel radius grew the planet from 400 m to
**1.0 km diameter** at the same work. Player lands in 10.5 s (was 12.5 s).

| | before | after |
|---|---|---|
| `VOXEL_SCALE` | 0.4 m | **1.0 m** (SE2 parity) |
| Planet diameter | 400 m | **1.0 km** |
| Moon | 120 m @ 1100 m | 300 m @ 2750 m |
| Star | 176 m @ 4.4 km | 440 m @ 11 km |
| Relief | 3 m | 7.5 m |
| `view_distance` | 410 m | **1024 m** |
| Surface gravity | 1.2 | 1.1998, aligned 0.99999 |
| Star pull / sun disc | 0.5% / 4.58 deg | 0.5001% / 4.58 deg |

Moved with the unit change: `DIG_RADIUS` 0.7 -> 1.75, `BUILD_RADIUS` 1.0 ->
2.5, `DIG_FRAGMENT_THRESHOLD` 0.22 -> 0.55 (these are world metres but sized
in VOXELS - left alone they become sub-voxel no-ops), and
`REFERENCE_RADIUS_WORLD` 200 -> 500 so surface gravity stays at the value
every projectile arc and turret solution is tuned against.

**Deliberately NOT scaled:** `Foundation.SIZE` and ship `CELL_SIZE` stay at
2 m. Buildings are human-scale, not voxel-scale - SE2 likewise keeps 2.5 m
blocks on 100 km planets. Bases now cover proportionally less of the world,
which is correct.

**Phase 1 gate resolved:** `NODE_SDF_SPHERE_HEIGHTMAP` is
`(x, y, z) -> sdf` with params `image` / `radius` / `factor`. **One image for
the whole sphere means equirectangular**, not cube-face - so no dominant-axis
branching is needed and Phase 3's graph stays simple. The bake must oversample
poles and wrap the +-180 degree seam.

#### (original Phase 0 spec, for reference)

- `VOXEL_SCALE` **0.4 -> 1.0 m**, matching SE2. We are currently 2.5x finer
  than SE2 and paying **6.25x their surface voxel count** for detail the game
  does not need.
- Retune everything derived from it: `DIG_RADIUS`, `BUILD_RADIUS`,
  `Foundation.SIZE`, spawn constants, `VoxelViewer.view_distance` (still at
  1024 voxels / 410 m - **known open issue**).
- Set the Slice 1 target body: **2 km radius home planet.**
- Gate: player still digs, builds, places foundations and walks the sphere at
  200 m before scaling up. This phase must not change behaviour, only units.

### Phase 1 — Heightmap-first base — **DONE 2026-09-09**

**The planet's shape now comes from a baked, eroded heightmap.** Noise is
demoted to sub-pixel detail on top, which is the Space Engineers 2
arrangement. Verified: elevation spans -25.8 to +28.4 m across the sphere and
the player lands at r=491 m on a 500 m nominal radius - standing on real
terrain, not a noise sphere.

**Cost:** time-to-walkable went 10.5 s -> 37.8 s. That is inherent, not a
regression: relief went from 3 m to 36 m, so the generated shell is 12x
thicker and far more voxels take the full per-voxel path. Phase 3 (graph port)
is what buys it back.

**Pipeline:** `tools/bake_planet_heightmap.py` (offline, numpy) ->
`data/heightmaps/home.png` -> `PlanetHeightmap` resource ->
`CelestialBody.heightmap` -> generator. Leaving `heightmap` null keeps the old
pure-noise path exactly, so bodies migrate one at a time.

> **Godot loads 16-bit greyscale PNGs as FORMAT_L8** - verified, only 256
> distinct height values survive. Harmless at 7.5 m relief (0.03 m steps),
> visible terracing past ~256 m. Height is therefore split across R (high
> byte) and G (low byte), decoded as `(r * 255 * 256 + g * 255) / 65535`.
> **Phase 3 will need a FORMAT_RF conversion**, since `SdfSphereHeightmap`
> reads a single channel.

**Three bugs found wiring it up, all instructive:**

1. **`Planet.max_relief_world()` omitted the map** (reported 3 m instead of
   36 m) because a batch edit aborted before reaching it. Spawn probes and
   LOD-0 collision coverage are both sized from this value - it is the exact
   understated-terrain-band failure that broke the km-scale attempt.
2. **A pessimistic spawn fallback is worse than a neutral one.** Falling back
   to `radius + relief` parked the player up to a full relief-height above the
   real ground; collision only exists at LOD 0, which covers `lod_distance`
   around the viewer, so the ground fell outside the only region that ever
   generates collision and the player waited forever for a collider that would
   never be built *because* they were too far from it. Falls back to nominal
   radius now. **Being far from the ground prevents the ground existing** -
   the "park higher to be safe" instinct is exactly backwards here.
3. **`Image.get_pixel()` in the hot loop, plus a data race.** Four Object
   calls per voxel took time-to-walkable to 66 s, and the lazy cache that
   populated them was shared mutable state written from several generator
   worker threads at once - the pattern already recorded in ore_generator.gd
   as having segfaulted the engine. Now decoded once into a
   `PackedFloat32Array` via `prepare()`, called single-threaded at generator
   construction.

**Remaining Phase 1 work:** the second detail tier (SE2 runs a base map at
1 px / 8 voxels plus a detail map reaching 1 px / voxel; we currently have one
tier at ~3.1 m/px).

#### (bake tool detail)

`tools/bake_planet_heightmap.py` produces an equirectangular 16-bit heightmap
with fBm continents + ridged mountains + **real droplet hydraulic erosion**.
1024x512 at the current 500 m planet is ~3.1 m/pixel, already finer than SE2's
8 m/pixel base tier.

Run: `python tools/bake_planet_heightmap.py --seed 1 --width 1024 --droplets 400000 --out data/heightmaps/home.png --preview /tmp/relief.png`

**Four real bugs found while building it, all worth knowing:**

1. **Erosion rates were sized for a metres-domain, not 0..1.** At `capacity
   4.0` one droplet moved 0.01/step over 64 steps - two thirds of the entire
   height range. A few cells then blew up and min/max normalisation collapsed
   everything else to flat grey. Fixed with realistic rates plus a per-step
   change clamp.
2. **Min/max normalisation has no outlier resistance.** Erosion always leaves
   a few extreme cells. Percentile-clip (0.05 / 99.95) instead.
3. **Point deposits cause stipple.** Depositing a droplet's whole load onto
   one integer pixel leaves a single-pixel spike each time. Deposit
   bilinearly across four cells; erode through a **falloff brush disc**, not a
   point. The brush is the big one - without it every droplet digs its own pit
   and they never merge into channels.
4. **Latitude belongs on the GRADIENT, not the step length.** Dividing the
   pixel step by `cos(lat)` made droplets jump ~7 px near the poles, skipping
   cells. A pixel spans less ground near the poles, so the same height
   difference is a steeper real slope - scale the gradient instead.

> **Method note.** Stipple was chased through four wrong fixes while judging it
> by eye. What actually converged it: (a) writing a **pre-erosion preview** so
> base and eroded could be compared directly, which immediately proved the
> base was clean and erosion was the source; and (b) an objective
> **high-frequency energy metric** (RMS deviation from a 3x3 blur, reported
> base vs eroded). Ratio near 1.0 = carved cleanly, >2 = stippling. Currently
> **1.26x**. Do not tune a visual artifact without a number for it.

Also added: `max_useful_frequency()` caps octaves at what the map resolution
can represent (~1 feature per 4 px). Noise past that aliases into regular
stipple no erosion tuning can remove.

**Known remaining artifacts:** faint horizontal banding at the poles (inherent
to equirect - pixels there cover almost no ground) and slight crinkle along
ridge lines. Neither blocks wiring the map into the generator.

**Still to do in Phase 1:** `PlanetHeightmap` resource, generator sampling the
map via `SdfSphereHeightmap` (equirect, params image/radius/factor), the
second detail tier, and keeping biome/ore/surface rules layered on top.

#### (original Phase 1 spec)

- `PlanetHeightmap` resource + an **offline bake tool** (numpy or a Godot tool
  script) running real hydraulic + thermal erosion once per seed.
- Two-tier like SE2: base heightmap at 1 px / 8 voxels, detail heightmap
  reaching 1 px / 1 voxel.
- Generator samples the heightmap for surface shape and adds 3D noise **only
  below pixel scale**.
- **Resolve first:** which projection `NODE_SDF_SPHERE_HEIGHTMAP` expects
  (equirectangular vs cube-face). Cube-face needs a branch on dominant axis,
  which the graph cannot express - this decides Phase 3's shape.
- The existing biome / ore / surface-rule / 4-slot-material work layers on top
  **unchanged**. None of it is wasted.

Delivers: the World Machine look (real drainage networks, valleys, talus),
which noise cannot produce at any octave count. Also a large speed win, since
the base shape becomes one image sample instead of multi-octave noise.

### Phase 2 — 3D detail layer (SE2's "voxel storages")

Overhangs, caves, arches and boulders applied on top of the heightmap base.
This is what makes the result genuinely 3D rather than 2.5D, and it is the
part SE1 could not do. Our generator is already 3D-capable - this is
re-pointing existing capability, not new machinery.

### Generator profiling — added 2026-09-09

`OreGenerator.profile_enabled` / `profile_timings` + `profile_reset()` /
`profile_report()`. Counters are locals merged once per block under a mutex
(never per voxel - the generator runs on several worker threads, and shared
per-voxel state is both a race and slower than the work it measures). Phase
timers are opt-in because `Time.get_ticks_usec()` per voxel perturbs the
measurement.

**First run, at 500 m radius with the heightmap, to first walkable ground:**

```
blocks generated : 129080  (uniform air 2379, uniform solid 1082, per-voxel 125619)
total time       : 264945 ms across threads (44.2 s wall)
voxels visited   : 11247552  (23.56 us/voxel)
path: air_skip 40.5%   deep_skip 25.8%   full 33.7%
time: shape 20.4%   climate 9.2%   material 8.1%   -> only 37.7% accounted
```

**The finding: ~62% of time is unaccounted, and it is shape work done for
voxels that are then thrown away.** The phase timers only run on full-path
voxels, but the 66% that early-out have *already* paid for direction, two
noise samples and a heightmap sample (with `atan2` + `asin`) before the
early-out can decide. The early-out skips climate/biome/ore/material - it does
not skip the shape evaluation that decides it.

**Per-block surface bounds were TRIED AND REVERTED 2026-09-09.** The idea was
to bound each block's surface range from a grid of heightmap samples, then skip
shape evaluation for voxels outside that band. It was implemented and proven
*correct* - a comparison across 260 blocks / 1,064,960 voxels at three LODs
showed zero solid/air sign flips, zero SDF differences and zero material
differences against the unoptimised path.

**It was reverted because it did nothing.** Instrumented properly:

```
blocks with usable bounds: 98553 ok / 2523 unavailable  (97.5% usable)
voxels skipped BEFORE any shape work: air 98553, deep 0  (0.9% of all)
```

The band works out to roughly `[surface - 23, surface + 7]` voxels once the
noise margin and ore depth are added, which is *wider than the 16 voxels a
block spans radially*. Almost nothing falls outside it, so it skipped about one
voxel per block while adding a per-block sampling pass.

> **Two lessons worth keeping.** First: a correctness proof is not a
> justification - passing the identical-output test said nothing about whether
> the optimisation was worth having, and it would have shipped as pure
> complexity. Second: the first attempt at counters incremented the SAME
> counter for the new path and the old one, so the path distribution looked
> identical whether the new path fired constantly or never. **Instrument the
> new path separately from the one it is meant to replace**, or the numbers
> cannot answer the question being asked.

**Where the time actually goes remains open.** Shape work on discarded voxels
is still ~62%, and the block-bounds approach cannot reach it because a block
simply is not radially thick enough for a surface band to exclude much of it.
The real fix is Phase 3 (graph port), not further per-voxel tuning.

> **Machine noise caveat:** identical or near-identical code measured 23.6,
> 31.3 and 39.9 us/voxel across three runs. **Do not judge a sub-2x change
> from a single end-to-end run on this machine** - use a controlled in-process
> A/B (as the earlier `BIOME_SURFACE_MARGIN` early-out did, measuring a clean
> 33%: 4.87 -> 3.25 us/voxel).

**Also note 97.3% of blocks take the per-voxel path.** The block-level shell
test is working; the shell is simply large (94 voxels thick once the heightmap
contributes +-33 voxels of relief on top of noise and ore depth).

### Phase 3 — `VoxelGeneratorGraph` port — **CORE DONE 2026-09-09**

**Time to playable: 40-60 s -> 3.4 s.** Measured three consecutive runs at
3.5 / 3.4 / 3.4 s with no variance, on a machine that had been producing 23.6 /
31.3 / 39.9 us/voxel for near-identical code. The load problem is gone.

| | |
|---|---|
| Graph vs script, shape only | **61x** (153061 -> 2503 us) |
| Graph vs script, + noise + materials | **13x** |
| Time to playable | **3.4 s** (was 40-60 s, once 117 s) |
| Landing radius | 490.9 vs script's 491.0 - shape matches |

Generation dominated boot far more than the 13x block figure implied; meshing,
collision and the spawn wait turned out to be a small share.

`PlanetGraphGenerator.build(body, voxel_scale)` constructs the graph in code
from the `CelestialBody`, per the standing rule that a new body is a new
resource and never a new script. `Planet.use_graph_generator` (default true)
switches back to the script generator, which stays the reference
implementation.

**NOT YET PORTED - real functional regression while this stands:** biome stone
selection, slope-driven cliff rock, and rarest-first ore veins. The graph has
no branching, so all three need branchless min/select rewrites. Terrain shape
and the ground-over-bedrock crust are correct; everything else is flat.
`NODE_SPOTS_3D` is already available for the ore.

**API gotchas hit, all silent-failure shaped:**

> **`SdfSphere` takes radius as INPUT PORT 3, not a parameter** - it has no
> params at all. `set_node_param` on it errors and leaves radius at its
> default, silently producing a wrong-sized planet. Only bodies *without* a
> heightmap take that path, so it hid until the moon was checked.

> **`FastNoise3D` needs `ZN_FastNoiseLite`**, godot_voxel's own class - it will
> not accept Godot's `FastNoiseLite`.

> **`SdfSphereHeightmap` needs a single-channel image**, so the baked PNG (16-bit
> height split across R and G to survive Godot's L8 loading) must be converted
> to `FORMAT_RF` first. ~80-110 ms once at build time.

> **Circular preload**: `Planet` preloads the generator, so the generator must
> NOT read `Planet.VOXEL_SCALE` - pass it as an argument. Godot reports this as
> a parse error in an unrelated file (`world.gd`), nowhere near the cycle.

### Phase 3 — original scope

**Deliberately after Phase 1, not before.** Once the heightmap carries the
shaping, the graph collapses to "sample image + add detail + surface rules,"
which is far easier to express in a branchless node graph than the current
multi-octave biome logic. Porting first would mean porting work Phase 1 then
deletes.

Budget 20-50x (no `FastNoise2` in this build; recompiling with it is the next
lever if still short). Hand-author the reference graph in the editor first -
the tuning is the quality - then port to a builder driven by `CelestialBody`.

### Phase 4 — Persistence and streaming

- Baked heightmap = the persistent base artifact (small).
- `VoxelStreamSQLite` = **player edits only** (deltas), which is what it is
  designed for.
- Loading screen covers the one-time bake. **User accepted this 2026-09-09**,
  and it is what makes the whole approach viable.
- Closes the terrain half of the missing save system.

### Phase 5 — SE2 content parity (after the foundation is solid)

Dynamic voxel hardness (sand deforms softly, rock resists), material
transition masks with height information, volumetric water, biome scatter via
`VoxelInstancer`.

---

### Cross-cutting: scale-dependency audit

**Anything assuming the surface sits at `radius_world()` breaks once relief is
a meaningful fraction of radius.** Three found so far this session:
`SPAWN_HOVER_HEIGHT` and `SPAWN_PROBE_DEPTH` (fixed - spawn now reads voxel
data via `max_relief_world()` / `_find_data_surface()`), and
`VoxelViewer.view_distance` (**still open**). Sweep for more before scaling,
rather than discovering them one failed playtest at a time.

### Definition of done for Slice 1

1. 2 km planet, walkable within a loading screen, no fall-through.
2. Terrain reads as eroded landforms, not noise.
3. Overhangs and caves exist.
4. Dig and build work at 1 m voxel granularity.
5. Player edits persist across launches.
6. Planet renders from orbit and from the surface with no popping.

### Verification rules adopted this session (all three were learned the hard way)

- **Run the instrument against a known-good config before diagnosing a
  failure.** A collider test that filtered on `StaticBody3D` reported failure
  at *every* scale, including the working one; four wrong mechanisms were
  diagnosed off it.
- **Never assert state from a position range.** A capsule held motionless by
  the spawn loop satisfied a "did it land" threshold. Use `is_on_floor()` or a
  real state change.
- **Headless cannot answer rendering questions.** Five headless checks
  confirmed the star mesh existed, was visible and was in frustum - all true,
  all useless. Capture frames with
  `get_viewport().get_texture().get_image().save_png()` and A/B one system
  between two captures.

---

### Terrain Critical Path — scoped 2026-09-09

Everything terrain-related now blocks on three pieces, in this order. Nothing
else in the terrain backlog is worth starting first.

**Where we actually are (measured, not estimated):**

| | value |
|---|---|
| Generator speed | 4.2-4.7 us/voxel (GDScript), flat in radius |
| Playable planet | 200 m radius, player lands in ~12 s |
| 2 km planet | collision never arrives in 170 s - **not viable** |
| Persistence | none. Every launch regenerates from scratch |
| Base representation | pure 3D noise SDF, no heightmap layer |

---

#### Piece 1 — `VoxelGeneratorGraph` port (~20-50x)

The single highest-leverage change. Removes the per-voxel GDScript
interpreter and gets automatic range analysis for block culling.

Node set already verified present in this build: `NODE_OUTPUT_SINGLE_TEXTURE`,
`NODE_OUTPUT_WEIGHT`, `NODE_CURVE` (splines), `NODE_IMAGE_2D`,
`NODE_SDF_SPHERE_HEIGHTMAP`, `NODE_SPOTS_3D`, `NODE_EXPRESSION`,
`NODE_FUNCTION`. **`FastNoise2` is NOT compiled in**, so budget 20-50x rather
than 50-200x; recompiling godot_voxel with FastNoise2 is the next lever after
this if it is still short.

Build order matters: hand-author one reference graph in the editor first (the
tuning IS the quality, and the editor has a live preview), then port it to a
programmatic builder driven by `CelestialBody`. Keep `ore_generator.gd` behind
a flag as the reference to diff against.

Unlocks: 2 km planets, and probably makes Piece 2 optional at that scale.

#### Piece 2 — Generate once, stream from disk (`VoxelStreamSQLite`)

We regenerate terrain from scratch every time the player moves, and again on
every launch. That is the actual cause of "terrain still popping in behind me
after I already landed" - the generator loses a race against the viewer.

`VoxelStreamSQLite` ships with the addon. Generate the planet once behind a
loading screen, persist it, and afterwards read blocks from disk. Disk reads
beat a GDScript generator by orders of magnitude, which turns scale from a CPU
problem into a storage one.

**User has explicitly accepted a loading screen for this (2026-09-09).** That
is what makes this route open, and it changes the architecture: we stop
optimising for "generate fast enough to keep up with a moving player" and
start optimising for "generate once, correctly, then read."

Also closes the long-standing "no save system exists" gap for terrain.

#### Piece 3 — Baked eroded heightmaps (the World Machine look)

**This is the piece that actually delivers the requested look, and it is not
optional for it.** No amount of layered noise reproduces real drainage
networks, river valleys or talus slopes - those are the product of simulated
erosion, which is iterative and non-local and cannot run per-block on demand.

Run real hydraulic erosion once per seed, offline (numpy or a Godot tool
script), into a 2048-4096 square heightmap. Sample it via
`NODE_SDF_SPHERE_HEIGHTMAP` / `NODE_IMAGE_2D` and let the graph add all detail
below pixel scale.

Open question to resolve first: which projection `NODE_SDF_SPHERE_HEIGHTMAP`
expects (equirectangular vs cube-face). Cube-face needs a branch on dominant
axis, which the graph cannot express.

---

### Reaching Space Engineers 2-Level Planets

**What SE2 actually does** (researched 2026-09-09, see Sources):

| | SE2 | Stellar TD today |
|---|---|---|
| Max planet diameter | **303 km** official (engine handles thousands) | 0.4 km |
| Voxel size | **1 m** | 0.4 m (we are 2.5x finer, at 6.25x the surface voxel cost) |
| Base representation | **heightmap at 1 px / 8 voxels + a detail heightmap giving 1 px / 1 voxel** | pure 3D noise SDF |
| Overhangs / caves | separate small voxel storages spawned on top of the heightmap | 3D noise (capable, unused) |
| Material transitions | multi-voxel transition mask with height information | 4-slot weight blend (built 2026-09-07) |
| Block precision | 25 cm unified grid | 0.4 m voxels |
| Dynamic hardness | yes - sand deforms softly, rock resists | no |
| Volumetric water | yes | no |
| Generator | native, decade of VRAGE lineage | GDScript |

**The most important finding: SE2 is heightmap-first, not noise-first.** Even
in VRAGE3 - which is specifically marketed on escaping SE1's 2.5D heightmap
limits - the core is still a heightmap, with 3D voxel detail *layered on top*
for overhangs and boulders. That independently validates Piece 3, and it means
our current pure-3D-noise architecture is the thing that does not scale, not
merely our language choice.

**What we would need, beyond the three pieces above:**

1. **Precision work.** At a 150 km radius, float32 quantum is ~16 mm - well
   past visible jitter. Requires the double-precision build or floating
   origin. Already scoped in the section below; unavoidable past ~10 km.
2. **Coarser voxels.** SE2 uses 1 m. At 0.4 m we pay 6.25x their surface voxel
   count for detail finer than the game needs. Changing `VOXEL_SCALE` also
   touches dig radius, building placement and foundation size - it is not a
   one-line change.
3. **LOD-aware collision + a deferred collision queue.** Collision currently
   exists only at LOD 0 (`collision_lod_count = 1`), which is why the player
   must be near real ground before anything is walkable.
4. **`VoxelViewer.view_distance`** is 1024 voxels (410 m) - fine at 200 m,
   caps everything at km scale regardless of `lod_count`. **Still open.**
5. **Content systems** SE2 has and we do not: volumetric water, dynamic voxel
   hardness, material transition masks with height, biome-driven scatter.

**Honest effort assessment.** Pieces 1-3 are a reasonable near-term project
and get us to a good-looking few-km planet. 303 km is a different category:
Keen has a professional engine team and a decade of VRAGE lineage behind
VRAGE3. A realistic ladder is 2 km (pieces 1-2), then 10-20 km (piece 3 plus
coarser voxels and LOD collision), then 100 km+ (precision plus almost
certainly native code). Treat SE2 parity as a direction, not a milestone.

**Sources:**
- [VRAGE3 wiki](https://spaceengineers2.wiki.gg/wiki/VRAGE3)
- [Marek's Dev Diary, Aug 21 2025](https://2.spaceengineersgame.com/mareks-dev-diary-august-21-2025/)
- [SE2 planets & survival foundations](https://blog.marekrosa.org/2025/12/space-engineers-2-alpha-vs2-planets-survival-foundations-live-now/)
- [SE1 planets (120 km, 2048 heightmaps)](https://spaceengineers.wiki.gg/wiki/Planets)

---

### Floating Origin / Large-World Coordinate System — 1.0 Release

**Locked-in decisions:** continuous seamless interplanetary flight (no loading/warp), full 1:1 real solar-system scale (sun through Oort), stock Godot build as primary (double-precision as fallback).

**Precision at different scales:**
| Distance | Position quantum | Playable? |
|---|---|---|
| 200 m (today) | 0.015 mm | fine |
| 2 km | 0.12 mm | fine |
| 10 km | ~1 mm | fine, watch for jitter |
| 60 km | ~3.9 mm | **visible jitter, unstable physics** |

**Why stock Godot suffices (initially):** GDScript's `float` is always 64-bit (true precision), but `Node3D.global_position` is 32-bit float. Governing rule: never store true world position in a node's transform. Instead: script-side double ("authoritative position") + small float32 offset in node transform (relative to camera). Danger is distance-from-local-frame, not distance-from-sun. Jitter appears at ~1–10km if raw global position is treated as truth.

**Double-precision fallback:** Zylann publishes official prebuilt editor builds with voxel module + double precision. Export templates must be compiled custom if needed for shipping (not automatic). Real cost: infrastructure tax on every engine/addon update.

**Architecture — three layers:**
1. Authoritative double-precision world state — true positions/velocities as script doubles. Save/load persists this layer only.
2. Reference-frame simulation strategy — active vessel + immediate surroundings run full real-time physics ("physics bubble," radius TBD). Every other body computed analytically from orbital elements (Kepler/patched-conic) each frame. Planetary self-rotation composed on top.
3. Render-layer camera-relative transform — every frame: `render_pos = body_true_pos - camera_true_pos` (float32, small delta). Always-on, no reset events.

**Subsystems requiring frame-awareness:** player/camera; `VoxelLodTerrain` (needs spike test — does it ever touch solar-system-scale coords?); active physics bodies (re-center to bubble before physics server); non-active bodies (analytic orbits only); projectiles/enemies (must track authoritative frame, handle handoffs); `GPUParticles3D` (camera-relative emission); skybox/starfield (parallax layers); UI world-to-screen (waypoints, targeting).

**Open decisions:** physics bubble radius / handoff logic; whether terrain streams long-range or only on landable bodies; enforcement (lint/tests) for "no raw global position at scale."

**First spike:** (1) double-precision position layer + camera-relative render offset, no gameplay; (2) two static bodies on correct orbits, verify no jitter at distance; (3) one craft flying continuously between them, verify rendering holds; (4) physics bubble handoff + terrain streaming, confirm `VoxelLodTerrain` never sees solar-system coordinates directly.

---

### Atmosphere System — BUILT 2026-09-07

**Current State:** physically-based single-scattering atmosphere, raymarched
per pixel, all bodies in one pass. Replaced the previous sky-gradient shader,
`Environment` fog, and the translucent proxy spheres. Missing: volumetric
clouds, re-entry heat shimmer.

**Interacts with:** projectile drag (shares one density model), Weather
system (future), `PlanetPhysics` (body registry).

**Architecture — three pieces, each removable**
- `PlanetAtmosphere` (`Resource`) — pure data. Scattering coefficients, not
  colours.
- `starfield.gdshader` (`shader_type sky`) — deep space, stars, sun disc.
  Identical on every body and in the void; knows nothing about atmospheres.
- `atmosphere_scatter.gdshader` + `AtmosphereRenderer` (`MeshInstance3D`) —
  one full-screen pass compositing scattering over the finished frame.
  Nothing depends on the renderer existing; deleting the node or setting
  `enabled = false` removes atmospheric rendering and breaks nothing, per the
  standing "every system toggleable" rule. Air density lives on
  `Planet`/`PlanetAtmosphere`, so drag keeps working with it gone.

**Why one integral rather than separate systems.** Sky colour, haze on distant
terrain, the lit limb from orbit, and the fade on leaving the atmosphere are
all the same physical quantity. Computing them separately is what let them
disagree before. It is also why there is **no "up" vector anywhere** in the
new code — the pass intersects a sphere and integrates along the view ray, so
it is correct at every point on every body automatically.

**Bugs this fixed (all four confirmed by reading the old code, not guessed):**
1. **Sand-yellow sky dome.** `world.gd` set `fog_light_color` from the
   planet's sand `fog_color` but never set `fog_sky_affect`, which **defaults
   to 1.0** — so fog painted over the entire background. Leaving the
   atmosphere drove the density to 0 and revealed the real sky, which is
   exactly the transition that was reported. The moon looked fine only
   because it had `fog_enabled = false`.
2. **Sky gradient built on the world Y axis** (`up = EYEDIR.y`). Correct only
   at the north pole; tilted everywhere else on a sphere.
3. **Stretched stars.** `floor((dir.xz + 1.0) * 260.0)` projects a 3D
   direction onto a plane, squashing toward ±Y into streaks. Stars are now
   hashed from a 3D cell on the unit sphere — roughly equal solid angle in
   every direction.
4. **`haze_color` never wired.** `PlanetAtmosphere` had no such field, so
   every planet got the shader's hardcoded blue haze.

> **CORRECTION to this section's previous recommendation:** it said to use
> Godot's built-in **`PhysicalSkyMaterial`** for ground-level sky. **That does
> not work for a spherical planet.** It hardcodes world +Y as up and a `Sky`
> has no transform, so its horizon stays locked to the world XZ plane while
> the player's actual horizon rotates as they walk around the body — it would
> reproduce bug #2 with no way to fix it. The shell raymarcher covers ground
> level too, which is why there is no separate ground-sky path.

**Per-planet parameters** (`PlanetAtmosphere`): `rayleigh_coefficients`
(vec3, ~1/wavelength^4; Earth ≈ `(5.5e-6, 13.0e-6, 22.4e-6)`),
`mie_coefficient` + `mie_anisotropy`, `ozone_absorption`,
`rayleigh_scale_ratio` / `mie_scale_ratio`, `shell_radius_ratio`,
`scattering_energy`, `surface_air_density`, sun colour/energy/angular size.

Scale heights are stored as a **fraction of body radius**, not in metres, so
an atmosphere stays proportionate on a 200 m starter planet and a 60 km one
without retuning.

**One deliberately non-physical number.** `AtmosphereRenderer.irradiance_to_scatter`
(default 17.0). The coefficients are real per-metre values, but our bodies are
~200 m rather than Earth's 6371 km, so the optical path through a whole
atmosphere is thousands of times shorter and the integral comes out nearly
black. This constant buys that back. It is a **unit conversion, not a
brightness dial** — sky brightness is derived as
`star.irradiance_at(reference_distance) * irradiance_to_scatter`, so **tune the
star's `luminosity` to change brightness**, which keeps the sky, the
directional light and (later) heat damage all reading from one number instead
of drifting apart. Will need revisiting at each rung of the scale ladder.

(This replaced a standalone hand-set `sun_intensity = 4200`. The derived value
lands at 4192.6, a 0.18% difference, so the change is not a visual one.)

**Density model shared with gameplay.** `PlanetAtmosphere.density_at()` is the
single source for both the rendered atmosphere and `projectile.gd` drag, so
they cannot drift. Exponential falloff on the Rayleigh scale height, eased to
exactly zero over the top fifth of the shell — a bare `exp()` cut off at the
boundary still has ~6% of sea level left when it stops, which would step a
projectile's drag as it crossed.

**Multi-planet:** the shader loops over up to `MAX_BODIES` (4) fed from
`PlanetPhysics.get_all_bodies()`. Both bodies are marched in the same frame,
so flying between planets crossfades on its own — no reload, no CPU-side
blending. Vacuum bodies are skipped so an airless moon costs no shader slot.
**Raising the limit means editing both** `MAX_BODIES` in the shader and the
constant in `AtmosphereRenderer` — a shader cannot size uniform arrays from
GDScript.

**Verified headless:** both shaders compile (checked against a deliberately
broken control, so the check is known non-vacuous); the runtime uniform feed
pushes 1 scattering body with the moon correctly skipped, shell radius 250 m
against a 200 m surface, unit-length sun direction; density is continuous to
zero and preserves the old 1.225 surface value; full smoke test clean.
**Not verifiable headless:** how any of it actually looks, and the depth
reconstruction. The pass clamps every span with `min()` against the shell
exit rather than special-casing "no geometry", so it should be correct under
either depth convention, but that specifically wants an F5.

**Tonemapping is part of this system, not an unrelated setting.** The pass
outputs real radiance, which exceeds 1.0 on a bright limb. Godot's default
`TONE_MAPPER_LINEAR` hard-clips there, which showed up on the first playtest
as a limb that blew out to flat white while staying blue in its dimmer parts —
hue discarded exactly where the effect reads most. `world.gd` now sets ACES
with `tonemap_white = 6.0`. **Any future change to `sun_intensity` or the
coefficients should be judged with a tonemapper active**, or bright regions
just clip and the tuning is meaningless.

Ambient is a small constant colour rather than sky-sourced: the sky is
near-black space now, so sky ambient is effectively zero and anything on a
body's night side renders as pure silhouette, including the player's own ship.

**Still missing:** volumetric clouds, re-entry heat shimmer (both need the
Weather system's dynamic-pressure/Mach inputs).

**Gotcha hit while building this:** adding a new `class_name` needs
`--headless --path . --import --quit` before the class resolves; otherwise
scripts referencing it fail with "Could not find type X in the current scope"
even though the file is correct.

---

### Weather System — Beta Scope

**Current State:** `PlanetPhysics` autoload has `get_air_density(pos)` (used for projectile drag) but no full Weather system yet.

**System Principles:**
1. Modular — standalone, clean query APIs, zero hard dependencies back
2. Graceful fallbacks — if disabled or no atmosphere, returns vacuum defaults (density=0, pressure=0)
3. Performance first — lightweight per-frame queries across many entities

**Core data model:**
- Per-planet `Resource` (e.g., `WeatherProfile`): `radius`, `gravity`, `P0` (sea-level pressure), `scale_height`, composition, temperature gradients
- Stateless query API: `GetDensity`, `GetPressure`, `GetTemperature`, `GetSpeedOfSound`, `GetDynamicPressure`, `GetSunlightAttenuation`
- Exponential decay: `density = P0 * exp(-altitude / scale_height)`
- Mach number: `speed_of_sound = sqrt(gamma * R_specific * temperature)`

**Scaling:**
- Small moons/asteroids below radius/mass threshold: `P0 = 0`, `scale_height = 0` (vacuum, no fallback branching needed)
- Super-Earths/Gas Giants: higher `Hmax`, thicker `P0`
- Manual overrides for edge cases (e.g., Titan)

**Integration:**
- Projectiles: air density → drag coefficient applied each tick
- Re-entry effects: dynamic pressure `q = 0.5 * ρ * v²` and Mach number drive shock-cone/plasma vfx
- Audio: density → acoustic attenuation; pressure → wind/roar parameters

---

### Factory / Logistics System — Alpha (minimal) → Beta (expanded)

**Current State:** Grid-cell pipe network (`PipeNetwork` autoload), 5 ore types, refining chain (Processor, Smelter), Conveyor (Vacuum Pipe, Merger, Splitter), Chest storage. Single recipe type per building (auto-craft on timer).

**Validated patterns:**
- **Single-source-of-truth placement:** `_resolve_build_placement()` drives both live ghost preview and actual building commit
- **Pipe network grid-cell lookup:** `Vector3i(floor(pos))` dictionary, O(1) neighbor queries
- **Merger fairness:** rotating cursor per-input, not first-come-first-served
- **Splitter:** rotating cursor per-output
- **Multi-input recipes:** parallel `input_ids`/`input_amounts` arrays (simpler to hand-author than nested sub-resources)
- **Building base class absorbs timer/auto-craft:** every recipe-driven building gets it for free; rotating cursor over multiple auto-recipes
- **Slot-based inventory:** backward-compatible wrapper over flat counter API; grid + hand slots via generic adapters

**Known architectural decisions:**
- `FoundationNetwork` uses flat linear scan (not `Vector3i` dictionary like `PipeNetwork`) — buildings aren't axis-aligned, so grid lookup doesn't work. At hobby scale (<100 foundations per base), linear scan is simpler and correct.
- `SlotCarry` (one click-to-carry implementation) driven through duck-typed container adapters, not duplicated code per UI screen
- `Building.input_capacity`/`output_capacity` are *not* storage caps — they're throughput-rate placeholders for future power/logistics system. Actual cap is `inventory_capacity`.

**Beta scope:** more resource types, more building tiers, power system, expanded conveyor mechanics.

---

### Weapon & Combat System — Alpha (partial) → Beta (full) → 1.0 (orbital/interplanetary)

**Current State:** Turrets (gun + cannon) built and validated. Projectile physics working. Scout ship AI basic. Wave spawning tied to crystal signature (not power, see Radiation Threat section). Enemy health and targeting working.

**Design intent:** combat is anti-air (planet-to-orbital) and ship-to-ship, not close-quarters. Readability + cinematic spectacle over simulation precision.

**Architecture — modular facade pattern:**

1. **CombatManager** — facade. All external combat access through it. `RequestFire()`, `RegisterMount()`, `QueryAmmo()`.
2. **WeaponDefinition** — `Resource` holding tier, muzzle velocity, drag coefficient, fire rate, ammo cost, projectile type. Tuned via data, not code rewrites.
3. **ProjectileSystem** — ballistic sim. **Current implementation:** one `Node3D` per projectile with hand-integrated semi-implicit Euler physics. **Architectural gap:** main-design calls for pooled, data-oriented system (parallel position/velocity arrays per frame). Current approach will be expensive with hundreds of live shells.
4. **HitscanResolver** — beam weapons (separate from projectile system, minimal shared code).
5. **DamageTarget** — duck-typed contract (`apply_damage(amount, type, position)`). Terrain, ships, shields all implement it.
6. **ShieldComponent** — absorbs damage to capacity, regenerates over time, forwards overflow. Fresnel-ripple shader. Same component serves personal/base scales (different capacity/radius).
7. **WeaponMount** — building piece (not separate placement system). References `WeaponDefinition`, has fire-arc constraint, ammo-feed to inventory.
8. **TargetingSolver** — stateless function: ballistic data + target position/velocity → lead-aim solution. Shared by player UI and enemy AI.
9. **CombatVFXController** — signal-driven. Listens to projectile "fired"/"impacted" signals; triggers hero-cam, explosions, debris, craters.
10. **Reference-frame tag** — each live projectile carries "which frame am I authoritative in" tag (for floating-origin handoff later).

**Ballistics model:**
- Lightweight point simulation (position/velocity struct), integrated per physics tick
- Gravity from `PlanetPhysics.get_gravity_accel()`
- Drag: `0.5 * air_density * Cd * cross_section_area * speed^2`, divided by mass for acceleration
- Aim model: solved no-drag quadratic for launch angle (deliberately different from flight model; acceptable divergence)
- Hit detection: swept raycast from previous to new position (no tunneling through thin targets)
- **Known issue:** determinism not verified for multiplayer. Main-design requires "pure function of (state, fixed delta), no per-frame randomness." Needs testing before scaling up to 100+ simultaneous projectiles.

**Ammo system:**
- `AmmoType` (`Resource`): `mass`, `muzzle_velocity`, `caliber`, `drag_coefficient` (ballistics spec) + `damage`, `splash` (combat spec)
- Turret holds `compatible_ammo: Array[AmmoType]` + per-item enable/disable toggle
- Ammo types: `iron_piercing_ammo` (both turrets), `he_shell` (cannon-only, splash)
- Why ammo owns ballistics: different ammo types are what differentiate combat outcomes, not which turret fired them

**Weapon tiers (planned, not all built):**
- Personal/infantry guns (player-carried, hitscan/short arcs)
- Point-defense (fast anti-missile)
- Medium ship-to-ship cannons (readable ballistic arcs, real travel time)
- Siege/capital/orbital guns (slow, dramatic arcs for spectacle)
- Missiles/guided (travel-time + tracking)
- Beam/energy (hitscan, distinct visual language)

**Cinematic features (future):**
- Hero-shot camera for capital-scale fire (tracking shell across long distance, slow-mo inserts)
- Shell-atmosphere interaction: hypersonic shells trigger same re-entry plasma effects as spacecraft
- Volumetric clouds: shells scatter clouds for visual spectacle (future, needs cloud layer)

**Roadmap:**
- Alpha: `CombatManager` + `WeaponDefinition` resources (1–2 weapons); minimal `ProjectileSystem` (gravity only, no drag); `DamageTarget` base class; basic enemy HP.
- Beta: full ballistics (drag), `HitscanResolver`, `ShieldComponent`, `WeaponMount` in building system, `TargetingSolver`, `CombatVFXController`.
- 1.0: reference-frame tagging, siege/orbital weapons, hero-cam, volumetric cloud disturbance, multiplayer hardening of `ProjectileSystem`.

**Multiplayer readiness:** deterministic, step-based ballistics are critical for client-side prediction/rollback. Currently not verified. Must test before shipping.

---

### Radiation Threat System — Slice 2, Scopes 1–5

**Current State:** Scope 1 complete and validated (crystal ore, signature tiers, scout ship). Scopes 2–5 designed but not built.

**Lore:** Player is corporate mining operation. Objective ore is radioactive crystal (direct use: reactor fuel, weapon cores, building material; dissolve: mission resource). Crystal creates persistent signature that draws alien attention. All enemies are starships (not ground troops).

**Threat tiers** (signature-driven, no arbitrary clock):

| Tier | Signature | Behavior |
|---|---|---|
| None | ~0 | No spawns. No signature is a legitimate playstyle. |
| Low | small leak | One scout ship flies in, hovers, scans. If it detects something (chance scales with depth into band), flees toward system edge. **Core tension:** kill it before escape (report never goes out), or let it slip and face escalation. |
| High | large/sustained | No scout — mothership detects source directly, puts player into constant war state (continuous fleet pressure) until signature drops back down. |

**Signature source:** crystal currently held/socketed (persistent) + dissolve-machine bursts (temporary spike, future). Barriers/containment (Scope 5) are the tool to drop signature without not-mining-at-all.

**Scopes:**

- **Scope 1** (✅ Complete): `RadiationSignature` autoload (reads crystal count, exposes tier + `tier_changed` signal), `ThreatDirector` (spawns one scout on Low tier entry), scout ship (flies in from edge, hovers, scans, flees with/without report), turret-targetable.
- **Scope 2** (❌ Not started): Escalation fleet — what `leak_reported` actually spawns. Open question: how do starships damage ground bases (orbital bombardment / landing / gunship)? Needs decision.
- **Scope 3** (❌ Not started): High tier constant-war spawning.
- **Scope 4** (❌ Not started): Dissolve machine (converts crystal to mission resource, produces signature spike).
- **Scope 5** (❌ Not started): Containment barriers (powered building that dampens signature radius).

---

### Vehicle Building System (Ship System) — Alpha → Production (Phases 1–5)

**Current State:** Phase 1 (Alpha vehicle loop) partially shipped. `Ship` RigidBody3D works. Blocks (Core, Hull, Thruster, Gyroscope, Cockpit) placed and removed. Grid transactions validate. Live ghost works. Entry/exit camera, dampeners functional. EnemyScoutShip migrated to `Ship` physics.

**Known rough edges:** placement against moving ship needs playtest, exit position can clip hull, no fuel/power/per-block health/persistence yet.

**Design rules:**
- `Ship` is the one `RigidBody3D` physics for player and AI (no separate controllers)
- Local integer grid (cell size = 2.0, matches Foundation)
- Blocks are data-driven `Item` resources + scenes; `Ship` owns grid + collision shapes
- All systems expose narrow capability interfaces (not one block per capability)
- Simulation must be deterministic (save/restore)

**Grid & block contracts:**
- `ShipBlock` holds: `block_id`, `display_name`, `mass_kg`, `max_health`, `health`, `armour_class`, `can_be_removed`, `is_critical`
- Capabilities exposed: `ShipThruster`, `ShipPowerConsumer`, `ShipInventory`, etc. (gathered dynamically, not hardcoded)
- `ShipGrid`: occupancy dict, add/remove/replace transactions, neighbor lookup, connectivity queries, collision shape ownership

**Thrust & rotation:**
- Dot-product thruster allocation (each thruster: `local_dir.dot(desired_accel)`, clamped 0..1) — works regardless of layout
- Gyro torque: `torque = error * (max_torque / ANGULAR_EASE_WINDOW)`, scales with available torque (more gyros = faster turn)
- Dampeners: swap "desired direction" to "cancel velocity," same allocator

**Damage model:**
- Per-block health + material damage profile (kinetic, explosive, thermal, impact, structural)
- Blocks degrade/leak/misfire before destruction
- Impact damage: `impulse_energy - threshold * damage_scale`
- Connectivity check after every removal/destruction (flood fill from Core); detached sections become new ships

**Collision:** ship vs. terrain/ship both receive damage from same contact; impulse split by mass; high-speed impacts detected via swept prediction.

**Critical systems:**
- No Core: invalid assembly, can't control/save
- No cockpit/remote: can drift but can't accept pilot input
- No usable gyro: no rotation authority
- No usable propulsion: coast under gravity/drag
- Core destroyed: ship becomes wrecked, blocks salvageable/debris

**Phases:**
- Phase 1 (Alpha): ShipGrid, live builder (first-person), garage (inventory + manifest + craft queue), per-block health, Core connectivity, wrecked state, landing gear/clamp
- Phase 2: `ShipFuelSystem`, fuel tank, fuel-consuming thrusters, empty-fuel failure
- Phase 3: hull profiles, multi-cell blocks, cargo, assembler
- Phase 4: spaceflight, oxygen, airtight compartments, save/restore
- Phase 5: symmetry, blueprints, docking, weapons, advanced construction

**Current roadmap:** 
- Live ghost placement is working and validated (1st-person builder, not top-down)
- Collision + damage system designed but damage per impact not yet tuned
- Fuel/power interfaces designed; actual fuels/batteries not built
- Ship persistence (save/restore) not built (blocks, health, inventory, fuel all need saving)

---

### Player Character, Animation & Viewmodel System

**Current State:** Capsule placeholder with radial-gravity physics working. No rigging, no animation.

**Rigging workflow** (Blender → Godot):
1. Model low-poly humanoid in A-pose, matching building kit aesthetic
2. Rigify: add Human meta-rig, adjust to match proportions, Generate Rig (produces FK/IK control rig + `DEF-*` deform bones)
3. Skin mesh: Automatic Weights first pass, then manual weight-paint trouble spots (armpits, shoulders, etc.)
4. Animate: use Rigify control rig (animator-friendly) or retarget Mixamo
5. Bake down: `Bake Action` onto `DEF-*` bones only (drop control rig)
6. Export: same glTF pipeline as buildings; Rigify names don't auto-map, need one-time `BoneMap` setup in Godot
7. Godot: confirm `Skeleton3D` + `BoneMap`, wire up `AnimationTree`/`AnimationPlayer` for locomotion, layer weapon-grip `IKModifier3D` on top

**Roadmap:** Alpha gets capsule placeholder (prove loop is fun). Beta gets full rigging (multi-day investment).

**Animation sourcing:** don't hand-key locomotion — use Mixamo free library (walk/run/idle/jump/etc.) with community retargeter plugins. Custom animations (weapon-specific, cinematic) hand-authored in Blender.

**Weapon-grip IK:** `IKModifier3D` (native in Godot 4.6+) chains hand onto weapon grip point. Swap weapons, grip stays correct automatically.

**Viewmodel (hands/weapon in FPS view):** two techniques:
- **SubViewport + cull-mask:** separate `SubViewport` with own camera, dedicated cull-mask layer. Fully correct depth separation, costs extra render pass.
- **FOV-override shader:** shader rewrites `PROJECTION_MATRIX`, fakes depth separation. Cheaper (one pass), common in shipped FPS games, slightly hacky.

**Animation architecture:** Locomotion as `AnimationTree` state machine (idle/walk/run/jump/fall/crouch, signal-driven transitions). Weapon-hold poses layer on top via blending.

---

### Asset Generation Pipeline (Blender + Agent) — Beta

**Status:** Designed but not built.

**Goal:** replace placeholder blocks with proper low-poly buildings via parametric generation (not freeform generative 3D, which produces messy topology).

**Approach:** agent-driven Blender Python script (`bpy`). Generator assembles buildings from kit parameters: footprint size, wall height, roof style, window count, material zone. Modular composition (walls, roofs, floors, corners), matching Satisfactory aesthetic.

**Execution:** `blender --background --python generator.py -- <args>`. Script uses `bpy.ops`/`bmesh` to build mesh, exports directly with `bpy.ops.export_scene.gltf(export_format='GLB')`. Reuses Material ID → texture array scheme (buildings sample same atlas as terrain — consistent style, fewer draw calls).

**Known gotcha:** headless glTF exports sometimes don't carry textures correctly depending on Blender version/flags. Smoke-test (export one building, reimport to Godot, confirm materials) before building full generator.

---

### Save/Load System — Alpha (Designed) → Beta (Built)

**Current State:** Infrastructure ready, not wired. `VoxelStreamSQLite` built into godot_voxel, but not enabled.

**Needs to persist:**
- Terrain edits (via `VoxelStreamSQLite` — designed in, just call `save_modified_blocks()`)
- Building/structure state (position, rotation, health, inventory)
- Player progress (inventory, position, quests)
- Ship state (blocks, health, fuel, inventory, position, orientation)
- Once floating-origin lands: true double-precision positions + orbital elements (not render-relative offsets)

**SQLite setup:** Set `stream = VoxelStreamSQLite.new()` on `VoxelTerrain`, set `database_path`, call `save_modified_blocks()` periodically/on quit. Stores deltas only; base terrain regenerates from generator.

---

### Underground System — Scope 3

*Not yet planned at all.*

---

### Radiation System (Alternate Name for Radiation Threat)

*See Radiation Threat System section above — this was added to Alpha scope as a specific wave-pressure mechanism, not part of 1.0 Release scope. Scopes 1–5 defined; Scope 1 built and validated.*

---

### Audio System

*Not yet planned as its own system.* Only touchpoint: Atmosphere system's audio modulation (density-based attenuation, pressure-based wind/roar parameters).

**Candidate plugin (user-supplied 2026-09-09, not yet evaluated):**
`SpatialAudio3D` — https://store.godotengine.org/asset/claude/spatialaudio3d/

Worth evaluating when audio starts, because this game's audio is unusually
positional: turret fire and impacts at range, ships passing overhead, and
sound that has to attenuate with `PlanetPhysics.get_air_density()` and cut to
silence in vacuum. Check before adopting: whether it plays well with the
atmosphere density model above, and whether it assumes a world-Y-up listener
(a recurring failure mode for this project - see the sky shader and the
climate field, both of which broke on a sphere for exactly that reason).

---

### UI / UX System

**Current State:** Inventory UI, building UI, build tool, quest board, journal tech-tree, compact HUD. HUD auto-hides when any modal is open.

**Validated patterns:**
- One `CanvasLayer` (compact HUD) with `UiState` autoload registry — all modals call `UiState.set_open(id, bool)`, HUD just watches aggregate
- Build tool: top-down camera (orthographic for uniform screen-to-world mapping), live ghost preview, grid-vs-free placement, R-key rotation
- Inventory: slot-based grid + hand slots, unified click-to-carry/merge/swap via `SlotCarry` adapter pattern
- Quest system: 7-quest diamond (two roots, two branches, one final) generated from pure data, no hand-laid-out nodes

*More detailed UI work deferred past Alpha.*

---

### Multiplayer / Networking

**Status:** Not scoped in detail, confirmed future goal.

**Risk:** Zylann's voxel module lists multiplayer terrain sync as an open wishlist item (not solved). Shared terrain deformation across clients needs research.

**Projectile readiness:** Ballistics designed deterministic/step-based from day one (requirement for client-side prediction/rollback). **Current gap:** determinism not yet verified. Must test before 100s of simultaneous shells become normal.

---

## Implementation Patterns & Known Fixes

This section documents validated architectural decisions and bug fixes to avoid repeating them.

### Radial Planet Gravity on CharacterBody3D

Set `up_direction = (global_position - planet_center).normalized()` every physics frame before `move_and_slide()`. Track vertical speed separately from `velocity` (since `velocity.y` no longer means "vertical"). Gravity: `_vertical_speed -= GRAVITY * delta`. Body orientation: rebuild basis via `Basis.looking_at(tangent_forward, up)` each frame so character stays aligned to surface.

**Verified:** driven headless test (walk from pole to near opposite pole, sample alignment/radius every second). Stays glued to surface (39.6–40.5m vs nominal 40m), never tunnels.

### Building Placement on Curved Terrain

Three-tier resolution (`_resolve_build_placement()`):
1. **Foundation item:** snaps to nearby foundation's edge (copies exact basis to stay aligned), or free-places tangent to terrain
2. **Non-foundation building:** snaps to nearby foundation's top face (inherits orientation), or free-places tangent to terrain
3. **Ghost orientation recomputed every frame** from cursor's actual current position (not build-session entry snapshot), derived from `(cursor_pos - planet_center).normalized()` for tangent direction

**Why not cache snapshot:** once camera pans far from entry point, sphere curvature means tangent direction changes measurably; snapshot would put ghost sideways away from spawn.

**Validated:** driven test (orientation matches local radial at 4 spread points, basis dot products 1.0000 each; snapped foundations exact `Foundation.SIZE` apart at exact neighbor basis; full end-to-end placement round-trip).

### Conveyor Network Grid-Cell Lookup

`PipeNetwork` autoload: `Dictionary[Vector3i, Node]` keyed by `Vector3i(floori(pos))`. Segments register at placement, unregister at removal. O(1) neighbor queries.

**Why not FoundationNetwork:** pipes are axis-aligned; foundations aren't. No fixed grid basis for arbitrary rotations, so linear nearest-neighbor scan is simpler than inventing a rotated spatial dict.

**Fairness in mergers:** rotating cursor per upstream input; don't accept from current-favorite if it has nothing, accept next input. Verified: 3 inputs into 1 merger produce even 14/14/14 split over test run (not one starving).

### Projectile Ballistics — Hand-Integrated Physics

Semi-implicit Euler each tick: `velocity += (gravity_accel + drag_accel) * delta; position += velocity * delta`. 

Gravity: `PlanetPhysics.get_gravity_accel(pos)` (radial, shared with player).

Drag: `0.5 * air_density * Cd * cross_section * speed^2`, divided by mass for acceleration.

Hit detection: `PhysicsRayQueryParameters3D` swept raycast (prev-position to new-position), not point-in-time checks. Can't tunnel through thin targets.

**Why not RigidBody3D:** Godot's built-in gravity is single global vector (wrong for radial planets). Custom integration buys the same benefit + simplicity. Hand-integration also makes hit detection trivial.

**Verified:** driven test (re-derive expected velocity/position after one step, compare to real projectile, sub-cm tolerance; trajectory visibly curves under gravity; turret auto-fires and actually damages on-range targets only; ammo disable genuinely stops fire).

**Architectural gap:** main-design calls for pooled, data-oriented system (parallel position/velocity arrays). Current node-per-projectile will be expensive with 100s of live shells. Not a problem for Alpha; should be on radar for Beta tuning or once waves get large.

### Slot-Based Inventory with Backward Compatibility

Rewrote `Inventory` from flat `Dictionary` counter to real grid+hand slots, preserved existing call signatures (`get_count`, `add`, `try_remove`, `changed` signal) as thin wrappers. Result: processor, debug UI, ore logic need **zero changes**.

Generic slot addressing: `{"kind": "grid", "index": i}` / `{"kind": "hand", "side": "left"|"right"}`. One `get_slot`/`set_slot` implementation serves both.

**Verified:** existing systems using old `Inventory` API still work unchanged.

### Unified Click-To-Carry for All UI Screens

`SlotCarry` (`RefCounted`): one `click(container, index)` method with pick-up/merge/swap state machine. Driven through duck-typed container adapters:
- `InventorySlotAdapter` — player grid or hand slots
- `BuildingInventoryAdapter` — any Building's stacked inventory
- `BuildingModifierAdapter` — single-item modifier slots

Both inventory UI and building UI now use same adapter; no code duplication per screen.

**Verified:** driven test (swapping different stacks between player/building now works identically; partial placement into capacity-limited containers still clamps correctly; modifier slots go through same code path).

### Building Autocraft via Base Class Timer

Moved `Timer`, `_timer_callback`, auto-recipe logic out of `Processor` into `Building` base class. Every recipe-driven building (`Processor`, `Smelter`, `Constructor`) now gets it for free. Rotating cursor over multiple `auto_enabled` recipes so all recipes get a fair turn each frame (not just recipe 0).

**Verified:** driven test (Constructor's 4 recipes with 2 flagged auto both produced output, not just recipe 0).

### Per-Voxel Material Indexing

1. `VoxelFormat.new()`, `set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)`, assign to `terrain.format`
2. `VoxelMesherTransvoxel.texturing_mode = TEXTURES_SINGLE_S4`
3. Generator writes material index (0–255) per solid voxel into `CHANNEL_INDICES`
4. Shader unpacks `CUSTOM1.x` via `floatBitsToUint` + bitshifts, colors/textures per index

**Known bug:** default format is 16-bit (not 8-bit), causes mesher to silently emit all-zero `CUSTOM1` data. Must set explicit format first.

**Known gotcha:** `CHANNEL_WEIGHTS` doesn't accept `DEPTH_8_BIT`; only set indices depth, leave weights at default.

### Digging/Building via VoxelTool — Coordinate Spaces

`VoxelTool` mixes coordinate spaces per API:
- `raycast(from, dir, max_distance)` — world-space in/out
- `do_sphere(center, radius)` — **LOCAL (voxel-grid) space**, not world
- `do_sphere()` radius must be divided by terrain scale to get world-meter size

**Fix for scaled terrain:** `_local_radius(world_radius) = world_radius / terrain.scale.x`. Wrap all `do_sphere()` radius args with it.

**Verified:** isolated headless test (raycast and do_sphere behavior differs in 2 tests; mining now digs consistent depth, not 1–2 voxels).

### Querying Terrain Colliders vs. Voxel Data

Voxel data streams fast (every LOD has data). Physics colliders stream much slower (only LODs within `collision_lod_count`). 

**Spawn design:** don't resolve off `VoxelTool.raycast()` (voxel data exists long before colliders). Instead: park capsule above surface, loop until `intersect_ray()` against *physics* world finds a collider under spawn point. Frame-cap the loop so broken generator can't hang spawn.

**Why this matters:** voxel data existing doesn't mean collision exists; player can spawn, fall through planet if collision hasn't generated yet.

### Headless Testing Patterns

**Use real engine frames, not manual `_physics_process` calls:** `await get_tree().physics_frame` loops work; calling `_physics_process(dt)` directly doesn't (CharacterBody3D reads engine's actual physics delta, ignores the arg). Capped loops to avoid hanging.

**Frame count is not wall-clock time under headless:** `--quit-after N` counts render frames (uncapped, can be hundreds per second). Gate assertions on `Time.get_ticks_msec()` instead.

**Autoloads aren't available in `-s` mode:** use temporary wrapper scene pointing `run/main_scene` at it instead.

**Stale Godot processes lock GDExtension DLLs:** check `Get-Process | Where-Object { $_.ProcessName -like '*Godot*' }` and stop lingering instances before retry.

---

## Known Issues & Design Debt

### Must Fix Before Scale-Up

1. **Projectile Determinism Unverified**
   - Main-design requires: "pure function of (state, fixed delta), no per-frame randomness" for multiplayer prediction
   - Current implementation: not tested for determinism
   - Action: verify projectile `_physics_process` produces identical results given identical input state across runs (no hidden per-frame state or stochastic operations)

2. **Wave Pressure Models Conflict**
   - Main-design Slice 2: "wave pressure scales with base output/power draw (Mindustry-style)"
   - Radiation-threat system: waves spawn based on crystal signature tier, not power
   - Question: do both systems spawn waves (redundant), or does radiation replace power-based waves?
   - Action: clarify design intent — confirm relationship or decide which is primary

3. **Projectile System Architecture Mismatch**
   - Main-design: "pooled, data-oriented system stepping parallel position/velocity arrays"
   - Current: one `Node3D` per projectile with hand-integrated physics
   - Cost: will be expensive with 100+ simultaneous shells (rung B+ performance gate)
   - Action: document acceptance that single-node approach is Alpha-scoped; plan data-oriented refactor for Beta tuning if wave sizes grow

4. **WeaponDefinition Interface Not Locked**
   - Main-design: weapons are building pieces (one `WeaponDefinition` interface for all)
   - Ship-system: weapons are Phase 5, interface not yet designed
   - Risk: planet turrets (already with `AmmoType` + `compatible_ammo`) might diverge from ship weapons
   - Action: confirm `WeaponDefinition` + `AmmoType` contract works for both planet-mounted and ship-mounted weapons, or document why they diverge

### Should Clarify

1. **Atmospheric Drag Accuracy vs. Real Aiming**
   - Projectile firing solution (no-drag quadratic) deliberately diverges from actual flight (with drag)
   - Acceptable for Alpha / cinematic focus
   - Must verify aiming still works correctly on moving targets and across different altitudes on a sphere before declaring validated

2. **Floating Origin vs. Double-Precision Decision Gate**
   - Must be made deliberately at rung B/C (can't scale past safely without it)
   - Floating-origin is complex (re-center discipline on all systems)
   - Double-precision is simpler code but infrastructure cost (rebuild on updates)
   - Action: document the trade-off explicitly; don't assume floating-origin without considering double build

3. **Biome Implementation Dependency on Generator Rewrite**
   - Biome system is fully designed but can't be built until `VoxelGeneratorGraph` rewrite (uses `NODE_SPOTS_3D` for ore, surface rules for materials)
   - Current hand-written generator is the bottleneck
   - Action: plan graph rewrite as explicit prerequisite for Beta biome work

4. **Save System Wiring**
   - Infrastructure (SQLite) ready but not wired
   - Alpha scope called for it; should be second priority after generator rewrite for Beta

---

## Cross-Cutting Open Risks (Verify Before Large Time Investment)

- `VoxelLodTerrain` coordinate handling under camera-relative render offset (module internals you don't control) — needs early spike test
- Deferred/async collision queue design (custom scheduling needed, no built-in solution for staggering collision rebuilds)
- Blender headless glTF export texture fidelity (smoke-test before building full parametric generator)
- Double-precision build is maintenance tax (rebuild on every engine/addon update) — confirm acceptable before committing at rung C
- Volumetric cloud rendering (needed for shell-scatter cinematic) has no existing reference implementation — budget prototyping time, not just integration
- Multiplayer terrain sync unsolved in voxel module itself (Zylann's wishlist item) — research when multiplayer phase starts, don't assume it's free
- `NODE_SDF_SPHERE_HEIGHTMAP` projection (equirectangular vs. cube-face) unverified — test before rung C heightmap approach commits
- Terrain generation at higher LODs with thin biome bands under-sampled (LOD popping risk, mitigated by low climate-noise frequency, needs visual validation)

---

## Art Direction (Reference)

**See separate `art-direction-brief.md` for complete reference.** Summary:
- Readability over detail (silhouette-first design)
- Kit-of-parts aesthetic (bolted metal, consistent grammar)
- Neutral structural colors + signal accents per category (amber for processing, cyan for logistics, red for combat)
- Low-to-mid poly hard-surface
- Ore materials realistic (iron=grey, copper=brown, sulfur=yellow, coal=black, silica=pale sand)
- **Terrain/ore:** flat tileable albedo + roughness (not baked lighting)
- **Buildings:** distinct per-category silhouettes, not just color differentiation
- **Turrets:** gun reads slender/fast, cannon reads thick-barreled/heavy

---

## Notes for Future Developers

### When Scaling to Larger Planets (Rung B → C)

1. Raise `lod_count` (currently 5, needs ~10 for 2km, ~15 for 60km)
2. ~~Delete proxy sphere system~~ — **done 2026-09-07**, replaced by the scattering pass. At rung B/C instead retune `AtmosphereRenderer.sun_intensity`: it compensates for our bodies being ~200 m rather than planet-scale, so a much larger body needs a much smaller value.
3. Migrate generator to `VoxelGeneratorGraph` for performance + visual quality
4. Implement `VoxelStreamSQLite` persistence (infrastructure ready, needs wiring)
5. Build deferred collision queue (prevent frame spikes as physics meshes compile)
6. Test `VoxelLodTerrain` coordinate safety under camera-relative render offset (early spike before committing to large scale)
7. Make precision decision (floating-origin vs. double-precision build) before committing to 60km scale

### When Starting Multiplayer

1. Verify projectile `_physics_process` is deterministic (pure function, no per-frame randomness) before scaling to 100+ shells
2. Research voxel terrain sync in module (Zylann's wishlist item; plan for real work, not free integration)
3. Ensure all network-critical systems (projectiles, ships, player position) are frame-aware and use consistent coordinate space

### When Building Asset Pipeline

1. Smoke-test Blender headless glTF export (texture fidelity, material survival) before committing to parametric generator
2. Keep reference hand-written generator around (test diff against it during porting to graph)
3. Extract domain-warp, ridged-fbm, surface-rules as reusable `NODE_FUNCTION` subgraphs

---

## References & Sources

- [Minecraft world generation (density functions, splines)](https://minecraft.wiki/w/World_generation)
- [Space Engineers 2 devblogs (planets, voxel density)](https://blog.marekrosa.org/)
- [Veloren (open-source voxel game, Rust/Bevy)](https://veloren.net/)
- [GPU Gems 2 ch.16, Atmospheric Scattering](https://developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-16-accurate-atmospheric-scattering)
- [Godot large world coordinates](https://github.com/godotengine/godot-docs/blob/master/tutorials/physics/large_world_coordinates.rst)
- [Godot emulating double precision on GPU](https://godotengine.org/article/emulating-double-precision-gpu-render-large-worlds/)

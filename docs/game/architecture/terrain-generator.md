# Terrain generator foundation

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

### Phase 0 â€” Align units â€” **DONE 2026-09-09**

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

### Phase 1 â€” Heightmap-first base â€” **DONE 2026-09-09**

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

### Phase 2 â€” 3D detail layer (SE2's "voxel storages")

Overhangs, caves, arches and boulders applied on top of the heightmap base.
This is what makes the result genuinely 3D rather than 2.5D, and it is the
part SE1 could not do. Our generator is already 3D-capable - this is
re-pointing existing capability, not new machinery.

### Generator profiling â€” added 2026-09-09

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

### Phase 3 â€” `VoxelGeneratorGraph` port â€” **CORE DONE 2026-09-09**

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

### Phase 3 â€” original scope

**Deliberately after Phase 1, not before.** Once the heightmap carries the
shaping, the graph collapses to "sample image + add detail + surface rules,"
which is far easier to express in a branchless node graph than the current
multi-octave biome logic. Porting first would mean porting work Phase 1 then
deletes.

Budget 20-50x (no `FastNoise2` in this build; recompiling with it is the next
lever if still short). Hand-author the reference graph in the editor first -
the tuning is the quality - then port to a builder driven by `CelestialBody`.

### Phase 4 â€” Persistence and streaming â€” **DONE 2026-09-10**

Built as designed: the baked heightmap is the persistent base artifact, and
`VoxelStreamSQLite` stores **player edits only** (`save_generator_output =
false`). `Planet._attach_edit_stream()` points each body at
`user://saves/<slot>/terrain_<body>.sqlite`, keyed on the `CelestialBody`
resource filename so a second planet needs no new code. One 6 m dig came to 24
blocks.

The loading screen the user accepted on 2026-09-09 exists
(`scenes/loading_screen.tscn`) and is gated on `Player.is_spawn_resolved()` -
"terrain data exists here AND a collider was found" - rather than a timer, so it
covers exactly as long as generation actually takes. Currently ~5 s.

> **`save_modified_blocks()` is asynchronous.** It returns a
> `VoxelSaveCompletionTracker` and godot_voxel writes on worker threads.
> Quitting when the call returns loses every edit silently. Callers must poll
> `SaveManager.terrain_save_complete()`.

Full save system (world state, menus, slot management) is documented in
`gameplay-systems.md`; only the terrain half belongs here.

### Phase 5 â€” SE2 content parity (after the foundation is solid)

Dynamic voxel hardness (sand deforms softly, rock resists), material
transition masks with height information, volumetric water, biome scatter via
`VoxelInstancer`.

#### Readiness check â€” 2026-09-10

Capability audit against this build, not against the docs. **56 graph node
types are available**; the ones that matter here:

| Want | Node / class | Status |
|---|---|---|
| Biome scatter | `VoxelInstancer` + `VoxelInstanceGenerator` | **spiked, works** |
| Caves / overhangs | `NODE_SDF_SMOOTH_SUBTRACT`, `NODE_SDF_SMOOTH_UNION` | available, unused |
| Boulders | `NODE_SPOTS_3D` | available, unused |
| Slope for cliff rock | finite differences on the heightmap | possible, see below |
| Branchless selection | `NODE_SELECT`, `NODE_EXPRESSION` | available, unused |

**`VoxelInstancer` spike: scatter renders on our `VoxelLodTerrain` with the
graph generator.** `up_mode = UP_MODE_SPHERE` aligns instances to radial up, so
it is correct on a sphere with no extra work. `VoxelInstanceGenerator` already
has slope, height and noise filtering built in - and
`voxel_texture_filter_array` / `voxel_texture_filter_threshold`, which key
scatter **directly off the material weight layers the generator already
writes**. Biome-aware scatter therefore needs no new biome lookup; it is data
authoring, not machinery.

> **The spike's instance COUNTER read zero while the screen was full of
> instances.** It looked for `MultiMeshInstance3D` children; `VoxelInstancer`
> renders through the RenderingServer instead. Same shape as the
> `collider is StaticBody3D` failure in `roadmap.md` - a check that cannot
> detect success cannot measure anything. The screenshot is what settled it.

**Correction to the Phase 3 note: slope-driven cliff rock is NOT impossible.**
The claim was "no gradient node for the heightmap", and there genuinely is no
gradient node for `SDF_SPHERE_HEIGHTMAP` (`FAST_NOISE_GRADIENT_3D` only
differentiates noise). But slope can be taken by finite differences - sample the
heightmap at three or four nearby directions and difference them. That is a few
extra samples per voxel in compiled C++, not a blocker.

**Two prerequisites are still open, and both sit inside the Slice 1 definition
of done below:** cliff rock is an unported regression from the script
generator, and **Phase 2 (3D detail) was never built - the terrain is 2.5D**.
Nothing overhangs, and there are no caves. Phase 5 is content parity layered on
a foundation that is still missing its third dimension, so the sensible order is
cliff rock -> Phase 2 -> Phase 5 scatter.

---

## Direction change â€” procedural planets (decided 2026-09-10)

**In 1.0 Alpha, planets are generated procedurally.** Terrain therefore has to
work at any radius, any orbital distance, any seed - "it looks right on the home
planet" stops being a meaningful statement. That requirement is incompatible
with the current backbone and this is the moment it changes.

### Why the baked heightmap cannot survive

`tools/bake_planet_heightmap.py` is an OFFLINE numpy tool. **Measured: 68 s for
a 1024x512 map.** A 4096x2048 map (the resolution an 8 km planet needs) is 16x
the cells and wants 16x the droplets - roughly 18 minutes - and none of it can
run inside Godot. It is a per-planet art asset. It works today precisely because
there is exactly one hand-baked planet.

Resolution is the second wall. At 8 km radius the circumference is ~50 km; a
4096-wide equirect map is 12.3 m/px. Everything finer has to be procedural
anyway, which is already the Space Engineers 2 arrangement (coarse base, detail
layered on).

### What replaces it

Minecraft's approach, which is what the "material variance and natural
formations that never feel repetitive" target actually describes: **low-frequency
density fields mapped through splines**, no simulation anywhere.

- `continentalness`, an `erosion` PARAMETER (not a simulation), `peaks_valleys`
  and `weirdness`, each low-frequency noise sampled on the sphere direction.
- Each mapped through `NODE_CURVE`, which is in this build and is the same
  mechanism Minecraft's splines use.
- Combined into a surface radius offset; SDF is `|p| - (R + offset)`.

All compiled C++, no baked assets, instant for any planet at any radius.

**`PlanetProfile` derives terrain from physics rather than authoring.** Inputs
already exist in the codebase: `radius`, `seed`, irradiance (via
`StarBody.irradiance_at_distance` - orbital distance to equilibrium temperature
is free) and atmosphere density. Derived: relief as a FRACTION of radius, so
scale changes need no retuning; continent wavelength scaled to circumference, so
a bigger planet gets MORE continents rather than bigger ones; and a biome palette
chosen by temperature and atmosphere.

**The heightmap path stays** as an optional per-body override for a
hand-authored planet. It is no longer the backbone.

### Honest cost of this choice

**No hydraulic erosion simulation, so no true drainage networks** - no river
systems that provably flow downhill into each other. Ridged and billowed noise
through erosion splines approximates the look; it does not compute it. Minecraft
has the same limitation, which is why the look is achievable, but it is an
approximation and should not be described as anything else.

---

## Deferred, and recoverable later

Each of these has a known slot to come back to; none is blocked by the decisions
above.

**GPU erosion (restores real drainage networks).** Move the droplet simulation
from offline numpy to a Godot compute shader run once at world creation, behind
the loading screen the user already accepted. It would produce the base field
the splines consume, so it drops into the same place with the spline layer
unchanged. Deferred because it is a substantial piece of new machinery and was
not worth building in the same pass as the scale bump and the 3D detail layer.

**Volumetric water.** Needs a second SDF channel or a dedicated surface pass,
plus buoyancy and swimming on the gameplay side. Blocked on nothing technical;
it is simply a large system. Sea level already exists as a concept
(`PlanetHeightmap.sea_level`) and the density fields will produce basins to put
it in.

**Biome scatter (`VoxelInstancer`).** **SPIKED AND WORKING, DELIBERATELY LEFT
OFF.** See the readiness check above - scatter renders correctly with
`UP_MODE_SPHERE` and can key off the material weight layers directly. It is not
enabled because the only meshes available are placeholder boxes, and a planet
covered in ugly boxes is worse than a bare one. Turn it on when the Blender asset
pipeline produces real props. Nothing needs to be rebuilt to do so.

**Dynamic voxel hardness.** Sand deforms softly, rock resists. This is gameplay
code in the dig path (`player.gd` already resolves the dominant material via
`_dominant_material_at`), not generator work, so it is independent of everything
here.

**Material transition masks with height information.** Wants the PBR material
work to land first, since it is a shader-side blend refinement rather than a
generator feature.

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

## Phase 3 complete - graph generator (2026-09-10)

`PlanetGraphGenerator.build(body, voxel_scale)` builds a `VoxelGeneratorGraph`
in code from a `CelestialBody`. It is the default; `Planet.use_graph_generator`
= false falls back to `ore_generator.gd`, which stays the reference
implementation.

**Time to first walkable ground: 40-60 s -> 4.9 s.** Head-to-head on identical
blocks: 61x shape-only, 13x with noise and materials.

**No branching in a graph.** The script generator picks a biome by
nearest-neighbour in climate space and an ore by rarest-first priority - both
control flow. The port gives every material its own soft membership and its own
`OutputWeight` layer, and the mesher keeps the strongest four per voxel. Same
result, no branches, and biome borders blend instead of stepping.

Ore veins come from `|noise|` near zero (a connected surface, so veins rather
than round blobs), gated by a depth window and by a low-frequency region field
split into one band per ore - which makes deposits exclusive with no priority
chain. `Spots3D` was tried first and returned all zeros in a probe; not worth
reverse-engineering when the noise approach was already proven.

Verified: 7 distinct materials across a 140-direction sample (all four biome
stones, ores, bedrock); landing radius 490.9 matches the script generator's
491.0; smoke clean.

**Node gotchas, all silent-failure shaped:**
- `SdfSphere` takes radius as INPUT PORT 3, not a parameter - it has none.
  `set_node_param` errors and leaves the default, silently producing a
  wrong-sized planet. Only bodies without a heightmap take that path.
- `FastNoise3D` needs `ZN_FastNoiseLite`, not Godot's `FastNoiseLite`.
- `SdfSphereHeightmap` reads ONE channel, so the RG-packed baked PNG must be
  converted to `FORMAT_RF` first (~80-110 ms once at build).
- `Planet` preloads the generator, so the generator must not read
  `Planet.VOXEL_SCALE`. Godot reports that cycle as a parse error in an
  unrelated file.

**Not ported:** slope-driven cliff rock. It needs a surface gradient, and the
graph has no gradient node for the heightmap - it would take extra offset
samples. Everything else from the script generator is in.

---

## Built 2026-09-11 — procedural shape, 8 km scale, cliffs, caves, logging

### Diagnostics first: `TerrainLog`

`scripts/world/terrain_log.gd`. Off by default, one bool test when off.

    godot --path . <scene> -- --terrain-log            # profile, graph, spawn, census
    godot --path . <scene> -- --terrain-log --terrain-cost   # + us/voxel

Writes `user://logs/terrain.log`, flushed every line (the runs worth
investigating are the ones that hang, and a buffered log loses exactly the tail
that explains why). It reports the derived profile, graph node count and compile
result, streaming config, a **material census over the whole sphere**, spawn
progress every second with the live data-block count, and time to playable.

This exists because every terrain question up to now was answered by writing a
throwaway harness scene. Those measured a slightly different thing each time and
none survived the session. `--terrain-cost` is separate from `--terrain-log`
because it is not an observation: it generates blocks purely to time them, and
measured **8.5 s per body** at 8 km — left on by default it would dominate the
load time it is meant to report.

### Scale: 8 km radius

| | before | after |
|---|---|---|
| Home planet radius | 500 vox | **8000 vox (16 km across)** |
| Moon | 300 @ 2750 | 2200 @ 44000 |
| Star | 440 @ 11 km | 7040 @ 176 km |
| `lod_count` / `view_distance` | 5 / 1024 vox | **12 / 40000 vox** |
| Relief | 36 m | **279 m** |
| Time to playable | 4.9 s | **7.3 s** (11.7 s with caves) |

Sun disc stays 4.58 deg and star pull stays 0.500% of surface gravity — the two
values the previous scale attempt validated. `REFERENCE_RADIUS_WORLD` moved to
8000 so surface gravity stays at 1.2 m/s^2.

> **The atmosphere had a scale bug that looked like a terrain bug.** At 8 km both
> the surface and the view from 3 km rendered as flat white. The scattering
> constant was calibrated on a 500 m body; optical path scales with radius, so
> the integral ran 16x long. Fixed by scaling each body's `scattering_energy` by
> `500 / radius` — **per body**, because a moon and a planet in one frame have
> different radii and no single global factor is right for both. Same class of
> bug as the noise frequencies: a constant calibrated at one scale is silently
> wrong at another.

### Cliff rock — ported, and what it costs

Slope by finite differences, since no gradient node exists for a composed field.
**Measured in-process** (`debug_measure_microseconds_per_voxel`, 3 interleaved
reps, variance under 3%):

| | us/voxel | vs base |
|---|---|---|
| base | 6.24 | — |
| + cliff, differencing the WHOLE height chain | 13.33 | **2.14x** |
| + cliff, differencing only the RIDGE term | 8.29 | **1.33x** |
| + caves | 9.70 | 1.55x |

Differencing everything paid 2.14x to differentiate two terms that barely
steepen anything — continents are smooth by construction and the detail octave
is finer than a cliff mask resolves. Narrowing it to the ridged mountain term
alone gave the same mask for a third of the cost.

Thresholds tuned against the census rather than guessed: 0.35/1.1 produced 39.6%
cliff, 1.2/3.0 produced 4.2%, **0.8/2.2 produced 12.9%** — matching the script
generator's ~15% target.

> **A false performance finding, caught by a control run.** The first cliff
> measurement showed 60 s and no walkable ground, which read as "finite
> differences are unaffordable". The log showed `data_blocks=0` and a compile
> error: one patch had replaced the region an earlier patch inserted into,
> deleting `_build_slope_mask`. The A/B control failed identically, which is what
> proved it was not the cliff cost. **The instrument must be run against a
> known-good config first** — the same rule the collider-test failure already
> established, re-learned because end-to-end timing was used where an in-process
> A/B was available.

### Caves — Phase 2, the 3D detail layer

`_carve_caves()`. Two noise fields thresholded and **intersected**: a single
`|noise| < w` region is a connected sheet through the rock and reads as a
collapsed quarry. Intersecting two gives tubes, because a point must be near
both zero-sets at once. Sampled on **world position, not sphere direction** —
every other field here is direction-sampled because it describes a surface, but
a direction-sampled cave is one identical shaft repeated to the core.

Faded out near the surface (or the crust becomes lace and the player falls
through on spawn) and above bedrock depth. `SDF_SMOOTH_SUBTRACT` rounds the
entrances.

This is what makes the terrain genuinely 3D: a radial height field has exactly
one surface per direction and can never overhang.

### Biome coverage — a silent default

The authored biomes' (temperature, roughness) boxes **do not tile the unit
square**. Points in the gaps had every biome at weight zero and fell through to
material index 0 — measured at **83% of the planet**, a generator quietly
painting most of the world in a default.

Replaced the box test with a falloff from each biome's centre
(`NODE_DISTANCE_2D`), which always resolves because some biome is always
nearest. That restores the script generator's "nearest biome in climate space"
rule without a branch.

> **Ranking matters, not just magnitude.** With coverage fixed, every ore
> disappeared from the census: `TEXTURES_MIXEL4_S4` keeps only the four strongest
> weights, and four biomes plus bedrock filled every slot. Biome stone is now
> capped at 0.7 so a full-strength vein always outranks it.

### Current census at 8 km

    surface on 232/240 dirs, radius 7769..8137
    stone 40% | cliffrock 12.9% | crystalfld 12.1% | sulfurflat 6.7% | frozen 1.7%

The 8 directions without a surface are a census limitation, not a terrain fault:
bisection assumes one SDF crossing along a ray, and a cave can produce several.

### Not done

- **PBR materials.** Still the debug shader. This is the next piece of work and
  the reason the surface reads as washed-out grey in captures.
- Regolith (index 0) wins ~40% of the surface. Its climate centre sits in the
  middle of the square, so it legitimately owns the largest cell — a palette
  authoring matter, not a generator fault, and it becomes moot once palettes are
  generated per planet.

---

## Surface materials and landforms — 2026-09-11 (second pass)

### Materials are data now, not shader branches

`SurfaceStyle` (resource) -> `SurfacePalette` (builds a 16-slot table from ONE
body's biomes and ores) -> `Planet._build_surface_material()` (duplicates the
material per body and uploads that table).

The shader's `if (idx == 7) return vec4(...)` chain is gone. It worked while
there was one authored planet; it cannot survive procedural generation, where a
world invents its own biome set and nobody is there to add a branch. Two planets
can now paint the same material INDEX differently, which is what makes biomes
mixable per planet rather than global.

`SurfaceStyle` carries albedo, roughness, metallic, specular, bump strength and
scale, fracture strength, dust gain and cavity strength. A generated planet fills
these the same way an authored one does.

### PBR is complete now — it was not before

> **Defining `light()` overrides Godot's ENTIRE lighting pipeline, not just the
> diffuse half.** The first version wrote only `DIFFUSE_LIGHT`, which silently
> removed every specular highlight from the terrain. `ROUGHNESS` was still being
> set and still fed the diffuse term, so the omission was invisible in code and
> nearly invisible on matte rock - it only shows on ice and crystal, where the
> missing sheen is the entire material.

Now Oren-Nayar diffuse + GGX specular (Smith visibility, Schlick Fresnel), with
`METALLIC` and `SPECULAR` actually set per material.

Oren-Nayar rather than Lambert because Lambert models a SMOOTH surface and falls
off as cos(theta) - which is why untextured terrain reads as a shiny sphere with
a soft terminator. Dust and rough rock are self-shadowing microfacets: bright
toward grazing angles, hard terminator. That flat-lit quality is a large part of
why lunar photography looks the way it does and no albedo work reproduces it.

Two gotchas worth keeping:
- **No `1.0 / PI` in `light()`.** Godot folds it into `LIGHT_COLOR` already.
  Dividing again made the planet ~3x too dark, which looked exactly like an
  albedo problem and nearly got "fixed" by brightening the rock.
- **`SPECULAR` cannot be read inside `light()`** (fragment-only output), so F0
  uses the standard 0.04 dielectric. Between two dielectrics it is ROUGHNESS
  that decides how a highlight reads anyway, and that IS per-material.

### The aliasing bug that survived five wrong fixes

Procedural noise has no mipmaps, so octave count has to follow the pixel
footprint. The formula was:

    lod = log2(max(pixel_world * 2.0 / bump_scale, 1.0))
    active_octaves = 6.0 - lod

That is the correct expression with **the ratio inverted**, then clamped at 1 -
so whenever features were near pixel size the log clamped to zero and it
evaluated all six octaves anyway, down to centimetre detail on a decimetre
pixel. Correct form:

    resolvable = log2(max(bump_scale / (2.0 * pixel_world), 1.0))
    active_octaves = clamp(resolvable, 1.0, 6.0)

This is what was producing the heavy stipple over every mid-distance slope. It
survived a stronger grazing fade, a distance-based fade, an MSAA pass and two
shadow-bias changes, because all of those were treating the symptom.

Related, and both real:
- **Fade on PIXEL FOOTPRINT, not camera distance.** Distance ignores view angle,
  and ground seen at a grazing angle has a huge footprint while still being
  close. `length(dFdx(world_pos))` IS the footprint.
- **Quintic, not cubic, noise interpolation.** Cubic smoothstep leaves a
  discontinuous second derivative at lattice boundaries, and the
  derivative-based normals turn that into a faint grid over the whole surface.

### MSAA was missing entirely

Terrain at range is sub-pixel triangles against a black sky. Without
multisampling those sparkle as edges flicker in and out - which looks exactly
like a shader artifact. 4x MSAA + FXAA are now set in `project.godot`. A
geometry problem needs a geometry-level fix; no amount of shading work touched it.

### Landforms: concentrate the relief budget

The terrain was a smooth dome because the relief budget was spread evenly over
the whole planet. Real mountains are **belts** - they sit on plate boundaries and
run in lines - and that is also what makes a realistic global ratio compatible
with dramatic local relief. Earth is 0.31% peak-to-trough globally but the Andes
rise 4 km over 50.

So: a low-frequency ridged `belt` field gates the mountain term through a curve
with a long dead zone (nothing below ~0.45), the erosion curve falls away much
faster than before, and the continent curve has long flat runs at BOTH ends -
basin floor and inland plateau. With mountains confined to a small fraction of
the surface, `PEAKS_SHARE` could go from 0.18 to **1.15** - taller than the
planet's whole nominal relief, locally - without moving the average at all.

Detail now follows both erosion AND the belt, so a plain is no longer exactly as
bumpy as a mountainside.

### Measurements

| | before this pass | after |
|---|---|---|
| Generation | 30.89 us/voxel | **6.88 us/voxel** |
| Time to playable | 45.4 s (caves) / 13.1 s | ~14-15 s |
| Relief exaggeration | 12x Earth | **6.0x** (planet), ~29x (moon) |
| Measured band | understated at 225 vs 338 real | measured per body, 101 vox |

Caves are OFF (`Planet.caves_enabled`). They work and the ceiling now scales with
bore, but they cost 45.4 s against 13.1 s and are not worth optimising yet.

### A methodology note

> A scripted edit used the pattern `lod_count = \d+`, which also matches the
> tail of **`collision_lod_count = 1`** and quietly set it to 12. Collision then
> generated at every LOD, so spawn resolved in 0.4 s against a coarse-LOD
> collider at the wrong radius - and several measurements taken in that window
> were meaningless. The project rule "assert the anchor matched" is not enough on
> its own: an anchor can match somewhere you did not intend. Anchor on the whole
> line, or assert the match COUNT.

---

## Textured materials + rock-scale geometry - 2026-09-11 (third pass)

### Procedural materials replaced with baked PBR textures

The old material evaluated **seven fbm fields per fragment**, each up to six
octaves of eight hash lookups - roughly 300 hash operations per pixel. That was
simultaneously the frame-rate problem (20-30 fps near the ground) and the
quality ceiling: value noise can make mottling, it cannot make rock. Texture
data is cheaper AND better, and those are the same fact.

**Measured: 20-30 fps -> 55-60 fps** (vsync-capped) at every framing from eye
level to 1 km. Remaining 7-25 fps entries are streaming hitches during LOD
meshing, not steady state.

Pipeline: `tools/bake_surface_textures.py` turns a generated photo into a tiling
PBR set. Source images come from local Flux.2 Klein via ComfyUI.

    <name>_alb.png   RGB = albedo (de-lit), A = roughness
    <name>_nrm.png   RG  = normal XY,       B = occlusion, A = height

Two RGBA textures, not four RGB ones, because sample count is the frame budget.

### What the baker has to do, and why

**An AI-generated rock image is not an albedo map.** It has lighting baked in,
so using it directly double-lights the surface - the generator's sun multiplied
by the engine's. De-lighting DIVIDES out low-frequency luminance rather than
subtracting it, because lighting is multiplicative; subtraction lifts shadows to
grey and looks washed.

> **Seamless tiling: the first implementation mirrored.** It rolled the image and
> blended each seam strip against a FLIPPED COPY OF ITSELF - mirroring by
> another name - producing exactly the bilateral symmetry its own docstring
> claimed to avoid, a visible cross through the middle of every tile. Writing
> the right intent in a comment does not make the code do it. Replaced with an
> edge cross-fade that crops the spent band: tiles exactly, no symmetry.

> **AO must not reach zero.** Every map baked out at `occlusion min 0.000`.
> Ambient occlusion is the fraction of sky a point can see, and a
> millimetre-deep pit in regolith still sees most of it - an AO map reaching 0
> claims the crevice is sealed, and crushes all cavity detail to black the
> moment the surface leaves direct sun. Floored at 0.45.

### Shader: triplanar, texture arrays, top-two blending

Voxel surfaces have **no UV parameterisation at all** - Transvoxel emits
arbitrary polygons from a density field. World-space triplanar is the standard
answer and has the useful property that digging produces correctly textured new
faces for free.

Texture ARRAYS indexed by material id, so the four indices the mesher emits can
be looked up without a branch per material - the same reason the palette exists.

**Only the top TWO materials are sampled.** Four layers triplanar is 24 fetches
per fragment; two is 12, and the third and fourth weights are almost always
negligible. This is the single biggest lever on the cost of this shader.

Blending between the two is **height-aware**: whichever surface stands taller at
a point wins the contested band. A linear crossfade between two rock textures
looks like a dissolve; this follows cracks and grain. It also fixed the blocky
material boundaries visible at LOD transitions, where weights interpolate across
coarse vertices.

### Rock-scale geometry: the band that was missing

Close-up terrain read as soft no matter how good the material got, because
**there was no terrain band at rock scale at all**. The finest layer was
`detail` at ~90 m features - from eye level that is a hillside, not a rock, so
there was no geometry to catch the light.

Added a band sized in METRES, not as a multiple of anything: 7 m features, 2.6 m
relief. It is the one band that must read at human scale on a 300 m moon and a
16 km planet alike, so unlike every other band it deliberately does not scale
with the body. Also sized against the 1 m voxel - below ~4 m the mesher rounds
features into mush.

> **`fractal_weighted_strength` must be 0 here, not 0.55.** That parameter
> weights each octave by the strength of the one below it, which makes
> ridgelines COHERENT and CONTINUOUS across scales. That is exactly right for
> mountain belts (the peaks band uses 0.6 for that reason) and exactly wrong for
> broken rock: at a single dominant frequency it lines the creases up into
> parallel corrugations and the hillside read as a washboard. Confirmed by A/B -
> disabling the band removed the corrugation and nothing else.

Domain warp is the better tool for that regularity, but measured **+6.4 to +8.8
us/voxel against +1 to +2 for the ridged octaves**. A third octave at an
irrational lacunarity buys most of the irregularity for a quarter of the price.

### Generator cost, measured clean

| config | us/voxel |
|---|---|
| full (cliff rock on, caves off) | **8.06** |
| no rock band | 7.38 |
| no cliff rock | 7.04 |
| neither | 6.39 |

The rock band costs **0.68 us** - not the 13 us an earlier run reported.

> **Every timing taken while ComfyUI was generating was garbage.** The same
> config measured 30.71 us during generation and 7.38 us after. Texture
> generation and the engine share one GPU and CPU. Interleaved A/B within a
> single contaminated run still gave the correct RELATIVE answer (warp is
> expensive), which is what made the right decision possible from bad absolute
> numbers - but the absolutes were off by 4x. Stop background generation before
> measuring, and re-check anything measured alongside it.

### Terracing removed

`STEPIFY` on a radial height field produces **topographic contour rings** -
contouring a dome gives concentric circles by construction. Not a tuning
problem: at any step size it reads as a contour map, and because it quantises
the summed height it fires at every scale, including across a 2 m dug rock face
where it looked machined. `MESA_STEP_SHARE` is parked at 0 and the block
early-outs.

A real mesa is a few benches where hard layers resisted erosion. Rebuilding it
needs step boundaries tied to a rock-layer field with its own thickness, not to
the height value itself.

### Godot gotcha

**A changed PNG does not reimport on its own in a headless run.** New 1024px
maps were served as the previous 881px import, and the mismatch killed rendering
silently - the harness printed "playable" and exited before any capture, with no
error. Delete `*.import` and run `--headless --editor --quit` after re-baking.

### Blocky patches and bright contour lines - the weight-slot problem

Zooming in showed pale blocky patches with hard stair-step edges, and bright
sinuous lines following the contours. Both were the same cause, and it is worth
understanding because it constrains how many materials a planet can show.

`TEXTURES_MIXEL4_S4` keeps the FOUR strongest weights per voxel. Their INDICES
are `flat` in the shader - index values cannot be interpolated, so wherever the
surviving set of four changes there is a hard seam. At LOD the index channel is
downsampled NEAREST-NEIGHBOUR (averaging material ids is meaningless), so every
seam becomes a block whose size grows with LOD level.

The generator writes up to **twelve** weight layers: bedrock, ground, cliff rock,
four biomes and six ores. Measured along 400 m of surface:

    BEFORE:  cliff rock present in 76% of samples
             frozen present in 22%,  regolith only 24%
             index set changed every ~11 m

Cliff rock was present nearly everywhere at a weight far too low to read as
cliff but high enough to hold a slot, and it is much brighter than regolith
(0.505 vs 0.404) - that was the bright banding. The pale patches were the frozen
biome's boundaries, blocked up by index downsampling.

Three changes, all aimed at "fewer materials present at once":

1. **`_cutoff()`** drives any weight below 0.22 to exactly zero before it is
   written, so a material cannot hold a slot it does not deserve.
2. **Cliff rock only on real cliffs** - slope thresholds raised from 0.8/2.2 to
   1.7/3.4.
3. **`BIOME_INFLUENCE` 0.5 -> 0.32**, so one biome dominates locally instead of
   three or four overlapping everywhere.

    AFTER:   cliff rock present in 37%
             frozen 12%,  regolith dominant at 67%
             index set changed every ~15 m

> **The reference ground is ONE material with variation, not a patchwork.** That
> is not only an art-direction observation - it is what the mesher's four-slot
> limit is built for. A planet that tries to show six materials in one square
> metre gets blocks, whatever the shader does.

---

## What the terrain is built on - decided 2026-09-11

### The mistake this replaces

The height field had grown to **eight noise bands summed together**, each pushed
through a hand-tuned spline: continentalness, erosion, belt, peaks, craters,
talus, mesa terracing, detail, rock. That is not a model of anything. It was
parameters being jiggled until a screenshot looked acceptable, and it produced a
specific recurring artifact that took four separate misdiagnoses to see as one
thing:

> **A spline with a steep knee applied to a smooth field draws a visible band
> along that field's level set.** `talus_curve` was a bump on the erosion field -
> a literal contour band. `crater_curve` on a spots field drew concentric rings.
> `STEPIFY` on a radial height field drew topographic contours. The cliff slope
> mask drew bands along iso-slope lines. Four sources of "those lines", one
> mistake repeated. Each was tuned individually as if it were its own bug.

### What VRAGE3 / Space Engineers 2 actually does

Researched rather than assumed ([SE2 VS2 announcement](https://2.spaceengineersgame.com/space-engineers-2-vs2-planets-survival-foundations-live-now/),
[VRAGE3 wiki](https://spaceengineers2.wiki.gg/wiki/VRAGE3)):

- A **planetary heightmap** provides the landform. Deliberately 2.5D.
- Full 3D comes from **spawning small voxel storages of overhangs and boulders**
  throughout the world, placed by the generator "in natural locations to enhance
  the shapes of mountains, hills, flat areas and canyons".
- **Triplanar material projection**, blended by face angle.
- Material transitions use a **height-information mask** spanning multiple
  voxels and triangles, rather than blending within a single voxel.
- Dynamic hardness per material.

**The load-bearing insight: the sharp, ragged, overhanging rock is PLACED
GEOMETRY, not more noise.** A height field has exactly one surface per direction
and cannot overhang at any octave count. Every band added to fake it only drew
more contour lines.

### The shape now

Four additive bands, each about a quarter the wavelength of the one above, plus
two fields used only as multiplicative gates (erosion, belt - gates have no
knee, so they draw no bands):

| band | features | role |
|---|---|---|
| continents | ~1600 m | where land is high or low |
| peaks | ~380 m | mountains, belt-gated so ranges are places |
| detail | ~90 m | the roll between the two |
| rock | ~7 m | metre-scale relief, gated to broken ground |

Craters, talus and terracing are gone. The plains are deliberately smooth,
because that is what boulders sit on.

### Materials: one, for now

Ores and all but one biome are disabled on both bodies, and cliff rock is off.
Getting one ground material right beats jiggling eight at once - and the mesher's
four-slot limit means a planet showing six materials per square metre gets blocky
seams whatever the shader does.

### Diagnostics, because screenshots lie

Both of the last two artifacts were misdiagnosed from beauty renders. Dark
patches in the terrain were read as mesh holes - including once as "sky showing
through", which was the atmosphere tinting them. They were neither.

Two instruments now answer these directly:

- **`_log_material_coverage()`** (in the terrain log) reports the fraction of
  surface samples with NO material written, the weakest total weight, and which
  materials are present. It found **34.0% of the surface had zero weight**.
- **`debug_view` on the terrain shader**, driven by
  `--debug-view=N` on the dev harness: 1 = total vertex weight (black means no
  material), 2 = material index, 3 = triplanar blend axes, 4 = geometric normal,
  5 = flat white to isolate geometry.

> **The coverage bug itself is worth keeping in mind.** Biome weights are
> normalised by dividing by their sum, which only guarantees coverage if
> something is non-zero. With a single biome whose falloff genuinely reaches
> zero, the sum is zero and every weight normalises to zero. Fixed with a small
> floor on each biome weight, making the set a true partition of unity
> regardless of palette size or influence radius. **0% uncovered after.**

### Next, in order

1. **Boulders and ragged rock as placed geometry** - the SE2 model. This is what
   the removed noise bands were failing to fake.
2. **Overhangs** - same mechanism; a height field cannot do it.
3. Lighting.

> **No programmer art in scatter.** Placeholder boxes were why scatter was
> disabled in the first place, and a planet covered in grey boxes is worse than a
> bare one. Rock meshes come from real modelling (Blender), not from primitives.

---

## GPU erosion: terrain stops being noise - 2026-09-11

### What changed

The landform no longer comes from summed noise. A hydraulically eroded
heightmap is baked **on the GPU at load**, and the noise bands are demoted to
surface detail on top of it. That is the VRAGE3 arrangement, with the one
difference that theirs ship pre-baked per planet and ours are generated from a
seed, so the bake moved to runtime.

`scripts/world/erosion_baker.gd` + `shaders/erosion/{generate,droplet,thermal}.glsl`.

### Why this and not more noise

Noise produces a field whose statistics are identical everywhere. Erosion
produces **causes**: water runs downhill, cuts where it is fast, drops what it
carries where it slows. That is what makes valleys connect to each other, ridges
sharpen between them, and sediment fan out at the foot of slopes.

The previous generator stacked eight noise bands trying to imitate those
features and still read as a smooth ocean from altitude, because that is what
band-limited noise looks like at every scale. Worse, each imitation was a spline
with a steep knee on a smooth field, and **a steep curve on a smooth field paints
that field's level set** - which is where all the mystery contour lines came
from.

### Measured cost

| | |
|---|---|
| 2048x1024, 4.6M droplets, 40 thermal passes | **~600 ms per planet** |
| of which base fBm | 60 ms |
| of which erosion | 250 ms |
| of which readback + normalise | 280 ms |
| Load to walkable (was 13-14 s with noise shape) | **6.8-8.3 s** |

Cheap enough to run at every load, so there is no disk cache and no cache
invalidation to get wrong. 2048x1024 is ~24 m per texel on an 8 km planet;
everything finer comes from the generator's rock band, which is exactly the
coarse-base-plus-detail split VRAGE3 uses.

### Two processes, both needed

- **Hydraulic** (`droplet.glsl`) cuts valleys and drainage networks. One
  invocation per droplet; height is fixed-point in an integer image because GLSL
  has no float image atomics and droplets genuinely collide. The remaining races
  are benign - erosion is stochastic over millions of droplets, and serialising
  would cost far more than it buys.
- **Thermal** (`thermal.glsl`) relaxes slopes past the angle of repose, which is
  what produces talus aprons and flat-topped plateaus. Hydraulic alone leaves
  unnaturally steep walls standing. Gather rather than scatter, so no atomics and
  order-independent.

They are interleaved in batches rather than run in sequence, so slopes relax as
they are cut - which is what real weathering does.

### Traps paid for

> **There is no GPU context in a headless Godot run.** `create_local_rendering_device()`
> returns null, so none of this can be exercised with `--headless`. Any test of
> erosion must run windowed.

> **Droplets must be spawned uniformly over the SPHERE, not over the map.** An
> equirectangular row near a pole represents far less real surface than one at
> the equator, so uniform (u,v) spawning over-erodes the poles. The first fix was
> to taper erosion strength by latitude, which traded that for a visible
> horizontal band right around the planet where the taper kicked in.
> `lat = asin(1 - 2u)` removes the problem instead of masking it, and needs no
> taper at all.

> **`.glsl` files must be imported before `load()` will return an RDShaderFile.**
> A fresh shader silently fails to load until `--headless --editor --quit` has
> run.

### Where this leaves the terrain

Working: real drainage networks, connected valleys, sharpened divides, talus.
0% of the surface unmaterialed, 54-62 fps, ~7 s to walkable.

**Still missing, and not solvable by the heightmap:** ragged rock, boulders and
overhangs. A heightmap has one surface per direction and cannot overhang at any
resolution. Those are placed voxel geometry - the other half of the VRAGE3 model
and the next piece of work.

**Relief is realistic, which means gentle.** At 8 km radius and 6x Earth's ratio
the planet carries ~149 m of relief, and from 1 km altitude that reads as gentle
undulation because that is what those numbers mean. Dramatic silhouettes need
either a larger exaggeration or a smaller body - a spec decision, not a bug.

### Getting mountains and plateaus out of the erosion

The first eroded maps produced smooth blobs with thin ridges and no landform.
Three causes, all in how the bake was set up rather than in the erosion itself:

1. **Over-eroding.** `erode_rate 0.45` with 2.2 droplets per cell planes the
   masses down. Water then has nothing left to carve and the field averages
   toward its mean.
2. **No mass to carve.** A plain fBm base has the same amplitude everywhere, so
   there are no distinct uplands. A redistribution curve applied to the base
   BEFORE erosion fixes this - and note it is NOT the mistake of splining the
   final field, because erosion then carves through those level sets rather than
   leaving them visible as contour bands.
3. **Not enough thermal erosion.** This is what makes a plateau: hydraulic
   erosion cuts the escarpment, thermal relaxes it to an angle of repose and
   piles talus at its foot. At 40 passes with a small talus the tops never
   flattened. 90 passes at 0.0065 turns eroded lumps into mesas.

Settings live in `ErosionBaker.Settings` as the "e_deep" set. ~700 ms.

> **Judge bakes from a HILLSHADE, never from raw height.** A greyscale height map
> cannot distinguish a plateau from a blob - both are mid-grey patches - and an
> over-eroded map was promoted to default on exactly that mistake.
> `scripts/dev/erosion_sweep.gd` bakes several parameter sets and writes shaded
> relief with a low sun, plus slope statistics (mean and p95), because slope is
> the number that separates a mountain from a swell where height SD does not.
> A sweep of five is faster than one game load.

> **THE SPAWN WAS AT THE NORTH POLE.** `(0, 8400, 0)` is where an
> equirectangular map's longitude texels all converge AND where every
> direction-sampled noise field hits a lattice extremum. Every capture taken
> during this work was of the single worst-distorted point on the planet, and it
> produced radial striations that were repeatedly mistaken for shading and LOD
> artifacts. Moved to a mid-latitude, non-axis-aligned direction. Anything that
> samples "the terrain near the player" inherits this - check the spawn before
> trusting a capture.

Note that a mesa TOP is flat, so a capture taken standing on one shows flat
ground and says nothing about whether the generator produces mesas. The
hillshaded world map is the evidence; the in-game view is one sample of it.

### Why the terrain read as flat: it was arithmetic, not tuning

Erosion was producing correct landforms and the planet still looked like a
smooth ocean. The cause was not the generator.

**The steepest slope a heightmap can express is (relief per texel) / (metres per
texel).** On an 8 km planet with a 2048-wide equirectangular map, one texel is
24.5 m of arc, and the measured p95 height gradient is 0.0248 normalised units
per texel:

| map | relief | p95 slope |
|---|---|---|
| 2048 | 199 m (8x Earth) | **11.4 deg** - a gentle hill |
| 2048 | 497 m (20x) | 26.8 deg |
| **4096** | **497 m** | **45.3 deg** - a mesa escarpment |
| 8192 | 497 m | 63.7 deg |

A mesa escarpment in the reference photography is 40-70 degrees. At 8x on a 2048
map **the terrain cannot exceed about 11 degrees regardless of how the erosion is
tuned** - which is exactly why it stayed flat through every parameter change.
Resolution and relief had to move together; neither alone is enough.

Now: 4096 map, 20x Earth relief, ~2.5 s bake, 9.8 s to walkable, 57-62 fps.

> **20x is above the 4-8x band originally specified, and that is a real realism
> cost.** The alternative that preserves the band is a SMALLER body: relief is a
> fraction of radius, so the same exaggeration on a 2 km planet gives far more
> relief relative to horizon distance. Recorded in `PlanetProfile` next to the
> constant so the trade is visible where it is made.

> **A hillshade preview lies about scale, and it fooled me.** The sweep renderer
> exaggerates vertical by 60x to make landform readable - which is correct for
> reading a map and completely wrong for judging drama. Beautiful mesas in the
> preview were a 60x stretch of an 11-degree surface, and the in-game view was
> the honest one. Use the hillshade to compare the SHAPE of two bakes; use slope
> in degrees, computed against real metres per texel, to judge whether that shape
> will read in game.

### Relief chosen by measuring slope, not by picking a ratio

`Planet._log_slope_profile()` reports the terrain's slope distribution in
DEGREES, computed against real metres of arc per texel. It is the instrument
this work lacked longest, and the one that finally settled the "terrain looks
flat" question.

Height standard deviation cannot answer it: two maps with identical SD can be a
gentle dome and a canyon system, because slope depends on how much horizontal
distance a height change spans. A CharacterBody3D walks up to `floor_max_angle`
(45 degrees by default), so the fraction above 45 is the playability budget.

Measured on the 4096 map (12.3 m of arc per texel):

| exaggeration | relief | mean | p50 | p95 | p99 | unwalkable |
|---|---|---|---|---|---|---|
| 20x | 497 m | 5.5 | 3.0 | 20.2 | 29.3 | 0.0% |
| 32x | 795 m | 8.6 | 4.8 | 30.5 | 42.0 | 0.5% |
| 45x | 1118 m | 11.5 | 6.8 | 39.5 | 51.6 | 2.9% |
| **65x** | **1615 m** | **15.5** | **9.8** | **50.0** | **61.3** | **7.4%** |
| 90x | 2236 m | 19.8 | 13.4 | 58.8 | 68.4 | 12.6% |

**65x chosen.** Median near 10 degrees is comfortable walking, the top 5% past
50 degrees are genuine cliffs, and 7.4% of the surface is unclimbable - which is
what real mountainous ground measures like. Everything remains reachable on foot
by going around. At 90x the ridgelines start reading as thin fins rather than
landforms.

> **An earlier prediction of "45 degrees at 20x" was wrong.** It reused a
> gradient measured from a different map at a different resolution and erosion
> setting. A slope number is only meaningful alongside the resolution it was
> measured at - the real figure at 20x is 20 degrees.

Final: 4096 map, 65x relief, ~2.5 s bake, **11.8 s to walkable, 60-67 fps**,
0% of the surface unmaterialed.

### The "wavy" look on flat ground was the rock band

Flat areas showed parallel ripples, like dunes. A/B confirmed the cause
immediately: disabling the rock band removed them entirely and changed nothing
else.

Ridged noise creases along its own lattice, so at one dominant frequency it lays
down parallel ridge lines. On a slope the landform breaks them up; on flat
ground there is nothing to break them, so they read as waves.

**Domain warping the rock band fixes it** - it breaks the lattice alignment
rather than hiding it, which is why more octaves alone never worked.

> Warp had been rejected earlier as too expensive, measured at +6-8 us/voxel.
> That measurement was taken against the old eight-band noise stack, at a
> different frequency and octave count. On the eroded path it costs **+0.9
> us/voxel** (2.61 -> 3.51). A cost measured in one configuration does not carry
> to another, and "too expensive" is worth re-testing after the thing it was
> measured against has been replaced.

The eroded path is 2.6 us/voxel against 8-30 for the noise stack it replaced, so
there is now real headroom for detail work that was previously unaffordable.

### Rings around the pole: erosion was running on the wrong metric

The orbit capture showed banding centred on the pole. Cause: erosion ran on the
equirectangular texel grid as if its cells were square. They are not - one texel
of x spans `cos(lat)` as much ground as one texel of y, shrinking to nothing at
the pole.

Measured with `scenes/dev/erosion_aniso.tscn`, which reports mean gradient
east-west against north-south in REAL metres, per latitude band. Isotropic
terrain reads 1.0 everywhere.

| latitude | before | after |
|---|---|---|
| +-80 | 4.14 / 4.73 | 1.53 / 1.93 |
| +-60 | 1.54 / 1.61 | 1.15 / 1.17 |
| equator | 1.07 | 1.07 |

The control is what made this airtight: the un-eroded base field measured 1.02
at every latitude, because it is generated on the sphere direction. Isotropic in,
anisotropic out - erosion was the cause, with nothing left to argue about.

Three separate places had the same bug:

1. **Angle of repose** (thermal.glsl) - a per-cell height limit is an angle only
   if it scales with the real distance between the cells. It did not, so an
   east-west slope at +-80 was allowed to stand ~5x steeper than the angle of
   repose and kept corrugation that every other latitude had relaxed away. This
   was most of the 4x.
2. **Droplet step** (droplet.glsl) - a unit step in texel space is not a unit
   step on the ground.
3. **Droplet trail** - once the step is corrected in real distance, a droplet
   running east near the pole jumps ~20 texels per step and erodes only the four
   cells around each landing, leaving gaps between them. The step is capped at 2
   texels so the trail stays contiguous.

One thing tried and reverted: making the gradient's central difference span
equal real distance on both axes. Correct on paper, measured 1.88 -> 1.90, so it
is not a fix and did not stay.

> **Edits to a `.glsl` are ignored until the file is reimported.** Running a
> scene directly does not reimport; the first measurement after the fix came
> back identical to three significant figures, which is what exposed it. Run
> `--headless --import` after touching a shader. Identical-to-3-digits is the
> signature of a change that never reached the GPU, not of a weak fix.

## Erosion masks: flow, wear, deposition

The erosion pass now emits three masks alongside the height, the way World
Machine's erosion devices do. They are what decide WHERE materials go.

|  | what it records | normalised |
|---|---|---|
| flow | water volume that crossed the cell | log, median..p99.9 |
| wear | material the water removed | linear, p20..p99.5 |
| deposition | material the water and the talus dropped | linear, p10..p99.5 |

Thermal erosion feeds deposition as well as hydraulic. Talus is the most
visually distinct sediment on a weathered planet - the scree apron at the foot
of a cliff - and it comes from the thermal pass. Leaving it out would have the
mask call a cliff base bare rock when it is buried in its own debris.

They are close to free. The droplets already computed all three; the values were
being discarded every step.

### Why this matters more than it sounds

Material placement used to come from noise fields unrelated to the terrain. That
is why the ground never agreed with the landform: bare rock in sediment basins,
dust on scoured divides. It was not a tuning problem. The noise did not know
where the water had been, so no setting of it could be right.

Measured on the rock-roughness gate, the first consumer: **3.51 -> 3.10
us/voxel**. Reading the mask is cheaper than the two-octave noise field it
replaced, so this was a straight win on both look and cost.

### Sampling a mask in the graph

`_sample_mask()` builds `SDF_SPHERE_HEIGHTMAP(img, r, 1) - SDF_SPHERE(r)`, which
evaluates to exactly `img(direction)`.

That is a strange way to read a texture and it is deliberate. The alternative -
an EXPRESSION node computing longitude and latitude for an IMAGE_2D - would be a
THIRD implementation of the equirectangular projection, alongside the height
lookup and `generate.glsl`, and it would have to stay byte-identical to both. A
half-texel drift there rotates every mask off the terrain it describes, and the
symptom would look like bad tuning. Going through the same node makes that
impossible.

> `SDF_SPHERE` takes its radius as an INPUT PORT. `SDF_SPHERE_HEIGHTMAP` takes
> it as a PARAMETER. Mixing them up throws "param_index = 0 is out of bounds".

### Normalising a mask is not normalising a heightmap

They have opposite problems. Height is roughly normal and needs its rare
extremes trimmed. A mask is one-sided and heavily skewed, so a mean-and-SD clamp
puts nearly everything at zero.

Masks are normalised against a percentile RANGE, not just a ceiling. The first
version anchored the low end at zero, and flow came back with a median of 0.72
and 98.7% of the surface above 0.1 - because 3.8 million droplets times 190
steps visit the average cell about 340 times, so every cell has *some* flow.
**A mask that says yes nearly everywhere cannot select anything.** Anchoring the
low end at the median dropped it to a median of 0.003 and 42.7% coverage, which
is a drainage network.

Percentiles come from a 2048-bucket histogram. Sorting 8.4 million values three
times would cost more than the whole GPU bake.

### Instrument

`scenes/dev/erosion_masks.tscn` bakes and reports coverage plus correlation
against height and slope, and writes the masks as PNGs. Coverage is the number
that caught the saturation above; a mask can be non-empty, plausible-looking and
still worthless.

One caveat learned from it: **wear correlates NEGATIVELY with final slope**
(-0.13), and that is not a bug. Erosion flattens what it cuts, so the places
that wore most are gentle by the time the bake ends. The check compares against
post-erosion slope, which is the only slope that exists. Do not "fix" the sign.

### Known limit

Flow reads as diffuse basins rather than thin channels, because it counts
droplet visits and droplets stall and wander in flat spots. Proper flow
accumulation (D8 routing over the finished height) would give the sharp
dendritic network, and is the obvious next step if flow is wanted for material
selection. Wear and deposition already have clean dendritic structure and are
the two in use.

## Boulders and overhangs: escaping the height field

Everything the heightmap produces is one surface per direction. It can make a
slope vertical but never lean it back over itself, and it cannot put a rock ON
the ground - only a bump made OF the ground. That is the hard ceiling on how a
heightmap-first planet reads close up, and it is why the surface kept looking
like a soft sheet however good the material got: every silhouette in view
belonged to the same continuous surface.

Two additions get past it.

### Boulders - `scripts/world/boulder_scatter.gd`

Real scanned rock from Poly Haven's moon collection (CC0), placed with
`VoxelInstancer` at terrain LOD 0 so they exist only in the blocks nearest the
camera. See `data/models/rocks/README.md` for the assets.

Placement is driven by the **deposition mask**, through the generator's
`noise_graph` input - which is what makes mask-driven scatter possible at all,
since the mask is an image and no `Noise` resource can return one. Boulders land
where the erosion actually left debris, the same signal the rock-roughness gate
reads, so loose rock and broken ground agree instead of each having its own
opinion about where rocky terrain is.

Density needed two passes. 0.02/m2 covered the ground edge to edge - a boulder
carpet, the same failure the rock-relief band hit twice before it was gated.
0.004 with a 0.45 threshold was nearly empty. **0.010 at a 0.36 threshold** is
clumps with bare ground between them. The lesson is the one already written
above about the rock band: a uniform amount of anything, high or low, is the
mistake.

### Overhangs - `_carve_overhangs()`

A field that varies with POSITION rather than direction, added to the SDF. The
isosurface stops being single-valued along a ray, which is exactly what an
overhang is.

ADDED, not subtracted through a min/max. A signed union carves discrete blobs
with visibly spherical mouths; adding a smooth field warps the existing surface,
so rock leans out instead of a hole being punched in it.

Gated by the **wear mask**: undercuts belong on scoured, exposed rock, not under
sediment. Amplitude is 3.5 voxels - near the rock band's own feature size it
stops undercutting and starts breaking the ground into floating shelves.

Cost: **3.10 -> 3.91 us/voxel**.

## Scale: radius 20 km, exaggeration 26

The home planet went 8 km -> 20 km radius, with `PLANET_EXAGGERATION` 65 -> 26 to
compensate. Relief lands back at 1614.6 m, so the mountains keep the absolute
size they had while the body grows around them.

**The slope collapsed and this is the open question.**

| | 8 km, 65x | 20 km, 26x |
|---|---|---|
| relief | 1614.6 m | 1614.6 m |
| metres per erosion texel | 12.3 | 30.7 |
| p50 slope | 9.0 deg | 3.6 deg |
| p95 slope | 48.3 deg | 24.2 deg |
| unwalkable | 6.4% | 0.1% |

The cause is not the exaggeration. It is that **the erosion map is a fixed 4096
texels regardless of radius**, so its features scale with the planet: at 2.5x
radius each texel covers 2.5x more ground, landforms are 2.5x wider in metres,
and with the height held constant the slope divides by 2.5. The numbers match
exactly - 9.0 / 2.5 = 3.6.

Note this is NOT true of the noise bands. `continent_freq = radius / CONTINENT_SIZE_M`,
so those keep a constant absolute feature size across the radius change. Only the
eroded landform, which is now the dominant term, scales with the body.

So the erosion map resolution has to be tied to ground distance, not to texel
count, if terrain character is to survive a change of planet size. 4096 -> 10240
would restore 12.3 m/texel, at roughly 6x the bake cost (12 s -> ~75 s) and
210 MB of map. **Resolved - see "Terrain character is independent of planet
size" below.**

## Terrain character is independent of planet size

The map is now sized from GROUND DISTANCE, not from a texel count:
`EROSION_METRES_PER_TEXEL = 12.3`, capped at 10240 wide. A 20 km planet gets
10216x5108; the moon gets 1120x560. Both see 12.3 m per texel.

Two separate fields had the same bug, and fixing only one was not enough:

1. **The map** was a fixed 4096 texels, so it scaled with the body.
2. **The base noise** in `generate.glsl` samples on the unit direction vector,
   so its frequency is ANGULAR - a given value always makes the same number of
   landmasses around the planet, whatever its size. Fixing the map alone got
   p95 slope from 24.2 to 33.2 degrees; scaling the frequency by
   `radius / 8000` closed the rest.

| | 8 km, 65x (reference) | 20 km, 26x, fixed |
|---|---|---|
| relief | 1614.6 m | 1614.6 m |
| m per erosion texel | 12.3 | 12.3 |
| p50 slope | 9.0 deg | 10.3 deg |
| p95 slope | 48.3 deg | 50.7 deg |
| unwalkable | 6.4% | 8.0% |

Terrain now reads the same at any planet size, which it did not before.

### The 65535 workgroup limit, and a silent failure

Scaling the map exposed a real bug. The droplet pass dispatched 1D, and Vulkan
guarantees only **65535 workgroups per dimension** - at 64 droplets per group
that caps a 1D dispatch at about 4.2 million. The 10240 map wants 94 million.

The over-limit dispatch **failed silently**: no error, no warning. It reported
`erode_ms 351` for 94M droplets where the 4096 map had taken 7396 ms for 15M -
roughly 0.5% of the work, on a planet that still looked entirely plausible. It
was caught only because the timing was arithmetically impossible.

> A number that is impossibly GOOD deserves the same suspicion as one that is
> bad. Dispatched 2D, it now takes 57 s, which is what 94 million droplets
> should cost.

### Bake cost and the disk cache

56 s at 10240, so the bake is a cached artifact keyed on seed, size and a format
version - `scripts/world/erosion_cache.gd`. A cache hit loads in **0.45 s** and
reproduces the slope statistics exactly.

Stored as raw float32 behind zstd, NOT as a PNG: 8 bits across 1615 m is 6.3 m
per step, and a height field quantised that coarsely terraces - the same contour
banding this generator spent so long removing from the noise path.

**Masks are downsampled to 2048; the height is not.** At full resolution four
masks cost 840 MB of RAM and 747 MB on disk, more than the terrain itself, for
data that never needed it: a mask answers "is this ground scoured, silted or
buried in talus" and that varies over hundreds of metres. The height genuinely
does need every texel - it IS the landform. Cache went to **206 MB**.

`FORMAT_VERSION` prunes its own predecessors on write. Without that, every bump
leaves a few hundred megabytes of unreadable terrain behind.

### Normalisation moved to the GPU

`shaders/erosion/normalize.glsl`: find the range, histogram it, map
`[lo, hi] -> [0, 1]`. Only a 2048-entry histogram crosses the bus before the
final image; the readback is a memcpy into `Image.create_from_data`.

The GDScript per-pixel loop it replaced was already the largest single cost at
4096 (4.7 s against 7.4 s of actual erosion) and at 52 megapixels x 5 layers
would have dominated everything. **Readback 1167 ms -> 52 ms**, with mask
statistics identical to three significant figures - which is what confirmed the
port rather than just made it faster.

## Where boulders actually go

The first version filtered on slope under 38 degrees and hydraulic deposition,
which scattered them evenly over the ground. Evenly is the tell.

Real loose rock on an arid or airless world sits in a few specific places:
scree aprons under scarps and crater walls, block fields where an outcrop has
broken up in place, and lag surfaces where the fines have blown out leaving the
coarse fraction behind. Every one is gravity moving broken rock a short distance
downslope. Where boulders are conspicuously ABSENT is fine sediment - silt fans,
dust basins, playa.

Which is exactly what hydraulic deposition records. **The first version was
placing boulders in the one setting that should have none.**

So thermal deposition is now its own mask, `talus`, split out from the droplets'
`deposition`. Both are "sediment" and merging them lost the only distinction
that matters here: hydraulic deposition is silt dropped where water slowed,
thermal deposition is coarse angular blocks that fell off a face and came to
rest at the angle of repose below it.

Boulders key off `talus`, in a slope BAND of 4-36 degrees. The lower bound
matters as much as the upper: a boulder field on dead-level ground has nowhere
for the material to have come from.

## Matching boulders to the ground

Two measured mismatches, both structural rather than tuning.

**Texel density.** The ground runs 341 px/m (1024 px tiled every 3.0 m). The
scans are 0.08-0.25 m with the same 1024 px texture, so one global 6-20x scale
gave 205 px/m on the largest at 20x and 2133 px/m on the smallest at 6x - a
TENFOLD spread between boulders sitting side by side.

Each variant now derives its own base scale from its actual mesh AABB, so they
agree with each other and with the ground:

    scale = (1024 / 341) / largest_AABB_axis

Matching exactly would force every boulder to 3.0 m - that division has no free
variable - so size varies 0.6-1.5x around it. Boulders run 1.8-4.5 m at
227-568 px/m: a factor of 1.7 against the ground instead of 10.

**Colour.** Mean albedo of the six diffuse maps is RGB 132,126,114 against the
ground's 102,102,103 - 1.23x brighter and warm where the regolith is neutral.
Corrected with `albedo_color = (0.776, 0.813, 0.900)`, the measured per-channel
ratios. The material is duplicated first: it comes off the imported glTF and is
shared, so writing to it would tint the source asset.

## Dust mantling, and the ripples on gentle ground

Mid-slopes read as regular parallel ripples - a corrugated meadow rather than a
hillside. Three hypotheses, two of them wrong, and the wrong ones are the
instructive part.

**Wrong 1: the rock band.** An A/B with `--no-rock` showed the ripples gone, so
the band looked guilty. It was a FALSE NEGATIVE: without the rock band the
surface is so smooth it barely catches the light, and the whole frame goes near
black. Nothing was visible, which is not the same as nothing being there. An A/B
is only evidence if BOTH sides are legible.

Two real bugs fell out of chasing it anyway. `--no-rock` also disabled overhangs,
because `_carve_overhangs` was gated on `rock_amplitude` - so the flag was never
testing one thing. And the warp amplitude on the rock band went 0.18 -> 0.55
(ridged noise only decorrugates if the warp displaces by something near the
feature wavelength). Both worth keeping; neither was the cause.

**Wrong 2: heightmap interpolation.** Bilinear is C0, so its derivative jumps at
every texel boundary, and a shaded surface shows those creases as a regular
lattice - which is what the pattern looked like. Testable: halve the map
resolution and a grid artifact gets COARSER.

**Right: the hydraulic channel comb.** At 24.6 m per texel the pattern vanishes
entirely and the terrain is naturally irregular. Erosion carves channels at a
spacing set by the texel grid, so at 12.3 m per texel they land 30-50 m apart -
correct for a gully system, wrong across an open hillside, where they read as
corrugation.

> Resolution is the right knob to TEST with and the wrong one to fix with.
> Backing off to 24.6 m per texel also throws away the landform detail that the
> whole cached-bake exercise was for.

### The fix

`shaders/erosion/mantle.glsl` blurs the height field where sediment collected,
before normalisation. Dust settling into topography and subduing it is a real
process and the dominant one on an airless world - it is why regolith plains are
smooth while the rock under them is not.

Weighted by the deposition mask, so ridges and scarps keep their edges. It has a
**floor** applied everywhere, including bare rock, because the comb is worst on
scoured ground where there is no sediment to mantle - deposition weighting alone
cannot reach it. The dust coverage log (`_log_dust_coverage`) is what established
that: median dust is 1.00 with only 26.3% of the surface rough, so the ripples
were on ground the gate was correctly leaving bare.

Cost, and it is a real one:

| | before mantling | after |
|---|---|---|
| p50 slope | 10.3 deg | 8.6 deg |
| p95 slope | 50.7 deg | 43.3 deg |
| unwalkable | 8.0% | 4.3% |

7 degrees off p95 to take the corrugation off. The floor is the term spending
most of that; lower `mantle_floor` for more drama and more ripple, raise it for
smoother ground.

> Note this is dust as GEOMETRY, not as a material. Smoothing the surface is
> what removes the ripples - they are in the height field, and no shader on top
> of them helps. A dust material layer selected by the same field is a separate
> and still-unbuilt thing.


## Rock-scale shape, and the warp that was tearing the landform - 2026-09-12

Raised from play: terrain reads fine at landform scale but has nothing at rock
scale, flat ground looks like water, and steep ground shows stretched streaks.

### The instrument this needed: `scenes/dev/micro_hillshade.tscn`

Samples the generator's real isosurface over a tangent patch and writes a
detrended hillshade plus slope over 1/2/8 m baselines and relief detrended over
4 m and 16 m. ~35 s per run against ~4 minutes for a capture, and it answers
shape questions without the material, the normal maps or the lighting in the
way. `--scout=N` finds steep ground to point it at; the two patches it is aimed
at are FIXED constants, because a patch chosen fresh each run moves when the
terrain changes and destroys the A/B.

Three traps it had to get past, all of which produced confident wrong numbers:

> **`generate_block` only evaluates the graph at INTEGER voxel positions.** A
> bisection that rounds its sample position measures the rounding, not the
> terrain - it reported a 36 degree median slope over 1 m on ground that renders
> smooth. Read the lattice trilinearly instead, which is also what Transvoxel
> does, so the measurement is of the surface the mesher will actually build.

> **A hillshade of a tilted patch saturates.** A 57 degree face renders flat
> white and its rock detail vanishes. Remove a least-squares plane first.

> **An 8-bit preview PNG fabricates contour hatching.** 1615 m across 255 levels
> is 6.3 m per step. A "diagonal comb across the whole map" read off
> `erosion_homeplanet.png` did not exist in the float field at all.

### What was actually wrong with the shape

Measured, not guessed:

| | |
|---|---|
| relief detrended over 4 m, rock band OFF | **0.09 m rms** |
| dust mantling median over the home planet | **1.00** |

The heightmap is smooth at every scale a standing player sees - one texel is
12.3 m of arc - so the rock band was the *only* source of rock-scale shape, and
it was gated by deposition alone, whose median is 1.00. It was therefore
suppressed over most of the world, at 1.1 m over 7 m features (a 9 degree swell)
where it did fire.

**Neither amplitude nor faceting fixes a single-wavelength band.** 2.5x
amplitude gave deeper lumps of the same shape; blending in a quantised copy at
the band's own step moved the numbers by nothing. One wavelength is a carpet.

### What replaced it

`_build_landform_slope` - landform steepness from the eroded map. The existing
`_build_slope_mask` differences the mountain NOISE term, which only exists on the
procedural path, so on the eroded path it was never called: **slope drove nothing
at all** - not cliff rock, not the rock band, not scatter. The gradient is the
sum of SQUARED differences along all three world axes, which for a
direction-only field is exact and isotropic, unlike the two-axis version that
degenerates near its own axes.

> Sampled from `height_lo`, a mask-resolution copy of the same landform added to
> the bake and the cache. Four samples of the full 10216x5108 map cost more than
> every noise band in the graph combined - **3.0 -> 8.8 us/voxel** - because
> 210 MB of image cannot stay in cache. A gradient does not need that resolution.

`_build_rock_relief` - three bands, gated differently so they cannot switch on
together into one thicker carpet:

| band | features | role | gate |
|---|---|---|---|
| crag | 20 m | outcrops and ledges, faceted hard | rockiness, in clumps |
| rock | 7 m | metre-scale break-up | rockiness |
| grain | 2.6 m | a trace everywhere, so plains are not mirrors | mostly ungated |

plus a dune band (130 m, 4 m) gated ON where rock is gated off, because flat
ground had nothing but the map's texel-scale wobble and an even field of small
waves with no larger structure reads as water.

Cost: 3.0 -> 14.3 us/voxel, 9.2 -> 10.8 s to walkable, 120 fps.

### The seams were the domain warp folding

`generate.glsl` displaces the sample direction by `warp_strength * noise`. At
0.35 that map stops being injective: two separated directions land on the same
noise coordinate and the field TEARS along a smooth curve. At this relief the
tear is a one-texel slot with near-vertical walls, tens of metres deep, which the
mesher renders as a fan of parallel corrugations - in game, a streaked wedge on a
slope that reads as stretched texture.

Established by A/B on the generator's own isosurface: present with hydraulic
erosion **disabled entirely**, gone at warp 0, gone at 0.15. Now 0.15.

> **The folding risk scales with planet radius.** `frequency` is multiplied by
> `radius / FREQUENCY_REFERENCE_RADIUS`, so a bigger body samples the warp at a
> higher frequency, its gradient rises, and a strength that was safe at 8 km
> folds at 20 km. Raise it only with a fresh hillshade at the largest body.

Two things were tried first and did not fix it, so they are not worth retrying:
hydraulic erosion tuning, and restoring the offline baker's falloff erosion
brush, which the GPU port had dropped. The brush changed nothing visible and its
9 atomics per erosion step tripped the driver's watchdog - **a GPU device reset
surfaces as "Can't create buffer ... 0x887a0005" from every later call, plus a
half-written cache file that the loader then rejects.**

### Godot's GPU adapter order is not stable here

The same build measured 22 fps and 120 fps in consecutive runs; the slow ones ran
on the Intel iGPU. A "5x frame-rate regression" attributed to this terrain work
was entirely that. **Read the `Using Device #N` line before believing an fps
number** - and note `--gpu-index 1` was NVIDIA in one run and Intel in the next.

## World pass - 2026-11-05 (design/05-planets.md W1-W5)

Planets are now built from **data per world**, not per-planet code: `TerrainRecipe` (every band, gate and
landform layer, in metres) inside a `PlanetArchetype` (recipe + biomes + palette + scatter rules + POI table +
hazards), referenced by `CelestialBody.archetype`. Values live in `scripts/dev/make_archetypes.gd`, which writes
`data/archetypes/*.tres` - the reason for every number is in that file, not lost in an inspector diff.

### W1 - extraction proven bit-identical

`TerrainRecipe.legacy()` is the generator as it was at commit ad29272. `scenes/dev/planet_test.tscn` hashes 24
surface blocks (SDF + both material channels) per body; the hash was recorded on the ORIGINAL code, then the
refactored generator reproduced it exactly: home 3963048574, moon 1219189082 (erosion map 2048 wide, see the CPU
note below). Every later layer is built only when its recipe flag is on, so legacy() keeps the graph byte-equal.

### The erosion masks were read at the wrong place - found by W3, fixed

`_sample_mask` computes `sdf_sphere(R) - sdf_sphere_heightmap(img, R, 1)` and treats it as `img(direction)`.
**It is not direction-only**: that difference is the image value near |p| = R and drifts away from it with
altitude. On a 20 km home with ~1.6 km of relief the real ground sits hundreds of metres off R, so slope, dust,
wear (and the new height field) were all read wrong at the surface. It surfaced because terraces - which read the
height field - moved the ground by exactly 0.00 m over 400 directions while every intermediate node evaluated
correctly at R (scripts/dev/mask_probe.gd, graph_node_probe.gd, recipe_probe.gd).

Fix: `mask_on_shell` - masks are looked up at `normalize(p) * R` (one normalize + three multiplies shared by all
masks). Effect of the fix ALONE on the home terrain (recipe_probe, 400 directions): 183 move, mean 0.87 m,
+13.8 / -10.0 m - the rock / crag / overhang gates now see the slope and dust they were designed around. This is
very likely why open item 1 found that crags "fire almost never". `legacy()` keeps the old lookup for the hash.
The boulder rule graph samples talus/slope on the shell too.

### W2 - slope + altitude erosion

Multipliers on the outcrop bands (crag, rock) from the coarse slope mask and height; swells and craters also fade
on slopes (`flat_detail_slope_damp`). Grain is left alone (never a mirror). Measured with
`scenes/dev/landform_ab.tscn` (3 flattest / steepest / lowest / highest of 160 directions, 60 m patches) BEFORE the
mask fix: flats calmer (2 m slope p90 6.8 -> 6.0 deg, rms over 4 m 0.06 -> 0.05 m), steep ground unchanged
(rms16 0.34 -> 0.33 m, p90 39.1 -> 38.9 deg). Modest on purpose and on this coarse map; re-measure on the full
12.3 m map before raising it.

### W3 - landform layers (all recipe-gated, all patch-gated)

| Layer | Mechanism | Measured (recipe_probe, full coverage) |
|---|---|---|
| Terraces / mesas | coarse height quantised: `T(u) = round(u) + 0.5 smoothstep(0.5-w,0.5,v) - 0.5 (1 - smoothstep(-0.5,-0.5+w,v))`, `v = u - round(u)` (STEPIFY rounds - probed) | 359/400 directions move, +-19 m at a 24 m step |
| Canyons | zero crossings of a warped low-frequency fbm: floor where abs(n) < width, walls to width (1 + 2/sharpness) | down to -47.8 m |
| Spires | cellular distance on the direction = vertical columns; the shell grazes 3D feature points, so radius varies and spires are sparse by construction; tapered, capped by a regionally varied height | dense test: 204/400, up to +57.6 m |

Spires and canyons extend the spawn / collision band (`_measure_terrain_band` adds their full extent - 240 probes
can miss every spire).

### W4 - archetypes and palette harmony

- **Home = Barren**: regolith only, mesa highlands (~30%, above mid altitude), canyon systems (~35%), spire fields
  (70 m cells in ~15%), ground a hair warmer than raw regolith, ambient 30% ground-coloured.
- **Moon = Frozen**: frozen-wastes biome only (census: frozen 100%), cratered x1.5, strong slope erosion (smooth
  ice), crevasse canyons (narrow 0.018, sheer 5.0, 18 m, ~70%: 2 m slope p99 71.6 deg), no mesas or spires, cold
  ground tint and 55% cold ambient, sparse pale boulders, probes and crash sites only, hazard cold 0.8.
- `SurfacePalette` multiplies every natural surface by the archetype's `ground_tint` (construction blocks
  excepted); `world.gd` leans the ambient toward the dust colour (`PlanetArchetype.ambient_tint`). A sky tint for
  the scattering pass is NOT built.

### W5 - scatter rules and points of interest

- **Boulders** (`ScatterSet`): score = max(talus x w, smoothstep(slope, 0.12, 0.32) x 0.85) x clump(60 m fbm) - debris
  at the foot of slopes and along broken edges, in clusters, rare on smooth plains. `ScatterSet.legacy()` = the old
  talus-only placement.
- **POIs**: `Planet.poi_sites()` - Fibonacci lattice at 1.6x the spacing, seeded jitter, seeded-order greedy
  rejection with a spatial hash, so the minimum spacing is a guarantee (home 777 sites, closest pair 1507 m >= 1500;
  moon 28 sites, >= 900). `PoiField` instances them within 2.2 km and frees them past 3 km, on the ground from the
  generator itself (works before colliders stream), standing on the local radial. Blockouts in
  `scripts/world/poi_blockouts.gd`: Continuance probe (landed, transmitting beacon), crash site (half-buried pod,
  scorch, debris downrange), crystal outcrop (glowing prisms + stained ground). Gameplay hooks: group "poi",
  metas "poi_type", "poi_id", "poi_name"; `PoiField.consumed` for looted sites (saving it is gameplay's call).

### Working on a CPU-only machine (this session's container)

- No GPU: install Mesa lavapipe (`apt-get install mesa-vulkan-drivers`) and run with `--rendering-driver vulkan`
  under `xvfb-run`, or `ErosionBaker` has no RenderingDevice and the game silently takes the NOISE shape path.
- The full home map (10240 x 5120) is impractical to bake on 4 CPU cores. `--erosion-width=2048` (dev only,
  `Planet.EROSION_WIDTH_OVERRIDE`) bakes a coarser map (~61 m/texel instead of 12.3) and caches it. Every number
  and image in this section is from that map: same bands, coarser landforms.
- Once the cache exists, headless runs (`--headless`) use the eroded path too - the cache is read before the
  RenderingDevice is needed. recipe_probe / mask_probe / make_archetypes run headless.
- `--legacy-world` makes every body use legacy() and no archetype: before/after captures from one build.
- A new `class_name` script is invisible to `load(...).call(...)` and to type hints until `godot --import` has
  re-scanned - planet_test's first baseline run failed on exactly that.

Tools: planet_test (regression), landform_ab (W2 numbers), recipe_probe (does a layer move the ground?),
landform_look (photograph each layer where it is strongest + nearest POI), mask_probe / graph_node_probe
(node semantics), make_archetypes (writes the archetypes).

# Terrain architecture plan

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

### Phase 4 â€” Persistence and streaming

- Baked heightmap = the persistent base artifact (small).
- `VoxelStreamSQLite` = **player edits only** (deltas), which is what it is
  designed for.
- Loading screen covers the one-time bake. **User accepted this 2026-09-09**,
  and it is what makes the whole approach viable.
- Closes the terrain half of the missing save system.

### Phase 5 â€” SE2 content parity (after the foundation is solid)

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

### Terrain Critical Path â€” scoped 2026-09-09

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

#### Piece 1 â€” `VoxelGeneratorGraph` port (~20-50x)

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

#### Piece 2 â€” Generate once, stream from disk (`VoxelStreamSQLite`)

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

#### Piece 3 â€” Baked eroded heightmaps (the World Machine look)

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

### Floating Origin / Large-World Coordinate System â€” 1.0 Release

**Locked-in decisions:** continuous seamless interplanetary flight (no loading/warp), full 1:1 real solar-system scale (sun through Oort), stock Godot build as primary (double-precision as fallback).

**Precision at different scales:**
| Distance | Position quantum | Playable? |
|---|---|---|
| 200 m (today) | 0.015 mm | fine |
| 2 km | 0.12 mm | fine |
| 10 km | ~1 mm | fine, watch for jitter |
| 60 km | ~3.9 mm | **visible jitter, unstable physics** |

**Why stock Godot suffices (initially):** GDScript's `float` is always 64-bit (true precision), but `Node3D.global_position` is 32-bit float. Governing rule: never store true world position in a node's transform. Instead: script-side double ("authoritative position") + small float32 offset in node transform (relative to camera). Danger is distance-from-local-frame, not distance-from-sun. Jitter appears at ~1â€“10km if raw global position is treated as truth.

**Double-precision fallback:** Zylann publishes official prebuilt editor builds with voxel module + double precision. Export templates must be compiled custom if needed for shipping (not automatic). Real cost: infrastructure tax on every engine/addon update.

**Architecture â€” three layers:**
1. Authoritative double-precision world state â€” true positions/velocities as script doubles. Save/load persists this layer only.
2. Reference-frame simulation strategy â€” active vessel + immediate surroundings run full real-time physics ("physics bubble," radius TBD). Every other body computed analytically from orbital elements (Kepler/patched-conic) each frame. Planetary self-rotation composed on top.
3. Render-layer camera-relative transform â€” every frame: `render_pos = body_true_pos - camera_true_pos` (float32, small delta). Always-on, no reset events.

**Subsystems requiring frame-awareness:** player/camera; `VoxelLodTerrain` (needs spike test â€” does it ever touch solar-system-scale coords?); active physics bodies (re-center to bubble before physics server); non-active bodies (analytic orbits only); projectiles/enemies (must track authoritative frame, handle handoffs); `GPUParticles3D` (camera-relative emission); skybox/starfield (parallax layers); UI world-to-screen (waypoints, targeting).

**Open decisions:** physics bubble radius / handoff logic; whether terrain streams long-range or only on landable bodies; enforcement (lint/tests) for "no raw global position at scale."

**First spike:** (1) double-precision position layer + camera-relative render offset, no gameplay; (2) two static bodies on correct orbits, verify no jitter at distance; (3) one craft flying continuously between them, verify rendering holds; (4) physics bubble handoff + terrain streaming, confirm `VoxelLodTerrain` never sees solar-system coordinates directly.

---


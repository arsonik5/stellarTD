# Engineering patterns, risks & references

## Implementation Patterns & Known Fixes

This section documents validated architectural decisions and bug fixes to avoid repeating them.

### Radial Planet Gravity on CharacterBody3D

Set `up_direction = (global_position - planet_center).normalized()` every physics frame before `move_and_slide()`. Track vertical speed separately from `velocity` (since `velocity.y` no longer means "vertical"). Gravity: `_vertical_speed -= GRAVITY * delta`. Body orientation: rebuild basis via `Basis.looking_at(tangent_forward, up)` each frame so character stays aligned to surface.

**Verified:** driven headless test (walk from pole to near opposite pole, sample alignment/radius every second). Stays glued to surface (39.6â€“40.5m vs nominal 40m), never tunnels.

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

### Projectile Ballistics â€” Hand-Integrated Physics

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
- `InventorySlotAdapter` â€” player grid or hand slots
- `BuildingInventoryAdapter` â€” any Building's stacked inventory
- `BuildingModifierAdapter` â€” single-item modifier slots

Both inventory UI and building UI now use same adapter; no code duplication per screen.

**Verified:** driven test (swapping different stacks between player/building now works identically; partial placement into capacity-limited containers still clamps correctly; modifier slots go through same code path).

### Building Autocraft via Base Class Timer

Moved `Timer`, `_timer_callback`, auto-recipe logic out of `Processor` into `Building` base class. Every recipe-driven building (`Processor`, `Smelter`, `Constructor`) now gets it for free. Rotating cursor over multiple `auto_enabled` recipes so all recipes get a fair turn each frame (not just recipe 0).

**Verified:** driven test (Constructor's 4 recipes with 2 flagged auto both produced output, not just recipe 0).

### Per-Voxel Material Indexing

1. `VoxelFormat.new()`, `set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)`, assign to `terrain.format`
2. `VoxelMesherTransvoxel.texturing_mode = TEXTURES_SINGLE_S4`
3. Generator writes material index (0â€“255) per solid voxel into `CHANNEL_INDICES`
4. Shader unpacks `CUSTOM1.x` via `floatBitsToUint` + bitshifts, colors/textures per index

**Known bug:** default format is 16-bit (not 8-bit), causes mesher to silently emit all-zero `CUSTOM1` data. Must set explicit format first.

**Known gotcha:** `CHANNEL_WEIGHTS` doesn't accept `DEPTH_8_BIT`; only set indices depth, leave weights at default.

### Digging/Building via VoxelTool â€” Coordinate Spaces

`VoxelTool` mixes coordinate spaces per API:
- `raycast(from, dir, max_distance)` â€” world-space in/out
- `do_sphere(center, radius)` â€” **LOCAL (voxel-grid) space**, not world
- `do_sphere()` radius must be divided by terrain scale to get world-meter size

**Fix for scaled terrain:** `_local_radius(world_radius) = world_radius / terrain.scale.x`. Wrap all `do_sphere()` radius args with it.

**Verified:** isolated headless test (raycast and do_sphere behavior differs in 2 tests; mining now digs consistent depth, not 1â€“2 voxels).

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
   - Action: clarify design intent â€” confirm relationship or decide which is primary

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

- `VoxelLodTerrain` coordinate handling under camera-relative render offset (module internals you don't control) â€” needs early spike test
- Deferred/async collision queue design (custom scheduling needed, no built-in solution for staggering collision rebuilds)
- Blender headless glTF export texture fidelity (smoke-test before building full parametric generator)
- Double-precision build is maintenance tax (rebuild on every engine/addon update) â€” confirm acceptable before committing at rung C
- Volumetric cloud rendering (needed for shell-scatter cinematic) has no existing reference implementation â€” budget prototyping time, not just integration
- Multiplayer terrain sync unsolved in voxel module itself (Zylann's wishlist item) â€” research when multiplayer phase starts, don't assume it's free
- `NODE_SDF_SPHERE_HEIGHTMAP` projection (equirectangular vs. cube-face) unverified â€” test before rung C heightmap approach commits
- Terrain generation at higher LODs with thin biome bands under-sampled (LOD popping risk, mitigated by low climate-noise frequency, needs visual validation)

---

## Art Direction (Reference)

**See `../art-direction.md` for complete reference.** Summary:
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

### When Scaling to Larger Planets (Rung B â†’ C)

1. Raise `lod_count` (currently 5, needs ~10 for 2km, ~15 for 60km)
2. ~~Delete proxy sphere system~~ â€” **done 2026-09-07**, replaced by the scattering pass. At rung B/C instead retune `AtmosphereRenderer.sun_intensity`: it compensates for our bodies being ~200 m rather than planet-scale, so a much larger body needs a much smaller value.
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

# Gameplay systems

### Factory / Logistics System â€” Alpha (minimal) â†’ Beta (expanded)

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
- `FoundationNetwork` uses flat linear scan (not `Vector3i` dictionary like `PipeNetwork`) â€” buildings aren't axis-aligned, so grid lookup doesn't work. At hobby scale (<100 foundations per base), linear scan is simpler and correct.
- `SlotCarry` (one click-to-carry implementation) driven through duck-typed container adapters, not duplicated code per UI screen
- `Building.input_capacity`/`output_capacity` are *not* storage caps â€” they're throughput-rate placeholders for future power/logistics system. Actual cap is `inventory_capacity`.

**Beta scope:** more resource types, more building tiers, power system, expanded conveyor mechanics.

---

### Weapon & Combat System â€” Alpha (partial) â†’ Beta (full) â†’ 1.0 (orbital/interplanetary)

**Current State:** Turrets (gun + cannon) built and validated. Projectile physics working. Scout ship AI basic. Wave spawning tied to crystal signature (not power, see Radiation Threat section). Enemy health and targeting working.

**Design intent:** combat is anti-air (planet-to-orbital) and ship-to-ship, not close-quarters. Readability + cinematic spectacle over simulation precision.

**Architecture â€” modular facade pattern:**

1. **CombatManager** â€” facade. All external combat access through it. `RequestFire()`, `RegisterMount()`, `QueryAmmo()`.
2. **WeaponDefinition** â€” `Resource` holding tier, muzzle velocity, drag coefficient, fire rate, ammo cost, projectile type. Tuned via data, not code rewrites.
3. **ProjectileSystem** â€” ballistic sim. **Current implementation:** one `Node3D` per projectile with hand-integrated semi-implicit Euler physics. **Architectural gap:** main-design calls for pooled, data-oriented system (parallel position/velocity arrays per frame). Current approach will be expensive with hundreds of live shells.
4. **HitscanResolver** â€” beam weapons (separate from projectile system, minimal shared code).
5. **DamageTarget** â€” duck-typed contract (`apply_damage(amount, type, position)`). Terrain, ships, shields all implement it.
6. **ShieldComponent** â€” absorbs damage to capacity, regenerates over time, forwards overflow. Fresnel-ripple shader. Same component serves personal/base scales (different capacity/radius).
7. **WeaponMount** â€” building piece (not separate placement system). References `WeaponDefinition`, has fire-arc constraint, ammo-feed to inventory.
8. **TargetingSolver** â€” stateless function: ballistic data + target position/velocity â†’ lead-aim solution. Shared by player UI and enemy AI.
9. **CombatVFXController** â€” signal-driven. Listens to projectile "fired"/"impacted" signals; triggers hero-cam, explosions, debris, craters.
10. **Reference-frame tag** â€” each live projectile carries "which frame am I authoritative in" tag (for floating-origin handoff later).

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
- Alpha: `CombatManager` + `WeaponDefinition` resources (1â€“2 weapons); minimal `ProjectileSystem` (gravity only, no drag); `DamageTarget` base class; basic enemy HP.
- Beta: full ballistics (drag), `HitscanResolver`, `ShieldComponent`, `WeaponMount` in building system, `TargetingSolver`, `CombatVFXController`.
- 1.0: reference-frame tagging, siege/orbital weapons, hero-cam, volumetric cloud disturbance, multiplayer hardening of `ProjectileSystem`.

**Multiplayer readiness:** deterministic, step-based ballistics are critical for client-side prediction/rollback. Currently not verified. Must test before shipping.

---

### Radiation Threat System â€” Slice 2, Scopes 1â€“5

**Current State:** Scope 1 complete and validated (crystal ore, signature tiers, scout ship). Scopes 2â€“5 designed but not built.

**Lore:** Player is corporate mining operation. Objective ore is radioactive crystal (direct use: reactor fuel, weapon cores, building material; dissolve: mission resource). Crystal creates persistent signature that draws alien attention. All enemies are starships (not ground troops).

**Threat tiers** (signature-driven, no arbitrary clock):

| Tier | Signature | Behavior |
|---|---|---|
| None | ~0 | No spawns. No signature is a legitimate playstyle. |
| Low | small leak | One scout ship flies in, hovers, scans. If it detects something (chance scales with depth into band), flees toward system edge. **Core tension:** kill it before escape (report never goes out), or let it slip and face escalation. |
| High | large/sustained | No scout â€” mothership detects source directly, puts player into constant war state (continuous fleet pressure) until signature drops back down. |

**Signature source:** crystal currently held/socketed (persistent) + dissolve-machine bursts (temporary spike, future). Barriers/containment (Scope 5) are the tool to drop signature without not-mining-at-all.

**Scopes:**

- **Scope 1** (âœ… Complete): `RadiationSignature` autoload (reads crystal count, exposes tier + `tier_changed` signal), `ThreatDirector` (spawns one scout on Low tier entry), scout ship (flies in from edge, hovers, scans, flees with/without report), turret-targetable.
- **Scope 2** (âŒ Not started): Escalation fleet â€” what `leak_reported` actually spawns. Open question: how do starships damage ground bases (orbital bombardment / landing / gunship)? Needs decision.
- **Scope 3** (âŒ Not started): High tier constant-war spawning.
- **Scope 4** (âŒ Not started): Dissolve machine (converts crystal to mission resource, produces signature spike).
- **Scope 5** (âŒ Not started): Containment barriers (powered building that dampens signature radius).

---

### Vehicle Building System (Ship System) â€” Alpha â†’ Production (Phases 1â€“5)

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
- Dot-product thruster allocation (each thruster: `local_dir.dot(desired_accel)`, clamped 0..1) â€” works regardless of layout
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

**Rigging workflow** (Blender â†’ Godot):
1. Model low-poly humanoid in A-pose, matching building kit aesthetic
2. Rigify: add Human meta-rig, adjust to match proportions, Generate Rig (produces FK/IK control rig + `DEF-*` deform bones)
3. Skin mesh: Automatic Weights first pass, then manual weight-paint trouble spots (armpits, shoulders, etc.)
4. Animate: use Rigify control rig (animator-friendly) or retarget Mixamo
5. Bake down: `Bake Action` onto `DEF-*` bones only (drop control rig)
6. Export: same glTF pipeline as buildings; Rigify names don't auto-map, need one-time `BoneMap` setup in Godot
7. Godot: confirm `Skeleton3D` + `BoneMap`, wire up `AnimationTree`/`AnimationPlayer` for locomotion, layer weapon-grip `IKModifier3D` on top

**Roadmap:** Alpha gets capsule placeholder (prove loop is fun). Beta gets full rigging (multi-day investment).

**Animation sourcing:** don't hand-key locomotion â€” use Mixamo free library (walk/run/idle/jump/etc.) with community retargeter plugins. Custom animations (weapon-specific, cinematic) hand-authored in Blender.

**Weapon-grip IK:** `IKModifier3D` (native in Godot 4.6+) chains hand onto weapon grip point. Swap weapons, grip stays correct automatically.

**Viewmodel (hands/weapon in FPS view):** two techniques:
- **SubViewport + cull-mask:** separate `SubViewport` with own camera, dedicated cull-mask layer. Fully correct depth separation, costs extra render pass.
- **FOV-override shader:** shader rewrites `PROJECTION_MATRIX`, fakes depth separation. Cheaper (one pass), common in shipped FPS games, slightly hacky.

**Animation architecture:** Locomotion as `AnimationTree` state machine (idle/walk/run/jump/fall/crouch, signal-driven transitions). Weapon-hold poses layer on top via blending.

---

### Asset Generation Pipeline (Blender + Agent) â€” Beta

**Status:** Designed but not built.

**Goal:** replace placeholder blocks with proper low-poly buildings via parametric generation (not freeform generative 3D, which produces messy topology).

**Approach:** agent-driven Blender Python script (`bpy`). Generator assembles buildings from kit parameters: footprint size, wall height, roof style, window count, material zone. Modular composition (walls, roofs, floors, corners), matching Satisfactory aesthetic.

**Execution:** `blender --background --python generator.py -- <args>`. Script uses `bpy.ops`/`bmesh` to build mesh, exports directly with `bpy.ops.export_scene.gltf(export_format='GLB')`. Reuses Material ID â†’ texture array scheme (buildings sample same atlas as terrain â€” consistent style, fewer draw calls).

**Known gotcha:** headless glTF exports sometimes don't carry textures correctly depending on Blender version/flags. Smoke-test (export one building, reimport to Godot, confirm materials) before building full generator.

---

### Save/Load System - Built (2026-09-10)

**Entry point is now the main menu** (`scenes/main_menu.tscn`, the project's main
scene): the slot list, New Game, Delete, Quit. Esc in-game opens the pause menu
(Resume / Save / Save and exit to menu / Save and quit); it is the only exit
path, so leaving always goes through code that can flush the world first.

**Two storage layers per slot** under `user://saves/<slot>/`:

| File | Holds |
|---|---|
| `state.json` | inventory, quests, placed objects, ships, player transform, playtime |
| `terrain_<body>.sqlite` | **edited voxel blocks only** (`save_generator_output = false`) |

Untouched terrain is never written - it is reproduced from the seed and baked
heightmap. One 6 m dig came to 24 blocks. The database file is per body, keyed
on the `CelestialBody` resource's filename (`Planet.save_key()`), so a second
planet needs no new code.

**How a system joins the save:** implement `save_state() -> Dictionary` and
`load_state(Dictionary)`. `SaveManager` only decides when and in what order and
never reaches into anyone's internals. Placed world objects additionally join
the `saveable` group and carry a `save_item_id` metadata key, both set by
`SaveManager.mark_placed()` at placement - so restoring any building is "look up
the Item, instance its scene, set the transform" with no per-type code.

**A new game is a slot with empty state, not a separate code path.**
`apply_pending()` does nothing when there is nothing to apply.

#### Things that bit, keep them in mind

- **`save_modified_blocks()` is asynchronous.** It returns a
  `VoxelSaveCompletionTracker` and godot_voxel writes on worker threads.
  Quitting when the call returns loses every edit. The pause menu holds a
  "Saving..." state until `SaveManager.terrain_save_complete()`.
- **Loading must not re-run spawn placement.** The normal spawn parks the player
  at the surface; doing that to a loaded save quietly relocates them (stand on a
  tower, quit, come back at ground level). `Player.load_state()` sets
  `_spawn_from_save`, and `_try_resolve_loaded_spawn()` then only *waits* for a
  collider under the saved position instead of choosing one.
- **Preload cycles are silent.** `pause_menu.gd` preloading `main_menu.tscn`
  while `main_menu.gd` preloads `world.tscn` (which contains the pause menu)
  closed a cycle; the scene came back unusable and "Save and exit to menu" sat
  on "Saving..." forever while "Save and quit" worked. It loads by path now.
- **`SceneTree.current_scene` is not assigned until the scene finishes being
  added**, so restoring placed objects is deferred one frame in `world.gd`.
  Inline, every saved building gets a null parent.

**Verified:** a scripted round trip - dig, place a building with contents, add
inventory, advance a quest, move the player, save, relaunch, load - restores all
five, with the crater still air (sdf > 0) and the player within 7 mm of the
saved position. The menu -> New Game -> play -> save -> exit -> Play flow was
driven end to end and captured as frames.

**Still not saved:** enemy ships (deliberate - they are ThreatDirector's, not
the player's), pipe round-robin cursors (cosmetic, sub-second), turret cooldowns
and targets (re-derived within a frame). Once floating origin lands this needs
true double-precision positions and orbital elements rather than render-relative
offsets.

---

### Underground System â€” Scope 3

*Not yet planned at all.*

---

### Radiation System (Alternate Name for Radiation Threat)

*See Radiation Threat System section above â€” this was added to Alpha scope as a specific wave-pressure mechanism, not part of 1.0 Release scope. Scopes 1â€“5 defined; Scope 1 built and validated.*

---

### Audio System

*Not yet planned as its own system.* Only touchpoint: Atmosphere system's audio modulation (density-based attenuation, pressure-based wind/roar parameters).

**Candidate plugin (user-supplied 2026-09-09, not yet evaluated):**
`SpatialAudio3D` â€” https://store.godotengine.org/asset/claude/spatialaudio3d/

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
- One `CanvasLayer` (compact HUD) with `UiState` autoload registry â€” all modals call `UiState.set_open(id, bool)`, HUD just watches aggregate
- Build tool: first-person, Satisfactory style (since 2026-11-04; the top-down camera was deleted). C opens the build menu, picking a building closes it, the ghost sits where the crosshair hits (30 m), LMB place, R / wheel rotate, G grid, B pipe mode, Q menu, RMB / C / Esc exit. Test: scenes/dev/build_fp_test.tscn
- Inventory: slot-based grid + hand slots, unified click-to-carry/merge/swap via `SlotCarry` adapter pattern
- Quest system: 7-quest diamond (two roots, two branches, one final) generated from pure data, no hand-laid-out nodes

*More detailed UI work deferred past Alpha.*

---

### Multiplayer / Networking

**Status:** Not scoped in detail, confirmed future goal.

**Risk:** Zylann's voxel module lists multiplayer terrain sync as an open wishlist item (not solved). Shared terrain deformation across clients needs research.

**Projectile readiness:** Ballistics designed deterministic/step-based from day one (requirement for client-side prediction/rollback). **Current gap:** determinism not yet verified. Must test before 100s of simultaneous shells become normal.

---

## Ore deposits (Space Engineers model)

Replaces the vein model, which was wrong about the thing that mattered: veins
are EVERYWHERE. `|noise| < width` is a connected surface through the whole
volume, so it scattered thin sheets of ore across the entire planet at the right
depth. Nothing to find, no reason to prospect, no reason to travel.

What SE does, from the wiki and the SE2 deposit design thread:

- Deposits are **discrete clusters**, not continuous structures.
- Clustered within ~150 m of the surface on planets.
- They appear "in groups of two or three, spread out in horizontal layers below
  each other" - one site, several ores stacked by depth.
- They have a **visible surface expression**: "groups of discoloured spots on
  the ground", readable from jetpack height, clearest on plains.

That last point is the design. Prospecting becomes something you do with your
eyes while travelling.

Ours: a world-space `Spots3D` field gives deposit sites; a continent-scale
region field decides which ores a site carries, with windows widened past their
1/n share so a site typically holds two or three; per-ore depth bands stack
them. Shallow ores (silica 1.5-22 m, iron 2-34 m) break the surface as patches;
deep ones (sulfur 48-110, crystal 70-150) stay buried and need the scanner.
Measured: one site carried five ore types within 600-740 m, and two of five
scan points found nothing at all.

### Spots3D must be sampled on WORLD POSITION, not on the surface direction

This cost the most time here. `Spots3D` scatters its centres through a 3D cell,
so sampling it on the unit direction only registers a spot when its centre
happens to land within `radius` of the unit sphere itself. At a radius of 0.011
against a cell of 0.07 almost every spot missed the shell: **0 ore voxels in a
1 km cube**, with only bedrock and stone present.

Found by bisecting the weight expression against a raw dump of the generated
buffer - constant 1.0 produced ore, `site` alone produced nothing, which located
it in one step. Guessing at it produced two wrong fixes first.

> The radius port is also NOT a plain sphere radius in metres, whatever the name
> suggests: 210 against a 1400 cell gave an empty field where a sphere model
> predicts ~460 hits, and 600 gave 7%. It is tuned by measurement against the
> generated buffer. `DEPOSIT_SPACING_M` is the number that actually controls how
> far apart deposits feel.

Ore region frequency is derived from `continent_freq` rather than the old
hardcoded 1.1, which was angular - the same scale bug the continent and erosion
fields already had fixed.

## Mining tool (Space Engineers hand drill model)

Target feel is SE's hand drill: hold to bore, the hole grows under the
crosshair, and you get paid for the rock you actually removed. Not Astroneer's
terrain-as-clay sculpting - ruled out 2026-09-13, it's a different game.

Code: `scripts/world/terrain_drill.gd` (bite, payout, tuning), hardness in
`VoxelMaterials.hardness_for()`, player hookup in `player.gd` `_dig()`.
Probe: `scenes/dev/drill_probe.tscn`.

**Tier 1 - core (built 2026-09-13, headless-probed, not yet playtested)**
1. Yield from removed volume: SDF solid fraction read before/after each bite
   (two bulk `copy()` reads), credited to each cell's dominant material,
   fractions carried between ticks.
2. Gradual bore: 1.25 m sphere, 0.05 s ticks, `sdf_strength` 0.065 / hardness.
   The bite centre sits half a radius back from the hit - centred on the hit,
   partial strength drilled a pinhole needle instead of a bore.
3. Per-material hardness (`VoxelMaterials.hardness_for`). Bedrock is the host
   rock under a few metres of topsoil, so it's 1.2, not "hard".
4. Stone (all filler rock + cliff + bedrock) yields a `stone` item at 0.25/m3,
   ore at 2/m3. Stone has no use yet and can clog the 24-slot grid - watch this.

Measured (drill_probe, headless): stone bore ~1.4 m/s, ~3.3 m2 face, ~1 stone/s;
iron works out ~6 ore/s (old dig: flat 8.3/s). Bore speed is linear in strength
down to ~0.07 but crystal-hard (0.026) drops to ~0.46 m/s and can stall.
Cost: bite sphere ~1 ms vs old dig's two spheres ~5 ms; whole bite avg 0.3-3.5
ms, but the FIRST bite at a fresh spot spiked 87-149 ms - unknown whether the
old dig spiked too; check with the profiler in a real run.

**Tier 2 - feedback**
5. Audio: motor spin-up/loop/spin-down, per-material grind (pitch by hardness),
   pickup tick. Check `SpatialAudio3D` notes in Audio System first.
6. Particles at the hit: material-tinted dust, sparks on ore/hard rock, debris
   falling along radial gravity (never world Y).
7. Viewmodel: real drill mesh, spinning bit, jitter while cutting, spin-up kick.
8. Small camera shake scaled by hardness; optional rumble.
9. Stacking "+3 Iron" pickup popup near the crosshair.
10. Inventory full: buzz + HUD warning; stop collecting or drop floating ore (SE).

**Tier 3 - readability**
11. Target preview ring/decal tinted by material, dimmed out of range.
12. Freshly cut faces tinted, ore veins clear on tunnel walls.
13. Short-range ore shimmer (SE's drill has a built-in 20 m detector); the
    long-range scanner stays.

**Tier 4 - progression**
14. Drill tiers crafted from refined ore. SE: speed 1.0/1.2/1.4/1.4x, reach
    1.0/1.2/1.4/1.6x.
15. Excavate mode (SE RMB): big fast holes, destroys resources. Needs RMB freed -
    block placing currently lives on the mining tool's RMB.

**Skipped:** overheat/durability (friction in a feel slice), power cost (out of
scope).

## Resource scanner (Satisfactory model)

`V` pings the scanner; markers appear pointing at nearby deposits with a name
and distance, clamped to the screen edge as arrows when off-screen, expiring
after 45 s. A scan is a snapshot, not a permanent minimap.

`OreScanner` samples the **real generator** through `generate_block` rather than
reimplementing deposit placement, because the `Spots3D` hash is not reproducible
from outside and any reimplementation would drift from the terrain the player
actually digs. A scanner that points at ore which is not there is worse than no
scanner.

Coarse by design: 32^3 samples at LOD 5 covers a ~1 km cube at 32 m spacing, and
deposits are hundreds of metres across. **25-76 ms per scan** measured.

> `ore_indices` is a required argument, not optional. Stone and bedrock share
> the material channel with ore and fill essentially every solid voxel, so the
> first unfiltered scan returned sixty "deposits" of biome stone and no ore.

`scenes/dev/scanner_probe.tscn` verifies both the scanner and that ore bodies
exist underground at all - the surface material census only samples the skin, so
it cannot tell a deposit from a stain with nothing under it.

## Ambient light follows air density

A single fixed ambient cannot serve a vacuum moon and an atmospheric planet. Air
scatters sunlight into shadow - that is what a blue sky IS, and why a daylit
shadow on Earth is readable while one on the Moon is black. Tuned for one, the
other is wrong, and it had been tuned for the moon: every shaded slope on the
home planet crushed to black and took the landform with it.

`world.gd` now lerps ambient from 0.045 (vacuum) to 0.34 (Earth-like) on air
density at the player, per frame so leaving the atmosphere darkens continuously.

## First-launch bake no longer freezes the window

`ErosionBaker.bake()` is a coroutine that yields to the main loop between
erosion batches and emits `progress`, which the loading screen draws as a bar.
The 56 s first bake of a seed used to be a black window - a synchronous GPU
sequence never lets the frame paint.

Threading was the other option and a worse one: a local `RenderingDevice` driven
from a second thread is a far larger surface for driver-specific breakage than
yielding between submits, and the wall-clock time is identical either way. What
changes is only whether the window responds.

> Consequence: `Planet._ready()` is now a coroutine, so **children are no longer
> ready before the parent**. `world.gd` awaits `terrain_ready` on every planet
> before placing the player or restoring a save. Relying on node order there
> would silently read an unbuilt planet, which fails as "the save restored
> nothing" rather than as an error.

Also worth knowing: the droplet pass has deliberate benign races, so a rebake is
not bit-identical. The disk cache is what makes a seed reproducible, not just
fast - a cache miss gives a subtly different planet.

### Scanner range has to beat deposit spacing

Reported in play: "ores spawn only in one place, I can't see anything else on
the scanner." Every marker was 589-879 m away in a single clump.

Not an ore-generation problem. The scan cube was 1024 m across - **+-512 m,
against a deposit spacing of 1400 m**. From most of the planet it could not
reach a single deposit, and the one time it did, the hits were all 589-879 m
out: in the CORNERS of the cube, the only part of it reaching far enough. A
scanner whose radius is under a third of the spacing of the thing it looks for
returns nothing almost everywhere.

Fixed by coarsening `SCAN_LOD` 5 -> 7 rather than enlarging the grid: cost goes
as the CUBE of the grid size and only linearly with metres per sample, so
128 m samples buy **4x the reach for the same 32768 evaluations**. Range is
+-2048 m. The cost is marker precision (~128 m), which does not matter for a
readout that says "copper, 1.4 km, that way".

Before ruling out a placement bug, the cube's position was verified against
ground truth (`scenes/dev/scan_verify.tscn`): `generate_block`'s origin
convention could have been misread, in which case the buffer would hold terrain
from somewhere else and every marker would be confidently wrong in a
self-consistent way - nothing in the scanner's own output could reveal that,
because the error cancels. The check counts solid vs air across the cube and
confirms it straddles the surface at the right radius.

> The first version of that check walked a world-Y column and reported "no
> surface found". That was the CHECK being wrong: on a sphere the player's up is
> radial, so a world-axis column need never cross the ground. Rewritten to be
> orientation-independent.

### Clustering: single-linkage, not centroid

Widening the scan first returned **112 contacts** - deposits shattered into
1-9 sample fragments. Greedy centroid-linkage was the cause: as a cluster grows
its centroid drifts inward, so a sample on the far edge of a large deposit ends
up beyond `CLUSTER_M` of it even though its neighbour is one grid step away.

Single linkage (within range of ANY member, merging clusters that a new point
bridges) holds a chain together however long it gets, which is what a deposit
spread over many grid cells is. With a 2-sample minimum and a cap of 2 markers
per ore type, a scan now returns 11-12 useful contacts instead of a wall of
overlapping text.

Measured across five widely separated points: **11-12 deposits each at 64-67 ms**,
against 0, 2, 8, 0, 1 before.

### Readout: a directional pulse, not markers

The Satisfactory-style marker list was replaced with a metal-detector pulse. The
scanner still knows where deposits are; it does not draw them.

Markers with names and distances turn prospecting into reading a list and
walking to the top entry - one press and the answer is on screen, and the tool
is never touched again during the walk. A directional pulse makes the player
sweep, notice the signal rise, turn until it peaks, and keep checking on the
way. Finding the deposit becomes something they did.

Signal is `aim^6 * proximity^2`, two terms that are useless alone: proximity
without aim is a compass with no needle, aim without proximity never says you
are arriving. The exponents are the feel - a sharp beam makes the peak a real
bearing rather than "somewhere ahead", and squared proximity puts the climb in
the last stretch where the feedback is wanted.

Deliberately withheld: distance, bearing, count, position. The only information
is "you are pointed at something" and "it is getting stronger". Ore identity IS
given, as a colour tint, because knowing whether you are chasing crystal or iron
changes whether you bother, while not telling you where it is.

Details that matter more than they look:
- **Pulse RATE** carries most of the signal (1.1 -> 7 Hz). A rising rate reads
  as warmer long before a brightness change is noticeable.
- **Asymmetric smoothing** - rises fast, falls slow - so sweeping across a
  contact registers immediately and the peak is not missed between frames.
- **Phase is integrated**, not derived from absolute time, so the pulse
  accelerates smoothly instead of jumping mid-cycle.
- `MAX_PER_ORE` went 2 -> 6. The cap existed to stop marker clutter; with
  nothing drawn per contact the only cost is a few dot products per frame.


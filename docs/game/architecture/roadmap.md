# Roadmap, scope & scale

# Stellar TD â€” Game Design Doc

**Core pillars:** Satisfactory-style factory/logistics + Mindustry-style tower defense + Space Engineers-style deformable voxel mining/terrain, in a persistent world of procedural planets/asteroids, defending against alien attack waves.

**Guiding principle:** every system is standalone and modular â€” able to be toggled off without breaking anything else. Research best practices before building; no shortcuts.

**Tech stack:** Godot 4.7 + Zylann's voxel module (1.7), Gaea for terrain generation, Blender for 3D assets (glTF export), Claude Code for all development work.

---

## Current Implementation Status (as of 2026-09-07)

This section tracks what's actually been built vs. what's planned, to distinguish design intent from current state.

### Shipping / Validated (Ready for playtest)
- **Slice 1 mining/building loop** â€” dig, place blocks, build structures on a spherical voxel planet (40m world radius)
- **Radial gravity and spherical terrain** â€” player moves all the way around the planet, gravity pulls toward center
- **Ore generation** â€” 6 ore types embedded procedurally with per-ore depth tiers
- **Refining chain** â€” ore â†’ processor/smelter â†’ ingot â†’ placeable block
- **Conveyor system** â€” tick-based pipe network with merger/splitter logic, grid-cell lookup
- **Building placement** â€” grid-snapped via Metal Foundations, free-placement as fallback, both orient tangent to terrain
- **Sky/atmosphere/fog per-planet** â€” data-driven `PlanetAtmosphere` resource, swappable per body
- **Multi-body physics foundation** â€” `CelestialBody` (data), `Planet` (scene), `PlanetPhysics` (registry); proven with two simultaneous planets
- **Projectile physics** â€” real ballistic flight with gravity + atmospheric drag, swept raycasts for collision
- **Turret buildings** â€” two variants (gun: fast/single-target; cannon: slow/splash), targeting via group + duck-type, ammo system with per-type compatibility
- **Scout ship threat** â€” crystal ore drives radiation signature; scout ship spawns at Low tier, targetable by turrets; kills before escape prevent escalation
- **Ship physics** â€” `Ship` RigidBody3D with thruster/gyro allocation, shared controller for player + AI
- **Quest system** â€” 7-quest tutorial chain with tech-tree UI, data-driven objective types
- **HUD + UI state management** â€” compact HUD auto-hides during modals, centralized `UiState` registry

### Ahead of Schedule (Built before Alpha scope called for)
- **Ship system** â€” full `Ship` RigidBody3D physics with mass/inertia from grid blocks, thruster/gyro allocation (originally 1.0 Release scope, now Alpha-validated)
- **Volumetric projectiles** â€” real ballistics instead of hitscan (Beta scope, now in use)
- **Radiation threat foundation** â€” crystal ore + signature tiers + scout mechanics (not in original roadmap; added as Slice 2 foundation)
- **Multi-body planetary physics** â€” `CelestialBody`/`Planet`/`PlanetPhysics` (1.0 Release scope, Phase 1 now shipped)

### In Progress / Known Gaps

**Terrain generation** - **REWRITTEN, see `terrain-generator.md`**
- The `VoxelGeneratorGraph` port shipped 2026-09-09. Time to walkable ground went
  from 40-60 s to ~5 s; the generator now runs compiled in C++ over whole blocks
  with automatic range analysis instead of per-voxel GDScript.
- Shape comes from a baked, hydraulically eroded heightmap (Phase 1), with noise
  demoted to sub-pixel detail - the Space Engineers 2 arrangement.
- Biomes and ore veins are expressed as per-material weight layers rather than
  branches, so borders blend instead of stepping.
- **Still not ported:** slope-driven cliff rock, which needs a surface gradient
  the graph has no node for against a heightmap.
- **Still not built:** the Phase 2 3D detail layer (overhangs, caves, arches).
  The terrain is 2.5D - eroded and varied, but nothing overhangs.
- Planet is 1 km diameter at SE2's 1 m voxels. The 2 km rung was reverted while
  the GDScript generator was the bottleneck; that bottleneck is gone and the
  rung has not been retried (see Scale Ladder below).

**Fixed 2026-09-07 â€” concentric ring banding on the starter planet.** Two
independent causes, both measured before and after rather than assumed:

1. *Climate was latitude-locked.* `temperature` used `1.0 - abs(dir.y)` at
   weight 1.0 against a wobble noise at weight 0.15 â€” measured 6x to 112x
   weaker than the term it was supposed to break up. Biome borders therefore
   fell on lines of constant latitude, i.e. concentric rings around the world
   Y axis, which is why the planet read as layered along one axis rather than
   spherical. Now a 3D climate field (noise 0.65 / latitude 0.35) so latitude
   is a trend, not geometry.
2. *Climate noise frequency was wrong for its input domain.* Both climate
   noises ran at `frequency = 0.5` but are sampled on the **unit-sphere
   direction**, whose whole domain is only 2 units across â€” that is about
   three features over an entire planet. Raised to 2.0 / 2.6. **This is the
   general gotcha: a frequency tuned for world-space sampling is meaningless
   when the input is a normalized direction.** The height/detail noises were
   already correct (1.8 / 9.0); only the climate pair was wrong.

Also fixed alongside: the roughness `slope` term saturated at ~0.9 everywhere
(a `* 0.5` where the height noise's own gradient is ~1.8), pinning roughness
into its top half and starving every low-roughness biome â€” `regolith_plains`
never appeared at all. And all six ores had `depth_min` of 0.5-1.0, so ore
occupied the *topmost* voxel and speckled the visible crust; raised to 3.0
(crystal already 8.0).

Verified by sampling 240 Fibonacci-sphere directions: ore visible on surface
0 (was non-zero), all four biomes present at 44.6/21.3/19.6/14.6%, and every
latitude band now carries 3-4 mixed materials instead of one. Still open and
*not* addressed by this: hard per-cell material edges when digging, which need
`TEXTURES_BLEND_4_OVER_16` + a weights channel, and the block-seam spikes.

**Save system** - **BUILT 2026-09-10**, see the Save/Load section in
`gameplay-systems.md`
- Main menu is the entry scene: slot list, New Game, Delete. Esc opens a pause
  menu (Resume / Save / Save and exit to menu / Save and quit).
- Per slot: `state.json` (inventory, quests, placed objects and their contents,
  ships and their block grids, player transform, playtime) plus one
  `VoxelStreamSQLite` per body holding **edited blocks only**.
- Verified by a scripted round trip and by driving the real menu flow end to end.
- Not saved on purpose: enemy ships (ThreatDirector's, not the player's).
- Open: once floating origin lands this needs true double-precision positions and
  orbital elements rather than render-relative offsets.

**Biome system**
- Designed in detail (see Biome System section below) but not implemented
- Requires generator rewrite (noted above) as prerequisite

**Atmosphere visuals** â€” **BUILT 2026-09-07**, see the Atmosphere System section
- Raymarched single-scattering pass covers ground sky, aerial perspective, orbital limb and the fade on leaving the atmosphere in one integral
- Proxy spheres and `Environment` fog both deleted; `PhysicalSkyMaterial` was evaluated and rejected (world-Y-locked horizon, unusable on a sphere)
- Still missing: volumetric clouds, re-entry heat shimmer â€” both blocked on the Weather system's dynamic-pressure/Mach inputs

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

### Alpha 1.0 â€” core loop only
**Current state:** Save/load and the terrain generator rewrite have both landed. Remaining Alpha gaps are wave scaling and personal weapons.

Goal: prove the loop is fun before investing in any large-scope system.

1. âœ… Single-planet voxel terrain (spherical, radial gravity) â€” **SHIPPED**; generator rewritten to `VoxelGeneratorGraph` on an eroded heightmap base
2. âœ… Mining/building loop â€” **SHIPPED**
3. âœ… Basic factory/logistics chain (5 ores, refining, conveyor) â€” **SHIPPED**
4. âš ï¸ Basic combat (personal guns not built; one turret variant, scout ship, projectiles) â€” **PARTIAL** (ships/projectiles built; wave scaling not)
5. âŒ Save/load â€” **NOT STARTED** (infrastructure ready, not wired)

Explicitly deferred past alpha: floating origin/interplanetary flight, full atmosphere/weather, ore injectors, foliage scatter, high-tier radiation, underground, full biome matrix, asset-generation pipeline. Build their *interfaces* now so nothing is architecturally blocked later; implement the guts post-alpha.

### Beta â€” fill out systems, still single-solar-system-local
- Full terrain system: VoxelGeneratorGraph rewrite, biomes via surface rules, proper shader polish
- Foliage scatter system (via `VoxelInstancer`)
- Full atmosphere system (raymarched orbital limb + re-entry effects, not just skybox)
- Weather system (scale-height density model, Mach-driven effects)
- Blender + agent building-generation pipeline (replace placeholder blocks)
- Expanded factory/logistics (more resource types, more building tiers)
- Expanded combat (personal weapons, enemy variety, wave spawning tied to crystal/power)
- Player character rigging (Rigify + Mixamo locomotion)

### 1.0 Full Release â€” large-scope systems
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

> **That gate is now open and UNTESTED.** The graph port shipped 2026-09-09 and
> is 13-61x faster on the same blocks. The 2 km rung has not been retried since,
> so it is not "known to work" - it is "no longer known to fail for the reason it
> failed before." Retry it with a measurement, not an assumption, and raise
> `VoxelViewer.view_distance` first (still open, see below).

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


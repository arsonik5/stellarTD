# Project Brief: Voxel Factory Defense Game

## Concept
A hobby game combining:
- **Space Engineers** — voxel-based, deformable terrain/planets, real mining
- **Satisfactory** — deep logistics/automation, conveyor-based production chains
- **Mindustry** — factory output directly feeds combat (turret ammo economy), wave-based enemy pressure tied to base output/power draw

Long-term persistent world (Satisfactory-style), with periodic wave combat (Mindustry-style) rather than constant threat.

## Tech Stack

| Layer | Tool |
|---|---|
| Engine | Godot 4.x (latest stable) |
| Voxel terrain | Zylann's Voxel Tools (godot_voxel GDExtension) |
| Terrain reference/heightmaps | Gaea |
| 3D models | Blender (glTF export → Godot import) |
| Code editor | VS Code + Claude Code extension (+ godot-tools extension for GDScript) |
| Language | GDScript (default) or C# if performance-heavy code needs it (requires Godot Mono/.NET build) |
| Version control | Git (GitHub/GitLab repo) |
| Primary coding agent | Claude Code — architecture, core systems, complex logic, code review |
| Bulk/repetitive coding agent | Local Qwen via LangGraph harness — boilerplate, asset pipeline scripting, test generation, routine refactors |
| Agent context/memory | Qdrant (RAG store) |
| Local model serving | vLLM |
| Claude Code rate-limit continuity | Community auto-resume wrapper (e.g. claude-auto-continue / claude-auto-retry) or custom bash retry loop |

**Role split**: user sets tasks, scope, and does testing/final approval. Claude Code handles architecture and judgment-heavy work; local Qwen loop handles repetitive/bulk work once patterns are established.

## Scope Philosophy
Deliberately staged — this is a large scope (voxel planets + factory logistics + tower defense) for a hobby/small-team project, so building in proven vertical slices rather than all systems at once.

## Slice 1 (current target): Voxel + Mining/Building Loop
**Goal**: prove the core "feel" before adding any combat.

- Small voxel **planet** (an actual sphere, ~40m world-space radius, noise-carved
  hills/craters) — sphere-wrapping was pulled forward into Slice 1 on explicit
  user request (2026-09-03) rather than staying later-stage; see
  `scripts/world/ore_generator.gd` (generator) and `scripts/player/player.gd`
  (radial gravity + surface-tangent movement/build camera).
- Player can dig (remove voxels) and place (add voxels/structures), and can
  walk/fall all the way around the sphere — gravity always pulls toward the
  planet center, not a fixed world axis.
- 5 ore types embedded in terrain, minable: iron, copper, sulfur, coal, silica
  (coal/silica added 2026-09-03, each with its own Processor/Smelter refine
  recipe producing an ingot, same pattern as iron/copper).
- Per-planet sky/sun/fog (`scripts/world/planet_atmosphere.gd` resource +
  `scripts/world/sky_atmosphere.gdshader`, added 2026-09-03) — a different
  planet is a different `PlanetAtmosphere` .tres, not a code change.
- Metal Foundation (`scripts/world/foundation.gd`, added 2026-09-03) — flat
  plates players snap edge-to-edge to build an artificial flat local grid on
  the curved planet, since a global axis-aligned grid doesn't exist on a
  sphere. Buildings still support direct-on-terrain placement as a fallback
  (both now correctly orient tangent to the local surface — this also fixed
  the "buildings placed sideways away from spawn" bug for the fallback case).
- Basic conveyor or simple inventory-carry to move ore to a processor
- One production chain: ore → refined material → placeable block
- No power grid yet, no combat, no UI polish

**Definition of done**: player can carve terrain, extract a resource, process it one step, and use the output to build something new — as a loop that feels worth repeating.

**Building-orientation follow-up from the sphere-conversion pass is now fixed
(2026-09-03)**: all buildings (foundation-mounted or direct-on-terrain) orient
tangent to the local surface everywhere on the planet — see the Metal
Foundation entry above.

**Still-open follow-up**: the Vacuum Pipe/Merger/Splitter conveyor system's
cardinal-direction math (`forward()`, upstream/downstream cell lookups in
`scripts/world/pipe_segment.gd` etc.) still derives directions from world-Y
90°-snapped rotation, same underlying issue the buildings just got fixed for.
Untested whether this actually breaks in practice for pipes placed on a
foundation far from spawn — not touched tonight since it wasn't part of what
was asked, but worth knowing before relying on long pipe runs away from the
spawn pole.

## Slice 2 (next, after Slice 1 is validated): Enemies + Waves
- Introduce enemy waves — **not started**: `scripts/world/enemy_dummy.gd` (`EnemyDummy`) added 2026-09-03 is a minimal stationary damageable test target (health + `take_damage()` + `"enemy"` group), not real enemy AI/movement/spawning
- Turret placement + ammo consumption tied into the production chain — **done 2026-09-03**: `scripts/world/turret.gd` (`class_name Turret extends Building`), two buildings (`turret_gun` fast/single-target, `turret_cannon` slow/splash). Targeting via group membership (`"enemy"`) + duck-typed `take_damage()`, so it'll work against whatever the real enemy system ends up being as long as it keeps that contract.
- **Volumetric/physics-based combat (2026-09-03, explicit user request)**: turrets no longer hitscan - they fire real `scripts/world/projectile.gd` rounds that fly with hand-integrated gravity+atmospheric-drag ballistics (`scripts/planet_physics.gd` autoload for shared gravity/air-density, air density itself pulled from the active `PlanetAtmosphere`). Each ammo type is a self-contained `AmmoType` resource (`scripts/data/ammo_type.gd`: mass/muzzle_velocity/caliber/drag_coefficient + damage/splash) - `iron_piercing_ammo` (fast, light, both turrets) and the new `he_shell` (heavy, splash, Constructor recipe from refined_material+gunpowder, cannon-only). Turrets carry a `compatible_ammo: Array[AmmoType]` list (not every turret accepts every ammo) and a per-item enable/disable toggle (`set_ammo_enabled`) so the player can lock out specific types without unloading them - both surfaced in `building_ui.gd`'s new ammo row. Modifier slots (pre-existing but inert `Building.modifier_slots`/`compatible_modifiers`) were made functionally real (click-to-carry, `set_modifier_slot`) but no modifier items/effects exist as content yet - the mechanism is wired, the content is undesigned. See `whatworks.md` for the ballistics/architecture writeup.
- Wave pressure scales with base output/power draw (Mindustry-style) — **started 2026-09-04**, but as a real lore-grounded mechanic rather than an abstract meter: see `radiation-threat-design.md` for the full corporate/crystal/alien-fleet design and its staged scopes. Scope 1 done: rare `ore_crystal` vein, `RadiationSignature` autoload (tier-driven off crystal held), and `EnemyScoutShip` (flies in, scans, flees with or without a report — killing it before it escapes prevents escalation). All enemies are starships, no ground troops, by explicit design. Scopes 2+ (the escalation fleet, High-tier constant war, the dissolve machine, containment barriers) are not started.
- Power grid becomes a meaningful attack surface — not started

## Later-stage systems (not yet scoped)
- Full power grid
- Advanced automation (multi-stage production, logistics networks)
- Full combat depth (more turret types, enemy variety, real wave AI)
- **Multi-planet/moons + open-space travel between them, no reload** (explicit
  user direction, refined 2026-09-04): one continuous space presented with no
  visible seam (streamed/LOD internally, not Astroneer/NMS-style instances),
  mechanical not physical travel limits (fuel/oxygen), a ship for real travel
  + later jetpack for short hops, one procedurally generated star system per
  save, and full persistence (dug terrain + buildings must survive leaving
  and returning — endgame is running bases across multiple planets at once).
  **Phase 1 done 2026-09-04**: the physics/generation layer is genuinely
  multi-body now (`CelestialBody`, `Planet`, generalized `PlanetPhysics`),
  proven with two simultaneous planets. Still not built: the star-system
  generator itself, floating-origin precision handling, the ship/oxygen
  systems, and save/persistence — each a separate substantial task, see
  `CLAUDE.md`'s "Architecture principles" section.

## Reference projects worth studying
- **Veloren** (open source, Rust/Bevy) — voxel world, persistent, base building, combat — closest existing analog to the target design

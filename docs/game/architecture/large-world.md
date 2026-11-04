# Large-world precision & scale

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


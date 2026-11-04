---
name: stellar-td-fp-building
description: "Stellar TD building is first-person Satisfactory style since 2026-11-04; the top-down build camera was deleted at Michael's request"
metadata:
  node_type: memory
  type: project
  originSessionId: 06af6e59-c7aa-4c8d-ac14-b8023a2089f8
  modified: 2026-11-03T23:40:14.029Z
---

2026-11-04 Michael: "building is shit for now. Delete the whole top down module and lets just make it like
satisfactory first person". Done in `scripts/player/player.gd` + `scripts/ui/build_ui.gd`:
- C enters build mode and opens the menu (mouse free). Picking a building closes it; Q reopens it.
- The ghost sits where the screen-centre ray hits (`_build_aim()`, physics ray 30 m, voxel ray fallback). The player
  keeps walking and looking. LMB places, R turns 90 deg, wheel turns 15 deg, G grid, B pipe straight/free.
  RMB drops a started pipe run, then leaves; C or Esc leaves.
- Only the open menu hides the HUD (UiState id `build_menu`). Crosshair and build key hints live on the HUD
  (compact_hud.gd); the ghost is the real meshes as a mint hologram. Rules: docs/game/ux-bible.md.
- Test: `scenes/dev/build_fp_test.tscn` (real input events; foundation snap + a pipe; 9 checks).

**Why:** Michael rejected the top-down camera outright.
**How to apply:** don't bring back a separate build camera. The build menu was redesigned the same day (categories,
baked icons, detail pane) per docs/game/ux-bible.md.

Related: [[stellar-td-ps2-look]].

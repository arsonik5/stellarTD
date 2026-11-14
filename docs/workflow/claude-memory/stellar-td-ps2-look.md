---
name: stellar-td-ps2-look
description: "Stellar TD's visual direction since 2026-11-04 is the PS2 aesthetic (Mafia 2002 / GTA SA era), carried by the assets at full resolution; no screen filters"
metadata:
  node_type: memory
  type: project
  originSessionId: 06af6e59-c7aa-4c8d-ac14-b8023a2089f8
  modified: 2026-11-03T23:40:08.602Z
---

On 2026-11-04 Michael showed TikTok clips ("how new york must feel like...": art deco penthouse, ballroom, Central Park
balcony, all in early-2000s console graphics) and asked what the aesthetic is called. Answer: the **PS2 aesthetic**
("PS2 core"). The clips are AI-made art-deco "old money" noir in that style. He wants Stellar TD in that look while
keeping what was built.

**Why:** the art direction Michael chose, not a technical limit.

**How to apply:**
- Render at FULL resolution. Two screen-level tricks were tried on 2026-11-04 and rejected the same day: Environment
  fog ("its all grey with the fog you can barely see anything") and a half-res bilinear pass ("the low res pass looks
  awful. render full resolution but get the textures and models to be styled"). `scripts/retro_look.gd` was deleted.
- The look lives in the ASSETS: the kit bake at 512 px with painted light (`PAINTED_LIGHT` in art_src/kit.py),
  strong silhouettes.
- **Superseded 2026-11-05** (Michael: "PS2 look everywhere BUT with modern technology, shading and lighting"):
  rendering is MODERN - per-pixel lighting (force_vertex_shading=false), PCSS soft shadows, SSAO/SSIL, glow, AgX
  tonemap, normal-mapped triplanar terrain. Planets: SE2 realism everywhere. See art-direction.md.
- If the look is changed, update docs/game/art-direction.md.

Related: [[stellar-td-buildings-grey]], [[stellar-td-parts-must-function]], [[stellar-td-fp-building]].

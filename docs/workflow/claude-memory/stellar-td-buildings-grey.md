---
name: stellar-td-buildings-grey
description: "Stellar TD (Godot, Documents/stellar-td) building models ship grey with Primary/Secondary paint slots; how buildings are made and judged"
metadata:
  node_type: memory
  type: project
  originSessionId: 06af6e59-c7aa-4c8d-ac14-b8023a2089f8
  modified: 2026-11-03T19:29:33.627Z
---

Stellar TD is a Godot 4.7 game at `C:\Users\Admin\Documents\stellar-td` (not `Documents\Projekty\StellarTD`, which only holds a `data` folder). Godot 4.7.2 was installed on 2026-11-03 at `C:\Tools\Godot\` (SHA-512 checked).

The whole workflow is now the skill `~/.claude/skills/blender-game-models/SKILL.md` (2026-11-03): start there.

Update 2026-11-03 (later): models are wired into the scenes (`art_src/wire_scenes.py`); building.gd / turret.gd / pipe_splitter.gd drive the animations; checks are `scripts/dev/check_building_models.gd` and `scenes/dev/model_showcase.tscn`. Michael asked "why are our tubes round but inputs/outputs are square?": every input/output is now the same round pipe port (`kit.machine_port`), and the merger is a round drum. Rule: one round pipe profile everywhere.

Also on 2026-11-03, these were added:
- **Pipes:** Satisfactory-style. They're modular (only the tube scales; collars and supports keep their size). B toggles STRAIGHT/FREE. Knees are generated in game for any angle in any direction ("not a pre-made bend"). Items flow through the knees.
- **Building pieces:** foundation 0.25 m, 1 m and 2 m, a frame foundation (beams), a ramp and stairs.
- **Animation reel:** `scenes/dev/anim_showcase.tscn`.

Details are in the skill's LESSONS.md.

Decision 2026-11-03: building models are grey by default. A Satisfactory-style paint tool comes later and recolors them.

**Why:** the paint tool owns color. Baked accents would fight it.

**How to apply:** two paint slots, `M_Paint_Primary` (mid grey) and `M_Paint_Secondary` (dark grey). Fixed slots: bare metal, dark rubber, hazard decal (yellow/black, hazard edges only), heat emissive, status emissive. Recorded in `docs/game/art-direction.md` ("Building color").

Pipeline (2026-11-03): `art_src/kit.py` is the shared kit; one generator per building in `art_src/<name>/<name>.py`. `sh art_src/build.sh <name> [views]` (from the repo root, Git Bash) builds, validates (tris/ngons/open edges/bounds), renders Eevee shots to `art_src/<name>/renders` and copies the .glb to `data/models/buildings/<name>/`. `art_src/README.md` has the table of origins, pivots and scene mappings. `python art_src/contact_sheet.py` makes the overview. Gotchas I hit: Blender needs Windows paths (`pwd -W`), never call `materials.clear()` on a joined mesh (it wiped the per-face materials), lathe profiles with both ends on the axis must skip the closing edge.

Later on 2026-11-03 Michael said the set was "still programeer art... random elements, and blocky aff look". The fix: kit.finish now bakes AO, edge wear and grime into a texture per model (paint keeps its colour as a factor). Chamfers were doubled, and random greebles (beacons, lugs, side screens, chevrons, hazard tabs) were removed, leaving one status strip per building. Rules are in art_src/README.md. Never add decorative bits that don't do something.

Then he said "Keep pushing" and gave reference images: a stylised tank with bolted clipped-corner armour plates and heavy edge wear, and a rusty layered sci-fi floor tile. He wants "procedurally wear and damage and stuff... this type of level of detail". The bar is Substance-style wear plus layered, plated geometry. Now in the kit:
- kit.plate (bolted armour plates);
- bake v2: chipped paint to bare steel, grime, rust, world-height dust, and an RM texture whose R channel is the paint mask;
- paint shader formula `D * mix(1, paint/default, RM.r)`;
- art_src/base_scene.py renders the whole set as an outpost.

Later he said the pipe connectors were "kinda fucked" ("look very closely") and that things still had a "boxy vibecoded look". What I did:
- All pipe/junction ends now use one kit.pipe_collar/pipe_port with the mating face on the cell edge.
- Housings and turret heads are lofts (kit.loft + squircle), the cockpit is a profile, and gussets brace the columns and towers.
- Before showing him anything, check geometry with art_src/inspect.py (10 close angles).

Michael also wants the buildings animated while working (2026-11-03). In the kit, moving parts are separate groups with pivots and parents, keyed with kit.spin/kit.swing and exported as glTF animations: `Working-loop` (loops in Godot) and `Fire` for turrets. The table is in art_src/README.md. Glow pulses are left to code. The Smelter is on the shared kit now (art_src/smelter/smelter.py, output SM_Smelter.glb).

Michael approved v2 of the Smelter on 2026-11-03 ("thats the spirit... Not perfect but its better. Good for now") and said to make the rest. All 16 were built the same day.

Michael rejected the first Smelter (2026-11-03) as "ugly as fuck... programmer art trash" and "not relevant to our game". It was a plain box stove, rendered in Workbench. The second version is a sci-fi induction smelter: container skid, crucible with glowing heat gaps, radiators, pipe dock, hazard chute. Judge every model in lit Eevee renders against that bar before showing him. Skills used: 3d-modeling, shader-programming, game-developer (`~/.claude/skills`), followed as written. Related: [[stellar-td-smelter-style]] (his verdict on v2, once given).

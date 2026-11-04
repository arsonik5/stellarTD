---
name: blender-game-models
description: Build game-ready industrial models (Satisfactory-like, grey and recolourable) with headless Blender Python generators, a part audit that fails the build on illogical parts, baked procedural wear, exported animations, modular pipes and foundation pieces, and wire them into a Godot game. Use when Michael asks to model, rebuild, fix or add a building/part/piece in Blender for Stellar TD (or any game using this pipeline), mentions "kit.py", "build.sh", the audit, wear bake, pipe ports, pipes/knees, foundations, or wants models checked or wired into Godot.
---

# Blender game models (Stellar TD pipeline)

Everything lives in the game repo: `C:\Users\Admin\Documents\stellar-td\art_src\`. Read these first, every time:
- `LESSONS.md` (next to this file): every rule, trap and fix found so far, in detail. Read it before modelling.
- `art_src/README.md` (workflow, shapes, animations, scene table, Godot wiring) and `art_src/FUNCTION.md`.
- `art_src/kit.py` (the shared kit) and `art_src/audit.py` (the part audit). Read a helper before using it.
- Memory notes `stellar-td-buildings-grey` and `stellar-td-parts-must-function`.

## Michael's rules (hard, from his feedback)

1. No programmer art: no stacked boxes, no boxy vibecoded look. Lofts, squircles, profiles, lathes.
2. Every part has a mechanical job. No job, no part. No armour for the sake of armour (panels are covers, vents or
   doors with a stated job).
3. Every part is mounted: bolts on bolted joints, a bead on every weld, fittings, clamps, base plates. Its size and
   position come from what it joins. Nothing floats, nothing merges into a neighbour without a joint.
4. "Its those details and things that overlap eachother etc that give it away" - overlaps are the tell.
5. Round pipe system, round ports everywhere (one collar profile).
6. Grey by default (paint slots PRI/SEC), Substance-level baked wear, working animations.
7. Look before calling it done: audit, renders, close-ups, in-engine shots.
8. Note everything down (LESSONS.md) so the next session starts where this one ended.

## The workflow (the audit enforces it; the build refuses to export with problems)

1. **Brief** in the generator docstring: what it does, what goes in/out where, the process chain.
2. **Blockout**: `sh art_src/build.sh <name> --blockout` - big parts only (no fasteners/welds), flat colour per
   declared part, `renders/blockout_*.png`, `parts.md` part sheet, audit. Undeclared parts render magenta.
3. **Declare every part**: `kit.part(prefix, job, on, joint, joins=())`. Joints: ground, seated, bolted, welded,
   clamped, hinged, pivot, through, inset (the last three may sink in). Kit helpers declare their own sub-parts.
4. **Hardware**: bolts (`bolts`, `bolt_ring`, `bolt_line`, plate corners), welds (`box_weld` for square parts,
   `weld_ring`, `weld_loop`, `saddle_weld`, `weld`), `fitting` where lines meet parts, `wall_bracket` to stand off
   walls, `housing_panel` for panels that follow a curved wall.
5. **Audit until clean**: `sh art_src/build.sh <name> --audit` (seconds). Errors: UNDOCUMENTED, NO MOUNT, FLOATING,
   CUTS INTO, NO HARDWARE, LOOSE BOLT/WELD, BURIED BOLT, HIDDEN. What each means and the usual fix: LESSONS.md.
6. **Full build**: `sh art_src/build.sh <name> hero back close` - bake, renders, glb copied to data/models/buildings.
   Read the renders yourself. A first-run pass is suspicious: check what the rules can't see (rings around pipes,
   rotation signs, parts outside the footprint).
7. **Engine**: Godot 4.7.2 at `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.
   - `--headless --path . --import`, then `--headless --path . --script res://scripts/dev/check_building_models.gd`
     (must end `failures=0`; autoload errors in --script mode are a harness artefact).
   - `--path . res://scenes/dev/model_showcase.tscn` and `res://scenes/dev/pipe_test.tscn` save screenshots to
     `art_src/ingame/`. Read them.
   - Animation reel: `--path . res://scenes/dev/anim_showcase.tscn --write-movie art_src/ingame/reel.avi
     --fixed-fps 30`, then ffmpeg (path in LESSONS/README) to mp4.
8. **Write it down**: new traps and rules into LESSONS.md, part jobs into FUNCTION.md, README table, memory.

## Coordinates and sizes

- 1 unit = 1 m. Buildings: origin bottom-centre; foundations/ship blocks/pipes: centre. Blender -Y = Godot +Z, so a
  script's +Y is Godot forward (-Z). Blender (x, y, z) -> Godot (x, z, -y).
- Footprints: 1.5 m machines, Smelter 2.0, Garage 3.0, foundation family 2.0. Pipe centreline 0.45 m.
- Pipe end profile: collar r 0.30 / bore 0.232, 0.07 deep, mating face where the next pipe starts.

## Kit map (art_src/kit.py)

Shapes: box, cyl (6-seg Bolt/Screw/Nut = real fastener), tube, octo, plate, recess_box, pipe, torus, lathe, loft,
squircle, zring/yring, profile, gusset. Assemblies: skid, housing (+HousingShape, housing_panel), pipe_collar,
pipe_port, machine_port, status_strip, ship_frame, foundation_block, deck_plate, wall_bracket, clamp, fitting,
base_plate. Welds: weld, weld_ring, weld_loop, saddle_weld, box_weld. Spec: part(). Export: assign/spin/swing/finish.

## Known traps (details and many more in LESSONS.md)

- Godot strips `-loop` from animation names; code matches `begins_with("Working")`.
- Housings: squircle seg 96; panels bisected at the loft creases; normals include the wall slope.
- `plate(clip=0)` breaks; plate corner bolts only when min(w, h) > 0.12.
- Never `python3` in Git Bash here; no `\n` in sed patterns; `cd` inside a backgrounded `&&` chain stays there.
- Don't commit unless Michael asks; the repo has unrelated uncommitted work.

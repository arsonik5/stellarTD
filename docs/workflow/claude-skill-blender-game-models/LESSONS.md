# Lessons log (blender-game-models)

Every rule, trap and fix found while building the Stellar TD set, in detail, so the next model is right first time.
Newest at the bottom of each section. SKILL.md links here; read this before modelling.

## Michael's feedback that defines "right" (verbatim where it matters)

- 2026-11-03: "why are our tubes round but inputs/outputs are square?" -> every connection uses the same round pipe
  profile (kit.pipe_collar / pipe_port / machine_port). No square chutes, docks or hubs anywhere in a round system.
- 2026-11-03, on a close-up of an output port: "Its those details and things that overlap eachother etc that give it
  away." Overlaps, parts merging into each other, rings stuck behind collars, belts running through ports: those are
  the tells, not polycount.
- "first getting the block out right ... even at the block out stage you have to think what each block is going to
  do", "every connection every detail also have to have sense and be a logical thing to add", "you can't just slap
  things one on top each other", armour plates "everywhere ... what purpose do they serve ... those plates are too
  little". -> no armour for the sake of armour; every panel has a job (cover, vent, door) or it does not exist.
- Wants a workflow that *forces* a checklist: every pipe, every piece, its connections, front/back/start, all with a
  logical explanation. -> the part audit (below) fails the build.
- "note everything you do down to detail so next time skill is perfect" -> this file.

## The workflow (enforced by tools, not by memory)

1. Brief in the generator's docstring: what the machine does, what goes in/out where, the process chain.
2. Blockout: `sh art_src/build.sh <name> --blockout`. Fasteners/welds/fittings are skipped (kit.BLOCKOUT), every
   declared part gets a flat colour, renders `renders/blockout_front/back.png`, writes `parts.md`, runs the audit
   (minus hardware checks). Undeclared parts render magenta.
3. Declare every part: `kit.part(prefix, job, on, joint, joins=())`. Longest prefix wins. A sub-part may leave on/joint
   None and inherits from the nearest shorter declared prefix. Kit helpers declare their own sub-parts.
4. Detail + hardware: bolts on every bolted joint, a bead on every welded joint (`box_weld`, `weld_ring`,
   `weld_loop`, `saddle_weld`), fittings where lines meet parts.
5. `sh art_src/build.sh <name> --audit` (4 s, no bake) until `0 problem(s)`. Then the full build (the full build also
   refuses to export with problems; `AUDIT=warn` only for WIP).
6. Look at the renders yourself (hero/back/close). The audit can't judge looks or missing function.
7. Godot: import, `check_building_models.gd`, showcase screenshots.

## The audit (art_src/audit.py) - what each error means and the usual fix

- UNDOCUMENTED: no kit.part() covers it. Declare it with a real job, or delete the part.
- NO MOUNT: on=None, or `on` names nothing. Note `on` matching: if a declared prefix equals `on` and objects carry
  that entry, only those match; otherwise any object whose name starts with `on` (groups like "Skid", assemblies
  whose sub-parts carry the declarations like "RadBracket").
- FLOATING (> 1.5 mm from its mount): measured from vertices AND face centres (a flat foot on a curved wall touches
  mid-face). Usual causes: a part sized to a wrong dimension, a box centred on a surface instead of resting on it,
  forgetting a housing's bulge/taper.
- CUTS INTO: two parts sink > 2.5 mm into each other without a joint allowing it. Allowed to embed: through, inset,
  pivot (and joins=). Thin parts passing clean through are caught by an edge-crossing test (reported as 10 mm).
- NO HARDWARE: bolted part with no fastener on it or its sub-parts; welded part with no bead touching it and its mount.
- LOOSE BOLT / LOOSE WELD: fastener touching nothing; weld touching fewer than two parts.
- BURIED BOLT: a fastener deep (> 4 mm) in more than the one part it fastens. Fittings (union nuts) may sit in 2
  (the pipe through them + the part).
- Joints: ground, seated, bolted, welded, clamped, hinged, pivot, through, inset.

## Audit implementation traps (fixed, keep them fixed)

- Read matrix_world only after `bpy.context.view_layer.update()` (clamp bands are placed via matrix_world).
- Inside test = nearest-face normal AND ray parity; points on a surface are unreliable, ignore depths <= 1.25 mm.
- Edge-crossing test must check the midpoint of the in/out stretch is > 2.5 mm inside, or edges grazing a face
  (seated parts) give false positives.
- Gap test must sample face centres, not just vertices.
- `related()` returns the most permissive joint among both directions and joins.

## Kit traps (fixed)

- `basis(normal, up)` with up parallel to normal produced garbage (clamp on a vertical pipe). Now falls back.
- `plate(..., clip=0)` makes duplicate corner vertices -> broken normals -> false audit hits. Use clip >= ~0.02.
- `plate()` only adds corner bolts when min(w, h) > 0.12; small plates need manual bolts (or the hardware check fails).
- `ship_frame` beams must be slimmer than the corner nodes in BOTH cross axes (`[B-0.04]*3`), or welds have nothing
  to sit on and panels hit the beams.
- Lofted housings are faceted: use `squircle(..., seg=96)` for housings so parts placed on the analytic surface
  (HousingShape) touch the mesh.
- Panels on housings: build in (u, v, offset) space, bisect into a 4 cm grid AND at the loft's crease heights
  (HousingShape.keys), then map every vertex onto the wall. A flat panel on a curved/tapered wall gaps or sinks.
- HousingShape.at() normal must include the z slope (numeric derivative), or anything tall sinks at one end
  (hinge pins, brackets) on tapered pedestals.
- Never `python3` in Git Bash here (Windows Store stub hangs). Edit files with the Edit tool or sed.

## Design rules learned per kind of part

- Ports: neck welded THROUGH the housing wall (machine_port) - a flat flange on a curved wall can't sit flush and
  hits the base trim. Lit output = band set INTO the collar rim, never a ring behind the collar (it hit the panel).
- Belts and trims must not run through ports: drop the belt (crafter) or keep ports below it.
- Junction drums: four necks of r 0.252 on a drum of r 0.34 overlap each other inside; drum r 0.37, neck start 0.26
  (between 0.252 and sqrt(R^2 - r^2)), rim r <= collar back (0.38).
- Things on walls stand off on `wall_bracket`s (foot plate bolted to the wall along its normal, arm welded both
  ends); posts go where the bracket arms end.
- Coolant goes to what needs cooling (the induction coil band), radially, with fittings at both ends.
- Feed lines end in a welded nozzle with a flange they bolt to; never at a bare surface.
- Hoods/lids/covers need their own flange to bolt through.
- Frames (cells, containers, ship blocks): rails/sills between post faces, never through posts; posts on bolted feet
  (feet big enough for bolts clear of post + weld: >= 0.18 for a 0.06 post); glass panes between the frame members.
- Rotating heads (turrets) are fed from the centre: ammo chutes go into the fixed pedestal, never into the slew ring.
- Slew: outer race bolted to the pedestal, turntable (pivot) inside it, head deck above the race bolts.
- Recoiling barrels slide in a shroud/sleeve welded to the mantlet; the mantlet is welded to the cradle with a
  weld_loop round the cradle's front ring.
- Ship blocks: welded frame + one panel per face (the hull's armour IS its job; small plates are not).
- Arms/robots: check the rotation sign (the crafter arm leaned backwards into the glass); clevis cheeks carry axles.
- Stands (junctions, pipes): base plate on the ground, post welded, body welded on top.

## Added later on 2026-11-03 (same session)

### More audit rules (each one caught a real defect the earlier rules let through)
- BURIED BOLT also fires when > 50% of a bolt's vertices are inside ANY part. The garage deck bolts sat flush on the
  deck but entirely inside the tower foot plates. Small depth, still invisible and useless.
- HIDDEN: a part with >= 95% of its vertices inside another part (and its bbox inside the other's) is an error.
  It caught foundation cladding ribs buried in the cladding, and port throat discs whose rim sat inside the neck wall.
- Throat/bore discs: radius = bore radius minus 0.3 mm, never bigger than the bore.
- A model that passes on the first run is suspicious: look at the close-ups and think about what the rules can't see.

### Pipe system (art_src/pipe/pipe.py + scripts/world/pipe_segment.gd + pipe_knee_mesh.gd)
- Modular, never stretched: the glb has separate meshes. SM_VacuumPipe (glass + rails, exactly 1 m, the only thing
  scaled, along its length to span - 2 collars), _EndIn/_EndOut (collars, origin on the mating face, placed at
  +/- span/2), _SupportHead (clamp, repeated every <= 2.5 m), _SupportPost (origin at its top, scaled down to the
  ground found by raycast), _SupportBase (origin on its underside, put on the ground).
- The game reads the post's top and length from the model (node position, mesh AABB), not from constants, so art
  changes can't desync it.
- Supports only on pipes within 30 deg of level. A riser with a stand beside it looked absurd; risers hang on knees.
- Supports retry for up to 10 s when no ground is hit (terrain collision streams in after a load).
- Knees are generated in game (PipeKneeMesh), bent to exactly the angle between the two pipes, any direction:
  circular arc of radius 0.6 on the centreline, straight 0.07 collar stub at each end, the pipe's own EndIn/EndOut
  collars copied onto both ends (collar meets collar at every joint). Leg per side = 0.6 * tan(angle/2) + 0.07.
  Limits: no knee under 2 deg, refuse over 150 deg, refuse if either pipe would be shorter than 0.5 m.
- Placement maths lives in ONE place: PipeSegment.knee_leg_for() + PipeSegment.lay(). The upstream pipe is shortened
  at its output end (its input end stays put, its own inlet knee's local joint shifts by -leg/2 on z).
- Everything is computed on the CENTRELINE (0.45 m above the build plane), never on the ground line: on slopes the
  pipe's local up tilts, so ground-line points don't meet.
- Build modes: B toggles STRAIGHT (level or vertical) / FREE (any angle). Shown by an on-screen label.
- Items: speed 5.4 m/s along the whole path (knee arc then straight). Pipe-to-pipe links come from geometry
  (relink_all: output point within 5 cm of an input point), rebuilt after every placement and after loading, never
  saved. Buildings are found by footprint (a point just past a pipe end lies inside the connected building).
- Saved per pipe: span, grid cell, inlet knee (joint + upstream direction, pipe-local), item in transit.
- Test: scenes/dev/pipe_test.tscn lays level -> 15 deg slope -> 90 deg turn -> 45 deg diagonal -> vertical, sends an
  item through (it must reach the last pipe) and saves art_src/ingame/pipe_*.png.

### Michael on the pipes (2026-11-03)
- Wants Satisfactory pipes: straight mode, 90 deg corners, and free angles "essentially infinite angles ... a knee
  part that can rotate or bend in any direction ... not modular bend already part but part that bends however the
  game needs". And pipes that "stretch modularly to keep its shape".
- "pipes half done though" + a close-up of the support: the strap was a bare ring floating ~2 cm off the glass,
  touching only the rails. Fixed with a real clamp: rubber liner gripping the glass (rails run through it),
  lower half-band on the cradle, bolted top strap with flanges on the cradle ears. Lesson: any ring/band around a
  pipe must touch the pipe all round (liner, saddle or shaped bore); the audit can't see a gap to a part that isn't
  the declared mount, so check rings around things by eye.

### Building pieces (foundation family)
- kit.foundation_block(h): h <= 0.3 = four perimeter beams + deck; taller = corner posts, top + bottom ring beams
  welded between them, cladding set 2 cm into each side with pressed ribs, deck on top. Faces exactly on +/-1, +/-h/2.
- kit.deck_plate(): seamed deck with diamond tread set into it.
- Pieces: foundation (0.25), foundation_1m, foundation_2m, frame_2m (columns on bolted base plates, I-beams, Y beams
  bolted through end plates, gusset plates welded to columns with a bolted diagonal brace per side), ramp_1m
  (triangular stringers, sloped deck cut as a profile so it stays in the box, cleats, back plate), stairs_1m
  (stringers cut as a band under the nosing line, 5 treads welded in, nosing strips, posts + handrails).
- Game: Foundation has @export height + mountable. Snapped neighbours line up their TOP faces; the R key turns
  pieces in quarter turns; buildings never mount on ramps/stairs. Ramps/stairs use a convex wedge collision
  (Blender (x, y, z) -> Godot (x, z, -y)). Item ghost_size.y is the piece height.
- New pieces need: generator, scene (foundation.gd, height, mountable, collision, Model instance), item .tres,
  recipe .tres, preload in scripts/inventory.gd and scripts/ui/build_ui.gd, and check_building_models.gd.

### Tooling traps
- A background `cmd1 && cmd2 &` puts `cd` inside the subshell; later commands run from the old directory.
- Bash `sed -i` with `\n` in the pattern does not match across lines; use awk to splice blocks from a file.
- Godot `Basis.scaled()` scales in parent space; use `basis * Basis.from_scale(...)` for a local axis.

### Tools (first-person held items)
- art_src/tool_mining, tool_scanner, tool_build: origin = the hand on the grip, Blender +Y forward, real size
  (~0.4 m), small bevels (0.002-0.003; BEVEL_SCALE doubles them), bake_res=1024, DUST_AMT 0.2.
- build.sh puts tool_* glbs in data/models/tools/<name>, vehicle_* in data/models/vehicles/<name>, the rest in
  data/models/buildings/<name>.
- Player: Camera3D/ViewmodelTool (Node3D, scale 1.2 at (0.17, -0.22, -0.33)) holds MiningTool / ScannerTool /
  BuildTool instances; _update_viewmodel shows the equipped one; _process_tool_anims: drill 'Working' while the
  trigger is held (+ a 4 mm shake), scanner dish 1.5 s after each scan, build-tool rings while equipped.
- Check: scenes/dev/tool_test.tscn renders each tool as the player sees it (art_src/ingame/tool_*.png).
- Michael rejected nothing yet on the tools; a trigger guard that was a rod through the grip was cut by the audit
  (parts with no job and no joint are worse than no part).

### Vehicles
- Michael wants a space IFV and a buggy, "all vehicles with animated suspension and stuff that works in game".
- Start with --blockout and show him the renders + parts.md before detailing (his own workflow).
- Blockout renders: kit's 'front' camera is now on the +Y side (forward); it was swapped.
- IFV: faceted 10-point hull sections (belly, sponson underside over the wheels, sponson edge, sloped upper armour),
  belly vertical up past the wheel tops or the wheels cut the sponsons; wheels under the sponsons; turret on a ring.
- Buggy: tube space frame declared as one assembly (part("Frame", ..., joins=("Frame",)) so frame tubes may meet);
  upper arms pivot on shock towers (tubes leaning out to the shock top); shocks run arm -> tower top.
- In game: plan is VehicleBody3D + VehicleWheel3D, wheels/hubs/arms/shocks as separate meshes driven from wheel
  travel each frame.

### Recording an animation reel
- godot --path . res://scenes/dev/anim_showcase.tscn --write-movie art_src/ingame/reel.avi --fixed-fps 30, then
  ffmpeg (C:\Users\Admin\AppData\Local\Microsoft\WinGet\Packages\Gyan.FFmpeg_...\ffmpeg-8.1.2-full_build\bin) to mp4.

### Decision 2026-11-03: vehicles are modular, like the ship
Michael: "why are we even detailing this? we can use the same mechanics as our ship right. Just parts and make it
100% modular". So no hand-made IFV/buggy models: ground vehicles are built from 2 m grid blocks on the Ship system
(RigidBody3D + blocks, per-block force allocation). New block types needed: wheel module (raycast spring/damper +
drive + steer, its arm/hub/wheel animated from the real compression), plus seats/turret mounts reusing what exists.
The IFV and buggy blockouts are only references for what a player could build.

### 2026-11-04: one grid for ships and vehicles, parts as blockouts, PS2 look
- Michael: "smaller and make it synced with the bigger grid so we can interplace stuff. Like 50cm grid", then "a set
  of parts for car and so that grid is one - so you can place whatever you want whenever you want", parts with
  different quirks (sealed cockpit gives O2 from tanks, open seat doesn't; wheels vs landing gear; engine drives
  wheels; thrusters, RCS; Crossout-style chassis parts), "build them as blockout for now".
- Ship grid: CELL_SIZE 0.5, BIG = 4 (2 m blocks fill 4x4x4 and snap to the 2 m lattice), cell k spans [k, k+1) x 0.5,
  blocks keyed by their min-corner anchor, every cell mapped to its block, block.size_cells + collision overrides.
  Old saves: grid < 2 -> anchor = cell * 4 - 2. Full list + quirks: stellar-td docs/game/ship-parts.md.
- Blockout export: build.sh <part> --blockout now EXPORTS the glb (no bake) when the audit is clean, so blockouts
  are playable. Parts: art_src/parts_lib.py (one function per part), part_<id>/part_<id>.py calls build(id),
  models go to data/models/parts/. Scenes/items/recipes generated; registry scripts/data/ship_parts.gd.
- Wheel physics lessons: size each wheel's spring from ITS static load (lever rule over x/z about the centre of
  mass), not the average, or the light end tops out and lifts off under power; push tyre forces at the axle, not
  the contact patch; fade drive toward top speed; cap braking (half a g) or the tail lifts. A dev scene with no
  planet needs Ship.fallback_gravity (PlanetPhysics gives zero there).
- Look: PS2 aesthetic (Mafia 2002 / GTA SA era; the TikTok clips are AI art-deco noir in that style). Kept the
  models, shifted render + bake: force_vertex_shading in project.godot, kit bakes at 512 px with PAINTED_LIGHT
  (top light x deep occlusion baked into the albedo).
- Screen filters for the look FAILED twice on the same day: Environment fog greyed out the whole screen (the
  atmosphere pass is a full-screen quad at the far plane, fog paints over it), and a half-res bilinear pass
  "looks awful". Michael: render full resolution, put the style in the textures and models. So the look is an
  ASSET job: painted light in the bake, silhouettes, texture density. retro_look.gd is deleted; don't bring back
  a resolution or fog filter.
- Icons (2026-11-04): Stellar TD bakes item icons from the exported models in Godot, not in Blender:
  scripts/dev/bake_icons.gd (160 px, transparent, one three-quarter camera, one light rig, AgX) -> data/icons/<id>.png.
  After rebuilding any model, rerun it and --import. The painted-light bake is what makes them read well at 64 px.
  The build ghost reuses the same meshes as a hologram (ModelMeshes.extract), so a model's silhouette IS its preview.

# Open items

Player-reported defects, in the order they are being worked. Tick when the fix
is validated by capture or measurement, not when the code is written.

Raised 2026-09-12.

## Terrain shape

Measured with `scenes/dev/micro_hillshade.tscn`, which samples the generator's
real isosurface over a 120 m patch and reports slope over 1/2/8 m baselines plus
relief detrended over 4 m and 16 m. Numbers below are from the fixed gentle
patch unless they say steep.

- [ ] **1. No close-scale detail.** Confirmed and quantified: with the rock band
  off, relief detrended over 4 m is **0.09 m rms** - the heightmap is smooth at
  every scale a standing player sees, because one texel is 12.3 m of arc. The
  rock band was therefore the *only* source of rock-scale shape, and it ran at
  1.1 m over 7 m features (a 9 degree swell), gated by deposition alone - whose
  median on this planet is **1.00**, i.e. suppressed nearly everywhere.
  - Neither amplitude nor faceting changes its character: 2.5x amplitude gave
    deeper lumps of the same shape, and blending in a quantised copy at the
    band's own step moved the numbers by nothing. One wavelength is one
    wavelength.
  - **Done:** landform slope field (`_build_landform_slope`), rockiness gate,
    and a three-band stack (crag 20 m / rock 7 m / grain 2.6 m) each gated
    differently. Crag in isolation produces clumped outcrops with bare ground
    between - the right character. Still to tune: the gates, so crags fire on
    genuinely rocky ground rather than almost never.
- [ ] **2. Flat ground ("meadows") is wrong at both ends.** The wavy, liquid look
  is **not** the rock band - it is the erosion map itself. On gentle ground with
  every band off, the surface is visibly the map's **12 m texels**, bilinear and
  square-cornered, carrying 0.98 m rms at 16 m and nothing at all below 4 m.
  - **Done:** a dune band (130 m features, 4 m) gated on where rock is gated off,
    plus the grain band so a plain is not a mirror.
  - **Fixed 2026-09-12: crags were standing on the meadows.** Rockiness also
    rises on flat *scoured* ground, and the crag band was gated by rockiness
    alone. Measured on a 6 degree patch, the crag band was 0.73 of the 0.75 m rms
    relief below 4 m. Crags now also need landform slope
    (`CRAG_SLOPE_START/FULL`). Meadows dropped to 0.17 m rms; the steep patch did
    not change across two very different thresholds, so cliffs lost nothing.
  - **Still open - the meadows are not solved.** With crags off, flat ground is a
    fine even speckle plus faint regular diagonal banding from the dune band - the
    same water-like look at a larger scale. Adding an fbm band adds broader waves,
    not formations. User chose **craters + gentle swells** (2026-09-13).
  - **In progress:** the dune band is replaced by a warped OpenSimplex2S swell
    band (450 m, 5 m) and three sizes of craters (900 / 260 / 70 m cells), both
    gated to `1 - rocky`. Craters use cellular DISTANCE with an all-smoothstep
    profile - see the next bullet for why not Spots3D.
  - **`NODE_SPOTS_3D` is binary, not a falloff.** Probed
    (`scripts/dev/spots_probe.gd`): ~0.99 inside the radius, 0 outside, a hard
    step. The generator's comments said "highest at each blob's centre", and the
    old `crater_curve` mapped that value through rim and wall segments it could
    never reach - so every old crater was a hard-edged disc whose edge read as a
    ring. Comments corrected. Also probed: ZN_FastNoiseLite defaults to
    OpenSimplex2 with no 3D rotation, and its cellular CELL_VALUE return stayed
    constant across a line crossing several cells, so nothing relies on it.
  - **Crater radius has to be set against 3D geometry, not the surface.** The
    cellular feature points sit through 3D direction-space and the ground only
    grazes them: along 2 km of real surface the value never went below -0.68,
    so the ground stayed at least 0.32 cells from every point
    (`scripts/dev/cellular_dir_probe.gd`). At a 0.22-cell radius the 1.5 km
    hillshade measured the same with craters on and off. At 0.30 (rim to 1.35x)
    the plain shows pits, medium bowls and a few large soft ones, with no rings.
    Size variety falls out of the geometry: a point on the ground makes a big
    bowl, a grazing one a small shallow pit.
  - Watching: the small craters look evenly spaced. Real crater fields cluster
    and follow a steep size distribution. From 1 km in game the plain now shows
    soft craters; close zooms show smooth bowls with no rings.
  - **Tried and reverted: blending meadow landform toward `height_lo`.** Meant to
    remove the 12 m texel wobble. Measured gain on a meadow was nothing
    (0.23 -> 0.22 m rms at 16 m, images indistinguishable), and it changed the
    approved cliff whichever way it was gated - by `1 - rocky` (54 -> 50 degrees)
    and by the crag slope ramp (54 -> 48 degrees, relief peak 5 -> 9 m). The
    structural reason: the gate and the substituted landform both come from the
    coarse map, which is exactly the map that cannot see a cliff, so no gate
    built from it can protect cliffs from it. Reverted; steep back to 53.7 deg /
    1.93 m.
  - **Evidence over-read, worth remembering:** crag numbers on the steep patch
    did not move across two very different slope thresholds, and that was taken
    to mean the slope mask saturates on the cliff. It did not mean that - another
    gate in the product could have been the limiting one. A null result only
    rules out the term that was varied being the bottleneck.
  - **The eye-level "carpet" on gentle ground was the 7 m rock band.** Measured
    on the 6 degree patch: rock band off 0.17 -> 0.05 m rms below 4 m; grain off
    changed nothing. The band carried about the same absolute relief on the meadow
    as on the 54 degree cliff, because scoured flat ground reads as partly rocky.
  - **Change, pending user decision:** rock band gate is now rockiness times the
    crag slope ramp, with a 20% floor on flats. Meadow 0.17 -> 0.06 m. Cost: the
    cliff now measures identical to "rock band off" (0.28 -> 0.23 m below 4 m;
    16 m relief unchanged at 1.92 m), which means the coarse slope mask reads that
    face as near-flat. A small loss of finest detail on the approved cliff look.
    Alternative if that is not acceptable: a better cliff detector (e.g. a
    mid-resolution slope map), at a real load/streaming cost.

- [x] **7. Hairline seams in the baked landform - FIXED: the domain warp was
  folding.** `generate.glsl` displaced the sample direction by
  `warp_strength * noise`; at 0.35 that map stops being injective, so the field
  tears along a smooth curve. The tear is a one-texel slot with near-vertical
  walls, tens of metres deep at this relief, which the mesher renders as a fan
  of parallel corrugations - the "stretched texture" wedge in the captures.
  `warp_strength` is now 0.15.
  - **The risk scales with planet radius.** `frequency` is multiplied by
    `radius / 8000`, so a bigger body samples the warp at higher frequency and a
    strength that was safe at 8 km folds at 20 km. Raise it only with a fresh
    hillshade at the largest body in play.
  - Ruled out along the way, and worth not re-testing: hydraulic erosion (the
    seam is present with droplets fully disabled), and the missing erosion
    brush (the GPU port had dropped the offline baker's falloff disc; adding it
    back changed nothing visible, cost a GPU device reset from atomics
    contention, and was reverted).
  - **An 8-bit preview lied.** The first read of this was "the whole map is
    covered in a diagonal comb", taken from `erosion_homeplanet.png` - which is
    8 bits over 1615 m, i.e. 6.3 m per level, so it fabricates contour hatching.
    Judge the field through `micro_hillshade`, which samples the real float
    surface, not through a preview PNG.

## Measurement traps found this session

- **Godot's GPU adapter order is not stable between runs on this machine.** The
  same build measured 22 fps and 120 fps in consecutive runs; the slow ones were
  on the Intel iGPU. A "5x frame-rate regression" from the terrain work was
  entirely this. Always read the `Using Device #N` line before believing an fps
  number, and pass `--gpu-index` after checking which index is the NVIDIA one
  that run.
- **`generate_block` only evaluates the graph at integer voxel positions.**
  Sampling it at a rounded position returns the same value everywhere inside a
  cell, so any sub-voxel measurement built on it measures the rounding. The
  first version of `micro_hillshade` did exactly that and reported a 36 degree
  median slope over 1 m on ground that renders smooth. It now reads the lattice
  trilinearly, which is also what Transvoxel does.
- **A hillshade of a tilted patch saturates.** A 57 degree face renders flat
  white, so the rock detail the image exists to show disappears. `micro_hillshade`
  removes a least-squares plane before shading.

- **ComfyUI (port 8188) runs on the same 6 GB GPU and was up all session.** An
  fps "drop" to 59-95 reproduced across every framing including 12 km orbit,
  with no thermal or power throttling - consistent with it contending for the
  card. Frame-rate numbers are only trustworthy with ComfyUI and LM Studio
  models unloaded, which is the same rule the erosion timing notes already give.

- **Capture harness declared "playable" at 0.5 s twice** (2026-09-13), on a
  world that takes 11-14 s to stream; the first frame then showed boulders
  floating over no terrain. Ruled out: a loaded save (the harness never starts
  a slot, so the new-game spawn path runs, and `edit_db` was none). Did not
  reproduce on the next run (13.2 s, 789 waiting frames). `terrain_look` now
  prints, at the moment it declares playable, the wait-frame count, the save
  flag, and what a downward ray from the player actually hits - so if it recurs
  the log says which spawn path fired and whether the ground is terrain or a
  boulder collider.

## Surface material

- [ ] **3. Texture glitches and stretches.** Suspects: triplanar UVs are raw
  world position (±20 km, float32 precision), and the macro-variation sample is
  planar on `xz` so it smears on steep faces.
- [ ] **4. Material does not follow slope.** Wants: rocky, sharp, textured,
  genuinely 3D-looking rock underground and on steep faces; on gentler ground
  much less prominent - dusty moon surface with scattered detail.

## Scatter

- [ ] **5. Scanned-rock boulders read as random.** No relation to the terrain
  they sit on. Wants them clustered around rocky/broken edges and much rarer on
  flat smooth ground.

## Ore

- [ ] **6. Scanner finds ore in only one place.** All ore types share one
  `Spots3D` site field at 1400 m spacing while a scan cube spans 1024 m, so a
  scan sees at most one site and every ore in it stacks at the same point.

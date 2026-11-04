# Stellar-TD Art Direction Brief

Paste this whole brief at the top of any Claude conversation before asking it to design, describe, or generate a model/texture for this game. It's the single style source so unrelated assets built weeks apart still look like they belong to the same game. Update it (don't fork it) when a decision changes — see "Amending this brief" at the bottom.

## The game, in one line

Space Engineers' voxel mining/deformable terrain + Satisfactory's conveyor logistics + Mindustry's factory-output-fuels-combat loop, on small spherical planets, first-person, persistent world with periodic waves rather than constant threat.

## Art direction

**Reference point**: Satisfactory's industrial readability crossed with Mindustry's flat-shaded functional clarity — not Space Engineers' greebled realism, not a painterly or cartoon style. Assets should look like *engineering hardware assembled from a small kit of parts*, not sculpted organic shapes.

**Core principles, in priority order:**
1. **Readability beats detail.** A building's function must be guessable from silhouette alone at 10+ meters: a smelter looks like it heats things, a turret looks like it points and shoots, a pipe looks like it carries flow. Never sacrifice a clear silhouette for surface ornamentation.
2. **Kit-of-parts construction.** Every model is built from a shared visual vocabulary: bolted metal panels, exposed pipe/conduit runs, warning-stripe edges, small vent grilles, a consistent bolt/rivet size and spacing. New buildings should look like they were assembled from the same parts bin as existing ones, not designed independently.
3. **Function reads through color, not decoration.** Base chassis colors stay in the neutral/industrial family (see palette). Color is spent purely as signal: what's active, what's dangerous, what's flowing, what's ore-derived. If a color doesn't carry information, it shouldn't be there.
4. **Low-to-mid poly, hard-surface.** Target real-time voxel-game budgets — chamfered hard edges, no fine surface sculpting, no cloth/organic shading. Bakeable normal-map detail (panel seams, bolts, stencil text) over raw geometry detail.

## Palette (the whole game shares this)

- **Structural neutral** (70% of any building's surface): desaturated gunmetal grey / off-white panel, `#7A7E82`–`#C9CCCF` range. This is the "kit" color — every building starts here.
- **Signal accent** (function-specific, ~15-20% of surface): each building category gets exactly one accent hue, used on its active/glowing parts only (see per-category table below). Never mix two signal hues on the same object.
- **Hazard stripe**: black/safety-yellow diagonal stripe, used only at genuine hazard edges — turret muzzles, high-heat smelter faces, exposed ore-processing intakes. Not decorative.
- **Emissive** (glow, not painted color): used for power/active state only — a building that's on has a faint emissive accent-color glow at its indicator strip; off/idle has none. This is the *only* place pure saturated color or bloom-worthy brightness belongs.
- **Ore-derived materials** keep real-world material logic so refined output is recognizable: iron → dull steel grey, copper → warm reddish-brown/patina, sulfur → pale yellow-green, coal → matte black, silica → pale sandy translucent-grey. Refined ingots/casings read as a *cleaner, more saturated* version of their raw ore color — that's the entire "this got processed" visual story, don't invent new colors for refined states.

## Building color: grey by default, paint tool later (decision 2026-11-03)

A paint tool is planned (like Satisfactory's color customizer), so buildings ship **all grey**. This overrides the per-category accents below for building meshes:
- Every building is neutral grey in game. No baked amber/cyan/red on the model.
- Two paintable material slots, Satisfactory-style: `M_Paint_Primary` (big panels, mid grey) and `M_Paint_Secondary` (frame, trims, skid, dark grey). The paint tool recolors these two. Fixed slots that never take paint: `M_Metal_Bare`, `M_Rubber_Dark`, `M_Hazard` (yellow/black decal, hazard edges only), `M_Emissive_Heat`, `M_Emissive_Status`. Do not bake paint into an albedo texture.
- Shared kit (first used on the Smelter): container-style skid with corner castings, chamfered housing with recessed panels, corner posts and a mid belt, crane lugs on the deck, pipe dock at pipe height (0.45 m) with a bolted flange, hex bolts, radiator fin banks. It lives in `art_src/kit.py`; every building generator imports it. A `M_Glass` slot (alpha blend) is used where you must see inside: pipes (items travel through), the Crafter's work cell, the Ship Core and the Cockpit canopy.
- How to make or change a building: see `art_src/README.md` (one Blender command builds the .glb, validates it and renders review shots).
- Category identity comes from **silhouette and shape**, not color. Color-blind and dim-light readability already required this.
- Emissive status glow (on/off) stays a separate material from the paintable slot.
- The table below is kept as the intended default palette for the paint tool and UI icons, not for the models.

## Per-category signal accents

| Category | Signal accent hue | Why |
|---|---|---|
| Ore extraction / mining tool | none (raw ore keeps natural mineral color) | ore is the input, not a system |
| Processing (Processor, Smelter, Constructor) | warm amber/orange | "heat/transformation" association, shared across every refining building |
| Logistics (Vacuum Pipe, Merger, Splitter, Chest) | cool cyan/teal | "flow" association — matches the color convention players already expect from conveyor games |
| Combat (Turret gun, Turret cannon, ammo) | red | matches hazard-adjacent expectation, distinct from processing amber |
| Structural (Metal Foundation, undecorated blocks) | none — neutral only | foundations are inert; they should visually recede under whatever sits on them |
| Power (future grid, not yet built) | reserve: electric blue/white | not in use yet — do not assign this hue to anything else even opportunistically |

If a new building category shows up later, pick one new accent that doesn't collide with this table, add it here, and never reuse an accent across two categories.

## Scale & proportion

- Player is a standard human first-person scale (~1.8m eye height).
- Foundation plate is the base grid unit (`Foundation.SIZE = 2.0` engine units ≈ human-scale floor tile) — every building's footprint should be a clean multiple of one foundation tile so buildings look intentionally modular when placed edge to edge.
- Buildings should feel liftable-by-crane industrial equipment, not architecture — think shipping-container-adjacent scale, not building-adjacent scale.
- Turrets, chests, processors: roughly waist-to-head height on the player, so the player can see over them for aiming/wave visibility.
- Ores are irregular chunks, not gems — mineral-realistic, not stylized-fantasy crystal.

## Per-asset-type generation notes

**Terrain/ore materials** (used on the deformable voxel sphere): must tile/blend seamlessly at any scale since the terrain shader already layers procedural noise + latitude tint on top — deliver as flat albedo/roughness base material references, not a final baked look. Rock should read as raw, uncut mineral-bearing stone; ore veins should be visually distinct from host rock at a glance (this is a gameplay-readability requirement, not just aesthetic).

**Buildings** (Processor, Smelter, Chest, Constructor, Vacuum Pipe, Merger, Splitter, Metal Foundation): kit-of-parts rules above apply in full. Each needs a visually distinct silhouette even in grey-box form — don't rely on the accent color alone to differentiate two buildings, since color-blind players and screenshots-in-dim-light need shape-level differentiation too. Show clearly where input connects (visually distinct from) output.

**Turrets** (gun: fast/light, cannon: slow/heavy splash): silhouette must communicate rate-of-fire and payload weight at a glance — gun turret reads as slender/high rate, cannon reads as thick-barreled/heavy. Ammo box (shared Building inventory) should look like a magazine/hopper feeding the weapon, not a generic crate.

**Ammo/projectiles** (Iron Piercing Ammo, HE Shell): caliber and purpose should be visually distinguishable side by side — piercing rounds slender/pointed, HE shells stubbier/finned. Keep to the red combat accent plus the relevant ore-derived material color, no new hues.

**Atmosphere/sky** (`PlanetAtmosphere` resources, e.g. `default_planet`, `moon`): each planet/moon gets its own gradient + sun-glow parameters, but describe these as variations on one procedural shader system, not one-off bespoke skies — a request for a new planet's atmosphere should specify only what changes (gradient hues, sun color/size, fog density/color, ambient tint) against the existing shader, since the multi-planet architecture (see project's own CLAUDE.md) requires new planets to drop in via resource swap alone.

**Enemies** (currently just `EnemyDummy`, a placeholder — real enemy art isn't scoped yet): when this becomes real, it should read as a clear third visual language distinct from both the neutral player-built kit and the ore/terrain material logic, so a threat is unmistakable from a factory at a glance. Don't design this yet without confirming direction first — flagged here so whoever picks it up later doesn't invent it in isolation from this brief.

## What to avoid

- No painterly/hand-painted texture look (that's a different game's aesthetic entirely).
- No two buildings sharing a silhouette that only differ by texture — silhouette-only readability is the whole point.
- No accent color reused across categories (see table).
- No fine organic detail (cloth folds, skin, foliage-style noise) — everything is hard-surface manufactured equipment or raw mineral.
- No planet-specific one-off shader hacks — new planets are resource swaps on the existing atmosphere/terrain systems, not new code paths (per this project's own multi-planet architecture rule).

## How to use this brief

When asking Claude to design or generate a specific asset, paste this brief, then add only the asset-specific ask: name, category (for accent-color lookup), rough dimensions in foundation-tile units, and what makes this one asset functionally different from its neighbors. Don't restate style rules per-request — if a generated result drifts from this brief, point at the specific rule it broke rather than re-explaining from scratch.

## Amending this brief

Treat this file like the project's `mistakes.md`/`whatworks.md` logs: edit in place, don't create v2/v3 copies. If a generation session reveals a rule is wrong or missing (e.g. a new building category needs an accent, or the palette values need adjusting after a real render), update the relevant section here and note the date inline if the reasoning matters later.

---

## Space and sky — cinematic, not functional (direction set 2026-09-11)

The art direction above governs BUILDINGS. Space is a separate brief, and the
user's direction for it is explicit: **"cinematic look over flat playable
shit."** Distant bodies, the star and the sky are set dressing whose job is awe,
not readability, and they should be tuned toward reference photography rather
than toward a clean game-art look.

**References supplied:** ISS photography of Earth's limb with the Moon above it;
a real photograph of a star; sci-fi concept art of a huge banded planet filling
the sky over eroded badlands. What to take from each:

**The atmospheric limb is LAYERED, not a single haze.** In the ISS photographs
the band from ground upward runs deep orange/red, through pale white-yellow,
into cyan, into deep navy, into black — distinct bands, not one blue glow fading
out. This is reachable with what the scattering pass already has: separate
Rayleigh and Mie scale heights plus the ozone term, which is specifically what
produces the cyan-to-navy transition in the real photographs. The money shot to
judge against is a camera just above the atmosphere looking tangentially along
the limb.

**A star is a sharply bounded disc with a thin warm ring, not a ball of haze.**
Real stellar photography shows a hard white edge, an orange rim maybe a fifth of
a radius wide, and a modest halo — nothing like the broad diffuse fog the first
corona produced. `star_corona.gdshader` now keys its rim off distance from the
limb in STAR RADII rather than off the quad's normalised coordinate, so the rim
width stays put when the halo extent is retuned.

**Deep space has structure between the stars.** Black-with-dots reads as a void,
not a place. `starfield.gdshader` carries a faint four-octave nebula. The
important part is the FLOOR: fbm averages ~0.5 and never reaches zero, so raising
it to a power directly leaves a non-zero haze across the entire sky. Subtracting
a floor before the contrast curve is what produces genuine empty sky between
filaments — without it the sky reads as fog.

**Distant bodies must read as destinations.** Crisp silhouette, no faceting, and
large-scale surface markings. Bias LOD toward keeping detail at range and accept
the cost; "cheap until you approach" is the wrong trade here.

> Detail on a body at real distance cannot come from geometry at any sane LOD -
> it has to come from the MATERIAL. The silhouette is an LOD problem; the
> markings are a shader problem. Do not try to solve the second with the first.

**Terrain should read as landforms, not noise.** The concept art shows what is
wanted: tall spires, layered mesas, eroded badlands, and genuine flat basins
between them. Uniform bumpiness at every scale is the failure mode.

## Look: PS2 era (decided 2026-11-04)

The game's look is the **PS2 aesthetic**: early-2000s sixth-gen 3D, in the spirit of Mafia (2002) and GTA San
Andreas. The reference is Michael's art-deco "old money" noir clips. The models we built stay as they are; the look
comes from:
- **Render:** full resolution. A half-resolution pass was tried on 2026-11-04 and dropped the same day (Michael:
  "the low res pass looks awful ... render full resolution but get the textures and models to be styled"). Fog was
  tried too and dropped: the atmosphere pass already gives the haze. The look lives in the assets, not in a
  screen filter.
- **Lighting:** per-vertex (Gouraud), set with `rendering/shading/overrides/force_vertex_shading` in
  project.godot. Changing it needs a restart.
- **Textures:** baked at 512 px with the light painted in: lit from above, shaded underneath, darker in the gaps
  (`PAINTED_LIGHT` in art_src/kit.py). Grey paint and the paint tool work the same as before.

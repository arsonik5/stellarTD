# Star system & gravity

### Star System & Gravity â€” BUILT 2026-09-09

**Current State:** the star is a real body, not a light. Gravity is summed
over every body. Was: a `DirectionalLight3D` at a hardcoded rotation, plus a
disc painted into the sky shader at a constant angular size â€” nothing existed
at any position, so it could not be approached, could not occlude, and both
planets were lit as though the sun were in the same direction for each.

**Shared base type.** `CelestialBodyNode` now owns position, radius, surface
gravity, gravitational parameter, influence radius, atmosphere geometry,
irradiance and terrain access. `Planet` and `Star` both extend it, and
`PlanetPhysics` registers and queries through it rather than through `Planet`.
This is the build-once rule applied: a star *is* a celestial body, and giving
it a parallel implementation is exactly the drift that rule exists to stop.

**`StarBody` resource** â€” physical, not art-directed, same discipline as
`PlanetAtmosphere`. Radius, effective temperature, luminosity, surface
gravity, limb darkening, visual brightness. **Colour is derived from
temperature** via the standard blackbody approximation, normalized so
temperature changes hue without changing apparent brightness â€” a red dwarf and
a blue giant fall out of one number instead of needing hand-matched tints.

**Rendering.** `star_surface.gdshader` on a real sphere: unshaded, emissive,
limb-darkened (a real disc is dimmer at the edge; without it a star reads as a
flat cartoon ball), with slow convection granulation. Because it is geometry
it occludes, grows on approach, and is flyable-into. The painted sun disc was
removed from `starfield.gdshader` â€” it would double-draw, and being at
infinity it would show *through* the real star. The halo comes from
`Environment` glow rather than a fake corona shell, so the atmosphere limb and
any other emissive surface get it too.

**Light is derived, not authored.** `Star.gd` re-aims the `DirectionalLight3D`
from the star toward the player every frame and scales energy by inverse
square. A directional light is still right â€” clean parallel shadows, good
atlas behaviour â€” but its direction cannot be a constant once more than one
body exists.

**Scattering now takes a star *position*.** `atmosphere_scatter.gdshader`
derives sun direction and brightness per body inside its existing loop, using
the same `(reference/actual)^2` convention `Star.gd` uses for light energy, so
lit terrain and lit sky brighten and dim together. The single global
`sun_direction` uniform it replaced was wrong the moment two planets sat on
opposite sides of a star.

> **BUG, fixed 2026-09-09: the star rendered as a black sphere.**
> `star_surface.gdshader` uses `render_mode unshaded` and wrote its colour to
> `EMISSION`, leaving `ALBEDO = vec3(0.0)`. **Under `unshaded` Godot outputs
> ALBEDO directly and never runs the lighting pass, so EMISSION is never
> read.** The star was drawn perfectly - correct size, position and limb
> darkening - in pure black against black space. Any glow that appeared was
> the atmosphere's Mie forward-scatter, not the star.
>
> **Rule: with `render_mode unshaded`, write ALBEDO. EMISSION does nothing.**
> Values above 1.0 in ALBEDO are what the Environment's glow picks up as
> bloom, so HDR values there are what produce the halo.
>
> **Method note that mattered more than the fix:** five headless diagnostics
> confirmed the mesh existed, was `visible_in_tree`, sat inside the frustum at
> 4.65 degrees, and was well within the far plane - all true, and all useless,
> because "does it exist" and "is it visible" are different questions.
> Rendering real frames to PNG (`get_viewport().get_texture().get_image()`)
> and toggling one system between two captures found it immediately.
> **Headless cannot answer rendering questions; capture frames instead.**

> **BUG, fixed 2026-09-10: the star rendered as a flat white disc with no
> corona, identical at every distance.** Two independent causes, both outside
> the star shader:
>
> 1. `Environment.glow_blend_mode` was `SOFTLIGHT`. Softlight is a contrast
>    operator - over a near-black backdrop it returns near-black. A star's halo
>    lives entirely in the black sky *around* the disc, so the blend was
>    multiplying away exactly the pixels it was supposed to light. **ADDITIVE is
>    the only blend mode that can put light where there was none.** Godot's
>    default glow levels (3 and 5 only) also give a rim a few pixels wide rather
>    than a corona; levels 4-7 are what make it wide and soft.
> 2. `visual_brightness` was 8.0 against an ACES tonemap with `white = 6`.
>    Everything past ~5 resolves to the same white, so the whole disc clipped
>    and the limb law had nothing to act on. **Peak disc intensity has to sit
>    just above the white point (~3), not far above it.**
>
> `glow_bloom` is a trap here and must stay at 0. It is not a strength dial: it
> lifts the *whole frame* into the glow buffer regardless of `glow_hdr_threshold`,
> which with the star filling a third of the screen fogged empty space out to a
> flat milky brown.
>
> The disc also moved from a linear limb-darkening law to the quadratic
> `1 - a(1-mu) - b(1-mu)^2`. For a sphere `mu = sqrt(1 - (r/R)^2)`, which stays
> above 0.5 until 87% of the way to the edge, so a linear law crams all its
> falloff into the outermost few pixels and reads as flat regardless of `a`.
>
> Verified by capturing frames at 1400 / 5000 / 20000 m from the photosphere.

> **Follow-up, same day: the corona moved off Environment glow and onto the
> star.** Additive glow at a threshold low enough to give the star a halo also
> caught sunlit TERRAIN, which sits just above 1.0 in HDR, and washed the whole
> ground out to flat white; a threshold high enough to spare the terrain left
> the star a bare dot. One global knob cannot serve both, so the halo is now
> `star_corona.gdshader` - a camera-facing additive quad on the star itself
> (`StarBody.corona_ratio/intensity/falloff`), and `glow_hdr_threshold` sits at
> 2.5 where it only touches the disc.
>
> A billboard rather than a shell sphere, because a shell needs front faces from
> outside and back faces from inside and either choice is wrong half the time.
>
> **It also has to sort after `AtmosphereRenderer`, by a lot.** The scattering
> pass rebuilds the frame from a screen capture and writes `ALPHA = 1.0` - it
> REPLACES the frame rather than compositing over it, so any transparent object
> drawn earlier and missing from the capture is simply erased. That is why the
> corona was invisible with the atmosphere on and appeared the moment it was
> switched off. `sorting_offset` is subtracted from distance-to-camera, not a
> priority, and the atmosphere quad sits near the world origin while the star is
> kilometres away - beating its 1000 was not enough, hence 1e7 for "always
> last". Depth testing still occludes it correctly.

#### Gravity: summed, not nearest-wins (decided 2026-09-09)

`PlanetPhysics.get_gravity_accel()` sums inverse-square pull from **every**
registered body. The old model took the nearest body inside its influence
radius, at a fixed magnitude with no falloff, and exactly zero outside.

Why the change: a star's pull must reach across the system while "which
surface am I standing on" must not, so the two questions had to stop sharing
one answer. Summing also deletes the special case entirely â€” the zero-g void
between planets still happens, because 1/dÂ² from distant bodies is negligible
rather than artificially clamped.

`get_up()` deliberately still resolves against the **nearest** body, not the
summed gravity vector. Orienting to net gravity would tilt the player, their
buildings and the build grid slightly toward the star. "Up" is a surface-frame
question; gravity is not.

> **Consequence to know: gravity now falls off with altitude.** Measured on
> the home planet: 1.20 m/sÂ² at the surface, 0.77 at +50 m. The old model was
> flat at 1.20 everywhere inside the influence radius. This changes jump and
> jetpack feel with altitude and is worth a deliberate playtest.

> **CALIBRATION TRAP, hit and fixed during this work.** A star mass that
> *sounds* plausible wrecks surface play. At `surface_gravity = 14.0` the star
> contributed **0.60 m/sÂ² against the home planet's 1.2** â€” half of surface
> gravity â€” tilting local "down" by about 30Â°, measured as a 0.87 dot product
> against the local radial. At 0.15 it contributes ~0.006 m/sÂ² (~0.5%),
> comparable to the Sun's real 0.06%-of-Earth-g influence, and the dot is
> 0.99999. **Rule: a star's pull at any planet must stay well under 1% of that
> planet's own surface gravity.** Check with
> `surface_gravity * radiusÂ² / distanceÂ²`. This is a consequence of the system
> being spatially compressed (star ~4.4 km from the home planet, not 150 Gm)
> and will need rechecking whenever bodies are moved.

#### Heat interface (built now, damage later)

`CelestialBodyNode.irradiance_at()` and `PlanetPhysics.get_irradiance()` /
`get_dominant_star()` exist and are verified inverse-square. Nothing consumes
them for damage yet â€” that is the deliberate "build the interface, defer the
guts" pattern, so adding heat damage later is not an architectural change.

#### Scale caveat

Realistic proportions would put the star ~109Ã— planet radius and ~4.7 million
metres away, far past the 10 km jitter threshold in the scale ladder. The
current layout is compressed but self-consistent, and every derived number is
a function of `luminosity`, `radius` and `reference_distance`, so rescaling
later is data rather than code. True 1:1 still needs the floating-origin work
below.

**Verified headless:** 3 bodies register; surface gravity 1.1997 m/sÂ² aligned
0.99999 with local down; midway between planets 0.129 m/sÂ² pointing home; deep
void 0.0023 m/sÂ²; irradiance ratio at 2r vs 4r = 4.000 exactly; dominant star
resolves correctly; blackbody colour at 5772 K = (1.00, 0.95, 0.90); all four
shaders compile; smoke test clean. **Verified by frame capture (2026-09-10):** disc, limb
colour and corona all read correctly at 1400 / 5000 / 20000 m. **Still open for
a real playtest:** the star seen from the planet surface through the
atmosphere, and whether `luminosity` puts daylight at a comfortable level.

---


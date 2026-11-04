# Atmosphere & weather

### Atmosphere System â€” BUILT 2026-09-07

**Current State:** physically-based single-scattering atmosphere, raymarched
per pixel, all bodies in one pass. Replaced the previous sky-gradient shader,
`Environment` fog, and the translucent proxy spheres. Missing: volumetric
clouds, re-entry heat shimmer.

**Interacts with:** projectile drag (shares one density model), Weather
system (future), `PlanetPhysics` (body registry).

**Architecture â€” three pieces, each removable**
- `PlanetAtmosphere` (`Resource`) â€” pure data. Scattering coefficients, not
  colours.
- `starfield.gdshader` (`shader_type sky`) â€” deep space, stars, sun disc.
  Identical on every body and in the void; knows nothing about atmospheres.
- `atmosphere_scatter.gdshader` + `AtmosphereRenderer` (`MeshInstance3D`) â€”
  one full-screen pass compositing scattering over the finished frame.
  Nothing depends on the renderer existing; deleting the node or setting
  `enabled = false` removes atmospheric rendering and breaks nothing, per the
  standing "every system toggleable" rule. Air density lives on
  `Planet`/`PlanetAtmosphere`, so drag keeps working with it gone.

**Why one integral rather than separate systems.** Sky colour, haze on distant
terrain, the lit limb from orbit, and the fade on leaving the atmosphere are
all the same physical quantity. Computing them separately is what let them
disagree before. It is also why there is **no "up" vector anywhere** in the
new code â€” the pass intersects a sphere and integrates along the view ray, so
it is correct at every point on every body automatically.

**Bugs this fixed (all four confirmed by reading the old code, not guessed):**
1. **Sand-yellow sky dome.** `world.gd` set `fog_light_color` from the
   planet's sand `fog_color` but never set `fog_sky_affect`, which **defaults
   to 1.0** â€” so fog painted over the entire background. Leaving the
   atmosphere drove the density to 0 and revealed the real sky, which is
   exactly the transition that was reported. The moon looked fine only
   because it had `fog_enabled = false`.
2. **Sky gradient built on the world Y axis** (`up = EYEDIR.y`). Correct only
   at the north pole; tilted everywhere else on a sphere.
3. **Stretched stars.** `floor((dir.xz + 1.0) * 260.0)` projects a 3D
   direction onto a plane, squashing toward Â±Y into streaks. Stars are now
   hashed from a 3D cell on the unit sphere â€” roughly equal solid angle in
   every direction.
4. **`haze_color` never wired.** `PlanetAtmosphere` had no such field, so
   every planet got the shader's hardcoded blue haze.

> **CORRECTION to this section's previous recommendation:** it said to use
> Godot's built-in **`PhysicalSkyMaterial`** for ground-level sky. **That does
> not work for a spherical planet.** It hardcodes world +Y as up and a `Sky`
> has no transform, so its horizon stays locked to the world XZ plane while
> the player's actual horizon rotates as they walk around the body â€” it would
> reproduce bug #2 with no way to fix it. The shell raymarcher covers ground
> level too, which is why there is no separate ground-sky path.

**Per-planet parameters** (`PlanetAtmosphere`): `rayleigh_coefficients`
(vec3, ~1/wavelength^4; Earth â‰ˆ `(5.5e-6, 13.0e-6, 22.4e-6)`),
`mie_coefficient` + `mie_anisotropy`, `ozone_absorption`,
`rayleigh_scale_ratio` / `mie_scale_ratio`, `shell_radius_ratio`,
`scattering_energy`, `surface_air_density`, sun colour/energy/angular size.

Scale heights are stored as a **fraction of body radius**, not in metres, so
an atmosphere stays proportionate on a 200 m starter planet and a 60 km one
without retuning.

**One deliberately non-physical number.** `AtmosphereRenderer.irradiance_to_scatter`
(default 17.0). The coefficients are real per-metre values, but our bodies are
~200 m rather than Earth's 6371 km, so the optical path through a whole
atmosphere is thousands of times shorter and the integral comes out nearly
black. This constant buys that back. It is a **unit conversion, not a
brightness dial** â€” sky brightness is derived as
`star.irradiance_at(reference_distance) * irradiance_to_scatter`, so **tune the
star's `luminosity` to change brightness**, which keeps the sky, the
directional light and (later) heat damage all reading from one number instead
of drifting apart. Will need revisiting at each rung of the scale ladder.

(This replaced a standalone hand-set `sun_intensity = 4200`. The derived value
lands at 4192.6, a 0.18% difference, so the change is not a visual one.)

**Density model shared with gameplay.** `PlanetAtmosphere.density_at()` is the
single source for both the rendered atmosphere and `projectile.gd` drag, so
they cannot drift. Exponential falloff on the Rayleigh scale height, eased to
exactly zero over the top fifth of the shell â€” a bare `exp()` cut off at the
boundary still has ~6% of sea level left when it stops, which would step a
projectile's drag as it crossed.

**Multi-planet:** the shader loops over up to `MAX_BODIES` (4) fed from
`PlanetPhysics.get_all_bodies()`. Both bodies are marched in the same frame,
so flying between planets crossfades on its own â€” no reload, no CPU-side
blending. Vacuum bodies are skipped so an airless moon costs no shader slot.
**Raising the limit means editing both** `MAX_BODIES` in the shader and the
constant in `AtmosphereRenderer` â€” a shader cannot size uniform arrays from
GDScript.

**Verified headless:** both shaders compile (checked against a deliberately
broken control, so the check is known non-vacuous); the runtime uniform feed
pushes 1 scattering body with the moon correctly skipped, shell radius 250 m
against a 200 m surface, unit-length sun direction; density is continuous to
zero and preserves the old 1.225 surface value; full smoke test clean.
**Not verifiable headless:** how any of it actually looks, and the depth
reconstruction. The pass clamps every span with `min()` against the shell
exit rather than special-casing "no geometry", so it should be correct under
either depth convention, but that specifically wants an F5.

**Tonemapping is part of this system, not an unrelated setting.** The pass
outputs real radiance, which exceeds 1.0 on a bright limb. Godot's default
`TONE_MAPPER_LINEAR` hard-clips there, which showed up on the first playtest
as a limb that blew out to flat white while staying blue in its dimmer parts â€”
hue discarded exactly where the effect reads most. `world.gd` now sets ACES
with `tonemap_white = 6.0`. **Any future change to `sun_intensity` or the
coefficients should be judged with a tonemapper active**, or bright regions
just clip and the tuning is meaningless.

Ambient is a small constant colour rather than sky-sourced: the sky is
near-black space now, so sky ambient is effectively zero and anything on a
body's night side renders as pure silhouette, including the player's own ship.

**Still missing:** volumetric clouds, re-entry heat shimmer (both need the
Weather system's dynamic-pressure/Mach inputs).

**Gotcha hit while building this:** adding a new `class_name` needs
`--headless --path . --import --quit` before the class resolves; otherwise
scripts referencing it fail with "Could not find type X in the current scope"
even though the file is correct.

---

### Weather System â€” Beta Scope

**Current State:** `PlanetPhysics` autoload has `get_air_density(pos)` (used for projectile drag) but no full Weather system yet.

**System Principles:**
1. Modular â€” standalone, clean query APIs, zero hard dependencies back
2. Graceful fallbacks â€” if disabled or no atmosphere, returns vacuum defaults (density=0, pressure=0)
3. Performance first â€” lightweight per-frame queries across many entities

**Core data model:**
- Per-planet `Resource` (e.g., `WeatherProfile`): `radius`, `gravity`, `P0` (sea-level pressure), `scale_height`, composition, temperature gradients
- Stateless query API: `GetDensity`, `GetPressure`, `GetTemperature`, `GetSpeedOfSound`, `GetDynamicPressure`, `GetSunlightAttenuation`
- Exponential decay: `density = P0 * exp(-altitude / scale_height)`
- Mach number: `speed_of_sound = sqrt(gamma * R_specific * temperature)`

**Scaling:**
- Small moons/asteroids below radius/mass threshold: `P0 = 0`, `scale_height = 0` (vacuum, no fallback branching needed)
- Super-Earths/Gas Giants: higher `Hmax`, thicker `P0`
- Manual overrides for edge cases (e.g., Titan)

**Integration:**
- Projectiles: air density â†’ drag coefficient applied each tick
- Re-entry effects: dynamic pressure `q = 0.5 * Ï * vÂ²` and Mach number drive shock-cone/plasma vfx
- Audio: density â†’ acoustic attenuation; pressure â†’ wind/roar parameters

---

## Dark-side artifact: too few samples, not the dither

The atmosphere read as speckled/glitching on the night side. Three attempts, and
the two wrong ones are the useful part of this note.

**Wrong 1: the dither hash.** Replaced `fract(sin(dot(...)))` with Interleaved
Gradient Noise, on the theory that the sin-hash clumps and its blotches show
against a dark sky. IGN is genuinely better distributed and was kept, but it
changed the measured grain by nothing.

**Wrong 2: fading the jitter out on the night side.** Reasoning: dithering hides
BANDING, banding needs signal to be visible, the night side has none, so the
jitter was spending its whole error budget on speckle for no benefit. This was
backwards - it removed the dither and brought the stair-step bands straight
back, visibly worse. Reverted, and the dead helper deleted with it.

**Right: 24 view samples is too few for a limb ray.** A ray straight down
crosses a couple of kilometres of shell; a grazing limb ray crosses tens. The
same fixed 24 samples covers both, so the limb is sampled two orders of
magnitude more coarsely - and the limb is exactly where the artifact appears.
Dithering converts that error from bands into grain but cannot remove it.

`view_samples` 24 -> 64, plus scaling the count with the ray's span against the
shell diameter (resolution-independent, no per-planet tuning).

| | grain (mean 3x3 deviation, dark region) |
|---|---|
| jitter disabled | 0.40 - but as visible BANDS, not grain |
| 24 samples + dither | 1.22 |
| 64 samples + adaptive + dither | **0.56** |

Frame time was vsync-capped at 144 fps before and after, so nothing measured the
atmosphere pass as the bottleneck. Revisit if a GPU-bound target appears.

### Two measurement traps this hit

**Every capture framing looked at LIT ground.** The harness parks the sun
relative to the camera, so no existing shot could see a night-side artifact at
all. Two rounds of A/B came back "no change" because the region being measured
did not contain the thing being fixed. `terrain_look.tscn` now has a `nightlimb`
framing with the sun parked BELOW the horizon.

**The first night metric measured stars.** Restricting to dark pixels selected
mostly empty space, so the number was dominated by the starfield and moved by
nothing. The metric now crops to the atmosphere region and rejects bright
outliers, so stars do not enter it.

> And once again: a result identical to four decimal places means the change
> never took effect. Raising the shader's `view_samples` default did nothing
> because `atmosphere_renderer.gd` sets that uniform from its own export every
> frame, so the default was dead code. Same lesson as the unreimported `.glsl`.

### Raising the sample count made the atmosphere DIMMER

Going 24 -> 64 samples dropped the whole atmosphere by 11-17%:

| framing | 24 samples | 64 samples |
|---|---|---|
| air1km | 136.4 | 117.7 (-13.7%) |
| orbit12km | 84.1 | 70.0 (-16.8%) |
| ridge | 104.9 | 93.2 (-11.2%) |
| eye | 95.3 | 95.3 (0%) |

Not a bug in the new code - the OLD result was wrong. Attenuation uses the
optical depth accumulated so far along the ray, and with coarse steps that
accumulation lags, so `att` stayed too high and the atmosphere was
systematically too bright. More samples integrate it correctly, and correct is
dimmer.

The look had been tuned against the inaccurate number, so `scattering_energy`
was recalibrated 1.0 -> 1.3 on the home planet to put the brightness back where
it was judged good. Within a few percent on every atmosphere-heavy framing; eye
level lands ~7% high, because a scalar cannot exactly compensate a change that
affects long rays more than short ones.

> `eye` was the only framing that did NOT move, and that is the tell: at ground
> level there is almost no atmosphere in shot. A regression check that had only
> looked at the eye shot would have reported no change at all.

**The moon must stay at `scattering_energy = 0.0`.** It is airless. A blanket
recalibration across both atmosphere resources briefly gave it an atmosphere -
caught only because the value was being read back after writing it.


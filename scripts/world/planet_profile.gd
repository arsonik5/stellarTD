class_name PlanetProfile
extends RefCounted

## Terrain parameters DERIVED from a body's physical properties, rather than
## authored per planet.
##
## This exists because 1.0 Alpha generates planets procedurally. Any constant
## tuned against one body - "relief is 36 m", "continent noise runs at 1.8" -
## is wrong on the next one, and hand-authoring every planet is exactly what
## procedural generation is supposed to remove. Everything here is expressed
## relative to the body's own radius and orbit, so a 300 m moon and an 8 km
## world both come out sane from the same code with nothing to retune.
##
## Nothing here is a look decision that a designer should be overriding per
## planet. The knobs that ARE authorial - biome palette, ore mix - stay on
## `CelestialBody`.

## Earth's real peak-to-trough relief as a fraction of its radius: Everest
## +8.849 km, Challenger Deep -10.935 km, radius 6371 km, so 19.78 / 6371.
## Every body's relief is a multiple of THIS rather than an invented fraction,
## so "how dramatic is this planet" is one honest number instead of a tuning
## constant nobody can sanity-check.
const EARTH_RELIEF_FRACTION := 0.003105

## How far to exaggerate Earth's ratio. Planets stay in a believable band;
## small bodies go much further because real ones genuinely are more irregular
## relative to their size - they lack the gravity to pull themselves smooth
## (Vesta, Phobos, Hyperion are lumpy in a way no planet is).
## 65x Earth's relief ratio. Chosen by measuring SLOPE IN DEGREES, not by
## picking a ratio and hoping - the instrument is `Planet._log_slope_profile()`.
##
## Measured on the 4096 map (metres of arc per texel = 12.3):
##
##   exagg   relief    mean    p50     p95     p99    unwalkable (>45 deg)
##    20x     497 m    5.5     3.0    20.2    29.3      0.0%   - gentle
##    32x     795 m    8.6     4.8    30.5    42.0      0.5%
##    45x    1118 m   11.5     6.8    39.5    51.6      2.9%
##   *65x*   1615 m   15.5     9.8    50.0    61.3      7.4%   - chosen
##    90x    2236 m   19.8    13.4    58.8    68.4     12.6%   - ridges read
##                                                              as thin fins
##
## 65x puts the median slope near 10 degrees (comfortable walking), the top 5%
## past 50 (genuine cliffs) and leaves 7.4% of the surface unclimbable. That is
## what real mountainous ground measures like: mostly traversable, with walls
## that are scenery rather than obstacles. Everything is still reachable on foot
## by going around.
##
## This is far above the 4-8x originally specified, and that band was set before
## anyone had measured what it produces: 8x on this planet is an 11-degree
## world, which is a desert pavement, not terrain. Explicitly authorised once the
## consequence was visible.
##
## An earlier estimate predicted 45 degrees at 20x. It was wrong - it reused a
## gradient measured from a different map at different erosion settings. The
## measured numbers above supersede it, and the lesson is that a slope figure is
## only meaningful alongside the resolution it was measured at.
## Dropped 65 -> 26 when the home planet went from 8 km to 20 km radius.
##
## Relief is a FRACTION of radius, so growing the planet at a fixed exaggeration
## grows the mountains with it - 2.5x radius gave 2.5x taller peaks and a
## silhouette identical to the one before, which is not what a bigger planet is
## supposed to look like. 26 is 65 divided by that same 2.5, which holds absolute
## relief at 1614.6 m while the body grows around it. The mountains stay the size
## they were and the horizon they sit against gets flatter, which was the point.
##
## Note this is now BELOW SMALL_BODY_EXAGGERATION, so the blend runs the other
## way: small bodies are relatively more dramatic than planets. That is
## deliberate and matches the brief - asteroids and moons at 32x, planets at
## 4-8x of Earth's real relief fraction.
const PLANET_EXAGGERATION := 26.0
const SMALL_BODY_EXAGGERATION := 32.0
## Radii (in voxels) the two exaggerations anchor to; bodies between them blend.
const SMALL_BODY_RADIUS := 1200.0
const PLANET_RADIUS := 6000.0

## Target width of one continent-scale feature, in metres. Frequency is derived
## from this so a bigger planet gets MORE continents rather than bigger ones -
## the opposite of what a fixed frequency does, and the reason a fixed one
## cannot survive a scale change.
const CONTINENT_SIZE_M := 1600.0
## Floor on continent frequency. Without it a small body works out to less than
## one feature across the whole sphere, i.e. a smooth egg.
const CONTINENT_FREQ_MIN := 1.5
const CONTINENT_FREQ_MAX := 14.0

## Frequency multipliers for the layers above continents. Deliberately not
## whole numbers: harmonically related frequencies line their features up and
## produce visible regularity, which is precisely the "feels repetitive" failure
## this whole system is trying to avoid.
const EROSION_FREQ_MULT := 1.73
const PEAKS_FREQ_MULT := 4.19
## Mountain belts run BELOW continent frequency, so a range spans several
## continent-scale features and reads as a chain rather than as a lump.
const BELT_FREQ_MULT := 0.55
const DETAIL_FREQ_MULT := 17.3
## Target size of one ROCK-SCALE feature, in metres, and how much relief it
## carries.
##
## Expressed in metres and not as a multiple of anything, because this band is
## the one the player stands on and it has to read at human scale on a 300 m
## moon and a 16 km planet alike. Every other band scales with the body; this
## one deliberately does not.
##
## Sized against the 1 m voxel: below about 4 m a feature is only a few voxels
## across and the mesher rounds it into mush, so there is no point generating it.
## 7 m with ~2.6 m of relief is roughly three voxels of rise over seven of run -
## steep enough to read as rock rather than as a swell.
const ROCK_FEATURE_M := 7.0
## Raised 1.1 -> 2.8 once the band became slope-gated.
##
## 1.1 m over 7 m of run is a 9 degree swell - which is why the ground read as
## having no rock in it at any zoom. It could not be raised before, because the
## band was gated only by deposition and so covered the whole planet: more
## amplitude meant a deeper carpet of identical lumps, not rock. With rockiness
## driven by landform slope the band is confined to ground that should be broken,
## and can carry relief that reads as such - 2.8 m over 7 m is a 39 degree face.
const ROCK_AMPLITUDE_M := 1.6
const CLIMATE_FREQ_MULT := 1.31
const ROUGHNESS_FREQ_MULT := 2.11
## Mesa/plateau regions run below continent frequency too, but not as far down
## as mountain belts - a mesa is one to a few continent-scale landmasses, not a
## chain spanning several of them.
const MESA_FREQ_MULT := 0.4
const MESA_FREQ_MIN := 0.3

## Target crater diameter, in metres, the same role `CONTINENT_SIZE_M` plays
## for continents: a size in real units converted to a frequency via this
## body's actual radius, so a 300 m moon and an 8 km planet both get craters
## that read as craters rather than as either a smooth field or a shattered
## mess of overlapping pits.
const CRATER_SIZE_M := 220.0
const CRATER_FREQ_MIN := 4.0
const CRATER_FREQ_MAX := 60.0

## Share of total relief the additive layers contribute on top of the continent
## term. Continents carry the bulk of the shape; detail is a surface texture,
## not a landform.
##
## Tightened 2026-09-11: frequency rises ~4.2x per band (continent -> erosion
## -> peaks -> detail) but these shares used to fall only ~3.3-3.8x, i.e.
## SHALLOWER than 1/f - every scale carried roughly its "fair share" of
## amplitude, which is why the terrain looked equally rough at every zoom
## level instead of reading as one dominant landform with finer accents on
## top. Real eroded terrain falls off faster than 1/f. These values now fall
## ~5-9x per band, steeper than the frequency ratio.
## Mountain amplitude, as a fraction of the body's relief.
##
## Larger than the total relief on purpose. Peaks are gated to mountain BELTS
## covering a small fraction of the surface, so this is local height INSIDE a
## range, not a contribution to the planet's average. Earth works the same way:
## 0.31% peak-to-trough globally, but 4 km of local relief in the Andes.
const PEAKS_SHARE := 1.15
const DETAIL_SHARE := 0.02
## Terrace step height, as a fraction of the body's total relief. One knob
## controls how many strata a mesa shows: small relief bodies get short, tight
## steps and dramatic ones get few, tall ones - both read as "terraced" because
## the step is always sized relative to the terrain that carries it.
## Terrace height as a fraction of the body's relief.
##
## Was 0.16, which on 149 voxels of relief is a 24 m step - every terrace a
## four-storey cliff, and the planet read as a ziggurat. Reference mesas show
## MANY thin strata stacked into one landform, not a few giant stairs, so this
## wants to be small enough that a single mesa carries several visible bands.
## PARKED AT ZERO - terracing is disabled. See the generator's mesa block.
##
## Quantising a RADIAL height field with STEPIFY produces concentric contour
## rings, because that is precisely what contouring a dome does. It was not a
## tuning problem: at any step size the result reads as a topographic map, and
## because the quantisation applies to the summed height it fires at every
## scale - including across a 2 m dug rock face, where it looked like machined
## steps.
##
## A real mesa is a FEW benches where specific hard layers resisted erosion, not
## uniform height quantisation. Rebuilding it needs the step boundaries tied to
## a rock-layer field with its own thickness, not to the height value itself.
const MESA_STEP_SHARE := 0.0
## Crater depth+rim amplitude, as a fraction of relief, before the weathering
## fade. Craters are a shape feature at the same scale as everything else here,
## not an independent constant.
const CRATER_AMPLITUDE_SHARE := 0.5
## How much weathering (atmosphere) erases craters. Not 1.0: even Earth keeps
## a few large ones, so a moderately weathered world should not go to exactly
## zero.
const CRATER_WEATHERING_FADE := 0.85

var body: CelestialBody
## Terrain extent, peak to trough, in VOXELS (the generator's own units).
var relief_voxels: float = 0.0
## Multiple of Earth's real relief ratio this body was given. Logged so the
## question "is this planet too dramatic" has a number attached to it.
var relief_exaggeration: float = 1.0
## Terrain band as actually MEASURED from the built generator, in voxels.
## Negative until measured - see Planet._measure_terrain_band().
var measured_deviation_voxels: float = -1.0
## Fraction of relief sitting below the nominal radius. Cold worlds read as
## highland, warm ones as basin - a small, cheap way for two planets at
## different orbits to feel different before biomes are even considered.
var sea_level: float = 0.45

var continent_freq: float = 1.5
var erosion_freq: float = 2.6
var peaks_freq: float = 6.3
var belt_freq: float = 0.8
var detail_freq: float = 26.0
var rock_freq: float = 100.0
var climate_freq: float = 2.0
var roughness_freq: float = 2.6
## Mesa/plateau region frequency - which fraction of the surface gets
## terraced, not how tall the terraces are (that is `mesa_step_voxels`).
var mesa_freq: float = 0.6
## Crater placement frequency, derived from `CRATER_SIZE_M` the same way
## continent frequency comes from `CONTINENT_SIZE_M`.
var crater_freq: float = 10.0

var peaks_amplitude: float = 0.0
var detail_amplitude: float = 0.0
var rock_amplitude: float = 0.0
## Terrace step height, in VOXELS - the generator's own units, matching
## `relief_voxels`.
var mesa_step_voxels: float = 0.0
## Crater depth+rim amplitude, in VOXELS, already folded down by weathering.
var crater_amplitude_voxels: float = 0.0

## 0 = frozen, 1 = scorching. Derived from irradiance, so it falls out of where
## the planet sits relative to its star.
var temperature_bias: float = 0.5
## 0 = airless and sharp, 1 = thick atmosphere and heavily weathered. Scales how
## much the erosion spline flattens things.
var weathering: float = 0.5

## `irradiance_ratio` is this body's irradiance divided by the star's irradiance
## at its own reference distance, so 1.0 means "as warm as the home orbit".
##
## SNAPSHOT CAVEAT: it is sampled once when the planet loads. Terrain must be
## stable, so once orbits move, this has to be captured at world CREATION and
## stored on the body - not re-derived each session, or a planet's mountains
## would migrate with its year.
static func derive(p_body: CelestialBody, voxel_scale: float,
		irradiance_ratio: float = 1.0, air_density: float = 0.0) -> PlanetProfile:
	var profile := PlanetProfile.new()
	profile.body = p_body
	if p_body == null:
		return profile

	var radius := maxf(p_body.radius, 1.0)

	# Smoothstep on radius, so a body of any size lands somewhere sensible on
	# the curve and nothing has to be classified as "planet" or "moon" by hand.
	var t := clampf((radius - SMALL_BODY_RADIUS) / (PLANET_RADIUS - SMALL_BODY_RADIUS),
		0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	profile.relief_exaggeration = lerpf(SMALL_BODY_EXAGGERATION, PLANET_EXAGGERATION, t)
	profile.relief_voxels = radius * EARTH_RELIEF_FRACTION * profile.relief_exaggeration

	# Radius is already in voxels, so metres have to be converted before the
	# feature-size target means anything.
	var radius_m := radius * maxf(voxel_scale, 0.0001)
	profile.continent_freq = clampf(radius_m / CONTINENT_SIZE_M,
		CONTINENT_FREQ_MIN, CONTINENT_FREQ_MAX)
	profile.erosion_freq = profile.continent_freq * EROSION_FREQ_MULT
	profile.peaks_freq = profile.continent_freq * PEAKS_FREQ_MULT
	profile.belt_freq = maxf(profile.continent_freq * BELT_FREQ_MULT, 0.8)
	profile.detail_freq = profile.continent_freq * DETAIL_FREQ_MULT
	# Frequency on the unit sphere that yields the target feature size: a noise
	# period of 1/f spans radius/f metres of arc, so f = radius / feature size.
	profile.rock_freq = maxf(radius_m / ROCK_FEATURE_M, 1.0)
	profile.climate_freq = profile.continent_freq * CLIMATE_FREQ_MULT
	profile.roughness_freq = profile.continent_freq * ROUGHNESS_FREQ_MULT
	profile.mesa_freq = maxf(profile.continent_freq * MESA_FREQ_MULT, MESA_FREQ_MIN)
	profile.crater_freq = clampf(radius_m / CRATER_SIZE_M, CRATER_FREQ_MIN, CRATER_FREQ_MAX)

	profile.peaks_amplitude = profile.relief_voxels * PEAKS_SHARE
	profile.detail_amplitude = profile.relief_voxels * DETAIL_SHARE
	profile.rock_amplitude = ROCK_AMPLITUDE_M / maxf(voxel_scale, 0.0001)
	profile.mesa_step_voxels = maxf(profile.relief_voxels * MESA_STEP_SHARE, 0.01)

	# Fourth root, matching how a real body's equilibrium temperature responds
	# to irradiance. Centred so the reference orbit lands mid-range and there is
	# room either side for a genuinely frozen or genuinely scorched world.
	profile.temperature_bias = clampf(
		pow(maxf(irradiance_ratio, 0.0001), 0.25) * 0.5, 0.0, 1.0)

	# An airless body has no weather to round its terrain off. Normalised
	# against roughly Earth-like density; anything thicker saturates.
	profile.weathering = clampf(air_density / 1.2, 0.0, 1.0)

	# Craters are a record of impacts a weathered world has since erased. An
	# airless moon keeps them at full depth; a thick atmosphere fades them
	# most of the way out, not all the way, since even Earth keeps a few.
	profile.crater_amplitude_voxels = (profile.relief_voxels * CRATER_AMPLITUDE_SHARE
		* (1.0 - CRATER_WEATHERING_FADE * profile.weathering))

	# Cold worlds read as highland, warm ones as basin.
	profile.sea_level = clampf(0.60 - profile.temperature_bias * 0.30, 0.25, 0.65)
	return profile

## Largest deviation from the nominal radius, in voxels. Spawn probes, LOD-0
## collision coverage and streaming bounds are all sized from this, so it must
## never UNDERSTATE - a bound smaller than the real terrain leaves the actual
## ground outside the region that ever gets generated, and the player then waits
## forever for a collider that will never be built.
##
## Prefers the measured value. The analytic estimate below is only a fallback:
## once the height field gained fractal octaves, ridging and domain warping, the
## naive sum of band amplitudes stopped predicting the real excursion. Measured
## at 338.6 voxels against an estimate of 225 - and that 113-voxel shortfall is
## exactly what stranded the player 60 s above the ground.
func max_deviation_voxels() -> float:
	if measured_deviation_voxels > 0.0:
		return measured_deviation_voxels
	return estimated_deviation_voxels()

## Analytic guess, used only to bracket the measurement and as a fallback if
## measuring is unavailable. Deliberately generous: overshooting costs a little
## streaming volume, undershooting strands the player.
func estimated_deviation_voxels() -> float:
	return (relief_voxels * maxf(sea_level, 1.0 - sea_level)
		+ peaks_amplitude + detail_amplitude) * 1.6

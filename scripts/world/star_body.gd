class_name StarBody
extends Resource

## Everything that makes one star different from another. Same discipline as
## PlanetAtmosphere: physical quantities, not art direction. Colour is derived
## from surface temperature via a blackbody approximation rather than being
## picked, so a red dwarf and a blue giant fall out of one number instead of
## needing someone to hand-match a tint to a luminosity.

@export var display_name: String = "Star"

@export_group("Physical")
## Photosphere radius in world metres. This is real geometry - the star can be
## approached and flown into, so this is the size of the thing you hit.
@export_range(1.0, 1000000.0, 1.0) var radius: float = 3000.0

## Effective surface temperature in kelvin. Drives colour AND, with radius,
## the total power output. Sol is 5772 K; 3000 K is a red dwarf, 10000 K+
## reads blue-white.
@export_range(1000.0, 40000.0, 10.0) var temperature: float = 5772.0

## Total radiated power, in arbitrary game units rather than watts - our
## bodies are metres rather than gigametres, so real solar luminosity would
## be meaningless here. What matters is that irradiance falls as 1/d^2 from
## this value, so relative brightness between system positions is honest even
## though the absolute unit is invented.
@export_range(0.0, 1e15, 1000.0) var luminosity: float = 6.0e8

## Surface gravity in m/s^2. Deliberately tiny for a star, because gravity is
## SUMMED over every body now (PlanetPhysics.get_gravity_accel) and our system
## is spatially compressed - the star sits ~4.4 km from the home planet rather
## than 150 million km.
##
## CALIBRATION RULE: the star's pull at a planet must stay well under 1% of
## that planet's own surface gravity, or it visibly tilts "down" for anyone
## standing there. Measured at 14.0 (a plausible-sounding stellar number) the
## star contributed 0.60 m/s^2 against the home planet's 1.2 - half of surface
## gravity, tilting local down by about 30 degrees. At 0.15 it contributes
## ~0.006 m/s^2, i.e. ~0.5%, which matches the Sun's real 0.06%-of-Earth-g
## influence closely enough to be invisible on foot while still being the
## thing that dominates in deep space.
##
## Check with: pull_at_planet = surface_gravity * radius^2 / distance^2
@export_range(0.0, 200.0, 0.001) var surface_gravity: float = 0.15

@export_group("Appearance")
## Limb darkening strength: a real star's disc is noticeably dimmer at the
## edge than the centre because you see shallower, cooler layers there. 0
## gives a flat disc, which reads as a cartoon ball.
@export_range(0.0, 1.0, 0.01) var limb_darkening: float = 0.45
## Quadratic term of the limb-darkening law. See the shader: the linear term on
## its own puts all of its falloff in the outermost 13% of the disc radius,
## which is not enough pixels to read as anything.
@export_range(0.0, 1.0, 0.01) var limb_darkening_quad: float = 0.35
## Peak HDR intensity of the rendered disc, independent of the physical
## luminosity used for irradiance and lighting.
##
## The scene tonemaps ACES with white = 6, so values past ~5 all resolve to the
## same white and the disc goes flat. Keep this around 3.
@export_range(0.0, 40.0, 0.1) var visual_brightness: float = 3.2

## Corona: the glow around the disc. Geometry on the star rather than
## Environment bloom, because one global glow threshold cannot both spare
## sunlit terrain and reach a star - see star_corona.gdshader.
## Extent in star radii (6 = the halo fades out three diameters from the limb).
@export_range(1.5, 20.0, 0.1) var corona_ratio: float = 3.0
@export_range(0.0, 8.0, 0.05) var corona_intensity: float = 1.35
## Higher = a tighter halo hugging the limb, lower = broader diffuse glow.
@export_range(0.5, 16.0, 0.1) var corona_falloff: float = 7.0
## Bright rim at the limb, as a fraction of the star radius, and its strength.
## A real star is a sharply bounded disc with a thin warm ring, not a diffuse
## ball of haze.
@export_range(0.02, 1.0, 0.01) var corona_rim_width: float = 0.22
@export_range(0.0, 6.0, 0.05) var corona_rim_boost: float = 2.4

## Blackbody colour for `temperature`, normalized so the brightest channel is
## 1.0. Uses the standard Tanner Helland piecewise approximation, which is
## accurate enough across 1000-40000 K for visual purposes and costs nothing.
func color() -> Color:
	var t: float = clampf(temperature, 1000.0, 40000.0) / 100.0
	var r: float
	var g: float
	var b: float

	if t <= 66.0:
		r = 255.0
		g = 99.4708025861 * log(t) - 161.1195681661
	else:
		r = 329.698727446 * pow(t - 60.0, -0.1332047592)
		g = 288.1221695283 * pow(t - 60.0, -0.0755148492)

	if t >= 66.0:
		b = 255.0
	elif t <= 19.0:
		b = 0.0
	else:
		b = 138.5177312231 * log(t - 10.0) - 305.0447927307

	var c := Color(
		clampf(r, 0.0, 255.0) / 255.0,
		clampf(g, 0.0, 255.0) / 255.0,
		clampf(b, 0.0, 255.0) / 255.0)

	# Normalize so temperature changes hue without also changing apparent
	# brightness - brightness is luminosity's job, not colour's.
	var peak := maxf(c.r, maxf(c.g, c.b))
	if peak > 0.0001:
		c = Color(c.r / peak, c.g / peak, c.b / peak)
	return c

## Radiant flux at `distance` metres from the star's centre, inverse-square,
## clamped at the photosphere so it doesn't diverge inside the body.
func irradiance_at_distance(distance: float) -> float:
	if luminosity <= 0.0:
		return 0.0
	var d := maxf(distance, maxf(radius, 0.001))
	return luminosity / (4.0 * PI * d * d)

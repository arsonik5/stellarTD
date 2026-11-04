class_name PlanetAtmosphere
extends Resource

## Physical description of one body's atmosphere. Pure data - no rendering
## decisions here. AtmosphereRenderer reads these into its scattering shader,
## PlanetPhysics reads density_at() for projectile drag, and world.gd reads
## the sun fields for the DirectionalLight3D.
##
## These are SCATTERING COEFFICIENTS, not colours. Sky colour, sunset colour,
## the orbital limb and the aerial-perspective haze on distant terrain all
## come out of one integral over these numbers, so a body physically cannot
## have a sky that disagrees with its own limb. The previous version of this
## resource held hand-picked zenith/horizon/haze/glow colours, which had to be
## kept consistent by hand across three different code paths and weren't.
##
## Rayleigh scattering goes as 1/wavelength^4, which is why thin clear air
## scatters blue strongly and red weakly. Mie is wavelength-neutral and
## strongly forward-scattering - dust, haze, aerosols.

@export_group("Composition")
## Rayleigh scattering coefficient per metre, per RGB channel. Earth at sea
## level is about (5.5e-6, 13.0e-6, 22.4e-6) - blue ~4x red, which is the
## whole reason Earth's sky is blue and its sunsets are red.
##
## Swapping the ratio is what makes another planet's sky genuinely different:
## a CO2-heavy atmosphere scatters much less blue and reads butterscotch,
## a methane one leans cyan. Change these, not a colour picker.
@export var rayleigh_coefficients := Vector3(5.5e-6, 13.0e-6, 22.4e-6)

## Mie (aerosol/dust) scattering per metre, wavelength-neutral. Higher = a
## hazier, milkier sky and a bigger glow around the sun. Earth clear-air is
## about 21e-6; a dusty world runs an order of magnitude above that.
@export_range(0.0, 0.001, 0.0000001) var mie_coefficient: float = 21e-6

## Mie forward-scattering bias, 0 = isotropic, ->1 = tightly forward. This is
## what makes the sky brightest right around the sun. 0.76-0.85 is typical.
@export_range(0.0, 0.99, 0.01) var mie_anisotropy: float = 0.78

## Ozone-like absorption per metre. Optional, but it is what keeps a real
## twilight sky blue instead of turning it grey-green, so it is worth having.
@export var ozone_absorption := Vector3(0.65e-6, 1.881e-6, 0.085e-6)

## Where the ozone layer sits, as a fraction of shell thickness (0 = surface,
## 1 = top of the shell) - NOT tied to `rayleigh_scale_ratio`. A real ozone
## layer sits in its own band well above the densest air; sharing Rayleigh's
## profile (the pre-2026-09-11 behaviour) can only tint the existing haze, not
## paint a separate band above it, which is what the ISS-limb reference
## photography wants (orange/white haze low down, then a distinct cyan/navy
## band higher up before space). Tuned by inspection against reference
## frames, not measured - there is no real ozone layer at this planet's scale
## to calibrate against.
@export_range(0.0, 1.0, 0.01) var ozone_peak_ratio: float = 0.42
## Gaussian width of the ozone layer, same units as `ozone_peak_ratio`.
@export_range(0.01, 1.0, 0.01) var ozone_width_ratio: float = 0.22

@export_group("Vertical structure")
## Altitude (metres) over which density falls by 1/e. Earth's Rayleigh scale
## height is ~8500 m against a 6371 km radius - a ratio of ~0.13%. Our bodies
## are far smaller, so these are expressed as a FRACTION of body radius below
## rather than in metres, to keep an atmosphere proportionate on any size body.
@export_range(0.001, 1.0, 0.001) var rayleigh_scale_ratio: float = 0.09
## Mie sits lower than Rayleigh in a real atmosphere - haze hugs the ground.
@export_range(0.001, 1.0, 0.001) var mie_scale_ratio: float = 0.035

## Top of the atmosphere as a multiple of the body's surface radius. Below
## this the scattering integral runs; above it is vacuum.
@export_range(1.0, 3.0, 0.01) var shell_radius_ratio: float = 1.25

## Overall multiplier on scattered light. A tuning knob for look, applied
## after the physics - leave at 1.0 unless a body needs to read brighter or
## dimmer than its coefficients alone give.
@export_range(0.0, 8.0, 0.05) var scattering_energy: float = 1.0

@export_group("Surface density")
## kg/m^3 at the surface, driving projectile aerodynamic drag via
## PlanetPhysics/projectile.gd. Earth sea level is 1.225; a vacuum body is 0.
## density_at() falls off with the Rayleigh scale height, so drag and the
## visible atmosphere thin out together instead of being two unrelated
## numbers that can silently disagree.
@export_range(0.0, 10.0, 0.001) var surface_air_density: float = 1.225

@export_group("Sun")
@export var sun_light_color: Color = Color(1.0, 0.97, 0.92)
@export_range(0.0, 8.0, 0.05) var sun_light_energy: float = 1.4
## Angular radius of the sun's disc in radians, as seen from this body.
@export_range(0.001, 0.2, 0.001) var sun_angular_size: float = 0.026

## Air density at `altitude` metres above the surface, exponential falloff on
## the Rayleigh scale height. `body_radius_world` is the body's surface radius
## in metres, since the scale height is stored as a ratio of it.
func density_at(altitude: float, body_radius_world: float) -> float:
	if surface_air_density <= 0.0:
		return 0.0
	var scale_height := maxf(rayleigh_scale_ratio * body_radius_world, 0.0001)
	var shell_height := (shell_radius_ratio - 1.0) * body_radius_world
	if shell_height <= 0.0 or altitude >= shell_height:
		return 0.0
	# Exponential falloff, but eased to exactly zero over the top fifth of the
	# shell. A bare exp() cut off at the shell boundary still has ~6% of sea
	# level left when it stops, and projectiles crossing that boundary would
	# take a visible step change in drag.
	var alt := maxf(altitude, 0.0)
	var edge := 1.0 - smoothstep(shell_height * 0.8, shell_height, alt)
	return surface_air_density * exp(-alt / scale_height) * edge

## True for bodies with no meaningful atmosphere (airless moons), so callers
## can skip both drag and the scattering pass entirely.
func is_vacuum() -> bool:
	return surface_air_density <= 0.0 and rayleigh_coefficients.length() <= 0.0

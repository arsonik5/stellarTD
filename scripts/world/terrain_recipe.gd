class_name TerrainRecipe
extends Resource
## One planet's terrain character as data (design/05-planets.md, W1): every band, gate and landform layer the
## graph generator builds, as parameters. Planets differ by RECIPE, not by code - the No Man's Sky "uber noise"
## arrangement, on top of SE2-style heightmap-first shape.
##
## Units are real metres / degrees / 0..1 shares, never voxels: the generator converts through the profile, so a
## recipe means the same thing on any planet size or voxel scale.
##
## `TerrainRecipe.new()` is the CURRENT home recipe. `legacy()` is the generator exactly as it was before the
## recipe existed (2026-11-05, commit ad29272): every later layer off. scenes/dev/planet_test.tscn holds the legacy
## recipe to a recorded hash, which is the proof the extraction changed nothing.

@export_group("Crags (outcrops, clumped, steep rocky ground only)")
@export var crag_enabled := true
@export var crag_feature_m := 20.0
@export var crag_amplitude_m := 5.0
@export var crag_facet_steps := 2.2
@export var crag_facet_blend := 0.62
@export var crag_patch_m := 90.0
@export var crag_patch_start := 0.35
@export var crag_patch_full := 0.62
@export var crag_rocky_start := 0.22
@export var crag_rocky_full := 0.55
@export var crag_slope_start := 0.02
@export var crag_slope_full := 0.2

@export_group("Rock (metre-scale break-up)")
@export var rock_enabled := true
## Multiplies PlanetProfile.rock_amplitude (ROCK_AMPLITUDE_M = 1.6 m at 1.0).
@export var rock_amplitude_mult := 1.0
@export var rock_octaves := 4
@export var rock_facet_steps := 4.0
@export var rock_facet_blend := 0.5
@export var rock_warp := 0.55
## Share of the rock band kept on flat rocky ground (the rest needs slope).
@export var rock_flat_floor := 0.2

@export_group("Grain (never a mirror)")
@export var grain_enabled := true
@export var grain_feature_m := 2.6
@export var grain_amplitude_m := 0.3
@export var grain_dust_share := 0.45

@export_group("Swells (broad meadow undulation)")
@export var swell_enabled := true
@export var swell_feature_m := 450.0
@export var swell_amplitude_m := 5.0
@export var swell_warp_fraction := 0.28

@export_group("Craters (meadow detail)")
@export var craters_enabled := true
## [period m, depth m, rim m, seed offset] per size class.
@export var crater_sizes: Array = [[900.0, 30.0, 6.0, 61], [260.0, 9.0, 2.0, 62], [70.0, 2.5, 0.6, 63]]
@export var crater_radius_cells := 0.30
@export var crater_cell_jitter := 0.6
@export var crater_rim_start := 0.55
@export var crater_rim_end := 1.35
@export var crater_amplitude_mult := 1.0

@export_group("Slope + altitude erosion (W2, NMS-style)")
## 0..1. Damps the fine bands where the LANDFORM (coarse map) is gentle and keeps them where it is steep, beyond
## the per-band gates: a gentle meadow loses the leftover rock carpet. 0 = off.
@export var slope_erosion := 0.0
## 0..1. Fine detail scales with altitude: low basins go calm (sediment), high ground goes sharp. 0 = off.
@export var altitude_erosion := 0.0
## Altitude (0..1 of the relief band) where altitude erosion is neutral (multiplier 1).
@export var altitude_pivot := 0.45
## Swells and craters are damped on slopes too (they belong to flats); 0 = off.
@export var flat_detail_slope_damp := 0.0

@export_group("Terraces / mesas (W3)")
@export var terrace_enabled := false
## Height of one terrace step, metres.
@export var terrace_step_m := 22.0
## Fraction of each step taken by the riser (smaller = flatter treads, steeper cliffs).
@export var terrace_riser := 0.22
## Terraces appear in patches this size (metres)...
@export var terrace_patch_m := 2600.0
## ...covering roughly this share of the planet, and only above this altitude (0..1 of relief).
@export var terrace_coverage := 0.45
@export var terrace_min_altitude := 0.35

@export_group("Canyons (W3)")
@export var canyon_enabled := false
@export var canyon_feature_m := 3200.0
@export var canyon_depth_m := 45.0
## Width of the canyon floor as a fraction of the noise band (0.02 narrow slot .. 0.12 broad valley).
@export var canyon_width := 0.045
## Wall steepness: higher = sheerer walls.
@export var canyon_sharpness := 2.5
@export var canyon_coverage := 0.55

@export_group("Spires (W3)")
@export var spire_enabled := false
## Average spacing between spire clusters, metres.
@export var spire_spacing_m := 380.0
@export var spire_radius_m := 7.0
@export var spire_height_m := 55.0
## Share of cells that actually raise a spire.
@export var spire_density := 0.35

@export_group("Erosion bake")
## Multiplies the GPU erosion bake's base frequency (more / fewer landmasses) and droplet density.
@export var bake_frequency_mult := 1.0
@export var bake_droplet_mult := 1.0
@export var bake_warp := -1.0

## The generator exactly as it was before recipes existed. Do not change these values: planet_test holds them to a
## recorded hash.
static func legacy() -> TerrainRecipe:
	var r := TerrainRecipe.new()
	r.slope_erosion = 0.0
	r.altitude_erosion = 0.0
	r.flat_detail_slope_damp = 0.0
	r.terrace_enabled = false
	r.canyon_enabled = false
	r.spire_enabled = false
	r.bake_frequency_mult = 1.0
	r.bake_droplet_mult = 1.0
	r.bake_warp = -1.0
	return r

## The recipe a body uses: its archetype's, else its own, else the default.
static func of(body: CelestialBody) -> TerrainRecipe:
	if body == null:
		return TerrainRecipe.new()
	var arch = body.get("archetype")
	if arch != null and arch.get("terrain") != null:
		return arch.terrain
	var own = body.get("terrain_recipe")
	if own != null:
		return own
	return TerrainRecipe.new()

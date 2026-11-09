class_name Planet
extends CelestialBodyNode

## One celestial body's terrain: wraps a VoxelTerrain child, builds a
## generator from this Planet's own CelestialBody (radius/seed/ore mix), and
## registers itself with PlanetPhysics so gravity/atmosphere/dig-target
## resolution all pick the nearest Planet automatically. Adding a second
## planet to the game is "instance this scene again with a different
## CelestialBody at a different position" - no new script, no touching this
## one, no touching PlanetPhysics.

## World-space size of one voxel, in meters. VoxelTerrain's `bounds` is in
## LOCAL (voxel-grid) units, which this node's `scale` does NOT rescale.
##
## 1.0 m matches Space Engineers 2. At the previous 0.4 m we were 2.5x finer
## than SE2 and paying 6.25x their surface voxel count for detail finer than
## the game needs. Because cost scales with voxel COUNT rather than world
## size, moving to 1 m made the planet 2.5x larger (400 m -> 1 km diameter)
## for exactly the same generation work.
##
## Anything expressed in world metres that should cover a fixed number of
## VOXELS - dig radius, build radius - has to move with this. Things that are
## genuinely human-scale (building tiles, ship cells) deliberately do not.
const VOXEL_SCALE := 1.0
## Margin (LOCAL units) added around the body's own radius/noise/ore-depth
## extent so streaming bounds never clip terrain generation or dig tunnels.
const BOUNDS_MARGIN := 20.0

## LOD tuning, derived from radius rather than authored on the shared
## `planet.tscn` scene.
##
## The bug: `lod_distance` is an ABSOLUTE voxel distance at which LOD 0
## becomes LOD 1 (each further level roughly doubles it), so the mesh's voxel
## step size at a given absolute viewing distance `d` is approximately
## `d / lod_distance`, REGARDLESS of the target body's own radius. Both
## bodies shared one authored `lod_distance` (64), so at any shared absolute
## distance they got the same absolute voxel step - which is a much bigger
## FRACTION of the 2200-voxel moon's radius than of the 8000-voxel planet's,
## reading as a faceted low-poly blob well before the planet shows the same
## artifact.
##
## Fix: keep `lod_distance * radius` constant instead of `lod_distance`
## itself. A body a quarter the radius gets a `lod_distance` roughly 4x
## larger, so its voxel-step-to-radius ratio at any given absolute viewing
## distance matches the reference body's. The reference point is the home
## planet's known-good, already-tested config (lod_distance 64 at radius
## 8000), times a deliberate CINEMATIC_BOOST - see below.
##
## Art direction 2026-09-11: a distant body (the moon seen from the home
## planet, ~44000 vox away) should read as a crisp DESTINATION, not something
## tuned to be cheap until approached. `CINEMATIC_BOOST` spends extra budget
## on keeping finer LOD at range across the board rather than only matching
## the old baseline - see terrain-generator.md for the measured cost of this.
const LOD_DISTANCE_RADIUS_PRODUCT_REF := 64.0 * 8000.0
const CINEMATIC_BOOST := 2.5
const VIEW_DISTANCE_RADII := 5.0
## Floor on `view_distance` so a small body's terrain still streams when seen
## from FAR outside its own `radius * VIEW_DISTANCE_RADII` - e.g. the moon
## (radius 2200, so 5x-radius alone gives only 11000) as seen from the home
## planet's surface, ~44000 vox away in this fixed alpha-system layout (see
## world.gd `_configure_fixed_alpha_system`). Without this floor the moon
## would render as nothing at all from that vantage rather than a distant
## silhouette - the opposite of the "reads as a destination" goal.
const SYSTEM_VIEW_DISTANCE_MIN := 60000.0
## Floor so a very small body doesn't get a `lod_distance` finer than its own
## mesh block (16 vox) - LOD 0 has to cover at least one block's width.
const LOD_DISTANCE_MIN := 8.0
const LOD_COUNT_MIN := 4
const LOD_COUNT_MAX := 20

const OreGenerator := preload("res://scripts/world/ore_generator.gd")
const GraphGenerator := preload("res://scripts/world/planet_graph_generator.gd")
const DebugMaterial := preload("res://scripts/world/voxel_terrain_material.tres")

@export var body: CelestialBody

## Use the compiled VoxelGeneratorGraph instead of the GDScript generator.
##
## Measured 13-61x faster on identical blocks depending on graph complexity -
## it runs in C++ over a whole block with automatic range analysis, which is
## what the script generator could only approximate by hand.
##
## TRADE-OFF while the port is incomplete: the graph has no branching, so
## nearest-biome selection, slope-driven cliff rock and rarest-first ore veins
## are NOT in it yet. Terrain shape is right; materials are ground-over-bedrock
## only. Set false to fall back to the full-featured script generator.
@export var use_graph_generator: bool = true

## Paint exposed rock on steep faces.
##
## Costs real generation time: there is no gradient node for a composed height
## field, so detecting slope means rebuilding that field at two neighbouring
## directions and differencing - three copies of the shape chain instead of one.
## Exposed as a toggle so the cost is measurable rather than assumed.
@export var cliff_rock_enabled: bool = true

## Carve caves and overhangs. This is what makes the terrain 3D rather than
## 2.5D - a radial height field has exactly one surface per direction and can
## never overhang.
@export var caves_enabled: bool = true

@export_group("Erosion")
## Bake a hydraulically eroded heightmap on the GPU at load and use it as the
## landform, instead of deriving shape from stacked noise bands.
@export var erosion_enabled: bool = true
## Equirectangular map width; height is half. 2048 is ~24 m/texel on an 8 km
## planet, with finer relief coming from the generator's rock band.
## 4096 = ~12 m per texel on an 8 km planet.
##
## Resolution is half of what sets maximum slope: an escarpment cannot be
## steeper than its height drop divided by the horizontal distance one texel
## spans. At 2048 the steepest 5% of the planet measured 11 degrees; at 4096
## with the same relief it is 22, and with the raised relief 45 - which is
## finally in mesa territory.
## Target ground distance per erosion texel, in metres.
##
## The map is sized from THIS, not from a fixed texel count, and that is the
## whole point. A fixed 4096 made the map scale with the body: at 8 km one texel
## was 12.3 m, at 20 km it was 30.7 m, so landforms got 2.5x wider in metres
## while their height stayed put and the p95 slope fell from 48 to 24 degrees.
## Terrain character has to be independent of planet size, and it only is if the
## resolution is pinned to ground distance.
##
## 12.3 m is the value the 8 km planet had when the terrain was judged good.
const EROSION_METRES_PER_TEXEL := 12.3

## Hard ceiling on map width. 10240x5120 is 52 million texels and about 210 MB
## per layer in memory - the largest that is sane to hold. Bodies big enough to
## want more get a coarser map rather than an allocation failure, and the log
## says so when it happens.
const EROSION_MAX_WIDTH := 10240

## Radius the erosion settings were tuned at, for scaling the base-noise
## frequency in _bake_eroded_heightmap().
##
## generate.glsl samples on the unit direction vector, so its frequency is
## ANGULAR: a given value always makes the same number of landmasses around the
## planet, whatever its size. On a 2.5x wider body that is a 2.5x wider landmass
## in metres, and with relief held constant the slopes flatten by the same
## factor - the identical failure the fixed-texel-count map had, in a different
## field. Pinning it to ground distance keeps continents the same real size on
## every planet.
const FREQUENCY_REFERENCE_RADIUS := 8000.0

## Test-only override for droplet density. Negative uses the baked-in setting;
## zero disables hydraulic erosion entirely, which is how a feature is proved to
## be the water's doing rather than the base field's.
static var EROSION_DENSITY_OVERRIDE: float = -1.0
## Test-only override for the base field's domain warp.
static var EROSION_WARP_OVERRIDE: float = -1.0

## Scattered rock geometry on the surface. Off for a body that should read as
## bare swept rock, and useful as an A/B switch when judging whether the
## terrain itself is carrying a shot.
@export var boulders_enabled: bool = true
## Pebbles and gravel around the viewer (NearScatter); null when this planet has no near-field lines.
var near_scatter: NearScatter

@onready var terrain: VoxelLodTerrain = $Terrain

## Terrain parameters derived from this body's physical properties. Built once
## in _ready() and reused, because the generator, the streaming bounds and the
## spawn probe must all be sized from the SAME numbers - deriving it twice is
## how they drift apart.
var profile: PlanetProfile

## GPU-eroded base heightmap for this body, baked once at load. Null when
## erosion is off or unavailable, in which case the generator falls back to the
## pure-noise shape rather than failing to produce a planet.
var _eroded_map: Image

## The erosion masks that came out of the same bake: "flow", "wear",
## "deposition". These are what decide WHERE materials go, in place of the
## unrelated noise fields that used to. Empty when erosion is off or the bake
## failed, and every consumer falls back rather than failing.
var _erosion_masks: Dictionary = {}

## Emitted once the terrain generator is live and the planet can be queried.
##
## Needed because _ready() is now a COROUTINE: the erosion bake yields between
## batches so the window keeps painting, which means _ready() returns to the
## engine long before the planet actually exists. Anything that used to rely on
## "children are ready before the parent" has to wait on this instead.
signal terrain_ready

var is_terrain_ready := false

## Relayed to the loading screen so a 56 s first bake shows progress rather than
## a frozen window.
func _on_bake_progress(fraction: float, label: String) -> void:
	var screen := get_tree().get_first_node_in_group("loading_screen")
	if screen != null and screen.has_method("set_progress"):
		screen.call("set_progress", fraction, "%s - %s" % [name, label])

func _ready() -> void:
	add_to_group("planet")
	# CelestialBodyNode._ready() does the group + PlanetPhysics registration
	# shared with every other body; it is called last so the terrain and
	# generator below exist before anything can query this body.

	TerrainLog.begin("world load")
	profile = _derive_profile()
	_eroded_map = await _bake_eroded_heightmap()
	TerrainLog.write_fields("profile", "%s: derived terrain profile" % name, {
		"radius_vox": body.radius,
		"radius_world_m": radius_world(),
		"relief_vox": profile.relief_voxels,
		"max_deviation_vox": profile.max_deviation_voxels(),
		"max_relief_world_m": max_relief_world(),
		"sea_level": profile.sea_level,
		"temperature_bias": profile.temperature_bias,
		"weathering": profile.weathering,
		"freq_continent": profile.continent_freq,
		"freq_erosion": profile.erosion_freq,
		"freq_peaks": profile.peaks_freq,
		"freq_detail": profile.detail_freq,
		"freq_climate": profile.climate_freq,
		"biomes": body.biomes.size(),
		"ore_types": body.ore_types.size(),
		"heightmap_override": body.heightmap != null,
	})

	var gen_t0 := Time.get_ticks_usec()
	terrain.generator = _make_generator()
	TerrainLog.write_fields("generator", "%s: generator ready" % name, {
		"class": terrain.generator.get_class(),
		"build_us": Time.get_ticks_usec() - gen_t0,
		"cliff_rock": cliff_rock_enabled,
		"caves": caves_enabled,
		"us_per_voxel": _measure_generator_cost(),
	})
	_log_dust_coverage()
	_spawn_boulders()
	_measure_terrain_band()
	_log_material_census()
	_log_material_coverage()
	_log_slope_profile()
	_attach_edit_stream()
	is_terrain_ready = true
	terrain_ready.emit()

	# TEXTURES_MIXEL4_S4 blends four weighted materials per vertex instead of
	# stamping one index per cell. TEXTURES_SINGLE_S4 is what produced the
	# hard square patches on the surface: with a single index per Transvoxel
	# cell, every material boundary is a cell-shaped step by construction, and
	# digging just exposes more of them.
	#
	# This mode needs BOTH channels at 16 bits - four 4-bit indices packed into
	# one, four 4-bit weights into the other. The indices channel must NOT be
	# 8-bit here (that is what SINGLE_S4 wanted); the weights channel only
	# accepts 16-bit and errors on anything else, so it is left at its default.
	var format := VoxelFormat.new()
	format.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_16_BIT)
	terrain.format = format

	var mesher := VoxelMesherTransvoxel.new()
	mesher.texturing_mode = VoxelMesherTransvoxel.TEXTURES_MIXEL4_S4
	# Transvoxel places a vertex wherever the density field crosses zero, which
	# can land arbitrarily close to a cell edge. Two neighbouring blocks at
	# DIFFERENT LOD levels then compute that crossing at different resolutions
	# and their vertices miss each other, leaving a crack that shows the sky
	# through the ground.
	#
	# The margin pushes near-edge vertices onto the edge so both sides agree.
	# The default 0.02 is far too tight here: it showed as rows of dark
	# rectangular gaps across every mid-distance slope, which survived disabling
	# shadows, disabling the atmosphere and tripling lod_distance - because none
	# of those were the cause.
	mesher.edge_clamp_margin = 0.25
	terrain.mesher = mesher

	terrain.material = _build_surface_material()
	terrain.generate_collisions = true
	terrain.scale = Vector3.ONE * VOXEL_SCALE

	# LOD distance/count/view distance derived from THIS body's radius rather
	# than left at the shared scene's authored values - see LOD_DISTANCE_FRACTION
	# above for why one fixed lod_distance cannot be right for both a moon and
	# a planet in the same scene.
	var lod_cfg := _derive_lod_config(body.radius)
	terrain.lod_distance = lod_cfg.lod_distance
	terrain.secondary_lod_distance = lod_cfg.lod_distance
	terrain.lod_count = lod_cfg.lod_count
	terrain.view_distance = int(round(lod_cfg.view_distance))

	# Cube bounds (LOCAL units, already the generator's own coordinate space)
	# sized to contain this body's whole solid sphere plus its height noise
	# and ore-vein depth - read straight from `body` so it can never drift
	# out of sync with what the generator itself is actually shaping.
	# Sized from the profile rather than the body's authored amplitudes: with
	# procedural shape those amplitudes no longer describe the terrain, and an
	# understated bound clips generation at the poles of the relief range.
	var half_extent := body.radius + max_relief_world() / VOXEL_SCALE \
		+ body.ore_vein_depth_max + BOUNDS_MARGIN
	var voxel_bounds := AABB(
		Vector3.ONE * -half_extent,
		Vector3.ONE * half_extent * 2.0
	)
	terrain.voxel_bounds = voxel_bounds
	TerrainLog.write_fields("stream", "%s: terrain configured" % name, {
		"lod_count": terrain.lod_count,
		"lod_distance": terrain.lod_distance,
		"view_distance_vox": terrain.view_distance,
		"voxel_scale": VOXEL_SCALE,
		"bounds_half_extent": half_extent,
		"edit_db": terrain.stream.database_path if terrain.stream != null else "(none)",
	})

	super._ready()

## Terrain parameters from physics: radius, how much starlight this body
## receives, and how thick its air is. See PlanetProfile.
##
## The irradiance ratio is measured against the star's own reference distance,
## so 1.0 means "as warm as the reference orbit" and the number is meaningful
## without hardcoding what a warm orbit is.
func _derive_profile() -> PlanetProfile:
	var ratio := 1.0
	var star := PlanetPhysics.get_dominant_star(global_position) as Star
	if star != null and star.body != null and star.reference_distance > 0.0:
		var here := star.body.irradiance_at_distance(
			global_position.distance_to(star.global_position))
		var reference := star.body.irradiance_at_distance(star.reference_distance)
		if reference > 0.0:
			ratio = here / reference
	var air := body.atmosphere.surface_air_density if body.atmosphere != null else 0.0
	return PlanetProfile.derive(body, VOXEL_SCALE, ratio, air)

## Graph when enabled and it builds; script generator otherwise. Falling back
## rather than erroring means a body the graph cannot yet express still loads.
func _make_generator() -> VoxelGenerator:
	if use_graph_generator:
		var g: VoxelGeneratorGraph = GraphGenerator.build(body, VOXEL_SCALE, profile, cliff_rock_enabled, caves_enabled, _eroded_map, _erosion_masks)
		if g != null:
			return g
		push_warning("Planet '%s': graph generator failed to build, using script generator." % name)
	return OreGenerator.new(body)

## Stable per-body key for this planet's edit database, taken from the
## CelestialBody resource's filename. Resources are already unique per body and
## their paths do not change between sessions, so this avoids adding an id field
## that could be left at its default on a new body and silently collide.
func save_key() -> String:
	if body == null or body.resource_path == "":
		return name.to_lower()
	return body.resource_path.get_file().get_basename()

## Points this planet's terrain at the current save slot's edit database.
##
## `save_generator_output = false` is the whole design: only blocks the player
## actually modified are written. Everything untouched is regenerated from the
## seed and baked heightmap, so a save stays kilobytes rather than storing a
## planet that the generator can reproduce exactly anyway.
func _attach_edit_stream() -> void:
	if SaveManager.current_slot == "":
		return
	var stream := VoxelStreamSQLite.new()
	stream.database_path = SaveManager.terrain_db_path(SaveManager.current_slot, save_key())
	stream.save_generator_output = false
	terrain.stream = stream

## Flushes edited blocks to disk. Returns the tracker to poll, or null when
## this planet has no database attached (no active save slot).
##
## The write is ASYNCHRONOUS - godot_voxel hands the blocks to worker threads.
## Quitting before the tracker reports complete loses the edits silently, which
## is why SaveManager.terrain_save_complete() exists and callers wait on it.
func save_terrain_edits() -> VoxelSaveCompletionTracker:
	if terrain.stream == null:
		return null
	return terrain.save_modified_blocks()

## Measures the real terrain band from the BUILT generator and stores it on the
## profile, so every consumer is sized against what the generator actually does
## rather than against a prediction of it.
##
## This replaces an analytic estimate that silently stopped being correct the
## moment the height field gained fractal octaves, ridging and domain warping -
## measured 338.6 voxels where the estimate said 225. Anything that adds a new
## term to the shape would have broken the estimate again; measuring cannot go
## stale, which matters a lot more once planets are generated procedurally and
## nobody is checking one hand-made world.
##
## Costs one Fibonacci-sphere sweep of direct generator queries (~0.05 s for 240
## directions at 8 km) and runs once per body at load.
func _measure_terrain_band(samples: int = 240) -> void:
	var graph := terrain.generator as VoxelGeneratorGraph
	if graph == null or profile == null:
		return
	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	# Bracket generously: the estimate only has to CONTAIN the surface for the
	# bisection to find it, and an estimate that is too tight here would hide the
	# very overshoot this is looking for.
	var bracket: float = profile.estimated_deviation_voxels() * 1.5 + 32.0
	var worst := 0.0
	var found := 0
	for i in samples:
		var dir := _fibonacci_dir(i, samples)
		var r := _bisect_surface(graph, buf, dir, bracket)
		if r < 0.0:
			continue
		found += 1
		worst = maxf(worst, absf(r - body.radius))
	if found < samples / 2:
		# Too few crossings to trust. Keep the estimate rather than adopting a
		# number derived from a handful of directions.
		TerrainLog.write("band", "%s: only %d/%d directions resolved, keeping estimate %.1f" % [
			name, found, samples, profile.estimated_deviation_voxels()])
		return
	# Margin on top of the worst sample: 240 directions cannot have hit the single
	# highest peak on the planet, and undershooting is the expensive direction.
	profile.measured_deviation_voxels = worst * 1.15 + 8.0
	TerrainLog.write_fields("band", "%s: terrain band measured" % name, {
		"directions_resolved": "%d / %d" % [found, samples],
		"worst_deviation_vox": worst,
		"adopted_band_vox": profile.measured_deviation_voxels,
		"analytic_estimate_vox": profile.estimated_deviation_voxels(),
		"relief_exaggeration_vs_earth": profile.relief_exaggeration,
	})

## Slope distribution of the baked terrain, in DEGREES.
##
## The number that decides both whether terrain reads as dramatic and whether it
## is playable, and the one instrument this project spent the longest without.
## Height standard deviation does not answer it: two maps with identical SD can
## be a gentle dome and a canyon system, because slope depends on how much
## horizontal distance a height change spans.
##
##     slope = (height change per texel) / (metres of arc per texel)
##
## A CharacterBody3D walks up to `floor_max_angle`, 45 degrees by default.
## Anything above that is scenery the player cannot climb, so the fraction above
## 45 is the playability budget - dramatic if it is a few percent, a prison if it
## is most of the planet.
##
## Reference: a mesa escarpment is 40-70 degrees; a gentle hill is around 10.
func _log_slope_profile(stride: int = 5) -> void:
	if not TerrainLog.enabled or _eroded_map == null or profile == null:
		return
	var w := _eroded_map.get_width()
	var h := _eroded_map.get_height()
	if w < 4 or h < 4:
		return

	# Metres of arc per texel at the equator. Rows nearer the poles cover less
	# ground per texel, so this understates slope there - acceptable, because the
	# playable band is the mid-latitudes and overstating walkability would be the
	# dangerous direction.
	var metres_per_texel: float = TAU * radius_world() / float(w)
	var relief_m: float = profile.relief_voxels * VOXEL_SCALE

	var angles := PackedFloat32Array()
	var y_lo := int(h * 0.15)
	var y_hi := int(h * 0.85)
	for y in range(y_lo, y_hi, stride):
		for x in range(0, w, stride):
			var dx: float = _eroded_map.get_pixel((x + 1) % w, y).r \
				- _eroded_map.get_pixel((x - 1 + w) % w, y).r
			var dy: float = _eroded_map.get_pixel(x, mini(y + 1, h - 1)).r \
				- _eroded_map.get_pixel(x, maxi(y - 1, 0)).r
			# Central difference spans two texels.
			var grade: float = sqrt(dx * dx + dy * dy) * relief_m \
				/ (2.0 * metres_per_texel)
			angles.append(rad_to_deg(atan(grade)))
	if angles.is_empty():
		return
	angles.sort()

	var mean := 0.0
	for a in angles:
		mean += a
	mean /= float(angles.size())
	var unwalkable := 0
	for a in angles:
		if a > 45.0:
			unwalkable += 1

	TerrainLog.write_fields("slope", "%s: terrain slope in degrees" % name, {
		"relief_m": relief_m,
		"metres_per_texel": metres_per_texel,
		"mean": "%.1f deg" % mean,
		"p50": "%.1f deg" % angles[int(angles.size() * 0.50)],
		"p95": "%.1f deg" % angles[int(angles.size() * 0.95)],
		"p99": "%.1f deg" % angles[int(angles.size() * 0.99)],
		"max": "%.1f deg" % angles[angles.size() - 1],
		"UNWALKABLE (>45 deg)": "%.1f%%" % (100.0 * unwalkable / angles.size()),
	})

## How much of the surface gets NO material at all.
##
## `TEXTURES_MIXEL4_S4` carries four weights per voxel. If every weight layer
## evaluates to zero at a point, the mesher receives nothing and the shader has
## no material to draw - which renders as a void-coloured patch that is easy to
## mistake for a hole in the geometry, and was mistaken for exactly that more
## than once. A weight audit answers it directly instead of by inspection.
##
## Reports the fraction of surface samples whose total weight is below a usable
## threshold, plus the weakest sample seen, so a coverage regression shows up as
## a number in the log rather than as an artifact in a screenshot.
func _log_material_coverage(samples: int = 400) -> void:
	if not TerrainLog.enabled:
		return
	var graph := terrain.generator as VoxelGeneratorGraph
	if graph == null or profile == null:
		return
	var buf := VoxelBuffer.new()
	buf.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_16_BIT)
	buf.set_channel_depth(VoxelBuffer.CHANNEL_WEIGHTS, VoxelBuffer.DEPTH_16_BIT)
	buf.create(1, 1, 1)

	var band := profile.max_deviation_voxels()
	var empty := 0
	var weak := 0
	var found := 0
	var worst := 999.0
	var histogram := {}
	for i in samples:
		var dir := _fibonacci_dir(i, samples)
		var r := _bisect_surface(graph, buf, dir, band)
		if r < 0.0:
			continue
		found += 1
		graph.generate_block(buf, Vector3i((dir * (r - 2.0)).round()), 0)
		var packed_w := int(buf.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_WEIGHTS))
		var packed_i := int(buf.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_INDICES))
		var total := 0.0
		for slot in 4:
			var wv := float((packed_w >> (slot * 4)) & 0xF) / 15.0
			total += wv
			if wv > 0.06:
				var idx := (packed_i >> (slot * 4)) & 0xF
				histogram[idx] = int(histogram.get(idx, 0)) + 1
		worst = minf(worst, total)
		if total <= 0.001:
			empty += 1
		elif total < 0.35:
			weak += 1

	if found == 0:
		TerrainLog.write("coverage", "%s: no surface found" % name)
		return
	var keys := histogram.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%d%%" % [VoxelMaterials.name_for(k), 100 * histogram[k] / found])
	TerrainLog.write_fields("coverage", "%s: surface material coverage" % name, {
		"samples_on_surface": found,
		"NO material (weight 0)": "%d  (%.1f%%)" % [empty, 100.0 * empty / found],
		"weak (<0.35 total)": "%d  (%.1f%%)" % [weak, 100.0 * weak / found],
		"weakest_total_weight": worst,
		"present": ", ".join(parts),
	})

## What the generator actually puts on the surface, sampled over the WHOLE
## sphere by asking the generator directly.
##
## Direct queries rather than raycasts into streamed voxels: streaming only
## covers a few degrees around the viewer at kilometre radii, so a raycast
## census silently reports on a tiny patch and calls it the planet. This is the
## check that caught biome boxes failing to tile climate space - 83% of the
## world was falling through to a default material index.
func _log_material_census(samples: int = 240) -> void:
	if not TerrainLog.enabled:
		return
	var graph := terrain.generator as VoxelGeneratorGraph
	if graph == null or profile == null:
		return

	var buf := VoxelBuffer.new()
	# Indices and weights are 16-bit under TEXTURES_MIXEL4_S4; at the default
	# depth the packed values truncate and every slot after the first reads zero.
	buf.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_16_BIT)
	buf.set_channel_depth(VoxelBuffer.CHANNEL_WEIGHTS, VoxelBuffer.DEPTH_16_BIT)
	buf.create(1, 1, 1)

	var band := profile.max_deviation_voxels()
	var counts := {}
	var lo := INF
	var hi := -INF
	var found := 0
	for i in samples:
		var dir := _fibonacci_dir(i, samples)
		var r := _bisect_surface(graph, buf, dir, band)
		if r < 0.0:
			continue
		found += 1
		lo = minf(lo, r)
		hi = maxf(hi, r)
		# Two voxels down: at the surface the SDF is ~0 and the material blend is
		# ambiguous between whatever meets there.
		var idx := _dominant_index(graph, buf, Vector3i((dir * (r - 2.0)).round()))
		if idx >= 0:
			counts[idx] = int(counts.get(idx, 0)) + 1

	if found == 0:
		TerrainLog.write("census", "%s: no surface found on any direction" % name)
		return
	TerrainLog.write("census", "%s: surface on %d/%d dirs, radius %.1f..%.1f (relief %.1f vox)" % [
		name, found, samples, lo, hi, hi - lo])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		TerrainLog.write("census", "    %-12s %4d  (%.1f%%)" % [
			VoxelMaterials.name_for(k), counts[k], 100.0 * float(counts[k]) / float(found)])

func _fibonacci_dir(i: int, n: int) -> Vector3:
	var t := (float(i) + 0.5) / float(n)
	var phi := acos(1.0 - 2.0 * t)
	var theta := PI * (1.0 + sqrt(5.0)) * float(i)
	return Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))

## Radius where the SDF crosses zero along `dir`, or -1 if the bracket does not
## contain a crossing.
func _bisect_surface(graph: VoxelGeneratorGraph, buf: VoxelBuffer,
		dir: Vector3, band: float) -> float:
	var lo := body.radius - band - 4.0
	var hi := body.radius + band + 4.0
	# A cave can put several SDF crossings along one ray; this finds the
	# outermost solid boundary, which is the one the surface band cares about.
	if _sdf_at(graph, buf, dir * lo) > 0.0 or _sdf_at(graph, buf, dir * hi) < 0.0:
		return -1.0
	for _i in 14:
		var mid := (lo + hi) * 0.5
		if _sdf_at(graph, buf, dir * mid) < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

## `generate_single` does not exist in this build; `generate_block` is the only
## entry point, so a 1x1x1 block is the smallest legal query.
func _sdf_at(graph: VoxelGeneratorGraph, buf: VoxelBuffer, p: Vector3) -> float:
	graph.generate_block(buf, Vector3i(p.round()), 0)
	return buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)

func _dominant_index(graph: VoxelGeneratorGraph, buf: VoxelBuffer, p: Vector3i) -> int:
	graph.generate_block(buf, p, 0)
	var packed_i := int(buf.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_INDICES))
	var packed_w := int(buf.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_WEIGHTS))
	var best := -1
	var best_w := -1
	for slot in 4:
		var w := (packed_w >> (slot * 4)) & 0xF
		if w > best_w:
			best_w = w
			best = (packed_i >> (slot * 4)) & 0xF
	return best

## Per-voxel generation cost, measured in-process.
##
## Only run when logging is on: it generates blocks to time them, which would be
## pure waste on a normal launch. In-process because end-to-end launch timing on
## this machine has measured 23.6 / 31.3 / 39.9 us for near-identical code -
## far too noisy to judge anything under a 2x change.
func _measure_generator_cost() -> float:
	if not TerrainLog.measure_cost:
		return -1.0
	var graph := terrain.generator as VoxelGeneratorGraph
	if graph == null:
		return -1.0
	return graph.debug_measure_microseconds_per_voxel(false)

## `lod_distance` is INVERSELY proportional to radius (see the constant
## comment above): a smaller body needs a LARGER `lod_distance` to keep the
## same voxel-step-to-radius ratio as a bigger one at the same absolute
## viewing distance. `view_distance` scales WITH radius instead, so every
## body is visible from a proportional multiple of its own size. `lod_count`
## falls out of how many doublings of `lod_distance` are needed to reach
## `view_distance` - a smaller body needs FEWER doublings here (its
## `lod_distance` is already large relative to its own `view_distance`), which
## is the expected shape: a small nearby destination should hold peak detail
## almost all the way out to where it stops being visible at all.
func _derive_lod_config(radius: float) -> Dictionary:
	var lod_distance := maxf(
		LOD_DISTANCE_RADIUS_PRODUCT_REF * CINEMATIC_BOOST / maxf(radius, 1.0),
		LOD_DISTANCE_MIN)
	var view_distance := maxf(radius * VIEW_DISTANCE_RADII, SYSTEM_VIEW_DISTANCE_MIN)
	var reach_needed := maxf(view_distance / lod_distance, 1.0)
	var lod_count := int(ceil(log(reach_needed) / log(2.0))) + 1
	lod_count = clampi(lod_count, LOD_COUNT_MIN, LOD_COUNT_MAX)
	return {"lod_distance": lod_distance, "lod_count": lod_count, "view_distance": view_distance}

## This body's own material instance, carrying its own surface palette.
##
## Duplicated rather than shared: the palette maps material INDEX to how it
## looks, and two planets generated with different biome sets legitimately paint
## the same index differently. A shared material would make the last planet to
## load win for everyone - and with procedurally generated planets that is the
## normal case, not an edge case.
func _build_surface_material() -> ShaderMaterial:
	var mat: ShaderMaterial = DebugMaterial.duplicate()
	var palette: Dictionary = SurfacePalette.build(body)
	mat.set_shader_parameter("pal_tint_rough", palette["tint_rough"])
	mat.set_shader_parameter("pal_extra", palette["extra"])
	mat.set_shader_parameter("pal_grade", palette["grade"])
	mat.set_shader_parameter("pal_far", palette["far"])
	mat.set_shader_parameter("tex_albedo", palette["albedo_array"])
	mat.set_shader_parameter("tex_normal", palette["normal_array"])
	if TerrainLog.enabled:
		var assigned: Array[String] = []
		var names: Array = palette["names"]
		for i in names.size():
			if String(names[i]) != "-":
				assigned.append("%d=%s" % [i, names[i]])
		var textures: Array = palette["textures"]
		var missing: Array[String] = []
		for i in textures.size():
			if String(names[i]) != "-" and String(textures[i]) == "":
				missing.append(str(i))
		TerrainLog.write("palette", "%s: %d/%d slots styled  %s%s" % [
			name, assigned.size(), SurfacePalette.SLOTS, ", ".join(assigned),
			"  UNTEXTURED: " + ", ".join(missing) if not missing.is_empty() else ""])
	return mat

## How much of the surface the dust field actually mantles.
##
## The rock-relief band is multiplied by (1 - dust), so this number IS how rough
## the ground is allowed to be, everywhere. It is logged because the gate range
## was picked from the deposition mask's median and that is one statistic about
## one mask - not evidence that the meadows come out smooth. Reasoning about a
## gate is not the same as measuring what comes out of it.
##
## Read it as: high dust = smooth ground. If the median is low, the planet is
## mostly bare rock however the gate was intended.
func _log_dust_coverage() -> void:
	if not TerrainLog.enabled:
		return
	var m: Image = _erosion_masks.get("deposition")
	if m == null:
		TerrainLog.write("dust", "%s: no deposition mask, rock band ungated" % name)
		return
	# Must match _dust_field() in planet_graph_generator.gd.
	const LOW := 0.02
	const HIGH := 0.22
	var w := m.get_width()
	var h := m.get_height()
	var vals := PackedFloat32Array()
	for y in range(int(h * 0.1), int(h * 0.9), 3):
		for x in range(0, w, 3):
			vals.append(smoothstep(LOW, HIGH, m.get_pixel(x, y).r))
	if vals.is_empty():
		return
	vals.sort()
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= float(vals.size())
	var rough := 0
	for v in vals:
		if v < 0.5:
			rough += 1
	TerrainLog.write_fields("dust", "%s: dust mantling coverage" % name, {
		"range": "%.2f..%.2f of deposition" % [LOW, HIGH],
		"mean": "%.2f" % mean,
		"p10": "%.2f" % vals[int(vals.size() * 0.10)],
		"p50": "%.2f" % vals[int(vals.size() * 0.50)],
		"p90": "%.2f" % vals[int(vals.size() * 0.90)],
		"ROUGH (dust<0.5)": "%.1f%%" % (100.0 * rough / vals.size()),
	})

## Scatters real rock geometry on the finished surface.
##
## Added AFTER the generator, because the instancer emits from meshed terrain -
## it needs the surface to exist before it can put anything on it.
func _spawn_boulders() -> void:
	if not boulders_enabled:
		return
	# planets with traits: every asset line their traits bring (ScatterEngine, stage 4a); others the old boulders
	if not TraitMixer.of(body).is_empty():
		var scatter := ScatterEngine.build(self, body, _erosion_masks, terrain.material as ShaderMaterial)
		if scatter != null:
			terrain.add_child(scatter)
		var near := ScatterEngine.near_lines(TraitMixer.of(body))
		if not near.is_empty():
			near_scatter = NearScatter.new()
			near_scatter.name = "NearScatter"
			add_child(near_scatter)
			near_scatter.setup(self, terrain, body, near, terrain.material as ShaderMaterial)
		if scatter != null or near_scatter != null:
			return
	var instancer := BoulderScatter.build(
		float(body.radius), _erosion_masks.get("talus"),
		VoxelInstancer.UP_MODE_SPHERE)
	if instancer == null:
		return
	terrain.add_child(instancer)
	TerrainLog.write_fields("boulders", "%s: boulders scattered" % name, {
		"variants": BoulderScatter.ROCKS.size(),
		"lod": BoulderScatter.BOULDER_LOD,
		"density_per_m2": BoulderScatter.DENSITY,
		"scale": "per-variant, texel-matched",
		"mask_driven": _erosion_masks.has("talus"),
	})

## Map width that gives EROSION_METRES_PER_TEXEL on this body.
##
## Rounded to a multiple of 8 because the compute shaders dispatch in 8x8 groups,
## and clamped at both ends - a tiny asteroid does not need a megatexel map and
## nothing gets one larger than EROSION_MAX_WIDTH.
func _erosion_width() -> int:
	var circumference: float = TAU * radius_world()
	var want := int(round(circumference / EROSION_METRES_PER_TEXEL / 8.0)) * 8
	return clampi(want, 512, EROSION_MAX_WIDTH)

## Bakes this body's eroded heightmap on the GPU.
##
## Measured ~0.6 s for 2048x1024 with 4.6M droplets and 40 thermal passes, so it
## runs at load rather than being cached to disk - a cache would cost more in
## invalidation bugs than it saves. If that changes, the save slot is the place.
##
## NOTE: there is no GPU context in a headless Godot run, so this returns null
## there and the noise path takes over. Any test of erosion must run windowed.
func _bake_eroded_heightmap() -> Image:
	# A coroutine, because the bake yields between batches so the loading screen
	# can draw. See ErosionBaker.bake().
	if not erosion_enabled:
		return null
	var baker := ErosionBaker.new()
	var settings := ErosionBaker.Settings.new()
	settings.seed = body.seed
	settings.frequency *= maxf(radius_world() / FREQUENCY_REFERENCE_RADIUS, 0.05)
	if EROSION_DENSITY_OVERRIDE >= 0.0:
		settings.droplet_density = EROSION_DENSITY_OVERRIDE
	if EROSION_WARP_OVERRIDE >= 0.0:
		settings.warp_strength = EROSION_WARP_OVERRIDE
	var width := _erosion_width()
	settings.width = width
	settings.height = width / 2
	# The slope mask needs real metres to be an angle. The profile is derived
	# before the bake (see _ready), so the relief is already known here.
	settings.relief_m = profile.relief_voxels * VOXEL_SCALE
	settings.metres_per_texel = TAU * radius_world() / float(width)

	# Cache hit: the bake is 6x the pixels it used to be and is deterministic in
	# the seed, so it is stored rather than repeated at every load.
	var cached := ErosionCache.load_entry(body.seed, settings.width, settings.height)
	if not cached.is_empty():
		_erosion_masks = {}
		for k in cached:
			if k != "height":
				_erosion_masks[k] = cached[k]
		TerrainLog.write_fields("erosion", "%s: eroded heightmap from cache" % name, {
			"size": "%dx%d" % [settings.width, settings.height],
			"metres_per_texel": TAU * radius_world() / float(settings.width),
			"path": ErosionCache.key(body.seed, settings.width, settings.height),
		})
		return cached["height"]
	baker.progress.connect(_on_bake_progress)
	var img: Image = await baker.bake(settings)
	if img == null:
		TerrainLog.write("erosion", "%s: bake unavailable, using noise shape" % name)
		return null
	_erosion_masks = baker.last_masks
	ErosionCache.save_entry(body.seed, settings.width, settings.height,
		img, _erosion_masks)
	if TerrainLog.enabled:
		# Dump what the game actually baked, plus its height distribution. A map
		# that looks right in isolation can still be applied with too little
		# contrast, and the two failures look identical from inside the game.
		var lo := 1.0
		var hi := 0.0
		var mean := 0.0
		var n := 0
		var preview := Image.create_empty(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
		for py in img.get_height():
			for px in img.get_width():
				var v := img.get_pixel(px, py).r
				lo = minf(lo, v)
				hi = maxf(hi, v)
				mean += v
				n += 1
				preview.set_pixel(px, py, Color(v, v, v))
		mean /= float(max(n, 1))
		var spread := 0.0
		for py in range(0, img.get_height(), 4):
			for px in range(0, img.get_width(), 4):
				var d := img.get_pixel(px, py).r - mean
				spread += d * d
		spread = sqrt(spread / float(max(n / 16, 1)))
		preview.save_png("user://erosion_%s.png" % name.to_lower())
		baker.last_stats["height_min"] = lo
		baker.last_stats["height_max"] = hi
		baker.last_stats["height_mean"] = mean
		baker.last_stats["height_sd"] = spread
		baker.last_stats["relief_voxels_applied"] = profile.relief_voxels
		for key in _erosion_masks:
			var m: Image = _erosion_masks[key]
			baker.last_stats["mask_" + key] = "%dx%d" % [m.get_width(), m.get_height()]
	TerrainLog.write_fields("erosion", "%s: eroded heightmap baked" % name, baker.last_stats)
	return img

## A direction to put the player, chosen from the eroded map.
##
## Scores candidates on two things that pull against each other: the ground
## immediately underfoot should be LEVEL enough to stand and build on, while the
## terrain within a few kilometres should have as much relief as possible so
## there is something to look at and walk to.
##
## Without this the spawn is wherever the scene file happens to point, and on a
## planet that is mostly plateau that means standing in the middle of a flat top
## with the escarpments over the horizon - which reads as "the generator makes
## flat terrain" when it does not. It is also just a better opening view.
##
## Returns Vector3.ZERO when there is no map, leaving the authored spawn alone.
func suggested_spawn_direction() -> Vector3:
	if _eroded_map == null:
		return Vector3.ZERO
	var w := _eroded_map.get_width()
	var h := _eroded_map.get_height()
	if w <= 0 or h <= 0:
		return Vector3.ZERO

	# Radius, in texels, over which "interesting scenery nearby" is measured.
	# ~40 texels is roughly 1 km at 2048 wide on an 8 km planet: far enough to
	# hold a whole escarpment, close enough to be walkable.
	var scan := 40
	var best_score := -INF
	var best_dir := Vector3.ZERO

	# Latitude range is trimmed: an equirectangular map is badly distorted near
	# the poles, and spawning there reintroduces exactly the artifacts that moving
	# off the pole was meant to remove.
	var y_lo := int(h * 0.22)
	var y_hi := int(h * 0.78)

	for y in range(y_lo, y_hi, 13):
		for x in range(0, w, 13):
			var centre := _eroded_map.get_pixel(x, y).r
			# Local flatness, from the immediate neighbours.
			var dx: float = absf(_eroded_map.get_pixel((x + 2) % w, y).r
				- _eroded_map.get_pixel((x - 2 + w) % w, y).r)
			var dy: float = absf(_eroded_map.get_pixel(x, mini(y + 2, h - 1)).r
				- _eroded_map.get_pixel(x, maxi(y - 2, 0)).r)
			var local_slope := dx + dy

			# Relief within the scan radius, sampled sparsely - this is the
			# "is there anything to look at" term.
			var lo := 1.0
			var hi := 0.0
			for oy in range(-scan, scan + 1, 10):
				for ox in range(-scan, scan + 1, 10):
					var v: float = _eroded_map.get_pixel(
						(x + ox + w) % w, clampi(y + oy, 0, h - 1)).r
					lo = minf(lo, v)
					hi = maxf(hi, v)
			var nearby_relief := hi - lo

			# Standable ground first, scenery second. The slope penalty is heavy
			# because spawning on a cliff face is worse than a dull view.
			var score := nearby_relief - local_slope * 6.0
			# Slight preference for sitting below the local high point, so the view
			# looks UP at something rather than down off an edge.
			score -= absf(centre - (lo + nearby_relief * 0.35)) * 0.5
			if score > best_score:
				best_score = score
				var lon := (float(x) + 0.5) / float(w) * TAU - PI
				var lat := PI * 0.5 - (float(y) + 0.5) / float(h) * PI
				best_dir = Vector3(
					cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))

	TerrainLog.write("spawn", "%s: suggested spawn score %.4f dir %s" % [
		name, best_score, best_dir])
	return best_dir

func radius_world() -> float:
	return body.radius * VOXEL_SCALE

## How far out (world meters) this body's gravity/atmosphere actually
## reaches before true open space takes over - a few radii, not infinite,
## so two planets far enough apart have a genuine zero-gravity void between
## them instead of gravity always snapping to whichever is merely closer no
## matter how far that still is. Simple radius multiple for now; real
## mass/orbit-based falloff isn't needed at this scope.
func influence_radius() -> float:
	return radius_world() * 4.0

## Scaled so a body twice the radius pulls twice as hard at its surface, which
## keeps walking around a moon and a planet feeling meaningfully different
## without a mass field to author.
func surface_gravity() -> float:
	return PlanetPhysics.REFERENCE_SURFACE_GRAVITY * radius_world() / PlanetPhysics.REFERENCE_RADIUS_WORLD

func terrain_node() -> VoxelNode:
	return terrain

## Largest distance (world metres) terrain can sit from the nominal radius.
##
## Spawn probes and LOD-0 collision coverage are both sized from this, so an
## understated value leaves the real ground outside the region that ever gets
## generated - precisely the class of bug that broke the first km-scale attempt.
## It must always come from the same source the generator used.
func max_relief_world() -> float:
	if body == null:
		return 0.0
	# A baked heightmap overrides the procedural shape, so it also overrides the
	# band. Its range ADDS to the noise range rather than replacing it.
	if body.heightmap != null:
		return (body.height_amplitude + body.detail_amplitude) * VOXEL_SCALE \
			+ body.heightmap.max_deviation()
	if profile == null:
		profile = _derive_profile()
	return profile.max_deviation_voxels() * VOXEL_SCALE

func atmosphere() -> PlanetAtmosphere:
	return body.atmosphere if body != null else null

func air_density() -> float:
	var atmo := atmosphere()
	return atmo.surface_air_density if atmo != null else 0.0

## Air density at a world position. Exponential falloff on the atmosphere's
## own Rayleigh scale height, so projectile drag thins out on exactly the
## same curve the scattering shader renders - they cannot disagree.
func air_density_at(pos: Vector3) -> float:
	var atmo := atmosphere()
	if atmo == null:
		return 0.0
	var altitude := maxf(global_position.distance_to(pos) - radius_world(), 0.0)
	return atmo.density_at(altitude, radius_world())

@tool
extends VoxelGeneratorScript

## Solid-sphere planet generator: noise-driven hills/craters, biome-shaped
## regions, and depth/rarity-tiered ore veins. Shape/seed/ore-types/biomes
## all come from a CelestialBody passed into _init() rather than being
## hardcoded here - this script is one reusable generator any number of
## differently-shaped planets each construct their own instance of (see
## Planet.gd). Biome design: biome-system-design.md.

const SDF_CHANNEL: int = VoxelBuffer.CHANNEL_SDF
const INDICES_CHANNEL: int = VoxelBuffer.CHANNEL_INDICES
const WEIGHTS_CHANNEL: int = VoxelBuffer.CHANNEL_WEIGHTS

## TEXTURES_MIXEL4_S4 packs FOUR 4-bit material indices into the 16-bit
## indices channel and four matching 4-bit weights into the 16-bit weights
## channel, and the mesher blends them per vertex. That is what removes the
## hard square patches TEXTURES_SINGLE_S4 produced: with one index per cell,
## every material boundary is a cell-shaped step by construction.
##
## Two hard constraints from the mesher, both easy to violate silently:
##   - material indices must fit in 4 bits, so 0..15 only
##   - the four indices in a voxel must be UNIQUE, even in slots whose weight
##     is zero (hence FILLER_INDICES below)
const MATERIAL_SLOTS := 4
const MAX_MATERIAL_INDEX := VoxelMaterials.MAX_INDEX
const WEIGHT_MAX := 15

## Never real materials - used to pad unused slots so the uniqueness rule
## holds without accidentally tinting a voxel with a material that exists.
const FILLER_INDICES := [13, 14, 15]

const CLIFF_INDEX := VoxelMaterials.CLIFF_ROCK
const BEDROCK_INDEX := VoxelMaterials.BEDROCK

## Depth (voxels below the surface) over which biome topsoil gives way to
## bedrock. Deliberately soft so digging shows a graded crust, not a step.
const TOPSOIL_DEPTH := 2.5
const BEDROCK_FADE := 6.0

## How many times steeper than this body's own characteristic gradient a face
## has to be before it reads as fully cliff rather than ground.
##
## Calibrated, not guessed: sampling 400 surface points, grad/reference runs
## p50 2.3, p90 3.8, max 7.0. At the 3.0 first tried, 73% of the planet came
## out mostly cliff - the whole surface turned to rock. 7.0 puts the cutoff
## around p85, so roughly the steepest 15% reads as cliff and everything else
## keeps its biome ground with a soft blend between.
const CLIFF_SLOPE_MULT := 7.0

## Half-thickness of a vein, in vein-noise units. A voxel is inside a vein
## where |vein noise| < this, fading to nothing at the edge. Expressed as a
## width rather than a threshold on 1-|n| because the latter is brutally
## non-linear near 1: the difference between a third of the planet being ore
## and almost none of it sat between 0.72 and 0.97.
const VEIN_WIDTH := 0.035

## Fraction of deposit regions that contain ore at all. The rest are barren
## rock, which is what makes finding a deposit mean something rather than
## ore being uniformly available wherever you happen to dig.
const ORE_REGION_SHARE := 0.45

## LOCAL (voxel-grid) space center. Always the origin: a Planet's Terrain
## node has no offset transform relative to its own Planet root, so "local
## origin" is already that specific planet's center - the Planet root's own
## global_position (wherever it's placed in the wider universe) is what
## actually varies from body to body, not this.
const CENTER := Vector3.ZERO

## Width (climate-space units, same 0..1 scale as temperature/roughness) of
## the blend band at a biome border - only affects terrain amplitude, since
## material index blending is handled by the mesher (see Planet.gd once it
## moves to TEXTURES_MIXED4_S4). Wider = more gradual transitions.
const BIOME_BLEND_WIDTH := 0.12

## Finite-difference step (unit-sphere direction units) for the surface-slope
## term of the roughness climate axis.
const SLOPE_EPS := 0.02

## Gradient magnitude that counts as fully "rough" (slope term = 1.0). The
## height noise's own frequency sets its typical gradient, so this is roughly
## twice that - typical terrain lands mid-axis, only genuinely steep ground
## saturates.
const SLOPE_NORM := 4.0

## How far `base_surface_radius` (which omits per-biome amplitude multipliers)
## can differ from the final surface. Used to decide when a voxel is safely
## air or safely deep bedrock without running the full material path. Biome
## multipliers reach ~2x, so twice the combined noise amplitude plus a voxel
## of slack is conservative.
const BIOME_SURFACE_MARGIN := 8.0

## Shared read-only empty bias map for bodies with no biomes - never mutated.
const EMPTY_ORE_BIAS := {}

# ---------------------------------------------------------------------------
# Profiling
# ---------------------------------------------------------------------------
# Answers "where is generation time actually going" instead of it being
# guessed at. Guessing has already cost this project real time: a single
# wall-clock load measurement suggested an optimisation had made things 50%
# slower when an isolated A/B showed it was 33% faster.
#
# Counters are per-voxel but only plain integer increments on LOCALS; they are
# merged into the shared totals exactly ONCE per block, under a mutex. That
# matters because godot_voxel calls _generate_block() from several worker
# threads at once - incrementing shared state per voxel would be both a data
# race and slower than the work being measured.
#
# Phase timers are opt-in (`profile_timings`) because calling
# Time.get_ticks_usec() per voxel perturbs the very thing it measures. Leave
# them off to get counts, turn them on to attribute cost.

static var profile_enabled := false
static var profile_timings := false

## Lazily created: a static var initialiser does not reliably run before first
## use when the script is reached via preload in a `-s` tool script, which
## crashed the profiler with a null mutex.
static var _prof_mutex: Mutex = null

static func _prof_lock() -> Mutex:
	if _prof_mutex == null:
		_prof_mutex = Mutex.new()
	return _prof_mutex
static var _prof := {}

static func profile_reset() -> void:
	var m := _prof_lock()
	m.lock()
	_prof = {
		"blocks": 0, "uniform_air": 0, "uniform_solid": 0,
		"block_usec": 0, "voxels": 0,
		"air_skip": 0, "deep_skip": 0, "full": 0,
		"t_shape_usec": 0, "t_climate_usec": 0, "t_material_usec": 0,
	}
	m.unlock()

static func _prof_merge(d: Dictionary) -> void:
	var m := _prof_lock()
	m.lock()
	for k in d:
		_prof[k] = _prof.get(k, 0) + d[k]
	m.unlock()

static func profile_report() -> String:
	var m := _prof_lock()
	m.lock()
	var p: Dictionary = _prof.duplicate()
	m.unlock()
	var blocks: int = p.get("blocks", 0)
	if blocks == 0:
		return "generator profile: no blocks generated"
	var vox: int = maxi(p.get("voxels", 1), 1)
	var us: int = p.get("block_usec", 0)
	var lines := []
	lines.append("=== generator profile ===")
	lines.append("blocks generated : %d  (uniform air %d, uniform solid %d, per-voxel %d)"
		% [blocks, p.get("uniform_air", 0), p.get("uniform_solid", 0),
		   blocks - p.get("uniform_air", 0) - p.get("uniform_solid", 0)])
	lines.append("total time       : %.1f ms  (%.1f ms/block over per-voxel blocks)"
		% [us / 1000.0, us / 1000.0 / maxi(blocks - p.get("uniform_air", 0) - p.get("uniform_solid", 0), 1)])
	lines.append("voxels visited   : %d  (%.2f us/voxel)" % [vox, float(us) / float(vox)])
	lines.append("")
	lines.append("path taken by voxel:")
	for key in ["air_skip", "deep_skip", "full"]:
		var n: int = p.get(key, 0)
		lines.append("   %-10s %9d  %5.1f%%" % [key, n, 100.0 * n / vox])
	if profile_timings:
		lines.append("")
		lines.append("time by phase (full-path voxels only):")
		for key in ["t_shape_usec", "t_climate_usec", "t_material_usec"]:
			var t: int = p.get(key, 0)
			lines.append("   %-16s %8.1f ms  %5.1f%%" % [key, t / 1000.0, 100.0 * t / maxi(us, 1)])
	return "
".join(lines)

var _radius := 100.0
var _height_amplitude := 6.0
var _detail_amplitude := 1.5

var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()

## When set, large-scale shape comes from this baked map and the height/detail
## noise becomes sub-pixel detail on top. See CelestialBody.heightmap.
var _heightmap: PlanetHeightmap = null
var _heightmap_relief := 0.0

var _biomes: Array[Biome] = []
var _climate_bias := Vector2(0.5, 0.5)
var _climate_wobble_noise := FastNoiseLite.new()
var _roughness_noise := FastNoiseLite.new()

## Sorted rarest-first so a rare ore (e.g. crystal) is checked - and can win
## - before a common one ever gets the chance to claim the same voxel. The
## old per-ore if/elif chain checked crystal last, so it was silently
## crowded out by commoner ores at any point where both noises cleared.
var _ore_types_by_rarity: Array[OreType] = []
## Which ore a deposit region favours, and whether this voxel sits in a vein
## of it. See _init() for why this replaced one-noise-per-ore.
var _deposit_noise := FastNoiseLite.new()
var _vein_noise := FastNoiseLite.new()
## Cumulative rarity shares over _ore_types_by_rarity; a deposit sample in
## [0,1) picks the first entry it falls under.
var _deposit_cdf := PackedFloat32Array()

## This body's typical surface gradient, used to express the cliff surface
## rule as a multiple of "normal for this planet" - see _init().
var _slope_reference := 0.0001

## Deepest any ore vein can reach below the surface - the inner edge of the
## shell _generate_block() actually has to sample noise in.
var _deepest_ore_depth := 0.0

## NOTE: godot_voxel calls _generate_block() on this same instance from
## several worker threads at once, so nothing here may hold mutable shared
## state. Caching the per-voxel biome result in one reused member Dictionary
## (to dodge the allocation) segfaulted the engine within seconds - the fix
## was to keep the per-voxel values in locals instead, see _generate_block()
## (2026-09-06).

## `body == null` (the @tool/editor-preview instantiation path, and any
## isolated test that doesn't care about a specific planet) falls back to
## the same numbers this generator always used - a real Planet always
## passes its own CelestialBody.
func _init(body: CelestialBody = null) -> void:
	var base_seed := 1
	if body != null:
		_radius = body.radius
		_height_amplitude = body.height_amplitude
		_detail_amplitude = body.detail_amplitude
		_biomes = body.biomes
		_climate_bias = body.climate_bias
		base_seed = body.seed
		_heightmap = body.heightmap
		if _heightmap != null:
			# Decode here, on the constructing thread, NOT lazily inside
			# _generate_block() - that runs on several worker threads at once
			# and populating a cache there is a data race.
			if not _heightmap.prepare():
				push_warning("PlanetHeightmap failed to prepare; falling back to noise-only shape.")
				_heightmap = null
			else:
				_heightmap_relief = _heightmap.max_deviation() / Planet.VOXEL_SCALE

	# Height noise is sampled on the unit sphere direction (not world position)
	# so it wraps seamlessly around the planet with no seams at poles/edges.
	# Fixed per-noise offsets from the one base seed give each body distinct
	# but reproducible terrain/ore/biome patterns from a single number.
	_height_noise.seed = base_seed
	_height_noise.frequency = 1.8
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_detail_noise.seed = base_seed + 5
	_detail_noise.frequency = 9.0
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	# Lower frequency than height/detail - biome regions should read as a
	# handful of large climate zones, not shimmer with the same density as
	# terrain hills. But these are sampled on the unit-sphere DIRECTION, whose
	# entire domain is only 2 units across: at the old 0.5 the field held
	# barely three features over the whole planet, so it could not break up
	# the latitude term it was supposed to perturb (see _generate_block).
	# ~2.0 gives roughly a dozen climate regions per great circle. The two
	# axes use slightly different frequencies so they don't visually correlate
	# into one blobby field.
	_climate_wobble_noise.seed = base_seed + 400
	_climate_wobble_noise.frequency = 2.0
	_climate_wobble_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_roughness_noise.seed = base_seed + 401
	_roughness_noise.frequency = 2.6
	_roughness_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	# Ore is a two-field model, not one noise per ore type.
	#
	# The old scheme sampled a separate noise per ore and took the first that
	# cleared its threshold inside a shared depth band. That produced ore in
	# concentric SHELLS: the depth gate is a function of radius, so every ore
	# occupied the same spherical layer under the surface and digging cut
	# straight through it as visible bands.
	#
	# Instead: a low-frequency DEPOSIT field decides which single ore (if any)
	# a whole region favours, and a mid-frequency VEIN field decides whether
	# this particular voxel is inside a vein of it. Depth is a soft weight on
	# top, not a hard gate. That gives localized single-ore deposits with
	# connected veins running through them, which is both how real ore bodies
	# read and what stops the banding. It is also cheaper: two noise samples
	# per solid voxel regardless of how many ore types the body defines,
	# against the old six.
	# CELLULAR / RETURN_CELL_VALUE, not simplex. Each Voronoi cell is one
	# deposit region and gets a single value that is constant inside it and
	# roughly UNIFORM across cells - which is exactly the semantics wanted
	# ("which ore, if any, does this deposit body contain") and is what makes
	# the rarity table below mean anything.
	#
	# Simplex would be wrong here twice over: its value drifts continuously
	# so a "region" has no edges, and its distribution is bell-shaped, so
	# feeding it through a uniform rarity CDF piles almost every deposit into
	# the middle entries. Measured with simplex: iron (the ore meant to be
	# commonest) came out at 2% of deposits and coal at 47%, exactly
	# inverted, because iron and crystal sit in the CDF's thin tails.
	#
	# Sampled on world voxel position, not the unit-sphere direction: a
	# deposit is a localized body of rock, not a wedge running all the way
	# through the planet.
	_deposit_noise.seed = base_seed + 300
	_deposit_noise.frequency = 0.012
	_deposit_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	_deposit_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	_deposit_noise.cellular_jitter = 1.0

	# 1 - abs(noise) peaks along the noise's zero set, which is a connected
	# surface - thresholded high that reads as veins/filaments rather than the
	# round blobs a plain threshold gives.
	_vein_noise.seed = base_seed + 301
	_vein_noise.frequency = 0.05
	_vein_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var ore_types := _resolve_ore_types(body)
	_ore_types_by_rarity = ore_types.duplicate()
	_ore_types_by_rarity.sort_custom(func(a: OreType, b: OreType) -> bool:
		return a.base_threshold > b.base_threshold)
	_build_deposit_cdf()
	for ore in _ore_types_by_rarity:
		_deepest_ore_depth = maxf(_deepest_ore_depth, ore.depth_max)

	# Characteristic surface gradient for this body: a noise field's mean
	# gradient scales with its frequency times its amplitude, and arc length
	# scales with radius. The cliff surface rule is expressed as a multiple
	# of this rather than an absolute number so it survives retuning terrain.
	_slope_reference = maxf(_height_amplitude * _height_noise.frequency / maxf(_radius, 0.0001), 0.000001)

	_cache_biome_arrays()

## Share of the planet's deposit regions each ore gets, derived from its
## rarity (`base_threshold`, higher = rarer). Cubed so the spread between
## common and rare ores is pronounced rather than nearly flat - at the raw
## values iron would only be ~1.7x more common than crystal.
func _build_deposit_cdf() -> void:
	_deposit_cdf.clear()
	var shares := PackedFloat32Array()
	var total := 0.0
	for ore in _ore_types_by_rarity:
		var share: float = pow(1.0 - clampf(ore.base_threshold, 0.0, 0.99), 3.0)
		shares.append(share)
		total += share
	if total <= 0.0001:
		return
	var acc := 0.0
	for s in shares:
		acc += s / total
		_deposit_cdf.append(acc)

## body.ore_types populated -> use it as-is. Otherwise fall back to the
## body's legacy scalar threshold fields (or, with no body at all, the
## numbers this generator has always used) so a CelestialBody that hasn't
## been migrated to the new per-ore/per-biome system still generates
## exactly as it did before biomes existed.
func _resolve_ore_types(body: CelestialBody) -> Array[OreType]:
	if body != null and not body.ore_types.is_empty():
		return body.ore_types
	if body != null:
		return [
			_default_ore_type("iron", VoxelMaterials.IRON_ORE, body.ore_iron_threshold, body.ore_vein_depth_min, body.ore_vein_depth_max, 0.08),
			_default_ore_type("copper", VoxelMaterials.COPPER_ORE, body.ore_copper_threshold, body.ore_vein_depth_min, body.ore_vein_depth_max, 0.08),
			_default_ore_type("sulfur", VoxelMaterials.SULFUR_ORE, body.ore_sulfur_threshold, body.ore_vein_depth_min, body.ore_vein_depth_max, 0.08),
			_default_ore_type("coal", VoxelMaterials.COAL_ORE, body.ore_coal_threshold, body.ore_vein_depth_min, body.ore_vein_depth_max, 0.09),
			_default_ore_type("silica", VoxelMaterials.SILICA_ORE, body.ore_silica_threshold, body.ore_vein_depth_min, body.ore_vein_depth_max, 0.07),
			_default_ore_type("crystal", VoxelMaterials.CRYSTAL_ORE, body.ore_crystal_threshold, body.ore_vein_depth_min, body.ore_vein_depth_max, 0.06),
		]
	return [
		_default_ore_type("iron", VoxelMaterials.IRON_ORE, 0.25, 0.5, 14.0, 0.08),
		_default_ore_type("copper", VoxelMaterials.COPPER_ORE, 0.3, 0.5, 14.0, 0.08),
		_default_ore_type("sulfur", VoxelMaterials.SULFUR_ORE, 0.35, 0.5, 14.0, 0.08),
		_default_ore_type("coal", VoxelMaterials.COAL_ORE, 0.32, 0.5, 14.0, 0.09),
		_default_ore_type("silica", VoxelMaterials.SILICA_ORE, 0.38, 0.5, 14.0, 0.07),
		_default_ore_type("crystal", VoxelMaterials.CRYSTAL_ORE, 0.55, 0.5, 14.0, 0.06),
	]

func _default_ore_type(id: String, material_index: int, threshold: float, depth_min: float, depth_max: float, frequency: float) -> OreType:
	var ore := OreType.new()
	ore.id = id
	ore.material_index = material_index
	ore.base_threshold = threshold
	ore.depth_min = depth_min
	ore.depth_max = depth_max
	ore.noise_frequency = frequency
	return ore

func _get_used_channels_mask() -> int:
	return (1 << SDF_CHANNEL) | (1 << INDICES_CHANNEL) | (1 << WEIGHTS_CHANNEL)

## Packs one fully-opaque material into the 4-slot format: all weight on the
## first slot, the rest padded with filler indices to satisfy uniqueness.
func _solid_indices(index: int) -> int:
	return (index & 0xf) | (FILLER_INDICES[0] << 4) | (FILLER_INDICES[1] << 8) | (FILLER_INDICES[2] << 12)

func _solid_weights() -> int:
	return WEIGHT_MAX

## Biome fields unpacked into flat parallel arrays at init time.
##
## The biome scan runs once per surface voxel - millions of times per body -
## and in GDScript the Resource property reads and the per-biome
## Biome.climate_distance() call cost more than the noise sampling they
## decide (measured 5.9 us/voxel, vs 1.5 us for the two terrain-height noise
## samples). Flat arrays let _generate_block() run the scan inline with no
## cross-object calls and no per-voxel Dictionary allocation. Written once in
## _init() and only ever read afterwards, which is what makes them safe under
## godot_voxel's multi-threaded calls into this same instance.
var _biome_count := 0
var _biome_t_min := PackedFloat32Array()
var _biome_t_max := PackedFloat32Array()
var _biome_r_min := PackedFloat32Array()
var _biome_r_max := PackedFloat32Array()
var _biome_h_mult := PackedFloat32Array()
var _biome_d_mult := PackedFloat32Array()
var _biome_stone := PackedInt32Array()
var _biome_ore_bias: Array[Dictionary] = []

func _cache_biome_arrays() -> void:
	_biome_count = _biomes.size()
	for biome in _biomes:
		_biome_t_min.append(biome.temperature_min)
		_biome_t_max.append(biome.temperature_max)
		_biome_r_min.append(biome.roughness_min)
		_biome_r_max.append(biome.roughness_max)
		_biome_h_mult.append(biome.height_amplitude_mult)
		_biome_d_mult.append(biome.detail_amplitude_mult)
		# TEXTURES_MIXEL4_S4 gives each material slot only 4 bits, so an index
		# above 15 would silently wrap into a different material.
		_biome_stone.append(clampi(biome.stone_material_index, 0, MAX_MATERIAL_INDEX))
		_biome_ore_bias.append(biome.ore_bias)

## Stone used for the deep interior, below where any biome's surface layer
## or ore vein can reach - biome selection is a surface-direction concern, so
## there's nothing to resolve down there.
func _default_stone_index() -> int:
	return VoxelMaterials.STONE

func _max_surface_deviation() -> float:
	var biome_scale := 1.0
	for biome in _biomes:
		biome_scale = maxf(biome_scale, maxf(biome.height_amplitude_mult, biome.detail_amplitude_mult))
	# The baked map's range ADDS to the noise range. Understating this culls
	# blocks that actually contain terrain, and they are never generated.
	return (_height_amplitude + _detail_amplitude) * biome_scale + _heightmap_relief

## Nearest/farthest distance from the body center to any point of an
## axis-aligned box - used to classify a whole block as all-air or
## all-stone without touching a single voxel.
func _box_distance_range(box_min: Vector3, box_max: Vector3) -> Vector2:
	var near := Vector3(
		maxf(box_min.x, minf(0.0, box_max.x)) if box_max.x < 0.0 or box_min.x > 0.0 else 0.0,
		maxf(box_min.y, minf(0.0, box_max.y)) if box_max.y < 0.0 or box_min.y > 0.0 else 0.0,
		maxf(box_min.z, minf(0.0, box_max.z)) if box_max.z < 0.0 or box_min.z > 0.0 else 0.0)
	var far := Vector3(
		maxf(absf(box_min.x), absf(box_max.x)),
		maxf(absf(box_min.y), absf(box_max.y)),
		maxf(absf(box_min.z), absf(box_max.z)))
	return Vector2(near.length(), far.length())

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	var size := out_buffer.get_size()
	var lod_step := 1 << lod
	var pos_world := Vector3.ZERO
	var amplitude_span := maxf(_height_amplitude + _detail_amplitude, 0.001)

	# The interesting shell is [radius - deviation - deepest ore vein,
	# radius + deviation]. Outside it the answer is a constant, so most
	# blocks (deep interior and open sky) can be filled uniformly instead of
	# running ~15 noise samples per voxel. Without this, a body the size of
	# the alpha planet takes minutes to stream in and the player is left
	# standing on nothing (2026-09-06).
	var deviation := _max_surface_deviation()
	var shell_outer := _radius + deviation
	var shell_inner := _radius - deviation - _deepest_ore_depth

	# Locals only - merged into the shared totals once at the end of the block.
	var _p_t0 := Time.get_ticks_usec() if profile_enabled else 0
	var _p_air := 0
	var _p_deep := 0
	var _p_full := 0
	var _p_shape := 0
	var _p_climate := 0
	var _p_material := 0

	var box_min := Vector3(origin_in_voxels) - CENTER
	var box_max := box_min + Vector3(size) * float(lod_step)
	var range_to_center := _box_distance_range(box_min, box_max)
	if range_to_center.x > shell_outer:
		# Entirely outside the tallest possible terrain: solid air.
		out_buffer.fill_f((range_to_center.x - _radius) / lod_step, SDF_CHANNEL)
		if profile_enabled:
			_prof_merge({"blocks": 1, "uniform_air": 1,
				"block_usec": Time.get_ticks_usec() - _p_t0})
		return
	if range_to_center.y < shell_inner:
		# Entirely below the deepest ore vein: plain bedrock, no ore rolls.
		out_buffer.fill_f((range_to_center.y - _radius) / lod_step, SDF_CHANNEL)
		out_buffer.fill(_solid_indices(BEDROCK_INDEX), INDICES_CHANNEL)
		out_buffer.fill(_solid_weights(), WEIGHTS_CHANNEL)
		if profile_enabled:
			_prof_merge({"blocks": 1, "uniform_solid": 1,
				"block_usec": Time.get_ticks_usec() - _p_t0})
		return

	for rz in size.z:
		pos_world.z = origin_in_voxels.z + rz * lod_step
		for rx in size.x:
			pos_world.x = origin_in_voxels.x + rx * lod_step
			for ry in size.y:
				pos_world.y = origin_in_voxels.y + ry * lod_step

				var to_center := pos_world - CENTER
				var dist := to_center.length()

				# Same classification as the block-level test above, for the
				# voxels of a block that only partly straddles the shell.
				if dist > shell_outer:
					out_buffer.set_voxel_f((dist - _radius) / lod_step, rx, ry, rz, SDF_CHANNEL)
					continue
				if dist < shell_inner:
					out_buffer.set_voxel_f((dist - _radius) / lod_step, rx, ry, rz, SDF_CHANNEL)
					out_buffer.set_voxel(_solid_indices(BEDROCK_INDEX), rx, ry, rz, INDICES_CHANNEL)
					out_buffer.set_voxel(_solid_weights(), rx, ry, rz, WEIGHTS_CHANNEL)
					continue

				var dir := to_center / dist if dist > 0.0001 else Vector3.UP

				var _p_vt := Time.get_ticks_usec() if profile_timings else 0
				var height_n := _height_noise.get_noise_3d(dir.x, dir.y, dir.z)
				var detail_n := _detail_noise.get_noise_3d(dir.x, dir.y, dir.z)

				# Baked map carries the large-scale shape; the noise octaves are
				# demoted to detail below its pixel scale. With no map they
				# carry the shape themselves, exactly as before.
				var map_elevation := 0.0
				if _heightmap != null:
					map_elevation = _heightmap.elevation(dir) / Planet.VOXEL_SCALE
				var base_surface_radius := _radius + map_elevation 					+ height_n * _height_amplitude + detail_n * _detail_amplitude
				# --- early-out on voxels whose material is already decided ---
				#
				# The shell is ~94 voxels thick once a heightmap is in play, but
				# only a thin band around the actual local surface, plus the ore
				# depth range, needs the full climate/biome/slope/ore path. Every
				# other voxel in the shell is either plain air well above the
				# ground or plain bedrock well below the deepest vein, and both
				# were previously paying for ~6 noise samples, a biome scan and a
				# 4-slot material pack to arrive at a foregone conclusion.
				#
				# `base_surface_radius` omits the per-biome amplitude multipliers,
				# so it can be off by at most the biome-scaled noise amplitude -
				# BIOME_SURFACE_MARGIN covers that. SDF written here is far enough
				# from the isosurface that the buffer's fixed-point range clamps
				# it anyway, so the approximation cannot move a surface.
				var approx_sd := dist - base_surface_radius
				if approx_sd > BIOME_SURFACE_MARGIN:
					out_buffer.set_voxel_f(approx_sd / lod_step, rx, ry, rz, SDF_CHANNEL)
					_p_air += 1
					continue
				if approx_sd < -(_deepest_ore_depth + BIOME_SURFACE_MARGIN):
					out_buffer.set_voxel_f(approx_sd / lod_step, rx, ry, rz, SDF_CHANNEL)
					out_buffer.set_voxel(_solid_indices(BEDROCK_INDEX), rx, ry, rz, INDICES_CHANNEL)
					out_buffer.set_voxel(_solid_weights(), rx, ry, rz, WEIGHTS_CHANNEL)
					_p_deep += 1
					continue

				_p_full += 1
				if profile_timings:
					_p_shape += Time.get_ticks_usec() - _p_vt
					_p_vt = Time.get_ticks_usec()

				var elevation_norm := clampf((base_surface_radius - _radius) / amplitude_span, -1.0, 1.0)
				# --- climate axes (inlined, was _climate_at/_slope_at) ---
				# temperature: cold at the poles and at high elevation, shifted
				# by the body's climate_bias, with a low-frequency wobble so
				# borders aren't perfect latitude rings. roughness: independent
				# low-frequency noise (stands in for a humidity axis) blended
				# with a cheap finite-difference surface slope, so cliffs and
				# crater rims read as harsh regardless of climate.
				var tangent := dir.cross(Vector3.UP)
				if tangent.length_squared() < 0.000001:
					tangent = dir.cross(Vector3.RIGHT)
				tangent = tangent.normalized()
				var bitangent := dir.cross(tangent).normalized()
				var da := (dir + tangent * SLOPE_EPS).normalized()
				var db := (dir + bitangent * SLOPE_EPS).normalized()
				var ha := _height_noise.get_noise_3d(da.x, da.y, da.z)
				var hb := _height_noise.get_noise_3d(db.x, db.y, db.z)
				# Dividing by (2 * SLOPE_EPS) recovers the mean gradient
				# magnitude of the height noise, which sits near its own
				# frequency (~1.8). The old * 0.5 mapped that onto ~0.9, so
				# slope saturated at 1.0 almost everywhere and dragged
				# roughness permanently into its top half - which starved
				# every low-roughness biome. SLOPE_NORM puts typical terrain
				# near the middle of the axis instead.
				var slope := clampf((absf(ha - height_n) + absf(hb - height_n)) / (2.0 * SLOPE_EPS) / SLOPE_NORM, 0.0, 1.0)

				# Climate is a 3D field over the sphere direction. A latitude
				# term still exists - poles genuinely do run colder - but it
				# is deliberately the minority contribution. It used to carry
				# weight 1.0 against a 0.15 wobble (measured 6-112x stronger
				# than the noise meant to break it up), which drew the biome
				# borders as concentric rings around the world Y axis and made
				# the planet read as layered along one axis rather than
				# spherical.
				var climate_n := _climate_wobble_noise.get_noise_3d(dir.x, dir.y, dir.z) * 0.5 + 0.5
				var latitude_term := 1.0 - absf(dir.y)
				var temperature := clampf(
					climate_n * 0.65
					+ latitude_term * 0.35
					- elevation_norm * 0.12
					+ (_climate_bias.x - 0.5), 0.0, 1.0)
				var rough_noise := _roughness_noise.get_noise_3d(dir.x, dir.y, dir.z) * 0.5 + 0.5
				var roughness := clampf(rough_noise * 0.7 + slope * 0.3 + (_climate_bias.y - 0.5), 0.0, 1.0)

				# --- biome (inlined, was _resolve_biome) ---
				# Nearest biome in climate space owns the stone/ore identity;
				# the two nearest blend their terrain amplitudes across
				# BIOME_BLEND_WIDTH so borders aren't hard steps. No biomes
				# resolves to the pre-biome identity: plain stone, no amplitude
				# change, no ore bias.
				var stone_index := VoxelMaterials.STONE
				var height_mult := 1.0
				var detail_mult := 1.0
				var ore_bias := EMPTY_ORE_BIAS
				if _biome_count > 0:
					var best := -1
					var best_dist := INF
					var second := -1
					var second_dist := INF
					for bi in _biome_count:
						var dt := 0.0
						if temperature < _biome_t_min[bi]:
							dt = _biome_t_min[bi] - temperature
						elif temperature > _biome_t_max[bi]:
							dt = temperature - _biome_t_max[bi]
						var dr := 0.0
						if roughness < _biome_r_min[bi]:
							dr = _biome_r_min[bi] - roughness
						elif roughness > _biome_r_max[bi]:
							dr = roughness - _biome_r_max[bi]
						var bd := sqrt(dt * dt + dr * dr)
						if bd < best_dist:
							second = best
							second_dist = best_dist
							best = bi
							best_dist = bd
						elif bd < second_dist:
							second = bi
							second_dist = bd
					stone_index = _biome_stone[best]
					ore_bias = _biome_ore_bias[best]
					height_mult = _biome_h_mult[best]
					detail_mult = _biome_d_mult[best]
					if second >= 0:
						var w0 := maxf(0.0, 1.0 - best_dist / BIOME_BLEND_WIDTH)
						var w1 := maxf(0.0, 1.0 - second_dist / BIOME_BLEND_WIDTH)
						var wsum := w0 + w1
						if wsum > 0.0001:
							height_mult = (_biome_h_mult[best] * w0 + _biome_h_mult[second] * w1) / wsum
							detail_mult = (_biome_d_mult[best] * w0 + _biome_d_mult[second] * w1) / wsum

				if profile_timings:
					_p_climate += Time.get_ticks_usec() - _p_vt
					_p_vt = Time.get_ticks_usec()

				var surface_radius: float = _radius + map_elevation \
					+ height_n * _height_amplitude * height_mult \
					+ detail_n * _detail_amplitude * detail_mult

				var signed_distance := dist - surface_radius
				out_buffer.set_voxel_f(signed_distance / lod_step, rx, ry, rz, SDF_CHANNEL)

				if signed_distance < 0.0:
					var depth_below_surface := surface_radius - dist

					# --- surface rules ---
					# Real surface gradient: metres of radius change per metre
					# of arc, from the same finite differences the climate
					# roughness axis already paid for. Normalised against this
					# body's own characteristic gradient so the rule keeps
					# meaning if terrain amplitude changes - an absolute
					# threshold would silently stop firing on a flatter planet
					# and cover a rougher one entirely in cliff.
					var arc := maxf(SLOPE_EPS * _radius, 0.0001)
					var amp := _height_amplitude * height_mult
					var grad_a := absf(ha - height_n) * amp / arc
					var grad_b := absf(hb - height_n) * amp / arc
					var surface_grad := sqrt(grad_a * grad_a + grad_b * grad_b)
					var cliff_frac := clampf(surface_grad / maxf(_slope_reference * CLIFF_SLOPE_MULT, 0.000001), 0.0, 1.0)

					# Topsoil gives way to bedrock with depth, softly, so a
					# dug shaft shows a graded crust instead of a hard step.
					var bed_frac := clampf((depth_below_surface - TOPSOIL_DEPTH) / BEDROCK_FADE, 0.0, 1.0)

					# --- ore: deposit region picks the type, vein field picks
					# the voxel, depth only weights it (see _init) ---
					var ore_weight := 0.0
					var ore_index := -1
					if not _deposit_cdf.is_empty():
						# Voronoi cell value: constant across one deposit
						# body, uniform between bodies. Cells above the ore
						# share are barren rock and cost nothing further.
						var cell := _deposit_noise.get_noise_3d(pos_world.x, pos_world.y, pos_world.z) * 0.5 + 0.5
						if cell < ORE_REGION_SHARE:
							var u := cell / ORE_REGION_SHARE
							var pick := 0
							while pick < _deposit_cdf.size() - 1 and u > _deposit_cdf[pick]:
								pick += 1
							var ore: OreType = _ore_types_by_rarity[pick]
							var depth_w: float = smoothstep(ore.depth_min - 1.5, ore.depth_min + 1.5, depth_below_surface) \
								* (1.0 - smoothstep(ore.depth_max - 2.0, ore.depth_max + 2.0, depth_below_surface))
							if depth_w > 0.01:
								# Biome bias widens or narrows veins rather
								# than gating them, per the biome design's
								# "ore_bias is never a hard gate" rule.
								var bias: float = ore_bias.get(ore.id, 1.0)
								var width := VEIN_WIDTH * clampf(bias, 0.05, 8.0)
								var vein := absf(_vein_noise.get_noise_3d(pos_world.x, pos_world.y, pos_world.z))
								if vein < width:
									ore_weight = (1.0 - vein / width) * depth_w
									ore_index = ore.material_index

					# --- pack 4 unique materials + weights ---
					var w_bed := bed_frac
					var w_cliff := (1.0 - bed_frac) * cliff_frac
					var w_ground := (1.0 - bed_frac) * (1.0 - cliff_frac)
					var w_ore := ore_weight
					var total := w_ground + w_cliff + w_bed + w_ore
					if total < 0.0001:
						w_ground = 1.0
						total = 1.0
					var inv := WEIGHT_MAX / total

					var i3: int = ore_index if ore_index >= 0 else FILLER_INDICES[0]
					out_buffer.set_voxel(
						(stone_index & 0xf)
						| ((CLIFF_INDEX & 0xf) << 4)
						| ((BEDROCK_INDEX & 0xf) << 8)
						| ((i3 & 0xf) << 12),
						rx, ry, rz, INDICES_CHANNEL)
					out_buffer.set_voxel(
						clampi(int(round(w_ground * inv)), 0, WEIGHT_MAX)
						| (clampi(int(round(w_cliff * inv)), 0, WEIGHT_MAX) << 4)
						| (clampi(int(round(w_bed * inv)), 0, WEIGHT_MAX) << 8)
						| (clampi(int(round(w_ore * inv)), 0, WEIGHT_MAX) << 12),
						rx, ry, rz, WEIGHTS_CHANNEL)
					if profile_timings:
						_p_material += Time.get_ticks_usec() - _p_vt

	if profile_enabled:
		_prof_merge({
			"blocks": 1,
			"block_usec": Time.get_ticks_usec() - _p_t0,
			"voxels": _p_air + _p_deep + _p_full,
			"air_skip": _p_air, "deep_skip": _p_deep, "full": _p_full,
			"t_shape_usec": _p_shape, "t_climate_usec": _p_climate,
			"t_material_usec": _p_material,
		})


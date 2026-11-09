class_name PlanetGraphGenerator
extends RefCounted

## Builds a `VoxelGeneratorGraph` for one `CelestialBody`.
##
## Phase 3 of the terrain plan. The graph is compiled and evaluated in C++ a
## whole block at a time with automatic range analysis, which is the same
## optimisation the GDScript generator could only approximate by hand.
## Measured head-to-head on identical blocks: 61x on shape alone, 13x with
## noise and materials. Time to first walkable ground went 40-60 s -> 3.4 s.
##
## Built in CODE from the resource rather than hand-authored as a .tres,
## because a saved graph hardcodes exactly one planet and the standing rule is
## that a new body is a new resource - never a new script or scene.
##
## THE GRAPH HAS NO BRANCHING. The script generator picks a biome by
## nearest-neighbour in climate space and an ore by rarest-first priority;
## both are control flow. This replaces them with independent weight layers -
## every material computes its own membership and the mesher keeps the
## strongest four. Same result, no branches, and biome borders blend smoothly
## instead of stepping.
##
## Node gotchas, all silent-failure shaped:
##   - `SdfSphere` takes radius as INPUT PORT 3, not a parameter (it has none).
##   - `FastNoise3D` needs `ZN_FastNoiseLite`, not Godot's `FastNoiseLite`.
##   - `SdfSphereHeightmap` reads ONE channel, so the baked RG-packed PNG has
##     to be converted to FORMAT_RF first.
##   - `Planet` preloads this script, so nothing here may read
##     `Planet.VOXEL_SCALE` - that cycle fails to parse, and Godot reports it
##     as an error in an unrelated file.

const GROUND_LAYER := 0      # VoxelMaterials.STONE
const BEDROCK_LAYER := 12    # VoxelMaterials.BEDROCK
const CLIFF_LAYER := 11      # VoxelMaterials.CLIFF_ROCK

## Angular step used to difference the height field, in radians. Small enough to
## be a local slope, large enough that the difference is not swamped by float
## noise at kilometre radii.
const SLOPE_EPSILON := 0.0015
## Surface gradient (voxels of height per voxel of arc) at which a face reads as
## fully cliff. Below this it blends back to biome stone.
## Cliff rock belongs on faces that are genuinely cliffs, not on every slope
## that is slightly steeper than its neighbour. Raised after measuring cliff
## rock PRESENT (weight above zero) in 76% of surface samples: it was taking a
## blend slot across most of the planet and its brightness read as pale bands
## following the contours.
const CLIFF_FULL_SLOPE := 3.4
const CLIFF_START_SLOPE := 1.7

## Caves. Two independent noise fields are thresholded and INTERSECTED: a single
## |noise| < w region is a connected sheet through the rock, which reads as a
## collapsed quarry rather than a cave system. Intersecting two gives tubes,
## because a point has to be near the zero-set of both at once.
const CAVE_TUBE_WIDTH := 0.09
## Tunnel bore in voxels, roughly. Larger = fewer, fatter caverns.
const CAVE_SIZE_VOXELS := 26.0
## Blend radius where a cave meets the rock face, so entrances are rounded
## rather than knife-edged.
const CAVE_SMOOTHNESS := 3.0
## How much solid rock must sit above a cave before it may exist, and over what
## depth it fades in. Expressed as MULTIPLES OF THE CAVE BORE, not as absolute
## voxels.
##
## They were absolute (8 and 14) and tuned when relief was 300 voxels. At 149 the
## crust is half as thick, so 26-voxel-bore caves reached the surface and turned
## it to floating shards - measured: spawn could not find a collider at all and
## timed out at 60 s, versus 22.9 s with caves off. A cave needs rock above it in
## proportion to its own size, which is a ratio, not a constant. This is the same
## scale-dependency that has now bitten relief, noise frequency, atmosphere
## energy and LOD distance.
const CAVE_CEILING_BORES := 0.85
const CAVE_CEILING_FADE_BORES := 1.3

## ZN_FastNoiseLite fractal type ids (see FRACTAL_TYPE probe, 2026-09-11):
## NONE=0, FBM=1, RIDGED=2, PING_PONG=3. Named here rather than looked up per
## call because `ClassDB.class_get_integer_constant` is a string lookup - fine
## once at graph-build time, wasteful if it ran per noise node.
const FRACTAL_FBM := 1
const FRACTAL_RIDGED := 2

## Facet ridgelines: quantise the ridge value into planar bands before it
## becomes height, so slopes read as flat faces meeting at edges instead of one
## smooth ramp. Blended rather than pure stepify, and at a MUCH finer step than
## the mesa terracing below, so peaks get faceted without the whole range
## turning into a wedding cake - that is the mesa job, at a coarse step and
## confined to its own gated region.
##
## Dimensionless (the ridge value this quantises is already 0..1 out of its own
## curve), so unlike the mesa step it does not need to live in PlanetProfile -
## same footing as CLIFF_START_SLOPE or CLIMATE_BLEND below.
const FACET_STEPS := 9.0
const FACET_BLEND := 0.55

## Craters, from the old procedural path. NOTE: `NODE_SPOTS_3D` is BINARY - probed
## 2026-09-12 with `scripts/dev/spots_probe.gd`, it returns ~0.99 everywhere
## inside the radius and 0 outside, with a hard step and no falloff. An earlier
## note here said it was "highest at each blob's own centre", which was a misread,
## and it matters: `crater_curve()` mapped that value through rim, wall and floor
## segments that could never be reached, so every crater came out as a
## hard-edged disc and its edge read as a ring. A smooth crater needs a
## continuous distance field - cellular noise returning DISTANCE - not this node.
const CRATER_JITTER := 0.9

## Test-only override for the rock band's octave count, so its cost can be
## attributed without editing constants between runs. -1 uses the shipped value.
static var ROCK_OCTAVES_OVERRIDE: int = -1
## Test-only overrides for the rock band's shape, set by the dev instruments so a
## tuning question costs one run instead of an edit-rebuild cycle. Negative means
## "use the shipped constant".
static var ROCK_FACET_BLEND_OVERRIDE: float = -1.0
static var ROCK_FACET_STEPS_OVERRIDE: float = -1.0
static var ROCK_AMPLITUDE_MULT: float = 1.0
static var CRAG_AMPLITUDE_MULT: float = 1.0
static var GRAIN_AMPLITUDE_MULT: float = 1.0
static var SWELL_AMPLITUDE_MULT: float = 1.0
static var CRATER_AMPLITUDE_MULT: float = 1.0
## Forces the rockiness gate to a fixed value, so the band can be judged at full
## strength without also arguing about where it belongs. Negative = use the real
## field.
static var ROCK_FORCE_GATE: float = -1.0
## Spot radius as a fraction of the cell it sits in. Below 0.5 so neighbouring
## craters do not solidly overlap into a shattered mess.
const CRATER_RADIUS_FRAC := 0.42
## Talus / scree apron at the foot of a mountain. Built from fields the height
## chain already has (`erosion01`, `belt`) rather than a new noise sample, so
## the apron sits at the SAME characteristic wavelength as the peak it flanks
## instead of introducing a second, unrelated distance scale.
const TALUS_SHARE := 0.35

## Depth below the surface (voxels) over which ground gives way to bedrock.
## Matches ore_generator.gd so both generators produce the same crust.
## How far, in voxels, the 3D overhang field displaces the surface. See
## _carve_overhangs - this is the one number that decides between "rock leans
## out over you" and "the ground has come apart into shelves".
const OVERHANG_VOXELS := 3.5

const TOPSOIL_DEPTH := 2.5
const BEDROCK_FADE := 6.0

## --- ground character: where the planet is rock and where it is dust --------
##
## Baseline distance, in metres of arc, over which landform slope is measured.
## Roughly 1.5 erosion texels: fine enough to find an escarpment, coarse enough
## that it describes the LANDFORM rather than the rock band sitting on it (which
## would make the gate that controls the rock band depend on the rock band).
const SLOPE_SAMPLE_M := 18.0
## Landform gradient (height per unit of arc) where ground starts and finishes
## reading as steep. tan(12 deg) and tan(40 deg).
##
## Squared, because _build_landform_slope compares squared gradients - a
## monotonic substitution that saves a square root per voxel.
const SLOPE_START := 0.213
const SLOPE_FULL := 0.839
## The same thresholds in degrees, for the baked slope mask (angle / 90).
const SLOPE_START_DEG := 12.0
const SLOPE_FULL_DEG := 40.0

## How strongly slope and scouring each argue that ground is broken rock.
##
## Slope dominates deliberately. Deposition alone was the only signal before
## this, and its median over the home planet is 1.00 - meaning the rock band was
## suppressed over most of the world and the ground had no metre-scale relief
## anywhere, on flats and cliff faces alike. Steep ground is bare rock whatever
## the sediment record says, because material does not stay on it.
const ROCKY_FROM_SLOPE := 0.85
const ROCKY_FROM_SCOUR := 0.45
## Rock relief left on fully dust-mantled ground. Not zero - a regolith plain is
## not a mirror - but far below what a rock face carries.
const ROCK_DUST_FLOOR := 0.05

## Quantisation applied to the rock band, and how far it is blended in.
##
## Ridged noise on its own gives rounded swells: every slope is a smooth ramp, so
## the ground reads as a carpet of lumps however much amplitude it is given.
## Stepping the band puts flat faces and hard edges into it, which is what makes
## rock read as rock. Same primitive the mountain facets use, at rock scale.
##
## Applied to the BAND, never to summed height. Quantising a total height field
## draws topographic contour rings around the whole planet - that mistake is
## recorded at length in terrain-generator.md and cost several passes to find.
const ROCK_FACET_STEPS := 4.0
const ROCK_FACET_BLEND := 0.5

## Crags: the coarse band that carries actual edges. Feature size is well above
## the rock band so the two read as different things rather than one thicker
## carpet, and the facet step is coarse because that is what puts a bench across
## an outcrop instead of merely roughening it.
const CRAG_FEATURE_M := 20.0
const CRAG_AMPLITUDE_M := 5.0
const CRAG_FACET_STEPS := 2.2
const CRAG_FACET_BLEND := 0.62
## Crags stand in groups with bare ground between, set by a patch field an order
## of magnitude coarser than the crags themselves.
const CRAG_PATCH_M := 90.0
const CRAG_PATCH_START := 0.35
const CRAG_PATCH_FULL := 0.62
## And only on ground that is properly rocky, not merely a bit steep.
const CRAG_ROCKY_START := 0.22
const CRAG_ROCKY_FULL := 0.55
## Landform steepness (the 0..1 slope mask, itself ramping 12..40 degrees) that
## crags need before they appear at all, and where they reach full strength.
## Low on purpose. The mask is read from `height_lo`, whose ~61 m texel averages
## a cliff with the ground around it and so under-reports steepness: at 0.15/0.5
## a 54 degree face lost more than half its crag relief (0.66 -> 0.28 m rms
## below 4 m). Meadows sit below the mask's own 12 degree floor and read 0
## whatever these are, so lowering them costs the flats nothing.
## Share of the 7 m rock band that survives on flat ground. See the rock gate in
## _build_rock_relief for the measurement behind it.
const ROCK_BAND_FLAT_FLOOR := 0.2
const CRAG_SLOPE_START := 0.02
const CRAG_SLOPE_FULL := 0.2

## Grain: the finest shape the terrain can carry on a 1 m voxel. Present on dust
## as well as rock, at a fraction of the strength, because a regolith plain is
## smooth but not polished.
const GRAIN_FEATURE_M := 2.6
const GRAIN_AMPLITUDE_M := 0.3
const GRAIN_DUST_SHARE := 0.45

## Craters on dust-mantled ground, at three sizes: [period m, depth m, rim m, seed].
##
## What a dusty moon plain actually is. Its "random details" are craters of every
## size on a gently undulating surface - not rocks, and not waves. Depth over
## diameter sits near 0.045 for the largest, i.e. old and softened by the dust
## rather than fresh, which is what reads as regolith rather than as a bombing
## range.
##
## Built from cellular DISTANCE, not `NODE_SPOTS_3D`. Spots3D is a step - inside
## or outside a sphere - so no profile can make a bowl out of it, and the
## previous craters were hard-edged discs whose edges read as rings. Probed in
## `scripts/dev/cellular_probe.gd`: the distance return is continuous, near -1 at
## a feature point, so `value + 1` is distance in cells.
const CRATER_SIZES := [
	[900.0, 30.0, 6.0, 61],
	[260.0, 9.0, 2.0, 62],
	[70.0, 2.5, 0.6, 63],
]
## Crater radius as a fraction of its cell - in 3D, not on the surface.
##
## The feature points are scattered through 3D direction-space and the ground
## only passes near them, so a crater is where the surface cuts a sphere of this
## radius around a point: a big bowl where the point sits on the ground, a small
## shallow one where the ground only grazes it. That is also where the size
## variety comes from.
##
## 0.22 almost never fired. Probed along 2 km of real surface
## (`scripts/dev/cellular_dir_probe.gd`), the cellular value never went below
## -0.68 - the ground stayed at least 0.32 cells from every point - and the
## 1.5 km hillshade with craters on measured identical to craters off.
##
## The rim finishes at CRATER_RIM_END times this, which has to stay under roughly
## half the spacing between points so the profile is exactly zero before a
## Voronoi boundary: distance fields crease there, and a crease under a sloping
## profile is a visible line. Overlapping craters sharing a sharp rim are the
## exception, and real ones do.
const CRATER_RADIUS_CELLS := 0.30
const CRATER_CELL_JITTER := 0.6
## Where the rim starts rising inside the bowl, and where it has faded back to
## flat ground outside, in units of crater radius.
const CRATER_RIM_START := 0.55
const CRATER_RIM_END := 1.35


## Broad, very gentle undulation on dust-mantled ground - the large-scale form a
## meadow sits on, with craters as its detail. Long wavelength and low relief on
## purpose: at 450 m and 5 m the slopes stay near 2 degrees, so this reads as the
## ground rising and falling rather than as waves.
const SWELL_FEATURE_M := 450.0
const SWELL_AMPLITUDE_M := 5.0
## Warp displacement as a fraction of the swell's own wavelength. Above the 0.18
## default because this band has to stop reading as regular, and no higher than
## ~0.3: past that a warp folds its domain, which is exactly what tore the eroded
## map into hairline seams (see erosion_baker.gd warp_strength).
const SWELL_WARP_FRACTION := 0.28

## Half-thickness of an ore vein in noise units, same meaning as the script
## generator's constant of the same name.
const VEIN_WIDTH := 0.035

## Metres between ore deposit sites. Deposits are discrete and worth travelling
## to; this is the distance that decides whether prospecting is a journey or a
## formality.
const DEPOSIT_SPACING_M := 500.0
## Deposit radius, in the units Spots3D wants - which are NOT a plain sphere
## radius in metres, whatever the port name suggests. Measured against the
## generated buffer rather than derived: at 210 against a 1400 cell the field
## was empty (0 of 32768 samples, where a sphere model predicts ~460), and at
## 600 it filled 7%. Tuned by measurement, and the deposit spacing below is the
## number that actually controls how far apart deposits feel.
const DEPOSIT_RADIUS_M := 250.0
const DEPOSIT_JITTER := 0.85
## How far each ore's region window is widened past its 1/n share, so sites
## carry two or three ores stacked by depth instead of exactly one.
const REGION_OVERLAP := 0.18

## Softness of a biome/ore membership edge, in the 0..1 units of the field
## being windowed.
const CLIMATE_BLEND := 0.06
const REGION_BLEND := 0.04
## Radius, in climate units, over which one biome's influence falls to zero.
## The climate space is the unit square, so a value near 0.7 guarantees every
## point is reached by at least one biome no matter how the palette is arranged.
## Narrowed from 0.5. The falloff has to be wide enough that every point in
## climate space is reached by SOME biome, but every extra biome that reaches a
## point is another competitor for a blend slot. At 0.5 three or four biomes
## overlapped almost everywhere; at 0.32 it is usually one, occasionally two at
## a border - which is what the reference ground looks like: one material with
## variation, not a patchwork.
const BIOME_WEIGHT_FLOOR := 0.02
const BIOME_INFLUENCE := 0.32
## Biome stone is capped below full strength so a full-strength ore vein always
## outranks it.
##
## TEXTURES_MIXEL4_S4 keeps only the FOUR strongest weights per voxel. With four
## biomes all contributing meaningfully and bedrock taking a slot, ore veins were
## pushed out entirely - measured: every ore disappeared from a 600-direction
## sample the moment biome coverage was made complete. Ranking matters here, not
## just magnitude.
const BIOME_WEIGHT_SCALE := 0.7

## Weights below this are forced to zero so the material never occupies one of
## the mesher's four slots. See _cutoff() for why that matters so much.
## Below the 1/N floor a normalised biome set guarantees (0.25 for four
## biomes), so the cutoff can never silently erase the winning material.
const WEIGHT_CUTOFF := 0.12
const WEIGHT_CUTOFF_FADE := 0.18
## Depth window softness, in voxels.
const DEPTH_BLEND := 2.0

## How far local climate variation swings either side of the body's orbital
## temperature. Below 1.0 so a genuinely cold world stays cold everywhere
## instead of every planet ending up with the same full 0..1 range of biomes.
const ORBITAL_TEMP_SPREAD := 0.7

## The centre-direction ridge node from the most recent _build_height_offset
## call, so the slope mask can difference against the SAME node the height field
## used instead of building a second copy that could silently diverge.
static var _last_ridge: Array = []

## Ground character from the most recent _build_eroded_shape call: how much this
## voxel's ground is broken rock rather than dust, 0..1, and the landform slope
## it was built from. Shape and materials MUST agree about this - rock relief
## painted with dust, or dust painted on a rock face, is the same mismatch the
## erosion masks were introduced to remove.
static var _last_rocky: Array = []
static var _last_slope: Array = []
## Strata beds as a 0..1 band (1 = the hard bed, STRATA_A), on ABSOLUTE radius with a slow warp: real beds are laid
## down level and cut by the landform, so a hillside shows them as contour stripes and a cliff as horizontal ledges.
## Shared by the shape (ledges) and the materials (stripes), built once per graph.
static var _strata_soft: Array = []
## The rock relief (crags, rock, grain) added on top of the eroded map, in voxels.
static var _last_relief: Array = []
## The overhang term (_overhang_amount), cached per graph.
static var _last_overhang: Array = []
static var _strata_band: Array = []

## `voxel_scale` is passed in rather than read from Planet.VOXEL_SCALE - see
## the circular-preload note above.
## Samples one of the erosion masks at this voxel's direction, 0..1.
##
## Built from an SDF_SPHERE_HEIGHTMAP minus a plain SDF_SPHERE of the same
## radius, which is an odd-looking way to read a texture and is deliberate.
## SDF_SPHERE_HEIGHTMAP(img, r, 1) evaluates to `length(p) - r - img(dir)` and
## SDF_SPHERE(r) to `length(p) - r`, so the difference is exactly `img(dir)`.
##
## The alternative is computing longitude and latitude by hand and feeding an
## IMAGE_2D. That needs an EXPRESSION node with atan2 and asin in it, and worse,
## it would be a SECOND implementation of the equirectangular projection that
## has to stay byte-identical to the one in the height lookup and in
## generate.glsl. Two of those already have to agree; a third that can silently
## drift half a texel and rotate every mask off its own terrain is not worth the
## few microseconds it might save. Going through the same node guarantees the
## mask lands on the landform it describes.
##
## SAMPLED ON THE NOMINAL SPHERE, not at the voxel. The node has an early-out: more than 1.2 x its image range
## (here ~2 m) from its radius it skips the image and returns the plain distance, so fed the real voxel position the
## difference below was 0 everywhere except a 2 m shell around the nominal radius. Found 2026-11-09: every mask
## (slope, deposition, talus, wear) read 0 over nearly the whole planet - no cliff rock, no dust rules, no talus.
## The voxel's direction is put on a sphere of MASK_SAMPLE_R instead (same direction, so the same map texel).
## `radius` is kept in the signature for the callers; the sample radius no longer depends on it.
const MASK_SAMPLE_R := 1000.0

static func _sample_mask(f: VoxelGraphFunction, x: int, y: int, z: int,
		image: Image, radius: float, pos: Vector2) -> Array:
	if image == null:
		return []
	return sample_mask_on_sphere(f, x, y, z, image, pos)

## Shared with the scatter placement graphs (ScatterEngine, BoulderScatter): mask value 0..1 at the direction of
## (x, y, z), through the same node the terrain height uses (SphereUV projection).
static func sample_mask_on_sphere(f: VoxelGraphFunction, x: int, y: int, z: int, image: Image,
		pos: Vector2) -> Array:
	var nn := f.create_node(VoxelGraphFunction.NODE_NORMALIZE_3D, pos + Vector2(-160, 0))
	f.add_connection(x, 0, nn, 0)
	f.add_connection(y, 0, nn, 1)
	f.add_connection(z, 0, nn, 2)
	var rr := _const(f, MASK_SAMPLE_R, pos + Vector2(-160, 120))
	var hm := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, pos)
	f.set_node_param(hm, 0, image)
	f.set_node_param(hm, 1, MASK_SAMPLE_R)
	f.set_node_param(hm, 2, 1.0)
	var sp := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, pos + Vector2(0, 60))
	f.add_connection(rr[0], rr[1], sp, 3)
	for i in 3:
		var c := _mul(f, [nn, i], rr, pos + Vector2(-80, i * 40))
		f.add_connection(c[0], c[1], hm, i)
		f.add_connection(c[0], c[1], sp, i)
	return _clamp01(f, _sub(f, [sp, 0], [hm, 0], pos + Vector2(90, 30)),
		pos + Vector2(160, 30))

static func build(body: CelestialBody, voxel_scale: float,
		profile: PlanetProfile = null, cliff_rock: bool = true,
		caves: bool = true, eroded: Image = null,
		masks: Dictionary = {}) -> VoxelGeneratorGraph:
	if profile == null:
		profile = PlanetProfile.derive(body, voxel_scale)
	var g := VoxelGeneratorGraph.new()
	var f: VoxelGraphFunction = g.get_main_function()
	_strata_soft = []
	_strata_band = []
	_last_relief = []
	_last_overhang = []

	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 80))
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 160))

	# One shared direction, reused by shape noise, climate and ore fields.
	# Sampling on direction rather than world position is what keeps every
	# field seamless around the sphere - no pole pinch, no meridian tear.
	var norm := f.create_node(VoxelGraphFunction.NODE_NORMALIZE_3D, Vector2(150, 300))
	f.add_connection(x, 0, norm, 0)
	f.add_connection(y, 0, norm, 1)
	f.add_connection(z, 0, norm, 2)

	# The height field is built here rather than inside _build_shape because
	# cliff detection has to difference the SAME field, and rebuilding it from a
	# second call would silently diverge the moment either copy was edited.
	var ridge: Array = []
	var sdf: Array
	if eroded != null:
		sdf = _build_eroded_shape(f, body, x, y, z, norm, profile, eroded, masks)
	elif body.heightmap != null:
		sdf = _build_baked_shape(f, body, x, y, z, voxel_scale)
	else:
		var height := _build_height_offset(f, body, norm, profile, 0.0)
		sdf = _build_sphere_sdf(f, body, x, y, z, height)
		# The mountain term the height field already built, reused rather than
		# rebuilt - the mask differences against this exact node.
		ridge = _last_ridge
	if sdf.is_empty():
		return null

	# the ground before anything is hollowed out: materials measure depth from this, so cave and tube walls are the
	# rock at that depth (bedrock, strata) rather than topsoil wrapped around every hole
	var ground_sdf := sdf
	if caves:
		sdf = _carve_caves(f, body, x, y, z, sdf, profile)
	sdf = _carve_lava_tubes(f, body, x, y, z, norm, profile, sdf, masks)

	var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(1100, 80))
	f.add_connection(sdf[0], sdf[1], out, 0)

	# Cliff rock needs a surface gradient, which only the procedural path has.
	var cliff: Array = []
	if cliff_rock and not ridge.is_empty():
		cliff = _build_slope_mask(f, body, x, y, z, norm, profile, ridge)

	_build_materials(f, body, norm, ground_sdf, profile, cliff, x, y, z, masks, eroded)

	var result: Dictionary = g.compile()
	if not result.get("success", false):
		push_error("PlanetGraphGenerator: compile failed: %s" % str(result))
		TerrainLog.write("graph", "COMPILE FAILED: %s" % str(result))
		return null
	TerrainLog.write("graph", "compiled ok  nodes=%d  cliff_rock=%s  caves=%s" % [
		f.get_node_ids().size(), cliff_rock, caves])
	return g

# --- small graph helpers -----------------------------------------------------

static func _const(f: VoxelGraphFunction, v: float, pos: Vector2) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_CONSTANT, pos)
	f.set_node_param(n, 0, v)
	return [n, 0]

static func _bin(f: VoxelGraphFunction, type_id: int, a: Array, b: Array, pos: Vector2) -> Array:
	var n := f.create_node(type_id, pos)
	f.add_connection(a[0], a[1], n, 0)
	f.add_connection(b[0], b[1], n, 1)
	return [n, 0]

static func _mul(f: VoxelGraphFunction, a: Array, b: Array, pos: Vector2) -> Array:
	return _bin(f, VoxelGraphFunction.NODE_MULTIPLY, a, b, pos)

static func _div(f: VoxelGraphFunction, a: Array, b: Array, pos: Vector2) -> Array:
	return _bin(f, VoxelGraphFunction.NODE_DIVIDE, a, b, pos)

static func _sub(f: VoxelGraphFunction, a: Array, b: Array, pos: Vector2) -> Array:
	return _bin(f, VoxelGraphFunction.NODE_SUBTRACT, a, b, pos)

static func _add(f: VoxelGraphFunction, a: Array, b: Array, pos: Vector2) -> Array:
	return _bin(f, VoxelGraphFunction.NODE_ADD, a, b, pos)

static func _smoothstep(f: VoxelGraphFunction, v: Array, e0: float, e1: float, pos: Vector2) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, pos)
	f.set_node_param(n, 0, e0)
	f.set_node_param(n, 1, e1)
	f.add_connection(v[0], v[1], n, 0)
	return [n, 0]

## Quantises `v` to the nearest multiple of `step` (probed empirically
## 2026-09-11: `floor(v/step + 0.5) * step`, i.e. round-to-nearest-multiple,
## not floor-to-multiple). This is the mesa/terrace and facet primitive - fed
## into a height field, the quantisation itself becomes a near-vertical wall
## in the resulting SDF wherever two neighbouring samples land on different
## steps, with no separate cliff construction needed.
static func _stepify(f: VoxelGraphFunction, v: Array, step: Array, pos: Vector2) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_STEPIFY, pos)
	f.add_connection(v[0], v[1], n, 0)
	f.add_connection(step[0], step[1], n, 1)
	return [n, 0]

## Lerp between two graph values by a COMPILE-TIME constant `t`. Used instead
## of `NODE_MIX` because this file already has `_add`/`_mul`/`_sub` covered and
## verifying a third node's port order was not worth it for a two-multiply-and-
## an-add.
static func _lerp_const(f: VoxelGraphFunction, a: Array, b: Array, t: float, pos: Vector2) -> Array:
	var at := _mul(f, a, _const(f, 1.0 - t, pos + Vector2(-60, 40)), pos + Vector2(-20, 20))
	var bt := _mul(f, b, _const(f, t, pos + Vector2(-60, 80)), pos + Vector2(-20, 60))
	return _add(f, at, bt, pos)

## Lerp between two graph values by a graph VALUE `t` (0..1, not necessarily
## constant) - same shape as `_lerp_const` but for a gate field like `mesa_gate`
## that varies per voxel.
static func _lerp_field(f: VoxelGraphFunction, a: Array, b: Array, t: Array, pos: Vector2) -> Array:
	var inv_t := _sub(f, _const(f, 1.0, pos + Vector2(-140, 20)), t, pos + Vector2(-100, 20))
	var at := _mul(f, a, inv_t, pos + Vector2(-20, 20))
	var bt := _mul(f, b, t, pos + Vector2(-20, 60))
	return _add(f, at, bt, pos)

static func _clamp01(f: VoxelGraphFunction, v: Array, pos: Vector2) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_CLAMP, pos)
	f.add_connection(v[0], v[1], n, 0)
	var lo := _const(f, 0.0, pos + Vector2(-90, 40))
	var hi := _const(f, 1.0, pos + Vector2(-90, 80))
	f.add_connection(lo[0], lo[1], n, 1)
	f.add_connection(hi[0], hi[1], n, 2)
	return [n, 0]

## Noise output is -1..1; most of this file wants 0..1.
static func _to01(f: VoxelGraphFunction, v: Array, pos: Vector2) -> Array:
	return _mul(f, _add(f, v, _const(f, 1.0, pos + Vector2(-60, 40)), pos),
		_const(f, 0.5, pos + Vector2(-60, 80)), pos + Vector2(60, 0))

## Soft membership of `v` in [lo, hi]: 1 inside, falling to 0 across `blend`
## at each edge. This is what replaces the nearest-biome and rarest-first-ore
## branches - each material computes its own membership independently.
static func _window(f: VoxelGraphFunction, v: Array, lo: float, hi: float,
		blend: float, pos: Vector2) -> Array:
	var rise := _smoothstep(f, v, lo - blend, lo + blend, pos)
	var fall := _smoothstep(f, v, hi - blend, hi + blend, pos + Vector2(0, 60))
	var inv := _sub(f, _const(f, 1.0, pos + Vector2(60, 100)), fall, pos + Vector2(140, 60))
	return _mul(f, rise, inv, pos + Vector2(220, 30))

## FRACTAL_NONE means "single octave, engine default" - every existing call
## site that does not care about spectral shape keeps behaving exactly as
## before. Everything else (octaves/gain/lacunarity/weighted_strength/warp) is
## left at the ZN_FastNoiseLite default unless a caller opts in, because the
## default was the entire bug: 2026-09-11 diagnosis found the four height
## bands used ONLY seed+period and left every octave/warp knob untouched, so
## every band was single-frequency noise with no internal structure - which is
## why the terrain read as regular bumps rather than eroded landforms at any
## one scale.
static func _zn_noise(seed_value: int, frequency: float,
		fractal_type: int = -1, octaves: int = 1, lacunarity: float = 2.0,
		gain: float = 0.5, weighted_strength: float = 0.0,
		warp: Resource = null) -> Resource:
	var n: Resource = ClassDB.instantiate("ZN_FastNoiseLite")
	if n == null:
		return null
	n.set("seed", seed_value)
	n.set("period", 1.0 / maxf(frequency, 0.000001))
	if fractal_type >= 0:
		n.set("fractal_type", fractal_type)
		n.set("fractal_octaves", octaves)
		n.set("fractal_lacunarity", lacunarity)
		n.set("fractal_gain", gain)
		n.set("fractal_weighted_strength", weighted_strength)
	if warp != null:
		n.set("warp_noise", warp)
	return n

## Domain-warp gradient for one noise field. Warping sample POSITIONS (not
## blending an extra noise layer) is what makes coastlines and ridgelines
## meander instead of forming symmetric blobs - the single highest-value
## technique tried this session for "stop looking like noise".
##
## Amplitude is a FRACTION OF THE FIELD'S OWN WAVELENGTH (period), not an
## absolute constant, so it stays correct at any planet radius: a value tuned
## in metres would be a repeat of the exact bug this file's noise frequencies
## were built to avoid. 0.18 sits in the 10-30% band the task guidance called
## out as the safe range before warping turns to mush - verified visually
## (see terrain-generator.md, "Built 2026-09-11 - noise overhaul").
const WARP_AMPLITUDE_FRACTION := 0.18

## `amplitude_fraction` overrides WARP_AMPLITUDE_FRACTION for callers that need
## a stronger displacement - see the rock band, where the default is not enough
## to break the ridge lattice.
static func _zn_warp(seed_value: int, frequency: float, octaves: int = 2,
		amplitude_fraction: float = WARP_AMPLITUDE_FRACTION) -> Resource:
	var g: Resource = ClassDB.instantiate("ZN_FastNoiseLiteGradient")
	if g == null:
		return null
	var period := 1.0 / maxf(frequency, 0.000001)
	g.set("seed", seed_value)
	g.set("period", period)
	g.set("amplitude", period * amplitude_fraction)
	if octaves > 1:
		g.set("fractal_type", 1) # FRACTAL_DOMAIN_WARP_PROGRESSIVE
		g.set("fractal_octaves", octaves)
	return g

static func _noise_on(f: VoxelGraphFunction, norm: int, seed_value: int,
		frequency: float, pos: Vector2, fractal_type: int = -1, octaves: int = 1,
		lacunarity: float = 2.0, gain: float = 0.5, weighted_strength: float = 0.0,
		warp: Resource = null) -> Array:
	var noise := _zn_noise(seed_value, frequency, fractal_type, octaves,
		lacunarity, gain, weighted_strength, warp)
	if noise == null:
		return []
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, pos)
	f.set_node_param(n, 0, noise)
	f.add_connection(norm, 0, n, 0)
	f.add_connection(norm, 1, n, 1)
	f.add_connection(norm, 2, n, 2)
	return [n, 0]

## A field of solid spheres on a jittered 3D grid. Output is a STEP: ~0.99
## inside a sphere, 0 outside, no falloff between (probed 2026-09-12, see the
## crater note near CRATER_JITTER). Fine for "is this voxel inside a deposit";
## useless for anything that needs a profile, like a crater bowl.
##
## `cell_size` and `radius` are in the SAME units as the position fed in - for
## direction sampling that means unit-sphere-direction units, exactly what
## `profile.crater_freq`'s period already is (same convention `_noise_on` uses
## for `profile.continent_freq` etc).
## Spots sampled on WORLD POSITION rather than on the surface direction.
##
## The direction-sampled variant below is wrong for anything that lives in the
## volume. Spots3D scatters its centres through a 3D cell, so sampling it on the
## unit direction only registers a spot when its centre happens to land within
## `radius` of the unit sphere itself - with a radius of 0.011 against a cell of
## 0.07, almost every spot missed the shell and the field was blank. Measured:
## zero ore voxels in a 1 km cube, with only bedrock and stone present.
##
## On world position the cells are real metres and a deposit is a real lump in
## the ground, which is also what Space Engineers deposits actually are.
static func _spots3d_xyz(f: VoxelGraphFunction, x: int, y: int, z: int,
		seed_value: int, cell_size: float, jitter: float, radius: float,
		pos: Vector2) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_SPOTS_3D, pos)
	f.set_node_param(n, 0, seed_value)
	f.set_node_param(n, 1, cell_size)
	f.set_node_param(n, 2, jitter)
	f.add_connection(x, 0, n, 0)
	f.add_connection(y, 0, n, 1)
	f.add_connection(z, 0, n, 2)
	var r := _const(f, radius, pos + Vector2(-90, 60))
	f.add_connection(r[0], r[1], n, 3)
	return [n, 0]

static func _spots3d(f: VoxelGraphFunction, norm: int, seed_value: int,
		cell_size: float, jitter: float, radius: float, pos: Vector2) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_SPOTS_3D, pos)
	f.set_node_param(n, 0, seed_value)
	f.set_node_param(n, 1, cell_size)
	f.set_node_param(n, 2, jitter)
	f.add_connection(norm, 0, n, 0)
	f.add_connection(norm, 1, n, 1)
	f.add_connection(norm, 2, n, 2)
	var r := _const(f, radius, pos + Vector2(-90, 60))
	f.add_connection(r[0], r[1], n, 3)
	return [n, 0]

static func _abs(f: VoxelGraphFunction, v: Array, pos: Vector2) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_ABS, pos)
	f.add_connection(v[0], v[1], n, 0)
	return [n, 0]

static func _curve(f: VoxelGraphFunction, v: Array, curve: Curve, pos: Vector2) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_CURVE, pos)
	f.set_node_param(n, 0, curve)
	f.add_connection(v[0], v[1], n, 0)
	return [n, 0]

## Drives weights below `WEIGHT_CUTOFF` to exactly zero, and rescales what
## survives back up to full range.
##
## This is what stops a material from holding a blend slot it does not deserve.
## TEXTURES_MIXEL4_S4 keeps the four strongest weights per voxel and their
## INDICES are `flat` - they cannot be interpolated, so every change in the
## surviving set is a hard seam, and at LOD the index channel is downsampled
## nearest-neighbour, turning each seam into a block.
##
## Measured before this: cliff rock was present in 76% of surface samples at a
## weight far too low to be seen as cliff, but high enough to occupy a slot
## everywhere. The set changed every ~11 m, which at LOD 2 is a hard edge every
## few vertices - the blocky pale patches and the bright slope-following lines
## were both this.
static func _cutoff(f: VoxelGraphFunction, w: Array, pos: Vector2) -> Array:
	return _smoothstep(f, w, WEIGHT_CUTOFF, WEIGHT_CUTOFF + WEIGHT_CUTOFF_FADE, pos)

static func _weight_out(f: VoxelGraphFunction, layer: int, w: Array, pos: Vector2) -> void:
	var n := f.create_node(VoxelGraphFunction.NODE_OUTPUT_WEIGHT, pos)
	f.set_node_param(n, 0, clampi(layer, 0, 15))
	f.add_connection(w[0], w[1], n, 0)

# --- shape -------------------------------------------------------------------

## Shape from a GPU-ERODED heightmap, with noise only as surface detail on top.
##
## This is the arrangement VRAGE3 uses and it is the reason the noise bands are
## no longer the landform. An eroded map has CAUSES in it - connected valleys,
## sharpened divides, sediment where water slowed - and none of those can be
## produced by summing noise, however many bands. The previous generator stacked
## eight and still read as a smooth ocean from altitude, because that is what
## band-limited noise looks like at every scale.
##
## What survives from the old chain is the ROCK band: metre-scale relief the
## heightmap has no resolution to carry (at 2048x1024 one texel is ~24 m on an
## 8 km planet). The continent, peaks, belt and erosion-parameter fields are all
## gone - the map does their job properly now.
static func _build_eroded_shape(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, norm: int, profile: PlanetProfile,
		eroded: Image, masks: Dictionary = {}) -> Array:
	var relief := profile.relief_voxels
	var n := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(300, 80))
	f.set_node_param(n, 0, eroded)
	# The map is 0..1, so the sphere radius is pulled down by the sea-level
	# fraction to centre terrain on the nominal surface rather than sitting
	# entirely above it.
	f.set_node_param(n, 1, body.radius - profile.sea_level * relief)
	f.set_node_param(n, 2, relief)
	f.add_connection(x, 0, n, 0)
	f.add_connection(y, 0, n, 1)
	f.add_connection(z, 0, n, 2)
	var sdf: Array = [n, 0]

	# --- ground character -------------------------------------------------
	#
	# Two questions decide everything below: how steep is the landform here, and
	# how deeply is it buried in its own debris. Steep and scoured is broken
	# rock; gentle and mantled is dust. Both the rock band and the dune band read
	# the same pair, so they cannot disagree about what kind of ground they are
	# on - and the materials read it too.
	var slope01 := _build_landform_slope(f, body, x, y, z, profile, eroded,
		masks, Vector2(200, 700))
	var dust := _dust_field(f, body, x, y, z, masks, Vector2(200, 1400))
	var rocky := _rockiness(f, slope01, dust, Vector2(560, 1000))
	_last_slope = slope01
	_last_rocky = rocky

	var rock_relief := _build_rock_relief(f, body, norm, profile, rocky, slope01, Vector2(400, 1100))
	_last_relief = rock_relief
	sdf = _sub(f, sdf, rock_relief, Vector2(1100, 1200))
	sdf = _sub(f, sdf, _build_ledges(f, body, x, y, z, norm, profile, slope01, Vector2(400, 2300)),
		Vector2(1100, 2300))

	# --- meadows: broad swells, and craters as the scattered detail ----------
	#
	# Flat ground carried only the erosion map's texel-scale wobble, and an even
	# field of small waves with nothing larger to sit in reads as water. The first
	# fix - a 130 m fbm "dune" band - only made broader waves and a faint regular
	# diagonal banding, because more rolling noise is still rolling noise. A moon
	# plain's structure is two things: very broad, very gentle undulation, and
	# craters of every size as the detail.
	#
	# Both gated to `meadow`, the exact complement of the rock gate, so the flats
	# and the rock faces cannot disagree about which kind of ground they are.
	var meadow := _sub(f, _const(f, 1.0, Vector2(700, 1760)), rocky, Vector2(760, 1780))

	# Swells. OpenSimplex2S rather than the OpenSimplex2 default, and warped:
	# ZN_FastNoiseLite defaults to OpenSimplex2 with NO 3D rotation (probed in
	# scripts/dev/spots_probe.gd), which has lattice-aligned directional
	# artifacts - the likely source of the dune band's regular diagonal banding.
	# Not changed in `_zn_noise` itself, because every band including the
	# approved rock goes through it.
	#
	# Frequency and amplitude derive from the rock band's own numbers so they
	# carry its voxel-scale conversion; the generator cannot read
	# Planet.VOXEL_SCALE (circular preload, see the top of this file).
	var swell_freq: float = maxf(profile.rock_freq
		* (PlanetProfile.ROCK_FEATURE_M / SWELL_FEATURE_M), 0.5)
	var swell_amp: float = profile.rock_amplitude 		* (SWELL_AMPLITUDE_M / PlanetProfile.ROCK_AMPLITUDE_M) * SWELL_AMPLITUDE_MULT
	var swell_noise := _zn_noise(body.seed + 27, swell_freq, FRACTAL_FBM, 3, 2.13, 0.5,
		0.0, _zn_warp(body.seed + 28, swell_freq * 0.5, 2, SWELL_WARP_FRACTION))
	if swell_noise != null:
		swell_noise.set("noise_type", 1) # TYPE_OPEN_SIMPLEX_2S
		var sn := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, Vector2(400, 1800))
		f.set_node_param(sn, 0, swell_noise)
		f.add_connection(norm, 0, sn, 0)
		f.add_connection(norm, 1, sn, 1)
		f.add_connection(norm, 2, sn, 2)
		var swell := _mul(f,
			_mul(f, [sn, 0], _const(f, swell_amp, Vector2(700, 1860)), Vector2(820, 1800)),
			meadow, Vector2(900, 1800))
		sdf = _sub(f, sdf, swell, Vector2(1040, 1800))

	sdf = _sub(f, sdf, _build_craters(f, body, norm, profile, meadow,
		Vector2(400, 1950)), Vector2(1040, 1950))

	sdf = _carve_overhangs(f, body, x, y, z, norm, profile, sdf, masks, rocky)
	return sdf

## Everything the surface carries below the erosion map's resolution, as a
## height to SUBTRACT from the SDF.
##
## Measured before this existed: with the single rock band switched off, relief
## detrended over 4 m was 0.09 m rms - the heightmap is glass-smooth at every
## scale a standing player can see, because one texel is ~12 m of arc. So this
## function is the ONLY source of rock-scale shape on the planet, and what it
## does decides whether the ground reads as stone or as a sheet.
##
## THREE bands, not one, and that is the point. A single ridged band produces a
## carpet of identical lumps at one wavelength, and measurement showed neither
## amplitude nor faceting changes that: 2.5x amplitude gave deeper lumps of the
## same shape, and blending in a quantised copy at the band's own step barely
## moved the numbers at all. Real broken ground has structure at several sizes at
## once - a ledge, the blocks on it, the grain of those blocks.
##
## Each band is gated differently, which is what keeps them from switching on
## together and becoming one thicker carpet:
##   crag  - outcrops, in CLUMPS, only where the ground is properly rocky
##   rock  - the metre-scale break-up, wherever the ground is rocky at all
##   grain - a trace everywhere, so dust plains are not mirrors
static func _build_rock_relief(f: VoxelGraphFunction, body: CelestialBody,
		norm: int, profile: PlanetProfile, rocky: Array, slope01: Array,
		pos: Vector2) -> Array:
	if profile.rock_amplitude <= 0.001:
		return _const(f, 0.0, pos)
	# Both conversions come from the rock band's own numbers, so the voxel scale
	# is carried rather than repeated - the generator cannot read Planet.VOXEL_SCALE
	# (see the circular-preload note at the top of this file).
	var freq_per_m: float = profile.rock_freq * PlanetProfile.ROCK_FEATURE_M
	var vox_per_m: float = profile.rock_amplitude / PlanetProfile.ROCK_AMPLITUDE_M
	var total: Array = []
	var row := pos.y

	# --- crags: outcrops and ledges -----------------------------------------
	#
	# Faceted hard and at a coarse step, because this is the band that has to
	# produce actual edges. Quantising a band of THIS wavelength puts a bench
	# across an outcrop; quantising the fine band only roughens it.
	#
	# Clumped by a patch field an order of magnitude coarser than the crags
	# themselves, so outcrops stand in groups with bare ground between them. A
	# uniform amount of anything, high or low, is the mistake this project has
	# now made three times - the rock carpet, the boulder carpet, and the empty
	# boulder field.
	# No domain warp, unlike the rock band. A warp is what stops single-frequency
	# ridged noise laying down parallel creases, but the clump gate below already
	# breaks this band into separate outcrops, and a second warped field measured
	# as the most expensive thing in the graph.
	var crag_n := _noise_on(f, norm, body.seed + 41, freq_per_m / CRAG_FEATURE_M,
		Vector2(pos.x, row), FRACTAL_RIDGED, 2, 2.11, 0.55, 0.0)
	var patch := _noise_on(f, norm, body.seed + 43, freq_per_m / CRAG_PATCH_M,
		Vector2(pos.x, row + 200), FRACTAL_FBM, 2, 2.0, 0.5, 0.0)
	if not crag_n.is_empty() and not patch.is_empty():
		var clump := _smoothstep(f, _to01(f, patch, Vector2(pos.x + 200, row + 200)),
			CRAG_PATCH_START, CRAG_PATCH_FULL, Vector2(pos.x + 300, row + 200))
		var faceted := _lerp_const(f, crag_n,
			_stepify(f, crag_n, _const(f, 1.0 / CRAG_FACET_STEPS, Vector2(pos.x + 200, row + 60)),
				Vector2(pos.x + 260, row + 20)),
			CRAG_FACET_BLEND, Vector2(pos.x + 340, row + 20))
		var gate := _mul(f, clump, _smoothstep(f, rocky, CRAG_ROCKY_START, CRAG_ROCKY_FULL,
			Vector2(pos.x + 300, row + 300)), Vector2(pos.x + 400, row + 250))
		# And the ground must actually be STEEP. Rockiness alone also rises on
		# flat scoured ground, and measured on a 6 degree meadow the crag band
		# was 97% of all relief below 4 m (0.73 of 0.75 m rms) - outcrops
		# standing on exactly the ground that was supposed to be dust. Steep
		# faces have slope01 at 1, so the rocky look there does not change.
		if not slope01.is_empty():
			gate = _mul(f, gate, _smoothstep(f, slope01, CRAG_SLOPE_START,
				CRAG_SLOPE_FULL, Vector2(pos.x + 300, row + 360)),
				Vector2(pos.x + 460, row + 300))
		total = _mul(f,
			_mul(f, faceted, _const(f, CRAG_AMPLITUDE_M * CRAG_AMPLITUDE_MULT * vox_per_m,
				Vector2(pos.x + 400, row + 60)), Vector2(pos.x + 460, row + 20)),
			gate, Vector2(pos.x + 540, row + 20))
	row += 400.0

	# --- rock: the metre-scale break-up -------------------------------------
	#
	# Domain warped. Ridged noise creases along its own lattice, so at one
	# dominant frequency it lays parallel ridge lines, and on gentle ground -
	# where no landform breaks them up - those read as ripples. A warp only
	# breaks the alignment if it displaces by something near the feature
	# wavelength; at the 0.18 default the creases still lined up.
	var rock_n := _noise_on(f, norm, body.seed + 18, profile.rock_freq,
		Vector2(pos.x, row), FRACTAL_RIDGED, 4, 2.17, 0.5, 0.0,
		_zn_warp(body.seed + 19, profile.rock_freq * 0.45, 2, 0.55))
	if not rock_n.is_empty():
		_last_ridge = rock_n
		var steps: float = ROCK_FACET_STEPS_OVERRIDE if ROCK_FACET_STEPS_OVERRIDE > 0.0 else ROCK_FACET_STEPS
		var blend: float = ROCK_FACET_BLEND_OVERRIDE if ROCK_FACET_BLEND_OVERRIDE >= 0.0 else ROCK_FACET_BLEND
		var faceted := _lerp_const(f, rock_n,
			_stepify(f, rock_n, _const(f, 1.0 / maxf(steps, 0.5), Vector2(pos.x + 200, row + 60)),
				Vector2(pos.x + 260, row + 20)),
			blend, Vector2(pos.x + 340, row + 20))
		# Rockiness, times a slope ramp with a floor.
		#
		# Rockiness alone did not tell flats from cliffs for this band: measured,
		# it carried ~0.16 m rms below 4 m on a 6 degree meadow and about the same
		# on a 54 degree face, because scoured flat ground reads as partly rocky.
		# On the meadow that was the whole eye-level "carpet" (0.17 -> 0.05 m with
		# the band off; grain off changed nothing). The floor keeps a trace of
		# break-up on flats so a plain is not polished.
		var gate: Array = _mul(f, rocky,
			_add(f, _const(f, ROCK_BAND_FLAT_FLOOR, Vector2(pos.x + 200, row + 160)),
				_mul(f, _const(f, 1.0 - ROCK_BAND_FLAT_FLOOR, Vector2(pos.x + 200, row + 200)),
					_smoothstep(f, slope01, CRAG_SLOPE_START, CRAG_SLOPE_FULL,
						Vector2(pos.x + 200, row + 240)),
					Vector2(pos.x + 260, row + 220)),
				Vector2(pos.x + 300, row + 180)),
			Vector2(pos.x + 340, row + 140))
		if ROCK_FORCE_GATE >= 0.0:
			gate = _const(f, ROCK_FORCE_GATE, Vector2(pos.x + 300, row + 120))
		var band := _mul(f,
			_mul(f, faceted,
				_const(f, profile.rock_amplitude * ROCK_AMPLITUDE_MULT,
					Vector2(pos.x + 400, row + 60)), Vector2(pos.x + 460, row + 20)),
			gate, Vector2(pos.x + 540, row + 20))
		total = band if total.is_empty() else _add(f, total, band, Vector2(pos.x + 620, row))
	row += 400.0

	# --- grain: never a mirror ----------------------------------------------
	#
	# Present on dust as well as rock, at a fraction of the strength. A regolith
	# plain is smooth, not polished, and what makes it read as ground rather than
	# as a surface of water is exactly this: scattered detail with no pattern to
	# it. fbm rather than ridged, because grain has no creases.
	#
	# At 2.6 m features on a 1 m voxel this is near the mesher's resolution and
	# deliberately so - it is the finest shape the terrain can carry at all.
	var grain_n := _noise_on(f, norm, body.seed + 45, freq_per_m / GRAIN_FEATURE_M,
		Vector2(pos.x, row), FRACTAL_FBM, 2, 2.19, 0.5, 0.0)
	if not grain_n.is_empty():
		var gate := _add(f,
			_mul(f, rocky, _const(f, 1.0 - GRAIN_DUST_SHARE, Vector2(pos.x + 200, row + 120)),
				Vector2(pos.x + 260, row + 100)),
			_const(f, GRAIN_DUST_SHARE, Vector2(pos.x + 200, row + 160)),
			Vector2(pos.x + 340, row + 100))
		var band := _mul(f,
			_mul(f, grain_n, _const(f, GRAIN_AMPLITUDE_M * GRAIN_AMPLITUDE_MULT * vox_per_m,
				Vector2(pos.x + 400, row + 60)), Vector2(pos.x + 460, row + 20)),
			gate, Vector2(pos.x + 540, row + 20))
		total = band if total.is_empty() else _add(f, total, band, Vector2(pos.x + 620, row))

	return total if not total.is_empty() else _const(f, 0.0, pos)

## Cellular noise returning DISTANCE to the nearest feature point, sampled on
## the shared direction like every other surface field.
##
## Direction rather than world position so a crater is the same bowl from the
## top of a rise to the bottom of a swale: the isosurface sits at different radii
## across the landscape, and a field that changed along the radial axis would
## distort the SDF rather than offset a height.
static func _cellular_on(f: VoxelGraphFunction, norm: int, seed_value: int,
		frequency: float, jitter: float, pos: Vector2) -> Array:
	var noise: Resource = ClassDB.instantiate("ZN_FastNoiseLite")
	if noise == null:
		return []
	noise.set("seed", seed_value)
	noise.set("period", 1.0 / maxf(frequency, 0.000001))
	noise.set("noise_type", 2)                 # TYPE_CELLULAR
	noise.set("fractal_type", 0)               # FRACTAL_NONE
	noise.set("cellular_distance_function", 0) # EUCLIDEAN
	noise.set("cellular_return_type", 1)       # RETURN_DISTANCE
	noise.set("cellular_jitter", jitter)
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, pos)
	f.set_node_param(n, 0, noise)
	f.add_connection(norm, 0, n, 0)
	f.add_connection(norm, 1, n, 1)
	f.add_connection(norm, 2, n, 2)
	return [n, 0]

## Crater relief, as a height to SUBTRACT from the SDF (negative in the bowl).
##
## Every piece of the profile is a smoothstep, and smoothstep has zero slope at
## both edges. That is the whole design, because the old craters failed on
## creases rather than on shape:
##   - Euclidean distance is a cone at the centre. `1 - smoothstep(0, 1, t)`
##     is flat there, so the floor is a bowl, not a point.
##   - The rim is `smoothstep(start, 1) - smoothstep(1, end)`: rises and falls
##     with no kink at either end or at the crest.
##   - Beyond CRATER_RIM_END the profile is exactly zero, so the distance
##     field's own creases at Voronoi boundaries sit under flat ground.
## A spline with a steep knee on this field would draw one ring per knee, which
## is the recorded failure; C1 all the way through draws none.
##
## `meadow` gates it: craters belong on dust-mantled flats, and a crater bitten
## into a cliff face reads as a mistake.
static func _build_craters(f: VoxelGraphFunction, body: CelestialBody,
		norm: int, profile: PlanetProfile, meadow: Array, pos: Vector2) -> Array:
	if profile.rock_amplitude <= 0.001:
		return _const(f, 0.0, pos)
	var freq_per_m: float = profile.rock_freq * PlanetProfile.ROCK_FEATURE_M
	var vox_per_m: float = profile.rock_amplitude / PlanetProfile.ROCK_AMPLITUDE_M
	var total: Array = []
	var row := pos.y
	for size in CRATER_SIZES:
		var dist := _cellular_on(f, norm, body.seed + int(size[3]),
			freq_per_m / float(size[0]), CRATER_CELL_JITTER, Vector2(pos.x, row))
		if dist.is_empty():
			continue
		var t := _mul(f,
			_add(f, dist, _const(f, 1.0, Vector2(pos.x + 120, row + 40)),
				Vector2(pos.x + 180, row)),
			_const(f, 1.0 / CRATER_RADIUS_CELLS, Vector2(pos.x + 180, row + 60)),
			Vector2(pos.x + 240, row))
		var depth: float = float(size[1]) * vox_per_m * CRATER_AMPLITUDE_MULT
		var rim_h: float = float(size[2]) * vox_per_m * CRATER_AMPLITUDE_MULT
		var bowl := _mul(f,
			_sub(f, _const(f, 1.0, Vector2(pos.x + 300, row + 40)),
				_smoothstep(f, t, 0.0, 1.0, Vector2(pos.x + 300, row)),
				Vector2(pos.x + 360, row)),
			_const(f, -depth, Vector2(pos.x + 360, row + 60)),
			Vector2(pos.x + 420, row))
		var rim := _mul(f,
			_sub(f,
				_smoothstep(f, t, CRATER_RIM_START, 1.0, Vector2(pos.x + 300, row + 120)),
				_smoothstep(f, t, 1.0, CRATER_RIM_END, Vector2(pos.x + 300, row + 180)),
				Vector2(pos.x + 360, row + 150)),
			_const(f, rim_h, Vector2(pos.x + 360, row + 210)),
			Vector2(pos.x + 420, row + 150))
		var one := _add(f, bowl, rim, Vector2(pos.x + 480, row + 60))
		total = one if total.is_empty() else _add(f, total, one, Vector2(pos.x + 540, row))
		row += 300.0
	if total.is_empty():
		return _const(f, 0.0, pos)
	if meadow.is_empty():
		return total
	return _mul(f, total, meadow, Vector2(pos.x + 600, pos.y))

## Landform steepness as a 0..1 mask, taken from the eroded heightmap itself.
##
## `_build_slope_mask` differences the MOUNTAIN NOISE term, which only exists on
## the procedural path. On the eroded path there is no ridge node to difference,
## so it was never called and `cliff` came back empty - meaning slope drove
## NOTHING on the planet the game actually ships: not the cliff material, not the
## rock band, not the scatter. Everything was decided by the deposition mask
## alone, whose median is 1.00 here.
##
## Sampled from `height_lo`, the mask-resolution copy of the same landform, NOT
## from the full-resolution map. Four samples of the 10216x5108 map cost more
## than every noise band in the graph combined - measured 3.0 -> 8.8 us/voxel,
## which the game showed as 21 fps while terrain streamed, because 210 MB of
## image cannot stay in cache. A gradient does not need that resolution: slope
## over 12 m of arc is rock detail, and this mask answers a landform question.
##
## The gradient is the SUM OF SQUARED differences along all three world axes, and
## that is exact rather than a proxy: for a field that depends only on direction,
## the three axis derivatives square-sum to the tangential gradient magnitude
## wherever the point sits on the sphere. Differencing along two axes - what the
## noise version does, and openly calls a proxy - degenerates near those axes, so
## the mask would vary with global orientation and paint rock on one hemisphere.
##
## Returns a mask compared in SQUARED units, so no square root is needed: the
## smoothstep edges are squared once at build time instead.
static func _build_landform_slope(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, profile: PlanetProfile, eroded: Image,
		masks: Dictionary, pos: Vector2) -> Array:
	# Preferred: the baked slope mask, one sample. Measured at full resolution
	# and max-pooled in slope.glsl, so a narrow cliff reads as the cliff it is.
	var baked: Image = masks.get("slope")
	if baked != null:
		var s := _sample_mask(f, x, y, z, baked, body.radius, pos)
		if not s.is_empty():
			return _smoothstep(f, s, SLOPE_START_DEG / 90.0, SLOPE_FULL_DEG / 90.0,
				pos + Vector2(200, 0))
	# Fallback for a bake with no slope mask: difference the full map. Correct
	# but expensive (see erosion_cache.gd), so only reached when it is missing.
	if eroded == null:
		return []
	var h0 := _sample_mask(f, x, y, z, eroded, body.radius, pos)
	if h0.is_empty():
		return []
	# Offset in VOXELS. The generator works in the terrain's own grid, and
	# SLOPE_SAMPLE_M is metres, so this assumes the 1 m voxel the whole project
	# is built on - the same assumption profile.rock_amplitude already carries.
	var eps := SLOPE_SAMPLE_M
	var sum: Array = []
	var sources := [x, y, z]
	for axis in 3:
		var shifted := _add(f, [sources[axis], 0],
			_const(f, eps, pos + Vector2(-60, 120 + axis * 90)),
			pos + Vector2(20, 100 + axis * 90))
		var args := [x, y, z]
		args[axis] = shifted[0]
		var h := _sample_mask(f, args[0], args[1], args[2], eroded, body.radius,
			pos + Vector2(120, 100 + axis * 90))
		if h.is_empty():
			return []
		var d := _sub(f, h, h0, pos + Vector2(300, 100 + axis * 90))
		var d2 := _mul(f, d, d, pos + Vector2(360, 100 + axis * 90))
		sum = d2 if sum.is_empty() else _add(f, sum, d2, pos + Vector2(420, 100 + axis * 90))

	# Map units are 0..1 over the body's whole relief, so scale to voxels of
	# height per voxel of arc before comparing against a gradient threshold.
	var k: float = profile.relief_voxels / eps
	var grad2 := _mul(f, sum, _const(f, k * k, pos + Vector2(480, 160)),
		pos + Vector2(540, 120))
	return _smoothstep(f, grad2, SLOPE_START * SLOPE_START,
		SLOPE_FULL * SLOPE_FULL, pos + Vector2(620, 120))

## How much this ground is broken rock rather than dust, 0..1.
##
## Steepness dominates, because material does not stay on a steep face whatever
## the sediment record says. Scouring is the second vote: ground the debris never
## reached is bare even where it is flat, which is what puts rock on a wind-swept
## divide and dust in the basin below it.
static func _rockiness(f: VoxelGraphFunction, slope01: Array, dust: Array,
		pos: Vector2) -> Array:
	var terms: Array = []
	if not slope01.is_empty():
		terms = _mul(f, slope01, _const(f, ROCKY_FROM_SLOPE, pos + Vector2(-60, 40)), pos)
	if not dust.is_empty():
		var scour := _mul(f,
			_sub(f, _const(f, 1.0, pos + Vector2(-60, 100)), dust, pos + Vector2(0, 120)),
			_const(f, ROCKY_FROM_SCOUR, pos + Vector2(-60, 160)), pos + Vector2(60, 120))
		terms = scour if terms.is_empty() else _add(f, terms, scour, pos + Vector2(120, 60))
	if terms.is_empty():
		# No map and no masks: neither signal exists, so leave the ground rocky
		# rather than silently flattening the whole planet.
		return _const(f, 1.0, pos)
	return _clamp01(f, terms, pos + Vector2(180, 60))

## How thoroughly this ground is mantled in dust, 0..1.
##
## ONE signal, shared by everything that needs to know whether it is standing on
## bare rock or on a sediment blanket - the rock-relief band and the overhang
## field both read it. Previously each had its own opinion, which is how the
## surface ended up rough in places nothing should have been rough.
##
## Dust mantling is a real process and the dominant one on an airless or arid
## world: fines settle into and drape over topography, subduing everything below
## their own depth. That is why regolith plains read as SMOOTH at metre scale
## while the rock they cover is not. Modelling it as "suppress the rock detail
## where sediment collected" is the same thing from the other side.
##
## The range is 0.02..0.22, and the narrowness is the point. Deposition has a
## median of 0.17, so the previous 0.04..0.45 mapping left typical ground at 76%
## of full rock amplitude - meadows nearly as broken as bare stone, which is
## exactly the wavy look. Mapped over the range the mask actually occupies, the
## same ground now comes out mostly dust.
static func _dust_field(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, masks: Dictionary, pos: Vector2) -> Array:
	var depo := _sample_mask(f, x, y, z, masks.get("deposition"), body.radius, pos)
	if depo.is_empty():
		return []
	return _smoothstep(f, depo, 0.02, 0.22, pos + Vector2(160, 0))

## Displaces the surface in THREE dimensions, producing undercuts.
##
## Everything above this point is a height field: one surface per direction, so
## it can make a slope vertical but never lean it back over itself. That is the
## hard ceiling on how a heightmap-first planet reads close up, and no amount of
## extra relief or finer noise gets past it - a 90 degree wall is still a wall.
##
## The fix is to add a field that varies with POSITION rather than direction. The
## isosurface then stops being single-valued along a ray, which is precisely what
## an overhang is. Caves work the same way (see _carve_caves) and are the other
## half of the same idea; this one stays near the surface instead of tunnelling.
##
## ADDED to the SDF rather than subtracted through a min/max. A signed union
## would carve discrete blobs with visibly spherical mouths; adding a smooth
## field warps the existing surface, so the result is the same rock leaning out
## rather than a hole punched in it.
##
## Gated by WEAR, so undercuts appear on scoured, bare ground and not in the
## sediment basins - overhangs are a feature of exposed rock being undermined,
## and putting them under dust fields is the same category of error as putting
## bare rock in a basin.
static func _carve_overhangs(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, norm: int, profile: PlanetProfile,
		sdf: Array, masks: Dictionary, rocky: Array = []) -> Array:
	var amount := _overhang_amount(f, body, x, y, z, norm, profile, masks, rocky)
	if amount.is_empty():
		return sdf
	return _add(f, sdf, amount, Vector2(1000, 2000))

## The overhang term alone (added to the SDF, so it moves the surface radially by exactly -amount): built before the
## strata so they can take it back out of the radius, like the rock relief. Cached per graph.
static func _overhang_amount(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, norm: int, profile: PlanetProfile,
		masks: Dictionary, rocky: Array = []) -> Array:
	if not _last_overhang.is_empty():
		return _last_overhang
	var sdf: Array = []
	# Feature size of the undercuts, in voxels. Around a player height: big
	# enough to shelter under, small enough that it reads as rock rather than
	# landform.
	var freq := 1.0 / 14.0
	var n := _noise_xyz(f, x, y, z, body.seed + 31, freq, Vector2(400, 2000))
	if n.is_empty():
		return sdf

	var gate: Array = _const(f, 1.0, Vector2(560, 2100))
	var wear: Array = _sample_mask(f, x, y, z, masks.get("wear"),
		body.radius, Vector2(400, 2140))
	if not wear.is_empty():
		# Only the scoured end of the range, and with a floor of zero: ground
		# that saw no erosion gets no undercuts at all rather than a little.
		gate = _smoothstep(f, wear, 0.35, 0.75, Vector2(560, 2140))
	# And only on ground that reads as broken rock. Rock cannot be undercut
	# through a sediment blanket, and an undercut in a flat meadow is the most
	# conspicuous place for one to look wrong. `rocky` already carries the dust
	# term, so this is one shared answer rather than a second opinion about the
	# same question.
	if not rocky.is_empty():
		gate = _mul(f, gate, rocky, Vector2(820, 2160))
	else:
		var dust := _dust_field(f, body, x, y, z, masks, Vector2(400, 2280))
		if not dust.is_empty():
			gate = _mul(f, gate,
				_sub(f, _const(f, 1.0, Vector2(680, 2260)), dust, Vector2(740, 2280)),
				Vector2(820, 2160))

	# Amplitude in voxels. Kept to a few metres: this displaces the REAL surface,
	# so an amplitude near the rock band's own feature size turns the ground into
	# floating shelves instead of undercutting it.
	var amount := _mul(f,
		_mul(f, n, _const(f, OVERHANG_VOXELS, Vector2(620, 2000)), Vector2(700, 2000)),
		gate, Vector2(800, 2020))
	_last_overhang = amount
	return amount

## Sphere SDF with the height field subtracted from it.
static func _build_sphere_sdf(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, height: Array) -> Array:
	var sph := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2(300, 80))
	f.add_connection(x, 0, sph, 0)
	f.add_connection(y, 0, sph, 1)
	f.add_connection(z, 0, sph, 2)
	# Radius is INPUT PORT 3 here, not a parameter.
	var rad := _const(f, body.radius, Vector2(150, 200))
	f.add_connection(rad[0], rad[1], sph, 3)
	if height.is_empty():
		return [sph, 0]
	# Raising the surface by d lowers the SDF by d.
	return _sub(f, [sph, 0], height, Vector2(1000, 80))

## Surface offset from the nominal radius, in voxels.
static func _build_height_offset(f: VoxelGraphFunction, body: CelestialBody,
		norm: int, profile: PlanetProfile, row_base: float) -> Array:
	var r := row_base

	# Domain warp on the continent field: the single highest-value technique for
	# breaking up symmetric noise blobs. Warps the SAMPLE POSITION before the
	# continent noise reads it, so coastlines and landmass edges meander instead
	# of forming smooth eggs. Amplitude is a fraction of the continent
	# wavelength (see WARP_AMPLITUDE_FRACTION), so it stays correct at any
	# radius. Only the continent field is warped - warping every band compounds
	# distortion into visible mush (tried, see terrain-generator.md).
	var cont_warp: Resource = null # TEMP: isolating warp cost

	# Continent is FRACTAL_FBM with sub-0.5 gain: each octave contributes much
	# less than the one below it, which is what a real spectral falloff needs
	# and a single-octave noise cannot have internally.
	#
	# COST NOTE (measured in-process, debug_measure_microseconds_per_voxel):
	# the first pass used 3 continent octaves + a 2-octave progressive warp + a
	# 2-octave erosion fractal + 4 ridged peak octaves and cost 30.8 us/voxel
	# shape-only - 5x the pre-existing 6.24 us/voxel base, blowing the ~15
	# us/voxel budget before cliffs or caves were even added back in. Octave
	# counts below are the trimmed values that keep the technique (warp +
	# multi-octave ridged peaks) while fitting the budget; erosion dropped
	# fractal octaves entirely since its only job is a slowly-varying mask, not
	# fine detail - the spline already gives it shape.
	# WHAT THIS FIELD IS, AND WHAT IT DELIBERATELY IS NOT
	#
	# FOUR additive bands, with two more fields used only as GATES (erosion and
	# belt, which multiply rather than add). That is the whole landform:
	#   continents  - where land is high or low          (~1600 m features)
	#   peaks       - mountains, gated to belts          (~380 m)
	#   detail      - the roll between the two           (~90 m)
	#   rock        - the metre-scale relief underfoot   (~7 m)
	#
	# Each band sits at roughly a quarter the wavelength of the one above it, so
	# they describe different things instead of competing. It used to be eight
	# bands, and the reason the others went matters more than the count:
	#
	# **A spline with a steep knee applied to a smooth field draws a band along
	# that field's level set.** Every one of those extra layers was a curve on a
	# low-frequency noise field, so every one of them drew contour lines across
	# the terrain - the talus curve was a literal bump on the erosion field, the
	# crater curve made concentric rings, STEPIFY on a radial height field made
	# topographic contours. They were diagnosed and tuned one at a time as if
	# they were separate bugs. They were one mistake repeated four times.
	#
	# The 3D character those layers were trying to fake - overhangs, ragged
	# stone, boulders - does not come from stacking more noise. It comes from
	# PLACED GEOMETRY, which is how VRAGE3 does it: a heightmap base, plus small
	# voxel storages of overhangs and boulders dropped at chosen locations. A
	# height field has one surface per direction and cannot overhang, no matter
	# how many octaves it is given.

	var cont_n := _noise_on(f, norm, body.seed + 11, profile.continent_freq,
		Vector2(400, r), FRACTAL_FBM, 1, 2.0, 0.45, 0.0, cont_warp)
	var eros_n := _noise_on(f, norm, body.seed + 12, profile.erosion_freq,
		Vector2(400, r + 120))
	# Peaks: FRACTAL_RIDGED with weighted_strength, so each octave is weighted
	# by the strength of the octave below it - THIS is what produces connected,
	# continuous ridgelines instead of an evenly-spaced egg-carton of bumps.
	# Verified in isolation (headless probe): output range is roughly
	# -0.63..0.93 with high values already sitting on ridges, so no separate
	# abs/invert step is needed - unlike the old single-octave "1 - |noise|"
	# approximation this replaces.
	var peak_n := _noise_on(f, norm, body.seed + 13, profile.peaks_freq,
		Vector2(400, r + 240), FRACTAL_RIDGED, 1, 2.0, 0.4, 0.6)
	# Mountain BELTS. Ridged noise well below continent frequency, so its crests
	# form long connected chains rather than isolated blobs - real ranges sit on
	# plate boundaries and run in lines, which is most of what makes a landscape
	# read as geology instead of as noise.
	#
	# This is also what lets the relief budget stay honest. Earth's 0.31%
	# peak-to-trough is a GLOBAL figure; locally the Andes rise 4 km over 50. The
	# same trick applies here: confine the mountain term to a small fraction of the
	# surface and it can be several times taller there without moving the planet's
	# average relief at all. Spreading the same budget evenly is what produced the
	# smooth dome.
	var belt_n := _noise_on(f, norm, body.seed + 15, profile.belt_freq,
		Vector2(400, r + 560), FRACTAL_RIDGED, 2, 2.1, 0.5, 0.4)
	if cont_n.is_empty() or eros_n.is_empty() or peak_n.is_empty() or belt_n.is_empty():
		return []

	# --- continents: the landform itself ---
	var cont01 := _to01(f, cont_n, Vector2(560, r))
	var cont_h := _curve(f, cont01, continent_curve(), Vector2(700, r))
	var cont := _mul(f,
		_sub(f, cont_h, _const(f, profile.sea_level, Vector2(760, r + 60)), Vector2(820, r)),
		_const(f, profile.relief_voxels, Vector2(760, r + 100)), Vector2(900, r))

	# --- erosion: a multiplier on the mountain term, never on the continent ---
	# Flattening the landmass itself would drown coastlines; flattening only what
	# sits on top of it is what produces plains next to ranges.
	var eros01 := _to01(f, eros_n, Vector2(560, r + 120))
	var flatten := _curve(f, eros01, erosion_curve(), Vector2(700, r + 120))

	# --- peaks and valleys: ridged, so crests come to a point ---
	var ridge_c := _build_ridge(f, peak_n, r + 240)
	_last_ridge = ridge_c
	# Belt membership, through a curve with a long dead zone: most of the planet
	# gets nothing at all, and the transition into a range is quick. A gentle
	# ramp here just reproduces the everywhere-slightly-bumpy look.
	var belt := _curve(f, _to01(f, belt_n, Vector2(560, r + 560)), belt_curve(),
		Vector2(700, r + 560))
	# The belt gate FLOORS rather than zeroes.
	#
	# `ridge * flatten * belt` gave mountains only inside belts, which cover
	# ~15% of the surface - so the other 85% had no landform above the continent
	# swell at all and the planet read as a smooth ocean from altitude. The fine
	# bands cannot fix that: at 1 km the silhouette is set by THIS term, and 7 m
	# rock detail is invisible there.
	#
	# Outside a belt the world still gets a quarter amplitude, which is hills and
	# plateaus rather than nothing. Inside a belt it is still full mountains, so
	# ranges remain places you travel to - the point of the belt in the first
	# place is preserved, it just no longer flattens everything else to make it.
	var belt_floor := _add(f,
		_mul(f, belt, _const(f, 0.75, Vector2(880, r + 330)), Vector2(900, r + 300)),
		_const(f, 0.25, Vector2(880, r + 360)), Vector2(920, r + 320))
	var gated := _mul(f, _mul(f, ridge_c, flatten, Vector2(880, r + 240)),
		belt_floor, Vector2(940, r + 300))
	var peaks := _mul(f, gated,
		_const(f, _peak_amplitude(profile), Vector2(880, r + 340)), Vector2(940, r + 240))

	var total := _add(f, cont, peaks, Vector2(1000, r + 120))

	# --- rock scale: the band the player actually stands on ----------------
	#
	# Everything above this is landform - the finest of them, `detail`, has
	# features around 90 m across. From eye level that is a hillside, not a rock,
	# which is why close-up terrain read as soft no matter how good the material
	# got: there was simply no geometry at rock scale to catch the light.
	#
	# FRACTAL_RIDGED with a strong weighted strength, because the point is EDGES.
	# Smooth fbm at this frequency gives gravel-like swells; a ridged field
	# creases along its zero set, and those creases are what read as fracture
	# planes and angular faces.
	#
	# Modulated by `flatten` so bare, uneroded ground is rocky while heavily
	# eroded basins stay smooth under their dust - the same signal that already
	# gates the mountain and detail terms, so the three agree about where rock
	# is exposed instead of each having its own opinion.
	if profile.rock_amplitude > 0.001:
		# Domain-warped. Un-warped ridged noise creases along its own lattice,
		# which at a single frequency reads as parallel corrugations - a
		# washboard hillside rather than broken rock. Warping the input breaks
		# that alignment, and it is the difference between "regular" and
		# "random" here far more than octave count is.
		# THREE octaves, NO domain warp.
		#
		# Warping is the better tool for breaking the lattice regularity that
		# makes single-frequency ridged noise read as a corrugated washboard -
		# but measured on this band it costs +6.4 to +8.8 us/voxel, against
		# +1 to +2 for the ridged octaves themselves (interleaved A/B, 3 reps).
		# A third octave at an irrational lacunarity buys most of the
		# irregularity for a quarter of the price: successive octaves no longer
		# share crest positions, so the corrugations break up.
		var rock_oct := 3 if ROCK_OCTAVES_OVERRIDE < 0 else ROCK_OCTAVES_OVERRIDE
		# weighted_strength 0, NOT 0.55.
		#
		# That parameter weights each octave by the strength of the one below it,
		# which makes ridgelines COHERENT and CONTINUOUS across scales. That is
		# exactly right for mountain belts - the peaks band uses 0.6 for exactly
		# that reason - and exactly wrong here: at a single dominant frequency it
		# lines the creases up into parallel corrugations, and the hillside read
		# as a washboard. Verified by A/B: with this band disabled entirely the
		# corrugation disappears and nothing else changes.
		#
		# Lacunarity stays irrational so octave crests do not re-align either.
		var rock_n := _noise_on(f, norm, body.seed + 18, profile.rock_freq,
			Vector2(400, r + 1200), FRACTAL_RIDGED, rock_oct, 2.17, 0.55, 0.0)
		if not rock_n.is_empty():
			# Gated hard to broken ground, with only a small floor elsewhere.
			#
			# At a 0.3 floor this band covered the entire planet in 7 m lumps and
			# the surface read as a carpet - there were no flat plains at all.
			# Real regolith plains ARE smooth at this scale; what breaks them up
			# is loose rock lying ON them, which is placed geometry, not a height
			# field. So the band now describes rocky ground only, and the plains
			# are left flat for boulders to sit on.
			# Driven by EROSION across the whole planet, not confined to belts.
			#
			# This was `flatten * belt * 0.88 + 0.12`. Belts cover ~15% of the
			# surface, so 85% of the world received only the 0.12 floor and the
			# planet read as a smooth ocean. That was an over-correction from the
			# opposite failure - an ungated band made everything a uniform lumpy
			# carpet - and both are the same mistake: a single global amount of
			# roughness, high or low.
			#
			# What terrain needs is roughness that VARIES over distance. The
			# erosion field already is exactly that signal and was being spent
			# only on gating mountains. Wide range (0.15..1.0) so heavily eroded
			# ground is genuinely smooth plain and uneroded ground is broken rock,
			# with everything between.
			var rock_gate := _add(f,
				_mul(f, flatten, _const(f, 0.85, Vector2(700, r + 1290)), Vector2(760, r + 1260)),
				_const(f, 0.15, Vector2(700, r + 1320)), Vector2(820, r + 1280))
			var rock := _mul(f,
				_mul(f, rock_n, _const(f, profile.rock_amplitude, Vector2(560, r + 1240)),
					Vector2(640, r + 1200)),
				rock_gate, Vector2(900, r + 1200))
			total = _add(f, total, rock, Vector2(1020, r + 1200))

	if profile.detail_amplitude > 0.001:
		var det_n := _noise_on(f, norm, body.seed + 14, profile.detail_freq, Vector2(400, r + 380))
		if not det_n.is_empty():
			# Modulated by `flatten`, the same erosion signal that gates the
			# mountain term - a plain WAS exactly as bumpy as a mountainside
			# before this, because the detail octave ignored erosion entirely.
			# Floored at 0.12 rather than zeroed so basins keep a whisper of
			# grain instead of reading as glass-smooth.
			# Follows BOTH erosion and the belt: a plain was exactly as bumpy as a
			# mountainside before any of this, because the detail octave ignored
			# them entirely. Floored at 0.12 rather than zeroed so basins keep a
			# whisper of grain instead of reading as glass.
			# Erosion only. Multiplying by `belt` here confined all mid-scale
			# relief to mountain ranges and left the plains featureless.
			var det_gate := flatten
			var det_scale := _add(f,
				_mul(f, det_gate, _const(f, 0.88, Vector2(700, r + 440)), Vector2(760, r + 440)),
				_const(f, 0.12, Vector2(700, r + 480)), Vector2(820, r + 460))
			var det := _mul(f,
				_mul(f, det_n, _const(f, profile.detail_amplitude, Vector2(560, r + 440)),
					Vector2(640, r + 380)),
				det_scale, Vector2(900, r + 400))
			total = _add(f, total, det, Vector2(1000, r + 380))
	return total

## Ridged mountain term, unscaled: the FRACTAL_RIDGED noise through the peaks
## spline.
##
## Used to invert a single-octave noise by hand ("1 - |noise|") before
## 2026-09-11. Replaced because that produced one ridge per octave with no
## relationship between neighbouring octaves - an egg-carton, not a range.
## `peak_noise` now comes pre-ridged (FRACTAL_RIDGED + weighted_strength, see
## `_build_height_offset`), which weights each octave by the strength of the
## one below it and is what makes ridgelines connect. Verified in a headless
## probe: this noise's raw range is roughly -0.63..0.93 with ridges already at
## the high end, so `_to01` + clamp is enough - no separate abs/invert step.
##
## Split out because cliff detection differences THIS and nothing else. Cliffs
## come from the mountain term - the continent field is smooth by construction
## and the detail octave is below the scale a cliff mask cares about - so
## rebuilding the whole height chain to find slope was paying 2.14x to
## differentiate two terms that barely contribute to it.
static func _build_ridge(f: VoxelGraphFunction, peak_noise: Array, row: float) -> Array:
	var ridge01 := _clamp01(f, _to01(f, peak_noise, Vector2(560, row)), Vector2(640, row))
	var shaped := _curve(f, ridge01, peaks_curve(), Vector2(760, row))

	# Facet: quantise into planar bands and blend back with the smooth curve, so
	# ridgelines get flat faces meeting at hard edges (the reference's sharp
	# ridgelines) rather than the fully continuous, swept slope `shaped` gives on
	# its own. Called from both the main height chain and the offset copies the
	# slope mask differences, so faceting is automatically consistent between
	# shape and cliff detection - no second call site to keep in sync by hand.
	var step := _const(f, 1.0 / FACET_STEPS, Vector2(820, row + 40))
	var stepped := _stepify(f, shaped, step, Vector2(880, row))
	return _lerp_const(f, shaped, stepped, FACET_BLEND, Vector2(960, row))

## Mountain amplitude after weathering. A thick atmosphere has weather to round
## terrain off; an airless body keeps its edges. Folded into a build-time
## constant rather than costing a node per voxel.
static func _peak_amplitude(profile: PlanetProfile) -> float:
	return profile.peaks_amplitude * (1.0 - 0.35 * profile.weathering)

## The original baked-heightmap path, kept as a per-body override.
static func _build_baked_shape(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, voxel_scale: float) -> Array:
	var hm: PlanetHeightmap = body.heightmap
	var img := heightmap_to_rf(hm)
	if img == null:
		push_error("PlanetGraphGenerator: heightmap could not be converted")
		return []
	# sdf = |p| - (radius + sample(dir) * factor). The map is 0..1, so the radius
	# is pulled down by the sea-level fraction to centre terrain on the nominal
	# surface instead of sitting entirely above it. Everything here is in VOXEL
	# units - the generator works in the terrain's own local grid.
	var relief_vox := hm.relief_meters / maxf(voxel_scale, 0.0001)
	var n := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2(300, 80))
	f.set_node_param(n, 0, img)
	f.set_node_param(n, 1, body.radius - hm.sea_level * relief_vox)
	f.set_node_param(n, 2, relief_vox)
	f.add_connection(x, 0, n, 0)
	f.add_connection(y, 0, n, 1)
	f.add_connection(z, 0, n, 2)
	return [n, 0]

## Surface steepness as a 0..1 mask, by finite differences on the MOUNTAIN term.
##
## There is no gradient node for a composed field - `FAST_NOISE_GRADIENT_3D`
## differentiates a single noise, not a spline-mapped combination of three - so
## the field is rebuilt at neighbouring directions and differenced.
##
## Only the ridged term is rebuilt, not the whole height chain. Differencing
## everything measured 2.14x per voxel (6.24 -> 13.33 us) for two extra terms
## that barely steepen anything: continents are smooth by construction and the
## detail octave is finer than a cliff mask resolves. The erosion multiplier is
## left out of the differenced copy too - it varies far more slowly than the
## ridge it scales.
##
## Both an X-offset and a Z-offset are used because a single one degenerates:
## nudging X barely rotates a direction already pointing along X. The two
## degenerate on different axes, so the sum always has one good term. That makes
## the magnitude direction-dependent, so this is a slope PROXY good enough for a
## material mask, not a metric.
static func _build_slope_mask(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, norm: int, profile: PlanetProfile,
		ridge: Array) -> Array:
	if ridge.is_empty():
		return []
	var eps := body.radius * SLOPE_EPSILON
	var amp := _peak_amplitude(profile)
	if amp <= 0.001:
		return []

	var parts: Array = []
	var row := 2300.0
	for axis in [0, 2]:
		var n := _offset_normal(f, x, y, z, axis, eps, Vector2(150, row))
		# Same fractal config as the primary peak noise in _build_height_offset -
		# a mismatch here would difference two different fields and the result
		# would not describe this planet's actual slope.
		var noise := _noise_on(f, n, body.seed + 13, profile.peaks_freq,
			Vector2(400, row), FRACTAL_RIDGED, 1, 2.0, 0.4, 0.6)
		if noise.is_empty():
			return []
		var r2 := _build_ridge(f, noise, row)
		var d := _abs(f, _sub(f, r2, ridge, Vector2(1200, row)), Vector2(1260, row))
		parts.append(d)
		row += 600.0

	# Scaled to height per unit distance, so the threshold means the same thing
	# at any radius: the ridge is unitless, amplitude turns it into voxels, and
	# the arc length turns the difference into a gradient.
	var sum := _add(f, parts[0], parts[1], Vector2(1340, 2600))
	var slope := _mul(f, sum,
		_const(f, amp / maxf(eps, 0.0001), Vector2(1340, 2660)), Vector2(1420, 2600))
	return _smoothstep(f, slope, CLIFF_START_SLOPE, CLIFF_FULL_SLOPE, Vector2(1500, 2600))

## A normalized direction with one world axis nudged, for finite differencing.
static func _offset_normal(f: VoxelGraphFunction, x: int, y: int, z: int,
		axis: int, eps: float, pos: Vector2) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_NORMALIZE_3D, pos)
	var sources := [x, y, z]
	for i in 3:
		if i == axis:
			var shifted := _add(f, [sources[i], 0],
				_const(f, eps, pos + Vector2(-150, 40 * i + 20)), pos + Vector2(-70, 40 * i))
			f.add_connection(shifted[0], shifted[1], n, i)
		else:
			f.add_connection(sources[i], 0, n, i)
	return n

## Carves tunnels out of `sdf`, returning the new SDF.
##
## This is the Phase 2 "3D detail" layer, and it is the thing that makes the
## terrain genuinely 3D rather than 2.5D: a heightmap or a radial height field
## cannot produce an overhang, because it has one surface per direction. Caves
## and the entrances they open are the only part of the shape that is a real
## volume.
##
## Sampled on WORLD position, not the sphere direction. Every other field here
## uses direction because it describes the surface; a cave has to vary with
## depth too, and a direction-sampled cave would be an identical shaft repeated
## all the way to the core.
static func _carve_caves(f: VoxelGraphFunction, body: CelestialBody,
		x: int, y: int, z: int, sdf: Array, profile: PlanetProfile) -> Array:
	var freq := 1.0 / maxf(CAVE_SIZE_VOXELS, 1.0)
	var a := _noise_xyz(f, x, y, z, body.seed + 21, freq, Vector2(400, 3600))
	var b := _noise_xyz(f, x, y, z, body.seed + 22, freq * 1.37, Vector2(400, 3760))
	if a.is_empty() or b.is_empty():
		return sdf

	# |n| - w is negative within w of the noise zero-set. max() of two such is the
	# INTERSECTION, i.e. only where both are near zero - a tube, not a sheet.
	var width := _const(f, CAVE_TUBE_WIDTH, Vector2(600, 3700))
	var ta := _sub(f, _abs(f, a, Vector2(560, 3600)), width, Vector2(680, 3600))
	var tb := _sub(f, _abs(f, b, Vector2(560, 3760)), width, Vector2(680, 3760))
	var tube := _bin(f, VoxelGraphFunction.NODE_MAX, ta, tb, Vector2(780, 3680))

	# Scaled from noise units into voxels so the smooth-subtract blend radius
	# means the same thing as every other distance in this graph.
	var cave := _mul(f, tube,
		_const(f, CAVE_SIZE_VOXELS, Vector2(780, 3840)), Vector2(860, 3680))

	# Push the cave SDF positive (= no cave) near the surface and below bedrock.
	# Without the ceiling the crust turns to lace and the player falls through on
	# spawn; without a floor the caves undermine the bedrock shell.
	var ceiling := CAVE_SIZE_VOXELS * CAVE_CEILING_BORES
	var fade := CAVE_SIZE_VOXELS * CAVE_CEILING_FADE_BORES
	var depth := _mul(f, sdf, _const(f, -1.0, Vector2(860, 3960)), Vector2(920, 3920))
	var near_surface := _sub(f, _const(f, 1.0, Vector2(980, 3980)),
		_smoothstep(f, depth, ceiling, ceiling + fade,
			Vector2(980, 3920)), Vector2(1060, 3920))
	var lift := _mul(f, near_surface,
		_const(f, CAVE_SIZE_VOXELS * 2.0, Vector2(1060, 3990)), Vector2(1140, 3920))
	cave = _add(f, cave, lift, Vector2(1220, 3680))

	var out := f.create_node(VoxelGraphFunction.NODE_SDF_SMOOTH_SUBTRACT, Vector2(1320, 3680))
	f.set_node_param(out, 0, CAVE_SMOOTHNESS)
	f.add_connection(sdf[0], sdf[1], out, 0)
	f.add_connection(cave[0], cave[1], out, 1)
	return [out, 0]

# --- lava tubes (stage 4b) ----------------------------------------------------------------------------------------
## Drained lava tubes: a lava flow crusts over, the molten core drains, a tunnel is left under a roof of solid basalt.
## Built as an SDF tunnel along the zero line of a slow noise on the surface direction (so it meanders like a flow
## path), at a fixed depth below the ground, in segments (tubes end where the flow did). Where the roof is thin it
## falls in: skylight pits and collapse trenches, in chains along the tube. Only inside the volcanic trait's region.
## Sizes from lunar and terrestrial tubes scaled to a player: 10-14 m wide, 7-9 m high, roof 6-10 m.
const TUBE_PATH_M := 700.0          # meander wavelength of the path field
const TUBE_SEGMENT_M := 1800.0      # length scale of tube segments
const TUBE_HALF_WIDTH_M := 6.0
const TUBE_HALF_HEIGHT_M := 4.0
const TUBE_DEPTH_M := 13.0          # centre below the ground
const TUBE_SKY_M := 140.0           # spacing scale of roof collapses
## The path is the edge network of a warped Voronoi field (F2 - F1 is ~2x the distance to the nearest edge, so the
## tunnel keeps one width; a noise zero line gave 1.5-36 m because its slope wanders). Edges branch and rejoin like
## real tube systems. Cell size in metres; lateral metres per unit of (value + 1) / 2, from scripts/dev/tube_probe.gd.
const TUBE_EDGE_M_PER_UNIT := 930.0
## Tests switch the tubes off to see what else in the ground is hollow (scripts/dev/tube_probe.gd).
static var tubes_enabled := true

static func _carve_lava_tubes(f: VoxelGraphFunction, body: CelestialBody, x: int, y: int, z: int, norm: int,
		profile: PlanetProfile, sdf: Array, masks: Dictionary) -> Array:
	var land := TraitMixer.landform(body)
	if not tubes_enabled or float(land.lava_tubes) <= 0.0 or profile.rock_amplitude <= 0.0:
		return sdf
	var P := Vector2(400, 5200)
	var freq_per_m: float = profile.rock_freq * PlanetProfile.ROCK_FEATURE_M
	var vox_per_m: float = profile.rock_amplitude / PlanetProfile.ROCK_AMPLITUDE_M
	# where: the volcanic trait's region (or everywhere if it is the dominant trait)
	var region: Array = []
	var mix := TraitMixer.of(body)
	for i in mix.size():
		var t: PlanetTrait = mix[i].trait
		if t.lava_tubes > 0.0:
			if i > 0:
				region = _trait_region(f, body, t, float(mix[i].weight), norm, masks, x, y, z, P + Vector2(0, 600))
			break
	var path := _cellular_edge_on(f, norm, body.seed + 701, freq_per_m / TUBE_PATH_M, P)
	var seg := _noise_on(f, norm, body.seed + 702, freq_per_m / TUBE_SEGMENT_M, P + Vector2(0, 120))
	var sky := _noise_on(f, norm, body.seed + 703, freq_per_m / TUBE_SKY_M, P + Vector2(0, 240), FRACTAL_FBM, 2)
	if path.is_empty() or seg.is_empty() or sky.is_empty():
		return sdf
	var hw := TUBE_HALF_WIDTH_M * vox_per_m
	var hh := TUBE_HALF_HEIGHT_M * vox_per_m
	# lateral distance from the path line, in voxels
	var lat := _mul(f, _add(f, path, _const(f, 1.0, P), P), _const(f, 0.5 * TUBE_EDGE_M_PER_UNIT * vox_per_m, P),
		P + Vector2(200, 0))
	var depth := _mul(f, sdf, _const(f, -1.0, P), P + Vector2(200, 60))
	# ellipse cross-section: sqrt((lat/hw)^2 + ((depth - dc)/hh)^2) - 1, scaled back to voxels
	var ex := _mul(f, lat, _const(f, 1.0 / hw, P), P)
	var ey := _mul(f, _sub(f, depth, _const(f, TUBE_DEPTH_M * vox_per_m, P), P), _const(f, 1.0 / hh, P), P)
	var e2 := _add(f, _mul(f, ex, ex, P), _mul(f, ey, ey, P), P)
	var en := f.create_node(VoxelGraphFunction.NODE_SQRT, P + Vector2(400, 0))
	f.add_connection(e2[0], e2[1], en, 0)
	var tube := _mul(f, _sub(f, [en, 0], _const(f, 1.0, P), P), _const(f, minf(hw, hh), P), P + Vector2(460, 0))
	# roof collapses: a shaft from the tube up to the ground where the collapse field peaks, as wide as the tube there
	var s01 := _smoothstep(f, _to01(f, sky, P), 0.62, 0.69, P + Vector2(200, 240))
	var r_sky := _sub(f, _mul(f, s01, _const(f, hw * 1.2, P), P), _const(f, 1.5, P), P)
	var shaft := _bin(f, VoxelGraphFunction.NODE_MAX, _sub(f, lat, r_sky, P),
		_sub(f, depth, _const(f, TUBE_DEPTH_M * vox_per_m, P), P), P + Vector2(460, 240))
	var cave := _bin(f, VoxelGraphFunction.NODE_MIN, tube, shaft, P + Vector2(560, 120))
	# segments (and region): outside them, push the cave field far positive
	var gate := _smoothstep(f, _to01(f, seg, P), 0.45, 0.55, P + Vector2(200, 120))
	if not region.is_empty():
		gate = _mul(f, gate, region, P)
	var lift := _mul(f, _sub(f, _const(f, 1.0, P), gate, P), _const(f, 60.0, P), P)
	cave = _add(f, cave, lift, P + Vector2(640, 120))
	var out := f.create_node(VoxelGraphFunction.NODE_SDF_SMOOTH_SUBTRACT, P + Vector2(740, 0))
	f.set_node_param(out, 0, 1.5)
	f.add_connection(sdf[0], sdf[1], out, 0)
	f.add_connection(cave[0], cave[1], out, 1)
	return [out, 0]

## Warped cellular F2 - F1 on the surface direction: ~ -1 on a Voronoi edge, rising away from it.
static func _cellular_edge_on(f: VoxelGraphFunction, norm: int, seed_value: int, frequency: float, pos: Vector2) -> Array:
	var noise: Resource = ClassDB.instantiate("ZN_FastNoiseLite")
	if noise == null:
		return []
	noise.set("seed", seed_value)
	noise.set("period", 1.0 / maxf(frequency, 0.000001))
	noise.set("noise_type", 2)                 # TYPE_CELLULAR
	noise.set("fractal_type", 0)
	noise.set("cellular_distance_function", 0) # EUCLIDEAN
	noise.set("cellular_return_type", 4)       # RETURN_DISTANCE_2_SUB
	noise.set("cellular_jitter", 1.0)
	noise.set("warp_noise", _zn_warp(seed_value + 1, frequency * 0.9, 1, 0.14))
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, pos)
	f.set_node_param(n, 0, noise)
	f.add_connection(norm, 0, n, 0)
	f.add_connection(norm, 1, n, 1)
	f.add_connection(norm, 2, n, 2)
	return [n, 0]

## Noise sampled on raw world coordinates rather than the sphere direction.
static func _noise_xyz(f: VoxelGraphFunction, x: int, y: int, z: int,
		seed_value: int, frequency: float, pos: Vector2) -> Array:
	var noise := _zn_noise(seed_value, frequency)
	if noise == null:
		return []
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, pos)
	f.set_node_param(n, 0, noise)
	f.add_connection(x, 0, n, 0)
	f.add_connection(y, 0, n, 1)
	f.add_connection(z, 0, n, 2)
	return [n, 0]

# --- splines -----------------------------------------------------------------
#
# These are the shape of the world far more than any noise setting is. Each maps
# a 0..1 field to a 0..1 response; the interesting behaviour is entirely in
# where the knees sit.

## Continentalness -> normalised surface height.
##
## The flat run at the bottom is ocean floor, the steep middle is continental
## shelf and coast, and the shallower top is inland. A straight line here gives
## the "everything is a gentle dome" look that reads as noise, not geography.
static func continent_curve() -> Curve:
	var c := Curve.new()
	# Long flat runs at BOTH ends - basin floor and inland plateau - with the
	# climb concentrated in the middle. Flat is not the absence of terrain; a
	# plain that actually reads as a plain is what gives the ranges something to
	# rise out of.
	c.add_point(Vector2(0.00, 0.06))
	c.add_point(Vector2(0.34, 0.10))
	c.add_point(Vector2(0.46, 0.26))
	c.add_point(Vector2(0.56, 0.60))
	c.add_point(Vector2(0.66, 0.74))
	c.add_point(Vector2(0.82, 0.80))
	c.add_point(Vector2(1.00, 0.92))
	return c

## Erosion -> how much of the mountain term survives. Decreasing: a heavily
## eroded region keeps almost none of it and reads as plains.
static func erosion_curve() -> Curve:
	var c := Curve.new()
	# Falls away much faster than a linear ramp. Combined with the belt gate this
	# leaves the large majority of the planet genuinely flat, which is what buys
	# the amplitude to make the remainder dramatic.
	c.add_point(Vector2(0.00, 1.00))
	c.add_point(Vector2(0.18, 0.86))
	c.add_point(Vector2(0.38, 0.45))
	c.add_point(Vector2(0.58, 0.14))
	c.add_point(Vector2(0.78, 0.03))
	c.add_point(Vector2(1.00, 0.00))
	return c

## Belt field -> mountain-range membership.
##
## The long dead zone is the whole point: below ~0.45 there is no range at all.
## Without it every value contributes something and ranges stop being places.
static func belt_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.00, 0.00))
	c.add_point(Vector2(0.45, 0.00))
	c.add_point(Vector2(0.62, 0.18))
	c.add_point(Vector2(0.80, 0.65))
	c.add_point(Vector2(1.00, 1.00))
	return c

## Ridge value -> mountain height. Convex, so only the top of the ridged noise
## becomes a peak and the rest stays foothills; a linear response gives evenly
## bumpy ground everywhere.
static func peaks_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.00, 0.00))
	c.add_point(Vector2(0.45, 0.06))
	c.add_point(Vector2(0.70, 0.22))
	c.add_point(Vector2(0.88, 0.58))
	c.add_point(Vector2(1.00, 1.00))
	return c

## Mesa/plateau region field -> terracing membership. Same dead-zone idiom as
## `belt_curve`: below ~0.55 there is no terracing at all, so mesas stay a
## regional feature instead of a global one.
static func mesa_curve() -> Curve:
	var c := Curve.new()
	# MEASURED, not guessed. Sampling this exact noise config over 4000
	# directions on the sphere gives raw -0.984..1.000 and, through _to01:
	#
	#     below 0.55 -> 34%     below 0.78 -> 66%
	#     below 0.88 -> ~82%    below 0.95 -> ~92%
	#
	# So the original 0.55 dead zone left roughly two thirds of the planet
	# terraced and 0.78 still left a third - which is why it read as a ziggurat
	# both times. FRACTAL_RIDGED is only mildly skewed upward here (mean ~0.62),
	# not the strong bias it was first assumed to be; the threshold was simply
	# far too low for "a few distinctive regions".
	#
	# 0.88 puts terracing on roughly 12-15% of the surface with full strength on
	# a few percent, which is what makes a mesa a place you travel to rather
	# than the shape of the whole world.
	c.add_point(Vector2(0.00, 0.00))
	c.add_point(Vector2(0.88, 0.00))
	c.add_point(Vector2(0.93, 0.30))
	c.add_point(Vector2(0.97, 0.80))
	c.add_point(Vector2(1.00, 1.00))
	return c

## UNREACHABLE AS WRITTEN: the spot value it is fed is binary (0 or ~0.99, see
## the note near CRATER_JITTER), so only the two end points of this curve ever
## apply and every crater it made was a hard-edged disc. Kept only because the
## procedural path still references it; do not build new craters on it.
static func crater_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.00, 0.00))
	c.add_point(Vector2(0.30, 0.00))
	c.add_point(Vector2(0.45, 0.35))
	c.add_point(Vector2(0.60, 0.10))
	c.add_point(Vector2(0.75, -0.30))
	c.add_point(Vector2(1.00, -1.00))
	return c

## Erosion field -> talus apron contribution, as a fraction of
## `peaks_amplitude * TALUS_SHARE`. A bump, not a ramp: `erosion_curve()`
## already carries the peak itself down to near zero by ~0.4, so the apron
## picks up right where the peak's own foot is and fades out again before the
## far plain - a debris skirt between the two, not a duplicate of either.
static func talus_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.00, 0.00))
	c.add_point(Vector2(0.28, 0.00))
	c.add_point(Vector2(0.48, 1.00))
	c.add_point(Vector2(0.75, 0.35))
	c.add_point(Vector2(1.00, 0.00))
	return c

# --- materials ---------------------------------------------------------------

## Weight for one biome at a climate point, as a falloff from that biome's
## CENTRE rather than a box test on its declared range.
##
## The box version left holes: four authored biomes covering
## (temperature, roughness) boxes do not tile the unit square, so any point in a
## gap had every biome at weight zero and fell back to material index 0.
## Measured over 600 directions, that fallback was 83% of the planet - a
## generator quietly painting most of the world in a default.
##
## A falloff from the centre always resolves, because SOME biome is always
## nearest. That is exactly the "nearest biome in climate space" rule the script
## generator used, restored without a branch: each biome computes its own
## distance independently and the mesher keeps the strongest.
##
## This matters more with procedural planets than it ever did with one authored
## world - a generated biome set has no one checking that its boxes tile.
static func _biome_weight(f: VoxelGraphFunction, temp: Array, rough: Array,
		biome: Biome, pos: Vector2) -> Array:
	var tc := (biome.temperature_min + biome.temperature_max) * 0.5
	var rc := (biome.roughness_min + biome.roughness_max) * 0.5

	var d := f.create_node(VoxelGraphFunction.NODE_DISTANCE_2D, pos)
	f.add_connection(temp[0], temp[1], d, 0)
	f.add_connection(rough[0], rough[1], d, 1)
	var cx := _const(f, tc, pos + Vector2(-120, 60))
	var cy := _const(f, rc, pos + Vector2(-120, 100))
	f.add_connection(cx[0], cx[1], d, 2)
	f.add_connection(cy[0], cy[1], d, 3)

	# Falls to zero at BIOME_INFLUENCE. Wide enough that neighbouring biomes
	# overlap and blend instead of meeting at a hard seam, and wide enough that no
	# point in the unit square is out of reach of every biome.
	var near := _sub(f, _const(f, 1.0, pos + Vector2(140, 80)),
		_smoothstep(f, [d, 0], 0.0, BIOME_INFLUENCE, pos + Vector2(140, 0)),
		pos + Vector2(240, 30))
	# Floored so it can never reach exactly zero.
	#
	# The weights are normalised by dividing by their sum, which only guarantees
	# coverage if SOMETHING is non-zero. With a single biome whose falloff
	# genuinely reaches zero outside its radius, the sum is zero, the division
	# yields zero, and the mesher gets no material at all - measured at 34.0% of
	# the surface, which rendered as void-coloured patches that look exactly like
	# holes in the geometry.
	#
	# A tiny floor makes the set a true partition of unity: with one biome it
	# normalises to 1.0 everywhere, and with several the floors are negligible
	# next to whichever biome actually wins. Coverage stops depending on how the
	# palette happens to be arranged in climate space.
	return _add(f, near, _const(f, BIOME_WEIGHT_FLOOR, pos + Vector2(240, 90)),
		pos + Vector2(320, 30))

## Every material writes its own weight layer; the mesher keeps the strongest
## four per voxel. No branching anywhere, which is the whole reason this can
## live in a graph at all.
static func _build_materials(f: VoxelGraphFunction, body: CelestialBody,
		norm: int, sdf: Array, profile: PlanetProfile, cliff: Array,
		x: int, y: int, z: int, masks: Dictionary = {}, eroded: Image = null) -> void:
	var depth := _mul(f, sdf, _const(f, -1.0, Vector2(900, 560)), Vector2(950, 500))
	# A planet with traits (reports/AAA voxel terrain fidelity.md) gets its ground from trait rules; the biome path
	# below stays for bodies that still use hand-authored biomes.
	var mix := TraitMixer.of(body)
	if not mix.is_empty():
		_build_trait_materials(f, body, mix, norm, depth, profile, cliff, x, y, z, masks, eroded)
		_build_ores(f, body, norm, depth, profile, x, y, z)
		return

	# Bedrock takes over below the topsoil band; biome ground fades out with it.
	var bed := _clamp01(f,
		_mul(f, _sub(f, depth, _const(f, TOPSOIL_DEPTH, Vector2(1000, 580)), Vector2(1050, 500)),
			_const(f, 1.0 / BEDROCK_FADE, Vector2(1050, 580)), Vector2(1120, 500)),
		Vector2(1220, 500))
	var surface := _sub(f, _const(f, 1.0, Vector2(1220, 400)), bed, Vector2(1300, 420))
	_weight_out(f, BEDROCK_LAYER, bed, Vector2(1600, 500))

	# --- climate ---
	# Noise dominates latitude 65/35, matching ore_generator.gd. A
	# latitude-dominated temperature draws biome borders as rings around the
	# world Y axis, which is exactly what the script generator originally got
	# wrong and had to be fixed.
	# Frequencies scale with the body: a value tuned for a 500 m planet gives one
	# climate band across an 8 km one.
	var climate := _noise_on(f, norm, body.seed + 400, profile.climate_freq, Vector2(400, 700))
	var rough := _noise_on(f, norm, body.seed + 401, profile.roughness_freq, Vector2(400, 820))
	if climate.is_empty() or rough.is_empty():
		_weight_out(f, GROUND_LAYER, surface, Vector2(1600, 420))
		return

	var climate01 := _to01(f, climate, Vector2(560, 700))
	var rough01 := _to01(f, rough, Vector2(560, 820))

	var ny := f.create_node(VoxelGraphFunction.NODE_ABS, Vector2(400, 940))
	f.add_connection(norm, 1, ny, 0)
	var lat := _sub(f, _const(f, 1.0, Vector2(460, 980)), [ny, 0], Vector2(540, 940))

	# Local variation (noise + latitude) around the body's ORBITAL temperature, so
	# a planet close to its star has a hot mean with cold poles rather than the
	# same 0..1 spread every world gets. This is what makes two planets with
	# identical biome lists still look different.
	var local := _add(f,
		_mul(f, climate01, _const(f, 0.65, Vector2(700, 740)), Vector2(760, 700)),
		_mul(f, lat, _const(f, 0.35, Vector2(700, 980)), Vector2(760, 940)),
		Vector2(840, 820))
	var temp := _clamp01(f, _add(f,
		_mul(f, _sub(f, local, _const(f, 0.5, Vector2(880, 780)), Vector2(920, 760)),
			_const(f, ORBITAL_TEMP_SPREAD, Vector2(880, 700)), Vector2(960, 760)),
		_const(f, profile.temperature_bias, Vector2(880, 860)), Vector2(1000, 800)),
		Vector2(1060, 800))

	# --- biomes: one weight layer each ---
	var biomes: Array = body.biomes
	var row := 260.0
	if biomes.is_empty():
		_weight_out(f, GROUND_LAYER, surface, Vector2(1600, 420))
	else:
		# Cliff rock replaces biome stone on steep faces rather than layering over
		# it: without the suppression both are written at full strength and the
		# blend reads as a muddy average instead of exposed rock.
		var not_cliff: Array = []
		if not cliff.is_empty():
			not_cliff = _sub(f, _const(f, 1.0, Vector2(1500, 180)), cliff, Vector2(1560, 160))
			_weight_out(f, CLIFF_LAYER,
				_cutoff(f, _mul(f, cliff, surface, Vector2(1620, 160)), Vector2(1660, 160)),
				Vector2(1700, 160))
		# NORMALISED across the biome set, not used raw.
		#
		# A raw falloff only covers climate space if the biomes happen to be close
		# enough together relative to BIOME_INFLUENCE. Narrowing that radius to 0.32
		# while cutting the planet to ONE biome left most of the sphere further than
		# 0.32 from any biome centre, so every weight layer was zero and whole mesh
		# blocks rendered with no material at all - they showed as rows of dark
		# rectangles that survived disabling shadows, the atmosphere, and every LOD
		# and edge-clamp change, because none of those were the cause.
		#
		# Dividing by the sum makes the weights a partition of unity: SOME biome
		# always owns a point, whatever the influence radius is and however many
		# biomes exist. Coverage stops being a tuning question.
		var raw: Array = []
		for biome in biomes:
			raw.append(_biome_weight(f, temp, rough01, biome, Vector2(960, row)))
			row += 300.0

		var total: Array = raw[0]
		for i in range(1, raw.size()):
			total = _add(f, total, raw[i], Vector2(1240, 200 + i * 40))
		# Floored so the division cannot blow up where every falloff has decayed.
		total = _bin(f, VoxelGraphFunction.NODE_MAX, total,
			_const(f, 0.0001, Vector2(1240, 160)), Vector2(1300, 180))

		row = 260.0
		for i in raw.size():
			var biome: Biome = biomes[i]
			var w := _mul(f,
				_mul(f, _div(f, raw[i], total, Vector2(1360, row)),
					_const(f, BIOME_WEIGHT_SCALE, Vector2(1340, row + 60)), Vector2(1400, row)),
				surface, Vector2(1440, row))
			if not not_cliff.is_empty():
				w = _mul(f, w, not_cliff, Vector2(1500, row))
			_weight_out(f, biome.stone_material_index,
				_cutoff(f, w, Vector2(1540, row)), Vector2(1600, row))
			row += 300.0

	_build_ores(f, body, norm, depth, profile, x, y, z)

## Ore deposits: one weight layer each (shared by the biome and the trait material paths).
static func _build_ores(f: VoxelGraphFunction, body: CelestialBody, norm: int, depth: Array,
		profile: PlanetProfile, x: int, y: int, z: int) -> void:
	var row := 1720.0
	# --- ore deposits: one weight layer each -------------------------------
	#
	# Modelled on Space Engineers rather than on veins, because the vein model
	# was wrong about the thing that matters: veins are EVERYWHERE. |noise| near
	# zero is a connected surface through the whole volume, so thresholding it
	# scatters thin sheets of ore across the entire planet at the right depth.
	# There is nothing to find, no reason to prospect, and no reason to travel.
	#
	# What SE actually does (wiki + the SE2 deposit design discussion):
	#
	#   - Deposits are DISCRETE CLUSTERS, not continuous structures.
	#   - They are clustered within ~150 m of the surface on planets.
	#   - They appear "in groups of two or three, spread out in horizontal
	#     layers below each other" - one site, several ores stacked by depth.
	#   - They have a VISIBLE SURFACE EXPRESSION: "groups of discoloured spots
	#     on the ground", readable from jetpack height, clearest on plains.
	#
	# That last point is the whole design. It makes prospecting a thing you do
	# with your eyes while travelling, and it is why an SE planet rewards
	# looking at the ground. A buried vein you can only find by digging at
	# random rewards nothing.
	var ores: Array = body.ore_types
	if ores.is_empty():
		return

	# Which ores a REGION of the planet carries. Frequency derived from
	# continent frequency rather than the old hardcoded 1.1, which was angular:
	# a fixed value gives the same number of ore regions on a moon and on a
	# planet, so their real size changed with the body. Same bug the continent
	# and erosion fields already had fixed.
	var region := _noise_on(f, norm, body.seed + 300,
		profile.continent_freq * 0.9, Vector2(400, 1420))
	if region.is_empty():
		return
	var region01 := _to01(f, region, Vector2(560, 1420))

	# Deposit SITES, shared by every ore, so a site stacks several ores rather
	# than each ore having its own unrelated scatter. Angular cell size, because
	# the field is sampled on the unit direction - a fixed value would space
	# deposits differently on every planet size.
	# Deposit sites, in WORLD space: real lumps of ore in the ground, cells
	# measured in metres. Shared by every ore, so a site stacks several rather
	# than each ore having its own unrelated scatter.
	var site := _spots3d_xyz(f, x, y, z, body.seed + 700,
		DEPOSIT_SPACING_M, DEPOSIT_JITTER, DEPOSIT_RADIUS_M, Vector2(400, 1500))
	if site.is_empty():
		return

	var n_ores := ores.size()
	for i in n_ores:
		var ore = ores[i]
		# Which ores a given site carries. The windows OVERLAP - each is wider
		# than its 1/n share - so a site typically holds two or three ores at
		# different depths rather than exactly one, which is the "groups of two
		# or three, in layers below each other" arrangement.
		var lo := float(i) / float(n_ores) - REGION_OVERLAP
		var hi := float(i + 1) / float(n_ores) + REGION_OVERLAP
		var in_region := _window(f, region01, lo, hi, REGION_BLEND, Vector2(900, row))
		var in_depth := _window(f, depth, ore.depth_min, ore.depth_max,
			DEPTH_BLEND, Vector2(900, row + 130))

		# The ore body. A shallow ore's depth window reaches the surface, so it
		# breaks out as the discoloured patch SE players prospect by eye; a deep
		# one stays buried and needs the scanner. That split falls out of the
		# depth bands rather than needing a separate surface term.
		var w := _mul(f, _mul(f, site, in_region, Vector2(1200, row)),
			in_depth, Vector2(1320, row))
		_weight_out(f, ore.material_index, w, Vector2(1600, row))
		row += 300.0

## Ground materials from the planet's TRAITS (stage 3 of reports/AAA voxel terrain fidelity.md). Every rule reads a
## physical signal, so each material sits where the process that makes it would put it:
##   cliff rock (11)      steep faces: the baked slope mask (or the procedural cliff mask)
##   fine surface (0)     where fines settle: the deposition record ("dust")
##   alternate (8)        open, wind- or impact-worked ground between
##   scree (10)           talus aprons below slopes: the thermal-erosion talus mask
##   secondary traits     (9, 14) claim regions by their spatial mode, sized by their weight, replacing the ground
##   strata (13) / bedrock (12)  below the topsoil: warped depth bands alternating, so a dig shows layers
## Slot roles are filled by PaletteBuilder from the same mix, so generator and palette always agree.
## Bed thickness (one hard + one soft bed per cycle). Thick enough that a hard bed (34% of a cycle) stays several
## voxels tall on a steep face at LOD 1-2 (thinner beds aliased into blotches at 100 m); the fine layering inside
## them is drawn per pixel by the terrain shader (strata_lamination).
const STRATA_MIN_M := 4.0
const STRATA_MAX_M := 9.0
## Ledges: the hard bed stands out by up to this much (radially) where the face is steep, times the planet's ledge
## strength (traits). Capped so the field stays monotonic along the radius (no slivers): see _build_ledges.
const LEDGE_AMPLITUDE_M := 1.4
## Faces from about 29 degrees up carry ledges, full from about 36 (slope01 is 12..40 degrees -> 0..1).
const LEDGE_SLOPE_START := 0.6
const LEDGE_SLOPE_FULL := 0.85

## The strata beds for this graph, built once and shared: [step (0..1 sawtooth: a steep riser at the base of each
## hard bed, then a long soft slope back), hard (0..1, the hard bed: STRATA_A)].
##
## Level beds on ABSOLUTE radius, so they are cut by the landform like real ones. Each cycle is one hard bed (the
## lower STRATA_HARD_SHARE of it) over softer rock. The cycle length wanders between beds (a second, incommensurate
## term in the phase) and is warped slowly across the planet, so neither the stripes nor the benches repeat evenly.
## First version (2026-11-09) was a sine at one thickness with 50/50 hard/soft: it read as zebra stripes and an even
## ripple on every slope.
const STRATA_HARD_SHARE := 0.34
const STRATA_RISER_SHARE := 0.25

## The bed function's numbers, shared with the terrain shader (Planet sets them as uniforms) so the shader draws the
## beds per pixel exactly where the generator puts the ledges and the underground strata:
##   t = (r - base) / period;  t += WOB_AMP * sin(TAU * WOB_RATIO * t + phase);  fr = fract(t)
##   hard bed: fr in [0, STRATA_HARD_SHARE)
## r is the distance from the planet's centre in metres. Level beds, no warp: the shader must reproduce it exactly.
const STRATA_WOB_RATIO := 0.381966
const STRATA_WOB_AMP := 0.35 / (TAU * 0.381966)      # +-35% bed-to-bed thickness

static func strata_params(body: CelestialBody, profile: PlanetProfile) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([body.seed, "strata"])
	var period_m := rng.randf_range(STRATA_MIN_M, STRATA_MAX_M) * 2.0     # one hard + one soft bed
	var phase := rng.randf() * TAU
	var vox_per_m: float = profile.rock_amplitude / PlanetProfile.ROCK_AMPLITUDE_M if profile.rock_amplitude > 0.0 else 1.0
	var period_vox := period_m * vox_per_m
	return {"period_m": period_m, "period_vox": period_vox, "phase": phase, "vox_per_m": vox_per_m,
		"base_vox": floorf(body.radius / period_vox) * period_vox}

static func _strata(f: VoxelGraphFunction, body: CelestialBody, x: int, y: int, z: int, norm: int,
		profile: PlanetProfile) -> Array:
	if not _strata_band.is_empty():
		return [_strata_soft, _strata_band]
	var P := Vector2(400, 2500)
	var sp_ := strata_params(body, profile)
	var period_vox: float = sp_.period_vox
	var sp := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, P)
	var r0 := _const(f, 0.0, P)
	f.add_connection(r0[0], r0[1], sp, 3)
	f.add_connection(x, 0, sp, 0)
	f.add_connection(y, 0, sp, 1)
	f.add_connection(z, 0, sp, 2)
	# t in cycles near 0 (precision), plus the bed-to-bed thickness wobble
	var t := _mul(f, _sub(f, [sp, 0], _const(f, float(sp_.base_vox), P), P), _const(f, 1.0 / period_vox, P), P)
	var wob := f.create_node(VoxelGraphFunction.NODE_SIN, P + Vector2(200, 60))
	var wob_in := _add(f, _mul(f, t, _const(f, TAU * STRATA_WOB_RATIO, P), P), _const(f, float(sp_.phase), P), P)
	f.add_connection(wob_in[0], wob_in[1], wob, 0)
	t = _add(f, t, _mul(f, [wob, 0], _const(f, STRATA_WOB_AMP, P), P), P)
	# fract(t) = t - floor(t); STEPIFY rounds to nearest, so floor(t) = stepify(t - 0.5, 1)
	var fl := _stepify(f, _sub(f, t, _const(f, 0.5, P), P), _const(f, 1.0, P), P + Vector2(300, 0))
	var fr := _sub(f, t, fl, P + Vector2(360, 0))
	var rise := _smoothstep(f, fr, 0.0, STRATA_RISER_SHARE, P + Vector2(420, 0))
	var fall := _smoothstep(f, fr, STRATA_RISER_SHARE, 1.0, P + Vector2(420, 60))
	_strata_soft = _sub(f, rise, fall, P + Vector2(480, 0))
	_strata_band = _mul(f, _smoothstep(f, fr, 0.0, 0.06, P + Vector2(420, 120)),
		_sub(f, _const(f, 1.0, P), _smoothstep(f, fr, STRATA_HARD_SHARE - 0.06, STRATA_HARD_SHARE + 0.04, P), P),
		P + Vector2(480, 120))
	return [_strata_soft, _strata_band]

## Hard beds standing out of steep faces as benches (stage 4b, "strata ledges + cliff sets"): the sawtooth from
## _strata, a steep riser at each hard bed and a long soft slope above it, as a radial offset. On a face of slope a
## that moves the wall sideways by offset / tan(a), so steeper faces get shallower ledges, as erosion does.
## The offset's derivative along the radius must stay under 1 or the field folds into floating slivers: the riser
## climbs AMP over RISER_SHARE of a cycle with smoothstep's 1.5x peak slope, so AMP <= 0.8 * share * period / 1.5.
static func _build_ledges(f: VoxelGraphFunction, body: CelestialBody, x: int, y: int, z: int, norm: int,
		profile: PlanetProfile, slope01: Array, pos: Vector2) -> Array:
	var strength: float = float(TraitMixer.landform(body).ledges)
	if strength <= 0.0 or slope01.is_empty():
		return _const(f, 0.0, pos)
	var beds := _strata(f, body, x, y, z, norm, profile)
	var vox_per_m: float = profile.rock_amplitude / PlanetProfile.ROCK_AMPLITUDE_M if profile.rock_amplitude > 0.0 else 1.0
	var period: float = float(strata_params(body, profile).period_m) * (1.0 - 0.35)    # thinnest cycle after wobble
	var amp := minf(LEDGE_AMPLITUDE_M * strength, 0.8 * STRATA_RISER_SHARE * period / 1.5) * vox_per_m
	var gate := _smoothstep(f, slope01, LEDGE_SLOPE_START, LEDGE_SLOPE_FULL, pos)
	return _mul(f, _mul(f, beds[0], _const(f, amp, pos), pos), gate, pos + Vector2(100, 0))

static func _build_trait_materials(f: VoxelGraphFunction, body: CelestialBody, mix: Array, norm: int,
		depth: Array, profile: PlanetProfile, cliff: Array, x: int, y: int, z: int,
		masks: Dictionary, eroded: Image) -> void:
	var P := Vector2(900, 2600)
	var bed := _clamp01(f,
		_mul(f, _sub(f, depth, _const(f, TOPSOIL_DEPTH, P), P), _const(f, 1.0 / BEDROCK_FADE, P), P), P)
	var surface := _sub(f, _const(f, 1.0, P), bed, P)

	# --- steepness -> cliff rock
	var slope01 := _build_landform_slope(f, body, x, y, z, profile, eroded, masks, P + Vector2(0, 200))
	var cliffw: Array = []
	if not slope01.is_empty():
		cliffw = _smoothstep(f, slope01, 0.5, 0.92, P + Vector2(300, 200))
	elif not cliff.is_empty():
		cliffw = cliff
	var ground := surface
	var cliff_strata: Array = []
	if not cliffw.is_empty():
		# one cliff rock: the beds on exposed faces are drawn per pixel by the terrain shader (strata_* uniforms),
		# from the same function as the ledges. As voxel weights they aliased into dashes at LOD 1-2.
		var cliff_surface := _mul(f, cliffw, surface, P)
		_weight_out(f, VoxelMaterials.CLIFF_ROCK, _cutoff(f, cliff_surface, P), P + Vector2(600, 200))
		ground = _mul(f, surface, _sub(f, _const(f, 1.0, P), cliffw, P), P)

	# --- secondary traits claim regions (replace mode), each into its own slot
	var free := _const(f, 1.0, P)
	var slots := [PaletteBuilder.SECONDARY_1, PaletteBuilder.SECONDARY_2]
	var si := 0
	for i in range(1, mix.size()):
		if si >= slots.size():
			break
		var t: PlanetTrait = mix[i].trait
		if t.material_mode != "replace" or (t.material("regional") == null and t.material("surface") == null):
			continue
		var region := _trait_region(f, body, t, float(mix[i].weight), norm, masks, x, y, z, P + Vector2(0, 600 + si * 400))
		if region.is_empty():
			continue
		_weight_out(f, slots[si], _cutoff(f, _mul(f, ground, region, P), P), P + Vector2(600, 600 + si * 400))
		free = _mul(f, free, _sub(f, _const(f, 1.0, P), region, P), P)
		si += 1
	var base := _mul(f, ground, free, P + Vector2(300, 1400))

	# --- the dominant trait's ground: fine where fines settle, scree on talus, worked ground between
	var dust := _dust_field(f, body, x, y, z, masks, P + Vector2(0, 1500))
	var talus: Array = []
	var tal_img: Image = masks.get("talus")
	if tal_img != null:
		var tm := _sample_mask(f, x, y, z, tal_img, body.radius, P + Vector2(0, 1700))
		if not tm.is_empty():
			talus = _smoothstep(f, tm, 0.12, 0.45, P + Vector2(200, 1700))
	if dust.is_empty():
		# no erosion record: noise decides, at hundred-metre patches
		var n := _noise_on(f, norm, body.seed + 520, profile.continent_freq * 6.0, P + Vector2(0, 1500))
		dust = _smoothstep(f, _to01(f, n, P), 0.35, 0.65, P) if not n.is_empty() else _const(f, 0.6, P)
	var not_dust := _sub(f, _const(f, 1.0, P), dust, P)
	_weight_out(f, VoxelMaterials.STONE, _cutoff(f, _mul(f, base, dust, P), P), P + Vector2(600, 1500))
	if talus.is_empty():
		_weight_out(f, PaletteBuilder.SURFACE_ALT, _cutoff(f, _mul(f, base, not_dust, P), P), P + Vector2(600, 1600))
	else:
		var open := _mul(f, not_dust, _sub(f, _const(f, 1.0, P), talus, P), P)
		_weight_out(f, PaletteBuilder.SURFACE_ALT, _cutoff(f, _mul(f, base, open, P), P), P + Vector2(600, 1600))
		_weight_out(f, PaletteBuilder.SCREE, _cutoff(f, _mul(f, base, _mul(f, not_dust, talus, P), P), P), P + Vector2(600, 1700))

	# --- below the topsoil: level beds (absolute radius, slowly warped) alternating hard / soft, so a dig shows layers
	# and a cut through a ledge shows the bed the ledge is made of
	var band: Array = _strata(f, body, x, y, z, norm, profile)[1]
	var strata_w := _mul(f, bed, band, P)
	if not cliff_strata.is_empty():
		strata_w = _add(f, strata_w, cliff_strata, P)
	_weight_out(f, PaletteBuilder.STRATA_A, _cutoff(f, strata_w, P), P + Vector2(600, 1900))
	_weight_out(f, VoxelMaterials.BEDROCK,
		_cutoff(f, _mul(f, bed, _sub(f, _const(f, 1.0, P), band, P), P), P), P + Vector2(600, 2000))

## Where a secondary trait shows, 0..1, by its spatial mode. Coverage follows its weight (a 0.3 trait claims roughly a
## third of the open ground), with soft edges so the material height blend shapes the border.
static func _trait_region(f: VoxelGraphFunction, body: CelestialBody, t: PlanetTrait, weight: float, norm: int,
		masks: Dictionary, x: int, y: int, z: int, pos: Vector2) -> Array:
	var cov := clampf(weight * 1.1, 0.08, 0.6)
	var seed_t := body.seed + 800 + String(t.id).hash() % 1000
	var cut := 1.0 - cov
	var patches := _noise_on(f, norm, seed_t, 9.0, pos, FRACTAL_FBM, 3)
	if patches.is_empty():
		return []
	var p01 := _to01(f, patches, pos)
	# crater-floor traits sit in the real crater floors from the bake (CraterField), patchy within each floor
	if t.spatial == "crater_floor" and masks.get("crater_floor") != null:
		var floor_m := _sample_mask(f, x, y, z, masks.get("crater_floor"), body.radius, pos + Vector2(0, 120))
		if not floor_m.is_empty():
			p01 = _mul(f, floor_m, _add(f, _const(f, 0.6, pos), _mul(f, p01, _const(f, 0.4, pos), pos), pos), pos)
			return _smoothstep(f, p01, 0.45, 0.6, pos + Vector2(200, 0))
	match t.spatial:
		"lowland", "crater_floor", "cold_trap":
			# where fines and ice collect: the deposition record, broken up by patches
			var dust := _dust_field(f, body, x, y, z, masks, pos + Vector2(0, 120))
			if not dust.is_empty():
				p01 = _mul(f, _add(f, p01, dust, pos), _const(f, 0.5, pos), pos)
		"highland":
			var wear := _sample_mask(f, x, y, z, masks.get("wear"), body.radius, pos + Vector2(0, 120))
			if not wear.is_empty():
				p01 = _mul(f, _add(f, p01, _smoothstep(f, wear, 0.05, 0.4, pos), pos), _const(f, 0.5, pos), pos)
		"polar":
			var ny := f.create_node(VoxelGraphFunction.NODE_ABS, pos + Vector2(0, 200))
			f.add_connection(norm, 1, ny, 0)
			p01 = _mul(f, _add(f, p01, [ny, 0], pos), _const(f, 0.5, pos), pos)
		"fault":
			# narrow ridged lines: 1 - |noise| sharpened
			var lines := _noise_on(f, norm, seed_t + 7, 14.0, pos + Vector2(0, 200))
			if not lines.is_empty():
				p01 = _sub(f, _const(f, 1.0, pos), _abs(f, lines, pos), pos)
				cut = 1.0 - cov * 0.5
	return _smoothstep(f, p01, cut - 0.06, cut + 0.06, pos + Vector2(200, 0))

## Single-channel float copy of a `PlanetHeightmap`'s image.
##
## The baked PNG stores 16-bit height split across R (high byte) and G (low
## byte), because Godot loads 16-bit greyscale PNGs as FORMAT_L8 and would
## otherwise discard half the precision. `SdfSphereHeightmap` reads ONE
## channel, so the two bytes must be recombined into a real float image first.
static func heightmap_to_rf(hm: PlanetHeightmap) -> Image:
	if hm == null or hm.image == null:
		return null
	var src: Image = hm.image.get_image()
	if src == null:
		return null
	if src.is_compressed():
		src.decompress()
	var w := src.get_width()
	var h := src.get_height()
	if w <= 0 or h <= 0:
		return null
	var dst := Image.create_empty(w, h, false, Image.FORMAT_RF)
	for py in h:
		for px in w:
			var c := src.get_pixel(px, py)
			var v := (c.r * 255.0 * 256.0 + c.g * 255.0) / 65535.0
			dst.set_pixel(px, py, Color(v, v, v, 1.0))
	return dst

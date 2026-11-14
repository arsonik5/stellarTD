class_name BoulderScatter
extends RefCounted

## Places real rock geometry on the terrain surface.
##
## This is the half of the VRAGE3 model the heightmap cannot do. A height field
## has exactly one surface per direction, so it can make a slope steep but never
## undercut, and it cannot put a loose rock ON the ground - only a bump made OF
## the ground. That is why close-up terrain kept reading as a soft sheet no
## matter how good the material got: every silhouette in view belonged to the
## same continuous surface.
##
## The rocks are photogrammetry scans from Poly Haven's moon collection (CC0) -
## real lunar-analogue basalt, not generated shapes. Programmer art is forbidden
## here and this is the reason the rule exists: a procedural "rock" is
## recognisable as one instantly, because real weathering leaves fracture faces
## and cavities that a noise-displaced sphere never produces.
##
## Scanned at hand size (7-25 cm), scaled up into boulders. That is a real
## compromise - texel density drops as they grow - and it is why the scale range
## below stops where it does rather than making metre-scale monoliths out of
## something photographed at 10 cm.

const ROCK_DIR := "res://data/models/rocks"

## moon_rock_01 is deliberately excluded: 18.7k triangles against 3-10k for the
## rest, for no extra visible detail at boulder scale. In a MultiMesh that cost
## is paid on every instance.
const ROCKS := [
	"moon_rock_02", "moon_rock_03", "moon_rock_04",
	"moon_rock_05", "moon_rock_06", "moon_rock_07",
]

## Which LOD the boulders live at. 0 is the finest terrain LOD, so they exist
## only in the blocks nearest the camera and vanish beyond that - the only way a
## few thousand scanned meshes stay affordable.
const BOULDER_LOD := 0

## Texel density the ground material runs at, in pixels per metre.
##
## The regolith albedo is 1024 px tiled every 3.0 m, so 341 px/m. Boulders have
## to land near this or they read as a different asset sitting on the terrain
## rather than part of it - which is exactly what they were doing.
##
## A single global scale range cannot get there. The scans range from 0.08 m to
## 0.25 m with the same 1024 px texture, so one 6-20x range gave 205 px/m on the
## largest at 20x and 2133 px/m on the smallest at 6x - a TENFOLD spread across
## boulders sitting side by side. Each variant now derives its own base scale
## from its actual mesh bounds, so they agree with each other and with the
## ground.
const GROUND_PX_PER_M := 341.0
const ROCK_TEXTURE_PX := 1024.0

## Size variation around the texel-matched scale.
##
## Matching texel density exactly forces every boulder to the same physical size
## (1024 px / 341 px per m is 3.0 m, for any rock, always), which is obviously
## wrong. This is the deliberate compromise: boulders run 1.8 m to 4.5 m and
## their texel density varies between about 227 and 568 px/m - still a factor of
## 1.7 against the ground rather than the factor of 10 it was.
const SIZE_MIN := 0.6
const SIZE_MAX := 1.5

## Albedo tint applied to every rock, measured rather than guessed.
##
## Mean albedo of the six diffuse maps is RGB 132,126,114 against the ground's
## 102,102,103 - the boulders are 1.23x brighter and warm where the regolith is
## neutral. These are the per-channel ratios that close that gap.
const ALBEDO_TINT := Color(0.776, 0.813, 0.900)

## Instances per square metre at full density, before any filter.
##
## 0.02 covered the ground edge to edge - a boulder carpet, the same failure the
## rock-relief band hit twice before it was gated. A uniform amount of anything,
## high or low, is the mistake; what real ground has is scree where the debris
## collected and bare stretches between. 0.004 with a harder mask threshold
## gives clumps with space around them.
const DENSITY := 0.010

## Sunk into the ground rather than balanced on it. A rock resting exactly on
## the surface reads as a sticker; real ones are always partly buried.
const SINK := -0.25

## Boulders key off the TALUS mask - thermal deposition, the debris that fell
## off a face and came to rest below it - not the hydraulic deposition mask.
##
## This is where loose rock actually is. On an airless or arid world the
## dominant settings for boulders are scree aprons under scarps and crater
## walls, block fields where an outcrop has broken up in place, and lag
## surfaces where the fines have been winnowed away leaving the coarse fraction
## behind. Every one of those is gravity moving broken rock a short distance
## downslope. Where they are conspicuously ABSENT is fine sediment - silt fans,
## dust basins, playa - which is precisely what hydraulic deposition records.
##
## Scattering on hydraulic deposition put boulders in the one setting that
## should have none.
const MASK_THRESHOLD := 0.30
const MASK_FALLOFF := 0.22

## Slope band boulders rest in.
##
## Not a plain "under 38 degrees". A scree apron sits between roughly the angle
## of repose and the flat ground it runs out onto, and bare rock steeper than
## that sheds its debris rather than holding it. The lower bound matters as much
## as the upper: a boulder field on dead-level ground has nowhere for the
## material to have come FROM, which is what made the first version read as
## scattered rather than placed.
const MIN_SLOPE_DEGREES := 4.0
const MAX_SLOPE_DEGREES := 36.0
const SLOPE_FALLOFF_DEGREES := 7.0

## Builds the instancer for a body, or null if the rocks are missing.
##
## `mask` is the TALUS mask from the erosion bake - see MASK_THRESHOLD for why
## that one and not hydraulic deposition.
## `rules` = the archetype's ScatterSet (null = ScatterSet.legacy(), the pre-W5 talus-only placement).
## `slope` = the erosion bake's slope mask, used for the broken-edge term; `seed_value` decorrelates bodies.
static func build(radius: float, mask: Image, up_mode: int, rules: ScatterSet = null, slope: Image = null,
		seed_value: int = 0) -> VoxelInstancer:
	if rules == null:
		rules = ScatterSet.legacy()
		slope = null
	var library := VoxelInstanceLibrary.new()
	var added := 0
	for i in ROCKS.size():
		var mesh := _load_mesh(ROCKS[i])
		if mesh == null:
			continue
		var item := VoxelInstanceLibraryMultiMeshItem.new()
		item.name = ROCKS[i]
		item.lod_index = BOULDER_LOD
		item.mesh = mesh
		item.cast_shadow = RenderingServer.SHADOW_CASTING_SETTING_ON
		item.material_override = _tinted_material(mesh, rules.tint)
		# Convex hull per instance so the player collides with the rock instead
		# of walking through it. Cheap relative to the LOD 0 gate above, which
		# already keeps instance count down to what's near the camera.
		var hull := mesh.create_convex_shape(true, false)
		if hull != null:
			item.collision_layer = 1
			item.collision_mask = 1
			item.collision_shapes = [hull, Transform3D.IDENTITY]
		item.generator = _make_generator(radius, mask, i, _base_scale(mesh), rules, slope, seed_value)
		library.add_item(i + 1, item)
		added += 1
	if added == 0:
		push_warning("BoulderScatter: no rock meshes found under %s" % ROCK_DIR)
		return null

	var instancer := VoxelInstancer.new()
	instancer.name = "Boulders"
	instancer.library = library
	# Instances orient to the planet's radial up, not world Y. Getting this wrong
	# lays every boulder on its side on the far hemisphere.
	instancer.up_mode = up_mode
	return instancer

## Pebble litter (ScatterSet pebble_*): the boulder meshes shrunk to hand size, everywhere below 40 degrees, a
## light clump modulation, no collision and no shadow casting (SSAO grounds them; thousands of shadow casters
## would not). Separate instancer so boulders and pebbles stream and tune independently.
static func build_pebbles(radius: float, up_mode: int, rules: ScatterSet, seed_value: int = 0) -> VoxelInstancer:
	if rules == null or rules.pebble_density <= 0.0:
		return null
	var library := VoxelInstanceLibrary.new()
	var added := 0
	for i in ROCKS.size():
		var mesh := _load_mesh(ROCKS[i])
		if mesh == null:
			continue
		var item := VoxelInstanceLibraryMultiMeshItem.new()
		item.name = "pebble_" + ROCKS[i]
		item.lod_index = BOULDER_LOD
		item.mesh = mesh
		item.cast_shadow = RenderingServer.SHADOW_CASTING_SETTING_OFF
		item.material_override = _tinted_material(mesh, rules.tint)
		var g := VoxelInstanceGenerator.new()
		g.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
		g.density = rules.pebble_density / float(ROCKS.size())
		var bs := _base_scale(mesh)
		g.min_scale = bs * rules.pebble_size_min
		g.max_scale = bs * rules.pebble_size_max
		g.scale_distribution = VoxelInstanceGenerator.DISTRIBUTION_QUADRATIC
		g.random_rotation = true
		g.vertical_alignment = 1.0
		g.offset_along_normal = -0.03
		g.max_slope_degrees = 40.0
		g.max_slope_falloff_degrees = 8.0
		var noise := FastNoiseLite.new()
		noise.seed = seed_value * 17 + 300 + i
		noise.frequency = 0.05
		g.noise = noise
		g.noise_dimension = VoxelInstanceGenerator.DIMENSION_3D
		g.noise_threshold = -0.2
		g.noise_falloff = 0.4
		item.generator = g
		library.add_item(100 + i, item)
		added += 1
	if added == 0:
		return null
	var instancer := VoxelInstancer.new()
	instancer.name = "Pebbles"
	instancer.library = library
	instancer.up_mode = up_mode
	return instancer

static func _load_mesh(id: String) -> Mesh:
	var path := "%s/%s/%s_1k.gltf" % [ROCK_DIR, id, id]
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var root := scene.instantiate()
	var mesh := _first_mesh(root)
	root.queue_free()
	return mesh

## Scale that puts this particular rock at the ground's texel density.
##
## Taken from the mesh's own bounding box rather than a hardcoded table, so it
## stays correct if an asset is replaced or a new one added.
##
##     metres across at scale 1        = largest AABB axis
##     metres across at the target     = ROCK_TEXTURE_PX / GROUND_PX_PER_M
##     scale                           = the ratio of those
static func _base_scale(mesh: Mesh) -> float:
	var size := mesh.get_aabb().size
	var span: float = maxf(size.x, maxf(size.y, size.z))
	if span <= 0.0001:
		return 1.0
	return (ROCK_TEXTURE_PX / GROUND_PX_PER_M) / span

## The scanned material, tinted to sit with the ground.
##
## Duplicated rather than edited in place: the material comes off the imported
## glTF and is shared with anything else that loads the same asset, so writing
## to it would tint the source. albedo_color MULTIPLIES the albedo texture, so
## this darkens and cools the scan without touching its detail.
static func _tinted_material(mesh: Mesh, tint: Color = ALBEDO_TINT) -> Material:
	if mesh.get_surface_count() == 0:
		return null
	var src := mesh.surface_get_material(0)
	if src == null:
		return null
	var mat := src.duplicate()
	if mat is BaseMaterial3D:
		(mat as BaseMaterial3D).albedo_color = tint
	return mat

static func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null

## The placement rules for one rock variant.
##
## Each variant gets its own seed offset so the six do not all land in the same
## spots - otherwise every boulder in the world is a six-rock clump.
static func _make_generator(radius: float, mask: Image, variant: int,
		base_scale: float, rules: ScatterSet, slope: Image, seed_value: int) -> VoxelInstanceGenerator:
	var g := VoxelInstanceGenerator.new()
	g.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
	g.density = rules.density
	g.min_scale = base_scale * rules.size_min
	g.max_scale = base_scale * rules.size_max
	# Quadratic: small rocks are far more common than large ones, which is true
	# of every real scree field. A linear distribution gives an unnaturally even
	# spread of sizes.
	g.scale_distribution = VoxelInstanceGenerator.DISTRIBUTION_QUADRATIC
	g.random_rotation = true
	g.random_vertical_flip = true
	# Fully aligned to the surface normal. A boulder lying on a slope tilts with
	# it; standing them all upright on sloping ground is the other obvious tell.
	g.vertical_alignment = 1.0
	g.offset_along_normal = SINK
	g.min_slope_degrees = rules.min_slope_deg
	g.max_slope_degrees = rules.max_slope_deg
	g.min_slope_falloff_degrees = SLOPE_FALLOFF_DEGREES
	g.max_slope_falloff_degrees = SLOPE_FALLOFF_DEGREES

	if mask != null:
		if rules.edge_weight > 0.0 or rules.clump_strength > 0.0:
			g.noise_graph = _rule_graph(radius, mask, slope, variant, rules, seed_value)
		else:
			g.noise_graph = _mask_graph(radius, mask, variant)
		g.noise_dimension = VoxelInstanceGenerator.DIMENSION_3D
		g.noise_threshold = rules.threshold
		g.noise_falloff = rules.falloff
	return g

## W5 placement score (see ScatterSet): max(talus * w_t, smoothstep(slope, a, b) * w_e) * clump * variant noise.
## The clump field is a cellular-free trick: fbm at clump_m through a steep smoothstep, so rocks gather in clusters
## with bare ground between them instead of a uniform sprinkle (open item 5).
static func _rule_graph(radius: float, talus: Image, slope: Image, variant: int, rules: ScatterSet,
		seed_value: int) -> VoxelGraphFunction:
	var f := VoxelGraphFunction.new()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 60))
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 120))
	var score := _mul_c(f, _mask_value(f, x, y, z, radius, talus, Vector2(200, 0)), rules.talus_weight,
		Vector2(400, 0))
	if slope != null and rules.edge_weight > 0.0:
		var sv := _mask_value(f, x, y, z, radius, slope, Vector2(200, 300))
		var ss := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(400, 300))
		f.set_node_param(ss, 0, rules.edge_start)
		f.set_node_param(ss, 1, rules.edge_full)
		f.add_connection(sv[0], sv[1], ss, 0)
		var edge := _mul_c(f, [ss, 0], rules.edge_weight, Vector2(500, 300))
		var mx := f.create_node(VoxelGraphFunction.NODE_MAX, Vector2(600, 150))
		f.add_connection(score[0], score[1], mx, 0)
		f.add_connection(edge[0], edge[1], mx, 1)
		score = [mx, 0]
	if rules.clump_strength > 0.0:
		var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, Vector2(400, 500))
		var noise := FastNoiseLite.new()
		noise.seed = seed_value * 31 + 900
		noise.frequency = 1.0 / maxf(rules.clump_m, 1.0)
		noise.fractal_octaves = 2
		f.set_node_param(n, 0, noise)
		f.add_connection(x, 0, n, 0)
		f.add_connection(y, 0, n, 1)
		f.add_connection(z, 0, n, 2)
		var ss := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(500, 500))
		f.set_node_param(ss, 0, -0.15)
		f.set_node_param(ss, 1, 0.25)
		f.add_connection(n, 0, ss, 0)
		# clump = (1 - k) + k * smoothstep(noise): k = clump_strength
		var k := _mul_c(f, [ss, 0], rules.clump_strength, Vector2(600, 500))
		var base := _add_c(f, k, 1.0 - rules.clump_strength, Vector2(700, 500))
		var m := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(800, 300))
		f.add_connection(score[0], score[1], m, 0)
		f.add_connection(base[0], base[1], m, 1)
		score = [m, 0]
	# Per-variant modulation so the six rock types do not co-locate (same as the legacy graph).
	var vn := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, Vector2(800, 600))
	var vnoise := FastNoiseLite.new()
	vnoise.seed = 7000 + variant * 131 + seed_value
	vnoise.frequency = 0.004
	vnoise.fractal_octaves = 2
	f.set_node_param(vn, 0, vnoise)
	f.add_connection(x, 0, vn, 0)
	f.add_connection(y, 0, vn, 1)
	f.add_connection(z, 0, vn, 2)
	var modu := _add_c(f, _mul_c(f, [vn, 0], 0.45, Vector2(900, 600)), 1.0, Vector2(1000, 600))
	var out_mul := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(1100, 300))
	f.add_connection(score[0], score[1], out_mul, 0)
	f.add_connection(modu[0], modu[1], out_mul, 1)
	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(1200, 300))
	f.add_connection(out_mul, 0, out, 0)
	return f

## mask(direction) = sphere(radius) - heightmap(mask, radius, scale 1).
## Sampled on the radius-shell (normalize(p) * radius): the heightmap lookup drifts with altitude, so a mask read
## at the instance's own height is wrong on a world with hundreds of metres of relief (planet_graph_generator.gd
## _sample_mask has the measurement).
static func _mask_value(f: VoxelGraphFunction, x: int, y: int, z: int, radius: float, mask: Image,
		pos: Vector2) -> Array:
	var nrm := f.create_node(VoxelGraphFunction.NODE_NORMALIZE_3D, pos + Vector2(-300, 0))
	f.add_connection(x, 0, nrm, 0)
	f.add_connection(y, 0, nrm, 1)
	f.add_connection(z, 0, nrm, 2)
	var shell := []
	for i in 3:
		var c := f.create_node(VoxelGraphFunction.NODE_CONSTANT, pos + Vector2(-240, 60 * i))
		f.set_node_param(c, 0, radius)
		var m := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, pos + Vector2(-180, 60 * i))
		f.add_connection(nrm, i, m, 0)
		f.add_connection(c, 0, m, 1)
		shell.append(m)
	x = shell[0]
	y = shell[1]
	z = shell[2]
	var hm := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, pos)
	f.set_node_param(hm, 0, mask)
	f.set_node_param(hm, 1, radius)
	f.set_node_param(hm, 2, 1.0)
	f.add_connection(x, 0, hm, 0)
	f.add_connection(y, 0, hm, 1)
	f.add_connection(z, 0, hm, 2)
	var sp := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, pos + Vector2(0, 100))
	var r := f.create_node(VoxelGraphFunction.NODE_CONSTANT, pos + Vector2(-100, 160))
	f.set_node_param(r, 0, radius)
	f.add_connection(x, 0, sp, 0)
	f.add_connection(y, 0, sp, 1)
	f.add_connection(z, 0, sp, 2)
	f.add_connection(r, 0, sp, 3)
	var sub := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, pos + Vector2(120, 50))
	f.add_connection(sp, 0, sub, 0)
	f.add_connection(hm, 0, sub, 1)
	return [sub, 0]

static func _mul_c(f: VoxelGraphFunction, v: Array, k: float, pos: Vector2) -> Array:
	var c := f.create_node(VoxelGraphFunction.NODE_CONSTANT, pos + Vector2(-60, 40))
	f.set_node_param(c, 0, k)
	var m := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, pos)
	f.add_connection(v[0], v[1], m, 0)
	f.add_connection(c, 0, m, 1)
	return [m, 0]

static func _add_c(f: VoxelGraphFunction, v: Array, k: float, pos: Vector2) -> Array:
	var c := f.create_node(VoxelGraphFunction.NODE_CONSTANT, pos + Vector2(-60, 40))
	f.set_node_param(c, 0, k)
	var m := f.create_node(VoxelGraphFunction.NODE_ADD, pos)
	f.add_connection(v[0], v[1], m, 0)
	f.add_connection(c, 0, m, 1)
	return [m, 0]

## A VoxelGraphFunction that evaluates to the given mask.
##
## The generator filters on a noise graph rather than a plain Noise resource,
## which is what makes mask-driven scatter possible at all: the mask is an
## image, and no Noise resource can return it. Built with the same
## heightmap-minus-sphere trick as PlanetGraphGenerator._sample_mask, for the
## same reason - it reuses the one equirectangular projection that already has
## to be correct instead of adding another that can drift.
static func _mask_graph(radius: float, mask: Image, variant: int) -> VoxelGraphFunction:
	var f := VoxelGraphFunction.new()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 60))
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 120))

	# mask(direction), read on the nominal sphere (PlanetGraphGenerator.sample_mask_on_sphere: the node's early-out
	# returned 0 for anything more than ~2 m off its radius)
	var sm := PlanetGraphGenerator.sample_mask_on_sphere(f, x, y, z, mask, Vector2(200, 0))
	var sub: int = sm[0]

	# Broken up per variant so the six rock types do not co-locate. A plain
	# offset would shift all of them identically; multiplying in a coarse noise
	# with a different seed gives each its own patchiness.
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, Vector2(380, 220))
	var noise := FastNoiseLite.new()
	noise.seed = 7000 + variant * 131
	noise.frequency = 0.004
	noise.fractal_octaves = 2
	f.set_node_param(n, 0, noise)
	f.add_connection(x, 0, n, 0)
	f.add_connection(y, 0, n, 1)
	f.add_connection(z, 0, n, 2)

	# noise is -1..1; shifted to 0.55..1.45 so it modulates rather than gates.
	var k := f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(440, 300))
	f.set_node_param(k, 0, 0.45)
	var half := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(520, 220))
	f.add_connection(n, 0, half, 0)
	f.add_connection(k, 0, half, 1)
	var one := f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(520, 300))
	f.set_node_param(one, 0, 1.0)
	var modu := f.create_node(VoxelGraphFunction.NODE_ADD, Vector2(620, 220))
	f.add_connection(half, 0, modu, 0)
	f.add_connection(one, 0, modu, 1)

	var out_mul := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(760, 120))
	f.add_connection(sub, 0, out_mul, 0)
	f.add_connection(modu, 0, out_mul, 1)

	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(900, 120))
	f.add_connection(out_mul, 0, out, 0)
	return f

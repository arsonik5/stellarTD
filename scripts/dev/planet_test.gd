extends Node
## Planet regression test (design/05-planets.md). Boots the world once, waits for every planet's generator, then:
##   - HASH:   samples surface blocks on fixed directions and hashes SDF + materials. The "legacy" recipe (every
##             W2+ feature off) must reproduce the hash recorded before the TerrainRecipe extraction, per erosion
##             map - proving the band code has not drifted. A map not seen before records its hash and passes.
##   - CENSUS: dominant surface material over 240 Fibonacci directions per body; each body's archetype lists
##             which materials must appear.
##   - SHAPE:  relief statistics per body (slope percentiles at 2 m / 20 m) printed for the docs and bounded.
##   - TIME:   graph cost per 16^3 surface block, against a budget.
##   - POI:    POI placement respects minimum spacing and sits on the ground (once POIs exist).
##   godot --path . res://scenes/dev/planet_test.tscn [-- --record]    ("--record" overwrites stored hashes)
## Prints PASS/FAIL lines and "PLANET DONE fails=N".

const BASELINE_PATH := "res://data/dev/planet_hash_baseline.json"
const HASH_DIRS := 24
const CENSUS_DIRS := 240
## Budget per 16^3 surface block at LOD 0 on this machine class. Measured on the CPU container at ~4-9 ms
## before the world pass; the budget leaves room for the landform layers but catches a 3x regression.
const BLOCK_BUDGET_MS := 30.0

const MAT_NAMES := {0: "stone", 1: "iron", 2: "copper", 3: "block", 4: "sulfur", 5: "coal", 6: "silica",
	7: "crystal", 8: "frozen", 9: "sulfurflat", 10: "crystalfld", 11: "cliff", 12: "bedrock"}

var _fails := 0
var _record := false
var _world: Node

func _ready() -> void:
	_record = "--record" in OS.get_cmdline_user_args()
	_world = preload("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await get_tree().process_frame
	var loading := _world.get_node_or_null("LoadingScreen")
	if loading != null:
		loading.queue_free()
	var planets: Array[Planet] = []
	for n in get_tree().get_nodes_in_group("planet"):
		planets.append(n as Planet)
	var t0 := Time.get_ticks_msec()
	for p in planets:
		while not p.is_terrain_ready:
			await get_tree().process_frame
	print("planets ready in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	for p in planets:
		await _test_planet(p)
	print("PLANET DONE fails=%d" % _fails)
	get_tree().quit(_fails)

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _test_planet(p: Planet) -> void:
	var graph := p.terrain.generator as VoxelGeneratorGraph
	_check(graph != null, "%s: graph generator compiled" % p.name)
	if graph == null:
		return
	var eroded := p.get("_eroded_map") as Image
	var map_key := "noise" if eroded == null else "map%08x" % hash(eroded.get_data())
	print("%s: radius %.0f m, shape path = %s" % [p.name, p.radius_world(), map_key])
	await _test_hash(p, map_key)
	_test_census(p, graph)
	_test_shape(p, graph)
	_test_time(p, graph)
	_test_pois(p)

# --- HASH -------------------------------------------------------------------------------------------------------

func _surface_hash(p: Planet, graph: VoxelGeneratorGraph) -> int:
	var h := 0
	var buf := VoxelBuffer.new()
	buf.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_16_BIT)
	buf.set_channel_depth(VoxelBuffer.CHANNEL_WEIGHTS, VoxelBuffer.DEPTH_16_BIT)
	buf.create(16, 16, 16)
	var probe := VoxelBuffer.new()
	probe.create(2, 2, 2)
	for i in HASH_DIRS:
		var dir := _fib(i, HASH_DIRS)
		var r := _surface_radius(p, graph, probe, dir)
		var origin := Vector3i((dir * r).floor()) - Vector3i(8, 8, 8)
		graph.generate_block(buf, origin, 0)
		var acc := PackedInt32Array()
		acc.resize(16 * 16 * 16 * 3)
		var k := 0
		for x in 16:
			for y in 16:
				for z in 16:
					acc[k] = int(round(buf.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF) * 1000.0))
					acc[k + 1] = buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_INDICES)
					acc[k + 2] = buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_WEIGHTS)
					k += 3
		h = hash([h, hash(acc.to_byte_array())])
	return h

func _test_hash(p: Planet, map_key: String) -> void:
	# The legacy recipe must reproduce the pre-extraction generator exactly.
	# Loaded by path, not by class name, so this test also ran on the code BEFORE the recipe existed - that run
	# recorded the baseline the refactor is held to.
	var legacy: Resource = null
	if _has_recipe():
		legacy = load("res://scripts/world/terrain_recipe.gd").call("legacy")
	var graph: VoxelGeneratorGraph
	if legacy != null and p.has_method("build_generator_with_recipe"):
		graph = p.call("build_generator_with_recipe", legacy)
	else:
		graph = p.terrain.generator as VoxelGeneratorGraph
	var h := _surface_hash(p, graph)
	var base := _load_baseline()
	var key := "%s/%s" % [p.save_key(), map_key]
	print("%s: legacy surface hash %d (key %s)" % [p.name, h, key])
	if _record or not base.has(key):
		base[key] = h
		_save_baseline(base)
		_check(true, "%s: hash recorded for %s" % [p.name, key])
	else:
		_check(int(base[key]) == h, "%s: legacy recipe reproduces the recorded terrain hash" % p.name)

static func _has_recipe() -> bool:
	return ResourceLoader.exists("res://scripts/world/terrain_recipe.gd")

func _load_baseline() -> Dictionary:
	if not FileAccess.file_exists(BASELINE_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	return d if d is Dictionary else {}

func _save_baseline(d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/dev"))
	var f := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ", true))

# --- CENSUS -----------------------------------------------------------------------------------------------------

func _test_census(p: Planet, graph: VoxelGeneratorGraph) -> void:
	var probe := VoxelBuffer.new()
	probe.create(2, 2, 2)
	var mat := VoxelBuffer.new()
	mat.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_16_BIT)
	mat.set_channel_depth(VoxelBuffer.CHANNEL_WEIGHTS, VoxelBuffer.DEPTH_16_BIT)
	mat.create(1, 1, 1)
	var counts := {}
	var found := 0
	for i in CENSUS_DIRS:
		var dir := _fib(i, CENSUS_DIRS)
		var r := _surface_radius(p, graph, probe, dir)
		if r < 0.0:
			continue
		found += 1
		graph.generate_block(mat, Vector3i((dir * (r - 1.0)).floor()), 0)
		var m := TerrainDrill.dominant_from_packed(mat.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_INDICES),
			mat.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_WEIGHTS))
		counts[m] = int(counts.get(m, 0)) + 1
	var parts := []
	var keys := counts.keys()
	keys.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
	for m in keys:
		parts.append("%s %.0f%%" % [MAT_NAMES.get(m, str(m)), 100.0 * counts[m] / float(found)])
	print("%s census (%d/%d dirs): %s" % [p.name, found, CENSUS_DIRS, ", ".join(parts)])
	_check(found >= CENSUS_DIRS * 0.9, "%s: surface found on >= 90%% of directions" % p.name)
	var want: Array = p.expected_surface_materials() if p.has_method("expected_surface_materials") else []
	for m in want:
		_check(counts.has(m), "%s: surface census includes material %d" % [p.name, m])

# --- SHAPE ------------------------------------------------------------------------------------------------------

## Slope statistics over a few 60 m transects: how steep the ground is at 2 m and 20 m baselines.
func _test_shape(p: Planet, graph: VoxelGeneratorGraph) -> void:
	var probe := VoxelBuffer.new()
	probe.create(2, 2, 2)
	var s2: Array[float] = []
	var s20: Array[float] = []
	var heights: Array[float] = []
	var scale := Planet.VOXEL_SCALE
	for i in 12:
		var dir := _fib(i * 7 + 3, 96)
		var east := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		var line: Array[float] = []
		for k in 31:
			var d := (dir + east * (float(k) * 2.0 / scale) / p.body.radius).normalized()
			line.append((_surface_radius(p, graph, probe, d) - p.body.radius) * scale)
		heights.append(line[15])
		for k in 30:
			s2.append(rad_to_deg(atan(absf(line[k + 1] - line[k]) / 2.0)))
		for k in range(0, 21):
			s20.append(rad_to_deg(atan(absf(line[k + 10] - line[k]) / 20.0)))
	s2.sort()
	s20.sort()
	print("%s shape: slope@2m p50 %.1f p90 %.1f p99 %.1f deg | slope@20m p50 %.1f p90 %.1f deg | height span %.0f m" % [
		p.name, s2[s2.size() / 2], s2[int(s2.size() * 0.9)], s2[int(s2.size() * 0.99)],
		s20[s20.size() / 2], s20[int(s20.size() * 0.9)], heights.max() - heights.min()])
	_check(s2[int(s2.size() * 0.99)] < 89.0, "%s: no vertical tearing at 2 m (p99 < 89 deg)" % p.name)

# --- TIME -------------------------------------------------------------------------------------------------------

func _test_time(p: Planet, graph: VoxelGeneratorGraph) -> void:
	var probe := VoxelBuffer.new()
	probe.create(2, 2, 2)
	var buf := VoxelBuffer.new()
	buf.create(16, 16, 16)
	var origins: Array[Vector3i] = []
	for i in 16:
		var dir := _fib(i, 16)
		origins.append(Vector3i((dir * _surface_radius(p, graph, probe, dir)).floor()) - Vector3i(8, 8, 8))
	var t0 := Time.get_ticks_usec()
	for o in origins:
		graph.generate_block(buf, o, 0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / origins.size()
	print("%s: %.2f ms per 16^3 surface block" % [p.name, ms])
	_check(ms < BLOCK_BUDGET_MS, "%s: surface block under %.0f ms" % [p.name, BLOCK_BUDGET_MS])

# --- POI --------------------------------------------------------------------------------------------------------

func _test_pois(p: Planet) -> void:
	if not p.has_method("poi_sites"):
		return
	var sites: Array = p.poi_sites()
	var min_d := INF
	for i in sites.size():
		for j in range(i + 1, sites.size()):
			min_d = minf(min_d, (sites[i]["dir"] as Vector3).angle_to(sites[j]["dir"]) * p.radius_world())
	print("%s: %d POI sites, closest pair %.0f m" % [p.name, sites.size(), min_d])
	_check(sites.size() > 0, "%s: POI sites placed" % p.name)
	if sites.size() > 1:
		_check(min_d >= p.poi_min_spacing_m() * 0.999, "%s: POI spacing >= %.0f m" % [p.name, p.poi_min_spacing_m()])

# --- helpers ----------------------------------------------------------------------------------------------------

func _fib(i: int, n: int) -> Vector3:
	var y := 1.0 - (float(i) + 0.5) / float(n) * 2.0
	var rr := sqrt(maxf(1.0 - y * y, 0.0))
	var th := float(i) * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(th) * rr, y, sin(th) * rr).normalized()

## Surface radius (voxels) along `dir`, by bisection on the generator; -1 if no single crossing is bracketed.
func _surface_radius(p: Planet, graph: VoxelGeneratorGraph, buf: VoxelBuffer, dir: Vector3) -> float:
	var band := p.profile.max_deviation_voxels() + 8.0
	var lo := p.body.radius - band
	var hi := p.body.radius + band
	if _sdf(graph, buf, dir * lo) > 0.0 or _sdf(graph, buf, dir * hi) < 0.0:
		return -1.0
	for _i in 22:
		var mid := (lo + hi) * 0.5
		if _sdf(graph, buf, dir * mid) < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

func _sdf(graph: VoxelGeneratorGraph, buf: VoxelBuffer, q: Vector3) -> float:
	var base := Vector3i(floori(q.x), floori(q.y), floori(q.z))
	graph.generate_block(buf, base, 0)
	var t: Vector3 = q - Vector3(base)
	var c := VoxelBuffer.CHANNEL_SDF
	var x00: float = lerpf(buf.get_voxel_f(0, 0, 0, c), buf.get_voxel_f(1, 0, 0, c), t.x)
	var x10: float = lerpf(buf.get_voxel_f(0, 1, 0, c), buf.get_voxel_f(1, 1, 0, c), t.x)
	var x01: float = lerpf(buf.get_voxel_f(0, 0, 1, c), buf.get_voxel_f(1, 0, 1, c), t.x)
	var x11: float = lerpf(buf.get_voxel_f(0, 1, 1, c), buf.get_voxel_f(1, 1, 1, c), t.x)
	return lerpf(lerpf(x00, x10, t.y), lerpf(x01, x11, t.y), t.z)

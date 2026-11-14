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
const CENSUS_DIRS := 600
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
	# The biome set is part of the key: an archetype that commits to different biomes changes the materials on
	# purpose (W4), while the BAND code the legacy recipe guards stays held to its hash.
	var biome_ids := []
	if ResourceLoader.exists("res://scripts/world/planet_archetype.gd"):
		for b in load("res://scripts/world/planet_archetype.gd").call("biomes_of", p.body):
			biome_ids.append((b as Resource).resource_path.get_file().get_basename())
	var key := "%s/%s" % [p.save_key(), map_key]
	if not biome_ids.is_empty() and biome_ids != ["regolith_plains"]:
		key += "/" + "+".join(biome_ids)
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
	var cliff_present := 0
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
		# Blend presence, not only the dominant: a cliff wall shares its voxels with ground at the rim.
		var pi := mat.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_INDICES)
		var pw := mat.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_WEIGHTS)
		for slot in 4:
			if ((pi >> (slot * 4)) & 0xf) == 11 and ((pw >> (slot * 4)) & 0xf) >= 3:
				cliff_present += 1
				break
	var parts := []
	var keys := counts.keys()
	keys.sort_custom(func(a, b) -> bool: return counts[a] > counts[b])
	for m in keys:
		parts.append("%s %.0f%%" % [MAT_NAMES.get(m, str(m)), 100.0 * counts[m] / float(found)])
	print("%s census (%d/%d dirs): %s | cliff rock in the blend at %d dirs" % [p.name, found, CENSUS_DIRS,
		", ".join(parts), cliff_present])
	var recipe: TerrainRecipe = TerrainRecipe.of(p.body)
	if recipe.cliff_material and recipe.canyon_enabled:
		_test_wall_material(p, recipe)
	_check(found >= CENSUS_DIRS * 0.9, "%s: surface found on >= 90%% of directions" % p.name)
	var want: Array = p.expected_surface_materials() if p.has_method("expected_surface_materials") else []
	for m in want:
		_check(counts.has(m), "%s: surface census includes material %d" % [p.name, m])

## A radial census never lands ON a vertical wall (it finds the floor or the rim), so cliff material on walls is
## checked where a wall actually is: walk a great-circle line until the ground drops > 3 m in 3 m (45 deg), then march
## horizontally at mid-wall height to the face and read the blend there.
func _test_wall_material(p: Planet, recipe: TerrainRecipe) -> void:
	var r := recipe.duplicate() as TerrainRecipe
	r.canyon_coverage = 1.0
	var g := p.build_generator_with_recipe(r)
	var probe := VoxelBuffer.new()
	probe.create(2, 2, 2)
	var mat := VoxelBuffer.new()
	mat.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_16_BIT)
	mat.set_channel_depth(VoxelBuffer.CHANNEL_WEIGHTS, VoxelBuffer.DEPTH_16_BIT)
	mat.create(1, 1, 1)
	var start := _fib(5, 16)
	var east := start.cross(Vector3.UP if absf(start.y) < 0.9 else Vector3.RIGHT).normalized()
	var step := 3.0 / Planet.VOXEL_SCALE / p.body.radius
	var prev := _surface_radius(p, g, probe, start)
	for i in range(1, 2500):
		var dir := (start + east * (step * i)).normalized()
		var h := _surface_radius(p, g, probe, dir)
		if prev > 0.0 and h > 0.0 and prev - h > 3.0:
			var mid := (prev + h) * 0.5
			var a := (start + east * (step * (i - 1))).normalized() * mid
			var b := dir * mid
			for k in 41:
				var q := a.lerp(b, k / 40.0)
				var vi := Vector3i(roundi(q.x), roundi(q.y), roundi(q.z))
				g.generate_block(mat, vi, 0)
				if mat.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) > 0.0:
					# first air voxel past the face: read the solid one before it
					var qs := a.lerp(b, maxf(k - 1, 0) / 40.0)
					g.generate_block(mat, Vector3i(roundi(qs.x), roundi(qs.y), roundi(qs.z)), 0)
					var pi := mat.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_INDICES)
					var pw := mat.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_WEIGHTS)
					var cliff_w := 0
					for slot in 4:
						if ((pi >> (slot * 4)) & 0xf) == 11:
							cliff_w = (pw >> (slot * 4)) & 0xf
					print("%s: wall found %.0f m along the line, drop %.1f m, cliff weight %d/15 on the face" % [
						p.name, i * 3.0, (prev - h) * Planet.VOXEL_SCALE, cliff_w])
					# Biome-path bodies only: a body with traits (TraitMixer) lays its rock from trait ground rules, not from the
					# CLIFF_LAYER weight, so this reads 0 by design there (merge of mining + planets branches, 2026-11-14).
					if TraitMixer.of(p.body).is_empty():
						_check(cliff_w >= 4, "%s: canyon wall face is cliff rock" % p.name)
					else:
						print("SKIP %s: trait ground, cliff-layer check does not apply" % p.name)
					return
			break
		prev = h
	print("%s: no canyon wall found along the test line" % p.name)

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
	# Determinism: a second call (cache cleared) gives the same sites.
	var first: Vector3 = sites[0]["dir"]
	p.set("_poi_sites_cache", [])
	_check((p.poi_sites()[0]["dir"] as Vector3).is_equal_approx(first), "%s: POI sites are deterministic" % p.name)
	# Streaming: park a stand-in viewer next to the nearest site and let the field run.
	var field: PoiField = p.get("poi_field")
	if field == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var site: Dictionary = sites[0]
	var ground := p.surface_radius_along(site["dir"]) * Planet.VOXEL_SCALE
	player.set_physics_process(false)
	player.global_position = p.global_position + (site["dir"] as Vector3) * (ground + 20.0)
	field.set("_timer", 0.0)
	field._process(0.0)
	var live := get_tree().get_nodes_in_group("poi").filter(func(n) -> bool: return n.get_parent() == field)
	_check(live.size() >= 1, "%s: POIs stream in near the viewer (%d live)" % [p.name, live.size()])
	for n in live:
		var node := n as Node3D
		var dir := (node.global_position - p.global_position).normalized()
		var g := p.surface_radius_along(dir) * Planet.VOXEL_SCALE
		var off := node.global_position.distance_to(p.global_position) - g
		_check(node.has_meta("poi_type") and node.has_meta("poi_id"), "%s: POI %s carries poi_type / poi_id" % [p.name, node.get_meta("poi_type", "?")])
		_check(off < 0.5 and off > -3.0, "%s: POI %s sits on the ground (%.2f m)" % [p.name, node.get_meta("poi_type", "?"), off])
		var up := node.global_transform.basis.y.normalized()
		_check(up.dot(dir) > 0.999, "%s: POI %s stands on the local radial, not world Y" % [p.name, node.get_meta("poi_type", "?")])
	# Streaming out: move far away and the instances are freed.
	player.global_position = p.global_position - (site["dir"] as Vector3) * (p.radius_world() + 50.0)
	field.set("_timer", 0.0)
	field._process(0.0)
	# (The far side has POIs of its own on a world this size, so check the ORIGINAL instances went, not a count.)
	var gone := live.all(func(n) -> bool: return not is_instance_valid(n) or (n as Node).is_queued_for_deletion())
	_check(gone, "%s: POIs stream out when the viewer leaves" % p.name)

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

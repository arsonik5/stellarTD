extends Node
## Landform A/B: boots the world once and measures several TerrainRecipe variants on the SAME eroded map and the
## SAME patches, so a recipe change is judged by numbers rather than by eye (design/05-planets.md W2/W3).
##
##   godot --path . res://scenes/dev/landform_ab.tscn -- [--erosion-width=2048] [--variants=legacy,w2,...]
##
## Patches are scouted once on the legacy recipe: the flattest, the steepest, the lowest and the highest of 160
## Fibonacci directions (slope over 20 m, coarse-map height). For each class and variant it prints relief detrended
## over 4 m and 16 m (rms, metres) and slope at a 2 m baseline (p50 / p90, degrees). The targets (open items 1-2):
## flats CALMER under the new recipe, steep ground UNCHANGED or sharper.
## Writes hillshades of the first flat and first steep patch per variant to user://ab_<variant>_<class>.png.

const PATCH_M := 60.0
const RES := 40
const PER_CLASS := 3

var _planet: Planet
var _variants := ["legacy", "w2"]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variants="):
			_variants = Array(a.substr(11).split(","))
	var world := preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var loading := world.get_node_or_null("LoadingScreen")
	if loading != null:
		loading.queue_free()
	_planet = world.get_node("HomePlanet")
	for a in OS.get_cmdline_user_args():
		if a == "--moon":
			_planet = world.get_node("TestMoon")
	while not _planet.is_terrain_ready:
		await get_tree().process_frame
	var legacy := _planet.build_generator_with_recipe(TerrainRecipe.legacy())
	var classes := _scout(legacy)
	for v: String in _variants:
		var recipe := variant(v)
		var g := _planet.build_generator_with_recipe(recipe)
		if g == null:
			print("VARIANT %s: FAILED TO COMPILE" % v)
			continue
		for cls: String in classes:
			var stats := {"r4": 0.0, "r16": 0.0, "p50": 0.0, "p90": 0.0}
			var first := true
			for dir: Vector3 in classes[cls]:
				var h := _patch(g, dir)
				var s := _stats(h)
				for k in stats:
					stats[k] += s[k] / float(classes[cls].size())
				if first:
					_hillshade(h, "user://ab_%s_%s.png" % [v, cls])
					first = false
			print("AB %-10s %-6s rms4 %5.2f m  rms16 %5.2f m  slope2m p50 %5.1f p90 %5.1f deg" % [
				v, cls, stats.r4, stats.r16, stats.p50, stats.p90])
	print("LANDFORM_AB_DONE")
	get_tree().quit()

## Named recipe variants. Add one here per experiment so every measurement in the docs can be re-run by name.
static func variant(v: String) -> TerrainRecipe:
	var r := TerrainRecipe.legacy()
	# Every experiment runs on the fixed (shell) mask sampling; only "legacy" keeps the pre-fix lookup.
	r.mask_on_shell = v != "legacy"
	match v:
		"shell":        # legacy recipe + the mask-sampling fix alone, to see what the fix itself changes
			pass
		"w2":           # the shipped W2 setting (TerrainRecipe defaults for slope / altitude erosion)
			var d := TerrainRecipe.new()
			r.slope_erosion = d.slope_erosion
			r.altitude_erosion = d.altitude_erosion
			r.flat_detail_slope_damp = d.flat_detail_slope_damp
		"slope":
			r.slope_erosion = 0.7
		"slope_hi":
			r.slope_erosion = 0.9
		"alt":
			r.altitude_erosion = 0.5
		"both":
			r.slope_erosion = 0.7
			r.altitude_erosion = 0.5
			r.flat_detail_slope_damp = 0.6
		"terrace":
			r.terrace_enabled = true
			r.terrace_coverage = 1.0
			r.terrace_min_altitude = 0.0
		"canyon":
			r.canyon_enabled = true
			r.canyon_coverage = 1.0
		"spire":
			r.spire_enabled = true
			r.spire_density = 1.0
		"spire_dense":     # proof-of-mechanism: small cells, full coverage, so a 400-direction probe must hit
			r.spire_enabled = true
			r.spire_density = 1.0
			r.spire_spacing_m = 30.0
			r.spire_radius_m = 9.0
		"default":
			r = TerrainRecipe.new()
	return r

func _scout(g: VoxelGeneratorGraph) -> Dictionary:
	var buf := VoxelBuffer.new()
	buf.create(2, 2, 2)
	var rows := []
	for i in 160:
		var dir := _fib(i, 160)
		var east := _east(dir)
		var a := _height(g, buf, dir)
		var b := _height(g, buf, (dir + east * (20.0 / _planet.radius_world())).normalized())
		rows.append({"dir": dir, "slope": absf(b - a) / 20.0, "h": a})
	var out := {}
	rows.sort_custom(func(p, q) -> bool: return p.slope < q.slope)
	out["flat"] = rows.slice(0, PER_CLASS).map(func(r): return r.dir)
	out["steep"] = rows.slice(rows.size() - PER_CLASS).map(func(r): return r.dir)
	rows.sort_custom(func(p, q) -> bool: return p.h < q.h)
	out["low"] = rows.slice(0, PER_CLASS).map(func(r): return r.dir)
	out["high"] = rows.slice(rows.size() - PER_CLASS).map(func(r): return r.dir)
	return out

func _patch(g: VoxelGeneratorGraph, up: Vector3) -> PackedFloat32Array:
	var buf := VoxelBuffer.new()
	buf.create(2, 2, 2)
	var east := _east(up)
	var north := up.cross(east).normalized()
	var out := PackedFloat32Array()
	out.resize(RES * RES)
	var step := PATCH_M / float(RES - 1)
	var rw := _planet.radius_world()
	for iy in RES:
		for ix in RES:
			var u := (float(ix) - float(RES - 1) * 0.5) * step
			var v := (float(iy) - float(RES - 1) * 0.5) * step
			out[iy * RES + ix] = _height(g, buf, (up + east * (u / rw) + north * (v / rw)).normalized())
	return out

func _stats(h: PackedFloat32Array) -> Dictionary:
	var spacing := PATCH_M / float(RES - 1)
	var out := {}
	for pair in [["r4", 4.0], ["r16", 16.0]]:
		var r: int = maxi(int(round(pair[1] / spacing)), 1)
		var resid := 0.0
		var n := 0
		for iy in range(r, RES - r):
			for ix in range(r, RES - r):
				var sum := 0.0
				var count := 0
				for jy in range(iy - r, iy + r + 1):
					for jx in range(ix - r, ix + r + 1):
						sum += h[jy * RES + jx]
						count += 1
				var e: float = h[iy * RES + ix] - sum / float(count)
				resid += e * e
				n += 1
		out[pair[0]] = sqrt(resid / maxf(float(n), 1.0))
	var d: int = maxi(int(round(2.0 / spacing)), 1)
	var angles := []
	for iy in range(0, RES - d):
		for ix in range(0, RES - d):
			var dx: float = h[iy * RES + ix + d] - h[iy * RES + ix]
			var dy: float = h[(iy + d) * RES + ix] - h[iy * RES + ix]
			angles.append(rad_to_deg(atan(sqrt(dx * dx + dy * dy) / (d * spacing))))
	angles.sort()
	out["p50"] = angles[angles.size() / 2]
	out["p90"] = angles[int(angles.size() * 0.9)]
	return out

func _hillshade(h: PackedFloat32Array, path: String) -> void:
	var img := Image.create_empty(RES, RES, false, Image.FORMAT_RGB8)
	var spacing := PATCH_M / float(RES - 1)
	var light := Vector3(-0.6, 0.55, -0.6).normalized()
	for iy in RES:
		for ix in RES:
			var x0 := h[iy * RES + maxi(ix - 1, 0)]
			var x1 := h[iy * RES + mini(ix + 1, RES - 1)]
			var y0 := h[maxi(iy - 1, 0) * RES + ix]
			var y1 := h[mini(iy + 1, RES - 1) * RES + ix]
			var n := Vector3(-(x1 - x0) / (2.0 * spacing), 1.0, -(y1 - y0) / (2.0 * spacing)).normalized()
			var c := clampf(n.dot(light), 0.0, 1.0)
			img.set_pixel(ix, iy, Color(c, c, c))
	img.resize(RES * 6, RES * 6, Image.INTERPOLATE_NEAREST)
	img.save_png(path)

func _east(dir: Vector3) -> Vector3:
	return dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()

func _fib(i: int, n: int) -> Vector3:
	var y := 1.0 - (float(i) + 0.5) / float(n) * 2.0
	var rr := sqrt(maxf(1.0 - y * y, 0.0))
	var th := float(i) * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(th) * rr, y, sin(th) * rr).normalized()

## Height above the nominal radius in metres along `dir` (bisection on the generator).
func _height(g: VoxelGeneratorGraph, buf: VoxelBuffer, dir: Vector3) -> float:
	var band := _planet.profile.max_deviation_voxels() + 80.0
	var lo := _planet.body.radius - band
	var hi := _planet.body.radius + band
	for _i in 22:
		var mid := (lo + hi) * 0.5
		var p := dir * mid
		var base := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		g.generate_block(buf, base, 0)
		var t := p - Vector3(base)
		var c := VoxelBuffer.CHANNEL_SDF
		var s := lerpf(lerpf(lerpf(buf.get_voxel_f(0, 0, 0, c), buf.get_voxel_f(1, 0, 0, c), t.x),
			lerpf(buf.get_voxel_f(0, 1, 0, c), buf.get_voxel_f(1, 1, 0, c), t.x), t.y),
			lerpf(lerpf(buf.get_voxel_f(0, 0, 1, c), buf.get_voxel_f(1, 0, 1, c), t.x),
			lerpf(buf.get_voxel_f(0, 1, 1, c), buf.get_voxel_f(1, 1, 1, c), t.x), t.y), t.z)
		if s < 0.0:
			lo = mid
		else:
			hi = mid
	return ((lo + hi) * 0.5 - _planet.body.radius) * Planet.VOXEL_SCALE

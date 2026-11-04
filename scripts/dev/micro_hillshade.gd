extends Node

## Dev tool: what the ground actually looks like at ROCK SCALE.
##
##     godot --path . res://scenes/dev/micro_hillshade.tscn -- --tag=<name>
##     ... -- --tag=<name> --patch=120 --res=192
##
## Samples the generator's real isosurface over a small tangent patch and writes
## a hillshade of it, plus slope statistics over 1 m, 2 m and 8 m baselines.
##
## This exists because the other terrain instruments measure the wrong scale or
## the wrong thing. `_log_slope_profile` reads the erosion MAP, whose texel is
## ~12 m of arc, so a planet with no metre-scale relief at all scores healthy
## there. The capture harness renders the surface, which mixes shape with the
## material, the normal maps and the lighting - three ways for a shape change to
## look like it did nothing, or to look like it worked when it did not.
##
## Same patch, same sun, same seed between runs: the point is A/B, so the
## direction below is FIXED rather than taken from wherever the player spawns.

## Mid-latitude, not axis-aligned. An equirectangular map's texels converge at
## the poles and every direction-sampled noise field hits a lattice extremum on
## an axis, so both are the worst possible place to judge terrain from. Captures
## taken at the north pole cost a previous session several wrong diagnoses.
const SAMPLE_DIR := Vector3(0.190693, -0.476731, 0.858116)

## Bisection depth. 18 halvings over a ~3 km bracket resolves 12 mm, which has
## to sit well under the relief being measured or the instrument quantises the
## very thing it is looking for.
const BISECT_STEPS := 18

## The SDF is read TRILINEARLY from the voxel lattice, not evaluated at
## arbitrary points, and that is deliberate twice over.
##
## `generate_block` only ever evaluates the graph at integer voxel positions, so
## sampling it at a rounded position gives the same value for every point inside
## a cell. The first version of this tool did exactly that and produced pure
## salt-and-pepper noise at +-0.5 m - it was measuring the rounding, not the
## terrain, and reported a 36 degree median slope over 1 m on ground that renders
## smooth.
##
## Interpolating is also the more honest measurement: Transvoxel interpolates
## linearly along cell edges, so this is the surface the mesher will actually
## build, including the fact that detail finer than a voxel is lost.

var _tag := "x"
var _patch := 120.0
var _res := 160
var _scout := 0
var _dir := SAMPLE_DIR.normalized()

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--patch="):
			_patch = float(a.substr(8))
		elif a.begins_with("--res="):
			_res = int(a.substr(6))
		# Rock-band overrides, applied before the world builds its generators.
		# A look question answered by one run beats one answered by an edit.
		elif a.begins_with("--facet="):
			PlanetGraphGenerator.ROCK_FACET_BLEND_OVERRIDE = float(a.substr(8))
		elif a.begins_with("--steps="):
			PlanetGraphGenerator.ROCK_FACET_STEPS_OVERRIDE = float(a.substr(8))
		elif a.begins_with("--rockmul="):
			PlanetGraphGenerator.ROCK_AMPLITUDE_MULT = float(a.substr(10))
		elif a.begins_with("--cragmul="):
			PlanetGraphGenerator.CRAG_AMPLITUDE_MULT = float(a.substr(10))
		elif a.begins_with("--grainmul="):
			PlanetGraphGenerator.GRAIN_AMPLITUDE_MULT = float(a.substr(11))
		elif a.begins_with("--swellmul="):
			PlanetGraphGenerator.SWELL_AMPLITUDE_MULT = float(a.substr(11))
		elif a.begins_with("--cratermul="):
			PlanetGraphGenerator.CRATER_AMPLITUDE_MULT = float(a.substr(12))
		elif a.begins_with("--forcerock="):
			PlanetGraphGenerator.ROCK_FORCE_GATE = float(a.substr(12))
		elif a.begins_with("--warp="):
			Planet.EROSION_WARP_OVERRIDE = float(a.substr(7))
		elif a.begins_with("--density="):
			Planet.EROSION_DENSITY_OVERRIDE = float(a.substr(10))
		elif a.begins_with("--scout="):
			_scout = int(a.substr(8))
		elif a.begins_with("--dir="):
			var p := a.substr(6).split(",")
			if p.size() == 3:
				_dir = Vector3(float(p[0]), float(p[1]), float(p[2])).normalized()

	var world := preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	var loading := world.get_node_or_null("LoadingScreen")
	if loading != null:
		loading.queue_free()
	var planet: Planet = world.get_node("HomePlanet")
	while not planet.is_terrain_ready:
		await get_tree().process_frame

	var graph := planet.terrain.generator as VoxelGeneratorGraph
	if graph == null:
		print("RESULT: FAIL - generator is not a graph")
		get_tree().quit()
		return

	if _scout > 0:
		_scout_directions(planet, graph)
		get_tree().quit()
		return

	var t0 := Time.get_ticks_msec()
	var heights := _sample_patch(planet, graph)
	print("sampled %dx%d over %.0f m in %.1f s" % [
		_res, _res, _patch, (Time.get_ticks_msec() - t0) / 1000.0])

	_report(heights)
	_write_hillshade(heights)
	print("MICRO_HILLSHADE_DONE")
	get_tree().quit()

## Surface height above the nominal radius, in metres, over a tangent grid.
##
## The grid is laid out on the tangent plane and each point projected back to a
## direction, so spacing is real ground distance rather than anything angular.
func _sample_patch(planet: Planet, graph: VoxelGeneratorGraph) -> PackedFloat32Array:
	var buf := VoxelBuffer.new()
	buf.create(2, 2, 2)
	var radius: float = planet.body.radius
	var band: float = planet.profile.max_deviation_voxels()
	var scale: float = Planet.VOXEL_SCALE

	var up := _dir
	var east := up.cross(Vector3.UP).normalized()
	var north := up.cross(east).normalized()

	var out := PackedFloat32Array()
	out.resize(_res * _res)
	# Voxels of arc per grid step, so the patch is `_patch` metres across.
	var step: float = (_patch / scale) / float(_res - 1)
	for iy in _res:
		for ix in _res:
			var u: float = (float(ix) - float(_res - 1) * 0.5) * step
			var v: float = (float(iy) - float(_res - 1) * 0.5) * step
			var dir: Vector3 = (up + east * (u / radius) + north * (v / radius)).normalized()
			out[iy * _res + ix] = (_bisect(graph, buf, dir, radius, band) - radius) * scale
	return out

func _bisect(graph: VoxelGeneratorGraph, buf: VoxelBuffer, dir: Vector3,
		radius: float, band: float) -> float:
	var lo := radius - band - 4.0
	var hi := radius + band + 4.0
	if _sdf(graph, buf, dir * lo) > 0.0 or _sdf(graph, buf, dir * hi) < 0.0:
		return radius
	for _i in BISECT_STEPS:
		var mid := (lo + hi) * 0.5
		if _sdf(graph, buf, dir * mid) < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

## Trilinear sample of the SDF at an arbitrary point - see the note on
## BISECT_STEPS for why this is not a direct evaluation.
func _sdf(graph: VoxelGeneratorGraph, buf: VoxelBuffer, p: Vector3) -> float:
	var base := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	graph.generate_block(buf, base, 0)
	var t: Vector3 = p - Vector3(base)
	var c := VoxelBuffer.CHANNEL_SDF
	var x00: float = lerpf(buf.get_voxel_f(0, 0, 0, c), buf.get_voxel_f(1, 0, 0, c), t.x)
	var x10: float = lerpf(buf.get_voxel_f(0, 1, 0, c), buf.get_voxel_f(1, 1, 0, c), t.x)
	var x01: float = lerpf(buf.get_voxel_f(0, 0, 1, c), buf.get_voxel_f(1, 0, 1, c), t.x)
	var x11: float = lerpf(buf.get_voxel_f(0, 1, 1, c), buf.get_voxel_f(1, 1, 1, c), t.x)
	return lerpf(lerpf(x00, x10, t.y), lerpf(x01, x11, t.y), t.z)

## Finds ground of a given character to point the patch at.
##
## The fixed sample direction is gentle, dust-mantled ground. That is half the
## planet and exactly the half the rock bands are supposed to leave alone - so
## judging a rock change there measures a gate, not a band. This prints steep
## candidates to hardcode as a second fixed patch, because a direction chosen
## fresh each run would move whenever the terrain changed and destroy the A/B.
func _scout_directions(planet: Planet, graph: VoxelGeneratorGraph) -> void:
	var buf := VoxelBuffer.new()
	buf.create(2, 2, 2)
	var radius: float = planet.body.radius
	var band: float = planet.profile.max_deviation_voxels()
	var found: Array = []
	for i in _scout:
		var dir := _fibonacci_dir(i, _scout)
		# Poles and the axes are the worst ground to judge from: equirect texels
		# converge at one and every direction-sampled noise field hits a lattice
		# extremum at the other.
		if absf(dir.y) > 0.75 or absf(dir.x) > 0.95 or absf(dir.z) > 0.95:
			continue
		var r0 := _bisect(graph, buf, dir, radius, band)
		var tangent := dir.cross(Vector3.UP).normalized()
		var step: float = 20.0 / Planet.VOXEL_SCALE
		var d2: Vector3 = (dir + tangent * (step / radius)).normalized()
		var r2 := _bisect(graph, buf, d2, radius, band)
		found.append({"dir": dir,
			"slope": rad_to_deg(atan(absf(r2 - r0) * Planet.VOXEL_SCALE / 20.0))})
	found.sort_custom(func(a, b): return a["slope"] > b["slope"])
	print("steepest of %d directions, over a 20 m baseline:" % _scout)
	for i in mini(8, found.size()):
		var d: Vector3 = found[i]["dir"]
		print("  %5.1f deg  --dir=%.6f,%.6f,%.6f" % [
			found[i]["slope"], d.x, d.y, d.z])
	var mid: Dictionary = found[found.size() / 2]
	var md: Vector3 = mid["dir"]
	print("  median %5.1f deg  --dir=%.6f,%.6f,%.6f" % [mid["slope"], md.x, md.y, md.z])
	# The flat end matters as much as the steep one: the dune and grain bands only
	# act on gentle, dust-mantled ground, so judging them needs a patch that is
	# genuinely flat rather than merely not steep.
	print("flattest:")
	for i in mini(6, found.size()):
		var e: Dictionary = found[found.size() - 1 - i]
		var fd: Vector3 = e["dir"]
		print("  %5.1f deg  --dir=%.6f,%.6f,%.6f" % [e["slope"], fd.x, fd.y, fd.z])

func _fibonacci_dir(i: int, n: int) -> Vector3:
	var t := (float(i) + 0.5) / float(n)
	var phi := acos(1.0 - 2.0 * t)
	var theta := PI * (1.0 + sqrt(5.0)) * float(i)
	return Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))

## Slope over several baselines, plus how much relief survives once the landform
## is removed.
##
## The detrended figure is the one that answers "is there rock here": a steep
## hillside with a glass-smooth surface and a flat plain covered in broken rock
## can report the same raw slope, and they are opposite failures.
func _report(h: PackedFloat32Array) -> void:
	var spacing: float = _patch / float(_res - 1)
	print("grid spacing %.2f m" % spacing)
	for baseline in [1.0, 2.0, 8.0]:
		var d: int = maxi(int(round(baseline / spacing)), 1)
		var angles := PackedFloat32Array()
		for iy in range(0, _res - d):
			for ix in range(0, _res - d):
				var dx: float = h[iy * _res + ix + d] - h[iy * _res + ix]
				var dy: float = h[(iy + d) * _res + ix] - h[iy * _res + ix]
				angles.append(rad_to_deg(atan(sqrt(dx * dx + dy * dy) / (d * spacing))))
		if angles.is_empty():
			continue
		angles.sort()
		var mean := 0.0
		for a in angles:
			mean += a
		print("  %4.1f m baseline (%d cells): mean %5.1f  p50 %5.1f  p90 %5.1f  p99 %5.1f deg" % [
			baseline, d, mean / angles.size(), angles[int(angles.size() * 0.5)],
			angles[int(angles.size() * 0.9)], angles[int(angles.size() * 0.99)]])

	for radius_m in [4.0, 16.0]:
		var r: int = maxi(int(round(radius_m / spacing)), 1)
		var resid := 0.0
		var peak := 0.0
		var n := 0
		for iy in range(r, _res - r):
			for ix in range(r, _res - r):
				var sum := 0.0
				var count := 0
				for jy in range(iy - r, iy + r + 1):
					for jx in range(ix - r, ix + r + 1):
						sum += h[jy * _res + jx]
						count += 1
				var e: float = h[iy * _res + ix] - sum / float(count)
				resid += e * e
				peak = maxf(peak, absf(e))
				n += 1
		if n > 0:
			print("  detrended over %.0f m: rms %.2f m  peak %.2f m" % [
				radius_m, sqrt(resid / float(n)), peak])

## Least-squares plane fit, removed. What is left is the relief ON the slope
## rather than the slope itself.
func _detrend(h: PackedFloat32Array, spacing: float) -> PackedFloat32Array:
	var n := float(h.size())
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	var sxz := 0.0
	var syz := 0.0
	for iy in _res:
		for ix in _res:
			var xf := float(ix) * spacing
			var yf := float(iy) * spacing
			var zf := h[iy * _res + ix]
			sx += xf
			sy += yf
			sz += zf
			sxx += xf * xf
			syy += yf * yf
			sxy += xf * yf
			sxz += xf * zf
			syz += yf * zf
	# Normal equations for z = a*x + b*y + c.
	var m := [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]]
	var rhs := [sxz, syz, sz]
	var det: float = (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
		- m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
		+ m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
	if absf(det) < 1e-9:
		return h
	var a: float = (rhs[0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
		- m[0][1] * (rhs[1] * m[2][2] - m[1][2] * rhs[2])
		+ m[0][2] * (rhs[1] * m[2][1] - m[1][1] * rhs[2])) / det
	var b: float = (m[0][0] * (rhs[1] * m[2][2] - m[1][2] * rhs[2])
		- rhs[0] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
		+ m[0][2] * (m[1][0] * rhs[2] - rhs[1] * m[2][0])) / det
	var c: float = (m[0][0] * (m[1][1] * rhs[2] - rhs[1] * m[2][1])
		- m[0][1] * (m[1][0] * rhs[2] - rhs[1] * m[2][0])
		+ rhs[0] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])) / det
	var out := PackedFloat32Array()
	out.resize(h.size())
	for iy in _res:
		for ix in _res:
			out[iy * _res + ix] = h[iy * _res + ix] 				- (a * float(ix) * spacing + b * float(iy) * spacing + c)
	return out

## Shaded relief under a low sun, which is the only way to read a height field by
## eye - raw greyscale cannot tell a plateau from a blob.
##
## Vertical is NOT exaggerated. A previous session was fooled by a preview that
## stretched height 60x and made an 11-degree surface look like a mesa field.
func _write_hillshade(h_raw: PackedFloat32Array) -> void:
	var spacing: float = _patch / float(_res - 1)
	# The patch's overall tilt is removed first. Without this a 57 degree face
	# renders as flat white - every normal points the same way, the shading
	# saturates, and the rock detail the image exists to show is invisible. The
	# first version did exactly that and made a cliff look smoother than a plain.
	var h := _detrend(h_raw, spacing)
	var img := Image.create(_res, _res, false, Image.FORMAT_RGB8)
	var sun := Vector3(-0.6, 0.35, -0.6).normalized()
	for iy in _res:
		for ix in _res:
			var xm: int = mini(ix + 1, _res - 1)
			var ym: int = mini(iy + 1, _res - 1)
			var dx: float = (h[iy * _res + xm] - h[iy * _res + ix]) / spacing
			var dy: float = (h[ym * _res + ix] - h[iy * _res + ix]) / spacing
			var n := Vector3(-dx, 1.0, -dy).normalized()
			var lambert: float = clampf(n.dot(sun), 0.0, 1.0)
			var v: float = pow(clampf(0.08 + 0.92 * lambert, 0.0, 1.0), 1.0 / 2.2)
			img.set_pixel(ix, iy, Color(v, v, v))
	var path := "user://micro_%s_hill.png" % _tag
	img.save_png(path)
	print("wrote ", path)

extends Node
## Quick recipe-layer probe (headless is fine once the erosion cache exists):
##   godot --headless --path . res://scenes/dev/recipe_probe.tscn -- --erosion-width=2048
## For each named variant (landform_ab.gd variant()), prints how far the surface moves vs the legacy recipe over
## 400 directions: share of directions that moved > 0.5 m, mean |delta|, max raise, max cut. A layer that moves
## nothing is wired wrong; one that moves everything is gated wrong.

func _ready() -> void:
	var world := preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	world.get_node("LoadingScreen").queue_free()
	var planet: Planet = world.get_node("HomePlanet")
	for a in OS.get_cmdline_user_args():
		if a == "--moon":
			planet = world.get_node("TestMoon")
	while not planet.is_terrain_ready:
		await get_tree().process_frame
	var legacy := planet.build_generator_with_recipe(TerrainRecipe.legacy())
	var variants := ["terrace", "canyon", "spire", "w2", "default"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variants="):
			variants = Array(a.substr(11).split(","))
	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	var base := []
	for i in 400:
		base.append(_h(planet, legacy, buf, _fib(i, 400)))
	for v: String in variants:
		var recipe: TerrainRecipe = TerrainRecipe.of(planet.body) if v == "body" else load("res://scripts/dev/landform_ab.gd").variant(v)
		var g := planet.build_generator_with_recipe(recipe)
		if g != null and "--no-opt" in OS.get_cmdline_user_args():
			g.use_optimized_execution_map = false
			g.use_subdivision = false
			legacy.use_optimized_execution_map = false
			legacy.use_subdivision = false
		if g == null:
			print("PROBE %-8s COMPILE FAILED" % v)
			continue
		if "--dump" in OS.get_cmdline_user_args():
			for i in 3:
				var dir := _fib(i * 37, 400)
				var r0: float = planet.body.radius + base[i * 37] / Planet.VOXEL_SCALE
				var line := ""
				for dr in [-20, -10, -5, 0, 5, 10, 20]:
					var q := dir * (r0 + float(dr))
					var vi := Vector3i(roundi(q.x), roundi(q.y), roundi(q.z))
					legacy.generate_block(buf, vi, 0)
					var a := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
					g.generate_block(buf, vi, 0)
					line += "%+d: %.3f/%.3f  " % [dr, a, buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)]
				print("DUMP %s dir%d %s" % [v, i, line])
		var moved := 0
		var sum := 0.0
		var up := 0.0
		var down := 0.0
		for i in 400:
			var d: float = _h(planet, g, buf, _fib(i, 400)) - base[i]
			if absf(d) > 0.5:
				moved += 1
			sum += absf(d)
			up = maxf(up, d)
			down = minf(down, d)
		print("PROBE %-8s moved %3d/400  mean|d| %6.2f m  max raise %6.1f m  max cut %6.1f m" % [
			v, moved, sum / 400.0, up, down])
	print("RECIPE_PROBE_DONE")
	get_tree().quit()

func _fib(i: int, n: int) -> Vector3:
	var y := 1.0 - (float(i) + 0.5) / float(n) * 2.0
	var rr := sqrt(maxf(1.0 - y * y, 0.0))
	var th := float(i) * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(th) * rr, y, sin(th) * rr).normalized()

func _h(planet: Planet, g: VoxelGeneratorGraph, buf: VoxelBuffer, dir: Vector3) -> float:
	var band := planet.profile.max_deviation_voxels() + 80.0
	var lo := planet.body.radius - band
	var hi := planet.body.radius + band
	for _i in 20:
		var mid := (lo + hi) * 0.5
		var q := dir * mid
		g.generate_block(buf, Vector3i(roundi(q.x), roundi(q.y), roundi(q.z)), 0)
		if buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) < 0.0:
			lo = mid
		else:
			hi = mid
	return ((lo + hi) * 0.5 - planet.body.radius) * Planet.VOXEL_SCALE

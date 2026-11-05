extends Node
## Checks PlanetGraphGenerator._sample_mask against a direct read of the same image: the graph's value along a
## direction must equal the equirect pixel there. Run after an erosion cache exists:
##   godot --headless --path . res://scenes/dev/mask_probe.tscn -- --erosion-width=2048

func _ready() -> void:
	var world := preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	world.get_node("LoadingScreen").queue_free()
	var planet: Planet = world.get_node("HomePlanet")
	while not planet.is_terrain_ready:
		await get_tree().process_frame
	var img: Image = planet.get("_eroded_map")
	var masks: Dictionary = planet.get("_erosion_masks")
	for label in ["height", "slope", "talus"]:
		var im: Image = img if label == "height" else masks.get(label)
		if im == null:
			print("MASK %s: missing" % label)
			continue
		var g := VoxelGeneratorGraph.new()
		var f: VoxelGraphFunction = g.get_main_function()
		var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
		var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
		var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
		var m := PlanetGraphGenerator._sample_mask(f, x, y, z, im, planet.body.radius, Vector2())
		var raw := PlanetGraphGenerator._sub(f, [f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2()), 0],
			m, Vector2())
		var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
		f.add_connection(m[0], m[1], out, 0)
		print("MASK %s compile %s  image %dx%d fmt %d" % [label, g.compile(), im.get_width(), im.get_height(), im.get_format()])
		var buf := VoxelBuffer.new()
		buf.create(1, 1, 1)
		var s := ""
		for i in 6:
			var dir := Vector3(cos(i * 1.1), sin(i * 0.7) * 0.6, sin(i * 1.1)).normalized()
			var q := dir * planet.body.radius
			g.generate_block(buf, Vector3i(roundi(q.x), roundi(q.y), roundi(q.z)), 0)
			var lon := atan2(dir.z, dir.x)
			var lat := asin(dir.y)
			var px := int((lon / TAU + 0.5) * im.get_width()) % im.get_width()
			var py := clampi(int((0.5 - lat / PI) * im.get_height()), 0, im.get_height() - 1)
			s += "graph %.3f img %.3f | " % [buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF), im.get_pixel(px, py).r]
		print("MASK %s: %s" % [label, s])
		var rad := ""
		var d0 := Vector3(0.3, 0.5, 0.8).normalized()
		for off in [-600.0, -100.0, -10.0, -1.0, 0.0, 0.5, 1.0, 2.0, 10.0, 100.0, 600.0]:
			var q2 := d0 * (planet.body.radius + off)
			g.generate_block(buf, Vector3i(roundi(q2.x), roundi(q2.y), roundi(q2.z)), 0)
			rad += "%+.0f:%.3f " % [off, buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)]
		print("RADIAL %s: %s" % [label, rad])
	# Two heightmap nodes on the SAME image (the main shape node + _sample_mask), as the eroded shape builds them.
	var g2 := VoxelGeneratorGraph.new()
	var f2: VoxelGraphFunction = g2.get_main_function()
	var x2 := f2.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	var y2 := f2.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
	var z2 := f2.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
	var main := f2.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2())
	f2.set_node_param(main, 0, img)
	f2.set_node_param(main, 1, planet.body.radius - 0.5 * planet.profile.relief_voxels)
	f2.set_node_param(main, 2, planet.profile.relief_voxels)
	f2.add_connection(x2, 0, main, 0)
	f2.add_connection(y2, 0, main, 1)
	f2.add_connection(z2, 0, main, 2)
	var h := PlanetGraphGenerator._sample_mask(f2, x2, y2, z2, img, planet.body.radius, Vector2())
	# output = h01 * 1000 + main * 0 (main must stay reachable so it is compiled)
	var sum := PlanetGraphGenerator._add(f2, PlanetGraphGenerator._mul(f2, h, PlanetGraphGenerator._const(f2, 0.5, Vector2()), Vector2()),
		PlanetGraphGenerator._mul(f2, [main, 0], PlanetGraphGenerator._const(f2, 0.0, Vector2()), Vector2()), Vector2())
	var out2 := f2.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
	f2.add_connection(sum[0], sum[1], out2, 0)
	print("SHARED compile ", g2.compile())
	var b2 := VoxelBuffer.new()
	b2.create(1, 1, 1)
	var line := ""
	for i in 6:
		var dir := Vector3(cos(i * 1.1), sin(i * 0.7) * 0.6, sin(i * 1.1)).normalized()
		var q := dir * planet.body.radius
		g2.generate_block(b2, Vector3i(roundi(q.x), roundi(q.y), roundi(q.z)), 0)
		line += "%.3f " % (b2.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) * 2.0)
	print("SHARED h01 with a second node on the same image: ", line)
	# _build_terraces on a bare heightmap graph: does the surface move?
	var rec := TerrainRecipe.legacy()
	rec.terrace_enabled = true
	rec.terrace_coverage = 1.0
	rec.terrace_min_altitude = 0.0
	PlanetGraphGenerator._r = rec
	for part in ["delta", "gate", "final", "plain"]:
		PlanetGraphGenerator.DEBUG_PART = part if part in ["delta", "gate"] else ""
		var g4 := VoxelGeneratorGraph.new()
		var f4: VoxelGraphFunction = g4.get_main_function()
		var x4 := f4.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
		var y4 := f4.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
		var z4 := f4.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
		var n4 := f4.create_node(VoxelGraphFunction.NODE_NORMALIZE_3D, Vector2())
		f4.add_connection(x4, 0, n4, 0)
		f4.add_connection(y4, 0, n4, 1)
		f4.add_connection(z4, 0, n4, 2)
		var h4 := PlanetGraphGenerator._sample_mask(f4, x4, y4, z4, img, planet.body.radius, Vector2())
		var m4 := f4.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2())
		f4.set_node_param(m4, 0, img)
		f4.set_node_param(m4, 1, planet.body.radius - planet.profile.sea_level * planet.profile.relief_voxels)
		f4.set_node_param(m4, 2, planet.profile.relief_voxels)
		f4.add_connection(x4, 0, m4, 0)
		f4.add_connection(y4, 0, m4, 1)
		f4.add_connection(z4, 0, m4, 2)
		var piece: Array = [m4, 0]
		if part != "plain":
			piece = PlanetGraphGenerator._build_terraces(f4, planet.body, n4, planet.profile, [m4, 0], h4, Vector2())
		# scale small values up so the SDF channel's +-100 clip and quantisation do not hide them
		var o4 := f4.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
		f4.add_connection(piece[0], piece[1], o4, 0)
		g4.compile()
		var b4 := VoxelBuffer.new()
		b4.create(1, 1, 1)
		var l4 := ""
		for i in 6:
			var dir := Vector3(cos(i * 0.8), sin(i * 0.5) * 0.7, sin(i * 0.8)).normalized()
			var off: float = [158.5, 239.5, 78.7, 330.2, 80.6, 359.9][i]
			var q := dir * (planet.body.radius + off)
			g4.generate_block(b4, Vector3i(roundi(q.x), roundi(q.y), roundi(q.z)), 0)
			l4 += "%.3f " % b4.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
		print("PART %s: %s" % [part, l4])
	PlanetGraphGenerator.DEBUG_PART = ""
	for with_terrace in [false, true]:
		var g3 := VoxelGeneratorGraph.new()
		var f3: VoxelGraphFunction = g3.get_main_function()
		var x3 := f3.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
		var y3 := f3.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
		var z3 := f3.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
		var nrm := f3.create_node(VoxelGraphFunction.NODE_NORMALIZE_3D, Vector2())
		f3.add_connection(x3, 0, nrm, 0)
		f3.add_connection(y3, 0, nrm, 1)
		f3.add_connection(z3, 0, nrm, 2)
		var relief: float = planet.profile.relief_voxels
		var m3 := f3.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2())
		f3.set_node_param(m3, 0, img)
		f3.set_node_param(m3, 1, planet.body.radius - planet.profile.sea_level * relief)
		f3.set_node_param(m3, 2, relief)
		f3.add_connection(x3, 0, m3, 0)
		f3.add_connection(y3, 0, m3, 1)
		f3.add_connection(z3, 0, m3, 2)
		var sdf3: Array = [m3, 0]
		if with_terrace:
			var h3 := PlanetGraphGenerator._sample_mask(f3, x3, y3, z3, img, planet.body.radius, Vector2())
			sdf3 = PlanetGraphGenerator._build_terraces(f3, planet.body, nrm, planet.profile, sdf3, h3, Vector2())
		var o3 := f3.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
		f3.add_connection(sdf3[0], sdf3[1], o3, 0)
		if "--no-opt" in OS.get_cmdline_user_args():
			g3.use_optimized_execution_map = false
			g3.use_subdivision = false
			g3.sdf_clip_threshold = 100000.0
		g3.compile()
		var b3 := VoxelBuffer.new()
		b3.create(1, 1, 1)
		var l3 := ""
		for i in 8:
			var dir := Vector3(cos(i * 0.8), sin(i * 0.5) * 0.7, sin(i * 0.8)).normalized()
			var lo: float = planet.body.radius - 1200.0
			var hi: float = planet.body.radius + 1200.0
			for _k in 26:
				var mid := (lo + hi) * 0.5
				var q := dir * mid
				g3.generate_block(b3, Vector3i(roundi(q.x), roundi(q.y), roundi(q.z)), 0)
				if b3.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) < 0.0:
					lo = mid
				else:
					hi = mid
			l3 += "%.1f " % (lo - planet.body.radius)
		print("TERRACE_ISO %s surface: %s" % [with_terrace, l3])
	print("MASK_PROBE_DONE")
	get_tree().quit()

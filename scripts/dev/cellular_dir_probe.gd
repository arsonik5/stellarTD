extends SceneTree

## Dev probe: the crater cellular field exactly as PlanetGraphGenerator builds it -
## sampled on a normalised direction, period in direction units, properties set
## by name through Object.set(), which silently ignores a wrong name.
##
##     godot --path . --headless -s res://scripts/dev/cellular_dir_probe.gd

func _init() -> void:
	var noise: Object = ClassDB.instantiate("ZN_FastNoiseLite")
	noise.set("seed", 62)
	noise.set("period", 900.0 / 20000.0)
	noise.set("noise_type", 2)
	noise.set("fractal_type", 0)
	noise.set("cellular_distance_function", 0)
	noise.set("cellular_return_type", 1)
	noise.set("cellular_jitter", 0.6)
	for p in ["seed", "period", "noise_type", "fractal_type",
			"cellular_distance_function", "cellular_return_type", "cellular_jitter"]:
		print("readback %s = %s" % [p, str(noise.get(p))])

	var g := VoxelGeneratorGraph.new()
	var f: VoxelGraphFunction = g.get_main_function()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 60))
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 120))
	var nm := f.create_node(VoxelGraphFunction.NODE_NORMALIZE_3D, Vector2(100, 60))
	f.add_connection(x, 0, nm, 0)
	f.add_connection(y, 0, nm, 1)
	f.add_connection(z, 0, nm, 2)
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, Vector2(200, 0))
	f.set_node_param(n, 0, noise)
	f.add_connection(nm, 0, n, 0)
	f.add_connection(nm, 1, n, 1)
	f.add_connection(nm, 2, n, 2)
	# Output the raw value scaled x10 so the SDF channel's fixed-point range does
	# not flatten a field that lives in -1..0.
	var k := f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(200, 120))
	f.set_node_param(k, 0, 10.0)
	var mul := f.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(300, 0))
	f.add_connection(n, 0, mul, 0)
	f.add_connection(k, 0, mul, 1)
	var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(400, 0))
	f.add_connection(mul, 0, out, 0)
	print("compile: ", g.compile().get("success", false))

	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	var lo := INF
	var hi := -INF
	var base := Vector3(-0.635046, 0.498000, 0.590519).normalized() * 20000.0
	var east := base.normalized().cross(Vector3.UP).normalized()
	var vals := []
	for i in 80:
		var p := base + east * float(i) * 25.0
		g.generate_block(buf, Vector3i(p.round()), 0)
		var v := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) / 10.0
		lo = minf(lo, v)
		hi = maxf(hi, v)
		vals.append("%.3f" % v)
	print("2 km of surface at 25 m steps:")
	print(" ".join(vals))
	print("range %.4f .. %.4f" % [lo, hi])
	quit()

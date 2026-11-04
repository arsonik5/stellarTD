extends SceneTree

## Dev probe: shape and range of ZN_FastNoiseLite cellular DISTANCE and CELL_VALUE
## returns, and whether two nodes with one seed/period/jitter share cells.
##
##     godot --path . --headless -s res://scripts/dev/cellular_probe.gd

func _make(ret: int) -> Object:
	var n: Object = ClassDB.instantiate("ZN_FastNoiseLite")
	n.set("seed", 11)
	n.set("period", 64.0)
	n.set("noise_type", 2)
	n.set("fractal_type", 0)
	n.set("cellular_distance_function", 0)
	n.set("cellular_return_type", ret)
	n.set("cellular_jitter", 0.8)
	return n

func _graph(noise: Object) -> VoxelGeneratorGraph:
	var g := VoxelGeneratorGraph.new()
	var f: VoxelGraphFunction = g.get_main_function()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 60))
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 120))
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, Vector2(200, 0))
	f.set_node_param(n, 0, noise)
	f.add_connection(x, 0, n, 0)
	f.add_connection(y, 0, n, 1)
	f.add_connection(z, 0, n, 2)
	var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(400, 0))
	f.add_connection(n, 0, out, 0)
	g.compile()
	return g

func _init() -> void:
	var gd := _graph(_make(1))
	var gc := _graph(_make(0))
	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	var lo := INF
	var hi := -INF
	print("z   distance   cell_value")
	for zi in range(0, 200, 4):
		gd.generate_block(buf, Vector3i(10, 20, zi), 0)
		var d := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
		gc.generate_block(buf, Vector3i(10, 20, zi), 0)
		var c := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
		lo = minf(lo, d)
		hi = maxf(hi, d)
		print("%3d  %+.4f   %+.4f" % [zi, d, c])
	print("distance range over line: %.4f .. %.4f" % [lo, hi])
	# Wider range estimate over a plane.
	lo = INF
	hi = -INF
	for xi in range(0, 512, 7):
		for zi in range(0, 512, 7):
			gd.generate_block(buf, Vector3i(xi, 3, zi), 0)
			var d := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
			lo = minf(lo, d)
			hi = maxf(hi, d)
	print("distance range over 512x512 plane: %.4f .. %.4f" % [lo, hi])
	quit()

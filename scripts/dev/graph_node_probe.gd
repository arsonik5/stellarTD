extends SceneTree
## Probes VoxelGraphFunction node semantics that the docs leave ambiguous (run headless, prints and quits):
##   godot --headless --path . -s res://scripts/dev/graph_node_probe.gd
## STEPIFY: floor or round? (it is used for terraces in planet_graph_generator.gd)

func _init() -> void:
	var g := VoxelGeneratorGraph.new()
	var f: VoxelGraphFunction = g.get_main_function()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	var c := f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2())
	f.set_node_param(c, 0, 4.0)
	var d := f.create_node(VoxelGraphFunction.NODE_DIVIDE, Vector2())
	f.add_connection(x, 0, d, 0)
	f.add_connection(c, 0, d, 1)
	var st := f.create_node(VoxelGraphFunction.NODE_STEPIFY, Vector2())
	var one := f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2())
	f.set_node_param(one, 0, 1.0)
	f.add_connection(d, 0, st, 0)
	f.add_connection(one, 0, st, 1)
	var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
	f.add_connection(st, 0, out, 0)
	print(g.compile())
	var buf := VoxelBuffer.new()
	buf.create(12, 1, 1)
	g.generate_block(buf, Vector3i(-6, 0, 0), 0)
	var s := ""
	for i in 12:
		s += "%.2f->%.2f  " % [float(i - 6) / 4.0, buf.get_voxel_f(i, 0, 0, VoxelBuffer.CHANNEL_SDF)]
	print("STEPIFY x/4: ", s)
	quit()

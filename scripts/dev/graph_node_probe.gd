extends SceneTree
## Probes VoxelGraphFunction node semantics that the docs leave ambiguous (run headless, prints and quits):
##   godot --headless --path . -s res://scripts/dev/graph_node_probe.gd
## 1. STEPIFY: floor or round? (it is used for terraces in planet_graph_generator.gd)  -> ROUND
## 2. The terrace staircase T(u) - u built from the generator's own helpers, sampled along X.

func _init() -> void:
	_stepify()
	_terrace()
	quit()

func _stepify() -> void:
	var g := VoxelGeneratorGraph.new()
	var f: VoxelGraphFunction = g.get_main_function()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	var u := PlanetGraphGenerator._mul(f, [x, 0], PlanetGraphGenerator._const(f, 0.25, Vector2()), Vector2())
	var st := PlanetGraphGenerator._stepify(f, u, PlanetGraphGenerator._const(f, 1.0, Vector2()), Vector2())
	var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
	f.add_connection(st[0], st[1], out, 0)
	g.compile()
	print("STEPIFY x/4 -> ", _row(g))

func _terrace() -> void:
	var g := VoxelGeneratorGraph.new()
	var f: VoxelGraphFunction = g.get_main_function()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
	var u := PlanetGraphGenerator._mul(f, [x, 0], PlanetGraphGenerator._const(f, 0.25, Vector2()), Vector2())
	var k := PlanetGraphGenerator._stepify(f, u, PlanetGraphGenerator._const(f, 1.0, Vector2()), Vector2())
	var v := PlanetGraphGenerator._sub(f, u, k, Vector2())
	var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
	f.add_connection(v[0], v[1], out, 0)
	g.compile()
	print("TERRACE v = u - round(u) -> ", _row(g))

func _row(g: VoxelGeneratorGraph) -> String:
	var buf := VoxelBuffer.new()
	buf.create(12, 1, 1)
	g.generate_block(buf, Vector3i(-6, 0, 0), 0)
	var s := ""
	for i in 12:
		s += "%.2f:%.2f " % [float(i - 6) / 4.0, buf.get_voxel_f(i, 0, 0, VoxelBuffer.CHANNEL_SDF)]
	return s

extends SceneTree

## Dev probe: the falloff SHAPE of NODE_SPOTS_3D, and ZN_FastNoiseLite defaults.
##
##     godot --path . --headless -s res://scripts/dev/spots_probe.gd
##
## A crater profile applied to the spot value inherits every crease the spot
## value has. If the falloff is linear in distance it has a crease at the rim
## and a cone tip at the centre, and a profile that does not cancel both draws
## rings - the failure the old crater_curve produced.

func _init() -> void:
	var g := VoxelGeneratorGraph.new()
	var f: VoxelGraphFunction = g.get_main_function()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 60))
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 120))
	var sp := f.create_node(VoxelGraphFunction.NODE_SPOTS_3D, Vector2(200, 0))
	f.set_node_param(sp, 0, 7)
	f.set_node_param(sp, 1, 64.0)
	f.set_node_param(sp, 2, 0.0)
	f.add_connection(x, 0, sp, 0)
	f.add_connection(y, 0, sp, 1)
	f.add_connection(z, 0, sp, 2)
	var r := f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(100, 200))
	f.set_node_param(r, 0, 20.0)
	f.add_connection(r, 0, sp, 3)
	var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2(400, 0))
	f.add_connection(sp, 0, out, 0)
	var res: Dictionary = g.compile()
	print("compile: ", res.get("success", false))

	# Jitter 0 puts each spot at its cell centre, so a line through (32,32,*)
	# with cell 64 crosses one spot centre at z=32.
	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	var prev := 0.0
	var prev_d := 0.0
	print("z  value  first-diff  second-diff")
	for zi in range(0, 65, 2):
		g.generate_block(buf, Vector3i(32, 32, zi), 0)
		var v := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
		var d := v - prev
		print("%2d  %.4f  %+.4f  %+.4f" % [zi, v, d, d - prev_d])
		prev_d = d
		prev = v

	var n: Object = ClassDB.instantiate("ZN_FastNoiseLite")
	for p in ["noise_type", "rotation_type_3d", "period", "fractal_type"]:
		print("ZN_FastNoiseLite.%s = %s" % [p, str(n.get(p))])
	for c in ClassDB.class_get_enum_list("ZN_FastNoiseLite"):
		print("enum ", c, ": ", ClassDB.class_get_enum_constants("ZN_FastNoiseLite", c))
	quit()

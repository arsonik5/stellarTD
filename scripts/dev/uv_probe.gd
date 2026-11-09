extends SceneTree
## Which equirectangular convention does NODE_SDF_SPHERE_HEIGHTMAP use? A test image with a known gradient, probed at
## known directions, compared with generate.glsl's (lon = atan2(z, x), lat = asin(y)).
func _init() -> void:
	var w := 512
	var h := 256
	var img := Image.create_empty(w, h, false, Image.FORMAT_RF)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color((float(x) + 0.5) / w, 0, 0))
	var img2 := Image.create_empty(w, h, false, Image.FORMAT_RF)
	for y in h:
		for x in w:
			img2.set_pixel(x, y, Color((float(y) + 0.5) / h, 0, 0))
	for which in [img, img2]:
		var g := VoxelGeneratorGraph.new()
		var f: VoxelGraphFunction = g.get_main_function()
		var nx := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
		var ny := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
		var nz := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
		var hm := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE_HEIGHTMAP, Vector2())
		f.set_node_param(hm, 0, which)
		f.set_node_param(hm, 1, 100000.0)
		f.set_node_param(hm, 2, 1.0)
		f.add_connection(nx, 0, hm, 0)
		f.add_connection(ny, 0, hm, 1)
		f.add_connection(nz, 0, hm, 2)
		var sp := f.create_node(VoxelGraphFunction.NODE_SDF_SPHERE, Vector2())
		var rc := f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2())
		f.set_node_param(rc, 0, 100000.0)
		f.add_connection(rc, 0, sp, 3)
		f.add_connection(nx, 0, sp, 0)
		f.add_connection(ny, 0, sp, 1)
		f.add_connection(nz, 0, sp, 2)
		var sub := f.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2())
		f.add_connection(sp, 0, sub, 0)
		f.add_connection(hm, 0, sub, 1)
		var out := f.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
		f.add_connection(sub, 0, out, 0)
		print(g.compile())
		var buf := VoxelBuffer.new()
		buf.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
		buf.create(1, 1, 1)
		var pairs := []
		if which == img:
			for i in range(-12, 13):
				pairs.append(Vector2(i * 15.0 - 0.001 * signf(i), 0.0))
		else:
			for i in range(-6, 7):
				pairs.append(Vector2(0.0, i * 14.9))
				pairs.append(Vector2(90.0, i * 14.9))
				pairs.append(Vector2(45.0, i * 14.9))
			for la in [80.0, 85.0, 88.0, -80.0, -85.0]:
				pairs.append(Vector2(30.0, la))
		for pr in pairs:
			var lon_deg: float = pr.x
			var lat_deg: float = pr.y
			if true:
				var lon := deg_to_rad(lon_deg)
				var lat := deg_to_rad(lat_deg)
				var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
				var pi := Vector3i((d * 100000.0).round())
				g.generate_block(buf, pi, 0)
				var v := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
				print("lon %4.0f lat %5.1f -> img %.5f   glsl u %.3f v %.3f" % [lon_deg, lat_deg, v, (lon + PI) / TAU, (PI * 0.5 - lat) / PI])
	quit()

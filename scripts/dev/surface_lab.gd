extends Node3D

## The real terrain shader on a flat patch, no planet, no streaming: one palette slot at full weight, from a body's
## trait mix (or a mix given on the command line), at eye height under a low sun. Checks shader features that need a
## particular trait (cracks, laminae) without baking or finding the right spot on a planet.
##     godot --path . res://scenes/dev/surface_lab.tscn -- mix=desert:0.7,rocky:0.3 slot=0 [tag=x] [h=1.7]
## Writes art_src/ingame/surface_<tag>.png.

func _ready() -> void:
	var mix_arg := "desert:0.7,rocky:0.3"
	var slot := 0
	var tag := "lab"
	var eye_h := 1.7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mix="):
			mix_arg = a.substr(4)
		elif a.begins_with("slot="):
			slot = int(a.substr(5))
		elif a.begins_with("tag="):
			tag = a.substr(4)
		elif a.begins_with("h="):
			eye_h = float(a.substr(2))
	var body := CelestialBody.new()
	body.seed = 1
	body.radius = 20000.0
	var ov := {}
	for part in mix_arg.split(","):
		var kv := part.split(":")
		ov[kv[0]] = float(kv[1])
	body.trait_override = ov

	var mat: ShaderMaterial = (load("res://scripts/world/voxel_terrain_material.tres") as ShaderMaterial).duplicate()
	var pal: Dictionary = SurfacePalette.build(body)
	for k in ["tint_rough", "extra", "grade", "far"]:
		mat.set_shader_parameter("pal_" + k, pal[k])
	mat.set_shader_parameter("tex_albedo", pal["albedo_array"])
	mat.set_shader_parameter("tex_normal", pal["normal_array"])
	mat.set_shader_parameter("planet_center", Vector3(0, -20000, 0))
	print("LAB mix %s slot %d crack size %.2f m  (%s)" % [mix_arg, slot, (pal["grade"] as PackedVector4Array)[slot].w,
		(pal["names"] as Array)[slot]])

	# 120 m patch, 1 m grid, every vertex carrying `slot` at full weight in the mesher's packed CUSTOM1 layout
	var n := 120
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var packed_i := slot | (slot << 8) | (slot << 16) | (slot << 24)
	var packed_w := 255
	var ci := _bits_to_float(packed_i)
	var cw := _bits_to_float(packed_w)
	for z in n:
		for x in n:
			for c in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				st.set_normal(Vector3.UP)
				st.set_custom(0, Color(ci, cw, 0, 0))
				st.add_vertex(Vector3(x + c.x - n * 0.5, 0, z + c.y - n * 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.position = Vector3(0, eye_h, 0)
	cam.look_at(Vector3(0, 0, -8.0), Vector3.UP)
	cam.make_current()
	for i in 20:
		await RenderingServer.frame_post_draw
	var path := "res://art_src/ingame/surface_%s.png" % tag
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("LAB wrote ", path)
	get_tree().quit()

static func _bits_to_float(bits: int) -> float:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, bits)
	return b.decode_float(0)

extends Node

## Dev: dig a trench in front of the player and screenshot it in each shader debug view (stretched-texture streaks).
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://art_src/ingame/streak_%s.png" % name
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", path)

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	await get_tree().create_timer(16.0).timeout
	var terrain: VoxelLodTerrain = planet.get("terrain")
	var cam := get_viewport().get_camera_3d()
	var vt := terrain.get_voxel_tool()
	vt.channel = VoxelBuffer.CHANNEL_SDF
	vt.mode = VoxelTool.MODE_REMOVE
	var up: Vector3 = PlanetPhysics.get_up(cam.global_position)
	var inv := terrain.global_transform.affine_inverse()
	var hit: VoxelRaycastResult = null
	hit = vt.raycast(inv * (cam.global_position + up * 30.0), inv.basis * -up, 200.0)
	print("hit: ", hit)
	if hit != null:
		var fwd := -cam.global_transform.basis.z
		fwd = (fwd - up * fwd.dot(up)).normalized()
		var p := Vector3(hit.position)
		var lf: Vector3 = (inv.basis * fwd).normalized()
		var ld: Vector3 = (inv.basis * -up).normalized()
		# a slanted trench running away from the player, down into the ground
		for i in 14:
			vt.do_sphere(p + lf * (3.0 + float(i) * 0.8) + ld * float(i) * 0.35, 1.8)
	await get_tree().create_timer(2.5).timeout
	if OS.get_environment("NOSHADOW") != "":
		for l in get_tree().root.find_children("*", "Light3D", true, false):
			print("light ", l, " shadow ", l.shadow_enabled)
			l.shadow_enabled = false
	var mat = terrain.material
	print("material: ", mat, " ", mat.get_class() if mat != null else "")
	# own camera, looking along the trench from above and behind, with a lamp
	var c2 := Camera3D.new()
	add_child(c2)
	var fl: Vector3 = (-cam.global_transform.basis.z)
	fl = (fl - up * fl.dot(up)).normalized()
	var base: Vector3 = terrain.to_global(Vector3(hit.position))
	c2.global_position = base + up * 4.0 - fl * 1.0
	c2.look_at(base + fl * 8.0 - up * 3.0, up)
	c2.make_current()
	var lamp := OmniLight3D.new()
	lamp.omni_range = 40.0
	lamp.light_energy = 6.0
	add_child(lamp)
	lamp.global_position = base + up * 5.0 + fl * 3.0
	for mode in [0, 1, 2, 3, 4]:
		mat.set_shader_parameter("debug_view", mode)
		await get_tree().create_timer(0.3).timeout
		await _shot("v%d" % mode)
	print("STREAK_DONE")
	get_tree().quit()

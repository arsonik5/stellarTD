extends Node

## Dev check: does ore READ in the ground? Finds the nearest deposit of each ore type, moves the player above it,
## digs a pit down to it and photographs the pit walls under the sun and under the helmet lamp.
##     godot --path . res://scenes/dev/ore_look.tscn -- tag=r1      (needs a window, not --headless)
## Writes art_src/ingame/ore_<tag>_<ore>_<sun|lamp>.png.
const OUT := "res://art_src/ingame"
var tag := "r0"

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/ore_%s_%s.png" % [OUT, tag, name]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", path)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	var player: Node3D = null
	for i in 900:  # the loading screen stays up until the spawn is resolved
		await get_tree().create_timer(0.2).timeout
		player = get_tree().get_first_node_in_group("player")
		if player != null and player.is_spawn_resolved():
			break
	await get_tree().create_timer(3.0).timeout
	var terrain: VoxelLodTerrain = planet.get("terrain")
	var body = planet.get("body")
	var names := {}
	for ore in body.ore_types:
		names[ore.material_index] = ore.id
	var found: Array = OreScanner.scan(terrain, player.global_position, names)
	var seen := {}
	var vt := terrain.get_voxel_tool()
	vt.channel = VoxelBuffer.CHANNEL_SDF
	var inv := terrain.global_transform.affine_inverse()
	for h in found:
		var idx: int = h["material_index"]
		if seen.has(idx):
			continue
		seen[idx] = true
		var target: Vector3 = h["position"]
		var up: Vector3 = PlanetPhysics.get_up(target)
		print("ORE %s at %.0f m" % [names[idx], h["distance"]])
		# stand above it (frozen, so the pit doesn't swallow the player), let the terrain load around us
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.global_position = target + up * 60.0
		await get_tree().create_timer(6.0).timeout
		vt.mode = VoxelTool.MODE_REMOVE
		var hit: VoxelRaycastResult = vt.raycast(inv * (target + up * 60.0), inv.basis * -up, 120.0)
		if hit == null:
			print("  no ground above it")
			continue
		var surf: Vector3 = terrain.to_global(Vector3(hit.position))
		player.global_position = surf + up * 2.0
		await get_tree().create_timer(4.0).timeout
		# a wide pit from the surface down to the deposit, so its walls cut through the ore
		var depth := (surf - target).dot(up)
		var steps := int(max(depth, 0.0) / 1.5) + 2
		for i in steps:
			vt.do_sphere(inv * (surf - up * (float(i) * 1.5)), 4.0)
		vt.do_sphere(inv * target, 5.0)
		await get_tree().create_timer(2.0).timeout
		var side: Vector3 = up.cross(Vector3(0.3, 0.9, 0.2)).normalized()
		var cam := Camera3D.new()
		add_child(cam)
		# inside the cavity at the deposit, looking at its wall (sun can't reach: this is what the lamp shows)
		cam.global_position = target + up * 0.5 + side * 2.0
		cam.look_at(target + side * 5.0 - up * 1.0, up)
		cam.make_current()
		await get_tree().create_timer(1.0).timeout
		await _shot("%s_dark" % names[idx])
		var lamp := SpotLight3D.new()
		lamp.spot_range = 32.0
		lamp.spot_angle = 30.0
		lamp.light_energy = 3.0
		lamp.light_color = Color("fff1dc")
		lamp.spot_attenuation = 0.8
		cam.add_child(lamp)
		await get_tree().create_timer(0.5).timeout
		await _shot("%s_lamp" % names[idx])
		cam.queue_free()
		if seen.size() >= 4:
			break
	print("ORE_LOOK_DONE")
	get_tree().quit()

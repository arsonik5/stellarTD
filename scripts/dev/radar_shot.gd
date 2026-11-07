extends Node

## Dev check for the radar minigame: opens it, adds a trace dead ahead, locks, screenshots both screens.
##     godot --path . res://scenes/dev/radar_shot.tscn      (needs a window, not --headless)
const OUT := "res://art_src/ingame"

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/radar_%s.png" % [OUT, name]
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
	var body = planet.get("body")
	var names := {}
	var depths := {}
	for ore in body.ore_types:
		names[ore.material_index] = ore.id
		depths[ore.id] = Vector2(ore.depth_min, ore.depth_max)
	var hud = get_tree().get_first_node_in_group("scanner_hud")
	var cam := get_viewport().get_camera_3d()
	hud.call("scan_from", terrain, cam.global_position, names, depths)
	print("radar open: ", hud.call("is_radar_open"), " contacts ", hud.get("_contacts").size())
	# A trace dead ahead on the tuned ore, plus two off to the sides.
	var fwd := -cam.global_transform.basis.z
	var up: Vector3 = (cam.global_position - planet.global_position).normalized()
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right: Vector3 = fwd.cross(up).normalized()
	var want: String = hud.get("_ore_order")[hud.get("_sel")]
	for off in [[0.0, 640.0, 7], [-35.0, 900.0, 3], [48.0, 1300.0, 12], [10.0, 420.0, 4]]:
		hud.get("_contacts").append({"position": cam.global_position + (fwd * cos(deg_to_rad(off[0])) + right * sin(deg_to_rad(off[0]))) * off[1],
			"name": want, "samples": off[2], "lit": 0.0})
	await get_tree().create_timer(1.2).timeout
	await _shot("scope")
	print("candidate: ", not hud.call("_candidate").is_empty())
	print("lock ok: ", hud.call("lock_press"))
	await get_tree().create_timer(0.4).timeout
	await _shot("guide")
	print("RADAR_SHOT_DONE")
	get_tree().quit()

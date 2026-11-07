extends Node

## Dev: ground-aligned placement + oxygen post. Prints results.
##     godot --path . res://scenes/dev/post_probe.tscn
func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	await get_tree().create_timer(16.0).timeout
	var p: Node = get_tree().get_first_node_in_group("player")
	var item: Item = Inventory.get_item_def("chest")
	for k in 3:
		var pos: Vector3 = p.global_position + (-p.global_transform.basis.z) * (3.0 + k * 4.0)
		var pl: Dictionary = p.call("_ground_aligned_placement", pos, item)
		var xf: Transform3D = pl.transform
		var up: Vector3 = PlanetPhysics.get_up(xf.origin)
		print("placement %d valid=%s tilt vs sphere-up = %.1f deg" % [k, pl.valid, rad_to_deg(xf.basis.y.angle_to(up))])
	# oxygen post
	var post: Node3D = load("res://scenes/oxygen_post.tscn").instantiate()
	get_tree().current_scene.add_child(post)
	post.global_position = p.global_position + (-p.global_transform.basis.z) * 4.0
	await get_tree().process_frame
	print("prompt: ", post.call("prompt_text"))
	p.suit_o2 = 10.0
	post.call("interact")
	await get_tree().create_timer(1.0).timeout
	print("after 1 s plugged in: o2 = %.0f refilling=%s prompt=%s" % [p.suit_o2, p.o2_refilling, post.call("prompt_text")])
	p.global_position += Vector3(0, 0, 0) + (-p.global_transform.basis.z) * 40.0
	await get_tree().create_timer(0.5).timeout
	print("after walking 40 m away: hose=%s" % [p.o2_hose])
	print("POST_DONE")
	get_tree().quit()

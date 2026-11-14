extends Node

## Dev: run the suffocation sequence. Screenshots at 30% and 80%, then waits for death and respawn.
##     godot --path . res://scenes/dev/suffocate_probe.tscn   (needs a window)
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://art_src/ingame/suffocate_%s.png" % name))
	print("SHOT ", name)

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	await get_tree().create_timer(16.0).timeout
	var p: Node = get_tree().get_first_node_in_group("player")
	var start: Vector3 = p.global_position
	p.suit_o2 = 0.0
	p.o2_empty_time = 7.5
	await get_tree().create_timer(0.5).timeout
	await _shot("early")
	p.o2_empty_time = 20.0
	await get_tree().create_timer(0.5).timeout
	await _shot("late")
	p.o2_empty_time = 24.9
	while not p.dying:
		await get_tree().process_frame
	print("dying started")
	await get_tree().create_timer(2.0).timeout
	await _shot("death")
	while p.dying:
		await get_tree().process_frame
	print("respawned: o2 %.0f empty %.1f moved %.0f m" % [p.suit_o2, p.o2_empty_time, p.global_position.distance_to(start)])
	print("SUFFOCATE_DONE")
	get_tree().quit()

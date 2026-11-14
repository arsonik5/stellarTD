extends Node

## Dev reel for digging, on the real planet with the real player and real input: daylight, look at the ground a few
## metres ahead, hold the drill (LMB through Input, the same path a mouse press takes) and save frames through the
## wind-up, the bore and the spin-down.
##     godot --path . res://scenes/dev/dig_reel.tscn -- tag=r1 [pitch=-38] [hold=3.0] [lamp=1]
## Writes art_src/ingame/dig_<tag>_<nn>.png and prints DIGREEL lines (bites, ore paid, hole depth).
const OUT := "res://art_src/ingame"
var tag := "r0"
var pitch := -38.0
var hold := 3.0
var lamp := false
var _n := 0

func _shot() -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/dig_%s_%02d.png" % [OUT, tag, _n]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	_n += 1

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
		elif a.begins_with("pitch="):
			pitch = float(a.substr(6))
		elif a.begins_with("hold="):
			hold = float(a.substr(5))
		elif a.begins_with("lamp="):
			lamp = a.substr(5) == "1"
	var player: Node3D = null
	for i in 900:
		await get_tree().create_timer(0.2).timeout
		player = get_tree().get_first_node_in_group("player")
		if player != null and player.is_spawn_resolved():
			break
	await get_tree().create_timer(3.0).timeout
	# daylight: the star 40 degrees up, off to the side of the view
	var star := get_tree().current_scene.find_child("Star", true, false) as Node3D
	var planet := get_tree().get_first_node_in_group("planet") as Node3D
	if star != null and planet != null:
		var u := PlanetPhysics.get_up(player.global_position)
		var e := u.cross(Vector3.UP).normalized() if absf(u.dot(Vector3.UP)) < 0.9 else u.cross(Vector3.RIGHT).normalized()
		var sun := (u * sin(deg_to_rad(40.0)) + e * cos(deg_to_rad(40.0))).normalized()
		star.global_position = player.global_position + sun * star.global_position.distance_to(planet.global_position)
	if lamp:
		player.call("toggle_lamp")
	# drill in the left hand
	Inventory.set_slot({"kind": "hand", "side": "left"}, "mining_tool", 1)
	player.set("_pitch", deg_to_rad(pitch))
	player.camera.rotation.x = deg_to_rad(pitch)
	await get_tree().create_timer(1.0).timeout
	await _shot()                                                         # idle
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.parse_input_event(ev)
	var t0 := Time.get_ticks_msec()
	var times := [0.12, 0.25, 0.4, 0.55, 0.7, 0.9, 1.2, 1.6, 2.0, 2.5, 3.0]
	for t in times:
		if t > hold:
			break
		while (Time.get_ticks_msec() - t0) / 1000.0 < t:
			await get_tree().process_frame
		await _shot()
		var fx: MiningToolFx = player.get("_tool_fx")
		if fx != null:
			var eye: Vector3 = player.camera.global_position
			print("DIGREEL t=%.2f engaged=%s tip_eye=%.2f contact_eye=%.2f tip_contact=%.2f" % [t, fx.is_engaged(),
					fx.bit_tip().distance_to(eye), fx.last_contact().distance_to(eye), fx.bit_tip().distance_to(fx.last_contact())])
	while (Time.get_ticks_msec() - t0) / 1000.0 < hold:
		await get_tree().process_frame
	var up_ev := ev.duplicate()
	up_ev.pressed = false
	Input.parse_input_event(up_ev)
	await get_tree().create_timer(0.15).timeout
	await _shot()                                                         # spin-down
	await get_tree().create_timer(0.6).timeout
	await _shot()                                                         # the hole
	var ore := 0
	for id in ["ore_a", "ore_b", "ore_iron", "ore_copper", "ore_coal", "ore_silica", "ore_sulfur", "ore_crystal", "regolith", "stone"]:
		ore += Inventory.get_count(id)
	print("DIGREEL tag=%s frames=%d items_now=%d" % [tag, _n, ore])
	get_tree().quit()

extends Node
## UX tour: boots the REAL game from a throwaway save and photographs every screen, so UI and feel changes are
## judged on what the player actually sees. Starts at the main menu, then a fresh world: HUD, walking, each tool,
## inventory, build menu, build aiming, a machine panel, journal, pause menu, settings. Saves PNGs to
## art_src/ingame/ux/<tag>_<nn>_<name>.png, deletes its save, quits.
##   godot --path . res://scenes/dev/ux_tour.tscn -- tag=r1
const OUT := "res://art_src/ingame/ux"
const SLOT_NAME := "UX Tour (dev)"
var tag := "r0"
var _slot := ""
var _n := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# survive scene changes: hang off the root, not the current scene
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_run.call_deferred()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var path := "%s/%s_%02d_%s.png" % [OUT, tag, _n, name]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", path)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame

func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await _wait(1.0)
	await _shot("main_menu")
	await _menu_extras()
	for s: Dictionary in SaveManager.list_slots():
		if s.name == SLOT_NAME:
			SaveManager.delete_slot(s.id)
	_slot = SaveManager.create_slot(SLOT_NAME)
	SaveManager.begin_session(_slot, SaveManager.read_state(_slot))
	get_tree().change_scene_to_file("res://scenes/world.tscn")
	await _wait(0.6)
	await _shot("loading")
	var player: Node = null
	for i in 900:
		await _wait(0.2)
		player = get_tree().get_first_node_in_group("player")
		if player != null and player.is_spawn_resolved():
			break
	if player == null or not player.is_spawn_resolved():
		print("UXTOUR FAIL spawn never resolved")
		_finish()
		return
	await _wait(2.0)
	await _shot("hud")
	DevConsole.call("_set_open", true)
	DevConsole.run("help")
	DevConsole.run("give iron 20")
	await _wait(0.4)
	await _shot("console")
	DevConsole.call("_set_open", false)
	Inventory.try_remove("ore_a", 20)
	await _wait(0.2)
	# walk forward 1.5 s for the bob/sway frames
	Input.action_press("ui_up")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	# feel probe: footsteps and camera bob range while walking, then sprinting
	var feel: Node = player.get("feel")
	var steps := [0]
	if feel != null:
		feel.stepped.connect(func(_l: bool) -> void: steps[0] += 1)
	var cam: Camera3D = player.camera
	var lo := 9.0
	var hi := -9.0
	for i in 40:
		await get_tree().process_frame
		lo = minf(lo, cam.position.y)
		hi = maxf(hi, cam.position.y)
	await _shot("walking")
	var walk_v: float = (player.velocity as Vector3).length()
	print("FEEL walk speed %.2f m/s, steps %d in 40 frames, camera y %.3f..%.3f" % [walk_v, steps[0], lo, hi])
	var sh := InputEventKey.new()
	sh.physical_keycode = KEY_SHIFT
	sh.keycode = KEY_SHIFT
	sh.pressed = true
	Input.parse_input_event(sh)
	steps[0] = 0
	await _wait(0.8)
	await _shot("sprinting")
	print("FEEL sprint speed %.2f m/s, steps %d in 0.8 s, fov %.1f" % [(player.velocity as Vector3).length(), steps[0], cam.fov])
	sh = sh.duplicate()
	sh.pressed = false
	Input.parse_input_event(sh)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(0.5)
	await _key(KEY_F)
	await _wait(0.4)
	await _shot("lamp")
	await _key(KEY_F)
	await _key(KEY_TAB)
	await _wait(0.4)
	await _shot("inventory")
	await _key(KEY_TAB)
	await _wait(0.3)
	await _key(KEY_C)
	await _wait(0.4)
	await _shot("build_menu")
	var ui := get_tree().get_first_node_in_group("build_ui")
	if ui != null:
		ui.call("_on_building_pressed", 1)
	player.set("_pitch", deg_to_rad(-25))
	player.camera.rotation.x = deg_to_rad(-25)
	await _wait(0.5)
	await _shot("build_aim")
	await _key(KEY_C)
	await _wait(0.3)
	# a machine panel: drop a smelter in front and open it the way E does
	var smelter_item: Item = Inventory.get_item_def("smelter")
	if smelter_item != null and smelter_item.building_scene != null:
		var b: Node3D = smelter_item.building_scene.instantiate()
		get_tree().current_scene.add_child(b)
		var p3 := player as Node3D
		var fwd: Vector3 = -p3.global_transform.basis.z
		b.global_transform = Transform3D(p3.global_transform.basis, p3.global_position + fwd * 4.0)
		await _wait(0.5)
		await _shot("machine_in_world")
		var bui := get_tree().get_first_node_in_group("building_ui")
		if bui != null:
			bui.show_for(b)
			await _wait(0.4)
			await _shot("machine_panel")
			bui.close()
	await _wait(0.3)
	await _key(KEY_J)
	await _wait(0.4)
	await _shot("journal")
	await _key(KEY_J)
	await _wait(0.3)
	await _key(KEY_ESCAPE)
	await _wait(0.4)
	await _shot("pause")
	await _pause_extras()
	await _key(KEY_ESCAPE)
	_finish()

## Hooks for screens that may or may not exist yet (settings, save manager). They look the nodes up by group.
func _menu_extras() -> void:
	var menu := get_tree().get_first_node_in_group("main_menu")
	if menu != null and menu.has_method("tour_pages"):
		for page: String in menu.tour_pages():
			menu.call("show_page", page)
			await _wait(0.4)
			await _shot("menu_" + page)

func _pause_extras() -> void:
	var menu := get_tree().get_first_node_in_group("pause_menu")
	if menu != null and menu.has_method("tour_pages"):
		for page: String in menu.tour_pages():
			menu.call("show_page", page)
			await _wait(0.4)
			await _shot("pause_" + page)

func _finish() -> void:
	SaveManager.end_session()
	if _slot != "":
		SaveManager.delete_slot(_slot)
	print("UXTOUR DONE shots=%d" % _n)
	get_tree().quit()

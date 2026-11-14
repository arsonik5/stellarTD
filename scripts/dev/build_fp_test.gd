extends Node3D
## Dev test for first-person building (2026-11-04): a real player and the real build menu on a flat floor.
## Enters build mode, checks the menu opens with a free mouse, picks Foundation (menu must close, mouse captured),
## looks at the floor next to an existing foundation and left-clicks through real input events - a second
## foundation must appear snapped beside the first. Then picks Vacuum Pipe and lays one with two clicks, turning
## between them. Prints PASS/FAIL lines and saves art_src/ingame/build_fp_*.png.
## godot --path . res://scenes/dev/build_fp_test.tscn
const PLAYER := preload("res://scenes/player.tscn")
const BUILD_UI := preload("res://scenes/build_ui.tscn")
const OUT := "res://art_src/ingame"
var player: Node
var ui: Node
var _t := 0.0
var _step := 0
var _fails := 0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	cs.shape = shape
	floor_body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = shape.size
	mi.mesh = bm
	floor_body.add_child(mi)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	# one foundation already standing 6 m ahead, top face on the floor's surface level + its height
	var f_item: Item = Inventory.get_item_def("metal_foundation")
	var first: Node3D = f_item.building_scene.instantiate()
	add_child(first)
	first.global_position = Vector3(0, f_item.ghost_size.y * 0.5, -6)
	ui = BUILD_UI.instantiate()
	add_child(ui)
	player = PLAYER.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.05, 0)
	player.set("_spawn_resolved", true)
	Inventory.add("ore_a", 20)
	Inventory.add("refined_material", 10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _click(button: MouseButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = get_viewport().get_visible_rect().size * 0.5
		get_viewport().push_input(ev)

func _look(yaw_deg: float, pitch_deg: float) -> void:
	player.rotation = Vector3(0, deg_to_rad(yaw_deg), 0)
	player.set("_pitch", deg_to_rad(pitch_deg))
	player.camera.rotation.x = deg_to_rad(pitch_deg)

func _count(group: String) -> int:
	return get_tree().get_nodes_in_group(group).size()

func _segments() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("pipe"):
		if p is PipeSegment:
			n += 1
	return n

func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	match _step:
		0:
			player.call("_enter_build_mode")
			_check(ui.is_menu_open(), "build mode opens the menu")
			_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "menu frees the mouse")
			_shot("build_fp_menu")
			_step = 1
		1:
			if _t < 1.0: return
			ui.call("_on_building_pressed", 0)
			_check(not ui.is_menu_open(), "picking a building closes the menu")
			_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse captured again for aiming")
			_look(0, -18)
			_step = 2
		2:
			if _t < 1.6: return
			_step = 3
			var ghost: MeshInstance3D = player.get("_build_ghost")
			_check(ghost != null and ghost.visible, "ghost follows the crosshair")
			print("ghost at ", ghost.global_position if ghost != null else null)
			_shot("build_fp_ghost")
			var before := _count("foundation")
			_click(MOUSE_BUTTON_LEFT)
			await get_tree().process_frame
			_check(_count("foundation") == before + 1, "left click places a foundation (%d -> %d)" % [before, _count("foundation")])
		3:
			if _t < 2.2: return
			ui.call("select_item", "vacuum_pipe")   # by id: menu indices move when buildings are added
			ui.call("_on_building_pressed", ui.get("_selected_index"))
			_look(-30, -22)
			_step = 4
		4:
			if _t < 2.6: return
			_step = 5                           # set before awaiting: _physics_process keeps running meanwhile
			var before := _segments()
			_click(MOUSE_BUTTON_LEFT)           # pipe start
			_look(10, -22)
			await get_tree().create_timer(0.3).timeout
			_click(MOUSE_BUTTON_LEFT)           # pipe end
			await get_tree().process_frame
			_check(_segments() >= before + 1, "two clicks lay a pipe run (%d -> %d)" % [before, _segments()])
		5:
			if _t < 3.4: return
			_shot("build_fp_after")
			_click(MOUSE_BUTTON_RIGHT)          # drops the pipe run
			_click(MOUSE_BUTTON_RIGHT)          # leaves build mode
			_step = 6
		6:
			pass
	if _step == 6:
			if _t < 3.8: return
			_check(not player.get("_build_mode"), "right click leaves build mode")
			print("BUILDFP DONE fails=%d" % _fails)
			get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, n]))

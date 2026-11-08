extends Node3D
## Dev test for pipe runs (PipeRoute) and dismantling, with a real player, the real build menu and real machines on
## a flat floor. Drives the same click handler LMB uses (player._pipe_click) with exact points. Checks:
##   straight run = axis legs + tight 90 degree knee; a connected end refuses a second pipe; an inlet can't start one
##   a run leaves a machine port straight for PipeRoute.PORT_STUB and enters the next port straight
##   items flow smelter -> pipes -> chest; curved runs bend wide (radius > the tight knee)
##   dismantle refunds the cost (+ contents) and removes it; a wide knee survives save/load
## Shots: art_src/ingame/pipe_route_<n>.png.   godot --path . res://scenes/dev/pipe_route_test.tscn
const PLAYER := preload("res://scenes/player.tscn")
const BUILD_UI := preload("res://scenes/build_ui.tscn")
const OUT := "res://art_src/ingame"
var player: Node
var ui: Node
var _fails := 0
var _pipe_item: Item

func _check(ok: bool, what: String) -> void:
	print("PIPEROUTE %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/pipe_route_%s.png" % [OUT, n]))

func _pipes() -> Array[PipeSegment]:
	var out: Array[PipeSegment] = []
	for p in get_tree().get_nodes_in_group("pipe"):
		if p is PipeSegment and not p.is_queued_for_deletion():
			out.append(p)
	return out

func _place(scene: String, at: Vector3, yaw_deg: float, id: String) -> Node3D:
	var n: Node3D = load(scene).instantiate()
	add_child(n)
	n.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at)
	SaveManager.mark_placed(n, id)
	return n

func _click(p: Vector3) -> void:
	player.call("_pipe_click", _pipe_item, p)

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.4, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.4
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
	ui = BUILD_UI.instantiate()
	add_child(ui)
	player = PLAYER.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.05, 12)
	player.set("_spawn_resolved", true)
	Inventory.add("refined_material", 60)
	_pipe_item = Inventory.get_item_def("vacuum_pipe")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	player.call("_enter_build_mode")
	ui.call("_on_building_pressed", ui.BUILDABLE_RECIPES.find(ui.recipe_for("vacuum_pipe")))
	await get_tree().process_frame

	# 1. straight mode: one pipe on open ground, then carrying on round a corner = a second pipe with a tight knee
	player.set("_pipe_curved", false)
	var n0 := _pipes().size()
	_click(Vector3(-6, 0, 2))
	_click(Vector3(-6, 0, -2))                       # 1 pipe
	_click(Vector3(-2, 0, -6))                       # the run carries on: straight on, 90 degree knee, along
	var run1 := _pipes().slice(n0)
	_check(run1.size() == 3, "straight run = 3 pipes (got %d)" % run1.size())
	run1 = run1.slice(1)
	var knee_ok: bool = run1.size() == 2 and not run1[1]._knee.is_empty() and absf(float(run1[1]._knee.get("r", 0)) - PipeSegment.KNEE_RADIUS) < 0.01
	_check(knee_ok, "second pipe carries a tight 90 degree knee")
	player.set("_pipe_anchor_set", false)
	# 2. the old bug: the end of a pipe that already feeds the next must refuse another pipe; an inlet can't start one
	var joint_end: Vector3 = run1[0].output_ports()[0] if run1.size() == 2 else Vector3.ZERO
	var info: Dictionary = player.call("_pipe_end_info", joint_end, true)
	_check(not info.ok, "a connected pipe end refuses a second pipe (%s)" % info.get("why", ""))
	var inlet: Vector3 = run1[0].input_ports()[0] if not run1.is_empty() else Vector3.ZERO
	info = player.call("_pipe_end_info", inlet, true)
	_check(not info.ok, "a pipe inlet can't start a pipe (%s)" % info.get("why", ""))
	# carrying on from the open end goes on in its direction (no knee into the old pipe)
	var before := _pipes().size()
	var free_end: Vector3 = run1[1].output_ports()[0]
	var old_span: float = run1[1]._span_length
	_click(free_end)
	_click(free_end + Vector3(3, 0, -2))
	_check(_pipes().size() > before and absf(run1[1]._span_length - old_span) < 0.001, "carrying on never shortens the pipe it starts from")
	player.set("_pipe_anchor_set", false)

	# 3. machine to machine: smelter out port -> chest port, leaving and entering straight
	var smelter := _place("res://scenes/smelter.tscn", Vector3(6, 0, 2), 0.0, "smelter")
	var chest := _place("res://scenes/chest.tscn", Vector3(11, 0, -4), 0.0, "chest")
	await get_tree().process_frame
	var out_port: Dictionary = (smelter as Building).get_pipe_ports().filter(func(p): return p.kind == 1)[0]
	var chest_port: Dictionary = (chest as Building).get_pipe_ports()[0]
	print("smelter out ", out_port.point, " dir ", out_port.out, "   chest port ", chest_port.point, " dir ", chest_port.out)
	var route: Dictionary = player.call("_plan_pipe_run", out_port.point, chest_port.point)
	_check(route.ok, "smelter -> chest route plans (%s)" % route.get("why", "ok"))
	if route.ok:
		var pts: Array = route.points
		var first_leg: Vector3 = pts[1] - pts[0]
		_check(first_leg.normalized().dot(out_port.out) > 0.999 and first_leg.length() >= PipeRoute.PORT_STUB - 0.001,
				"leaves the smelter straight for %.2f m" % first_leg.length())
		var last_leg: Vector3 = pts[pts.size() - 1] - pts[pts.size() - 2]
		_check(last_leg.normalized().dot(-(chest_port.out as Vector3)) > 0.999 and last_leg.length() >= PipeRoute.PORT_STUB - 0.001,
				"enters the chest straight for %.2f m" % last_leg.length())
	before = _pipes().size()
	_click(out_port.point)
	_click(chest_port.point)
	var run3 := _pipes().slice(before)
	_check(not run3.is_empty() and not player.get("_pipe_anchor_set"), "laid %d pipes; ending on a machine closes the run" % run3.size())
	info = player.call("_pipe_end_info", out_port.point, true)
	_check(not info.ok, "the smelter's out port now refuses a second pipe")
	# items: one ore handed to the first pipe arrives in the chest
	if not run3.is_empty():
		run3[0].pipe_accept("ore_a")
	await get_tree().create_timer(6.0).timeout
	_check((chest as Building).get_inventory_count("ore_a") == 1, "an item rides the run into the chest (%d)" % (chest as Building).get_inventory_count("ore_a"))

	# 4. curved run: from the smelter's inlet side, one wide arc
	player.set("_pipe_curved", true)
	var in_port: Dictionary = (smelter as Building).get_pipe_ports().filter(func(p): return p.kind == -1)[0]
	before = _pipes().size()
	_click(Vector3(1, 0, -9))
	_click(in_port.point)
	var run4 := _pipes().slice(before)
	var widest := 0.0
	for p in run4:
		widest = maxf(widest, float(p._knee.get("r", 0.0)))
	_check(run4.size() >= 2 and widest > PipeSegment.KNEE_RADIUS + 0.3, "curved run bends wide (largest radius %.2f m, %d pipes)" % [widest, run4.size()])
	# a wide knee survives save / load
	if run4.size() >= 2:
		var curved_seg: PipeSegment = run4[run4.size() - 1] if not run4[run4.size() - 1]._knee.is_empty() else run4[1]
		var st := curved_seg.save_state()
		var copy: PipeSegment = _pipe_item.building_scene.instantiate()
		add_child(copy)
		copy.global_transform = curved_seg.global_transform
		copy.load_state(st)
		_check(absf(float(copy._knee.get("r", 0)) - float(curved_seg._knee.get("r", -1))) < 0.001, "knee radius saved and loaded")
		copy.free()
	player.set("_pipe_anchor_set", false)
	# overview shots (flow arrows show while a pipe is in hand)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(3, 15, 9)
	cam.look_at(Vector3(3, 0, -3))
	cam.make_current()
	for i in 3:
		await get_tree().process_frame
	await _shot("overview")
	cam.global_position = smelter.global_position + Vector3(2.8, 2.2, 3.5)
	cam.look_at(out_port.point + Vector3(0, 0.45, 0.6))
	await _shot("smelter_port")
	cam.global_position = Vector3(-6.5, 3.0, -1.0)
	cam.look_at(Vector3(-2, 0.45, -1.5))
	await _shot("straight_knee")
	cam.global_position = Vector3(4, 4, -12)
	cam.look_at(Vector3(4, 0.4, -6))
	await _shot("curved")
	cam.global_position = Vector3(-4.2, 1.3, 0.5)
	cam.look_at(Vector3(-6, 0.45, 0.0))
	await _shot("close")
	# the live preview of a run (mint, arrows) and of one that can't be laid (red)
	player.call("_exit_build_mode")                 # (in build mode the player redraws the preview from its own aim)
	var free_port: Vector3 = (chest as Building).get_pipe_ports()[1].point
	var ok_route: Dictionary = player.call("_plan_pipe_run", free_port, free_port + Vector3(4, 0, -5))
	player.call("_show_pipe_preview", ok_route, true)
	cam.global_position = free_port + Vector3(5.5, 3.5, 2.5)
	cam.look_at(free_port + Vector3(2, 0.4, -2.5))
	await _shot("preview")
	player.call("_show_pipe_preview", ok_route, false)
	await _shot("preview_bad")
	player.call("_hide_pipe_preview")

	# 5. dismantle: a pipe gives back its cost; the smelter gives back its cost plus what it holds
	player.call("_set_dismantle_mode", true)
	var victim: PipeSegment = run1[0]
	var rm_before := Inventory.get_count("refined_material")
	player.call("_set_dismantle_target", victim)
	player.call("_dismantle")
	await get_tree().process_frame
	_check(not is_instance_valid(victim) and Inventory.get_count("refined_material") == rm_before + 1, "dismantling a pipe refunds 1 Refined Material")
	(smelter as Building).add_input("ore_a", 3)
	var smelt_recipe: Recipe = ui.recipe_for("smelter")
	var first_in := smelt_recipe.input_ids[0]
	var had := Inventory.get_count(first_in)
	var ore_had := Inventory.get_count("ore_a")
	player.call("_set_dismantle_target", smelter)
	cam.global_position = smelter.global_position + Vector3(3.5, 2.5, 3.5)
	cam.look_at(smelter.global_position + Vector3(0, 1, 0))
	await _shot("dismantle")
	player.call("_dismantle")
	await get_tree().process_frame
	_check(not is_instance_valid(smelter) and Inventory.get_count(first_in) >= had + smelt_recipe.input_amounts[0] and Inventory.get_count("ore_a") >= ore_had + 1,
			"dismantling the smelter refunds its cost and its contents")
	player.call("_set_dismantle_mode", false)
	print("PIPEROUTE_DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

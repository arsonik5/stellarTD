extends Node
## Playthrough: the first arc played through the PLAYER'S OWN code paths on the real planet - the hand drill's
## raycast and bite, the scanner, build mode's ghost placement on real terrain, dismantle by crosshair, a machine
## fed and run on the clock, research bought, a drill placed through build mode, suffocation and respawn.
## Where a real player would press keys this calls the same functions the key handlers call.
##   godot --path . res://scenes/dev/playthrough_test.tscn          (tools/run_tests.sh playthrough)
const SLOT_NAME := "Playthrough Test (dev)"
var _slot := ""
var _fails := 0
var player: Node3D

func _ready() -> void:
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _look(pitch_deg: float) -> void:
	player.set("_pitch", deg_to_rad(pitch_deg))
	player.camera.rotation.x = deg_to_rad(pitch_deg)

func _run() -> void:
	await get_tree().process_frame
	for s: Dictionary in SaveManager.list_slots():
		if s.name == SLOT_NAME:
			SaveManager.delete_slot(s.id)
	_slot = SaveManager.create_slot(SLOT_NAME)
	SaveManager.begin_session(_slot, SaveManager.read_state(_slot))
	get_tree().change_scene_to_file("res://scenes/world.tscn")
	await _wait(0.5)
	for i in 1500:
		await _wait(0.2)
		player = get_tree().get_first_node_in_group("player")
		if player != null and player.is_spawn_resolved():
			break
	_check(player != null and player.is_spawn_resolved(), "the player lands on the planet")
	if player == null:
		return _finish()
	await _wait(1.0)
	Progression.reset()

	# 1. dig: look at the ground at your feet and hold the drill (the same _dig() the held LMB calls each tick).
	# Straight down, not ahead: the spawn can be a cliff edge, where ground ahead is out of the drill's 6 m reach.
	_look(-85)
	await _wait(0.2)
	var before := 0
	for id in ["stone", "ore_a", "ore_b", "ore_coal", "ore_silica", "sulfur", "ore_crystal"]:
		before += Inventory.get_count(id)
	for i in 120:
		player.call("_dig")
		if i % 6 == 0:
			await get_tree().physics_frame
	var after := 0
	for id in ["stone", "ore_a", "ore_b", "ore_coal", "ore_silica", "sulfur", "ore_crystal"]:
		after += Inventory.get_count(id)
	print("PLAY dug %d items" % (after - before))
	_check(after > before, "the hand drill cuts rock and pays items (%d)" % (after - before))

	# 2. scan: put the scanner in the right hand and ping (the tool's own trigger path)
	Inventory.set_slot({"kind": "hand", "side": "right"}, "scanner_tool", 1)
	var scanned := [false]
	GameEvents.scanned.connect(func(_k: Array) -> void: scanned[0] = true, CONNECT_ONE_SHOT)
	player.set("_scan_cooldown", 0.0)
	player.call("_dig")      # with the scanner equipped, the trigger scans
	await _wait(0.5)
	_check(scanned[0], "the scanner pings and reports to GameEvents")
	Inventory.set_slot({"kind": "hand", "side": "right"}, "building_tool", 1)

	# 3. build a crafter through build mode: pick it, aim the ghost at the ground, click
	Inventory.add("ore_a", 30)
	player.call("_toggle_build_mode")
	var ui := get_tree().get_first_node_in_group("build_ui")
	_check(bool(player.get("_build_mode")), "C opens build mode with the build tool in hand")
	ui.select_item("basic_crafter")
	player.call("on_build_picked")
	_look(-35)
	for i in 10:
		await get_tree().physics_frame
	var ore_before := Inventory.get_count("ore_a")
	var crafters_before := _count("basic_crafter")
	player.call("_place_building")
	await get_tree().process_frame
	_check(_count("basic_crafter") == crafters_before + 1, "the ghost places a crafter on the real terrain")
	_check(Inventory.get_count("ore_a") == ore_before - 5, "placing it spent its 5 iron ore")
	var crafter := _last("basic_crafter") as Building

	# 4. a locked building is refused with a reason
	ui.select_item("deposit_drill")
	player.call("on_build_picked")
	var hud := get_tree().get_first_node_in_group("compact_hud")
	player.call("_place_building")
	_check(String(hud.get("_toast").text).begins_with("Locked"), "a locked building is refused and the HUD says why ('%s')" % hud.get("_toast").text)

	# 5. run the crafter on the clock: feed it, switch auto on, wait
	if crafter != null:
		crafter.add_input("ore_a", 10)
		crafter.set_auto(0, true)
		# wait on the outcome, not a fixed time: under a CPU renderer the physics loop cannot always keep up with
		# a raised time scale, so "4 s at 4x" was sometimes only a few seconds of game time
		Engine.time_scale = 4.0
		for i in 240:
			await _wait(0.25)
			if crafter.get_inventory_count("refined_material") >= 4:
				break
		Engine.time_scale = 1.0
		_check(crafter.get_inventory_count("refined_material") >= 4, "the crafter makes iron ingots on its own (%d)" % crafter.get_inventory_count("refined_material"))

	# 6. research: first-time actions paid data; buy deep drilling and place a drill through build mode
	Progression.award("geology", 2, "test top-up")   # the scan above may have found nothing nearby
	_check(Progression.buy("r_deep_drilling"), "research Deep Drilling")
	Inventory.add("refined_material", 10)
	Inventory.add("refined_copper_ingot", 4)
	ui.select_item("deposit_drill")
	player.call("on_build_picked")
	player.rotate_object_local(Vector3.UP, deg_to_rad(70))
	for i in 10:
		await get_tree().physics_frame
	player.call("_place_building")
	await get_tree().process_frame
	_check(_count("deposit_drill") == 1, "the researched deposit drill places through build mode ('%s')" % hud.get("_toast").text)

	# 7. dismantle the crafter by crosshair: X, aim, hold
	if crafter != null and is_instance_valid(crafter):
		player.rotate_object_local(Vector3.UP, deg_to_rad(-70))
		player.call("_set_dismantle", true)
		var cam: Camera3D = player.camera
		var to := crafter.global_position + PlanetPhysics.get_up(crafter.global_position) * 0.8 - cam.global_position
		player.look_at(player.global_position + to, PlanetPhysics.get_up(player.global_position))
		_look(rad_to_deg(asin(clampf(to.normalized().dot(PlanetPhysics.get_up(cam.global_position)), -1.0, 1.0))))
		await get_tree().physics_frame
		var iron := Inventory.get_count("ore_a")
		var ingots := Inventory.get_count("refined_material")
		player.set("_dismantle_held", true)
		for i in 60:
			await get_tree().physics_frame
			if not is_instance_valid(crafter):
				break
		player.set("_dismantle_held", false)
		_check(not is_instance_valid(crafter), "holding LMB in dismantle mode takes the crafter down")
		_check(Inventory.get_count("ore_a") >= iron + 5 and Inventory.get_count("refined_material") > ingots, "dismantle refunds its cost and its ingots")
		player.call("_set_dismantle", false)
	player.call("_toggle_build_mode")

	# 8. suffocation: run the suit dry and wait - the player dies and comes back with air
	var v: PlayerVitals = player.get("vitals")
	player.set("suit_o2", 0.0)
	var died := [false]
	GameEvents.player_died.connect(func(c: String) -> void: died[0] = c == "suffocation", CONNECT_ONE_SHOT)
	Engine.time_scale = 8.0
	for i in 200:
		await _wait(0.25)
		if died[0]:
			break
	Engine.time_scale = 1.0
	_check(died[0], "an empty suit suffocates the player")
	await _wait(PlayerVitals.RESPAWN_DELAY + 0.5)
	_check(not v.dead and float(player.get("suit_o2")) > 290.0, "and they respawn with a full suit")
	_finish()

func _count(item_id: String) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("building"):
		if String(b.get_meta(SaveManager.ITEM_ID_META, "")) == item_id and not b.is_queued_for_deletion():
			n += 1
	return n

func _last(item_id: String) -> Node:
	var found: Node = null
	for b in get_tree().get_nodes_in_group("building"):
		if String(b.get_meta(SaveManager.ITEM_ID_META, "")) == item_id:
			found = b
	return found

func _finish() -> void:
	Engine.time_scale = 1.0
	if _slot != "":
		SaveManager.end_session()
		SaveManager.delete_slot(_slot)
	print("PLAYTHROUGH DONE fails=%d" % _fails)
	get_tree().quit(_fails)

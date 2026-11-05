extends Node
## Game test: boots the REAL world (planet, streaming, player spawn) from a throwaway save and drives the
## systems that only exist there: player vitals (fall damage, death, respawn), placing and dismantling a building
## on the real terrain, and a save -> reload round trip of the new state. Deletes its save and quits.
##   godot --path . res://scenes/dev/game_test.tscn        (tools/run_tests.sh game)
## Prints PASS/FAIL and "GAME DONE fails=N".
const SLOT_NAME := "Game Test (dev)"
var _slot := ""
var _fails := 0

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

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player")

func _boot(fresh: bool) -> Node3D:
	if fresh:
		for s: Dictionary in SaveManager.list_slots():
			if s.name == SLOT_NAME:
				SaveManager.delete_slot(s.id)
		_slot = SaveManager.create_slot(SLOT_NAME)
	if fresh:
		SaveManager.begin_session(_slot, SaveManager.read_state(_slot))
	else:
		SaveManager.open_slot(_slot)
	get_tree().change_scene_to_file("res://scenes/world.tscn")
	await _wait(0.5)
	for i in 1500:
		await _wait(0.2)
		var p := _player()
		if p != null and p.is_spawn_resolved():
			await _wait(1.0)
			return p
	return null

func _run() -> void:
	await get_tree().process_frame
	var player: Node3D = await _boot(true)
	_check(player != null, "real world boots and the player lands")
	if player == null:
		_finish()
		return
	var v: PlayerVitals = player.get("vitals")
	_check(v != null and v.has_respawn, "landing spot recorded as respawn point")
	_check(is_equal_approx(v.health.health, 100.0), "player starts at full health")

	# fall damage: a hard landing hurts, a jump does not
	v.on_landed(6.0)
	_check(is_equal_approx(v.health.health, 100.0), "a jump landing does no damage")
	v.on_landed(17.0)
	_check(v.health.health < 100.0 and v.health.health > 0.0, "a 17 m/s landing hurts but does not kill")

	# death and respawn: move away, die, come back at the landing spot with full health and air
	var home: Vector3 = v.respawn_transform.origin
	var up := PlanetPhysics.get_up(player.global_position)
	player.global_position += up * 3.0 + player.global_transform.basis.x * 25.0
	player.set("suit_o2", 0.0)
	var died := [false]
	GameEvents.player_died.connect(func(_c: String) -> void: died[0] = true, CONNECT_ONE_SHOT)
	Health.deal(player, 500.0, "env")
	_check(died[0] and v.dead, "lethal damage kills the player")
	await _wait(PlayerVitals.RESPAWN_DELAY + 0.5)
	_check(not v.dead and is_equal_approx(v.health.health, 100.0), "player respawns at full health")
	_check(player.global_position.distance_to(home) < 2.0, "respawn is at the landing spot (%.1f m)" % player.global_position.distance_to(home))
	# the suit drains 1 s per s outside, and 0.5 s passed since the respawn
	_check(float(player.get("suit_o2")) >= float(player.get("SUIT_O2_MAX")) - 2.0, "respawn refills the suit")

	# place a chest on the real ground in front of the player, then dismantle it for a refund
	await _wait(1.0)
	var item := Inventory.get_item_def("chest")
	var chest: Node3D = item.building_scene.instantiate()
	get_tree().current_scene.add_child(chest)
	var fwd := -player.global_transform.basis.z
	chest.global_transform = Transform3D(player.global_transform.basis, player.global_position + fwd * 3.0)
	SaveManager.mark_placed(chest, "chest")
	(chest as Building).add_input("ore_b", 9)
	var iron := Inventory.get_count("ore_a")
	_check(WorldObjects.dismantle(chest), "dismantle a chest in the real world")
	_check(Inventory.get_count("ore_a") == iron + 3 and Inventory.get_count("ore_b") >= 9, "refund = 3 iron ore + its 9 copper")

	await _test_drill(player)

	# save -> reload: vitals survive
	Health.deal(player, 30.0, "env")
	var hp := v.health.health
	var snap := _snapshot()
	SaveManager.save_now()
	for i in 300:
		if SaveManager.terrain_save_complete():
			break
		await _wait(0.1)
	player = await _boot(false)
	_check(player != null, "reloaded save boots")
	if player != null:
		var v2: PlayerVitals = player.get("vitals")
		_check(absf(v2.health.health - hp) < 6.0, "health survives save/load (%.0f vs %.0f; regen allowed)" % [v2.health.health, hp])
		_check(v2.has_respawn and v2.respawn_transform.origin.distance_to(home) < 0.5, "respawn point survives save/load")
		await _wait(1.0)
		_verify_reload(snap)
	_finish()

## State captured right before saving, checked again after reloading (each feature adds its fields).
func _snapshot() -> Dictionary:
	var s := {}
	if _drill != null and is_instance_valid(_drill):
		s["drill_pos"] = _drill.global_position
		s["drill_depth"] = _drill.depth_m
		s["drill_shaft"] = _drill.shaft
		s["drill_count"] = _drill.get_total_count()
		s["bore_point"] = _drill.global_position - PlanetPhysics.get_up(_drill.global_position) * (DepositDrill.START_DEPTH_M + 0.5)
	return s

func _verify_reload(s: Dictionary) -> void:
	if s.has("drill_pos"):
		var found: DepositDrill = null
		for n in get_tree().get_nodes_in_group("building"):
			if n is DepositDrill and (n as Node3D).global_position.distance_to(s.drill_pos) < 0.1:
				found = n
		_check(found != null, "deposit drill is restored by the save")
		if found != null:
			# the clock kept it boring for a moment between snapshot and save, so allow forward progress only
			var progressed: bool = found.shaft > int(s.drill_shaft) or found.depth_m >= float(s.drill_depth) - 0.01
			_check(progressed, "drill shaft/depth restored (%.1f m, saved %.1f m)" % [found.depth_m, s.drill_depth])
			_check(found.get_total_count() >= int(s.drill_count) - 5, "drill contents restored")
		var terrain := PlanetPhysics.get_nearest_terrain(s.bore_point)
		var sdf := terrain.get_voxel_tool().get_voxel_f(Vector3i(terrain.to_local(s.bore_point).round()))
		_check(sdf > 0.0, "the bored shaft is still air after reload (sdf %.2f)" % sdf)

## Where the ground is under a point `ahead` metres in front of the player (radial raycast, any body).
func _ground_ahead(player: Node3D, ahead: float) -> Variant:
	var up := PlanetPhysics.get_up(player.global_position)
	var p := player.global_position - player.global_transform.basis.z * ahead
	var q := PhysicsRayQueryParameters3D.create(p + up * 8.0, p - up * 20.0)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return null if hit.is_empty() else hit.position

func _test_drill(player: Node3D) -> void:
	var ground: Variant = _ground_ahead(player, 6.0)
	_check(ground != null, "found ground for the drill")
	if ground == null:
		return
	var up := PlanetPhysics.get_up(ground)
	var drill: DepositDrill = load("res://scenes/deposit_drill.tscn").instantiate()
	get_tree().current_scene.add_child(drill)
	var fwd := (-player.global_transform.basis.z - up * (-player.global_transform.basis.z).dot(up)).normalized()
	drill.global_transform = Transform3D(Basis.looking_at(fwd, up), ground)
	SaveManager.mark_placed(drill, "deposit_drill")
	drill.keep_stone = true
	FactoryClock.speed = 0.0     # drive bites by hand so the count is exact
	var terrain := PlanetPhysics.get_nearest_terrain(ground)
	var tool := terrain.get_voxel_tool()
	var start_head := drill.head_position()
	var start_solid := clampf(0.5 - tool.get_voxel_f(Vector3i(terrain.to_local(start_head).round())), 0.0, 1.0)
	var t_bites := 0.0
	for i in 160:
		var t0 := Time.get_ticks_usec()
		drill.bite_once()
		t_bites += float(Time.get_ticks_usec() - t0)
		if i % 8 == 0:
			await get_tree().process_frame
	var ms := t_bites / 1000.0 / 160.0
	var end_solid := clampf(0.5 - tool.get_voxel_f(Vector3i(terrain.to_local(start_head).round())), 0.0, 1.0)
	var total := 0
	for id: String in drill.mined:
		total += int(drill.mined[id])
	print("DRILL depth %.1f m shaft %d mined %s reason '%s' solid %.2f -> %.2f, %.2f ms/bite" % [drill.depth_m,
		drill.shaft, drill.mined, drill.idle_reason(), start_solid, end_solid, ms])
	_check(drill.idle_reason() == "", "drill finds editable terrain under itself")
	_check(start_solid > 0.5 and end_solid <= DepositDrill.CLEAR_SOLID + 0.05, "drill really removes rock at the head (%.2f -> %.2f)" % [start_solid, end_solid])
	_check(drill.depth_m > DepositDrill.START_DEPTH_M + 1.0 or drill.shaft > 0, "the bore head advances down the shaft (%.1f m)" % drill.depth_m)
	_check(total > 0 and drill.get_total_count() == total, "drill pays what it cut into its output (%d items)" % total)
	# radial: the head must sit below the base along the body's up, not world Y
	var below := (drill.global_position - drill.head_position()).normalized().dot(up)
	_check(below > 0.99 or drill.shaft > 0, "shaft goes along the radial down (dot %.3f)" % below)
	# the clock drives it too
	FactoryClock.speed = 1.0
	var bites_before := drill.bites_total
	await _wait(3.0)
	_check(drill.bites_total > bites_before, "FactoryClock keeps the drill boring in the real world")
	_drill = drill

var _drill: DepositDrill

func _finish() -> void:
	if _slot != "":
		SaveManager.end_session()
		SaveManager.delete_slot(_slot)
	print("GAME DONE fails=%d" % _fails)
	get_tree().quit(_fails)

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

	# save -> reload: vitals survive
	Health.deal(player, 30.0, "env")
	var hp := v.health.health
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
	_finish()

func _finish() -> void:
	if _slot != "":
		SaveManager.end_session()
		SaveManager.delete_slot(_slot)
	print("GAME DONE fails=%d" % _fails)
	get_tree().quit(_fails)

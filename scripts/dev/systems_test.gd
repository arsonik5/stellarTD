extends Node3D
## Systems test: the G1 foundations, without a planet (fast, deterministic).
##   godot --headless --path . res://scenes/dev/systems_test.tscn
## Prints PASS/FAIL per check and "SYSTEMS DONE fails=N"; exit code = N.
## Grows with every service: add a _test_* function and call it from _run().

var _fails := 0

func _ready() -> void:
	# let autoloads finish _ready
	await get_tree().process_frame
	FactoryClock.speed = 0.0 # only advance() moves the factory here, so results do not depend on frame timing
	await _run()
	print("SYSTEMS DONE fails=%d" % _fails)
	get_tree().quit(_fails)

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _run() -> void:
	_test_events()
	_test_recipe_book()
	await _test_factory_clock()
	await _test_health()
	await _test_dismantle()
	_test_save_migration()

func _test_events() -> void:
	var got := []
	var cb := func(id: String, n: int) -> void: got.append([id, n])
	GameEvents.item_added.connect(cb)
	Inventory.add("ore_a", 3)
	GameEvents.item_added.disconnect(cb)
	_check(got.size() == 1 and got[0][0] == "ore_a" and got[0][1] == 3, "inventory add emits item_added")
	var before := QuestManager.get_progress_current("open_inventory")
	GameEvents.act("open_inventory")
	_check(QuestManager.get_state("open_inventory") == "complete" or QuestManager.get_progress_current("open_inventory") > before,
		"quests listen to GameEvents.action")
	Inventory.try_remove("ore_a", 3)

func _test_recipe_book() -> void:
	var r := RecipeBook.for_output("basic_crafter")
	_check(r != null and r.input_ids == ["ore_a"] and r.input_amounts == [5], "RecipeBook finds the build recipe")
	_check(RecipeBook.uses_of("ore_a").size() >= 5, "RecipeBook lists uses of iron ore")

func _test_factory_clock() -> void:
	var crafter: Building = load("res://scenes/processor.tscn").instantiate()
	add_child(crafter)
	await get_tree().process_frame
	crafter.add_input("ore_a", 4)
	crafter.set_auto(0, true) # refine_ore_a: 2 ore -> 1 ingot, 3.0 s
	FactoryClock.advance(0.1)  # tick 1 starts the job
	_check(crafter.get_active_recipe_index() == 0, "auto recipe starts on a factory tick")
	FactoryClock.advance(2.9)
	_check(crafter.get_inventory_count("refined_material") == 0, "not finished before 3.0 s")
	FactoryClock.advance(0.1)
	_check(crafter.get_inventory_count("refined_material") == 1, "finished exactly at 3.0 s")
	var data := crafter.save_state()
	FactoryClock.advance(0.1) # second job starts
	data = crafter.save_state()
	_check(int(data.get("job", -1)) == 0, "running job is saved")
	crafter.set_auto(0, false)
	_check(crafter.idle_reason() == "", "busy machine has no idle reason")
	FactoryClock.advance(3.0)
	_check(crafter.idle_reason() == "Idle", "machine with no auto recipe reports Idle")
	crafter.set_auto(0, true)
	_check(crafter.idle_reason() == "Missing input", "starved machine reports Missing input")
	crafter.queue_free()

func _test_health() -> void:
	var enemy: Node3D = load("res://scenes/enemy_dummy.tscn").instantiate()
	add_child(enemy)
	await get_tree().process_frame
	var h := Health.of(enemy)
	_check(h != null and h.faction == "alien", "enemy dummy carries an alien Health")
	var shooter := Node.new()
	shooter.set_meta("faction", "alien")
	_check(Health.deal(enemy, 10.0, "kinetic", shooter) == 0.0, "no friendly fire within a faction")
	shooter.set_meta("faction", "player")
	_check(is_equal_approx(Health.deal(enemy, 10.0, "kinetic", shooter), 10.0), "player damage hurts aliens")
	var died := [false]
	GameEvents.destroyed.connect(func(t: Node, _s: Node) -> void:
		if t == enemy:
			died[0] = true, CONNECT_ONE_SHOT)
	Health.deal(enemy, 1000.0, "kinetic", shooter)
	await get_tree().process_frame
	_check(died[0] and not is_instance_valid(enemy), "lethal damage destroys and frees the enemy")
	shooter.free()
	# building: destroyed without refund, removed from the save group
	var b: Building = load("res://scenes/chest.tscn").instantiate()
	add_child(b)
	SaveManager.mark_placed(b, "chest")
	await get_tree().process_frame
	_check(Health.of(b) != null and Health.of(b).faction == "player", "buildings carry player Health")
	Health.deal(b, 10000.0, "explosive", null)
	await get_tree().process_frame
	_check(not is_instance_valid(b), "destroyed building is removed")

func _test_dismantle() -> void:
	var c: Building = load("res://scenes/processor.tscn").instantiate()
	add_child(c)
	SaveManager.mark_placed(c, "basic_crafter")
	await get_tree().process_frame
	c.add_input("ore_b", 7)
	var iron := Inventory.get_count("ore_a")
	var copper := Inventory.get_count("ore_b")
	_check(WorldObjects.dismantle(c), "dismantle succeeds with room in the inventory")
	_check(Inventory.get_count("ore_a") == iron + 5, "dismantle refunds the build cost (5 iron ore)")
	_check(Inventory.get_count("ore_b") == copper + 7, "dismantle returns the machine's contents")
	Inventory.try_remove("ore_a", 5)
	Inventory.try_remove("ore_b", 7)
	await get_tree().process_frame
	_check(not is_instance_valid(c), "dismantled building is gone")
	# full inventory: refuse, change nothing
	var saved := Inventory.save_state()
	for i in Inventory.GRID_SIZE:
		Inventory.set_slot({"kind": "grid", "index": i}, "stone", 100)
	var d: Building = load("res://scenes/processor.tscn").instantiate()
	add_child(d)
	SaveManager.mark_placed(d, "basic_crafter")
	await get_tree().process_frame
	_check(not WorldObjects.dismantle(d) and is_instance_valid(d), "dismantle refused when the refund will not fit")
	Inventory.load_state(saved)
	d.queue_free()

func _test_save_migration() -> void:
	var old := {"version": 1, "inventory": {}}
	var m := SaveManager.migrate(old)
	_check(int(m.get("version", 0)) == SaveManager.FORMAT_VERSION, "v1 save migrates to the current version")

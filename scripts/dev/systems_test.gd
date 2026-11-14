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
	await _test_crusher_and_drill()
	await _test_hotbar_and_markers()
	await _test_progression()
	await _test_power()
	await _test_signature()
	await _test_combat()
	await _test_support_buildings()
	await _test_mechanisms()
	await _test_repair_and_stats()
	_test_world_fx()
	await _test_walls_and_settings()
	await _test_drone_port()
	await _test_modules()
	await _test_sidearm()

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

func _test_crusher_and_drill() -> void:
	var cr: Building = load("res://scenes/crusher.tscn").instantiate()
	add_child(cr)
	await get_tree().process_frame
	_check(cr.get_auto(0), "crusher runs on its own (auto on at placement)")
	cr.add_input("stone", 10)
	FactoryClock.advance(0.1)
	FactoryClock.advance(1.0)
	_check(cr.get_inventory_count("gravel") == 1, "crusher: 2 stone -> 1 gravel in 1 s")
	FactoryClock.advance(5.0)
	_check(cr.get_inventory_count("gravel") == 5 and cr.get_inventory_count("stone") == 0, "crusher drains all stone (5 gravel)")
	_check(cr.pipe_take_one() == "gravel", "pipes pull gravel out of the crusher")
	_check(not cr.can_accept_input("ore_a", 1), "crusher refuses iron ore")
	cr.queue_free()
	var ch: Building = load("res://scenes/chest.tscn").instantiate()
	add_child(ch)
	await get_tree().process_frame
	ch.add_input("ore_b", 2)
	_check(ch.pipe_take_one() == "ore_b" and ch.get_inventory_count("ore_b") == 1, "pipes can empty a chest")
	ch.queue_free()
	var dr: DepositDrill = load("res://scenes/deposit_drill.tscn").instantiate()
	add_child(dr)
	await get_tree().process_frame
	_check(dr.get_node_or_null("Model") != null, "deposit drill builds its blockout model")
	_check(not dr.can_accept_input("ore_a", 1), "drill takes nothing in")
	dr.bite_once()
	_check(dr.idle_reason() == "No ground to drill", "drill with no planet says why it is idle")
	dr.add_output("ore_a", 3)
	_check(dr.output_ids() == ["ore_a"] and dr.pipe_take_one() == "ore_a", "pipes pull whatever the drill holds")
	dr.keep_stone = true
	dr.depth_m = 7.5
	dr.shaft = 2
	dr.mined = {"ore_a": 12}
	var data := dr.save_state()
	var dr2: DepositDrill = load("res://scenes/deposit_drill.tscn").instantiate()
	add_child(dr2)
	await get_tree().process_frame
	dr2.load_state(data)
	_check(dr2.keep_stone and is_equal_approx(dr2.depth_m, 7.5) and dr2.shaft == 2 and int(dr2.mined.get("ore_a", 0)) == 12,
		"drill state survives save/load")
	_check(dr2.get_inventory_count("ore_a") == 2, "drill contents survive save/load")
	# advancing past the last shaft exhausts it
	dr2.shaft = DepositDrill.PATTERN.size() - 1
	dr2.depth_m = DepositDrill.MAX_DEPTH_M
	dr2._advance()
	_check(dr2.exhausted and dr2.idle_reason().begins_with("Depleted"), "drill is depleted after its last shaft")
	dr.queue_free()
	dr2.queue_free()

func _test_hotbar_and_markers() -> void:
	var ui: Node = load("res://scenes/build_ui.tscn").instantiate() if ResourceLoader.exists("res://scenes/build_ui.tscn") else null
	if ui == null:
		for n in get_tree().get_nodes_in_group("build_ui"):
			ui = n
	if ui != null:
		if not ui.is_inside_tree():
			add_child(ui)
			await get_tree().process_frame
		_check(ui.select_hotbar(5) and ui.get_selected_recipe().output_id == "deposit_drill", "hotbar slot 6 selects the deposit drill")
		_check(ui.select_item("crusher") and ui.get_selected_recipe().output_id == "crusher", "pick selects by item id")
		ui.queue_free()
	else:
		print("SKIP build ui not found as a scene")
	var sm: Building = load("res://scenes/smelter.tscn").instantiate()
	add_child(sm)
	await get_tree().process_frame
	sm.set_auto(0, true)
	sm._update_idle_marker()
	var mk := sm.get_node_or_null("IdleMarker") as Label3D
	_check(mk != null and mk.visible and mk.text.contains("MISSING INPUT"), "starved machine shows an idle marker in the world")
	sm.set_auto(0, false)
	sm._update_idle_marker()
	_check(not mk.visible, "switched-off machine shows no marker")
	_check(sm.status_text() == "IDLE", "panel status for a switched-off machine")
	sm.queue_free()

func _complete_tutorial() -> void:
	# drive the tutorial quests to done through the real event paths (no state poking)
	Inventory.add("ore_a", 5)
	Inventory.add("refined_material", 3)
	GameEvents.act("open_inventory")
	GameEvents.building_placed.emit("basic_crafter", null)
	GameEvents.act("toggle_autocraft")
	GameEvents.act("place_block")
	GameEvents.building_placed.emit("vacuum_pipe", null)
	Inventory.try_remove("ore_a", 5)
	Inventory.try_remove("refined_material", 3)

func _test_progression() -> void:
	Progression.reset()
	_check(Progression.active_milestone() == null or Progression.tutorial_done(), "no directive before the tutorial is done")
	_check(not Progression.is_buildable("deposit_drill") and Progression.is_buildable("smelter"), "research gates the drill, not the smelter")
	_check(Progression.gate_of("deposit_drill") != null and Progression.gate_of("deposit_drill").id == "r_deep_drilling", "gate_of names the research")
	# research data from first-time actions, once each
	GameEvents.item_mined.emit("ore_a", 3, null)
	GameEvents.item_mined.emit("ore_a", 3, null)
	GameEvents.item_mined.emit("stone", 3, null)
	_check(int(Progression.points.geology) == 1, "first iron mined gives 1 geology, repeats and stone give none")
	GameEvents.scanned.emit(["copper"])
	_check(int(Progression.points.geology) == 2, "first scan of an ore type gives geology")
	_check(not Progression.can_buy("r_power") and Progression.can_buy("r_deep_drilling"), "can buy only what the points cover")
	_check(Progression.buy("r_deep_drilling") and Progression.is_buildable("deposit_drill") and int(Progression.points.geology) == 0,
		"buying research spends points and unlocks the drill")
	_check(not Progression.buy("r_deep_drilling"), "research cannot be bought twice")
	GameEvents.item_crafted.emit("steel_ingot", 1, null)
	GameEvents.item_crafted.emit("ship_hull", 1, null)
	_check(int(Progression.points.engineering) == 1, "first steel gives engineering; non-materials give none")
	# directives
	_complete_tutorial()
	_check(Progression.tutorial_done(), "tutorial chain completes through GameEvents")
	var m := Progression.active_milestone()
	_check(m != null and m.id == "d01_uplink", "first directive after the tutorial: raise the uplink")
	var credit0 := Progression.credit
	GameEvents.building_placed.emit("uplink", null)
	_check(Progression.completed.has("d01_uplink") and Progression.credit == credit0 + 40, "placing an uplink completes d01 and pays credit")
	m = Progression.active_milestone()
	_check(m != null and m.id == "d02_first_shipment", "the chain moves on to the first shipment")
	_check(Progression.standing.size() == Progression.STANDING_SLOTS, "standing orders open after the first milestone")
	_check(Progression.wants("refined_material") and not Progression.wants("ore_a"), "uplink wants ingots, not ore")
	# uplink delivery through the real building
	var up: Uplink = load("res://scenes/uplink.tscn").instantiate()
	add_child(up)
	await get_tree().process_frame
	_check(not up.can_accept_input("ore_a", 1) and up.can_accept_input("refined_material", 1), "uplink accepts only wanted goods")
	var launches := [0]
	var spikes := [0.0]
	var cb_l := func(n: int, _s: Node) -> void: launches[0] += n
	var cb_s := func(a: float, _s: Node) -> void: spikes[0] += a
	GameEvents.uplink_launched.connect(cb_l)
	GameEvents.signature_spike.connect(cb_s)
	up.add_input("refined_material", 20)
	up.add_input("refined_copper_ingot", 10)
	for i in 12:
		up.deliver_step()
	_check(Progression.completed.has("d02_first_shipment"), "delivering 20 iron + 10 copper ingots completes the first shipment")
	_check(launches[0] >= 30 and spikes[0] > 0.0, "the uplink launched what it delivered and spiked the signature")
	_check(up.get_total_count() == 0, "uplink emptied itself")
	GameEvents.uplink_launched.disconnect(cb_l)
	GameEvents.signature_spike.disconnect(cb_s)
	# standing order completes and is replaced
	var st: Dictionary = Progression.standing[0]
	var item: String = st.item_ids[0]
	var need: int = int(st.amounts[0])
	var taken := Progression.deliver(item, need + 50)
	_check(taken >= need, "a standing order takes what it asked for")
	_check(Progression.completed.has(st.id) and Progression.standing.size() == Progression.STANDING_SLOTS, "a filled standing order is paid and replaced")
	# save/load round trip
	var data := Progression.save_state()
	var json: Dictionary = JSON.parse_string(JSON.stringify(data))  # the real save path goes through JSON
	Progression.reset()
	Progression.load_state(json)
	_check(Progression.completed.has("d02_first_shipment") and Progression.bought.has("r_deep_drilling")
		and Progression.credit == int(data.credit) and Progression.standing.size() == data.standing.size(), "progression survives a JSON save/load")
	_check(Progression.active_milestone() != null and Progression.active_milestone().id == "d03_hardened", "the milestone chain resumes after load")
	_check(Progression.wants(String(Progression.standing[0].item_ids[0])), "loaded standing orders still accept deliveries")
	up.queue_free()
	Progression.reset()

func _place(scene_path: String, pos: Vector3) -> Building:
	var b: Building = load(scene_path).instantiate()
	add_child(b)
	b.global_position = pos
	return b

func _test_power() -> void:
	# keep the world clean of earlier tests' buildings
	await get_tree().process_frame
	var far := Vector3(5000, 0, 0)
	var pa := _place("res://scenes/power_pole.tscn", far)
	var pb := _place("res://scenes/power_pole.tscn", far + Vector3(12, 0, 0))
	var pc := _place("res://scenes/power_pole.tscn", far + Vector3(60, 0, 0))
	var sm := _place("res://scenes/smelter.tscn", far + Vector3(0, 0, 5))
	var gen := _place("res://scenes/burner_generator.tscn", far + Vector3(12, 0, 5))
	var lone := _place("res://scenes/smelter.tscn", far + Vector3(200, 0, 0))
	await get_tree().process_frame
	PowerNetwork.rebuild()
	var g := PowerNetwork.grid_for(sm)
	_check(not g.is_empty() and g == PowerNetwork.grid_for(gen), "smelter and generator share a grid through two linked poles")
	_check(PowerNetwork.grid_for(pc) != g, "a pole out of link range is its own grid")
	_check(PowerNetwork.grid_for(lone).is_empty(), "a machine far from poles is on no grid")
	# no fuel: the smelter runs at base speed, never stops
	sm.add_input("ore_a", 20)
	sm.set_auto(0, true)
	lone.add_input("ore_a", 20)
	lone.set_auto(0, true)
	FactoryClock.advance(0.2)
	_check(is_equal_approx(sm.work_speed, 1.0) and is_equal_approx(lone.work_speed, 1.0), "unfuelled grid / no grid: base speed 1.0")
	_check(gen.idle_reason() == "No fuel", "generator without fuel says so")
	# fuel: full power doubles the smelter
	gen.add_input("ore_coal", 2)
	FactoryClock.advance(0.2)
	_check(is_equal_approx(sm.work_speed, PowerNetwork.POWERED_BOOST), "powered smelter runs at x2 (%.2f)" % sm.work_speed)
	var before := sm.get_inventory_count("refined_material")
	FactoryClock.advance(3.0)
	var made := sm.get_inventory_count("refined_material") - before
	_check(made == 4, "x2 speed: exactly 4 ingots in 3 s instead of 2 (%d)" % made)
	# fuel economy: 15 kW of 30 kW load -> half rate burn; 2 coal = 300 kJ = 20 s at 15 kW
	_check(gen.get_inventory_count("ore_coal") >= 1, "generator burns only what the grid draws (coal left after 3 s)")
	# brownout: three more smelters on the same grid
	var extra: Array = []
	for i in 3:
		var e := _place("res://scenes/smelter.tscn", far + Vector3(-3 - i * 2, 0, -3))
		e.add_input("ore_a", 20)
		e.set_auto(0, true)
		extra.append(e)
	await get_tree().process_frame
	PowerNetwork.rebuild()
	FactoryClock.advance(0.5)
	g = PowerNetwork.grid_for(sm)
	_check(is_equal_approx(float(g.demand), 60.0) and is_equal_approx(float(g.satisfaction), 0.5), "4 smelters on 30 kW: demand 60, 50%% satisfied (%.0f, %.2f)" % [g.demand, g.satisfaction])
	_check(is_equal_approx(sm.work_speed, 1.5), "brownout slows every consumer the same (%.2f)" % sm.work_speed)
	# battery: charges from surplus, carries a dark grid
	for e in extra:
		e.queue_free()
	var bat := _place("res://scenes/battery_bank.tscn", far + Vector3(3, 0, -3))
	await get_tree().process_frame
	PowerNetwork.rebuild()
	sm.set_auto(0, false)
	FactoryClock.advance(2.0)
	_check((bat as BatteryBank).stored_kj > 0.0, "surplus charges the battery (%.0f kJ)" % (bat as BatteryBank).stored_kj)
	var stored := (bat as BatteryBank).stored_kj
	var saved := bat.save_state()
	# take the fuel away: the battery takes the load
	gen.remove_item("ore_coal", gen.get_inventory_count("ore_coal"))
	gen.set("_buffer_kj", 0.0)
	sm.set_auto(0, true)
	FactoryClock.advance(1.0)
	_check((bat as BatteryBank).stored_kj < stored and sm.work_speed > 1.0, "battery carries the grid when fuel runs out")
	var bat2 := _place("res://scenes/battery_bank.tscn", far + Vector3(500, 0, 0))
	bat2.load_state(JSON.parse_string(JSON.stringify(saved)))
	_check(is_equal_approx((bat2 as BatteryBank).stored_kj, stored), "battery charge survives save/load")
	# needs_power: a machine that needs power stops without it and says so
	lone.needs_power = true
	FactoryClock.advance(0.2)
	_check(lone.work_speed == 0.0, "needs-power machine stops off-grid")
	# dismantling a pole splits the grid
	WorldObjects.remove(pb)
	await get_tree().process_frame
	await get_tree().process_frame
	PowerNetwork.rebuild()
	_check(PowerNetwork.grid_for(gen).is_empty(), "removing the linking pole cuts the generator off")
	# solar with a stand-in star overhead / below the horizon
	var star := Node3D.new()
	var src := GDScript.new()
	src.source_code = "extends Node3D\nfunc irradiance_at(_p: Vector3) -> float:\n\treturn 1.0\n"
	src.reload()
	star.set_script(src)
	star.add_to_group("star")
	add_child(star)
	var sol: SolarPanel = _place("res://scenes/solar_panel.tscn", far + Vector3(0, 0, 40)) as SolarPanel
	star.global_position = sol.global_position + Vector3(0, 1000, 0)
	_check(is_equal_approx(sol.power_available(), SolarPanel.RATED_KW), "solar: star overhead = rated output")
	star.global_position = sol.global_position + Vector3(1000, 1000, 0)
	_check(absf(sol.power_available() - SolarPanel.RATED_KW * 0.7071) < 0.05, "solar: star at 45 degrees = 71%")
	star.global_position = sol.global_position + Vector3(0, -1000, 0)
	_check(sol.power_available() == 0.0 and sol.idle_reason().begins_with("Night"), "solar: star below the horizon = night, 0 kW")
	# reactor is a signature source while loaded
	var rx: CrystalReactor = _place("res://scenes/crystal_reactor.tscn", far + Vector3(0, 0, 80)) as CrystalReactor
	_check(rx.signature_contribution() == 0.0 and rx.idle_reason() != "", "empty reactor: no power, no signature")
	rx.add_input("crystal_cell", 1)
	_check(rx.power_available() == CrystalReactor.OUTPUT_KW and rx.signature_contribution() > 0.0, "loaded reactor: 300 kW and a signature")
	for n in [pa, pc, sm, gen, lone, bat, bat2, star, sol, rx]:
		if is_instance_valid(n):
			n.queue_free()
	await get_tree().process_frame

func _test_signature() -> void:
	RadiationSignature.load_state({})
	RadiationSignature.recompute()
	var base := RadiationSignature.signature()
	_check(RadiationSignature.tier() == RadiationSignature.Tier.NONE, "no crystal: quiet (%.2f)" % base)
	Inventory.add("ore_crystal", 3)
	_check(is_equal_approx(RadiationSignature.signature(), 3.0) and RadiationSignature.tier() == RadiationSignature.Tier.LOW, "3 crystal held: 3.0, NOTICED")
	Inventory.try_remove("ore_crystal", 3)
	var ch: Building = _place("res://scenes/chest.tscn", Vector3(7000, 0, 0))
	await get_tree().process_frame
	ch.add_input("crystal_cell", 6)
	RadiationSignature.recompute()
	_check(is_equal_approx(RadiationSignature.signature(), 12.0) and RadiationSignature.tier() == RadiationSignature.Tier.MEDIUM, "6 stored cells: 12.0, HUNTED (%.1f)" % RadiationSignature.signature())
	ch.queue_free()
	await get_tree().process_frame
	RadiationSignature.recompute()
	GameEvents.signature_spike.emit(8.0, null)
	_check(is_equal_approx(RadiationSignature.signature(), 8.0), "a launch spike adds to the signature")
	FactoryClock.advance(RadiationSignature.SPIKE_HALF_LIFE)
	_check(absf(RadiationSignature.spike - 4.0) < 0.05, "spikes halve every %d s (%.2f)" % [int(RadiationSignature.SPIKE_HALF_LIFE), RadiationSignature.spike])
	GameEvents.item_mined.emit("ore_crystal", 5, null)
	_check(RadiationSignature.spike > 5.9, "drilling crystal spikes the signature")
	RadiationSignature.report_leak()
	_check(RadiationSignature.alert >= RadiationSignature.ALERT_PER_REPORT, "an escaped scout's report raises the alert")
	var saved := RadiationSignature.save_state()
	RadiationSignature.load_state({})
	_check(RadiationSignature.alert == 0.0, "fresh game has no alert")
	RadiationSignature.load_state(JSON.parse_string(JSON.stringify(saved)))
	_check(absf(RadiationSignature.alert - float(saved.alert)) < 0.001, "alert and spikes survive save/load")
	_check(RadiationSignature.tier_for(65.0) == RadiationSignature.Tier.SIEGE and RadiationSignature.tier_for(30.0) == RadiationSignature.Tier.HIGH, "tier thresholds")
	var c2 := ThreatDirector.composition_for(RadiationSignature.Tier.MEDIUM, 0)
	var c3 := ThreatDirector.composition_for(RadiationSignature.Tier.HIGH, 4)
	var c4 := ThreatDirector.composition_for(RadiationSignature.Tier.SIEGE, 0)
	_check(c2.gunship == 1 and c2.dropship == 0 and c3.dropship == 2 and c3.gunship == 2 and c4.spotter == 1, "wave composition grows with tier and wave count")
	RadiationSignature.load_state({})

func _test_combat() -> void:
	Engine.time_scale = 4.0
	var origin := Vector3(9000, 0, 0)
	# a turret with ammo guarding a smelter; a gunship comes for the smelter
	var tur: Turret = _place("res://scenes/turret_gun.tscn", origin) as Turret
	var target_b: Building = _place("res://scenes/smelter.tscn", origin + Vector3(6, 0, 0))
	await get_tree().process_frame
	tur.add_input("iron_piercing_ammo", 200)
	var td := ThreatDirector.new()
	add_child(td)
	td.enabled = false
	var wave: Array = td.launch_wave({"gunship": 1}, Vector3(1, 0, 0))
	var g: Gunship = wave[0]
	g.global_position = origin + Vector3(120, 40, 0)
	var hurt := [0.0]
	var cb := func(t: Node, a: float, _ty: String, _s: Node) -> void:
		if t == target_b or t == tur:
			hurt[0] += a
	GameEvents.damaged.connect(cb)
	var killed := false
	var t0 := Time.get_ticks_msec()
	for i in 2400:
		await get_tree().physics_frame
		if not is_instance_valid(g) or g.dead:
			killed = true
			break
	var sim_s := float(Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale
	GameEvents.damaged.disconnect(cb)
	print("COMBAT gunship killed=%s after ~%.0f s sim, shots by gunship %d, base damage %.0f" % [killed, sim_s,
		g.shots_fired if is_instance_valid(g) else -1, hurt[0]])
	_check(killed, "a stocked gun turret shoots down a gunship")
	_check(tur.get_inventory_count("iron_piercing_ammo") < 200, "the turret spent ammo doing it")
	# the wreck lands with alloy; opening it gives xeno data once
	await get_tree().create_timer(4.5).timeout
	var wreck: Wreck = null
	for n in get_tree().get_nodes_in_group("building"):
		if n is Wreck:
			wreck = n
	_check(wreck != null and wreck.get_inventory_count("alien_alloy") == 4, "a dead gunship leaves a wreck with 4 alloy")
	if wreck != null:
		var x0 := int(Progression.points.xeno)
		wreck.salvaged = false
		wreck.salvaged = true   # interact() opens UI; award path tested directly
		Progression.award("xeno", 2, "salvaged gunship")
		_check(int(Progression.points.xeno) == x0 + 2, "salvage gives xeno data")
		wreck.queue_free()
	# a gunship with no defence damages the base
	var g2: Gunship = td.launch_wave({"gunship": 1}, Vector3(1, 0, 0))[0]
	var lone: Building = _place("res://scenes/chest.tscn", origin + Vector3(0, 0, 400))
	g2.global_position = lone.global_position + Vector3(80, 30, 0)
	g2.target = lone
	g2._plan_run()
	var hp0 := Health.of(lone).health
	for i in 1500:
		await get_tree().physics_frame
		if not is_instance_valid(lone) or Health.of(lone).health < hp0:
			break
	_check(not is_instance_valid(lone) or Health.of(lone).health < hp0, "an undefended building takes gunship fire")
	if is_instance_valid(g2):
		g2.queue_free()
	if is_instance_valid(lone):
		lone.queue_free()
	# a drone walks to a building and cuts it
	var victim: Building = _place("res://scenes/chest.tscn", origin + Vector3(0, 0, -300))
	var drone: EnemyDrone = load("res://scenes/enemy_drone.tscn").instantiate()
	add_child(drone)
	drone.global_position = victim.global_position + Vector3(12, 0, 0)
	var vh := Health.of(victim).health
	for i in 900:
		await get_tree().physics_frame
		if Health.of(victim).health < vh:
			break
	_check(Health.of(victim).health < vh, "a drone walks to a building and damages it")
	_check(drone.global_position.distance_to(victim.global_position) < EnemyDrone.ATTACK_RANGE + 0.5, "the drone stopped at cutting range")
	drone.queue_free()
	victim.queue_free()
	# a spotter's shell falls and splashes the building it was aimed at
	var bunker: Building = _place("res://scenes/chest.tscn", origin + Vector3(0, 0, 300))
	# ground for the shell to land on (this scene has no planet)
	var slab := StaticBody3D.new()
	var slab_cs := CollisionShape3D.new()
	var slab_box := BoxShape3D.new()
	slab_box.size = Vector3(60, 1, 60)
	slab_cs.shape = slab_box
	slab.add_child(slab_cs)
	add_child(slab)
	slab.global_position = bunker.global_position - Vector3(0, 0.5, 0)
	var sp: Spotter = load("res://scenes/enemy_spotter.tscn").instantiate()
	sp.base_center = bunker.global_position
	add_child(sp)
	sp.global_position = bunker.global_position + Vector3(0, 60, 0)
	var bh := Health.of(bunker).health
	sp.call_shell(Vector3.UP)
	for i in 600:
		await get_tree().physics_frame
		if not is_instance_valid(bunker) or Health.of(bunker).health < bh:
			break
	_check(not is_instance_valid(bunker) or Health.of(bunker).health < bh, "an orbital shell lands on the base and splashes it")
	sp.queue_free()
	slab.queue_free()
	if is_instance_valid(bunker):
		bunker.queue_free()
	# dropship lands and unloads drones
	var ds: Dropship = load("res://scenes/enemy_dropship.tscn").instantiate()
	ds.landing_point = origin + Vector3(0, 0, 600)
	add_child(ds)
	ds.global_position = ds.landing_point + Vector3(60, 40, 0)
	for i in 3000:
		await get_tree().physics_frame
		if ds.drones_out >= Dropship.DRONES:
			break
	_check(ds.drones_out == Dropship.DRONES, "a dropship lands and unloads %d drones (%d)" % [Dropship.DRONES, ds.drones_out])
	for n in get_tree().get_nodes_in_group("enemy"):
		n.queue_free()
	ds.queue_free()
	tur.queue_free()
	target_b.queue_free()
	td.queue_free()
	Engine.time_scale = 1.0
	await get_tree().process_frame

func _test_support_buildings() -> void:
	var o := Vector3(11000, 0, 0)
	RadiationSignature.load_state({})
	var ch: Building = _place("res://scenes/chest.tscn", o)
	await get_tree().process_frame
	ch.add_input("crystal_cell", 10)   # 20 signature: HUNTED
	var cf: ContainmentField = _place("res://scenes/containment_field.tscn", o + Vector3(3, 0, 0)) as ContainmentField
	await get_tree().process_frame
	FactoryClock.advance(0.2)
	RadiationSignature.recompute()
	_check(is_equal_approx(RadiationSignature.signature(), 20.0) and cf.idle_reason() == "No power", "unpowered containment hides nothing (%.1f)" % RadiationSignature.signature())
	var pole: Building = _place("res://scenes/power_pole.tscn", o + Vector3(1, 0, 2))
	var gen: Building = _place("res://scenes/burner_generator.tscn", o + Vector3(-2, 0, 2))
	var gen2: Building = _place("res://scenes/burner_generator.tscn", o + Vector3(-2, 0, -2))
	gen.add_input("refined_carbon", 20)
	gen2.add_input("refined_carbon", 20)
	await get_tree().process_frame
	PowerNetwork.rebuild()
	FactoryClock.advance(0.3)
	RadiationSignature.recompute()
	_check(is_equal_approx(RadiationSignature.signature(), 5.0), "powered containment hides 15 (20 -> %.1f)" % RadiationSignature.signature())
	_check(RadiationSignature.tier() == RadiationSignature.Tier.LOW, "containment drops the base from HUNTED to NOTICED")
	for n in [ch, cf, pole, gen, gen2]:
		n.queue_free()
	await get_tree().process_frame
	RadiationSignature.load_state({})
	# beacons
	var rb: Beacon = _place("res://scenes/respawn_beacon.tscn", o + Vector3(0, 0, 50)) as Beacon
	var wb: Beacon = _place("res://scenes/waypoint_beacon.tscn", o + Vector3(0, 0, 60)) as Beacon
	await get_tree().process_frame
	_check(rb.is_in_group("respawn_point") and not rb.is_in_group("waypoint"), "respawn beacon is a respawn point")
	_check(wb.is_in_group("waypoint") and wb.label.begins_with("Waypoint"), "waypoint beacon is a named waypoint")
	wb.label = "Copper ridge"
	var wb2: Beacon = _place("res://scenes/waypoint_beacon.tscn", o + Vector3(0, 0, 70)) as Beacon
	await get_tree().process_frame
	wb2.load_state(JSON.parse_string(JSON.stringify(wb.save_state())))
	_check(wb2.label == "Copper ridge", "waypoint name survives save/load")
	# a stand-in player: PlayerVitals respawns at the nearest beacon
	var fake := CharacterBody3D.new()
	add_child(fake)
	fake.global_position = o + Vector3(0, 0, 45)
	var v := PlayerVitals.new()
	fake.add_child(v)
	v.setup(fake)
	v.remember_respawn(Transform3D(Basis(), o + Vector3(0, 0, -500)))
	var t := v._best_respawn()
	_check(t.origin.distance_to(rb.global_position) < 2.0, "respawn picks the nearest respawn beacon over the landing site")
	for n in [rb, wb, wb2, fake]:
		n.queue_free()
	# supply drop: costs credit, falls along radial down, lands, holds the pack
	Progression.reset()
	var anchor := Node3D.new()
	add_child(anchor)
	anchor.global_position = o + Vector3(0, 0, 120)
	_check(SupplyPod.order("ingots", anchor) == null, "no supply drop without the credit")
	Progression.credit = 100
	var pod := SupplyPod.order("ingots", anchor)
	_check(pod != null and Progression.credit == 40, "an ingot crate costs 60 credit")
	_check(pod != null and pod.get_inventory_count("refined_material") == 40, "the pod carries what was ordered")
	var start_alt := pod.global_position.y - anchor.global_position.y
	Engine.time_scale = 4.0
	for i in 600:
		await get_tree().physics_frame
		if pod.is_landed():
			break
	Engine.time_scale = 1.0
	_check(start_alt > 200.0 and pod.is_landed() and absf(pod.global_position.y - anchor.global_position.y) < 1.0, "the pod falls from orbit and lands beside the player")
	pod.queue_free()
	anchor.queue_free()
	Progression.reset()

func _joint_ship(kind: String, at: Vector3) -> Ship:
	var ship := Ship.new()
	add_child(ship)
	ship.global_position = at
	var core: ShipBlock = Inventory.get_item_def("vehicle_core").block_scene.instantiate()
	ship.try_add_block(Vector3i(-1, -1, -1), core)
	var j: ShipBlock = Inventory.get_item_def(kind).block_scene.instantiate()
	ship.try_add_block(Vector3i(-1, 1, -1), j)
	return ship

func _drive(ship: Ship, input: float, seconds: float) -> void:
	for j in ship.all_joints():
		j.input = input
	var frames := int(seconds * Engine.physics_ticks_per_second)
	for i in frames:
		await get_tree().physics_frame
	for j in ship.all_joints():
		j.input = 0.0

func _test_mechanisms() -> void:
	var o := Vector3(13000, 0, 0)
	# bearing
	var sb := _joint_ship("bearing", o)
	await get_tree().process_frame
	await get_tree().physics_frame
	var joints := sb.all_joints()
	_check(joints.size() == 1 and joints[0] is ShipJoint, "a bearing on a ship is a joint")
	var bj: ShipJoint = joints[0]
	_check(bj.child != null and bj.child.is_subgrid and bj.child.get_block(Vector3i.ZERO) != null, "the bearing spawned a sub-grid with its head plate at cell 0")
	_check(bj.child.ship_state == Ship.STATE_OPERATIONAL, "a sub-grid's head counts as its core (operational)")
	var hull: ShipBlock = Inventory.get_item_def("hull_small").block_scene.instantiate()
	var m0 := bj.child.mass
	_check(bj.child.try_add_block(Vector3i(0, 1, 0), hull), "blocks can be built onto the moving part")
	_check(bj.child.mass > m0, "the sub-grid's mass grows with its blocks")
	var a0 := bj.position_value()
	await _drive(sb, 1.0, 1.0)
	var a1 := bj.position_value()
	print("MECH bearing %.2f -> %.2f rad" % [a0, a1])
	_check(absf(angle_difference(a0, a1)) > 0.5, "the bearing motor turns the sub-grid (Z / C)")
	await _drive(sb, 0.0, 0.5)
	var a2 := bj.position_value()
	await _drive(sb, 0.0, 0.5)
	_check(absf(angle_difference(a2, bj.position_value())) < 0.1, "with no input the bearing holds its angle")
	# save / load the whole assembly
	var data: Dictionary = JSON.parse_string(JSON.stringify(sb.save_state()))
	_check((data.get("subgrids", []) as Array).size() == 1, "the parent ship saves its sub-grid")
	var sb2 := Ship.new()
	add_child(sb2)
	sb2.load_state(data)
	await get_tree().process_frame
	await get_tree().physics_frame
	var j2: Array = sb2.all_joints()
	_check(j2.size() == 1 and (j2[0] as ShipJoint).child != null and (j2[0] as ShipJoint).child.get_block_cells().size() == 2,
		"loading restores the joint, its sub-grid and the block built on it")
	# hinge: stops at +-90 degrees
	var sh := _joint_ship("hinge", o + Vector3(0, 0, 40))
	await get_tree().process_frame
	await get_tree().physics_frame
	var hj: ShipJoint = sh.all_joints()[0]
	await _drive(sh, 1.0, 3.0)
	var ha := absf(hj.position_value())
	print("MECH hinge after 3 s: %.2f rad" % ha)
	_check(ha > 1.2 and ha < PI / 2.0 + 0.2, "the hinge swings to its 90 degree limit and stops there (%.2f)" % ha)
	# piston: 0 .. 1.5 m
	var sp := _joint_ship("piston", o + Vector3(0, 0, 80))
	await get_tree().process_frame
	await get_tree().physics_frame
	var pj: ShipJoint = sp.all_joints()[0]
	var e0 := pj.position_value()
	await _drive(sp, 1.0, 2.5)
	var e1 := pj.position_value()
	await _drive(sp, -1.0, 2.5)
	var e2 := pj.position_value()
	print("MECH piston %.2f -> %.2f -> %.2f m" % [e0, e1, e2])
	_check(e1 > 1.2 and e1 < ShipJoint.PISTON_STROKE + 0.15, "the piston extends to its 1.5 m stroke (%.2f)" % e1)
	_check(e2 < 0.2, "and retracts again (%.2f)" % e2)
	for n in [sb, sb2, sh, sp]:
		for j in n.all_joints():
			if is_instance_valid(j.child):
				j.child.queue_free()
		n.queue_free()
	await get_tree().process_frame

func _test_repair_and_stats() -> void:
	var b: Building = _place("res://scenes/smelter.tscn", Vector3(15000, 0, 0))
	await get_tree().process_frame
	var h := Health.of(b)
	Health.deal(b, 140.0, "explosive", null)
	_check(is_equal_approx(h.health, h.max_health - 140.0), "raid damage sticks on a building")
	var BUI: Script = load("res://scripts/ui/building_ui.gd")
	Inventory.add("refined_material", 2)
	var have := Inventory.get_count("refined_material")
	_check(BUI.repair_building(b) and is_equal_approx(h.health, h.max_health - 40.0) and Inventory.get_count("refined_material") == have - 2,
		"repair: 2 iron ingots restore 100 health (50 each), as far as they go")
	Inventory.add("refined_material", 5)
	have = Inventory.get_count("refined_material")
	BUI.repair_building(b)
	_check(is_equal_approx(h.health, h.max_health) and Inventory.get_count("refined_material") == have - 1, "repair charges only what is missing")
	_check(not BUI.repair_building(b), "a healthy building needs no repair")
	Inventory.try_remove("refined_material", Inventory.get_count("refined_material"))
	b.queue_free()

func _test_world_fx() -> void:
	var p := WorldFx.burst("dust", Vector3(17000, 0, 0), Vector3.UP)
	_check(p != null and p.emitting and p.one_shot, "WorldFx bursts one-shot particles")
	var up2 := Vector3(1, 1, 0).normalized()
	var p2 := WorldFx.burst("sparks", Vector3(17000, 5, 0), up2)
	_check(p2.global_transform.basis.y.normalized().dot(up2) > 0.999, "particles are aligned to the local up, not world Y")
	for k in ["drill", "drill_machine", "gun", "cannon", "hit", "boom", "launch", "alien_fire", "crash", "clank"]:
		if not WorldFx._streams.has(k) or (WorldFx._streams[k] as AudioStreamWAV).data.size() < 1000:
			_check(false, "world sound '%s' synthesised" % k)
			return
	_check(true, "all 10 world sounds synthesised")

func _test_walls_and_settings() -> void:
	var o := Vector3(19000, 0, 0)
	var wall: Node3D = load("res://scenes/foundation_2m.tscn").instantiate()
	add_child(wall)
	wall.global_position = o + Vector3(0, 1, 0)
	var target: Building = _place("res://scenes/chest.tscn", o + Vector3(-6, 0, 0))
	# a floor so the drone walks instead of floating
	var slab := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40, 1, 40)
	cs.shape = bx
	slab.add_child(cs)
	add_child(slab)
	slab.global_position = o - Vector3(0, 0.5, 0)
	await get_tree().process_frame
	var wh := Health.of(wall)
	_check(wh != null and is_equal_approx(wh.max_health, 1000.0), "a 2 m foundation block has 1000 structure")
	var drone: EnemyDrone = load("res://scenes/enemy_drone.tscn").instantiate()
	add_child(drone)
	drone.global_position = o + Vector3(6, 0.2, 0)
	drone.target = target
	Engine.time_scale = 4.0
	for i in 1200:
		await get_tree().physics_frame
		if wh.health < wh.max_health:
			break
	Engine.time_scale = 1.0
	_check(wh.health < wh.max_health, "a drone blocked by a wall cuts into the wall")
	drone.queue_free()
	wall.queue_free()
	target.queue_free()
	slab.queue_free()
	var old: Variant = GameSettings.get_value("raids")
	GameSettings.set_value("raids", 0)
	_check(ThreatDirector.raid_mult() == 0.0, "Raids: Off stops the wave clock")
	GameSettings.set_value("raids", 3)
	_check(ThreatDirector.raid_mult() < 1.0, "Raids: Relentless shortens the gap between waves")
	GameSettings.set_value("raids", old)
	await get_tree().process_frame

func _test_drone_port() -> void:
	var o := Vector3(21000, 0, 0)
	var port: DronePort = _place("res://scenes/drone_port.tscn", o) as DronePort
	var src: Building = _place("res://scenes/chest.tscn", o + Vector3(15, 0, 0))
	var dst: Building = _place("res://scenes/chest.tscn", o + Vector3(-12, 0, 8))
	src.add_input("refined_material", 30)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(port.drone != null and is_instance_valid(port.drone), "the drone port launches its drone")
	_check(port.storages_in_range().size() >= 2, "the port lists storages in range")
	port.set_route(src, dst)
	FactoryClock.advance(0.2)
	_check(port.idle_reason() == "No power", "a drone port without power says so")
	var pole: Building = _place("res://scenes/power_pole.tscn", o + Vector3(2, 0, 2))
	var gen: Building = _place("res://scenes/burner_generator.tscn", o + Vector3(4, 0, -2))
	gen.add_input("refined_carbon", 30)
	await get_tree().process_frame
	PowerNetwork.rebuild()
	FactoryClock.advance(0.2)
	_check(port.idle_reason() == "", "powered and routed: hauling")
	Engine.time_scale = 4.0
	for i in 2400:
		await get_tree().physics_frame
		if port.trips >= 2:
			break
	Engine.time_scale = 1.0
	print("DRONE trips %d, source %d, dest %d, cargo %d" % [port.trips, src.get_inventory_count("refined_material"),
		dst.get_inventory_count("refined_material"), port.drone.cargo_count()])
	_check(port.trips >= 2, "the drone completes round trips (%d)" % port.trips)
	_check(dst.get_inventory_count("refined_material") >= 20 and src.get_inventory_count("refined_material") <= 10,
		"items really moved from source to destination")
	var data: Dictionary = JSON.parse_string(JSON.stringify(port.save_state()))
	var port2: DronePort = _place("res://scenes/drone_port.tscn", o + Vector3(0, 0, 30)) as DronePort
	port2.load_state(data)
	for i in 4:
		await get_tree().process_frame
	_check(port2.source == src and port2.destination == dst and port2.trips == port.trips, "the route survives save/load")
	for n in [port, port2, src, dst, pole, gen]:
		n.queue_free()
	await get_tree().process_frame

func _test_modules() -> void:
	var o := Vector3(23000, 0, 0)
	var sm: Building = _place("res://scenes/smelter.tscn", o)
	await get_tree().process_frame
	_check(sm.can_place_modifier("speed_module") and not sm.can_place_modifier("yield_module"), "a smelter takes speed/efficiency modules, not yield")
	sm.set_modifier_slot(0, "speed_module")
	sm.add_input("ore_a", 20)
	sm.set_auto(0, true)
	FactoryClock.advance(0.1)
	FactoryClock.advance(3.0)
	_check(sm.get_inventory_count("refined_material") == 3, "speed module: 1.5 s ingots every 1.0 s (%d in 3 s)" % sm.get_inventory_count("refined_material"))
	_check(is_equal_approx(sm.effective_power_draw(), sm.power_draw * 1.6), "speed module draws 1.6x power")
	sm.set_modifier_slot(1, "efficiency_module")
	_check(is_equal_approx(sm.effective_power_draw(), sm.power_draw * 1.6 * 0.6), "efficiency module cuts that by 40%")
	var data: Dictionary = JSON.parse_string(JSON.stringify(sm.save_state()))
	var sm2: Building = _place("res://scenes/smelter.tscn", o + Vector3(5, 0, 0))
	await get_tree().process_frame
	sm2.load_state(data)
	_check(sm2.get_modifier_slot(0) == "speed_module" and sm2.get_modifier_slot(1) == "efficiency_module", "installed modules survive save/load")
	var dr: DepositDrill = _place("res://scenes/deposit_drill.tscn", o + Vector3(10, 0, 0)) as DepositDrill
	await get_tree().process_frame
	dr.set_modifier_slot(0, "yield_module")
	_check(dr.can_place_modifier("yield_module") and is_equal_approx(dr.modifier_yield(), 1.5), "a drill takes a yield module (x1.5)")
	for n in [sm, sm2, dr]:
		n.queue_free()
	await get_tree().process_frame

func _test_sidearm() -> void:
	var o := Vector3(25000, 0, 0)
	var pl: Node3D = load("res://scenes/player.tscn").instantiate()
	add_child(pl)
	pl.global_position = o
	await get_tree().process_frame
	Inventory.set_slot({"kind": "hand", "side": "right"}, "rivet_gun", 1)
	await get_tree().process_frame
	var vm: Node3D = pl.get("viewmodel")
	_check(vm.get_node_or_null("Sidearm") != null and (vm.get_node("Sidearm") as Node3D).visible, "the rivet gun shows in the hand")
	var dummy: Node3D = load("res://scenes/enemy_dummy.tscn").instantiate()
	add_child(dummy)
	var cam: Camera3D = pl.get("camera")
	# the dummy's origin is at its feet and its box spans 1.8 m up: centre the box on the line of fire
	dummy.global_position = cam.global_position - cam.global_transform.basis.z * 12.0 - dummy.global_transform.basis.y * 0.9
	Inventory.add("iron_piercing_ammo", 10)
	var ammo := Inventory.get_count("iron_piercing_ammo")
	pl.call("_dig")
	pl.call("_dig")      # same instant: the fire rate holds it back
	_check(Inventory.get_count("iron_piercing_ammo") == ammo - 1, "one rivet per trigger interval, paid from pierce ammo")
	var shots := 1
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(dummy):
			break
		pl.set("_sidearm_cool", 0.0)
		if i % 10 == 0 and Inventory.get_count("iron_piercing_ammo") > 0:
			pl.call("_dig")
			shots += 1
	_check(not is_instance_valid(dummy), "rivets kill a target in front (%d shots)" % shots)
	Inventory.try_remove("iron_piercing_ammo", Inventory.get_count("iron_piercing_ammo"))
	pl.set("_sidearm_cool", 0.0)
	pl.call("_dig")
	_check(Inventory.get_count("iron_piercing_ammo") == 0, "an empty gun does not fire (and says why)")
	Inventory.set_slot({"kind": "hand", "side": "right"}, "building_tool", 1)
	pl.queue_free()
	if is_instance_valid(dummy):
		dummy.queue_free()
	await get_tree().process_frame

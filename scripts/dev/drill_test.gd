extends Node
## Deposit drill on REAL terrain, headless (no rendering, so it runs in well under a minute):
##   godot --headless --path . res://scenes/dev/drill_test.tscn     (tools/run_tests.sh drill)
## Places a DepositDrill on the planet surface at the spawn direction (radial, no world-Y), bores N bites and
## checks it cuts, advances, pays, survives save/load, and keeps going on the FactoryClock.
var _fails := 0

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	var guard := 0
	while (planet == null or not planet.get("is_terrain_ready")) and guard < 6000:
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
		guard += 1
	var terrain: VoxelLodTerrain = planet.get("terrain")
	var tool := terrain.get_voxel_tool()
	# terrain streams around the player's viewer, so drill next to wherever the player landed
	var player: Node3D = null
	guard = 0
	while guard < 9000:
		player = get_tree().get_first_node_in_group("player")
		if player != null and player.is_spawn_resolved():
			break
		await get_tree().process_frame
		guard += 1
	_check(player != null and player.is_spawn_resolved(), "player landed (terrain streamed)")
	if player == null:
		return _done()
	var pup := PlanetPhysics.get_up(player.global_position)
	var fwd := player.global_transform.basis.z
	fwd = (fwd - pup * fwd.dot(pup)).normalized()
	var probe := player.global_position + fwd * 6.0
	var hit: VoxelRaycastResult = tool.raycast(probe + pup * 10.0, -pup, 40.0)
	_check(hit != null, "found the surface by voxel raycast")
	if hit == null:
		return _done()
	var ground := terrain.to_global(Vector3(hit.position) + Vector3.ONE * 0.5)
	var up := PlanetPhysics.get_up(ground)
	var tangent := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	FactoryClock.speed = 0.0
	var drill: DepositDrill = load("res://scenes/deposit_drill.tscn").instantiate()
	add_child(drill)
	drill.global_transform = Transform3D(Basis.looking_at(tangent, up), ground)
	drill.keep_stone = true
	var start_head := drill.head_position()
	var solid0 := _solid(tool, terrain, start_head)
	var t_bite := 0.0
	var n := 0
	var reached := 0.0
	for i in 400:
		var t0 := Time.get_ticks_usec()
		drill.bite_once()
		t_bite += float(Time.get_ticks_usec() - t0)
		n += 1
		reached = maxf(reached, drill.depth_m + drill.shaft * 100.0)
		if drill.idle_reason() != "":
			print("blocked: ", drill.idle_reason())
			await get_tree().process_frame
		if i % 40 == 0:
			await get_tree().process_frame
	var total := 0
	for id: String in drill.mined:
		total += int(drill.mined[id])
	var ms := t_bite / 1000.0 / float(n)
	print("DRILL %d bites: depth %.1f m shaft %d, mined %s, %.2f ms/bite, head solid %.2f -> %.2f" % [n, drill.depth_m,
		drill.shaft, drill.mined, ms, solid0, _solid(tool, terrain, start_head)])
	_check(drill.idle_reason() == "" or drill.exhausted, "drill sees editable terrain (%s)" % drill.idle_reason())
	_check(solid0 > 0.5 and _solid(tool, terrain, start_head) < 0.3, "rock at the first head position is gone")
	_check(reached > DepositDrill.START_DEPTH_M + 3.0, "head advanced more than 3 m in %d bites (%.1f)" % [n, reached])
	_check(total > 0 and drill.get_total_count() == total, "drill paid %d items into its output" % total)
	_check(ms < 25.0, "a bite costs %.2f ms (budget 25)" % ms)
	var down := (drill.global_position - drill.head_position()).normalized().dot(up)
	_check(drill.shaft > 0 or down > 0.99, "shaft follows radial down (%.3f)" % down)
	# a fresh drill keeps boring on the clock alone
	FactoryClock.speed = 1.0
	var bites_before := drill.bites_total
	await get_tree().create_timer(3.0).timeout
	var clock_bites := drill.bites_total - bites_before
	_check(clock_bites >= 8 and clock_bites <= 16, "FactoryClock drives the drill at 4 bites/s (%d in 3 s)" % clock_bites)
	# power through a real grid: a pole and a fuelled burner generator next to it double the bite rate
	var pole: Building = load("res://scenes/power_pole.tscn").instantiate()
	add_child(pole)
	pole.global_transform = drill.global_transform.translated(tangent * 3.0)
	var gen: Building = load("res://scenes/burner_generator.tscn").instantiate()
	add_child(gen)
	gen.global_transform = drill.global_transform.translated(tangent * 6.0)
	gen.add_input("ore_coal", 20)
	await get_tree().process_frame
	PowerNetwork.rebuild()
	bites_before = drill.bites_total
	await get_tree().create_timer(3.0).timeout
	clock_bites = drill.bites_total - bites_before
	_check(clock_bites >= 20 and clock_bites <= 28, "on a powered grid the drill bites twice as fast (%d in 3 s)" % clock_bites)
	# a drill that needs power, cut off, stops and says so
	pole.queue_free()
	drill.needs_power = true
	await get_tree().process_frame
	PowerNetwork.rebuild()
	await get_tree().create_timer(0.3).timeout
	bites_before = drill.bites_total
	await get_tree().create_timer(1.0).timeout
	_check(drill.bites_total == bites_before and drill.idle_reason() == "No power", "no power, no bites, and it says so")
	drill.needs_power = false
	gen.queue_free()
	# save / load mid-shaft keeps going from the same spot
	var data := JSON.parse_string(JSON.stringify(drill.save_state())) as Dictionary
	var d3: DepositDrill = load("res://scenes/deposit_drill.tscn").instantiate()
	add_child(d3)
	d3.global_transform = drill.global_transform
	d3.load_state(data)
	_check(is_equal_approx(d3.depth_m, drill.depth_m) and d3.shaft == drill.shaft and d3.keep_stone, "drill resumes the same shaft after a JSON save/load")
	d3.queue_free()
	# void stone by default
	var d2: DepositDrill = load("res://scenes/deposit_drill.tscn").instantiate()
	add_child(d2)
	d2.global_transform = Transform3D(Basis.looking_at(tangent, up), ground + tangent * 8.0 - up * 0.0)
	FactoryClock.speed = 0.0
	for i in 200:
		d2.bite_once()
	_check(d2.get_inventory_count("stone") == 0, "stone is voided unless 'Keep stone' is on")
	_done()

func _solid(tool: VoxelTool, terrain: Node3D, world: Vector3) -> float:
	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	return clampf(0.5 - tool.get_voxel_f(Vector3i(terrain.to_local(world).round())), 0.0, 1.0)

func _done() -> void:
	print("DRILLTEST DONE fails=%d" % _fails)
	get_tree().quit(_fails)

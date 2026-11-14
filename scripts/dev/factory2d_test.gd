extends Node

## The 2D factory loop on a hand-made map: drill -> belts -> smelter -> belts -> chest, placement rules, paying,
## dismantle refunds, save/load of buildings and belts.
##   godot --headless --path . res://scenes/dev/factory2d_test.tscn

var _fails := 0

func _ready() -> void:
	var g := WorldGrid.new(48, 24)
	for t: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		g.ore[g.idx(t.x, t.y)] = 1
		g.ore_amount[g.idx(t.x, t.y)] = 30
	g.set_level(30, 15, 2)          # a bump for the flat-ground rule
	var bg := BuildGrid2D.new()
	add_child(bg)
	bg.setup(g, null)

	# --- placement rules
	_check(bg.can_place("deposit_drill", Vector2i(10, 15), 0) == "Needs ore under it", "a drill needs ore under it")
	_check(bg.can_place("smelter", Vector2i(29, 14), 0) == "Needs flat ground", "machines need flat ground")
	_check(bg.can_place("drone_port", Vector2i(2, 2), 0) == "Not buildable", "unknown ids are refused")

	# --- the line: drill (5,5) 2x2 -> belts x 7..12 at row 5 -> smelter (13,5) 2x2 -> belts 15..19 -> chest (20,5)
	var drill: Building2D = bg.place("deposit_drill", Vector2i(5, 5), 0, false)
	for x in range(7, 13):
		bg.place(BuildGrid2D.BELT, Vector2i(x, 5), 0, false)
	var smelter: Building2D = bg.place("smelter", Vector2i(13, 5), 0, false)
	for x in range(15, 20):
		bg.place(BuildGrid2D.BELT, Vector2i(x, 5), 0, false)
	var chest: Building2D = bg.place("chest", Vector2i(20, 5), 0, false)
	_check(drill != null and smelter != null and chest != null, "drill, smelter and chest placed")
	_check(bg.can_place("chest", Vector2i(6, 6), 0) == "Something is in the way", "can't build on top of a building")

	FactoryClock.advance(40.0)
	var ingots := chest.get_inventory_count("refined_material")
	print("FACTORY drill ore left %d, belts carry %d, smelter %s, chest ingots %d" % [
		_ore_left(g), bg.belts.item_count(), smelter.status_text(), ingots])
	_check(ingots >= 5, "ore goes drill -> belt -> smelter -> belt -> chest as ingots (%d)" % ingots)
	_check(_ore_left(g) < 120, "the drill draws the deposit down (%d of 120 left)" % _ore_left(g))

	# --- save / load round trip
	var state := bg.save_state()
	var bg2 := BuildGrid2D.new()
	add_child(bg2)
	bg2.setup(g, null)
	bg2.load_state(state)
	var chest2 := bg2.building_at(Vector2i(20, 5))
	_check(chest2 != null and chest2.get_inventory_count("refined_material") == ingots and bg2.belts.belts.size() == bg.belts.belts.size(),
		"save/load keeps buildings, contents and belts")
	bg2.queue_free()

	# --- paying and dismantling
	Inventory.add("refined_material", 3)
	var rm0 := Inventory.get_count("refined_material")
	var had_belts := Inventory.get_count(BuildGrid2D.BELT)
	_check(bg.place(BuildGrid2D.BELT, Vector2i(30, 20), 0) != null, "a belt can be paid for")
	_check(Inventory.get_count("refined_material") == rm0 - 1 and Inventory.get_count(BuildGrid2D.BELT) == had_belts + 1,
		"a belt recipe makes 2: one placed, one carried")
	bg.place(BuildGrid2D.BELT, Vector2i(31, 20), 0)
	_check(Inventory.get_count("refined_material") == rm0 - 1, "the carried belt is used before materials")
	var chests0 := Inventory.get_count("chest")
	var ing0 := Inventory.get_count("refined_material")
	_check(bg.dismantle_at(Vector2i(20, 5)), "dismantle the chest")
	_check(Inventory.get_count("chest") == chests0 + 1 and Inventory.get_count("refined_material") == ing0 + ingots,
		"dismantling refunds the chest and everything in it")
	_check(bg.building_at(Vector2i(20, 5)) == null and bg.can_place("chest", Vector2i(20, 5), 0) == "", "the tile is free again")

	print("FACTORY2D DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _ore_left(g: WorldGrid) -> int:
	var n := 0
	for t: Vector2i in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		n += int(g.ore_amount[g.idx(t.x, t.y)])
	return n

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

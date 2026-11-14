extends Node

## 2D save/load (Save2D): a played world goes to disk and comes back the same - dug tiles, drained ore, buildings
## with contents, belts with items, inventory, player - and loading stays inside the 2 s budget.
##   godot --headless --path . res://scenes/dev/save2d_test.tscn

const SLOT := "_test2d"
var _fails := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(Save2D.slot_dir(SLOT))
	var w := _world(true)
	add_child(w)
	await get_tree().process_frame
	var t := w.player.tile()
	# play a little: dig next to the player, build a drill-less line, put things in a chest
	var dig := t + Vector2i(2, 0)
	Mining2D.dig(w.grid, dig.x, dig.y)
	var chest: Variant = w.build.place("chest", t + Vector2i(-2, 2), 0, false)
	(chest as Building2D).add_input("ore_a", 7)
	w.build.place(BuildGrid2D.BELT, t + Vector2i(-1, 2), 2, false)
	w.build.belts.insert(t + Vector2i(-1, 2), "stone")
	Inventory.add("ore_b", 5)
	var inv_b := Inventory.get_count("ore_b")
	var h := w.grid.data_hash()
	var pos := w.player.position
	_check(w.save_game(), "save writes the slot")
	w.queue_free()
	await get_tree().process_frame
	Inventory.load_state({})        # forget, so the load has to bring it back

	var w2 := _world(false)
	add_child(w2)
	await get_tree().process_frame
	_check(w2.loaded, "a new scene continues the save")
	_check(w2.load_ms < 2000.0, "load is under 2 s (%.0f ms)" % w2.load_ms)
	_check(w2.grid.data_hash() == h, "the tile map comes back exactly (dug tile level %d)" % w2.grid.level_at(dig.x, dig.y))
	var c2 := w2.build.building_at(t + Vector2i(-2, 2))
	_check(c2 != null and c2.get_inventory_count("ore_a") == 7, "the chest comes back with its 7 iron")
	_check(w2.build.belts.item_count() == 1, "the belt comes back with its item")
	_check(Inventory.get_count("ore_b") == inv_b, "the inventory comes back (copper %d)" % Inventory.get_count("ore_b"))
	_check(w2.player.position.distance_to(pos) < 1.0, "the player is where they saved")
	w2.queue_free()
	await get_tree().process_frame
	for f in ["state.json", "world.bin"]:
		DirAccess.remove_absolute(Save2D.slot_dir(SLOT) + "/" + f)
	DirAccess.remove_absolute(Save2D.slot_dir(SLOT))
	print("SAVE2D DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _world(new_game: bool) -> GameWorld2D:
	var w: GameWorld2D = load("res://scenes/world2d.tscn").instantiate()
	w.slot = SLOT
	w.force_new = new_game
	return w

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

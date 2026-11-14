class_name Save2D
extends RefCounted

## Save format v2 for the 2D game (pivot-2d.md M34): one folder per slot under user://saves2d/
##   world.bin   the whole tile grid (WorldGrid.to_bytes, zstd) - dug holes, drained ore, everything
##   state.json  version, seed, size, player, inventory, research, quests, signature, buildings, belts
## Loading never regenerates the map, so it stays well inside the 2 s budget.

const DIR := "user://saves2d"
const VERSION := 2

static func slot_dir(slot: String) -> String:
	return "%s/%s" % [DIR, slot]

static func exists(slot: String) -> bool:
	return FileAccess.file_exists(slot_dir(slot) + "/state.json") and FileAccess.file_exists(slot_dir(slot) + "/world.bin")

static func save(w: GameWorld2D, slot: String) -> bool:
	DirAccess.make_dir_recursive_absolute(slot_dir(slot))
	var f := FileAccess.open(slot_dir(slot) + "/world.bin", FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(w.grid.to_bytes())
	f.close()
	var state := {
		"version": VERSION,
		"seed": w.grid.seed_value,
		"size": [w.grid.width, w.grid.height],
		"player": {"pos": [w.player.position.x, w.player.position.y], "level": w.player.level},
		"inventory": Inventory.save_state(),
		"progression": Progression.save_state(),
		"quests": QuestManager.save_state(),
		"signature": RadiationSignature.save_state(),
		"build": w.build.save_state(),
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var j := FileAccess.open(slot_dir(slot) + "/state.json", FileAccess.WRITE)
	if j == null:
		return false
	j.store_string(JSON.stringify(state))
	j.close()
	return true

## Reads a slot: {"grid": WorldGrid, "state": Dictionary} or {} if it is missing or broken.
static func read(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_dir(slot) + "/state.json"))
	if not (parsed is Dictionary) or int(parsed.get("version", 0)) != VERSION:
		return {}
	var st: Dictionary = parsed
	var g := WorldGrid.new(int(st["size"][0]), int(st["size"][1]))
	g.seed_value = int(st.get("seed", 0))
	g.from_bytes(FileAccess.get_file_as_bytes(slot_dir(slot) + "/world.bin"))
	return {"grid": g, "state": st}

## Applies the game-level part of a save (everything but the grid, the player and the buildings).
static func apply_game_state(st: Dictionary) -> void:
	Inventory.load_state(st.get("inventory", {}))
	Progression.load_state(st.get("progression", {}))
	QuestManager.load_state(st.get("quests", {}))
	RadiationSignature.load_state(st.get("signature", {}))

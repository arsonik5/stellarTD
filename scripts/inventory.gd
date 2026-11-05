extends Node

signal changed

const GRID_COLS := 6
const GRID_ROWS := 4
const GRID_SIZE := GRID_COLS * GRID_ROWS

const ITEM_DEFS_LIST := [
	preload("res://data/items/ore_a.tres"),
	preload("res://data/items/ore_b.tres"),
	preload("res://data/items/refined_material.tres"),
	preload("res://data/items/refined_copper_ingot.tres"),
	preload("res://data/items/placeable_block.tres"),
	preload("res://data/items/mining_tool.tres"),
	preload("res://data/items/scanner_tool.tres"),
	preload("res://data/items/building_tool.tres"),
	preload("res://data/items/basic_crafter.tres"),
	preload("res://data/items/sulfur.tres"),
	preload("res://data/items/smelter.tres"),
	preload("res://data/items/chest.tres"),
	preload("res://data/items/constructor.tres"),
	preload("res://data/items/piercing_core.tres"),
	preload("res://data/items/copper_casing.tres"),
	preload("res://data/items/gunpowder.tres"),
	preload("res://data/items/iron_piercing_ammo.tres"),
	preload("res://data/items/vacuum_pipe.tres"),
	preload("res://data/items/merger.tres"),
	preload("res://data/items/splitter.tres"),
	preload("res://data/items/ore_coal.tres"),
	preload("res://data/items/ore_silica.tres"),
	preload("res://data/items/refined_carbon.tres"),
	preload("res://data/items/refined_silica.tres"),
	preload("res://data/items/metal_foundation.tres"),
	preload("res://data/items/foundation_1m.tres"),
	preload("res://data/items/foundation_2m.tres"),
	preload("res://data/items/frame_2m.tres"),
	preload("res://data/items/ramp_1m.tres"),
	preload("res://data/items/stairs_1m.tres"),
	preload("res://data/items/turret_gun.tres"),
	preload("res://data/items/turret_cannon.tres"),
	preload("res://data/items/he_shell.tres"),
	preload("res://data/items/ore_crystal.tres"),
	preload("res://data/items/stone.tres"),
	preload("res://data/items/ship_core.tres"),
	preload("res://data/items/ship_hull.tres"),
	preload("res://data/items/ship_thruster.tres"),
	preload("res://data/items/ship_gyroscope.tres"),
	preload("res://data/items/ship_cockpit.tres"),
	preload("res://data/items/ship_garage.tres"),
	preload("res://data/items/copper_wire.tres"),
	preload("res://data/items/steel_ingot.tres"),
	preload("res://data/items/circuit.tres"),
	preload("res://data/items/gravel.tres"),
	preload("res://data/items/concrete.tres"),
	preload("res://data/items/crystal_cell.tres"),
	preload("res://data/items/deposit_drill.tres"),
	preload("res://data/items/crusher.tres"),
	preload("res://data/items/uplink.tres"),
	preload("res://data/items/power_pole.tres"),
	preload("res://data/items/burner_generator.tres"),
	preload("res://data/items/solar_panel.tres"),
	preload("res://data/items/battery_bank.tres"),
	preload("res://data/items/crystal_reactor.tres"),
	preload("res://data/items/alien_alloy.tres"),
	preload("res://data/items/wreck.tres"),
]

var _item_defs: Dictionary = {}
var _grid: Array[Dictionary] = []
var _hands: Dictionary = {
	"left": {"item_id": "", "count": 0},
	"right": {"item_id": "", "count": 0},
}

func _ready() -> void:
	for item: Item in ITEM_DEFS_LIST + ShipParts.ITEMS:
		_item_defs[item.id] = item
	for i in GRID_SIZE:
		_grid.append({"item_id": "", "count": 0})
	set_slot({"kind": "hand", "side": "left"}, "mining_tool", 1)
	set_slot({"kind": "hand", "side": "right"}, "building_tool", 1)
	# Into the grid, not a hand slot - both hands are already taken, and the
	# scanner is something you swap in when you go prospecting rather than
	# carry drawn. Granted at start because ore deposits are sparse and mostly
	# buried, so without it a new game has no way to find anything below the
	# surface patches.
	add("scanner_tool", 1)

## --- Back-compat resource-counter API (used by player.gd/processor.gd/debug_ui.gd) ---

func get_count(item_id: String) -> int:
	var total := 0
	for slot in _grid:
		if slot.item_id == item_id:
			total += slot.count
	return total

func add(item_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var item: Item = _item_defs.get(item_id)
	var max_stack: int = item.max_stack if item != null else 100
	var remaining := amount

	for slot in _grid:
		if remaining <= 0:
			break
		if slot.item_id == item_id and slot.count < max_stack:
			var take: int = min(max_stack - slot.count, remaining)
			slot.count += take
			remaining -= take

	for slot in _grid:
		if remaining <= 0:
			break
		if slot.item_id == "":
			var take: int = min(max_stack, remaining)
			slot.item_id = item_id
			slot.count = take
			remaining -= take

	var added := amount - remaining
	if added > 0:
		changed.emit()
		GameEvents.item_added.emit(item_id, added)
	return added

func try_remove(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if get_count(item_id) < amount:
		return false

	var remaining := amount
	for slot in _grid:
		if remaining <= 0:
			break
		if slot.item_id == item_id:
			var take: int = min(slot.count, remaining)
			slot.count -= take
			remaining -= take
			if slot.count <= 0:
				slot.item_id = ""
				slot.count = 0

	changed.emit()
	GameEvents.item_removed.emit(item_id, amount)
	return true

## --- Slot-based API (inventory UI, hand slots) ---

func get_item_def(item_id: String) -> Item:
	return _item_defs.get(item_id)

func get_slot(ref: Dictionary) -> Dictionary:
	if ref.kind == "grid":
		return _grid[ref.index]
	return _hands[ref.side]

func set_slot(ref: Dictionary, item_id: String, count: int) -> void:
	var target: Dictionary = get_slot(ref)
	if count <= 0:
		item_id = ""
		count = 0
	target.item_id = item_id
	target.count = count
	changed.emit()

func can_place(ref: Dictionary, item_id: String) -> bool:
	if item_id == "":
		return true
	if ref.kind == "hand":
		var item := get_item_def(item_id)
		return item != null and (item.is_tool or item.is_ship_core or item.is_ship_block)
	return true

## "left", "right" or "" - which hand holds this tool.
func hand_holding(item_id: String) -> String:
	for side in ["right", "left"]:
		if _hands[side].item_id == item_id:
			return side
	return ""

func has_tool_equipped(item_id: String) -> bool:
	return _hands["left"].item_id == item_id or _hands["right"].item_id == item_id

## --- Persistence (see scripts/save/save_manager.gd) ---
##
## Only the slot contents are stored, never the Item resources themselves: item
## ids are the stable identity across versions, and a saved copy of a .tres
## would go stale the moment a recipe or stack size changed.

func save_state() -> Dictionary:
	var grid: Array = []
	for slot in _grid:
		grid.append({"item_id": slot.item_id, "count": slot.count})
	return {
		"grid": grid,
		"hands": {
			"left": {"item_id": _hands.left.item_id, "count": _hands.left.count},
			"right": {"item_id": _hands.right.item_id, "count": _hands.right.count},
		},
	}

func load_state(data: Dictionary) -> void:
	var grid: Array = data.get("grid", [])
	for i in GRID_SIZE:
		# Tolerates a saved grid of a different size than the current build's,
		# so changing GRID_COLS/ROWS later degrades to "some slots empty"
		# instead of crashing on an old save.
		var src: Dictionary = grid[i] if i < grid.size() else {}
		_grid[i].item_id = String(src.get("item_id", ""))
		_grid[i].count = int(src.get("count", 0))
	var hands: Dictionary = data.get("hands", {})
	for side in ["left", "right"]:
		var src: Dictionary = hands.get(side, {})
		_hands[side].item_id = String(src.get("item_id", ""))
		_hands[side].count = int(src.get("count", 0))
	changed.emit()

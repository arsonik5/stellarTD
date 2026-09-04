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
	preload("res://data/items/turret_gun.tres"),
	preload("res://data/items/turret_cannon.tres"),
	preload("res://data/items/he_shell.tres"),
	preload("res://data/items/ore_crystal.tres"),
]

var _item_defs: Dictionary = {}
var _grid: Array[Dictionary] = []
var _hands: Dictionary = {
	"left": {"item_id": "", "count": 0},
	"right": {"item_id": "", "count": 0},
}

func _ready() -> void:
	for item: Item in ITEM_DEFS_LIST:
		_item_defs[item.id] = item
	for i in GRID_SIZE:
		_grid.append({"item_id": "", "count": 0})
	set_slot({"kind": "hand", "side": "left"}, "mining_tool", 1)
	set_slot({"kind": "hand", "side": "right"}, "building_tool", 1)

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
	target.item_id = item_id
	target.count = count
	changed.emit()

func can_place(ref: Dictionary, item_id: String) -> bool:
	if item_id == "":
		return true
	if ref.kind == "hand":
		var item := get_item_def(item_id)
		return item != null and item.is_tool
	return true

func has_tool_equipped(item_id: String) -> bool:
	return _hands["left"].item_id == item_id or _hands["right"].item_id == item_id

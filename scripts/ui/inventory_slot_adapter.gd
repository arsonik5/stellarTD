class_name InventorySlotAdapter
extends RefCounted

## SlotCarry adapter over the player's Inventory autoload. One instance
## covers either the 24-slot grid or the 2 hand slots (index 0=left,
## 1=right) depending on `kind` - both inventory_ui.gd and building_ui.gd's
## player-inventory panel share these same two adapter instances/kinds
## rather than each hand-rolling their own grid/hand addressing.

enum Kind { GRID, HAND }

var kind: Kind

func _init(k: Kind) -> void:
	kind = k

func _ref(index: int) -> Dictionary:
	if kind == Kind.GRID:
		return {"kind": "grid", "index": index}
	return {"kind": "hand", "side": "left" if index == 0 else "right"}

func get_slot(index: int) -> Dictionary:
	return Inventory.get_slot(_ref(index))

func set_slot(index: int, item_id: String, count: int) -> void:
	Inventory.set_slot(_ref(index), item_id, count)

## Amount is irrelevant here - the player's Inventory has no total-capacity
## concept, only per-slot stacking (already handled generically by SlotCarry
## via get_max_stack) and hand slots only accepting tools (Inventory.can_place).
func can_accept_at(index: int, item_id: String, _amount: int) -> bool:
	return Inventory.can_place(_ref(index), item_id)

func get_room(_item_id: String) -> int:
	return 999999

func get_max_stack(item_id: String) -> int:
	var item := Inventory.get_item_def(item_id)
	return item.max_stack if item != null else 100

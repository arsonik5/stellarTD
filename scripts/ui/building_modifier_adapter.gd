class_name BuildingModifierAdapter
extends RefCounted

## SlotCarry adapter over a Building's single-item modifier slots
## (get_modifier_slot/set_modifier_slot/can_place_modifier). No stacking -
## reported as max_stack 1, which makes SlotCarry's generic merge logic
## behave correctly ("occupied slot of the same item" is never mergeable)
## without this adapter needing any special-casing of its own.

var building: Building

func _init(b: Building) -> void:
	building = b

func get_slot(index: int) -> Dictionary:
	var item_id := building.get_modifier_slot(index)
	return {"item_id": item_id, "count": 1 if item_id != "" else 0}

func set_slot(index: int, item_id: String, count: int) -> void:
	building.set_modifier_slot(index, item_id if count > 0 else "")

func can_accept_at(_index: int, item_id: String, _amount: int) -> bool:
	return building.can_place_modifier(item_id)

func get_room(_item_id: String) -> int:
	return 999999

func get_max_stack(_item_id: String) -> int:
	return 1

class_name BuildingInventoryAdapter
extends RefCounted

## SlotCarry adapter over a Building's main stacked inventory
## (get_inventory_slot/set_slot/can_accept_input) - the same one Chest,
## Constructor, Turret's ammo box, etc. all already share via the Building
## base class, so this adapter (and therefore every slot UI built on it)
## works identically for all of them with zero building-specific code here.

var building: Building

func _init(b: Building) -> void:
	building = b

func get_slot(index: int) -> Dictionary:
	return building.get_inventory_slot(index)

func set_slot(index: int, item_id: String, count: int) -> void:
	building.set_slot(index, item_id, count)

func can_accept_at(_index: int, item_id: String, amount: int) -> bool:
	return building.can_accept_input(item_id, amount)

func get_room(item_id: String) -> int:
	# Probing with amount=0 isolates "is item_id even a type this building
	# accepts" from the capacity math (every can_accept_input override folds
	# both into one bool) - an incompatible item correctly gets 0 room here
	# rather than falsely reporting free space it could never actually use.
	if not building.can_accept_input(item_id, 0):
		return 0
	return maxi(building.inventory_capacity - building.get_total_count(), 0)

func get_max_stack(item_id: String) -> int:
	var item := Inventory.get_item_def(item_id)
	return item.max_stack if item != null else 100

class_name SlotCarry
extends RefCounted

## The ONE click-to-carry/place/merge/swap interaction, shared by every
## slot-based UI in the game (inventory_ui.gd's player grid+hands,
## building_ui.gd's building inventory, player-inventory panel, and modifier
## slots). Container-agnostic: driven entirely through a small duck-typed
## adapter contract so it works identically against the player's Inventory
## autoload, a Building's stacked inventory, or a Building's single-item
## modifier slots without knowing which one it's talking to.
##
## Adapter contract (see inventory_slot_adapter.gd / building_inventory_adapter.gd
## / building_modifier_adapter.gd for the concrete implementations):
##   get_slot(index: int) -> {"item_id": String, "count": int}
##   set_slot(index: int, item_id: String, count: int) -> void
##   can_accept_at(index: int, item_id: String, amount: int) -> bool
##   get_room(item_id: String) -> int   # more this container could hold in
##                                      # total, a big number if uncapped
##   get_max_stack(item_id: String) -> int
##
## Existing before this: three independent hand-rolled copies of this exact
## interaction had already drifted from each other (inventory_ui.gd allowed
## swapping two different stacks, building_ui.gd's building-slot version
## silently refused it; carried-item labels used raw item_id in one place
## and display_name in another). One implementation now, so a fix/feature
## here reaches every slot UI in the game instead of some of them.

signal changed

var carried_item_id := ""
var carried_count := 0

var _origin_container = null
var _origin_index := -1

func has_carried() -> bool:
	return carried_item_id != ""

## Click on a slot: picks up if empty-handed and the slot has something,
## otherwise tries to place/merge/swap the carried stack into it.
func click(container, index: int) -> void:
	if not has_carried():
		_pick_up(container, index)
	else:
		_place(container, index)
	changed.emit()

func return_to_origin() -> void:
	if not has_carried():
		return
	if _origin_container != null:
		_origin_container.set_slot(_origin_index, carried_item_id, carried_count)
	_clear()
	changed.emit()

func _pick_up(container, index: int) -> void:
	var slot: Dictionary = container.get_slot(index)
	if slot.item_id == "":
		return
	carried_item_id = slot.item_id
	carried_count = slot.count
	_origin_container = container
	_origin_index = index
	container.set_slot(index, "", 0)

func _place(container, index: int) -> void:
	var slot: Dictionary = container.get_slot(index)
	if slot.item_id == "" or slot.item_id == carried_item_id:
		var max_stack: int = container.get_max_stack(carried_item_id)
		var stack_room: int = max_stack if slot.item_id == "" else max_stack - slot.count
		var move: int = min(carried_count, stack_room, container.get_room(carried_item_id))
		if move <= 0:
			return
		if not container.can_accept_at(index, carried_item_id, move):
			return
		container.set_slot(index, carried_item_id, slot.count + move)
		carried_count -= move
		if carried_count <= 0:
			_clear()
		return

	# Target holds a different item - swap, if both sides would actually
	# accept what they're about to receive (origin must take back what's
	# being displaced, matching what a "cancel" via return_to_origin() would
	# need to be able to do anyway).
	var other_id: String = slot.item_id
	var other_count: int = slot.count
	var net_delta := carried_count - other_count
	if net_delta > 0 and container.get_room(carried_item_id) < net_delta:
		return
	if not container.can_accept_at(index, carried_item_id, carried_count):
		return
	if _origin_container != null and not _origin_container.can_accept_at(_origin_index, other_id, other_count):
		return
	container.set_slot(index, carried_item_id, carried_count)
	carried_item_id = other_id
	carried_count = other_count
	_origin_container = container
	_origin_index = index

func _clear() -> void:
	carried_item_id = ""
	carried_count = 0
	_origin_container = null
	_origin_index = -1

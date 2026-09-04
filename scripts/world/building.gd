class_name Building
extends StaticBody3D

signal changed

@export var inventory_capacity: int = 100
@export var inventory_slots: int = 20
@export var input_capacity: int = 15
@export var output_capacity: int = 15
@export var output_multiplier: int = 1
@export var modifier_slots: int = 4
@export var compatible_modifiers: Array[String] = []
@export var recipes: Array[Recipe] = []
@export var accepts_any_item: bool = false

var _inventory: Array[Dictionary] = []
var _modifiers: Array[String] = []
var _timer: Timer
var _active_recipe_index: int = -1
var _auto_recipes: Array[bool] = []
var _last_auto_index: int = -1
var _mesh_instances: Array[MeshInstance3D] = []
var _highlight_material: StandardMaterial3D

func _ready() -> void:
	for i in inventory_slots:
		_inventory.append({"item_id": "", "count": 0})
	for i in modifier_slots:
		_modifiers.append("")
	for i in recipes.size():
		_auto_recipes.append(false)
	add_to_group("building")
	if not recipes.is_empty():
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.timeout.connect(_on_process_timeout)
		add_child(_timer)

	_mesh_instances.assign(find_children("*", "MeshInstance3D", true, false))
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(1.0, 1.0, 0.4, 0.35)
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

## Drawn as an overlay pass (doesn't replace the base material) so it works
## the same regardless of what each building's mesh material actually is.
func set_highlighted(active: bool) -> void:
	for mesh in _mesh_instances:
		mesh.material_overlay = _highlight_material if active else null

func _process(_delta: float) -> void:
	if recipes.is_empty() or _timer == null or not _timer.is_stopped() or _active_recipe_index != -1:
		return
	for offset in recipes.size():
		var index := (_last_auto_index + 1 + offset) % recipes.size()
		if _auto_recipes[index] and process_recipe(index):
			return

func set_auto(index: int, enabled: bool) -> void:
	if index >= 0 and index < _auto_recipes.size():
		_auto_recipes[index] = enabled

func get_auto(index: int) -> bool:
	return _auto_recipes[index] if index >= 0 and index < _auto_recipes.size() else false

func get_active_recipe_index() -> int:
	return _active_recipe_index

## 0..1 fraction of the active recipe's process_time elapsed so far, 0 when idle.
func get_process_progress() -> float:
	if _active_recipe_index == -1 or _timer == null or _timer.wait_time <= 0.0:
		return 0.0
	return clampf(1.0 - (_timer.time_left / _timer.wait_time), 0.0, 1.0)

func process_recipe(recipe_index: int = 0) -> bool:
	if recipe_index < 0 or recipe_index >= recipes.size() or _timer == null or not _timer.is_stopped():
		return false
	var recipe: Recipe = recipes[recipe_index]
	var output_amount := recipe.output_amount * output_multiplier
	for i in recipe.input_ids.size():
		if get_inventory_count(recipe.input_ids[i]) < recipe.input_amounts[i]:
			return false
	if not can_add_output(recipe.output_id, output_amount):
		return false
	for i in recipe.input_ids.size():
		remove_item(recipe.input_ids[i], recipe.input_amounts[i])
	_active_recipe_index = recipe_index
	_last_auto_index = recipe_index
	_timer.wait_time = max(recipe.process_time, 0.05)
	_timer.start()
	return true

func _on_process_timeout() -> void:
	if _active_recipe_index != -1:
		var recipe: Recipe = recipes[_active_recipe_index]
		add_output(recipe.output_id, recipe.output_amount * output_multiplier)
		_active_recipe_index = -1

func interact() -> void:
	var building_ui := get_tree().get_first_node_in_group("building_ui")
	if building_ui != null:
		building_ui.show_for(self)

func get_inventory_slot(index: int) -> Dictionary:
	return _inventory[index]

func get_modifier_slot(index: int) -> String:
	return _modifiers[index]

## A modifier slot holds at most one of a single item id (no stacking, unlike
## the main inventory) - an empty item_id clears the slot. Not gated on
## can_place_modifier() itself so a slot can always be cleared regardless of
## compatibility; building_ui.gd checks compatibility before calling this
## with a non-empty id.
func set_modifier_slot(index: int, item_id: String) -> void:
	_modifiers[index] = item_id
	changed.emit()

## Empty compatible_modifiers means "doesn't accept any modifier yet" (a
## building has to opt in), not "accepts anything" - matches how
## Turret.compatible_ammo works, and stays honest about which buildings
## actually have modifier content designed for them yet.
func can_place_modifier(item_id: String) -> bool:
	return compatible_modifiers.has(item_id)

func set_slot(index: int, item_id: String, count: int) -> void:
	_inventory[index].item_id = item_id
	_inventory[index].count = count
	changed.emit()

func get_inventory_count(item_id: String) -> int:
	var total := 0
	for slot in _inventory:
		if slot.item_id == item_id:
			total += slot.count
	return total

func get_input_count() -> int:
	if accepts_any_item:
		return get_total_count()
	var seen_ids: Dictionary = {}
	for recipe in recipes:
		for item_id in recipe.input_ids:
			seen_ids[item_id] = true
	var total := 0
	for item_id in seen_ids:
		total += get_inventory_count(item_id)
	return total

func get_output_count() -> int:
	var seen_ids: Dictionary = {}
	for recipe in recipes:
		seen_ids[recipe.output_id] = true
	var total := 0
	for item_id in seen_ids:
		total += get_inventory_count(item_id)
	return total

func get_total_count() -> int:
	var total := 0
	for slot in _inventory:
		total += slot.count
	return total

## input_capacity/output_capacity are informational (meant to read as a
## throughput rate later, e.g. for a power/logistics system) - they do NOT
## gate storage. The only real storage ceiling is inventory_capacity.
func can_accept_input(item_id: String, amount: int) -> bool:
	if accepts_any_item:
		return get_total_count() + amount <= inventory_capacity
	for recipe in recipes:
		if recipe.has_input(item_id):
			return get_total_count() + amount <= inventory_capacity
	return false

func can_add_output(item_id: String, amount: int) -> bool:
	for recipe in recipes:
		if recipe.output_id == item_id:
			return get_total_count() + amount <= inventory_capacity
	return false

func add_input(item_id: String, amount: int) -> int:
	if amount <= 0 or not can_accept_input(item_id, amount):
		return 0
	return _add_item(item_id, amount)

func add_output(item_id: String, amount: int) -> int:
	if amount <= 0 or not can_add_output(item_id, amount):
		return 0
	return _add_item(item_id, amount)

func _add_item(item_id: String, amount: int) -> int:
	var item := Inventory.get_item_def(item_id)
	var max_stack: int = item.max_stack if item != null else 100
	var remaining := amount
	for slot in _inventory:
		if remaining <= 0:
			break
		if slot.item_id == item_id and slot.count < max_stack:
			var moved: int = min(max_stack - slot.count, remaining)
			slot.count += moved
			remaining -= moved
	for slot in _inventory:
		if remaining <= 0:
			break
		if slot.item_id == "":
			var moved: int = min(max_stack, remaining)
			slot.item_id = item_id
			slot.count = moved
			remaining -= moved
	var added := amount - remaining
	if added > 0:
		changed.emit()
	return added

func remove_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if get_inventory_count(item_id) < amount:
		return false
	var remaining := amount
	for slot in _inventory:
		if remaining <= 0:
			break
		if slot.item_id == item_id:
			var moved: int = min(slot.count, remaining)
			slot.count -= moved
			remaining -= moved
			if slot.count == 0:
				slot.item_id = ""
	changed.emit()
	return true

func take_slot(index: int) -> Dictionary:
	var slot := _inventory[index]
	var result := {"item_id": slot.item_id, "count": slot.count}
	if slot.item_id != "":
		slot.item_id = ""
		slot.count = 0
		changed.emit()
	return result

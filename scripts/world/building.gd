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
## Structural health (design G1 / C6). Raids and bombardment damage buildings through the Health contract;
## at zero the building is destroyed WITHOUT refund (dismantling refunds, destruction does not).
@export var max_health: float = 300.0

var _inventory: Array[Dictionary] = []
var _modifiers: Array[String] = []
## Crafting runs on FactoryClock ticks (deterministic, power-scalable), not a per-building Timer.
var _craft_elapsed := 0.0
var _craft_duration := 0.0
## 0..1 speed applied to crafting each tick - power satisfaction plugs in here (design G3). 1 = full speed.
var work_speed := 1.0
var _active_recipe_index: int = -1
var _auto_recipes: Array[bool] = []
var _last_auto_index: int = -1
var _mesh_instances: Array[MeshInstance3D] = []
var _highlight_material: StandardMaterial3D
## The model's "Working" animation (press stroke, robot arm, fans...), played only while a recipe runs.
var _work_player: AnimationPlayer
var _work_anim := ""

func _ready() -> void:
	for i in inventory_slots:
		_inventory.append({"item_id": "", "count": 0})
	for i in modifier_slots:
		_modifiers.append("")
	for i in recipes.size():
		_auto_recipes.append(false)
	add_to_group("building")
	var hp := Health.ensure(self, max_health, "player")
	hp.free_owner_on_death = false
	hp.died.connect(func(_src: Node) -> void: WorldObjects.remove(self))
	if not recipes.is_empty():
		FactoryClock.tick.connect(_on_factory_tick)

	_mesh_instances.assign(find_children("*", "MeshInstance3D", true, false))
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(1.0, 1.0, 0.4, 0.35)
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_setup_work_anim()

func _setup_work_anim() -> void:
	var players := find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_work_player = players[0]
	for anim_name in _work_player.get_animation_list():
		if String(anim_name).begins_with("Working"):
			_work_anim = anim_name
			_work_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
			return

func _update_work_anim() -> void:
	if _work_anim == "":
		return
	var working := _active_recipe_index != -1
	if working and not _work_player.is_playing():
		_work_player.play(_work_anim)
	elif not working and _work_player.is_playing():
		_work_player.pause()

## Drawn as an overlay pass (doesn't replace the base material) so it works
## the same regardless of what each building's mesh material actually is.
func set_highlighted(active: bool) -> void:
	for mesh in _mesh_instances:
		mesh.material_overlay = _highlight_material if active else null

func _process(_delta: float) -> void:
	_update_work_anim()

func _on_factory_tick(dt: float) -> void:
	if _active_recipe_index != -1:
		_craft_elapsed += dt * work_speed
		# small epsilon: 20 x 0.1 must finish a 2.0 s recipe on tick 20, not 21
		if _craft_elapsed >= _craft_duration - 0.0001:
			_finish_craft()
		return
	for offset in recipes.size():
		var index := (_last_auto_index + 1 + offset) % recipes.size()
		if _auto_recipes[index] and process_recipe(index):
			return

## Why this machine is not working right now, "" when it is (machine panels and the idle icon show this).
func idle_reason() -> String:
	if recipes.is_empty():
		return ""
	if _active_recipe_index != -1:
		return "No power" if work_speed <= 0.0 else ""
	var any_auto := false
	for i in recipes.size():
		if not _auto_recipes[i]:
			continue
		any_auto = true
		var recipe: Recipe = recipes[i]
		var has_inputs := true
		for k in recipe.input_ids.size():
			if get_inventory_count(recipe.input_ids[k]) < recipe.input_amounts[k]:
				has_inputs = false
		if has_inputs:
			return "Output full"
	return "Missing input" if any_auto else "Idle"

func set_auto(index: int, enabled: bool) -> void:
	if index >= 0 and index < _auto_recipes.size():
		_auto_recipes[index] = enabled

func get_auto(index: int) -> bool:
	return _auto_recipes[index] if index >= 0 and index < _auto_recipes.size() else false

func get_active_recipe_index() -> int:
	return _active_recipe_index

## 0..1 fraction of the active recipe's process_time elapsed so far, 0 when idle.
func get_process_progress() -> float:
	if _active_recipe_index == -1 or _craft_duration <= 0.0:
		return 0.0
	return clampf(_craft_elapsed / _craft_duration, 0.0, 1.0)

func process_recipe(recipe_index: int = 0) -> bool:
	if recipe_index < 0 or recipe_index >= recipes.size() or _active_recipe_index != -1:
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
	_craft_elapsed = 0.0
	_craft_duration = maxf(recipe.process_time, FactoryClock.TICK)
	return true

func _finish_craft() -> void:
	var recipe: Recipe = recipes[_active_recipe_index]
	var amount := recipe.output_amount * output_multiplier
	add_output(recipe.output_id, amount)
	_active_recipe_index = -1
	_craft_elapsed = 0.0
	GameEvents.item_crafted.emit(recipe.output_id, amount, self)

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

## Item ids a pipe on this building's output side may pull. Machines give their recipe outputs; storage
## (accepts_any_item) gives whatever it holds; extractors override this.
func output_ids() -> Array:
	if accepts_any_item:
		var ids := []
		for slot in _inventory:
			if slot.item_id != "" and not ids.has(slot.item_id):
				ids.append(slot.item_id)
		return ids
	var out := []
	for recipe in recipes:
		if not out.has(recipe.output_id):
			out.append(recipe.output_id)
	return out

## One item for a pipe to carry away: removed from this building and its id returned, or "" if nothing to give.
func pipe_take_one() -> String:
	for id: String in output_ids():
		if get_inventory_count(id) > 0 and remove_item(id, 1):
			return id
	return ""

func take_slot(index: int) -> Dictionary:
	var slot := _inventory[index]
	var result := {"item_id": slot.item_id, "count": slot.count}
	if slot.item_id != "":
		slot.item_id = ""
		slot.count = 0
		changed.emit()
	return result

## --- Persistence (see scripts/save/save_manager.gd) ---
##
## Recipes are saved by INDEX rather than id because that is what the auto
## flags and the running job are keyed on. A recipe list reordered in a later
## build would therefore shift a save's auto toggles; ids would fix that, but
## the running-job index has no id to fall back on, so both stay indices and
## the array is length-clamped on load.

func save_state() -> Dictionary:
	var slots: Array = []
	for slot in _inventory:
		slots.append({"item_id": slot.item_id, "count": slot.count})
	return {
		"inventory": slots,
		"modifiers": _modifiers.duplicate(),
		"auto": _auto_recipes.duplicate(),
		# the running job: its inputs are already consumed, so dropping it on save would delete them
		"job": _active_recipe_index,
		"job_elapsed": _craft_elapsed,
		"hp": (get_node("Health") as Health).health if has_node("Health") else max_health,
	}

func load_state(data: Dictionary) -> void:
	var slots: Array = data.get("inventory", [])
	for i in _inventory.size():
		var src: Dictionary = slots[i] if i < slots.size() else {}
		_inventory[i].item_id = String(src.get("item_id", ""))
		_inventory[i].count = int(src.get("count", 0))
	var mods: Array = data.get("modifiers", [])
	for i in _modifiers.size():
		_modifiers[i] = String(mods[i]) if i < mods.size() else ""
	var autos: Array = data.get("auto", [])
	for i in _auto_recipes.size():
		_auto_recipes[i] = bool(autos[i]) if i < autos.size() else false
	if has_node("Health"):
		(get_node("Health") as Health).health = clampf(float(data.get("hp", max_health)), 1.0, max_health)
	var job := int(data.get("job", -1))
	if job >= 0 and job < recipes.size():
		_active_recipe_index = job
		_craft_duration = maxf(recipes[job].process_time, FactoryClock.TICK)
		_craft_elapsed = float(data.get("job_elapsed", 0.0))
	changed.emit()

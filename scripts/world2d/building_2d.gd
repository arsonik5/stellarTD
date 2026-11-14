class_name Building2D
extends Node2D

## A machine on the 2D tile grid (pivot-2d.md C3/C4). The logic - inventory slots, recipes crafted on FactoryClock
## ticks, auto-recipes, modifier modules, power hooks, idle reasons, save/load - is ported line for line from the 3D
## `Building` (scripts/world/building.gd), so machines behave exactly as before; only placement and drawing are new:
## a footprint of `size` tiles at `tile` (top-left), rotated `rot` quarter turns clockwise, standing on `level`.
## Belts connect through `ports`. The 3D Building is legacy and goes when the 3D game is removed.
##
## Drawing is a placeholder until the art exists: a base plate and a raised housing that leans with its height.

signal changed
signal removed

@export var item_id := ""                    ## the item this building is placed from (refunds, saves)
@export var display_name := "Building"
@export var size := Vector2i(2, 2)
@export var height_px := 14.0                ## how tall the housing stands (lean)
@export var colour := Color("#b8bccb")
@export var inventory_capacity: int = 100
@export var inventory_slots: int = 20
@export var output_multiplier: int = 1
@export var modifier_slots: int = 4
@export var compatible_modifiers: Array[String] = []
@export var recipes: Array[Recipe] = []
@export var accepts_any_item: bool = false
@export var max_health: float = 300.0
@export var power_draw: float = 0.0
@export var needs_power: bool = false
## Belt ports in the UNROTATED footprint: {"at": Vector2i cell, "dir": Vector2i outward, "kind": 1 out / -1 in / 0 both}
@export var ports: Array[Dictionary] = []

var tile := Vector2i.ZERO
var rot := 0
var level := 0
var view: WorldView

var _inventory: Array[Dictionary] = []
var _modifiers: Array[String] = []
var _craft_elapsed := 0.0
var _craft_duration := 0.0
var work_speed := 1.0
var _active_recipe_index: int = -1
var _auto_recipes: Array[bool] = []
var _last_auto_index: int = -1
var highlighted := false

func _ready() -> void:
	for i in inventory_slots:
		_inventory.append({"item_id": "", "count": 0})
	for i in modifier_slots:
		_modifiers.append("")
	for i in recipes.size():
		_auto_recipes.append(false)
	add_to_group("building2d")
	var hp := Health.ensure(self, max_health, "player")
	hp.free_owner_on_death = false
	hp.died.connect(func(_src: Node) -> void: removed.emit())
	if not recipes.is_empty():
		FactoryClock.tick.connect(_on_factory_tick)
	if power_draw > 0.0 and compatible_modifiers.is_empty():
		compatible_modifiers = ["speed_module", "efficiency_module"]

## --- placement ---------------------------------------------------------------------------------------------

## Footprint size after rotation.
func footprint() -> Vector2i:
	return Vector2i(size.y, size.x) if rot % 2 == 1 else size

## Every tile this building covers.
func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var f := footprint()
	for y in f.y:
		for x in f.x:
			out.append(tile + Vector2i(x, y))
	return out

static func rotate_cell(c: Vector2i, s: Vector2i, r: int) -> Vector2i:
	var p := c
	var w := s.x
	var h := s.y
	for i in r % 4:
		p = Vector2i(h - 1 - p.y, p.x)
		var t := w
		w = h
		h = t
	return p

static func rotate_dir(d: Vector2i, r: int) -> Vector2i:
	var p := d
	for i in r % 4:
		p = Vector2i(-p.y, p.x)
	return p

## Ports in world tiles: {"tile": the building's own tile at the port, "out": direction away from it, "kind"}.
func world_ports() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in ports:
		out.append({"tile": tile + rotate_cell(p["at"], size, rot), "out": rotate_dir(p["dir"], rot), "kind": int(p["kind"])})
	return out

func centre_px() -> Vector2:
	return (Vector2(tile) + Vector2(footprint()) * 0.5) * WorldGrid.TILE_PX

## --- drawing (placeholder) -----------------------------------------------------------------------------------

func _process(_dt: float) -> void:
	z_index = WorldView.z_for_level(level)
	queue_redraw()

func _draw() -> void:
	var t := float(WorldGrid.TILE_PX)
	var f := Vector2(footprint()) * t
	var base := Rect2(Vector2(tile) * t, f)
	var cam := view.camera.get_screen_center_position() if view != null and view.camera != null else base.get_center()
	var k0 := float(level) * WorldGrid.LEVEL_HEIGHT / WorldView.CAM_HEIGHT
	var k1 := (float(level) * WorldGrid.LEVEL_HEIGHT + height_px) / WorldView.CAM_HEIGHT
	var lb := Rect2(base.position + (base.position - cam) * k0, f * (1.0 + k0))
	var inset := Rect2(base.position + Vector2(5, 5), f - Vector2(10, 10))
	var top := Rect2(inset.position + (inset.position - cam) * k1, inset.size * (1.0 + k1))
	draw_rect(lb, Color("#3b3d4b"))
	draw_rect(lb.grow(-1), Color("#5c5f70"))
	# walls between the plate and the raised top: a few stacked outlines
	for i in 4:
		var kk := lerpf(k0, k1, float(i) / 4.0)
		var r := Rect2(inset.position + (inset.position - cam) * kk, inset.size * (1.0 + kk))
		draw_rect(r, colour.darkened(0.45))
	draw_rect(top, Color("#16161f"))
	draw_rect(top.grow(-1), colour.darkened(0.1) if highlighted == false else colour.lightened(0.3))
	draw_rect(Rect2(top.position + Vector2(2, 2), Vector2(top.size.x - 4, 2)), colour.lightened(0.25))
	if _active_recipe_index != -1:
		draw_rect(Rect2(top.get_center() - Vector2(6, 3), Vector2(12, 6)), Color("#ffb066"))
	var reason := idle_reason()
	if reason != "" and reason != "Idle":
		draw_circle(top.position + Vector2(top.size.x - 5, 5), 3.0, UiTokens.WARN)
	# ports: little arrows on the plate edge
	for p: Dictionary in world_ports():
		var c := (Vector2(p["tile"]) + Vector2(0.5, 0.5) + Vector2(p["out"]) * 0.42) * t
		c = c + (c - cam) * k0
		var col := Color("#ffa65c") if int(p["kind"]) == 1 else (Color("#7ae8d8") if int(p["kind"]) == -1 else Color("#e6c040"))
		draw_circle(c, 3.0, col)

## --- logic, ported from scripts/world/building.gd -----------------------------------------------------------

func status_text() -> String:
	if _active_recipe_index != -1:
		return "WORKING"
	var r := idle_reason()
	return r.to_upper() if r != "" else "IDLE"

func _on_factory_tick(dt: float) -> void:
	if _active_recipe_index != -1:
		_craft_elapsed += dt * work_speed * modifier_speed()
		if _craft_elapsed < _craft_duration - 0.0001:
			return
		var overflow := _craft_elapsed - _craft_duration
		_finish_craft()
		if _try_start_auto():
			_craft_elapsed = maxf(overflow, 0.0)
		return
	_try_start_auto()

func _try_start_auto() -> bool:
	for offset in recipes.size():
		var index := (_last_auto_index + 1 + offset) % recipes.size()
		if _auto_recipes[index] and process_recipe(index):
			return true
	return false

func wants_power() -> bool:
	return _active_recipe_index != -1 or (recipes.is_empty() and idle_reason() in ["", "No power"])

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

func get_inventory_slot(index: int) -> Dictionary:
	return _inventory[index]

func get_modifier_slot(index: int) -> String:
	return _modifiers[index]

func set_modifier_slot(index: int, id: String) -> void:
	_modifiers[index] = id
	changed.emit()

func can_place_modifier(id: String) -> bool:
	return compatible_modifiers.has(id)

const MOD_SPEED := {"speed_module": 1.5}
const MOD_POWER := {"speed_module": 1.6, "efficiency_module": 0.6}
const MOD_YIELD := {"yield_module": 1.5}

func _mod_product(table: Dictionary) -> float:
	var f := 1.0
	for m in _modifiers:
		if table.has(m):
			f *= float(table[m])
	return f

func modifier_speed() -> float:
	return _mod_product(MOD_SPEED)

func modifier_power() -> float:
	return _mod_product(MOD_POWER)

func modifier_yield() -> float:
	return _mod_product(MOD_YIELD)

func effective_power_draw() -> float:
	return power_draw * modifier_power()

func set_slot(index: int, id: String, count: int) -> void:
	_inventory[index].item_id = id
	_inventory[index].count = count
	changed.emit()

func get_inventory_count(id: String) -> int:
	var total := 0
	for slot in _inventory:
		if slot.item_id == id:
			total += slot.count
	return total

func get_total_count() -> int:
	var total := 0
	for slot in _inventory:
		total += slot.count
	return total

func can_accept_input(id: String, amount: int) -> bool:
	if accepts_any_item:
		return get_total_count() + amount <= inventory_capacity
	for recipe in recipes:
		if recipe.has_input(id):
			return get_total_count() + amount <= inventory_capacity
	return false

func can_add_output(id: String, amount: int) -> bool:
	for recipe in recipes:
		if recipe.output_id == id:
			return get_total_count() + amount <= inventory_capacity
	return false

func add_input(id: String, amount: int) -> int:
	if amount <= 0 or not can_accept_input(id, amount):
		return 0
	return _add_item(id, amount)

func add_output(id: String, amount: int) -> int:
	if amount <= 0 or not can_add_output(id, amount):
		return 0
	return _add_item(id, amount)

func _add_item(id: String, amount: int) -> int:
	var item := Inventory.get_item_def(id)
	var max_stack: int = item.max_stack if item != null else 100
	var remaining := amount
	for slot in _inventory:
		if remaining <= 0:
			break
		if slot.item_id == id and slot.count < max_stack:
			var moved: int = mini(max_stack - slot.count, remaining)
			slot.count += moved
			remaining -= moved
	for slot in _inventory:
		if remaining <= 0:
			break
		if slot.item_id == "":
			var moved: int = mini(max_stack, remaining)
			slot.item_id = id
			slot.count = moved
			remaining -= moved
	var added := amount - remaining
	if added > 0:
		changed.emit()
	return added

func remove_item(id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if get_inventory_count(id) < amount:
		return false
	var remaining := amount
	for slot in _inventory:
		if remaining <= 0:
			break
		if slot.item_id == id:
			var moved: int = mini(slot.count, remaining)
			slot.count -= moved
			remaining -= moved
			if slot.count == 0:
				slot.item_id = ""
	changed.emit()
	return true

## Item ids a belt on an output port may take. Machines give their recipe outputs; storage gives what it holds.
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

## One item for a belt to carry away: removed and its id returned, or "".
func take_one_output() -> String:
	for id: String in output_ids():
		if get_inventory_count(id) > 0 and remove_item(id, 1):
			return id
	return ""

## Everything dismantling gives back besides the build cost: what is stored inside and the installed modules.
func contents_refund() -> Dictionary:
	var out := {}
	for slot in _inventory:
		if String(slot.item_id) != "" and int(slot.count) > 0:
			out[slot.item_id] = int(out.get(slot.item_id, 0)) + int(slot.count)
	for m in _modifiers:
		if m != "":
			out[m] = int(out.get(m, 0)) + 1
	return out

func save_state() -> Dictionary:
	var slots: Array = []
	for slot in _inventory:
		slots.append({"item_id": slot.item_id, "count": slot.count})
	return {
		"item_id": item_id, "tile": [tile.x, tile.y], "rot": rot,
		"inventory": slots, "modifiers": _modifiers.duplicate(), "auto": _auto_recipes.duplicate(),
		"job": _active_recipe_index, "job_elapsed": _craft_elapsed,
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

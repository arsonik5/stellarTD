extends CanvasLayer

const SlotCarry := preload("res://scripts/ui/slot_carry.gd")
const InventorySlotAdapter := preload("res://scripts/ui/inventory_slot_adapter.gd")
const BuildingInventoryAdapter := preload("res://scripts/ui/building_inventory_adapter.gd")
const BuildingModifierAdapter := preload("res://scripts/ui/building_modifier_adapter.gd")

var _building: Building = null
var _inventory_buttons: Array[Button] = []
var _player_inventory_buttons: Array[Button] = []
var _player_hand_buttons: Array[Button] = []
var _modifier_buttons: Array[Button] = []
var _ammo_buttons: Array[Button] = []
var _recipe_buttons: Array[Button] = []
var _auto_buttons: Array[Button] = []
var _progress_bars: Array[ProgressBar] = []

## One SlotCarry (the same shared interaction every slot-based UI in the
## game uses - see slot_carry.gd) driving four different adapters: this
## screen has four independently-clickable slot groups, but only one
## "currently carrying" state at a time between them, matching the original
## single-carry-slot feel.
var _carry := SlotCarry.new()
var _grid_adapter := InventorySlotAdapter.new(InventorySlotAdapter.Kind.GRID)
var _hand_adapter := InventorySlotAdapter.new(InventorySlotAdapter.Kind.HAND)
var _building_adapter: BuildingInventoryAdapter = null
var _modifier_adapter: BuildingModifierAdapter = null

@onready var panel: PanelContainer = $Panel
@onready var player_panel: PanelContainer = $PlayerPanel
@onready var title: Label = $Panel/Layout/Title
@onready var inventory_grid: GridContainer = $Panel/Layout/InventoryGrid
@onready var player_grid: GridContainer = $PlayerPanel/Layout/PlayerGrid
@onready var player_hands: HBoxContainer = $PlayerPanel/Layout/PlayerHands
@onready var modifier_row: HBoxContainer = $Panel/Layout/ModifierRow
@onready var ammo_label: Label = $Panel/Layout/AmmoLabel
@onready var ammo_row: HBoxContainer = $Panel/Layout/AmmoRow
@onready var recipe_row: VBoxContainer = $Panel/Layout/RecipeList
@onready var carried_label: Label = $CarriedLabel

func _ready() -> void:
	visible = false
	add_to_group("building_ui")
	for i in 4:
		var button := Button.new()
		button.custom_minimum_size = Vector2(90, 55)
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.pressed.connect(_on_modifier_pressed.bind(i))
		modifier_row.add_child(button)
		_modifier_buttons.append(button)
	for i in Inventory.GRID_SIZE:
		var button := Button.new()
		button.custom_minimum_size = Vector2(62, 40)
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.pressed.connect(_on_player_grid_pressed.bind(i))
		player_grid.add_child(button)
		_player_inventory_buttons.append(button)
	for i in 2:
		var button := Button.new()
		button.custom_minimum_size = Vector2(140, 48)
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.pressed.connect(_on_player_hand_pressed.bind(i))
		player_hands.add_child(button)
		_player_hand_buttons.append(button)
	Inventory.changed.connect(_refresh)
	_carry.changed.connect(_refresh)
	carried_label.visible = false

func _process(_delta: float) -> void:
	if visible and (_building == null or not is_instance_valid(_building)):
		close()
	if visible and _carry.has_carried():
		carried_label.global_position = get_viewport().get_mouse_position() + Vector2(12.0, 12.0)
	if visible and _building != null:
		var active_index := _building.get_active_recipe_index()
		for i in _progress_bars.size():
			_progress_bars[i].value = _building.get_process_progress() * 100.0 if i == active_index else 0.0

func show_for(building: Building) -> void:
	_building = building
	_building_adapter = BuildingInventoryAdapter.new(building)
	_modifier_adapter = BuildingModifierAdapter.new(building)
	_rebuild_inventory_grid()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _building.changed.is_connected(_refresh):
		_building.changed.connect(_refresh)
	_refresh()

func close() -> void:
	_carry.return_to_origin()
	_update_carried_label()
	visible = false
	_building = null
	_building_adapter = null
	_modifier_adapter = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_open() -> bool:
	return visible and _building != null

func is_mouse_over_ui() -> bool:
	return is_open() and panel.get_global_rect().has_point(get_viewport().get_mouse_position())

func _display_name(item_id: String) -> String:
	var item := Inventory.get_item_def(item_id)
	return item.display_name if item != null else item_id

func _recipe_item_name(item_id: String) -> String:
	return _display_name(item_id)

func _refresh() -> void:
	if _building == null:
		return
	for i in _building.inventory_slots:
		var slot := _building_adapter.get_slot(i)
		_inventory_buttons[i].text = "" if slot.item_id == "" else "%s\nx%d" % [_display_name(slot.item_id), slot.count]
	for i in _building.modifier_slots:
		var slot := _modifier_adapter.get_slot(i)
		_modifier_buttons[i].text = "Modifier %d\n%s" % [i + 1, _display_name(slot.item_id) if slot.item_id != "" else "Empty"]
	_refresh_ammo_row()
	for i in Inventory.GRID_SIZE:
		var slot := _grid_adapter.get_slot(i)
		_player_inventory_buttons[i].text = "" if slot.item_id == "" else "%s\nx%d" % [_display_name(slot.item_id), slot.count]
	for i in 2:
		var side := "Left" if i == 0 else "Right"
		var slot := _hand_adapter.get_slot(i)
		_player_hand_buttons[i].text = "%s\nx%d" % [_display_name(slot.item_id), slot.count] if slot.item_id != "" else "%s hand\nEmpty" % side
	# input_capacity/output_capacity are informational only (meant to read as a
	# throughput rate, not a storage cap) - only inventory_capacity actually
	# gates how full the building can get, so that's the only ratio shown.
	title.text = "%s  |  Inventory %d/%d  |  Input %d  |  Output %d" % [
		_building.name, _building.get_total_count(), _building.inventory_capacity,
		_building.get_input_count(), _building.get_output_count(),
	]
	for column in recipe_row.get_children():
		column.queue_free()
	_recipe_buttons.clear()
	_auto_buttons.clear()
	_progress_bars.clear()
	for i in _building.recipes.size():
		var recipe: Recipe = _building.recipes[i]
		var column := VBoxContainer.new()
		var row := HBoxContainer.new()
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		var input_parts: Array[String] = []
		for j in recipe.input_ids.size():
			input_parts.append("%d %s" % [recipe.input_amounts[j], _recipe_item_name(recipe.input_ids[j])])
		button.text = "Make %s\n%s -> %d" % [_recipe_item_name(recipe.output_id), " + ".join(input_parts), recipe.output_amount * _building.output_multiplier]
		button.pressed.connect(_on_recipe_pressed.bind(i))
		row.add_child(button)
		_recipe_buttons.append(button)
		var auto_button := Button.new()
		auto_button.focus_mode = Control.FOCUS_NONE
		auto_button.toggle_mode = true
		auto_button.text = "Auto"
		auto_button.button_pressed = _building.get_auto(i)
		auto_button.toggled.connect(_on_auto_toggled.bind(i))
		row.add_child(auto_button)
		_auto_buttons.append(auto_button)
		column.add_child(row)
		var progress_bar := ProgressBar.new()
		progress_bar.custom_minimum_size = Vector2(0, 10)
		progress_bar.max_value = 100.0
		progress_bar.value = 0.0
		progress_bar.show_percentage = false
		column.add_child(progress_bar)
		_progress_bars.append(progress_bar)
		recipe_row.add_child(column)

func _on_inventory_pressed(index: int) -> void:
	if _building == null:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_quick_transfer_building(index)
		return
	_carry.click(_building_adapter, index)
	_update_carried_label()

func _on_player_grid_pressed(index: int) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		_quick_transfer_player(_grid_adapter, index)
		return
	_carry.click(_grid_adapter, index)
	_update_carried_label()

func _on_player_hand_pressed(index: int) -> void:
	_carry.click(_hand_adapter, index)
	_update_carried_label()

## Click-to-carry for a modifier slot - same SlotCarry interaction as every
## other slot group on this screen, just pointed at the modifier adapter.
func _on_modifier_pressed(index: int) -> void:
	if _building == null:
		return
	_carry.click(_modifier_adapter, index)
	_update_carried_label()

## Shift-click bulk transfer bypasses the carry state entirely (moves a
## whole stack in one step rather than pick-up-then-place) - a genuinely
## different interaction from SlotCarry, so it stays separate, but still
## goes through Building/Inventory's own canonical add/remove methods rather
## than duplicating any capacity or stacking math of its own.
func _quick_transfer_player(source_adapter, index: int) -> void:
	var slot: Dictionary = source_adapter.get_slot(index)
	if slot.item_id == "":
		return
	var room: int = _building.inventory_capacity - _building.get_total_count()
	var amount: int = min(slot.count, room)
	var moved: int = _building.add_input(slot.item_id, amount)
	if moved > 0:
		source_adapter.set_slot(index, slot.item_id, slot.count - moved)

func _quick_transfer_building(index: int) -> void:
	var slot := _building_adapter.get_slot(index)
	if slot.item_id == "":
		return
	var moved: int = Inventory.add(slot.item_id, slot.count)
	if moved > 0:
		_building.remove_item(slot.item_id, moved)

func _update_carried_label() -> void:
	if not _carry.has_carried():
		carried_label.visible = false
		return
	carried_label.text = "%s x%d" % [_display_name(_carry.carried_item_id), _carry.carried_count]
	carried_label.visible = true

func _on_recipe_pressed(index: int) -> void:
	if _building != null and _building.has_method("process_recipe"):
		var recipe: Recipe = _building.recipes[index]
		var crafted: bool = _building.process_recipe(index)
		var missing_local_input := false
		if not crafted:
			for i in recipe.input_ids.size():
				var item_id: String = recipe.input_ids[i]
				if _building.get_inventory_count(item_id) < recipe.input_amounts[i] and Inventory.get_count(item_id) >= recipe.input_amounts[i]:
					missing_local_input = true
					break
		_refresh()
		if missing_local_input:
			var button: Button = _recipe_buttons[index]
			button.modulate = Color(1.0, 0.2, 0.2)
			get_tree().create_timer(0.5).timeout.connect(_clear_recipe_error.bind(button))

func _on_auto_toggled(pressed: bool, index: int) -> void:
	if _building != null:
		_building.set_auto(index, pressed)

## Rebuilt every _refresh() the same way recipe_row is - cheap at this
## building count, and keeps the toggle labels (ENABLED/disabled) always
## in sync with Turret's own _enabled_ammo state without a second signal.
func _refresh_ammo_row() -> void:
	for child in ammo_row.get_children():
		child.queue_free()
	_ammo_buttons.clear()
	var is_turret := _building is Turret
	ammo_label.visible = is_turret
	ammo_row.visible = is_turret
	if not is_turret:
		return
	var turret: Turret = _building
	for ammo in turret.compatible_ammo:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 44)
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		btn.toggle_mode = true
		var enabled := turret.is_ammo_enabled(ammo.item_id)
		btn.button_pressed = enabled
		btn.text = "%s\n%s" % [ammo.display_name, "ENABLED" if enabled else "disabled"]
		btn.toggled.connect(_on_ammo_toggled.bind(ammo.item_id))
		ammo_row.add_child(btn)
		_ammo_buttons.append(btn)

func _on_ammo_toggled(pressed: bool, item_id: String) -> void:
	if _building is Turret:
		_building.set_ammo_enabled(item_id, pressed)
		_refresh()

func _clear_recipe_error(button: Button) -> void:
	if is_instance_valid(button):
		button.modulate = Color.WHITE

func _rebuild_inventory_grid() -> void:
	for button in _inventory_buttons:
		button.queue_free()
	_inventory_buttons.clear()
	if _building == null:
		return
	for i in _building.inventory_slots:
		var button := Button.new()
		button.custom_minimum_size = Vector2(62, 40)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_inventory_pressed.bind(i))
		inventory_grid.add_child(button)
		_inventory_buttons.append(button)

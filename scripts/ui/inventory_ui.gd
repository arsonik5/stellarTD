extends CanvasLayer

const SlotCarry := preload("res://scripts/ui/slot_carry.gd")
const InventorySlotAdapter := preload("res://scripts/ui/inventory_slot_adapter.gd")

var _carry := SlotCarry.new()
var _grid_adapter := InventorySlotAdapter.new(InventorySlotAdapter.Kind.GRID)
var _hand_adapter := InventorySlotAdapter.new(InventorySlotAdapter.Kind.HAND)

var _slot_buttons: Dictionary = {}

@onready var hand_left_button: Button = $Layout/HandRow/HandLeft
@onready var hand_right_button: Button = $Layout/HandRow/HandRight
@onready var grid_container: GridContainer = $Layout/GridContainer
@onready var carried_label: Label = $CarriedLabel

func _ready() -> void:
	visible = false
	add_to_group("inventory_ui")

	# Buttons default to grabbing keyboard focus on click, which lets Tab get
	# consumed by GUI focus-navigation instead of reaching the player's toggle.
	# This is a click-to-carry grid, not a keyboard-navigable form, so slots
	# never need focus at all.
	hand_left_button.focus_mode = Control.FOCUS_NONE
	hand_right_button.focus_mode = Control.FOCUS_NONE
	hand_left_button.pressed.connect(_on_hand_pressed.bind(0))
	hand_right_button.pressed.connect(_on_hand_pressed.bind(1))
	_slot_buttons["hand:0"] = hand_left_button
	_slot_buttons["hand:1"] = hand_right_button

	grid_container.columns = Inventory.GRID_COLS
	for i in Inventory.GRID_SIZE:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(82, 54)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_grid_pressed.bind(i))
		grid_container.add_child(btn)
		_slot_buttons["grid:%d" % i] = btn

	Inventory.changed.connect(_refresh_all)
	_carry.changed.connect(_refresh_all)
	carried_label.visible = false

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh_all()
	else:
		_carry.return_to_origin()
		_update_carried_label()

func _process(_delta: float) -> void:
	if visible and _carry.has_carried():
		carried_label.global_position = get_viewport().get_mouse_position() + Vector2(12.0, 12.0)

func _on_grid_pressed(index: int) -> void:
	_carry.click(_grid_adapter, index)
	_update_carried_label()

func _on_hand_pressed(index: int) -> void:
	_carry.click(_hand_adapter, index)
	_update_carried_label()

func _refresh_all() -> void:
	for i in Inventory.GRID_SIZE:
		_refresh_button("grid:%d" % i, _grid_adapter.get_slot(i), "")
	_refresh_button("hand:0", _hand_adapter.get_slot(0), "Left hand")
	_refresh_button("hand:1", _hand_adapter.get_slot(1), "Right hand")

func _refresh_button(key: String, slot: Dictionary, empty_label: String) -> void:
	var btn: Button = _slot_buttons[key]
	if slot.item_id == "":
		btn.text = "%s\nEmpty" % empty_label if empty_label != "" else ""
	else:
		var item := Inventory.get_item_def(slot.item_id)
		var label: String = item.display_name if item != null else slot.item_id
		btn.text = "%s\nx%d" % [label, slot.count]

func _update_carried_label() -> void:
	if not _carry.has_carried():
		carried_label.visible = false
		return
	var item := Inventory.get_item_def(_carry.carried_item_id)
	var label: String = item.display_name if item != null else _carry.carried_item_id
	carried_label.text = "%s x%d" % [label, _carry.carried_count]
	carried_label.visible = true

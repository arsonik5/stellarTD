extends CanvasLayer

## Data-driven list of what the build tool can place: each Recipe's output_id
## must resolve to an Item with is_building = true and a building_scene set.
const BUILDABLE_RECIPES := [
	preload("res://data/recipes/build_foundation.tres"),
	preload("res://data/recipes/build_crafter.tres"),
	preload("res://data/recipes/build_smelter.tres"),
	preload("res://data/recipes/build_chest.tres"),
	preload("res://data/recipes/build_constructor.tres"),
	preload("res://data/recipes/build_vacuum_pipe.tres"),
	preload("res://data/recipes/build_merger.tres"),
	preload("res://data/recipes/build_splitter.tres"),
	preload("res://data/recipes/build_turret_gun.tres"),
	preload("res://data/recipes/build_turret_cannon.tres"),
]

var _selected_index := 0
var _recipe_buttons: Dictionary = {}
var _player: Node = null

@onready var panel: PanelContainer = $Panel
@onready var building_list: VBoxContainer = $Panel/BuildingList
@onready var controls_bar: HBoxContainer = $ControlsBar
@onready var keybinds_legend: PanelContainer = $KeybindsLegend

func _ready() -> void:
	visible = false
	add_to_group("build_ui")

	for i in BUILDABLE_RECIPES.size():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 50)
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = true
		btn.pressed.connect(_on_building_pressed.bind(i))
		building_list.add_child(btn)
		_recipe_buttons[i] = btn

	var grid_btn := Button.new()
	grid_btn.text = "Grid"
	grid_btn.focus_mode = Control.FOCUS_NONE
	grid_btn.pressed.connect(_on_grid_toggled)
	controls_bar.add_child(grid_btn)

	var rotate_btn := Button.new()
	rotate_btn.text = "Rotate"
	rotate_btn.focus_mode = Control.FOCUS_NONE
	rotate_btn.pressed.connect(_on_rotate_pressed)
	controls_bar.add_child(rotate_btn)

	var lock_btn := Button.new()
	lock_btn.text = "Lock"
	lock_btn.focus_mode = Control.FOCUS_NONE
	lock_btn.pressed.connect(_on_lock_pressed)
	controls_bar.add_child(lock_btn)

	Inventory.changed.connect(_refresh_all)

func bind_player(player: Node) -> void:
	_player = player

func show_ui() -> void:
	visible = true
	if _selected_index >= BUILDABLE_RECIPES.size():
		_selected_index = 0
	_refresh_all()

func hide_ui() -> void:
	visible = false

func get_selected_recipe() -> Recipe:
	if _selected_index < 0 or _selected_index >= BUILDABLE_RECIPES.size():
		return null
	return BUILDABLE_RECIPES[_selected_index]

func is_mouse_over_ui() -> bool:
	if not visible:
		return false
	var mouse_pos := get_viewport().get_mouse_position()
	return panel.get_global_rect().has_point(mouse_pos) \
		or controls_bar.get_global_rect().has_point(mouse_pos) \
		or keybinds_legend.get_global_rect().has_point(mouse_pos)

func _on_building_pressed(index: int) -> void:
	_selected_index = index
	_refresh_all()

func _on_grid_toggled() -> void:
	if _player != null and _player.has_method("toggle_build_grid_snap"):
		_player.toggle_build_grid_snap()

func _on_rotate_pressed() -> void:
	if _player != null and _player.has_method("rotate_build_ghost"):
		_player.rotate_build_ghost()

func _on_lock_pressed() -> void:
	if _player != null and _player.has_method("toggle_build_lock"):
		_player.toggle_build_lock()

func _refresh_all() -> void:
	for i in BUILDABLE_RECIPES.size():
		_refresh_button(i)

func _refresh_button(index: int) -> void:
	var recipe: Recipe = BUILDABLE_RECIPES[index]
	var btn: Button = _recipe_buttons[index]
	var output_item := Inventory.get_item_def(recipe.output_id)
	var output_label: String = output_item.display_name if output_item != null else recipe.output_id
	var cost_parts: Array[String] = []
	for i in recipe.input_ids.size():
		var input_item := Inventory.get_item_def(recipe.input_ids[i])
		var input_label: String = input_item.display_name if input_item != null else recipe.input_ids[i]
		var have: int = Inventory.get_count(recipe.input_ids[i])
		cost_parts.append("%dx %s (have %d)" % [recipe.input_amounts[i], input_label, have])
	btn.text = "%s\n%s" % [output_label, " + ".join(cost_parts)]
	btn.button_pressed = (index == _selected_index)

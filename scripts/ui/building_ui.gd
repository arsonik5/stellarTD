extends CanvasLayer

## A machine's own screen, opened by looking at it and pressing E (docs/game/ux-bible.md, "Machine panel").
## Standard screen frame; title = the machine's name, subtitle = what it is doing right now.
##   left   the machine: recipes (output, inputs, Make, Auto, progress), its storage, modifier slots, and the
##          extras a machine type has (turret ammo, garage repair)
##   right  your storage and hands, so moving things in and out never needs a second screen
## Click carries a stack (SlotCarry, same as everywhere); Shift+click moves a whole stack across at once.

const SlotCarry := preload("res://scripts/ui/slot_carry.gd")
const InventorySlotAdapter := preload("res://scripts/ui/inventory_slot_adapter.gd")
const BuildingInventoryAdapter := preload("res://scripts/ui/building_inventory_adapter.gd")
const BuildingModifierAdapter := preload("res://scripts/ui/building_modifier_adapter.gd")

var _building: Building = null
var _carry := SlotCarry.new()
var _grid_adapter := InventorySlotAdapter.new(InventorySlotAdapter.Kind.GRID)
var _hand_adapter := InventorySlotAdapter.new(InventorySlotAdapter.Kind.HAND)
var _building_adapter: BuildingInventoryAdapter = null
var _modifier_adapter: BuildingModifierAdapter = null

var _root: Control
var _panel: Control
var _title: Label
var _status: Label
var _machine_col: VBoxContainer
var _recipes_box: VBoxContainer
var _storage_grid: GridContainer
var _storage_caption: Label
var _mod_row: HBoxContainer
var _mod_section: Label
var _extras: VBoxContainer
var _player_slots: Array[SlotButton] = []
var _hand_slots: Array[SlotButton] = []
var _storage_slots: Array[SlotButton] = []
var _mod_slots: Array[SlotButton] = []
var _progress_bars: Array[ProgressBar] = []
var _recipe_rows: Array[Control] = []
var _cursor: ItemIcon

func _ready() -> void:
	visible = false
	layer = 20
	add_to_group("building_ui")
	_build()
	Inventory.changed.connect(_refresh)
	_carry.changed.connect(_refresh)

func _build() -> void:
	var frame := UiKit.screen("Machine", [["Shift+LMB", "Move stack"], ["E/Esc", "Close"]], Vector2(1080, 560), "Machine  /")
	_root = frame.root
	_panel = frame.panel
	add_child(_root)
	_title = frame.title
	_status = UiKit.label("", "SectionLabel")
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(frame.header as HBoxContainer).add_child(_status)

	var row := UiKit.hbox(UiTokens.GAP_L + 8)
	(frame.body as Control).add_child(row)

	# --- machine column ---
	var mscroll := ScrollContainer.new()
	mscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mscroll.custom_minimum_size.y = 220      # fills the screen's height; a fixed 470 overflowed 648 px windows
	row.add_child(mscroll)
	_machine_col = UiKit.vbox(UiTokens.GAP)
	_machine_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mscroll.add_child(_machine_col)
	_machine_col.add_child(UiKit.section("Recipes"))
	_recipes_box = UiKit.vbox(6)
	_machine_col.add_child(_recipes_box)
	_extras = UiKit.vbox(6)
	_machine_col.add_child(_extras)
	var shead := UiKit.hbox()
	shead.add_child(UiKit.section("Machine storage"))
	shead.add_child(UiKit.spacer())
	_storage_caption = UiKit.label("", "DimLabel")
	shead.add_child(_storage_caption)
	_machine_col.add_child(shead)
	_storage_grid = GridContainer.new()
	_storage_grid.columns = 8
	_storage_grid.add_theme_constant_override("h_separation", 6)
	_storage_grid.add_theme_constant_override("v_separation", 6)
	_machine_col.add_child(_storage_grid)
	_mod_section = UiKit.section("Modifiers")
	_machine_col.add_child(_mod_section)
	_mod_row = UiKit.hbox(6)
	_machine_col.add_child(_mod_row)

	# --- player column ---
	var pcol := UiKit.vbox(UiTokens.GAP)
	row.add_child(pcol)
	pcol.add_child(UiKit.section("Your storage"))
	var pgrid := GridContainer.new()
	pgrid.columns = Inventory.GRID_COLS
	pgrid.add_theme_constant_override("h_separation", 4)
	pgrid.add_theme_constant_override("v_separation", 4)
	pcol.add_child(pgrid)
	for i in Inventory.GRID_SIZE:
		var s := SlotButton.new(52)
		s.pressed.connect(_on_player_grid_pressed.bind(i))
		pgrid.add_child(s)
		_player_slots.append(s)
	pcol.add_child(UiKit.section("Hands"))
	var hrow2 := UiKit.hbox(4)
	pcol.add_child(hrow2)
	for i in 2:
		var s := SlotButton.new(52)
		s.pressed.connect(func() -> void: _carry.click(_hand_adapter, i))
		hrow2.add_child(s)
		_hand_slots.append(s)

	_cursor = ItemIcon.new()
	_cursor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor.size = Vector2(52, 52)
	_cursor.visible = false
	add_child(_cursor)

func _process(_delta: float) -> void:
	if not visible:
		return
	if _building == null or not is_instance_valid(_building):
		close()
		return
	if _cursor.visible:
		_cursor.position = get_viewport().get_mouse_position() + Vector2(6, 6)
	var active := _building.get_active_recipe_index()
	var p := _building.get_process_progress()
	for i in _progress_bars.size():
		_progress_bars[i].value = p if i == active else 0.0
	# the header says what the machine is doing, or exactly why it is not (Building.status_text / idle_reason)
	var reason := _building.idle_reason()
	_status.text = ("◆  " if reason == "" and active >= 0 else "") + _building.status_text()
	var col := UiTokens.GOOD if reason == "" and active >= 0 else (UiTokens.TEXT_DIM if reason in ["", "Idle"] else UiTokens.WARN)
	_status.add_theme_color_override("font_color", col)

func show_for(building: Building) -> void:
	var inventory_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inventory_ui != null and inventory_ui.has_method("close"):
		inventory_ui.close()
	_building = building
	_building_adapter = BuildingInventoryAdapter.new(building)
	_modifier_adapter = BuildingModifierAdapter.new(building)
	_rebuild_machine()
	visible = true
	UiState.set_open("building", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _building.changed.is_connected(_refresh):
		_building.changed.connect(_refresh)
	_refresh()
	UiKit.pop_in(_root)

func close() -> void:
	var visible_was := visible
	if _building is ShipGarage:
		(_building as ShipGarage).unlink_ship()
	_carry.return_to_origin()
	visible = false
	UiState.set_open("building", false)
	if visible_was:
		UiSound.play("close")
	if _building != null and is_instance_valid(_building) and _building.changed.is_connected(_refresh):
		_building.changed.disconnect(_refresh)
	_building = null
	_building_adapter = null
	_modifier_adapter = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_open() -> bool:
	return visible and _building != null

func is_mouse_over_ui() -> bool:
	return is_open() and _panel.get_global_rect().has_point(get_viewport().get_mouse_position())

func _display_name(item_id: String) -> String:
	var item := Inventory.get_item_def(item_id)
	return item.display_name if item != null else item_id

func _machine_name() -> String:
	var id: String = String(_building.get_meta(SaveManager.ITEM_ID_META, ""))
	if id != "":
		return _display_name(id)
	return String(_building.name).rstrip("0123456789").capitalize()

## Static parts of the machine column: recipe rows, storage and modifier slots. Rebuilt per machine opened.
func _rebuild_machine() -> void:
	_title.text = _machine_name().to_upper()
	for c in _recipes_box.get_children():
		c.queue_free()
	_progress_bars.clear()
	_recipe_rows.clear()
	for i in _building.recipes.size():
		_recipes_box.add_child(_recipe_row(i, _building.recipes[i]))
	UiKit.stagger(_recipes_box)
	_recipes_box.get_parent().get_child(0).visible = not _building.recipes.is_empty()
	for s in _storage_slots:
		s.queue_free()
	_storage_slots.clear()
	for i in _building.inventory_slots:
		var s := SlotButton.new(56)
		s.pressed.connect(_on_storage_pressed.bind(i))
		_storage_grid.add_child(s)
		_storage_slots.append(s)
	for s in _mod_slots:
		s.queue_free()
	_mod_slots.clear()
	_mod_section.visible = _building.modifier_slots > 0
	for i in _building.modifier_slots:
		var s := SlotButton.new(56)
		s.pressed.connect(func() -> void: _carry.click(_modifier_adapter, i))
		_mod_row.add_child(s)
		_mod_slots.append(s)

func _recipe_row(i: int, r: Recipe) -> Control:
	var card := UiKit.panel("Card")
	var col := UiKit.vbox(6)
	card.add_child(col)
	var row := UiKit.hbox(UiTokens.GAP)
	col.add_child(row)
	var ib := Control.new()
	ib.custom_minimum_size = Vector2(40, 40)
	ib.add_child(ItemIcon.new(r.output_id))
	row.add_child(ib)
	var names := UiKit.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	names.add_child(UiKit.label("%s  x%d" % [_display_name(r.output_id), r.output_amount * _building.output_multiplier]))
	var parts: Array[String] = []
	for j in r.input_ids.size():
		parts.append("%d %s" % [r.input_amounts[j], _display_name(r.input_ids[j])])
	# throughput at the machine's current speed (power doubles it): what a production line is planned with
	var per_min := 60.0 / maxf(r.process_time, FactoryClock.TICK) * _building.work_speed
	var inputs := UiKit.label("from  " + "  +  ".join(parts) + "   ·   %.1f / min" % (per_min * r.output_amount * _building.output_multiplier), "DimLabel")
	inputs.name = "Inputs"
	names.add_child(inputs)
	var make := UiKit.button("Make", _on_recipe_pressed.bind(i))
	make.custom_minimum_size.x = 80
	make.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(make)
	var auto := UiKit.button("Auto", Callable())
	auto.toggle_mode = true
	auto.custom_minimum_size.x = 72
	auto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	auto.button_pressed = _building.get_auto(i)
	auto.tooltip_text = "Keep making this while the inputs last."
	auto.toggled.connect(_on_auto_toggled.bind(i))
	row.add_child(auto)
	var bar := UiKit.bar("", 4)
	col.add_child(bar)
	_progress_bars.append(bar)
	_recipe_rows.append(card)
	return card

func _refresh() -> void:
	if _building == null or not is_instance_valid(_building):
		return
	for i in _storage_slots.size():
		var s := _building_adapter.get_slot(i)
		_storage_slots[i].show_slot(s.item_id, s.count)
	for i in _mod_slots.size():
		var s := _modifier_adapter.get_slot(i)
		_mod_slots[i].show_slot(s.item_id, s.count, "MOD %d" % (i + 1))
	for i in Inventory.GRID_SIZE:
		var s := _grid_adapter.get_slot(i)
		_player_slots[i].show_slot(s.item_id, s.count)
	for i in 2:
		var s := _hand_adapter.get_slot(i)
		_hand_slots[i].show_slot(s.item_id, s.count, "LEFT" if i == 0 else "RIGHT")
	_storage_caption.text = "%d / %d" % [_building.get_total_count(), _building.inventory_capacity]
	# a recipe whose inputs aren't in the machine reads amber; it lights up again when they are
	for i in _recipe_rows.size():
		var r: Recipe = _building.recipes[i]
		var ok := true
		for j in r.input_ids.size():
			if _building.get_inventory_count(r.input_ids[j]) < r.input_amounts[j]:
				ok = false
		var inputs := _recipe_rows[i].find_child("Inputs", true, false) as Label
		if inputs != null:
			inputs.theme_type_variation = "DimLabel" if ok else "WarnLabel"
	_cursor.visible = _carry.has_carried()
	_cursor.item_id = _carry.carried_item_id
	_cursor.count = _carry.carried_count
	_refresh_extras()

## Damaged buildings (raids, bombardment) show their structure and a Repair button: iron ingots for health,
## REPAIR_HP_PER_INGOT each, paid from the player's inventory.
const REPAIR_HP_PER_INGOT := 50.0

func _repair_section() -> void:
	var h := Health.of(_building)
	if h == null or h.health >= h.max_health - 0.5:
		return
	_extras.add_child(UiKit.section("Structure"))
	var row := UiKit.hbox(UiTokens.GAP)
	_extras.add_child(row)
	var need := ceili((h.max_health - h.health) / REPAIR_HP_PER_INGOT)
	var info := UiKit.label("%d / %d  ·  repair costs %d Iron Ingot" % [roundi(h.health), roundi(h.max_health), need], "WarnLabel")
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var b := UiKit.button("Repair", func() -> void:
		if repair_building(_building):
			UiSound.play("confirm")
		else:
			UiSound.play("deny")
		_refresh(), "PrimaryButton")
	b.disabled = Inventory.get_count("refined_material") <= 0
	row.add_child(b)

## Spend iron ingots (as many as needed and available) to restore health. Returns true if anything was repaired.
static func repair_building(b: Node) -> bool:
	var h := Health.of(b)
	if h == null or h.is_dead():
		return false
	var need := ceili((h.max_health - h.health) / REPAIR_HP_PER_INGOT)
	var have := mini(need, Inventory.get_count("refined_material"))
	if have <= 0:
		return false
	Inventory.try_remove("refined_material", have)
	h.heal(have * REPAIR_HP_PER_INGOT)
	GameEvents.act("repair")
	return true

func _on_storage_pressed(index: int) -> void:
	if _building == null:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		var slot := _building_adapter.get_slot(index)
		if slot.item_id != "":
			var moved: int = Inventory.add(slot.item_id, slot.count)
			if moved > 0:
				_building.remove_item(slot.item_id, moved)
		return
	_carry.click(_building_adapter, index)

func _on_player_grid_pressed(index: int) -> void:
	if Input.is_key_pressed(KEY_SHIFT) and _building != null:
		var slot: Dictionary = _grid_adapter.get_slot(index)
		if slot.item_id == "":
			return
		var room: int = _building.inventory_capacity - _building.get_total_count()
		var moved: int = _building.add_input(slot.item_id, mini(slot.count, room))
		if moved > 0:
			_grid_adapter.set_slot(index, slot.item_id, slot.count - moved)
		return
	_carry.click(_grid_adapter, index)

func _on_recipe_pressed(index: int) -> void:
	if _building == null or not _building.has_method("process_recipe"):
		return
	var crafted: bool = _building.process_recipe(index)
	_refresh()
	var card := _recipe_rows[index]
	if crafted:
		UiSound.play("confirm")
		UiKit.pulse(card)
	else:
		# say no clearly: the row shakes, tints orange for a moment, and the error sound plays
		card.modulate = Color(1.4, 0.75, 0.5)
		UiMotion.animate(card, {"modulate": Color.WHITE}, {"duration": 0.6, "easing": "outQuad"})
		UiKit.shake(card)

func _on_auto_toggled(pressed: bool, index: int) -> void:
	if _building != null:
		_building.set_auto(index, pressed)
	if pressed:
		GameEvents.act("toggle_autocraft")

## Turret ammo toggles and the garage's repair card. Rebuilt on refresh; cheap at this size.
func _refresh_extras() -> void:
	for c in _extras.get_children():
		c.queue_free()
	if _building.has_method("build_ui_extras"):
		_building.build_ui_extras(_extras, _refresh)
	elif _building.power_draw > 0.0:
		PowerUi.grid_section(_extras, _building)
	_repair_section()
	if _building is Turret:
		var turret: Turret = _building
		_extras.add_child(UiKit.section("Ammunition"))
		var r := UiKit.hbox(6)
		_extras.add_child(r)
		for ammo in turret.compatible_ammo:
			var b := UiKit.button(ammo.display_name)
			b.toggle_mode = true
			b.button_pressed = turret.is_ammo_enabled(ammo.item_id)
			b.tooltip_text = "Allowed" if b.button_pressed else "Not used"
			b.toggled.connect(func(on: bool) -> void:
				turret.set_ammo_enabled(ammo.item_id, on)
				_refresh())
			r.add_child(b)
	if _building is ShipGarage:
		var garage: ShipGarage = _building
		if garage.can_edit_ship():
			var m := garage.get_manifest()
			_extras.add_child(UiKit.section("Docked ship"))
			var card := UiKit.panel("Card")
			var r := UiKit.hbox(UiTokens.GAP)
			card.add_child(r)
			var info := UiKit.label("%d blocks   ·   %.0f / %.0f HP   ·   %s" % [m.blocks, m.health, m.max_health, String(m.state).to_upper()])
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(info)
			r.add_child(UiKit.button("Repair", func() -> void:
				garage.repair_ship()
				_refresh(), "PrimaryButton"))
			_extras.add_child(card)

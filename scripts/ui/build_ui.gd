extends CanvasLayer

## The build tool's screen (docs/game/ux-bible.md, "Build menu"). Opens only with the Build Tool in hand (C), and
## closes the moment a building is picked - then the player aims it in first person. Layout, standard screen frame:
##   left   category tabs (Structure, Production, Logistics, Defense, Vehicles), remembered between openings
##   centre cards: icon, name, cost; a card you can't afford is dimmed and its missing input shown in amber
##   right  detail of the hovered card: what it is for, full cost against what you carry
## While aiming, the menu is closed and the HUD shows the build key hints (player.gd _refresh_build_hint).

## Data-driven list of what the build tool can place: each Recipe's output_id
## must resolve to an Item with is_building = true and a building_scene set.
const BUILDABLE_RECIPES := [
	preload("res://data/recipes/build_foundation.tres"),
	preload("res://data/recipes/build_foundation_1m.tres"),
	preload("res://data/recipes/build_foundation_2m.tres"),
	preload("res://data/recipes/build_frame_2m.tres"),
	preload("res://data/recipes/build_ramp_1m.tres"),
	preload("res://data/recipes/build_stairs_1m.tres"),
	preload("res://data/recipes/build_crafter.tres"),
	preload("res://data/recipes/build_smelter.tres"),
	preload("res://data/recipes/build_chest.tres"),
	preload("res://data/recipes/build_constructor.tres"),
	preload("res://data/recipes/build_vacuum_pipe.tres"),
	preload("res://data/recipes/build_merger.tres"),
	preload("res://data/recipes/build_splitter.tres"),
	preload("res://data/recipes/build_turret_gun.tres"),
	preload("res://data/recipes/build_turret_cannon.tres"),
	preload("res://data/recipes/build_ship_garage.tres"),
	preload("res://data/recipes/build_oxygen_post.tres"),
]
const TABS := ["structure", "production", "logistics", "defense", "vehicles"]
const CARD := Vector2(152, 148)

var _selected_index := 0
var _player: Node = null
var _tab := "structure"
var _menu_open := false
var _frame: Dictionary
var _tab_buttons := {}
var _grid: GridContainer
var _cards := {}                      # recipe index -> Button
var _detail: VBoxContainer
var _hover := -1

func _ready() -> void:
	visible = false
	layer = 20
	add_to_group("build_ui")
	_frame = UiKit.screen("Build", [["LMB", "Pick and aim"], ["Esc/C", "Close"]], Vector2(1040, 620), "Build tool  /")
	add_child(_frame.root)
	var row := UiKit.hbox(UiTokens.GAP_L)
	(_frame.body as Control).add_child(row)
	# tabs
	var tabs := UiKit.vbox(2)
	tabs.custom_minimum_size.x = 170
	row.add_child(tabs)
	for t: String in TABS:
		var b := UiKit.button(String(ItemInfo.CATEGORY_NAMES[t]).to_upper(), _show_tab.bind(t), "NavButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.toggle_mode = true
		tabs.add_child(b)
		_tab_buttons[t] = b
	# cards
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", UiTokens.GAP)
	_grid.add_theme_constant_override("v_separation", UiTokens.GAP)
	scroll.add_child(_grid)
	# detail
	var dpanel := UiKit.panel("Well")
	dpanel.custom_minimum_size.x = 250
	row.add_child(dpanel)
	_detail = UiKit.vbox(UiTokens.GAP)
	dpanel.add_child(_detail)
	Inventory.changed.connect(func() -> void:
		if visible:
			_refresh())

func bind_player(player: Node) -> void:
	_player = player

func show_ui() -> void:
	visible = true

func hide_ui() -> void:
	visible = false
	set_menu_open(false)

func set_menu_open(open: bool) -> void:
	if _menu_open and not open:
		UiSound.play("close")
	_menu_open = open
	(_frame.root as Control).visible = open
	UiState.set_open("build_menu", open)
	if open:
		var item := Inventory.get_item_def(BUILDABLE_RECIPES[_selected_index].output_id)
		if item != null and TABS.has(ItemInfo.category(item.id)):
			_tab = ItemInfo.category(item.id)
		_show_tab(_tab)
		UiKit.pop_in(_frame.root)

func is_menu_open() -> bool:
	return visible and _menu_open

## Kept for callers; build hints now live on the HUD.
func set_hint(_text: String) -> void:
	pass

func get_selected_recipe() -> Recipe:
	if _selected_index < 0 or _selected_index >= BUILDABLE_RECIPES.size():
		return null
	return BUILDABLE_RECIPES[_selected_index]

func _show_tab(t: String) -> void:
	_tab = t
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = k == t
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	for i in BUILDABLE_RECIPES.size():
		var r: Recipe = BUILDABLE_RECIPES[i]
		if ItemInfo.category(r.output_id) == t:
			var card := _card(i, r)
			_grid.add_child(card)
			_cards[i] = card
	UiKit.stagger(_grid)
	_hover = _selected_index if _cards.has(_selected_index) else (_cards.keys()[0] if not _cards.is_empty() else -1)
	_refresh()

func _affordable(r: Recipe) -> bool:
	return _carried(r) > 0 or _has_inputs(r)

## Copies of this building already in the inventory (crafted, picked up, given by a command). Placing uses one of
## these first, for free; only when there are none does it cost the recipe's materials.
func _carried(r: Recipe) -> int:
	return Inventory.get_count(r.output_id)

func _has_inputs(r: Recipe) -> bool:
	for k in r.input_ids.size():
		if Inventory.get_count(r.input_ids[k]) < r.input_amounts[k]:
			return false
	return true

## For the placer: true if this recipe can be placed now.
func can_pay(r: Recipe) -> bool:
	return r != null and _affordable(r)

## For the placer: take one carried copy, or else the materials. False (nothing taken) if neither is there.
func pay(r: Recipe) -> bool:
	if r == null:
		return false
	if _carried(r) > 0:
		return Inventory.try_remove(r.output_id, 1)
	if not _has_inputs(r):
		return false
	for k in r.input_ids.size():
		Inventory.try_remove(r.input_ids[k], r.input_amounts[k])
	return true

func _card(i: int, r: Recipe) -> Button:
	var b := Button.new()
	b.theme_type_variation = "CardButton"
	b.custom_minimum_size = CARD
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.pressed.connect(_on_building_pressed.bind(i))
	UiKit.juice(b)
	b.mouse_entered.connect(func() -> void:
		_hover = i
		_refresh_detail())
	var v := UiKit.vbox(4)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(0, 72)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(ItemIcon.new(r.output_id))
	v.add_child(icon_box)
	var item := Inventory.get_item_def(r.output_id)
	var n := UiKit.label(item.display_name if item != null else r.output_id)
	n.name = "Name"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var cost := UiKit.label(_cost_short(r), "DimLabel")
	cost.name = "Cost"
	cost.add_theme_font_size_override("font_size", 12)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cost)
	return b

func _cost_short(r: Recipe) -> String:
	var parts: Array[String] = []
	for k in r.input_ids.size():
		var it := Inventory.get_item_def(r.input_ids[k])
		parts.append("%d %s" % [r.input_amounts[k], it.display_name if it != null else r.input_ids[k]])
	return "  ·  ".join(parts)

func _refresh() -> void:
	for i in _cards:
		var b: Button = _cards[i]
		var ok := _affordable(BUILDABLE_RECIPES[i])
		b.button_pressed = i == _selected_index
		# on the light plate the words turn dark (Warframe's selected item)
		var nm := b.find_child("Name", true, false) as Label
		if nm != null:
			nm.add_theme_color_override("font_color", UiTokens.ACCENT_INK if b.button_pressed else UiTokens.TEXT)
		b.modulate = Color(1, 1, 1, 1) if ok else Color(1, 1, 1, 0.55)
		var cost := b.find_child("Cost", true, false) as Label
		if cost != null:
			var carried := _carried(BUILDABLE_RECIPES[i])
			cost.text = "%d in inventory" % carried if carried > 0 else _cost_short(BUILDABLE_RECIPES[i])
			cost.theme_type_variation = ("AccentLabel" if carried > 0 else "DimLabel") if ok else "WarnLabel"
	_refresh_detail()

func _refresh_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if _hover < 0:
		return
	var r: Recipe = BUILDABLE_RECIPES[_hover]
	var item := Inventory.get_item_def(r.output_id)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(0, 110)
	icon_box.add_child(ItemIcon.new(r.output_id))
	_detail.add_child(icon_box)
	_detail.add_child(UiKit.title(item.display_name if item != null else r.output_id))
	var cat := UiKit.label(String(ItemInfo.CATEGORY_NAMES[ItemInfo.category(r.output_id)]).to_upper(), "SectionLabel")
	cat.add_theme_color_override("font_color", ItemInfo.color(r.output_id))
	_detail.add_child(cat)
	var d := UiKit.label(ItemInfo.description(r.output_id))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 230
	_detail.add_child(d)
	var carried := _carried(r)
	if carried > 0:
		_detail.add_child(UiKit.section("In inventory"))
		_detail.add_child(UiKit.label("%d ready to place, no materials used" % carried, "AccentLabel"))
	_detail.add_child(UiKit.section("Cost" if carried == 0 else "Cost once those are used"))
	for k in r.input_ids.size():
		var it := Inventory.get_item_def(r.input_ids[k])
		var have := Inventory.get_count(r.input_ids[k])
		var need := r.input_amounts[k]
		var line := UiKit.hbox(UiTokens.GAP)
		var ib := Control.new()
		ib.custom_minimum_size = Vector2(28, 28)
		ib.add_child(ItemIcon.new(r.input_ids[k]))
		line.add_child(ib)
		var nl := UiKit.label(it.display_name if it != null else r.input_ids[k])
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(nl)
		line.add_child(UiKit.label("%d / %d" % [have, need], "AccentLabel" if have >= need else "WarnLabel"))
		_detail.add_child(line)
	_detail.add_child(UiKit.spacer(false))
	_detail.add_child(UiKit.hint("LMB", "Pick and aim" if _affordable(r) else "Pick (not enough to place yet)"))

func _on_building_pressed(index: int) -> void:
	_selected_index = index
	_refresh()
	if _player != null and _player.has_method("on_build_picked"):
		_player.on_build_picked()

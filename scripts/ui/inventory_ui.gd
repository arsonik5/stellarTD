extends CanvasLayer

## The suit's storage (Tab). Standard screen frame: hands on the left (what the player holds - the tools),
## the storage grid in the middle, and the hovered item's detail on the right. Click to pick a stack up,
## click again to put it down, merge or swap (SlotCarry, the one slot interaction in the game). The carried
## stack follows the cursor as an icon.

const SlotCarry := preload("res://scripts/ui/slot_carry.gd")
const InventorySlotAdapter := preload("res://scripts/ui/inventory_slot_adapter.gd")

var _carry := SlotCarry.new()
var _grid_adapter := InventorySlotAdapter.new(InventorySlotAdapter.Kind.GRID)
var _hand_adapter := InventorySlotAdapter.new(InventorySlotAdapter.Kind.HAND)

var _frame: Dictionary
var _grid_slots: Array[SlotButton] = []
var _hand_slots: Array[SlotButton] = []
var _detail: VBoxContainer
var _cursor: ItemIcon
var _hover_id := "-"

func _ready() -> void:
	visible = false
	layer = 20
	add_to_group("inventory_ui")
	_frame = UiKit.screen("Inventory", [["LMB", "Pick up / put down"], ["Tab/Esc", "Close"]], Vector2(900, 0), "Suit  /")
	add_child(_frame.root)
	var row := UiKit.hbox(UiTokens.GAP_L + 8)
	(_frame.body as Control).add_child(row)

	var hands := UiKit.vbox(UiTokens.GAP)
	row.add_child(hands)
	hands.add_child(UiKit.section("Hands"))
	for i in 2:
		var s := SlotButton.new(76)
		s.pressed.connect(_on_slot.bind(_hand_adapter, i))
		s.mouse_entered.connect(_hover.bind(_hand_adapter, i))
		hands.add_child(s)
		_hand_slots.append(s)

	var store := UiKit.vbox(UiTokens.GAP)
	row.add_child(store)
	store.add_child(UiKit.section("Storage"))
	var grid := GridContainer.new()
	grid.columns = Inventory.GRID_COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	store.add_child(grid)
	for i in Inventory.GRID_SIZE:
		var s := SlotButton.new()
		s.pressed.connect(_on_slot.bind(_grid_adapter, i))
		s.mouse_entered.connect(_hover.bind(_grid_adapter, i))
		grid.add_child(s)
		_grid_slots.append(s)
	store.add_child(UiKit.hint_row([["LMB", "Pick up / put down, merge or swap"]]))

	var dpanel := UiKit.panel("Well")
	dpanel.custom_minimum_size = Vector2(240, 0)
	dpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dpanel)
	_detail = UiKit.vbox(UiTokens.GAP)
	dpanel.add_child(_detail)

	_cursor = ItemIcon.new()
	_cursor.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cursor.size = Vector2(56, 56)
	_cursor.visible = false
	add_child(_cursor)

	Inventory.changed.connect(_refresh_all)
	_carry.changed.connect(_refresh_all)

func toggle() -> void:
	# Delegates to close() rather than pre-flipping `visible` - close() guards on `visible` itself.
	if visible:
		close()
	else:
		visible = true
		UiState.set_open("inventory", true)
		_refresh_all()
		_show_detail("")
		UiKit.pop_in(_frame.root)
		QuestManager.notify_action("open_inventory")

func close() -> void:
	if not visible:
		return
	_carry.return_to_origin()
	visible = false
	UiState.set_open("inventory", false)
	UiSound.play("close")

func _process(_delta: float) -> void:
	if visible and _cursor.visible:
		_cursor.position = get_viewport().get_mouse_position() + Vector2(6, 6)

func _on_slot(adapter, index: int) -> void:
	_carry.click(adapter, index)

func _hover(adapter, index: int) -> void:
	_show_detail(String(adapter.get_slot(index).item_id))

func _refresh_all() -> void:
	for i in Inventory.GRID_SIZE:
		var s: Dictionary = _grid_adapter.get_slot(i)
		_grid_slots[i].show_slot(s.item_id, s.count)
	for i in 2:
		var s: Dictionary = _hand_adapter.get_slot(i)
		_hand_slots[i].show_slot(s.item_id, s.count, "LEFT HAND" if i == 0 else "RIGHT HAND")
	_cursor.visible = _carry.has_carried()
	_cursor.item_id = _carry.carried_item_id
	_cursor.count = _carry.carried_count

func _show_detail(id: String) -> void:
	if id == _hover_id:
		return
	_hover_id = id
	for c in _detail.get_children():
		c.queue_free()
	if id == "":
		_detail.add_child(UiKit.label("Select an item", "DimLabel"))
		return
	var item := Inventory.get_item_def(id)
	var ib := Control.new()
	ib.custom_minimum_size = Vector2(0, 96)
	ib.add_child(ItemIcon.new(id))
	_detail.add_child(ib)
	_detail.add_child(UiKit.title(item.display_name if item != null else id))
	var cat := UiKit.label(String(ItemInfo.CATEGORY_NAMES.get(ItemInfo.category(id), "")).to_upper(), "SectionLabel")
	cat.add_theme_color_override("font_color", ItemInfo.color(id))
	_detail.add_child(cat)
	var d := UiKit.label(ItemInfo.description(id))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 210
	_detail.add_child(d)
	_detail.add_child(UiKit.label("You carry %d" % Inventory.get_count(id), "DimLabel"))

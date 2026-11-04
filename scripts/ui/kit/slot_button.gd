class_name SlotButton
extends Button
## One inventory slot, the same everywhere (player grid, hands, machine storage, modifiers): a square well with the
## item icon and count. Empty slots can carry a faint caption ("LEFT HAND", "FUEL"). Hovering shows the item's name
## and what it is for (Godot tooltip, themed). Click behaviour stays with SlotCarry - this is only the look.

var _icon: ItemIcon
var _caption: Label

func _init(px: int = UiTokens.SLOT) -> void:
	theme_type_variation = "Slot"
	custom_minimum_size = Vector2(px, px)
	focus_mode = Control.FOCUS_NONE
	_icon = ItemIcon.new()
	add_child(_icon)
	_caption = Label.new()
	_caption.theme_type_variation = "SectionLabel"
	_caption.add_theme_font_size_override("font_size", 10)
	_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate = Color(1, 1, 1, 0.6)
	add_child(_caption)
	UiKit.juice(self)

func show_slot(item_id: String, count: int, empty_caption: String = "") -> void:
	_icon.item_id = item_id
	_icon.count = count
	_caption.text = empty_caption if item_id == "" else ""
	if item_id == "":
		tooltip_text = ""
	else:
		var item := Inventory.get_item_def(item_id)
		tooltip_text = "%s  x%d\n%s" % [item.display_name if item != null else item_id, count, ItemInfo.description(item_id)]

class_name SavesPanel
extends VBoxContainer
## Save manager: one card per save (name, play time, last played), Load and Delete on each, newest first.
## Delete asks inside the card (no pop-up window). Used by the main menu and the pause menu.
## `load_requested(id)` is emitted; the owner decides how to leave the current scene.

signal load_requested(slot_id: String)

var _list: VBoxContainer
var _empty: Label
var current_slot_hint := ""          # the pause menu marks the save that is being played

func _ready() -> void:
	add_theme_constant_override("separation", UiTokens.GAP)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = UiKit.vbox(UiTokens.GAP)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_empty = UiKit.label("No saves yet. Start a new game.", "DimLabel")
	refresh()

func refresh() -> void:
	for c in _list.get_children():
		if c != _empty:
			c.queue_free()
	if _empty.get_parent() == null:
		_list.add_child(_empty)
	var slots := SaveManager.list_slots()
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.updated_unix) > int(b.updated_unix))
	_empty.visible = slots.is_empty()
	for s: Dictionary in slots:
		_list.add_child(_card(s))
	UiKit.stagger(_list)

func _card(s: Dictionary) -> Control:
	var card := UiKit.panel("Card")
	var row := UiKit.hbox(UiTokens.GAP_L)
	card.add_child(row)
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_row := UiKit.hbox(UiTokens.GAP)
	name_row.add_child(UiKit.label(String(s.name)))
	if String(s.id) == current_slot_hint:
		name_row.add_child(UiKit.label("PLAYING", "AccentLabel"))
	info.add_child(name_row)
	info.add_child(UiKit.label("%s played   ·   %s" % [SaveManager.format_playtime(s.playtime_sec), _when(int(s.updated_unix))], "DimLabel"))
	var id := String(s.id)
	# Two-step delete inside the card, no pop-up: Delete turns the pair into "Keep" / "Delete for good".
	var left := UiKit.button("Load", Callable(), "PrimaryButton")
	var right := UiKit.button("Delete", Callable(), "DangerButton")
	left.custom_minimum_size.x = 110
	right.custom_minimum_size.x = 140
	right.disabled = id == current_slot_hint            # never delete the save that is being played
	var confirming := [false]
	left.pressed.connect(func() -> void:
		if confirming[0]:
			confirming[0] = false
			left.text = "Load"
			left.theme_type_variation = "PrimaryButton"
			right.text = "Delete"
		else:
			load_requested.emit(id))
	right.pressed.connect(func() -> void:
		if confirming[0]:
			UiSound.play("deny")
			SaveManager.delete_slot(id)
			refresh()
		else:
			confirming[0] = true
			left.text = "Keep"
			left.theme_type_variation = ""
			right.text = "Delete for good")
	row.add_child(left)
	row.add_child(right)
	return card

## Relative and readable: "today 19:11", "yesterday 08:02", "12 Sep 2026".
func _when(unix: int) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0) * 60
	var local := unix + bias
	var now := int(Time.get_unix_time_from_system()) + bias
	var d := Time.get_datetime_dict_from_unix_time(local)
	var hm := "%02d:%02d" % [d.hour, d.minute]
	var days := (now / 86400) - (local / 86400)
	if days == 0:
		return "today " + hm
	if days == 1:
		return "yesterday " + hm
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d" % [d.day, months[d.month - 1], d.year]

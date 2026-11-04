class_name SettingsPanel
extends VBoxContainer
## The settings page, built from GameSettings.SPEC: page tabs, then one row per option (name, control, help line).
## The same panel is used by the main menu and the pause menu, so the two never drift apart.

var _page := "Video"
var _tabs := {}
var _rows: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", UiTokens.GAP_L)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tabs := UiKit.hbox(0)
	add_child(tabs)
	for p in GameSettings.PAGES:
		var b := UiKit.button(String(p).to_upper(), _show.bind(p), "TabButton")
		b.toggle_mode = true
		tabs.add_child(b)
		_tabs[p] = b
	tabs.add_child(UiKit.spacer())
	tabs.add_child(UiKit.button("Reset page", func() -> void:
		GameSettings.reset_page(_page)
		_show(_page)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = UiKit.vbox(UiTokens.GAP_L)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_show(_page)

func show_page(page: String) -> void:
	_show(page)

func _show(page: String) -> void:
	_page = page
	for p in _tabs:
		(_tabs[p] as Button).button_pressed = p == page
	for c in _rows.get_children():
		c.queue_free()
	for key: String in GameSettings.SPEC:
		var spec: Array = GameSettings.SPEC[key]
		if spec[0] == page:
			_rows.add_child(_row(key, spec))
	UiKit.stagger(_rows)

func _row(key: String, spec: Array) -> Control:
	var col := UiKit.vbox(2)
	var row := UiKit.hbox(UiTokens.GAP_L)
	col.add_child(row)
	var name_l := UiKit.label(spec[1])
	name_l.custom_minimum_size.x = 200
	row.add_child(name_l)
	var value: Variant = GameSettings.get_value(key)
	match String(spec[2]):
		"slider":
			var ex: Array = spec[4]
			var s := HSlider.new()
			s.min_value = ex[0]
			s.max_value = ex[1]
			s.step = ex[2]
			s.value = float(value)
			s.custom_minimum_size = Vector2(240, 24)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.focus_mode = Control.FOCUS_NONE
			var readout := UiKit.label("", "AccentLabel")
			readout.custom_minimum_size.x = 64
			var fmt := func(x: float) -> String:
				if ex[3] == "":
					return "%d%%" % roundi(x * 100.0)
				return ("%d" % roundi(x) if ex[2] >= 1.0 else "%.2f" % x) + String(ex[3])
			readout.text = fmt.call(s.value)
			s.value_changed.connect(func(x: float) -> void:
				readout.text = fmt.call(x)
				UiSound.play("tick", 0.9 + 0.2 * inverse_lerp(s.min_value, s.max_value, x), 0.04)
				GameSettings.set_value(key, x))
			row.add_child(s)
			row.add_child(readout)
		"toggle":
			var c := CheckBox.new()
			c.button_pressed = bool(value)
			c.text = "On" if c.button_pressed else "Off"
			c.focus_mode = Control.FOCUS_NONE
			c.custom_minimum_size.x = 80
			c.toggled.connect(func(on: bool) -> void:
				c.text = "On" if on else "Off"
				UiSound.play("toggle_on" if on else "toggle_off")
				GameSettings.set_value(key, on))
			row.add_child(c)
		"choice":
			var o := OptionButton.new()
			for label: String in spec[4]:
				o.add_item(label)
			o.selected = int(value)
			o.custom_minimum_size = Vector2(240, UiTokens.BUTTON_H)
			o.focus_mode = Control.FOCUS_NONE
			o.item_selected.connect(func(i: int) -> void:
				UiSound.play("click")
				GameSettings.set_value(key, i))
			row.add_child(o)
	if String(spec[5]) != "":
		var help := UiKit.label(spec[5], "DimLabel")
		help.add_theme_font_size_override("font_size", 13)
		col.add_child(help)
	return col

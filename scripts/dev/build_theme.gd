extends SceneTree
## Generates ui/stellar_theme.tres from UiTokens - the project-wide theme (project.godot gui/theme/custom).
## Never hand-edit the .tres; change UiTokens or this file and rerun:
##   godot --headless --path . --script res://scripts/dev/build_theme.gd
## Look (docs/game/ux-bible.md): frosted glass, minimal, Warframe cuts. Translucent light sheets with a soft shadow
## and a faint rim, two big and two nearly square corners, ice-blue accent for selection/focus/values, the selected
## thing a solid light plate with dark text.
const T := preload("res://scripts/ui/kit/ui_tokens.gd")
const OUT := "res://ui/stellar_theme.tres"
const CLEAR := Color(0, 0, 0, 0)

var th := Theme.new()
var saira: FontFile

func _init() -> void:
	saira = load(T.FONT_FILE)
	if saira == null:
		push_error("Saira font missing - run godot --import first")
		quit(1)
		return
	th.default_font = _f(T.W_REGULAR)
	th.default_font_size = T.FS_BODY
	_labels()
	_panels()
	_buttons()
	_inputs()
	_bars()
	_scroll()
	_popups()
	var err := ResourceSaver.save(th, OUT)
	print("THEME saved %s err=%d" % [OUT, err])
	quit()

## Saira at a weight (and width: 100 normal, 112 for the wide titles), with optional letter spacing (px).
func _f(weight: int, spacing: int = 0, width: int = 100) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = saira
	var ts := TextServerManager.get_primary_interface()
	v.variation_opentype = {ts.name_to_tag("wght"): weight, ts.name_to_tag("wdth"): width}
	v.spacing_glyph = spacing
	return v

func _box(bg: Color, border: Color = CLEAR, bw: int = 0, mh: float = 12.0, mv: float = 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(0)
	s.content_margin_left = mh
	s.content_margin_right = mh
	s.content_margin_top = mv
	s.content_margin_bottom = mv
	s.anti_aliasing = false
	return s

## Glass sheet: translucent fill, faint rim, soft drop shadow, asymmetric corners (big top-left/bottom-right).
func _glass(bg: Color, border: Color = T.LINE, bw: int = 1, mh: float = 12.0, mv: float = 8.0, big: int = T.CORNER_BIG,
		shadow: int = 0) -> StyleBoxFlat:
	var s := _box(bg, border, bw, mh, mv)
	s.corner_radius_top_left = big
	s.corner_radius_bottom_right = big
	s.corner_radius_top_right = T.CORNER_SMALL
	s.corner_radius_bottom_left = T.CORNER_SMALL
	s.corner_detail = 6
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.32)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.35)
	return s

## A box with a border on some sides only (l, t, r, b widths).
func _edge(bg: Color, border: Color, l: int, t: int, r: int, b: int, mh: float = 12.0, mv: float = 8.0) -> StyleBoxFlat:
	var s := _box(bg, border, 0, mh, mv)
	s.border_width_left = l
	s.border_width_top = t
	s.border_width_right = r
	s.border_width_bottom = b
	return s

func _variation(name: String, base: String) -> void:
	th.add_type(name)
	th.set_type_variation(name, base)

func _labels() -> void:
	th.set_color("font_color", "Label", T.TEXT)
	th.set_color("font_shadow_color", "Label", CLEAR)
	th.set_font_size("font_size", "Label", T.FS_BODY)
	th.set_constant("line_spacing", "Label", 2)
	_variation("SectionLabel", "Label")                 # "STORAGE": small, tracked, gold-dim
	th.set_font("font", "SectionLabel", _f(T.W_MEDIUM, 3))
	th.set_font_size("font_size", "SectionLabel", T.FS_CAPTION)
	th.set_color("font_color", "SectionLabel", T.ACCENT_DIM)
	_variation("TitleLabel", "Label")                   # "INVENTORY": thin, wide, very tracked
	th.set_font("font", "TitleLabel", _f(T.W_LIGHT, 3, 104))
	th.set_font_size("font_size", "TitleLabel", T.FS_TITLE)
	_variation("DisplayLabel", "Label")
	th.set_font("font", "DisplayLabel", _f(T.W_LIGHT, 4, 104))
	th.set_font_size("font_size", "DisplayLabel", T.FS_DISPLAY)
	_variation("CrumbLabel", "Label")                   # breadcrumb over a title: "SUIT  /"
	th.set_font("font", "CrumbLabel", _f(T.W_MEDIUM, 3))
	th.set_font_size("font_size", "CrumbLabel", T.FS_CAPTION)
	th.set_color("font_color", "CrumbLabel", T.TEXT_DIM)
	_variation("DimLabel", "Label")
	th.set_color("font_color", "DimLabel", T.TEXT_DIM)
	_variation("AccentLabel", "Label")
	th.set_color("font_color", "AccentLabel", T.ACCENT)
	th.set_font("font", "AccentLabel", _f(T.W_MEDIUM))
	_variation("ValueLabel", "Label")                   # numbers that matter
	th.set_color("font_color", "ValueLabel", T.ACCENT)
	th.set_font("font", "ValueLabel", _f(T.W_SEMI))
	_variation("GoodLabel", "Label")
	th.set_color("font_color", "GoodLabel", T.GOOD)
	_variation("WarnLabel", "Label")
	th.set_color("font_color", "WarnLabel", T.WARN)
	_variation("DangerLabel", "Label")
	th.set_color("font_color", "DangerLabel", T.DANGER)
	# HUD text sits straight on the world, no panels: a soft shadow and a thin dark outline carry it
	for hv in ["HudLabel", "HudCaption", "HudValue"]:
		_variation(hv, "Label")
		th.set_color("font_outline_color", hv, Color(0, 0, 0, 0.35))
		th.set_constant("outline_size", hv, 1)
		th.set_color("font_shadow_color", hv, Color(0, 0, 0, 0.75))
		th.set_constant("shadow_offset_x", hv, 0)
		th.set_constant("shadow_offset_y", hv, 1)
		th.set_constant("shadow_outline_size", hv, 0)
	th.set_font("font", "HudLabel", _f(T.W_MEDIUM))
	th.set_font_size("font_size", "HudLabel", T.FS_HUD)
	th.set_font("font", "HudCaption", _f(T.W_MEDIUM, 3))
	th.set_font_size("font_size", "HudCaption", T.FS_CAPTION)
	th.set_color("font_color", "HudCaption", T.ACCENT)          # full gold on the HUD: dim gold vanishes on bright ground
	th.set_font("font", "HudValue", _f(T.W_SEMI, 1))
	th.set_font_size("font_size", "HudValue", 22)
	# key cap: an outlined key, not a filled one - "[E]" in the thin-line language
	_variation("KeyCap", "Label")
	th.set_font("font", "KeyCap", _f(T.W_SEMI, 1))
	th.set_font_size("font_size", "KeyCap", T.FS_CAPTION)
	th.set_color("font_color", "KeyCap", T.TEXT)
	th.set_stylebox("normal", "KeyCap", _box(Color(0, 0, 0, 0.25), Color(T.TEXT, 0.55), 1, 5.0, 1.0))
	th.set_font_size("font_size", "RichTextLabel", T.FS_BODY)
	th.set_color("default_color", "RichTextLabel", T.TEXT)

func _panels() -> void:
	var panel := _glass(T.PANEL, T.LINE, 1, T.PAD, T.PAD, T.CORNER_BIG, 16)
	th.set_stylebox("panel", "Panel", panel)
	th.set_stylebox("panel", "PanelContainer", panel)
	_variation("Card", "PanelContainer")                # a row-like block: faint light strip
	th.set_stylebox("panel", "Card", _glass(T.STRIP, Color(T.LINE, 0.6), 1, 14.0, 10.0, 6))
	_variation("Well", "PanelContainer")                # detail pane: dark, hairline frame
	th.set_stylebox("panel", "Well", _glass(T.PANEL, T.LINE, 1, 16.0, 14.0, T.CORNER_BIG, 18))
	_variation("HudPanel", "PanelContainer")            # HUD: no box at all, only spacing
	th.set_stylebox("panel", "HudPanel", _box(CLEAR, CLEAR, 0, 0.0, 0.0))
	_variation("HeaderBar", "PanelContainer")
	th.set_stylebox("panel", "HeaderBar", _box(CLEAR, CLEAR, 0, 0.0, 0.0))
	_variation("Backdrop", "PanelContainer")
	th.set_stylebox("panel", "Backdrop", _box(T.SHADE, CLEAR, 0, 0.0, 0.0))

func _button_set(type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox,
		fc: Color, fc_hover: Color, fc_pressed: Color) -> void:
	th.set_stylebox("normal", type, normal)
	th.set_stylebox("hover", type, hover)
	th.set_stylebox("pressed", type, pressed)
	th.set_stylebox("hover_pressed", type, pressed)
	th.set_stylebox("disabled", type, disabled)
	th.set_stylebox("focus", type, _box(CLEAR, T.ACCENT, 1))
	th.set_color("font_color", type, fc)
	th.set_color("font_hover_color", type, fc_hover)
	th.set_color("font_focus_color", type, fc)
	th.set_color("font_pressed_color", type, fc_pressed)
	th.set_color("font_hover_pressed_color", type, fc_pressed)
	th.set_color("font_disabled_color", type, T.TEXT_FAINT)

func _buttons() -> void:
	# default: a faint strip; hover brightens it and draws a gold underline; selected = the light plate
	_button_set("Button",
		_glass(T.STRIP, Color(T.LINE, 0.7), 1, 16.0, 8.0, 6),
		_glass(T.STRIP_HI, T.ACCENT, 1, 16.0, 8.0, 6),
		_glass(T.PLATE, CLEAR, 0, 16.0, 8.0, 6),
		_glass(Color(1, 1, 1, 0.02), Color(T.LINE, 0.3), 1, 16.0, 8.0, 6), T.TEXT, T.TEXT, T.ACCENT_INK)
	th.set_font("font", "Button", _f(T.W_MEDIUM, 1))
	th.set_font_size("font_size", "Button", 14)
	# primary: the one main action - gold outline, solid gold on hover
	_variation("PrimaryButton", "Button")
	_button_set("PrimaryButton",
		_glass(T.ACCENT_DEEP, T.ACCENT, 1, 18.0, 8.0, 6),
		_glass(T.ACCENT, T.ACCENT, 1, 18.0, 8.0, 6),
		_glass(T.ACCENT.darkened(0.15), T.ACCENT, 1, 18.0, 8.0, 6),
		_glass(Color(T.ACCENT, 0.06), Color(T.ACCENT, 0.3), 1, 18.0, 8.0, 6), T.ACCENT, T.ACCENT_INK, T.ACCENT_INK)
	th.set_font("font", "PrimaryButton", _f(T.W_SEMI, 2))
	_variation("DangerButton", "Button")
	_button_set("DangerButton",
		_box(CLEAR, Color(T.DANGER, 0.55), 1, 16.0, 8.0),
		_box(T.DANGER, T.DANGER, 1, 16.0, 8.0),
		_box(T.DANGER.darkened(0.25), T.DANGER, 1, 16.0, 8.0),
		_box(CLEAR, Color(T.LINE, 0.5), 1, 16.0, 8.0), T.DANGER.lightened(0.15), T.ACCENT_INK, T.TEXT)
	# nav: menu entries - bare text; hover = faint strip + gold bar on the left; open page = the light plate
	_variation("NavButton", "Button")
	_button_set("NavButton",
		_box(CLEAR, CLEAR, 0, 18.0, 10.0),
		_edge(T.STRIP, T.ACCENT, 2, 0, 0, 0, 18.0, 10.0),
		_box(T.PLATE, CLEAR, 0, 18.0, 10.0),
		_box(CLEAR, CLEAR, 0, 18.0, 10.0), T.TEXT, T.TEXT, T.ACCENT_INK)
	th.set_font("font", "NavButton", _f(T.W_MEDIUM, 2, 104))
	th.set_font_size("font_size", "NavButton", T.FS_NAV)
	# tab: dim text; hover lights it; the open tab sits in a hairline box (Warframe's options tabs)
	_variation("TabButton", "Button")
	_button_set("TabButton",
		_box(CLEAR, CLEAR, 0, 14.0, 7.0),
		_box(T.STRIP, CLEAR, 0, 14.0, 7.0),
		_box(Color(1, 1, 1, 0.06), T.LINE_HI, 1, 14.0, 7.0),
		_box(CLEAR, CLEAR, 0, 14.0, 7.0), T.TEXT_DIM, T.TEXT, T.TEXT)
	th.set_font("font", "TabButton", _f(T.W_MEDIUM, 3))
	th.set_font_size("font_size", "TabButton", 12)
	# slot: dark well with a hairline; hover = gold hairline; carrying/selected = gold wash
	_variation("Slot", "Button")
	_button_set("Slot",
		_glass(T.WELL, T.LINE, 1, 4.0, 4.0, 5),
		_glass(Color(0.04, 0.09, 0.13, 0.5), T.ACCENT, 1, 4.0, 4.0, 5),
		_glass(T.ACCENT_DEEP, T.ACCENT, 1, 4.0, 4.0, 5),
		_glass(Color(0, 0, 0, 0.2), Color(T.LINE, 0.5), 1, 4.0, 4.0, 5), T.TEXT, T.TEXT, T.TEXT)
	th.set_font_size("font_size", "Slot", T.FS_CAPTION)
	# card: the build menu's catalogue tiles - strip, hover gold underline, selected = light plate
	_variation("CardButton", "Button")
	_button_set("CardButton",
		_box(T.STRIP, CLEAR, 0, 8.0, 8.0),
		_edge(T.STRIP_HI, T.ACCENT, 0, 0, 0, 2, 8.0, 8.0),
		_box(T.PLATE, CLEAR, 0, 8.0, 8.0),
		_box(Color(1, 1, 1, 0.02), CLEAR, 0, 8.0, 8.0), T.TEXT, T.TEXT, T.ACCENT_INK)
	for t in ["CheckBox", "CheckButton", "OptionButton", "MenuButton"]:
		th.set_color("font_color", t, T.TEXT)
		th.set_color("font_hover_color", t, T.TEXT)
		th.set_color("font_pressed_color", t, T.TEXT)
		th.set_color("font_hover_pressed_color", t, T.TEXT)
		th.set_font("font", t, _f(T.W_MEDIUM, 1))
		th.set_font_size("font_size", t, 14)
	th.set_stylebox("normal", "OptionButton", _box(T.STRIP, CLEAR, 0, 12.0, 7.0))
	th.set_stylebox("hover", "OptionButton", _edge(T.STRIP_HI, T.ACCENT, 0, 0, 0, 1, 12.0, 7.0))
	th.set_stylebox("pressed", "OptionButton", _box(T.STRIP_HI, T.ACCENT, 1, 12.0, 7.0))
	th.set_stylebox("focus", "OptionButton", _box(CLEAR, T.ACCENT, 1))
	th.set_icon("arrow", "OptionButton", _arrow_icon())
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		th.set_stylebox(st, "CheckBox", _box(CLEAR, CLEAR, 0, 2.0, 4.0))

func _inputs() -> void:
	th.set_stylebox("normal", "LineEdit", _edge(Color(0, 0, 0, 0.3), T.LINE_HI, 0, 0, 0, 1, 12.0, 8.0))
	th.set_stylebox("focus", "LineEdit", _edge(Color(0, 0, 0, 0.4), T.ACCENT, 0, 0, 0, 2, 12.0, 8.0))
	th.set_color("font_color", "LineEdit", T.TEXT)
	th.set_color("caret_color", "LineEdit", T.ACCENT)
	th.set_color("selection_color", "LineEdit", Color(T.ACCENT, 0.3))
	th.set_color("font_placeholder_color", "LineEdit", T.TEXT_FAINT)
	th.set_font("font", "LineEdit", _f(T.W_MEDIUM, 1))
	th.set_font_size("font_size", "LineEdit", 16)
	# sliders: a 2 px hairline rail, gold fill, a small gold diamond grabber (Warframe's sliders)
	var rail := _box(Color(1, 1, 1, 0.14), CLEAR, 0, 0.0, 1.0)
	th.set_stylebox("slider", "HSlider", rail)
	var fill := _box(T.ACCENT, CLEAR, 0, 0.0, 1.0)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", _diamond(14, T.ACCENT))
	th.set_icon("grabber_highlight", "HSlider", _diamond(16, T.TEXT))
	th.set_icon("checked", "CheckBox", _check_icon(true))
	th.set_icon("unchecked", "CheckBox", _check_icon(false))

func _diamond(s: int, c: Color) -> ImageTexture:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	var h := (s - 1) * 0.5
	for y in s:
		for x in s:
			var d := absf(x - h) + absf(y - h)
			if d <= h - 0.5:
				img.set_pixel(x, y, c)
			elif d <= h + 0.5:
				img.set_pixel(x, y, Color(c, h + 0.5 - d))
	return ImageTexture.create_from_image(img)

func _arrow_icon() -> ImageTexture:
	var img := Image.create(10, 6, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	for i in 5:
		img.set_pixel(i, i, T.ACCENT)
		img.set_pixel(9 - i, i, T.ACCENT)
	return ImageTexture.create_from_image(img)

## Toggle: a hairline square; on = gold fill with a dark tick, off = an empty box with a faint cross.
func _check_icon(on: bool) -> ImageTexture:
	var s := 18
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(T.ACCENT if on else Color(0, 0, 0, 0.3))
	var edge := T.ACCENT if on else T.LINE_HI
	for i in s:
		for e in [0, s - 1]:
			img.set_pixel(i, e, edge)
			img.set_pixel(e, i, edge)
	if on:
		for p in [Vector2i(4, 9), Vector2i(5, 10), Vector2i(6, 11), Vector2i(7, 12), Vector2i(8, 11), Vector2i(9, 10),
				Vector2i(10, 9), Vector2i(11, 8), Vector2i(12, 7), Vector2i(13, 6)]:
			img.set_pixel(p.x, p.y, T.ACCENT_INK)
			img.set_pixel(p.x, p.y - 1, T.ACCENT_INK)
	else:
		for i in range(5, 13):
			img.set_pixel(i, i, Color(T.TEXT, 0.3))
			img.set_pixel(17 - i, i, Color(T.TEXT, 0.3))
	return ImageTexture.create_from_image(img)

func _bars() -> void:
	th.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.12), CLEAR, 0, 0.0, 0.0))
	th.set_stylebox("fill", "ProgressBar", _box(T.ACCENT, CLEAR, 0, 0.0, 0.0))
	th.set_color("font_color", "ProgressBar", T.TEXT)
	for pair in [["GoodBar", T.GOOD], ["WarnBar", T.WARN], ["DangerBar", T.DANGER], ["LightBar", T.TEXT]]:
		_variation(pair[0], "ProgressBar")
		th.set_stylebox("fill", pair[0], _box(pair[1], CLEAR, 0, 0.0, 0.0))

func _scroll() -> void:
	for t in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", t, _box(Color(1, 1, 1, 0.04), CLEAR, 0, 1.0, 1.0))
		th.set_stylebox("grabber", t, _box(Color(T.TEXT, 0.25), CLEAR, 0, 1.0, 1.0))
		th.set_stylebox("grabber_highlight", t, _box(Color(T.TEXT, 0.5), CLEAR, 0, 1.0, 1.0))
		th.set_stylebox("grabber_pressed", t, _box(T.ACCENT, CLEAR, 0, 1.0, 1.0))
	th.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

func _popups() -> void:
	th.set_stylebox("panel", "PopupMenu", _glass(Color(0.04, 0.07, 0.10, 0.88), T.LINE_HI, 1, 4.0, 4.0, 6))
	th.set_stylebox("hover", "PopupMenu", _box(T.PLATE, CLEAR, 0, 10.0, 5.0))
	th.set_color("font_color", "PopupMenu", T.TEXT)
	th.set_color("font_hover_color", "PopupMenu", T.ACCENT_INK)
	th.set_font("font", "PopupMenu", _f(T.W_MEDIUM, 1))
	th.set_stylebox("panel", "TooltipPanel", _glass(Color(0.04, 0.07, 0.10, 0.88), T.LINE_HI, 1, 12.0, 8.0, 6, 10))
	th.set_color("font_color", "TooltipLabel", T.TEXT)
	th.set_font("font", "TooltipLabel", _f(T.W_REGULAR))
	th.set_stylebox("embedded_border", "Window", _box(Color("0a0f14"), T.LINE_HI, 1, 16.0, 16.0))
	th.set_stylebox("panel", "AcceptDialog", _box(Color("0a0f14"), CLEAR, 0, 16.0, 16.0))
	th.set_color("title_color", "Window", T.TEXT)

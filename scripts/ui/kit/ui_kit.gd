class_name UiKit
## Builders for the standard UI pieces (docs/game/ux-bible.md, "Components"). Screens are composed from these
## so a title, a key hint or a slot looks, moves and sounds the same everywhere. Styling lives in the theme
## (ui/stellar_theme.tres, generated from UiTokens); motion in UiMotion (anime.js model); sound in UiSound.

const BACKDROP_SHADER := preload("res://ui/shaders/backdrop.gdshader")

static func vbox(sep: int = UiTokens.GAP) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

static func hbox(sep: int = UiTokens.GAP) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

static func panel(variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p

static func label(text: String, variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l

## Small tracked gold-dim caps heading inside a screen ("STORAGE").
static func section(text: String) -> Label:
	return label(text.to_upper(), "SectionLabel")

## Thin, wide-spaced title capitals ("INVENTORY").
static func title(text: String) -> Label:
	return label(text.to_upper(), "TitleLabel")

## Buttons answer with sound and motion (juice). Nav entries indent, tabs only sound, everything else lifts.
static func button(text: String, on_pressed: Callable = Callable(), variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size.y = UiTokens.BUTTON_H
	b.focus_mode = Control.FOCUS_NONE
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	var kind := "lift"
	if variation == "NavButton":
		kind = "indent"
	elif variation == "TabButton":
		kind = "none"
	juice(b, kind, "confirm" if variation == "PrimaryButton" else ("tick" if variation == "TabButton" else "click"))
	return b

static func spacer(expand_h: bool = true) -> Control:
	var c := Control.new()
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## A key drawn as an outlined key cap: [E].
static func keycap(key: String) -> Label:
	var l := label(key, "KeyCap")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 20
	return l

## "[E] Open Smelter" - the one way a key is ever shown to the player.
static func hint(key: String, text: String, on_hud: bool = false) -> HBoxContainer:
	var row := hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in key.split("/"):
		row.add_child(keycap(k.strip_edges()))
	var l := label(text.to_upper(), "HudCaption" if on_hud else "CrumbLabel")
	if on_hud:
		l.add_theme_color_override("font_color", UiTokens.TEXT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row

## A row of hints, evenly spaced.
static func hint_row(pairs: Array, on_hud: bool = false) -> HBoxContainer:
	var row := hbox(22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in pairs:
		row.add_child(hint(p[0], p[1], on_hud))
	return row

## Short accent bar then a faint hairline - underlines every screen title (one Warframe-style mark, no ornament).
static func rule(width: float = 320.0) -> Control:
	var r := Control.new()
	r.custom_minimum_size = Vector2(width, 3)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.draw.connect(func() -> void:
		r.draw_line(Vector2(0, 1.5), Vector2(r.size.x, 1.5), Color(UiTokens.LINE, 0.12), 1.0)
		r.draw_rect(Rect2(0, 0, 44, 3), UiTokens.ACCENT))
	return r

## Square inventory slot.
static func slot(size: int = UiTokens.SLOT) -> Button:
	return SlotButton.new(size)

## The layer behind every full-screen UI: the world blurred and darkened (ui/shaders/backdrop.gdshader).
## Stops clicks reaching the world.
static func shade(tint: Color = UiTokens.SHADE) -> ColorRect:
	var c := ColorRect.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var m := ShaderMaterial.new()
	m.shader = BACKDROP_SHADER
	m.set_shader_parameter("tint", tint)
	c.material = m
	return c

static func bar(variation: String = "", height: int = 3) -> ProgressBar:
	var p := ProgressBar.new()
	p.theme_type_variation = variation
	p.show_percentage = false
	p.custom_minimum_size.y = height
	p.max_value = 1.0
	p.step = 0.0
	return p

## Centered container that fills the screen.
static func centered() -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## The standard full-screen frame (Warframe-style: no box around the screen). Blurred world behind; breadcrumb,
## thin title and gold rule top-left; the body fills the space under it, aligned to the same left edge; key hints
## bottom-right. Returns {root, panel (the body area, for hit tests), body, title, header (row after the title
## for status words), footer}. Open it with UiKit.pop_in(root) for the standard entrance.
static func screen(title_text: String, hints: Array, _min_size: Vector2 = Vector2.ZERO, crumb: String = "") -> Dictionary:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := shade()
	root.add_child(back)
	var head := vbox(6)
	head.position = Vector2(UiTokens.EDGE, 40)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	var crumb_l := label(crumb.to_upper(), "CrumbLabel")
	crumb_l.visible = false          # breadcrumbs ("SUIT /") were decoration: the title says where you are
	head.add_child(crumb_l)
	var trow := hbox(UiTokens.GAP_L + 4)
	head.add_child(trow)
	var t := title(title_text)
	trow.add_child(t)
	var r := rule()
	head.add_child(r)
	var body := MarginContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("margin_left", UiTokens.EDGE)
	body.add_theme_constant_override("margin_right", UiTokens.EDGE)
	body.add_theme_constant_override("margin_top", 150)
	body.add_theme_constant_override("margin_bottom", 84)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	var foot := hint_row(hints)
	foot.anchor_left = 1.0
	foot.anchor_right = 1.0
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_right = -UiTokens.EDGE
	foot.offset_bottom = -36
	root.add_child(foot)
	var frame := {"root": root, "panel": body, "body": body, "title": t, "header": trow, "footer": foot,
		"backdrop": back, "head": head, "rule": r, "crumb": crumb_l}
	root.set_meta("uikit_frame", frame)
	return frame

# --- motion ---------------------------------------------------------------------------------------------
## Entrance. For a UiKit.screen root: the world blurs in, the title tracks in from wide letter spacing, the rule
## draws out from its diamond, the body's rows arrive one after another, the hints fade up. Anything else:
## fade + small rise. Every screen opening plays the "open" sound.
static func pop_in(c: CanvasItem) -> void:
	if not (c is Control) or not is_instance_valid(c):
		return
	var ctl := c as Control
	UiSound.play("open")
	if not ctl.has_meta("uikit_frame"):
		UiMotion.animate(ctl, {"opacity": [0.0, 1.0]}, {"duration": 0.28, "easing": "outQuad"})
		return
	var f: Dictionary = ctl.get_meta("uikit_frame")
	var mat := (f.backdrop as ColorRect).material as ShaderMaterial
	var tw := ctl.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("blur", 0.0)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.22)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("blur", v), 0.0, 3.2, 0.45)
	UiMotion.animate(f.head, {"opacity": [0.0, 1.0], "x": [-24, 0]}, {"duration": 0.7, "easing": "outExpo"})
	title_in(f.title)
	var r: Control = f.rule
	r.pivot_offset = Vector2(0, 4.5)
	UiMotion.animate(r, {"scale": [Vector2(0, 1), Vector2.ONE]}, {"duration": 0.8, "delay": 0.12, "easing": "outExpo"})
	UiMotion.animate(f.footer, {"opacity": [0.0, 1.0]}, {"duration": 0.4, "delay": 0.25, "easing": "outQuad"})
	var body: Control = f.body
	if body.get_child_count() > 0:
		var first := body.get_child(0) as Control
		var rows: Array = []
		for ch in first.get_children():
			if ch is Control and (ch as Control).visible:
				rows.append(ch)
		if rows.is_empty():
			rows = [first]
		UiMotion.animate(rows, {"opacity": [0.0, 1.0], "y": [16, 0]}, {"duration": 0.6, "delay": UiMotion.stagger(0.05, {"start": 0.08}), "easing": "outExpo"})

## A title tracking in: letter spacing closes from wide to its set value while it fades up.
static func title_in(l: Label, from_spacing: int = 26) -> void:
	if not is_instance_valid(l):
		return
	var base := l.get_theme_font("font") as FontVariation
	if base == null:
		return
	var fv := base.duplicate() as FontVariation
	var to := base.spacing_glyph
	l.add_theme_font_override("font", fv)
	fv.spacing_glyph = from_spacing
	var tw := l.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(l):
			fv.spacing_glyph = int(round(v))
			l.queue_redraw(), float(from_spacing), float(to), 0.9)

## Rows of a list arrive one after another: fade + 12 px rise, 35 ms apart, outExpo (anime.js stagger).
static func stagger(box: Control) -> void:
	var rows: Array = []
	for ch in box.get_children():
		if ch is Control and (ch as Control).visible and not ch.is_queued_for_deletion():
			rows.append(ch)
	UiMotion.animate(rows.slice(0, 16), {"opacity": [0.0, 1.0], "y": [12, 0]}, {"duration": 0.55, "delay": UiMotion.stagger(0.035), "easing": "outExpo"})

## Feedback on a control: sound on hover and press, plus motion by kind -
##   "lift"   (slots, cards, small buttons) springs up 4 % on hover, dips on press
##   "indent" (nav entries) slides 8 px right on hover
##   "none"   sound only
static func juice(c: Control, kind: String = "lift", press_sound: String = "click") -> void:
	if c.has_meta("juiced"):
		return
	c.set_meta("juiced", true)
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	c.mouse_entered.connect(func() -> void:
		if c is BaseButton and (c as BaseButton).disabled:
			return
		UiSound.play("hover")
		if kind == "lift":
			UiMotion.animate(c, {"scale": 1.04}, {"easing": "spring(1, 180, 12, 0)"})
		elif kind == "indent":
			UiMotion.animate(c, {"x": [0, 8]}, {"duration": 0.35, "easing": "outExpo"})
		)
	c.mouse_exited.connect(func() -> void:
		if kind == "lift":
			UiMotion.animate(c, {"scale": 1.0}, {"easing": "spring(1, 180, 14, 0)"})
		elif kind == "indent":
			UiMotion.animate(c, {"x": [8, 0]}, {"duration": 0.4, "easing": "outExpo"})
		)
	if c is BaseButton:
		var b := c as BaseButton
		b.button_down.connect(func() -> void:
			if kind == "lift":
				UiMotion.animate(c, {"scale": 0.96}, {"duration": 0.07, "easing": "outQuad"}))
		b.button_up.connect(func() -> void:
			if kind == "lift":
				var over := c.get_global_rect().has_point(c.get_global_mouse_position())
				UiMotion.animate(c, {"scale": 1.04 if over else 1.0}, {"easing": "spring(1, 220, 10, 0)"}))
		b.pressed.connect(func() -> void:
			if press_sound != "":
				UiSound.play(press_sound))

## A "no": the control shakes sideways and the error sound plays (anime.js keyframes).
static func shake(c: Control, sound: String = "error") -> void:
	if sound != "":
		UiSound.play(sound)
	UiMotion.keys(c, "x", [-9, 9, -6, 6, -3, 3, 0], 0.36, "outSine")

## A short attention pulse (value changed, goal updated): brighten and settle back.
static func pulse(c: CanvasItem, col: Color = Color(1.5, 1.3, 0.9)) -> void:
	if not is_instance_valid(c):
		return
	c.modulate = col
	UiMotion.animate(c, {"modulate": Color.WHITE}, {"duration": 0.6, "easing": "outQuad"})

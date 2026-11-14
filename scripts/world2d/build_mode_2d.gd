class_name BuildMode2D
extends Node2D

## Build mode for the 2D world (pivot-2d.md C4), Mindustry/Factorio feel:
##   1-5        pick a building from the bar (enters build mode)      R      rotate
##   LMB        place; drag with a belt to lay a line in the drag direction
##   X          dismantle mode (LMB takes down what is under the cursor, full refund)
##   Esc / RMB  leave build mode                                       E      open/close the panel of a machine
## While build mode is on, the player's mining is off (the mouse belongs to building).

signal mode_changed(active: bool)

var build: BuildGrid2D
var view: WorldView
var player: Player2D
var selected := ""
var rot := 0
var dismantle := false
var active := false

var _bar: HBoxContainer
var _tip: Label
var _panel: PanelContainer
var _panel_label: Label
var _panel_target: Building2D
var _drag_from := Vector2i(-1, -1)
var _last_placed := Vector2i(-1, -1)

func setup(b: BuildGrid2D, v: WorldView, p: Player2D, ui: CanvasLayer) -> void:
	build = b
	view = v
	player = p
	z_index = 210
	_bar = HBoxContainer.new()
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.position = Vector2(8, -58)
	_bar.add_theme_constant_override("separation", 6)
	ui.add_child(_bar)
	_tip = Label.new()
	_tip.add_theme_color_override("font_outline_color", Color.BLACK)
	_tip.add_theme_constant_override("outline_size", 4)
	ui.add_child(_tip)
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 70)
	_panel.visible = false
	_panel_label = Label.new()
	_panel.add_child(_panel_label)
	ui.add_child(_panel)
	_rebuild_bar()
	Inventory.changed.connect(_rebuild_bar)

func _rebuild_bar() -> void:
	for c in _bar.get_children():
		c.queue_free()
	var ids := BuildGrid2D.buildable_ids()
	for i in ids.size():
		var id: String = ids[i]
		var item := Inventory.get_item_def(id)
		var l := Label.new()
		var carried := Inventory.get_count(id)
		var name_s := item.display_name if item != null else id
		l.text = "%d %s\n%s" % [i + 1, name_s, ("x%d carried" % carried) if carried > 0 else _cost_text(id)]
		var ok := build.can_pay(id)
		l.add_theme_color_override("font_color", Color(1, 0.85, 0.5) if id == selected else (Color(0.9, 0.9, 0.92) if ok else Color(0.6, 0.45, 0.42)))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		_bar.add_child(l)

func _cost_text(id: String) -> String:
	var r := build.build_recipe(id)
	if r == null:
		return "-"
	var parts: Array[String] = []
	for k in r.input_ids.size():
		parts.append("%d %s" % [r.input_amounts[k], r.input_ids[k].replace("refined_", "").replace("_ingot", "")])
	return ", ".join(parts)

func _set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	player.mining_enabled = not on
	if not on:
		selected = ""
		dismantle = false
	_rebuild_bar()
	mode_changed.emit(on)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var ids := BuildGrid2D.buildable_ids()
		if e.keycode >= KEY_1 and e.keycode < KEY_1 + ids.size():
			selected = ids[e.keycode - KEY_1]
			dismantle = false
			_set_active(true)
			_rebuild_bar()
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_R and active:
			rot = (rot + 1) % 4
			UiSound.play("tick")
		elif e.keycode == KEY_X:
			dismantle = not (active and dismantle)
			selected = ""
			_set_active(dismantle)
		elif e.keycode == KEY_ESCAPE and active:
			_set_active(false)
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_E:
			_toggle_panel()
	elif e is InputEventMouseButton and active:
		if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			_set_active(false)
			get_viewport().set_input_as_handled()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag_from = _cursor_tile()
				_last_placed = Vector2i(-1, -1)
				_act_at(_drag_from)
			else:
				_drag_from = Vector2i(-1, -1)
			get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if active and _drag_from.x >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and (selected == BuildGrid2D.BELT or dismantle):
		var t := _cursor_tile()
		if t != _last_placed:
			# belts follow the drag: the direction from the last tile to this one
			if selected == BuildGrid2D.BELT and _last_placed.x >= 0:
				var d := t - _last_placed
				if absi(d.x) + absi(d.y) == 1:
					rot = BuildGrid2D.DIRS.find(d)
					# turn the previous belt too, so the line bends where the drag bends
					if build.belts.has_belt(_last_placed):
						(build.belts.belts[_last_placed] as BeltSystem2D.Belt).dir = d
			_act_at(t)
	_update_tip()
	if _panel.visible:
		_fill_panel()
	queue_redraw()

func _cursor_tile() -> Vector2i:
	return view.pick_tile(get_global_mouse_position(), player.level)

## Top-left tile for placing `selected` so its footprint is centred on the cursor tile.
func _origin_for(t: Vector2i) -> Vector2i:
	var f := build.footprint(selected, rot)
	return t - Vector2i((f.x - 1) / 2, (f.y - 1) / 2)

func _act_at(t: Vector2i) -> void:
	if dismantle:
		if build.dismantle_at(t):
			UiSound.play("back")
		_last_placed = t
		return
	if selected == "":
		return
	var o := _origin_for(t)
	var why := build.can_place(selected, o, rot)
	if why == "" and not build.can_pay(selected):
		why = "Can't afford"
	if why != "":
		if _last_placed.x < 0:
			UiSound.play("deny")
		_last_placed = t
		return
	build.place(selected, o, rot)
	UiSound.play("place")
	_last_placed = t
	_rebuild_bar()

func _update_tip() -> void:
	_tip.visible = active
	if not active:
		return
	var vp := get_viewport()
	_tip.position = vp.get_mouse_position() + Vector2(18, 14)
	if dismantle:
		_tip.text = "DISMANTLE  (X / Esc to stop)"
		return
	var o := _origin_for(_cursor_tile())
	var why := build.can_place(selected, o, rot)
	if why == "" and not build.can_pay(selected):
		why = "Can't afford: " + _cost_text(selected)
	_tip.text = why if why != "" else "R rotate   LMB place" + ("   drag for a line" if selected == BuildGrid2D.BELT else "")

func _draw() -> void:
	if not active:
		return
	var ts := float(WorldGrid.TILE_PX)
	var t := _cursor_tile()
	if dismantle:
		var lv := build.grid.level_at(t.x, t.y)
		var a := view.leaned(Vector2(t) * ts, lv)
		var b := view.leaned(Vector2(t + Vector2i.ONE) * ts, lv)
		draw_rect(Rect2(a, b - a), Color(1, 0.35, 0.3, 0.35))
		draw_rect(Rect2(a, b - a), Color(1, 0.35, 0.3, 0.9), false, 2.0)
		return
	if selected == "":
		return
	var o := _origin_for(t)
	var f := build.footprint(selected, rot)
	var lv0 := build.grid.level_at(o.x, o.y)
	var ok := build.can_place(selected, o, rot) == "" and build.can_pay(selected)
	var col := Color(0.55, 0.95, 0.7) if ok else Color(1.0, 0.4, 0.35)
	var a := view.leaned(Vector2(o) * ts, lv0)
	var b := view.leaned(Vector2(o + f) * ts, lv0)
	draw_rect(Rect2(a, b - a), Color(col, 0.25))
	draw_rect(Rect2(a, b - a), col, false, 2.0)
	if selected == BuildGrid2D.BELT:
		var c := (a + b) * 0.5
		var d := Vector2(BuildGrid2D.DIRS[rot])
		draw_line(c - d * 8, c + d * 8, col, 2.0)
		draw_line(c + d * 8, c + d * 2 + Vector2(-d.y, d.x) * 5, col, 2.0)
		draw_line(c + d * 8, c + d * 2 - Vector2(-d.y, d.x) * 5, col, 2.0)

## --- machine panel (E on a machine): status, contents, recipe auto toggles via number keys in the panel later ---

func _toggle_panel() -> void:
	if _panel.visible:
		_panel.visible = false
		_panel_target = null
		return
	var b := build.building_at(_cursor_tile())
	if b == null:
		return
	_panel_target = b
	_panel.visible = true
	UiSound.play("open")

func _fill_panel() -> void:
	if _panel_target == null or not is_instance_valid(_panel_target):
		_panel.visible = false
		return
	var b := _panel_target
	var lines: Array[String] = ["%s   %s" % [b.display_name, b.status_text()]]
	if not b.recipes.is_empty():
		var active_r := b.get_active_recipe_index()
		for i in b.recipes.size():
			var r: Recipe = b.recipes[i]
			lines.append("%s %s%s" % ["[on] " if b.get_auto(i) else "[  ] ", r.output_id, "  <" if i == active_r else ""])
	var stuff: Array[String] = []
	for i in b.inventory_slots:
		var s := b.get_inventory_slot(i)
		if String(s.item_id) != "":
			stuff.append("%s %d" % [s.item_id, s.count])
	lines.append("holds: " + (", ".join(stuff) if not stuff.is_empty() else "nothing"))
	_panel_label.text = "\n".join(lines)

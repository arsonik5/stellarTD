extends CanvasLayer
## In-game command console for testing (autoload "DevConsole"). Open with ` (backtick) or /, close with Esc or the
## same key. Commands work with or without a leading slash, Minecraft style:
##   give <item> [amount]     put items in your suit        give iron 50      give mining_tool
##   clear [item]             remove all of one item, or everything
##   items [filter]           list item ids (optionally only those containing the filter)
##   spawn <item> [amount]    same as give
##   tools                    mining tool, scanner and building tool
##   ores [amount]            every ore type
##   hand <left|right> <item> put an item straight into a hand
##   tp <x> <y> <z>           teleport to world coordinates
##   tp up <metres>           straight up (radial up on a planet)
##   o2 [seconds|fill]        set the suit oxygen
##   pos                      print your position
##   save | reload            save the game / reload the scene
##   help [command]
## A suggestion list is always shown under the input: everything you can type next (empty input = every command).
## Up/Down pick a suggestion, Tab or a click fills it in, PageUp/PageDown walk the history. Add a command: one entry in COMMANDS and one
## `_cmd_<name>(args: PackedStringArray)` function.

const COMMANDS := {
	"help": "help [command]  - list commands, or explain one",
	"give": "give <item> [amount]  - add items (Tab completes the item id)",
	"clear": "clear [item]  - remove one item, or everything",
	"items": "items [filter]  - list item ids",
	"spawn": "spawn <item> [amount]  - same as give",
	"tools": "tools  - get the mining tool, scanner and building tool",
	"ores": "ores [amount]  - get every ore type (default 50 each)",
	"hand": "hand <left|right> <item>  - put an item in a hand",
	"tp": "tp <x> <y> <z>  |  tp up <metres>",
	"o2": "o2 [seconds|fill]  - set suit oxygen",
	"pos": "pos  - print your world position",
	"save": "save  - save the game now",
	"reload": "reload  - reload the current scene",
}
## Short names that point at the real item ids, so "give iron" works.
const ALIASES := {
	"iron": "ore_a", "copper": "ore_b", "coal": "ore_coal", "silica": "ore_silica", "crystal": "ore_crystal",
	"mining": "mining_tool", "scanner": "scanner_tool", "building": "building_tool", "build": "building_tool",
}

var is_open := false
var _panel: PanelContainer
var _log: RichTextLabel
var _field: LineEdit
var _history: PackedStringArray = []
var _hist_i := 0
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _sugg_box: VBoxContainer
var _sugg_scroll: ScrollContainer
var _sugg: Array = []        # [{insert, label, desc}]
var _sugg_i := 0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_left = 24.0
	_panel.offset_right = -24.0
	_panel.offset_top = 24.0
	_panel.offset_bottom = 500.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.09, 0.82)       # darker than the menu glass: it sits on the live world
	sb.border_color = UiTokens.LINE
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	sb.corner_radius_top_left = UiTokens.CORNER_BIG
	sb.corner_radius_bottom_right = UiTokens.CORNER_BIG
	sb.corner_radius_top_right = UiTokens.CORNER_SMALL
	sb.corner_radius_bottom_left = UiTokens.CORNER_SMALL
	sb.anti_aliasing = true
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_color_override("default_color", UiTokens.TEXT)
	box.add_child(_log)
	_field = LineEdit.new()
	_field.placeholder_text = "command (pick from the list below)"
	_field.caret_blink = true
	_field.text_submitted.connect(_on_submit)
	_field.text_changed.connect(func(_t: String) -> void: _refresh_suggestions())
	box.add_child(_field)
	_sugg_scroll = ScrollContainer.new()
	_sugg_scroll.custom_minimum_size = Vector2(0, 150)
	_sugg_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_sugg_scroll)
	_sugg_box = VBoxContainer.new()
	_sugg_box.add_theme_constant_override("separation", 1)
	_sugg_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sugg_scroll.add_child(_sugg_box)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if not is_open:
		if k == KEY_QUOTELEFT or k == KEY_SLASH:
			_set_open(true, "/" if k == KEY_SLASH else "")
			get_viewport().set_input_as_handled()
		return
	if k == KEY_ESCAPE or k == KEY_QUOTELEFT:
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif k == KEY_TAB:
		_complete()
		get_viewport().set_input_as_handled()
	elif k == KEY_UP:
		_move_sugg(-1)
		get_viewport().set_input_as_handled()
	elif k == KEY_DOWN:
		_move_sugg(1)
		get_viewport().set_input_as_handled()
	elif k == KEY_PAGEUP:
		_walk_history(-1)
		get_viewport().set_input_as_handled()
	elif k == KEY_PAGEDOWN:
		_walk_history(1)
		get_viewport().set_input_as_handled()

func _set_open(v: bool, prefill: String = "") -> void:
	if v == is_open:
		return
	is_open = v
	_panel.visible = v
	UiState.set_open("console", v)
	if v:
		_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _log.get_parsed_text().is_empty():
			_print("[color=#%s]Console. Type help.[/color]" % UiTokens.TEXT_DIM.to_html(false))
		_field.text = prefill
		_field.caret_column = prefill.length()
		_field.grab_focus.call_deferred()
		_hist_i = _history.size()
		_refresh_suggestions()
	else:
		_field.release_focus()
		Input.mouse_mode = _prev_mouse

func _print(line: String) -> void:
	_log.append_text(line + "\n")

func _err(line: String) -> void:
	_print("[color=#%s]%s[/color]" % [UiTokens.DANGER.to_html(false), line])

func _ok(line: String) -> void:
	_print("[color=#%s]%s[/color]" % [UiTokens.GOOD.to_html(false), line])

func _walk_history(d: int) -> void:
	if _history.is_empty():
		return
	_hist_i = clampi(_hist_i + d, 0, _history.size())
	_field.text = "" if _hist_i >= _history.size() else _history[_hist_i]
	_field.caret_column = _field.text.length()

func _on_submit(text: String) -> void:
	var line := text.strip_edges()
	_field.text = ""
	_refresh_suggestions()
	if line.is_empty():
		return
	_history.append(line)
	_hist_i = _history.size()
	_print("[color=#%s]> %s[/color]" % [UiTokens.TEXT_DIM.to_html(false), line.replace("[", "[lb]")])
	run(line)
	_field.grab_focus.call_deferred()

## Runs one command line. Public so scripts and tests can call it: DevConsole.run("give iron 50").
func run(line: String) -> void:
	var parts := line.strip_edges().trim_prefix("/").split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	if not COMMANDS.has(cmd):
		_err("Unknown command '%s'. Type help." % cmd)
		return
	call("_cmd_" + cmd, args)

# --- suggestions ------------------------------------------------------------------------------------------
func _item_entries(prefix: String) -> Array:
	var out: Array = []
	for id: String in _item_ids():
		var def: Item = Inventory.get_item_def(id)
		var nm: String = def.display_name if def != null else ""
		if prefix == "" or id.contains(prefix) or nm.to_lower().contains(prefix):
			out.append({"insert": id, "label": id, "desc": nm})
	for a: String in ALIASES:
		if prefix == "" or a.contains(prefix):
			out.append({"insert": a, "label": a, "desc": "-> " + String(ALIASES[a])})
	return out

func _word_entries(words: Array, prefix: String, desc: String) -> Array:
	var out: Array = []
	for w: String in words:
		if w.begins_with(prefix):
			out.append({"insert": w, "label": w, "desc": desc})
	return out

## Everything that can be typed next, given the text so far.
func _build_suggestions() -> Array:
	var parts := _field.text.trim_prefix("/").split(" ")
	var prefix := parts[parts.size() - 1].to_lower()
	var cmd := parts[0].to_lower()
	var n := parts.size()
	var names: Array = COMMANDS.keys()
	names.sort()
	if n <= 1:
		var out: Array = []
		for c: String in names:
			if c.begins_with(prefix):
				out.append({"insert": c, "label": c, "desc": String(COMMANDS[c]).get_slice("  - ", 1)})
		return out
	if cmd in ["give", "spawn"]:
		if n == 2:
			return _item_entries(prefix)
		if n == 3:
			return _word_entries(["1", "10", "50", "100", "1000"], prefix, "amount")
	elif cmd in ["clear", "items"] and n == 2:
		return _item_entries(prefix)
	elif cmd == "hand":
		if n == 2:
			return _word_entries(["left", "right"], prefix, "hand")
		if n == 3:
			return _item_entries(prefix)
	elif cmd == "help" and n == 2:
		return _word_entries(names, prefix, "")
	elif cmd == "o2" and n == 2:
		return _word_entries(["fill", "60", "300"], prefix, "seconds, or fill")
	elif cmd == "tp" and n == 2:
		return _word_entries(["up"], prefix, "tp up <metres>")
	elif cmd == "ores" and n == 2:
		return _word_entries(["10", "50", "200"], prefix, "amount of each")
	return []

func _refresh_suggestions() -> void:
	if _sugg_box == null:
		return
	_sugg = _build_suggestions()
	_sugg_i = clampi(_sugg_i, 0, maxi(_sugg.size() - 1, 0))
	for ch in _sugg_box.get_children():
		ch.queue_free()
	if _sugg.is_empty():
		var l := Label.new()
		l.text = "nothing to suggest here. Enter runs what you typed."
		l.add_theme_color_override("font_color", UiTokens.TEXT_FAINT)
		_sugg_box.add_child(l)
		return
	for i in _sugg.size():
		var e: Dictionary = _sugg[i]
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.text = ("%s     %s" % [e["label"], e["desc"]]) if String(e["desc"]) != "" else String(e["label"])
		b.add_theme_color_override("font_color", UiTokens.ACCENT if i == _sugg_i else UiTokens.TEXT_DIM)
		# every row gets the same box (margins and height), so the list does not jiggle as the selection moves
		var row_box := StyleBoxFlat.new()
		row_box.bg_color = UiTokens.ACCENT_DEEP if i == _sugg_i else Color(0, 0, 0, 0)
		row_box.content_margin_left = 8
		row_box.content_margin_right = 8
		row_box.content_margin_top = 3
		row_box.content_margin_bottom = 3
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, row_box)
		b.pressed.connect(_apply_sugg.bind(i))
		_sugg_box.add_child(b)
	_scroll_to_selected.call_deferred()

func _scroll_to_selected() -> void:
	if _sugg_i < _sugg_box.get_child_count():
		_sugg_scroll.ensure_control_visible(_sugg_box.get_child(_sugg_i))

func _move_sugg(d: int) -> void:
	if _sugg.is_empty():
		return
	_sugg_i = posmod(_sugg_i + d, _sugg.size())
	_refresh_suggestions()

func _apply_sugg(i: int) -> void:
	if i < 0 or i >= _sugg.size():
		return
	var text := _field.text
	var slash := "/" if text.begins_with("/") else ""
	var parts := text.trim_prefix("/").split(" ")
	parts[parts.size() - 1] = String(_sugg[i]["insert"])
	_field.text = slash + " ".join(parts) + " "
	_field.caret_column = _field.text.length()
	_sugg_i = 0
	_refresh_suggestions()
	_field.grab_focus.call_deferred()

func _complete() -> void:
	_apply_sugg(_sugg_i)

# --- items ------------------------------------------------------------------------------------------------
func _item_ids() -> Array:
	var ids: Array = Inventory._item_defs.keys()
	ids.sort()
	return ids

func _resolve_item(name: String) -> String:
	var n := name.to_lower()
	if ALIASES.has(n):
		n = ALIASES[n]
	return n if Inventory.get_item_def(n) != null else ""

# --- commands ---------------------------------------------------------------------------------------------
func _cmd_help(args: PackedStringArray) -> void:
	if not args.is_empty() and COMMANDS.has(args[0].to_lower()):
		_print(COMMANDS[args[0].to_lower()])
		return
	for c: String in COMMANDS:
		_print(COMMANDS[c])

func _cmd_give(args: PackedStringArray) -> void:
	if args.is_empty():
		_err("Usage: " + COMMANDS["give"])
		return
	var id := _resolve_item(args[0])
	if id == "":
		_err("No item '%s'. Try: items %s" % [args[0], args[0].substr(0, 3)])
		return
	var n := 1
	if args.size() > 1:
		if not args[1].is_valid_int():
			_err("Amount must be a number.")
			return
		n = clampi(int(args[1]), 1, 100000)
	var added := Inventory.add(id, n)
	if added == 0:
		_err("Inventory is full.")
	elif added < n:
		_ok("Gave %d x %s (inventory full, %d did not fit)." % [added, id, n - added])
	else:
		_ok("Gave %d x %s." % [added, id])

func _cmd_spawn(args: PackedStringArray) -> void:
	_cmd_give(args)

func _cmd_tools(_args: PackedStringArray) -> void:
	for id in ["mining_tool", "scanner_tool", "building_tool"]:
		if Inventory.get_count(id) == 0 and Inventory.hand_holding(id) == "":
			Inventory.add(id, 1)
	_ok("Mining tool, scanner and building tool are in your suit or hands.")

func _cmd_ores(args: PackedStringArray) -> void:
	var n := 50
	if not args.is_empty() and args[0].is_valid_int():
		n = clampi(int(args[0]), 1, 100000)
	for id in ["ore_a", "ore_b", "ore_coal", "ore_silica", "ore_crystal"]:
		Inventory.add(id, n)
	_ok("Gave %d of every ore." % n)

func _cmd_hand(args: PackedStringArray) -> void:
	if args.size() < 2 or not args[0].to_lower() in ["left", "right"]:
		_err("Usage: " + COMMANDS["hand"])
		return
	var id := _resolve_item(args[1])
	if id == "":
		_err("No item '%s'." % args[1])
		return
	Inventory.set_slot({"kind": "hand", "side": args[0].to_lower()}, id, 1)
	_ok("%s hand: %s." % [args[0].to_lower().capitalize(), id])

func _cmd_clear(args: PackedStringArray) -> void:
	if args.is_empty():
		for id: String in _item_ids():
			var c := Inventory.get_count(id)
			if c > 0:
				Inventory.try_remove(id, c)
		_ok("Cleared the grid (items in your hands stay).")
		return
	var id := _resolve_item(args[0])
	if id == "":
		_err("No item '%s'." % args[0])
		return
	var c := Inventory.get_count(id)
	Inventory.try_remove(id, c)
	_ok("Removed %d x %s." % [c, id])

func _cmd_items(args: PackedStringArray) -> void:
	var f := args[0].to_lower() if not args.is_empty() else ""
	var ids: Array = _item_ids().filter(func(i: String) -> bool: return f == "" or i.contains(f))
	_print(", ".join(PackedStringArray(ids)) if not ids.is_empty() else "No matches.")

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

func _cmd_tp(args: PackedStringArray) -> void:
	var p := _player()
	if p == null:
		_err("No player.")
		return
	if args.size() == 2 and args[0].to_lower() == "up" and args[1].is_valid_float():
		p.global_position += PlanetPhysics.get_up(p.global_position) * float(args[1])
		p.velocity = Vector3.ZERO
		_ok("Moved up %s m." % args[1])
	elif args.size() == 3 and args[0].is_valid_float() and args[1].is_valid_float() and args[2].is_valid_float():
		p.global_position = Vector3(float(args[0]), float(args[1]), float(args[2]))
		p.velocity = Vector3.ZERO
		_ok("Teleported.")
	else:
		_err("Usage: " + COMMANDS["tp"])

func _cmd_o2(args: PackedStringArray) -> void:
	var p := _player()
	if p == null:
		_err("No player.")
		return
	var v: float = p.SUIT_O2_MAX
	if not args.is_empty() and args[0].to_lower() != "fill":
		if not args[0].is_valid_float():
			_err("Usage: " + COMMANDS["o2"])
			return
		v = clampf(float(args[0]), 0.0, p.SUIT_O2_MAX)
	p.suit_o2 = v
	_ok("Suit oxygen set to %d s." % int(v))

func _cmd_pos(_args: PackedStringArray) -> void:
	var p := _player()
	if p != null:
		_print("%.1f %.1f %.1f" % [p.global_position.x, p.global_position.y, p.global_position.z])

func _cmd_save(_args: PackedStringArray) -> void:
	if SaveManager.save_now():
		_ok("Saved.")
	else:
		_err("Nothing saved (no active save slot).")

func _cmd_reload(_args: PackedStringArray) -> void:
	_set_open(false)
	get_tree().reload_current_scene()

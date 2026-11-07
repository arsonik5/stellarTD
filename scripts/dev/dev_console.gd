extends CanvasLayer
## In-game command console for testing (autoload "DevConsole"). Open with ` (backtick) or /, close with Esc or the
## same key. Commands work with or without a leading slash, Minecraft style:
##   give <item> [amount]     put items in your suit        give iron 50      give mining_tool
##   clear [item]             remove all of one item, or everything
##   items [filter]           list item ids (optionally only those containing the filter)
##   tp <x> <y> <z>           teleport to world coordinates
##   tp up <metres>           straight up (radial up on a planet)
##   o2 [seconds|fill]        set the suit oxygen
##   pos                      print your position
##   save | reload            save the game / reload the scene
##   help [command]
## Tab completes commands and item ids, Up/Down walk the history. Add a command: one entry in COMMANDS and one
## `_cmd_<name>(args: PackedStringArray)` function.

const COMMANDS := {
	"help": "help [command]  - list commands, or explain one",
	"give": "give <item> [amount]  - add items (Tab completes the item id)",
	"clear": "clear [item]  - remove one item, or everything",
	"items": "items [filter]  - list item ids",
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
	_panel.offset_bottom = 340.0
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
	_field.placeholder_text = "command (type help)"
	_field.caret_blink = true
	_field.text_submitted.connect(_on_submit)
	box.add_child(_field)

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
		_walk_history(-1)
		get_viewport().set_input_as_handled()
	elif k == KEY_DOWN:
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

# --- completion -------------------------------------------------------------------------------------------
func _complete() -> void:
	var text := _field.text
	var trimmed := text.trim_prefix("/")
	var slash := "/" if text.begins_with("/") else ""
	var parts := trimmed.split(" ")
	var options: Array = []
	var prefix := parts[parts.size() - 1].to_lower()
	if parts.size() <= 1:
		options = COMMANDS.keys()
	elif parts[0].to_lower() in ["give", "clear", "items"] and parts.size() == 2:
		options = _item_ids()
		options.append_array(ALIASES.keys())
	elif parts[0].to_lower() == "help" and parts.size() == 2:
		options = COMMANDS.keys()
	var matches: Array = options.filter(func(o: String) -> bool: return o.begins_with(prefix))
	matches.sort()
	if matches.is_empty():
		return
	if matches.size() == 1:
		parts[parts.size() - 1] = matches[0]
		_field.text = slash + " ".join(parts) + " "
		_field.caret_column = _field.text.length()
	else:
		_print(", ".join(PackedStringArray(matches)))

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

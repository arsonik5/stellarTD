extends CanvasLayer

## The suit HUD (docs/game/ux-bible.md, "HUD"). One CanvasLayer, built in code from UiKit pieces, hidden as a whole
## while any full-screen UI is open (UiState). Fixed places, so the eye learns where to look:
##   centre        crosshair (+ the interact prompt just under it, interact_prompt.gd)
##   top right     current objective, progress bar, [J] Journal
##   bottom left   suit O2 (bar + time); ship O2 under it while seated
##   bottom right  pickup feed ("+3 Iron Ore"), then the held tools (L / R)
##   bottom centre context hints: the starter keys until each has been used once, the ship keys while flying,
##                 the build keys while building (set by player.gd through set_context_hints)
##   top left      ship instruments, only while piloting
## No text is ever permanently on screen that the player has already learned.

const FEED_TIME := 3.5
const STARTER_HINTS := [["WASD", "Move"], ["Shift", "Sprint"], ["E", "Use"], ["Tab", "Inventory"], ["C", "Build"], ["J", "Journal"], ["F", "Lamp"]]

var _player: Node = null
var _ship: Ship = null
var _crosshair: Control
var _quest_box: VBoxContainer
var _quest_title: Label
var _quest_bar: ProgressBar
var _quest_count: Label
var _o2_bar: ProgressBar
var _o2_text: Label
var _o2_state: Label
var _ship_o2: Label
var _hands: Dictionary = {}
var _feed: VBoxContainer
var _feed_items: Dictionary = {}       # item_id -> {label, amount, time}
var _hint_holder: CenterContainer
var _ship_box: PanelContainer
var _ship_rows: Dictionary = {}
var _context_hints: Array = []
var _used_keys: Dictionary = {}
var _last_counts: Dictionary = {}
var _cross_open := 0.0
var _o2_alarm := 0.0
var _last_quest_title := ""

func _ready() -> void:
	add_to_group("compact_hud")
	layer = 10
	_build()
	UiState.changed.connect(_refresh_visibility)
	QuestManager.changed.connect(_refresh_quest)
	Inventory.changed.connect(_on_inventory_changed)
	GameSettings.changed.connect(func(_k: String) -> void: _refresh_hints())
	_last_counts = _counts()
	_refresh_visibility()
	_refresh_quest()
	_refresh_hands()
	_refresh_hints()

# --- building -------------------------------------------------------------------------------------------
func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# crosshair: a small dot with a dark rim so it reads on snow and on night sky
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# On something usable, four mint ticks open out around the dot (_cross_open 0..1, eased in _process).
	_crosshair.draw.connect(func() -> void:
		_crosshair.draw_circle(Vector2.ZERO, 3.5, Color(0, 0, 0, 0.6))
		_crosshair.draw_circle(Vector2.ZERO, 2.0, UiTokens.TEXT.lerp(UiTokens.ACCENT, _cross_open))
		if _cross_open > 0.02:
			var r := 6.0 + 6.0 * _cross_open
			var col := Color(UiTokens.ACCENT, _cross_open)
			for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var p := d.normalized() * r
				_crosshair.draw_line(p, p + d.normalized() * 5.0, Color(0, 0, 0, 0.5 * _cross_open), 4.0)
				_crosshair.draw_line(p, p + d.normalized() * 5.0, col, 2.0))
	root.add_child(_crosshair)

	# objective (top left, Warframe's pinned-mission spot): a gold diamond, the goal, a 2 px progress line
	var qpanel := UiKit.panel("HudPanel")
	qpanel.offset_left = 40
	qpanel.offset_top = 32
	qpanel.custom_minimum_size.x = 300
	qpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(qpanel)
	_quest_box = UiKit.vbox(5)
	qpanel.add_child(_quest_box)
	var qhead := UiKit.hbox(10)
	qhead.add_child(UiKit.label("◆  OBJECTIVE", "HudCaption"))
	qhead.add_child(UiKit.spacer())
	qhead.add_child(UiKit.hint("J", "Journal", true))
	_quest_box.add_child(qhead)
	_quest_title = UiKit.label("", "HudLabel")
	_quest_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_box.add_child(_quest_title)
	var qrow := UiKit.hbox(10)
	_quest_bar = UiKit.bar("", 2)
	_quest_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qrow.add_child(_quest_bar)
	_quest_count = UiKit.label("", "HudCaption")
	qrow.add_child(_quest_count)
	_quest_box.add_child(qrow)

	# suit O2 (bottom left): a caption, the time large, a 2 px line under it
	var o2 := UiKit.vbox(2)
	o2.anchor_top = 1.0
	o2.anchor_bottom = 1.0
	o2.grow_vertical = Control.GROW_DIRECTION_BEGIN
	o2.offset_left = 40
	o2.offset_right = 300
	o2.offset_bottom = -32
	o2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(o2)
	var o2head := UiKit.hbox(10)
	o2head.add_child(UiKit.label("SUIT O2", "HudCaption"))
	_o2_state = UiKit.label("", "HudCaption")
	o2head.add_child(_o2_state)
	o2.add_child(o2head)
	_o2_text = UiKit.label("5:00", "HudValue")
	o2.add_child(_o2_text)
	_o2_bar = UiKit.bar("LightBar", 2)
	_o2_bar.custom_minimum_size.x = 220
	_o2_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	o2.add_child(_o2_bar)
	_ship_o2 = UiKit.label("", "HudCaption")
	o2.add_child(_ship_o2)

	# held tools (bottom right)
	var hands := UiKit.hbox(UiTokens.GAP)
	hands.anchor_left = 1.0
	hands.anchor_right = 1.0
	hands.anchor_top = 1.0
	hands.anchor_bottom = 1.0
	hands.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hands.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hands.offset_right = -40
	hands.offset_bottom = -32
	hands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hands)
	# one compact panel: "L  Mining Tool" / "R  Build Tool", the hand letter in a key cap like every other label
	var card := UiKit.panel("HudPanel")
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UiKit.vbox(4)
	card.add_child(v)
	hands.add_child(card)
	for side in ["left", "right"]:
		var r := UiKit.hbox(UiTokens.GAP)
		r.add_child(UiKit.keycap("L" if side == "left" else "R"))
		var n := UiKit.label("", "HudLabel")
		n.add_theme_font_size_override("font_size", 14)
		r.add_child(n)
		v.add_child(r)
		_hands[side] = n

	# pickup feed (above the hands)
	_feed = UiKit.vbox(2)
	_feed.anchor_left = 1.0
	_feed.anchor_right = 1.0
	_feed.anchor_top = 1.0
	_feed.anchor_bottom = 1.0
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_feed.offset_right = -40
	_feed.offset_bottom = -88
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	# context hints (bottom centre)
	_hint_holder = CenterContainer.new()
	_hint_holder.anchor_right = 1.0
	_hint_holder.anchor_top = 1.0
	_hint_holder.anchor_bottom = 1.0
	_hint_holder.offset_top = -104
	_hint_holder.offset_bottom = -72
	_hint_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint_holder)

	# ship instruments (top right, piloting only)
	_ship_box = UiKit.panel("HudPanel")
	_ship_box.anchor_left = 1.0
	_ship_box.anchor_right = 1.0
	_ship_box.offset_left = -260
	_ship_box.offset_right = -40
	_ship_box.offset_top = 32
	_ship_box.custom_minimum_size.x = 220
	_ship_box.visible = false
	_ship_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_ship_box)
	var sv := UiKit.vbox(4)
	_ship_box.add_child(sv)
	sv.add_child(UiKit.label("SHIP", "HudCaption"))
	for k in ["Speed", "Altitude", "Dampeners", "Status"]:
		var r := UiKit.hbox()
		r.add_child(UiKit.label(k.to_upper(), "HudCaption"))
		r.add_child(UiKit.spacer())
		var val := UiKit.label("--", "HudLabel")
		r.add_child(val)
		sv.add_child(r)
		_ship_rows[k] = val

# --- public API (player.gd) -----------------------------------------------------------------------------
## Kept for player.gd: the mode name picks which hint set shows; the old legend text is no longer drawn.
func set_mode_text(mode_name: String, _legend: String) -> void:
	if mode_name == "SHIP":
		set_context_hints([["W/S", "Thrust"], ["A/D", "Steer"], ["Space/Ctrl", "Up/Down"], ["G", "Gear"], ["X", "Dampeners"], ["E", "Leave"]])
	else:
		set_context_hints([])

func set_piloted_ship(ship: Ship) -> void:
	_ship = ship
	_ship_box.visible = ship != null

## Hints for the current activity (building, flying). Empty = the starter hints, which vanish once learned.
func set_context_hints(pairs: Array) -> void:
	_context_hints = pairs
	_refresh_hints()

## The player used a key: its starter hint goes away for good this session.
func key_used(key: String) -> void:
	if not _used_keys.has(key):
		_used_keys[key] = true
		_refresh_hints()

func _refresh_hints() -> void:
	for c in _hint_holder.get_children():
		c.queue_free()
	if not GameSettings.get_value("key_hints"):
		return
	var pairs: Array = _context_hints.duplicate()
	if pairs.is_empty():
		for p in STARTER_HINTS:
			if not _used_keys.has(p[0]):
				pairs.append(p)
	if pairs.is_empty():
		return
	_hint_holder.add_child(UiKit.hint_row(pairs, true))

# --- live state ------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not visible:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		_update_o2()
	if _ship != null and is_instance_valid(_ship):
		_update_ship()
	_update_feed(delta)
	var prompt := get_tree().get_first_node_in_group("interact_prompt") as CanvasLayer
	var want := 1.0 if prompt != null and prompt.visible else 0.0
	if absf(want - _cross_open) > 0.001:
		_cross_open = move_toward(_cross_open, want, delta / 0.12)
		_crosshair.queue_redraw()

func _update_o2() -> void:
	var o2: float = _player.get("suit_o2")
	var mx: float = _player.get("SUIT_O2_MAX")
	var refilling: bool = _player.get("o2_refilling") == true
	_o2_bar.value = lerpf(_o2_bar.value, o2 / mx, 0.2)          # eased, so refills visibly flow in
	var s := int(ceil(o2))
	_o2_text.text = "%d:%02d" % [s / 60, s % 60]
	var low := o2 < 60.0
	_o2_bar.theme_type_variation = "DangerBar" if o2 <= 0.0 else ("WarnBar" if low else ("GoodBar" if refilling else "LightBar"))
	var flash := 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 250.0))
	_o2_text.modulate = Color(UiTokens.DANGER, flash) if o2 <= 0.0 else (UiTokens.WARN if low else UiTokens.TEXT)
	if o2 <= 0.0:
		_o2_state.text = "EMPTY  ·  FIND A GARAGE OR A SEALED COCKPIT"
		_o2_state.modulate = UiTokens.DANGER
	elif refilling:
		_o2_state.text = "REFILLING"
		_o2_state.modulate = UiTokens.GOOD
	elif low:
		_o2_state.text = "LOW"
		_o2_state.modulate = UiTokens.WARN
	else:
		_o2_state.text = ""
	# heard as well as seen: two beeps every 12 s while low, the error buzz every 4 s when empty
	_o2_alarm -= get_process_delta_time()
	if _o2_alarm <= 0.0 and o2 < 60.0 and not refilling:
		UiSound.play("error" if o2 <= 0.0 else "warn")
		_o2_alarm = 4.0 if o2 <= 0.0 else 12.0
	var ship: Ship = _player.get("_piloted_ship")
	_ship_o2.text = "SHIP O2  %d s" % int(ship.oxygen_left()) if ship != null else ""

func _update_ship() -> void:
	_ship_rows["Speed"].text = "%d m/s" % roundi(_ship.linear_velocity.length())
	var body := PlanetPhysics.get_nearest_body(_ship.global_position) as CelestialBodyNode
	_ship_rows["Altitude"].text = "%d m" % roundi(body.global_position.distance_to(_ship.global_position) - body.radius_world()) if body != null else "--"
	_ship_rows["Dampeners"].text = "ON" if _ship.dampeners_enabled else "OFF"
	_ship_rows["Status"].text = String(_ship.ship_state).to_upper()

func _refresh_quest() -> void:
	var ids: Array = QuestManager.get_active_ids()
	var panel := _quest_box.get_parent() as Control
	panel.visible = not ids.is_empty()
	if ids.is_empty():
		return
	var quest: Quest = QuestManager.get_def(ids[0])
	if quest.title != _last_quest_title:
		if _last_quest_title != "":
			UiKit.pulse(panel)                                   # a new goal: the panel flashes gold
			UiSound.play("objective")
			UiKit.pop_in(panel)
		_last_quest_title = quest.title
	_quest_title.text = quest.title
	var multi := quest.target_amount > 1
	_quest_bar.visible = multi
	_quest_count.visible = multi
	if multi:
		var cur := QuestManager.get_progress_current(ids[0])
		var target := float(cur) / float(quest.target_amount)
		if not is_equal_approx(target, _quest_bar.value):
			_quest_bar.create_tween().set_ease(Tween.EASE_OUT).tween_property(_quest_bar, "value", target, 0.35)
			UiKit.pulse(_quest_count)
		_quest_count.text = "%d / %d" % [cur, quest.target_amount]
	if ids.size() > 1:
		_quest_title.text += "   (+%d more)" % (ids.size() - 1)

func _refresh_hands() -> void:
	for side in _hands:
		var slot: Dictionary = Inventory.get_slot({"kind": "hand", "side": side})
		var item: Item = Inventory.get_item_def(slot.item_id) if slot.item_id != "" else null
		(_hands[side] as Label).text = item.display_name if item != null else "Empty"
		(_hands[side] as Label).modulate = UiTokens.TEXT if item != null else UiTokens.TEXT_FAINT

func _counts() -> Dictionary:
	var out := {}
	for i in Inventory.GRID_SIZE:
		var s: Dictionary = Inventory.get_slot({"kind": "grid", "index": i})
		if s.item_id != "":
			out[s.item_id] = int(out.get(s.item_id, 0)) + int(s.count)
	for side in ["left", "right"]:
		var s: Dictionary = Inventory.get_slot({"kind": "hand", "side": side})
		if s.item_id != "":
			out[s.item_id] = int(out.get(s.item_id, 0)) + int(s.count)
	return out

## Pickups and crafts: show what was GAINED, merged per item while it is still on screen.
func _on_inventory_changed() -> void:
	_refresh_hands()
	var now := _counts()
	if not UiState.is_any_open():                 # moving stacks around in a menu is not a pickup
		for id in now:
			var gain: int = int(now[id]) - int(_last_counts.get(id, 0))
			if gain > 0:
				_feed_add(id, gain)
	_last_counts = now

func _feed_add(id: String, amount: int) -> void:
	var item := Inventory.get_item_def(id)
	var item_name: String = item.display_name if item != null else id
	UiSound.play("pickup", 1.0 + minf(amount, 10) * 0.01, 0.12)
	if _feed_items.has(id):
		var e: Dictionary = _feed_items[id]
		e.amount += amount
		e.time = FEED_TIME
		var ex := e.label as Label
		ex.text = "+%d   %s" % [e.amount, item_name.to_upper()]
		ex.modulate.a = 1.0
		UiKit.pulse(ex)                                     # the same line counts up and flashes gold
		return
	var l := UiKit.label("+%d   %s" % [amount, item_name.to_upper()], "HudLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	# slides in from the right edge (anime.js translateX + outExpo)
	UiMotion.animate(l, {"opacity": [0.0, 1.0], "x": [36, 0]}, {"duration": 0.55, "easing": "outExpo"})
	_feed_items[id] = {"label": l, "amount": amount, "time": FEED_TIME}

func _update_feed(delta: float) -> void:
	for id in _feed_items.keys():
		var e: Dictionary = _feed_items[id]
		e.time -= delta
		(e.label as Label).modulate.a = clampf(e.time / 0.6, 0.0, 1.0)
		if e.time <= 0.0:
			(e.label as Label).queue_free()
			_feed_items.erase(id)

func _refresh_visibility() -> void:
	visible = not UiState.is_any_open()

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
var _hp_bar: ProgressBar
var _hp_text: Label
var _hurt: ColorRect
var _hurt_amount := 0.0
var _death_label: Label
var _action_box: VBoxContainer
var _action_label: Label
var _action_bar: ProgressBar
var _toast: Label
var _sig_box: VBoxContainer
var _sig_label: Label
var _sig_bar: ProgressBar
var _raid_label: Label
var _raid_eta := -1.0
var _raid_from := Vector3.ZERO
var _raid_comp: Dictionary = {}
var _toast_time := 0.0
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
	GameEvents.damaged.connect(_on_damaged)
	Progression.changed.connect(_refresh_quest)
	RadiationSignature.changed.connect(_refresh_signature)
	RadiationSignature.tier_changed.connect(func(old_t: int, new_t: int) -> void:
		if new_t > old_t:
			toast("SIGNATURE  ·  " + RadiationSignature.tier_name(), UiTokens.DANGER)
			UiSound.play("warn"))
	GameEvents.wave_warning.connect(func(from: Vector3, eta: float, comp: Dictionary) -> void:
		_raid_eta = eta
		_raid_from = from
		_raid_comp = comp
		UiSound.play("error"))
	GameEvents.wave_started.connect(func(_n: int, _e: int) -> void:
		_raid_eta = 0.0
		_raid_hold = 6.0)
	Progression.points_awarded.connect(_on_points)
	Progression.directive_completed.connect(_on_directive_done)
	GameEvents.player_died.connect(func(_c: String) -> void: _death_label.visible = true)
	GameEvents.player_respawned.connect(func() -> void: _death_label.visible = false)
	_last_counts = _counts()
	_refresh_visibility()
	_refresh_quest()
	_refresh_hands()
	_refresh_hints()
	_refresh_signature()

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

	# damage vignette + death card: full-screen, input-transparent, drawn under every panel
	_hurt = ColorRect.new()
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt.color = Color(UiTokens.DANGER, 0.0)
	root.add_child(_hurt)
	_death_label = UiKit.label("SUIT FAILURE  ·  RECOVERING AT LANDING SITE", "HudValue")
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_label.visible = false
	root.add_child(_death_label)

	# hold-action progress (dismantle, later repair/salvage): under the crosshair, label + 2 px line
	_action_box = UiKit.vbox(4)
	_action_box.set_anchors_preset(Control.PRESET_CENTER)
	_action_box.offset_top = 28
	_action_box.offset_left = -110
	_action_box.offset_right = 110
	_action_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_box.visible = false
	root.add_child(_action_box)
	_action_label = UiKit.label("", "HudCaption")
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_box.add_child(_action_label)
	_action_bar = UiKit.bar("WarnBar", 2)
	_action_box.add_child(_action_bar)

	# toast: one line of feedback for refused actions ("Inventory full ..."), centre, fades after 2.5 s
	_toast = UiKit.label("", "HudLabel")
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.offset_top = 64
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.modulate = Color(UiTokens.WARN, 0.0)
	root.add_child(_toast)

	# signature gauge (top right): how loud the base is, and the tier it puts you in
	_sig_box = UiKit.vbox(3)
	_sig_box.anchor_left = 1.0
	_sig_box.anchor_right = 1.0
	_sig_box.offset_left = -300
	_sig_box.offset_right = -40
	_sig_box.offset_top = 32
	_sig_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_sig_box)
	_sig_label = UiKit.label("", "HudCaption")
	_sig_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sig_box.add_child(_sig_label)
	_sig_bar = UiKit.bar("LightBar", 2)
	_sig_box.add_child(_sig_bar)
	# raid warning (top centre): bearing relative to where you look, ETA, what is coming
	_raid_label = UiKit.label("", "HudValue")
	_raid_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_raid_label.offset_top = 36
	_raid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_raid_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_raid_label.modulate = UiTokens.DANGER
	_raid_label.visible = false
	root.add_child(_raid_label)

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
	# suit integrity (health) sits above the air: same caption / value / 2 px line grammar
	var hphead := UiKit.hbox(10)
	hphead.add_child(UiKit.label("SUIT INTEGRITY", "HudCaption"))
	_hp_text = UiKit.label("100", "HudCaption")
	hphead.add_child(_hp_text)
	o2.add_child(hphead)
	_hp_bar = UiKit.bar("GoodBar", 2)
	_hp_bar.custom_minimum_size.x = 220
	_hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_hp_bar.value = 1.0
	o2.add_child(_hp_bar)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o2.add_child(gap)
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
		_update_health(delta)
	if _ship != null and is_instance_valid(_ship):
		_update_ship()
	_update_feed(delta)
	_update_raid(delta)
	_toast_time = maxf(_toast_time - delta, 0.0)
	_toast.modulate = Color(_toast_color, clampf(_toast_time / 0.4, 0.0, 1.0))
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

func _refresh_signature() -> void:
	var v := RadiationSignature.signature()
	var t := RadiationSignature.tier()
	_sig_box.visible = v > 0.05 or t > 0
	_sig_label.text = "SIGNATURE  %.1f  ·  %s" % [v, RadiationSignature.tier_name()]
	_sig_bar.value = clampf(v / RadiationSignature.next_threshold(), 0.0, 1.0)
	_sig_bar.theme_type_variation = ["LightBar", "WarnBar", "WarnBar", "DangerBar", "DangerBar"][t]
	_sig_label.modulate = [UiTokens.TEXT_DIM, UiTokens.WARN, UiTokens.WARN, UiTokens.DANGER, UiTokens.DANGER][t]

var _raid_hold := 0.0
var _raid_beep := 0.0

## Raid banner: "RAID INBOUND · 2 GUNSHIPS · 38 s · ◀ 40°" - the bearing is relative to where the player looks,
## measured in the local tangent plane (radial up), so "turn left 40 degrees" is literally true on any body.
func _update_raid(delta: float) -> void:
	if _raid_hold > 0.0:
		_raid_hold -= delta
		_raid_label.visible = true
		_raid_label.text = "RAID ARRIVING  ·  DEFEND THE BASE"
		if _raid_hold <= 0.0:
			_raid_eta = -1.0
		return
	if _raid_eta < 0.0 or _player == null:
		_raid_label.visible = false
		return
	_raid_eta = maxf(_raid_eta - delta, 0.0)
	var parts := []
	for k: String in ["gunship", "dropship", "spotter"]:
		var n := int(_raid_comp.get(k, 0))
		if n > 0:
			parts.append("%d %s%s" % [n, k.to_upper(), "S" if n > 1 else ""])
	var cam := get_viewport().get_camera_3d()
	var bearing := ""
	if cam != null:
		var up := PlanetPhysics.get_up(cam.global_position)
		var fwd := -cam.global_transform.basis.z
		fwd = (fwd - up * fwd.dot(up)).normalized()
		var to := _raid_from - cam.global_position
		to = (to - up * to.dot(up)).normalized()
		var ang := rad_to_deg(fwd.signed_angle_to(to, up))
		bearing = ("◀ %d°" % roundi(absf(ang))) if ang > 5.0 else (("%d° ▶" % roundi(absf(ang))) if ang < -5.0 else "▲ AHEAD")
	_raid_label.visible = true
	_raid_label.text = "RAID INBOUND  ·  %s  ·  %d s  ·  %s" % [", ".join(parts), ceili(_raid_eta), bearing]
	_raid_beep -= delta
	if _raid_beep <= 0.0 and _raid_eta < 10.0:
		_raid_beep = 1.0
		UiSound.play("warn")

func set_action_progress(fraction: float, text: String) -> void:
	_action_box.visible = fraction > 0.0
	_action_bar.value = clampf(fraction, 0.0, 1.0)
	_action_label.text = text.to_upper()

var _toast_color := UiTokens.WARN

## One line of centre-screen feedback. Amber = refused / warning (default), mint = success.
func toast(text: String, col: Color = UiTokens.WARN) -> void:
	_toast.text = text
	_toast_color = col
	_toast_time = 2.5

func _on_damaged(target: Node, amount: float, _type: String, _source: Node) -> void:
	if target == null or not target.is_in_group("player"):
		return
	_hurt_amount = minf(_hurt_amount + amount / 40.0 + 0.15, 0.6)
	UiSound.play("error")

func _update_health(delta: float) -> void:
	var v: PlayerVitals = _player.get("vitals")
	if v == null or v.health == null:
		return
	var f := v.health.fraction()
	_hp_bar.value = lerpf(_hp_bar.value, f, 0.25)
	_hp_text.text = "%d" % ceili(v.health.health)
	_hp_bar.theme_type_variation = "DangerBar" if f < 0.3 else ("WarnBar" if f < 0.6 else "GoodBar")
	_hurt_amount = move_toward(_hurt_amount, 0.0, delta * 0.8)
	var dead_dim := 0.85 if v.dead else 0.0
	_hurt.color = Color(0.0, 0.0, 0.0, dead_dim) if v.dead else Color(UiTokens.DANGER, _hurt_amount * 0.45)

func _update_ship() -> void:
	_ship_rows["Speed"].text = "%d m/s" % roundi(_ship.linear_velocity.length())
	var body := PlanetPhysics.get_nearest_body(_ship.global_position) as CelestialBodyNode
	_ship_rows["Altitude"].text = "%d m" % roundi(body.global_position.distance_to(_ship.global_position) - body.radius_world()) if body != null else "--"
	_ship_rows["Dampeners"].text = "ON" if _ship.dampeners_enabled else "OFF"
	_ship_rows["Status"].text = String(_ship.ship_state).to_upper()

func _refresh_quest() -> void:
	var ids: Array = QuestManager.get_active_ids()
	var panel := _quest_box.get_parent() as Control
	if ids.is_empty():
		_refresh_directive(panel)
		return
	panel.visible = true
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

## After the tutorial the objective panel carries the Continuance's current Directive (milestone first).
func _refresh_directive(panel: Control) -> void:
	var open := Progression.open_directives()
	panel.visible = not open.is_empty()
	if open.is_empty():
		return
	var d: Dictionary = open[0]
	if String(d.title) != _last_quest_title:
		if _last_quest_title != "":
			UiKit.pulse(panel)
			UiSound.play("objective")
			UiKit.pop_in(panel)
		_last_quest_title = String(d.title)
	var lines := []
	var got := Progression.progress_of(d)
	for i in d.item_ids.size():
		var def := Inventory.get_item_def(d.item_ids[i])
		lines.append("%s %d/%d" % [def.display_name if def else d.item_ids[i], mini(int(got.get(d.item_ids[i], 0)), int(d.amounts[i])), int(d.amounts[i])])
	_quest_title.text = String(d.title) + ("   (+%d more)" % (open.size() - 1) if open.size() > 1 else "")
	_quest_bar.visible = true
	_quest_count.visible = true
	var f := Progression.fraction_of(d)
	if not is_equal_approx(f, _quest_bar.value):
		_quest_bar.create_tween().set_ease(Tween.EASE_OUT).tween_property(_quest_bar, "value", f, 0.35)
	_quest_count.text = "  ·  ".join(lines)

func _on_points(category: String, amount: int, reason: String) -> void:
	_feed_text("+%d %s DATA  ·  %s" % [amount, category.to_upper(), reason], UiTokens.ACCENT)

func _on_directive_done(_id: String, title: String) -> void:
	toast("DIRECTIVE COMPLETE  ·  " + title.to_upper(), UiTokens.GOOD)
	UiSound.play("objective")

## One line in the pickup feed that is not an item (research data, credit).
func _feed_text(text: String, col: Color) -> void:
	var l := UiKit.label(text, "HudCaption")
	l.modulate = col
	_feed.add_child(l)
	_feed.move_child(l, 0)
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

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

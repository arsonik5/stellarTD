extends CanvasLayer

## The journal (J): the questline as a tree, on the standard screen frame. One node per Quest, column = depth
## (longest prerequisite chain), schematic connectors to every prerequisite. State reads the same way everywhere
## in the UI: the current goal is ACCENT-outlined, done is dim with a tick, locked is faint.
## Right: the selected quest - what to do, the hint, progress.
const QuestTreeLines := preload("res://scripts/ui/quest_tree_lines.gd")

const NODE_SIZE := Vector2(200.0, 56.0)
const COL_SPACING := 240.0
const ROW_SPACING := 80.0
const MARGIN := Vector2(16.0, 16.0)

var _tree_canvas: Control
var _detail: VBoxContainer
var _node_buttons: Dictionary = {}
var _selected_id: String = ""

func _ready() -> void:
	visible = false
	layer = 20
	add_to_group("journal_ui")
	var frame := UiKit.screen("Journal", [["J/Esc", "Close"]], Vector2(1100, 600), "Suit  /")
	add_child(frame.root)
	var row := UiKit.hbox(UiTokens.GAP_L)
	(frame.body as Control).add_child(row)
	# three pages share the left side: the tutorial tree, the Continuance's directives, the research tree
	var left := UiKit.vbox(UiTokens.GAP)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var tabs := UiKit.hbox(6)
	left.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 460
	left.add_child(scroll)
	_directives_page = _page(left)
	_research_page = _page(left)
	_pages = {"Tutorial": scroll, "Directives": _directives_page.get_parent(), "Research": _research_page.get_parent()}
	for page_name: String in _pages:
		var b := UiKit.button(page_name)
		b.toggle_mode = true
		b.pressed.connect(func() -> void: show_page(page_name))
		tabs.add_child(b)
		_tab_buttons[page_name] = b
	_points_label = UiKit.label("", "DimLabel")
	tabs.add_child(UiKit.spacer())
	tabs.add_child(_points_label)
	_tree_canvas = Control.new()
	scroll.add_child(_tree_canvas)
	var dpanel := UiKit.panel("Well")
	dpanel.custom_minimum_size.x = 320
	row.add_child(dpanel)
	_detail = UiKit.vbox(UiTokens.GAP)
	dpanel.add_child(_detail)
	_build_tree()
	QuestManager.changed.connect(_refresh_states)
	Progression.changed.connect(_refresh_progression)
	show_page("Tutorial")

var _pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _directives_page: VBoxContainer
var _research_page: VBoxContainer
var _points_label: Label
var _page_name := "Tutorial"

func _page(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 460
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := UiKit.vbox(UiTokens.GAP)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return v

func show_page(page_name: String) -> void:
	_page_name = page_name
	for k: String in _pages:
		(_pages[k] as Control).visible = k == page_name
		(_tab_buttons[k] as Button).button_pressed = k == page_name
	_refresh_progression()

## Directives (open + done) and the research tree with Buy buttons.
func _refresh_progression() -> void:
	if _points_label == null:
		return
	_points_label.text = "GEOLOGY %d  ·  ENGINEERING %d  ·  XENO %d  ·  CREDIT %d" % [
		int(Progression.points.geology), int(Progression.points.engineering), int(Progression.points.xeno), Progression.credit]
	if not visible:
		return
	for c in _directives_page.get_children():
		c.queue_free()
	var open := Progression.open_directives()
	if open.is_empty():
		_directives_page.add_child(UiKit.label("The Continuance is waiting for you to finish setting up (Tutorial page).", "DimLabel"))
	for d: Dictionary in open:
		var card := UiKit.panel("Card")
		var v := UiKit.vbox(4)
		card.add_child(v)
		v.add_child(UiKit.label(("STANDING ORDER  ·  " if d.standing else "DIRECTIVE  ·  ") + String(d.title).to_upper(), "HudLabel"))
		var msg := UiKit.label(String(d.message), "DimLabel")
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(msg)
		var got := Progression.progress_of(d)
		for i in d.item_ids.size():
			var def := Inventory.get_item_def(d.item_ids[i])
			var have := mini(int(got.get(d.item_ids[i], 0)), int(d.amounts[i]))
			var verb := "Place" if int(d.kind) == Directive.Kind.PLACE else "Deliver"
			v.add_child(UiKit.label("%s %s  %d / %d" % [verb, def.display_name if def else d.item_ids[i], have, int(d.amounts[i])],
				"AccentLabel" if have >= int(d.amounts[i]) else "HudCaption"))
		v.add_child(UiKit.label("Reward: %d credit" % int(d.reward_credit), "DimLabel"))
		_directives_page.add_child(card)
	var done := 0
	for m in Progression.milestones():
		if Progression.completed.has(m.id):
			done += 1
	_directives_page.add_child(UiKit.label("Milestones done: %d / %d" % [done, Progression.milestones().size()], "DimLabel"))
	for c in _research_page.get_children():
		c.queue_free()
	for r: ResearchNode in Progression.research_nodes():
		var card := UiKit.panel("Card")
		var h := UiKit.hbox(UiTokens.GAP)
		card.add_child(h)
		var v := UiKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var owned := Progression.bought.has(r.id)
		v.add_child(UiKit.label(r.title.to_upper() + ("  ·  RESEARCHED" if owned else ""), "AccentLabel" if owned else "HudLabel"))
		var desc := UiKit.label(r.description, "DimLabel")
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(desc)
		var unl := []
		for id in r.unlocks:
			var def := Inventory.get_item_def(id)
			unl.append(def.display_name if def else id)
		var cost_parts := []
		for c2: String in r.cost:
			cost_parts.append("%d %s" % [int(r.cost[c2]), c2])
		v.add_child(UiKit.label("Unlocks: %s   ·   Cost: %s" % [", ".join(unl), ", ".join(cost_parts)], "HudCaption"))
		if not owned:
			var b := UiKit.button("Research", func() -> void:
				if Progression.buy(r.id):
					UiSound.play("confirm")
				else:
					UiSound.play("deny"), "PrimaryButton")
			b.disabled = not Progression.can_buy(r.id)
			h.add_child(b)
		_research_page.add_child(card)

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	UiState.set_open("journal", true)
	_refresh_states()
	# after the tutorial the journal opens on what Earth wants now
	show_page("Directives" if Progression.tutorial_done() and _page_name == "Tutorial" else _page_name)
	# open on the current goal, not on the first quest ever
	var active: Array = QuestManager.get_active_ids()
	if not active.is_empty():
		_select(active[0])
	elif _selected_id == "" and not _node_buttons.is_empty():
		_select(_node_buttons.keys()[0])
	UiKit.pop_in(get_child(0))

func close() -> void:
	visible = false
	UiState.set_open("journal", false)
	UiSound.play("close")

func _build_tree() -> void:
	var ids: Array = QuestManager.get_all_ids()
	var columns: Dictionary = {}
	for id: String in ids:
		var depth := QuestManager.get_depth(id)
		if not columns.has(depth):
			columns[depth] = []
		columns[depth].append(id)
	var positions: Dictionary = {}
	var max_col := 0
	var max_row := 0
	for depth: int in columns:
		max_col = maxi(max_col, depth)
		var rows: Array = columns[depth]
		for row_index in rows.size():
			max_row = maxi(max_row, row_index)
			positions[rows[row_index]] = MARGIN + Vector2(depth * COL_SPACING, row_index * ROW_SPACING)
	_tree_canvas.custom_minimum_size = MARGIN * 2.0 + Vector2(max_col * COL_SPACING + NODE_SIZE.x, max_row * ROW_SPACING + NODE_SIZE.y)
	var lines := QuestTreeLines.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tree_canvas.add_child(lines)
	var segments: Array = []
	for id: String in ids:
		var quest: Quest = QuestManager.get_def(id)
		var node := UiKit.button(quest.title, _select.bind(id))
		node.custom_minimum_size = NODE_SIZE
		node.size = NODE_SIZE
		node.position = positions[id]
		node.clip_text = true
		node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		node.mouse_entered.connect(_select.bind(id))
		_tree_canvas.add_child(node)
		_node_buttons[id] = node
		for prereq_id: String in quest.prerequisite_ids:
			if positions.has(prereq_id):
				segments.append({
					"from_id": prereq_id,
					"from_pos": positions[prereq_id] + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5),
					"to_pos": positions[id] + Vector2(0.0, NODE_SIZE.y * 0.5),
				})
	lines.setup(segments)
	_refresh_states()

func _select(id: String) -> void:
	_selected_id = id
	var quest: Quest = QuestManager.get_def(id)
	if quest == null:
		return
	for c in _detail.get_children():
		c.queue_free()
	var state := QuestManager.get_state(id)
	var st := UiKit.label(String({"locked": "LOCKED", "complete": "DONE", "active": "CURRENT GOAL"}.get(state, "")), "SectionLabel")
	st.add_theme_color_override("font_color", UiTokens.ACCENT if state == "active" else UiTokens.TEXT_DIM)
	_detail.add_child(st)
	var t := UiKit.title(quest.title)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(t)
	var d := UiKit.label(quest.description)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 280
	_detail.add_child(d)
	if quest.hint != "":
		var h := UiKit.label(quest.hint, "AccentLabel" if state == "active" else "DimLabel")
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.custom_minimum_size.x = 280
		_detail.add_child(h)
	if state == "locked":
		_detail.add_child(UiKit.label("Finish the goals before it first.", "DimLabel"))
	elif quest.target_amount > 1:
		var cur := QuestManager.get_progress_current(id)
		var bar := UiKit.bar("", 8)
		bar.value = 1.0 if state == "complete" else float(cur) / float(quest.target_amount)
		_detail.add_child(bar)
		_detail.add_child(UiKit.label("%d / %d" % [quest.target_amount if state == "complete" else cur, quest.target_amount], "DimLabel"))

func _refresh_states() -> void:
	for id: String in _node_buttons:
		var b: Button = _node_buttons[id]
		var quest: Quest = QuestManager.get_def(id)
		match QuestManager.get_state(id):
			"locked":
				b.modulate = Color(1, 1, 1, 0.4)
				b.text = quest.title
				b.remove_theme_stylebox_override("normal")
				b.add_theme_color_override("font_color", UiTokens.TEXT_DIM)
			"active":
				b.modulate = Color.WHITE
				b.text = quest.title
				var sb := StyleBoxFlat.new()
				sb.bg_color = UiTokens.ACCENT_DEEP
				sb.border_color = UiTokens.ACCENT
				sb.set_border_width_all(1)
				sb.content_margin_left = 16
				sb.content_margin_right = 16
				b.add_theme_stylebox_override("normal", sb)
				b.add_theme_color_override("font_color", UiTokens.ACCENT)
			"complete":
				b.modulate = Color(1, 1, 1, 0.85)
				b.text = "✓  " + quest.title
				b.remove_theme_stylebox_override("normal")
				b.add_theme_color_override("font_color", UiTokens.TEXT_DIM)
	if _selected_id != "" and visible:
		_select(_selected_id)

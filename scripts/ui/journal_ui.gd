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
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 500
	row.add_child(scroll)
	_tree_canvas = Control.new()
	scroll.add_child(_tree_canvas)
	var dpanel := UiKit.panel("Well")
	dpanel.custom_minimum_size.x = 320
	row.add_child(dpanel)
	_detail = UiKit.vbox(UiTokens.GAP)
	dpanel.add_child(_detail)
	_build_tree()
	QuestManager.changed.connect(_refresh_states)

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

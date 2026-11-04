extends CanvasLayer

## Esc menu. The same pattern as the start menu: nav on the left, the page it opens on the right with a thin
## title and a gold rule - here over the paused world, blurred and darkened. Every way out of the world saves
## first: Exit to menu, Quit to desktop and Load game all go through _start_save(), and the save is not instant -
## VoxelStreamSQLite writes edited blocks on worker threads, so the menu waits on
## SaveManager.terrain_save_complete() before it changes scenes or quits.

## Loaded by path, NOT preloaded. main_menu.gd preloads world.tscn, world.tscn instances this scene - a preload
## here closes a cycle (pause -> menu -> world -> pause) and the scene comes back unusable.
const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const WORLD_PATH := "res://scenes/world.tscn"
const PAGE_W := 640.0

enum Pending {NONE, MENU, QUIT, LOAD}

var _root: Control
var _backdrop: ColorRect
var _nav_col: VBoxContainer
var _colony: Label
var _played: Label
var _page_root: Control
var _page_title: Label
var _page_rule: Control
var _pages := {}
var _nav_pages := {}
var _saves: SavesPanel
var _status: Label
var _nav_buttons: Array[Button] = []
var _pending: int = Pending.NONE
var _pending_slot := ""
var _saving := false
var _page := "home"

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	_build_ui()
	_root.visible = false

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_backdrop = UiKit.shade(Color(0.012, 0.02, 0.03, 0.78))
	_root.add_child(_backdrop)

	var head := UiKit.vbox(6)
	head.position = Vector2(UiTokens.EDGE, 40)
	_root.add_child(head)
	head.add_child(UiKit.label("PAUSED  /", "CrumbLabel"))
	_colony = UiKit.title("")
	head.add_child(_colony)
	head.add_child(UiKit.rule())
	_played = UiKit.label("", "CrumbLabel")
	head.add_child(_played)

	_nav_col = UiKit.vbox(2)
	_nav_col.anchor_top = 0.5
	_nav_col.anchor_bottom = 0.5
	_nav_col.offset_left = UiTokens.EDGE
	_nav_col.offset_right = UiTokens.EDGE + 300
	_nav_col.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_nav_col)
	_nav("Resume", close)
	_nav("Save", func() -> void: _start_save(Pending.NONE))
	_nav_pages["load"] = _nav("Load game", show_page.bind("load"))
	_nav_pages["settings"] = _nav("Settings", show_page.bind("settings"))
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	_nav_col.add_child(gap)
	_nav("Exit to menu", func() -> void: _start_save(Pending.MENU))
	_nav("Quit to desktop", func() -> void: _start_save(Pending.QUIT))
	_status = UiKit.label("", "AccentLabel")
	var sm := MarginContainer.new()
	sm.add_theme_constant_override("margin_left", 20)
	sm.add_theme_constant_override("margin_top", 12)
	sm.add_child(_status)
	_nav_col.add_child(sm)

	var note := UiKit.label("LEAVING ALWAYS SAVES FIRST", "CrumbLabel")
	note.anchor_top = 1.0
	note.anchor_bottom = 1.0
	note.offset_left = UiTokens.EDGE
	note.offset_top = -56
	_root.add_child(note)
	var foot := UiKit.hint_row([["Esc", "Back"]])
	foot.anchor_left = 1.0
	foot.anchor_right = 1.0
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_right = -UiTokens.EDGE
	foot.offset_bottom = -36
	_root.add_child(foot)

	_page_root = Control.new()
	_page_root.anchor_left = 1.0
	_page_root.anchor_right = 1.0
	_page_root.anchor_bottom = 1.0
	_page_root.offset_right = -UiTokens.EDGE
	_page_root.offset_top = 56
	_page_root.offset_bottom = -84
	_root.add_child(_page_root)
	get_viewport().size_changed.connect(_fit_page)
	_fit_page.call_deferred()
	var col := UiKit.vbox(6)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_root.add_child(col)
	col.add_child(UiKit.label("MENU  /", "CrumbLabel"))
	_page_title = UiKit.title("")
	col.add_child(_page_title)
	_page_rule = UiKit.rule()
	col.add_child(_page_rule)
	var g2 := Control.new()
	g2.custom_minimum_size.y = 18
	col.add_child(g2)
	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_saves = SavesPanel.new()
	_saves.load_requested.connect(func(id: String) -> void:
		_pending_slot = id
		_start_save(Pending.LOAD))
	_pages["load"] = _saves
	_pages["settings"] = SettingsPanel.new()
	for p in _pages.values():
		body.add_child(p)

func _nav(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text.to_upper(), cb, "NavButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(280, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_nav_col.add_child(b)
	_nav_buttons.append(b)
	return b

func _fit_page() -> void:
	var w := get_viewport().get_visible_rect().size.x
	_page_root.offset_left = -minf(PAGE_W, w - 400.0 - 2.0 * UiTokens.EDGE) - UiTokens.EDGE

func tour_pages() -> Array:
	return ["load", "settings"]

func show_page(page: String) -> void:
	var was := _page
	_page = page
	for k in _nav_pages:
		var nb: Button = _nav_pages[k]
		nb.toggle_mode = true
		nb.set_pressed_no_signal(k == page)
	_page_root.visible = page != "home"
	for k in _pages:
		(_pages[k] as Control).visible = k == page
	if page == "load":
		_page_title.text = "LOAD GAME"
		_saves.current_slot_hint = SaveManager.current_slot
		_saves.refresh()
	elif page == "settings":
		_page_title.text = "SETTINGS"
	if page != "home" and was != page:
		UiSound.play("open")
		UiMotion.animate(_page_root, {"opacity": [0.0, 1.0], "x": [40, 0]}, {"duration": 0.6, "easing": "outExpo"})
		UiKit.title_in(_page_title)
		_page_rule.pivot_offset = Vector2(0, 4.5)
		UiMotion.animate(_page_rule, {"scale": [Vector2(0, 1), Vector2.ONE]}, {"duration": 0.8, "delay": 0.1, "easing": "outExpo"})

func is_open() -> bool:
	return _root.visible

## Esc goes back one level: an open page first, then the menu itself.
func back() -> void:
	UiSound.play("back")
	if _page != "home":
		show_page("home")
	else:
		close()

func open() -> void:
	_root.visible = true
	_page = "x"
	show_page("home")
	_status.text = ""
	_colony.text = ""
	_played.text = ""
	for s: Dictionary in SaveManager.list_slots():
		if s.id == SaveManager.current_slot:
			_colony.text = String(s.name).to_upper()
			_played.text = "%s PLAYED" % SaveManager.format_playtime(SaveManager.playtime_seconds())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UiState.set_open("pause", true)
	# the world really stops: threats, machines, physics. This menu runs PROCESS_MODE_ALWAYS and takes Esc itself.
	get_tree().paused = true
	UiSound.play("open")
	var mat := _backdrop.material as ShaderMaterial
	var tw := _root.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.25)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("blur", v), 0.0, 3.4, 0.5)
	UiKit.title_in(_colony)
	UiMotion.animate(_nav_col.get_children(), {"opacity": [0.0, 1.0], "x": [-24, 0]},
		{"duration": 0.7, "delay": UiMotion.stagger(0.04, {"start": 0.05}), "easing": "outExpo"})

func close() -> void:
	if _saving:
		return
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	UiState.set_open("pause", false)
	UiSound.play("close")

func _input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		back()
		get_viewport().set_input_as_handled()

func _start_save(after: int) -> void:
	if _saving:
		return
	_pending = after
	if not SaveManager.save_now():
		_status.theme_type_variation = "DangerLabel"
		_status.text = "SAVE FAILED - SEE THE LOG"
		UiKit.shake(_status)
		return
	_saving = true
	_status.theme_type_variation = "AccentLabel"
	_status.text = "SAVING..."
	for b in _nav_buttons:
		b.disabled = true

func _process(_delta: float) -> void:
	if not _saving or not SaveManager.terrain_save_complete():
		return
	_saving = false
	for b in _nav_buttons:
		b.disabled = false
	if _pending != Pending.NONE:
		get_tree().paused = false                 # never carry a paused tree into the next scene
	match _pending:
		Pending.MENU:
			UiState.set_open("pause", false)
			if get_tree().change_scene_to_file(MAIN_MENU_PATH) != OK:
				_status.text = "SAVED, BUT COULD NOT RETURN TO THE MENU"
				return
		Pending.QUIT:
			get_tree().quit()
		Pending.LOAD:
			UiState.set_open("pause", false)
			if SaveManager.open_slot(_pending_slot):
				get_tree().change_scene_to_file(WORLD_PATH)
		_:
			_status.text = "SAVED"
			UiSound.play("confirm")
			UiKit.pulse(_status)
	_pending = Pending.NONE

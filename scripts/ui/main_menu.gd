extends Control

## Start menu (docs/game/ux-bible.md, "Menus"). Minimal, Warframe-style: the game's own outpost at dusk fills the
## screen; a short nav sits on the left - Continue (the newest save named under it), New game, Load game,
## Settings, Quit - and the page it opens slides in on the right with a thin title and a gold rule. No game name
## or tagline for now (Michael, 2026-11-04: no logo yet, decide later). Built in code; the scene is just the root.

const WorldScene := preload("res://scenes/world.tscn")
## The outpost behind the menu: [item id, position, yaw deg]. Foundations are centre-anchored (0.25 m), so their
## centre sits at -0.125; buildings stand on y = 0.
const BACKDROP_SCENE := [
	["metal_foundation", Vector3(-2, -0.125, -1), 0], ["metal_foundation", Vector3(0, -0.125, -1), 0],
	["metal_foundation", Vector3(2, -0.125, -1), 0], ["metal_foundation", Vector3(-2, -0.125, 1), 0],
	["metal_foundation", Vector3(0, -0.125, 1), 0], ["metal_foundation", Vector3(2, -0.125, 1), 0],
	["smelter", Vector3(-2, 0, -1), 90], ["constructor", Vector3(0, 0, -1), 0], ["chest", Vector3(2, 0, -1), 180],
	["turret_cannon", Vector3(2, 0, 1), 220], ["basic_crafter", Vector3(-2, 0, 1), 90],
]
const VERSION := "v0.1 alpha"
const PAGE_W := 640.0

var _cam: Camera3D
var _orbit_t := 0.0
var _pages := {}
var _nav_pages := {}                  # page -> its nav entry, the light plate while that page is open
var _nav_col: VBoxContainer
var _page_root: Control
var _page_shade: TextureRect
var _page_crumb: Label
var _page_title: Label
var _page_rule: Control
var _page_body: MarginContainer
var _foot: HBoxContainer
var _continue_btn: Button
var _continue_sub: Label
var _saves: SavesPanel
var _name_edit: LineEdit
var _page := "home"

func _ready() -> void:
	add_to_group("main_menu")
	SaveManager.end_session()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_nav()
	_build_page()
	show_page("home")
	# first impression: the nav arrives one entry after another
	UiMotion.animate(_nav_col.get_children(), {"opacity": [0.0, 1.0], "x": [-28, 0]},
		{"duration": 0.9, "delay": UiMotion.stagger(0.06, {"start": 0.25}), "easing": "outExpo"})

func _process(delta: float) -> void:
	_orbit_t += delta
	_orbit(_orbit_t)

## Slow orbit round the outpost (one turn in ~4 minutes), framed so the base sits in the right two-thirds.
func _orbit(t: float) -> void:
	if _cam == null:
		return
	var a := deg_to_rad(205.0) + t * 0.026
	var target := Vector3(0.6, 0.9, 0.0)
	_cam.look_at_from_position(target + Vector3(sin(a) * 15.0, 4.6 + sin(t * 0.21) * 0.25, cos(a) * 15.0), target + Vector3(-3.4, -0.4, 0).rotated(Vector3.UP, a), Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _page != "home":
		UiSound.play("back")
		show_page("home")

## --- backdrop: the outpost in a SubViewport behind the UI ---------------------------------------------------
func _build_backdrop() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	# Dusk: a low warm sun raking across a small outpost, cold sky above, the horizon glowing. The game's own
	# buildings (meshes only, no scripts) on a 3 x 2 pad of foundations, the camera drifting slowly round.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("0a1520")
	sm.sky_horizon_color = Color("4a5560")
	sm.ground_horizon_color = Color("2a2a2c")
	sm.ground_bottom_color = Color("0a0c0e")
	sm.sun_angle_max = 12.0
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.05
	e.fog_enabled = true                    # a separate world: fog here cannot grey the game's sky
	e.fog_light_color = Color("4a5560")
	e.fog_density = 0.028
	e.fog_sky_affect = 0.3
	env.environment = e
	sv.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-11, 118, 0)
	key.light_color = Color("ffd6a0")
	key.light_energy = 3.2
	key.shadow_enabled = true
	sv.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-35, -60, 0)
	rim.light_color = Color("8fb0d0")
	rim.light_energy = 0.5
	sv.add_child(rim)
	var base := Node3D.new()
	sv.add_child(base)
	for p in BACKDROP_SCENE:
		var item := Inventory.get_item_def(String(p[0]))
		if item == null or item.building_scene == null:
			continue
		var m := ModelMeshes.extract(item.building_scene)
		m.position = p[1]
		m.rotation.y = deg_to_rad(float(p[2]))
		base.add_child(m)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("3a3836")
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position.y = -0.26
	sv.add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 34
	sv.add_child(_cam)
	_orbit(0.0)
	add_child(_side_gradient(false, 0.94, 700.0))
	_page_shade = _side_gradient(true, 0.9, 900.0)
	_page_shade.modulate.a = 0.0
	add_child(_page_shade)

## A dark gradient from one edge so text reads on the 3D scene (left for the nav, right for an open page).
func _side_gradient(right: bool, strength: float, width: float) -> TextureRect:
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(UiTokens.INK, strength))
	g.set_color(1, Color(UiTokens.INK, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(1, 0) if right else Vector2(0, 0)
	gt.fill_to = Vector2(0, 0) if right else Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.anchor_bottom = 1.0
	if right:
		grad.anchor_left = 1.0
		grad.anchor_right = 1.0
		grad.offset_left = -width
	else:
		grad.offset_right = width
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return grad

## --- nav ---------------------------------------------------------------------------------------------------
func _build_nav() -> void:
	_nav_col = UiKit.vbox(2)
	_nav_col.anchor_top = 0.5
	_nav_col.anchor_bottom = 0.5
	_nav_col.offset_left = UiTokens.EDGE
	_nav_col.offset_right = UiTokens.EDGE + 300
	_nav_col.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_nav_col)
	_continue_btn = _nav("Continue", _on_continue)
	_continue_sub = UiKit.label("", "CrumbLabel")
	var sub_m := MarginContainer.new()
	sub_m.add_theme_constant_override("margin_left", 20)
	sub_m.add_theme_constant_override("margin_bottom", 10)
	sub_m.add_child(_continue_sub)
	_nav_col.add_child(sub_m)
	_nav_pages["new"] = _nav("New game", show_page.bind("new"))
	_nav_pages["load"] = _nav("Load game", show_page.bind("load"))
	_nav_pages["settings"] = _nav("Settings", show_page.bind("settings"))
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	_nav_col.add_child(gap)
	_nav("Quit", func() -> void: get_tree().quit())
	var ver := UiKit.label(VERSION.to_upper(), "CrumbLabel")
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = UiTokens.EDGE
	ver.offset_top = -56
	add_child(ver)
	_foot = UiKit.hint_row([["Esc", "Back"]])
	_foot.anchor_left = 1.0
	_foot.anchor_right = 1.0
	_foot.anchor_top = 1.0
	_foot.anchor_bottom = 1.0
	_foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_foot.offset_right = -UiTokens.EDGE
	_foot.offset_bottom = -36
	add_child(_foot)

func _nav(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text.to_upper(), cb, "NavButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(280, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_nav_col.add_child(b)
	return b

## --- the page on the right ----------------------------------------------------------------------------------
func _build_page() -> void:
	_page_root = Control.new()
	_page_root.anchor_left = 1.0
	_page_root.anchor_right = 1.0
	_page_root.anchor_bottom = 1.0
	_page_root.offset_left = -PAGE_W - UiTokens.EDGE
	_page_root.offset_right = -UiTokens.EDGE
	_page_root.offset_top = 56
	_page_root.offset_bottom = -84
	add_child(_page_root)
	get_viewport().size_changed.connect(_fit_page)
	_fit_page.call_deferred()
	var col := UiKit.vbox(6)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page_root.add_child(col)
	_page_crumb = UiKit.label("MAIN MENU  /", "CrumbLabel")
	col.add_child(_page_crumb)
	_page_title = UiKit.title("")
	col.add_child(_page_title)
	_page_rule = UiKit.rule()
	col.add_child(_page_rule)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	col.add_child(gap)
	_page_body = MarginContainer.new()
	_page_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_page_body)
	_pages["new"] = _new_game_page()
	_saves = SavesPanel.new()
	_saves.load_requested.connect(_load_slot)
	_pages["load"] = _saves
	_pages["settings"] = SettingsPanel.new()
	for p in _pages.values():
		_page_body.add_child(p)

## The page column is 640 px, narrower on small windows, and never covers the nav.
func _fit_page() -> void:
	var w := get_viewport().get_visible_rect().size.x
	_page_root.offset_left = -minf(PAGE_W, w - 400.0 - 2.0 * UiTokens.EDGE) - UiTokens.EDGE

func _new_game_page() -> Control:
	var col := UiKit.vbox(UiTokens.GAP_L)
	col.add_child(UiKit.section("Colony name"))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(420, 42)
	_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name_edit.max_length = 32
	_name_edit.text_submitted.connect(func(_t: String) -> void: _start_new())
	col.add_child(_name_edit)
	var info := UiKit.label("You land with a mining drill and a build tool. Your suit holds five minutes of air; a Ship Garage refills it.", "DimLabel")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 420
	col.add_child(info)
	var start := UiKit.button("START", _start_new, "PrimaryButton")
	start.custom_minimum_size = Vector2(180, 42)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(start)
	return col

func tour_pages() -> Array:
	return ["new", "load", "settings"]

func show_page(page: String) -> void:
	var titles := {"new": "New game", "load": "Load game", "settings": "Settings"}
	var was := _page
	_page = page
	for k in _nav_pages:
		var nb: Button = _nav_pages[k]
		nb.toggle_mode = true
		nb.set_pressed_no_signal(k == page)
	var open := page != "home"
	_page_root.visible = open
	_foot.visible = open
	for k in _pages:
		(_pages[k] as Control).visible = k == page
	if open:
		_page_title.text = String(titles[page]).to_upper()
		if page == "new":
			_name_edit.text = "New Colony"
			_name_edit.grab_focus()
			_name_edit.select_all()
		if page == "load":
			_saves.refresh()
		if was != page:
			# the page slides in from the right, its title tracks in, the rule draws, the rows follow
			UiSound.play("open")
			UiMotion.animate(_page_root, {"opacity": [0.0, 1.0], "x": [40, 0]}, {"duration": 0.6, "easing": "outExpo"})
			UiKit.title_in(_page_title)
			_page_rule.pivot_offset = Vector2(0, 4.5)
			UiMotion.animate(_page_rule, {"scale": [Vector2(0, 1), Vector2.ONE]}, {"duration": 0.8, "delay": 0.1, "easing": "outExpo"})
			UiMotion.animate(_page_shade, {"opacity": 1.0}, {"duration": 0.4, "easing": "outQuad"})
	else:
		UiMotion.animate(_page_shade, {"opacity": 0.0}, {"duration": 0.4, "easing": "outQuad"})
	_refresh_continue()

func _refresh_continue() -> void:
	var slots := SaveManager.list_slots()
	_continue_btn.visible = not slots.is_empty()
	_continue_sub.get_parent().visible = not slots.is_empty()
	if not slots.is_empty():
		_continue_sub.text = "%s   ·   %s PLAYED" % [String(slots[0].name).to_upper(), SaveManager.format_playtime(slots[0].playtime_sec)]

func _on_continue() -> void:
	var slots := SaveManager.list_slots()
	if not slots.is_empty():
		_load_slot(String(slots[0].id))

func _load_slot(id: String) -> void:
	if SaveManager.open_slot(id):
		UiSound.play("confirm")
		get_tree().change_scene_to_packed(WorldScene)

func _start_new() -> void:
	var colony := _name_edit.text.strip_edges()
	if colony == "":
		UiKit.shake(_name_edit)
		return
	var id := SaveManager.create_slot(colony)
	if id == "":
		UiKit.shake(_name_edit)
		return
	# A brand-new game is an open slot with no state to apply - see SaveManager.apply_pending().
	SaveManager.begin_session(id, SaveManager.read_state(id))
	get_tree().change_scene_to_packed(WorldScene)

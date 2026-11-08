extends CharacterBody3D

const SPEED := 6.0
const SPRINT_SPEED := 9.5
## m/s^2. Ground: reach full speed in ~0.13 s, stop in ~0.1 s - responsive but not a light switch.
const GROUND_ACCEL := 45.0
const GROUND_DECEL := 60.0
const AIR_ACCEL := 9.0
const JUMP_VELOCITY := 6.0
var sprinting := false
var _move_vel := Vector3.ZERO
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT := 1.4

const DIG_RANGE := 6.0
## World metres, but sized in VOXELS: this was 2.5 voxels at the old 0.4 m
## scale and is kept at the same voxel count under 1 m voxels. Bore size and
## rate live in TerrainDrill.
const BUILD_RADIUS := 2.5
const INTERACT_RANGE := 3.5
const SHIP_PLACE_RANGE := 40.0
const SHIP_CORE_SPAWN_DISTANCE := 10.0
const UI_INPUT_COOLDOWN := 0.15


## First-person building, Satisfactory style (2026-11-04, replaced the top-down build camera Michael called "shit"):
## the player keeps walking and looking around, the ghost sits where the crosshair hits the world, up to this far.
const BUILD_MODE_RANGE := 30.0
const BUILD_ROTATE_STEP := PI / 2.0
## Mouse wheel turns the ghost in finer steps than R.
const BUILD_WHEEL_STEP := PI / 12.0

## How close the cursor needs to be to an existing foundation's edge slot to
## snap a new foundation there, and how close a regular building's ghost
## needs to be to a foundation's center to mount flush on top of it instead
## of free-placing tangent to the raw terrain.
const FOUNDATION_SNAP_RADIUS := 3.0
const FOUNDATION_MOUNT_RADIUS := 1.3

## How long left-click must be held before the tool "spins up" and starts
## actually cutting, and how often it cuts again while held after that.
const DIG_SPINUP_TIME := 0.35

const BuildRecipe: Recipe = preload("res://data/recipes/build_block.tres")
const MiningToolItem: Item = preload("res://data/items/mining_tool.tres")
const BuildingToolItem: Item = preload("res://data/items/building_tool.tres")
const ScannerToolItem: Item = preload("res://data/items/scanner_tool.tres")

## Seconds between scans. The scan itself costs 30-80 ms of generator work, so
## holding fire has to be rate limited rather than merely discouraged.
const SCAN_COOLDOWN := 1.5
var _scan_cooldown := 0.0

## Fractional items owed by the drill, {item_id: float} - see TerrainDrill.payout().
var _yield_carry := {}

@onready var camera: Camera3D = $Camera3D
@onready var viewmodel: Node3D = $Camera3D/ViewmodelTool
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var _pitch := 0.0
## Camera bob, tool sway, landing and use kicks (scripts/player/first_person_feel.gd).
var feel: FirstPersonFeel = null
var _held_sig := ""
var _terrain: VoxelNode = null
var _inventory_open := false
var _ui_input_cooldown_until := 0.0
var _interact_was_down := false
var _targeted_building: Building = null
var _targeted_cockpit: ShipCockpit = null
var _piloted_ship: Ship = null
var _ship_controller: PlayerShipController = null
var _ship_viewer: VoxelViewer = null

## Planet gravity: the world is a sphere, so "down" is always toward the
## planet's center - PlanetPhysics (autoload) is the one shared source of
## truth for that center and the gravity constant, also read by turrets and
## projectiles so none of them can drift out of sync with each other. Speed
## along that radial axis is tracked separately from tangential (WASD) speed
## since CharacterBody3D.velocity is reconstructed fresh from both every
## frame rather than storing gravity in velocity.y the way a flat-world
## controller would.
var _vertical_speed := 0.0
var _spawn_resolved := false
## Physics frames spent waiting for the nearest body's collision meshes to
## exist under the spawn point before giving up and dropping in anyway.
const SPAWN_WAIT_MAX_FRAMES := 3600
## World meters above the body's nominal radius the capsule is parked at
## while waiting - clear of the tallest terrain the height/detail noise can
## produce, so streaming terrain never spawns inside the player.
## Clearance above the body's HIGHEST possible terrain, added on top of that
## body's relief rather than used as an absolute height. These were flat
## constants tuned when relief was +-3 m; at +-80 m the capsule parked at
## radius+20 could sit 100 m above the actual local ground, the probe below
## never reached it, and spawn never resolved - the player fell through the
## planet. Anything that assumes the surface is at radius_world() breaks the
## moment relief is a meaningful fraction of the radius.
const SPAWN_HOVER_CLEARANCE := 20.0
## Extra height the spawn probe starts above the parked capsule, and how far
## below the nominal radius it reaches, so it crosses the surface no matter
## where the noise put it.
const SPAWN_PROBE_RISE := 10.0
const SPAWN_PROBE_DEPTH := 30.0
const SPAWN_SURFACE_CLEARANCE := 0.5
var _spawn_wait_frames := 0
## Set by load_state(): the player's position came from a save and must be
## preserved, so spawn resolution waits for terrain instead of placing them.
var _spawn_from_save := false

var _dig_held := false
var _dig_hold_time := 0.0
var _dig_spun_up := false
var _dig_tick_timer := 0.0
var _dig_hold_started := false

## Build mode: the player walks and looks as normal; the build menu (mouse free) opens on entry and on Q, and
## closes once a building is picked. While it is open the world gets no clicks.
var _build_mode := false
var _build_grid_snap := true
var _build_rotation := 0.0
var _build_ghost: MeshInstance3D = null
var _build_ghost_material: StandardMaterial3D = null
var _pipe_anchor: Vector3 = Vector3.ZERO
var _pipe_anchor_set := false
var _pipe_preview_end: Vector3 = Vector3.ZERO
## Pipe build mode: false = STRAIGHT (axis runs, tight knees), true = CURVED (natural path, wide bends). B toggles.
var _pipe_curved := false

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.far = 1000000.0
	_terrain = PlanetPhysics.get_nearest_terrain(global_position)
	_spawn_resolved = false
	Inventory.changed.connect(_update_viewmodel)
	Inventory.changed.connect(_on_tools_changed)
	feel = FirstPersonFeel.new()
	feel.name = "Feel"
	add_child(feel)
	feel.setup(self, camera, viewmodel)
	_build_lamp()
	_update_viewmodel()
	_refresh_hud()

## A tool taken out of the hand stops doing its job: the scanner's pulse and the build mode must not outlive it
## (the scanner kept "searching" on screen for 90 s after it was put away, and build mode stayed on with no tool).
## True while the hand that owns the drill's mouse button still holds the Mining Tool.
func _drill_in_hand() -> bool:
	var side := "left" if _dig_button == MOUSE_BUTTON_LEFT else "right"
	return Inventory.get_slot({"kind": "hand", "side": side}).item_id == MiningToolItem.id

func _on_tools_changed() -> void:
	var scanner_hud := get_tree().get_first_node_in_group("scanner_hud")
	if scanner_hud != null and scanner_hud.has_method("set_active"):
		scanner_hud.set_active(Inventory.has_tool_equipped(ScannerToolItem.id))
	if _build_mode and not Inventory.has_tool_equipped(BuildingToolItem.id):
		_toggle_build_mode()

func _update_viewmodel() -> void:
	# the held tool: one model per tool item (data/models/tools), shown in the first-person view
	var shown := false
	for pair in [["MiningTool", MiningToolItem], ["ScannerTool", ScannerToolItem], ["BuildTool", BuildingToolItem]]:
		var node := viewmodel.get_node_or_null(String(pair[0])) as Node3D
		if node == null:
			continue
		var hand := Inventory.hand_holding((pair[1] as Item).id)
		node.visible = hand != ""
		# each tool in its own hand: right hand on the right of the view, left hand mirrored to the left, both
		# turned a little in toward the crosshair so the player sees their sides, not their back ends
		node.position = Vector3(-0.46 if hand == "left" else 0.0, 0.0, 0.0)
		node.rotation = Vector3(0.0, -0.13 if hand == "left" else 0.13, 0.0)
		shown = shown or node.visible
	viewmodel.visible = shown   # first-person building keeps the build tool in hand
	var held := "%s/%s" % [Inventory.get_slot({"kind": "hand", "side": "left"}).item_id, Inventory.get_slot({"kind": "hand", "side": "right"}).item_id]
	if held != _held_sig and feel != null:
		feel.equip()            # tools changed: raise the new ones into view
	_held_sig = held
	_refresh_hud()

## Only PLAYER/SHIP text is needed here: every other mode (build, inventory,
## journal, a building panel) hides the whole HUD via UiState (see
## compact_hud.gd), so nobody would ever see a legend for those anyway.
func _refresh_hud() -> void:
	var hud := get_tree().get_first_node_in_group("compact_hud")
	if hud == null or not hud.has_method("set_mode_text"):
		return
	if hud.has_method("set_piloted_ship"):
		hud.set_piloted_ship(_piloted_ship)
	if _piloted_ship != null:
		hud.set_mode_text("SHIP", "W/S Drive or thrust  A/D Steer or strafe  Space/Ctrl Lift  Q/R Roll  G Landing gear  V Camera  X Dampeners  E Exit")
		return
	if _build_mode:
		_refresh_build_hint()
		return
	hud.set_mode_text("PLAYER", "")

func _input(event: InputEvent) -> void:
	if DevConsole.is_open:
		return   # typing in the console must not trigger C/F/J/Tab etc.
	if _piloted_ship != null:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var ship_item := _equipped_ship_item()
			if ship_item != null and _ship_controller != null:
				_place_ship_item(ship_item, _ship_controller.get_active_camera())
		return
	# Handled in _input (before GUI focus navigation can eat it) rather than
	# _unhandled_input: Tab is bound to GUI focus-next by default, and once an
	# inventory slot Button has focus it swallows Tab before _unhandled_input
	# ever sees it, permanently getting the player stuck with the mouse freed.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			if _ui_input_on_cooldown():
				return
			_start_ui_input_cooldown()
			_toggle_inventory()
			_hud_key("Tab")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			if _ui_input_on_cooldown():
				return
			_start_ui_input_cooldown()
			_toggle_build_mode()
			_hud_key("C")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F and _build_mode and not _build_menu_open():
			_set_dismantle_mode(not _dismantle_mode)      # Satisfactory: F with the build tool out = dismantle
			_hud_key("F")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F and not UiState.is_any_open():
			toggle_lamp()
			_hud_key("F")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_J:
			if _ui_input_on_cooldown():
				return
			_start_ui_input_cooldown()
			_toggle_journal()
			_hud_key("J")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _ui_input_on_cooldown():
				return
			_start_ui_input_cooldown()
			if _inventory_open:
				_toggle_inventory()
			elif _is_journal_open():
				_toggle_journal()
			elif _is_building_ui_open():
				_close_building_ui()
			elif _build_mode:
				_toggle_build_mode()
			else:
				_toggle_pause_menu()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if DevConsole.is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			get_tree().reload_current_scene()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F2:
			_spawn_debug_ship()
			get_viewport().set_input_as_handled()
			return

	if _piloted_ship != null:
		return

	if _inventory_open or _is_journal_open():
		return

	if _build_mode:
		if _build_menu_open():
			return # the menu's buttons take the clicks; picking one closes it (on_build_picked)
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT and _dismantle_mode:
				_dismantle()
			elif event.button_index == MOUSE_BUTTON_RIGHT and _dismantle_mode:
				_set_dismantle_mode(false)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if _is_pipe_item(_selected_build_item()):
					_place_pipe_or_set_anchor()
				else:
					_place_building()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				# first right click drops a started pipe run, the next one leaves build mode
				if _pipe_anchor_set:
					_pipe_anchor_set = false
				else:
					_toggle_build_mode()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_build_rotation = wrapf(_build_rotation + BUILD_WHEEL_STEP, 0.0, TAU)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_build_rotation = wrapf(_build_rotation - BUILD_WHEEL_STEP, 0.0, TAU)
			get_viewport().set_input_as_handled()
			if _build_mode:
				_refresh_build_hint()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_B and _is_pipe_item(_selected_build_item()):
				_pipe_curved = not _pipe_curved
			elif event.keycode == KEY_G:
				_build_grid_snap = not _build_grid_snap
			elif event.keycode == KEY_R:
				_build_rotation = wrapf(_build_rotation + BUILD_ROTATE_STEP, 0.0, TAU)
			elif event.keycode == KEY_Q:
				_set_dismantle_mode(false)
				_open_build_menu()
			_refresh_build_hint()
		# mouse motion falls through to the normal look below

	if event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_on_hand_button(event.button_index, event.pressed)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# rotate_object_local (not rotate_y/rotate_y works in the PARENT frame)
		# so yaw always turns around the player's own current up axis - on a
		# sphere that axis constantly changes as the player walks around, and
		# only the object-local rotation stays correct once away from the
		# spawn point's "pole".
		var sens := MOUSE_SENSITIVITY * float(GameSettings.get_value("mouse_sens"))
		var dy: float = event.relative.y * (-1.0 if GameSettings.get_value("invert_y") else 1.0)
		rotate_object_local(Vector3.UP, -event.relative.x * sens)
		_pitch = clamp(_pitch - dy * sens, -PITCH_LIMIT, PITCH_LIMIT)
		camera.rotation.x = _pitch
		if feel != null:
			feel.add_look(event.relative * float(GameSettings.get_value("mouse_sens")))

## Esc with nothing else open. Previously this just freed the mouse, which left
## no way to save or leave the game; the pause menu is now the only exit path,
## so quitting always goes through code that can flush the world to disk first.
func _toggle_pause_menu() -> void:
	var menu := get_tree().current_scene.get_node_or_null("PauseMenu")
	if menu == null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if not menu.is_open():
		menu.open()           # closing is the menu's own job: it runs while the tree is paused and takes Esc

## THE tool rule (docs/game/tools.md): the left mouse button uses the tool in the LEFT hand, the right button the
## tool in the RIGHT hand. What a press does depends only on what that hand holds:
##   Mining Tool   hold to bore (spins up, then bites)
##   Scanner       one ping per press
##   Building Tool opens build mode (the build menu); in build mode LMB places, RMB leaves
##   ship part     places it (ship cores and blocks)
##   empty / other nothing - except RMB with a Mining Tool in the other hand, which lays a terrain block (the old
##                 place-block action, kept for the "Lay a Block" quest)
## Both hands are always live, so there is no hidden "which tool wins": put a tool in a hand (Tab, drag it in)
## and that mouse button is that tool.
func _on_hand_button(button: int, pressed: bool) -> void:
	if not pressed:
		if button == _dig_button:
			var was_boring := _dig_spun_up or _dig_hold_started
			_reset_dig_hold()
			if was_boring:
				UiSound.play("spindown", 1.0, 0.1)   # the drill winds down, whether or not it got up to speed
		return
	var side := "left" if button == MOUSE_BUTTON_LEFT else "right"
	var tool_id: String = Inventory.get_slot({"kind": "hand", "side": side}).item_id
	if tool_id == MiningToolItem.id:
		_dig_held = true
		_dig_button = button
		_dig_hold_started = true
		UiSound.play("spinup", 1.0, 0.1)             # the wind-up whine is the feedback while it spins up
	elif tool_id == ScannerToolItem.id:
		_scan_for_ore()
	elif tool_id == BuildingToolItem.id:
		if not _ui_input_on_cooldown():
			_start_ui_input_cooldown()
			_toggle_build_mode()
	else:
		var item := Inventory.get_item_def(tool_id) if tool_id != "" else null
		if item != null and (item.is_ship_core or item.is_ship_block):
			_place_ship_item(item)
		elif button == MOUSE_BUTTON_RIGHT and Inventory.has_tool_equipped(MiningToolItem.id):
			_build()
		elif feel != null:
			feel.kick("deny")                         # empty hand: a small no, so it never feels dead

var _dig_button := 0                                 # the mouse button driving the drill (0 = none)

func _reset_dig_hold() -> void:
	_dig_held = false
	_dig_button = 0
	_dig_empty_bites = 0
	_dig_hold_time = 0.0
	_dig_spun_up = false
	_dig_tick_timer = 0.0
	_dig_hold_started = false

func _ui_input_on_cooldown() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _ui_input_cooldown_until

func _start_ui_input_cooldown() -> void:
	_ui_input_cooldown_until = Time.get_ticks_msec() / 1000.0 + UI_INPUT_COOLDOWN

func _toggle_inventory() -> void:
	# Inventory, build mode, and the journal are all mutually exclusive:
	# closing whichever else is open first keeps mouse-mode and dig/build
	# gating unambiguous instead of having to track several independently-
	# active modes at once.
	if _is_building_ui_open():
		_close_building_ui()
	if _build_mode:
		_toggle_build_mode()
	if _is_journal_open():
		_toggle_journal()
	_inventory_open = not _inventory_open
	if _inventory_open:
		_reset_dig_hold()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _inventory_open else Input.MOUSE_MODE_CAPTURED
	_refresh_hud()
	# Looked up fresh rather than cached in _ready(): InventoryUI registers its
	# group via add_to_group() in its own _ready(), and Player appears earlier
	# than InventoryUI in world.tscn, so caching this in Player._ready() would
	# run before InventoryUI has joined the group and silently find nothing.
	var inventory_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inventory_ui != null:
		inventory_ui.toggle()

func _toggle_build_mode() -> void:
	if _is_building_ui_open():
		_close_building_ui()
		return
	# Gated like the mining tool's dig/build: the Building Tool must be
	# equipped in a hand slot to ENTER build mode (closing it stays allowed
	# unconditionally, e.g. if the tool got unequipped mid-session).
	if not _build_mode and not Inventory.has_tool_equipped(BuildingToolItem.id):
		return
	if _inventory_open:
		_toggle_inventory()
	if _is_journal_open():
		_toggle_journal()
	if _build_mode:
		_exit_build_mode()
	else:
		_enter_build_mode()
	_refresh_hud()

func _is_journal_open() -> bool:
	var journal := get_tree().get_first_node_in_group("journal_ui")
	return journal != null and journal.is_open()

func _toggle_journal() -> void:
	# Same mutual-exclusion rule as the other full-screen GUIs (see
	# _toggle_inventory()'s comment).
	if _is_building_ui_open():
		_close_building_ui()
	if _build_mode:
		_toggle_build_mode()
	if _inventory_open:
		_toggle_inventory()
	var journal := get_tree().get_first_node_in_group("journal_ui")
	if journal == null:
		return
	journal.toggle()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if journal.is_open() else Input.MOUSE_MODE_CAPTURED
	_refresh_hud()

func _enter_build_mode() -> void:
	_build_mode = true
	_reset_dig_hold()
	_build_rotation = 0.0
	_build_grid_snap = true
	_pipe_anchor_set = false
	_update_viewmodel()
	_spawn_build_ghost()
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui != null:
		build_ui.bind_player(self)
		build_ui.show_ui()
	_open_build_menu()
	_refresh_hud()

func _exit_build_mode() -> void:
	_build_mode = false
	_pipe_anchor_set = false
	_clear_build_ghost()
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui != null:
		build_ui.hide_ui()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_viewmodel()
	_refresh_hud()
	_refresh_build_hint()

func _build_menu_open() -> bool:
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	return build_ui != null and build_ui.is_menu_open()

func _open_build_menu() -> void:
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null:
		return
	_pipe_anchor_set = false
	build_ui.set_menu_open(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_build_hint()

## Called by the build menu when a building is picked: close the menu, back to aiming with the crosshair.
func on_build_picked() -> void:
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui != null:
		build_ui.set_menu_open(false)
	_pipe_anchor_set = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_build_hint()

## Build key hints go on the HUD (bottom centre) while aiming, and clear when building ends.
func _refresh_build_hint() -> void:
	var hud := get_tree().get_first_node_in_group("compact_hud")
	if hud == null:
		return
	if not _build_mode:
		_last_hint_pairs = ""
		hud.set_context_hints([])
		return
	var item := _selected_build_item()
	var pairs: Array = [["LMB", "Place " + (item.display_name if item != null else "")], ["R/Wheel", "Rotate"],
		["G", "Grid " + ("on" if _build_grid_snap else "off")], ["F", "Dismantle"], ["Q", "Menu"], ["RMB", "Done"]]
	if item != null and item.id == "vacuum_pipe":
		pairs = [["LMB", "Start / end pipe" if not _pipe_anchor_set else "End pipe here"],
			["B", "Curved" if _pipe_curved else "Straight"], ["F", "Dismantle"], ["Q", "Menu"],
			["RMB", "Cancel" if _pipe_anchor_set else "Done"]]
		if _pipe_anchor_set and not _pipe_route_preview.is_empty() and not _pipe_route_preview.get("ok", true):
			pairs.push_front(["!", String(_pipe_route_preview.get("why", ""))])
	if _dismantle_mode:
		var t := _dismantle_target
		if t != null and is_instance_valid(t):
			pairs = [["LMB", "Dismantle, get back " + _refund_text(_dismantle_refund(t))], ["F/RMB", "Back to building"]]
		else:
			pairs = [["LMB", "Aim at something you built"], ["F/RMB", "Back to building"]]
	if _build_message != "" and Time.get_ticks_msec() < _build_message_until:
		pairs.push_front(["!", _build_message])
	if str(pairs) == _last_hint_pairs:
		return                                        # unchanged: the HUD rebuilds its row on every call
	_last_hint_pairs = str(pairs)
	hud.set_context_hints(pairs)

func _spawn_build_ghost() -> void:
	_clear_build_ghost()
	var ghost := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.5, 1.5, 1.5)
	ghost.mesh = mesh
	# Hologram: the suit's mint status light, see-through, unlit - the same colour as every "OK" in the UI.
	# Red when the spot is not valid. The building's real meshes are shown (ModelMeshes), not a box.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GHOST_OK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	ghost.material_override = mat
	ghost.visible = false
	get_tree().current_scene.add_child(ghost)
	_build_ghost = ghost
	_build_ghost_material = mat
	_ghost_model_id = ""

const GHOST_OK := Color(0.56, 0.89, 0.69, 0.32)
const GHOST_BAD := Color(0.9, 0.33, 0.24, 0.38)
var _ghost_model_id := ""

## Swap the ghost's look to the picked building's real meshes (once per pick, not per frame).
func _ghost_model_for(item: Item) -> void:
	var want := item.id if item != null and item.building_scene != null and item.id != "vacuum_pipe" else ""
	if want == _ghost_model_id:
		return
	_ghost_model_id = want
	for c in _build_ghost.get_children():
		c.queue_free()
	if want != "":
		_build_ghost.add_child(ModelMeshes.extract(item.building_scene, _build_ghost_material))

func _clear_build_ghost() -> void:
	if _build_ghost != null:
		_build_ghost.queue_free()
		_build_ghost = null
	_hide_pipe_preview()
	_set_pipe_arrows(false)
	_set_dismantle_mode(false)

# --- pipe run preview -----------------------------------------------------------------------------------------
var _pipe_preview: MeshInstance3D
var _pipe_preview_mat: StandardMaterial3D
var _pipe_route_preview: Dictionary = {}
var _pipe_arrows_on := false

func _show_pipe_preview(route: Dictionary, ok: bool) -> void:
	if _pipe_preview == null:
		_pipe_preview = MeshInstance3D.new()
		_pipe_preview.name = "PipeRunPreview"
		_pipe_preview.top_level = true
		_pipe_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pipe_preview_mat = StandardMaterial3D.new()
		_pipe_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_pipe_preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_pipe_preview_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		get_tree().current_scene.add_child(_pipe_preview)
	_pipe_preview.global_transform = Transform3D.IDENTITY
	_pipe_preview.mesh = PipeRoute.preview_mesh(route, func(p: Vector3) -> Vector3: return PlanetPhysics.get_up(p))
	_pipe_preview.set_surface_override_material(0, _pipe_preview_mat)
	var c := GHOST_OK if ok else GHOST_BAD
	_pipe_preview_mat.albedo_color = Color(c.r, c.g, c.b, 0.6)
	_pipe_preview.visible = true

func _hide_pipe_preview() -> void:
	_pipe_route_preview = {}
	if _pipe_preview != null and is_instance_valid(_pipe_preview):
		_pipe_preview.visible = false

# --- dismantle (Satisfactory: F with the build tool out) ------------------------------------------------------
## F in build mode switches to dismantling: what you look at turns red with its refund on the HUD; LMB takes it
## apart and gives back everything it cost plus what it holds (all or nothing: refused if it won't fit). F again,
## Q (menu) or RMB goes back.
var _dismantle_mode := false
var _dismantle_target: Node3D
var _dismantle_mat: StandardMaterial3D

func _set_dismantle_mode(on: bool) -> void:
	if on == _dismantle_mode:
		return
	_dismantle_mode = on
	_pipe_anchor_set = false
	if not on:
		_set_dismantle_target(null)
	_refresh_build_hint()

func _update_dismantle_target() -> void:
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - camera.global_transform.basis.z * BUILD_MODE_RANGE)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Node3D = null
	if not hit.is_empty():
		var n: Node = hit.collider
		while n != null and not n.has_meta(SaveManager.ITEM_ID_META):
			n = n.get_parent()
		if n is Node3D and _refund_recipe(n) != null:
			target = n
	_set_dismantle_target(target)

func _refund_recipe(n: Node) -> Recipe:
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null or not n.has_meta(SaveManager.ITEM_ID_META):
		return null
	return build_ui.recipe_for(String(n.get_meta(SaveManager.ITEM_ID_META)))

func _set_dismantle_target(t: Node3D) -> void:
	if t == _dismantle_target:
		return
	if _dismantle_target != null and is_instance_valid(_dismantle_target):
		for g in _dismantle_target.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_overlay = null
	_dismantle_target = t
	if t != null:
		if _dismantle_mat == null:
			_dismantle_mat = StandardMaterial3D.new()
			_dismantle_mat.albedo_color = Color(GHOST_BAD.r, GHOST_BAD.g, GHOST_BAD.b, 0.45)
			_dismantle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_dismantle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for g in t.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_overlay = _dismantle_mat
	_refresh_build_hint()

## Everything taking `t` apart gives back: its build cost, plus a machine's stored items and modifiers and a pipe's
## item in transit.
func _dismantle_refund(t: Node3D) -> Dictionary:
	var out := {}
	var r := _refund_recipe(t)
	if r != null:
		for k in r.input_ids.size():
			out[r.input_ids[k]] = int(out.get(r.input_ids[k], 0)) + r.input_amounts[k]
	if t is Building:
		var b := t as Building
		for i in b.inventory_slots:
			var slot := b.get_inventory_slot(i)
			if String(slot.item_id) != "" and int(slot.count) > 0:
				out[slot.item_id] = int(out.get(slot.item_id, 0)) + int(slot.count)
		for m: String in b._modifiers:
			if m != "":
				out[m] = int(out.get(m, 0)) + 1
	if t is PipeSegment and (t as PipeSegment)._held_item_id != "":
		var h := (t as PipeSegment)._held_item_id
		out[h] = int(out.get(h, 0)) + 1
	return out

func _dismantle() -> void:
	var t := _dismantle_target
	if t == null or not is_instance_valid(t):
		_deny_build()
		return
	var refund := _dismantle_refund(t)
	if not Inventory.can_add_all(refund):
		_deny_build("No room in your inventory")
		return
	for id: String in refund:
		Inventory.add(id, refund[id])
	_set_dismantle_target(null)
	var was_pipe := t.is_in_group("pipe")
	for g in ["pipe", "building", SaveManager.SAVEABLE_GROUP]:
		if t.is_in_group(g):
			t.remove_from_group(g)
	t.queue_free()
	if was_pipe:
		PipeSegment.relink_all(get_tree())
	if feel != null:
		feel.kick("place")
	UiSound.play("place", 0.7)

func _refund_text(refund: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in refund:
		var it := Inventory.get_item_def(id)
		parts.append("%d %s" % [refund[id], it.display_name if it != null else id])
	return ", ".join(parts)

## Flow arrows on every laid pipe while a pipe is in the build tool.
func _set_pipe_arrows(on: bool) -> void:
	if on == _pipe_arrows_on:
		return
	_pipe_arrows_on = on
	for n in get_tree().get_nodes_in_group("pipe"):
		if n is PipeSegment and is_instance_valid(n):
			(n as PipeSegment).show_flow_arrows(on)

## Holds the player motionless above the nearest body until a real physics
## collider actually exists under the spawn point, then drops them onto it.
##
## Deliberately a PHYSICS raycast, not VoxelTool.raycast(): voxel *data* is
## generated for every LOD, but colliders only exist for LODs within
## collision_lod_count, and they arrive seconds after the data on a planet
## this size. Resolving the spawn off a voxel-data hit released the player
## into free fall through terrain that had no collider yet - they sank to
## the planet core and sat there, with no mesh block near them to render
## and the space proxy backface-culled from the inside, which read as "the
## world disappeared once the voxels loaded" (2026-09-06).
## Radius (world metres) of the highest solid voxel along `dir`, read from
## voxel DATA rather than physics. Returns -1.0 if nothing is streamed yet.
##
## Steps down in voxel-sized increments from the highest terrain can reach to
## the lowest, so it is correct for any relief without needing to be retuned
## per body.
func _find_data_surface(planet: Planet, dir: Vector3) -> float:
	if planet == null or planet.terrain == null:
		return -1.0
	var tool := planet.terrain.get_voxel_tool()
	if tool == null:
		return -1.0
	var scale: float = Planet.VOXEL_SCALE
	var relief := planet.max_relief_world()
	var r := planet.radius_world() + relief + scale
	var lowest := planet.radius_world() - relief - scale
	var step: float = maxf(scale, 0.25)
	while r > lowest:
		var local: Vector3 = dir * (r / scale)
		if tool.get_voxel_f(Vector3i(local.round())) < 0.0:
			return r
		r -= step
	return -1.0

func _try_resolve_spawn() -> bool:
	# Re-fetched every attempt, not just once in _ready(): a Planet may not
	# have registered with PlanetPhysics yet on the first physics frame.
	_terrain = PlanetPhysics.get_nearest_terrain(global_position)
	var nearest_planet := PlanetPhysics.get_nearest_body(global_position) as Planet
	if nearest_planet == null:
		return false
	if _spawn_from_save:
		return _try_resolve_loaded_spawn(nearest_planet)
	var planet_center := nearest_planet.global_position
	# Reach derived from the actual nearest body's radius (not a flat
	# constant) so spawn-resolution works correctly regardless of which
	# planet/moon the player starts near, not just one sized like "home."
	var radius_world := nearest_planet.radius_world()
	var radial_up := (global_position - planet_center).normalized()
	if radial_up.length_squared() < 0.5:
		radial_up = Vector3.UP

	# Parked (and re-parked every attempt) clear of the noisiest possible
	# surface so the capsule is never left embedded in terrain that streams
	# in underneath it while we wait.
	var relief := nearest_planet.max_relief_world()

	# Park just above where the GENERATOR says the ground is, not above where
	# the nominal radius says it should be.
	#
	# Voxel data streams far faster than colliders (see main-design.md,
	# "Querying Terrain Colliders vs. Voxel Data"), so the real surface is
	# readable long before anything is walkable. Parking off the nominal
	# radius instead put the capsule up to 180 m above the actual ground on a
	# body with +-80 m relief - and since collision only exists at LOD 0,
	# which only covers `lod_distance` around the viewer, the ground then fell
	# outside the collision region entirely. Terrain data was correct and
	# meshing simply went idle, because nothing near the player needed it.
	var surface_r := _find_data_surface(nearest_planet, radial_up)
	if surface_r <= 0.0:
		# Data not streamed yet on this attempt. Fall back to the NOMINAL
		# radius, not to the highest terrain could possibly reach.
		#
		# The pessimistic guess is actively harmful: collision only exists at
		# LOD 0, which covers `lod_distance` around the viewer, so parking at
		# radius + relief puts the player up to a full relief-height above the
		# real ground and pushes that ground outside the only region that ever
		# generates collision. The player then hovers forever waiting for a
		# collider that will never be built because they are too far from it.
		# Nominal radius keeps them inside LOD 0 of any point on the surface.
		surface_r = radius_world
	global_position = planet_center + radial_up * (surface_r + SPAWN_HOVER_CLEARANCE)
	up_direction = radial_up
	_align_to_up(radial_up)
	_vertical_speed = 0.0
	velocity = Vector3.ZERO
	_move_vel = Vector3.ZERO

	# Probe the entire band terrain can occupy, not a fixed slab around the
	# nominal radius.
	var query := PhysicsRayQueryParameters3D.create(
		global_position + radial_up * SPAWN_PROBE_RISE,
		planet_center + radial_up * (radius_world - relief - SPAWN_PROBE_DEPTH))
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_spawn_wait_frames += 1
		# Every second of waiting, not every frame: this is the symptom of every
		# generation problem so far, and the data-block count says whether the
		# generator is working at all or producing nothing.
		if _spawn_wait_frames % 60 == 0:
			var node := nearest_planet.terrain_node() as VoxelLodTerrain
			TerrainLog.write("spawn", "waiting %ds  data_blocks=%d  probe_from_r=%.1f surface_r=%.1f" % [
				_spawn_wait_frames / 60,
				node.debug_get_data_block_count() if node != null else -1,
				global_position.distance_to(planet_center), surface_r])
		if _spawn_wait_frames >= SPAWN_WAIT_MAX_FRAMES:
			TerrainLog.write("spawn", "GAVE UP after %d frames - no collider ever appeared" % _spawn_wait_frames)
			# Last-resort bail-out so a generator failure can't strand the
			# player hovering above the planet with no way to notice.
			push_warning("Player spawn: no terrain collider after %d physics frames, dropping in anyway." % _spawn_wait_frames)
			_spawn_resolved = true
			return true
		return false

	global_position = (hit.position as Vector3) + radial_up * SPAWN_SURFACE_CLEARANCE
	_align_to_up(radial_up)
	_spawn_resolved = true
	TerrainLog.write_fields("spawn", "resolved after %d waiting frames" % _spawn_wait_frames, {
		"body": nearest_planet.name,
		"landed_radius": global_position.distance_to(planet_center),
		"nominal_radius": radius_world,
		"offset_from_nominal": global_position.distance_to(planet_center) - radius_world,
		"relief_band": relief,
	})
	return true

## Spawn path for a loaded save: the player's position is already known, so
## unlike _try_resolve_spawn() this must NOT move them - it only waits until
## terrain physically exists underneath before handing back control.
##
## Re-parking a loaded player at the surface would quietly undo the save: stand
## on a tower you built, quit, come back at ground level.
func _try_resolve_loaded_spawn(planet: Planet) -> bool:
	var up := (global_position - planet.global_position).normalized()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	up_direction = up
	velocity = Vector3.ZERO
	_move_vel = Vector3.ZERO
	_vertical_speed = 0.0

	var relief := planet.max_relief_world()
	var query := PhysicsRayQueryParameters3D.create(
		global_position + up * SPAWN_PROBE_RISE,
		planet.global_position + up * (planet.radius_world() - relief - SPAWN_PROBE_DEPTH))
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_align_to_up(up)
		_spawn_resolved = true
		return true

	_spawn_wait_frames += 1
	if _spawn_wait_frames >= SPAWN_WAIT_MAX_FRAMES:
		push_warning("Player spawn: loaded position has no collider after %d frames, resuming anyway." % _spawn_wait_frames)
		_align_to_up(up)
		_spawn_resolved = true
		return true
	return false

## True once the player has real ground under them and control has been handed
## over. The loading screen waits on this rather than on a timer, so it covers
## exactly as long as generation actually takes.
func is_spawn_resolved() -> bool:
	return _spawn_resolved

## --- Persistence (see scripts/save/save_manager.gd) ---

func save_state() -> Dictionary:
	return {"transform": SaveManager.transform_to_array(global_transform)}

func load_state(data: Dictionary) -> void:
	global_transform = SaveManager.array_to_transform(data.get("transform", []))
	_spawn_from_save = true
	_spawn_resolved = false
	_spawn_wait_frames = 0

func _physics_process(delta: float) -> void:
	_process_tool_anims(delta)
	_update_suit_o2(delta)
	_scan_cooldown = maxf(_scan_cooldown - delta, 0.0)
	if not _spawn_resolved:
		_try_resolve_spawn()
		return

	if _piloted_ship != null:
		return # PlayerShipController drives the ship independently while piloting.

	if _is_building_ui_open() or _build_mode or _inventory_open or _is_journal_open():
		_clear_interact_target()
	else:
		_update_interact_target()

	if _is_building_ui_open():
		return

	if _build_mode:
		_update_build_ghost()   # the player keeps walking; the ghost follows the crosshair

	# Re-resolve the nearest terrain every frame (not just once in _ready())
	# now that more than one Planet can exist - correct for whichever body
	# the player actually happens to be near right now, null in true open
	# space where dig/build/support raycasts have nothing to act on.
	_terrain = PlanetPhysics.get_nearest_terrain(global_position)

	# Radial planet gravity: "up" always points away from the nearest body's
	# center, not a fixed world axis (and is Vector3.UP/zero-gravity in open
	# space between bodies, PlanetPhysics.get_up()/get_gravity_accel()'s own
	# fallback). Realigning the body's own basis to match (while preserving
	# its current facing, projected flat onto the new tangent plane) is what
	# lets transform.basis-based WASD movement below stay correct anywhere.
	var up := PlanetPhysics.get_up(global_position)
	up_direction = up
	_align_to_up(up)

	# .length() rather than the raw GRAVITY_MAGNITUDE constant: zero in true
	# open space (PlanetPhysics.get_gravity_accel()'s own void fallback), not
	# just near a planet - matters once the player can actually reach open
	# space (ship/jetpack, not built yet), so it's correct from day one
	# rather than needing a second fix later.
	var was_on_floor := is_on_floor()
	var fall_speed := -_vertical_speed
	if not is_on_floor():
		_vertical_speed -= PlanetPhysics.get_gravity_accel(global_position).length() * delta
	elif Input.is_physical_key_pressed(KEY_SPACE) and not DevConsole.is_open:
		_vertical_speed = JUMP_VELOCITY
		if feel != null:
			feel.jump()
	else:
		_vertical_speed = 0.0

	var input_dir := Vector2.ZERO
	var typing := DevConsole.is_open
	if Input.is_physical_key_pressed(KEY_W) and not typing:
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) and not typing:
		input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) and not typing:
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) and not typing:
		input_dir.x += 1.0
	input_dir = input_dir.normalized()

	var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	# Sprint: Shift while moving forward on the ground. Out of air you can't sprint and barely walk.
	sprinting = Input.is_physical_key_pressed(KEY_SHIFT) and input_dir.y < -0.1 and suit_o2 > 0.0 and not _build_menu_open()
	if input_dir != Vector2.ZERO:
		_hud_key("WASD")
	if sprinting:
		_hud_key("Shift")
	var top := (SPRINT_SPEED if sprinting else SPEED) * (lerpf(0.4, 0.15, suffocation) if suit_o2 <= 0.0 else 1.0)
	if dying:
		top = 0.0
	# Momentum instead of instant velocity: quick to start and stop on the ground, sluggish in the air.
	_move_vel -= up * _move_vel.dot(up)                     # stay tangent as "up" turns over the sphere
	var target := move_dir * top
	var rate := (GROUND_ACCEL if move_dir != Vector3.ZERO else GROUND_DECEL) if is_on_floor() else AIR_ACCEL
	_move_vel = _move_vel.move_toward(target, rate * delta)
	velocity = _move_vel + up * _vertical_speed

	move_and_slide()
	if is_on_floor() and not was_on_floor and feel != null:
		feel.land(fall_speed)

	var interact_down := Input.is_physical_key_pressed(KEY_E)
	if not _inventory_open and not _is_journal_open() and interact_down and not _interact_was_down:
		if not _ui_input_on_cooldown():
			_try_interact()
			_hud_key("E")
	_interact_was_down = interact_down

	_dig_miss_cooldown = maxf(_dig_miss_cooldown - delta, 0.0)
	if _dig_held and (_dig_button == 0 or not Input.is_mouse_button_pressed(_dig_button) or not _drill_in_hand()):
		_reset_dig_hold()                    # a release the game never saw (menu opened, focus lost), or the drill left the hand
	if _dig_held and not _inventory_open and not _is_journal_open():
		_dig_hold_time += delta
		if not _dig_spun_up and _dig_hold_time >= DIG_SPINUP_TIME:
			_dig_spun_up = true
			_dig_tick_timer = TerrainDrill.TICK_INTERVAL # fire immediately once spun up
			if feel != null and Inventory.has_tool_equipped(MiningToolItem.id):
				feel.kick("engage")                       # up to speed: the drill snaps forward into the rock
		if _dig_spun_up:
			_dig_tick_timer += delta
			if _dig_tick_timer >= TerrainDrill.TICK_INTERVAL:
				_dig_tick_timer = 0.0
				_dig()

## Rebuilds global_transform.basis so local Y matches `up`, keeping the
## body's current forward direction (projected flat onto the new tangent
## plane) rather than snapshotting/reconstructing from Euler angles - Euler Y
## rotation has no well-defined meaning once the player isn't standing near
## the spawn point's "pole", so this works directly in basis/vector space
## instead. Falls back to the body's right axis if forward is degenerate
## (looking almost exactly along the new up axis).
func _align_to_up(up: Vector3) -> void:
	var current_forward := -global_transform.basis.z
	var tangent_forward := current_forward - up * current_forward.dot(up)
	if tangent_forward.length() < 0.001:
		var current_right := global_transform.basis.x
		tangent_forward = current_right - up * current_right.dot(up)
		if tangent_forward.length() < 0.001:
			return
	var new_basis := Basis.looking_at(tangent_forward.normalized(), up)
	global_transform = Transform3D(new_basis, global_position)

func _raycast() -> VoxelRaycastResult:
	if _terrain == null:
		return null
	var tool := _terrain.get_voxel_tool()
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	# Confirmed empirically (isolated headless VoxelTool test): raycast()
	# converts world-space from/dir to the terrain's LOCAL voxel-grid space
	# internally and returns hit.position already in that local space - so
	# DIG_RANGE (a world-meter distance) is correct to pass here unconverted.
	return TerrainDrill.raycast_close(tool, from, dir, DIG_RANGE)

## do_sphere()'s radius, unlike raycast()'s from/dir/distance, is NOT
## world-space - it's in the terrain's LOCAL voxel-grid units (confirmed via
## the same isolated test: a do_sphere() center/radius passed straight
## through in world units only ever affected the local-space coordinates
## numerically equal to the input, never the world-equivalent local
## position). Terrain.scale (world.gd's VOXEL_SCALE) means 1 local unit !=
## 1 world meter, so a world-meter-intended radius constant (BORE_RADIUS_M,
## BUILD_RADIUS, ...) has to be divided by the terrain's scale before being
## handed to do_sphere(), or the actual dig/build sphere ends up far smaller
## than intended - this was the cause of mining barely denting the surface
## and appearing to "get stuck" after 1-2 voxels, since a too-small sphere
## doesn't fully clear the isosurface at a spot, so the next raycast keeps
## re-hitting almost the same point instead of progressing deeper.
func _local_radius(world_radius: float) -> float:
	var scale := _terrain.scale.x
	return world_radius / scale if scale > 0.0001 else world_radius

func _dig() -> void:
	# The scanner is a TOOL, held in a hand slot like the mining and building
	# tools, and fired the same way they are - not bound to a global key.
	#
	# It was a global key first, which was wrong twice over: it worked with
	# nothing equipped and in any mode (including piloting a ship, where V is
	# already the camera toggle), and it ignored the tool pattern this project
	# already has. Equipping something and using it is the interaction the rest
	# of the game is built on.
	if not Inventory.has_tool_equipped(MiningToolItem.id):
		return

	var hit := _raycast()
	if hit == null:
		# nothing in reach: the drill spins on air, say so (rate-limited - this runs 20 times a second while held)
		if _dig_miss_cooldown <= 0.0:
			_dig_miss_cooldown = 0.5
			UiSound.play("deny")
			if feel != null:
				feel.kick("deny")
		return

	# Hardness comes from what's under the crosshair; payout from everything
	# the bite actually removed.
	var tool := _terrain.get_voxel_tool()
	var material_index := TerrainDrill.dominant_material_at(tool, hit.position)
	var radius := _local_radius(TerrainDrill.BORE_RADIUS_M)
	var inv := _terrain.global_transform.affine_inverse()
	var aim_local := (inv.basis * -camera.global_transform.basis.z).normalized()
	# bite exactly where the crosshair meets the rock, not at the hit voxel: smooth, centred, follows the aim
	var surface := TerrainDrill.surface_point(tool, inv * camera.global_position, aim_local, hit.position)
	var center := TerrainDrill.bite_center(surface, aim_local, radius)
	# a bite that removes nothing for a few ticks in a row (the face sits just outside the cut) pushes in deeper
	# until something comes away, so the drill can never sit there spinning on a surface it can't reach
	if _dig_empty_bites >= 3:
		center += aim_local * radius * minf(0.25 * float(_dig_empty_bites - 2), 1.0)
	var removed := TerrainDrill.bite(tool, center, radius, TerrainDrill.strength_for(material_index))
	_dig_empty_bites = 0 if not removed.is_empty() else _dig_empty_bites + 1
	var scale := _terrain.scale.x
	var paid := TerrainDrill.payout(_yield_carry, removed, scale * scale * scale)
	for item_id: String in paid:
		Inventory.add(item_id, paid[item_id])
	_mine_feedback(hit, not removed.is_empty())

var _dig_miss_cooldown := 0.0
var _dig_empty_bites := 0
var _dig_fx: CPUParticles3D = null

## Every bite answers: the drill shoves forward into the rock (feel.kick "mine"), a puff of dust flies off the face,
## and a thud plays. A bite that removed nothing yet (hard rock not broken through) still gets the shove and a
## quieter, higher tick so the player can tell the drill is working, not dead.
func _mine_feedback(hit: VoxelRaycastResult, removed_something: bool) -> void:
	if feel != null:
		feel.kick("mine")
	UiSound.play("mine_hit" if removed_something else "tick", 1.0 if removed_something else 1.4, 0.06)
	if _dig_fx == null:
		_dig_fx = CPUParticles3D.new()
		_dig_fx.one_shot = true
		_dig_fx.emitting = false
		_dig_fx.amount = 10
		_dig_fx.lifetime = 0.45
		_dig_fx.explosiveness = 1.0
		_dig_fx.direction = Vector3.UP
		_dig_fx.spread = 70.0
		_dig_fx.initial_velocity_min = 1.5
		_dig_fx.initial_velocity_max = 3.5
		_dig_fx.gravity = Vector3.ZERO
		_dig_fx.scale_amount_min = 0.5
		_dig_fx.scale_amount_max = 1.2
		_dig_fx.color = Color(0.72, 0.66, 0.58, 1.0)
		var m := SphereMesh.new()
		m.radius = 0.035
		m.height = 0.07
		m.radial_segments = 6
		m.rings = 3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		m.material = mat
		_dig_fx.mesh = m
		get_tree().current_scene.add_child(_dig_fx)
	var world_pos := _terrain.to_global(Vector3(hit.position) + Vector3(0.5, 0.5, 0.5))
	var away := (camera.global_position - world_pos).normalized()
	_dig_fx.global_position = world_pos
	_dig_fx.direction = away
	_dig_fx.restart()
	_dig_fx.emitting = true

func _build() -> void:
	if not Inventory.has_tool_equipped(MiningToolItem.id):
		return
	if not Inventory.try_remove(BuildRecipe.input_ids[0], BuildRecipe.input_amounts[0]):
		return

	var hit := _raycast()
	if hit == null:
		Inventory.add(BuildRecipe.input_ids[0], BuildRecipe.input_amounts[0])
		return

	var place_pos := Vector3(hit.previous_position) + Vector3(0.5, 0.5, 0.5)
	var tool := _terrain.get_voxel_tool()

	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	tool.set_mode(VoxelTool.MODE_ADD)
	tool.do_sphere(place_pos, _local_radius(BUILD_RADIUS))

	tool.set_mode(VoxelTool.MODE_TEXTURE_PAINT)
	tool.set_texture_index(VoxelMaterials.CONSTRUCTION_BLOCK)
	tool.set_texture_opacity(1.0)
	tool.set_texture_falloff(0.5)
	tool.do_sphere(place_pos, _local_radius(BUILD_RADIUS))

	QuestManager.notify_action("place_block")

## Where the crosshair (screen centre) hits the world within BUILD_MODE_RANGE: terrain collision, foundations and
## buildings alike, never the player. Null when it hits nothing (looking at the sky), and the ghost hides.
func _build_aim() -> Variant:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * BUILD_MODE_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	# terrain whose collider has not streamed in yet still has voxel data
	if _terrain != null:
		var vhit := _terrain.get_voxel_tool().raycast(from, to - from, BUILD_MODE_RANGE, 0xFFFFFFFF)
		if vhit != null:
			return _terrain.to_global(Vector3(vhit.previous_position) + Vector3(0.5, 0.5, 0.5))
	return null

func _snap_build_position(pos: Vector3, force: bool = false) -> Vector3:
	if _build_grid_snap or force:
		return Vector3(pos.x, pos.y, pos.z).floor() + Vector3(0.5, 0.5, 0.5)
	return pos

## Currently selected buildable item, resolved via the build UI's selected
## Recipe -> its output Item. Null while no build recipe is selected.
func _selected_build_item() -> Item:
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null:
		return null
	var recipe: Recipe = build_ui.get_selected_recipe()
	if recipe == null:
		return null
	return Inventory.get_item_def(recipe.output_id)

## Fresh terrain-support check directly below `pos` using the LOCAL up at that exact point.
func _terrain_supports(pos: Vector3) -> bool:
	if _terrain == null:
		return false
	var up := PlanetPhysics.get_up(pos)
	var tool := _terrain.get_voxel_tool()
	var support_hit := tool.raycast(pos + up * 8.0, -up, 20.0, 0xFFFFFFFF)
	return support_hit != null

## Basis tangent to the sphere at `up` (Y = up, -Z = the given reference
## forward projected flat onto that tangent plane), falling back through the
## player's own facing and finally world-right if the reference is degenerate (looking almost exactly along `up`). Same
## projection technique as _align_to_up(), just returning a Basis instead of
## mutating a transform, so it works for ghost/instance placement too.
func _tangent_basis_at(up: Vector3, reference_forward: Vector3) -> Basis:
	var fwd := reference_forward - up * reference_forward.dot(up)
	if fwd.length() < 0.001:
		var own := -global_transform.basis.z
		fwd = own - up * own.dot(up)
		if fwd.length() < 0.001:
			fwd = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	return Basis.looking_at(fwd.normalized(), up)

## Free (unsnapped) placement transform at `pos`: always flat/tangent to the
## local surface right there, using the camera's current facing (continuous,
## re-derived every frame - never stale) as the yaw reference, then the
## ghost's own R-key rotation on top. This is what makes raw-terrain
## fallback placement correct everywhere on the planet, not just near spawn.
func _free_tangent_transform(pos: Vector3) -> Transform3D:
	var up := PlanetPhysics.get_up(pos)
	var tangent := _tangent_basis_at(up, -camera.global_transform.basis.z)
	var final_basis := Basis(up, _build_rotation) * tangent
	return Transform3D(final_basis, pos)

## Where a new foundation snapped against `neighbor` should sit: exactly one
## neighbor-width away along whichever of the neighbor's own 4 cardinal
## directions `raw_pos` is closest to, with the neighbor's EXACT basis (not
## _build_rotation) - every foundation in one connected chain shares the
## same orientation, which is what keeps the whole cluster flat/square to
## itself regardless of how the sphere curves underneath it.
func _foundation_snap_transform(neighbor: Node, raw_pos: Vector3, new_height: float = Foundation.HEIGHT) -> Transform3D:
	var basis: Basis = neighbor.global_transform.basis
	var origin: Vector3 = neighbor.global_position
	var right: Vector3 = basis.x
	var fwd: Vector3 = -basis.z
	var candidates := [
		origin + right * Foundation.SIZE,
		origin - right * Foundation.SIZE,
		origin + fwd * Foundation.SIZE,
		origin - fwd * Foundation.SIZE,
	]
	var best: Vector3 = candidates[0]
	var best_dist := raw_pos.distance_to(best)
	for c in candidates:
		var d := raw_pos.distance_to(c)
		if d < best_dist:
			best_dist = d
			best = c
	# tops line up: a taller block reaches further down, never sticks up above its neighbour
	var neighbor_h: float = neighbor.height if "height" in neighbor else Foundation.HEIGHT
	best += basis.y * (neighbor_h * 0.5 - new_height * 0.5)
	# the R key turns ramps and stairs, in quarter turns so the grid stays square
	var quarter := roundf(_build_rotation / (PI * 0.5)) * (PI * 0.5)
	return Transform3D(Basis(basis.y, quarter) * basis, best)

## Single source of truth for "where/how does the current build ghost sit
## this frame" - also re-run once more at commit time in _place_building()
## to revalidate rather than trusting a possibly one-frame-stale ghost
## transform. Three cases, in priority order:
## 1. Placing a Foundation near an existing one -> snap to its edge, exact
##    orientation match (see _foundation_snap_transform).
## 2. Placing a Foundation with no neighbor nearby -> free tangent placement,
##    origin shifted so the plate's TOP face (not its center) lands on the
##    surface point, since Foundation is center-anchored unlike Building.
## 3. Placing any other building near an existing foundation -> mount flush
##    on its top face, inheriting its orientation, with _build_rotation still
##    free to spin the building's facing on top of that (matters for
##    input/output-side buildings).
## 4. Otherwise -> free tangent placement directly on raw terrain (the
##    explicit fallback for players who don't want to bother with foundations).
func _resolve_build_placement(raw_pos: Vector3, item: Item) -> Dictionary:
	var is_foundation := item != null and item.is_foundation

	if is_foundation:
		var neighbor := FoundationNetwork.find_nearest(raw_pos, FOUNDATION_SNAP_RADIUS)
		if neighbor != null:
			return {"transform": _foundation_snap_transform(neighbor, raw_pos, item.ghost_size.y), "valid": true}
		var xf := _free_tangent_transform(raw_pos)
		xf.origin -= xf.basis.y * (item.ghost_size.y * 0.5)
		return {"transform": xf, "valid": _terrain_supports(raw_pos)}

	var mount := FoundationNetwork.find_nearest(raw_pos, FOUNDATION_MOUNT_RADIUS)
	if mount != null and not ("mountable" in mount and not mount.mountable):
		var mount_basis: Basis = mount.global_transform.basis
		var mount_h: float = mount.height if "height" in mount else Foundation.HEIGHT
		var mount_pos: Vector3 = mount.global_position + mount_basis.y * (mount_h * 0.5)
		var final_basis := Basis(mount_basis.y, _build_rotation) * mount_basis
		return {"transform": Transform3D(final_basis, mount_pos), "valid": true}

	return _ground_aligned_placement(raw_pos, item)

## One ray straight "down" (local up reversed) through `p`, or null. Used to read the ground under a footprint.
func _ground_hit(p: Vector3, up0: Vector3) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(p + up0 * 3.0, p - up0 * 10.0)
	q.exclude = [get_rid()]
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	return h.position if not h.is_empty() else null

## A building with no foundation lies flat ON the ground, not on the sphere's ideal surface: the ground is sampled
## under the footprint (centre + four edge points), the building is tilted to that plane (R still turns it around the
## ground normal), and it is lifted so its base touches the highest sample - it can hover a little over a dip but
## never sinks into a bump. Grid snapping (G) only moves the point the footprint is measured at.
func _ground_aligned_placement(raw_pos: Vector3, item: Item) -> Dictionary:
	var up0 := PlanetPhysics.get_up(raw_pos)
	var ref := _tangent_basis_at(up0, -camera.global_transform.basis.z)
	var half := 0.75 if item == null else maxf(item.ghost_size.x, item.ghost_size.z) * 0.5
	var offs := [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var pts: Array = []
	for o: Vector2 in offs:
		var h: Variant = _ground_hit(raw_pos + ref.x * o.x * half + ref.z * o.y * half, up0)
		if h == null:
			var fallback := _free_tangent_transform(raw_pos)
			return {"transform": fallback, "valid": _terrain_supports(raw_pos)}
		pts.append(h)
	var n: Vector3 = ((pts[1] as Vector3) - (pts[2] as Vector3)).cross((pts[4] as Vector3) - (pts[3] as Vector3))
	if n.length() < 0.0001:
		n = up0
	n = n.normalized()
	if n.dot(up0) < 0.0:
		n = -n
	# never lean past ~50 degrees: a cliff face is not somewhere to stand a machine
	if n.angle_to(up0) > deg_to_rad(50.0):
		n = up0.slerp(n, deg_to_rad(50.0) / n.angle_to(up0))
	var base: Vector3 = pts[0]
	var lift := 0.0
	for p: Vector3 in pts:
		lift = maxf(lift, (p - base).dot(n))
	var basis := Basis(n, _build_rotation) * _tangent_basis_at(n, -camera.global_transform.basis.z)
	return {"transform": Transform3D(basis, base + n * lift), "valid": true}

func _is_pipe_item(item: Item) -> bool:
	return item != null and item.id in ["vacuum_pipe", "merger", "splitter"]

func _pipe_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group("pipe"):
		if node is Node3D and is_instance_valid(node):
			result.append(node)
	for node in get_tree().get_nodes_in_group("building"):
		if node is Node3D and is_instance_valid(node):
			result.append(node)
	return result

func _connection_points(node: Node3D) -> Array[Vector3]:
	if node.has_method("get_connection_points"):
		return node.get_connection_points()
	var basis := node.global_transform.basis
	return [
		node.global_position + basis.x * 0.5,
		node.global_position - basis.x * 0.5,
		node.global_position + basis.z * 0.5,
		node.global_position - basis.z * 0.5,
	]

func _snap_pipe_point(raw_pos: Vector3) -> Vector3:
	var best := raw_pos
	var best_distance := 1.05
	for node in _pipe_nodes():
		for point in _connection_points(node):
			var distance := raw_pos.distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best = point
	var terrain_point: Variant = _snap_pipe_to_terrain(raw_pos)
	if terrain_point != null and raw_pos.distance_to(terrain_point) < best_distance:
		best = terrain_point
	return best

func _snap_pipe_to_terrain(raw_pos: Vector3) -> Variant:
	var terrain := PlanetPhysics.get_nearest_terrain(raw_pos)
	if terrain == null:
		return null
	var hit := terrain.get_voxel_tool().raycast(camera.global_position, -camera.global_transform.basis.z, BUILD_MODE_RANGE, 0xFFFFFFFF)
	if hit == null:
		return null
	return terrain.to_global(Vector3(hit.previous_position) + Vector3(0.5, 0.5, 0.5))

## Plain pipes follow the full 3D line between their ends (they can climb a slope); junctions stay tangent to
## the ground. Pipe transforms put the origin on the build plane, the centreline 0.45 m above it.
func _pipe_transform(start: Vector3, end: Vector3, is_junction: bool) -> Transform3D:
	var direction := end - start
	if direction.length() < 0.01:
		direction = -camera.global_transform.basis.z
	var center := end if is_junction else (start + end) * 0.5
	var up := PlanetPhysics.get_up(center)
	if is_junction:
		return Transform3D(_tangent_basis_at(up, direction), center)
	return Transform3D(_pipe_basis(direction, up), center)

## Basis looking along `direction` (any slope) with its up as close to the planet's as the slope allows.
func _pipe_basis(direction: Vector3, up: Vector3) -> Basis:
	var d := direction.normalized()
	var ref := up if absf(d.dot(up)) < 0.999 else -camera.global_transform.basis.z
	return Basis.looking_at(d, ref)

## Pipe runs (PipeRoute): B toggles STRAIGHT (along the ground axes and straight up, tight 90 degree knees) and
## CURVED (the natural path, wide bends). A run carries on from an open pipe end in that pipe's direction and leaves /
## enters a machine port straight along its axis. An end that is already connected can't take a second pipe.
const PIPE_END_TOL := 0.1

## What is at a build-plane point, as one end of a run: {ok, why, centre (centreline point), dir, kind}.
## kind "free" (ground), "pipe" (an open pipe or junction end) or "port" (a machine port).
func _pipe_end_info(point: Vector3, as_start: bool) -> Dictionary:
	var up := PlanetPhysics.get_up(point)
	var info := {"ok": true, "why": "", "centre": point + up * PipeSegment.PIPE_HEIGHT, "dir": Vector3.ZERO, "kind": "free"}
	for n in get_tree().get_nodes_in_group("pipe"):
		var p := n as PipeSegment
		if p == null or not is_instance_valid(p):
			continue
		var lift := p.global_transform.basis.y.normalized() * PipeSegment.PIPE_HEIGHT
		for q: Vector3 in p.output_ports():
			if q.distance_to(point) < PIPE_END_TOL:
				if not as_start:
					return {"ok": false, "why": "That end is an outlet: start from it", "centre": info.centre}
				if _pipe_input_near(q, p):
					return {"ok": false, "why": "Already connected", "centre": info.centre}
				var d := p.flow_dir() if p._is_modular() else p._outward(q)
				return {"ok": true, "why": "", "centre": q + lift, "dir": d.normalized(), "kind": "pipe"}
		for q: Vector3 in p.input_ports():
			if q.distance_to(point) < PIPE_END_TOL:
				if as_start:
					return {"ok": false, "why": "That end is an inlet: end a pipe on it", "centre": info.centre}
				if _pipe_output_near(q, p) or (p._is_modular() and p._building_at(p.input_point() - p.input_dir() * 0.4) != null):
					return {"ok": false, "why": "Already connected", "centre": info.centre}
				var d := p.input_dir() if p._is_modular() else -p._outward(q)
				return {"ok": true, "why": "", "centre": q + lift, "dir": d.normalized(), "kind": "pipe"}
	for n in get_tree().get_nodes_in_group("building"):
		var b := n as Building
		if b == null or not is_instance_valid(b):
			continue
		for port: Dictionary in b.get_pipe_ports():
			var q: Vector3 = port["point"]
			if q.distance_to(point) >= PIPE_END_TOL:
				continue
			var kind: int = port["kind"]
			var c := q + b.global_transform.basis.y.normalized() * PipeSegment.PIPE_HEIGHT
			if as_start:
				if kind < 0:
					return {"ok": false, "why": "That port takes items in", "centre": c}
				if _pipe_input_near(q, null):
					return {"ok": false, "why": "Already connected", "centre": c}
				return {"ok": true, "why": "", "centre": c, "dir": port["out"], "kind": "port"}
			if kind > 0:
				return {"ok": false, "why": "That port sends items out", "centre": c}
			if _pipe_output_near(q, null):
				return {"ok": false, "why": "Already connected", "centre": c}
			return {"ok": true, "why": "", "centre": c, "dir": -(port["out"] as Vector3), "kind": "port"}
	return info

func _pipe_input_near(point: Vector3, except: Node) -> bool:
	for n in get_tree().get_nodes_in_group("pipe"):
		if n != except and is_instance_valid(n):
			for q: Vector3 in (n as PipeSegment).input_ports():
				if q.distance_to(point) < PIPE_END_TOL:
					return true
	return false

func _pipe_output_near(point: Vector3, except: Node) -> bool:
	for n in get_tree().get_nodes_in_group("pipe"):
		if n != except and is_instance_valid(n):
			for q: Vector3 in (n as PipeSegment).output_ports():
				if q.distance_to(point) < PIPE_END_TOL:
					return true
	return false

## The run from the anchor to `end` (build-plane points), checked: PipeRoute.plan's result, "why" when it can't.
func _plan_pipe_run(start: Vector3, end: Vector3) -> Dictionary:
	var a := _pipe_end_info(start, true)
	if not a.ok:
		return {"ok": false, "why": a.why}
	var e := _pipe_end_info(end, false)
	if not e.ok:
		return {"ok": false, "why": e.why}
	var route := PipeRoute.plan(a.centre, a.dir, a.kind, e.centre, e.dir, e.kind, PlanetPhysics.get_up(start),
			_pipe_curved, -camera.global_transform.basis.z)
	route["end_kind"] = e.kind
	return route

func _place_pipe_or_set_anchor() -> void:
	var aim: Variant = _build_aim()
	if aim == null:
		return
	var item := _selected_build_item()
	if item == null:
		_pipe_anchor_set = false
		return
	_pipe_click(item, _snap_pipe_point(aim))

## One LMB with a pipe item at the (snapped, build-plane) point: start a run, or end it there.
func _pipe_click(item: Item, point: Vector3) -> void:
	if item.id != "vacuum_pipe":
		# mergers and splitters: one click, on the point
		if not _place_pipe(item, point, point):
			_deny_build()
		return
	if not _pipe_anchor_set:
		var a := _pipe_end_info(point, true)
		if not a.ok:
			_deny_build(a.why)
			return
		_pipe_anchor = point
		_pipe_preview_end = point
		_pipe_anchor_set = true
		return
	if point.distance_to(_pipe_anchor) < 0.1:
		return
	var route := _plan_pipe_run(_pipe_anchor, point)
	if not route.ok:
		_deny_build(route.why)
		return
	if _lay_pipe_run(item, route):
		# ending on a machine or another pipe closes the run; on open ground the next run carries on from here
		if route.get("end_kind", "free") != "free":
			_pipe_anchor_set = false
		else:
			_pipe_anchor = point
		return
	_pipe_anchor_set = false

func _deny_build(why: String = "") -> void:
	if feel != null:
		feel.kick("deny")
	UiSound.play("deny", 1.0, 0.25)
	if why != "":
		_build_message = why
		_build_message_until = Time.get_ticks_msec() + 2500
		_refresh_build_hint()

var _build_message := ""
var _last_hint_pairs := ""
var _build_message_until := 0

func _lay_pipe_run(item: Item, route: Dictionary) -> bool:
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null:
		return false
	var recipe: Recipe = build_ui.get_selected_recipe()
	var count := PipeRoute.piece_count(route)
	if recipe == null or not build_ui.can_pay(recipe, count):
		_deny_build("Not enough for %d pipe pieces" % count)
		return false
	var pipes := PipeRoute.build(route, get_tree().current_scene, item.building_scene,
			func(p: Vector3) -> Vector3: return PlanetPhysics.get_up(p))
	for seg in pipes:
		build_ui.pay(recipe)
		PipeNetwork.register(seg.grid_pos, seg)
		SaveManager.mark_placed(seg, item.id)
		seg.show_flow_arrows(true)
		QuestManager.notify_building_placed(item.id)
	PipeSegment.relink_all(get_tree())
	if feel != null:
		feel.kick("place")
	UiSound.play("place")
	return true

## Mergers and splitters (one click).
func _place_pipe(item: Item, start: Vector3, end: Vector3) -> bool:
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null:
		return false
	var recipe: Recipe = build_ui.get_selected_recipe()
	if recipe == null or not build_ui.can_pay(recipe):
		return false
	build_ui.pay(recipe)
	var instance: Node3D = item.building_scene.instantiate()
	get_tree().current_scene.add_child(instance)
	instance.global_transform = _pipe_transform(start, end, true)
	PipeNetwork.register(Vector3i(floori(instance.global_position.x), floori(instance.global_position.y), floori(instance.global_position.z)), instance)
	SaveManager.mark_placed(instance, item.id)
	QuestManager.notify_building_placed(item.id)
	if feel != null:
		feel.kick("place")
	UiSound.play("place")
	PipeSegment.relink_all(get_tree())
	return true

func _update_build_ghost() -> void:
	if _build_ghost == null:
		return
	if _build_message != "" and Time.get_ticks_msec() >= _build_message_until:
		_build_message = ""
		_refresh_build_hint()

	if _dismantle_mode:
		_build_ghost.visible = false
		_hide_pipe_preview()
		_update_dismantle_target()
		return
	var aim: Variant = _build_aim()
	if _build_menu_open() or aim == null:
		_build_ghost.visible = false
		_hide_pipe_preview()
		return

	var item := _selected_build_item()
	_ghost_model_for(item)
	if item != null:
		# the box only shows when there is no model to show (pipes); otherwise it shrinks away
		(_build_ghost.mesh as BoxMesh).size = item.ghost_size if _ghost_model_id == "" else Vector3.ONE * 0.001
	var is_foundation := item != null and item.is_foundation
	var force_snap := item != null and item.force_grid_snap

	var raw_pos: Vector3 = aim
	_set_pipe_arrows(item != null and item.id == "vacuum_pipe")
	if _is_pipe_item(item):
		var pipe_end := _snap_pipe_point(raw_pos)
		_pipe_preview_end = pipe_end
		_build_ghost_material.albedo_color = GHOST_OK
		if _pipe_anchor_set and item.id == "vacuum_pipe":
			# the whole planned run, with arrows the way items will flow; red (and the reason on the HUD) when not
			var route := _plan_pipe_run(_pipe_anchor, pipe_end)
			_pipe_route_preview = route
			if route.get("points", []).size() >= 2:
				_show_pipe_preview(route, route.ok)
			else:
				_hide_pipe_preview()
			_build_ghost.visible = false
			_refresh_build_hint()
			return
		_hide_pipe_preview()
		if item.id == "vacuum_pipe":
			# before the first click: a pipe-sized marker where the run would start, red if nothing may start there
			var up := PlanetPhysics.get_up(pipe_end)
			var a := _pipe_end_info(pipe_end, true)
			var fwd: Vector3 = a.dir if a.dir != Vector3.ZERO else -camera.global_transform.basis.z
			_build_ghost.global_transform = Transform3D(_tangent_basis_at(up, fwd), a.centre)
			(_build_ghost.mesh as BoxMesh).size = Vector3(0.5, 0.5, 0.5)
			_build_ghost_material.albedo_color = GHOST_OK if a.ok else GHOST_BAD
		else:
			_build_ghost.global_transform = _pipe_transform(pipe_end, pipe_end, true)
		_build_ghost.visible = true
		return
	_hide_pipe_preview()
	if not is_foundation and _build_grid_snap:
		# Foundations get their own continuous edge-snap/free-tangent
		# placement below - the old flat voxel-cell snap is a different,
		# now-superseded concept for them specifically.
		raw_pos = _snap_build_position(raw_pos)

	var placement := _resolve_build_placement(raw_pos, item)
	var is_valid: bool = placement.valid
	_build_ghost.visible = true
	if _build_ghost_material != null:
		_build_ghost_material.albedo_color = GHOST_OK if is_valid else GHOST_BAD
	_build_ghost.global_transform = placement.transform

func _place_building() -> void:
	if _build_ghost == null or not _build_ghost.visible:
		return
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null:
		return
	var recipe: Recipe = build_ui.get_selected_recipe()
	if recipe == null:
		return
	var item := Inventory.get_item_def(recipe.output_id)
	if item == null or not item.is_building or item.building_scene == null:
		return

	# Revalidate at commit time rather than trusting a possibly one-frame-
	# stale ghost transform (same principle the old code already applied via
	# a separate _is_build_position_valid() re-check here).
	var placement := _resolve_build_placement(_build_ghost.global_position, item)
	if not placement.valid:
		if feel != null:
			feel.kick("deny")
		UiSound.play("deny", 1.0, 0.25)
		return

	if not build_ui.pay(recipe):                     # a carried copy first, else the materials
		return

	var instance: Node3D = item.building_scene.instantiate()
	get_tree().current_scene.add_child(instance)
	instance.global_transform = placement.transform

	var cell := Vector3i(floori(instance.global_position.x), floori(instance.global_position.y), floori(instance.global_position.z))
	if "grid_pos" in instance:
		instance.grid_pos = cell
	PipeNetwork.register(cell, instance)
	SaveManager.mark_placed(instance, item.id)
	QuestManager.notify_building_placed(item.id)
	if feel != null:
		feel.kick("place")
	UiSound.play("place")

## Ship Core/blocks are equipped in a hand slot and placed with right-click,
## like Minecraft/Space-Engineers hold-and-click - deliberately NOT routed
## through _resolve_build_placement()/the top-down build-mode camera, which
## is built entirely around a tangent plane snapshotted at build-mode entry
## on a STATIC planet surface. A Ship is a moving, rotating rigid body with
## its own independent local grid; reusing that camera/placement model would
## mean fighting it, not reusing it. See ship-system-design.md.
func _equipped_ship_item() -> Item:
	for side in ["left", "right"]:
		var slot: Dictionary = Inventory.get_slot({"kind": "hand", "side": side})
		if slot.item_id == "":
			continue
		var item := Inventory.get_item_def(slot.item_id)
		if item != null and (item.is_ship_core or item.is_ship_block):
			return item
	return null

func _place_ship_item(item: Item, active_camera: Camera3D = null) -> void:
	var space_state := get_world_3d().direct_space_state
	var placement_camera := active_camera if active_camera != null else camera
	var from := placement_camera.global_position
	var to := from + (-placement_camera.global_transform.basis.z) * SHIP_PLACE_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space_state.intersect_ray(query)

	if item.is_ship_core:
		_spawn_ship_core(item, hit, placement_camera)
	elif item.is_ship_block:
		_place_ship_block(item, hit)

## Spawns a brand new Ship with one block (the Core) at its local grid
## origin - this is the anchor every other ship block snaps onto, same
## conceptual role Foundation plays for the planetary grid.
func _spawn_ship_core(item: Item, hit: Dictionary, placement_camera: Camera3D = null) -> void:
	var source_camera := placement_camera if placement_camera != null else camera
	var forward := -source_camera.global_transform.basis.z
	var spawn_pos: Vector3 = hit.position if not hit.is_empty() else source_camera.global_position + forward * SHIP_CORE_SPAWN_DISTANCE
	if not Inventory.try_remove(item.id, 1):
		return

	var ship := Ship.new()
	ship.is_player_ship = true
	get_tree().current_scene.add_child(ship)
	var up := PlanetPhysics.get_up(spawn_pos)
	ship.global_transform = Transform3D(Basis.looking_at(forward, up), spawn_pos)

	var block: ShipBlock = item.block_scene.instantiate()
	ship.add_child(block)
	# the core sits centred on the ship origin (a 2 m core fills cells -2..1, a 1 m vehicle core -1..0)
	var anchor := Ship.anchor_for_center(Vector3.ZERO, block.ship_size())
	block.position = Ship.block_center(anchor, block.ship_size())
	ship.add_block(anchor, block)

func _spawn_debug_ship() -> void:
	if _piloted_ship != null:
		return
	var root := get_tree().current_scene
	if root == null:
		return

	var ship := Ship.new()
	ship.is_player_ship = true
	root.add_child(ship)

	var forward := -camera.global_transform.basis.z
	var up := PlanetPhysics.get_up(global_position)
	var spawn_pos := global_position + forward * 8.0 + up * 12.0
	up = PlanetPhysics.get_up(spawn_pos)
	ship.global_transform = Transform3D(Basis.looking_at(forward, up), spawn_pos)

	var core_scene: PackedScene = preload("res://scenes/ship_core.tscn")
	var cockpit_scene: PackedScene = preload("res://scenes/ship_cockpit.tscn")
	var thruster_scene: PackedScene = preload("res://scenes/ship_thruster.tscn")
	var gyroscope_scene: PackedScene = preload("res://scenes/ship_gyroscope.tscn")
	var hull_scene: PackedScene = preload("res://scenes/ship_hull.tscn")

	var placements: Array[Dictionary] = [
		{"scene": core_scene, "cell": Vector3i.ZERO},
		{"scene": cockpit_scene, "cell": Vector3i(0, 0, -2)},
		{"scene": hull_scene, "cell": Vector3i(0, 0, 2)},
		{"scene": hull_scene, "cell": Vector3i(0, -2, 0)},
		{"scene": hull_scene, "cell": Vector3i(0, 2, 0)},
		{"scene": thruster_scene, "cell": Vector3i(1, 0, 3)},
		{"scene": thruster_scene, "cell": Vector3i(-1, 0, 3)},
		{"scene": thruster_scene, "cell": Vector3i(1, 0, -3), "rotation": Vector3(0.0, PI, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(-1, 0, -3), "rotation": Vector3(0.0, PI, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(2, 0, 1), "rotation": Vector3(0.0, -PI / 2.0, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(2, 0, -1), "rotation": Vector3(0.0, -PI / 2.0, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(-2, 0, 1), "rotation": Vector3(0.0, PI / 2.0, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(-2, 0, -1), "rotation": Vector3(0.0, PI / 2.0, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(0, 2, 1), "rotation": Vector3(PI / 2.0, 0.0, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(0, 2, -1), "rotation": Vector3(PI / 2.0, 0.0, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(0, -2, 1), "rotation": Vector3(-PI / 2.0, 0.0, 0.0)},
		{"scene": thruster_scene, "cell": Vector3i(0, -2, -1), "rotation": Vector3(-PI / 2.0, 0.0, 0.0)},
		{"scene": gyroscope_scene, "cell": Vector3i(0, 0, 4)},
		{"scene": gyroscope_scene, "cell": Vector3i(0, 0, -4)}
	]

	for entry in placements:
		var block: ShipBlock = entry["scene"].instantiate() as ShipBlock
		ship.add_child(block)
		var anchor := Ship.legacy_anchor(entry["cell"])          # this layout counts whole 2 m blocks
		if entry.has("rotation"):
			block.rotation = entry["rotation"]
		if block is ShipThruster:
			block.max_force = 12000.0
		block.position = Ship.block_center(anchor, block.ship_size())
		ship.add_block(anchor, block)


## Places a block against whichever existing player-built Ship the raycast hit, on the ship's 0.5 m grid: the
## block's face lands flush on the face that was hit. Big (2 m) blocks also snap sideways to the 2 m lattice so
## they line up with the classic blocks; small ones go wherever the cursor is. Wheel modules turn so their mount
## faces the block they bolt to. Shift + click removes the block under the cursor.
func _place_ship_block(item: Item, hit: Dictionary) -> void:
	if hit.is_empty():
		return
	var ship := hit.get("collider") as Ship
	if ship == null or not ship.is_player_ship or not ship.is_operational():
		return

	var inv_basis := ship.global_transform.basis.inverse()
	var local_point: Vector3 = inv_basis * (hit.position - ship.global_position)
	var local_normal: Vector3 = inv_basis * hit.get("normal", Vector3.UP)
	var axis := 0
	for i in 3:
		if absf(local_normal[i]) > absf(local_normal[axis]):
			axis = i
	var n := Vector3i.ZERO
	n[axis] = 1 if local_normal[axis] > 0.0 else -1
	if Input.is_key_pressed(KEY_SHIFT):
		var inside := local_point - Vector3(n) * (Ship.CELL_SIZE * 0.5)
		ship.try_remove_block(Vector3i((inside / Ship.CELL_SIZE).floor()))
		return
	if not Inventory.try_remove(item.id, 1):
		return
	var block: ShipBlock = item.block_scene.instantiate()
	if block is ShipWheel:
		# the mount (block -X) faces back into the ship
		var out := Vector3(n)
		if absf(out.y) > 0.5:
			block.queue_free()
			Inventory.add(item.id, 1)
			return
		block.basis = Basis(Vector3.UP, atan2(-out.z, out.x))
	var size := block.ship_size()
	var outside := local_point + Vector3(n) * (Ship.CELL_SIZE * 0.5)
	var cell := Vector3i((outside / Ship.CELL_SIZE).floor())
	var anchor := Vector3i.ZERO
	for i in 3:
		if i == axis:
			anchor[i] = cell[i] if n[i] > 0 else cell[i] - size[i] + 1
		elif size[i] >= Ship.BIG:
			anchor[i] = floori(float(cell[i] + Ship.BIG / 2) / Ship.BIG) * Ship.BIG - Ship.BIG / 2
		else:
			anchor[i] = cell[i] - size[i] / 2
	if not ship.try_add_block(anchor, block):
		block.queue_free()
		Inventory.add(item.id, 1)

func _enter_ship(cockpit: ShipCockpit) -> void:
	var ship := cockpit.ship()
	if ship == null:
		return
	_piloted_ship = ship
	_clear_interact_target()
	velocity = Vector3.ZERO
	_move_vel = Vector3.ZERO
	visible = false
	collision_shape.set_deferred("disabled", true)
	reparent(cockpit, true)
	global_transform = cockpit.global_transform

	_ship_controller = PlayerShipController.new()
	ship.add_child(_ship_controller)
	_ship_controller.ship = ship
	_ship_controller.exit_requested.connect(_exit_ship)
	_ship_controller.activate(cockpit.cockpit_camera(), ship.get_node_or_null("ChaseCamera"))
	var ship_camera := cockpit.cockpit_camera()
	if ship_camera != null:
		ship_camera.far = 1000000.0
		_ship_viewer = VoxelViewer.new()
		_ship_viewer.name = "ShipVoxelViewer"
		_ship_viewer.view_distance = 1024
		_ship_viewer.requires_visuals = true
		_ship_viewer.requires_collisions = true
		ship_camera.add_child(_ship_viewer)
	_refresh_hud()

func _exit_ship() -> void:
	if _piloted_ship == null:
		return
	var ship := _piloted_ship
	reparent(get_tree().current_scene, true)
	visible = true
	global_position = ship.global_position + ship.global_transform.basis.y * 2.0
	collision_shape.set_deferred("disabled", false)
	if _ship_controller != null and is_instance_valid(_ship_controller):
		_ship_controller.queue_free()
	_ship_controller = null
	if _ship_viewer != null and is_instance_valid(_ship_viewer):
		_ship_viewer.queue_free()
		_ship_viewer = null
	_piloted_ship = null
	camera.current = true
	_refresh_hud()

func _try_interact() -> void:
	if _is_building_ui_open():
		return
	if _targeted_cockpit != null and is_instance_valid(_targeted_cockpit):
		_enter_ship(_targeted_cockpit)
	elif _targeted_building != null and is_instance_valid(_targeted_building):
		if _targeted_building is ShipGarage:
			(_targeted_building as ShipGarage).link_ship(_nearest_player_ship())
		_targeted_building.interact()

func _nearest_player_ship() -> Ship:
	var nearest: Ship = null
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group("ship"):
		var ship := node as Ship
		if ship == null or not ship.is_player_ship:
			continue
		var distance := global_position.distance_to(ship.global_position)
		if distance < nearest_distance:
			nearest = ship
			nearest_distance = distance
	return nearest

## Forward raycast (not just proximity) so E targets whatever the player is
## actually looking at, not just the first building found within range - a
## plain distance check could open the wrong building when several are close
## together or the targeted one is behind the player.
func _raycast_building() -> Building:
	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * INTERACT_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var collider = result.get("collider")
	return collider if collider is Building else null

## Same forward-raycast shape as _raycast_building(), separate call rather
## than a shared/branching one so neither building nor ship targeting risks
## regressing the other.
func _raycast_cockpit() -> ShipCockpit:
	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * INTERACT_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var collider := result.get("collider") as Ship
	if collider == null:
		return null
	var hit_position: Vector3 = result.get("position", Vector3.ZERO)
	var closest: ShipCockpit = null
	var closest_distance := INF
	for child in collider.get_children():
		if child is ShipCockpit:
			var distance: float = child.global_position.distance_to(hit_position)
			if distance < closest_distance:
				closest_distance = distance
				closest = child
	return closest if closest_distance <= Ship.BLOCK_SIZE else null

func _update_interact_target() -> void:
	var building := _raycast_building()
	if building != _targeted_building:
		if _targeted_building != null and is_instance_valid(_targeted_building):
			_targeted_building.set_highlighted(false)
		_targeted_building = building
		if _targeted_building != null:
			_targeted_building.set_highlighted(true)
	_targeted_cockpit = _raycast_cockpit() if building == null else null
	var prompt := get_tree().get_first_node_in_group("interact_prompt")
	if prompt == null:
		return
	if _targeted_building != null:
		prompt.show_prompt("E", _targeted_building.call("prompt_text") if _targeted_building.has_method("prompt_text") else "Open " + _display_name_of(_targeted_building))
	elif _targeted_cockpit != null:
		prompt.show_prompt("E", "Take the controls" if _targeted_cockpit.sealed else "Take the driver seat")
	else:
		prompt.hide_prompt()

## The player-facing name of a placed thing (its item's display name), never the scene node's name.
func _display_name_of(node: Node) -> String:
	var id: String = String(node.get_meta(SaveManager.ITEM_ID_META, ""))
	var item := Inventory.get_item_def(id) if id != "" else null
	if item != null:
		return item.display_name
	return String(node.name).rstrip("0123456789").capitalize()

func _hud_key(key: String) -> void:
	var hud := get_tree().get_first_node_in_group("compact_hud")
	if hud != null:
		hud.key_used(key)

func _clear_interact_target() -> void:
	if _targeted_building != null and is_instance_valid(_targeted_building):
		_targeted_building.set_highlighted(false)
	_targeted_building = null
	_targeted_cockpit = null
	var prompt := get_tree().get_first_node_in_group("interact_prompt")
	if prompt != null:
		prompt.hide_prompt()

func _is_building_ui_open() -> bool:
	var building_ui := get_tree().get_first_node_in_group("building_ui")
	return building_ui != null and building_ui.is_open()

func _close_building_ui() -> void:
	var building_ui := get_tree().get_first_node_in_group("building_ui")
	if building_ui != null:
		building_ui.close()

## Pings the resource scanner and puts markers on screen.
##
## Scans from the PLAYER, not the camera: the readout answers "how far do I have
## to walk", and in build mode the camera is somewhere overhead.
func _scan_for_ore() -> void:
	_scan_anim_left = 1.5
	var open_hud := get_tree().get_first_node_in_group("scanner_hud")
	if open_hud != null and open_hud.call("is_radar_open"):
		# Radar already up: the scanner button locks the trace on the centre line.
		if feel != null:
			feel.kick("scan")
		open_hud.call("lock_press")
		return
	if feel != null and _scan_cooldown <= 0.0:
		feel.kick("scan")
	if _scan_cooldown > 0.0:
		return
	# A scan is ~30-80 ms of generator work, so it must not be spammable by
	# holding the fire button.
	_scan_cooldown = SCAN_COOLDOWN
	var hud := get_tree().get_first_node_in_group("scanner_hud")
	if hud == null:
		return
	var body := PlanetPhysics.get_nearest_body(global_position)
	if body == null or not body.has_method("get"):
		return
	var terrain = body.get("terrain")
	var celestial = body.get("body")
	if terrain == null or celestial == null:
		return
	# Material index -> ore id. Doubles as the filter for what counts as ore;
	# without it a scan reports the ground itself, since stone and bedrock share
	# the same material channel.
	var names := {}
	var depths := {}
	for ore in celestial.ore_types:
		names[ore.material_index] = ore.id
		depths[ore.id] = Vector2(ore.depth_min, ore.depth_max)
	hud.call("scan_from", terrain, global_position, names, depths)

## --- Held tool animation --------------------------------------------------
## The drill's chuck and bit spin while the trigger is held (and the tool shakes a little); the scanner's dish
## spins for a moment after each scan; the build tool's alignment rings turn while it is in hand.
var _scan_anim_left := 0.0

## --- Helmet lamp (F) -------------------------------------------------------
## A spot on the helmet for night and caves, plus a faint always-on chest fill so the held tools never read as
## black shapes against a dark world. Built in code so player.tscn stays the body.
var _lamp: SpotLight3D
var _fill: OmniLight3D

func _build_lamp() -> void:
	_lamp = SpotLight3D.new()
	_lamp.light_color = Color("fff1dc")
	_lamp.light_energy = 3.0
	_lamp.spot_range = 32.0
	_lamp.spot_angle = 30.0
	_lamp.spot_attenuation = 0.8
	_lamp.position = Vector3(0.12, 0.08, 0.0)
	_lamp.visible = false
	camera.add_child(_lamp)
	_fill = OmniLight3D.new()
	_fill.light_color = Color("dfe8ee")
	_fill.light_energy = 0.45
	_fill.omni_range = 1.1
	_fill.position = Vector3(0.0, -0.15, -0.2)
	camera.add_child(_fill)

func toggle_lamp() -> void:
	_lamp.visible = not _lamp.visible
	if feel != null:
		feel.kick("deny" if not _lamp.visible else "scan")

func _tool_player(tool_name: String) -> AnimationPlayer:
	var node := viewmodel.get_node_or_null(tool_name)
	if node == null:
		return null
	var players := node.find_children("*", "AnimationPlayer", true, false)
	return players[0] if not players.is_empty() else null

func _run_tool_anim(tool_name: String, running: bool, speed: float = 1.0) -> void:
	var p := _tool_player(tool_name)
	if p == null:
		return
	var anim := ""
	for a in p.get_animation_list():
		if String(a).begins_with("Working"):
			anim = a
	if anim == "":
		return
	p.speed_scale = speed
	if running:
		if not p.is_playing():
			p.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
			p.play(anim)
	elif p.is_playing():
		p.pause()

func _process_tool_anims(delta: float) -> void:
	if viewmodel == null or not viewmodel.visible:
		return
	var drilling := _dig_held and Inventory.has_tool_equipped(MiningToolItem.id)
	# 0 -> 1 over the spin-up, then stays 1 while held: drives the bit's speed, the shake and the wind-up pose
	var spin := clampf(_dig_hold_time / DIG_SPINUP_TIME, 0.0, 1.0) if drilling else 0.0
	_run_tool_anim("MiningTool", drilling, lerpf(0.2, 1.0, spin * spin))
	_scan_anim_left = maxf(_scan_anim_left - delta, 0.0)
	_run_tool_anim("ScannerTool", _scan_anim_left > 0.0)
	_run_tool_anim("BuildTool", Inventory.has_tool_equipped(BuildingToolItem.id))
	# drilling kicks: a small, fast shake of the held drill (the feel node places the tool, see first_person_feel.gd)
	var shake := Vector3.ZERO
	if drilling:
		# a stronger rattle while it winds up than once it is boring: the shake is the "it is working" signal
		var amp := lerpf(0.0035, 0.007, spin) if not _dig_spun_up else 0.0045
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(0, 1)) * amp
	if feel != null:
		feel.set_shake(shake)
		feel.set_windup(spin if (drilling and not _dig_spun_up) else 0.0)
		feel.set_lunge(1.0 if (drilling and _dig_spun_up) else 0.0)

## --- Suit oxygen -------------------------------------------------------------
## The suit carries SUIT_O2_MAX seconds of air and uses it outside. It refills near a Ship Garage (base life
## support) and in a SEALED cockpit, from that ship's oxygen tanks (the pilot also breathes from them there). An
## open driver seat gives nothing: the driver lives on the suit. Out of air you can barely move.
const SUIT_O2_MAX := 300.0
const SUIT_REFILL_RATE := 30.0      # seconds of air per second while refilling
const BASE_AIR_RANGE := 10.0
var suit_o2 := SUIT_O2_MAX
## True while the suit is filling up (read by the HUD).
var o2_refilling := false

func _update_suit_o2(delta: float) -> void:
	var refill := false
	var cockpit := get_parent() as ShipCockpit
	if _piloted_ship != null and cockpit != null and cockpit.sealed:
		var breathe := _piloted_ship.take_oxygen(delta)
		if breathe >= delta * 0.99:
			var want := minf(SUIT_REFILL_RATE * delta, SUIT_O2_MAX - suit_o2)
			suit_o2 += _piloted_ship.take_oxygen(want)
			refill = true
	elif _piloted_ship == null:
		for g in get_tree().get_nodes_in_group("building"):
			if g is ShipGarage and global_position.distance_to((g as Node3D).global_position) < BASE_AIR_RANGE:
				suit_o2 = minf(suit_o2 + SUIT_REFILL_RATE * delta, SUIT_O2_MAX)
				refill = true
				break
	if not refill and o2_hose != null:
		if not is_instance_valid(o2_hose) or global_position.distance_to(o2_hose.global_position) > OxygenPost.HOSE_LENGTH + 1.0:
			disconnect_hose(true)          # walked too far: the hose pops out
		else:
			suit_o2 = minf(suit_o2 + SUIT_REFILL_RATE * delta, SUIT_O2_MAX)
			refill = true
	if not refill:
		suit_o2 = maxf(suit_o2 - delta, 0.0)
	o2_refilling = refill and suit_o2 < SUIT_O2_MAX
	# Out of air: the clock runs. Air back (refill) winds it down fast. At the end of it you die.
	if suit_o2 <= 0.0 and not refill:
		if not dying:
			o2_empty_time += delta
			if o2_empty_time >= SUFFOCATE_SECONDS:
				dying = true
				dying_time = 0.0
	elif not dying:
		o2_empty_time = maxf(o2_empty_time - delta * 4.0, 0.0)
	suffocation = clampf(o2_empty_time / SUFFOCATE_SECONDS, 0.0, 1.0)
	if dying:
		dying_time += delta
		if dying_time >= 3.5:
			_respawn_after_death()

## The Oxygen Post the suit is plugged into, or null.
var o2_hose: Node3D = null

func connect_hose(post: Node3D) -> void:
	if o2_hose != null and is_instance_valid(o2_hose):
		o2_hose.call("set_connected", false)
	o2_hose = post
	post.call("set_connected", true)
	UiSound.play("confirm")

func disconnect_hose(snapped: bool = false) -> void:
	if o2_hose != null and is_instance_valid(o2_hose):
		o2_hose.call("set_connected", false)
	o2_hose = null
	UiSound.play("warn" if snapped else "back")

## Seconds from the first empty breath to death.
const SUFFOCATE_SECONDS := 25.0
var o2_empty_time := 0.0
## 0..1 progress towards suffocating (read by SuffocationFX).
var suffocation := 0.0
var dying := false
var dying_time := 0.0

## After the death fade: refill the suit and stand back at the landing spot. Inventory is kept.
func _respawn_after_death() -> void:
	dying = false
	dying_time = 0.0
	o2_empty_time = 0.0
	suffocation = 0.0
	suit_o2 = SUIT_O2_MAX
	if _piloted_ship != null:
		return          # in a ship: just give the air back
	var body := PlanetPhysics.get_nearest_body(global_position) as Planet
	if body == null:
		return
	var dir := body.suggested_spawn_direction()
	if dir == Vector3.ZERO:
		dir = (global_position - body.global_position).normalized()
	global_position = body.global_position + dir * (body.radius_world() + body.max_relief_world() + 60.0)
	_move_vel = Vector3.ZERO
	_vertical_speed = 0.0
	velocity = Vector3.ZERO
	_spawn_from_save = false
	_spawn_resolved = false
	_spawn_wait_frames = 0

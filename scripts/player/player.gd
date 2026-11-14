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
const DIG_SPINUP_TIME := 0.2

const BuildRecipe: Recipe = preload("res://data/recipes/build_block.tres")
const MiningToolItem: Item = preload("res://data/items/mining_tool.tres")
const BuildingToolItem: Item = preload("res://data/items/building_tool.tres")
const ScannerToolItem: Item = preload("res://data/items/scanner_tool.tres")
const SidearmItem: Item = preload("res://data/items/rivet_gun.tres")
const SidearmAmmo: AmmoType = preload("res://data/ammo_types/iron_piercing_ammo.tres")
## Sidearm (design M25): one rivet per SIDEARM_INTERVAL while the trigger is held, from pierce ammo in the bag.
const SIDEARM_INTERVAL := 0.22
var _sidearm_cool := 0.0

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
## Health, falls, suffocation, death/respawn (scripts/player/player_vitals.gd).
var vitals: PlayerVitals = null
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

## Build mode: the player walks and looks as normal; the build menu (mouse free) opens on entry and on Q, and
## closes once a building is picked. While it is open the world gets no clicks.
var _build_mode := false
## Dismantle sub-mode of the build tool (X): aim at something you placed, hold LMB, get its cost + contents back.
var _dismantle := false
var _dismantle_held := false
var _dismantle_hold := 0.0
var _dismantle_target: Node3D = null
const DISMANTLE_TIME := 0.45
var _build_grid_snap := true
var _build_rotation := 0.0
var _build_ghost: MeshInstance3D = null
var _build_ghost_material: StandardMaterial3D = null
var _pipe_anchor: Vector3 = Vector3.ZERO
var _pipe_anchor_set := false
var _pipe_preview_end: Vector3 = Vector3.ZERO
## Pipe build mode: false = STRAIGHT (level or vertical runs), true = FREE (any angle). B toggles it.
var _pipe_free_mode := false

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.far = 1000000.0
	_terrain = PlanetPhysics.get_nearest_terrain(global_position)
	_spawn_resolved = false
	Inventory.changed.connect(_update_viewmodel)
	feel = FirstPersonFeel.new()
	feel.name = "Feel"
	add_child(feel)
	feel.setup(self, camera, viewmodel)
	vitals = PlayerVitals.new()
	vitals.name = "Vitals"
	add_child(vitals)
	vitals.setup(self)
	_build_lamp()
	_update_viewmodel()
	_refresh_hud()

func _update_viewmodel() -> void:
	# the held tool: one model per tool item (data/models/tools), shown in the first-person view
	var shown := false
	if viewmodel.get_node_or_null("Sidearm") == null:
		_build_sidearm_model()
	for pair in [["MiningTool", MiningToolItem], ["ScannerTool", ScannerToolItem], ["BuildTool", BuildingToolItem], ["Sidearm", SidearmItem]]:
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
		if _dismantle and event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_dismantle_held = event.pressed
				if not event.pressed:
					_dismantle_hold = 0.0
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_set_dismantle(false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
			_pick_what_i_look_at()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
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
			if event.keycode == KEY_X:
				_set_dismantle(not _dismantle)
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				var build_ui := get_tree().get_first_node_in_group("build_ui")
				if build_ui != null and build_ui.select_hotbar(event.keycode - KEY_1):
					_set_dismantle(false)
					_pipe_anchor_set = false
					UiSound.play("click")
			elif event.keycode == KEY_B and _is_pipe_item(_selected_build_item()):
				_pipe_free_mode = not _pipe_free_mode
			elif event.keycode == KEY_G:
				_build_grid_snap = not _build_grid_snap
			elif event.keycode == KEY_R:
				_build_rotation = wrapf(_build_rotation + BUILD_ROTATE_STEP, 0.0, TAU)
			elif event.keycode == KEY_Q:
				_open_build_menu()
			_refresh_build_hint()
		# mouse motion falls through to the normal look below

	if event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dig_held = event.pressed
			if not event.pressed:
				_reset_dig_hold()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var ship_item := _equipped_ship_item()
			if ship_item != null:
				_place_ship_item(ship_item)
			else:
				_build()
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			_pick_what_i_look_at()

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

func _reset_dig_hold() -> void:
	_dig_held = false
	_dig_hold_time = 0.0
	_dig_spun_up = false
	_dig_tick_timer = 0.0

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
	_set_dismantle(false)
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
		hud.set_context_hints([])
		return
	if _dismantle:
		hud.set_context_hints([["Hold LMB", "Dismantle"], ["X", "Back to building"], ["RMB", "Back"]])
		return
	var item := _selected_build_item()
	var pairs: Array = [["LMB", "Place " + (item.display_name if item != null else "")], ["R/Wheel", "Rotate"],
		["G", "Grid " + ("on" if _build_grid_snap else "off")], ["1-9", "Hotbar"], ["X", "Dismantle"],
		["Q", "Menu"], ["RMB", "Done"]]
	if item != null and item.id == "vacuum_pipe":
		pairs = [["LMB", "Start / end pipe" if not _pipe_anchor_set else "End pipe here"],
			["B", "Free angle" if _pipe_free_mode else "Straight"], ["Q", "Menu"], ["RMB", "Cancel" if _pipe_anchor_set else "Done"]]
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
	return {
		"transform": SaveManager.transform_to_array(global_transform),
		"vitals": vitals.save_state() if vitals != null else {},
		"suit_o2": suit_o2,
	}

func load_state(data: Dictionary) -> void:
	global_transform = SaveManager.array_to_transform(data.get("transform", []))
	if vitals != null:
		vitals.load_state(data.get("vitals", {}))
	suit_o2 = clampf(float(data.get("suit_o2", SUIT_O2_MAX)), 0.0, SUIT_O2_MAX)
	_spawn_from_save = true
	_spawn_resolved = false
	_spawn_wait_frames = 0

func _physics_process(delta: float) -> void:
	_process_tool_anims(delta)
	# air is only used once the player is standing in the world, not while a save streams in
	if _spawn_resolved and not (vitals != null and vitals.dead):
		_update_suit_o2(delta)
	_scan_cooldown = maxf(_scan_cooldown - delta, 0.0)
	if not _spawn_resolved:
		_try_resolve_spawn()
		if _spawn_resolved and vitals != null and not vitals.has_respawn:
			vitals.remember_respawn(global_transform)
		return

	if vitals != null and vitals.dead:
		velocity = Vector3.ZERO
		return

	if _piloted_ship != null:
		return # PlayerShipController drives the ship independently while piloting.

	if _is_building_ui_open() or _build_mode or _inventory_open or _is_journal_open():
		_clear_interact_target()
	else:
		_update_interact_target()

	if _is_building_ui_open():
		return

	if _build_mode and _dismantle:
		_update_dismantle(delta)
	elif _build_mode:
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
	elif Input.is_physical_key_pressed(KEY_SPACE):
		_vertical_speed = JUMP_VELOCITY
		if feel != null:
			feel.jump()
	else:
		_vertical_speed = 0.0

	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1.0
	input_dir = input_dir.normalized()

	var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	# Sprint: Shift while moving forward on the ground. Out of air you can't sprint and barely walk.
	sprinting = Input.is_physical_key_pressed(KEY_SHIFT) and input_dir.y < -0.1 and suit_o2 > 0.0 and not _build_menu_open()
	if input_dir != Vector2.ZERO:
		_hud_key("WASD")
	if sprinting:
		_hud_key("Shift")
	var top := (SPRINT_SPEED if sprinting else SPEED) * (0.4 if suit_o2 <= 0.0 else 1.0)
	# Momentum instead of instant velocity: quick to start and stop on the ground, sluggish in the air.
	_move_vel -= up * _move_vel.dot(up)                     # stay tangent as "up" turns over the sphere
	var target := move_dir * top
	var rate := (GROUND_ACCEL if move_dir != Vector3.ZERO else GROUND_DECEL) if is_on_floor() else AIR_ACCEL
	_move_vel = _move_vel.move_toward(target, rate * delta)
	velocity = _move_vel + up * _vertical_speed

	move_and_slide()
	if is_on_floor() and not was_on_floor:
		if feel != null:
			feel.land(fall_speed)
		if vitals != null:
			vitals.on_landed(fall_speed)

	var interact_down := Input.is_physical_key_pressed(KEY_E)
	if not _inventory_open and not _is_journal_open() and interact_down and not _interact_was_down:
		if not _ui_input_on_cooldown():
			_try_interact()
			_hud_key("E")
	_interact_was_down = interact_down

	if _dig_held and not _inventory_open and not _is_journal_open():
		_dig_hold_time += delta
		if not _dig_spun_up and _dig_hold_time >= DIG_SPINUP_TIME:
			_dig_spun_up = true
			_dig_tick_timer = TerrainDrill.TICK_INTERVAL # fire immediately once spun up
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
	return tool.raycast(from, dir, DIG_RANGE, 0xFFFFFFFF)

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
	if Inventory.has_tool_equipped(ScannerToolItem.id):
		_scan_for_ore()
		return
	if Inventory.has_tool_equipped(SidearmItem.id):
		_fire_sidearm()
		return
	if not Inventory.has_tool_equipped(MiningToolItem.id):
		return

	var hit := _raycast()
	if hit == null:
		return

	# Hardness comes from what's under the crosshair; payout from everything
	# the bite actually removed.
	var tool := _terrain.get_voxel_tool()
	var material_index := TerrainDrill.dominant_material_at(tool, hit.position)
	var radius := _local_radius(TerrainDrill.BORE_RADIUS_M)
	var aim_local := _terrain.global_transform.basis.inverse() * -camera.global_transform.basis.z
	var removed := TerrainDrill.bite(tool, TerrainDrill.bite_center(hit.position, aim_local, radius),
		radius, TerrainDrill.strength_for(material_index))
	var scale := _terrain.scale.x
	var paid := TerrainDrill.payout(_yield_carry, removed, scale * scale * scale)
	# feedback: dust tinted by what is being cut, sparks on ore, the grind of the bit (pitched by hardness)
	var hit_world := _terrain.to_global(Vector3(hit.position) + Vector3.ONE * 0.5)
	var hit_up := PlanetPhysics.get_up(hit_world)
	var ore_item: String = TerrainDrill.ITEM_BY_MATERIAL.get(material_index, "stone")
	var tint := Color(0.5, 0.48, 0.45)
	var def := Inventory.get_item_def(ore_item)
	if def != null and ore_item != "stone":
		tint = def.debug_color
	if Engine.get_process_frames() % 3 == 0:
		WorldFx.burst("dust", hit_world, hit_up, tint)
		if ore_item != "stone":
			WorldFx.burst("sparks", hit_world, hit_up)
	WorldFx.sound("drill", hit_world, 1.3 / sqrt(VoxelMaterials.hardness_for(material_index)), 0.14)
	for item_id: String in paid:
		var took := Inventory.add(item_id, paid[item_id])
		GameEvents.item_mined.emit(item_id, took, self)
		if took < int(paid[item_id]):
			_inventory_full_feedback()

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

	GameEvents.act("place_block")

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
		return {"transform": xf, "valid": _terrain_supports(raw_pos), "reason": "Needs solid ground under it"}

	var mount := FoundationNetwork.find_nearest(raw_pos, FOUNDATION_MOUNT_RADIUS)
	if mount != null and not ("mountable" in mount and not mount.mountable):
		var mount_basis: Basis = mount.global_transform.basis
		var mount_h: float = mount.height if "height" in mount else Foundation.HEIGHT
		var mount_pos: Vector3 = mount.global_position + mount_basis.y * (mount_h * 0.5)
		var final_basis := Basis(mount_basis.y, _build_rotation) * mount_basis
		return {"transform": Transform3D(final_basis, mount_pos), "valid": true}

	var xf := _free_tangent_transform(raw_pos)
	return {"transform": xf, "valid": _terrain_supports(raw_pos), "reason": "Needs solid ground under it"}

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

## Pipe build modes (B toggles): STRAIGHT keeps a pipe exactly level or exactly vertical, FREE lets it run at any
## angle (up a slope, diagonally). Where a new pipe leaves the end of an existing one at another angle, a knee is
## built bent to exactly that angle.
func _pipe_constrain(anchor: Vector3, end: Vector3) -> Vector3:
	if _pipe_free_mode:
		return end
	var up := PlanetPhysics.get_up(anchor)
	var d := end - anchor
	var vertical := d.dot(up)
	var level := d - up * vertical
	if absf(vertical) > level.length():
		return anchor + up * vertical
	return anchor + level

func _place_pipe_or_set_anchor() -> void:
	var aim: Variant = _build_aim()
	if aim == null:
		return
	var raw_pos: Vector3 = aim
	var point := _snap_pipe_point(raw_pos)
	if not _pipe_anchor_set:
		_pipe_anchor = point
		_pipe_preview_end = point
		_pipe_anchor_set = true
		return
	var item := _selected_build_item()
	if item == null:
		_pipe_anchor_set = false
		return
	var end := _snap_pipe_point(raw_pos)
	if item.id == "vacuum_pipe":
		end = _pipe_constrain(_pipe_anchor, end)
	if end.distance_to(_pipe_anchor) < 0.1:
		return
	if _place_pipe(item, _pipe_anchor, end) and item.id == "vacuum_pipe":
		# keep building: the next pipe starts where this one ended (a knee is added if it turns)
		_pipe_anchor = end
		return
	_pipe_anchor_set = false

## The plain pipe whose output end is at `point` (build-plane point), if any.
func _pipe_ending_at(point: Vector3) -> PipeSegment:
	for n in get_tree().get_nodes_in_group("pipe"):
		var p := n as PipeSegment
		if p == null or not is_instance_valid(p) or not p._is_modular():
			continue
		var pts := p.get_connection_points()
		if pts[1].distance_to(point) < 0.05:
			return p
	return null

func _place_pipe(item: Item, start: Vector3, end: Vector3) -> bool:
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null:
		return false
	var recipe: Recipe = build_ui.get_selected_recipe()
	if recipe == null:
		return false
	for i in recipe.input_ids.size():
		if Inventory.get_count(recipe.input_ids[i]) < recipe.input_amounts[i]:
			return false
	var is_junction := item.id != "vacuum_pipe"
	# Plain pipes are laid on their centreline (0.45 m above the build plane). A pipe started on the end of an
	# existing one continues from that pipe's centreline; if it turns, a knee takes one leg from each.
	var upstream: PipeSegment = null if is_junction else _pipe_ending_at(start)
	var c_start := upstream.output_point() if upstream != null else start + PlanetPhysics.get_up(start) * PipeSegment.PIPE_HEIGHT
	var c_end := end + PlanetPhysics.get_up(end) * PipeSegment.PIPE_HEIGHT
	var leg := 0.0 if is_junction else PipeSegment.knee_leg_for(upstream, c_start, c_end)
	if leg < 0.0:
		return false                                     # too sharp to bend, or no room for the bend
	for i in recipe.input_ids.size():
		Inventory.try_remove(recipe.input_ids[i], recipe.input_amounts[i])
	var instance: Node3D = item.building_scene.instantiate()
	get_tree().current_scene.add_child(instance)
	if instance is PipeSegment and not is_junction:
		var segment := instance as PipeSegment
		PipeSegment.lay(segment, c_start, c_end, upstream if leg > 0.0 else null, leg, PlanetPhysics.get_up(c_end))
		segment.grid_pos = Vector3i(floori(start.x), floori(start.y), floori(start.z))
	else:
		instance.global_transform = _pipe_transform(start, end, is_junction)
	PipeNetwork.register(Vector3i(floori(instance.global_position.x), floori(instance.global_position.y), floori(instance.global_position.z)), instance)
	SaveManager.mark_placed(instance, item.id)
	GameEvents.building_placed.emit(item.id, instance)
	if feel != null:
		feel.kick("place")
	UiSound.play("place")
	PipeSegment.relink_all(get_tree())
	return true

func _update_build_ghost() -> void:
	if _build_ghost == null:
		return

	var aim: Variant = _build_aim()
	if _build_menu_open() or aim == null:
		_build_ghost.visible = false
		return

	var item := _selected_build_item()
	_ghost_model_for(item)
	if item != null:
		# the box only shows when there is no model to show (pipes); otherwise it shrinks away
		(_build_ghost.mesh as BoxMesh).size = item.ghost_size if _ghost_model_id == "" else Vector3.ONE * 0.001
	var is_foundation := item != null and item.is_foundation
	var force_snap := item != null and item.force_grid_snap

	var raw_pos: Vector3 = aim
	if _is_pipe_item(item):
		var pipe_end := _snap_pipe_point(raw_pos)
		if _pipe_anchor_set and item.id == "vacuum_pipe":
			pipe_end = _pipe_constrain(_pipe_anchor, pipe_end)
		_pipe_preview_end = pipe_end
		_build_ghost_material.albedo_color = GHOST_OK
		if _pipe_anchor_set:
			_build_ghost.global_transform = _pipe_transform(_pipe_anchor, pipe_end, item.id != "vacuum_pipe")
			if item.id == "vacuum_pipe":
				var run := _build_ghost.global_transform
				run.origin += run.basis.y.normalized() * PipeSegment.PIPE_HEIGHT
				_build_ghost.global_transform = run
				(_build_ghost.mesh as BoxMesh).size = Vector3(0.5, 0.5, maxf(_pipe_anchor.distance_to(pipe_end), 0.05))
		elif item.id == "vacuum_pipe":
			# before the first click: a pipe-sized marker where the run would start
			var up := PlanetPhysics.get_up(pipe_end)
			_build_ghost.global_transform = Transform3D(_tangent_basis_at(up, -camera.global_transform.basis.z), pipe_end + up * PipeSegment.PIPE_HEIGHT)
			(_build_ghost.mesh as BoxMesh).size = Vector3(0.5, 0.5, 0.5)
		else:
			_build_ghost.global_transform = _pipe_transform(pipe_end, pipe_end, true)
		_build_ghost.visible = true
		return
	if not is_foundation and (_build_grid_snap or force_snap):
		# Foundations get their own continuous edge-snap/free-tangent
		# placement below - the old flat voxel-cell snap is a different,
		# now-superseded concept for them specifically.
		raw_pos = _snap_build_position(raw_pos, force_snap)

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
		_deny_place(String(placement.get("reason", "Can't place here")))
		return

	var block: String = build_ui.placement_block_reason()
	if block != "":
		_deny_place(block)
		return
	for i in recipe.input_ids.size():
		Inventory.try_remove(recipe.input_ids[i], recipe.input_amounts[i])

	var instance: Node3D = item.building_scene.instantiate()
	get_tree().current_scene.add_child(instance)
	instance.global_transform = placement.transform

	var cell := Vector3i(floori(instance.global_position.x), floori(instance.global_position.y), floori(instance.global_position.z))
	if "grid_pos" in instance:
		instance.grid_pos = cell
	PipeNetwork.register(cell, instance)
	SaveManager.mark_placed(instance, item.id)
	GameEvents.building_placed.emit(item.id, instance)
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
		prompt.show_prompt("E", "Open " + _display_name_of(_targeted_building))
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
	for ore in celestial.ore_types:
		names[ore.material_index] = ore.id
	hud.call("scan_from", terrain, global_position, names)

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

func _run_tool_anim(tool_name: String, running: bool) -> void:
	var p := _tool_player(tool_name)
	if p == null:
		return
	var anim := ""
	for a in p.get_animation_list():
		if String(a).begins_with("Working"):
			anim = a
	if anim == "":
		return
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
	_run_tool_anim("MiningTool", drilling)
	_scan_anim_left = maxf(_scan_anim_left - delta, 0.0)
	_run_tool_anim("ScannerTool", _scan_anim_left > 0.0)
	_run_tool_anim("BuildTool", Inventory.has_tool_equipped(BuildingToolItem.id))
	# drilling kicks: a small, fast shake of the held drill (the feel node places the tool, see first_person_feel.gd)
	var shake := Vector3.ZERO
	if drilling:
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(0, 1)) * 0.004
	if feel != null:
		feel.set_shake(shake)

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
	if not refill:
		suit_o2 = maxf(suit_o2 - delta, 0.0)
	o2_refilling = refill and suit_o2 < SUIT_O2_MAX

## --- Death and respawn (driven by PlayerVitals) ----------------------------------------------------------------
func on_died() -> void:
	if _piloted_ship != null:
		_exit_ship()
	if _build_mode and has_method("_exit_build_mode"):
		call("_exit_build_mode")
	_dig_held = false
	_move_vel = Vector3.ZERO
	_vertical_speed = 0.0
	UiSound.play("error")

func on_respawned() -> void:
	suit_o2 = SUIT_O2_MAX
	_move_vel = Vector3.ZERO
	_vertical_speed = 0.0
	_align_to_up(PlanetPhysics.get_up(global_position))

## --- Dismantle and pick (design M13, small-things QoL) ---------------------------------------------------------
func _set_dismantle(on: bool) -> void:
	if _dismantle == on:
		return
	_dismantle = on
	_dismantle_held = false
	_dismantle_hold = 0.0
	_set_dismantle_target(null)
	_pipe_anchor_set = false
	if _build_ghost != null:
		_build_ghost.visible = false
	_refresh_build_hint()

func _set_dismantle_target(t: Node3D) -> void:
	if t == _dismantle_target:
		return
	if _dismantle_target != null and is_instance_valid(_dismantle_target) and _dismantle_target.has_method("set_highlighted"):
		_dismantle_target.set_highlighted(false)
	_dismantle_target = t
	_dismantle_hold = 0.0
	if t != null and t.has_method("set_highlighted"):
		t.set_highlighted(true)
		UiSound.play("hover")

## Whatever placed object the crosshair is on (within build range), or null.
func _aimed_placed_object() -> Node3D:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * BUILD_MODE_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return WorldObjects.placed_root(hit.collider)

func _update_dismantle(delta: float) -> void:
	if _build_ghost != null:
		_build_ghost.visible = false
	_set_dismantle_target(_aimed_placed_object())
	var hud := get_tree().get_first_node_in_group("compact_hud")
	if _dismantle_target == null or not _dismantle_held:
		_dismantle_hold = 0.0
		if hud != null and hud.has_method("set_action_progress"):
			hud.set_action_progress(0.0, "")
		return
	_dismantle_hold += delta
	var name_of := Inventory.get_item_def(String(_dismantle_target.get_meta(SaveManager.ITEM_ID_META, "")))
	if hud != null and hud.has_method("set_action_progress"):
		hud.set_action_progress(_dismantle_hold / DISMANTLE_TIME, "Dismantling " + (name_of.display_name if name_of else ""))
	if _dismantle_hold < DISMANTLE_TIME:
		return
	var target := _dismantle_target
	_set_dismantle_target(null)
	_dismantle_held = false
	if hud != null and hud.has_method("set_action_progress"):
		hud.set_action_progress(0.0, "")
	if WorldObjects.dismantle(target):
		if feel != null:
			feel.kick("place")
		UiSound.play("confirm")
	else:
		if feel != null:
			feel.kick("deny")
		UiSound.play("deny")
		if hud != null and hud.has_method("toast"):
			hud.toast("Inventory full - make room to dismantle")

## Middle click: start building another of whatever is under the crosshair, same rotation.
func _pick_what_i_look_at() -> void:
	var target := _aimed_placed_object()
	if target == null:
		return
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null or not build_ui.select_item(String(target.get_meta(SaveManager.ITEM_ID_META, ""))):
		return
	if not _build_mode:
		if not Inventory.has_tool_equipped(BuildingToolItem.id):
			return
		_enter_build_mode()
	_set_dismantle(false)
	on_build_picked()
	UiSound.play("click")

## Refused placement: kick, buzz, and say WHY on the HUD (design/04 "invalid place" row).
func _deny_place(reason: String) -> void:
	if feel != null:
		feel.kick("deny")
	UiSound.play("deny", 1.0, 0.25)
	var hud := get_tree().get_first_node_in_group("compact_hud")
	if hud != null and hud.has_method("toast"):
		hud.toast(reason)

## Drilling with a full bag: the rock still comes away, the ore is lost - say so, loudly but not every bite.
var _full_warn_cool := 0.0
func _inventory_full_feedback() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _full_warn_cool:
		return
	_full_warn_cool = now + 2.0
	UiSound.play("error")
	if feel != null:
		feel.kick("deny")
	var hud := get_tree().get_first_node_in_group("compact_hud")
	if hud != null and hud.has_method("toast"):
		hud.toast("INVENTORY FULL - ore is being lost")

## --- Sidearm --------------------------------------------------------------------------------------------------
func _fire_sidearm() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _sidearm_cool:
		return
	_sidearm_cool = now + SIDEARM_INTERVAL
	if not Inventory.try_remove(SidearmAmmo.item_id, 1):
		UiSound.play("deny", 1.0, 0.4)
		var hud := get_tree().get_first_node_in_group("compact_hud")
		if hud != null and hud.has_method("toast"):
			hud.toast("NO PIERCE AMMO - craft it in the Constructor")
		return
	var fwd := -camera.global_transform.basis.z
	var muzzle := camera.global_position + fwd * 0.7 - camera.global_transform.basis.y * 0.15
	var p: Node3D = preload("res://scenes/projectile.tscn").instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle
	p.set_meta("faction", "player")
	p.setup(fwd * SidearmAmmo.muzzle_velocity + velocity, SidearmAmmo, get_rid())
	WorldFx.burst("muzzle", muzzle, fwd)
	WorldFx.sound("gun", muzzle, 1.4)
	if feel != null:
		feel.kick("place")

## Blockout sidearm for the viewmodel (no Blender model yet): grip, receiver, barrel, magazine, sight.
func _build_sidearm_model() -> void:
	var g := Node3D.new()
	g.name = "Sidearm"
	viewmodel.add_child(g)
	Blockout.box(g, Vector3(0.05, 0.12, 0.05), Vector3(0.23, -0.27, -0.42), Blockout.DARK)        # grip
	Blockout.box(g, Vector3(0.07, 0.08, 0.26), Vector3(0.23, -0.19, -0.5), Blockout.STEEL)       # receiver
	Blockout.cyl(g, 0.018, 0.22, Vector3(0.23, -0.18, -0.72), Blockout.DARK, "z")               # barrel
	Blockout.box(g, Vector3(0.04, 0.09, 0.05), Vector3(0.23, -0.26, -0.55), Blockout.HAZARD)     # rivet magazine
	Blockout.cyl(g, 0.012, 0.02, Vector3(0.23, -0.14, -0.45), UiTokens.ACCENT, "y", "", true)    # sight dot

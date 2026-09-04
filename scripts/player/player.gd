extends CharacterBody3D

const SPEED := 6.0
const JUMP_VELOCITY := 6.0
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT := 1.4

const DIG_RANGE := 6.0
const DIG_RADIUS := 0.7
const DIG_FRAGMENT_THRESHOLD := 0.22
const BUILD_RADIUS := 1.0
const INTERACT_RANGE := 3.5

## Camera3D's rest local transform in FPS mode (matches scenes/player.tscn).
## Recomputed on exit from build mode rather than snapshotted on entry: _pitch
## is left untouched the whole time build mode is active (mouse-look input is
## gated off), so this always reconstructs the exact pose the player left.
const CAMERA_FPS_LOCAL_POSITION := Vector3(0.0, 1.6, 0.0)

const BUILD_MODE_RANGE := 80.0
## Smooth top-down build camera: perspective ONLY during the enter/exit flight
## animation (cosmetic - no world input is processed until _build_view_ready,
## see _unhandled_input) for a GTA-style fly-through feel. Switches to
## orthographic for the entire interactive placement session, since a
## perspective ray intersected with a plane it isn't perpendicular to (any
## pitch other than straight down) is a non-uniform projective mapping - an
## orthographic camera's parallel rays keep that same intersection affine/
## uniform at any pitch. See _enter_build_mode()'s tween completion callback.
const BUILD_CAM_PITCH_DEG := -55.0
## Fixed height above the focus point; perspective still has a real camera
## position, so we use a smooth orbit offset plus a world-space zoom distance.
const BUILD_CAM_HEIGHT := 20.0
const BUILD_CAM_MIN_ZOOM := 10.0
const BUILD_CAM_MAX_ZOOM := 35.0
const BUILD_CAM_DEFAULT_ZOOM := 22.0
const BUILD_CAM_ZOOM_STEP := 3.0
const BUILD_PAN_SPEED := 14.0
const BUILD_CAMERA_TRANSITION_TIME := 0.6
const BUILD_ROTATE_STEP := PI / 2.0

## How close the cursor needs to be to an existing foundation's edge slot to
## snap a new foundation there, and how close a regular building's ghost
## needs to be to a foundation's center to mount flush on top of it instead
## of free-placing tangent to the raw terrain.
const FOUNDATION_SNAP_RADIUS := 3.0
const FOUNDATION_MOUNT_RADIUS := 1.3

## How long left-click must be held before the tool "spins up" and starts
## actually cutting, and how often it cuts again while held after that.
const DIG_SPINUP_TIME := 0.2
const DIG_INTERVAL := 0.12

const BuildRecipe: Recipe = preload("res://data/recipes/build_block.tres")
const MiningToolItem: Item = preload("res://data/items/mining_tool.tres")
const BuildingToolItem: Item = preload("res://data/items/building_tool.tres")

const ORE_ITEM_BY_MATERIAL := {
	VoxelMaterials.IRON_ORE: "ore_a",
	VoxelMaterials.COPPER_ORE: "ore_b",
	VoxelMaterials.SULFUR_ORE: "sulfur",
	VoxelMaterials.COAL_ORE: "ore_coal",
	VoxelMaterials.SILICA_ORE: "ore_silica",
	VoxelMaterials.CRYSTAL_ORE: "ore_crystal",
}

@onready var camera: Camera3D = $Camera3D
@onready var viewmodel: MeshInstance3D = $Camera3D/ViewmodelTool

var _pitch := 0.0
var _terrain: VoxelTerrain = null
var _inventory_open := false
var _targeted_building: Building = null

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

var _dig_held := false
var _dig_hold_time := 0.0
var _dig_spun_up := false
var _dig_tick_timer := 0.0

## True for the whole duration build mode is active, including both camera
## flight animations. _build_view_ready is only true once the "enter" flight
## has finished and the top-down view/GUI are actually interactive.
var _build_mode := false
var _build_view_ready := false
var _build_grid_snap := true
var _build_rotation := 0.0
var _build_ghost: MeshInstance3D = null
var _build_ghost_material: StandardMaterial3D = null
var _build_focus := Vector3.ZERO
var _build_zoom := BUILD_CAM_DEFAULT_ZOOM
var _build_camera_yaw := 0.0
var _build_camera_pitch := -1.2
var _build_rotate_dragging := false
var _build_lock_ghost := false
var _build_locked_position := Vector3.ZERO
## Local "up" (radial-away-from-planet-center) and a tangent-plane forward/
## right pair, snapshotted once when build mode is entered. The player is
## fully frozen for the whole duration build mode is active (_physics_process
## returns early below), so global_position never changes meanwhile and this
## frame stays exactly correct - it stands in for Vector3.UP/world-X/world-Z
## everywhere the old flat-world build camera used to assume a horizontal
## ground plane.
var _build_up := Vector3.UP
var _build_ref_forward := Vector3.FORWARD
var _build_ref_right := Vector3.RIGHT
var _camera_tween: Tween = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_terrain = PlanetPhysics.get_nearest_terrain(global_position)
	_spawn_resolved = false
	Inventory.changed.connect(_update_viewmodel)
	_update_viewmodel()

func _update_viewmodel() -> void:
	viewmodel.visible = not _build_mode and Inventory.has_tool_equipped(MiningToolItem.id)

func _input(event: InputEvent) -> void:
	# Handled in _input (before GUI focus navigation can eat it) rather than
	# _unhandled_input: Tab is bound to GUI focus-next by default, and once an
	# inventory slot Button has focus it swallows Tab before _unhandled_input
	# ever sees it, permanently getting the player stuck with the mouse freed.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_toggle_inventory()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			_toggle_build_mode()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if _inventory_open:
				_toggle_inventory()
			elif _is_building_ui_open():
				_close_building_ui()
			elif _build_mode:
				_toggle_build_mode()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _inventory_open:
		return

	if _build_mode:
		if not _build_view_ready:
			return # ignore world input mid-flight
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_place_building()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_build_rotate_dragging = event.pressed
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_build_zoom = clamp(_build_zoom - BUILD_CAM_ZOOM_STEP, BUILD_CAM_MIN_ZOOM, BUILD_CAM_MAX_ZOOM)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_build_zoom = clamp(_build_zoom + BUILD_CAM_ZOOM_STEP, BUILD_CAM_MIN_ZOOM, BUILD_CAM_MAX_ZOOM)
		elif event is InputEventMouseMotion and _build_rotate_dragging:
			_build_camera_yaw -= event.relative.x * 0.0035
			_build_camera_pitch = clamp(_build_camera_pitch + event.relative.y * 0.0022, deg_to_rad(15.0), deg_to_rad(90.0))
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F1:
				get_tree().reload_current_scene()
				get_viewport().set_input_as_handled()
				return

			if event.keycode == KEY_G:
				_build_grid_snap = not _build_grid_snap
			elif event.keycode == KEY_R:
				_build_rotation = wrapf(_build_rotation + BUILD_ROTATE_STEP, 0.0, TAU)
			elif event.keycode == KEY_H:
				_build_lock_ghost = not _build_lock_ghost
				if _build_lock_ghost:
					_build_locked_position = _build_ghost.global_position if _build_ghost != null and _build_ghost.visible else _build_focus
			elif _build_lock_ghost:
				var move_step := 1.0
				var yaw_basis := Basis(_build_up, _build_camera_yaw)
				var camera_forward: Vector3 = yaw_basis * _build_ref_forward
				var camera_right: Vector3 = yaw_basis * _build_ref_right
				match event.keycode:
					KEY_UP:
						_build_locked_position += camera_forward * move_step
					KEY_DOWN:
						_build_locked_position -= camera_forward * move_step
					KEY_KP_8:
						_build_locked_position += _build_up * move_step
					KEY_KP_2:
						_build_locked_position -= _build_up * move_step
					KEY_LEFT, KEY_KP_4:
						_build_locked_position -= camera_right * move_step
					KEY_RIGHT, KEY_KP_6:
						_build_locked_position += camera_right * move_step
					KEY_KP_7:
						_build_locked_position -= camera_forward * move_step
					KEY_KP_9:
						_build_locked_position += camera_forward * move_step
					KEY_KP_1:
						_build_locked_position -= camera_forward * move_step
					KEY_KP_3:
						_build_locked_position += camera_forward * move_step
					_:
						pass
		return

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
			_build()

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# rotate_object_local (not rotate_y/rotate_y works in the PARENT frame)
		# so yaw always turns around the player's own current up axis - on a
		# sphere that axis constantly changes as the player walks around, and
		# only the object-local rotation stays correct once away from the
		# spawn point's "pole".
		rotate_object_local(Vector3.UP, -event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
		camera.rotation.x = _pitch

func _reset_dig_hold() -> void:
	_dig_held = false
	_dig_hold_time = 0.0
	_dig_spun_up = false
	_dig_tick_timer = 0.0

func _toggle_inventory() -> void:
	# Inventory and build mode are mutually exclusive: closing the other one
	# first (if open) keeps mouse-mode and dig/build gating unambiguous
	# instead of having to track two independently-active modes.
	if _build_mode:
		_toggle_build_mode()
	_inventory_open = not _inventory_open
	if _inventory_open:
		_reset_dig_hold()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _inventory_open else Input.MOUSE_MODE_CAPTURED
	# Looked up fresh rather than cached in _ready(): InventoryUI registers its
	# group via add_to_group() in its own _ready(), and Player appears earlier
	# than InventoryUI in world.tscn, so caching this in Player._ready() would
	# run before InventoryUI has joined the group and silently find nothing.
	var inventory_ui := get_tree().get_first_node_in_group("inventory_ui")
	if inventory_ui != null:
		inventory_ui.toggle()

func _toggle_build_mode() -> void:
	# Gated like the mining tool's dig/build: the Building Tool must be
	# equipped in a hand slot to ENTER build mode (closing it stays allowed
	# unconditionally, e.g. if the tool got unequipped mid-session).
	if not _build_mode and not Inventory.has_tool_equipped(BuildingToolItem.id):
		return
	if _inventory_open:
		_toggle_inventory()
	if _build_mode:
		_exit_build_mode()
	else:
		_enter_build_mode()

func _enter_build_mode() -> void:
	_build_mode = true
	_build_view_ready = false
	_reset_dig_hold()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_viewmodel()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 55.0

	_build_focus = global_position
	_build_zoom = BUILD_CAM_DEFAULT_ZOOM
	_build_rotation = 0.0

	# Snapshot the local "ground frame" for the whole build session: up is
	# radially away from the planet center, forward is the player's current
	# facing projected flat onto that tangent plane (falls back to the
	# right axis in the degenerate case of looking almost straight up/down).
	_build_up = up_direction
	var fwd := -global_transform.basis.z
	var ref_forward := fwd - _build_up * fwd.dot(_build_up)
	if ref_forward.length() < 0.001:
		var right := global_transform.basis.x
		ref_forward = right - _build_up * right.dot(_build_up)
	_build_ref_forward = ref_forward.normalized()
	_build_ref_right = _build_ref_forward.cross(_build_up).normalized()

	_build_camera_yaw = 0.0
	_build_camera_pitch = deg_to_rad(35.0)
	_build_grid_snap = true

	_spawn_build_ghost()

	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui != null:
		build_ui.bind_player(self)
		build_ui.show_ui()

	var end_transform := global_transform.affine_inverse() * _build_camera_world_transform()
	_animate_camera(end_transform, func() -> void:
		# Perspective only for the flight itself (cosmetic - no world input is
		# processed until _build_view_ready anyway, see _unhandled_input).
		# Orthographic for the whole interactive placement session: a
		# perspective ray intersected with a plane it isn't perpendicular to
		# is a non-uniform projective mapping (confirmed via a driven test -
		# >20x cursor-to-world sensitivity swing from top to bottom of screen
		# at a tilted pitch), while an orthographic camera's rays are all
		# parallel, so the same intersection is affine/uniform at ANY pitch.
		# Switched only once fully arrived (never mid-flight, which would
		# pop) - matches the exit-side switch below, which already did this.
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = _build_zoom
		_build_view_ready = true
	)

func _exit_build_mode() -> void:
	_build_view_ready = false
	_clear_build_ghost()

	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui != null:
		build_ui.hide_ui()

	_animate_camera(_fps_camera_local_transform(), func() -> void:
		_build_mode = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_update_viewmodel()
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	)

func _fps_camera_local_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, _pitch), CAMERA_FPS_LOCAL_POSITION)

func toggle_build_grid_snap() -> void:
	_build_grid_snap = not _build_grid_snap

func rotate_build_ghost() -> void:
	_build_rotation = wrapf(_build_rotation + BUILD_ROTATE_STEP, 0.0, TAU)

func toggle_build_lock() -> void:
	_build_lock_ghost = not _build_lock_ghost
	if _build_lock_ghost and _build_ghost != null:
		_build_locked_position = _build_ghost.global_position

func _build_camera_world_transform() -> Transform3D:
	var yaw_basis := Basis(_build_up, _build_camera_yaw)
	var forward: Vector3 = yaw_basis * _build_ref_forward
	var horiz := -forward * _build_zoom * cos(_build_camera_pitch)
	var vert := _build_up * _build_zoom * sin(_build_camera_pitch)
	var camera_pos := _build_focus + horiz + vert
	var basis := Basis().looking_at(_build_focus - camera_pos, _build_up)
	return Transform3D(basis, camera_pos)

func _animate_camera(target_local_transform: Transform3D, on_complete: Callable) -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(camera, "transform", target_local_transform, BUILD_CAMERA_TRANSITION_TIME)
	_camera_tween.finished.connect(on_complete, CONNECT_ONE_SHOT)

func _spawn_build_ghost() -> void:
	_clear_build_ghost()
	var ghost := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.5, 1.5, 1.5)
	ghost.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 0.4, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = mat
	ghost.visible = false
	get_tree().current_scene.add_child(ghost)
	_build_ghost = ghost
	_build_ghost_material = mat

func _clear_build_ghost() -> void:
	if _build_ghost != null:
		_build_ghost.queue_free()
		_build_ghost = null

func _try_resolve_spawn() -> bool:
	if _terrain == null:
		return false
	var planet_center := PlanetPhysics.get_planet_center(global_position)
	var radial_up := PlanetPhysics.get_up(global_position)
	var tool := _terrain.get_voxel_tool()
	# Reach derived from the actual nearest body's radius (not a flat
	# constant) so spawn-resolution works correctly regardless of which
	# planet/moon the player starts near, not just one sized like "home."
	var nearest_planet := PlanetPhysics.get_nearest_body(global_position) as Planet
	var radius_world: float = nearest_planet.radius_world() if nearest_planet != null else 40.0
	var ray_origin := planet_center + radial_up * (radius_world + 25.0)
	var hit := tool.raycast(ray_origin, -radial_up, 45.0, 0xFFFFFFFF)
	if hit == null:
		return false
	var surface_position := Vector3(hit.previous_position)
	global_position = surface_position + radial_up * 0.2
	up_direction = radial_up
	_align_to_up(radial_up)
	_vertical_speed = 0.0
	_spawn_resolved = true
	return true

func _physics_process(delta: float) -> void:
	if not _spawn_resolved:
		_try_resolve_spawn()
		return

	if _is_building_ui_open() or _build_mode or _inventory_open:
		_clear_interact_target()
	else:
		_update_interact_target()

	if _is_building_ui_open():
		return

	if _build_mode:
		if _build_view_ready:
			_update_build_camera(delta)
			_update_build_ghost()
		return

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
	if not is_on_floor():
		_vertical_speed -= PlanetPhysics.get_gravity_accel(global_position).length() * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		_vertical_speed = JUMP_VELOCITY
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
	velocity = move_dir * SPEED + up * _vertical_speed

	move_and_slide()

	if not _inventory_open and Input.is_physical_key_pressed(KEY_E):
		_try_interact()

	if _dig_held and not _inventory_open:
		_dig_hold_time += delta
		if not _dig_spun_up and _dig_hold_time >= DIG_SPINUP_TIME:
			_dig_spun_up = true
			_dig_tick_timer = DIG_INTERVAL # fire immediately once spun up
		if _dig_spun_up:
			_dig_tick_timer += delta
			if _dig_tick_timer >= DIG_INTERVAL:
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

func _update_build_camera(delta: float) -> void:
	var pan_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		pan_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		pan_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		pan_dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		pan_dir.x -= 1.0
	pan_dir = pan_dir.normalized()

	# Top-down build camera is completely independent from the player, but
	# still tangent to the planet surface at the point build mode was
	# entered (_build_up/_build_ref_forward/_build_ref_right) so panning
	# stays flat against "the ground" instead of drifting into the terrain
	# or off into space.
	var yaw_basis := Basis(_build_up, _build_camera_yaw)
	var camera_forward: Vector3 = yaw_basis * _build_ref_forward
	var camera_right: Vector3 = yaw_basis * _build_ref_right

	if pan_dir != Vector2.ZERO:
		_build_focus += (camera_right * pan_dir.x + camera_forward * pan_dir.y) * BUILD_PAN_SPEED * delta

	# Orthographic apparent zoom is camera.size (world-space visible height),
	# not camera distance - keep it synced to the same _build_zoom the scroll
	# wheel already drives so "zoom in/out" keeps meaning what it always did.
	camera.size = _build_zoom

	var target_world_transform := _build_camera_world_transform()
	var target_local_transform := global_transform.affine_inverse() * target_world_transform
	var smooth := 1.0 - exp(-delta * 10.0)
	camera.transform = camera.transform.interpolate_with(target_local_transform, smooth)

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
## 1 world meter, so a world-meter-intended radius constant (DIG_RADIUS,
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
	if not Inventory.has_tool_equipped(MiningToolItem.id):
		return

	var hit := _raycast()
	if hit == null:
		return

	var tool := _terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_INDICES)
	var material_index: int = tool.get_voxel(hit.position)

	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	tool.set_mode(VoxelTool.MODE_REMOVE)
	tool.do_sphere(Vector3(hit.position) + Vector3(0.5, 0.5, 0.5), _local_radius(DIG_RADIUS))
	tool.do_sphere(Vector3(hit.position) + Vector3(0.5, 0.5, 0.5), _local_radius(DIG_FRAGMENT_THRESHOLD))

	var item_id: String = ORE_ITEM_BY_MATERIAL.get(material_index, "")
	if item_id != "":
		Inventory.add(item_id, 1)

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

## get_viewport().get_mouse_position() is in this project's "canvas_items"
## stretch-mode LOGICAL/UI coordinate space (project.godot: window/stretch/
## mode="canvas_items") - that mode deliberately keeps 3D rendering at the
## real native window resolution while only rescaling 2D/UI into a separate
## logical space, so it does NOT match what Camera3D.project_ray_origin/
## project_ray_normal expect (the real window pixel rect). The two spaces
## coincide near screen center and diverge toward the edges - exactly a
## "ghost tracks the cursor near the middle, drifts further away toward the
## edges" symptom. Reading the OS-level cursor position directly, relative to
## the window's own screen position, sidesteps the canvas transform entirely
## and always matches the real pixel rect 3D projection uses.
func _mouse_viewport_position() -> Vector2:
	return Vector2(DisplayServer.mouse_get_position() - get_window().position)

## Grid mode reuses VoxelTool's raycast (like terrain digging/block-building
## already do), which only ever returns whole-voxel integer positions - that
## IS the grid snap. Free mode uses a plain physics raycast against the
## terrain's generated collision mesh for a continuous float-precision point.
## Both are cast from the mouse cursor through the (now top-down) camera,
## not from the camera's forward look direction.
func _screen_to_build_plane(mouse_pos: Vector2) -> Vector3:
	var ray_from := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var plane_point := _build_focus + _build_up * 0.5
	var denom := ray_dir.dot(_build_up)
	if abs(denom) < 0.0001:
		return _build_focus
	var t := (plane_point - ray_from).dot(_build_up) / denom
	return ray_from + ray_dir * t

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

## Fresh terrain-support check directly below `pos` using the LOCAL up at
## that exact point (not the stale build-mode-entry _build_up snapshot) -
## matters once the ghost/camera has panned far enough from the entry point
## that the sphere has curved a meaningful amount in between.
func _terrain_supports(pos: Vector3) -> bool:
	if _terrain == null:
		return false
	var up := PlanetPhysics.get_up(pos)
	var tool := _terrain.get_voxel_tool()
	var support_hit := tool.raycast(pos + up * 8.0, -up, 20.0, 0xFFFFFFFF)
	return support_hit != null

## Basis tangent to the sphere at `up` (Y = up, -Z = the given reference
## forward projected flat onto that tangent plane), falling back through the
## build-session's entry-snapshot forward and finally world-right if the
## reference is degenerate (looking almost exactly along `up`). Same
## projection technique as _align_to_up(), just returning a Basis instead of
## mutating a transform, so it works for ghost/instance placement too.
func _tangent_basis_at(up: Vector3, reference_forward: Vector3) -> Basis:
	var fwd := reference_forward - up * reference_forward.dot(up)
	if fwd.length() < 0.001:
		fwd = _build_ref_forward - up * _build_ref_forward.dot(up)
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
func _foundation_snap_transform(neighbor: Node, raw_pos: Vector3) -> Transform3D:
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
	return Transform3D(basis, best)

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
			return {"transform": _foundation_snap_transform(neighbor, raw_pos), "valid": true}
		var xf := _free_tangent_transform(raw_pos)
		xf.origin -= xf.basis.y * (Foundation.HEIGHT * 0.5)
		return {"transform": xf, "valid": _terrain_supports(raw_pos)}

	var mount := FoundationNetwork.find_nearest(raw_pos, FOUNDATION_MOUNT_RADIUS)
	if mount != null:
		var mount_basis: Basis = mount.global_transform.basis
		var mount_pos: Vector3 = mount.global_position + mount_basis.y * (Foundation.HEIGHT * 0.5)
		var final_basis := Basis(mount_basis.y, _build_rotation) * mount_basis
		return {"transform": Transform3D(final_basis, mount_pos), "valid": true}

	var xf := _free_tangent_transform(raw_pos)
	return {"transform": xf, "valid": _terrain_supports(raw_pos)}

func _update_build_ghost() -> void:
	if _build_ghost == null:
		return

	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui != null and build_ui.is_mouse_over_ui():
		_build_ghost.visible = false
		return

	var item := _selected_build_item()
	if item != null:
		(_build_ghost.mesh as BoxMesh).size = item.ghost_size
	var is_foundation := item != null and item.is_foundation
	var force_snap := item != null and item.force_grid_snap

	var mouse_pos := _mouse_viewport_position()
	var raw_pos := _screen_to_build_plane(mouse_pos)
	if _build_lock_ghost:
		raw_pos = _build_locked_position
	elif not is_foundation and (_build_grid_snap or force_snap):
		# Foundations get their own continuous edge-snap/free-tangent
		# placement below - the old flat voxel-cell snap is a different,
		# now-superseded concept for them specifically.
		raw_pos = _snap_build_position(raw_pos, force_snap)

	var placement := _resolve_build_placement(raw_pos, item)
	var is_valid: bool = placement.valid
	_build_ghost.visible = true
	if _build_ghost_material != null:
		_build_ghost_material.albedo_color = Color(1.0, 0.25, 0.25, 0.45) if not is_valid else Color(0.3, 0.9, 0.4, 0.45)
	_build_ghost.global_transform = placement.transform

func _place_building() -> void:
	if _build_ghost == null or not _build_ghost.visible:
		return
	var build_ui := get_tree().get_first_node_in_group("build_ui")
	if build_ui == null:
		return
	if build_ui.is_mouse_over_ui():
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
		return

	for i in recipe.input_ids.size():
		if Inventory.get_count(recipe.input_ids[i]) < recipe.input_amounts[i]:
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

func _try_interact() -> void:
	if _is_building_ui_open():
		return
	if _targeted_building != null and is_instance_valid(_targeted_building):
		_targeted_building.interact()

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

func _update_interact_target() -> void:
	var building := _raycast_building()
	if building != _targeted_building:
		if _targeted_building != null and is_instance_valid(_targeted_building):
			_targeted_building.set_highlighted(false)
		_targeted_building = building
		if _targeted_building != null:
			_targeted_building.set_highlighted(true)
	var prompt := get_tree().get_first_node_in_group("interact_prompt")
	if prompt == null:
		return
	if _targeted_building != null:
		prompt.show_prompt("Press E to open %s" % _targeted_building.name)
	else:
		prompt.hide_prompt()

func _clear_interact_target() -> void:
	if _targeted_building != null and is_instance_valid(_targeted_building):
		_targeted_building.set_highlighted(false)
	_targeted_building = null
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

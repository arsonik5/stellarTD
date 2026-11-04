class_name Ship
extends RigidBody3D

signal block_damaged(cell: Vector3i, amount: float)
signal block_destroyed(cell: Vector3i)
signal ship_state_changed(state: String)

const STATE_OPERATIONAL := "operational"
const STATE_DEGRADED := "degraded"
const STATE_WRECKED := "wrecked"

## Shared flight physics for every ship in the game, player-piloted or
## AI-flown - the whole point being that both fly on the exact same code,
## not parallel implementations. Real RigidBody3D physics (mass, momentum,
## collisions), not a kinematic hand-mover: gravity_scale is zeroed and
## radial gravity/atmospheric drag are applied manually every tick via
## PlanetPhysics, the same autoload/formulas projectile.gd already uses, so
## a ship drifting near a planet is consistent with everything else in the
## game and floats true-Newtonian once far enough into the void.
##
## Any controller (PlayerShipController or an AI steering script) drives a
## Ship purely through desired_linear_thrust/desired_angular_velocity, both
## in ship-local space - it never touches forces/torques directly. Thrust
## allocation across an arbitrary, possibly asymmetric thruster layout is a
## per-thruster dot product against the desired direction each tick (a
## thruster fires proportionally to how well it's aligned, not from a
## pre-sorted "forward/back" bucket) - this is what makes both a
## hand-authored enemy scene and a player-built block ship "just work"
## through the same code with no per-case branching.

@export var desired_linear_thrust: Vector3 = Vector3.ZERO
@export var desired_angular_velocity: Vector3 = Vector3.ZERO
@export var dampeners_enabled: bool = true
## True only for a ship spawned via player.gd's Ship Core placement - gates
## whether the in-game block-placement tool is allowed to add blocks to it,
## so right-clicking a ship-block item at an enemy ship (also a Ship,
## through the same shared physics class) can't graft blocks onto it.
var is_player_ship: bool = false
var ship_state: String = STATE_OPERATIONAL

## Coarse drag stats - a real per-block cross-section isn't worth modeling
## yet, same "good enough" simplification level as everything else in
## Slice 1/2. Tune per-ship-class later if it matters.
@export var drag_coefficient: float = 1.0
@export var cross_section_area: float = 6.0

## Angular-velocity error (rad/s) below which rotation torque tapers off
## proportionally instead of saturating at full available gyro torque - a
## fixed window rather than a fixed force gain, so response scales
## correctly regardless of a specific ship's mass/inertia or how many
## gyroscopes it has (more gyros = more available torque = faster turning,
## same as thrust already scales with more thrusters).
const ANGULAR_EASE_WINDOW := 0.15
## Fine build grid: 0.5 m cells. Classic 2 m blocks fill BIG x BIG x BIG of them and sit on the 2 m lattice
## (their min corner on a multiple of BIG offset by -BIG/2, so a 2 m block is centred on a multiple of 2 m exactly
## as before); small blocks go anywhere next to them. Cell k spans [k, k+1) x CELL_SIZE.
const CELL_SIZE := 0.5
const BIG := 4
## One classic block's size in metres (the old CELL_SIZE): cockpit reach and similar distances use it.
const BLOCK_SIZE := 2.0
const DAMPENER_BRAKE_TIME := 0.35
const ANGULAR_DAMPING_TIME := 0.2

## Occupancy registry for the in-game buildable grid ONLY (player-built ships and vehicles) - hand-authored enemy
## ships never populate this, their thrusters/gyroscopes are just scene children with their own hand-placed hull
## collision. _rebuild_stats() reads real ShipBlock-derived children directly (see _gather_blocks), never these
## dicts, so both cases recompute mass/thrust identically either way.
var _blocks: Dictionary = {} # anchor (min corner cell) -> ShipBlock
var _cells: Dictionary = {}  # every occupied cell -> ShipBlock
## CollisionShape3D must be a DIRECT child of the RigidBody3D to actually register as collision - a block
## scene's own nested shape two levels down would silently do nothing. So each placed block's collision lives
## here as a sibling Ship owns directly, not inside the block's own scene.
var _block_shapes: Dictionary = {} # anchor -> CollisionShape3D

var _thrusters: Array[ShipThruster] = []
var _wheels: Array[ShipWheel] = []
var _max_torque: float = 1.0
## Summed from the blocks in _rebuild_stats(): engines drive the wheels, batteries store power (not simulated yet).
var _drive_force := 0.0
var power_capacity := 0.0
## Used only where there is no planet (dev scenes): the planets' gravity otherwise.
var fallback_gravity := Vector3.ZERO

func gravity_accel() -> Vector3:
	var a := PlanetPhysics.get_gravity_accel(global_position)
	return a if a.length_squared() > 1e-6 else fallback_gravity
var _impact_cooldowns: Dictionary = {}

## Centre of a block of `size` cells whose min corner cell is `anchor` (ship-local metres).
static func block_center(anchor: Vector3i, size: Vector3i) -> Vector3:
	return (Vector3(anchor) + Vector3(size) * 0.5) * CELL_SIZE

## The min corner cell of a block of `size` cells centred on `center`.
static func anchor_for_center(center: Vector3, size: Vector3i) -> Vector3i:
	var a := center / CELL_SIZE - Vector3(size) * 0.5
	return Vector3i(roundi(a.x), roundi(a.y), roundi(a.z))

## Old saves and hand-written layouts count in whole 2 m blocks: their block at `big_cell` starts here.
static func legacy_anchor(big_cell: Vector3i) -> Vector3i:
	return big_cell * BIG - Vector3i.ONE * (BIG / 2)

static func cells_of(anchor: Vector3i, size: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for x in size.x:
		for y in size.y:
			for z in size.z:
				out.append(anchor + Vector3i(x, y, z))
	return out

func _ready() -> void:
	add_to_group("ship")
	gravity_scale = 0.0
	contact_monitor = true
	max_contacts_reported = 16
	_rebuild_stats()
	if not has_node("ChaseCamera"):
		var chase := Camera3D.new()
		chase.name = "ChaseCamera"
		chase.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 8.0))
		add_child(chase)

## `block` must already be added as a direct child of this Ship (at its final local `position` =
## block_center(anchor, size) and rotation) before calling this - it only registers its cells, adds the matching
## collision shape and recomputes stats.
func add_block(anchor: Vector3i, block: ShipBlock) -> void:
	_blocks[anchor] = block
	block.set_meta("anchor", anchor)
	for c in cells_of(anchor, block.ship_size()):
		_cells[c] = block
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var local_size := block.collision_size if block.collision_size != Vector3.ZERO else Vector3(block.size_cells) * CELL_SIZE
	box.size = (block.transform.basis * local_size).abs()
	shape.shape = box
	shape.transform.origin = block.position + block.transform.basis * block.collision_offset
	add_child(shape)
	_block_shapes[anchor] = shape
	_rebuild_stats()

## Places `block` (already rotated) with its min corner at `anchor`: every cell it needs must be free and (unless
## the ship is empty) at least one of them must touch an existing block face to face.
func try_add_block(anchor: Vector3i, block: ShipBlock) -> bool:
	if block == null:
		return false
	var cells := cells_of(anchor, block.ship_size())
	for c in cells:
		if _cells.has(c):
			return false
	if not _cells.is_empty() and not _touches(cells):
		return false
	add_child(block)
	block.position = block_center(anchor, block.ship_size())
	add_block(anchor, block)
	return true

func try_remove_block(cell: Vector3i) -> bool:
	if not can_remove_block(cell):
		return false
	remove_block(cell)
	return true

## Removes the block filling `cell` (any of its cells, or its anchor).
func remove_block(cell: Vector3i) -> void:
	var block: ShipBlock = _cells.get(cell)
	if block == null:
		return
	var anchor: Vector3i = block.get_meta("anchor", cell)
	for c in cells_of(anchor, block.ship_size()):
		_cells.erase(c)
	_blocks.erase(anchor)
	if is_instance_valid(block):
		block.queue_free()
	if _block_shapes.has(anchor):
		var shape: CollisionShape3D = _block_shapes[anchor]
		_block_shapes.erase(anchor)
		if is_instance_valid(shape):
			shape.queue_free()
	_rebuild_stats()
	_recalculate_state()

func can_remove_block(cell: Vector3i) -> bool:
	var block: ShipBlock = _cells.get(cell)
	if block == null or block.critical:
		return false
	var remaining: Dictionary = _blocks.duplicate()
	remaining.erase(block.get_meta("anchor", cell))
	return _is_connected_to_core(remaining)

func get_block(cell: Vector3i) -> ShipBlock:
	return _cells.get(cell)

## Anchors of every block (one per block).
func get_block_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for cell in _blocks:
		cells.append(cell)
	return cells

func apply_damage(cell: Vector3i, amount: float) -> void:
	var block := get_block(cell)
	if block == null or amount <= 0.0:
		return
	var applied := block.apply_damage(maxf(amount - block.armour, 0.0))
	if applied <= 0.0:
		return
	block_damaged.emit(cell, applied)
	if not block.is_operational():
		block_destroyed.emit(cell)
		if block.critical:
			_set_state(STATE_WRECKED)
		else:
			_rebuild_stats()
	_recalculate_state()

func repair_all(amount: float) -> float:
	var restored := 0.0
	for cell in _blocks:
		restored += (_blocks[cell] as ShipBlock).repair(amount)
	_recalculate_state()
	return restored

func is_operational() -> bool:
	return ship_state != STATE_WRECKED and _has_operational_core()

func has_block_at(cell: Vector3i) -> bool:
	return _cells.has(cell)

## GDScript's `is` operator correctly resolves class_name inheritance
## (Node.find_children's string-based type filter does not reliably do the
## same for custom script classes), so blocks are gathered by hand rather
## than trusting a type-string match - the mass/thrust totals silently
## coming back empty would be a much worse failure than a few extra lines.
func _gather_blocks() -> Array[ShipBlock]:
	var result: Array[ShipBlock] = []
	_gather_blocks_recursive(self, result)
	return result

func _gather_blocks_recursive(node: Node, result: Array[ShipBlock]) -> void:
	for child in node.get_children():
		if child is ShipBlock:
			result.append(child)
		_gather_blocks_recursive(child, result)

func _rebuild_stats() -> void:
	var blocks := _gather_blocks()
	var total_mass := 0.0
	var weighted_pos := Vector3.ZERO
	var total_torque := 0.0
	_thrusters.clear()
	_wheels.clear()
	_drive_force = 0.0
	power_capacity = 0.0

	for block in blocks:
		total_mass += block.mass_kg
		weighted_pos += block.position * block.mass_kg
		if not block.is_operational():
			continue
		if block is ShipThruster:
			if block is ShipRCS:
				total_torque += block.rcs_torque
			_thrusters.append(block)
		elif block is ShipGyroscope:
			total_torque += block.max_torque
		elif block is ShipEngine:
			_drive_force += block.drive_force
		elif block is ShipBattery:
			power_capacity += block.capacity_kwh
		elif block is ShipWheel:
			_wheels.append(block)

	mass = maxf(total_mass, 1.0)
	if total_mass > 0.0:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = weighted_pos / total_mass
	_max_torque = maxf(total_torque, 1.0)
	_compute_wheel_shares()

## Static load on each wheel (kg): the smallest set of loads that adds up to the ship's mass and balances about the
## centre of mass (lever rule in x and z). Each wheel's spring is sized from its own load, so a nose-light or
## tail-heavy build still sits level with every wheel at mid-travel.
func _compute_wheel_shares() -> void:
	var n := _wheels.size()
	if n == 0:
		return
	var sz := 0.0; var sx := 0.0; var szz := 0.0; var sxx := 0.0; var sxz := 0.0
	for w in _wheels:
		var p := w.position
		sz += p.z; sx += p.x; szz += p.z * p.z; sxx += p.x * p.x; sxz += p.x * p.z
	var m := Basis(Vector3(n, sz, sx), Vector3(sz, szz, sxz), Vector3(sx, sxz, sxx))
	var even := mass / n
	if absf(m.determinant()) < 1e-4:
		for w in _wheels:
			w.static_share = even
		return
	var lam: Vector3 = m.inverse() * Vector3(mass, mass * center_of_mass.z, mass * center_of_mass.x)
	for w in _wheels:
		w.static_share = clampf(lam.x + lam.y * w.position.z + lam.z * w.position.x, even * 0.25, even * 3.0)

const _DIRS: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]

## True if any of `cells` shares a face with an occupied cell outside the set.
func _touches(cells: Array[Vector3i]) -> bool:
	var own := {}
	for c in cells:
		own[c] = true
	for c in cells:
		for d in _DIRS:
			var n := c + d
			if not own.has(n) and _cells.has(n):
				return true
	return false

func _has_operational_core() -> bool:
	var core := get_block(Vector3i.ZERO)
	return core != null and core.is_operational()

## blocks: anchor -> ShipBlock. Every block must reach the core (the block filling cell 0) through face contact.
func _is_connected_to_core(blocks: Dictionary) -> bool:
	var cell_owner := {}
	for anchor in blocks:
		var b: ShipBlock = blocks[anchor]
		for c in cells_of(anchor, b.ship_size()):
			cell_owner[c] = anchor
	if not cell_owner.has(Vector3i.ZERO):
		return false
	var start: Vector3i = cell_owner[Vector3i.ZERO]
	var visited := {start: true}
	var pending: Array[Vector3i] = [start]
	while not pending.is_empty():
		var anchor: Vector3i = pending.pop_back()
		var b: ShipBlock = blocks[anchor]
		for c in cells_of(anchor, b.ship_size()):
			for d in _DIRS:
				var n: Vector3i = c + d
				if cell_owner.has(n):
					var other: Vector3i = cell_owner[n]
					if not visited.has(other):
						visited[other] = true
						pending.append(other)
	return visited.size() == blocks.size()

func _set_state(next_state: String) -> void:
	if ship_state == next_state:
		return
	ship_state = next_state
	ship_state_changed.emit(ship_state)

func _recalculate_state() -> void:
	if not _has_operational_core():
		_set_state(STATE_WRECKED)
		return
	var has_cockpit := false
	var has_propulsion := false
	for block in _gather_blocks():
		if not block.is_operational():
			continue
		if block is ShipCockpit:
			has_cockpit = true
		if block is ShipThruster or block is ShipGyroscope or block is ShipWheel:
			has_propulsion = true
	_set_state(STATE_OPERATIONAL if has_cockpit and has_propulsion else STATE_DEGRADED)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var pos := global_position
	state.apply_central_force(gravity_accel() * mass)
	# a vehicle on wheels brakes and steers through its wheels; the flight dampeners would fight them
	if dampeners_enabled and _wheels.is_empty():
		state.angular_velocity *= exp(-state.step / ANGULAR_DAMPING_TIME)
		if desired_linear_thrust.length() < 0.05 and state.linear_velocity.length() > 0.05:
			state.apply_central_force(-state.linear_velocity * mass / DAMPENER_BRAKE_TIME)

	var speed := state.linear_velocity.length()
	if speed > 0.01:
		var air_density := PlanetPhysics.get_air_density(pos)
		var drag_force := 0.5 * air_density * drag_coefficient * cross_section_area * speed * speed
		state.apply_central_force(-state.linear_velocity.normalized() * drag_force)

	_apply_thrust(state)
	_apply_wheels(state)
	_apply_rotation(state)
	_process_impacts(state)

func _process_impacts(state: PhysicsDirectBodyState3D) -> void:
	if state.linear_velocity.length() < 4.0:
		return
	for index in state.get_contact_count():
		var impulse := state.get_contact_impulse(index).length()
		# despite the name this is the contact point in global space
		var local_position: Vector3 = global_transform.affine_inverse() * state.get_contact_local_position(index)
		var cell := Vector3i(
			floori(local_position.x / CELL_SIZE),
			floori(local_position.y / CELL_SIZE),
			floori(local_position.z / CELL_SIZE)
		)
		if not _cells.has(cell):
			continue
		var frame := Engine.get_physics_frames()
		if _impact_cooldowns.get(cell, -1000) == frame:
			continue
		_impact_cooldowns[cell] = frame
		var speed := state.linear_velocity.length()
		var effective_mass := maxf(mass * 0.5, 1.0)
		var energy := maxf(0.5 * effective_mass * speed * speed, impulse)
		apply_damage(cell, energy * 0.002)

func _apply_thrust(state: PhysicsDirectBodyState3D) -> void:
	var effective_desired := desired_linear_thrust
	if dampeners_enabled and desired_linear_thrust.length() < 0.05:
		var local_vel := global_transform.basis.inverse() * state.linear_velocity
		effective_desired = -local_vel.normalized() if local_vel.length() > 0.05 else Vector3.ZERO

	for thruster in _thrusters:
		if not is_instance_valid(thruster) or not thruster.is_operational():
			continue
		if thruster is ShipRCS:
			# RCS: pushes whichever way the pilot asks, at its own (small) force
			var amount := clampf(effective_desired.length(), 0.0, 1.0)
			thruster.output = amount
			if amount > 0.0:
				var rcs_force: Vector3 = (global_transform.basis * effective_desired.normalized()) * thruster.max_force * amount
				state.apply_force(rcs_force, thruster.global_position - global_position)
			continue
		var local_dir: Vector3 = thruster.transform.basis * Vector3(0.0, 0.0, -1.0)
		var alignment := clampf(local_dir.dot(effective_desired), 0.0, 1.0)
		thruster.output = alignment
		if alignment > 0.0:
			var force: Vector3 = thruster.world_direction() * thruster.max_force * alignment
			var offset: Vector3 = thruster.global_position - global_position
			state.apply_force(force, offset)

## Wheels: each one is a raycast spring + drive + steer (ship_wheel.gd). Throttle is the controller's forward
## thrust (W/S), steering its sideways thrust (A/D) - the same inputs a ship uses, so no separate vehicle controls.
## The engines' drive force is shared over the driven wheels; with no engine the wheels only roll and brake.
func _apply_wheels(state: PhysicsDirectBodyState3D) -> void:
	if _wheels.is_empty():
		return
	var g := gravity_accel().length()
	var share := mass / _wheels.size()
	var throttle := -desired_linear_thrust.z
	var steer := -desired_linear_thrust.x
	var driven := 0
	for wheel in _wheels:
		if is_instance_valid(wheel) and wheel.driven:
			driven += 1
	var drive := _drive_force / driven if driven > 0 else 0.0
	for wheel in _wheels:
		if is_instance_valid(wheel) and wheel.is_operational():
			wheel.apply_physics(state, self, wheel.static_share if wheel.static_share > 0.0 else share, g, throttle, steer,
				center_of_mass.z, drive if wheel.driven else 0.0)

## Landing gear up / down (key G while piloting).
func toggle_landing_gear() -> void:
	for block in _gather_blocks():
		if block is ShipLandingGear:
			block.retracted = not block.retracted

## Breathable air for the pilot of a sealed cockpit: takes up to `seconds` from the oxygen tanks, returns how much
## it got.
func take_oxygen(seconds: float) -> float:
	var got := 0.0
	for block in _gather_blocks():
		if block is ShipO2Tank and block.is_operational() and got < seconds:
			var t := minf(block.oxygen_s, seconds - got)
			block.oxygen_s -= t
			got += t
	return got

func oxygen_left() -> float:
	var total := 0.0
	for block in _gather_blocks():
		if block is ShipO2Tank and block.is_operational():
			total += block.oxygen_s
	return total

func _apply_rotation(state: PhysicsDirectBodyState3D) -> void:
	if not is_operational():
		return
	var desired_world_av: Vector3 = global_transform.basis * desired_angular_velocity
	var error := desired_world_av - state.angular_velocity
	var torque := error * (_max_torque / ANGULAR_EASE_WINDOW)
	if torque.length() > _max_torque:
		torque = torque.normalized() * _max_torque
	state.apply_torque(torque)

## --- Persistence (see scripts/save/save_manager.gd) ---
##
## A ship is saved as its rigid-body state plus its block grid, and rebuilt by
## replaying add_block() cell by cell. Nothing about the mesh, mass, thrust or
## centre of mass is stored: _rebuild_stats() derives all of it from the blocks
## themselves, so a save can never disagree with the ship it describes.
##
## Blocks are keyed by `block_id`, which is also the Item id, so the block scene
## is looked up the same way the in-game build tool looks it up.

func save_state() -> Dictionary:
	var blocks: Array = []
	for cell: Vector3i in _blocks:
		var block: ShipBlock = _blocks[cell]
		if not is_instance_valid(block):
			continue
		blocks.append({
			"cell": [cell.x, cell.y, cell.z],
			"block_id": block.block_id,
			"rotation": SaveManager.vec3_to_array(block.rotation),
			"health": block.health,
			"o2": block.oxygen_s if block is ShipO2Tank else -1.0,
		})
	return {
		"transform": SaveManager.transform_to_array(global_transform),
		"linear_velocity": SaveManager.vec3_to_array(linear_velocity),
		"angular_velocity": SaveManager.vec3_to_array(angular_velocity),
		"dampeners_enabled": dampeners_enabled,
		"grid": 2,                     # cells are 0.5 m, "cell" is each block's min corner (1 = old 2 m cells)
		"blocks": blocks,
	}

func load_state(data: Dictionary) -> void:
	global_transform = SaveManager.array_to_transform(data.get("transform", []))
	dampeners_enabled = bool(data.get("dampeners_enabled", true))

	for entry: Dictionary in data.get("blocks", []):
		var item: Item = Inventory.get_item_def(String(entry.get("block_id", "")))
		if item == null or item.block_scene == null:
			push_warning("Ship.load_state: unknown block '%s', skipped." % entry.get("block_id", "?"))
			continue
		var block: ShipBlock = item.block_scene.instantiate()
		add_child(block)
		block.rotation = SaveManager.array_to_vec3(entry.get("rotation", []))
		var cell := SaveManager.array_to_vec3i(entry.get("cell", []))
		if int(data.get("grid", 1)) < 2:
			cell = legacy_anchor(cell)          # an old save: whole 2 m cells
		block.position = block_center(cell, block.ship_size())
		# add_block(), not try_add_block(): the saved layout was already
		# validated when it was built. Re-checking adjacency here would reject
		# blocks purely because of the order they happen to come out of the
		# save, since a grid is only connected once all of it is present.
		add_block(cell, block)
		block.health = float(entry.get("health", block.max_health))
		if block is ShipO2Tank and float(entry.get("o2", -1.0)) >= 0.0:
			block.oxygen_s = float(entry["o2"])

	# Velocity last: setting it before the blocks exist would be applied to a
	# body whose mass and inertia are still those of an empty ship.
	linear_velocity = SaveManager.array_to_vec3(data.get("linear_velocity", []))
	angular_velocity = SaveManager.array_to_vec3(data.get("angular_velocity", []))

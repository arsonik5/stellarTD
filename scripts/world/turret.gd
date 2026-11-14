class_name Turret
extends Building

## Ammo types this turret can fire, in priority order (see _select_ammo()).
## Deliberately NOT "every ammo works in every turret" - a turret only
## accepts item_ids that appear here, both for firing and for what
## can_accept_input() lets the player deposit at all. Mindustry-style: a
## light gun can't chamber a heavy shell.
@export var compatible_ammo: Array[AmmoType] = []
@export var ammo_per_shot: int = 1
@export var attack_range: float = 14.0
@export var fire_interval: float = 0.35
## Radians/sec the head turns to face its target. Kept fast enough that
## "couldn't quite aim in time" isn't a real failure mode at these
## ranges/speeds - _physics_process fires on cooldown+range+ammo regardless
## of the head's exact instantaneous facing (same simplification most
## Mindustry-style turrets make).
@export var head_turn_speed: float = 6.0

const ProjectileScene := preload("res://scenes/projectile.tscn")

@onready var _head: Node3D = $Head
@onready var _muzzle: Node3D = $Head/Muzzle
## The model's moving parts: the yaw fork turns about Y, the cradle between the fork arms pitches about X.
## Head stays the invisible aim node; _sync_model_head() copies its yaw/pitch onto them.
var _model_head: Node3D
var _model_cradle: Node3D
var _fire_player: AnimationPlayer

var _fire_cooldown := 0.0
var _target: Node3D = null
## item_id -> bool. Player-toggleable "don't fire this type even if I have
## it and it's compatible" (see set_ammo_enabled()/building_ui.gd's ammo
## row) - separate from compatible_ammo, which is what's physically
## possible at all vs. what the player currently wants used.
var _enabled_ammo: Dictionary = {}

func _ready() -> void:
	# Turrets don't craft - recipes stay empty so Building's auto-recipe scan
	# in _process() and its crafting Timer never activate. inventory_slots
	# here is purely an ammo box.
	recipes = []
	inventory_capacity = 400
	inventory_slots = 4
	input_capacity = 400
	output_capacity = 0
	for ammo in compatible_ammo:
		_enabled_ammo[ammo.item_id] = true
	super._ready()
	var model := get_node_or_null("Model")
	if model != null:
		_model_head = model.find_child("*_Head", true, false)
		_model_cradle = model.find_child("*_Cradle", true, false)
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_fire_player = players[0]

## Only a compatible ammo item may be deposited - Building's default would
## reject everything (no recipes to match against). Compatible-but-disabled
## ammo can still be stored (see _enabled_ammo) - disabling only stops it
## from being fired, not from being carried/held as reserve stock.
func can_accept_input(item_id: String, amount: int) -> bool:
	return is_ammo_compatible(item_id) and get_total_count() + amount <= inventory_capacity

## Turrets never produce a storable "output" item (damage isn't inventory).
func can_add_output(_item_id: String, _amount: int) -> bool:
	return false

func is_ammo_compatible(item_id: String) -> bool:
	for ammo in compatible_ammo:
		if ammo.item_id == item_id:
			return true
	return false

func is_ammo_enabled(item_id: String) -> bool:
	return _enabled_ammo.get(item_id, true)

## Ignored for an item_id this turret isn't compatible with at all (see
## is_ammo_compatible) - there's nothing meaningful to toggle for ammo it
## could never fire in the first place.
func set_ammo_enabled(item_id: String, enabled: bool) -> void:
	if is_ammo_compatible(item_id):
		_enabled_ammo[item_id] = enabled

## First compatible, enabled ammo type with enough count in inventory, in
## compatible_ammo's declared order - gives a stable, predictable priority
## when several are both enabled and in stock (e.g. prefer the cheap round,
## fall back to the expensive one only once the cheap one runs out).
func _select_ammo() -> AmmoType:
	for ammo in compatible_ammo:
		if _enabled_ammo.get(ammo.item_id, true) and get_inventory_count(ammo.item_id) >= ammo_per_shot:
			return ammo
	return null

func _physics_process(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

	# is_instance_valid() must run before _target ever gets touched by
	# anything with a statically-typed Node3D parameter below: once a target
	# dies (queue_free), GDScript's own argument type-check on a freed
	# object throws "previously freed, not a subclass of..." at the call
	# boundary, before a validity guard inside the callee's body ever runs.
	# Clearing the dangling reference here first avoids passing it anywhere.
	if _target != null and not is_instance_valid(_target):
		_target = null

	if not _is_target_valid(_target):
		_target = _find_target()

	if _target == null:
		return

	var ammo := _select_ammo()
	# Still track the target even with nothing to fire (no enabled/stocked
	# ammo) - a turret visibly watching a target it can't yet shoot reads
	# better than one that ignores it entirely. Without a chosen round there's
	# no muzzle velocity to solve a ballistic arc with, so aim flat at the
	# target itself rather than computing a (meaningless) trajectory.
	var aim_point: Vector3 = _compute_aim_point(_lead(_target, ammo), ammo) if ammo != null else _target.global_position
	_aim_at(aim_point, delta)

	if ammo != null and _fire_cooldown <= 0.0:
		_fire(ammo)

## `target` is intentionally untyped (not `Node3D`) - see the comment in
## _physics_process about why a freed object must never be passed into a
## statically-typed parameter.
func _is_target_valid(target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var h := Health.of(target)
	if h == null or h.is_dead():
		return false
	return target.global_position.distance_to(global_position) <= attack_range

## Nearest live member of the "enemy" group within range. Re-scanning only
## happens once the current target goes invalid/out-of-range/dead (see
## _physics_process), so a turret doesn't flicker between equally-close
## targets every frame.
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist := attack_range
	for node in get_tree().get_nodes_in_group("enemy"):
		if not node is Node3D or Health.of(node) == null:
			continue
		var dist: float = node.global_position.distance_to(global_position)
		if dist <= best_dist:
			best = node
			best_dist = dist
	return best

## Ballistic firing solution (flat ground / no-drag projectile-range
## formula, solved for launch angle) so a gravity-affected round actually
## lands on target instead of sailing flat and falling short - the standard
## "aim assist" simplification most ballistics games use. This is a
## deliberately separate approximation from the projectile's own actual
## simulated flight (which DOES include drag, see projectile.gd) - a real
## gunnery computer's firing solution and the round's real flight path are
## never exactly the same model either. No target-leading: EnemyDummy is
## stationary, so predicting a moving target's future position isn't
## meaningful yet (worth revisiting once real enemy movement exists).
## Falls back to aiming flat at the target if no real solution exists at
## this ammo's muzzle velocity (target technically out of THIS ammo's
## ballistic reach even though it's within attack_range - the shot will
## fall short, which is honest given the chosen round can't actually get
## there, not a bug to hide).
## Where a moving target will be when the round gets there (two passes of time-of-flight; raiders move at
## ~30 m/s, so aiming at where they ARE misses by metres at range).
func _lead(target: Node3D, ammo: AmmoType) -> Vector3:
	var vel := Vector3.ZERO
	if target is RigidBody3D:
		vel = (target as RigidBody3D).linear_velocity
	elif target is CharacterBody3D:
		vel = (target as CharacterBody3D).velocity
	var p := target.global_position
	for i in 2:
		var t := _muzzle.global_position.distance_to(p) / maxf(ammo.muzzle_velocity, 1.0)
		p = target.global_position + vel * t
	return p

func _compute_aim_point(target_pos: Vector3, ammo: AmmoType) -> Vector3:
	var up: Vector3 = global_transform.basis.y
	var to_target := target_pos - _muzzle.global_position
	var y := to_target.dot(up)
	var horizontal := to_target - up * y
	var x := horizontal.length()
	if x < 0.01:
		return target_pos

	var g := maxf(PlanetPhysics.get_gravity_accel(global_position).length(), 0.01)
	var v2 := ammo.muzzle_velocity * ammo.muzzle_velocity
	var discriminant := v2 * v2 - g * (g * x * x + 2.0 * y * v2)
	if discriminant < 0.0:
		return target_pos

	var root := sqrt(discriminant)
	var tan_theta := (v2 - root) / (g * x) # low-arc (direct-fire) root, not the lobbed one
	var theta := atan(tan_theta)
	var horiz_dir := horizontal.normalized()
	var launch_dir := (horiz_dir * cos(theta) + up * sin(theta)).normalized()
	return _muzzle.global_position + launch_dir * 10.0

## Smoothly turns the Head node (barrel+muzzle) to face target_pos, using
## Transform3D.looking_at() to compute the desired orientation and
## Basis.slerp() to ease toward it rather than snapping.
func _aim_at(target_pos: Vector3, delta: float) -> void:
	var to_target := target_pos - _head.global_position
	if to_target.length() < 0.001:
		return
	var up := global_transform.basis.y
	# looking_at() degenerates if the aim direction is ~parallel to `up`;
	# swap in a perpendicular fallback hint the same way player.gd's
	# _align_to_up() falls back for its own degenerate case.
	if absf(to_target.normalized().dot(up.normalized())) > 0.999:
		up = global_transform.basis.z
	var desired_basis := _head.global_transform.looking_at(target_pos, up).basis
	var t := clampf(head_turn_speed * delta, 0.0, 1.0)
	_head.global_transform.basis = _head.global_transform.basis.slerp(desired_basis, t)
	_sync_model_head()

## Splits the Head's facing into yaw (fork) and pitch (cradle on its trunnions), in the turret's own frame
## so it works on any slope of the spherical planet.
func _sync_model_head() -> void:
	if _model_head == null:
		return
	var dir := global_transform.basis.orthonormalized().inverse() * (-_head.global_transform.basis.z)
	if dir.length() < 0.0001:
		return
	dir = dir.normalized()
	_model_head.rotation.y = atan2(-dir.x, -dir.z)
	if _model_cradle != null:
		_model_cradle.rotation.x = asin(clampf(dir.y, -1.0, 1.0))

## Fires along the head's CURRENT facing (whatever _aim_at() has turned it
## to so far this session, mid-turn or not - same "don't wait for a perfect
## lock" simplification as the original hitscan version) at the chosen
## ammo's muzzle velocity. The actual hit/damage resolution happens later,
## in projectile.gd, once the simulated round actually arrives somewhere -
## this function only launches it.
func _fire(ammo: AmmoType) -> void:
	remove_item(ammo.item_id, ammo_per_shot)
	_fire_cooldown = fire_interval
	if _fire_player != null and _fire_player.has_animation("Fire"):
		_fire_player.stop()
		_fire_player.play("Fire")

	var launch_dir := -_head.global_transform.basis.z
	var projectile: Node3D = ProjectileScene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = _muzzle.global_position
	projectile.set_meta("faction", "player")
	WorldFx.burst("muzzle", _muzzle.global_position, launch_dir)
	WorldFx.sound("cannon" if ammo.splash_radius > 0.0 else "gun", _muzzle.global_position)
	projectile.setup(launch_dir * ammo.muzzle_velocity, ammo, get_rid())

## --- Persistence (see scripts/save/save_manager.gd) ---
## Adds the ammo toggles on top of Building's inventory/modifier/auto state.
## Cooldown and current target are deliberately not saved: both are sub-second
## and re-derived within a frame of loading.

func save_state() -> Dictionary:
	var data := super.save_state()
	data["enabled_ammo"] = _enabled_ammo.duplicate()
	return data

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	_enabled_ammo.clear()
	var saved: Dictionary = data.get("enabled_ammo", {})
	for item_id: String in saved:
		if is_ammo_compatible(item_id):
			_enabled_ammo[item_id] = bool(saved[item_id])

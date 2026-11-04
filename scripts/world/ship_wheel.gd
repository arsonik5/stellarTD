class_name ShipWheel
extends ShipBlock

## A wheel module: a mount bracket bolted to the block face it sits on, a torsion-bar housing, a trailing arm and
## the wheel on its hub. Any Ship with wheels drives like a vehicle - the same controller, the same blocks.
##
## Ship._apply_wheels() calls apply_physics() every physics tick. A ray goes from the mount straight down (the
## ship's down) to find the ground; a spring + damper push the ship up at the contact point. The springs are sized
## from the ship's weight shared over its wheels, so any build sits with its wheels at mid-travel. The wheel drives
## along its heading from the throttle (W/S), steers (A/D) if it sits ahead of the centre of mass, grips sideways,
## and brakes when there is no throttle. The visible arm and wheel follow the real spring travel and the wheel
## turns with the ground speed. The model's mount faces the block's local -X (the ship side it bolts to).

@export var radius := 0.42
## Wheel centre below the ray origin at static load, and the travel either way from there.
@export var rest_drop := 0.15
@export var travel := 0.12
## Ray origin, block-local (straight above the wheel centre).
@export var mount_local := Vector3(0.08, 0.15, 0.0)
## Trailing arm length (hinge behind the wheel, along block +Z).
@export var arm_length := 0.35
## Driven wheels share the engines' force (Ship._apply_wheels); undriven ones (landing gear) only roll and brake.
@export var driven := true
## The drive fades out toward this speed (m/s).
@export var top_speed := 20.0
@export var max_steer := 0.45
## How hard the tyre resists sliding sideways (per second).
@export var grip := 6.0

var _drop := 0.15
var _spin := 0.0
var _steer := 0.0
var contact := false
## Static load on this wheel (kg), set by Ship._compute_wheel_shares().
var static_share := 0.0

var _wheel_node: Node3D
var _arm_node: Node3D
var _wheel_rest := Vector3.ZERO

func _ready() -> void:
	super._ready()
	_drop = rest_drop
	_wheel_node = find_child("*_Wheel", true, false) as Node3D
	_arm_node = find_child("*_Arm", true, false) as Node3D
	if _wheel_node != null:
		_wheel_rest = _wheel_node.position

func apply_physics(state: PhysicsDirectBodyState3D, ship: Ship, share: float, g: float, throttle: float,
		steer_input: float, com_z: float, drive: float = 0.0) -> void:
	var up := ship.global_transform.basis.y.normalized()
	var origin := global_transform * mount_local
	var reach := rest_drop + travel + radius
	var q := PhysicsRayQueryParameters3D.create(origin, origin - up * reach)
	q.exclude = [ship.get_rid()]
	var hit := ship.get_world_3d().direct_space_state.intersect_ray(q)
	# steering wheels: the ones ahead of the centre of mass (ship forward is -Z)
	var steers := position.z < com_z - 0.05
	_steer = lerpf(_steer, steer_input * max_steer if steers else 0.0, 0.2)
	var heading := (ship.global_transform.basis * Vector3(-sin(_steer), 0.0, -cos(_steer))).normalized()
	if hit.is_empty():
		contact = false
		_drop = minf(_drop + 0.02, rest_drop + travel)
		_update_visual()
		return
	contact = true
	var dist := origin.distance_to(hit["position"])
	_drop = clampf(dist - radius, rest_drop - travel, rest_drop + travel)
	var compression := (rest_drop + travel) - (dist - radius)     # 0 hanging, travel at rest, 2 x travel bottomed
	if compression > 0.0:
		var offset: Vector3 = hit["position"] - ship.global_position
		var vel := state.get_velocity_at_local_position(offset)
		var k := share * g / travel
		var damping := 2.0 * sqrt(k * share) * 0.7
		var f_up := maxf(k * compression - damping * vel.dot(up), 0.0)
		state.apply_force(up * f_up, offset)
		var n: Vector3 = hit["normal"]
		var fwd := (heading - n * heading.dot(n)).normalized()
		var side := n.cross(fwd).normalized()
		var v_fwd := vel.dot(fwd)
		var v_side := vel.dot(side)
		var f_long := throttle * drive * clampf(1.0 - absf(v_fwd) / top_speed, 0.0, 1.0)
		if absf(throttle) < 0.05:
			f_long = -signf(v_fwd) * minf(absf(v_fwd) * share * 1.5, share * g * 0.5)   # brakes, at most half a g
		var f := fwd * f_long - side * v_side * share * grip
		var limit := f_up * 1.2                                        # tyre friction
		if f.length() > limit:
			f = f.normalized() * limit
		# tyre forces act at the axle, not the contact patch: far less pitching under power and braking
		state.apply_force(f, offset + up * (dist - radius * 0.5) * 0.0 + up * radius * 0.5)
		_spin += v_fwd * state.step / radius
	_update_visual()

func _update_visual() -> void:
	if _wheel_node != null:
		_wheel_node.position = _wheel_rest + Vector3(0.0, rest_drop - _drop, 0.0)
		# turning direction: modules on the other side of the ship are turned round
		var facing := signf(transform.basis.z.z) if absf(transform.basis.z.z) > 0.5 else 1.0
		_wheel_node.rotation = Vector3(-_spin * facing, _steer * facing, 0.0)
	if _arm_node != null:
		_arm_node.rotation.x = -asin(clampf((_drop - rest_drop) / arm_length, -0.9, 0.9))

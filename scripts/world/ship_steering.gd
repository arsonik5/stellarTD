class_name ShipSteering
extends RefCounted

## Small reusable steering-behavior toolkit producing the same abstract
## desired_linear_thrust/desired_angular_velocity inputs any Ship expects -
## shared by EnemyScoutShip today and by any future fleet ship, so AI ships
## never need their own bespoke movement code, only their own state machine
## deciding WHERE to point these functions at.

## Local-space thrust that pushes `ship` toward `target_point`. Pure seek -
## no arrival slowdown, callers that want to stop precisely (like the scout
## hovering to scan) rely on Ship's own dampener behavior once thrust drops
## to zero near the target instead of a separate braking curve.
static func seek(ship: Ship, target_point: Vector3) -> Vector3:
	var to_target: Vector3 = target_point - ship.global_position
	if to_target.length() < 0.01:
		return Vector3.ZERO
	var local_dir: Vector3 = ship.global_transform.basis.inverse() * to_target.normalized()
	return local_dir

## Local-space angular velocity that turns `ship` to point its -Z (forward)
## axis at `target_point`, capped at max_rate (rad/s). turn_gain trades
## sharpness for overshoot - same P-controller idea as Ship's own rotation
## authority, just producing the desired input rather than the torque.
static func face(ship: Ship, target_point: Vector3, turn_gain: float = 3.0, max_rate: float = 1.5) -> Vector3:
	var to_target: Vector3 = target_point - ship.global_position
	if to_target.length() < 0.01:
		return Vector3.ZERO
	var local_dir: Vector3 = (ship.global_transform.basis.inverse() * to_target).normalized()
	var forward := Vector3(0.0, 0.0, -1.0)
	var axis := forward.cross(local_dir)
	var angle := forward.angle_to(local_dir)
	if axis.length() < 0.001:
		return Vector3.ZERO
	var desired: Vector3 = axis.normalized() * angle * turn_gain
	if desired.length() > max_rate:
		desired = desired.normalized() * max_rate
	return desired

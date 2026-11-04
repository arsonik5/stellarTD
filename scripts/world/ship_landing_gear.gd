class_name ShipLandingGear
extends ShipWheel

## Landing gear: a sprung leg with a foot pad. Same raycast suspension as a wheel, but it never drives and its pad
## grips hard, so a parked ship or vehicle stays put. Retracts for flight (Ship.toggle_landing_gear, key G while
## piloting): the leg swings up and it stops touching the ground. The mount is the block's top face.
var retracted := false
var _leg: Node3D
var _foot: Node3D
var _foot_rest := Vector3.ZERO

func _ready() -> void:
	super._ready()
	driven = false
	_leg = find_child("*_Leg", true, false) as Node3D
	_foot = find_child("*_Foot", true, false) as Node3D
	if _foot != null:
		_foot_rest = _foot.position

func apply_physics(state: PhysicsDirectBodyState3D, ship: Ship, share: float, g: float, throttle: float,
		steer_input: float, com_z: float, drive: float = 0.0) -> void:
	if retracted:
		contact = false
		_update_visual()
		return
	super.apply_physics(state, ship, share, g, 0.0, 0.0, com_z, 0.0)

func _update_visual() -> void:
	if _leg != null:
		_leg.rotation.x = lerpf(_leg.rotation.x, PI * 0.5 if retracted else 0.0, 0.15)
	if _foot != null:
		_foot.position = _foot_rest + Vector3(0.0, rest_drop - _drop, 0.0)

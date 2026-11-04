class_name ShipGyroscope
extends ShipBlock

## Contributes rotational authority only - Ship sums every gyroscope's
## max_torque into one ship-wide cap used by the P-controller in
## Ship._integrate_forces(). No orientation/position of its own matters
## (real gyroscopes apply torque about the ship's own axes regardless of
## where they're mounted), so this is deliberately just a number.

@export var max_torque: float = 6000.0

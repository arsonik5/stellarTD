class_name ShipRCS
extends ShipThruster

## RCS block: small nozzles on five faces. Weak, but it pushes in whatever direction the pilot asks for (not just
## along one axis like a thruster), and adds a little turning authority (rcs_torque, summed like gyroscopes).
@export var rcs_torque: float = 800.0

class_name ShipThruster
extends ShipBlock

## Local thrust axis is always -Z (Godot's forward), same convention every
## other forward-facing node in this project uses (camera, turret head).
## `output` (0..1) is set by Ship each physics tick from the controller's
## desired_linear_thrust - this node itself holds no per-frame state beyond
## that, all summation happens in Ship._integrate_forces().

@export var max_force: float = 4000.0

var output: float = 0.0

func world_direction() -> Vector3:
	return -global_transform.basis.z

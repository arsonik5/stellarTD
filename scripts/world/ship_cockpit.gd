class_name ShipCockpit
extends ShipBlock

## The pilot's seat: where player.gd's interact raycast finds "E to enter",
## and where the first-person camera lives (the block scene has a
## "CockpitCamera" child positioned at the seat). The third-person chase
## camera lives on the Ship root instead (see ship.gd) since it needs to
## follow the whole ship, not one block.
##
## sealed: a pressurised cockpit (canopy shut) - the pilot breathes the ship's air, which refills the suit from
## the ship's oxygen tanks. An open driver seat is not sealed: the driver lives on the suit's own oxygen.
@export var sealed := true

func cockpit_camera() -> Camera3D:
	return get_node_or_null("CockpitCamera")

func ship() -> Ship:
	return get_parent() as Ship

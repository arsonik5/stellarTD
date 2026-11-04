class_name ShipEngine
extends ShipBlock

## Engine: the drive motor for wheels. A ship or vehicle's wheels only drive when it has a working engine; the
## engines' drive_force is shared over every driven wheel (Ship._apply_wheels). Without one, wheels just roll.
@export var drive_force: float = 3500.0

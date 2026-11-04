class_name ShipO2Tank
extends ShipBlock

## Oxygen tank: a store of breathable air. A SEALED cockpit on the same ship or vehicle refills its pilot's suit
## from these (Ship.take_oxygen); an open driver seat does not use them. Measured in seconds of breathing.
@export var capacity_s: float = 1200.0
var oxygen_s: float = 1200.0

func _ready() -> void:
	super._ready()
	oxygen_s = capacity_s

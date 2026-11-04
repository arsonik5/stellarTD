class_name ShipBattery
extends ShipBlock

## Battery: stored power. Power is not simulated yet - for now a battery is mass, health and a capacity number
## the ship sums (Ship.power_capacity) for the HUD and for when engines start drawing power.
@export var capacity_kwh: float = 50.0

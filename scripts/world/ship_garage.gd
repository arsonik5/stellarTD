class_name ShipGarage
extends Building

const CraftShipCore: Recipe = preload("res://data/recipes/craft_ship_core.tres")
const CraftShipHull: Recipe = preload("res://data/recipes/craft_ship_hull.tres")
const CraftShipThruster: Recipe = preload("res://data/recipes/craft_ship_thruster.tres")
const CraftShipGyroscope: Recipe = preload("res://data/recipes/craft_ship_gyroscope.tres")
const CraftShipCockpit: Recipe = preload("res://data/recipes/craft_ship_cockpit.tres")

var locked_for_building := false
var linked_ship: Ship = null

func _ready() -> void:
	recipes = [CraftShipCore, CraftShipHull, CraftShipThruster, CraftShipGyroscope, CraftShipCockpit]
	recipes.append_array(ShipParts.RECIPES)
	inventory_capacity = 300
	inventory_slots = 30
	input_capacity = 300
	output_capacity = 300
	super._ready()

func link_ship(ship: Ship) -> void:
	if linked_ship != null and is_instance_valid(linked_ship):
		linked_ship.freeze = false
	linked_ship = ship
	locked_for_building = ship != null
	if linked_ship != null:
		linked_ship.freeze = true
	changed.emit()

func unlink_ship() -> void:
	if linked_ship != null and is_instance_valid(linked_ship):
		linked_ship.freeze = false
	linked_ship = null
	locked_for_building = false
	changed.emit()

func can_edit_ship() -> bool:
	return linked_ship != null and is_instance_valid(linked_ship) and linked_ship.is_player_ship

func get_manifest() -> Dictionary:
	if not can_edit_ship():
		return {"blocks": 0, "mass": 0.0, "health": 0.0, "max_health": 0.0}
	var health := 0.0
	var max_health := 0.0
	for cell in linked_ship.get_block_cells():
		var block := linked_ship.get_block(cell)
		health += block.health
		max_health += block.max_health
	return {
		"blocks": linked_ship.get_block_cells().size(),
		"mass": linked_ship.mass,
		"health": health,
		"max_health": max_health,
		"state": linked_ship.ship_state,
	}

func repair_ship(amount: float = 25.0) -> float:
	if not can_edit_ship():
		return 0.0
	var restored := linked_ship.repair_all(amount)
	if restored > 0.0:
		changed.emit()
	return restored

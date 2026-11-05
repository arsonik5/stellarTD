extends Building

const CraftPiercingCore: Recipe = preload("res://data/recipes/craft_piercing_core.tres")
const CraftCopperCasing: Recipe = preload("res://data/recipes/craft_copper_casing.tres")
const CraftGunpowder: Recipe = preload("res://data/recipes/craft_gunpowder.tres")
const CraftIronPiercingAmmo: Recipe = preload("res://data/recipes/craft_iron_piercing_ammo.tres")
const CraftHeShell: Recipe = preload("res://data/recipes/craft_he_shell.tres")
const CraftShipCore: Recipe = preload("res://data/recipes/craft_ship_core.tres")
const CraftShipHull: Recipe = preload("res://data/recipes/craft_ship_hull.tres")
const CraftShipThruster: Recipe = preload("res://data/recipes/craft_ship_thruster.tres")
const CraftShipGyroscope: Recipe = preload("res://data/recipes/craft_ship_gyroscope.tres")
const CraftShipCockpit: Recipe = preload("res://data/recipes/craft_ship_cockpit.tres")
const CraftCopperWire: Recipe = preload("res://data/recipes/craft_copper_wire.tres")
const CraftCircuit: Recipe = preload("res://data/recipes/craft_circuit.tres")
const CraftConcrete: Recipe = preload("res://data/recipes/craft_concrete.tres")
const CraftCrystalCell: Recipe = preload("res://data/recipes/craft_crystal_cell.tres")

func _ready() -> void:
	recipes = [
		CraftCopperWire, CraftCircuit, CraftConcrete, CraftCrystalCell,
		CraftPiercingCore, CraftCopperCasing, CraftGunpowder, CraftIronPiercingAmmo, CraftHeShell,
		CraftShipCore, CraftShipHull, CraftShipThruster, CraftShipGyroscope, CraftShipCockpit,
	]
	recipes.append_array(ShipParts.RECIPES)
	inventory_capacity = 150
	inventory_slots = 24
	input_capacity = 60
	output_capacity = 60
	power_draw = 20.0
	super._ready()

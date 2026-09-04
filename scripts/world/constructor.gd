extends Building

const CraftPiercingCore: Recipe = preload("res://data/recipes/craft_piercing_core.tres")
const CraftCopperCasing: Recipe = preload("res://data/recipes/craft_copper_casing.tres")
const CraftGunpowder: Recipe = preload("res://data/recipes/craft_gunpowder.tres")
const CraftIronPiercingAmmo: Recipe = preload("res://data/recipes/craft_iron_piercing_ammo.tres")
const CraftHeShell: Recipe = preload("res://data/recipes/craft_he_shell.tres")

func _ready() -> void:
	recipes = [CraftPiercingCore, CraftCopperCasing, CraftGunpowder, CraftIronPiercingAmmo, CraftHeShell]
	inventory_capacity = 150
	inventory_slots = 24
	input_capacity = 60
	output_capacity = 60
	super._ready()

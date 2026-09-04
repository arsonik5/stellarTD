extends CanvasLayer

const IRON_ORE_ID := "ore_a"
const COPPER_ORE_ID := "ore_b"
const SULFUR_ID := "sulfur"
const COAL_ID := "ore_coal"
const SILICA_ID := "ore_silica"
const IRON_INGOT_ID := "refined_material"
const COPPER_INGOT_ID := "refined_copper_ingot"
const CARBON_INGOT_ID := "refined_carbon"
const SILICA_GLASS_ID := "refined_silica"

@onready var label: Label = $Label

func _ready() -> void:
	Inventory.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	label.text = "Iron Ore: %d\nCopper Ore: %d\nSulfur: %d\nCoal: %d\nSilica: %d\nIron Ingot: %d\nCopper Ingot: %d\nCarbon Ingot: %d\nSilica Glass: %d" % [
		Inventory.get_count(IRON_ORE_ID),
		Inventory.get_count(COPPER_ORE_ID),
		Inventory.get_count(SULFUR_ID),
		Inventory.get_count(COAL_ID),
		Inventory.get_count(SILICA_ID),
		Inventory.get_count(IRON_INGOT_ID),
		Inventory.get_count(COPPER_INGOT_ID),
		Inventory.get_count(CARBON_INGOT_ID),
		Inventory.get_count(SILICA_GLASS_ID),
	]

extends Building

const SmeltIron: Recipe = preload("res://data/recipes/smelt_iron.tres")
const SmeltCopper: Recipe = preload("res://data/recipes/smelt_copper.tres")
const SmeltCoal: Recipe = preload("res://data/recipes/smelt_coal.tres")
const SmeltSilica: Recipe = preload("res://data/recipes/smelt_silica.tres")
const SmeltSteel: Recipe = preload("res://data/recipes/smelt_steel.tres")

func _ready() -> void:
	recipes = [SmeltIron, SmeltCopper, SmeltCoal, SmeltSilica, SmeltSteel]
	power_draw = 15.0
	super._ready()

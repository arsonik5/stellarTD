extends Building

const IronIngotRecipe: Recipe = preload("res://data/recipes/refine_ore_a.tres")
const CopperIngotRecipe: Recipe = preload("res://data/recipes/refine_ore_b.tres")
const CarbonIngotRecipe: Recipe = preload("res://data/recipes/refine_ore_coal.tres")
const SilicaGlassRecipe: Recipe = preload("res://data/recipes/refine_ore_silica.tres")

func _ready() -> void:
	recipes = [IronIngotRecipe, CopperIngotRecipe, CarbonIngotRecipe, SilicaGlassRecipe]
	power_draw = 5.0
	super._ready()

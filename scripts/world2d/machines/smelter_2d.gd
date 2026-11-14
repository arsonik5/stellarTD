extends Building2D
## Smelter, 2x2: same recipes as the 3D smelter (scripts/world/smelter.gd).

func _init() -> void:
	item_id = "smelter"
	display_name = "Smelter"
	size = Vector2i(2, 2)
	height_px = 16.0
	colour = Color("#e4e6ee")
	power_draw = 15.0
	recipes = [preload("res://data/recipes/smelt_iron.tres"), preload("res://data/recipes/smelt_copper.tres"),
		preload("res://data/recipes/smelt_coal.tres"), preload("res://data/recipes/smelt_silica.tres"),
		preload("res://data/recipes/smelt_steel.tres")]

func _ready() -> void:
	super._ready()
	# a smelter just placed runs whatever it is fed (P1: no recipe UI yet)
	for i in recipes.size():
		set_auto(i, true)

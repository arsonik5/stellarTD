extends Building2D
## Constructor, 3x3: the 3D constructor's recipe list (scripts/world/constructor.gd).

func _init() -> void:
	item_id = "constructor"
	display_name = "Constructor"
	size = Vector2i(3, 3)
	height_px = 18.0
	colour = Color("#d4dce8")
	power_draw = 20.0
	inventory_capacity = 150

func _ready() -> void:
	recipes = _constructor_recipes()
	super._ready()

static func _constructor_recipes() -> Array[Recipe]:
	var out: Array[Recipe] = []
	for p in ["craft_copper_wire", "craft_circuit", "craft_concrete", "craft_crystal_cell", "craft_speed_module",
			"craft_efficiency_module", "craft_yield_module", "craft_rivet_gun", "craft_piercing_core",
			"craft_copper_casing", "craft_gunpowder", "craft_iron_piercing_ammo", "craft_he_shell"]:
		out.append(load("res://data/recipes/%s.tres" % p))
	return out

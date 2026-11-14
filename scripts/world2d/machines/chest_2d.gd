extends Building2D
## Storage, 1x1: takes anything a belt brings, gives anything to a belt pointing away.

func _init() -> void:
	item_id = "chest"
	display_name = "Chest"
	size = Vector2i(1, 1)
	height_px = 8.0
	colour = Color("#868a9e")
	recipes = []
	accepts_any_item = true
	inventory_capacity = 300
	inventory_slots = 30

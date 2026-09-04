extends Building

func _ready() -> void:
	recipes = []
	accepts_any_item = true
	inventory_capacity = 300
	inventory_slots = 30
	input_capacity = 300
	output_capacity = 0
	super._ready()

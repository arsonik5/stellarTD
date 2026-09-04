class_name Recipe
extends Resource

@export var input_ids: Array[String] = []
@export var input_amounts: Array[int] = []
@export var output_id: String
@export var output_amount: int = 1
@export var process_time: float = 1.0

func has_input(item_id: String) -> bool:
	return input_ids.has(item_id)

func get_input_amount(item_id: String) -> int:
	var index := input_ids.find(item_id)
	return input_amounts[index] if index != -1 else 0

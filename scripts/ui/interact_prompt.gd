extends CanvasLayer

@onready var label: Label = $Label

func _ready() -> void:
	add_to_group("interact_prompt")
	visible = false

func show_prompt(text: String) -> void:
	label.text = text
	visible = true

func hide_prompt() -> void:
	visible = false

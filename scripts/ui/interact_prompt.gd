extends CanvasLayer
## The one interaction prompt: a key cap and a verb + name, just under the crosshair - "[E] Open Smelter".
## Shown by player.gd while the crosshair rests on something usable; hidden while a menu is open.

var _holder: CenterContainer
var _shown := ""

func _ready() -> void:
	add_to_group("interact_prompt")
	layer = 11
	_holder = CenterContainer.new()
	_holder.anchor_right = 1.0
	_holder.anchor_top = 0.5
	_holder.anchor_bottom = 0.5
	_holder.offset_top = 28
	_holder.offset_bottom = 60
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	visible = false
	UiState.changed.connect(func() -> void: _holder.visible = not UiState.is_any_open())

## show_prompt("E", "Open Smelter"). One argument is read as the text, with E as the key.
func show_prompt(key_or_text: String, text: String = "") -> void:
	if text == "":
		text = key_or_text
		key_or_text = "E"
	var sig := key_or_text + "|" + text
	if sig != _shown:
		_shown = sig
		for c in _holder.get_children():
			c.queue_free()
		var h := UiKit.hint(key_or_text, text, true)
		_holder.add_child(h)
		h.modulate.a = 0.0
		h.create_tween().tween_property(h, "modulate:a", 1.0, 0.12)
	visible = true

func hide_prompt() -> void:
	visible = false

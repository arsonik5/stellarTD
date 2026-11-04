extends Node

## Tracks which modal GUIs/modes are currently open, so any presentation
## layer (the HUD, later a crosshair, etc.) can react generically to "is
## something taking over the screen right now" without each GUI having to
## know about every other GUI. Every full-screen GUI (inventory, building
## panel, build mode, journal, ...) registers itself here via set_open()
## with its own id under add/remove; nothing here is specific to any one of
## them, so a future GUI just calls set_open(its_own_id, ...) to participate.
signal changed

var _open: Dictionary = {}

func set_open(id: String, is_open: bool) -> void:
	var was_any := is_any_open()
	if is_open:
		_open[id] = true
	else:
		_open.erase(id)
	if is_any_open() != was_any:
		changed.emit()

func is_any_open() -> bool:
	return not _open.is_empty()

extends PipeSegment

var _last_output_index := 0
## The distributor drive (coupling under the gear motor) turns while an item is passing through.
var _rotor_player: AnimationPlayer
var _rotor_anim := ""

func _process(_delta: float) -> void:
	if _rotor_player == null:
		var players := find_children("*", "AnimationPlayer", true, false)
		if players.is_empty():
			set_process(false)
			return
		_rotor_player = players[0]
		for anim_name in _rotor_player.get_animation_list():
			if String(anim_name).begins_with("Working"):
				_rotor_anim = anim_name
				_rotor_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	if _rotor_anim == "":
		return
	var busy := _held_item_id != ""
	if busy and not _rotor_player.is_playing():
		_rotor_player.play(_rotor_anim)
	elif not busy and _rotor_player.is_playing():
		_rotor_player.pause()

func get_connection_points() -> Array[Vector3]:
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	return [
		global_position - fwd * 0.5,
		global_position + fwd * 0.5,
		global_position + right * 0.5,
		global_position - right * 0.5,
	]

## Front, left, right relative to forward() - a Splitter's 3 possible
## downstream cells (its one fixed input is the base class's back cell).
func _downstream_cells() -> Array[Vector3i]:
	var fwd := forward()
	var right := Vector3i(-fwd.z, 0, fwd.x)
	var left := Vector3i(fwd.z, 0, -fwd.x)
	return [grid_pos + fwd, grid_pos + left, grid_pos + right]

func _try_advance() -> void:
	var cells := _downstream_cells()
	for offset in cells.size():
		var index := (_last_output_index + offset) % cells.size()
		var target := PipeNetwork.get_node_at(cells[index])
		if target == null:
			continue
		var moved := false
		if target is PipeSegment:
			moved = target.pipe_accept(_held_item_id, grid_pos)
		elif target is Building:
			moved = target.add_input(_held_item_id, 1) > 0
		if moved:
			_last_output_index = (index + 1) % cells.size()
			_held_item_id = ""
			_progress = 0.0
			_item_cube.visible = false
			return

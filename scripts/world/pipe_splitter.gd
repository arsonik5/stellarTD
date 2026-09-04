extends PipeSegment

var _last_output_index := 0

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

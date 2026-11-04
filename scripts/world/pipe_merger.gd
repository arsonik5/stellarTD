extends PipeSegment

var _last_input_cursor := 0

func get_connection_points() -> Array[Vector3]:
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	return [
		global_position + fwd * 0.5,
		global_position - fwd * 0.5,
		global_position + right * 0.5,
		global_position - right * 0.5,
	]

## Back, left, right relative to forward() - a Merger's 3 possible upstream
## cells (its one fixed output is forward()).
func _upstream_cells() -> Array[Vector3i]:
	var fwd := forward()
	var right := Vector3i(-fwd.z, 0, fwd.x)
	var left := Vector3i(fwd.z, 0, -fwd.x)
	return [grid_pos - fwd, grid_pos + left, grid_pos + right]

## Fairness gate: without this, whichever upstream segment's _physics_process
## happens to run first in scene-tree order would win every single cycle this
## Merger empties (a fixed bias, not round-robin) since a plain pipe_accept()
## call carries no caller identity to arbitrate between simultaneous pushers.
## Only accept the currently-favored upstream cell unless it has nothing ready.
func pipe_accept(item_id: String, from_grid_pos: Vector3i = Vector3i.ZERO) -> bool:
	if _held_item_id != "":
		return false
	var cells := _upstream_cells()
	var favored: Vector3i = cells[_last_input_cursor]
	if from_grid_pos != favored:
		var favored_node := PipeNetwork.get_node_at(favored)
		if favored_node is PipeSegment and favored_node.has_ready_item():
			return false
	_last_input_cursor = (_last_input_cursor + 1) % cells.size()
	return super.pipe_accept(item_id, from_grid_pos)

func _try_pull_from_input_side() -> void:
	for cell in _upstream_cells():
		var source := PipeNetwork.get_node_at(cell)
		if source == null or not (source is Building):
			continue
		var building: Building = source
		for recipe in building.recipes:
			var output_id: String = recipe.output_id
			if building.get_inventory_count(output_id) > 0 and building.remove_item(output_id, 1):
				pipe_accept(output_id, cell)
				return

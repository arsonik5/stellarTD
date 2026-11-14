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

## Ports in 3D: three inlets (back, left, right) and one outlet (front). Order matters: [front, back, right, left]
## from get_connection_points().
func input_ports() -> Array[Vector3]:
	var c := get_connection_points()
	return [c[1], c[3], c[2]]

func output_ports() -> Array[Vector3]:
	return [get_connection_points()[0]]

## Fairness gate: without this, whichever upstream segment's _physics_process
## happens to run first in scene-tree order would win every single cycle this
## Merger empties (a fixed bias, not round-robin) since a plain pipe_accept()
## call carries no caller identity to arbitrate between simultaneous pushers.
## Only accept the currently-favored inlet unless nothing is waiting there.
## The caller is identified by its grid_pos, matched against the piece whose outlet sits on each inlet.
func pipe_accept(item_id: String, from_grid_pos: Vector3i = Vector3i.ZERO) -> bool:
	if _held_item_id != "":
		return false
	var ports := input_ports()
	var favored := _piece_with_port_near(ports[_last_input_cursor], false)
	if favored != null and favored.grid_pos != from_grid_pos and favored.has_ready_item():
		return false
	_last_input_cursor = (_last_input_cursor + 1) % ports.size()
	return super.pipe_accept(item_id, from_grid_pos)

func _try_pull_from_input_side() -> void:
	for port in input_ports():
		var source := _building_at(port + _outward(port) * 0.4 + global_transform.basis.y * 0.3)
		if source == null or not (source is Building):
			continue
		var building: Building = source
		for recipe in building.recipes:
			var output_id: String = recipe.output_id
			if building.get_inventory_count(output_id) > 0 and building.remove_item(output_id, 1):
				pipe_accept(output_id, grid_pos)
				return

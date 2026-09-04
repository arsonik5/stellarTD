extends Node

var _cells: Dictionary = {}

func register(grid_pos: Vector3i, node: Node) -> void:
	_cells[grid_pos] = node

func get_node_at(grid_pos: Vector3i) -> Node:
	var node: Node = _cells.get(grid_pos)
	if node != null and not is_instance_valid(node):
		_cells.erase(grid_pos)
		return null
	return node

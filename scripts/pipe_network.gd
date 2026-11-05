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

## Drop every cell that points at `node` (dismantled / destroyed). Lookups also prune freed nodes lazily, but an
## explicit removal keeps a queued-for-deletion node from receiving items during the frame it still exists.
func unregister_node(node: Node) -> void:
	for cell in _cells.keys():
		if _cells[cell] == node:
			_cells.erase(cell)

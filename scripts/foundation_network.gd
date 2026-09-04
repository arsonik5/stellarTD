extends Node

## Flat list, not a spatial grid: foundations (and the buildings that mount
## on them) can end up anywhere in world space at any orientation, so unlike
## PipeNetwork there's no fixed axis-aligned cell size to key a dictionary
## on. Foundation counts in a hobby-scale base are small enough that a linear
## nearest-neighbor scan is simpler and more robust than a spatial hash here.

var _foundations: Array[Node] = []

func register(node: Node) -> void:
	_foundations.append(node)

## Nearest registered foundation to `pos` within `max_dist`, or null. Prunes
## freed foundations encountered along the way (no explicit unregister path
## exists yet - no building-removal system exists anywhere in this project).
func find_nearest(pos: Vector3, max_dist: float) -> Node:
	var best: Node = null
	var best_dist := max_dist
	var i := 0
	while i < _foundations.size():
		var f: Node = _foundations[i]
		if not is_instance_valid(f):
			_foundations.remove_at(i)
			continue
		var d: float = f.global_position.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = f
		i += 1
	return best

class_name BeltSystem
extends Node2D

## Conveyor belts as data (docs/game/design/pivot-2d.md 5.2). Belts are grouped into LINES (a run of belt tiles in
## one direction chain); a line stores its items as GAPS, Factorio-style: gap[0] = distance from the line's end to
## the first item, gap[i] = distance from item i-1 to item i. Moving the line means shrinking ONE gap (the first
## one that can still close), so a compressed belt costs nothing per tick, however many items it carries.
##
## Simulation: `step(dt)` on the factory clock. Drawing: one MultiMesh for every item in view, positions computed
## from the gaps each frame; belts themselves are drawn as one MultiMesh of tile quads.
##
## Spike scope: straight lines and lines that feed another line at their end (loops included). Turns, junctions,
## routers, bridges and lifts build on the same line model in P1.

const ITEM_SPACING := 0.25          ## tiles between two items (4 items per tile when compressed)
const SPEED := 2.0                  ## tiles per second (mk1)

class Line:
	var start := Vector2.ZERO       ## world px, tile centre of the first tile
	var dir := Vector2.RIGHT        ## unit direction, items move this way
	var length := 1.0               ## tiles
	var gaps := PackedFloat32Array()
	var item_ids := PackedInt32Array()
	var next := -1                  ## index of the line this one feeds, -1 = end (items stop)
	var level := 0                  ## elevation (draw offset)

var lines: Array[Line] = []
var _items_mm: MultiMeshInstance2D
var _belts_mm: MultiMeshInstance2D
var camera: Camera2D
var item_colours := [Color(0.85, 0.45, 0.25), Color(0.85, 0.6, 0.3), Color(0.25, 0.25, 0.27), Color(0.8, 0.85, 0.9)]

func _ready() -> void:
	_belts_mm = _make_mm(Vector2(30, 22), Color(0.22, 0.22, 0.24))
	_items_mm = _make_mm(Vector2(8, 8), Color.WHITE)
	add_child(_belts_mm)
	add_child(_items_mm)

func _make_mm(size: Vector2, col: Color) -> MultiMeshInstance2D:
	var q := QuadMesh.new()
	q.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = q
	var mi := MultiMeshInstance2D.new()
	mi.multimesh = mm
	mi.self_modulate = col
	return mi

func add_line(start_tile: Vector2i, dir: Vector2i, length_tiles: int, level: int = 0) -> int:
	var l := Line.new()
	l.start = (Vector2(start_tile) + Vector2(0.5, 0.5)) * WorldGrid.TILE_PX
	l.dir = Vector2(dir)
	l.length = float(length_tiles)
	l.level = level
	lines.append(l)
	_rebuild_belt_mesh()
	return lines.size() - 1

## Puts up to `count` items on a line, evenly from its end backwards. Returns how many fit.
func fill(line_idx: int, count: int, spacing: float = ITEM_SPACING) -> int:
	var l := lines[line_idx]
	var used := 0.0
	for g in l.gaps:
		used += g
	var put := 0
	while put < count and used + spacing <= l.length:
		var gap := 0.0 if l.gaps.is_empty() else spacing
		l.gaps.append(gap)
		l.item_ids.append(put % item_colours.size())
		used += gap
		put += 1
	return put

func item_count() -> int:
	var n := 0
	for l in lines:
		n += l.gaps.size()
	return n

## Advance every line by dt seconds. Cost per line = the number of leading gaps that are already closed (usually 0).
func step(dt: float) -> void:
	var move := SPEED * dt
	for li in lines.size():
		var l := lines[li]
		if l.gaps.is_empty():
			continue
		var budget := move
		var k := 0
		var n := l.gaps.size()
		# hand the front item over when it reached the end and the next line has room at its start
		if l.gaps[0] <= 0.0 and l.next >= 0:
			var nl := lines[l.next]
			if _room_at_start(nl):
				_push_start(nl, l.item_ids[0])
				var rest := l.gaps[1] if n > 1 else 0.0
				l.gaps.remove_at(0)
				l.item_ids.remove_at(0)
				if not l.gaps.is_empty():
					l.gaps[0] = rest
				n -= 1
				if n == 0:
					continue
		while budget > 0.0 and k < n:
			var min_gap := 0.0 if k == 0 else ITEM_SPACING
			var can := l.gaps[k] - min_gap
			if can > 0.0:
				var d := minf(can, budget)
				l.gaps[k] -= d
				budget -= d
				if k + 1 < n:
					l.gaps[k + 1] += d     # the items behind keep their place: only this gap closes
				break
			k += 1

func _room_at_start(l: Line) -> bool:
	var used := 0.0
	for g in l.gaps:
		used += g
	return used + ITEM_SPACING <= l.length

func _push_start(l: Line, id: int) -> void:
	var used := 0.0
	for g in l.gaps:
		used += g
	l.gaps.append(l.length - used if l.gaps.is_empty() else maxf(l.length - used, ITEM_SPACING))
	l.item_ids.append(id)

## Item positions for drawing (only lines whose box touches `view`).
func _process(_dt: float) -> void:
	if camera == null:
		return
	var vp := get_viewport_rect().size / camera.zoom
	var view := Rect2(camera.global_position - vp * 0.5, vp).grow(64)
	var mm := _items_mm.multimesh
	var total := item_count()
	if mm.instance_count < total:
		mm.instance_count = total
	var t := WorldGrid.TILE_PX
	var shown := 0
	for l in lines:
		var end_px := l.start + l.dir * (l.length - 0.5) * t
		var box := Rect2(l.start, Vector2.ZERO).expand(end_px).grow(t)
		if not view.intersects(box):
			continue
		var lift := Vector2(0, -l.level * WorldGrid.LEVEL_PX)
		var dist := 0.0
		for i in l.gaps.size():
			dist += l.gaps[i]
			var p := end_px - l.dir * dist * t + lift
			mm.set_instance_transform_2d(shown, Transform2D(0.0, p))
			mm.set_instance_color(shown, item_colours[l.item_ids[i]])
			shown += 1
	mm.visible_instance_count = shown

func _rebuild_belt_mesh() -> void:
	var tiles := 0
	for l in lines:
		tiles += int(l.length)
	var mm := _belts_mm.multimesh
	mm.instance_count = tiles
	var i := 0
	for l in lines:
		for k in int(l.length):
			var p := l.start + l.dir * k * WorldGrid.TILE_PX + Vector2(0, -l.level * WorldGrid.LEVEL_PX)
			mm.set_instance_transform_2d(i, Transform2D(l.dir.angle(), p))
			mm.set_instance_color(i, Color.WHITE)
			i += 1

class_name WorldMapView
extends Node2D

## Draws a WorldGrid with height (docs/game/design/pivot-2d.md 4.2). Only chunks near the camera exist as nodes.
##
## Each chunk is cut into one MeshInstance2D per tile ROW, all Y-sorted together with buildings and units under
## this node. That is what makes height read correctly: a raised row further down the screen is drawn later and
## covers whatever stands behind it, so a unit at the foot of a cliff disappears behind the plateau in front of it.
## Row strip origin = top edge of the row on the level-0 plane; anything standing on row r sits at y = r*32 + 16,
## between strip r and strip r+1 in the sort.

const BUILD_PER_FRAME := 2       ## chunk meshes built per frame (spreads the cost while panning)
const KEEP_MARGIN_CHUNKS := 1    ## chunks kept alive outside the view before they are freed

var grid: WorldGrid
var camera: Camera2D
var _chunks := {}                # Vector2i -> Node2D (chunk root)
var _queue: Array[Vector2i] = []

const GROUND_COLOURS := {
	WorldGrid.Ground.REGOLITH: Color(0.47, 0.45, 0.42),
	WorldGrid.Ground.GRAVEL: Color(0.40, 0.39, 0.38),
	WorldGrid.Ground.SAND: Color(0.62, 0.53, 0.40),
	WorldGrid.Ground.BASALT: Color(0.30, 0.29, 0.31),
	WorldGrid.Ground.ICE: Color(0.62, 0.72, 0.78),
}

func _ready() -> void:
	y_sort_enabled = true

func setup(g: WorldGrid, cam: Camera2D) -> void:
	grid = g
	camera = cam

func chunk_count() -> int:
	return _chunks.size()

func _process(_dt: float) -> void:
	if grid == null or camera == null:
		return
	var need := _visible_chunks()
	for c: Vector2i in need:
		if not _chunks.has(c) and not _queue.has(c):
			_queue.append(c)
	# nearest first
	var cc := Vector2i(camera.global_position / float(WorldGrid.TILE_PX * WorldGrid.CHUNK))
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - cc).length_squared() < (b - cc).length_squared())
	var built := 0
	while built < BUILD_PER_FRAME and not _queue.is_empty():
		var c: Vector2i = _queue.pop_front()
		if need.has(c) and not _chunks.has(c):
			_chunks[c] = _build_chunk(c)
			built += 1
	# free chunks well outside the view
	for c: Vector2i in _chunks.keys():
		if not _near(c, need):
			(_chunks[c] as Node).queue_free()
			_chunks.erase(c)

## Builds every chunk the camera currently sees, now (tests and first frame use it).
func build_visible_now() -> void:
	for c: Vector2i in _visible_chunks():
		if not _chunks.has(c):
			_chunks[c] = _build_chunk(c)

func _visible_chunks() -> Array[Vector2i]:
	var vp := get_viewport_rect().size / camera.zoom
	var tl := camera.global_position - vp * 0.5
	var br := camera.global_position + vp * 0.5
	# a tile can be drawn up to MAX_LEVEL * LEVEL_PX above its row: look that far below the screen
	br.y += WorldGrid.MAX_LEVEL * WorldGrid.LEVEL_PX
	tl.y -= -WorldGrid.MIN_LEVEL * WorldGrid.LEVEL_PX
	var cs := float(WorldGrid.TILE_PX * WorldGrid.CHUNK)
	var out: Array[Vector2i] = []
	for cy in range(maxi(int(floor(tl.y / cs)), 0), mini(int(floor(br.y / cs)), grid.chunks_y() - 1) + 1):
		for cx in range(maxi(int(floor(tl.x / cs)), 0), mini(int(floor(br.x / cs)), grid.chunks_x() - 1) + 1):
			out.append(Vector2i(cx, cy))
	return out

func _near(c: Vector2i, need: Array[Vector2i]) -> bool:
	for n: Vector2i in need:
		if absi(n.x - c.x) <= KEEP_MARGIN_CHUNKS and absi(n.y - c.y) <= KEEP_MARGIN_CHUNKS:
			return true
	return false

## Rebuilds the chunk that holds tile (x, y) and the one above it (a level change moves a cliff face that can
## belong to the row above's chunk).
func refresh_tile(x: int, y: int) -> void:
	for c: Vector2i in [Vector2i(x / WorldGrid.CHUNK, y / WorldGrid.CHUNK), Vector2i(x / WorldGrid.CHUNK, (y - 1) / WorldGrid.CHUNK)]:
		if _chunks.has(c):
			(_chunks[c] as Node).queue_free()
			_chunks[c] = _build_chunk(c)

func _build_chunk(c: Vector2i) -> Node2D:
	var root := Node2D.new()
	root.name = "Chunk_%d_%d" % [c.x, c.y]
	root.y_sort_enabled = true
	add_child(root)
	var t := WorldGrid.TILE_PX
	var lp := WorldGrid.LEVEL_PX
	var x0 := c.x * WorldGrid.CHUNK
	var y0 := c.y * WorldGrid.CHUNK
	for ry in WorldGrid.CHUNK:
		var y := y0 + ry
		if y >= grid.height:
			break
		var verts := PackedVector2Array()
		var cols := PackedColorArray()
		for rx in WorldGrid.CHUNK:
			var x := x0 + rx
			if x >= grid.width:
				break
			var lv := grid.level_at(x, y)
			var top := float(-lv * lp)
			var g := int(grid.ground[grid.idx(x, y)])
			var base: Color = GROUND_COLOURS.get(g, Color.MAGENTA)
			# higher ground slightly lighter; a per-tile checker jitter so the grid is readable in the spike
			var col := base.lightened(0.05 * lv) if lv > 0 else base.darkened(0.06 * -lv)
			col = col.lightened(0.025) if ((x + y) & 1) == 0 else col
			# contact shadow: ground right in front of a higher row is darker (the cliff above shades it)
			var lv_back := grid.level_at(x, y - 1)
			if lv_back > lv:
				col = col.darkened(0.22)
			_quad(verts, cols, Rect2(rx * t, top, t, t), col)
			# front cliff face down to the row in front: rock bands (strata), darkest at the foot
			var lv_front := grid.level_at(x, y + 1)
			if lv_front < lv:
				var steps := lv - lv_front
				for k in steps:
					var band := base.darkened(0.42 + 0.10 * float(k) / float(maxi(steps, 1)))
					_quad(verts, cols, Rect2(rx * t, top + t + k * lp, t, lp * 0.5), band)
					_quad(verts, cols, Rect2(rx * t, top + t + k * lp + lp * 0.5, t, lp * 0.5), band.darkened(0.12))
				# lit lip on the cliff edge
				_quad(verts, cols, Rect2(rx * t, top + t - 3, t, 3), base.lightened(0.3))
			# side edges: a dark line where the tile to the left/right is lower, so plateau outlines read
			if grid.level_at(x - 1, y) < lv:
				_quad(verts, cols, Rect2(rx * t, top, 2, t), base.darkened(0.3))
			if grid.level_at(x + 1, y) < lv:
				_quad(verts, cols, Rect2(rx * t + t - 2, top, 2, t), base.darkened(0.3))
		var mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance2D.new()
		mi.mesh = mesh
		mi.position = Vector2(x0 * t, y * t)
		root.add_child(mi)
	return root

static func _quad(v: PackedVector2Array, c: PackedColorArray, r: Rect2, col: Color) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var d := Vector2(r.position.x, r.end.y)
	var e := r.end
	v.append_array([a, b, e, a, e, d])
	for i in 6:
		c.append(col)

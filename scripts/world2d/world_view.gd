class_name WorldView
extends Node2D

## Terrain renderer v2 for the straight-down camera (pivot-2d.md 4.2 + 6.1). Replaces the 3/4-tilt WorldMapView of
## the P0 spike.
##
## Every vertex carries its real height (UV.x, px); the lean shader moves it away from the screen centre by
## height / CAM_HEIGHT, so cliffs and mountains lean like a perspective camera looking down (Unfallen). Each chunk
## is split into one mesh per elevation LEVEL, drawn with z_index by level: higher ground is drawn later and
## covers what is behind it. Inside a level mesh, cliff walls come first and tops last, so a top hides its own
## inner walls and only the walls on the far side from the camera show.
##
## Things standing in the world use `z_for_level(level)` so terrain one level up is drawn over them.

const CAM_HEIGHT := 360.0
const BUILD_PER_FRAME := 2
const KEEP_MARGIN := 1

var grid: WorldGrid
var camera: Camera2D
var material_lean: ShaderMaterial
var _chunks := {}            # Vector2i -> Node2D
var _queue: Array[Vector2i] = []

const GROUND_COLOURS := {
	WorldGrid.Ground.REGOLITH: Color("#76695d"),
	WorldGrid.Ground.GRAVEL: Color("#64605c"),
	WorldGrid.Ground.SAND: Color("#9a8264"),
	WorldGrid.Ground.BASALT: Color("#4a474e"),
	WorldGrid.Ground.ICE: Color("#a9bcc6"),
}
const ORE_COLOURS := [Color.TRANSPARENT, Color("#c8683a"), Color("#d89a48"), Color("#2c2b30"), Color("#d8e6ee"),
	Color("#e4cc44"), Color("#a070e8")]

## z for things standing on `level`: above that level's terrain, below the next level's.
static func z_for_level(level: int) -> int:
	return (level - WorldGrid.MIN_LEVEL) * 2 + 1

func setup(g: WorldGrid, cam: Camera2D) -> void:
	grid = g
	camera = cam
	material_lean = ShaderMaterial.new()
	material_lean.shader = load("res://shaders/world2d/lean.gdshader")
	material_lean.set_shader_parameter("cam_height", CAM_HEIGHT)
	if not grid.tile_changed.is_connected(refresh_tile):
		grid.tile_changed.connect(refresh_tile)

func _process(_dt: float) -> void:
	if grid == null or camera == null:
		return
	material_lean.set_shader_parameter("cam_center", camera.get_screen_center_position())
	var need := _visible_chunks()
	for c: Vector2i in need:
		if not _chunks.has(c) and not _queue.has(c):
			_queue.append(c)
	var cc := Vector2i(camera.get_screen_center_position() / float(WorldGrid.TILE_PX * WorldGrid.CHUNK))
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - cc).length_squared() < (b - cc).length_squared())
	var built := 0
	while built < BUILD_PER_FRAME and not _queue.is_empty():
		var c: Vector2i = _queue.pop_front()
		if need.has(c) and not _chunks.has(c):
			_chunks[c] = _build_chunk(c)
			built += 1
	for c: Vector2i in _chunks.keys():
		if not _near(c, need):
			(_chunks[c] as Node).queue_free()
			_chunks.erase(c)

func build_visible_now() -> void:
	material_lean.set_shader_parameter("cam_center", camera.get_screen_center_position())
	for c: Vector2i in _visible_chunks():
		if not _chunks.has(c):
			_chunks[c] = _build_chunk(c)

func chunk_count() -> int:
	return _chunks.size()

func refresh_tile(x: int, y: int) -> void:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var c := Vector2i(floori(float(x + dx) / WorldGrid.CHUNK), floori(float(y + dy) / WorldGrid.CHUNK))
			if _chunks.has(c):
				(_chunks[c] as Node).queue_free()
				_chunks[c] = _build_chunk(c)

func _visible_chunks() -> Array[Vector2i]:
	var vp := get_viewport_rect().size / camera.zoom
	var centre := camera.get_screen_center_position()
	# tall terrain leans in from outside the view: widen by the largest lean at the screen edge
	# (pits lean inward, so only the high side matters)
	var grow := 1.0 + float(WorldGrid.MAX_LEVEL) * WorldGrid.LEVEL_HEIGHT / CAM_HEIGHT
	var half := vp * 0.5 * grow
	var cs := float(WorldGrid.TILE_PX * WorldGrid.CHUNK)
	var out: Array[Vector2i] = []
	for cy in range(maxi(floori((centre.y - half.y) / cs), 0), mini(floori((centre.y + half.y) / cs), grid.chunks_y() - 1) + 1):
		for cx in range(maxi(floori((centre.x - half.x) / cs), 0), mini(floori((centre.x + half.x) / cs), grid.chunks_x() - 1) + 1):
			out.append(Vector2i(cx, cy))
	return out

func _near(c: Vector2i, need: Array[Vector2i]) -> bool:
	for n: Vector2i in need:
		if absi(n.x - c.x) <= KEEP_MARGIN and absi(n.y - c.y) <= KEEP_MARGIN:
			return true
	return false

## One mesh per level present in the chunk. Walls first, then tops.
func _build_chunk(c: Vector2i) -> Node2D:
	var root := Node2D.new()
	root.name = "Chunk_%d_%d" % [c.x, c.y]
	add_child(root)
	var t := float(WorldGrid.TILE_PX)
	var lh := WorldGrid.LEVEL_HEIGHT
	var x0 := c.x * WorldGrid.CHUNK
	var y0 := c.y * WorldGrid.CHUNK
	var walls := {}   # level -> [verts, cols, uvs]
	var tops := {}
	for ry in WorldGrid.CHUNK:
		var y := y0 + ry
		if y >= grid.height:
			break
		for rx in WorldGrid.CHUNK:
			var x := x0 + rx
			if x >= grid.width:
				break
			var lv := grid.level_at(x, y)
			var i := grid.idx(x, y)
			var h := float(lv) * lh                 # level 0 = the plane the camera's lean is measured on
			var base: Color = GROUND_COLOURS.get(int(grid.ground[i]), Color.MAGENTA)
			var ramp := (grid.flags[i] & WorldGrid.F_RAMP) != 0
			var col := base.lightened(0.02 * lv) if lv > 0 else base.darkened(0.04 * -lv)
			# slope shading, light from the top-left: lit where the ground falls away to the top-left, shaded where
			# it rises; read over 2 tiles so a terrace edge shows as a band, not a line
			var sl := float(grid.level_at(x - 2, y - 2) - grid.level_at(x + 1, y + 1))
			if sl > 0.0:
				col = col.darkened(clampf(sl * 0.05, 0.0, 0.25))
			elif sl < 0.0:
				col = col.lightened(clampf(-sl * 0.04, 0.0, 0.18))
			if ((x * 7 + y * 13) % 5) == 0:
				col = col.darkened(0.04)          # placeholder texture: a little tile variation
			var o := int(grid.ore[i])
			var px := Vector2(rx * t, ry * t)
			if not tops.has(lv):
				tops[lv] = [PackedVector2Array(), PackedColorArray(), PackedVector2Array()]
			var tp: Array = tops[lv]
			_quad(tp, px, Vector2(t, t), col, h, h, h, h)
			if o > 0:
				# ore: clumps of the ore colour on the tile, more when the deposit is richer
				var oc: Color = ORE_COLOURS[o]
				var n := 2 + int(grid.ore_amount[i]) / 64
				for k in n:
					var hsh := (x * 92821 + y * 68917 + k * 31337) & 0xffff
					var ox := float(hsh % 24) + 2.0
					var oy := float((hsh >> 5) % 24) + 2.0
					_quad(tp, px + Vector2(ox, oy), Vector2(6, 5), oc, h, h, h, h)
					_quad(tp, px + Vector2(ox + 1, oy), Vector2(3, 1), oc.lightened(0.35), h, h, h, h)
			if ramp:
				_quad(tp, px + Vector2(6, 15), Vector2(t - 12, 2), col.lightened(0.08), h, h, h, h)
			# walls down to every lower neighbour: a quad from the top edge (h) to the neighbour's height
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var nl := grid.level_at(x + d.x, y + d.y)
				if nl >= lv:
					continue
				var hl := float(nl) * lh
				if not walls.has(lv):
					walls[lv] = [PackedVector2Array(), PackedColorArray(), PackedVector2Array()]
				var wl: Array = walls[lv]
				# light from the top-left: walls facing up/left lighter, down/right darker; ramp edges are slopes
				var shade := 0.18 if (d == Vector2i.UP or d == Vector2i.LEFT) else 0.5
				var wc := base.darkened(shade)
				if ramp or grid.is_ramp(x + d.x, y + d.y):
					wc = base.darkened(shade * 0.5)
				_wall(wl, px, d, t, h, hl, wc, lv - nl)
	var lvls := walls.keys()
	for k in tops.keys():
		if not lvls.has(k):
			lvls.append(k)
	for lv: int in lvls:
		var verts := PackedVector2Array()
		var cols := PackedColorArray()
		var uvs := PackedVector2Array()
		for part: Dictionary in [walls, tops]:
			if part.has(lv):
				verts.append_array(part[lv][0])
				cols.append_array(part[lv][1])
				uvs.append_array(part[lv][2])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance2D.new()
		mi.mesh = mesh
		mi.material = material_lean
		mi.position = Vector2(x0 * t, y0 * t)
		mi.z_index = (lv - WorldGrid.MIN_LEVEL) * 2
		root.add_child(mi)
	return root

## Quad with per-corner heights (tl, tr, br, bl).
static func _quad(a: Array, p: Vector2, s: Vector2, c: Color, htl: float, htr: float, hbr: float, hbl: float) -> void:
	var v: PackedVector2Array = a[0]
	var cc: PackedColorArray = a[1]
	var uv: PackedVector2Array = a[2]
	var tl := p
	var tr := p + Vector2(s.x, 0)
	var br := p + s
	var bl := p + Vector2(0, s.y)
	v.append_array([tl, tr, br, tl, br, bl])
	uv.append_array([Vector2(htl, 0), Vector2(htr, 0), Vector2(hbr, 0), Vector2(htl, 0), Vector2(hbr, 0), Vector2(hbl, 0)])
	for k in 6:
		cc.append(c)

## A cliff wall along one tile edge, from height h_top down to h_low, split into level bands (strata).
static func _wall(a: Array, p: Vector2, d: Vector2i, t: float, h_top: float, h_low: float, c: Color, levels: int) -> void:
	var e0: Vector2
	var e1: Vector2
	match d:
		Vector2i.UP:
			e0 = p
			e1 = p + Vector2(t, 0)
		Vector2i.DOWN:
			e0 = p + Vector2(t, t)
			e1 = p + Vector2(0, t)
		Vector2i.LEFT:
			e0 = p + Vector2(0, t)
			e1 = p
		_:
			e0 = p + Vector2(t, 0)
			e1 = p + Vector2(t, t)
	var v: PackedVector2Array = a[0]
	var cc: PackedColorArray = a[1]
	var uv: PackedVector2Array = a[2]
	for k in levels:
		var ha := h_top - (h_top - h_low) * float(k) / levels
		var hb := h_top - (h_top - h_low) * float(k + 1) / levels
		var col := c.darkened(0.12) if k % 2 == 1 else c
		if k == 0:
			col = c.lightened(0.1)              # lit lip under the edge
		v.append_array([e0, e1, e1, e0, e1, e0])
		uv.append_array([Vector2(ha, 0), Vector2(ha, 0), Vector2(hb, 0), Vector2(ha, 0), Vector2(hb, 0), Vector2(hb, 0)])
		for i in 6:
			cc.append(col)

class_name BeltSystem2D
extends Node2D

## Conveyor belts on the tile grid (pivot-2d.md C3, Mindustry rules). Each belt tile has a direction and up to
## 1 / SPACING items on it, positions 0..1 along the tile (front item first). On every FactoryClock tick items move
## SPEED tiles/s, keep SPACING apart, and the front item is handed to whatever the belt points at: another belt
## (not one pointing straight back) or a building that accepts it (`add_input`). Buildings push their output onto
## belts pointing away from them (BuildGrid2D does that).
##
## P1 scale is hundreds of belts, so this is per-tile data. The P0 spike's gap-line model (scripts/world2d/
## belt_system.gd) is the plan for Mindustry-scale bases (20 000 belts) once this needs it.

const SPEED := 4.0
const SPACING := 0.25

class Belt:
	var dir := Vector2i.RIGHT
	var level := 0
	var pos := PackedFloat32Array()     ## front item first (highest pos)
	var ids := PackedStringArray()

var grid: WorldGrid
var view: WorldView
var build: BuildGrid2D
var belts := {}                         ## Vector2i -> Belt
var _layers := {}                       ## level -> Node2D drawing that level's belts
var _scroll := 0.0

func _ready() -> void:
	FactoryClock.tick.connect(step)

func has_belt(t: Vector2i) -> bool:
	return belts.has(t)

func add_belt(t: Vector2i, dir: Vector2i) -> void:
	var b := Belt.new()
	b.dir = dir
	b.level = grid.level_at(t.x, t.y)
	belts[t] = b
	_layer(b.level)

## Removes a belt; returns the items it carried ({id: count}) so a dismantle can refund them.
func remove_belt(t: Vector2i) -> Dictionary:
	var out := {}
	if belts.has(t):
		var b: Belt = belts[t]
		for id in b.ids:
			out[id] = int(out.get(id, 0)) + 1
		belts.erase(t)
	return out

func item_count() -> int:
	var n := 0
	for b: Belt in belts.values():
		n += b.ids.size()
	return n

## Room for one more item at the start of belt t?
func has_room(t: Vector2i) -> bool:
	if not belts.has(t):
		return false
	var b: Belt = belts[t]
	return b.ids.is_empty() or b.pos[b.pos.size() - 1] >= SPACING

## Put an item at the start of belt t (a building dumping onto it). False if there is no room.
func insert(t: Vector2i, id: String) -> bool:
	if not has_room(t):
		return false
	var b: Belt = belts[t]
	b.pos.append(0.0)
	b.ids.append(id)
	return true

func step(dt: float) -> void:
	var move := SPEED * dt
	for t: Vector2i in belts.keys():
		var b: Belt = belts[t]
		if b.ids.is_empty():
			continue
		# front item: to the end of the tile, then over to whatever the belt points at
		var front := b.pos[0] + move
		if front >= 1.0:
			if _hand_off(t, b, b.ids[0]):
				b.pos.remove_at(0)
				b.ids.remove_at(0)
			else:
				b.pos[0] = 1.0
		else:
			b.pos[0] = front
		for i in range(1, b.pos.size()):
			b.pos[i] = minf(b.pos[i] + move, b.pos[i - 1] - SPACING)
			b.pos[i] = maxf(b.pos[i], 0.0)

func _hand_off(t: Vector2i, b: Belt, id: String) -> bool:
	var n := t + b.dir
	if belts.has(n):
		var nb: Belt = belts[n]
		if nb.dir == -b.dir or nb.level != b.level:
			return false
		return insert(n, id)
	if build != null:
		var bld := build.building_at(n)
		if bld != null and bld.level == b.level:
			return bld.add_input(id, 1) == 1
	return false

## --- drawing: one node per level so belts sort with the terrain (z by level) ------------------------------------

func _layer(lv: int) -> Node2D:
	if not _layers.has(lv):
		var n := Node2D.new()
		n.z_index = WorldView.z_for_level(lv)
		n.draw.connect(_draw_level.bind(n, lv))
		add_child(n)
		_layers[lv] = n
	return _layers[lv]

func _process(dt: float) -> void:
	_scroll = fmod(_scroll + dt * SPEED, 1.0)
	for n: Node2D in _layers.values():
		n.queue_redraw()

func _draw_level(n: Node2D, lv: int) -> void:
	if view == null or view.camera == null:
		return
	var cam := view.camera.get_screen_center_position()
	var k := float(lv) * WorldGrid.LEVEL_HEIGHT / WorldView.CAM_HEIGHT
	var ts := float(WorldGrid.TILE_PX)
	var vp := n.get_viewport_rect().size / view.camera.zoom
	var vis := Rect2(cam - vp * 0.6, vp * 1.2)
	for t: Vector2i in belts:
		var b: Belt = belts[t]
		if b.level != lv:
			continue
		var p := Vector2(t) * ts
		if not vis.has_point(p):
			continue
		var a := p + (p - cam) * k
		var s := ts * (1.0 + k)
		var fwd := Vector2(b.dir)
		var side := Vector2(-fwd.y, fwd.x)
		var c := a + Vector2(s, s) * 0.5
		n.draw_rect(Rect2(a + Vector2(2, 2), Vector2(s - 4, s - 4)), Color("#23242e"))
		n.draw_rect(Rect2(a + Vector2(3, 3), Vector2(s - 6, s - 6)), Color("#3b3d4b"))
		# moving chevrons show the direction
		for kk in 2:
			var u := fmod(_scroll + kk * 0.5, 1.0) - 0.5
			var tip := c + fwd * u * s * 0.9
			n.draw_line(tip - fwd * 4 + side * 5, tip, Color("#5c5f70"), 2.0)
			n.draw_line(tip - fwd * 4 - side * 5, tip, Color("#5c5f70"), 2.0)
		for i in b.ids.size():
			var ip := c + fwd * (b.pos[i] - 0.5) * s
			n.draw_rect(Rect2(ip - Vector2(4, 4), Vector2(8, 8)), Color("#16161f"))
			n.draw_rect(Rect2(ip - Vector2(3, 3), Vector2(6, 6)), _item_colour(b.ids[i]))

static func _item_colour(id: String) -> Color:
	var it := Inventory.get_item_def(id)
	return it.debug_color if it != null else Color.MAGENTA

func save_state() -> Array:
	var out := []
	for t: Vector2i in belts:
		var b: Belt = belts[t]
		out.append({"t": [t.x, t.y], "d": [b.dir.x, b.dir.y], "pos": Array(b.pos), "ids": Array(b.ids)})
	return out

func load_state(data: Array) -> void:
	belts.clear()
	for e: Dictionary in data:
		var t := Vector2i(int(e["t"][0]), int(e["t"][1]))
		add_belt(t, Vector2i(int(e["d"][0]), int(e["d"][1])))
		var b: Belt = belts[t]
		b.pos = PackedFloat32Array(e.get("pos", []))
		b.ids = PackedStringArray(e.get("ids", []))

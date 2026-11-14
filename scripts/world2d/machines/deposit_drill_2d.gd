extends Building2D
## Deposit drill, 2x2 (pivot-2d.md C2): mines the ore under its footprint. Rate grows with the number of ore tiles
## it covers; every item comes out of a tile's ore_amount, so a deposit runs dry and the drill must move.
## Output goes onto belts like any machine (dump to belts pointing away).

const SECONDS_PER_ITEM := 2.0      ## with one ore tile under it; 4 tiles = 4x faster
var grid: WorldGrid
var _acc := 0.0

func _init() -> void:
	item_id = "deposit_drill"
	display_name = "Deposit Drill"
	size = Vector2i(2, 2)
	height_px = 12.0
	colour = Color("#ffa65c")
	recipes = []
	inventory_capacity = 20
	inventory_slots = 4

func _ready() -> void:
	super._ready()
	FactoryClock.tick.connect(_on_drill_tick)

## The ore it drills: the one under most of its footprint.
func ore_under() -> int:
	var count := {}
	for t in tiles():
		var o := grid.ore_at(t.x, t.y) if grid != null else 0
		if o > 0:
			count[o] = int(count.get(o, 0)) + 1
	var best := 0
	var bn := 0
	for o: int in count:
		if count[o] > bn:
			bn = count[o]
			best = o
	return best

func ore_tiles(o: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t in tiles():
		if grid.ore_at(t.x, t.y) == o and int(grid.ore_amount[grid.idx(t.x, t.y)]) > 0:
			out.append(t)
	return out

func _on_drill_tick(dt: float) -> void:
	if grid == null:
		return
	var o := ore_under()
	if o == 0:
		return
	var src := ore_tiles(o)
	if src.is_empty() or get_total_count() >= inventory_capacity:
		return
	_acc += dt * work_speed * modifier_speed() * float(src.size()) / SECONDS_PER_ITEM
	while _acc >= 1.0 and not src.is_empty():
		_acc -= 1.0
		var t: Vector2i = src[0]
		var i := grid.idx(t.x, t.y)
		grid.ore_amount[i] = int(grid.ore_amount[i]) - 1
		if int(grid.ore_amount[i]) <= 0:
			grid.ore[i] = 0
			grid.tile_changed.emit(t.x, t.y)
			src.remove_at(0)
		_add_item(WorldGrid.ORE_ITEMS[o], int(roundf(modifier_yield())))

func output_ids() -> Array:
	var out := []
	for slot in _inventory:
		if slot.item_id != "" and not out.has(slot.item_id):
			out.append(slot.item_id)
	return out

func can_accept_input(_id: String, _n: int) -> bool:
	return false

func idle_reason() -> String:
	if grid == null or ore_under() == 0:
		return "No ore"
	if get_total_count() >= inventory_capacity:
		return "Output full"
	return ""

func status_text() -> String:
	var r := idle_reason()
	return "DRILLING %s" % WorldGrid.ORE_IDS[ore_under()].to_upper() if r == "" else r.to_upper()

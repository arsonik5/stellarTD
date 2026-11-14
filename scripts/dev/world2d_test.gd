extends Node

## 2D world tests (pivot-2d.md 4.3): determinism, generation budget, variety census, save round trip.
##   godot --headless --path . res://scenes/dev/world2d_test.tscn

const SIZE := 1024
const BUDGET_MS := 5000.0

var _fails := 0

func _ready() -> void:
	var a := WorldGrid.new(SIZE, SIZE)
	WorldGen.generate(a, 1)
	var t := WorldGen.last_timing
	print("GEN timing ms: ", t)
	_check(float(t["total"]) < BUDGET_MS, "1024^2 world generates under %.0f ms (%.0f ms)" % [BUDGET_MS, t["total"]])

	var b := WorldGrid.new(SIZE, SIZE)
	WorldGen.generate(b, 1)
	_check(a.data_hash() == b.data_hash(), "same seed -> same map")
	var c := WorldGrid.new(SIZE, SIZE)
	WorldGen.generate(c, 2)
	_check(a.data_hash() != c.data_hash(), "different seed -> different map")

	# --- census
	var n := SIZE * SIZE
	var hist := {}
	var ramps := 0
	var cliffs := 0
	var ore_count := {}
	for y in SIZE:
		for x in SIZE:
			var i := y * SIZE + x
			var lv := a.level_at(x, y)
			hist[lv] = int(hist.get(lv, 0)) + 1
			if a.is_ramp(x, y):
				ramps += 1
			if x + 1 < SIZE and a.level_at(x + 1, y) != lv and not a.can_step(x, y, x + 1, y):
				cliffs += 1
			var o := int(a.ore[i])
			if o > 0:
				ore_count[o] = int(ore_count.get(o, 0)) + 1
	var levels := hist.keys()
	levels.sort()
	var line := ""
	for lv: int in levels:
		line += "%d:%.1f%% " % [lv, 100.0 * hist[lv] / n]
	print("CENSUS levels ", line)
	print("CENSUS ramps %.1f%%  cliff edges %.1f%%" % [100.0 * ramps / n, 100.0 * cliffs / n])
	_check(levels.size() >= 12, "at least 12 distinct levels (%d): mountains and basins exist" % levels.size())
	_check(int(levels[-1]) >= 10, "mountains reach level 10+ (max %d)" % levels[-1])
	_check(ramps > n / 500, "ramps exist (%d)" % ramps)
	_check(cliffs > n / 500, "cliffs exist (%d edges)" % cliffs)
	for oi in range(1, WorldGrid.ORE_IDS.size()):
		var share := 100.0 * float(ore_count.get(oi, 0)) / n
		print("CENSUS ore %-8s %.2f%%" % [WorldGrid.ORE_IDS[oi], share])
		var floor_pct := 0.01 if WorldGrid.ORE_IDS[oi] == "crystal" else 0.05   # crystal is rare on purpose (signature)
		_check(share > floor_pct and share < 10.0, "%s covers %.2f-10%% of the map (%.2f%%)" % [WorldGrid.ORE_IDS[oi], floor_pct, share])

	# walkable region from the map centre must be large (a start that is boxed in by cliffs is a broken map)
	var reach := _flood(a, Vector2i(SIZE / 2, SIZE / 2), 200000)
	print("CENSUS walkable from centre: %d tiles" % reach)
	_check(reach > n / 20, "the centre connects to >5%% of the map on foot (%d tiles)" % reach)

	# save round trip
	var bytes := a.to_bytes()
	var d := WorldGrid.new(SIZE, SIZE)
	d.from_bytes(bytes)
	_check(d.data_hash() == a.data_hash(), "save/load round trip is exact (%d KB compressed)" % (bytes.size() / 1024))

	print("WORLD2D DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _flood(g: WorldGrid, start: Vector2i, cap: int) -> int:
	var seen := {}
	var q: Array[Vector2i] = [start]
	seen[start] = true
	var head := 0
	while head < q.size() and q.size() < cap:
		var p: Vector2i = q[head]
		head += 1
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nb := p + d
			if not seen.has(nb) and g.can_step(p.x, p.y, nb.x, nb.y):
				seen[nb] = true
				q.append(nb)
	return q.size()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

extends Node2D

## P0.2 tech spike for the 2D pivot (docs/game/design/pivot-2d.md 5.2 and 7): a 1024^2 map with 9 levels and cliff
## faces, 2 000 placeholder buildings Y-sorted with the terrain, 20 000 belt tiles carrying 10 000 items, a camera
## flight at three zooms. Prints frame times, factory-tick cost, memory and draw calls, saves screenshots.
##   godot --path . res://scenes/dev/spike2d.tscn                 (automatic flight, then quits)
##   godot --path . res://scenes/dev/spike2d.tscn -- --interactive (WASD / wheel to look around yourself)

const MAP := 1024
const BUILDINGS := 2000
const BELT_LINES := 200
const BELT_LEN := 100
const ITEMS_PER_LINE := 50
const TICK := 0.1

var grid: WorldGrid
var view: WorldMapView
var belts: BeltSystem
var cam: Camera2D
var interactive := false

var _phase := -1
var _phase_t := 0.0
var _frames: Array[float] = []
var _tick_us: Array[int] = []
var _tick_acc := 0.0
var _results: Array[String] = []
var PHASES := [
	{"name": "zoom1_mesa", "zoom": 1.0, "secs": 2.0, "from": Vector2(28, 25), "to": Vector2(28, 25)},
	{"name": "zoom1_cliffs", "zoom": 1.0, "secs": 4.0, "from": Vector2.ZERO, "to": Vector2.ZERO},
	{"name": "zoom1_pan", "zoom": 1.0, "secs": 8.0, "from": Vector2(300, 300), "to": Vector2(700, 520)},
	{"name": "zoom0.5_pan", "zoom": 0.5, "secs": 8.0, "from": Vector2(150, 150), "to": Vector2(850, 650)},
	{"name": "zoom2_base", "zoom": 2.0, "secs": 5.0, "from": Vector2(140, 140), "to": Vector2(190, 200)},
]

func _ready() -> void:
	interactive = OS.get_cmdline_user_args().has("--interactive")
	RenderingServer.set_default_clear_color(Color(0.08, 0.08, 0.1))
	var t0 := Time.get_ticks_usec()
	grid = WorldGrid.new(MAP, MAP)
	grid.generate(1)
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0

	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()

	view = WorldMapView.new()
	add_child(view)
	view.setup(grid, cam)

	t0 = Time.get_ticks_usec()
	_place_buildings()
	var bld_ms := (Time.get_ticks_usec() - t0) / 1000.0

	belts = BeltSystem.new()
	belts.z_index = 1           # spike: belts over terrain (P1 sorts them per row like everything else)
	add_child(belts)
	belts.camera = cam
	for i in BELT_LINES:
		var row := 100 + i * 4
		var li := belts.add_line(Vector2i(100, row), Vector2i.RIGHT, BELT_LEN, grid.level_at(100, row))
		belts.lines[li].next = li    # loop: the end feeds its own start
		belts.fill(li, ITEMS_PER_LINE, 1.6)

	_results.append("map %dx%d generated in %.0f ms, hash %d" % [MAP, MAP, gen_ms, grid.data_hash()])
	_results.append("%d buildings placed in %.0f ms" % [BUILDINGS, bld_ms])
	_results.append("belts: %d lines, %d tiles, %d items" % [belts.lines.size(), BELT_LINES * BELT_LEN, belts.item_count()])
	# a known shape at the start corner: a 3-level mesa with a 1-level terrace in front and a pit, so every case
	# (face, multi-level face, side edges, contact shadow, a unit behind the mesa) is on one screenshot
	for y in range(10, 40):
		for x in range(10, 50):
			grid.set_level(x, y, 0)
	for y in range(16, 26):
		for x in range(16, 34):
			grid.set_level(x, y, 3)
	for y in range(26, 30):
		for x in range(20, 30):
			grid.set_level(x, y, 1)
	for y in range(30, 34):
		for x in range(38, 44):
			grid.set_level(x, y, -2)
	# test units: behind the mesa (should be partly hidden by it), on top, in front
	for p: Vector2i in [Vector2i(24, 15), Vector2i(26, 19), Vector2i(25, 31)]:
		_add_unit(p.x, p.y)
	var rough := _roughest_spot()
	PHASES[1]["from"] = rough
	PHASES[1]["to"] = rough + Vector2(12, 6)
	_results.append("roughest spot at tile %s" % rough)
	if interactive:
		cam.position = Vector2(150, 150) * WorldGrid.TILE_PX
	else:
		_next_phase()

## Tile with the most level changes around it (sampled), so a screenshot shows cliffs.
func _roughest_spot() -> Vector2:
	var best := Vector2(300, 300)
	var best_n := -1
	for sy in range(40, MAP - 40, 24):
		for sx in range(40, MAP - 40, 24):
			var n := 0
			for k in range(-16, 16, 2):
				n += absi(grid.level_at(sx + k, sy) - grid.level_at(sx + k + 2, sy))
				n += absi(grid.level_at(sx, sy + k) - grid.level_at(sx, sy + k + 2))
			if n > best_n:
				best_n = n
				best = Vector2(sx, sy)
	return best

func _add_unit(x: int, y: int) -> void:
	var s := Sprite2D.new()
	var tex := GradientTexture2D.new()
	tex.width = 16
	tex.height = 28
	s.texture = tex
	s.modulate = Color(0.3, 0.8, 1.0)
	s.centered = false
	s.position = (Vector2(x, y) + Vector2(0.5, 0.5)) * WorldGrid.TILE_PX
	s.offset = Vector2(-8, -26 - grid.level_at(x, y) * WorldGrid.LEVEL_PX)
	view.add_child(s)

func _place_buildings() -> void:
	var tex := GradientTexture2D.new()
	tex.width = 56
	tex.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(0.75, 0.62, 0.35))
	g.set_color(1, Color(0.35, 0.28, 0.2))
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in BUILDINGS:
		# half of them packed near the start corner (a "base"), the rest spread out
		var x := rng.randi_range(110, 220) if i < BUILDINGS / 2 else rng.randi_range(0, MAP - 1)
		var y := rng.randi_range(110, 220) if i < BUILDINGS / 2 else rng.randi_range(0, MAP - 1)
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		# node position = where it stands (tile centre on the level-0 plane) -> Y-sort; the picture is lifted by
		# its level and drawn upward from its feet
		s.position = (Vector2(x, y) + Vector2(0.5, 0.5)) * WorldGrid.TILE_PX
		s.offset = Vector2(-28, -60 - grid.level_at(x, y) * WorldGrid.LEVEL_PX)
		view.add_child(s)

func _next_phase() -> void:
	if _phase >= 0:
		_report_phase()
		_shot(PHASES[_phase]["name"])
	_phase += 1
	_phase_t = 0.0
	_frames.clear()
	_tick_us.clear()
	if _phase >= PHASES.size():
		_finish()
		return
	cam.zoom = Vector2.ONE * float(PHASES[_phase]["zoom"])
	cam.position = Vector2(PHASES[_phase]["from"]) * WorldGrid.TILE_PX
	view.build_visible_now()

func _process(dt: float) -> void:
	_tick_acc += dt
	while _tick_acc >= TICK:
		_tick_acc -= TICK
		var t0 := Time.get_ticks_usec()
		belts.step(TICK)
		_tick_us.append(Time.get_ticks_usec() - t0)
	if interactive:
		var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		cam.position += v * 900.0 * dt / cam.zoom.x
		return
	if _phase < 0 or _phase >= PHASES.size():
		return
	var p: Dictionary = PHASES[_phase]
	_phase_t += dt
	_frames.append(dt)
	var k := clampf(_phase_t / float(p["secs"]), 0.0, 1.0)
	cam.position = (Vector2(p["from"]).lerp(Vector2(p["to"]), k)) * WorldGrid.TILE_PX
	if _phase_t >= float(p["secs"]):
		_next_phase()

func _unhandled_input(e: InputEvent) -> void:
	if interactive and e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = (cam.zoom * 1.25).clamp(Vector2.ONE * 0.25, Vector2.ONE * 4.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = (cam.zoom / 1.25).clamp(Vector2.ONE * 0.25, Vector2.ONE * 4.0)

func _report_phase() -> void:
	var p: Dictionary = PHASES[_phase]
	var fr := _frames.duplicate()
	if fr.size() > 10:
		fr = fr.slice(5)          # the first frames include chunk builds after the jump
	fr.sort()
	var avg := 0.0
	for f in fr:
		avg += f
	avg /= maxf(fr.size(), 1)
	var p99: float = fr[int(fr.size() * 0.99) - 1] if fr.size() > 1 else 0.0
	var tick_avg := 0.0
	var tick_max := 0
	for t in _tick_us:
		tick_avg += t
		tick_max = maxi(tick_max, t)
	tick_avg /= maxf(_tick_us.size(), 1)
	_results.append("%-12s avg %5.1f fps  p99 frame %5.1f ms  | factory tick avg %.2f ms max %.2f ms | chunks %d draw calls %d" % [
		p["name"], 1.0 / maxf(avg, 1e-6), p99 * 1000.0, tick_avg / 1000.0, tick_max / 1000.0,
		view.chunk_count(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://spike2d_%s.png" % name)

func _finish() -> void:
	_results.append("static memory %.0f MB, nodes %d, video memory %.0f MB" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	for r in _results:
		print("SPIKE ", r)
	print("SPIKE screenshots in ", ProjectSettings.globalize_path("user://"))
	print("SPIKE DONE")
	get_tree().quit()

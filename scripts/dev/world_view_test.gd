extends Node2D

## Renderer v2 look + speed check: generated world, straight-down camera, perspective lean. Screenshots at a
## mountain range (three camera positions, to see walls swap sides), a plain with ore, and zoomed out.
##   godot --path . res://scenes/dev/world_view_test.tscn

var grid: WorldGrid
var view: WorldView
var cam: Camera2D
var _fails := 0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.05, 0.07))
	grid = WorldGrid.new(1024, 1024)
	WorldGen.generate(grid, 1)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	view = WorldView.new()
	add_child(view)
	view.setup(grid, cam)
	_run.call_deferred()

func _run() -> void:
	var peak := _find(func(x: int, y: int) -> int: return grid.level_at(x, y))
	var ore := _find(func(x: int, y: int) -> int: return 1 if grid.ore_at(x, y) > 0 else 0)
	var shots := [
		["peak_centre", peak, 1.0], ["peak_left", peak + Vector2i(14, 0), 1.0], ["peak_below", peak + Vector2i(0, -10), 1.0],
		["ore_plain", ore, 2.0], ["zoomed_out", peak, 0.35],
	]
	for s: Array in shots:
		cam.zoom = Vector2.ONE * float(s[2])
		cam.position = (Vector2(s[1]) + Vector2(0.5, 0.5)) * WorldGrid.TILE_PX
		await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		view.build_visible_now()
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		for i in 3:
			await get_tree().process_frame
		var t1 := Time.get_ticks_usec()
		for i in 30:
			await get_tree().process_frame
		var fps := 30.0 / ((Time.get_ticks_usec() - t1) / 1e6)
		print("VIEW %-12s chunks %3d  build %6.1f ms  ~%5.0f fps" % [s[0], view.chunk_count(), build_ms, fps])
		get_viewport().get_texture().get_image().save_png("user://view_%s.png" % s[0])
	print("VIEW DONE ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()

## Tile maximising f inside the middle of the map (coarse search).
func _find(f: Callable) -> Vector2i:
	var best := Vector2i(512, 512)
	var bv := -9999
	for y in range(100, 924, 8):
		for x in range(100, 924, 8):
			var v: int = f.call(x, y)
			if v > bv:
				bv = v
				best = Vector2i(x, y)
	return best

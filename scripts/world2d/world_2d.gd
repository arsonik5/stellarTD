class_name GameWorld2D
extends Node2D

## The 2D game world scene (pivot-2d.md P1): generates (or later loads) a WorldGrid, draws it with WorldView,
## spawns the player on open flat ground and follows them with the camera. Mouse wheel zooms in whole steps.
##   godot --path . res://scenes/world2d.tscn [-- --seed=N]

const ZOOMS := [1.0, 2.0, 3.0, 4.0]

var grid: WorldGrid
var view: WorldView
var player: Player2D
var cam: Camera2D
var hud: Label
var build: BuildGrid2D
var build_mode: BuildMode2D
var _zoom_i := 1

## What a Voyager lands with (P1 placeholder for the landing pod's kit).
const LANDING_KIT := {"deposit_drill": 2, "smelter": 1, "chest": 2, "conveyor_belt": 24, "refined_material": 10}
var gen_ms := 0.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.05, 0.07))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var seed_v := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
	var t0 := Time.get_ticks_usec()
	grid = WorldGrid.new(1024, 1024)
	WorldGen.generate(grid, seed_v)
	gen_ms = (Time.get_ticks_usec() - t0) / 1000.0

	cam = Camera2D.new()
	cam.zoom = Vector2.ONE * ZOOMS[_zoom_i]
	add_child(cam)
	cam.make_current()
	view = WorldView.new()
	add_child(view)
	view.setup(grid, cam)
	build = BuildGrid2D.new()
	add_child(build)
	build.setup(grid, view)
	player = Player2D.new()
	add_child(player)
	player.setup(grid, view, find_spawn(grid))
	cam.position = player.position
	view.build_visible_now()
	var cursor := Node2D.new()
	cursor.set_script(preload("res://scripts/world2d/cursor_overlay_2d.gd"))
	cursor.set("player", player)
	cursor.set("view", view)
	add_child(cursor)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(8, 6)
	hud.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud)
	build_mode = BuildMode2D.new()
	add_child(build_mode)
	build_mode.setup(build, view, player, layer)
	if Inventory.get_count("deposit_drill") == 0 and Inventory.get_count("smelter") == 0:
		for id: String in LANDING_KIT:
			Inventory.add(id, LANDING_KIT[id])
	if OS.get_cmdline_user_args().has("--shot"):
		_shot.call_deferred()

## Dev: walk a little, save a screenshot, quit (for checks without a person at the keyboard).
func _shot() -> void:
	for i in 30:
		await get_tree().process_frame
	player.input_override = Vector2(1, 0.4).normalized()
	for i in 60:
		await get_tree().physics_frame
	player.input_override = Vector2.ZERO
	# lay a small line through the real build code next to the player: drill on the nearest ore, belts, a chest
	var ore := _nearest_ore(player.tile(), 40)
	if ore.x >= 0:
		player.position = (Vector2(ore) + Vector2(-2.5, 0.5)) * WorldGrid.TILE_PX
		var placed: Variant = build.place("deposit_drill", ore, 0)
		var x0 := ore.x + 2
		for x in range(x0, x0 + 4):
			build.place(BuildGrid2D.BELT, Vector2i(x, ore.y), 0)
		build.place("chest", Vector2i(x0 + 4, ore.y), 0)
		print("WORLD2D_SHOT drill at %s: %s" % [ore, "placed" if placed != null else build.can_place("deposit_drill", ore, 0)])
	build_mode.selected = "smelter"
	build_mode._set_active(true)
	for i in 120:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://world2d_shot.png")
	print("WORLD2D_SHOT gen %.0f ms, player tile %s level %d" % [gen_ms, player.tile(), player.level])
	get_tree().quit()

func _nearest_ore(c: Vector2i, r: int) -> Vector2i:
	for d in r:
		for y in range(c.y - d, c.y + d + 1):
			for x in range(c.x - d, c.x + d + 1):
				if grid.ore_at(x, y) > 0 and build.can_place("deposit_drill", Vector2i(x, y), 0) == "":
					return Vector2i(x, y)
	return Vector2i(-1, -1)

## Open flat ground near the map centre: a 7x7 block on one level, no ore, no ramps, with enough walkable land
## around it. Spiral search, deterministic.
static func find_spawn(g: WorldGrid) -> Vector2i:
	var c := Vector2i(g.width / 2, g.height / 2)
	for r in range(0, 300, 3):
		for k in range(0, maxi(1, r * 8), 3):
			var a := TAU * float(k) / float(maxi(1, r * 8))
			var p := c + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			if _flat_block(g, p, 3):
				return p
	return c

static func _flat_block(g: WorldGrid, p: Vector2i, rad: int) -> bool:
	if not g.in_bounds(p.x - rad, p.y - rad) or not g.in_bounds(p.x + rad, p.y + rad):
		return false
	var lv := g.level_at(p.x, p.y)
	if lv < -1 or lv > 3:
		return false          # start on the plains, not on a mountain terrace
	for y in range(p.y - rad, p.y + rad + 1):
		for x in range(p.x - rad, p.x + rad + 1):
			if g.level_at(x, y) != lv or g.is_ramp(x, y) or g.ore_at(x, y) != 0:
				return false
	return true

func _process(dt: float) -> void:
	if player == null:
		return
	cam.position = cam.position.lerp(player.position, clampf(10.0 * dt, 0.0, 1.0))
	var mt := grid.tile_of(get_global_mouse_position())
	var ore_name: String = WorldGrid.ORE_IDS[grid.ore_at(mt.x, mt.y)] if grid.in_bounds(mt.x, mt.y) else ""
	var bag := ""
	for id: String in ["stone", "ore_a", "ore_b", "ore_coal", "ore_silica", "sulfur", "ore_crystal"]:
		var c := Inventory.get_count(id)
		if c > 0:
			bag += "%s %d  " % [id, c]
	hud.text = "%d fps   tile %s  level %d   cursor %s lv %d %s%s %s   gen %.0f ms   zoom %dx
%s" % [
		Engine.get_frames_per_second(), player.tile(), player.level, mt, grid.level_at(mt.x, mt.y),
		ore_name, " ramp" if grid.is_ramp(mt.x, mt.y) else "", player.dig_refused, gen_ms, int(ZOOMS[_zoom_i]), bag]

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_i = mini(_zoom_i + 1, ZOOMS.size() - 1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_i = maxi(_zoom_i - 1, 0)
		cam.zoom = Vector2.ONE * ZOOMS[_zoom_i]

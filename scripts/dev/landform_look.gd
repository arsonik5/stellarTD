extends Node
## Landform look: photographs the W3 layers and W5 POIs where they actually are.
##
## The fixed terrain_look framings sit at the spawn, and landform layers are patchy by design - a mesa field may be
## kilometres away. This finds, for each layer, the direction where it changes the ground the most (the generator
## with only that layer on, minus the legacy recipe), moves the viewer there, waits for streaming, and shoots a
## raking ground view and an aerial view. Then it does the same at the nearest POI site.
##   godot --path . res://scenes/dev/landform_look.tscn -- --tag=w3 [--erosion-width=2048] [--moon]
## Writes user://landform_<tag>_<layer>_<view>.png and prints the site it chose.

const SCOUT_DIRS := 1500
const SETTLE_S := 14.0

var _tag := "x"
var _world: Node
var _planet: Planet
var _player: Node3D
var _cam: Camera3D

func _ready() -> void:
	var moon := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		if a == "--moon":
			moon = true
	_world = preload("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await get_tree().process_frame
	_world.get_node("LoadingScreen").queue_free()
	_planet = _world.get_node("TestMoon" if moon else "HomePlanet")
	_player = _world.get_node("Player")
	while not _planet.is_terrain_ready:
		await get_tree().process_frame
	_player.set_physics_process(false)
	_player.set_process(false)
	_cam = Camera3D.new()
	_cam.far = 200000.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.make_current()
	# Judge the ground, not the HUD.
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var legacy := _planet.build_generator_with_recipe(TerrainRecipe.legacy())
	var full := TerrainRecipe.of(_planet.body)
	for layer in ["terrace", "canyon", "spire"]:
		var only := TerrainRecipe.legacy()
		only.mask_on_shell = full.mask_on_shell
		only.set(layer + "_enabled", true)
		for prop in full.get_property_list():
			var n: String = prop.name
			if n.begins_with(layer + "_") and n != layer + "_enabled":
				only.set(n, full.get(n))
		if layer == "terrace":
			only.terrace_coverage = full.terrace_coverage
		if not bool(full.get(layer + "_enabled")):
			print("LOOK %s: off in this body's recipe, skipped" % layer)
			continue
		var g := _planet.build_generator_with_recipe(only)
		var site := _scout(legacy, g, layer)
		print("LOOK %s: strongest at %s (delta %.1f m)" % [layer, site.dir, site.delta])
		await _shoot(site.dir, layer)
	if _planet.poi_field != null:
		var sites := _planet.poi_sites()
		if not sites.is_empty():
			var vdir := (_player.global_position - _planet.global_position).normalized()
			var best: Dictionary = sites[0]
			for s: Dictionary in sites:
				if (s.dir as Vector3).angle_to(vdir) < (best.dir as Vector3).angle_to(vdir):
					best = s
			print("LOOK poi: %s at %s" % [(best.spec as PoiSpec).poi_type, best.dir])
			await _shoot(best.dir, "poi_" + (best.spec as PoiSpec).poi_type, 18.0)
	print("LANDFORM_LOOK_DONE")
	get_tree().quit()

func _scout(legacy: VoxelGeneratorGraph, g: VoxelGeneratorGraph, layer: String) -> Dictionary:
	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	var best := {"dir": Vector3.UP, "delta": 0.0}
	for i in SCOUT_DIRS:
		var dir := _fib(i, SCOUT_DIRS)
		var d := _h(g, buf, dir) - _h(legacy, buf, dir)
		var score := absf(d)
		if layer == "spire":
			score = d
		elif layer == "canyon":
			score = -d
		if score > absf(best.delta) or (best.delta == 0.0 and score > 0.0):
			best = {"dir": dir, "delta": d}
	return best

func _shoot(dir: Vector3, label: String, ground_dist := 60.0) -> void:
	var up := dir
	var ground_r := _planet.surface_radius_along(dir) * Planet.VOXEL_SCALE
	var centre := _planet.global_position
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	# Viewer goes to the site so terrain there streams in; the camera stands back from it.
	_player.global_position = centre + up * (ground_r + 3.0)
	var stand := (dir - east * (ground_dist / _planet.radius_world())).normalized()
	var stand_r := _planet.surface_radius_along(stand) * Planet.VOXEL_SCALE
	var views := [
		["ground", centre + stand * (stand_r + 6.0), -0.08],
		["aerial", centre + stand * (stand_r + 160.0) - east * 80.0, -0.55],
	]
	_park_sun(dir)
	await get_tree().create_timer(SETTLE_S).timeout
	for v in views:
		var pos: Vector3 = v[1]
		_cam.global_position = pos
		var target := centre + up * (ground_r + 8.0)
		var vup := (pos - centre).normalized()
		_cam.look_at(target, vup)
		if v[0] == "aerial":
			_cam.look_at(centre + up * ground_r, vup)
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		var path := "user://landform_%s_%s_%s.png" % [_tag, label, v[0]]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)

## Moves the star so the sun stands 25 degrees above this site's horizon, off to the side of the view - every shot
## lit the same raking way (terrain_look.gd's rule: compare like with like, and relief only reads in raking light).
func _park_sun(dir: Vector3) -> void:
	var star := _world.get_node_or_null("Star") as Node3D
	if star == null:
		return
	var up := dir
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var el := deg_to_rad(25.0)
	var sun_dir := (up * sin(el) + east.rotated(up, 1.1) * cos(el)).normalized()
	var dist: float = star.global_position.distance_to(_planet.global_position)
	star.global_position = _planet.global_position + up * _planet.radius_world() + sun_dir * dist

func _fib(i: int, n: int) -> Vector3:
	var y := 1.0 - (float(i) + 0.5) / float(n) * 2.0
	var rr := sqrt(maxf(1.0 - y * y, 0.0))
	var th := float(i) * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(th) * rr, y, sin(th) * rr).normalized()

func _h(g: VoxelGeneratorGraph, buf: VoxelBuffer, dir: Vector3) -> float:
	var band := _planet.profile.max_deviation_voxels() + 80.0
	var lo := _planet.body.radius - band
	var hi := _planet.body.radius + band
	for _i in 20:
		var mid := (lo + hi) * 0.5
		var q := dir * mid
		g.generate_block(buf, Vector3i(roundi(q.x), roundi(q.y), roundi(q.z)), 0)
		if buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) < 0.0:
			lo = mid
		else:
			hi = mid
	return ((lo + hi) * 0.5 - _planet.body.radius) * Planet.VOXEL_SCALE

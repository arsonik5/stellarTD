extends Node
## Planet look rig - the fixed capture set every look round is judged on (design/05-planets.md, SE2 target).
##   godot --rendering-driver vulkan --path . res://scenes/dev/planet_look.tscn -- --body=home|moon --tag=rN
##         [--erosion-width=2048] [--only=eye_noon,cliff,...]
##
## Same framings, same sun, every round, on each body:
##   base site:  eye_noon, eye_low (sun 8 deg), eye_night, alt_50m, alt_500m, alt_5km, orbit, dug_hole
##   features:   cliff (close-up of the steepest face), plain (flattest ground), canyon, mesa (terrace riser),
##               crater
## Feature sites are found from the generator itself (steepest / flattest of 600 directions; canyon, mesa and
## crater = where turning that one layer off changes the ground most), so they follow the terrain as it changes.
##
## Measures, printed as METRIC lines:
##   walkable_s   time from world load to the player standing on ground (home only - that is the spawn body)
##   frame_ms     mean frame time over 1.5 s per framing (CPU lavapipe or whatever GPU ran it - see the
##                "Using Device" line; numbers on a CPU renderer say nothing about a GPU)
##   lod_changes  frames whose terrain mesh-block count changed while flying 5 km -> 50 m in 12 s: a proxy for
##                LOD popping (each change is a block appearing or swapping LOD)
## Writes user://look_<tag>_<body>_<framing>.png and prints "PLANET_LOOK_DONE".

const SETTLE_SITE := 9.0
const SETTLE_SHOT := 2.0
const SUN_HIGH := 55.0
const SUN_LOW := 8.0

var _tag := "r0"
var _body := "home"
var _only: Array = []
var _world: Node
var _planet: Planet
var _player: Node3D
var _cam: Camera3D
var _t0 := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--body="):
			_body = a.substr(7)
		elif a.begins_with("--only="):
			_only = Array(a.substr(7).split(","))
	_t0 = Time.get_ticks_msec()
	_world = preload("res://scenes/world.tscn").instantiate()
	add_child(_world)
	await get_tree().process_frame
	_world.get_node("LoadingScreen").queue_free()
	_planet = _world.get_node("HomePlanet" if _body == "home" else "TestMoon")
	_player = _world.get_node("Player")
	while not _planet.is_terrain_ready:
		await get_tree().process_frame
	if _body == "home":
		while not _player.is_spawn_resolved():
			await get_tree().process_frame
			if Time.get_ticks_msec() - _t0 > 300000:
				break
		print("METRIC %s walkable_s %.1f" % [_body, (Time.get_ticks_msec() - _t0) / 1000.0])
	_player.set_physics_process(false)
	_player.set_process(false)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--debug-view="):
			(_planet.terrain.material as ShaderMaterial).set_shader_parameter("debug_view", int(a.substr(13)))
	print("CAMERA_CHECK ground_r %.1f body_r %.1f" % [_ground(_base_dir()), _planet.radius_world()])
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	_cam = Camera3D.new()
	_cam.far = 300000.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.make_current()
	await _run()
	print("PLANET_LOOK_DONE")
	get_tree().quit()

func _want(n: String) -> bool:
	return _only.is_empty() or _only.has(n)

func _run() -> void:
	var base := _base_dir()
	var g := _planet.terrain.generator as VoxelGeneratorGraph
	var r := _planet.radius_world()
	var east := _east(base)
	# --- base site ---------------------------------------------------------------------------------------------
	await _goto(base, SUN_HIGH)
	var gr := _ground(base)
	var look_dir := east.rotated(base, 0.6)
	if _want("eye_noon"):
		await _shot("eye_noon", _at(base, gr + 1.7), _at((base + look_dir * (300.0 / r)).normalized(), gr - 10.0), base)
	if _want("eye_low"):
		_park_sun(base, SUN_LOW, look_dir)
		await _shot("eye_low", _at(base, gr + 1.7), _at((base + look_dir * (300.0 / r)).normalized(), gr - 10.0), base)
	if _want("eye_night"):
		_park_sun(base, -25.0, look_dir)
		await _shot("eye_night", _at(base, gr + 1.7), _at((base + look_dir * (300.0 / r)).normalized(), gr - 10.0), base)
	_park_sun(base, 25.0, look_dir)
	for pair in [["alt_50m", 50.0, 400.0], ["alt_500m", 500.0, 2500.0], ["alt_5km", 5000.0, 12000.0]]:
		if _want(pair[0]):
			var tgt := (base + look_dir * (float(pair[2]) / r)).normalized()
			await _shot(pair[0], _at(base, gr + float(pair[1])), _at(tgt, _ground_fast(tgt)), base)
	if _want("orbit"):
		var alt := r * (2.2 if _body == "home" else 3.0)
		await _shot("orbit", _planet.global_position + base * (r + alt), _planet.global_position, east)
	if _want("lod_fly"):
		await _lod_fly(base, gr, look_dir)
	if _want("dug_hole"):
		await _dug_hole(base, gr, look_dir)
	# --- feature sites -----------------------------------------------------------------------------------------
	var recipe := TerrainRecipe.of(_planet.body)
	var sites := {}
	if _want("cliff") or _want("plain"):
		var sp := _scout_slope(g)
		sites["cliff"] = sp[1]
		sites["plain"] = sp[0]
	for layer in [["canyon", "canyon_enabled"], ["mesa", "terrace_enabled"], ["crater", "craters_enabled"]]:
		if _want(layer[0]) and bool(recipe.get(layer[1])):
			var off := recipe.duplicate() as TerrainRecipe
			off.set(layer[1], false)
			sites[layer[0]] = _scout_layer(g, _planet.build_generator_with_recipe(off), layer[0])
	for name: String in ["cliff", "plain", "canyon", "mesa", "crater"]:
		if not sites.has(name) or not _want(name):
			continue
		var d: Vector3 = sites[name]
		await _goto(d, 25.0)
		var e := _east(d)
		var back := 45.0
		var height := 9.0
		if name == "cliff":
			back = 18.0
			height = 3.0
		elif name == "plain":
			back = 3.0
			height = 1.7
		elif name == "crater":
			back = 90.0
			height = 30.0
		var stand := (d - e * (back / r)).normalized()
		var target_r := _ground(d)
		var cam_pos := _at(stand, _ground(stand) + height)
		var tgt := _at(d, target_r + (2.0 if name != "plain" else -4.0))
		if name == "plain":
			tgt = _at((d + e * (200.0 / r)).normalized(), target_r - 6.0)
		_park_sun(d, 25.0, e)
		await _shot(name, cam_pos, tgt, d)

# --- helpers ------------------------------------------------------------------------------------------------

func _base_dir() -> Vector3:
	if _body == "home":
		return (_player.global_position - _planet.global_position).normalized()
	var d := _planet.suggested_spawn_direction()
	return d if d != Vector3.ZERO else Vector3(0.3, 0.8, 0.2).normalized()

func _east(d: Vector3) -> Vector3:
	return d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()

func _ground(d: Vector3) -> float:
	return _planet.surface_radius_along(d) * Planet.VOXEL_SCALE

func _ground_fast(d: Vector3) -> float:
	return _ground(d)

func _at(d: Vector3, radius_m: float) -> Vector3:
	return _planet.global_position + d * radius_m

func _goto(d: Vector3, sun_el: float) -> void:
	_player.global_position = _at(d, _ground(d) + 3.0)
	_park_sun(d, sun_el, _east(d))
	await get_tree().create_timer(SETTLE_SITE).timeout

## Sun `el` degrees above the local horizon, coming from 70 degrees off the view direction (raking light).
func _park_sun(d: Vector3, el: float, view: Vector3) -> void:
	var star := _world.get_node_or_null("Star") as Node3D
	if star == null:
		return
	var e := deg_to_rad(el)
	var horiz := view.rotated(d, 1.2).normalized()
	var sun_dir := (d * sin(e) + horiz * cos(e)).normalized()
	var dist: float = star.global_position.distance_to(_planet.global_position)
	star.global_position = _at(d, _planet.radius_world()) + sun_dir * dist

func _shot(name: String, pos: Vector3, target: Vector3, up_hint: Vector3) -> void:
	_cam.global_position = pos
	var up := (pos - _planet.global_position).normalized()
	if absf(up.dot((target - pos).normalized())) > 0.98:
		up = up_hint
	_cam.look_at(target, up)
	_cam.fov = 70.0
	await get_tree().create_timer(SETTLE_SHOT).timeout
	# frame time over 1.5 s
	var t := 0.0
	var n := 0
	while t < 1.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		n += 1
	await RenderingServer.frame_post_draw
	var path := "user://look_%s_%s_%s.png" % [_tag, _body, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("METRIC %s %s frame_ms %.1f" % [_body, name, 1000.0 * t / maxf(n, 1)])
	print("SHOT ", path)

## Fly the viewer (player node = VoxelViewer) and camera straight down from 5 km to 50 m in 12 s, counting
## frames whose terrain mesh-block count changed.
func _lod_fly(base: Vector3, gr: float, look_dir: Vector3) -> void:
	var tr := _planet.terrain as VoxelLodTerrain
	if tr == null:
		return
	_player.global_position = _at(base, gr + 5000.0)
	await get_tree().create_timer(SETTLE_SITE).timeout
	var last := tr.debug_get_mesh_block_count()
	var changes := 0
	var biggest := 0
	var t := 0.0
	while t < 12.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := clampf(t / 12.0, 0.0, 1.0)
		var alt := lerpf(5000.0, 50.0, k * k * (3.0 - 2.0 * k))
		_player.global_position = _at(base, gr + alt)
		_cam.global_position = _player.global_position
		_cam.look_at(_at((base + look_dir * (alt * 2.0 / _planet.radius_world())).normalized(), gr), base)
		var c := tr.debug_get_mesh_block_count()
		if c != last:
			changes += 1
			biggest = maxi(biggest, absi(c - last))
			last = c
	print("METRIC %s lod_changes %d (largest step %d blocks, final %d blocks)" % [_body, changes, biggest, last])

## Bore a 3 m hole 6 m in front of the eye with the real terrain tool, wait for the remesh, shoot into it.
func _dug_hole(base: Vector3, gr: float, look_dir: Vector3) -> void:
	var r := _planet.radius_world()
	var hole_dir := (base + look_dir * (6.0 / r)).normalized()
	var hole_r := _ground(hole_dir)
	var vt := _planet.terrain.get_voxel_tool()
	vt.channel = VoxelBuffer.CHANNEL_SDF
	vt.mode = VoxelTool.MODE_REMOVE
	var local := _planet.terrain.to_local(_at(hole_dir, hole_r - 1.0))
	vt.do_sphere(local, 3.0 / Planet.VOXEL_SCALE)
	_player.global_position = _at(base, gr + 3.0)
	await get_tree().create_timer(4.0).timeout
	await _shot("dug_hole", _at(base, gr + 2.2), _at(hole_dir, hole_r - 2.0), base)

func _scout_slope(g: VoxelGeneratorGraph) -> Array:
	var r := _planet.radius_world()
	var flat := Vector3.UP
	var steep := Vector3.UP
	var fmin := INF
	var smax := -1.0
	for i in 600:
		var d := _fib(i, 600)
		var e := _east(d)
		var a := _ground(d)
		var b := _ground((d + e * (12.0 / r)).normalized())
		var c := _ground((d - e * (12.0 / r)).normalized())
		var s := maxf(absf(b - a), absf(a - c)) / 12.0
		var curv := absf(b + c - 2.0 * a)
		if s + curv * 0.1 < fmin:
			fmin = s + curv * 0.1
			flat = d
		if s > smax:
			smax = s
			steep = d
	print("SITE cliff slope %.0f deg, plain slope %.1f deg" % [rad_to_deg(atan(smax)), rad_to_deg(atan(fmin))])
	return [flat, steep]

func _scout_layer(g: VoxelGeneratorGraph, off: VoxelGeneratorGraph, name: String) -> Vector3:
	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	var best := Vector3.UP
	var best_v := 0.0
	for i in 600:
		var d := _fib(i, 600)
		var dv := _h(g, buf, d) - _h(off, buf, d)
		var v := absf(dv) if name == "mesa" else -dv
		if v > best_v:
			best_v = v
			best = d
	print("SITE %s delta %.1f m" % [name, best_v])
	return best

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
	return (lo + hi) * 0.5 * Planet.VOXEL_SCALE

func _fib(i: int, n: int) -> Vector3:
	var y := 1.0 - (float(i) + 0.5) / float(n) * 2.0
	var rr := sqrt(maxf(1.0 - y * y, 0.0))
	var th := float(i) * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(th) * rr, y, sin(th) * rr).normalized()

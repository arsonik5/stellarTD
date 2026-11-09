extends Node

## The ground shot set (stage 0 of reports/AAA voxel terrain fidelity.md): the same views of the real planet every
## time, so every terrain change is judged against the last one. Low sun (25 degrees) from the side, because grazing
## light is what shows (or exposes) surface detail.
##     godot --path . res://scenes/dev/ground_shots.tscn -- tag=s0 [sun=25]
## Views (camera height above the ground at the spawn, looking ahead and down):
##   eye2    1.7 m, 30 degrees down       - pebble scale, the drill's view
##   m10     10 m,  35 degrees down       - the ground around a base
##   m50     50 m,  25 degrees down       - mid distance, tiling and scatter rhythm
##   m500    500 m, 20 degrees down       - landscape, macro variation, far colour
##   orbit   3 radii out, at the planet   - the body as a whole
## Writes art_src/ingame/ground_<tag>_<view>.png and prints GROUND lines with the mean GPU frame time per view.
const OUT := "res://art_src/ingame"
const VIEWS := [["eye2", 1.7, 30.0], ["m10", 10.0, 35.0], ["m50", 50.0, 25.0], ["m500", 500.0, 20.0], ["orbit", -1.0, 0.0],
		["top40", 40.0, 89.0], ["close", 1.2, 55.0]]
var tag := "s0"
var sun_deg := 25.0
var debug := 0
var only := ""
var noscatter := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
		elif a.begins_with("sun="):
			sun_deg = float(a.substr(4))
		elif a.begins_with("debug="):
			debug = int(a.substr(6))                 # terrain shader debug_view (2 = material, 7 = ladder step)
		elif a.begins_with("only="):
			only = a.substr(5)
		elif a == "noscatter=1":
			noscatter = true
	var player: Node3D = null
	for i in 900:
		await get_tree().create_timer(0.2).timeout
		player = get_tree().get_first_node_in_group("player")
		if player != null and player.is_spawn_resolved():
			break
	await get_tree().create_timer(3.0).timeout
	# the planet under the player (the "planet" group holds every body; the first may be a moon)
	var planet: Node3D = null
	for n in get_tree().get_nodes_in_group("planet"):
		var p3 := n as Node3D
		if planet == null or p3.global_position.distance_to(player.global_position) < planet.global_position.distance_to(player.global_position):
			planet = p3
	var star := get_tree().current_scene.find_child("Star", true, false) as Node3D
	var ground: Vector3 = player.global_position
	var up := PlanetPhysics.get_up(ground)
	var east := up.cross(Vector3.UP).normalized() if absf(up.dot(Vector3.UP)) < 0.9 else up.cross(Vector3.RIGHT).normalized()
	var north := east.cross(up).normalized()
	if star != null and planet != null:
		var sun := (up * sin(deg_to_rad(sun_deg)) + east * cos(deg_to_rad(sun_deg))).normalized()
		star.global_position = ground + sun * star.global_position.distance_to(planet.global_position)
	player.process_mode = Node.PROCESS_MODE_DISABLED        # hold the body still; the camera does the moving
	if player.get("viewmodel") != null:
		(player.viewmodel as Node3D).visible = false         # the held tools hang in front of the player's eyes
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false               # no HUD in the shot set
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 200000.0
	add_child(cam)
	cam.make_current()
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if debug != 0:
		var terrain = planet.get("terrain")
		if terrain != null and terrain.material is ShaderMaterial:
			(terrain.material as ShaderMaterial).set_shader_parameter("debug_view", debug)
	if noscatter:
		for n in get_tree().root.find_children("*", "VoxelInstancer", true, false):
			n.queue_free()
		for n in get_tree().root.find_children("NearScatter", "", true, false):
			n.queue_free()
		await get_tree().process_frame
	# scatter census: instances per item (ScatterEngine)
	for inst in get_tree().root.find_children("*", "VoxelInstancer", true, false):
		var vi := inst as VoxelInstancer
		if vi.has_method("debug_get_instance_counts"):
			var counts: Dictionary = vi.debug_get_instance_counts()
			var total := 0
			var by_line := {}
			for item_id in counts:
				var it := vi.library.get_item(item_id)
				var key := String(it.name).rsplit("_", true, 1)[0] if it != null else str(item_id)
				by_line[key] = int(by_line.get(key, 0)) + int(counts[item_id])
				total += int(counts[item_id])
			print("SCATTER %s total %d %s" % [vi.name, total, by_line])
	for v in VIEWS:
		var name: String = v[0]
		if only != "" and name != only:
			continue
		var h: float = v[1]
		if h > 0.0:
			var eye := ground + up * h - north * h * 0.2
			cam.global_position = eye
			var pitch := deg_to_rad(float(v[2]))
			var look := (north * cos(pitch) - up * sin(pitch)).normalized()
			cam.look_at(eye + look, up)
			cam.near = 0.05
		else:
			var c := planet.global_position
			var r: float = planet.call("radius_world") if planet.has_method("radius_world") else ground.distance_to(c)
			var dir := (up + east * 0.6).normalized()
			cam.global_position = c + dir * r * 3.0
			cam.look_at(c, north)
			cam.near = 5.0
		# let the terrain stream in around the new view, then measure 60 frames
		await get_tree().create_timer(6.0 if h > 100.0 or h < 0.0 else 3.0).timeout
		var sum := 0.0
		for i in 60:
			await RenderingServer.frame_post_draw
			sum += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		await RenderingServer.frame_post_draw
		var path := "%s/ground_%s_%s.png" % [OUT, tag, name]
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("GROUND tag=%s view=%s gpu_ms=%.2f draws=%d prims=%.1fM" % [tag, name, sum / 60.0, calls, prims / 1.0e6])
		var ns = planet.get("near_scatter")
		if ns != null:
			print("NEAR %s stones %d" % [name, ns.instance_count()])
	get_tree().quit()

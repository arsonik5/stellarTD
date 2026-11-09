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
##   cliff   110 m out from the steepest face within 1.2 km, looking at it - ledges, strata stripes, talus
## Writes art_src/ingame/ground_<tag>_<view>.png and prints GROUND lines with the mean GPU frame time per view.
const OUT := "res://art_src/ingame"
const VIEWS := [["eye2", 1.7, 30.0], ["m10", 10.0, 35.0], ["m50", 50.0, 25.0], ["m500", 500.0, 20.0], ["orbit", -1.0, 0.0],
		["top40", 40.0, 89.0], ["close", 1.2, 55.0], ["cliff", -2.0, 0.0]]
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
		if h == -2.0:
			var face := _steepest_face(planet, ground, up)
			if face.is_empty():
				print("GROUND no cliff found")
				continue
			var p: Vector3 = face.point
			var out: Vector3 = face.downhill
			var fu := PlanetPhysics.get_up(p)
			var side := out.cross(fu).normalized()
			cam.global_position = p + out * 110.0 + fu * 35.0 + side * 30.0
			cam.look_at(p + fu * 10.0, fu)
			if star != null:
				# light the face from over the camera's shoulder, low, so ledges cast shadows down the face
				var sdir := (out * cos(deg_to_rad(30.0)) + fu * sin(deg_to_rad(30.0)) + side * 0.5).normalized()
				star.global_position = p + sdir * star.global_position.distance_to(planet.global_position)
			cam.near = 0.1
			print("GROUND cliff slope %.0f deg at %.0f m from spawn" % [face.deg, p.distance_to(ground)])
		elif h > 0.0:
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
		if h == -2.0:
			await get_tree().create_timer(4.0).timeout
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

## The steepest landform within 1.2 km of the spawn, from the generator itself (no collision needed that far out):
## surface radius by bisection along a grid of directions, slope from two 40 m differences (landform, not a boulder).
## -> {"point": world Vector3, "downhill": world tangent Vector3, "deg": float} or {}
func _steepest_face(planet: Node3D, ground: Vector3, up: Vector3) -> Dictionary:
	var terrain = planet.get("terrain")
	if terrain == null or not (terrain.generator is VoxelGeneratorGraph):
		return {}
	var graph := terrain.generator as VoxelGeneratorGraph
	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	var c := planet.global_position
	var inv := planet.global_transform.basis.orthonormalized().inverse()
	var r0 := ground.distance_to(c)
	var surf := func(wdir: Vector3) -> float:
		var d: Vector3 = (inv * wdir).normalized()
		var lo := r0 - 400.0
		var hi := r0 + 400.0
		for _i in 18:
			var mid := (lo + hi) * 0.5
			graph.generate_block(buf, Vector3i((d * mid).round()), 0)
			if buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) < 0.0:
				lo = mid
			else:
				hi = mid
		return (lo + hi) * 0.5
	var east := up.cross(Vector3.UP).normalized() if absf(up.dot(Vector3.UP)) < 0.9 else up.cross(Vector3.RIGHT).normalized()
	var north := east.cross(up).normalized()
	var best := {}
	var best_s := 0.0
	var step := 40.0
	for gx in range(-12, 13):
		for gy in range(-12, 13):
			var off := east * gx * 100.0 + north * gy * 100.0
			if off.length() < 60.0:
				continue
			var wdir := (ground + off - c).normalized()
			var t_e := up.cross(wdir).cross(wdir).normalized() * -1.0
			var t_e2 := wdir.cross(t_e).normalized()
			var rc: float = surf.call(wdir)
			var re: float = surf.call((c + wdir * r0 + t_e * step - c).normalized())
			var rn: float = surf.call((c + wdir * r0 + t_e2 * step - c).normalized())
			var g := Vector2(re - rc, rn - rc) / step
			var sl := g.length()
			if sl > best_s:
				best_s = sl
				var down := -(t_e * g.x + t_e2 * g.y).normalized()
				best = {"point": c + wdir * rc, "downhill": down, "deg": rad_to_deg(atan(sl))}
	if not best.is_empty():
		# what the generator paints just under that face: slots and 4-bit weights, plus the baked slope mask there
		var lp: Vector3 = inv * (best.point - c)
		var q := lp - lp.normalized() * 1.5
		graph.generate_block(buf, Vector3i(q.round()), 0)
		var pi := int(buf.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_INDICES))
		var pw := int(buf.get_voxel(0, 0, 0, VoxelBuffer.CHANNEL_WEIGHTS))
		var parts := []
		for k in 4:
			parts.append("%d:%d" % [(pi >> (k * 4)) & 0xF, (pw >> (k * 4)) & 0xF])
		var masks = planet.get("_erosion_masks")
		var sm := -1.0
		if masks is Dictionary and masks.has("slope"):
			var img: Image = masks["slope"]
			var d := lp.normalized()
			var uv := SphereUV.uv_of(d)
			var u := uv.x
			var v := uv.y
			sm = img.get_pixel(clampi(int(u * img.get_width()), 0, img.get_width() - 1), clampi(int(v * img.get_height()), 0, img.get_height() - 1)).r * 90.0
		# and the same mask read the way the generator reads it (through the heightmap node)
		var node_sm := -1.0
		if masks is Dictionary and masks.has("slope"):
			var tg := VoxelGeneratorGraph.new()
			var tf: VoxelGraphFunction = tg.get_main_function()
			var ix := tf.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2())
			var iy := tf.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2())
			var iz := tf.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2())
			var m := PlanetGraphGenerator._sample_mask(tf, ix, iy, iz, masks["slope"], float(planet.body.radius), Vector2())
			var o := tf.create_node(VoxelGraphFunction.NODE_OUTPUT_SDF, Vector2())
			tf.add_connection(m[0], m[1], o, 0)
			tg.compile()
			var b2 := VoxelBuffer.new()
			b2.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
			b2.create(1, 1, 1)
			tg.generate_block(b2, Vector3i(q.round()), 0)
			node_sm = b2.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) * 90.0
		print("GROUND cliff slots %s  baked slope %.0f deg (cpu)  %.0f deg (node)" % [" ".join(parts), sm, node_sm])
	return best

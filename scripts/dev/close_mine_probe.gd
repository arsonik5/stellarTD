extends Node
## Dev probe: does the mining raycast find the face from very close (and from just inside it)?
##     godot --path . res://scenes/dev/close_mine_probe.tscn
## For eye distances from 2 m in front of the surface down to 0.3 m inside the rock, prints whether the plain
## VoxelTool.raycast hits and whether TerrainDrill.raycast_close (what the drill uses) hits.
const RANGE: float = preload("res://scripts/player/player.gd").DIG_RANGE

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	var terrain: VoxelLodTerrain = planet.get("terrain")
	var tool := terrain.get_voxel_tool()
	var centre: Vector3 = planet.global_position
	var dir: Vector3 = planet.call("suggested_spawn_direction")
	var above: float = planet.call("radius_world") + planet.call("max_relief_world") + 10.0
	var sky := centre + dir * above
	var hit: VoxelRaycastResult = null
	var deadline := Time.get_ticks_msec() + 20000
	while hit == null and Time.get_ticks_msec() < deadline:
		hit = tool.raycast(sky, -dir, 400.0)
		if hit == null:
			await get_tree().process_frame
	if hit == null:
		print("CLOSE no surface")
		get_tree().quit()
		return
	var surface := terrain.to_global(Vector3(hit.position) + Vector3(0.5, 0.5, 0.5))
	var plain_fail := 0
	var close_fail := 0
	for d: float in [2.0, 1.0, 0.6, 0.3, 0.15, 0.05, -0.05, -0.15, -0.3]:
		var eye := surface + dir * d
		var a := tool.raycast(eye, -dir, RANGE, 0xFFFFFFFF)
		var b := TerrainDrill.raycast_close(tool, eye, -dir, RANGE)
		if a == null: plain_fail += 1
		if b == null: close_fail += 1
		print("CLOSE eye %+.2f m from surface: plain=%s drill=%s" % [d, a != null, b != null])
	print("CLOSE plain misses %d, drill misses %d" % [plain_fail, close_fail])
	# bites: hold the drill still at each eye distance for 2 s (40 bites) at spots 10 m apart, count what came out
	var tangent := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	var spot := 1
	for d: float in [1.5, 0.6, 0.15, -0.1]:
		var sdir := (dir * above + tangent * (10.0 * spot)).normalized()
		spot += 1
		var s_hit: VoxelRaycastResult = null
		var dl := Time.get_ticks_msec() + 20000
		while s_hit == null and Time.get_ticks_msec() < dl:
			s_hit = tool.raycast(centre + sdir * above, -sdir, 400.0)
			if s_hit == null:
				await get_tree().process_frame
		if s_hit == null:
			print("CLOSE bite d=%.2f no surface" % d)
			continue
		var surf := terrain.to_global(Vector3(s_hit.position) + Vector3(0.5, 0.5, 0.5))
		var eye2 := surf + sdir * d
		var scale := terrain.scale.x
		var radius := TerrainDrill.BORE_RADIUS_M / scale
		var aim_local := (terrain.global_transform.basis.inverse() * -sdir).normalized()
		var total := 0.0
		var misses := 0
		var depth0 := surf.distance_to(eye2)
		for t in 40:
			var h := TerrainDrill.raycast_close(tool, eye2, -sdir, RANGE)
			if h == null:
				misses += 1
				await get_tree().create_timer(TerrainDrill.TICK_INTERVAL).timeout
				continue
			var mi := TerrainDrill.dominant_material_at(tool, h.position)
			var rem := TerrainDrill.bite(tool, TerrainDrill.bite_center(Vector3(h.position), aim_local, radius), radius, TerrainDrill.strength_for(mi))
			for k: int in rem:
				total += rem[k]
			await get_tree().create_timer(TerrainDrill.TICK_INTERVAL).timeout
		var h_end := TerrainDrill.raycast_close(tool, eye2, -sdir, RANGE)
		var face_now := terrain.to_global(Vector3(h_end.position) + Vector3(0.5, 0.5, 0.5)).distance_to(eye2) if h_end != null else -1.0
		print("CLOSE bite eye %+.2f m: removed %.1f voxels in 2 s, raycast misses %d/40, face %.2f -> %.2f m from eye" % [d, total, misses, depth0, face_now])
	get_tree().quit()

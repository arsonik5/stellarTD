extends Node

## Dev tool: does the mining drill actually bore, and how fast does it pay?
##
##     godot --path . res://scenes/dev/drill_probe.tscn
##
## Bores straight down the radial at spots near spawn, the way a held mouse
## button would: raycast from the "eye" with the player's real DIG_RANGE, bite
## at the hit, and follow the drill into the hole. The eye only ever moves
## ALONG the bore axis - snapping it to the hit voxel's centre each tick
## ratcheted it sideways across the voxel staircase and turned the bore into a
## trench walking 20 m/s across the surface.
##   A - real per-material strength (what the player gets)
##   B - forced strength 1.0 (control: proves sdf_strength changes anything)
##   C - strength for hardness 2.5 (crystal-hard rock)
##   COST - raw engine timings: copy(), the new bite sphere, the OLD dig's
##          full-strength 1.75 m sphere (baseline the new bite is judged against)

const SECONDS := 3.0
const EYE_BACK := 2.0
const DIG_RANGE: float = preload("res://scripts/player/player.gd").DIG_RANGE
const COST_SAMPLES := 20

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	var terrain: VoxelLodTerrain = planet.get("terrain")
	var tool := terrain.get_voxel_tool()
	var centre: Vector3 = planet.global_position
	var spawn_dir: Vector3 = planet.call("suggested_spawn_direction")
	var above: float = planet.call("radius_world") + planet.call("max_relief_world") + 10.0

	# Spots a few metres apart, tangent to the surface - no world-Y.
	var tangent := spawn_dir.cross(Vector3.RIGHT if absf(spawn_dir.x) < 0.9 else Vector3.FORWARD).normalized()
	var spots := {
		"A_real": -1.0,
		"B_full": 1.0,
		"C_hard": TerrainDrill.BASE_STRENGTH / 2.5,
	}
	var i := 0
	for label: String in spots:
		var dir := (spawn_dir * above + tangent * (8.0 * i)).normalized()
		await _bore(label, tool, terrain, centre + dir * above, -dir, spots[label])
		i += 1
	var cost_dir := (spawn_dir * above + tangent * (8.0 * i)).normalized()
	await _cost(tool, terrain, centre + cost_dir * above, -cost_dir, tangent)
	print("DRILL done")
	get_tree().quit()

func _surface(tool: VoxelTool, sky: Vector3, dir: Vector3) -> VoxelRaycastResult:
	var hit: VoxelRaycastResult = null
	var deadline := Time.get_ticks_msec() + 20000
	while hit == null and Time.get_ticks_msec() < deadline:
		hit = tool.raycast(sky, dir, 400.0)
		if hit == null:
			await get_tree().process_frame
	return hit

func _bore(label: String, tool: VoxelTool, terrain: VoxelLodTerrain, sky: Vector3, dir: Vector3, forced_strength: float) -> void:
	var hit: VoxelRaycastResult = await _surface(tool, sky, dir)
	if hit == null:
		print("DRILL %s no surface" % label)
		return

	_check_copy(label + "_start", tool, hit.position)
	var scale := terrain.scale.x
	var radius := TerrainDrill.BORE_RADIUS_M / scale
	var aim_local := (terrain.global_transform.basis.inverse() * dir).normalized()
	var surface := _world(terrain, hit)
	var eye := surface - dir * EYE_BACK
	var carry := {}
	var paid := {}
	var removed_total := 0.0
	var ticks := int(SECONDS / TerrainDrill.TICK_INTERVAL)
	var bite_usec := 0
	var worst_usec := 0
	for t in ticks:
		hit = tool.raycast(eye, dir, DIG_RANGE)
		if hit == null:
			print("DRILL %s out of range at tick %d" % [label, t])
			break
		var mat := TerrainDrill.dominant_material_at(tool, hit.position)
		var strength := forced_strength if forced_strength > 0.0 else TerrainDrill.strength_for(mat)
		var u0 := Time.get_ticks_usec()
		var removed := TerrainDrill.bite(tool, TerrainDrill.bite_center(Vector3(hit.position), aim_local, radius), radius, strength)
		var cost := Time.get_ticks_usec() - u0
		bite_usec += cost
		worst_usec = maxi(worst_usec, cost)
		for m: int in removed:
			removed_total += removed[m]
		var out := TerrainDrill.payout(carry, removed, scale * scale * scale)
		for id: String in out:
			paid[id] = paid.get(id, 0) + out[id]
		# Follow the face along the axis only.
		var face := tool.raycast(eye, dir, DIG_RANGE)
		if face != null:
			var ahead := (_world(terrain, face) - eye).dot(dir) - EYE_BACK
			if ahead > 0.0:
				eye += dir * ahead
		if (t + 1) % 20 == 0:
			var depth := (eye + dir * EYE_BACK - surface).dot(dir)
			var width := _bore_width(tool, terrain, eye + dir * (EYE_BACK - 0.6), dir)
			print("DRILL %s t=%.2fs mat=%s str=%.2f depth=%.2fm width=%.1fm removed=%.1fvox paid=%s" % [
				label, (t + 1) * TerrainDrill.TICK_INTERVAL, VoxelMaterials.name_for(mat),
				strength, depth, width, removed_total, paid])
		await get_tree().process_frame
	print("DRILL %s bite_ms avg=%.2f worst=%.2f" % [label, bite_usec / 1000.0 / ticks, worst_usec / 1000.0])
	var end_hit := tool.raycast(eye, dir, DIG_RANGE)
	if end_hit != null:
		_check_copy(label + "_end", tool, end_hit.position)

## Raw engine costs, each on untouched ground so earlier edits don't skew it.
func _cost(tool: VoxelTool, terrain: VoxelLodTerrain, sky: Vector3, dir: Vector3, tangent: Vector3) -> void:
	var hit: VoxelRaycastResult = await _surface(tool, sky, dir)
	if hit == null:
		print("DRILL COST no surface")
		return
	var radius := TerrainDrill.BORE_RADIUS_M / terrain.scale.x
	var reach := radius + 1.0
	var size := Vector3i.ONE * (int(ceil(reach * 2.0)) + 1)
	var copy_us := 0
	var new_us := 0
	var old_us := 0
	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	tool.set_mode(VoxelTool.MODE_REMOVE)
	for k in COST_SAMPLES:
		var p := Vector3(hit.position) + Vector3(0.5, 0.5, 0.5) + tangent * (3.0 * k)
		var buf := TerrainDrill._buffer(size)
		var u := Time.get_ticks_usec()
		tool.copy(Vector3i(p.floor()) - size / 2, buf, TerrainDrill.READ_MASK, false)
		copy_us += Time.get_ticks_usec() - u

		tool.set_sdf_strength(TerrainDrill.BASE_STRENGTH)
		u = Time.get_ticks_usec()
		tool.do_sphere(p, radius)
		new_us += Time.get_ticks_usec() - u

		# Old dig: two full-strength spheres, 1.75 and 0.55, 3 m further along.
		tool.set_sdf_strength(1.0)
		var q := p + tangent * 1.5
		u = Time.get_ticks_usec()
		tool.do_sphere(q, 1.75 / terrain.scale.x)
		tool.do_sphere(q, 0.55 / terrain.scale.x)
		old_us += Time.get_ticks_usec() - u
		await get_tree().process_frame
	print("DRILL COST avg_ms copy=%.2f new_sphere=%.2f old_dig_spheres=%.2f (n=%d)" % [
		copy_us / 1000.0 / COST_SAMPLES, new_us / 1000.0 / COST_SAMPLES, old_us / 1000.0 / COST_SAMPLES, COST_SAMPLES])

## Widest air diameter across the bore just above the face: sample outward
## along two tangents until SDF says solid.
func _bore_width(tool: VoxelTool, terrain: VoxelLodTerrain, at: Vector3, dir: Vector3) -> float:
	var t1 := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	var t2 := dir.cross(t1)
	var inv := terrain.global_transform.affine_inverse()
	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	if tool.get_voxel_f(Vector3i((inv * at).floor())) < 0.0:
		return -1.0 # sample point is inside rock - no bore here
	var best := 0.0
	for axis: Vector3 in [t1, t2]:
		var span := 0.0
		for sgn: float in [1.0, -1.0]:
			var r := 0.0
			while r < 4.0:
				var p: Vector3 = inv * (at + axis * sgn * (r + 0.1))
				if tool.get_voxel_f(Vector3i(p.floor())) < 0.0:
					break
				r += 0.1
			span += r
		best = maxf(best, span)
	return best

## bite() trusts copy() into a VoxelBuffer to read the same SDF and packed
## material words as per-voxel tool reads. Prove it on a 5^3 cube.
func _check_copy(label: String, tool: VoxelTool, at: Vector3i) -> void:
	var lo := at - Vector3i(2, 2, 2)
	var buf := TerrainDrill._buffer(Vector3i(5, 5, 5))
	tool.copy(lo, buf, TerrainDrill.READ_MASK, false)
	var sdf_bad := 0
	var mat_bad := 0
	var worst := 0.0
	for x in 5:
		for y in 5:
			for z in 5:
				var p := lo + Vector3i(x, y, z)
				tool.set_channel(VoxelBuffer.CHANNEL_SDF)
				var diff := absf(tool.get_voxel_f(p) - buf.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF))
				if diff > 0.01:
					sdf_bad += 1
					worst = maxf(worst, diff)
				var m := TerrainDrill.dominant_from_packed(
					buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_INDICES),
					buf.get_voxel(x, y, z, VoxelBuffer.CHANNEL_WEIGHTS))
				if m != TerrainDrill.dominant_material_at(tool, p):
					mat_bad += 1
	print("DRILL %s copy_check sdf_mismatch=%d (worst %.2f) mat_mismatch=%d of 125" % [label, sdf_bad, worst, mat_bad])

func _world(terrain: VoxelLodTerrain, hit: VoxelRaycastResult) -> Vector3:
	return terrain.global_transform * (Vector3(hit.position) + Vector3(0.5, 0.5, 0.5))

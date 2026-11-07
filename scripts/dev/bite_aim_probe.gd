extends Node
## Dev probe: where does do_sphere really centre its cut, relative to the integer voxel index?
## Carves a sphere deep in solid rock at an integer centre and reports the centroid of the cut cells.
##     godot --path . res://scenes/dev/bite_aim_probe.tscn
func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	var terrain: VoxelLodTerrain = planet.get("terrain")
	var tool := terrain.get_voxel_tool()
	var dir: Vector3 = planet.call("suggested_spawn_direction")
	var above: float = planet.call("radius_world") + planet.call("max_relief_world") + 10.0
	var hit: VoxelRaycastResult = null
	var dl := Time.get_ticks_msec() + 20000
	while hit == null and Time.get_ticks_msec() < dl:
		hit = tool.raycast(planet.global_position + dir * above, -dir, 400.0)
		if hit == null:
			await get_tree().process_frame
	print("AIM terrain scale %s, hit index %s" % [terrain.scale, hit.position])
	var ldir := (terrain.global_transform.basis.inverse() * -dir).normalized()
	var c := Vector3(hit.position) + ldir * 12.0 / terrain.scale.x
	c = Vector3(roundi(c.x), roundi(c.y), roundi(c.z))
	var r := 3.0
	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	tool.set_mode(VoxelTool.MODE_REMOVE)
	tool.do_sphere(c, r)
	var lo := Vector3i((c - Vector3.ONE * (r + 3)).floor())
	var n := int(2 * (r + 3)) + 1
	var buf := VoxelBuffer.new()
	buf.create(n, n, n)
	tool.copy(lo, buf, 1 << VoxelBuffer.CHANNEL_SDF, false)
	var sum := Vector3.ZERO
	var cnt := 0.0
	var mx := -99.0
	for x in n:
		for y in n:
			for z in n:
				var s: float = buf.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
				mx = maxf(mx, s)
				if s > 0.0:
					sum += Vector3(lo + Vector3i(x, y, z))
					cnt += 1.0
	print("AIM carved at %s r=%.1f: %d cells with sdf>0, centroid of their indices %s, max sdf %.2f" % [c, r, int(cnt), sum / maxf(cnt, 1.0), mx])
	print("AIM centroid minus centre = %s  (0 => samples sit AT the index, -0.5 => at index+0.5)" % [sum / maxf(cnt, 1.0) - c])
	# --- aim accuracy: the same 25 bites with the OLD centre (hit voxel + 0.5) and the NEW one (exact surface point) ---
	var tangent := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	var spot := 1
	for mode: String in ["old (+0.5 voxel centre)", "new (exact surface)"]:
		var sdir := (dir * above + tangent * (12.0 * spot)).normalized()
		spot += 1
		var h2: VoxelRaycastResult = null
		var dl2 := Time.get_ticks_msec() + 20000
		while h2 == null and Time.get_ticks_msec() < dl2:
			h2 = tool.raycast(planet.global_position + sdir * above, -sdir, 400.0)
			if h2 == null:
				await get_tree().process_frame
		# eye 3 m above the surface, aiming 20 degrees off the straight-down line (so the aim is not on a grid axis)
		var surf_w := terrain.to_global(Vector3(h2.position))
		var lat := sdir.cross(tangent).normalized()
		var aim_w := (-sdir * cos(deg_to_rad(20.0)) + tangent * sin(deg_to_rad(20.0))).normalized()
		var eye_w := surf_w + sdir * 3.0 - aim_w * 0.0
		var inv := terrain.global_transform.affine_inverse()
		var eye_l: Vector3 = inv * eye_w
		var aim_l: Vector3 = (inv.basis * aim_w).normalized()
		var radius := TerrainDrill.BORE_RADIUS_M / terrain.scale.x
		var lo2 := Vector3i((eye_l - Vector3.ONE * 14.0).floor())
		var sz := 29
		var before := VoxelBuffer.new()
		before.create(sz, sz, sz)
		tool.copy(lo2, before, 1 << VoxelBuffer.CHANNEL_SDF, false)
		var first_hit: VoxelRaycastResult = tool.raycast(eye_w, aim_w, 30.0)
		if first_hit == null:
			print("AIM %s: aim ray missed the ground" % mode)
			continue
		var aim_point: Vector3 = TerrainDrill.surface_point(tool, eye_l, aim_l, first_hit.position)   # where the crosshair truly meets rock
		for i in 25:
			var hh: VoxelRaycastResult = tool.raycast(eye_w, aim_w, 30.0)
			if hh == null:
				break
			var ctr: Vector3
			if mode.begins_with("old"):
				ctr = Vector3(hh.position) + Vector3(0.5, 0.5, 0.5) - aim_l * radius * TerrainDrill.BITE_BACKOFF
			else:
				ctr = TerrainDrill.bite_center(TerrainDrill.surface_point(tool, eye_l, aim_l, hh.position), aim_l, radius)
			TerrainDrill.bite(tool, ctr, radius, 1.0)
		var after := VoxelBuffer.new()
		after.create(sz, sz, sz)
		tool.copy(lo2, after, 1 << VoxelBuffer.CHANNEL_SDF, false)
		var wsum := 0.0
		var csum := Vector3.ZERO
		for x in sz:
			for y in sz:
				for z in sz:
					var dsolid := TerrainDrill._solid(before.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)) - TerrainDrill._solid(after.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF))
					if dsolid > 0.001:
						wsum += dsolid
						csum += Vector3(lo2 + Vector3i(x, y, z)) * dsolid
		var cen := csum / maxf(wsum, 0.001)
		# how far the crater's centre line sits from the aim line, and how deep along it
		var rel := cen - eye_l
		var along := rel.dot(aim_l)
		var off := (rel - aim_l * along).length()
		print("AIM %s: removed %.0f, crater centre is %.2f voxels off the aim line, %.1f along it (first contact at %.1f)" % [mode, wsum, off, along, (aim_point - eye_l).dot(aim_l)])
	# --- stall check: hold the drill still for 8 s at real stone strength (0.065), count what each 1 s comes out ---
	var sdir2 := (dir * above + tangent * (12.0 * spot)).normalized()
	var h3: VoxelRaycastResult = null
	var dl3 := Time.get_ticks_msec() + 20000
	while h3 == null and Time.get_ticks_msec() < dl3:
		h3 = tool.raycast(planet.global_position + sdir2 * above, -sdir2, 400.0)
		if h3 == null:
			await get_tree().process_frame
	var inv3 := terrain.global_transform.affine_inverse()
	var eye3: Vector3 = inv3 * (terrain.to_global(Vector3(h3.position)) + sdir2 * 2.0)
	var aim3: Vector3 = (inv3.basis * -sdir2).normalized()
	var empty_run := 0
	var chunk := 0.0
	var worst_empty := 0
	var r3 := TerrainDrill.BORE_RADIUS_M / terrain.scale.x
	for i in 160:
		var hh3: VoxelRaycastResult = tool.raycast(terrain.to_global(eye3), terrain.global_transform.basis * aim3, 30.0)
		if hh3 == null:
			print("AIM stall: ray lost the ground at bite %d" % i)
			break
		var c3 := TerrainDrill.bite_center(TerrainDrill.surface_point(tool, eye3, aim3, hh3.position), aim3, r3)
		if empty_run >= 3:
			c3 += aim3 * r3 * minf(0.25 * float(empty_run - 2), 1.0)
		var rem3 := TerrainDrill.bite(tool, c3, r3, TerrainDrill.BASE_STRENGTH / 1.0)
		var amount := 0.0
		for k: int in rem3:
			amount += rem3[k]
		chunk += amount
		empty_run = 0 if amount > 0.0 else empty_run + 1
		worst_empty = maxi(worst_empty, empty_run)
		if (i + 1) % 20 == 0:
			print("AIM stall: bites %d-%d removed %.1f voxels" % [i - 18, i + 1, chunk])
			chunk = 0.0
	print("AIM stall: longest run of empty bites = %d" % worst_empty)
	get_tree().quit()

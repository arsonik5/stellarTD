extends Node

## Dev tool: is the scan cube actually WHERE the scanner thinks it is?
##
##     godot --path . res://scenes/dev/scan_verify.tscn
##
## OreScanner labels every hit with a world position it derives from the same
## `origin_voxels` it passed to generate_block. If generate_block interprets
## that origin differently than assumed - LOD-space voxels rather than LOD-0
## voxels, say - the buffer holds terrain from somewhere else entirely and every
## marker is confidently wrong in a self-consistent way. Nothing in the scanner
## output could reveal that, because the error cancels.
##
## Ground truth: the SDF channel. The surface inside the buffer has to sit at
## the planet radius the census already reports for that direction. If it does,
## the mapping is right.

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	var terrain: VoxelLodTerrain = planet.get("terrain")
	var centre: Vector3 = planet.global_position
	var radius: float = planet.call("radius_world")

	var dir := Vector3(0.19, -0.48, 0.86).normalized()
	var origin: Vector3 = centre + dir * (radius + 30.0)

	var step: int = 1 << OreScanner.SCAN_LOD
	var span: int = OreScanner.GRID * step
	var buffer := VoxelBuffer.new()
	buffer.create(OreScanner.GRID, OreScanner.GRID, OreScanner.GRID)
	var corner := origin - terrain.global_position - Vector3.ONE * (span * 0.5)
	var ov := Vector3i(
		int(floor(corner.x / step)) * step,
		int(floor(corner.y / step)) * step,
		int(floor(corner.z / step)) * step)
	terrain.generator.generate_block(buffer, ov, OreScanner.SCAN_LOD)

	# Orientation-independent: count solid vs air across the WHOLE cube, and
	# check the solid voxels really are at the radius they should be.
	#
	# An earlier version walked a world-Y column and reported "no surface". That
	# was the check being wrong, not the scanner: the player's up is RADIAL, so a
	# world-axis column through a cube on the far side of the planet need never
	# cross the ground at all.
	var solid := 0
	var air := 0
	var min_r := INF
	var max_r := -INF
	var step_f := float(step)
	for z in OreScanner.GRID:
		for y in OreScanner.GRID:
			for x in OreScanner.GRID:
				var sdf := buffer.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF)
				var wpos: Vector3 = terrain.global_position + Vector3(
					ov.x + x * step, ov.y + y * step, ov.z + z * step)
				var r := wpos.distance_to(centre)
				if sdf < 0.0:
					solid += 1
					min_r = minf(min_r, r)
					max_r = maxf(max_r, r)
				else:
					air += 1

	var total := OreScanner.GRID * OreScanner.GRID * OreScanner.GRID
	print("
=== scan cube coordinate check ===")
	print("  planet nominal radius   %.1f" % radius)
	print("  scan origin distance    %.1f  (radius + 30)" % origin.distance_to(centre))
	print("  cube spans              %d m at %d m per sample" % [span, step])
	print("  solid voxels            %d of %d  (%.1f%%)" % [solid, total, 100.0 * solid / total])
	if solid == 0:
		print("  VERDICT: cube is ENTIRELY AIR - it is not on the ground")
	elif air == 0:
		print("  VERDICT: cube is ENTIRELY SOLID - it is buried")
	else:
		print("  solid radius range      %.1f .. %.1f" % [min_r, max_r])
		print("  expected surface near   %.1f" % radius)
		print("  VERDICT: %s" % ("mapping OK - cube straddles the surface"
			if max_r > radius - 2000.0 and min_r < radius + 2000.0
			else "MAPPING WRONG - solid ground is at the wrong radius"))
	print("SCAN_VERIFY_DONE")
	get_tree().quit()

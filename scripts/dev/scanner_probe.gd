extends Node

## Dev tool: does the ore scanner find anything, and are there deposits to find?
##
##     godot --path . res://scenes/dev/scanner_probe.tscn
##
## Doubles as the check that ore bodies exist UNDERGROUND. The surface material
## census only samples the skin, so it can only ever see the discoloured
## patches - it cannot tell a deposit from a stain with nothing under it.

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var planet: Node = get_tree().get_first_node_in_group("planet")
	while planet == null or not planet.get("is_terrain_ready"):
		await get_tree().process_frame
		planet = get_tree().get_first_node_in_group("planet")
	var terrain: VoxelLodTerrain = planet.get("terrain")
	var body = planet.get("body")

	var names := {}
	for ore in body.ore_types:
		names[ore.material_index] = "%s (%.0f-%.0f m)" % [ore.id, ore.depth_min, ore.depth_max]

	# Several widely separated points, because one sample says nothing about
	# whether deposits are distributed or whether we happened to land on one.
	var radius: float = planet.call("radius_world")
	var dirs := [
		Vector3(1, 0.2, 0.3), Vector3(-0.4, 0.8, 0.1), Vector3(0.2, -0.5, 0.9),
		Vector3(-0.7, -0.3, -0.6), Vector3(0.5, 0.5, -0.7),
	]
	# Unfiltered dump first: which material indices exist at all, and at what
	# weight. Zero results from a filtered scan has three possible causes -
	# no ore generated, wrong indices, or the weight threshold - and they are
	# indistinguishable without looking at the raw channel.
	_dump_materials(terrain, planet.global_position
		+ Vector3(1, 0.2, 0.3).normalized() * (radius + 30.0), names)

	var total := 0
	for d: Vector3 in dirs:
		var pos: Vector3 = planet.global_position + d.normalized() * (radius + 30.0)
		var t0 := Time.get_ticks_msec()
		var found: Array = OreScanner.scan(terrain, pos, names)
		var ms := Time.get_ticks_msec() - t0
		print("\n--- scan at %s   %d ms, %d deposits" % [d.normalized(), ms, found.size()])
		for h in found:
			var label: String = names.get(h["material_index"],
				"material %d" % h["material_index"])
			print("      %-22s %6.0f m away, %d samples" %
				[label, h["distance"], h["samples"]])
		total += found.size()
	print("\nTOTAL deposits across %d scans: %d" % [dirs.size(), total])

	# The HUD path, end to end. The scanner core being right says nothing about
	# whether the overlay is wired to it - and a scanner that finds deposits but
	# shows nothing is indistinguishable, from the player's side, from one that
	# finds nothing.
	var hud := get_tree().get_first_node_in_group("scanner_hud")
	if hud == null:
		print("HUD: NOT FOUND in group scanner_hud")
	else:
		var rich: Vector3 = planet.global_position + Vector3(0.190693, -0.476731, 0.858116).normalized() * (radius + 30.0)
		hud.call("scan_from", terrain, rich, names)
		var markers: Array = hud.get("_contacts")
		print("HUD: %d contacts after scan_from" % markers.size())
		for m in markers:
			print("      marker %-10s %.0f m" % [m["name"], rich.distance_to(m["position"])])

	print("SCANNER_PROBE_DONE")
	get_tree().quit()

func _dump_materials(terrain: VoxelLodTerrain, origin: Vector3, names: Dictionary) -> void:
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

	var max_w := {}
	var count := {}
	var solid := 0
	for z in OreScanner.GRID:
		for y in OreScanner.GRID:
			for x in OreScanner.GRID:
				var wts: int = buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_WEIGHTS)
				var idc: int = buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_INDICES)
				if wts == 0:
					continue
				solid += 1
				for slot in 4:
					var w: int = (wts >> (slot * 4)) & 0xF
					if w == 0:
						continue
					var i: int = (idc >> (slot * 4)) & 0xF
					max_w[i] = maxi(max_w.get(i, 0), w)
					count[i] = count.get(i, 0) + 1
	print("
=== raw material dump: %d voxels with any weight ===" % solid)
	var keys := max_w.keys()
	keys.sort()
	for i in keys:
		print("   index %2d  max weight %2d/15  in %6d voxels   %s" %
			[i, max_w[i], count[i], "ORE: " + str(names.get(i, "")) if names.has(i) else ""])
	print("   ore indices expected: ", names.keys())

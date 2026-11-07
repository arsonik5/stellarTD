class_name OreScanner
extends RefCounted

## Finds ore deposits near a point, by asking the real generator.
##
## Satisfactory's resource scanner: ping, then on-screen markers point at the
## nearest nodes with a distance. This is the part that answers "where".
##
## It samples the ACTUAL generator through `generate_block` rather than
## reimplementing deposit placement in GDScript. That matters more than it
## sounds: the deposits come out of a `Spots3D` graph node whose internal hash
## is not reproducible from outside, so any GDScript reimplementation would be
## an approximation that drifts from the terrain the player actually digs. A
## scanner that points at ore which is not there is worse than no scanner.
##
## Coarse on purpose. Deposits are hundreds of metres across, so sampling every
## 32 m finds them comfortably while keeping a scan to tens of thousands of
## voxel evaluations instead of millions.

## Cube edge in samples. 32^3 is 32768 evaluations - at ~6 us/voxel that is
## about 0.2 s, which is a scan pulse rather than a freeze.
##
## Widening the scan was done by coarsening SCAN_LOD rather than by raising
## this, because cost goes as the CUBE of this number and only linearly with
## the metres each sample covers. Doubling GRID would have been 8x the work for
## 2x the reach.
const GRID := 32

## LOD to generate at. Each step doubles the metres per sample.
##
## LOD 7 is 128 m per sample, so the 32-sample cube spans 4 km - reaching
## +-2048 m rather than the +-512 m LOD 5 gave, for exactly the same number of
## evaluations.
##
## The range matters more than the precision here. Deposits sit ~1400 m apart
## (DEPOSIT_SPACING_M), so a +-512 m scan could not reach even one from most
## places on the planet: it reported nothing over and over, and the one time it
## did find something the hits were all 589-879 m away - in the CORNERS of the
## cube, which is the only part of it that reached far enough. A scanner whose
## radius is under a third of the spacing of the thing it looks for is going to
## come back empty almost everywhere.
##
## The cost of the trade is marker precision: a deposit is located to within
## about a sample, so 128 m rather than 32 m. For a readout that says "copper,
## 1.4 km, that way" it does not matter, and the deposits themselves are several
## hundred metres across.
const SCAN_LOD := 6

## Minimum blend weight for a material to count as present. The mesher keeps
## four weighted materials per voxel; a trace of ore in a mostly-stone voxel is
## not a deposit.
const MIN_WEIGHT := 6  # of 15

## Samples of the same ore within this distance are treated as one deposit.
## Comfortably wider than the sample spacing, so a single deposit does not come
## back as a scatter of separate contacts.
## Comfortably above the 128 m sample spacing, so the samples within one
## deposit chain together into a single contact instead of the coarse grid
## splitting one deposit into several markers.
const CLUSTER_M := 160.0

## Clusters smaller than this are grid-clipped edges rather than deposits.
const MIN_SAMPLES := 1

## Contacts kept per ore type, nearest first.
##
## Was 2, when the readout drew a labelled marker per contact and more than a
## handful was a wall of overlapping text. The readout is now a directional
## pulse that draws nothing per contact, so the only cost of keeping more is a
## few dot products per frame - and a detector that responds to more of what is
## actually around the player is a better detector.
const MAX_PER_ORE := 12

## Results: [{"material_index": int, "position": Vector3, "distance": float,
## "samples": int}], nearest first.
##
## `origin` is in world space; the returned positions are too.
## `ore_indices` is the set of material indices that count as ore. Required, and
## not optional: without it the scan reports the ground itself. Stone and
## bedrock share the material channel with ore and fill essentially every solid
## voxel, so an unfiltered scan came back with sixty "deposits" of biome stone
## and no ore at all.
static func scan(terrain: VoxelLodTerrain, origin: Vector3,
		ore_indices: Dictionary, lod: int = SCAN_LOD) -> Array:
	if terrain == null or terrain.generator == null or ore_indices.is_empty():
		return []
	var step: int = 1 << lod
	var span: int = GRID * step

	var buffer := VoxelBuffer.new()
	buffer.create(GRID, GRID, GRID)
	# generate_block wants the origin in VOXELS AT LOD 0, and the block is laid
	# out at the given LOD - so the cube covers GRID * 2^LOD metres.
	var corner := origin - terrain.global_position - Vector3.ONE * (span * 0.5)
	var origin_voxels := Vector3i(
		int(floor(corner.x / step)) * step,
		int(floor(corner.y / step)) * step,
		int(floor(corner.z / step)) * step)
	terrain.generator.generate_block(buffer, origin_voxels, lod)

	# Collect hits by material.
	var hits := {}
	for z in GRID:
		for y in GRID:
			for x in GRID:
				var indices: int = buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_INDICES)
				var weights: int = buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_WEIGHTS)
				if weights == 0:
					continue
				# TEXTURES_MIXEL4_S4 packs FOUR material slots into each channel,
				# four bits per slot: index 0..15 and weight 0..15. There is no
				# accessor for the individual slots, so they are unpacked here.
				for slot in 4:
					var w: int = (weights >> (slot * 4)) & 0xF
					if w < MIN_WEIGHT:
						continue
					var idx: int = (indices >> (slot * 4)) & 0xF
					if not ore_indices.has(idx):
						continue
					if not hits.has(idx):
						hits[idx] = []
					hits[idx].append(terrain.global_position + Vector3(
						origin_voxels.x + x * step,
						origin_voxels.y + y * step,
						origin_voxels.z + z * step))

	var out: Array = []
	for idx in hits:
		var found: Array = []
		for centre in _cluster(hits[idx], float(step) * 2.5):
			# One stray sample is a deposit edge clipped by the grid, not a
			# deposit. Requiring two keeps the readout to things worth walking to.
			if centre["samples"] < MIN_SAMPLES:
				continue
			found.append({
				"material_index": idx,
				"position": centre["position"],
				"distance": origin.distance_to(centre["position"]),
				"samples": centre["samples"],
			})
		# Nearest few of EACH ore, rather than everything in range.
		#
		# A 4 km scan finds a lot: the first widened scan returned 112 contacts,
		# which as on-screen markers is a wall of overlapping text that tells the
		# player less than three would. What is actually wanted is "where is the
		# nearest copper" - the rest is noise until the near one is mined out.
		found.sort_custom(func(a, b): return a["distance"] < b["distance"])
		for i in mini(found.size(), MAX_PER_ORE):
			out.append(found[i])
	out.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return out

## Single-linkage clustering: a point joins a cluster if it is within
## CLUSTER_M of ANY member, not of the cluster's centroid.
##
## Centroid-linkage was the bug. As a cluster grows its centroid drifts toward
## the middle, so a sample on the far edge of a large deposit ends up further
## than CLUSTER_M from it even though its neighbour is one grid step away - and
## the deposit comes back shattered into a dozen contacts. Single linkage lets a
## chain of adjacent samples hold together however long the chain gets, which is
## exactly what a deposit spread over many grid cells is.
static func _cluster(points: Array, link_m: float = CLUSTER_M) -> Array:
	var clusters: Array = []
	for p: Vector3 in points:
		var joined := -1
		var i := 0
		while i < clusters.size():
			var members: Array = clusters[i]["points"]
			var near := false
			for m: Vector3 in members:
				if m.distance_to(p) < link_m:
					near = true
					break
			if near:
				if joined < 0:
					members.append(p)
					joined = i
				else:
					# p bridges two clusters that were separate until now, so they
					# are one deposit and have to be merged. Without this a long
					# deposit still fragments, just less often.
					clusters[joined]["points"].append_array(members)
					clusters.remove_at(i)
					continue
			i += 1
		if joined < 0:
			clusters.append({"points": [p]})

	var out: Array = []
	for c in clusters:
		var sum := Vector3.ZERO
		for m: Vector3 in c["points"]:
			sum += m
		out.append({
			"position": sum / float(c["points"].size()),
			"samples": c["points"].size(),
		})
	return out

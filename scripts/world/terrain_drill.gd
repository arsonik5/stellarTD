class_name TerrainDrill
extends RefCounted

## One bite of the mining tool, and what actually came out of the ground.
##
## Space Engineers' hand drill model: hold to bore, the hole grows under the
## crosshair, and what you get is the rock you actually removed. The old dig
## popped a full 1.75 m sphere every tick and paid 1 item for whichever single
## voxel sat under the crosshair - a tick through a mixed seam paid one ore,
## stone paid nothing, and hard and soft rock cut identically.
##
## Positions and radii passed to bite() are the terrain's LOCAL voxel-grid
## units (see player.gd's _local_radius()). Nothing here knows which way is up,
## so it holds on any body at any orientation.

## Bore sphere radius in world metres. Smaller than the old 1.75 m pop so the
## hole reads as drilled rather than stamped out.
const BORE_RADIUS_M := 1.25

## sdf_strength for a hardness-1 material: how far each bite pulls the SDF
## toward "removed". Below 1 the cut takes several ticks to break through.
## Bore speed measured linear in strength at ~23.5 m/s per 1.0 (drill_probe:
## 1.0 -> 23.5 m/s, 0.29 -> 6.3, 0.14 -> 2.9), so 0.065 is ~1.5 m/s in stone.
const BASE_STRENGTH := 0.065
const MIN_STRENGTH := 0.02

## Seconds between bites while held.
const TICK_INTERVAL := 0.05

## How far (as a fraction of the radius) the bite centre sits back from the hit,
## toward the drill. Centred ON the hit, a partial-strength bite breaks through
## at its centre first, the next raycast follows that pinhole, and the drill
## sinks a needle metres deep while removing almost nothing (probe: 11.6 m in
## 3 s for 26 voxels). Backed off, each bite is a shallow dish as wide as the
## bore, so depth can only advance as fast as the whole face comes away.
const BITE_BACKOFF := 0.5

## Where to centre a bite for a raycast hit. `ray_dir_local` is the drill's
## aim in the terrain's local grid space (rotate the world direction by the
## inverse terrain basis - bodies can be rotated).
static func bite_center(hit_position: Vector3i, ray_dir_local: Vector3, radius: float) -> Vector3:
	return Vector3(hit_position) + Vector3(0.5, 0.5, 0.5) - ray_dir_local.normalized() * radius * BITE_BACKOFF

## How far behind the eye a second ray may start when the first finds nothing.
const RAY_RETRY_BACK := 1.5

## Raycast for the drill that also works up close. A ray that starts inside rock (eye pressed into a wall, or
## the camera dipping under the surface on a bob) or hugs it can report nothing, so the drill "did not work" at close
## range. Retry from behind the eye, along the same line, which always starts in open air in front of the face.
## `range_m` is world metres (see player.gd's _raycast()).
static func raycast_close(tool: VoxelTool, from: Vector3, dir: Vector3, range_m: float) -> VoxelRaycastResult:
	var hit := tool.raycast(from, dir, range_m, 0xFFFFFFFF)
	if hit != null:
		return hit
	return tool.raycast(from - dir * RAY_RETRY_BACK, dir, range_m + RAY_RETRY_BACK, 0xFFFFFFFF)

const ITEM_BY_MATERIAL := {
	VoxelMaterials.STONE: "stone",
	VoxelMaterials.STONE_FROZEN: "stone",
	VoxelMaterials.STONE_SULFUR_FLATS: "stone",
	VoxelMaterials.STONE_CRYSTAL_FIELDS: "stone",
	VoxelMaterials.CLIFF_ROCK: "stone",
	VoxelMaterials.BEDROCK: "stone",
	VoxelMaterials.IRON_ORE: "ore_a",
	VoxelMaterials.COPPER_ORE: "ore_b",
	VoxelMaterials.SULFUR_ORE: "sulfur",
	VoxelMaterials.COAL_ORE: "ore_coal",
	VoxelMaterials.SILICA_ORE: "ore_silica",
	VoxelMaterials.CRYSTAL_ORE: "ore_crystal",
}

## Items paid per cubic metre removed. Stone pays less than ore so a tunnel
## doesn't bury the ore under stacks of rubble. The bore clears ~3 m2 of face,
## so iron (hardness 1.5, ~1 m/s) pays ~6 ore/s - near the old dig's flat 8.3/s.
const ITEMS_PER_M3 := {"stone": 0.25}
const ORE_ITEMS_PER_M3 := 2.0

static func strength_for(material_index: int) -> float:
	return clampf(BASE_STRENGTH / VoxelMaterials.hardness_for(material_index), MIN_STRENGTH, 1.0)

## Carves one bite and returns {material_index: solid voxels removed}.
##
## Removed volume is measured, not assumed: each cell's solid fraction is read
## before and after the cut. A partial-strength bite that hasn't broken through
## yet correctly removes nothing.
##
## Reads go through two bulk copy() calls rather than per-voxel get_voxel_f():
## each tool read on VoxelLodTerrain takes its own lock, and ~700 of them per
## bite measured 3-19 ms - a visible hitch at 20 bites a second.
static func bite(tool: VoxelTool, center: Vector3, radius: float, strength: float) -> Dictionary:
	var reach := radius + 1.0
	var lo := Vector3i((center - Vector3.ONE * reach).floor())
	var hi := Vector3i((center + Vector3.ONE * reach).ceil())
	var size := hi - lo + Vector3i.ONE

	var before := _buffer(size)
	tool.copy(lo, before, READ_MASK, false)

	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	tool.set_mode(VoxelTool.MODE_REMOVE)
	tool.set_sdf_strength(strength)
	tool.do_sphere(center, radius)
	tool.set_sdf_strength(1.0)

	var after := _buffer(size)
	tool.copy(lo, after, 1 << VoxelBuffer.CHANNEL_SDF, false)

	var removed := {}
	for x in size.x:
		for y in size.y:
			for z in size.z:
				var s := _solid(before.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF))
				if s <= 0.0:
					continue
				var d := s - _solid(after.get_voxel_f(x, y, z, VoxelBuffer.CHANNEL_SDF))
				if d <= 0.0001:
					continue
				var m := dominant_from_packed(
					before.get_voxel(x, y, z, VoxelBuffer.CHANNEL_INDICES),
					before.get_voxel(x, y, z, VoxelBuffer.CHANNEL_WEIGHTS))
				removed[m] = removed.get(m, 0.0) + d
	return removed

const READ_MASK := (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES) | (1 << VoxelBuffer.CHANNEL_WEIGHTS)

## Indices and weights are packed 16-bit words (see dominant_from_packed), so
## the buffer must not truncate them to a narrower default depth.
static func _buffer(size: Vector3i) -> VoxelBuffer:
	var b := VoxelBuffer.new()
	b.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_16_BIT)
	b.set_channel_depth(VoxelBuffer.CHANNEL_WEIGHTS, VoxelBuffer.DEPTH_16_BIT)
	b.create(size.x, size.y, size.z)
	return b

## Turns removed volume into whole items, keeping fractions in `carry`
## ({item_id: float}) so small bites still add up.
static func payout(carry: Dictionary, removed: Dictionary, voxel_volume_m3: float) -> Dictionary:
	var out := {}
	for m: int in removed:
		var item_id: String = ITEM_BY_MATERIAL.get(m, "")
		if item_id == "":
			continue
		var rate: float = ITEMS_PER_M3.get(item_id, ORE_ITEMS_PER_M3)
		var total: float = carry.get(item_id, 0.0) + removed[m] * voxel_volume_m3 * rate
		var whole := int(floor(total))
		carry[item_id] = total - whole
		if whole > 0:
			out[item_id] = whole
	return out

## Under TEXTURES_MIXEL4_S4 the indices channel holds FOUR 4-bit material
## indices packed into one 16-bit word, with matching 4-bit weights in the
## weights channel - a raw read of either is a packed word, not a material.
## (Reading the channel directly, as the dig did under TEXTURES_SINGLE_S4,
## returns the packed word and silently matches no ore at all.)
static func dominant_material_at(tool: VoxelTool, pos: Vector3i) -> int:
	tool.set_channel(VoxelBuffer.CHANNEL_INDICES)
	var packed_indices: int = tool.get_voxel(pos)
	tool.set_channel(VoxelBuffer.CHANNEL_WEIGHTS)
	var packed_weights: int = tool.get_voxel(pos)
	return dominant_from_packed(packed_indices, packed_weights)

static func dominant_from_packed(packed_indices: int, packed_weights: int) -> int:
	var best_index: int = packed_indices & 0xf
	var best_weight: int = packed_weights & 0xf
	for slot in range(1, 4):
		var shift: int = slot * 4
		var w: int = (packed_weights >> shift) & 0xf
		if w > best_weight:
			best_weight = w
			best_index = (packed_indices >> shift) & 0xf
	return best_index

## SDF is negative inside rock; a cell counts as fully solid half a voxel in.
static func _solid(sdf: float) -> float:
	return clampf(0.5 - sdf, 0.0, 1.0)

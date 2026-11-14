class_name Mining2D
extends RefCounted

## Hand mining on the tile grid (pivot-2d.md C2): hold on a tile until it cracks; it pays stone (+ ore while the
## deposit lasts) and drops one level - holes stay dug. A freshly dug tile is loose rubble (a ramp), so a shallow
## pit can be walked out of while a shaft deeper than one level is a real hole. Cliff faces can be cut back the
## same way. Hardness follows the 3D drill's material table (VoxelMaterials.hardness_for).

const REACH := 2.6                 ## tiles from the player's tile centre
const BASE_SECONDS := 0.7          ## time to break plain stone (hardness 1.0)
const STONE_PER_DIG := 2
const ORE_PER_DIG := 4             ## items per dig while the tile's ore lasts (ore_amount counts down by this)

const ORE_MATERIAL := [VoxelMaterials.STONE, VoxelMaterials.IRON_ORE, VoxelMaterials.COPPER_ORE,
	VoxelMaterials.COAL_ORE, VoxelMaterials.SILICA_ORE, VoxelMaterials.SULFUR_ORE, VoxelMaterials.CRYSTAL_ORE]

static func ground_hardness(g: WorldGrid, x: int, y: int) -> float:
	var h := VoxelMaterials.hardness_for(ORE_MATERIAL[g.ore_at(x, y)])
	if int(g.ground[g.idx(x, y)]) == WorldGrid.Ground.BASALT:
		h *= 1.4
	elif int(g.ground[g.idx(x, y)]) == WorldGrid.Ground.SAND:
		h *= 0.6
	return h

static func seconds_for(g: WorldGrid, x: int, y: int) -> float:
	return BASE_SECONDS * ground_hardness(g, x, y)

## Why a tile cannot be dug from where the player stands, "" if it can.
static func refuse_reason(g: WorldGrid, from: Vector2i, from_level: int, t: Vector2i) -> String:
	if not g.in_bounds(t.x, t.y):
		return "Edge of the map"
	if t == from:
		return "Standing on it"
	if Vector2(t - from).length() > REACH:
		return "Out of reach"
	var lv := g.level_at(t.x, t.y)
	if lv <= WorldGrid.MIN_LEVEL:
		return "Bedrock"
	if lv < from_level - 1:
		return "Too far down"
	if (g.flags[g.idx(t.x, t.y)] & WorldGrid.F_FLOOR) != 0:
		return "Built floor"
	return ""

## Breaks the tile: lowers it one level, pays items. Returns {item_id: count}.
static func dig(g: WorldGrid, x: int, y: int) -> Dictionary:
	var i := g.idx(x, y)
	var paid := {"stone": STONE_PER_DIG}
	var o := int(g.ore[i])
	if o > 0:
		var take := mini(ORE_PER_DIG, int(g.ore_amount[i]))
		paid[WorldGrid.ORE_ITEMS[o]] = take
		var left := int(g.ore_amount[i]) - take
		g.ore_amount[i] = left
		if left <= 0:
			g.ore[i] = 0
	g.set_level(x, y, g.level_at(x, y) - 1)
	g.flags[i] |= WorldGrid.F_RAMP          # loose rubble: one-level steps out of it are walkable
	g.tile_changed.emit(x, y)
	return paid

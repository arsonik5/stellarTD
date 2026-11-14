class_name WorldGrid
extends RefCounted

## Tile data for one flat 2D world (docs/game/design/pivot-2d.md section 4). Tiles are DATA, never nodes: one packed
## array per layer for the whole map, read by the renderer, movement, the build grid and (later) pathing.
##
## Elevation: levels MIN_LEVEL..MAX_LEVEL (-4..+20), stored as level + LEVEL_OFFSET in a byte.
## Moving between neighbouring tiles is allowed when the levels match, or differ by one and either tile is a RAMP.

const TILE_PX := 32            ## pixels per tile at 1x zoom (1 tile = 1 m)
const LEVEL_PX := 16           ## legacy 3/4 shift used by the P0.2 spike renderer only
const LEVEL_HEIGHT := 6.0      ## px of real height per level, for the perspective lean (WorldMapView)
const CHUNK := 64              ## tiles per chunk side
const MIN_LEVEL := -4
const MAX_LEVEL := 20
const LEVEL_OFFSET := 4

enum Ground { REGOLITH, GRAVEL, SAND, BASALT, ICE }

## flags bits
const F_RAMP := 1
const F_FLOOR := 2             ## a built floor tile
const F_EXPLORED := 4

## ore index -> item id paid when mined (0 = no ore). Matches the 3D drill's item table (terrain_drill.gd).
const ORE_ITEMS := ["", "ore_a", "ore_b", "ore_coal", "ore_silica", "sulfur", "ore_crystal"]
const ORE_IDS := ["", "iron", "copper", "coal", "silica", "sulfur", "crystal"]

var width := 0
var height := 0
var seed_value := 0
var elevation := PackedByteArray()   ## level + LEVEL_OFFSET
var ground := PackedByteArray()      ## Ground
var ore := PackedByteArray()         ## index into ORE_ITEMS
var ore_amount := PackedByteArray()  ## 0..255 units left (one unit = one item from a hand bite)
var flags := PackedByteArray()

signal tile_changed(x: int, y: int)

func _init(w: int = 1024, h: int = 1024) -> void:
	width = w
	height = h
	for a: PackedByteArray in [elevation, ground, ore, ore_amount, flags]:
		a.resize(w * h)
	elevation.fill(LEVEL_OFFSET)

func idx(x: int, y: int) -> int:
	return y * width + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

## Elevation level at a tile (MIN_LEVEL off the map, so the edge reads as a drop).
func level_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return MIN_LEVEL
	return int(elevation[y * width + x]) - LEVEL_OFFSET

func set_level(x: int, y: int, level: int) -> void:
	elevation[y * width + x] = clampi(level, MIN_LEVEL, MAX_LEVEL) + LEVEL_OFFSET

func is_ramp(x: int, y: int) -> bool:
	return in_bounds(x, y) and (flags[y * width + x] & F_RAMP) != 0

func ore_at(x: int, y: int) -> int:
	return int(ore[y * width + x]) if in_bounds(x, y) else 0

## Can something walking step from tile a to its neighbour b?
func can_step(ax: int, ay: int, bx: int, by: int) -> bool:
	if not in_bounds(bx, by):
		return false
	var d := level_at(bx, by) - level_at(ax, ay)
	if d == 0:
		return true
	return absi(d) == 1 and (is_ramp(ax, ay) or is_ramp(bx, by))

func chunks_x() -> int:
	return int(ceil(float(width) / CHUNK))

func chunks_y() -> int:
	return int(ceil(float(height) / CHUNK))

func tile_of(world_px: Vector2) -> Vector2i:
	return Vector2i(floori(world_px.x / TILE_PX), floori(world_px.y / TILE_PX))

## P0.2 spike generator, kept so the spike scene still runs. The game uses WorldGen.generate().
func generate(seed_in: int) -> void:
	WorldGen.generate(self, seed_in)

## Stable hash of the tile data (determinism test: same seed -> same map).
func data_hash() -> int:
	return hash([elevation, ground, ore, ore_amount, flags])

## --- save (world format v2): the whole grid, compressed. A 1024^2 map is ~5 MB raw, well under 1 MB packed.
func to_bytes() -> PackedByteArray:
	var raw := PackedByteArray()
	for a: PackedByteArray in [elevation, ground, ore, ore_amount, flags]:
		raw.append_array(a)
	return raw.compress(FileAccess.COMPRESSION_ZSTD)

func from_bytes(data: PackedByteArray) -> void:
	var n := width * height
	var raw := data.decompress(n * 5, FileAccess.COMPRESSION_ZSTD)
	elevation = raw.slice(0, n)
	ground = raw.slice(n, n * 2)
	ore = raw.slice(n * 2, n * 3)
	ore_amount = raw.slice(n * 3, n * 4)
	flags = raw.slice(n * 4, n * 5)

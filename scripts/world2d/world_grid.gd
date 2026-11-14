class_name WorldGrid
extends RefCounted

## Tile data for one flat 2D world (docs/game/design/pivot-2d.md section 4). Tiles are DATA, never nodes: one byte
## array per layer for the whole map, read by the chunk renderer, the build grid and (later) pathing.
##
## Elevation is stored as level + LEVEL_OFFSET so it fits a byte: levels MIN_LEVEL..MAX_LEVEL (-3..+5).

const TILE_PX := 32            ## pixels per tile at 1x zoom (1 tile = 1 m)
const LEVEL_PX := 16           ## how far one elevation level shifts a tile up on screen (the 2.5D trick)
const CHUNK := 64              ## tiles per chunk side
const MIN_LEVEL := -3
const MAX_LEVEL := 5
const LEVEL_OFFSET := 3

## Ground types (P0 spike set; the real list comes from trait ground rules in P1).
enum Ground { REGOLITH, GRAVEL, SAND, BASALT, ICE }

var width := 0
var height := 0
var seed_value := 0
var elevation := PackedByteArray()   ## level + LEVEL_OFFSET per tile, row-major
var ground := PackedByteArray()      ## Ground per tile

func _init(w: int = 1024, h: int = 1024) -> void:
	width = w
	height = h
	elevation.resize(w * h)
	ground.resize(w * h)

func idx(x: int, y: int) -> int:
	return y * width + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

## Elevation level at a tile (MIN_LEVEL for out of bounds, so the map edge reads as a drop).
func level_at(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return MIN_LEVEL
	return int(elevation[y * width + x]) - LEVEL_OFFSET

func set_level(x: int, y: int, level: int) -> void:
	elevation[y * width + x] = clampi(level, MIN_LEVEL, MAX_LEVEL) + LEVEL_OFFSET

func chunks_x() -> int:
	return int(ceil(float(width) / CHUNK))

func chunks_y() -> int:
	return int(ceil(float(height) / CHUNK))

## Spike generator: a noise heightfield quantised into levels, so wide flats are separated by cliffs. The noise
## runs in C++ (Image from FastNoiseLite), so a 1024^2 map takes well under a second. The real generator (traits,
## landforms, erosion, ore, scatter) replaces this in P1.
func generate(seed_in: int) -> void:
	seed_value = seed_in
	var n := FastNoiseLite.new()
	n.seed = seed_in
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.004
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	var img := n.get_image(width, height, false, false, true)
	var hdata := img.get_data()            # L8, one byte per pixel, 0..255
	var g := FastNoiseLite.new()
	g.seed = seed_in + 17
	g.frequency = 0.012
	var gdata := g.get_image(width, height, false, false, true).get_data()
	var levels := MAX_LEVEL - MIN_LEVEL + 1
	for i in width * height:
		var v := float(hdata[i]) / 255.0
		elevation[i] = clampi(int(v * levels), 0, levels - 1)
		var gv := int(gdata[i])
		ground[i] = Ground.GRAVEL if gv < 70 else (Ground.SAND if gv > 190 else Ground.REGOLITH)
	# the highest ground is basalt, the lowest pits ice: enough variety to judge reading at a glance
	for i in width * height:
		var lv := int(elevation[i]) - LEVEL_OFFSET
		if lv >= 4:
			ground[i] = Ground.BASALT
		elif lv <= -2:
			ground[i] = Ground.ICE

## Stable hash of the tile data (determinism test: same seed -> same map).
func data_hash() -> int:
	return hash(elevation) ^ (hash(ground) << 1)

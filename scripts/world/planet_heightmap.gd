class_name PlanetHeightmap
extends Resource

## A baked, eroded elevation map for one body. Produced offline by
## `tools/bake_planet_heightmap.py`; see main-design.md Phase 1.
##
## This exists because hydraulic erosion is iterative and non-local - a
## drainage network only emerges after tens of thousands of droplets have run
## across the whole map, which cannot be evaluated per-block on demand. It is
## also what Space Engineers 2 does: VRAGE3 is heightmap-first with 3D voxel
## detail layered on top, not noise-first.
##
## Projection is EQUIRECTANGULAR, matching godot_voxel's `SdfSphereHeightmap`
## node (one Image for the whole sphere, params image/radius/factor). The
## convention here must stay identical to the baker's:
##     lon = (x + 0.5) / w * 2pi - pi     dir = (cos(lat)cos(lon), sin(lat), cos(lat)sin(lon))
##     lat = pi/2 - (y + 0.5) / h * pi

## The baked map. Height is encoded across R (high byte) and G (low byte)
## because **Godot loads 16-bit greyscale PNGs as FORMAT_L8**, collapsing a
## planet's elevation range to 256 steps. Splitting the value across two
## channels keeps all 16 bits through the normal RGBA8 load path.
@export var image: Texture2D

## Peak-to-trough elevation range in world metres. The map itself is 0..1.
@export_range(0.0, 20000.0, 0.5) var relief_meters: float = 60.0

## Fraction of `relief_meters` that sits below the body's nominal radius.
## 0.5 centres the terrain on the sphere; lower values make the planet read as
## mostly highland, higher as mostly basin.
@export_range(0.0, 1.0, 0.01) var sea_level: float = 0.45

## Heights decoded ONCE into a flat float array. Two reasons this is not done
## lazily from an Image:
##
## 1. `Image.get_pixel()` is an Object call returning a Color. At four texels
##    per bilinear sample and one sample per voxel, that dominated generation
##    entirely - time to first walkable ground went from ~10 s to 66 s.
## 2. godot_voxel calls the generator from several worker threads at once.
##    Lazily populating a cache during generation is a data race on shared
##    mutable state, which this project has already had segfault the engine
##    (see the note in ore_generator.gd). `prepare()` must be called once,
##    single-threaded, before any generation starts.
var _heights := PackedFloat32Array()
var _w := 0
var _h := 0
var _ready := false

## Decode the map into a flat float array. Call once, from the main thread,
## before handing this to a generator.
func prepare() -> bool:
	if _ready:
		return true
	if image == null:
		return false
	var img: Image = image.get_image()
	if img == null:
		return false
	if img.is_compressed():
		img.decompress()
	_w = img.get_width()
	_h = img.get_height()
	if _w <= 0 or _h <= 0:
		return false
	_heights.resize(_w * _h)
	for y in _h:
		var row := y * _w
		for x in _w:
			var c := img.get_pixel(x, y)
			# R = high byte, G = low byte (see the baker; Godot loads 16-bit
			# greyscale PNGs as L8, so the value is split across channels).
			_heights[row + x] = (c.r * 255.0 * 256.0 + c.g * 255.0) / 65535.0
	_ready = true
	return true

## Normalized height (0..1) along a unit direction, bilinearly filtered.
## Longitude wraps; latitude clamps.
func sample(dir: Vector3) -> float:
	if not _ready:
		return 0.5
	var lon := atan2(dir.z, dir.x)
	var lat := asin(clampf(dir.y, -1.0, 1.0))
	var u := (lon + PI) / (TAU) * float(_w) - 0.5
	var v := (0.5 - lat / PI) * float(_h) - 0.5

	var x0 := int(floor(u))
	var y0 := int(floor(v))
	var fx := u - float(x0)
	var fy := v - float(y0)
	var x1 := x0 + 1
	var y1 := y0 + 1

	var c00 := _texel(x0, y0)
	var c10 := _texel(x1, y0)
	var c01 := _texel(x0, y1)
	var c11 := _texel(x1, y1)
	return lerp(lerp(c00, c10, fx), lerp(c01, c11, fx), fy)

func _texel(x: int, y: int) -> float:
	# Longitude wraps around the planet; latitude does not.
	return _heights[clampi(y, 0, _h - 1) * _w + posmod(x, _w)]

## Elevation offset in world metres to add to a body's nominal radius.
func elevation(dir: Vector3) -> float:
	return (sample(dir) - sea_level) * relief_meters

## Largest possible deviation from nominal radius, in world metres. Callers
## that need the terrain band (spawn probes, shell bounds) must use this
## rather than assuming the surface sits at the nominal radius.
func max_deviation() -> float:
	return relief_meters * maxf(sea_level, 1.0 - sea_level)

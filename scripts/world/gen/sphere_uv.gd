class_name SphereUV
extends RefCounted

## The ONE projection between a direction on the planet and a pixel of its planet-wide maps (height, erosion masks,
## crater masks): the one godot_voxel's SdfSphereHeightmap node uses, because that node is how the terrain and every
## mask are read per voxel (generators/graph/nodes/image.h):
##     u = 0.5 - atan2(z, x) / TAU
##     v = 0.5 - 0.5 * skew3(y),  skew3(y) = (y^3 + y) / 2      (a cubic stand-in for asin(y) / (PI/2))
## sampled bilinear at pixel CORNERS (u * width, no half-texel offset), wrapping on both axes.
##
## Found 2026-11-09: the bake wrote plain equirectangular maps (lon = +atan2, lat = asin, pixel centres), so in game
## every map was mirrored east-west and stretched ~27% north-south at the equator (4/PI), squeezed toward the poles.
## Now the bake works in equirectangular (its erosion assumes it) and ErosionBaker reprojects the results into this
## projection at the end; anything reading a map by direction (shader, spawn search, tools) goes through here.
## GLSL copies: shaders/erosion/reproject.glsl, voxel_terrain_material.gdshader (keep all three identical).

static func skew3(y: float) -> float:
	return (y * y * y + y) * 0.5

## Direction (any length) -> uv in 0..1.
static func uv_of(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	return Vector2(0.5 - atan2(d.z, d.x) / TAU, 0.5 - 0.5 * skew3(d.y))

## uv -> unit direction (inverse: the real root of y^3 + y = 2s, by Cardano).
static func dir_of(uv: Vector2) -> Vector3:
	var lon := (0.5 - uv.x) * TAU
	var s := (0.5 - uv.y) * 2.0                                   # = skew3(y)
	var q := sqrt(s * s + 1.0 / 27.0)
	var y := clampf(_cbrt(s + q) + _cbrt(s - q), -1.0, 1.0)
	var c := sqrt(maxf(1.0 - y * y, 0.0))
	return Vector3(c * cos(lon), y, c * sin(lon))

## Pixel (corner convention, as the node samples) of an image w x h -> direction.
static func dir_of_pixel(x: float, y: float, w: int, h: int) -> Vector3:
	return dir_of(Vector2(x / float(w), y / float(h)))

static func _cbrt(v: float) -> float:
	return signf(v) * pow(absf(v), 1.0 / 3.0)

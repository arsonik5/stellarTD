class_name CraterField
extends RefCounted

## The planet's impact craters, from its seed: a list baked into the base heightmap BEFORE erosion (ErosionBaker ->
## shaders/erosion/craters.glsl), so the same water and talus passes that shape everything else then weather them:
## walls slump into scree aprons, floors fill with fines, old rims round off. Stage 4b of
## reports/AAA voxel terrain fidelity.md ("craters read from orbit").
##
## Sizes follow a power law (cumulative N(>D) ~ D^-2, the lunar production function's slope over this range), so
## there are few big craters and many small ones. Shapes follow measured morphometry (Pike 1977, Melosh):
##   simple   D < D_t   parabolic bowl, depth 0.2 D, rim 0.04 D, ejecta thickness falling as (r/R)^-3
##   complex  D >= D_t  shallower (depth ~ D^0.3), flat floor, slumped terraced walls
##   peak     D > 1.6 D_t  complex plus a central peak cluster
## Age degrades all of it: rims drop, floors fill. Only young craters keep a bright ejecta blanket and rays, which
## space weathering erases (Moon: ~1 Gyr), so they are a minority.
##
## The graph generator's cellular craters (PlanetGraphGenerator.CRATER_SIZES) stay for the sizes below the
## heightmap's resolution; this list starts at D_MIN_TEXELS texels.

## Floats per crater, as three vec4: (dir.xyz, radius m), (depth m, rim m, age 0..1, kind), (east.xyz, ray seed).
const STRIDE := 12
const D_MIN_TEXELS := 8.0
const MAX_CRATERS := 3000
## Craters wider than 1 km per km2 on a saturated, airless, never-resurfaced body (lunar highlands ~0.1; this is
## below saturation so ground between craters stays readable).
const PER_KM2_OVER_1KM := 0.03
const SIZE_EXPONENT := 2.0
## Largest crater as a share of the body radius (bigger would be a basin that reshapes the whole body).
const MAX_D_FRAC := 0.35
## Simple-to-complex transition diameter as a share of body radius, clamped to metres. Real D_t scales with 1/g;
## this keeps a few complex craters on every body big enough to hold them.
const DT_FRAC := 0.1
const DT_MIN_M := 800.0
const DT_MAX_M := 15000.0
## Share of craters young enough to keep rays (age < YOUNG_AGE).
const YOUNG_AGE := 0.12

## -> {"data": PackedFloat32Array (STRIDE per crater), "count": int, "key": int (hash of the list, for the cache),
##     "d_min_m", "d_max_m", "complex": int}
static func build(body: CelestialBody, radius_m: float, metres_per_texel: float) -> Dictionary:
	var land := TraitMixer.landform(body)
	var density: float = land.craters
	var out := {"data": PackedFloat32Array(), "count": 0, "key": 0, "d_min_m": 0.0, "d_max_m": 0.0, "complex": 0,
		"ray_strength": 0.0}
	if density <= 0.0 or radius_m <= 0.0:
		return out
	var area_km2 := 4.0 * PI * pow(radius_m / 1000.0, 2.0)
	var n_1km := PER_KM2_OVER_1KM * density * area_km2
	var d_min := maxf(D_MIN_TEXELS * metres_per_texel, 40.0)
	var d_max := MAX_D_FRAC * radius_m
	if d_min >= d_max:
		return out
	# count above d_min, capped by raising d_min (the smallest are the cheapest to lose: the graph has its own)
	var n := n_1km * pow(1000.0 / d_min, SIZE_EXPONENT)
	if n > MAX_CRATERS:
		d_min = 1000.0 * pow(n_1km / MAX_CRATERS, 1.0 / SIZE_EXPONENT)
		n = MAX_CRATERS
	var count := int(round(n))
	if count <= 0:
		return out
	var d_t := clampf(DT_FRAC * radius_m * 2.0, DT_MIN_M, DT_MAX_M)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([body.seed, "craters"])
	var data := PackedFloat32Array()
	data.resize(count * STRIDE)
	var lo := pow(d_min, -SIZE_EXPONENT)
	var hi := pow(d_max, -SIZE_EXPONENT)
	var n_complex := 0
	var biggest := 0.0
	for i in count:
		# uniform direction on the sphere
		var zc := rng.randf_range(-1.0, 1.0)
		var phi := rng.randf() * TAU
		var s := sqrt(1.0 - zc * zc)
		var dir := Vector3(s * cos(phi), zc, s * sin(phi))
		# inverse CDF of the truncated power law
		var d := pow(lerpf(lo, hi, rng.randf()), -1.0 / SIZE_EXPONENT)
		var r := d * 0.5
		biggest = maxf(biggest, d)
		var age := rng.randf()
		var depth: float
		var rim: float
		var kind := 0.0
		if d < d_t:
			depth = 0.2 * d
			rim = 0.04 * d
		else:
			depth = 0.2 * d_t * pow(d / d_t, 0.3)
			rim = minf(0.03 * d, depth * 0.5)
			kind = 2.0 if d > 1.6 * d_t else 1.0
			n_complex += 1
		# degradation: rims erode faster than floors fill
		depth *= 1.0 - 0.55 * age
		rim *= 1.0 - 0.75 * age
		var east := Vector3.UP.cross(dir)
		if east.length() < 1e-4:
			east = Vector3.RIGHT
		east = east.normalized()
		var o := i * STRIDE
		data[o + 0] = dir.x; data[o + 1] = dir.y; data[o + 2] = dir.z; data[o + 3] = r
		data[o + 4] = depth; data[o + 5] = rim; data[o + 6] = age; data[o + 7] = kind
		data[o + 8] = east.x; data[o + 9] = east.y; data[o + 10] = east.z; data[o + 11] = rng.randf() * 1000.0
	out.data = data
	out.count = count
	out.key = hash([body.seed, count, snappedf(density, 0.001), snappedf(d_min, 0.1), snappedf(land.rays, 0.001)])
	out.d_min_m = d_min
	out.d_max_m = biggest
	out.complex = n_complex
	out.ray_strength = land.rays
	return out

## How far a crater's influence reaches, in crater radii: the ejecta taper ends at 3 R; a young crater's rays reach
## up to 3 + 9 * ray strength. Must match craters.glsl.
static func reach_radii(age: float, ray_strength: float) -> float:
	if age < YOUNG_AGE and ray_strength > 0.0:
		return 3.0 + 9.0 * ray_strength
	return 3.0

## Equirectangular tile lists: for each tile of `tile_px` pixels, the craters whose reach overlaps it. A pixel then
## loops only its tile's list. -> {"start": PackedInt32Array (tiles + 1), "list": PackedInt32Array, "tiles_x": int}
static func bin_tiles(field: Dictionary, width: int, height: int, radius_m: float, tile_px: int) -> Dictionary:
	var tx := int(ceil(float(width) / tile_px))
	var ty := int(ceil(float(height) / tile_px))
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(tx * ty)
	var data: PackedFloat32Array = field.data
	var rays: float = field.get("ray_strength", 0.0)
	for i in int(field.count):
		var o := i * STRIDE
		var dir := Vector3(data[o], data[o + 1], data[o + 2])
		var reach := data[o + 3] * reach_radii(data[o + 6], rays)
		var a := minf(reach / radius_m, PI)                       # angular radius
		var lat := asin(clampf(dir.y, -1.0, 1.0))
		var lon := atan2(dir.z, dir.x)
		var lat0 := lat - a
		var lat1 := lat + a
		# pixel rows: y = (pi/2 - lat) / pi * h
		var y0 := clampi(int(floor((PI * 0.5 - lat1) / PI * height)), 0, height - 1)
		var y1 := clampi(int(floor((PI * 0.5 - lat0) / PI * height)), 0, height - 1)
		var full_lon := lat1 >= PI * 0.5 or lat0 <= -PI * 0.5
		var dlon := PI
		if not full_lon:
			var c := cos(maxf(absf(lat0), absf(lat1)))
			if sin(a) < c:
				dlon = asin(sin(a) / c)
			else:
				full_lon = true
		var x0: int
		var x1: int
		if full_lon:
			x0 = 0
			x1 = width - 1
		else:
			x0 = int(floor((lon - dlon + PI) / TAU * width))
			x1 = int(floor((lon + dlon + PI) / TAU * width))
		for ty_i in range(y0 / tile_px, y1 / tile_px + 1):
			var seen := {}
			for xx in range(int(floor(float(x0) / tile_px)), int(floor(float(x1) / tile_px)) + 1):
				var tcol := posmod(xx, tx)
				if seen.has(tcol):
					continue
				seen[tcol] = true
				buckets[ty_i * tx + tcol].append(i)
	var start := PackedInt32Array()
	start.resize(tx * ty + 1)
	var list := PackedInt32Array()
	var acc := 0
	for t in tx * ty:
		start[t] = acc
		list.append_array(buckets[t])
		acc += buckets[t].size()
	start[tx * ty] = acc
	if list.is_empty():
		list.append(0)          # a storage buffer cannot be empty
	return {"start": start, "list": list, "tiles_x": tx}

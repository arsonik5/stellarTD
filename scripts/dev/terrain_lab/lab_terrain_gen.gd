extends VoxelGeneratorScript

## Terrain lab, shape prototypes: one 192 m patch per planet archetype, each built from a "recipe" of geological
## processes rather than from one more noise band. Materials follow rules a geologist would accept: a loose top layer
## (dust, sand, snow) over bedrock, rock showing where the slope is too steep to hold loose material, and whatever a
## cut exposes coming from the layer at that depth.
##   moon     airless, old: rolling regolith + craters (bowl, raised rim), basalt on steep walls
##   desert   wind: dune ridges across one wind direction, mesas from hard rock layers (benches), dry crust flats
##   ice      glacier sheet cut by crevasses, fields of penitentes (ice spikes), clear ice on steep faces
##   volcanic cones and lava plains, dark ash on flats, fissures
##   mountain eroded ridges, scree (gravel) on mid slopes, cliffs of bare rock, a cave mouth
## Material indices refer to terrain_lab.gd SETS.

const SIZE := 192.0

var biome := "moon"
var _n := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _cell := FastNoiseLite.new()
var _cave := FastNoiseLite.new()

func _init() -> void:
	_n.seed = 11
	_n.frequency = 0.012
	_n.fractal_octaves = 4
	_n2.seed = 23
	_n2.frequency = 0.03
	_n2.fractal_octaves = 3
	_cell.seed = 5
	_cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	_cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_cell.frequency = 0.5
	_cave.seed = 31
	_cave.frequency = 0.045
	_cave.fractal_octaves = 2

func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES) | (1 << VoxelBuffer.CHANNEL_WEIGHTS)

# --- landform recipes -------------------------------------------------------------------------------------------

## A crater: bowl below the surroundings, a raised rim, flat-ish floor. r = radius in metres.
static func _crater(d: float, r: float) -> float:
	var t := d / r
	if t > 2.2:
		return 0.0
	var bowl := -0.32 * r * (1.0 - t * t) if t < 1.0 else 0.0
	var rim := 0.08 * r * exp(-pow((t - 1.0) * 3.2, 2.0))
	return maxf(bowl, -0.22 * r) + rim

func _height(x: float, z: float) -> float:
	match biome:
		"moon":
			var h := 3.0 * _n.get_noise_2d(x, z) + 0.6 * _n2.get_noise_2d(x, z)
			for c in [[60.0, 70.0, 26.0], [130.0, 120.0, 14.0], [150.0, 40.0, 8.0], [40.0, 150.0, 10.0], [100.0, 165.0, 5.0], [85.0, 30.0, 4.0]]:
				h += _crater(Vector2(x - c[0], z - c[1]).length(), c[2])
			return h
		"desert":
			# dunes: ridges across the wind (+x), asymmetric (gentle windward, steep lee), warped so they meander
			var w := x + 18.0 * _n.get_noise_2d(x * 0.6, z * 0.6)
			var ph := fposmod(w / 22.0, 1.0)
			var dune := (ph / 0.8) if ph < 0.8 else (1.0 - (ph - 0.8) / 0.2)
			var amp := 3.5 * (0.6 + 0.4 * _n2.get_noise_2d(x, z))
			var h := dune * amp
			# a mesa: hard caprock disc with two benches
			var md := Vector2(x - 135.0, z - 120.0).length() + 8.0 * _n2.get_noise_2d(x * 2.0, z * 2.0)
			var mesa := 0.0
			if md < 34.0:
				mesa = 18.0
			elif md < 40.0:
				mesa = 11.0
			elif md < 48.0:
				mesa = 11.0 * (1.0 - (md - 40.0) / 8.0)
			if md < 36.0 and md >= 34.0:
				mesa = lerpf(18.0, 11.0, (md - 34.0) / 2.0)
			return maxf(h, mesa + 0.5 * _n2.get_noise_2d(x * 3.0, z * 3.0))
		"ice":
			var h := 4.0 * _n.get_noise_2d(x, z)
			# penitentes: a field of sharp cones, only in one part of the sheet
			var field := smoothstep(0.0, 0.25, _n2.get_noise_2d(x * 0.5 + 40.0, z * 0.5))
			var cell := _cell.get_noise_2d(x, z)            # distance to the nearest feature point, ~0..1
			h += field * maxf(0.0, 2.6 * (1.0 - cell * 1.6))
			return h
		"volcanic":
			var h := 1.2 * _n.get_noise_2d(x, z)
			for c in [[70.0, 80.0, 40.0, 16.0], [150.0, 140.0, 22.0, 9.0]]:
				var d := Vector2(x - c[0], z - c[1]).length()
				var cone: float = c[3] * maxf(0.0, 1.0 - d / c[2])
				var vent: float = -c[3] * 0.45 * maxf(0.0, 1.0 - d / (c[2] * 0.18))
				h += cone + vent
			return h
		"mountain":
			var r := 1.0 - absf(_n.get_noise_2d(x * 0.8, z * 0.8))
			var h := 26.0 * r * r * r + 4.0 * _n2.get_noise_2d(x, z)
			return h - 8.0
	return 0.0

## Carving as a proper signed distance (positive = air), combined with max(): crevasses and fissures are slots of a
## given width and depth around the zero lines of a stretched noise; the cave is a tube where 3D noise is near zero.
## Returns -INF where nothing is carved. (The first version returned a -1 sentinel, which made a discontinuity the
## mesher turned into shards.)
func _carve(x: float, y: float, z: float, h: float) -> float:
	match biome:
		"ice":
			var c := absf(_n2.get_noise_2d(x * 1.4, z * 0.35)) * 30.0        # ~metres to the crack line
			var slot := maxf(c - 1.4, (h - 14.0) - y)                          # inside: near the line and above the floor
			return -slot
		"volcanic":
			var f := absf(_n2.get_noise_2d(x * 0.9 + 100.0, z * 0.3)) * 30.0
			return -maxf(f - 0.9, (h - 5.0) - y)
		"mountain":
			var v := absf(_cave.get_noise_3d(x, y * 1.6, z)) * 22.0             # ~metres from the tube's centre
			return -(v - 2.2)
	return -INF

# --- materials (indices into terrain_lab.gd SETS) -------------------------------------------------------------
## Returns [top material, rock under it, steep-face material].
func _palette() -> Array:
	match biome:
		"moon": return [0, 8, 8]            # Ground091 regolith, Rock035 basalt
		"desert": return [1, 11, 11]        # Ground097 sand, Rock061 sandstone
		"ice": return [13, 15, 15]          # Snow010A snow, Ice002 ice
		"volcanic": return [4, 8, 8]        # Ground110 dark ash, Rock035 basalt
		"mountain": return [5, 7, 10]       # Gravel040 scree, Rock030, Rock058 cliff
	return [0, 7, 7]

func _generate_block(out: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var size := out.get_size()
	var step := 1 << lod
	var pal := _palette()
	for z in size.z:
		for x in size.x:
			var wx := float(origin.x + x * step)
			var wz := float(origin.z + z * step)
			var h := _height(wx, wz)
			var gx := _height(wx + 1.0, wz) - h
			var gz := _height(wx, wz + 1.0) - h
			var slope := Vector2(gx, gz).length()          # rise per metre
			# loose material slides off past ~35 degrees (tan = 0.7); it fades out between 0.55 and 0.9
			var steep := smoothstep(0.55, 0.9, slope)
			for y in size.y:
				var wy := float(origin.y + y * step)
				var d := wy - h
				var carve := _carve(wx, wy, wz, h)
				var s := maxf(d, carve)
				out.set_voxel_f(s / step, x, y, z, VoxelBuffer.CHANNEL_SDF)
				if s > 2.0:
					continue
				# depth below the original surface decides the layer a cut exposes
				var depth := h - wy
				var rock := smoothstep(0.8, 2.0, depth)
				var w_top := (1.0 - steep) * (1.0 - rock)
				var w_cliff := steep * (1.0 - rock)
				var w_rock := rock
				var mats := [[int(pal[0]), w_top], [int(pal[2]), w_cliff], [int(pal[1]), w_rock]]
				# merge duplicates, keep two strongest
				var acc := {}
				for m in mats:
					acc[m[0]] = float(acc.get(m[0], 0.0)) + float(m[1])
				var keys := acc.keys()
				keys.sort_custom(func(a, b): return acc[a] > acc[b])
				var i0: int = keys[0]
				var i1: int = keys[1] if keys.size() > 1 else -1
				var w0: float = acc[i0]
				var w1: float = acc[i1] if i1 >= 0 else 0.0
				var tot := maxf(w0 + w1, 0.0001)
				var a := clampi(int(round(w0 / tot * 15.0)), 0, 15)
				var b := 15 - a
				var fill: Array = []
				for k in 16:
					if k != i0 and k != i1:
						fill.append(k)
				if i1 < 0:
					i1 = fill.pop_front()
					b = 0
				var idx := (i0 & 0xF) | ((i1 & 0xF) << 4) | ((int(fill[0]) & 0xF) << 8) | ((int(fill[1]) & 0xF) << 12)
				out.set_voxel(idx, x, y, z, VoxelBuffer.CHANNEL_INDICES)
				out.set_voxel(a | (b << 4), x, y, z, VoxelBuffer.CHANNEL_WEIGHTS)

extends VoxelGeneratorScript

## Terrain lab, shape prototypes: one 192 m patch per planet archetype, each built from a "recipe" of geological
## processes rather than from one more noise band. Materials follow rules a geologist would accept: a loose top layer
## (dust, sand, snow) over bedrock, rock showing where the slope is too steep to hold loose material, and whatever a
## cut exposes coming from the layer at that depth.
##   moon     airless, old: rolling regolith + craters (bowl, raised rim), basalt on steep walls
##   desert   wind: dune ridges across one wind direction, mesas from hard rock layers (benches), dry crust flats
##   ice      glacier sheet cut by crevasses, fields of penitentes (ice spikes), clear ice on steep faces
##   volcanic cones and lava plains, dark ash on flats, fissures
##   mountain eroded ridges, scree (gravel) on mid slopes, cliffs of bare rock, a designed cave (capsule path + chambers)
## Material indices refer to terrain_lab.gd SETS.

const SIZE := 192.0

var biome := "moon":
	set(v):
		biome = v
		if v.begins_with("planet_"):
			_proc = derive(PRESETS[v.substr(7)])
			print("PLANET ", v, " -> ", _proc)
		if v == "mountain" and _cave_pts.is_empty():
			_build_cave()   # needs _height(), which depends on the biome
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

## Designed cave (replaces the 3D-noise tube, which shredded at 1 m voxels): a path of capsules from a mouth on the
## mountain flank, descending ~15 degrees and turning gently, opening into two chambers. Built once from a fixed seed,
## like a placed structure, then carved as a signed distance with a little wall noise.
var _cave_pts: Array[Vector3] = []
var _cave_rad: Array[float] = []
var _cave_lo := Vector3.ZERO
var _cave_hi := Vector3.ZERO

func _build_cave() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var x := 70.0
	var z := 60.0
	var p := Vector3(x, _height(x, z) + 1.0, z)
	var dir := Vector3(1.0, 0.0, 0.6).normalized()
	for i in 22:
		_cave_pts.append(p)
		var r := 3.2 + rng.randf_range(-0.6, 0.8)
		if i == 9 or i == 18:
			r = 8.5                                  # chambers
		elif i == 8 or i == 10 or i == 17 or i == 19:
			r = 5.5
		_cave_rad.append(r)
		var yaw := rng.randf_range(-0.35, 0.35)
		dir = Vector3(dir.x * cos(yaw) - dir.z * sin(yaw), 0.0, dir.x * sin(yaw) + dir.z * cos(yaw)).normalized()
		var drop := -0.27 if i < 16 else -0.05
		p += (dir + Vector3(0.0, drop, 0.0)).normalized() * 6.0
	_cave_lo = _cave_pts[0]
	_cave_hi = _cave_pts[0]
	for q in _cave_pts:
		_cave_lo = _cave_lo.min(q)
		_cave_hi = _cave_hi.max(q)
	_cave_lo -= Vector3.ONE * 12.0
	_cave_hi += Vector3.ONE * 12.0

## Signed distance to the cave (negative inside the air).
func _cave_sdf(q: Vector3) -> float:
	if q.x < _cave_lo.x or q.y < _cave_lo.y or q.z < _cave_lo.z or q.x > _cave_hi.x or q.y > _cave_hi.y or q.z > _cave_hi.z:
		return INF
	var best := INF
	for i in _cave_pts.size() - 1:
		var a: Vector3 = _cave_pts[i]
		var b: Vector3 = _cave_pts[i + 1]
		var ab := b - a
		var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var r := lerpf(_cave_rad[i], _cave_rad[i + 1], t)
		var c := a + ab * t
		var dv := q - c
		dv.y *= 1.35                                 # a little flatter than round: a floor you can walk
		best = minf(best, dv.length() - r)
	return best + 0.9 * _n2.get_noise_3d(q.x * 2.0, q.y * 2.0, q.z * 2.0)

# --- planet-input model -----------------------------------------------------------------------------------------
## A planet is physical inputs; process strengths and materials are derived from them, never rolled separately.
## (docs/game/architecture/terrain-lab.md "Planet design"). biome = "planet_<preset>" uses this.
const PRESETS := {
	# temp K, gravity g, atmosphere 0..1, volatiles 0..1, volcanism 0..1, age 0..1
	"coldmoon": {"temp": 90.0, "gravity": 0.17, "atmo": 0.0, "volatiles": 0.6, "volcanism": 0.0, "age": 0.9},
	"hotdesert": {"temp": 320.0, "gravity": 0.6, "atmo": 0.5, "volatiles": 0.05, "volcanism": 0.5, "age": 0.5},
	"icemountain": {"temp": 210.0, "gravity": 1.1, "atmo": 0.8, "volatiles": 0.9, "volcanism": 0.1, "age": 0.3},
}
var _proc := {}

## inputs -> process strengths 0..1 and a material palette [top, rock, steep]
static func derive(pl: Dictionary) -> Dictionary:
	var atmo: float = pl["atmo"]
	var cold := clampf((273.0 - float(pl["temp"])) / 120.0, 0.0, 1.0)     # 0 at freezing, 1 at ~150 K
	var proc := {
		"impacts": clampf((1.0 - atmo * 1.5) * float(pl["age"]), 0.0, 1.0),     # no air to burn them up, old surface
		"wind": clampf(atmo * (1.0 - float(pl["volatiles"]) * 0.6) * (1.0 - cold), 0.0, 1.0),
		"ice": clampf(cold * float(pl["volatiles"]) * 1.3, 0.0, 1.0),
		"volcanism": float(pl["volcanism"]),
		"erosion": clampf(atmo * float(pl["volatiles"]) + (1.0 - float(pl["age"])) * 0.4, 0.0, 1.0),
		# low gravity holds taller relief
		"relief": clampf(1.0 / sqrt(maxf(float(pl["gravity"]), 0.1)), 0.6, 2.0),
	}
	# materials (indices into terrain_lab.gd SETS)
	var top := 0                                                  # Ground091 regolith
	var rock := 8                                                 # Rock035 basalt
	var steep := 8
	if proc["ice"] > 0.5:
		top = 13; rock = 15; steep = 7                            # snow, ice, grey rock on the steepest faces
	elif proc["wind"] > 0.3:
		top = 1; rock = 11; steep = 11                            # sand, sandstone
	elif proc["erosion"] > 0.5:
		top = 5; rock = 7; steep = 10                             # scree, rock, cliff rock
	if proc["volcanism"] > 0.4 and proc["ice"] < 0.5:
		rock = 8                                                  # basalt under it all
	proc["palette"] = [top, rock, steep]
	return proc

func _planet_height(x: float, z: float) -> float:
	var p := _proc
	var rel: float = p["relief"]
	var h := 2.0 * _n.get_noise_2d(x, z) * rel
	if p["erosion"] > 0.0:                                        # ridged ranges
		var r := 1.0 - absf(_n.get_noise_2d(x * 0.8, z * 0.8))
		h += float(p["erosion"]) * (22.0 * r * r * r - 7.0) * rel
	if p["impacts"] > 0.0:
		for c in [[60.0, 70.0, 26.0], [130.0, 120.0, 14.0], [150.0, 40.0, 8.0], [40.0, 150.0, 10.0], [100.0, 165.0, 5.0], [85.0, 30.0, 4.0], [20.0, 100.0, 6.0], [170.0, 90.0, 9.0]]:
			h += float(p["impacts"]) * _crater(Vector2(x - c[0], z - c[1]).length(), c[2]) * rel
	if p["wind"] > 0.0:
		var w := x + 18.0 * _n.get_noise_2d(x * 0.6, z * 0.6)
		var ph := fposmod(w / 22.0, 1.0)
		var dune := (ph / 0.8) if ph < 0.8 else (1.0 - (ph - 0.8) / 0.2)
		h += float(p["wind"]) * dune * 3.5 * (0.6 + 0.4 * _n2.get_noise_2d(x, z))
	if p["volcanism"] > 0.0:
		for c in [[70.0, 80.0, 40.0, 16.0], [150.0, 140.0, 22.0, 9.0]]:
			var d := Vector2(x - c[0], z - c[1]).length()
			h += float(p["volcanism"]) * (c[3] * maxf(0.0, 1.0 - d / c[2]) - c[3] * 0.45 * maxf(0.0, 1.0 - d / (c[2] * 0.18))) * rel
	if p["ice"] > 0.0:
		var field := smoothstep(0.0, 0.25, _n2.get_noise_2d(x * 0.5 + 40.0, z * 0.5))
		h += float(p["ice"]) * field * maxf(0.0, 2.6 * (1.0 - _cell.get_noise_2d(x, z) * 1.6))
	return h

func _planet_carve(x: float, y: float, z: float, h: float) -> float:
	var out := -INF
	if _proc["ice"] > 0.4:                                        # crevasses, sparser than the ice prototype's maze
		var c := absf(_n2.get_noise_2d(x * 0.7, z * 0.18)) * 30.0
		out = maxf(out, -maxf(c - 1.2 * float(_proc["ice"]), (h - 10.0) - y))
	if _proc["volcanism"] > 0.3:
		var f := absf(_n2.get_noise_2d(x * 0.9 + 100.0, z * 0.3)) * 30.0
		out = maxf(out, -maxf(f - 0.9 * float(_proc["volcanism"]), (h - 5.0) - y))
	return out

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
	if not _proc.is_empty():
		return _planet_height(x, z)
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
## given width and depth around the zero lines of a stretched noise; the cave is a designed capsule path (_build_cave).
## Returns -INF where nothing is carved. (The first version returned a -1 sentinel, which made a discontinuity the
## mesher turned into shards.)
func _carve(x: float, y: float, z: float, h: float) -> float:
	if not _proc.is_empty():
		return _planet_carve(x, y, z, h)
	match biome:
		"ice":
			var c := absf(_n2.get_noise_2d(x * 1.4, z * 0.35)) * 30.0        # ~metres to the crack line
			var slot := maxf(c - 1.4, (h - 14.0) - y)                          # inside: near the line and above the floor
			return -slot
		"volcanic":
			var f := absf(_n2.get_noise_2d(x * 0.9 + 100.0, z * 0.3)) * 30.0
			return -maxf(f - 0.9, (h - 5.0) - y)
		"mountain":
			return -_cave_sdf(Vector3(x, y, z))
	return -INF

# --- materials (indices into terrain_lab.gd SETS) -------------------------------------------------------------
## Returns [top material, rock under it, steep-face material].
func _palette() -> Array:
	if not _proc.is_empty():
		return _proc["palette"]
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

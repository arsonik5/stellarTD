extends VoxelGeneratorScript

## Terrain lab ground: a 4 x 4 grid of 16 m tiles, one material each (material index = tile index, 0..15 - exactly the
## 16 slots the 4-bit MIXEL4 format allows). Every tile has the same shapes so materials are compared on equal terms:
## gentle ground, a mound (slopes at every angle), a dug trench (vertical walls and a floor - what digging exposes).
## `blend_width` > 0 cross-fades each tile into its neighbours over that many metres, to judge material transitions.

const TILE := 16.0
const N := 4

var blend_width := 0.0
var _noise := FastNoiseLite.new()

func _init() -> void:
	_noise.seed = 7
	_noise.frequency = 0.12
	_noise.fractal_octaves = 3

func _get_used_channels_mask() -> int:
	return (1 << VoxelBuffer.CHANNEL_SDF) | (1 << VoxelBuffer.CHANNEL_INDICES) | (1 << VoxelBuffer.CHANNEL_WEIGHTS)

static func _box(p: Vector3, half: Vector3) -> float:
	var q := p.abs() - half
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)

func _tile(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floor(x / TILE)), 0, N - 1), clampi(int(floor(z / TILE)), 0, N - 1))

func _sdf(x: float, y: float, z: float) -> float:
	var t := _tile(x, z)
	var u := x - (t.x + 0.5) * TILE
	var v := z - (t.y + 0.5) * TILE
	var h := 0.35 * _noise.get_noise_2d(x, z)
	h += 2.6 * exp(-((u + 3.0) * (u + 3.0) + (v + 3.0) * (v + 3.0)) / 10.0)
	var d := y - h
	# trench: 3 m wide, 10 m long, 2.2 m deep
	var trench := _box(Vector3(u - 3.5, y + 1.1, v), Vector3(1.5, 1.6, 5.0))
	return maxf(d, -trench)

func _generate_block(out: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	var size := out.get_size()
	var step := 1 << lod
	for z in size.z:
		for x in size.x:
			var wx := float(origin.x + x * step)
			var wz := float(origin.z + z * step)
			var t := _tile(wx, wz)
			var i := t.y * N + t.x
			var j := i
			var wj := 0.0
			if blend_width > 0.0:
				# nearest tile border and the tile across it
				var lx := wx - t.x * TILE
				var lz := wz - t.y * TILE
				var cand := [[lx, Vector2i(t.x - 1, t.y)], [TILE - lx, Vector2i(t.x + 1, t.y)],
					[lz, Vector2i(t.x, t.y - 1)], [TILE - lz, Vector2i(t.x, t.y + 1)]]
				var best := INF
				for c in cand:
					var nb: Vector2i = c[1]
					if nb.x < 0 or nb.y < 0 or nb.x >= N or nb.y >= N:
						continue
					if float(c[0]) < best:
						best = c[0]
						j = nb.y * N + nb.x
				if best < blend_width and j != i:
					wj = 0.5 * (1.0 - best / blend_width)
			var others: Array = []
			for k in 16:
				if k != i and k != j:
					others.append(k)
				if others.size() == 3:
					break
			var idx: int
			var wts: int
			if j != i and wj > 0.0:
				var a := clampi(int(round((1.0 - wj) * 15.0)), 0, 15)
				var b := clampi(15 - a, 0, 15)
				idx = (i & 0xF) | ((j & 0xF) << 4) | ((int(others[0]) & 0xF) << 8) | ((int(others[1]) & 0xF) << 12)
				wts = a | (b << 4)
			else:
				idx = (i & 0xF) | ((int(others[0]) & 0xF) << 4) | ((int(others[1]) & 0xF) << 8) | ((int(others[2]) & 0xF) << 12)
				wts = 15
			for y in size.y:
				var wy := float(origin.y + y * step)
				var s := _sdf(wx, wy, wz)
				out.set_voxel_f(s / step, x, y, z, VoxelBuffer.CHANNEL_SDF)
				if s < 2.0:
					out.set_voxel(idx, x, y, z, VoxelBuffer.CHANNEL_INDICES)
					out.set_voxel(wts, x, y, z, VoxelBuffer.CHANNEL_WEIGHTS)

extends SceneTree
## Are craters round in the actual terrain? For the biggest young craters of the home planet, the generator's surface
## radius at 0.5 R from the centre in 12 directions: a round bowl gives the same depth all round. Reads the erosion
## cache (bake windowed first). godot --headless --path . --script res://scripts/dev/crater_round_check.gd
func _init() -> void:
	var body: CelestialBody = load("res://data/celestial_bodies/home_planet.tres")
	var r_m: float = body.radius
	var w := 10216
	var h := 5108
	var field := CraterField.build(body, r_m, TAU * r_m / w)
	var e := ErosionCache.load_entry(body.seed, w, h, field.key)
	if e.is_empty():
		print("no cache")
		quit(1)
		return
	var masks := {}
	for k in e:
		if k != "height":
			masks[k] = e[k]
	var profile := PlanetProfile.derive(body, 1.0)
	var g := PlanetGraphGenerator.build(body, 1.0, profile, false, false, e["height"], masks)
	var buf := VoxelBuffer.new()
	buf.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	buf.create(1, 1, 1)
	var data: PackedFloat32Array = field.data
	var picks := []
	for i in int(field.count):
		var o := i * CraterField.STRIDE
		if data[o + 6] < 0.45 and data[o + 3] > 250.0:
			picks.append(i)
	picks.sort_custom(func(a, b): return data[a * CraterField.STRIDE + 3] > data[b * CraterField.STRIDE + 3])
	for i in picks.slice(0, 6):
		var o: int = i * CraterField.STRIDE
		var c := Vector3(data[o], data[o + 1], data[o + 2])
		var R := data[o + 3]
		var east := Vector3(data[o + 8], data[o + 9], data[o + 10])
		var north := c.cross(east)
		var vals := []
		for k in 12:
			var a := TAU * k / 12.0
			var d := (c * r_m + (east * cos(a) + north * sin(a)) * R * 0.5).normalized()
			vals.append(_surf(g, buf, d, r_m))
		var mn: float = vals.min()
		var mx: float = vals.max()
		var rim := _surf(g, buf, (c * r_m + east * R * 1.05).normalized(), r_m)
		var ctr := _surf(g, buf, c, r_m)
		print("crater R %4.0f m lat %5.1f  rim-centre %6.1f m  ring spread %5.1f m  (E-W %5.1f, N-S %5.1f)" % [R,
			rad_to_deg(asin(c.y)), rim - ctr, mx - mn, (vals[0] + vals[6]) * 0.5 - ctr, (vals[3] + vals[9]) * 0.5 - ctr])
	quit()

func _surf(g: VoxelGeneratorGraph, buf: VoxelBuffer, d: Vector3, r0: float) -> float:
	var lo := r0 - 900.0
	var hi := r0 + 900.0
	for _i in 22:
		var mid := (lo + hi) * 0.5
		g.generate_block(buf, Vector3i((d * mid).round()), 0)
		if buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

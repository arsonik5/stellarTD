extends SceneTree
## Lava tubes in the real generator, headless (reads the erosion cache, so bake windowed once first):
##   godot --headless --path . --script res://scripts/dev/tube_probe.gd
## Scans a grid of directions; at each, is the voxel TUBE_DEPTH below the ground air? Then for a few hits measures
## the tunnel's width (sideways scan) and height (radial scan), and whether its roof is open (skylight).
func _init() -> void:
	var body: CelestialBody = load("res://data/celestial_bodies/home_planet.tres")
	var r_m: float = body.radius
	var w := 10216
	var h := 5108
	var field := CraterField.build(body, r_m, TAU * r_m / w)
	var e := ErosionCache.load_entry(body.seed, w, h, field.key)
	if e.is_empty():
		print("TUBE no cache")
		quit(1)
		return
	var masks := {}
	for k in e:
		if k != "height":
			masks[k] = e[k]
	var profile := PlanetProfile.derive(body, 1.0)
	print("TUBE landform ", TraitMixer.landform(body), "  mix ", TraitMixer.describe(TraitMixer.of(body)))
	var t0 := Time.get_ticks_msec()
	PlanetGraphGenerator.tubes_enabled = false
	var g_off := PlanetGraphGenerator.build(body, 1.0, profile, false, false, e["height"], masks)
	PlanetGraphGenerator.tubes_enabled = true
	var g := PlanetGraphGenerator.build(body, 1.0, profile, false, false, e["height"], masks)
	print("TUBE graph build ms ", Time.get_ticks_msec() - t0)
	var buf := VoxelBuffer.new()
	buf.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	buf.create(1, 1, 1)
	var sdf := func(p: Vector3) -> float:
		g.generate_block(buf, Vector3i(p.round()), 0)
		return buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
	var surf := func(d: Vector3) -> float:
		var lo := r_m - 900.0
		var hi := r_m + 900.0
		for _i in 22:
			var mid := (lo + hi) * 0.5
			if sdf.call(d * mid) < 0.0:
				lo = mid
			else:
				hi = mid
		return (lo + hi) * 0.5
	var n := 0
	var n_other := 0
	var pits := 0
	var hits := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 15000:
		var zc := rng.randf_range(-0.8, 0.8)
		var ph := rng.randf() * TAU
		var s := sqrt(1.0 - zc * zc)
		var d := Vector3(s * cos(ph), zc, s * sin(ph))
		# cheap: ground from the bisection only every sample (costly), so a coarse 12-step one
		n += 1
		# ground without tubes (one crossing, bisection is safe), then the real ground by marching down from above it:
		# bisection on the real field can settle on a tube floor instead of the outermost crossing
		var lo2 := r_m - 900.0
		var hi2 := r_m + 900.0
		for _i in 22:
			var mid := (lo2 + hi2) * 0.5
			g_off.generate_block(buf, Vector3i((d * mid).round()), 0)
			if buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) < 0.0:
				lo2 = mid
			else:
				hi2 = mid
		var r_off := (lo2 + hi2) * 0.5
		var rs := r_off + 3.0
		while rs > r_off - 30.0 and sdf.call(d * rs) > 0.0:
			rs -= 0.5
		if r_off - rs > 4.0:
			pits += 1
		if sdf.call(d * (rs - PlanetGraphGenerator.TUBE_DEPTH_M)) > 0.0:
			g_off.generate_block(buf, Vector3i((d * (rs - PlanetGraphGenerator.TUBE_DEPTH_M)).round()), 0)
			if buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) > 0.0:
				n_other += 1                       # hollow without tubes too: an overhang or cliff, not a tube
			else:
				hits.append([d, rs])
	print("TUBE ground fallen into a tube (skylights, collapse trenches): %d samples (%.2f%%), %.0f%% of tube area" % [pits, 100.0 * pits / n, 100.0 * pits / maxf(pits + hits.size(), 1)])
	print("TUBE samples %d  tube air at tube depth %d (%.2f%%), other hollows %d" % [n, hits.size(), 100.0 * hits.size() / n, n_other])
	for hit in hits.slice(0, 0):
		var d: Vector3 = hit[0]
		var rs: float = hit[1]
		var c := d * (rs - PlanetGraphGenerator.TUBE_DEPTH_M)
		var east := Vector3.UP.cross(d).normalized()
		var north := d.cross(east)
		var best_w := 1e9
		for ax in [east, north, (east + north).normalized(), (east - north).normalized()]:
			var a := 0.0
			while a < 80.0 and sdf.call(c + ax * a) > 0.0:
				a += 0.5
			var b := 0.0
			while b < 80.0 and sdf.call(c - ax * b) > 0.0:
				b += 0.5
			best_w = minf(best_w, a + b)
		var up_ := 0.0
		while up_ < 40.0 and sdf.call(c + d * up_) > 0.0:
			up_ += 0.5
		var dn := 0.0
		while dn < 40.0 and sdf.call(c - d * dn) > 0.0:
			dn += 0.5
		print("TUBE hit  width %.1f m  height %.1f m  open to sky %s  lat %.1f" % [best_w, up_ + dn, up_ >= PlanetGraphGenerator.TUBE_DEPTH_M - 1.0, rad_to_deg(asin(d.y))])
	quit()


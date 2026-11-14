extends SceneTree
## Generator cost per voxel for the home planet, tubes on vs off, on surface blocks (headless, from the erosion cache).
func _init() -> void:
	var body: CelestialBody = load("res://data/celestial_bodies/home_planet.tres")
	var r_m: float = body.radius
	var field := CraterField.build(body, r_m, TAU * r_m / 10216)
	var e := ErosionCache.load_entry(body.seed, 10216, 5108, field.key)
	var masks := {}
	for k in e:
		if k != "height":
			masks[k] = e[k]
	var profile := PlanetProfile.derive(body, 1.0)
	for on in [false, true, false, true]:
		PlanetGraphGenerator.tubes_enabled = on
		var g := PlanetGraphGenerator.build(body, 1.0, profile, false, false, e["height"], masks)
		var buf := VoxelBuffer.new()
		buf.create(32, 32, 32)
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		var t0 := Time.get_ticks_usec()
		for i in 24:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)).normalized()
			g.generate_block(buf, Vector3i((d * (r_m + 300.0 * rng.randf_range(-1, 1))).round()), 0)
		var us := float(Time.get_ticks_usec() - t0) / (24.0 * 32768.0)
		print("COST tubes=%s  %.3f us/voxel  nodes %d" % [on, us, g.get_main_function().get_node_ids().size()])
	quit()

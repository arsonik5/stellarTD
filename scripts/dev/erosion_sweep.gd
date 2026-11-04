extends Node

## Dev tool: bake several erosion parameter sets and write HILLSHADED previews.
##
##     godot --path . res://scenes/dev/erosion_sweep.tscn
##
## Hillshaded, not raw height. A greyscale heightmap is almost impossible to
## judge landform from - blobs and plateaus look identical - whereas a shaded
## relief render shows slope, which is what actually reads as terrain. Judging
## bakes from raw height is how an over-eroded map got promoted to default.
##
## Runs at ~0.6 s per bake, so a sweep of six is faster than a single game load.
## Must run WINDOWED: headless Godot has no GPU context.

func _ready() -> void:
	var variants := [
		{
			"name": "a_current",
			"note": "current defaults - heavy hydraulic, weak thermal",
			"apply": func(s): pass,
		},
		{
			"name": "b_massive",
			"note": "mass curve + bigger base features, gentler water",
			"apply": func(s):
				s.frequency = 1.25
				s.octaves = 6
				s.ridge_mix = 0.6
				s.mass_low = 0.32
				s.mass_high = 0.78
				s.droplet_density = 1.1
				s.erode_rate = 0.22,
		},
		{
			"name": "c_plateau",
			"note": "as b, plus strong thermal for flat tops and talus",
			"apply": func(s):
				s.frequency = 1.25
				s.octaves = 6
				s.ridge_mix = 0.6
				s.mass_low = 0.32
				s.mass_high = 0.78
				s.droplet_density = 1.1
				s.erode_rate = 0.22
				s.thermal_iterations = 120
				s.talus = 0.0075,
		},
		{
			"name": "d_mountain",
			"note": "ridged-dominant base: sharp divides for water to cut between",
			"apply": func(s):
				s.frequency = 1.5
				s.octaves = 7
				s.ridge_mix = 0.85
				s.gain = 0.55
				s.mass_low = 0.25
				s.mass_high = 0.85
				s.droplet_density = 1.4
				s.erode_rate = 0.28
				s.thermal_iterations = 80
				s.talus = 0.006,
		},
		{
			"name": "e_deep",
			"note": "as d, with long droplet runs so channels connect into systems",
			"apply": func(s):
				s.frequency = 1.5
				s.octaves = 7
				s.ridge_mix = 0.85
				s.gain = 0.55
				s.mass_low = 0.25
				s.mass_high = 0.85
				s.droplet_density = 1.8
				s.droplet_steps = 190
				s.erode_rate = 0.3
				s.capacity = 12.0
				s.thermal_iterations = 90
				s.talus = 0.0065,
		},
	]

	for v in variants:
		var baker := ErosionBaker.new()
		var s := ErosionBaker.Settings.new()
		s.width = 2048
		s.height = 1024
		s.seed = 1
		v["apply"].call(s)
		var img := baker.bake(s)
		if img == null:
			print("FAIL ", v["name"])
			continue
		var stats: Dictionary = baker.last_stats
		var relief := _relief_stats(img)
		print("%-12s %5d ms  sd=%.3f  slope_mean=%.4f  slope_p95=%.4f   %s" % [
			v["name"], stats["total_ms"], relief["sd"], relief["slope_mean"],
			relief["slope_p95"], v["note"]])
		_save_hillshade(img, "user://sweep_%s.png" % v["name"])
	print("SWEEP_DONE")
	get_tree().quit()

## Standard deviation of height, plus slope statistics.
##
## Slope is the number that actually separates "mountains" from "swells": two
## maps can have identical height SD while one is a gentle dome and the other is
## a cliff. p95 says how steep the steep parts are.
func _relief_stats(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var mean := 0.0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			mean += img.get_pixel(x, y).r
	var n := (h / 2) * (w / 2)
	mean /= float(n)

	var var_sum := 0.0
	var slopes := PackedFloat32Array()
	for y in range(1, h - 1, 4):
		for x in range(1, w - 1, 4):
			var c := img.get_pixel(x, y).r
			var_sum += (c - mean) * (c - mean)
			var dx: float = img.get_pixel(x + 1, y).r - img.get_pixel(x - 1, y).r
			var dy: float = img.get_pixel(x, y + 1).r - img.get_pixel(x, y - 1).r
			slopes.append(sqrt(dx * dx + dy * dy))
	var sd := sqrt(var_sum / maxf(float(slopes.size()), 1.0))
	var sorted := slopes.duplicate()
	sorted.sort()
	var mean_slope := 0.0
	for s in sorted:
		mean_slope += s
	mean_slope /= maxf(float(sorted.size()), 1.0)
	var p95: float = sorted[int(sorted.size() * 0.95)] if sorted.size() > 0 else 0.0
	return {"sd": sd, "slope_mean": mean_slope, "slope_p95": p95}

## Shaded relief with a low sun, which is how terrain is read on a map.
func _save_hillshade(img: Image, path: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	# Light from the upper left at a low angle - the convention, and low angles
	# reveal shallow landform that an overhead light flattens away.
	var lx := -0.6
	var ly := -0.6
	var lz := 0.35
	var inv := 1.0 / sqrt(lx * lx + ly * ly + lz * lz)
	lx *= inv; ly *= inv; lz *= inv
	for y in h:
		for x in w:
			var xm := (x - 1 + w) % w
			var xp := (x + 1) % w
			var ym: int = maxi(y - 1, 0)
			var yp: int = mini(y + 1, h - 1)
			# Exaggerated vertically, or a planetary-scale map shades almost flat.
			var dx: float = (img.get_pixel(xp, y).r - img.get_pixel(xm, y).r) * 60.0
			var dy: float = (img.get_pixel(x, yp).r - img.get_pixel(x, ym).r) * 60.0
			var len := sqrt(dx * dx + dy * dy + 1.0)
			var ndl: float = clampf((-dx * lx - dy * ly + lz) / len, 0.0, 1.0)
			# A little of the raw height mixed in so basins read as low rather
			# than just unlit.
			var shade: float = ndl * 0.82 + img.get_pixel(x, y).r * 0.18
			out.set_pixel(x, y, Color(shade, shade, shade))
	out.save_png(path)

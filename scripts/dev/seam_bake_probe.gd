extends SceneTree
## Which bake stage puts a ridge on the x = 0 column? Bakes a small map with stages switched off one at a time and
## prints the seam's second difference against the median column. Needs a GPU: run windowed (no --headless).

func _score(h: Image) -> String:
	var w := h.get_width()
	var cols := []
	for x in [0, 1, w / 3, w / 2]:
		var s := 0.0
		var n := 0
		for y in range(h.get_height() / 10, h.get_height() * 9 / 10, 7):
			var a := h.get_pixel(posmod(x - 1, w), y).r
			var b := h.get_pixel(x, y).r
			var c := h.get_pixel(posmod(x + 1, w), y).r
			s += absf(2.0 * b - a - c)
			n += 1
		cols.append("%.5f" % (s / n))
	return "x0 %s  x1 %s  mid %s %s" % cols

func _init() -> void:
	await process_frame
	var cases := {

		"full": {},
		
		


	}
	for name in cases:
		var c: Dictionary = cases[name]
		var s := ErosionBaker.Settings.new()
		s.seed = 1
		s.width = 10216
		s.height = 5108
		s.relief_m = 1600.0
		s.metres_per_texel = 12.3
		s.batches = c.get("batches", 40)
		s.thermal_iterations = c.get("thermal", 90)
		s.droplet_density = c.get("density", 1.8)
		s.mantle_iterations = c.get("mantle", 4)
		var b := ErosionBaker.new()
		var img: Image = await b.bake(s)
		print("SEAM ", name, ": ", _score(img) if img != null else "bake failed")
	quit()

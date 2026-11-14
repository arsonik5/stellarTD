extends SceneTree
## OKLCH of every library material as the planet shows it (PaletteBuilder.displayed_colour): picking materials by numbers.
func _init() -> void:
	var dir := DirAccess.open("res://data/surfaces/library")
	var rows := []
	for f in dir.get_files():
		if f.ends_with(".tres"):
			var s: SurfaceStyle = load("res://data/surfaces/library/" + f)
			var c := PaletteBuilder.oklch(PaletteBuilder.displayed_colour(s))
			rows.append([c.x, "MAT %-16s L %.2f C %.3f h %3.0f" % [f.get_basename(), c.x, c.y, c.z]])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	for r in rows:
		print(r[1])
	quit()

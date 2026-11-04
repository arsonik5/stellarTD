extends Node

## Dev tool: bake and inspect the three erosion masks.
##
##     godot --path . res://scenes/dev/erosion_masks.tscn
##
## Writes flow/wear/deposition previews next to a hillshade of the height, and
## prints statistics that say whether each mask is MEANINGFUL rather than merely
## non-empty. A mask full of plausible-looking grey is easy to produce and worth
## nothing; these are the numbers that separate the two:
##
##   coverage  - fraction of the surface above 0.1. A mask that covers
##               everything or almost nothing cannot select a material.
##   vs height - correlation with elevation. Flow and deposition must be
##               NEGATIVE (water and sediment end up low); wear should be near
##               zero or positive (scouring happens on slopes, not in basins).
##   vs slope  - correlation with terrain steepness. Wear must be POSITIVE or
##               it is not tracking erosion at all.
##
## Signs that come out backwards mean the mask is inverted somewhere, which is
## the failure mode that would otherwise be discovered only by painting a planet
## with dust on the ridges.

func _ready() -> void:
	var baker := ErosionBaker.new()
	var s := ErosionBaker.Settings.new()
	s.width = 2048
	s.height = 1024
	s.seed = 1
	var img := baker.bake(s)
	if img == null:
		print("FAIL: no map")
		get_tree().quit()
		return
	print("bake: ", baker.last_stats)

	var height := _grid(img)
	var slope := _slope_grid(img)
	print("\n%-12s %9s %9s %9s %10s %10s" % [
		"mask", "mean", "p50", "coverage", "vs height", "vs slope"])
	for key in ["flow", "wear", "deposition"]:
		var m: Image = baker.last_masks.get(key)
		if m == null:
			print("%-12s MISSING" % key)
			continue
		var g := _grid(m)
		print("%-12s %9.4f %9.4f %8.1f%% %10.2f %10.2f" % [
			key, _mean(g), _median(g), 100.0 * _coverage(g),
			_corr(g, height), _corr(g, slope)])
		m.save_png("user://mask_%s.png" % key)
	img.save_png("user://mask_height.png")
	print("MASKS_DONE")
	get_tree().quit()

## Subsampled to a flat array - the statistics below are O(n) each and run
## several times, and full resolution buys no accuracy for a correlation.
func _grid(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var w := img.get_width()
	var h := img.get_height()
	for y in range(1, h - 1, 4):
		for x in range(0, w, 4):
			out.append(img.get_pixel(x, y).r)
	return out

func _slope_grid(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var w := img.get_width()
	var h := img.get_height()
	for y in range(1, h - 1, 4):
		for x in range(0, w, 4):
			var dx: float = img.get_pixel((x + 1) % w, y).r \
				- img.get_pixel((x - 1 + w) % w, y).r
			var dy: float = img.get_pixel(x, y + 1).r - img.get_pixel(x, y - 1).r
			out.append(sqrt(dx * dx + dy * dy))
	return out

func _mean(a: PackedFloat32Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t / maxf(float(a.size()), 1.0)

func _median(a: PackedFloat32Array) -> float:
	var c := a.duplicate()
	c.sort()
	return c[c.size() / 2] if c.size() > 0 else 0.0

func _coverage(a: PackedFloat32Array) -> float:
	var n := 0
	for v in a:
		if v > 0.1:
			n += 1
	return float(n) / maxf(float(a.size()), 1.0)

## Pearson correlation. -1 to +1; the SIGN is what matters here.
func _corr(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n == 0:
		return 0.0
	var ma := _mean(a)
	var mb := _mean(b)
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in n:
		var x := a[i] - ma
		var y := b[i] - mb
		num += x * y
		da += x * x
		db += y * y
	return num / maxf(sqrt(da * db), 1e-12)

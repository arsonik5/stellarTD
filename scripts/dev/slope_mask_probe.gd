extends SceneTree

## Dev probe: is the baked slope mask telling the truth?
##
##     godot --path . --headless -s res://scripts/dev/slope_mask_probe.gd
##
## Loads the cached bake on the CPU and, for a spread of mask texels, recomputes
## the slope directly from the full-resolution height over the same footprint.
## Both live in the map's own texel space, so this validates the mask without
## depending on any direction-to-texel convention being right.
##
## Written because a cliff got LESS rocky after the mask replaced the old
## gradient, which is the opposite of what the mask exists for. Either its values
## are wrong or the gating that reads it is - and those need different fixes.

const SEED := 1
const W := 10216
const H := 5108
const RADIUS_M := 20000.0
const RELIEF_M := 1614.6

func _init() -> void:
	var e := ErosionCache.load_entry(SEED, W, H)
	if e.is_empty():
		print("FAIL: no cache entry")
		quit()
		return
	var mask: Image = e.get("slope")
	var hm: Image = e.get("height")
	if mask == null or hm == null:
		print("FAIL: missing layer slope=%s height=%s" % [mask != null, hm != null])
		quit()
		return
	var mw := mask.get_width()
	var mh := mask.get_height()
	print("mask %dx%d  height %dx%d" % [mw, mh, hm.get_width(), hm.get_height()])

	var vals := PackedFloat32Array()
	for y in range(int(mh * 0.15), int(mh * 0.85), 2):
		for x in range(0, mw, 2):
			vals.append(mask.get_pixel(x, y).r * 90.0)
	vals.sort()
	print("mask degrees: p10 %.1f  p50 %.1f  p90 %.1f  p99 %.1f  max %.1f" % [
		vals[int(vals.size() * 0.1)], vals[int(vals.size() * 0.5)],
		vals[int(vals.size() * 0.9)], vals[int(vals.size() * 0.99)], vals[vals.size() - 1]])

	var mpt := TAU * RADIUS_M / float(W)
	var fx := W / mw
	var fy := H / mh
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var diffs := PackedFloat32Array()
	var steep_mask := 0
	var steep_cpu := 0
	print("  ox    oy   mask_deg  cpu_max_deg  cpu_mean_deg")
	for i in 600:
		var ox := rng.randi_range(0, mw - 1)
		var oy := rng.randi_range(int(mh * 0.15), int(mh * 0.85))
		var bx := ox * W / mw
		var by := oy * H / mh
		var mx := 0.0
		var sum := 0.0
		var n := 0
		for dy in fy:
			for dx in fx:
				var px := (bx + dx) % W
				var py := clampi(by + dy, 1, H - 2)
				var lat := PI * 0.5 - (float(py) + 0.5) / float(H) * PI
				var xm := maxf(cos(lat), 0.05)
				var gx := (hm.get_pixel((px + 1) % W, py).r - hm.get_pixel((px - 1 + W) % W, py).r) \
					/ (2.0 * mpt * xm)
				var gy := (hm.get_pixel(px, py + 1).r - hm.get_pixel(px, py - 1).r) / (2.0 * mpt)
				var a := rad_to_deg(atan(Vector2(gx, gy).length() * RELIEF_M))
				mx = maxf(mx, a)
				sum += a
				n += 1
		var m := mask.get_pixel(ox, oy).r * 90.0
		diffs.append(absf(m - mx))
		if m > 40.0:
			steep_mask += 1
		if mx > 40.0:
			steep_cpu += 1
		if i < 12 or mx > 45.0 and i < 200:
			print("%5d %5d   %6.1f     %6.1f       %6.1f" % [ox, oy, m, mx, sum / maxf(n, 1)])
	diffs.sort()
	print("|mask - cpu max| degrees: p50 %.2f  p90 %.2f  p99 %.2f" % [
		diffs[int(diffs.size() * 0.5)], diffs[int(diffs.size() * 0.9)],
		diffs[int(diffs.size() * 0.99)]])
	print("texels over 40 deg: mask %d  cpu %d  of %d" % [steep_mask, steep_cpu, diffs.size()])
	mask.save_png("user://slope_mask_probe.png")
	print("SLOPE_PROBE_DONE")
	quit()

extends Node

## Dev tool: is the eroded map ISOTROPIC in real distance?
##
##     godot --path . res://scenes/dev/erosion_aniso.tscn
##
## The orbit capture showed concentric rings centred on the pole. Rings on a
## sphere are latitude-aligned structure, and latitude-aligned structure is what
## you get when a process treats an equirectangular grid as if its cells were
## square. They are not: one texel of x spans cos(lat) as much ground as one
## texel of y, shrinking to nothing at the pole.
##
## The base field is generated on the sphere direction, so it starts isotropic.
## Erosion then runs on the raw texel grid, which sees the same terrain as
## stretched east-west, so it carves north-south and leaves east-west bands.
##
## This measures the claim instead of arguing it: per latitude band, the mean
## gradient in REAL metres east-west against the same north-south. Isotropic
## terrain gives a ratio near 1 at every latitude. A ratio that collapses toward
## the poles is the ring artifact, measured.

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
	_report("eroded", img)

	# The base field alone, with erosion switched off, as the control. If this
	# one is isotropic and the eroded one is not, erosion is the cause and no
	# further argument is needed.
	var s2 := ErosionBaker.Settings.new()
	s2.width = 2048
	s2.height = 1024
	s2.seed = 1
	s2.droplet_density = 0.0
	s2.thermal_iterations = 0
	var base := baker.bake(s2)
	if base != null:
		_report("base (no erosion)", base)
	print("ANISO_DONE")
	get_tree().quit()

## Mean |gradient| east-west vs north-south, in real metres, per latitude band.
func _report(label: String, img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	print("\n=== %s ===" % label)
	print("%-14s %10s %10s %8s" % ["latitude", "d/dEast", "d/dNorth", "EW/NS"])
	var bands := 9
	for b in bands:
		var y0 := int(h * float(b) / bands)
		var y1 := int(h * float(b + 1) / bands)
		var sum_ew := 0.0
		var sum_ns := 0.0
		var n := 0
		for y in range(maxi(y0, 1), mini(y1, h - 1), 2):
			# Real ground per texel: y is constant, x shrinks with cos(lat).
			var lat: float = PI * 0.5 - (float(y) + 0.5) / float(h) * PI
			var cos_lat: float = maxf(cos(lat), 1e-4)
			for x in range(0, w, 2):
				var dx: float = img.get_pixel((x + 1) % w, y).r \
					- img.get_pixel((x - 1 + w) % w, y).r
				var dy: float = img.get_pixel(x, y + 1).r - img.get_pixel(x, y - 1).r
				# Divide by the real span the difference covers. The y span is the
				# unit; the x span is cos(lat) of it.
				sum_ew += absf(dx) / cos_lat
				sum_ns += absf(dy)
				n += 1
		if n == 0:
			continue
		var ew := sum_ew / n
		var ns := sum_ns / n
		var lat_mid: float = 90.0 - (float(y0 + y1) * 0.5 / float(h)) * 180.0
		print("%+6.0f deg      %10.5f %10.5f %8.2f" % [lat_mid, ew, ns, ew / maxf(ns, 1e-9)])

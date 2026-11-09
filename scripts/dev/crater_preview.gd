extends SceneTree

## Hillshade + crater masks straight from the erosion cache, no GPU needed:
##   godot --headless --path . --script res://scripts/dev/crater_preview.gd -- [seed=1] [crop=x,y,w,h] [tag=x]
## Writes art_src/ingame/craters_<tag>_shade.png (full map, downsampled), _crop.png (full-res crop) and _fresh.png.

func _init() -> void:
	var seed_v := 1
	var tag := "s1"
	var crop := Rect2i()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed_v = int(a.substr(5))
		elif a.begins_with("tag="):
			tag = a.substr(4)
		elif a.begins_with("crop="):
			var p := a.substr(5).split(",")
			crop = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
	var dir := DirAccess.open(ErosionCache.DIR)
	var file := ""
	for f in dir.get_files():
		if f.begins_with("v%d_s%d_" % [ErosionCache.FORMAT_VERSION, seed_v]):
			file = f
	if file == "":
		print("no cache for seed ", seed_v)
		quit(1)
		return
	var p := file.trim_suffix(".bin").split("_")
	var wh := p[2].split("x")
	var feat := p[3].substr(1).hex_to_int()
	var e := ErosionCache.load_entry(seed_v, int(wh[0]), int(wh[1]), feat)
	if e.is_empty():
		print("load failed ", file)
		quit(1)
		return
	var h: Image = e["height"]
	var w := h.get_width()
	var hh := h.get_height()
	var out := "res://art_src/ingame/craters_%s" % tag
	_shade(h, Rect2i(0, 0, w, hh), maxi(w / 2048, 1), 0.6).save_png(ProjectSettings.globalize_path(out + "_shade.png"))
	if crop.size.x > 0:
		_shade(h, crop, 1, 0.25).save_png(ProjectSettings.globalize_path(out + "_crop.png"))
	for k in ["fresh", "crater_floor"]:
		var m: Image = e.get(k)
		if m != null:
			var img := Image.create_empty(m.get_width(), m.get_height(), false, Image.FORMAT_RGB8)
			for y in m.get_height():
				for x in m.get_width():
					var v := m.get_pixel(x, y).r
					img.set_pixel(x, y, Color(v, v, v))
			if img.get_width() > 2048:
				img.resize(2048, 1024)
			img.save_png(ProjectSettings.globalize_path(out + "_" + k + ".png"))
	print("preview ", file)
	quit()

## Lambert hillshade, sun from the north-west at 35 degrees. `exag` multiplies the slope.
func _shade(h: Image, r: Rect2i, step: int, exag: float) -> Image:
	var ow := r.size.x / step
	var oh := r.size.y / step
	var img := Image.create_empty(ow, oh, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.55, -0.6).normalized()
	var W := h.get_width()
	var H := h.get_height()
	var k := 400.0 * exag
	for oy in oh:
		for ox in ow:
			var x := r.position.x + ox * step
			var y := r.position.y + oy * step
			var hx := h.get_pixel(posmod(x + step, W), y).r - h.get_pixel(posmod(x - step, W), y).r
			var hy := h.get_pixel(x, clampi(y + step, 0, H - 1)).r - h.get_pixel(x, clampi(y - step, 0, H - 1)).r
			var n := Vector3(-hx * k / step, 1.0, -hy * k / step).normalized()
			var v := clampf(n.dot(light), 0.0, 1.0) * 0.85 + 0.1
			img.set_pixel(ox, oy, Color(v, v, v))
	return img

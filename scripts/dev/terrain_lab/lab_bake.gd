extends SceneTree

## Terrain lab: turns the raw CC0 sets in art_src/terrain_lab/cc0/<id>/ into the terrain shader's two-texture format,
## in two looks, at 512 px:
##   pbr  - the source maps as they are (albedo stays de-lit; relief comes from the normal map at render time)
##   ps2  - "light painted in": AO, cavity and a fixed top light are baked into the albedo, because the game renders
##          with per-vertex lighting (force_vertex_shading) and a normal map alone barely shows under it
## Output: art_src/terrain_lab/baked/<id>_<look>_alb.png  (RGB albedo, A roughness)
##         art_src/terrain_lab/baked/<id>_<look>_nrm.png  (RG normal, B occlusion, A height)
##   godot --headless --path . --script res://scripts/dev/terrain_lab/lab_bake.gd

const SRC := "res://art_src/terrain_lab/cc0"
const OUT := "res://art_src/terrain_lab/baked"
const SIZE := 512
## Looks and their size. "lo" = low-res PBR: 256 px maps meant for per-pixel lighting (modern light, retro texels).
const LOOKS := {"pbr": 512, "ps2": 512, "lo": 256}
## Painted top light, in texture space (z = out of the surface).
const LIGHT := Vector3(0.35, 0.45, 0.82)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var dir := DirAccess.open(SRC)
	var n := 0
	for id in dir.get_directories():
		if _bake(id):
			n += 1
	print("LAB_BAKE baked %d sets" % n)
	quit()

func _load(id: String, map: String) -> Image:
	var p := ProjectSettings.globalize_path("%s/%s/%s_1K-JPG_%s.jpg" % [SRC, id, id, map])
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	img.convert(Image.FORMAT_RGBA8)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return img

func _bake(id: String) -> bool:
	var col := _load(id, "Color")
	var nrm := _load(id, "NormalGL")
	if col == null or nrm == null:
		print("skip ", id)
		return false
	var ao := _load(id, "AmbientOcclusion")
	var disp := _load(id, "Displacement")
	var rough := _load(id, "Roughness")
	var l := LIGHT.normalized()
	var flat := 0.45 + 0.75 * l.z
	for look in LOOKS:
		var alb := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var nm := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		for y in SIZE:
			for x in SIZE:
				var c := col.get_pixel(x, y)
				var n := nrm.get_pixel(x, y)
				var o := ao.get_pixel(x, y).r if ao != null else 1.0
				var h := disp.get_pixel(x, y).r if disp != null else 0.5
				var r := rough.get_pixel(x, y).r if rough != null else 0.8
				if look == "ps2":
					var nv := Vector3(n.r * 2.0 - 1.0, n.g * 2.0 - 1.0, n.b * 2.0 - 1.0).normalized()
					var shade := clampf(0.45 + 0.75 * nv.dot(l), 0.3, 1.35) / flat
					var occl := 0.5 + 0.5 * o
					var lift := 0.82 + 0.36 * h
					var k := shade * occl * lift
					c = Color(c.r * k, c.g * k, c.b * k)
					# a touch more saturation and contrast: era textures were punchy, not photographic
					var g := c.get_luminance()
					c = Color(g + (c.r - g) * 1.15, g + (c.g - g) * 1.15, g + (c.b - g) * 1.15)
					c = Color((c.r - 0.5) * 1.08 + 0.5, (c.g - 0.5) * 1.08 + 0.5, (c.b - 0.5) * 1.08 + 0.5)
				alb.set_pixel(x, y, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1), r))
				nm.set_pixel(x, y, Color(n.r, n.g, maxf(o, 0.45), h))
		if LOOKS[look] != SIZE:
			alb.resize(LOOKS[look], LOOKS[look], Image.INTERPOLATE_LANCZOS)
			nm.resize(LOOKS[look], LOOKS[look], Image.INTERPOLATE_LANCZOS)
		alb.save_png(ProjectSettings.globalize_path("%s/%s_%s_alb.png" % [OUT, id, look]))
		nm.save_png(ProjectSettings.globalize_path("%s/%s_%s_nrm.png" % [OUT, id, look]))
	print("baked ", id)
	return true

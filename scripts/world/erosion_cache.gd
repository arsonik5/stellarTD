class_name ErosionCache
extends RefCounted

## Stores a baked erosion result on disk, keyed by everything that affects it.
##
## The bake became a cached artifact when the home planet grew to 20 km. The map
## has to keep a fixed GROUND resolution rather than a fixed texel count - that
## was the finding behind the slope collapse, see terrain-generator.md - which
## at 20 km means 10240x5120, about 6x the pixels of the old 4096. That is too
## slow to run at every load and completely fine to run once per seed.
##
## Stored as raw float32 behind FileAccess.open_compressed. NOT as a PNG: 8 bits
## across 1615 m of relief is 6.3 m per step, and a height field quantised that
## coarsely produces visible terracing - the same contour-band artifact this
## generator spent so long removing from the noise path. There is no point
## baking a careful map and then rounding it into steps on the way to disk.

const DIR := "user://erosion_cache"

## Bumped whenever the bake changes in a way that invalidates stored results -
## a shader edit, a settings default, a new mask. Without it, a stale cache
## silently serves the old terrain and every measurement afterwards is of
## something that is no longer in the source.
const FORMAT_VERSION := 14

## Layers in a cache entry, in write order. Height first so a truncated file
## still fails cleanly rather than loading masks against no terrain.
## `slope` is landform steepness (angle / 90) measured at full resolution on
## the GPU and max-pooled to mask size. It replaced `height_lo`, a
## mask-resolution copy of the height the generator differenced per voxel:
## cheap, but at ~61 m per texel it read a 54 degree cliff as near-flat.
## Differencing the full map instead cost 3.0 -> 8.8 us/voxel in cache
## misses, so the gradient moved into the bake.
## `fresh` and `crater_floor` come from the crater pass (CraterField, craters.glsl).
const LAYERS := ["height", "flow", "wear", "deposition", "talus", "slope", "fresh", "crater_floor"]

## `features` is a hash of what was baked into the base before erosion (the crater list), so changing a planet's
## traits rebakes it instead of serving the old craters.
## `variant` names bake settings that differ from the defaults (a TerrainRecipe's bake multipliers), so two
## recipes on one seed never share an entry. Empty for default settings.
static func key(seed_value: int, width: int, height: int, features: int = 0, variant: String = "") -> String:
	var v := "" if variant == "" else "_" + variant
	return "%s/v%d_s%d_%dx%d_f%x%s.bin" % [DIR, FORMAT_VERSION, seed_value, width, height, features & 0xffffffff, v]

## Returns {"height": Image, "flow": Image, ...} or an empty Dictionary.
static func load_entry(seed_value: int, width: int, height: int, features: int = 0, variant: String = "") -> Dictionary:
	var path := key(seed_value, width, height, features, variant)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var out := {}
	for name in LAYERS:
		# Each layer stores its own dimensions: the height is full resolution and
		# the masks are downsampled, so one size for the file would be wrong for
		# four of the five layers.
		var lw := f.get_32()
		var lh := f.get_32()
		if lw <= 0 or lh <= 0 or lw > 65536 or lh > 65536:
			push_warning("ErosionCache: %s has a bad header at layer %s" % [path, name])
			return {}
		var expected := lw * lh * 4
		var raw := f.get_buffer(expected)
		if raw.size() != expected:
			# Truncated or written by an older build. Treat as a miss and let the
			# caller rebake rather than handing back half a planet.
			push_warning("ErosionCache: %s is incomplete at layer %s" % [path, name])
			return {}
		out[name] = Image.create_from_data(lw, lh, false, Image.FORMAT_RF, raw)
	return out

static func save_entry(seed_value: int, width: int, height: int,
		height_img: Image, masks: Dictionary, features: int = 0, variant: String = "") -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	_prune_old_versions()
	var path := key(seed_value, width, height, features, variant)
	# the same planet and recipe variant baked with an older feature list is dead weight (hundreds of MB): drop it
	# (other variants of the seed are other recipes and stay)
	var same := RegEx.create_from_string("^v%d_s%d_%dx%d_f[0-9a-f]+%s\\.bin$" % [
		FORMAT_VERSION, seed_value, width, height, "" if variant == "" else "_" + variant])
	var dir := DirAccess.open(DIR)
	if dir != null:
		for fname in dir.get_files():
			if same.search(fname) != null and DIR + "/" + fname != path:
				dir.remove(fname)
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("ErosionCache: cannot write %s" % path)
		return false
	for name in LAYERS:
		var img: Image = height_img if name == "height" else masks.get(name)
		if img == null:
			f.close()
			DirAccess.remove_absolute(path)
			return false
		f.store_32(img.get_width())
		f.store_32(img.get_height())
		f.store_buffer(img.get_data())
	f.close()
	return true

## Deletes entries written by an older FORMAT_VERSION.
##
## Without this every bump leaves its predecessor behind, and at a few hundred
## megabytes each the user accumulates a pile of terrain that can never be read
## again. Only stale VERSIONS are removed - other seeds at the current version
## are other planets and stay.
static func _prune_old_versions() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var prefix := "v%d_" % FORMAT_VERSION
	for f in dir.get_files():
		if f.begins_with("v") and not f.begins_with(prefix):
			dir.remove(f)

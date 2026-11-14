extends SceneTree

## Pre-compresses the terrain surface maps to BC7 (BPTC) with full mip chains, once, so the planet's 16-slot
## Texture2DArrays are built from GPU-ready layers instead of raw RGBA8. At 2048 px, 16 slots x 2 maps:
## RGBA8 ~680 MiB of VRAM, BC7 ~180 MiB (reports/AAA voxel terrain fidelity.md, "Budgets").
##     godot --headless --path . --script res://scripts/dev/compress_surfaces.gd [-- only=rock058]
## Reads data/textures/surfaces/<name>_alb.png / _nrm.png and data/textures/surfaces/scan/..., writes
## data/textures/surfaces/bc7/<name>_alb.res / _nrm.res
## (Image resources). Also writes the neutral layer used for empty slots. Re-run after packing new sets.
const SRC := "res://data/textures/surfaces"
const DST := "res://data/textures/surfaces/bc7"
const SIZE := 2048

func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	var n := 0
	for src in [SRC, SRC + "/scan"]:
		n += _compress_dir(src, only)
	_neutral()
	print("COMPRESS_DONE %d maps" % n)
	quit(0)

func _compress_dir(src: String, only: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(src):
		if not (f.ends_with("_alb.png") or f.ends_with("_nrm.png")):
			continue
		var name := f.trim_suffix(".png")
		if only != "" and not name.begins_with(only):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path("%s/%s" % [src, f]))
		if img == null:
			continue
		if img.get_width() != SIZE:
			# older 1024 generated sets: brought to the library size so any palette mixes them with scans in one
			# array format (arrays need equal size and format per layer)
			img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		if _write(img, name):
			n += 1
	return n

func _neutral() -> void:
	# neutral layers for empty slots: grey, rough / flat normal, open AO, mid height
	var alb := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	alb.fill(Color(0.42, 0.42, 0.43, 0.9))
	_write(alb, "neutral_alb")
	var nrm := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	nrm.fill(Color(0.5, 0.5, 1.0, 0.5))
	_write(nrm, "neutral_nrm")

func _write(img: Image, name: String) -> bool:
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var err := img.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_GENERIC)
	if err != OK:
		print("COMPRESS FAIL %s err %d" % [name, err])
		return false
	var path := "%s/%s.res" % [DST, name]
	ResourceSaver.save(img, path)
	print("COMPRESS %s %s %d bytes" % [name, img.get_format(), img.get_data_size()])
	return true

class_name SurfacePalette
extends RefCounted

## Builds the per-planet surface palette: a 16-slot parameter table plus the two
## texture arrays those slots index into.
##
## The mesher blends four material INDICES per voxel; this maps each index to a
## texture layer and a set of response values. Assembled per body from that
## body's own biomes and ores, so the same index can be two different rocks on
## two different planets - which is the point, because procedurally generated
## planets invent their own biome sets and cannot share a global table.
##
## Texture ARRAYS rather than separate textures: the shader has to look up
## whichever four indices the mesher happened to emit, and an array is the only
## way to do that without a branch per material.

const SLOTS := 16
const TEXTURE_DIR := "res://data/textures/surfaces"

## Built texture arrays are cached by their layer signature. Two planets sharing
## a biome set would otherwise each build and upload their own copy of the same
## 32 images, which is both slow and a straightforward waste of VRAM.
static var _array_cache: Dictionary = {}

static func _fallback_style() -> SurfaceStyle:
	var s := SurfaceStyle.new()
	s.display_name = "Unassigned"
	s.albedo_tint = Color(0.42, 0.42, 0.43)
	return s

## Fixed-function indices: not owned by any biome or ore, so they carry built-in
## styles. Bedrock and cliff rock are structural (depth and slope rules) and the
## construction block is placed by the player.
static func _builtin_styles() -> Dictionary:
	var bedrock := SurfaceStyle.new()
	bedrock.display_name = "Bedrock"
	bedrock.texture_name = "bedrock"
	bedrock.albedo_tint = Color(0.62, 0.62, 0.66)
	bedrock.texture_scale_m = 3.0
	bedrock.specular = 0.45

	var cliff := SurfaceStyle.new()
	cliff.display_name = "Cliff Rock"
	cliff.texture_name = "cliffrock"
	cliff.albedo_tint = Color(0.82, 0.81, 0.80)
	# Larger tiles: bedding on an exposed face reads at the scale of the face,
	# not at hand scale.
	cliff.texture_scale_m = 8.0
	cliff.normal_strength = 1.3
	cliff.specular = 0.45

	var block := SurfaceStyle.new()
	block.display_name = "Block"
	block.texture_name = "bedrock"
	block.albedo_tint = Color(1.25, 1.20, 0.92)
	block.roughness_scale = 0.55
	# Manufactured: almost no surface relief, which is what makes a placed block
	# read as built rather than grown.
	block.normal_strength = 0.15
	block.texture_scale_m = 2.0
	block.specular = 0.5

	return {
		VoxelMaterials.BEDROCK: bedrock,
		VoxelMaterials.CLIFF_ROCK: cliff,
		VoxelMaterials.CONSTRUCTION_BLOCK: block,
	}

## Collects styles for `body` into shader-ready arrays plus the texture arrays.
## Returns { tint_rough, extra, albedo_array, normal_array, names }.
static func build(body: CelestialBody) -> Dictionary:
	var styles: Dictionary = _builtin_styles()

	if body != null:
		for biome: Biome in body.biomes:
			if biome != null and biome.surface != null:
				styles[biome.stone_material_index] = biome.surface
		for ore: OreType in body.ore_types:
			if ore != null and ore.surface != null:
				styles[ore.material_index] = ore.surface

	var fallback := _fallback_style()
	var tint_rough := PackedVector4Array()
	var extra := PackedVector4Array()
	var names: Array[String] = []
	var texture_names: Array[String] = []

	for i in SLOTS:
		var style: SurfaceStyle = styles.get(i, fallback)
		var tr := style.tint_roughness()
		var ex := style.extra_params()
		tint_rough.append(Vector4(tr.x, tr.y, tr.z, tr.d))
		extra.append(Vector4(ex.x, ex.y, ex.z, ex.d))
		names.append(style.display_name if styles.has(i) else "-")
		texture_names.append(style.texture_name)

	var arrays := _build_texture_arrays(texture_names)
	return {
		"tint_rough": tint_rough,
		"extra": extra,
		"albedo_array": arrays["albedo"],
		"normal_array": arrays["normal"],
		"names": names,
		"textures": texture_names,
	}

## One `Texture2DArray` per map, with layer i holding material index i's texture.
##
## A missing or unbaked texture becomes a neutral layer rather than a failure:
## flat grey albedo, and a normal map that is "pointing straight up, fully lit,
## mid height". A broken layer must not make the terrain black or invisible,
## because that reads as a generator bug rather than as a missing asset.
static func _build_texture_arrays(texture_names: Array[String]) -> Dictionary:
	var key := "|".join(texture_names)
	if _array_cache.has(key):
		return _array_cache[key]

	var albedo_images: Array[Image] = []
	var normal_images: Array[Image] = []
	var size := 0

	# One pass to find the working size, so the placeholders match the real
	# layers - every layer of an array must share dimensions and format.
	for n in texture_names:
		if n == "":
			continue
		var img := _load_image("%s/%s_alb.png" % [TEXTURE_DIR, n])
		if img != null:
			size = img.get_width()
			break
	if size == 0:
		size = 64

	for n in texture_names:
		albedo_images.append(_load_layer("%s/%s_alb.png" % [TEXTURE_DIR, n], size,
			Color(0.42, 0.42, 0.43, 0.9)))
		normal_images.append(_load_layer("%s/%s_nrm.png" % [TEXTURE_DIR, n], size,
			Color(0.5, 0.5, 1.0, 0.5)))

	var albedo := Texture2DArray.new()
	albedo.create_from_images(albedo_images)
	var normal := Texture2DArray.new()
	normal.create_from_images(normal_images)

	var result := {"albedo": albedo, "normal": normal}
	_array_cache[key] = result
	return result

static func _load_image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	return img

static func _load_layer(path: String, size: int, fallback: Color) -> Image:
	var img := _load_image(path)
	if img == null:
		img = Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
		img.fill(fallback)
		return img
	if img.get_width() != size or img.get_height() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	# Mipmaps are not optional here. These are sampled triplanar at every range
	# from underfoot to the horizon, and without a mip chain the minified case
	# aliases into exactly the crawling speckle the procedural material spent so
	# long fighting.
	img.generate_mipmaps()
	return img

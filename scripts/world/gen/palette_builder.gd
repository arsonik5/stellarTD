class_name PaletteBuilder
extends RefCounted

## Trait mix -> the planet's ground materials in the 16 MIXEL4 slots, plus a colour-harmony report.
##
## Slot roles (VoxelMaterials): the dominant trait owns the base ground, secondary traits get the regional slots by
## weight, ores and the construction block keep their own styles.
##   0  STONE                surface of the dominant trait
##   8  STONE_FROZEN         regional slot 1   (strongest secondary trait, else the dominant's surface_alt)
##   9  STONE_SULFUR_FLATS   regional slot 2
##   10 STONE_CRYSTAL_FIELDS regional slot 3
##   11 CLIFF_ROCK           cliff rock of the dominant trait
##   12 BEDROCK              bedrock (dominant)
##   13 STRATA_A, 14 STRATA_B  depth bands (stage 3: what a dig reveals)
##   15 FRESH_CUT            what the drill leaves on a cut face (stage 3)
## The old slot names come from when those slots were hard-wired biomes; the role is what matters now.
##
## Harmony (reports/AAA voxel terrain fidelity.md, "Beauty is a separate goal"): colours are judged in OKLCH, the
## perceptual space where equal steps look equal. Rules:
##   - one saturation budget: only ACCENT traits may exceed BASE_CHROMA_MAX; at most one accent per planet
##   - the base ground (surface, cliff, bedrock) keeps a narrow lightness band so the accent reads
##   - accent hue analogous (within 45 deg) or complementary (180 +- 35) to the base hue, when the base has a hue
##   - the swatch at 64 px must show a clear base, mid and accent (lightness / chroma steps)

const STRATA_A := 13
const STRATA_B := 14
const FRESH_CUT := 15
const REGIONAL := [8, 9, 10]
const BASE_CHROMA_MAX := 0.06
const BASE_LIGHTNESS_SPREAD := 0.28

## -> {"styles": {index: SurfaceStyle}, "roles": {index: "trait/role"}, "report": {...}}
static func build(mix: Array) -> Dictionary:
	var styles := {}
	var roles := {}
	if mix.is_empty():
		return {"styles": styles, "roles": roles, "report": {"ok": false, "warnings": ["no traits"]}}
	var dom: PlanetTrait = mix[0].trait
	var put := func(idx: int, t: PlanetTrait, role: String, fallback_roles: Array) -> void:
		var s := t.material(role)
		var used := role
		for fr in fallback_roles:
			if s == null:
				s = t.material(fr)
				used = fr
		if s != null:
			styles[idx] = s
			roles[idx] = "%s/%s" % [t.id, used]
	put.call(VoxelMaterials.STONE, dom, "surface", [])
	put.call(VoxelMaterials.CLIFF_ROCK, dom, "cliff", ["bedrock", "surface"])
	put.call(VoxelMaterials.BEDROCK, dom, "bedrock", ["cliff", "surface"])
	put.call(STRATA_A, dom, "strata_a", ["bedrock", "cliff"])
	put.call(STRATA_B, dom, "strata_b", ["strata_a", "cliff"])
	put.call(FRESH_CUT, dom, "fresh_cut", ["cliff", "bedrock"])
	# regional slots: secondary traits by weight (their regional material, else their surface), then the dominant's
	# alternate surface so a single-trait planet still has variety
	var r := 0
	for i in range(1, mix.size()):
		if r >= REGIONAL.size():
			break
		var t: PlanetTrait = mix[i].trait
		if t.material("regional") != null or t.material("surface") != null:
			put.call(REGIONAL[r], t, "regional", ["surface"])
			r += 1
	while r < REGIONAL.size():
		put.call(REGIONAL[r], dom, "surface_alt" if r == 0 else "regional", ["surface"])
		r += 1
	return {"styles": styles, "roles": roles, "report": harmony(mix, styles)}

# --- harmony ---------------------------------------------------------------------------------------------------------
static func harmony(mix: Array, styles: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var base_idx := [VoxelMaterials.STONE, VoxelMaterials.CLIFF_ROCK, VoxelMaterials.BEDROCK]
	var lab := {}
	for idx in styles:
		lab[idx] = oklch(displayed_colour(styles[idx]))
	var base_l: Array[float] = []
	var base_h := 0.0
	var base_c := 0.0
	for idx in base_idx:
		if lab.has(idx):
			var c: Vector3 = lab[idx]
			base_l.append(c.x)
			if c.y > BASE_CHROMA_MAX:
				warnings.append("base slot %d too saturated (C %.3f > %.3f)" % [idx, c.y, BASE_CHROMA_MAX])
			if idx == VoxelMaterials.STONE:
				base_h = c.z
				base_c = c.y
	if base_l.size() >= 2:
		var spread: float = base_l.max() - base_l.min()
		if spread > BASE_LIGHTNESS_SPREAD:
			warnings.append("base lightness spread %.2f > %.2f (surface/cliff/bedrock fight)" % [spread, BASE_LIGHTNESS_SPREAD])
	var accents := 0
	for o in mix:
		var t: PlanetTrait = o.trait
		if t.accent or t.emissive:
			accents += 1
	if accents > 1:
		warnings.append("%d accent traits: only one may spend the saturation budget" % accents)
	for idx in REGIONAL:
		if not lab.has(idx):
			continue
		var c: Vector3 = lab[idx]
		if c.y > BASE_CHROMA_MAX and base_c > 0.015:
			var dh := absf(fposmod(c.z - base_h + 180.0, 360.0) - 180.0)
			if not (dh <= 45.0 or absf(dh - 180.0) <= 35.0):
				warnings.append("accent slot %d hue %.0f clashes with base hue %.0f (%.0f deg apart)" % [idx, c.z, base_h, dh])
	return {"ok": warnings.is_empty(), "warnings": warnings, "oklch": lab}

## The colour a material reads as from a distance (linear): SurfaceStyle.far_colour (scan mean, saturation, tint),
## or a mid grey x tint when its set has no stats yet.
static func displayed_colour(s: SurfaceStyle) -> Color:
	var f := s.far_colour()
	if f.d > 0.5:
		return Color(f.x, f.y, f.z)
	return Color(0.18 * s.albedo_tint.r, 0.18 * s.albedo_tint.g, 0.18 * s.albedo_tint.b)

## Linear sRGB -> OKLCH (L 0..1, C, h degrees). Björn Ottosson's OKLab.
static func oklch(c: Color) -> Vector3:
	var l := 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
	var m := 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
	var s := 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b
	l = pow(maxf(l, 0.0), 1.0 / 3.0)
	m = pow(maxf(m, 0.0), 1.0 / 3.0)
	s = pow(maxf(s, 0.0), 1.0 / 3.0)
	var L := 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
	var a := 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
	var b := 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	return Vector3(L, sqrt(a * a + b * b), fposmod(rad_to_deg(atan2(b, a)), 360.0))

## A palette swatch image (64 px per role, the thumbnail check): one square per filled slot, in slot order.
static func swatch(styles: Dictionary, px: int = 64) -> Image:
	var keys := styles.keys()
	keys.sort()
	var img := Image.create_empty(px * maxi(keys.size(), 1), px, false, Image.FORMAT_RGB8)
	for i in keys.size():
		var lin := displayed_colour(styles[keys[i]])
		img.fill_rect(Rect2i(i * px, 0, px, px), lin.linear_to_srgb())
	return img

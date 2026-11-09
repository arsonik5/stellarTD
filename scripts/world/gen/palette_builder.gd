class_name PaletteBuilder
extends RefCounted

## Trait mix -> the planet's ground materials in the 16 MIXEL4 slots, plus a colour-harmony report.
##
## Slot roles (the graph generator writes the same roles: PlanetGraphGenerator._build_trait_materials):
##   0  STONE        fine surface (dominant trait), where fines settle
##   8  SURFACE_ALT  open, worked ground (dominant)
##   9  SECONDARY_1  the strongest secondary trait's ground, in its regions
##   10 SCREE        talus / scree aprons (the dominant trait's coarse "regional" material)
##   11 CLIFF_ROCK   steep faces (dominant)
##   12 BEDROCK      deep rock, alternating with strata (dominant)
##   13 STRATA_A     strata bands below the topsoil (dominant)
##   14 SECONDARY_2  the second secondary trait's ground (else the dominant's second strata)
##   15 FRESH_CUT    what the drill leaves on a cut face
## Ores (1, 2, 4, 5, 6, 7) and the construction block (3) keep their own styles.
## Harmony (reports/AAA voxel terrain fidelity.md, "Beauty is a separate goal"): colours are judged in OKLCH, the
## perceptual space where equal steps look equal. Rules:
##   - one saturation budget: only ACCENT traits may exceed BASE_CHROMA_MAX; at most one accent per planet
##   - the base ground (surface, cliff, bedrock) keeps a narrow lightness band so the accent reads
##   - accent hue analogous (within 45 deg) or complementary (180 +- 35) to the base hue, when the base has a hue
##   - the swatch at 64 px must show a clear base, mid and accent (lightness / chroma steps)

const SURFACE_ALT := 8
const SECONDARY_1 := 9
const SCREE := 10
const STRATA_A := 13
const SECONDARY_2 := 14
const FRESH_CUT := 15
const REGIONAL := [9, 14]
const BASE_CHROMA_MAX := 0.06
const BASE_LIGHTNESS_SPREAD := 0.28

## -> {"styles": {index: SurfaceStyle}, "roles": {index: "trait/role"}, "cracks": {index: polygon size m},
##     "report": {...}}
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
	put.call(SURFACE_ALT, dom, "surface_alt", ["surface"])
	put.call(SCREE, dom, "regional", ["surface_alt", "surface"])
	put.call(VoxelMaterials.CLIFF_ROCK, dom, "cliff", ["bedrock", "surface"])
	put.call(VoxelMaterials.BEDROCK, dom, "bedrock", ["cliff", "surface"])
	put.call(STRATA_A, dom, "strata_a", ["bedrock", "cliff"])
	put.call(FRESH_CUT, dom, "fresh_cut", ["cliff", "bedrock"])
	# secondary traits' ground, in the order the generator gives them regions (replace-mode traits with a material)
	var r := 0
	for i in range(1, mix.size()):
		if r >= REGIONAL.size():
			break
		var t: PlanetTrait = mix[i].trait
		if t.material_mode == "replace" and (t.material("regional") != null or t.material("surface") != null):
			put.call(REGIONAL[r], t, "regional", ["surface"])
			r += 1
	if r < 2:
		put.call(SECONDARY_2, dom, "strata_b", ["strata_a", "cliff"])
	# contraction cracks (stage 4b): only on the flat-ground slots, from the trait that filled them
	var cracks := {}
	for idx in [VoxelMaterials.STONE, SURFACE_ALT, SECONDARY_1, SECONDARY_2]:
		if not roles.has(idx):
			continue
		var parts: PackedStringArray = String(roles[idx]).split("/")
		if parts.size() < 2 or not parts[1] in ["surface", "surface_alt", "regional"]:
			continue
		for o in mix:
			var t: PlanetTrait = o.trait
			if String(t.id) == parts[0] and t.crack_cell_m > 0.0:
				cracks[idx] = t.crack_cell_m
	return {"styles": styles, "roles": roles, "cracks": cracks, "report": harmony(mix, styles)}

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

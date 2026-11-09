class_name ScatterEngine
extends RefCounted

## Ground content from the planet's traits (stage 4a of reports/AAA voxel terrain fidelity.md). Every trait in the mix
## brings its asset lines (data/asset_lines/<id>.tres); each line becomes VoxelInstancer items, one per rock variant,
## placed by the same physical signals as the ground materials (the erosion masks), clumped, with deliberate bare
## stretches between clumps, only on the ground roles the line belongs on (material filter), sized by a skewed law
## (many small, few large), partly buried, and shaded to match the ground it lies on (scatter_rock.gdshader).
##
## godot_voxel removes instances when the ground under them is dug, and regenerates them by rule; saves store only
## the edits (HZD's "nothing baked" property).

const LINE_DIR := "res://data/asset_lines"
const ROCK_DIR := "res://data/models/rocks"
const RockShader := preload("res://scripts/world/scatter_rock.gdshader")

## Ground role names -> palette slots (PaletteBuilder).
const ROLE_SLOTS := {
	"fine": [0], "worked": [8], "scree": [10], "secondary": [9, 14], "cliff": [11], "strata": [13, 12],
}
const SKEW := {"linear": 0, "quadratic": 1, "cubic": 2, "quintic": 3}
const MAX_VARIANTS := 3
## Ground roles a line lies on when it doesn't say: every open ground role.
const DEFAULT_GROUND := ["fine", "worked", "scree", "secondary"]

static func _combos(variants: Array, slots: PackedInt32Array) -> Array:
	var out: Array = []
	for v in variants:
		for sl in slots:
			out.append([v, sl])
	return out

static func lines_for(mix: Array) -> Array:
	var out: Array = []
	var seen := {}
	for o in mix:
		var t: PlanetTrait = o.trait
		for lid in t.asset_lines:
			if seen.has(lid):
				seen[lid].weight = maxf(seen[lid].weight, float(o.weight))
				continue
			var p := "%s/%s.tres" % [LINE_DIR, lid]
			if not ResourceLoader.exists(p):
				continue                                           # a line that has no data yet (later stages)
			var e := {"line": load(p) as AssetLine, "weight": float(o.weight)}
			seen[lid] = e
			out.append(e)
	return out

## The near-field lines of a mix (NearScatter places these around the viewer).
static func near_lines(mix: Array) -> Array:
	return lines_for(mix).filter(func(e: Dictionary) -> bool: return (e.line as AssetLine).near_field)

## The instancer for `planet` (a Planet node), or null when its traits bring no lines with data.
static func build(planet: Node3D, body: CelestialBody, masks: Dictionary, terrain_mat: ShaderMaterial) -> VoxelInstancer:
	var mix := TraitMixer.of(body)
	if mix.is_empty():
		return null
	var lines := lines_for(mix)
	if lines.is_empty():
		return null
	var library := VoxelInstanceLibrary.new()
	var next_id := 1
	var report: Array[String] = []
	for e in lines:
		var line: AssetLine = e.line
		if line.near_field:
			continue                                               # NearScatter's
		var variants := _variants(line)
		if variants.is_empty():
			continue
		# every variant is one MultiMesh draw per terrain block it lands in, so a line keeps MAX_VARIANTS, picked by the
		# planet's seed: different planets still get different rocks, each pays a bounded draw count
		if variants.size() > MAX_VARIANTS:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([body.seed, String(line.id)])
			for i in range(variants.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = variants[i]
				variants[i] = variants[j]
				variants[j] = tmp
			variants = variants.slice(0, MAX_VARIANTS)
		# a secondary trait's lines are thinner, in proportion to how much of the planet it is
		var trait_scale := clampf(float(e.weight) / float(mix[0].weight), 0.25, 1.0)
		var per_variant := line.density * trait_scale / float(variants.size())
		# one item set per ground role it can lie on, each shaded to THAT ground (a boulder in dark volcanic gravel goes
		# dark, the same boulder on pale regolith stays light): the material filter picks the role, the material the colour
		var slots := PackedInt32Array()
		for role in (line.on_ground if not line.on_ground.is_empty() else DEFAULT_GROUND):
			for sl in ROLE_SLOTS.get(role, []):
				slots.append(sl)
		var vi := 0
		for combo in _combos(variants, slots):
			var v: Dictionary = combo[0]
			var slot: int = combo[1]
			var item := VoxelInstanceLibraryMultiMeshItem.new()
			item.name = "%s_%d" % [line.id, vi]
			item.lod_index = line.lod
			item.mesh = v.lod1 if (line.low_poly and v.lod1 != null) else v.mesh
			if v.lod1 != null and not line.low_poly:
				item.mesh_lod1 = v.lod1
				item.mesh_lod0_distance_ratio = line.view_ratio * 0.4
				item.mesh_lod1_distance_ratio = line.view_ratio
			else:
				item.mesh_lod0_distance_ratio = line.view_ratio
			item.hide_beyond_max_lod = line.view_ratio < 0.999
			item.cast_shadow = RenderingServer.SHADOW_CASTING_SETTING_ON if line.shadows else RenderingServer.SHADOW_CASTING_SETTING_OFF
			item.material_override = _material(v, line, planet, terrain_mat, slot)
			if line.collision:
				var hull := (v.mesh as Mesh).create_convex_shape(true, false)
				if hull != null:
					item.collision_layer = 1
					item.collision_mask = 1
					item.collision_shapes = [hull, Transform3D.IDENTITY]
					item.collision_distance = 60.0
			item.generator = _generator(line, body, masks, per_variant, float(v.span), vi % variants.size(), PackedInt32Array([slot]))
			library.add_item(next_id, item)
			next_id += 1
			vi += 1
		report.append("%s x%d (%.4f/m2)" % [line.id, variants.size(), line.density * trait_scale])
	if next_id == 1:
		return null
	var inst := VoxelInstancer.new()
	inst.name = "GroundScatter"
	inst.library = library
	inst.up_mode = VoxelInstancer.UP_MODE_SPHERE
	inst.fading_enabled = true
	TerrainLog.write("scatter", "%s: %s" % [body.display_name, ", ".join(report)])
	return inst

## Every rock mesh a line can use: data/models/rocks/<model>/game/*.glb (+ _lod1), with its native size.
static func _variants(line: AssetLine) -> Array:
	var out: Array = []
	for m in line.models:
		var dir := "%s/%s/game" % [ROCK_DIR, m]
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
			continue
		for f in DirAccess.get_files_at(dir):
			var fn := f.trim_suffix(".import")
			if not fn.ends_with(".glb") or fn.ends_with("_lod1.glb") or f.ends_with(".import"):
				continue
			var a := _load_mesh("%s/%s" % [dir, fn])
			if a.is_empty():
				continue
			var b := _load_mesh("%s/%s" % [dir, fn.trim_suffix(".glb") + "_lod1.glb"])
			var mesh: Mesh = a.mesh
			var sz := mesh.get_aabb().size
			out.append({"mesh": mesh, "lod1": b.get("mesh"), "material": a.material,
					"span": maxf(sz.x, maxf(sz.y, sz.z))})
	return out

## {mesh, material} of a .glb's first mesh; the material may sit on the MeshInstance (glTF import) rather than the mesh.
static func _load_mesh(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var sc := load(path) as PackedScene
	if sc == null:
		return {}
	var root := sc.instantiate()
	var mis := root.find_children("*", "MeshInstance3D", true, false)
	var out := {}
	if not mis.is_empty():
		var mi := mis[0] as MeshInstance3D
		out = {"mesh": mi.mesh, "material": mi.get_active_material(0)}
	root.free()
	return out

## The rock's own maps from its glTF material, plus the ground it lies on (the line's first ground role) from the
## planet's terrain material.
static func _material(v: Dictionary, line: AssetLine, planet: Node3D, terrain_mat: ShaderMaterial, ground_slot: int = -1) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RockShader
	var src := v.get("material") as BaseMaterial3D
	if src != null:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("normal_tex", src.normal_texture)
		if src.roughness_texture != null:
			m.set_shader_parameter("orm_tex", src.roughness_texture)
			m.set_shader_parameter("has_orm", true)
		m.set_shader_parameter("rock_mean", _mean_colour(src.albedo_texture))
	var slot := ground_slot
	if slot < 0:
		slot = int(ROLE_SLOTS.get(line.on_ground[0], [8])[0]) if not line.on_ground.is_empty() else 8
	if terrain_mat != null:
		var arr = terrain_mat.get_shader_parameter("tex_albedo")
		if arr is Texture2DArray:
			m.set_shader_parameter("terrain_albedo", arr)
			m.set_shader_parameter("has_terrain", true)
		else:
			TerrainLog.write("scatter", "no terrain albedo array yet for %s (got %s)" % [line.id, str(arr)])
		var far = terrain_mat.get_shader_parameter("pal_far")
		var tint = terrain_mat.get_shader_parameter("pal_tint_rough")
		var extra = terrain_mat.get_shader_parameter("pal_extra")
		if far is PackedVector4Array and slot < far.size():
			m.set_shader_parameter("ground_colour", Vector3(far[slot].x, far[slot].y, far[slot].z))
		if tint is PackedVector4Array and slot < tint.size():
			m.set_shader_parameter("ground_tint", Vector3(tint[slot].x, tint[slot].y, tint[slot].z))
		if extra is PackedVector4Array and slot < extra.size():
			m.set_shader_parameter("ground_tile_m", extra[slot].w)
	m.set_shader_parameter("ground_layer", slot)
	m.set_shader_parameter("planet_center", planet.global_position)
	m.set_shader_parameter("colour_match", line.colour_match)
	m.set_shader_parameter("dust", line.dust)
	var mean_size := (line.size_min_m + line.size_max_m) * 0.5
	m.set_shader_parameter("burial_m", line.burial * mean_size)
	# the ground-blend band scales with the rock: a fixed 18 cm swallowed whole pebbles into the ground colour
	m.set_shader_parameter("blend_height_m", clampf(mean_size * 0.25, 0.02, 0.4))
	return m

static func _mean_colour(tex: Texture2D) -> Vector3:
	if tex == null:
		return Vector3(0.4, 0.4, 0.4)
	var img := tex.get_image()
	if img == null:
		return Vector3(0.4, 0.4, 0.4)
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
	var acc := Vector3.ZERO
	for y in 8:
		for x in 8:
			var c := img.get_pixel(x, y).srgb_to_linear()
			acc += Vector3(c.r, c.g, c.b)
	return acc / 64.0

static func _generator(line: AssetLine, body: CelestialBody, masks: Dictionary, density: float, span: float,
		variant: int, filter_slots: PackedInt32Array = PackedInt32Array()) -> VoxelInstanceGenerator:
	var g := VoxelInstanceGenerator.new()
	g.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
	g.density = density
	g.min_scale = line.size_min_m / maxf(span, 0.01)
	g.max_scale = line.size_max_m / maxf(span, 0.01)
	g.scale_distribution = SKEW.get(line.size_skew, 2)
	g.random_rotation = true
	g.random_vertical_flip = false
	g.vertical_alignment = 1.0
	g.offset_along_normal = -line.burial * (line.size_min_m + line.size_max_m) * 0.5
	g.min_slope_degrees = line.slope_min_deg
	g.max_slope_degrees = line.slope_max_deg
	g.min_slope_falloff_degrees = 4.0
	g.max_slope_falloff_degrees = 6.0
	if not filter_slots.is_empty():
		g.voxel_texture_filter_enabled = true
		g.voxel_texture_filter_array = filter_slots
		g.voxel_texture_filter_threshold = 0.5                 # the dominant material: its colour is what the rock gets
	g.noise_graph = _placement_graph(line, body, masks, variant)
	g.noise_dimension = VoxelInstanceGenerator.DIMENSION_3D
	g.noise_threshold = 0.25
	g.noise_falloff = 0.2
	return g

## signal (erosion mask, remapped) x clumping field x rest field, evaluated on world position.
static func _placement_graph(line: AssetLine, body: CelestialBody, masks: Dictionary, variant: int) -> VoxelGraphFunction:
	var f := VoxelGraphFunction.new()
	var x := f.create_node(VoxelGraphFunction.NODE_INPUT_X, Vector2(0, 0))
	var y := f.create_node(VoxelGraphFunction.NODE_INPUT_Y, Vector2(0, 60))
	var z := f.create_node(VoxelGraphFunction.NODE_INPUT_Z, Vector2(0, 120))
	var value := [_k(f, 1.0), 0]
	var img: Image = masks.get(line.signal_mask) if line.signal_mask != "none" else null
	if img != null:
		# on the nominal sphere: see PlanetGraphGenerator.sample_mask_on_sphere (the node's early-out read 0 off it)
		var sig := PlanetGraphGenerator.sample_mask_on_sphere(f, x, y, z, img, Vector2(200, 0))
		var ss := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(400, 60))
		f.set_node_param(ss, 0, line.signal_low)
		f.set_node_param(ss, 1, line.signal_high)
		f.add_connection(sig[0], sig[1], ss, 0)
		value = [ss, 0]
		if line.signal_invert:
			value = _op(f, VoxelGraphFunction.NODE_SUBTRACT, [_k(f, 1.0), 0], value)
	# clumps: a noise field at the clump size, so a line comes in groups with ground between
	var clump := _noise(f, x, y, z, body.seed * 31 + String(line.id).hash() % 997 + variant * 7, 1.0 / maxf(line.clump_m, 1.0))
	var cl := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(600, 200))
	f.set_node_param(cl, 0, 0.5 - line.clump_cover)
	f.set_node_param(cl, 1, 0.5 - line.clump_cover + 0.45)
	f.add_connection(clump[0], clump[1], cl, 0)
	value = _op(f, VoxelGraphFunction.NODE_MULTIPLY, value, [cl, 0])
	# rest: big bare stretches shared by every line of the planet (same seed), so busy and empty alternate
	var rest := _noise(f, x, y, z, body.seed * 17 + 5, 1.0 / maxf(line.rest_m, 1.0))
	var rs := f.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(600, 320))
	f.set_node_param(rs, 0, -1.0 + line.rest_share * 2.0 - 0.2)
	f.set_node_param(rs, 1, -1.0 + line.rest_share * 2.0 + 0.2)
	f.add_connection(rest[0], rest[1], rs, 0)
	value = _op(f, VoxelGraphFunction.NODE_MULTIPLY, value, [rs, 0])
	var out := f.create_node(VoxelGraphFunction.NODE_CUSTOM_OUTPUT, Vector2(900, 120))
	f.add_connection(value[0], value[1], out, 0)
	return f

static func _k(f: VoxelGraphFunction, v: float) -> int:
	var n := f.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(0, 300))
	f.set_node_param(n, 0, v)
	return n

static func _op(f: VoxelGraphFunction, type_id: int, a: Array, b: Array) -> Array:
	var n := f.create_node(type_id, Vector2(500, 0))
	f.add_connection(a[0], a[1], n, 0)
	f.add_connection(b[0], b[1], n, 1)
	return [n, 0]

## Simplex noise on world position, -1..1 (2 octaves).
static func _noise(f: VoxelGraphFunction, x: int, y: int, z: int, seed_value: int, frequency: float) -> Array:
	var n := f.create_node(VoxelGraphFunction.NODE_FAST_NOISE_3D, Vector2(300, 300))
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.frequency = frequency
	fn.fractal_octaves = 2
	f.set_node_param(n, 0, fn)
	f.add_connection(x, 0, n, 0)
	f.add_connection(y, 0, n, 1)
	f.add_connection(z, 0, n, 2)
	return [n, 0]

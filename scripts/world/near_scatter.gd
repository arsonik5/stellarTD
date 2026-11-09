class_name NearScatter
extends Node

## Near-field ground cover: pebbles, gravel and clods within NEAR_RADIUS of the viewer, at real density (several per
## square metre), the way AAA games scatter grass and pebbles around the camera. The VoxelInstancer scatter
## (ScatterEngine) covers the whole finest terrain LOD, which on this planet is hundreds of metres across: at a pebble
## density there it would be a million instances nobody can see. Here, 12 m chunks follow the viewer; each chunk places
## its stones deterministically from the planet's seed onto the real terrain surface (physics raycast), keeping only
## those on the ground roles the line belongs on (the dominant material under each stone), clumped like the line says.
## Digging calls invalidate(), and the chunks around the bite are rebuilt once the new collider exists.
## reports/AAA voxel terrain fidelity.md, stage 4a.

const CHUNK := 12.0
const NEAR_RADIUS := 30.0
const BUILD_PER_FRAME := 2
const MAX_VARIANTS := 3
const REFRESH := 0.25

var planet: Node3D
var terrain: VoxelLodTerrain
var body: CelestialBody
var lines: Array = []            # [{line, weight, variants: [{mesh, material}], noise}]
var _chunks := {}                # Vector3i -> Array[MultiMeshInstance3D] (empty = no surface in this cell)
var _queue: Array[Vector3i] = []
var _timer := 0.0
var _dirty_at := {}              # Vector3i -> ticks when it may rebuild (after a dig)
var _far                         # the planet's per-slot far colours (PackedVector4Array), for each stone's ground
var stats := {"chunks": 0, "probe_hits": 0, "probe_miss": 0, "cand": 0, "hit": 0, "cell": 0, "clump": 0, "ground": 0, "slope": 0, "placed": 0, "other_collider": 0}

func setup(p: Node3D, t: VoxelLodTerrain, b: CelestialBody, near_lines: Array, terrain_mat: ShaderMaterial) -> void:
	planet = p
	terrain = t
	body = b
	_far = terrain_mat.get_shader_parameter("pal_far") if terrain_mat != null else null
	for e in near_lines:
		var line: AssetLine = e.line
		var vs := ScatterEngine._variants(line)
		if vs.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([b.seed, String(line.id), "near"])
		for i in range(vs.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = vs[i]
			vs[i] = vs[j]
			vs[j] = tmp
		vs = vs.slice(0, MAX_VARIANTS)
		var variants: Array = []
		for v in vs:
			var mat: Material = ScatterEngine._material(v, line, p, terrain_mat, -1, false)   # sunk per instance below
			(mat as ShaderMaterial).set_shader_parameter("ground_from_instance", true)
			variants.append({"mesh": v.lod1 if (line.low_poly and v.lod1 != null) else v.mesh, "material": mat,
					"span": v.span, "height": v.height})
		var n := FastNoiseLite.new()
		n.seed = b.seed * 31 + String(line.id).hash() % 997
		n.frequency = 1.0 / maxf(line.clump_m, 1.0)
		var slots := PackedInt32Array()
		var slot_density := {}
		for role in line.on_ground:
			for s in ScatterEngine.ROLE_SLOTS.get(role, []):
				slots.append(s)
				slot_density[s] = float(line.ground_density.get(role, 1.0))
		lines.append({"line": line, "weight": float(e.weight), "variants": variants, "noise": n, "slots": slots,
				"slot_density": slot_density})

## Rebuild the chunks around a bite (world position, metres) once the terrain has re-meshed there.
func invalidate(world_pos: Vector3, radius: float) -> void:
	var reach := radius + CHUNK
	for key in _chunks.keys():
		var c := (Vector3(key) + Vector3(0.5, 0.5, 0.5)) * CHUNK
		if c.distance_to(world_pos) < reach:
			_free_chunk(key)
			_dirty_at[key] = Time.get_ticks_msec() + 350

func _process(delta: float) -> void:
	if lines.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		# terrain collision streams in after the mesh: building before it exists cached the nearest chunks as empty
		var up := (eye - planet.global_position).normalized()
		if _ray(planet.get_world_3d().direct_space_state, eye, eye - up * 60.0).is_empty():
			return
		_expire_empty()
		_plan(eye)
	var built := 0
	while built < BUILD_PER_FRAME and not _queue.is_empty():
		var key: Vector3i = _queue.pop_front()
		if _chunks.has(key):
			continue
		if _dirty_at.has(key) and Time.get_ticks_msec() < int(_dirty_at[key]):
			_queue.append(key)
			break
		_dirty_at.erase(key)
		_chunks[key] = _build_chunk(key)
		if (_chunks[key] as Array).is_empty():
			_empty_since[key] = Time.get_ticks_msec()
		built += 1

func _plan(eye: Vector3) -> void:
	# drop far chunks, queue near missing ones, nearest first
	var c0 := Vector3i((eye / CHUNK).floor())
	var r := int(ceil(NEAR_RADIUS / CHUNK))
	for key in _chunks.keys():
		if ((Vector3(key) + Vector3(0.5, 0.5, 0.5)) * CHUNK).distance_to(eye) > NEAR_RADIUS + CHUNK * 1.5:
			_free_chunk(key)
	var want: Array = []
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			for z in range(-r, r + 1):
				var key := c0 + Vector3i(x, y, z)
				if _chunks.has(key) or _queue.has(key):
					continue
				var d := ((Vector3(key) + Vector3(0.5, 0.5, 0.5)) * CHUNK).distance_to(eye)
				if d <= NEAR_RADIUS + CHUNK * 0.9:
					want.append([d, key])
	want.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for w in want:
		_queue.append(w[1])

## Chunks found to have no surface are retried after a while (collision may have arrived since, or a dig opened one).
const EMPTY_RETRY_MS := 4000
var _empty_since := {}

func _expire_empty() -> void:
	var now := Time.get_ticks_msec()
	for key in _empty_since.keys():
		if now - int(_empty_since[key]) > EMPTY_RETRY_MS:
			_empty_since.erase(key)
			_chunks.erase(key)

func _free_chunk(key: Vector3i) -> void:
	if _chunks.has(key):
		for mmi in _chunks[key]:
			if is_instance_valid(mmi):
				mmi.queue_free()
		_chunks.erase(key)

func _build_chunk(key: Vector3i) -> Array:
	var out: Array = []
	var centre := (Vector3(key) + Vector3(0.5, 0.5, 0.5)) * CHUNK
	var up := (centre - planet.global_position).normalized()
	var space := planet.get_world_3d().direct_space_state
	# one probe through the cell: no surface in it, nothing to do (most cells of the cube are air or rock)
	stats.chunks += 1
	if _ray(space, centre + up * CHUNK, centre - up * CHUNK).is_empty():
		stats.probe_miss += 1
		return out
	stats.probe_hits += 1
	var t := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	var b := up.cross(t)
	var inv := terrain.global_transform.affine_inverse()
	# the ground's materials for this chunk, straight from the planet's generator: the LOD terrain keeps no voxel data
	# for ground nobody has edited, so reading it returned empty (material 0) everywhere
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := -lo
	for cx in 2:
		for cy in 2:
			for cz in 2:
				var corner := inv * ((Vector3(key) + Vector3(cx, cy, cz)) * CHUNK)
				lo = Vector3i(mini(lo.x, floori(corner.x)), mini(lo.y, floori(corner.y)), mini(lo.z, floori(corner.z)))
				hi = Vector3i(maxi(hi.x, ceili(corner.x)), maxi(hi.y, ceili(corner.y)), maxi(hi.z, ceili(corner.z)))
	lo -= Vector3i(1, 1, 1)
	var bsize := hi - lo + Vector3i(2, 2, 2)
	var mats := TerrainDrill._buffer(bsize)
	terrain.generator.generate_block(mats, lo, 0)
	for li in lines.size():
		var L: Dictionary = lines[li]
		var line: AssetLine = L.line
		var nvar: int = (L.variants as Array).size()
		var xforms: Array = []
		var colours: Array = []
		for v in nvar:
			xforms.append([])
			colours.append([])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([body.seed, key, String(line.id)])
		var trait_scale := clampf(float(L.weight), 0.25, 1.0)
		var count := int(line.density * trait_scale * CHUNK * CHUNK)
		for i in count:
			var u := rng.randf_range(-0.5, 0.5) * CHUNK
			var w := rng.randf_range(-0.5, 0.5) * CHUNK
			var roll := rng.randf()
			var size_t := rng.randf()
			var variant := rng.randi_range(0, nvar - 1)
			var spin := rng.randf() * TAU
			var start := centre + t * u + b * w + up * CHUNK
			stats.cand += 1
			var hit := _ray(space, start, start - up * CHUNK * 2.0)
			if hit.is_empty():
				continue
			stats.hit += 1
			var pos: Vector3 = hit.position
			if Vector3i((pos / CHUNK).floor()) != key:
				stats.cell += 1
				continue                                 # belongs to the neighbouring cell
			# clumps
			var cl := ((L.noise as FastNoiseLite).get_noise_3dv(pos) + 1.0) * 0.5
			if roll > smoothstep(0.5 - line.clump_cover, 0.95 - line.clump_cover, cl):
				stats.clump += 1
				continue
			# the ground under the stone: its role decides whether the line lies here, its colour shades the stone
			var lp := inv * (pos - (hit.normal as Vector3) * 0.4) - Vector3(lo)
			var q := Vector3i(clampi(roundi(lp.x), 0, bsize.x - 1), clampi(roundi(lp.y), 0, bsize.y - 1), clampi(roundi(lp.z), 0, bsize.z - 1))
			var m := TerrainDrill.dominant_from_packed(mats.get_voxel(q.x, q.y, q.z, VoxelBuffer.CHANNEL_INDICES),
					mats.get_voxel(q.x, q.y, q.z, VoxelBuffer.CHANNEL_WEIGHTS))
			if not (L.slots as PackedInt32Array).is_empty() and not (L.slots as PackedInt32Array).has(m):
				stats.ground += 1
				continue
			if rng.randf() > float((L.slot_density as Dictionary).get(m, 1.0)):
				stats.ground += 1
				continue
			var n: Vector3 = hit.normal
			if rad_to_deg(acos(clampf(n.dot(up), -1.0, 1.0))) > line.slope_max_deg:
				stats.slope += 1
				continue
			stats.placed += 1
			var size := lerpf(line.size_min_m, line.size_max_m, pow(size_t, float(ScatterEngine.SKEW.get(line.size_skew, 2)) + 1.0))
			var span: float = L.variants[variant].span
			var s := size / maxf(span, 0.01)
			var ny := n.lerp(up, 0.3).normalized()
			var nx := ny.cross(t if absf(ny.dot(t)) < 0.95 else b).normalized().rotated(ny, spin)
			var nz := nx.cross(ny)
			var basis := Basis(nx, ny, nz).scaled(Vector3(s, s, s))
			# sunk by a share of this stone's own height (not its span: a flat stone would vanish)
			xforms[variant].append(Transform3D(basis, pos - ny * line.burial * float(L.variants[variant].height) * s))
			var gc := Color(0.2, 0.2, 0.2, float(m) / 15.0)
			if _far is PackedVector4Array and m < (_far as PackedVector4Array).size():
				var f: Vector4 = _far[m]
				gc = Color(f.x, f.y, f.z, float(m) / 15.0)
			colours[variant].append(gc)
		for v in nvar:
			if (xforms[v] as Array).is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = L.variants[v].mesh
			mm.instance_count = (xforms[v] as Array).size()
			for k in mm.instance_count:
				mm.set_instance_transform(k, xforms[v][k])
				mm.set_instance_color(k, colours[v][k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = L.variants[v].material
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if line.shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			out.append(mmi)
	return out

func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return hit
	# only the terrain itself, not rocks, buildings or ships
	var c: Object = hit.collider
	if c == terrain or (c is Node and terrain.is_ancestor_of(c)):
		return hit
	stats.other_collider += 1
	return {}

## Total stones placed (tests).
func instance_count() -> int:
	var n := 0
	for key in _chunks:
		for mmi in _chunks[key]:
			if is_instance_valid(mmi):
				n += (mmi as MultiMeshInstance3D).multimesh.instance_count
	return n

class_name Rocket
extends Node3D

## Unguided rocket (Hydra-70 class, scaled for the game). Leaves the tube at the ship's velocity plus a push, burns
## its motor for BURN_S, then coasts. Radial gravity and air drag every tick from PlanetPhysics, so it drops and slows
## the same way everywhere on the planet. Fin-stabilised: the body always points along its velocity.
## Every tick sweeps a physics ray (near terrain, ships, buildings, enemies) and a voxel ray (terrain that has no
## collider yet, i.e. far LODs) from the old to the new position, so it can't tunnel.
## On impact: digs a crater, damages enemies (take_damage) and ships (Ship.apply_damage) inside the blast radius.
## predict() runs the same flight model with no side effects: the CCIP pipper uses it.

const LAUNCH_SPEED := 45.0          # m/s added by the tube's kick, along the tube
const BURN_S := 1.1
const BURN_ACCEL := 260.0           # m/s^2 while the motor burns: ~330 m/s at burnout
const MASS_KG := 6.2
const DRAG_CD := 0.25
const AREA := 0.0038                # 70 mm body
const MAX_LIFETIME := 18.0
const DAMAGE := 60.0
const BLAST_RADIUS := 4.0
const CRATER_RADIUS := 1.7
const SPREAD_DEG := 0.5             # unguided: each rocket leaves the tube up to this far off-axis

## Where the last rocket went off (tests and debug: compare with the CCIP prediction).
static var last_impact := Vector3.INF

var velocity := Vector3.ZERO
var _age := 0.0
var _exclude: Array[RID] = []
var _flame: MeshInstance3D
var _smoke: GPUParticles3D
var _light: OmniLight3D

## Fire one rocket from `muzzle` (global transform, -Z = tube axis). `carrier_velocity` is the ship's own velocity.
static func launch(parent: Node, muzzle: Transform3D, carrier_velocity: Vector3, exclude: Array[RID]) -> Rocket:
	var r := Rocket.new()
	var axis := -muzzle.basis.z.normalized()
	var off := deg_to_rad(randf() * SPREAD_DEG)
	var spin := randf() * TAU
	var side := axis.cross(muzzle.basis.y).normalized()
	axis = axis.rotated(side.rotated(axis, spin), off).normalized()
	r.velocity = carrier_velocity + axis * LAUNCH_SPEED
	r._exclude = exclude
	parent.add_child(r)
	r.global_position = muzzle.origin
	r._face(axis)
	return r

func _ready() -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = 1.1
	body.mesh = cyl
	body.rotation_degrees.x = 90.0                 # cylinder along -Z
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.56, 0.52)
	m.roughness = 0.6
	body.material_override = m
	add_child(body)
	_flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.06
	cone.height = 0.7
	_flame.mesh = cone
	_flame.rotation_degrees.x = -90.0
	_flame.position = Vector3(0, 0, 0.9)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.75, 0.35)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.6, 0.2)
	fm.emission_energy_multiplier = 4.0
	_flame.material_override = fm
	add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.3)
	_light.light_energy = 2.0
	_light.omni_range = 6.0
	_light.position = Vector3(0, 0, 0.9)
	add_child(_light)
	_smoke = _make_smoke()
	add_child(_smoke)

static func _smoke_material() -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.82, 0.82, 0.8, 0.55)
	sm.albedo_texture = _puff()
	return sm

## Soft round puff (radial falloff), shared by every smoke and dust sprite.
static var _puff_tex: Texture2D = null
static func _puff() -> Texture2D:
	if _puff_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_puff_tex = t
	return _puff_tex

func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 120
	p.lifetime = 2.2
	p.local_coords = false
	p.position = Vector3(0, 0, 0.7)
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.spread = 8.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.5))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.7))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.material = _smoke_material()
	p.draw_pass_1 = q
	return p

func _face(dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	var up := PlanetPhysics.get_up(global_position)
	if absf(dir.normalized().dot(up)) > 0.98:
		up = up.cross(Vector3.RIGHT).normalized()
	look_at(global_position + dir, up)

## One integration step of the flight model (shared with predict()).
static func step(pos: Vector3, vel: Vector3, age: float, dt: float) -> Vector3:
	var accel := PlanetPhysics.get_gravity_accel(pos)
	var speed := vel.length()
	if speed > 0.01:
		if age < BURN_S:
			accel += vel / speed * BURN_ACCEL
		var drag := 0.5 * PlanetPhysics.get_air_density(pos) * DRAG_CD * AREA * speed * speed
		accel -= vel / speed * (drag / MASS_KG)
	return vel + accel * dt

## Swept hit test between two points: physics first, then the voxel terrain (far LODs have no collider).
## Returns {} or {"position", "collider" (may be null), "terrain" (bool)}.
static func sweep(world: World3D, a: Vector3, b: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 0xFFFFFFFF, exclude)
	var hit := world.direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return {"position": hit["position"], "collider": hit["collider"], "terrain": false}
	var terrain := PlanetPhysics.get_nearest_terrain(a)
	if terrain == null:
		return {}
	var tool := terrain.get_voxel_tool()
	var inv := terrain.global_transform.affine_inverse()
	var seg := b - a
	var len := seg.length()
	if len < 0.001:
		return {}
	var r: VoxelRaycastResult = tool.raycast(inv * a, (inv.basis * seg).normalized(), len / terrain.scale.x)
	if r == null:
		return {}
	return {"position": terrain.global_transform * Vector3(r.position), "collider": terrain, "terrain": true}

## Where a rocket fired now would land (CCIP). Coarse steps; returns {"hit": bool, "position", "time"}.
static func predict(world: World3D, origin: Vector3, carrier_velocity: Vector3, axis: Vector3, exclude: Array[RID],
		max_time := 12.0, dt := 0.05) -> Dictionary:
	var pos := origin
	var vel := carrier_velocity + axis.normalized() * LAUNCH_SPEED
	var t := 0.0
	while t < max_time:
		var nv := step(pos, vel, t, dt)
		var np := pos + nv * dt
		var hit := sweep(world, pos, np, exclude)
		if not hit.is_empty():
			return {"hit": true, "position": hit["position"], "time": t}
		pos = np
		vel = nv
		t += dt
	return {"hit": false, "position": pos, "time": t}

func _physics_process(delta: float) -> void:
	_age += delta
	if _age > MAX_LIFETIME:
		queue_free()
		return
	if _age >= BURN_S and _flame.visible:
		_flame.visible = false
		_light.visible = false
		_smoke.emitting = false
	var prev := global_position
	velocity = step(prev, velocity, _age - delta, delta)
	var next := prev + velocity * delta
	var hit := sweep(get_world_3d(), prev, next, _exclude)
	if not hit.is_empty():
		_explode(hit)
		return
	global_position = next
	_face(velocity)

func _explode(hit: Dictionary) -> void:
	var p: Vector3 = hit["position"]
	Rocket.last_impact = p
	var collider: Object = hit.get("collider")
	# terrain: a crater (also when it hit something standing on the ground nearby)
	var terrain := PlanetPhysics.get_nearest_terrain(p)
	if terrain != null:
		Rocket.dig_crater(terrain, p, CRATER_RADIUS)
	# enemies: direct hit full damage, the rest by distance
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or not e.has_method("take_damage"):
			continue
		if e == collider:
			e.take_damage(DAMAGE)
			continue
		var d := e.global_position.distance_to(p)
		if d < BLAST_RADIUS:
			e.take_damage(DAMAGE * (1.0 - d / BLAST_RADIUS))
	# ships (any but the one that fired): damage the blocks inside the blast
	for n in get_tree().get_nodes_in_group("ship"):
		var s := n as Ship
		if s == null or s.get_rid() in _exclude:
			continue
		if s.global_position.distance_to(p) > BLAST_RADIUS + 20.0:
			continue
		var local := s.global_transform.affine_inverse() * p
		for cell: Vector3i in s.get_block_cells():
			var b := s.get_block(cell)
			if b == null:
				continue
			var d := b.position.distance_to(local)
			if d < BLAST_RADIUS:
				s.apply_damage(cell, DAMAGE * (1.0 - d / BLAST_RADIUS) * 0.25)
	Rocket.blast_fx(get_parent(), p)
	queue_free()

## Craters far from the player land on terrain that is only loaded at low detail, where the voxel engine refuses
## edits ("Area not editable"). Those wait in a queue and are dug as soon as their area becomes editable (the player
## comes closer). Not saved: a crater still waiting when the game is saved is lost.
static var _pending: Array = []                 # [terrain, world point, radius]
static var _queue_node: Node = null

static func dig_crater(terrain: Node3D, p: Vector3, radius: float) -> void:
	if not _try_dig(terrain, p, radius):
		_pending.append([terrain, p, radius])
		if _queue_node == null or not is_instance_valid(_queue_node):
			_queue_node = Timer.new()
			_queue_node.wait_time = 0.5
			_queue_node.autostart = true
			_queue_node.timeout.connect(Rocket._drain)
			terrain.get_tree().root.add_child.call_deferred(_queue_node)

static func _try_dig(terrain: Node3D, p: Vector3, radius: float) -> bool:
	var tool: VoxelTool = terrain.get_voxel_tool()
	var inv := terrain.global_transform.affine_inverse()
	var c := inv * p
	var r := radius / terrain.scale.x
	if not tool.is_area_editable(AABB(c - Vector3.ONE * (r + 1.0), Vector3.ONE * (2.0 * r + 2.0))):
		return false
	tool.channel = VoxelBuffer.CHANNEL_SDF
	tool.mode = VoxelTool.MODE_REMOVE
	tool.do_sphere(c, r)
	return true

static func _drain() -> void:
	var left: Array = []
	for e in _pending:
		if not is_instance_valid(e[0]):
			continue
		if not _try_dig(e[0], e[1], e[2]):
			left.append(e)
	_pending = left

## Explosion: a flash, a light that fades, a burst of smoke and dust.
static func blast_fx(parent: Node, p: Vector3) -> void:
	var fx := Node3D.new()
	parent.add_child(fx)
	fx.global_position = p
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.2
	flash.mesh = sphere
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(1.0, 0.8, 0.45, 0.9)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.55, 0.2)
	fm.emission_energy_multiplier = 6.0
	flash.material_override = fm
	fx.add_child(flash)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 10.0
	light.omni_range = 18.0
	fx.add_child(light)
	var dust := GPUParticles3D.new()
	dust.amount = 48
	dust.lifetime = 2.6
	dust.one_shot = true
	dust.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.gravity = -PlanetPhysics.get_up(p) * 3.0
	pm.scale_min = 1.0
	pm.scale_max = 2.4
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.47, 0.43, 0.8))
	g.set_color(1, Color(0.5, 0.47, 0.43, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	dust.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	q.material = _smoke_material()
	dust.draw_pass_1 = q
	fx.add_child(dust)
	# local "up" for the dust: point the emitter along planet up
	var up := PlanetPhysics.get_up(p)
	dust.look_at_from_position(p, p + up, up.cross(Vector3.RIGHT).normalized() if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD)
	dust.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	dust.emitting = true
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 2.2, 0.25)
	tw.tween_property(fm, "albedo_color:a", 0.0, 0.25)
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.chain().tween_interval(2.6)
	tw.chain().tween_callback(fx.queue_free)

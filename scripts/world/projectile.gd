class_name Projectile
extends Node3D

## Real ballistic simulation, not hitscan: semi-implicit Euler integration
## of gravity (PlanetPhysics, radial toward the planet center - consistent
## with the player's own gravity) plus quadratic aerodynamic drag driven by
## the current planet's air density (PlanetAtmosphere -> PlanetPhysics) and
## this specific round's mass/caliber/drag_coefficient. Every physics tick
## moves the visual mesh AND sweeps a physics raycast from the old to the
## new position (not a discrete point-in-time check) so a fast-moving round
## can't tunnel through a thin target in one step.

const MAX_LIFETIME := 6.0
const IMPACT_FLASH_LIFETIME := 0.15
const MIN_FLASH_RADIUS := 0.25

var velocity: Vector3 = Vector3.ZERO
var mass_kg: float = 0.05
var drag_coefficient: float = 0.3
var cross_section_area: float = 0.0003
var damage: float = 8.0
var splash_radius: float = 0.0
var splash_damage_falloff: float = 0.5

var _lifetime := 0.0
var _exclude_rid: RID = RID()

@onready var _mesh: MeshInstance3D = $MeshInstance3D
var _mesh_material: StandardMaterial3D

## Called once right after instancing, before or after add_child (only sets
## fields/mesh params, doesn't need to be in the tree yet). `firer_rid` is
## the launching Building's collision RID, excluded from the very first
## impact raycast so a round can't immediately self-hit the barrel/body it
## was just fired from.
func setup(initial_velocity: Vector3, ammo: AmmoType, firer_rid: RID) -> void:
	velocity = initial_velocity
	mass_kg = ammo.mass_kg
	drag_coefficient = ammo.drag_coefficient
	var radius := ammo.caliber_m * 0.5
	cross_section_area = PI * radius * radius
	damage = ammo.damage
	splash_radius = ammo.splash_radius
	splash_damage_falloff = ammo.splash_damage_falloff
	_exclude_rid = firer_rid

	var visual_radius := clampf(ammo.caliber_m * 4.0, 0.03, 0.25)
	var sphere := SphereMesh.new()
	sphere.radius = visual_radius
	sphere.height = visual_radius * 2.0
	_mesh.mesh = sphere
	_mesh_material.albedo_color = ammo.projectile_color
	_mesh_material.emission = ammo.projectile_color

func _ready() -> void:
	_mesh_material = StandardMaterial3D.new()
	_mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_material.emission_enabled = true
	_mesh.material_override = _mesh_material

func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		queue_free()
		return

	var prev_pos := global_position
	var gravity_accel := PlanetPhysics.get_gravity_accel(prev_pos)

	var speed := velocity.length()
	var accel := gravity_accel
	if speed > 0.01 and mass_kg > 0.0001:
		var drag_force := 0.5 * PlanetPhysics.get_air_density(prev_pos) * drag_coefficient * cross_section_area * speed * speed
		accel -= velocity.normalized() * (drag_force / mass_kg)

	velocity += accel * delta
	var new_pos := prev_pos + velocity * delta

	if prev_pos.distance_to(new_pos) > 0.0005:
		var space_state := get_world_3d().direct_space_state
		# A ternary between a literal array and [] infers as plain untyped
		# Array, not Array[RID] - assigning that to a typed var throws at
		# runtime ("Trying to assign an array of type Array to a variable of
		# type Array[RID]"), caught via a driven test. Build it imperatively
		# instead so it's unambiguously Array[RID] from the start.
		var exclude: Array[RID] = []
		if _exclude_rid.is_valid():
			exclude.append(_exclude_rid)
		var query := PhysicsRayQueryParameters3D.create(prev_pos, new_pos, 0xFFFFFFFF, exclude)
		var result := space_state.intersect_ray(query)
		if not result.is_empty():
			_resolve_impact(result)
			return

	global_position = new_pos

func _resolve_impact(result: Dictionary) -> void:
	var collider = result.get("collider")
	var hit_pos: Vector3 = result.get("position", global_position)
	# One damage contract (Health.deal): factions decide who is hurt, so turret rounds pass over friendly
	# buildings and alien rounds will hurt the base, with no per-target code here.
	var dtype := "explosive" if splash_radius > 0.0 else "kinetic"
	if collider != null:
		Health.deal(collider, damage, dtype, self, hit_pos)
	if splash_radius > 0.0:
		for node in get_tree().get_nodes_in_group("damageable"):
			if node == collider or not node is Node3D:
				continue
			if node.global_position.distance_to(hit_pos) <= splash_radius:
				Health.deal(node, damage * splash_damage_falloff, dtype, self, hit_pos)
	var hit_up := PlanetPhysics.get_up(hit_pos)
	if splash_radius > 0.0:
		WorldFx.burst("explosion", hit_pos, hit_up)
		WorldFx.sound("boom", hit_pos)
	else:
		WorldFx.burst("sparks", hit_pos, hit_up)
		WorldFx.sound("hit", hit_pos, 1.0, 0.06)
	if has_meta("crater_radius"):
		_crater(hit_pos, float(get_meta("crater_radius")))
	_spawn_impact_flash(hit_pos)
	queue_free()

## Orbital shells dig: a sphere of terrain removed where they land (saved like any other dig).
func _crater(at: Vector3, radius_m: float) -> void:
	var terrain := PlanetPhysics.get_nearest_terrain(at)
	if terrain == null:
		return
	var tool := terrain.get_voxel_tool()
	var local := terrain.to_local(at)
	var r := radius_m / maxf(terrain.scale.x, 0.0001)
	if not tool.is_area_editable(AABB(local - Vector3.ONE * r, Vector3.ONE * r * 2.0)):
		return
	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	tool.set_mode(VoxelTool.MODE_REMOVE)
	tool.do_sphere(local, r)

## Brief self-removing flash, sized to the splash radius for a splash round
## (so the AOE reads visually) or a small fixed size for a direct-hit round.
func _spawn_impact_flash(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = maxf(splash_radius, MIN_FLASH_RADIUS)
	sphere.height = sphere.radius * 2.0
	flash.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.3, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	get_tree().create_timer(IMPACT_FLASH_LIFETIME).timeout.connect(flash.queue_free)

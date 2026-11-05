class_name EnemyFlyer
extends RigidBody3D
## Base for alien raid craft (design C6 / roadmap G4): a real rigid body - mass, radial gravity, collisions, drag
## through PlanetPhysics - flown by a PD controller that outputs a force capped at MAX_ACCEL. Unlike player Ships
## it is not assembled from blocks (raiders arrive built), but it obeys the same physics: it can be knocked about,
## it falls when it dies, and its wreck lands where it actually came down.
##
## Subclasses set `goal` (world point) each physics frame from their own small state machine and call fire().
## Everything is body-local: "up" is PlanetPhysics.get_up(), never world Y.

signal died

@export var max_health := 60.0
@export var max_accel := 14.0         # m/s^2 the engines can give (on top of cancelling gravity)
@export var cruise_speed := 28.0
@export var turn_rate := 2.5
@export var wreck_alloy := 4           # alien alloy in the wreck it leaves
@export var kind := "raider"

var goal := Vector3.ZERO
## Where the nose should point (defaults to the velocity direction / goal).
var look_target := Vector3.INF
var dead := false
var health: Health

const WreckScene := preload("res://scenes/wreck.tscn")

func _ready() -> void:
	gravity_scale = 0.0
	can_sleep = false
	contact_monitor = false
	add_to_group("enemy")
	set_meta("enemy_kind", kind)
	set_meta("faction", "alien")
	health = Health.ensure(self, max_health, "alien")
	health.free_owner_on_death = false
	health.died.connect(_on_died)
	if goal == Vector3.ZERO:
		goal = global_position

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var g := PlanetPhysics.get_gravity_accel(global_position)
	if dead:
		state.apply_central_force(g * mass)       # engines out: it falls
		return
	# PD toward the goal, speed-limited; then cancel gravity; cap at the engines' authority
	var to_goal := goal - global_position
	var want_vel := to_goal * 0.8
	if want_vel.length() > cruise_speed:
		want_vel = want_vel.normalized() * cruise_speed
	var accel := (want_vel - state.linear_velocity) * 1.6
	if accel.length() > max_accel:
		accel = accel.normalized() * max_accel
	state.apply_central_force((accel - g) * mass + g * mass)
	# the force above = engines (accel - g) plus gravity (g): written out so the physics reads honestly
	# face the look target (or the direction of travel), rolling to keep the belly toward the ground
	var face_to := look_target if look_target != Vector3.INF else global_position + state.linear_velocity
	var fwd := face_to - global_position
	if fwd.length() > 0.5:
		var up := PlanetPhysics.get_up(global_position)
		var want := Basis.looking_at(fwd.normalized(), up if absf(fwd.normalized().dot(up)) < 0.98 else global_transform.basis.y)
		var cur := global_transform.basis.orthonormalized()
		var delta := (want * cur.inverse()).get_rotation_quaternion()
		var axis := delta.get_axis()
		var angle := delta.get_angle()
		if angle > PI:
			angle -= TAU
		if axis.is_finite() and absf(angle) > 0.001:
			state.angular_velocity = axis * angle * turn_rate
		else:
			state.angular_velocity = Vector3.ZERO

## Fire an alien bolt from `from` toward `target` (leading it by its velocity).
func fire_at(target: Node3D, from: Vector3, ammo: AmmoType) -> void:
	if target == null or not is_instance_valid(target):
		return
	var tp := target.global_position + Vector3(0, 0, 0)
	var tv: Vector3 = target.get("linear_velocity") if target is RigidBody3D else (target.get("velocity") if "velocity" in target else Vector3.ZERO)
	var t := from.distance_to(tp) / maxf(ammo.muzzle_velocity, 1.0)
	var aim := (tp + tv * t - from).normalized()
	var p: Node3D = preload("res://scenes/projectile.tscn").instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = from
	p.set_meta("faction", "alien")
	p.setup(aim * ammo.muzzle_velocity + linear_velocity, ammo, get_rid())

func _on_died(_src: Node) -> void:
	dead = true
	died.emit()
	# smoke + fall; the wreck replaces it when it hits the ground or after a few seconds
	angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0
	get_tree().create_timer(4.0).timeout.connect(_crash)

func _crash() -> void:
	if not is_inside_tree():
		return
	Wreck.spawn_at(get_tree().current_scene, global_position, wreck_alloy, kind)
	queue_free()

## Nearest player building (or the player) to `from`, for target selection.
static func nearest_player_target(tree: SceneTree, from: Vector3, include_player := true) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for b in tree.get_nodes_in_group("building"):
		var n := b as Node3D
		if n == null or not is_instance_valid(n) or n.is_queued_for_deletion() or n is Wreck:
			continue
		var d := n.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n
	if include_player:
		var p := tree.get_first_node_in_group("player") as Node3D
		if p != null:
			var v = p.get("vitals")
			var alive: bool = v == null or not v.dead
			if alive and p.global_position.distance_to(from) < best_d:
				best = p
	return best

## Alien hull material: near-black with a violet glow line - not the player's palette, readable as hostile.
static func hull_mat(glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.07, 0.11) if not glow else Color(0.85, 0.25, 0.95)
	m.metallic = 0.6
	m.roughness = 0.4
	if glow:
		m.emission_enabled = true
		m.emission = Color(0.85, 0.25, 0.95)
		m.emission_energy_multiplier = 2.5
	return m

static func part(parent: Node3D, mesh: Mesh, pos: Vector3, glow := false, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = hull_mat(glow)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

static func box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

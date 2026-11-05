class_name Gunship
extends EnemyFlyer
## Gunship (tier HUNTED+): strafing runs. Picks the nearest building (or the player), climbs to an attack lane
## ATTACK_ALT above it, dives along a pass that crosses over the target firing alien bolts while the nose is on
## it, then pulls out past it, swings round and comes again. Turrets kill it; its wreck can be salvaged.

const Bolt: AmmoType = preload("res://data/ammo_types/alien_bolt.tres")
const ATTACK_ALT := 26.0
const RUN_LENGTH := 70.0
const FIRE_INTERVAL := 0.45
const FIRE_CONE := 0.93        # cos of the half-angle the nose must be inside to fire
const FIRE_RANGE := 70.0

enum Phase { INGRESS, RUN, EGRESS }
var phase := Phase.INGRESS
var target: Node3D
var _cool := 0.0
var _run_from := Vector3.ZERO
var _run_to := Vector3.ZERO
var shots_fired := 0

func _init() -> void:
	max_health = 60.0
	max_accel = 16.0
	cruise_speed = 30.0
	wreck_alloy = 4
	kind = "gunship"

func _ready() -> void:
	super._ready()
	_build_model()

func _physics_process(delta: float) -> void:
	if dead:
		return
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		target = EnemyFlyer.nearest_player_target(get_tree(), global_position)
		if target == null:
			goal = global_position + PlanetPhysics.get_up(global_position) * 50.0
			return
		_plan_run()
	var up := PlanetPhysics.get_up(target.global_position)
	match phase:
		Phase.INGRESS:
			goal = _run_from
			look_target = target.global_position
			if global_position.distance_to(_run_from) < 12.0:
				phase = Phase.RUN
		Phase.RUN:
			goal = _run_to
			look_target = target.global_position if (target.global_position - global_position).dot(_run_to - _run_from) > 0.0 else Vector3.INF
			if global_position.distance_to(_run_to) < 14.0:
				phase = Phase.EGRESS
				_run_from = target.global_position + (global_position - target.global_position).normalized() * 30.0 + up * 45.0
		Phase.EGRESS:
			goal = _run_from
			look_target = Vector3.INF
			if global_position.distance_to(_run_from) < 14.0:
				_plan_run()
	_cool -= delta
	if phase == Phase.RUN and _cool <= 0.0:
		var to_t := target.global_position - global_position
		var nose := -global_transform.basis.z
		if to_t.length() < FIRE_RANGE and nose.dot(to_t.normalized()) > FIRE_CONE:
			fire_at(target, global_position + nose * 2.2, Bolt)
			shots_fired += 1
			_cool = FIRE_INTERVAL

## A lane across the target: start RUN_LENGTH/2 before it at attack altitude, end the same distance past it.
func _plan_run() -> void:
	phase = Phase.INGRESS
	var up := PlanetPhysics.get_up(target.global_position)
	var approach := global_position - target.global_position
	approach -= up * approach.dot(up)
	if approach.length() < 1.0:
		approach = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	approach = approach.normalized().rotated(up, randf_range(-0.6, 0.6))
	_run_from = target.global_position + approach * RUN_LENGTH * 0.5 + up * ATTACK_ALT
	_run_to = target.global_position - approach * RUN_LENGTH * 0.5 + up * (ATTACK_ALT * 0.6)

func _build_model() -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.0, 1.0, 5.0)
	cs.shape = sh
	add_child(cs)
	mass = 4000.0
	# dart hull, swept wings, twin cannon pods under the nose, violet engine glow at the tail
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(1.2, 0.8, 5.0)), Vector3.ZERO)
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(4.2, 0.15, 1.8)), Vector3(0, 0, 0.6))
	for x in [-0.5, 0.5]:
		EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(0.22, 0.22, 1.6)), Vector3(x, -0.45, -1.8))
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(1.0, 0.4, 0.2)), Vector3(0, 0, 2.55), true)

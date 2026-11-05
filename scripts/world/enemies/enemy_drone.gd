class_name EnemyDrone
extends CharacterBody3D
## Ground drone (dropped by dropships): walks over the surface to the nearest player building and cuts it apart
## (DPS through Health). Radial gravity like the player; moves on the local tangent plane toward the target; hops
## when blocked. Simple on purpose - the threat is that it reaches the machines, so walls and turrets matter.

const SPEED := 4.5
const ATTACK_RANGE := 2.6
const DPS := 9.0
const JUMP := 4.0

@export var max_health := 30.0
var target: Node3D
var _vspeed := 0.0
var _stuck := 0.0
var _last_pos := Vector3.ZERO
var health: Health

func _ready() -> void:
	add_to_group("enemy")
	set_meta("enemy_kind", "drone")
	set_meta("faction", "alien")
	health = Health.ensure(self, max_health, "alien")
	_build_model()

func _physics_process(delta: float) -> void:
	var up := PlanetPhysics.get_up(global_position)
	up_direction = up
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		target = EnemyFlyer.nearest_player_target(get_tree(), global_position, true)
	var g := PlanetPhysics.get_gravity_accel(global_position).length()
	if is_on_floor():
		_vspeed = 0.0
	else:
		_vspeed -= g * delta
	var move := Vector3.ZERO
	if target != null:
		var to := target.global_position - global_position
		var flat := to - up * to.dot(up)
		if flat.length() > ATTACK_RANGE:
			move = flat.normalized() * SPEED
			# face along the walk, upright on the sphere
			global_transform.basis = Basis.looking_at(flat.normalized(), up)
		else:
			Health.deal(target, DPS * delta, "kinetic", self)
	# stuck against something: hop
	if move.length() > 0.1 and is_on_floor():
		if global_position.distance_to(_last_pos) < SPEED * delta * 0.2:
			_stuck += delta
		else:
			_stuck = 0.0
		if _stuck > 0.6:
			_vspeed = JUMP
			_stuck = 0.0
	_last_pos = global_position
	velocity = move + up * _vspeed
	move_and_slide()

func _build_model() -> void:
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.45
	sh.height = 1.2
	cs.shape = sh
	cs.position = Vector3(0, 0.6, 0)
	add_child(cs)
	# squat body on four legs, a cutting arm forward, one violet sensor
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(0.9, 0.5, 1.1)), Vector3(0, 0.8, 0))
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(0.12, 0.6, 0.12)), Vector3(d.x * 0.45, 0.3, d.y * 0.5))
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(0.12, 0.12, 0.9)), Vector3(0.3, 0.85, -0.9))
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(0.2, 0.12, 0.08)), Vector3(0, 0.95, -0.56), true)

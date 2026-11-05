class_name Dropship
extends EnemyFlyer
## Dropship (tier CONTESTED+): flies to a landing point beside the base, settles onto the ground (radial raycast),
## unloads DRONES ground drones that walk to the machines, waits, then lifts off and leaves. Kill it before it
## lands and the drones never come out.

const DroneScene := preload("res://scenes/enemy_drone.tscn")
const DRONES := 3
const GROUND_TIME := 6.0

enum Phase { INBOUND, DESCEND, UNLOAD, DEPART }
var phase := Phase.INBOUND
var landing_point := Vector3.ZERO     # set by ThreatDirector: on the ground near the base
var exit_point := Vector3.ZERO
var drones_out := 0
var _timer := 0.0

func _init() -> void:
	max_health = 140.0
	max_accel = 10.0
	cruise_speed = 22.0
	wreck_alloy = 8
	kind = "dropship"

func _ready() -> void:
	super._ready()
	_build_model()
	if exit_point == Vector3.ZERO:
		exit_point = global_position

func _physics_process(delta: float) -> void:
	if dead:
		return
	var up := PlanetPhysics.get_up(landing_point)
	match phase:
		Phase.INBOUND:
			goal = landing_point + up * 30.0
			look_target = Vector3.INF
			if global_position.distance_to(goal) < 8.0:
				phase = Phase.DESCEND
		Phase.DESCEND:
			goal = landing_point + up * 1.8
			if global_position.distance_to(goal) < 1.5 and linear_velocity.length() < 2.0:
				phase = Phase.UNLOAD
				_timer = 0.0
		Phase.UNLOAD:
			goal = landing_point + up * 1.8
			_timer += delta
			if drones_out < DRONES and _timer > 0.8 * (drones_out + 1):
				_release_drone(up)
			if _timer >= GROUND_TIME:
				phase = Phase.DEPART
		Phase.DEPART:
			goal = exit_point
			if global_position.distance_to(exit_point) < 20.0:
				queue_free()

func _release_drone(up: Vector3) -> void:
	var d: Node3D = DroneScene.instantiate()
	get_tree().current_scene.add_child(d)
	var side := global_transform.basis.x * (drones_out - 1) * 1.6
	d.global_position = global_position - up * 0.8 + side + (-global_transform.basis.z) * 2.6
	drones_out += 1

func _build_model() -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.0, 2.4, 6.0)
	cs.shape = sh
	add_child(cs)
	mass = 9000.0
	# boxy troop bay, ramp at the front, four landing legs, lift-engine glow underneath
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(3.6, 2.2, 5.6)), Vector3.ZERO)
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(2.4, 0.15, 1.2)), Vector3(0, -0.9, -3.2), false, Vector3(-0.5, 0, 0))
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(0.25, 1.2, 0.25)), Vector3(d.x * 1.7, -1.4, d.y * 2.4))
	EnemyFlyer.part(self, EnemyFlyer.box_mesh(Vector3(2.8, 0.1, 4.4)), Vector3(0, -1.12, 0), true)

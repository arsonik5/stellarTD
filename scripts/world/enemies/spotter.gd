class_name Spotter
extends EnemyFlyer
## Spotter (tier SIEGE): hovers high over the base and calls orbital shells onto it, one every SHELL_INTERVAL,
## each a real projectile falling from altitude that craters the terrain and splashes buildings. The only way to
## stop the bombardment is to kill the spotter (it sits inside cannon range on purpose).

const Shell: AmmoType = preload("res://data/ammo_types/alien_shell.tres")
const HOVER_ALT := 60.0
const SHELL_INTERVAL := 7.0
const SHELL_DROP_ALT := 220.0
const CRATER_RADIUS_M := 3.0

var base_center := Vector3.ZERO
var shells_called := 0
var _timer := 3.0

func _init() -> void:
	max_health = 90.0
	max_accel = 8.0
	cruise_speed = 18.0
	wreck_alloy = 6
	kind = "spotter"

func _ready() -> void:
	super._ready()
	_build_model()

func _physics_process(delta: float) -> void:
	if dead:
		return
	var up := PlanetPhysics.get_up(base_center)
	goal = base_center + up * HOVER_ALT
	look_target = base_center
	_timer -= delta
	if _timer <= 0.0 and global_position.distance_to(goal) < 25.0:
		_timer = SHELL_INTERVAL
		call_shell(up)

func call_shell(up: Vector3) -> void:
	var target := EnemyFlyer.nearest_player_target(get_tree(), base_center + up.cross(Vector3.FORWARD).normalized() * randf_range(-12, 12), false)
	if target == null:
		return
	var p: Projectile = preload("res://scenes/projectile.tscn").instantiate()
	get_tree().current_scene.add_child(p)
	var aim_point := target.global_position + up.cross(Vector3.RIGHT).normalized() * randf_range(-4, 4)
	p.global_position = aim_point + up * SHELL_DROP_ALT
	p.set_meta("faction", "alien")
	p.set_meta("crater_radius", CRATER_RADIUS_M)
	p.setup(-up * Shell.muzzle_velocity, Shell, get_rid())
	shells_called += 1

func _build_model() -> void:
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.6
	cs.shape = sh
	add_child(cs)
	mass = 2500.0
	# a disc with a downward sensor eye: it watches and points, nothing else
	var disc := CylinderMesh.new()
	disc.top_radius = 1.8
	disc.bottom_radius = 1.2
	disc.height = 0.6
	EnemyFlyer.part(self, disc, Vector3.ZERO)
	var eye := SphereMesh.new()
	eye.radius = 0.5
	eye.height = 1.0
	EnemyFlyer.part(self, eye, Vector3(0, -0.45, 0), true)

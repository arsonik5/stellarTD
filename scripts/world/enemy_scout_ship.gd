class_name EnemyScoutShip
extends CharacterBody3D

## All enemies are starships, not ground troops (radiation-threat-design.md).
## Scope 1's only enemy: flies in from system edge, hovers near the crystal
## source to scan, then flees back out either silently (nothing found) or
## carrying a report (something found). Reaching flee_point while carrying a
## report is what actually matters - killing the scout before that point
## means the report never goes out, so the player has a real reason to hunt
## it down rather than just tank the eventual escalation. Targetable by the
## existing turret system with zero turret-side changes: same "enemy" group
## + take_damage() contract every enemy already uses (see enemy_dummy.gd).

signal died
## Emitted once, right before this node frees itself, when it reaches
## flee_point un-destroyed. `reported` is whether it found something worth
## telling the mothership about.
signal left_system(reported: bool)

@export var max_health: float = 25.0
@export var speed: float = 18.0
@export var scan_duration: float = 4.0
@export var arrival_distance: float = 4.0

## Set by ThreatDirector right after instantiation, before this node enters
## the tree - both are world-space points, not local offsets.
var scan_point: Vector3
var flee_point: Vector3

enum State { APPROACH, SCAN, FLEE }

var _state: State = State.APPROACH
var _scan_timer: float = 0.0
var _reported: bool = false
var _health: float
var _dead := false

func _ready() -> void:
	_health = max_health
	add_to_group("enemy")

func take_damage(amount: float) -> void:
	if _dead:
		return
	_health = maxf(_health - amount, 0.0)
	if _health <= 0.0:
		_dead = true
		died.emit()
		queue_free()

func _physics_process(delta: float) -> void:
	if _dead:
		return
	match _state:
		State.APPROACH:
			_fly_toward(scan_point)
			if global_position.distance_to(scan_point) <= arrival_distance:
				_state = State.SCAN
				_scan_timer = 0.0
		State.SCAN:
			velocity = Vector3.ZERO
			_scan_timer += delta
			if _scan_timer >= scan_duration:
				# Deeper into the Low band = more obviously "something's
				# leaking here" = more likely the scout actually finds it.
				_reported = randf() < RadiationSignature.low_tier_progress()
				_state = State.FLEE
		State.FLEE:
			_fly_toward(flee_point)
			if global_position.distance_to(flee_point) <= arrival_distance:
				left_system.emit(_reported)
				queue_free()

func _fly_toward(target: Vector3) -> void:
	var to_target := target - global_position
	velocity = to_target.normalized() * speed if to_target.length() > arrival_distance else Vector3.ZERO
	move_and_slide()
	var flat_facing := Vector3(velocity.x, 0.0, velocity.z)
	if flat_facing.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP)

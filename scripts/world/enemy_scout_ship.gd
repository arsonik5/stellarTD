class_name EnemyScoutShip
extends Ship

## All enemies are starships, not ground troops (radiation-threat-design.md).
## Flies in from system edge, hovers near the crystal source to scan, then
## flees back out either silently (nothing found) or carrying a report
## (something found). Reaching flee_point while carrying a report is what
## actually matters - killing the scout before that point means the report
## never goes out, so the player has a real reason to hunt it down rather
## than just tank the eventual escalation. Targetable by the existing
## turret system with zero turret-side changes: same "enemy" group +
## take_damage() contract every enemy already uses.
##
## Flies on the exact same Ship physics/steering every other ship (player
## included) uses - see ship-system-design.md. Its thrusters/gyroscope are
## hand-placed in enemy_scout_ship.tscn (not built through the player's
## in-game grid tool: enemies share the physics engine, not the
## construction tool), so this script only ever sets desired_linear_thrust/
## desired_angular_velocity each tick and lets the inherited Ship
## _integrate_forces() do the actual flying.

signal died
## Emitted once, right before this node frees itself, when it reaches
## flee_point un-destroyed. `reported` is whether it found something worth
## telling the mothership about.
signal left_system(reported: bool)

@export var max_health: float = 25.0
@export var arrival_distance: float = 4.0
@export var scan_duration: float = 4.0
@export var turn_gain: float = 3.0
@export var max_turn_rate: float = 1.5

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
	super._ready()
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

func _physics_process(_delta: float) -> void:
	if _dead:
		return
	match _state:
		State.APPROACH:
			_steer_toward(scan_point)
			if global_position.distance_to(scan_point) <= arrival_distance:
				_state = State.SCAN
				_scan_timer = 0.0
		State.SCAN:
			desired_linear_thrust = Vector3.ZERO
			desired_angular_velocity = Vector3.ZERO
			_scan_timer += _delta
			if _scan_timer >= scan_duration:
				# Deeper into the Low band = more obviously "something's
				# leaking here" = more likely the scout actually finds it.
				_reported = randf() < RadiationSignature.low_tier_progress()
				_state = State.FLEE
		State.FLEE:
			_steer_toward(flee_point)
			if global_position.distance_to(flee_point) <= arrival_distance:
				left_system.emit(_reported)
				queue_free()

func _steer_toward(target: Vector3) -> void:
	desired_linear_thrust = ShipSteering.seek(self, target)
	desired_angular_velocity = ShipSteering.face(self, target, turn_gain, max_turn_rate)

class_name ThreatDirector
extends Node3D

## Watches RadiationSignature and spawns Scope 1's scout ship when the
## player enters the Low tier - see radiation-threat-design.md. The bigger
## escalation fleet (Scope 2) and the High-tier constant-war state (Scope 3)
## both hang off signals already available here (leak_reported, or
## RadiationSignature.tier_changed firing HIGH) - neither is implemented
## yet, this only spawns the scout and reports the outcome.

signal leak_reported

@export var target_planet: Planet
@export var spawn_distance: float = 800.0
@export var scan_altitude: float = 60.0
@export var scout_scene: PackedScene = preload("res://scenes/enemy_scout_ship.tscn")
## Floor between scout spawns so signature hovering right at the Low
## threshold can't spam ships in and out.
@export var spawn_cooldown: float = 30.0

var _cooldown_remaining: float = 0.0
var _active_scout: EnemyScoutShip = null

func _ready() -> void:
	RadiationSignature.tier_changed.connect(_on_tier_changed)

func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta

func _on_tier_changed(_old_tier: RadiationSignature.Tier, new_tier: RadiationSignature.Tier) -> void:
	if new_tier == RadiationSignature.Tier.LOW:
		_try_spawn_scout()

func _try_spawn_scout() -> void:
	if _cooldown_remaining > 0.0 or is_instance_valid(_active_scout) or target_planet == null:
		return
	_cooldown_remaining = spawn_cooldown

	var planet_pos: Vector3 = target_planet.global_position
	var spawn_dir := Vector3(randf() - 0.5, randf() * 0.5, randf() - 0.5).normalized()
	var scan_dir := Vector3(randf() - 0.5, randf() * 0.5 + 0.2, randf() - 0.5).normalized()
	var surface_radius := target_planet.radius_world()

	var scout: EnemyScoutShip = scout_scene.instantiate()
	scout.scan_point = planet_pos + scan_dir * (surface_radius + scan_altitude)
	scout.flee_point = planet_pos + spawn_dir * spawn_distance
	scout.left_system.connect(_on_scout_left_system)
	get_tree().current_scene.add_child(scout)
	scout.global_position = scout.flee_point
	_active_scout = scout

func _on_scout_left_system(reported: bool) -> void:
	_active_scout = null
	if reported:
		leak_reported.emit()
		print("ThreatDirector: scout escaped with a report - escalation pending (Scope 2 not implemented yet)")

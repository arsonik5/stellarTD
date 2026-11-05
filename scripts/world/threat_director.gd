class_name ThreatDirector
extends Node3D

## Turns the signature tier into threats (design C6 / roadmap G4). Mixed by tier (decision 2026-11-04):
##   LOW (noticed)       a scout comes to look; if it escapes with a report the signature gains ALERT (they know)
##   MEDIUM (hunted)     gunship raids
##   HIGH (contested)    raids + a dropship landing ground drones
##   SIEGE               raids + dropships + a spotter calling orbital shells until it is shot down
## Raids come as WAVES WITH WARNING: GameEvents.wave_warning gives bearing, ETA and composition WARNING_TIME
## before they arrive, and there is always a calm between waves (pillar 3: prepare, then fight).
##
## Everything is placed relative to the base centre (centroid of player buildings, else the player) in the
## body's local frame: approach directions lie in the tangent plane, altitude is along radial up. No world Y.

signal leak_reported

@export var target_planet: Planet
@export var spawn_distance: float = 650.0
@export var spawn_altitude: float = 220.0
@export var scan_altitude: float = 60.0
@export var scout_scene: PackedScene = preload("res://scenes/enemy_scout_ship.tscn")
@export var spawn_cooldown: float = 90.0

const GunshipScene := preload("res://scenes/enemy_gunship.tscn")
const DropshipScene := preload("res://scenes/enemy_dropship.tscn")
const SpotterScene := preload("res://scenes/enemy_spotter.tscn")
const WARNING_TIME := 45.0
## Seconds between raid waves by tier (MEDIUM, HIGH, SIEGE). The wave clock only runs at MEDIUM or above.
const WAVE_INTERVAL := {2: 300.0, 3: 220.0, 4: 160.0}

var _cooldown_remaining: float = 0.0
var _active_scout: EnemyScoutShip = null
## Seconds until the next wave lands (counts down only while tier >= MEDIUM). -1 = no wave scheduled.
var wave_timer := -1.0
var wave_number := 0
var _warned := false
var _next_bearing := Vector3.ZERO
var _next_comp: Dictionary = {}
var enabled := true

func _ready() -> void:
	add_to_group("threat_director")
	RadiationSignature.tier_changed.connect(_on_tier_changed)
	leak_reported.connect(RadiationSignature.report_leak)

func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta
	if not enabled:
		return
	var tier := RadiationSignature.tier()
	if tier == RadiationSignature.Tier.LOW and not is_instance_valid(_active_scout) and _cooldown_remaining <= 0.0:
		_try_spawn_scout()
	if tier < RadiationSignature.Tier.MEDIUM:
		wave_timer = -1.0
		_warned = false
		return
	if wave_timer < 0.0:
		_schedule(tier)
	elif _next_comp.is_empty():
		# restored from a save mid-countdown: re-derive what is coming
		_next_comp = composition_for(tier, wave_number)
		_next_bearing = _random_tangent(base_center())
	wave_timer -= delta
	if not _warned and wave_timer <= WARNING_TIME:
		_warned = true
		GameEvents.wave_warning.emit(base_center() + _next_bearing * spawn_distance, maxf(wave_timer, 0.0), _next_comp)
	if wave_timer <= 0.0:
		launch_wave(_next_comp, _next_bearing)
		wave_timer = -1.0
		_warned = false

func _on_tier_changed(_old_tier: RadiationSignature.Tier, new_tier: RadiationSignature.Tier) -> void:
	if new_tier == RadiationSignature.Tier.LOW:
		_try_spawn_scout()

## Wave contents by tier and wave count: raids grow slowly the longer the base stays loud.
static func composition_for(tier: int, wave: int) -> Dictionary:
	var c := {"gunship": 0, "dropship": 0, "spotter": 0}
	if tier >= RadiationSignature.Tier.MEDIUM:
		c.gunship = 1 + mini(wave / 3, 3)
	if tier >= RadiationSignature.Tier.HIGH:
		c.dropship = 1 + mini(wave / 4, 2)
	if tier >= RadiationSignature.Tier.SIEGE:
		c.spotter = 1
	return c

func _schedule(tier: int) -> void:
	# the first wave after crossing into a raid tier gives a full warning window plus some calm
	wave_timer = float(WAVE_INTERVAL.get(tier, 300.0)) if wave_number > 0 else WARNING_TIME + 30.0
	_next_comp = composition_for(tier, wave_number)
	_next_bearing = _random_tangent(base_center())
	_warned = false

## The middle of what the player has built (or the player when nothing is built yet).
func base_center() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for b in get_tree().get_nodes_in_group("building"):
		if b is Building and not (b is Wreck) and is_instance_valid(b):
			sum += (b as Node3D).global_position
			n += 1
	if n > 0:
		return sum / n
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p.global_position if p != null else (target_planet.global_position if target_planet != null else Vector3.ZERO)

func _random_tangent(at: Vector3) -> Vector3:
	var up := PlanetPhysics.get_up(at)
	var t := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	return t.rotated(up, randf() * TAU)

## Spawn a wave now. Public so tests and debugging can call it directly. Returns the spawned enemies.
func launch_wave(comp: Dictionary, bearing: Vector3 = Vector3.ZERO) -> Array:
	var center := base_center()
	var up := PlanetPhysics.get_up(center)
	if bearing == Vector3.ZERO:
		bearing = _random_tangent(center)
	var origin := center + bearing * spawn_distance + up * spawn_altitude
	var out: Array = []
	var scene := get_tree().current_scene
	for i in int(comp.get("gunship", 0)):
		var g: Gunship = GunshipScene.instantiate()
		scene.add_child(g)
		g.global_position = origin + bearing.cross(up).normalized() * (i * 12.0)
		out.append(g)
	for i in int(comp.get("dropship", 0)):
		var d: Dropship = DropshipScene.instantiate()
		d.landing_point = _landing_point(center, up, bearing, i)
		d.exit_point = origin + up * 100.0
		scene.add_child(d)
		d.global_position = origin - bearing.cross(up).normalized() * (20.0 + i * 15.0)
		out.append(d)
	for i in int(comp.get("spotter", 0)):
		var s: Spotter = SpotterScene.instantiate()
		s.base_center = center
		scene.add_child(s)
		s.global_position = origin + up * 40.0
		out.append(s)
	wave_number += 1
	GameEvents.wave_started.emit(wave_number, out.size())
	return out

## On the ground on the raiders' side of the base, ~35 m out (radial raycast; falls back to the base height).
func _landing_point(center: Vector3, up: Vector3, bearing: Vector3, i: int) -> Vector3:
	var p := center + bearing * (35.0 + i * 10.0) + bearing.cross(up).normalized() * (i * 8.0)
	var q := PhysicsRayQueryParameters3D.create(p + up * 60.0, p - up * 80.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p

func _try_spawn_scout() -> void:
	if _cooldown_remaining > 0.0 or is_instance_valid(_active_scout) or target_planet == null:
		return
	_cooldown_remaining = spawn_cooldown
	var center := base_center()
	var up := PlanetPhysics.get_up(center)
	var scout: EnemyScoutShip = scout_scene.instantiate()
	scout.scan_point = center + up * scan_altitude
	scout.flee_point = center + _random_tangent(center) * spawn_distance + up * spawn_altitude
	scout.left_system.connect(_on_scout_left_system)
	get_tree().current_scene.add_child(scout)
	scout.global_position = scout.flee_point
	_active_scout = scout

func _on_scout_left_system(reported: bool) -> void:
	_active_scout = null
	if reported:
		leak_reported.emit()

func save_state() -> Dictionary:
	return {"wave_timer": wave_timer, "wave_number": wave_number}

func load_state(data: Dictionary) -> void:
	wave_timer = float(data.get("wave_timer", -1.0))
	wave_number = int(data.get("wave_number", 0))

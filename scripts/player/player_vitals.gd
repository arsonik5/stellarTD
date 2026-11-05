class_name PlayerVitals
extends Node
## Player survival layer (design/02-core-mechanics.md C9): health, fall damage, suffocation, death, respawn.
## A child of Player; kept out of player.gd so survival rules live in one small file.
##
## Death costs time, not items (open decision 3 in design/07-roadmap.md - backpack drop is the proposal):
## a short fade, then the player is back at the respawn point with full health and air.

## Landing faster than this (m/s along "down") hurts; FALL_LETHAL_SPEED kills from full health. Jumping lands at
## JUMP_VELOCITY (6 m/s) so normal play is far below the threshold.
const FALL_SAFE_SPEED := 10.0
const FALL_LETHAL_SPEED := 24.0
## Health per second lost with an empty suit (on top of the 40% move speed). ~67 s from full to dead: enough to
## reach a garage you can see, not enough to ignore.
const SUFFOCATION_DPS := 1.5
const RESPAWN_DELAY := 2.0

var health: Health
var player: CharacterBody3D
## Where the player comes back. Set at first landing, moved by respawn beacons (any node in "respawn_point").
var respawn_transform := Transform3D.IDENTITY
var has_respawn := false
var dead := false
var _respawn_timer := 0.0

func setup(p: CharacterBody3D) -> void:
	player = p
	health = Health.new()
	health.name = "Health"
	health.faction = "player"
	health.max_health = 100.0
	health.regen_delay = 6.0
	health.regen_rate = 4.0
	health.free_owner_on_death = false
	p.add_child(health)
	health.died.connect(_on_died)

func _physics_process(delta: float) -> void:
	if player == null:
		return
	# nothing ticks until the player has ground under them: a reloaded save streams terrain for many seconds,
	# and regeneration (or suffocation) during that wait would change the state that was just restored
	var live: bool = player.has_method("is_spawn_resolved") and player.is_spawn_resolved()
	health.set_process(live and not dead)
	if not live:
		return
	if dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn()
		return
	var o2 = player.get("suit_o2")
	if o2 != null and float(o2) <= 0.0:
		health.apply_damage(SUFFOCATION_DPS * delta, "env", null)

## Called by Player when it touches ground; `speed` is how fast it was falling (m/s, positive).
func on_landed(speed: float) -> void:
	if dead or speed <= FALL_SAFE_SPEED:
		return
	var t := (speed - FALL_SAFE_SPEED) / (FALL_LETHAL_SPEED - FALL_SAFE_SPEED)
	health.apply_damage(health.max_health * t, "env", null)

## First landing on a new game (and beacon use later) records where to come back to.
func remember_respawn(t: Transform3D) -> void:
	respawn_transform = t
	has_respawn = true

func _on_died(_source: Node) -> void:
	dead = true
	_respawn_timer = RESPAWN_DELAY
	var cause := "suffocation" if float(player.get("suit_o2")) <= 0.0 else "damage"
	GameEvents.player_died.emit(cause)
	if player.has_method("on_died"):
		player.on_died()

func respawn() -> void:
	dead = false
	var t := _best_respawn()
	player.global_transform = t
	player.velocity = Vector3.ZERO
	health.revive()
	if player.has_method("on_respawned"):
		player.on_respawned()
	GameEvents.player_respawned.emit()

## Nearest respawn beacon if any exist (buildings in group "respawn_point"), else the landing spot.
func _best_respawn() -> Transform3D:
	var best := respawn_transform
	var best_d := INF
	for n in player.get_tree().get_nodes_in_group("respawn_point"):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d := n3.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			var up := PlanetPhysics.get_up(n3.global_position)
			best = Transform3D(n3.global_transform.basis, n3.global_position + up * 1.2)
	return best

func save_state() -> Dictionary:
	return {
		"health": health.health,
		"respawn": SaveManager.transform_to_array(respawn_transform) if has_respawn else [],
	}

func load_state(data: Dictionary) -> void:
	health.health = clampf(float(data.get("health", health.max_health)), 1.0, health.max_health)
	var r: Array = data.get("respawn", [])
	if r.size() == 12:
		respawn_transform = SaveManager.array_to_transform(r)
		has_respawn = true

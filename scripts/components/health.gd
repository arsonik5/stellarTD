class_name Health
extends Node
## Health - the one damage contract (design/06-architecture.md A4).
##
## Anything that can be hurt carries a Health child: the player, buildings, enemies. Projectiles, explosions, falls
## and hazards all go through Health.deal(), so armour, factions, events and death work the same everywhere.
## Construct (ship) blocks keep their own per-block health inside ShipGrid; Health.deal() routes to them through
## the ship's apply_damage_at() so callers never need to know which kind of thing they hit.

signal damaged(amount: float, damage_type: String, source: Node)
signal healed(amount: float)
signal died(source: Node)

## Who this belongs to. Damage from a source of the same faction is ignored (no friendly fire), except "env"
## (falls, suffocation, hazards) which hurts everyone.
@export_enum("player", "alien", "neutral") var faction := "neutral"
@export var max_health := 100.0
## Flat reduction per hit (applied before resistances). Kinetic rounds feel this most.
@export var armour := 0.0
## Multipliers by damage type, e.g. {"explosive": 1.5}. Missing types = 1.0.
@export var resistances: Dictionary = {}
## Seconds after the last damage before regeneration starts; regen_rate is health per second. 0 = no regen.
@export var regen_delay := 5.0
@export var regen_rate := 0.0
## Free the owner automatically on death (enemies, buildings). The player handles its own death.
@export var free_owner_on_death := true

var health := 100.0
var _since_damage := 0.0
var _dead := false

func _ready() -> void:
	health = max_health
	set_process(regen_rate > 0.0)
	# splash damage and threat AI find damageable things through this group
	if get_parent() != null:
		get_parent().add_to_group("damageable")

func _process(delta: float) -> void:
	if _dead or health >= max_health:
		return
	_since_damage += delta
	if _since_damage >= regen_delay:
		heal(regen_rate * delta)

func is_dead() -> bool:
	return _dead

func fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0

## Returns the damage actually applied (0 when ignored: dead, friendly, fully armoured).
func apply_damage(amount: float, damage_type: String = "kinetic", source: Node = null) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	if damage_type != "env" and source != null and faction != "neutral" and _faction_of(source) == faction:
		return 0.0
	var dealt := maxf(amount - armour, 0.0) * float(resistances.get(damage_type, 1.0))
	if dealt <= 0.0:
		return 0.0
	dealt = minf(dealt, health)
	health -= dealt
	_since_damage = 0.0
	damaged.emit(dealt, damage_type, source)
	GameEvents.damaged.emit(get_parent(), dealt, damage_type, source)
	if health <= 0.0:
		_dead = true
		died.emit(source)
		GameEvents.destroyed.emit(get_parent(), source)
		if free_owner_on_death and get_parent() != null:
			get_parent().queue_free()
	return dealt

func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	var before := health
	health = minf(health + amount, max_health)
	if health > before:
		healed.emit(health - before)

## Bring back to full (respawn). Only meaningful when free_owner_on_death is false.
func revive(at_fraction: float = 1.0) -> void:
	_dead = false
	health = max_health * clampf(at_fraction, 0.0, 1.0)
	_since_damage = 0.0

## --- static helpers --------------------------------------------------------------------------------------------

## The Health on `node` or on one of its first few ancestors (a ray usually hits a child collider), or null.
static func of(node: Object) -> Health:
	var n := node as Node
	var depth := 0
	while n != null and depth < 4:
		if n is Health:
			return n
		var h := n.get_node_or_null("Health") as Health
		if h != null:
			return h
		n = n.get_parent()
		depth += 1
	return null

## Damage anything. `at` is the world hit position (constructs use it to find the block).
static func deal(target: Object, amount: float, damage_type: String = "kinetic", source: Node = null,
		at: Vector3 = Vector3.INF) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	var h := of(target)
	if h != null:
		return h.apply_damage(amount, damage_type, source)
	if at != Vector3.INF and target.has_method("apply_damage_at"):
		return target.apply_damage_at(at, amount)
	return 0.0

## Faction of whatever caused damage: its own Health, or a `faction` meta set on projectiles by their shooter.
static func _faction_of(source: Node) -> String:
	if source == null or not is_instance_valid(source):
		return ""
	if source.has_meta("faction"):
		return String(source.get_meta("faction"))
	var h := of(source)
	return h.faction if h != null else ""

## Convenience: add a Health child to `owner` if it has none. Returns it.
static func ensure(owner: Node, max_hp: float, owner_faction: String) -> Health:
	var h := owner.get_node_or_null("Health") as Health
	if h == null:
		h = Health.new()
		h.name = "Health"
		h.max_health = max_hp
		h.faction = owner_faction
		owner.add_child(h)
	return h

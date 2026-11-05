extends Node

## How "loud" the base is, and which threat tier that puts it in (design/02-core-mechanics.md C6, roadmap G4).
##
## signature = persistent sources + decaying spikes + alert - containment
##   persistent: crystal in the player's inventory (1 each), crystal stored in buildings (ore 0.5, cells 2 each),
##               anything in group "signature_source" (signature_contribution(), e.g. a loaded crystal reactor)
##   spikes:     GameEvents.signature_spike (uplink launches) and drilling crystal; halve every SPIKE_HALF_LIFE
##   alert:      a scout that escaped with a report adds ALERT_PER_REPORT; halves every ALERT_HALF_LIFE.
##               This is the "they know you are here" memory - it is what makes killing scouts matter.
##   containment: group "signature_damper" (damping()) subtracts, never below zero
##
## Tiers are the design's five, keeping the old enum names for the first three so Scope 1 code still reads:
##   NONE (quiet) < LOW (noticed: scouts) < MEDIUM (hunted: gunship raids) < HIGH (contested: + dropships)
##   < SIEGE (+ spotter-directed bombardment)

enum Tier { NONE, LOW, MEDIUM, HIGH, SIEGE }

const TIER_NAMES := ["QUIET", "NOTICED", "HUNTED", "CONTESTED", "SIEGE"]
const SIGNATURE_PER_CRYSTAL := 1.0
const STORED_CRYSTAL := 0.5
const STORED_CELL := 2.0
const CRYSTAL_MINED_SPIKE := 0.4
const LOW_TIER_MIN := 1.0
const MEDIUM_TIER_MIN := 10.0
const HIGH_TIER_MIN := 25.0
const SIEGE_TIER_MIN := 60.0
const SPIKE_HALF_LIFE := 120.0
const ALERT_HALF_LIFE := 600.0
const ALERT_PER_REPORT := 12.0
const RECOMPUTE_EVERY := 1.0

signal tier_changed(old_tier: Tier, new_tier: Tier)
signal changed

var spike := 0.0
var alert := 0.0
var _tier: Tier = Tier.NONE
var _value := 0.0
var _since := 0.0

func _ready() -> void:
	Inventory.changed.connect(recompute)
	GameEvents.signature_spike.connect(func(amount: float, _src: Node) -> void:
		add_spike(amount))
	GameEvents.item_mined.connect(func(id: String, n: int, _src: Node) -> void:
		if id == "ore_crystal":
			add_spike(CRYSTAL_MINED_SPIKE * n))
	FactoryClock.tick.connect(_on_tick)
	recompute()

func _on_tick(dt: float) -> void:
	spike *= pow(0.5, dt / SPIKE_HALF_LIFE)
	alert *= pow(0.5, dt / ALERT_HALF_LIFE)
	_since += dt
	if _since >= RECOMPUTE_EVERY:
		_since = 0.0
		recompute()

func add_spike(amount: float) -> void:
	spike += maxf(amount, 0.0)
	recompute()

## A scout got away with a report (ThreatDirector.leak_reported).
func report_leak() -> void:
	alert += ALERT_PER_REPORT
	recompute()

func signature() -> float:
	return _value

## Breakdown for the HUD and debugging: {held, stored, sources, spike, alert, damping}.
func breakdown() -> Dictionary:
	var held := Inventory.get_count("ore_crystal") * SIGNATURE_PER_CRYSTAL + Inventory.get_count("crystal_cell") * STORED_CELL
	var stored := 0.0
	var sources := 0.0
	var damping := 0.0
	var tree := get_tree()
	if tree != null:
		for b in tree.get_nodes_in_group("building"):
			if b is Building and is_instance_valid(b):
				stored += (b as Building).get_inventory_count("ore_crystal") * STORED_CRYSTAL
				stored += (b as Building).get_inventory_count("crystal_cell") * STORED_CELL
		for n in tree.get_nodes_in_group("signature_source"):
			if is_instance_valid(n) and n.has_method("signature_contribution"):
				sources += float(n.signature_contribution())
		for n in tree.get_nodes_in_group("signature_damper"):
			if is_instance_valid(n) and n.has_method("damping"):
				damping += float(n.damping())
	return {"held": held, "stored": stored, "sources": sources, "spike": spike, "alert": alert, "damping": damping}

func recompute() -> void:
	var b := breakdown()
	_value = maxf(b.held + b.stored + b.sources + b.spike + b.alert - b.damping, 0.0)
	var new_tier := tier_for(_value)
	if new_tier != _tier:
		var old_tier := _tier
		_tier = new_tier
		tier_changed.emit(old_tier, new_tier)
	changed.emit()

static func tier_for(value: float) -> Tier:
	if value >= SIEGE_TIER_MIN:
		return Tier.SIEGE
	if value >= HIGH_TIER_MIN:
		return Tier.HIGH
	if value >= MEDIUM_TIER_MIN:
		return Tier.MEDIUM
	if value >= LOW_TIER_MIN:
		return Tier.LOW
	return Tier.NONE

func tier() -> Tier:
	return _tier

func tier_name() -> String:
	return TIER_NAMES[_tier]

## Lower edge of the next tier up (for the HUD gauge), or the siege floor when already there.
func next_threshold() -> float:
	match _tier:
		Tier.NONE: return LOW_TIER_MIN
		Tier.LOW: return MEDIUM_TIER_MIN
		Tier.MEDIUM: return HIGH_TIER_MIN
		_: return SIEGE_TIER_MIN

## 0 at the low-tier floor, 1 at the medium floor - the scout's detection chance scales with it.
func low_tier_progress() -> float:
	return clampf((_value - LOW_TIER_MIN) / (MEDIUM_TIER_MIN - LOW_TIER_MIN), 0.0, 1.0)

func save_state() -> Dictionary:
	return {"spike": spike, "alert": alert}

func load_state(data: Dictionary) -> void:
	spike = float(data.get("spike", 0.0))
	alert = float(data.get("alert", 0.0))
	recompute()

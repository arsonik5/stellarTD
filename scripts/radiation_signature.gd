extends Node

## Single source of truth for how "loud" the player's crystal footprint is,
## and which threat tier that puts them in - see radiation-threat-design.md.
## Scope 1: signature is just crystal currently held (Inventory count). The
## dissolve machine's temporary burst (Scope 4) and containment dampening
## (Scope 5) both plug into this same value later; nothing else needs to
## change on their end, they just push/pull this number.

enum Tier { NONE, LOW, HIGH }

## Signature units, not item count directly - kept separate so a future
## "1 crystal = N signature" tuning knob doesn't need to touch thresholds.
const SIGNATURE_PER_CRYSTAL := 1.0
const LOW_TIER_MIN := 1.0
const HIGH_TIER_MIN := 25.0

signal tier_changed(old_tier: Tier, new_tier: Tier)

var _tier: Tier = Tier.NONE

func _ready() -> void:
	Inventory.changed.connect(_recompute)
	_recompute()

func signature() -> float:
	return Inventory.get_count("ore_crystal") * SIGNATURE_PER_CRYSTAL

func tier() -> Tier:
	return _tier

## 0 at the low-tier floor, 1 at the high-tier floor - how deep into the Low
## band the current signature sits. Used by the scout ship to scale its
## detection chance; meaningless outside the Low tier.
func low_tier_progress() -> float:
	return clampf((signature() - LOW_TIER_MIN) / (HIGH_TIER_MIN - LOW_TIER_MIN), 0.0, 1.0)

func _recompute() -> void:
	var s := signature()
	var new_tier: Tier = Tier.NONE
	if s >= HIGH_TIER_MIN:
		new_tier = Tier.HIGH
	elif s >= LOW_TIER_MIN:
		new_tier = Tier.LOW
	if new_tier != _tier:
		var old_tier := _tier
		_tier = new_tier
		tier_changed.emit(old_tier, new_tier)

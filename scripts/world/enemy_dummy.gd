class_name EnemyDummy
extends StaticBody3D

## Minimal damageable target so turrets (targeting/ammo/damage) can be built
## and verified before the real Slice 2 wave/AI system exists - NOT that
## system. No movement, no spawning, no AI: a stationary "enemy"-group node
## with health, for turrets to find via get_tree().get_nodes_in_group("enemy")
## and call take_damage() on. Whatever the real enemy scene ends up being
## later just needs the same group membership + take_damage() contract.

signal died

@export var max_health: float = 40.0

var health: float
var _dead := false

func _ready() -> void:
	health = max_health
	add_to_group("enemy")

func take_damage(amount: float) -> void:
	if _dead:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_dead = true
		died.emit()
		queue_free()

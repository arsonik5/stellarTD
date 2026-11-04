class_name ShipBlock
extends Node3D

## One block of a Ship - base class, used directly for plain hull filler (same convention as Chest using bare
## Building directly). ShipThruster/ShipGyroscope/ShipCockpit/ShipWheel subclass this for real behavior.
## A ShipBlock is meaningless outside a Ship: Ship._rebuild_stats() scans its own children for these on _ready()
## and whenever add_block()/remove_block() changes the set, whether they arrived via the in-game grid
## (player-built ships and vehicles) or were hand-placed in a .tscn (enemy ships).
##
## Grid: the Ship grid is 0.5 m cells (Ship.CELL_SIZE). A block fills `size_cells` of them: the classic 2 m blocks
## (hull, core, thruster, gyroscope, cockpit) are 4 x 4 x 4, the small vehicle parts 1 or 2 per side. Big blocks
## snap to the 2 m lattice, so small and big blocks line up and can be mixed on one ship.

@export var mass_kg: float = 50.0
@export var block_id: String = "ship_hull"
@export var max_health: float = 100.0
@export var armour: float = 0.0
@export var critical: bool = false
## How many 0.5 m cells the block fills along its own x, y, z.
@export var size_cells: Vector3i = Vector3i(4, 4, 4)
## Collision box (block-local, metres); zero = the whole cell box. Wheels only collide with their mount.
@export var collision_size: Vector3 = Vector3.ZERO
@export var collision_offset: Vector3 = Vector3.ZERO

var health: float

func _ready() -> void:
	health = max_health

## The cells it fills once rotated into the ship (rotations are quarter turns).
func ship_size() -> Vector3i:
	var s: Vector3 = (transform.basis * Vector3(size_cells)).abs()
	return Vector3i(roundi(s.x), roundi(s.y), roundi(s.z))

func is_operational() -> bool:
	return health > 0.0

func apply_damage(amount: float) -> float:
	if amount <= 0.0 or health <= 0.0:
		return 0.0
	var applied := minf(amount, health)
	health -= applied
	return applied

func repair(amount: float) -> float:
	if amount <= 0.0 or health >= max_health:
		return 0.0
	var restored := minf(amount, max_health - health)
	health += restored
	return restored

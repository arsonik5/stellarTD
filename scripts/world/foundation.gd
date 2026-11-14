class_name Foundation
extends StaticBody3D

## Flat plate players place to build an artificial local grid on a curved
## planet surface: every foundation snapped to a neighbor copies that
## neighbor's exact orientation (see player.gd's _foundation_snap_transform())
## instead of re-deriving its own from the terrain, so a whole connected
## cluster stays perfectly flat/square to itself no matter how the sphere
## curves underneath it. Origin is the block's CENTER (unlike Building's
## base-anchored origin convention) - see player.gd's mount-position math,
## which offsets by half of `height` either way from this center.
## The family (foundation, 1 m, 2 m, frame, ramp, stairs) shares SIZE; each scene sets its own height. Snapped
## neighbours line up their TOP faces. Ramps and stairs are not mountable (nothing stands on a slope).
const SIZE := 2.0
const HEIGHT := 0.25

@export var height := HEIGHT
@export var mountable := true

## Structural health: foundations are the walls and floors raids hit. Thicker blocks are tougher (G4: drones cut
## through what blocks them, so a wall is a delay you can stack). Destroyed = removed without refund.
@export var max_health := 0.0

func _ready() -> void:
	add_to_group("foundation")
	FoundationNetwork.register(self)
	var hp := Health.ensure(self, max_health if max_health > 0.0 else 200.0 + 400.0 * height, "player")
	hp.free_owner_on_death = false
	hp.died.connect(func(_src: Node) -> void: WorldObjects.remove(self))

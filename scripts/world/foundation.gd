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

func _ready() -> void:
	add_to_group("foundation")
	FoundationNetwork.register(self)

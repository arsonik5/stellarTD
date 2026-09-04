class_name Foundation
extends StaticBody3D

## Flat plate players place to build an artificial local grid on a curved
## planet surface: every foundation snapped to a neighbor copies that
## neighbor's exact orientation (see player.gd's _foundation_snap_transform())
## instead of re-deriving its own from the terrain, so a whole connected
## cluster stays perfectly flat/square to itself no matter how the sphere
## curves underneath it. Origin is the plate's CENTER (unlike Building's
## base-anchored origin convention) - see player.gd's mount-position math,
## which offsets by half of HEIGHT either way from this center.
const SIZE := 2.0
const HEIGHT := 0.25

func _ready() -> void:
	add_to_group("foundation")
	FoundationNetwork.register(self)

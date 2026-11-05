class_name PoiSpec
extends Resource
## One kind of point of interest an archetype can carry (W5). Sites are placed by Planet.poi_sites() - a
## deterministic sphere-spots field with a minimum ground spacing - and the scene is only instanced when the player
## comes near (PoiField). Gameplay hooks in through the group "poi" and the metas "poi_type" / "poi_id"
## (research data from probes, salvage from crash sites, crystal from spires).

@export var poi_type := "probe"
@export var display_name := "Continuance Probe"
## Relative frequency among the archetype's POIs.
@export var weight := 1.0
@export var scene: PackedScene
## Sink the scene's origin this far below the ground (metres) - a crashed pod is half buried, a probe stands on
## its feet.
@export var sink_m := 0.0

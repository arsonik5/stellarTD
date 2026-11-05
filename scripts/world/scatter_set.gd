class_name ScatterSet
extends Resource
## Rules for the instanced surface rocks of one archetype (W5, open item 5: "boulders read as random").
##
## Real rock debris is not spread evenly: it sits at the foot of what it broke off from (talus below cliffs),
## along broken edges, and in clumps - and it is rare on smooth sediment plains. The score that decides where
## boulders go is therefore built from the erosion bake's own TALUS and SLOPE masks, then clumped:
##   score = max(talus * talus_weight, smoothstep(slope, edge_start, edge_full) * edge_weight) * clump
## and an instance is emitted where the score passes `threshold`.

@export var enabled := true
## Instances per square metre before the mask (VoxelInstanceGenerator.density).
@export var density := 0.010
@export var size_min := 0.6
@export var size_max := 1.5
## Multiplies the rock textures' own albedo (cool grey-blue by default, matched to the regolith).
@export var tint := Color(0.776, 0.813, 0.900)
@export var talus_weight := 1.0
## Slope mask (0..1 = 0..90 deg) range over which a broken edge turns on.
@export var edge_start := 0.12
@export var edge_full := 0.32
@export var edge_weight := 0.85
## Clump field: metres between clump centres and how hard it gates (0 = no clumping, 1 = gaps between clumps).
@export var clump_m := 60.0
@export_range(0.0, 1.0) var clump_strength := 0.75
@export var threshold := 0.30
@export var falloff := 0.18
@export var min_slope_deg := 0.0
@export var max_slope_deg := 38.0

## The legacy rules (talus-only mask, mild variant modulation) - what shipped before W5, for A/B.
static func legacy() -> ScatterSet:
	var s := ScatterSet.new()
	s.edge_weight = 0.0
	s.clump_strength = 0.0
	s.min_slope_deg = 4.0
	s.max_slope_deg = 36.0
	s.falloff = 0.22
	return s

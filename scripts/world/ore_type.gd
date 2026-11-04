class_name OreType
extends Resource

## One diggable ore's complete generation spec - depth band, rarity, vein
## noise frequency. Replaces ore_generator.gd's old hardcoded per-ore
## fields/noise objects: adding a new ore is "add a new OreType resource,"
## not "add a new branch to the generator." See biome-system-design.md.

@export var id: String = ""
@export var material_index: int = 0
## Optional per-ore surface look. Ores are usually a colour change on the same
## rock, so leaving this null and letting the fallback apply is reasonable.
@export var surface: SurfaceStyle
@export_range(0.0, 200.0) var depth_min := 0.5
@export_range(0.0, 200.0) var depth_max := 10.0
## Higher = rarer.
@export_range(0.0, 1.0) var base_threshold := 0.25
## Lower = larger contiguous deposits (broader noise lobes); higher = smaller
## scattered pockets. This is the one knob that controls deposit size - no
## separate size parameter needed.
@export_range(0.01, 1.0) var noise_frequency := 0.08

class_name Biome
extends Resource

## One planetary region's material/ore identity, selected per-point by where
## (temperature, roughness) falls relative to this biome's declared range -
## see ore_generator.gd's _resolve_biome(). Never an exclusive ore gate:
## ore_bias only tilts rarity, per explicit design direction (biomes bias
## like Minecraft, they don't lock ores to one region). See
## biome-system-design.md for the full design.

@export var display_name: String = "Biome"

@export_group("Climate range")
@export_range(0.0, 1.0) var temperature_min := 0.0
@export_range(0.0, 1.0) var temperature_max := 1.0
@export_range(0.0, 1.0) var roughness_min := 0.0
@export_range(0.0, 1.0) var roughness_max := 1.0

@export_group("Surface")
## How this biome's stone looks on the ground. Null falls back to a neutral
## grey, so a biome with no style authored is visibly unfinished rather than
## silently borrowing someone else's rock.
@export var surface: SurfaceStyle

@export_group("Terrain")
@export var height_amplitude_mult := 1.0
@export var detail_amplitude_mult := 1.0
## Material index painted where no ore vein wins at this point - each biome
## gets its own "filler rock" look. Ore indices themselves stay
## biome-independent (see VoxelMaterials).
@export var stone_material_index: int = 0

@export_group("Ore bias")
## ore id -> rarity multiplier. >1 = more common here, <1 = rarer. A missing
## id means 1.0 (no change). Never drop to 0 - biomes tilt odds, they never
## exclude an ore outright.
@export var ore_bias: Dictionary = {}

## NOTE: ore_generator.gd's _generate_block() runs this same comparison
## inline off flat arrays rather than calling here - a cross-object call per
## surface voxel measured more expensive than the noise sampling it decides.
## Change both together, or biome borders will differ between the generator
## and anything else that asks a Biome directly.
##
## 0.0 = point sits inside this biome's range (best possible match).
## Positive = distance outside the range, in the same 0..1 climate units the
## temperature/roughness axes use - used both to pick the winning biome and,
## for the runner-up, to blend terrain amplitude smoothly across borders.
func climate_distance(temperature: float, roughness: float) -> float:
	var dt := 0.0
	if temperature < temperature_min:
		dt = temperature_min - temperature
	elif temperature > temperature_max:
		dt = temperature - temperature_max
	var dr := 0.0
	if roughness < roughness_min:
		dr = roughness_min - roughness
	elif roughness > roughness_max:
		dr = roughness - roughness_max
	return sqrt(dt * dt + dr * dr)

class_name CelestialBody
extends Resource

## Everything that makes one planet/moon different from another: terrain
## shape/seed, ore mix, and atmosphere. A new celestial body is a new .tres
## of this (plus a world-space position where its Planet instance gets
## placed) - never a copy of ore_generator.gd or world.gd with different
## numbers hardcoded in.

@export var display_name: String = "Planet"
@export var seed: int = 1

@export_group("Shape")
## LOCAL (voxel-grid) units, same convention ore_generator.gd always used -
## world-space meters = radius * Planet.VOXEL_SCALE.
@export_range(10.0, 50000.0) var radius: float = 100.0
## Two noise octaves shape the surface: broad hills/lowlands, then smaller
## bumps/craters on top so the sphere doesn't read as perfectly smooth.
@export_range(0.0, 4000.0) var height_amplitude: float = 6.0
@export_range(0.0, 1000.0) var detail_amplitude: float = 1.5

@export_group("Ore veins")
@export_range(0.0, 50.0) var ore_vein_depth_min: float = 0.5
@export_range(0.0, 100.0) var ore_vein_depth_max: float = 14.0
## Higher = rarer. Same five ore types everywhere for now (shared tech tree
## across planets) - what varies per body is how common each one is.
@export_range(0.0, 1.0) var ore_iron_threshold: float = 0.25
@export_range(0.0, 1.0) var ore_copper_threshold: float = 0.3
@export_range(0.0, 1.0) var ore_sulfur_threshold: float = 0.35
@export_range(0.0, 1.0) var ore_coal_threshold: float = 0.32
@export_range(0.0, 1.0) var ore_silica_threshold: float = 0.38
## Deliberately much rarer than the others - this is the objective resource
## the whole threat system reacts to, not a routine crafting ingredient.
@export_range(0.0, 1.0) var ore_crystal_threshold: float = 0.55

@export_group("World character")
## What this world IS (W4): terrain recipe, biomes, palette, scatter, points of interest. Null = default recipe,
## the body's own biomes, legacy boulders, no POIs.
@export var archetype: PlanetArchetype
## Terrain character as data (W1). Null = the default recipe. The archetype's recipe wins over this.
@export var terrain_recipe: TerrainRecipe

@export_group("Shape - baked heightmap")
## Optional. When set, this body's LARGE-SCALE shape comes from a baked,
## eroded heightmap instead of from height_amplitude/detail_amplitude noise,
## and the noise fields above are demoted to sub-pixel detail on top of it.
##
## This is the Space Engineers 2 arrangement (heightmap-first, 3D voxel detail
## layered over it) and it is the only way to get real drainage networks and
## river valleys - those come from iterative erosion, which cannot be
## evaluated per-block on demand. Bake with tools/bake_planet_heightmap.py.
##
## Leaving it null keeps the pre-heightmap pure-noise behaviour exactly, so
## bodies migrate one at a time.
@export var heightmap: PlanetHeightmap

@export_group("Atmosphere")
@export var atmosphere: PlanetAtmosphere

@export_group("Biomes")
## Empty = legacy behavior (single shared depth band + the ore_*_threshold
## fields above, exactly as before biomes existed) - never a regression risk
## for a body that hasn't been migrated yet. See biome-system-design.md.
@export var ore_types: Array[OreType] = []
@export var biomes: Array[Biome] = []
## A point in (temperature, roughness) space that shifts the whole climate
## noise field's center - (0.5, 0.5) is neutral/unbiased. One number turns a
## body "mostly ice moon" or "mostly volcanic" without touching biome
## definitions themselves.
@export var climate_bias := Vector2(0.5, 0.5)

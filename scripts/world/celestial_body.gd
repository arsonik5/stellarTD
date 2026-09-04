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
@export_range(10.0, 2000.0) var radius: float = 100.0
## Two noise octaves shape the surface: broad hills/lowlands, then smaller
## bumps/craters on top so the sphere doesn't read as perfectly smooth.
@export_range(0.0, 100.0) var height_amplitude: float = 6.0
@export_range(0.0, 20.0) var detail_amplitude: float = 1.5

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

@export_group("Atmosphere")
@export var atmosphere: PlanetAtmosphere

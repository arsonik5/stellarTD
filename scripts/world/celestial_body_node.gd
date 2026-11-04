class_name CelestialBodyNode
extends Node3D

## Shared base for everything that occupies a place in the star system and
## pulls on things: planets, moons, and the star itself.
##
## This exists because a star IS a celestial body - it has a position, a
## radius, and gravity - and giving it a parallel implementation would be
## exactly the drift this project's architecture rules exist to prevent.
## `PlanetPhysics` registers and queries through this type, so it no longer
## knows or cares whether a given body happens to have terrain.
##
## Subclasses override what they actually have. The defaults here describe a
## body with no atmosphere, no terrain and no light output, so a subclass only
## has to implement the parts that make it different.

func _ready() -> void:
	add_to_group("celestial_body")
	PlanetPhysics.register_body(self)

func _exit_tree() -> void:
	PlanetPhysics.unregister_body(self)

## Surface radius in world metres.
func radius_world() -> float:
	return 0.0

## Acceleration due to this body at its own surface, m/s^2.
func surface_gravity() -> float:
	return 0.0

## Standard gravitational parameter (mu = g * r^2). Gravity at distance d is
## mu / d^2, so expressing it this way is what lets bodies of very different
## sizes be summed against each other without a mass unit anywhere.
func gravitational_parameter() -> float:
	var r := radius_world()
	return surface_gravity() * r * r

## How far out this body's *non-gravitational* influence reaches - which body
## owns the "up" direction, whose atmosphere you are in, whose terrain a dig
## ray should hit. Gravity is no longer cut off at this radius (it is summed
## over all bodies now), so this is purely about local frame resolution.
func influence_radius() -> float:
	return radius_world() * 4.0

## How far this body's terrain can deviate from its nominal radius, in world
## metres. Anything that needs to find the actual ground - spawn probes, LOD
## budgeting, camera framing - has to work in terms of this rather than
## assuming the surface sits at radius_world().
func max_relief_world() -> float:
	return 0.0

func atmosphere() -> PlanetAtmosphere:
	return null

## World-space radius of the top of the atmosphere shell, falling back to the
## surface radius for bodies with no atmosphere.
func atmosphere_radius_world() -> float:
	var atmo := atmosphere()
	return radius_world() * atmo.shell_radius_ratio if atmo != null else radius_world()

func atmosphere_height_world() -> float:
	return atmosphere_radius_world() - radius_world()

## kg/m^3 at a world position. Zero for airless bodies and for the void.
func air_density_at(_pos: Vector3) -> float:
	return 0.0

## Radiant flux this body emits at a world position, in W/m^2. Non-zero only
## for stars. Consumed by the atmosphere renderer for sunlight strength, and
## reserved for the heat-damage system that isn't built yet - the interface
## exists now so adding that later isn't an architectural change.
func irradiance_at(_pos: Vector3) -> float:
	return 0.0

## This body's voxel terrain, or null if it has none (stars, gas bodies).
func terrain_node() -> VoxelNode:
	return null

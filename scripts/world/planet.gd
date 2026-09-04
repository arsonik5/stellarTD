class_name Planet
extends Node3D

## One celestial body's terrain: wraps a VoxelTerrain child, builds a
## generator from this Planet's own CelestialBody (radius/seed/ore mix), and
## registers itself with PlanetPhysics so gravity/atmosphere/dig-target
## resolution all pick the nearest Planet automatically. Adding a second
## planet to the game is "instance this scene again with a different
## CelestialBody at a different position" - no new script, no touching this
## one, no touching PlanetPhysics.

## World-space size of one voxel, in meters. VoxelTerrain's `bounds` is in
## LOCAL (voxel-grid) units, which this node's `scale` does NOT rescale.
const VOXEL_SCALE := 0.4
## Margin (LOCAL units) added around the body's own radius/noise/ore-depth
## extent so streaming bounds never clip terrain generation or dig tunnels.
const BOUNDS_MARGIN := 20.0

const OreGenerator := preload("res://scripts/world/ore_generator.gd")
const DebugMaterial := preload("res://scripts/world/voxel_debug_material.tres")

@export var body: CelestialBody

@onready var terrain: VoxelTerrain = $Terrain

func _ready() -> void:
	add_to_group("planet")

	terrain.generator = OreGenerator.new(body)

	# TEXTURES_SINGLE_S4 needs an 8-bit indices channel to actually emit per-vertex
	# material data; the default format (16-bit) silently produces blank texturing.
	var format := VoxelFormat.new()
	format.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_8_BIT)
	terrain.format = format

	var mesher := VoxelMesherTransvoxel.new()
	mesher.texturing_mode = VoxelMesherTransvoxel.TEXTURES_SINGLE_S4
	terrain.mesher = mesher

	terrain.material_override = DebugMaterial
	terrain.generate_collisions = true
	terrain.scale = Vector3.ONE * VOXEL_SCALE

	# Cube bounds (LOCAL units, already the generator's own coordinate space)
	# sized to contain this body's whole solid sphere plus its height noise
	# and ore-vein depth - read straight from `body` so it can never drift
	# out of sync with what the generator itself is actually shaping.
	var half_extent := body.radius + body.height_amplitude + body.detail_amplitude + body.ore_vein_depth_max + BOUNDS_MARGIN
	terrain.bounds = AABB(
		Vector3.ONE * -half_extent,
		Vector3.ONE * half_extent * 2.0
	)

	PlanetPhysics.register_body(self)

func _exit_tree() -> void:
	PlanetPhysics.unregister_body(self)

func radius_world() -> float:
	return body.radius * VOXEL_SCALE

## How far out (world meters) this body's gravity/atmosphere actually
## reaches before true open space takes over - a few radii, not infinite,
## so two planets far enough apart have a genuine zero-gravity void between
## them instead of gravity always snapping to whichever is merely closer no
## matter how far that still is. Simple radius multiple for now; real
## mass/orbit-based falloff isn't needed at this scope.
func influence_radius() -> float:
	return radius_world() * 4.0

func air_density() -> float:
	return body.atmosphere.air_density if body != null and body.atmosphere != null else 1.225

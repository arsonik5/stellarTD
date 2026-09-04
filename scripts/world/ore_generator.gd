@tool
extends VoxelGeneratorScript

## Solid-sphere planet generator: noise-driven hills/craters, five ore veins
## embedded near the surface. Shape/seed/ore-rarity all come from a
## CelestialBody passed into _init() rather than being hardcoded here - this
## script is now one reusable generator any number of differently-shaped
## planets can each construct their own instance of (see Planet.gd).

const SDF_CHANNEL: int = VoxelBuffer.CHANNEL_SDF
const INDICES_CHANNEL: int = VoxelBuffer.CHANNEL_INDICES

## LOCAL (voxel-grid) space center. Always the origin: a Planet's Terrain
## node has no offset transform relative to its own Planet root, so "local
## origin" is already that specific planet's center - the Planet root's own
## global_position (wherever it's placed in the wider universe) is what
## actually varies from body to body, not this.
const CENTER := Vector3.ZERO

var _radius := 100.0
var _height_amplitude := 6.0
var _detail_amplitude := 1.5
var _ore_vein_depth_min := 0.5
var _ore_vein_depth_max := 14.0
var _ore_iron_threshold := 0.25
var _ore_copper_threshold := 0.3
var _ore_sulfur_threshold := 0.35
var _ore_coal_threshold := 0.32
var _ore_silica_threshold := 0.38
var _ore_crystal_threshold := 0.55

var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _ore_iron_noise := FastNoiseLite.new()
var _ore_copper_noise := FastNoiseLite.new()
var _ore_sulfur_noise := FastNoiseLite.new()
var _ore_coal_noise := FastNoiseLite.new()
var _ore_silica_noise := FastNoiseLite.new()
var _ore_crystal_noise := FastNoiseLite.new()

## `body == null` (the @tool/editor-preview instantiation path, and any
## isolated test that doesn't care about a specific planet) falls back to
## the same numbers this generator always used - a real Planet always
## passes its own CelestialBody.
func _init(body: CelestialBody = null) -> void:
	if body != null:
		_radius = body.radius
		_height_amplitude = body.height_amplitude
		_detail_amplitude = body.detail_amplitude
		_ore_vein_depth_min = body.ore_vein_depth_min
		_ore_vein_depth_max = body.ore_vein_depth_max
		_ore_iron_threshold = body.ore_iron_threshold
		_ore_copper_threshold = body.ore_copper_threshold
		_ore_sulfur_threshold = body.ore_sulfur_threshold
		_ore_coal_threshold = body.ore_coal_threshold
		_ore_silica_threshold = body.ore_silica_threshold
		_ore_crystal_threshold = body.ore_crystal_threshold
	var base_seed := body.seed if body != null else 1

	# Height noise is sampled on the unit sphere direction (not world position)
	# so it wraps seamlessly around the planet with no seams at poles/edges.
	# Fixed per-noise offsets from the one base seed give each body distinct
	# but reproducible terrain/ore patterns from a single number.
	_height_noise.seed = base_seed
	_height_noise.frequency = 1.8
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_detail_noise.seed = base_seed + 5
	_detail_noise.frequency = 9.0
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_ore_iron_noise.seed = base_seed + 1
	_ore_iron_noise.frequency = 0.08
	_ore_iron_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_ore_copper_noise.seed = base_seed + 2
	_ore_copper_noise.frequency = 0.08
	_ore_copper_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_ore_sulfur_noise.seed = base_seed + 4
	_ore_sulfur_noise.frequency = 0.08
	_ore_sulfur_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_ore_coal_noise.seed = base_seed + 6
	_ore_coal_noise.frequency = 0.09
	_ore_coal_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_ore_silica_noise.seed = base_seed + 7
	_ore_silica_noise.frequency = 0.07
	_ore_silica_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_ore_crystal_noise.seed = base_seed + 8
	_ore_crystal_noise.frequency = 0.06
	_ore_crystal_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

func _get_used_channels_mask() -> int:
	return (1 << SDF_CHANNEL) | (1 << INDICES_CHANNEL)

func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, lod: int) -> void:
	if lod != 0:
		return

	var size := out_buffer.get_size()
	var pos_world := Vector3(origin_in_voxels)

	for rz in size.z:
		pos_world.z = origin_in_voxels.z + rz
		for rx in size.x:
			pos_world.x = origin_in_voxels.x + rx
			for ry in size.y:
				pos_world.y = origin_in_voxels.y + ry

				var to_center := pos_world - CENTER
				var dist := to_center.length()
				var dir := to_center / dist if dist > 0.0001 else Vector3.UP

				var surface_radius := _radius \
					+ _height_noise.get_noise_3d(dir.x, dir.y, dir.z) * _height_amplitude \
					+ _detail_noise.get_noise_3d(dir.x, dir.y, dir.z) * _detail_amplitude

				var signed_distance := dist - surface_radius
				out_buffer.set_voxel_f(signed_distance, rx, ry, rz, SDF_CHANNEL)

				if signed_distance < 0.0:
					var depth_below_surface := surface_radius - dist
					var material := VoxelMaterials.STONE
					if depth_below_surface >= _ore_vein_depth_min and depth_below_surface <= _ore_vein_depth_max:
						if _ore_iron_noise.get_noise_3d(pos_world.x, pos_world.y, pos_world.z) > _ore_iron_threshold:
							material = VoxelMaterials.IRON_ORE
						elif _ore_copper_noise.get_noise_3d(pos_world.x, pos_world.y, pos_world.z) > _ore_copper_threshold:
							material = VoxelMaterials.COPPER_ORE
						elif _ore_sulfur_noise.get_noise_3d(pos_world.x, pos_world.y, pos_world.z) > _ore_sulfur_threshold:
							material = VoxelMaterials.SULFUR_ORE
						elif _ore_coal_noise.get_noise_3d(pos_world.x, pos_world.y, pos_world.z) > _ore_coal_threshold:
							material = VoxelMaterials.COAL_ORE
						elif _ore_silica_noise.get_noise_3d(pos_world.x, pos_world.y, pos_world.z) > _ore_silica_threshold:
							material = VoxelMaterials.SILICA_ORE
						elif _ore_crystal_noise.get_noise_3d(pos_world.x, pos_world.y, pos_world.z) > _ore_crystal_threshold:
							material = VoxelMaterials.CRYSTAL_ORE
					out_buffer.set_voxel(material, rx, ry, rz, INDICES_CHANNEL)

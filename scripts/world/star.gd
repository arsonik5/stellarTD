class_name Star
extends CelestialBodyNode

## The system's star as an actual body: a real sphere at a real position with
## real geometry, not a direction on a DirectionalLight3D and a disc painted
## into the skybox.
##
## What that buys, and why it was worth doing rather than keeping the light:
##   - the sun's direction genuinely differs at different planets. A fixed
##     light rotation is simply wrong the moment there is more than one body,
##     and both planets were previously lit as though from the same angle.
##   - brightness falls off with distance instead of being a constant.
##   - it grows as you approach and can be flown into, because it is geometry.
##   - it occludes things behind it and is occluded by things in front.
##
## Registers with PlanetPhysics like any other body (see CelestialBodyNode),
## so gravity, irradiance and frame resolution all pick it up with no special
## casing anywhere.

const SurfaceShader := preload("res://scripts/world/star_surface.gdshader")
const CoronaShader := preload("res://scripts/world/star_corona.gdshader")

@export var body: StarBody

## The scene's sun light, re-aimed at this star every frame. Left as an
## export rather than searched for, so a system with no light still works.
@export var sun_light: DirectionalLight3D

## Light energy at the reference distance below. Together these set how bright
## the sun reads on the home planet; everything else scales from them by
## inverse square, so moving a planet changes its lighting for free.
@export_range(0.0, 20.0, 0.05) var reference_light_energy: float = 1.6
@export_range(1.0, 1e9, 1.0) var reference_distance: float = 1100.0

var _surface: MeshInstance3D
var _material: ShaderMaterial
var _corona: MeshInstance3D
var _corona_material: ShaderMaterial

func _ready() -> void:
	add_to_group("star")
	_build_surface()
	super._ready()

func _build_surface() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius_world()
	sphere.height = radius_world() * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32

	_material = ShaderMaterial.new()
	_material.shader = SurfaceShader
	if body != null:
		_material.set_shader_parameter("star_color", body.color())
		_material.set_shader_parameter("brightness", body.visual_brightness)
		_material.set_shader_parameter("limb_darkening", body.limb_darkening)
		_material.set_shader_parameter("limb_darkening_quad", body.limb_darkening_quad)

	_surface = MeshInstance3D.new()
	_surface.name = "Photosphere"
	_surface.mesh = sphere
	_surface.material_override = _material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	_build_corona()

## The halo around the disc. See star_corona.gdshader for why this is geometry
## and not Environment glow.
func _build_corona() -> void:
	if body == null:
		return
	var extent := radius_world() * body.corona_ratio
	var quad := QuadMesh.new()
	quad.size = Vector2(extent * 2.0, extent * 2.0)

	_corona_material = ShaderMaterial.new()
	_corona_material.shader = CoronaShader
	_corona_material.set_shader_parameter("star_color", body.color())
	_corona_material.set_shader_parameter("intensity", body.corona_intensity)
	_corona_material.set_shader_parameter("shell_ratio", body.corona_ratio)
	_corona_material.set_shader_parameter("falloff", body.corona_falloff)
	_corona_material.set_shader_parameter("rim_width", body.corona_rim_width)
	_corona_material.set_shader_parameter("rim_boost", body.corona_rim_boost)

	_corona = MeshInstance3D.new()
	_corona.name = "Corona"
	_corona.mesh = quad
	_corona.material_override = _corona_material
	_corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The quad is rotated to face the camera in the vertex shader, so its own
	# bounds are meaningless to the culler - without this it vanishes whenever
	# the camera looks at the star from anywhere near edge-on.
	_corona.custom_aabb = AABB(Vector3.ONE * -extent, Vector3.ONE * extent * 2.0)
	# Must sort AFTER AtmosphereRenderer (sorting_offset 1000), not just after
	# the photosphere. The scattering pass rebuilds the frame from a screen
	# capture and writes ALPHA = 1.0, so it does not composite over what came
	# before it - it REPLACES it. Anything transparent drawn earlier that was
	# not in the capture is simply gone, which is what made the corona invisible
	# with the atmosphere enabled and visible the instant it was switched off.
	#
	# Depth testing still applies, so terrain and the photosphere occlude the
	# corona correctly despite it drawing last.
	#
	# The value has to be enormous because sorting_offset is SUBTRACTED from
	# distance-to-camera, not a priority: the atmosphere quad sits near the
	# world origin while the star is kilometres away, so merely beating its
	# 1000 still left the corona sorting as the farther (earlier) object. This
	# is "always last" expressed in the only units the sorter has.
	_corona.sorting_offset = 1.0e7
	add_child(_corona)

func _process(_delta: float) -> void:
	_aim_sun()

## Points the scene's DirectionalLight3D from this star toward whatever the
## player is standing on, and scales its energy by inverse square.
##
## A directional light is still the right tool - it gives clean parallel
## shadows and Godot's shadow atlas handles it well - but its DIRECTION now
## has to be derived rather than authored. Aiming at the player rather than at
## a fixed angle is what makes standing on a far planet look correct.
func _aim_sun() -> void:
	if not is_instance_valid(sun_light) or body == null:
		return
	var viewer := get_tree().get_first_node_in_group("player") as Node3D
	if viewer == null:
		return

	var to_viewer: Vector3 = viewer.global_position - global_position
	var dist := to_viewer.length()
	if dist < 0.001:
		return

	# A DirectionalLight3D shines along its own -Z, so it must look FROM the
	# star TOWARD the viewer.
	sun_light.global_position = global_position
	sun_light.look_at(viewer.global_position, _stable_up(to_viewer / dist))

	var falloff := (reference_distance * reference_distance) / maxf(dist * dist, 0.0001)
	sun_light.light_energy = reference_light_energy * falloff
	sun_light.light_color = body.color()

## look_at() fails when the target direction is parallel to the chosen up
## vector, which happens whenever the player crosses the star's polar axis.
func _stable_up(dir: Vector3) -> Vector3:
	return Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.999 else Vector3.UP

func radius_world() -> float:
	return body.radius if body != null else 0.0

func surface_gravity() -> float:
	return body.surface_gravity if body != null else 0.0

func irradiance_at(pos: Vector3) -> float:
	if body == null:
		return 0.0
	return body.irradiance_at_distance(global_position.distance_to(pos))

## A star has no local surface frame worth resolving against - you should
## never be "standing on" it - but it still needs a sane influence radius so
## get_nearest_body() doesn't hand the star's frame to a player who is merely
## closer to it than to anything else. Kept tight to the photosphere.
func influence_radius() -> float:
	return radius_world() * 1.5

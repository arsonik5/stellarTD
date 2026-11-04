class_name AtmosphereRenderer
extends MeshInstance3D

## Draws every registered body's atmosphere in one full-screen pass.
##
## Self-contained on purpose: it pulls what it needs from PlanetPhysics and
## pushes it into one ShaderMaterial. Nothing else in the game reads from it
## or depends on it existing, so deleting this node (or setting `enabled` to
## false) removes atmospheric rendering entirely and breaks nothing - the
## project's standing "every system toggleable" rule. Gameplay-facing air
## density lives on Planet/PlanetAtmosphere, not here, so drag keeps working
## with this node gone.
##
## The mesh is a unit quad that the shader forces to clip space in vertex(),
## so its transform is irrelevant - it only has to be somewhere the camera's
## frustum culling won't discard it, which is why extents are set huge and
## culling is disabled.

const ScatterShader := preload("res://scripts/world/atmosphere_scatter.gdshader")

## Hard limit shared with the shader's MAX_BODIES. Raising it means editing
## both - the shader cannot size its uniform arrays from GDScript.
const MAX_BODIES := 4

@export var enabled: bool = true:
	set(value):
		enabled = value
		visible = value

## Converts the star's irradiance into the shader's in-scatter multiplier.
##
## Sky brightness is DERIVED from the star now, not authored: it is
## `star.irradiance_at(reference_distance) * this`. That matters because the
## same luminosity also drives the DirectionalLight3D's energy and (later) the
## heat-damage system - with a standalone brightness knob, changing the star
## or moving it would silently desynchronise three things that should agree.
##
## This constant is all that remains of the old hand-set 4200. It exists
## because the scattering coefficients are real per-metre values while our
## planets are ~200 m rather than ~6371 km, so the optical path through a
## whole atmosphere is thousands of times shorter than Earth's and the
## integral would otherwise come out nearly black. It is a unit conversion,
## not a brightness dial - tune the star's `luminosity` for brightness.
@export_range(0.0, 500.0, 0.1) var irradiance_to_scatter: float = 17.0

## Body radius the scattering constant above was calibrated against.
##
## The optical path through an atmosphere scales with the body it wraps, and so
## does the integral's result. `irradiance_to_scatter` was tuned on a 500 m
## planet; on the 8 km one the same value made the path 16x longer and washed
## both the surface and the view from 3 km altitude to flat white - terrain was
## being rendered correctly and then buried under haze.
##
## Compensating PER BODY rather than globally, because a moon and a planet in
## the same frame have different radii and one global scale cannot be right for
## both. This is the same class of bug as the noise frequencies: a constant
## calibrated at one scale is silently wrong at another.
const SCATTER_REFERENCE_RADIUS := 500.0

## Raised 24 -> 64.
##
## 24 was too few for a grazing limb ray, which crosses tens of kilometres of
## shell against a couple for a ray straight down. Dithering converts that
## error from stair-step bands into grain but cannot remove it, and on the dark
## side - where the eye is adapted and the signal is small - the grain is what
## reads as the atmosphere glitching.
##
## Free here in practice: the atmosphere is a screen-space post-process and the
## frame was vsync-capped at 144 fps both before and after, so nothing measured
## it as the bottleneck. Revisit if a GPU-bound target appears.
@export_range(4, 128) var view_samples: int = 64
@export_range(2, 16) var light_samples: int = 6

var _material: ShaderMaterial
var _star: Star

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad

	# The vertex shader writes POSITION directly, so this AABB exists purely to
	# stop frustum culling from throwing the quad away when the camera looks
	# somewhere the (irrelevant) quad transform isn't.
	custom_aabb = AABB(Vector3.ONE * -1e6, Vector3.ONE * 2e6)
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_material = ShaderMaterial.new()
	_material.shader = ScatterShader
	material_override = _material

	# Draw after ordinary transparent geometry so it composites over the
	# finished frame.
	sorting_offset = 1000.0
	visible = enabled

## The star drives sun direction and brightness. Left as an explicit setter
## rather than a group lookup so a system with no star still renders (every
## body simply goes unlit) instead of erroring.
func set_star(star: Star) -> void:
	_star = star

func _process(_delta: float) -> void:
	if not enabled or _material == null:
		return
	_push_uniforms()

func _push_uniforms() -> void:
	var centers := PackedVector3Array()
	var surface_radii := PackedFloat32Array()
	var ground_radii := PackedFloat32Array()
	var shell_radii := PackedFloat32Array()
	var rayleigh := PackedVector3Array()
	var ozone := PackedVector3Array()
	var mie := PackedFloat32Array()
	var mie_g := PackedFloat32Array()
	var rayleigh_scale := PackedFloat32Array()
	var mie_scale := PackedFloat32Array()
	var ozone_peak := PackedFloat32Array()
	var ozone_width := PackedFloat32Array()
	var energy := PackedFloat32Array()

	for node in PlanetPhysics.get_all_bodies():
		if centers.size() >= MAX_BODIES:
			break
		# Typed against the shared base, not Planet: anything with an
		# atmosphere renders one, whether or not it happens to have terrain.
		var celestial := node as CelestialBodyNode
		if celestial == null:
			continue
		var atmo := celestial.atmosphere()
		# An airless body contributes nothing to the integral; skipping it
		# keeps a moon from burning a shader slot and sample budget.
		if atmo == null or atmo.shell_radius_ratio <= 1.0 or atmo.scattering_energy <= 0.0:
			continue

		var radius := celestial.radius_world()
		centers.append(celestial.global_position)
		surface_radii.append(radius)
		# Lowest terrain can reach. See body_ground_radius in the shader.
		var relief := 0.0
		var as_planet := celestial as Planet
		if as_planet != null:
			relief = as_planet.max_relief_world()
		ground_radii.append(maxf(radius - relief, 1.0))
		shell_radii.append(celestial.atmosphere_radius_world())
		rayleigh.append(atmo.rayleigh_coefficients)
		ozone.append(atmo.ozone_absorption)
		mie.append(atmo.mie_coefficient)
		mie_g.append(atmo.mie_anisotropy)
		rayleigh_scale.append(maxf(atmo.rayleigh_scale_ratio * radius, 0.001))
		mie_scale.append(maxf(atmo.mie_scale_ratio * radius, 0.001))
		ozone_peak.append(atmo.ozone_peak_ratio)
		ozone_width.append(atmo.ozone_width_ratio)
		energy.append(atmo.scattering_energy * SCATTER_REFERENCE_RADIUS / maxf(radius, 1.0))

	_material.set_shader_parameter("body_count", centers.size())
	_material.set_shader_parameter("body_center", centers)
	_material.set_shader_parameter("body_surface_radius", surface_radii)
	_material.set_shader_parameter("body_ground_radius", ground_radii)
	_material.set_shader_parameter("body_shell_radius", shell_radii)
	_material.set_shader_parameter("body_rayleigh", rayleigh)
	_material.set_shader_parameter("body_ozone", ozone)
	_material.set_shader_parameter("body_mie", mie)
	_material.set_shader_parameter("body_mie_g", mie_g)
	_material.set_shader_parameter("body_rayleigh_scale", rayleigh_scale)
	_material.set_shader_parameter("body_mie_scale", mie_scale)
	_material.set_shader_parameter("body_ozone_peak", ozone_peak)
	_material.set_shader_parameter("body_ozone_width", ozone_width)
	_material.set_shader_parameter("body_energy", energy)

	if is_instance_valid(_star):
		_material.set_shader_parameter("star_position", _star.global_position)
		_material.set_shader_parameter("star_reference_distance", _star.reference_distance)
		if _star.body != null:
			_material.set_shader_parameter("sun_color", _star.body.color())
	# No star -> no sunlight -> no in-scatter. Correct rather than a fallback:
	# an atmosphere with nothing illuminating it should be dark.
	var intensity := 0.0
	if is_instance_valid(_star) and _star.body != null:
		intensity = _star.body.irradiance_at_distance(_star.reference_distance) * irradiance_to_scatter
	_material.set_shader_parameter("sun_intensity", intensity)
	_material.set_shader_parameter("view_samples", view_samples)
	_material.set_shader_parameter("light_samples", light_samples)

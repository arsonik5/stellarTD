extends Node3D

## The "universe" root: no longer owns a Terrain directly (each Planet
## instance owns its own, see planet.gd/planet.tscn) - just the shared
## system star (one DirectionalLight3D - a real per-planet sun isn't
## meaningful without orbital mechanics, which don't exist yet) and the
## shared sky/fog (one WorldEnvironment, since only one can render at a
## time - swapped to whichever Planet the player is actually nearest, so
## flying from one body toward another visibly transitions atmospheres
## with no scene reload).

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var player: Node3D = $Player
@onready var threat_director: ThreatDirector = $ThreatDirector
@onready var home_planet: Planet = $HomePlanet

const SkyShader := preload("res://scripts/world/sky_atmosphere.gdshader")

var _current_atmosphere: PlanetAtmosphere = null

func _ready() -> void:
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	_update_atmosphere()
	threat_director.target_planet = home_planet

func _process(_delta: float) -> void:
	_update_atmosphere()

## Only reapplies when the nearest Planet's atmosphere actually changed
## (not every frame) - _apply_atmosphere() builds fresh Sky/Environment
## resources, no need to redo that work while sitting on the same planet.
func _update_atmosphere() -> void:
	var nearest: Node = PlanetPhysics.get_nearest_body(player.global_position)
	var planet := nearest as Planet
	if planet == null or planet.body == null or planet.body.atmosphere == null:
		return
	var atmo: PlanetAtmosphere = planet.body.atmosphere
	if atmo == _current_atmosphere:
		return
	_current_atmosphere = atmo
	_apply_atmosphere(atmo)

## Pushes one PlanetAtmosphere's values into the DirectionalLight + a fresh
## Sky/Environment built here in code (not hand-authored as .tscn/.tres
## sub-resources - a ShaderMaterial with a dozen parameters is much
## lower-risk to construct in GDScript than to get right by hand in
## resource text).
func _apply_atmosphere(atmo: PlanetAtmosphere) -> void:
	sun.light_color = atmo.sun_light_color
	sun.light_energy = atmo.sun_light_energy

	var sky_material := ShaderMaterial.new()
	sky_material.shader = SkyShader
	sky_material.set_shader_parameter("zenith_color", atmo.zenith_color)
	sky_material.set_shader_parameter("horizon_color", atmo.horizon_color)
	sky_material.set_shader_parameter("ground_color", atmo.ground_color)
	sky_material.set_shader_parameter("horizon_curve", atmo.horizon_curve)
	sky_material.set_shader_parameter("sun_color", atmo.sun_color)
	sky_material.set_shader_parameter("sun_angular_size", atmo.sun_angular_size)
	sky_material.set_shader_parameter("sun_glow_color", atmo.sun_glow_color)
	sky_material.set_shader_parameter("sun_glow_intensity", atmo.sun_glow_intensity)
	sky_material.set_shader_parameter("sun_glow_exponent", atmo.sun_glow_exponent)
	sky_material.set_shader_parameter("atmosphere_energy", atmo.atmosphere_energy)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.fog_enabled = atmo.fog_enabled
	env.fog_light_color = atmo.fog_color
	env.fog_density = atmo.fog_density

	world_environment.environment = env

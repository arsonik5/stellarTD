extends Node3D

## Ambient fill in vacuum. Near black: an airless body has no sky to scatter
## light into its shadows, and that hard contrast is most of what makes rock
## read as rock in the reference photography.
const VACUUM_AMBIENT_COLOR := Color(0.28, 0.31, 0.38)
const VACUUM_AMBIENT_ENERGY := 0.045

## Ambient fill at Earth-like sea level. A real overcast-free daylit shadow sits
## a couple of stops under the sunlit ground, not twenty - the previous fixed
## 0.045 was crushing every shaded slope on an atmospheric planet to black and
## taking the terrain's landform with it.
const AIR_AMBIENT_COLOR := Color(0.42, 0.52, 0.68)
const AIR_AMBIENT_ENERGY := 0.34

## Air density (kg/m3) at which ambient reaches AIR_AMBIENT_*. Earth sea level
## is 1.225 and the home planet matches it.
const AMBIENT_FULL_DENSITY := 1.0

var _env: Environment

## The "universe" root: no longer owns a Terrain directly (each Planet
## instance owns its own, see planet.gd/planet.tscn) - just the shared
## system star (one DirectionalLight3D - a real per-planet sun isn't
## meaningful without orbital mechanics, which don't exist yet), one
## WorldEnvironment holding a fixed starfield background, and the
## AtmosphereRenderer that draws every body's atmosphere over it.
##
## Nothing here is swapped per-planet any more. The old version rebuilt a
## Sky + Environment (and scaled fog) every time the player got nearest to a
## different body; atmospheres now come from one raymarched pass that draws
## all bodies at once, so approaching another planet crossfades on its own.

const StarfieldShader := preload("res://scripts/world/starfield.gdshader")

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var player: Node3D = $Player
@onready var threat_director: ThreatDirector = $ThreatDirector
@onready var home_planet: Planet = $HomePlanet as Planet
@onready var star: Star = $Star as Star
@onready var atmosphere_renderer: AtmosphereRenderer = $AtmosphereRenderer as AtmosphereRenderer

## Waits for every planet to finish generating.
##
## Children used to be guaranteed ready before the parent, and that guarantee is
## gone now that Planet._ready() awaits its erosion bake. Anything here that
## touches a planet has to wait on `terrain_ready` explicitly - relying on node
## order would silently read an unbuilt planet, which fails as "the save
## restored nothing" rather than as an error.
func _await_planets() -> void:
	for p in get_tree().get_nodes_in_group("planet"):
		if p.has_method("get") and not p.get("is_terrain_ready"):
			await p.terrain_ready

## Resource scanner readout. Added in code because it is a single global
## overlay with no per-scene wiring, and it groups itself so the player can find
## it without a hard path.
func _add_scanner_hud() -> void:
	var hud := ScannerHUD.new()
	hud.add_to_group("scanner_hud")
	add_child(hud)

func _add_suffocation_fx() -> void:
	add_child(SuffocationFX.new())

func _ready() -> void:
	_configure_fixed_alpha_system()
	# The sun's rotation is no longer authored here. Star.gd re-aims the light
	# from the star's real position toward the player every frame, so a fixed
	# angle would just be overwritten - and was wrong anyway, since two planets
	# on opposite sides of a star are not lit from the same direction.
	_configure_sun_shadows()
	_apply_starfield()
	_add_scanner_hud()
	_add_suffocation_fx()
	if is_instance_valid(star):
		star.sun_light = sun
	if is_instance_valid(atmosphere_renderer):
		atmosphere_renderer.set_star(star)
	if is_instance_valid(home_planet):
		threat_director.target_planet = home_planet
	# Deferred by one frame: SceneTree.current_scene is not assigned until the
	# scene finishes being added, and restoring placed objects parents them to
	# it. Doing this inline puts every saved building under a null parent.
	# Planets bake asynchronously, so their _ready() returns to the engine long
	# before the terrain exists. Both of these need a real planet: the landmark
	# search reads the eroded map, and a restored save places objects onto
	# terrain that has to be there to receive them.
	await _await_planets()
	_place_player_at_landmark()
	call_deferred("_restore_save")

## Moves the player to a spot the home planet considers worth starting at,
## before spawn resolution runs.
##
## Only for a NEW game: a loaded save has its own player position and moving it
## would quietly relocate the player every time they load, which is the same
## class of bug as re-running spawn placement on a save.
func _place_player_at_landmark() -> void:
	if not SaveManager.pending_state.is_empty():
		return
	if not is_instance_valid(home_planet) or not is_instance_valid(player):
		return
	var dir := home_planet.suggested_spawn_direction()
	if dir == Vector3.ZERO:
		return
	# Above the highest the terrain can reach, so spawn resolution drops the
	# player onto real ground instead of starting them inside it.
	var altitude: float = home_planet.radius_world() + home_planet.max_relief_world() + 60.0
	player.global_position = home_planet.global_position + dir * altitude

## Puts a loaded save back into the freshly built world. Does nothing for a new
## game, which is simply a slot whose state is empty - there is no separate
## "start fresh" branch anywhere in the save system.
func _restore_save() -> void:
	SaveManager.apply_pending(get_tree())

## Fixed alpha-system layout for reliable testing: one home world and one
## moon in a predictable orbit, without any procedural generation decisions
## or runtime re-layouts. This is deliberately stable and deterministic so
## the rest of the gameplay loop can be tested against a known scenario.
func _configure_fixed_alpha_system() -> void:
	var fixed_home: Planet = get_node_or_null("HomePlanet") as Planet
	if fixed_home != null:
		home_planet = fixed_home
		home_planet.global_position = Vector3.ZERO
	var moon: Node3D = get_node_or_null("TestMoon") as Node3D
	if moon != null:
		moon.global_position = Vector3(44000.0, 0.0, 0.0)

## Shadow settings for a planetary-scale scene lit at a low sun angle.
##
## Every one of these was at its engine default, which is tuned for a
## human-scale interior. On an 8 km sphere with the sun near the horizon the
## result was shadow ACNE: a band of scattered black pixels along every ridge
## where the surface goes edge-on to the light and the default bias is far too
## small to clear the depth comparison. It reads as speckle, which is easy to
## mistake for a shader or LOD problem - raising `lod_distance` 3x changed it
## not at all, which is what ruled those out.
##
## The long shadow distance is a deliberate cost: terrain shadows reaching to
## the horizon are a large part of the cinematic look, and the reference
## photography is entirely long raking shadows.
func _configure_sun_shadows() -> void:
	sun.shadow_enabled = true
	# Look rule (art-direction.md, Michael 2026-11-05): PS2-styled ASSETS, MODERN rendering. The sun is an area
	# light: a 0.53 deg disc (the Sun seen from Earth) gives shadows that are crisp at contact and soften with
	# distance from the caster - long soft shadows at a low sun (PCSS, Forward+).
	sun.light_angular_distance = 0.53
	# Normal bias does the work at grazing incidence; depth bias alone would
	# have to be large enough to visibly detach shadows from their casters.
	sun.shadow_normal_bias = 6.0
	sun.shadow_bias = 0.04
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# 0-2 km in four cascades: a tight first split for crevices and the rocks at your feet (40 m), then 160 m,
	# 600 m, 2 km - about a standing player's horizon on the 20 km home world.
	sun.directional_shadow_max_distance = 2000.0
	sun.directional_shadow_split_1 = 0.02
	sun.directional_shadow_split_2 = 0.08
	sun.directional_shadow_split_3 = 0.3
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	# Slightly soft rather than razor-edged: a real terminator on dusty ground
	# is not a hard line, and it hides the remaining split seams.
	sun.shadow_blur = 1.0

## The background never changes: deep space and stars, identical on every
## body and in the void. Everything that used to make one planet's sky differ
## from another's now comes from the scattering pass on top of it.
func _apply_starfield() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = StarfieldShader

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# No fog. Aerial perspective is part of the scattering integral now.
	# Environment fog was also what made the sky read as a flat sand-coloured
	# dome: fog_sky_affect defaults to 1.0, so the fog colour painted over the
	# entire background and only lifted once the player left the atmosphere.
	env.fog_enabled = false

	# The scattering pass outputs real radiance, which goes well above 1.0 on a
	# bright limb. Godot's default TONEMAP_LINEAR hard-clips there, so the limb
	# blew out to flat white while staying blue in its dimmer parts - colour
	# information thrown away exactly where the effect is most visible. ACES
	# rolls the highlights off instead, keeping the hue through the bright band.
	# Filmic AgX instead of ACES: ACES shifts saturated highlights' hue, AgX rolls off to white - grounded and
	# photographic (the SE2 target) rather than punchy.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# Subtle grade: a touch more contrast, a touch less saturation. Real geology is not colourful.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.9
	env.adjustment_brightness = 1.0
	# Contact shadow and bounce light: crevices, the foot of every rock, a sunlit cliff lighting its own shadow.
	# Screen-space, so the cost does not grow with a 20 km world. SDFGI was not adopted: its world-space cascades
	# are at their worst on a planet-sized scene and could not be measured on the CPU-only machine this was built
	# on - revisit with a GPU profile.
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.8
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.15
	env.ssao_ao_channel_affect = 0.5
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.7
	env.ssil_sharpness = 0.98

	# The sky is now near-black space, so sky-sourced ambient is effectively
	# zero and anything on a body's night side renders as pure silhouette -
	# including the player's own ship. A small constant floor keeps unlit
	# geometry readable without washing out the terminator.
	# Ambient is a readability floor, not lighting. It was at 0.12 with a blue
	# tint, which lifted every shadow on the planet into flat grey - the
	# reference photography this is aimed at has near-BLACK shadows next to
	# bright sunlit slopes, and that contrast is most of what makes rock read as
	# rock. Airless bodies have essentially no fill light at all.
	#
	# Not taken to zero: the night side would become pure silhouette, including
	# the player's own ship.
	#
	# Which is right for an AIRLESS body and wrong for one with an atmosphere,
	# and the same fixed value was being used for both. Air scatters sunlight
	# into shadow - that is what a blue sky IS, and it is why a shadow on Earth
	# is blue and readable while a shadow on the Moon is black. Driving ambient
	# from air density (see _update_ambient) keeps the hard lunar contrast on the
	# moon and gives the home planet the fill light its own atmosphere implies.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = VACUUM_AMBIENT_COLOR
	env.ambient_light_energy = VACUUM_AMBIENT_ENERGY

	# Bloom. The star is emissive geometry well above 1.0, so glow is what gives
	# it a halo that grows as you approach - handled by the renderer rather than
	# a fake corona shell on the star, so the atmosphere limb and any other
	# emissive surface get the same treatment for free.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	# glow_bloom must stay at zero. It is not a strength dial - it lifts the
	# WHOLE frame into the glow buffer regardless of the HDR threshold, so with
	# the star filling a third of the screen it washed empty space out to a flat
	# milky brown. Threshold + levels are what shape a corona; bloom just fogs.
	env.glow_bloom = 0.03
	env.glow_strength = 1.0
	# 2.5, not 1.0. Sunlit terrain lands a little over 1.0 in HDR, so a
	# threshold of 1.0 fed the entire ground into an ADDITIVE glow and washed
	# the surface out to flat white. The star's disc peaks at ~3.2, comfortably
	# above this, so it still blooms while nothing lit by it does.
	env.glow_hdr_threshold = 2.5
	env.glow_hdr_scale = 1.2
	# ADDITIVE, not SOFTLIGHT. Softlight is a contrast operator: applied over a
	# near-black backdrop it returns near-black, so the star's halo - which lives
	# entirely in the black sky AROUND the disc - was being multiplied away. The
	# star rendered as a hard-edged white circle with no corona at all. Additive
	# is the only blend that can put light where there was none.
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# A corona is wide and soft, so the halo has to come from the coarse mip
	# levels. Godot's defaults only enable 3 and 5, which gives a tight rim a few
	# pixels across rather than something that reads as a star.
	env.set("glow_levels/2", 0.0)
	env.set("glow_levels/3", 0.5)
	env.set("glow_levels/4", 0.8)
	env.set("glow_levels/5", 1.0)
	env.set("glow_levels/6", 0.6)
	env.set("glow_levels/7", 0.25)

	world_environment.environment = env
	_env = env

## Ambient fill tracks the air the player is actually standing in.
##
## A single fixed value cannot serve both a vacuum moon and an atmospheric
## planet: the moon needs near-black shadows (no sky to scatter light into them)
## and the planet needs real fill (a blue sky IS scattered sunlight, and it is
## why a daylit shadow on Earth is readable rather than a hole). Tuned for one,
## the other is wrong - and it was tuned for the moon, which is why every shaded
## slope on the home planet was crushing to black and taking the landform with
## it.
##
## Per frame rather than per body, so flying up out of the atmosphere darkens
## the shadows continuously instead of snapping when a boundary is crossed.
func _update_ambient() -> void:
	if _env == null or not is_instance_valid(player):
		return
	var density: float = PlanetPhysics.get_air_density(player.global_position)
	var t: float = clampf(density / AMBIENT_FULL_DENSITY, 0.0, 1.0)
	var ambient := VACUUM_AMBIENT_COLOR.lerp(AIR_AMBIENT_COLOR, t)
	# Palette harmony (design/05-planets.md W4): shadows are lit by sky AND by light bounced off the ground, so the
	# ambient leans toward the body's own dust colour - a frozen moon's shadows go cold, a barren world's stay grey.
	var near := PlanetPhysics.get_nearest_body(player.global_position)
	var arch := PlanetArchetype.of(near.get("body") as CelestialBody) if near != null else null
	if arch != null:
		ambient = arch.ambient_tint(ambient)
	_env.ambient_light_color = ambient
	_env.ambient_light_energy = lerpf(VACUUM_AMBIENT_ENERGY, AIR_AMBIENT_ENERGY, t)
	_log_ambient_once(density, t)

var _ambient_logged := false

## One line, once, a few seconds in. Ambient is invisible to reason about - a
## value that never takes effect and a value that is correct look the same from
## the outside, and a shadow-luminance measurement of the rendered frame moved
## the WRONG WAY on the first attempt, which is not something guessing resolves.
func _log_ambient_once(density: float, t: float) -> void:
	if _ambient_logged or Time.get_ticks_msec() < 5000:
		return
	_ambient_logged = true
	TerrainLog.write_fields("ambient", "ambient fill", {
		"player_air_density": "%.3f" % density,
		"t": "%.2f" % t,
		"energy": "%.3f" % _env.ambient_light_energy,
		"source_is_color": _env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR,
		"env_is_live": world_environment.environment == _env,
	})

func _process(_delta: float) -> void:
	_update_ambient()

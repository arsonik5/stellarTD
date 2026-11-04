extends Node

## Single source of truth for "which celestial body am I near, how strong is
## its gravity, how thick is its air" - read by the player, turrets, and
## projectiles alike so none of them can disagree. A real multi-body
## registry, not a singleton: any number of Planet instances can coexist,
## each registering itself on _ready()/unregistering on _exit_tree()
## (Planet.gd), and every query here resolves against whichever registered
## body is actually nearest to the position being asked about - including
## correctly resolving to "no body nearby" (true void: zero gravity, vacuum)
## when nothing is close enough to matter, rather than assuming exactly one
## planet always exists.

## Radius at which REFERENCE_SURFACE_GRAVITY applies. Moved 200 -> 2000
## alongside the scale-up so the home planet keeps its established 1.2
## m/s^2: surface gravity scales linearly with radius, so leaving this at
## 200 would have made a 2 km planet pull 12 m/s^2 and invalidated every
## jump height, projectile arc and turret firing solution already tuned.
## Home planet's world radius. Surface gravity scales linearly with radius,
## so this tracks the home planet to keep it at REFERENCE_SURFACE_GRAVITY -
## every jump height, projectile arc and turret firing solution is tuned
## against that number.
const REFERENCE_RADIUS_WORLD := 8000.0
const REFERENCE_SURFACE_GRAVITY := 1.2

var _bodies: Array[Node] = []

func register_body(planet: Node) -> void:
	if not _bodies.has(planet):
		_bodies.append(planet)

func unregister_body(planet: Node) -> void:
	_bodies.erase(planet)

## Every currently registered body, freed entries pruned. For consumers that
## need ALL bodies rather than just the nearest - the atmosphere renderer
## draws every body's shell at once, since flying between two planets has to
## show both. Returns a copy so callers can't mutate the registry.
func get_all_bodies() -> Array[Node]:
	var i := 0
	while i < _bodies.size():
		if not is_instance_valid(_bodies[i]):
			_bodies.remove_at(i)
		else:
			i += 1
	return _bodies.duplicate()

## Nearest registered body that `pos` is actually within the influence radius
## of, or null if none qualify. This resolves the LOCAL FRAME - whose "up" you
## are standing in, whose atmosphere you are breathing, whose terrain a dig ray
## should hit. It is deliberately NOT how gravity is computed any more (see
## get_gravity_accel), because a star's pull has to reach across the whole
## system while "which surface am I on" clearly should not.
func get_nearest_body(pos: Vector3) -> Node:
	var best: Node = null
	var best_dist := INF
	var i := 0
	while i < _bodies.size():
		var b: Node = _bodies[i]
		if not is_instance_valid(b):
			_bodies.remove_at(i)
			continue
		var body := b as CelestialBodyNode
		var d: float = b.global_position.distance_to(pos)
		var in_range := body == null or d <= body.influence_radius()
		if d < best_dist and in_range:
			best_dist = d
			best = b
		i += 1
	return best

## The nearest body's VoxelTerrain, for dig/build/support raycasts - null in
## open space and for bodies that have no terrain at all, such as the star.
func get_nearest_terrain(pos: Vector3) -> VoxelNode:
	var body := get_nearest_body(pos) as CelestialBodyNode
	return body.terrain_node() if body != null else null

func get_planet_center(pos: Vector3) -> Vector3:
	var body := get_nearest_body(pos) as Node3D
	return body.global_position if body != null else pos

## Radial "up" (away from the nearest body's centre). Deliberately resolved
## against the NEAREST body rather than along the summed gravity vector: while
## standing on a planet the star contributes a small sideways pull, and
## orienting to net gravity would tilt the player, their buildings and the
## build grid slightly toward the sun. "Up" is a surface-frame question.
func get_up(pos: Vector3) -> Vector3:
	var body := get_nearest_body(pos) as Node3D
	if body == null:
		return Vector3.UP
	var up: Vector3 = pos - body.global_position
	return up.normalized() if up.length() > 0.0001 else Vector3.UP

## Summed inverse-square gravity from EVERY registered body.
##
## Was: the nearest body inside its influence radius, at a fixed magnitude
## with no falloff, and exactly zero outside. That gave a hard discontinuity
## at every influence boundary and no way for a star to hold a system
## together. Summing is both physically right and simpler - there is no
## special case left, and the "genuine zero-g void between planets" the old
## cutoff was protecting still happens naturally, because 1/d^2 from far-away
## bodies is negligible rather than artificially clamped to nothing.
func get_gravity_accel(pos: Vector3) -> Vector3:
	var accel := Vector3.ZERO
	var i := 0
	while i < _bodies.size():
		var b: Node = _bodies[i]
		if not is_instance_valid(b):
			_bodies.remove_at(i)
			continue
		var body := b as CelestialBodyNode
		if body != null:
			var mu := body.gravitational_parameter()
			if mu > 0.0:
				var offset: Vector3 = body.global_position - pos
				# Clamp to the surface radius so gravity cannot blow up as
				# distance goes to zero at a body's centre.
				var d := maxf(offset.length(), maxf(body.radius_world(), 0.001))
				accel += offset.normalized() * (mu / (d * d))
		i += 1
	return accel

## Vacuum (0.0) in true open space - no aerodynamic drag between planets.
## Resolved against the nearest body, since you are only ever inside one
## atmosphere at a time.
func get_air_density(pos: Vector3) -> float:
	var body := get_nearest_body(pos) as CelestialBodyNode
	return body.air_density_at(pos) if body != null else 0.0

## Total radiant flux at a world position, W/m^2, summed over every emitting
## body. Drives sunlight strength in the atmosphere renderer, and is the hook
## the not-yet-built heat-damage system will read.
func get_irradiance(pos: Vector3) -> float:
	var total := 0.0
	for b in _bodies:
		if not is_instance_valid(b):
			continue
		var body := b as CelestialBodyNode
		if body != null:
			total += body.irradiance_at(pos)
	return total

## Brightest emitting body as seen from `pos` - the one that should cast
## shadows and drive the scattering pass. Null in a system with no star.
func get_dominant_star(pos: Vector3) -> Node:
	var best: Node = null
	var best_flux := 0.0
	for b in _bodies:
		if not is_instance_valid(b):
			continue
		var body := b as CelestialBodyNode
		if body == null:
			continue
		var flux := body.irradiance_at(pos)
		if flux > best_flux:
			best_flux = flux
			best = b
	return best

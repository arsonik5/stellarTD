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

const GRAVITY_MAGNITUDE := 20.0

var _bodies: Array[Node] = []

func register_body(planet: Node) -> void:
	if not _bodies.has(planet):
		_bodies.append(planet)

func unregister_body(planet: Node) -> void:
	_bodies.erase(planet)

## Nearest registered Planet to `pos` that `pos` is actually within the
## influence radius of, or null if none qualify (no bodies registered, or
## every registered body is too far away - true open space). Deliberately
## NOT just "whichever is least far" with no cutoff - two planets far apart
## need a real zero-gravity gap between them, not gravity always snapping to
## one side or the other no matter the distance.
func get_nearest_body(pos: Vector3) -> Node:
	var best: Node = null
	var best_dist := INF
	var i := 0
	while i < _bodies.size():
		var b: Node = _bodies[i]
		if not is_instance_valid(b):
			_bodies.remove_at(i)
			continue
		var planet := b as Planet
		var body_pos: Vector3 = b.global_position
		var d: float = body_pos.distance_to(pos)
		var in_range := planet == null or d <= planet.influence_radius()
		if d < best_dist and in_range:
			best_dist = d
			best = b
		i += 1
	return best

## The nearest body's VoxelTerrain, for dig/build/support raycasts - null in
## open space, same as get_nearest_body().
func get_nearest_terrain(pos: Vector3) -> VoxelTerrain:
	var planet := get_nearest_body(pos) as Planet
	return planet.terrain if planet != null else null

func get_planet_center(pos: Vector3) -> Vector3:
	var body := get_nearest_body(pos)
	if body == null:
		return pos
	var body_pos: Vector3 = body.global_position
	return body_pos

## Radial "up" (away from the nearest body's center) at a given world
## position - Vector3.UP as an arbitrary-but-stable fallback in true open
## space, where there's no real "up" at all.
func get_up(pos: Vector3) -> Vector3:
	var body := get_nearest_body(pos)
	if body == null:
		return Vector3.UP
	var body_pos: Vector3 = body.global_position
	var up := pos - body_pos
	return up.normalized() if up.length() > 0.0001 else Vector3.UP

## Zero in true open space (no body nearby) - a player/projectile genuinely
## floats/flies straight once far enough from every registered body.
func get_gravity_accel(pos: Vector3) -> Vector3:
	if get_nearest_body(pos) == null:
		return Vector3.ZERO
	return -get_up(pos) * GRAVITY_MAGNITUDE

## Vacuum (0.0) in true open space - no aerodynamic drag between planets,
## same as it should physically be. Each Planet exposes its own
## air_density() from its CelestialBody's atmosphere.
func get_air_density(pos: Vector3) -> float:
	var planet := get_nearest_body(pos) as Planet
	return planet.air_density() if planet != null else 0.0

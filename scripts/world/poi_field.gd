class_name PoiField
extends Node3D
## Points of interest on one planet (design/05-planets.md W5; NMS rule: something on the horizon from almost any
## landing spot).
##
## Sites are DATA: Planet.poi_sites() places them deterministically from the seed with a minimum ground spacing
## (a sphere-spots field), so every machine and every load sees the same probe on the same ridge, and nothing has to
## be saved. Scenes are instanced only near the player (STREAM_IN_M) and freed again past STREAM_OUT_M; the ground
## height comes from the generator itself (bisection), so a POI can appear before its terrain collider has streamed
## and still sit on the ground.
##
## Gameplay hooks: every instance is in group "poi" and carries metas "poi_type", "poi_id" (stable: body key + site
## index) and "poi_name". A site the player has already looted can be skipped by gameplay through `consumed` -
## that list is saved with the planet's state by whoever owns the loot (not built here).

const STREAM_IN_M := 2200.0
const STREAM_OUT_M := 3000.0
const CHECK_INTERVAL := 1.0

var planet: Planet
var consumed: Dictionary = {}       # poi_id -> true
var _sites: Array = []
var _live: Dictionary = {}          # site index -> Node3D
var _timer := 0.0

func setup(p: Planet) -> void:
	planet = p
	_sites = p.poi_sites()

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or planet == null or _sites.is_empty():
		return
	_timer = CHECK_INTERVAL
	var viewer := _viewer_position()
	if viewer == Vector3.INF:
		return
	var centre := planet.global_position
	var vdir := (viewer - centre).normalized()
	var rw := planet.radius_world()
	for i in _sites.size():
		var site: Dictionary = _sites[i]
		var ground_d: float = vdir.angle_to(site["dir"]) * rw
		if ground_d < STREAM_IN_M and not _live.has(i):
			_spawn(i, site)
		elif ground_d > STREAM_OUT_M and _live.has(i):
			var n: Node = _live[i]
			_live.erase(i)
			if is_instance_valid(n):
				n.queue_free()

## Instance count right now (tests / debug overlay).
func live_count() -> int:
	return _live.size()

func _viewer_position() -> Vector3:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		return player.global_position
	if cam != null:
		return cam.global_position
	return Vector3.INF

func _spawn(i: int, site: Dictionary) -> void:
	var spec: PoiSpec = site["spec"]
	var id := "%s:%d" % [planet.save_key(), i]
	if consumed.has(id) or spec == null:
		return
	var node: Node3D
	if spec.scene != null:
		node = spec.scene.instantiate()
	else:
		node = PoiBlockouts.build(spec.poi_type)
	var dir: Vector3 = site["dir"]
	var ground_r := planet.surface_radius_along(dir)
	if ground_r < 0.0:
		return
	add_child(node)
	# Body-local placement: up is the radial, yaw from the site's own seeded angle.
	var up := dir
	var ref := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var fwd := up.cross(ref).normalized().rotated(up, float(site["yaw"]))
	var right := fwd.cross(up).normalized()
	var basis := Basis(right, up, -fwd)
	node.global_transform = Transform3D(basis,
		planet.global_position + dir * (ground_r * Planet.VOXEL_SCALE - spec.sink_m))
	node.add_to_group("poi")
	node.set_meta("poi_type", spec.poi_type)
	node.set_meta("poi_id", id)
	node.set_meta("poi_name", spec.display_name)
	_live[i] = node

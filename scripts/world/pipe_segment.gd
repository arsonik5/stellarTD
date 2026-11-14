class_name PipeSegment
extends StaticBody3D

const ITEMS_PER_SECOND := 6.0
const _CUBE_START := Vector3(0.0, 0.45, 0.45)
const _CUBE_END := Vector3(0.0, 0.45, -0.45)
## Item speed through a plain pipe (m/s): the old fixed 0.9 m cell at ITEMS_PER_SECOND.
const ITEM_SPEED := 0.9 * ITEMS_PER_SECOND

## Modular model layout, from art_src/pipe/pipe.py: only the 1 m tube is ever scaled (along its length);
## collars, supports and bases keep their size and are placed for the span.
const PIPE_HEIGHT := 0.45          # centreline above the scene origin
const COLLAR_W := 0.07
const POST_TOP := -0.334           # post top, below the centreline
const POST_PREVIEW := 0.098        # the post's length in the model (scale = wanted / this)
const SUPPORT_SPACING := 2.5
const SUPPORT_REACH := 8.0         # supports look this far down for ground
const BASE_T := 0.018              # base plate thickness (origin on its underside)
## Knees: bend radius of the centreline, and the straight collar stub at each end of a knee.
const KNEE_RADIUS := 0.6
const KNEE_MIN_ANGLE := deg_to_rad(2.0)
const KNEE_MAX_ANGLE := deg_to_rad(150.0)

var grid_pos: Vector3i
var _held_item_id: String = ""
var _progress: float = 0.0
var _item_cube_material: StandardMaterial3D
var _span_length: float = 0.9
## Chained runs: the pipe this one hands items to / takes them from directly (set by relink_all()).
var _next: PipeSegment
var _prev: PipeSegment
## Inlet knee, in this pipe's local space: the joint point and the upstream flow direction. Empty = none.
var _knee: Dictionary = {}
var _knee_node: Node3D
var _supports: Array[Node3D] = []
var _support_retries := 0

@onready var _item_cube: MeshInstance3D = $ItemCube

func _ready() -> void:
	add_to_group("pipe")
	_item_cube_material = StandardMaterial3D.new()
	_item_cube_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_item_cube.material_override = _item_cube_material
	_item_cube.visible = false
	if _is_modular():
		_layout_body.call_deferred()

## Local -Z is this segment's forward/output direction, matching Godot's
## default "objects look along local -Z" convention (same one player.gd's own
## camera-forward raycast uses). Rounded to a grid step for the junction/grid code.
func forward() -> Vector3i:
	var dir := -global_transform.basis.z
	return Vector3i(roundi(dir.x), 0, roundi(dir.z))

## Exact 3D flow direction (pipes can slope).
func flow_dir() -> Vector3:
	return -global_transform.basis.z.normalized()

## --- Ports, in 3D (any orientation on a round planet) ---
## Where items enter / leave this piece, on the base plane (same plane as get_connection_points()). A plain pipe
## has one of each; the merger and splitter override these. Neighbours are found by matching ports in world space,
## not by stepping world-axis grid cells around world Y, which only worked where planet up happened to be +Y.
const PORT_TOL := 0.3

func input_ports() -> Array[Vector3]:
	var cps := get_connection_points()
	return [cps[0]]

func output_ports() -> Array[Vector3]:
	var cps := get_connection_points()
	return [cps[cps.size() - 1]]

## The pipe piece (not self) with an input port (want_input) or output port within PORT_TOL of `point`.
func _piece_with_port_near(point: Vector3, want_input: bool) -> PipeSegment:
	for n in get_tree().get_nodes_in_group("pipe"):
		var p := n as PipeSegment
		if p == null or p == self or not is_instance_valid(p):
			continue
		for q in (p.input_ports() if want_input else p.output_ports()):
			if q.distance_to(point) < PORT_TOL:
				return p
	return null

## What receives items from the output port at `port` (direction `outward`): a pipe piece whose input is there, or
## a building whose footprint is just past it.
func _receiver_at(port: Vector3, outward: Vector3) -> Node:
	var p := _piece_with_port_near(port, true)
	if p != null:
		return p
	return _building_at(port + outward * 0.4 + global_transform.basis.y * 0.3)

## Outward direction of a port: from this piece's centre on the base plane to the port.
func _outward(port: Vector3) -> Vector3:
	var d := port - global_position
	return d.normalized() if d.length() > 0.01 else flow_dir()

func _is_modular() -> bool:
	return has_node("Body") and $Body.find_child("*SupportPost", true, false) != null

## Where items enter (the knee's start when there is one) and leave this pipe, in global space.
func input_point() -> Vector3:
	if not _knee.is_empty():
		return to_global(_knee_geometry()["p0"])
	return global_position + global_transform.basis * Vector3(0, PIPE_HEIGHT, _span_length * 0.5)

func output_point() -> Vector3:
	return global_position + global_transform.basis * Vector3(0, PIPE_HEIGHT, -_span_length * 0.5)

## Direction items arrive in (the upstream pipe's direction when this pipe starts with a knee).
func input_dir() -> Vector3:
	if not _knee.is_empty():
		return (global_transform.basis * Vector3(_knee["dir"])).normalized()
	return flow_dir()

## Connection points sit on the scene origin's plane (the build grid's level), not on the centreline: the
## placement code adds the 0.45 m pipe height through the pipe's own transform.
func get_connection_points() -> Array[Vector3]:
	var lift := global_transform.basis.y * PIPE_HEIGHT
	return [input_point() - lift, output_point() - lift]

func set_span(length: float) -> void:
	_span_length = maxf(length, 0.25)
	$CollisionShape3D.scale.z = _span_length / 0.9
	$InputArrow.position.z = _span_length * 0.5
	$OutputArrow.position.z = -_span_length * 0.5
	_item_cube.position = Vector3(0.0, PIPE_HEIGHT, _span_length * 0.5)
	if _is_modular():
		_layout_body()

## Inlet knee: `joint` is where the upstream pipe's straight line and this pipe's line meet, `upstream_dir` the
## upstream flow direction, both global. The knee bends exactly through the angle between the two lines.
func set_knee(joint: Vector3, upstream_dir: Vector3, radius: float = KNEE_RADIUS) -> void:
	_knee = {"joint": to_local(joint), "dir": (global_transform.basis.inverse() * upstream_dir).normalized(), "r": radius}
	_build_knee()

func clear_knee() -> void:
	_knee = {}
	_build_knee()

## The straight length a knee of `angle` takes from each of the two lines it joins (arc tangent + collar stub).
## Radius: KNEE_RADIUS for a tight bend (straight runs), larger for the wide bends of curved runs.
static func knee_leg(angle: float, radius: float = KNEE_RADIUS) -> float:
	return radius * tan(angle * 0.5) + COLLAR_W

# ------------------------------------------------------------------ modular layout

func _layout_body() -> void:
	var body: Node3D = $Body
	body.scale = Vector3.ONE
	var tube := body.find_child("SM_VacuumPipe", false, false) as Node3D
	var end_in := body.find_child("*EndIn", true, false) as Node3D
	var end_out := body.find_child("*EndOut", true, false) as Node3D
	if tube == null or end_in == null or end_out == null:
		return
	tube.scale = Vector3(1, 1, maxf(_span_length - 2.0 * COLLAR_W, 0.01))
	tube.position = Vector3.ZERO
	end_in.position = Vector3(0, 0, _span_length * 0.5)
	end_out.position = Vector3(0, 0, -_span_length * 0.5)
	_layout_supports(body)

func _layout_supports(body: Node3D) -> void:
	var head := body.find_child("*SupportHead", true, false) as Node3D
	var post := body.find_child("*SupportPost", true, false) as Node3D
	var base := body.find_child("*SupportBase", true, false) as Node3D
	if head == null or post == null or base == null:
		return
	for s in _supports:
		s.queue_free()
	_supports.clear()
	head.visible = false
	post.visible = false
	base.visible = false
	if not is_inside_tree():
		return
	var count := maxi(1, ceili(_span_length / SUPPORT_SPACING))
	var usable := _span_length - 2.0 * COLLAR_W - 0.1
	if usable < 0.1:
		return
	var up := _planet_up(global_position, self)
	if absf(flow_dir().dot(up)) > 0.5:
		return                                    # steeper than 30 degrees: a riser hangs on its knees, no stands
	var space := get_world_3d().direct_space_state
	var missing := false
	# the model decides: the post node sits at its top (origin), its mesh is its preview length
	var post_top_y := post.position.y
	var post_len := POST_PREVIEW
	var pm := post as MeshInstance3D
	if pm != null and pm.mesh != null:
		post_len = pm.mesh.get_aabb().size.y
	for i in count:
		var z := -usable * 0.5 + usable * (i + 0.5) / count
		var at := global_position + global_transform.basis * Vector3(0, PIPE_HEIGHT, z)
		var post_top := at + global_transform.basis.y * post_top_y
		var q := PhysicsRayQueryParameters3D.create(post_top, post_top - up * SUPPORT_REACH)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			missing = true
			continue
		var ground: Vector3 = hit["position"]
		var length := (post_top - (ground + up * BASE_T)).dot(up)
		if length < 0.02:
			continue
		var s := Node3D.new()
		body.add_child(s)
		_supports.append(s)
		var h := head.duplicate() as Node3D
		h.visible = true
		s.add_child(h)
		h.position = Vector3(0, 0, z)
		var upright := Basis.looking_at(_tangent(up, flow_dir()), up)
		var p := post.duplicate() as Node3D
		p.visible = true
		s.add_child(p)
		p.top_level = true
		p.global_transform = Transform3D(upright * Basis.from_scale(Vector3(1, length / post_len, 1)), post_top)
		var b := base.duplicate() as Node3D
		b.visible = true
		s.add_child(b)
		b.top_level = true
		b.global_transform = Transform3D(upright, ground)
	# ground not there yet (terrain still streaming in after a load): try again in a moment
	if missing and _support_retries < 10:
		_support_retries += 1
		get_tree().create_timer(1.0).timeout.connect(_layout_body)

static func _tangent(up: Vector3, dir: Vector3) -> Vector3:
	var t := dir - up * dir.dot(up)
	if t.length() < 0.001:
		t = up.cross(Vector3.RIGHT)
		if t.length() < 0.001:
			t = up.cross(Vector3.FORWARD)
	return t.normalized()

# ------------------------------------------------------------------ knee

## The knee's path in local space: p0 (its input collar face), the arc from a0 to a1 round centre c about axis,
## and p1 (= this pipe's input end).
func _knee_geometry() -> Dictionary:
	var j: Vector3 = _knee["joint"]
	var d0: Vector3 = _knee["dir"]
	var d1 := Vector3(0, 0, -1)
	var angle := d0.angle_to(d1)
	var r: float = _knee.get("r", KNEE_RADIUS)
	var leg := knee_leg(angle, r)
	var k := leg - COLLAR_W
	var a0 := j - d0 * k
	var a1 := j + d1 * k
	var axis := d0.cross(d1).normalized()
	var to_c := (d1 - d0 * d0.dot(d1)).normalized()
	return {"p0": j - d0 * leg, "a0": a0, "a1": a1, "p1": j + d1 * leg, "d0": d0, "d1": d1, "angle": angle,
			"c": a0 + to_c * r, "axis": axis, "r": r, "len": 2.0 * COLLAR_W + r * angle}

func _build_knee() -> void:
	if _knee_node != null:
		_knee_node.queue_free()
		_knee_node = null
	if _knee.is_empty() or not _is_modular():
		return
	_knee_node = PipeKneeMesh.build(self, _knee_geometry())
	add_child(_knee_node)

## Point along the item path at distance s from the input (knee first, then the straight pipe), local space.
func _path_point(s: float) -> Vector3:
	if not _knee.is_empty():
		var g := _knee_geometry()
		var kl: float = g["len"]
		if s < kl:
			if s < COLLAR_W:
				return g["p0"] + g["d0"] * s
			if s > kl - COLLAR_W:
				return g["a1"] + g["d1"] * (s - (kl - COLLAR_W))
			var phi := (s - COLLAR_W) / float(g["r"])
			var c: Vector3 = g["c"]
			return c + (g["a0"] - c).rotated(g["axis"], phi)
		s -= kl
	return Vector3(0, PIPE_HEIGHT, _span_length * 0.5 - s)

func _path_length() -> float:
	return _span_length + (_knee_geometry()["len"] if not _knee.is_empty() else 0.0)

# ------------------------------------------------------------------ flow arrows

var _arrows: MeshInstance3D

## Arrowheads along the pipe pointing the way items move: shown on every pipe while a pipe is in the build tool.
func show_flow_arrows(on: bool) -> void:
	if not on or not _is_modular():
		if _arrows != null:
			_arrows.queue_free()
			_arrows = null
		return
	if _arrows != null:
		return
	var marks: Array = []
	var total := _path_length()
	var s := 0.5 if total > 1.0 else total * 0.5
	while s < total:
		var p := _path_point(s)
		var t := (_path_point(minf(s + 0.02, total)) - _path_point(maxf(s - 0.02, 0.0))).normalized()
		marks.append([p, t])
		s += 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	PipeRoute.arrows_into(st, marks, func(_p: Vector3) -> Vector3: return Vector3.UP, 0.31)
	_arrows = MeshInstance3D.new()
	_arrows.name = "FlowArrows"
	_arrows.mesh = st.commit()
	_arrows.material_override = arrow_material()
	_arrows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arrows)

static var _arrow_mat: StandardMaterial3D
static func arrow_material() -> StandardMaterial3D:
	if _arrow_mat == null:
		_arrow_mat = StandardMaterial3D.new()
		_arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_arrow_mat.albedo_color = Color(0.55, 1.0, 0.85)
	return _arrow_mat

# ------------------------------------------------------------------ items

func has_ready_item() -> bool:
	return _held_item_id != "" and _progress >= 1.0

func pipe_accept(item_id: String, _from_grid_pos: Vector3i = Vector3i.ZERO) -> bool:
	if _held_item_id != "":
		return false
	_held_item_id = item_id
	_progress = 0.0
	_item_cube.position = _cube_at(0.0)
	_item_cube.visible = true
	var item := Inventory.get_item_def(item_id)
	_item_cube_material.albedo_color = item.debug_color if item != null else Color.WHITE
	return true

func _cube_at(progress: float) -> Vector3:
	if not _is_modular():
		return _CUBE_START.lerp(_CUBE_END, progress)
	return _path_point(progress * _path_length())

func _physics_process(delta: float) -> void:
	if _held_item_id == "":
		_try_pull_from_input_side()
		return
	var step := ITEMS_PER_SECOND * delta
	if _is_modular():
		step = ITEM_SPEED * delta / maxf(_path_length(), 0.1)
	_progress = min(_progress + step, 1.0)
	_item_cube.position = _cube_at(_progress)
	if _progress >= 1.0:
		_try_advance()

func _try_advance() -> void:
	var target: Node = null
	if is_instance_valid(_next):
		target = _next
	elif _is_modular():
		target = _building_at(output_point() + flow_dir() * 0.4)
		if target == null:
			target = _piece_with_port_near(output_ports()[0], true)      # a merger/splitter at the outlet
		if target == null:
			target = PipeNetwork.get_node_at(_cell_of(output_point() + flow_dir() * 0.4))
	else:
		var port: Vector3 = output_ports()[0]
		target = _receiver_at(port, _outward(port))
		if target == null:
			target = PipeNetwork.get_node_at(grid_pos + forward())    # old saves laid on the flat grid
	if target == null:
		return
	var moved := false
	if target is PipeSegment:
		moved = target.pipe_accept(_held_item_id, grid_pos)
	elif target is Building:
		moved = target.add_input(_held_item_id, 1) > 0
	if moved:
		_held_item_id = ""
		_progress = 0.0
		_item_cube.visible = false

func _try_pull_from_input_side() -> void:
	if is_instance_valid(_prev):
		return                                    # the upstream pipe pushes into this one
	var source: Node
	if _is_modular():
		source = _building_at(input_point() - input_dir() * 0.4)
	else:
		var port: Vector3 = input_ports()[0]
		source = _building_at(port + _outward(port) * 0.4 + global_transform.basis.y * 0.3)
		if source == null:
			source = PipeNetwork.get_node_at(grid_pos - forward())
	if source == null or not (source is Building):
		return
	var building: Building = source
	var taken := building.pipe_take_one()
	if taken != "":
		pipe_accept(taken, grid_pos - forward())

## A building whose footprint holds `point` (ports sit on the footprint edge, so a point just past a pipe's end
## is inside the building it is connected to).
func _building_at(point: Vector3) -> Node:
	for b in get_tree().get_nodes_in_group("building"):
		var n := b as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var local := n.to_local(point)
		if absf(local.x) < 1.05 and absf(local.z) < 1.05 and local.y > -0.5 and local.y < 3.0:
			return n
	return null

static func _cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))

## Chains every plain pipe to the pipe whose output meets its input (within 5 cm). Run after placing a pipe and
## after loading a save: links are derived from geometry, so they are never saved.
static func relink_all(tree: SceneTree) -> void:
	var pipes: Array[PipeSegment] = []
	for n in tree.get_nodes_in_group("pipe"):
		var p := n as PipeSegment
		if p != null and is_instance_valid(p) and p._is_modular():
			pipes.append(p)
			p._next = null
			p._prev = null
	for p in pipes:
		var inp := p.input_point()
		for q in pipes:
			if q != p and q.output_point().distance_to(inp) < 0.05:
				q._next = p
				p._prev = q
				break

## --- Persistence (see scripts/save/save_manager.gd) ---
## Span, grid cell and the inlet knee are set by the placement code rather than by the scene, so unlike every
## other placed object a pipe is NOT fully described by its transform and has to store them. The item in transit
## is saved too - dropping it would quietly delete ore on every load. Links are rebuilt by relink_all().

func save_state() -> Dictionary:
	var out := {
		"grid_pos": [grid_pos.x, grid_pos.y, grid_pos.z],
		"span": _span_length,
		"held_item_id": _held_item_id,
		"progress": _progress,
	}
	if not _knee.is_empty():
		var j: Vector3 = _knee["joint"]
		var d: Vector3 = _knee["dir"]
		out["knee"] = [j.x, j.y, j.z, d.x, d.y, d.z, float(_knee.get("r", KNEE_RADIUS))]
	return out

func load_state(data: Dictionary) -> void:
	grid_pos = SaveManager.array_to_vec3i(data.get("grid_pos", []))
	set_span(float(data.get("span", 0.9)))
	var k: Array = data.get("knee", [])
	if k.size() >= 6:
		_knee = {"joint": Vector3(k[0], k[1], k[2]), "dir": Vector3(k[3], k[4], k[5]).normalized(),
				"r": float(k[6]) if k.size() >= 7 else KNEE_RADIUS}
		_build_knee()
	# Routed back through pipe_accept() rather than assigning the fields
	# directly, so the cube's colour and starting position come from the one
	# place that already knows how to set them.
	var held := String(data.get("held_item_id", ""))
	if held != "":
		pipe_accept(held)
		_progress = clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
		_item_cube.position = _cube_at(_progress)

## Planet "up" at a point (the PlanetPhysics autoload), or the node's own up where there is no planet (dev scenes).
static func _planet_up(p: Vector3, from: Node) -> Vector3:
	var pp := from.get_node_or_null("/root/PlanetPhysics")
	if pp != null and pp.has_method("get_up"):
		return pp.get_up(p)
	return Vector3.UP

## Checks whether a pipe can run on its centreline from `c_start` to `c_end` after `upstream` (null = a fresh
## start). Returns the knee leg (0 = no knee) or -1 when it can't: too sharp (> KNEE_MAX_ANGLE) or no room.
static func knee_leg_for(upstream: PipeSegment, c_start: Vector3, c_end: Vector3) -> float:
	if upstream == null:
		return 0.0
	var angle := upstream.flow_dir().angle_to((c_end - c_start).normalized())
	if angle > KNEE_MAX_ANGLE:
		return -1.0
	if angle < KNEE_MIN_ANGLE:
		return 0.0
	var leg := knee_leg(angle)
	if upstream._span_length - leg < 0.5 or c_start.distance_to(c_end) - leg < 0.5:
		return -1.0
	return leg

## Lays `segment` (already in the tree) on its centreline from `c_start` to `c_end`. With an `upstream` pipe and a
## knee leg > 0, the upstream pipe gives up one leg at its output end and this pipe starts one leg after the
## joint, with a knee bent through exactly the angle between them. The single place pipe geometry is decided
## (player placement and the dev pipe test both call it).
static func lay(segment: PipeSegment, c_start: Vector3, c_end: Vector3, upstream: PipeSegment, leg: float, up: Vector3) -> void:
	var d1 := (c_end - c_start).normalized()
	var upstream_dir := Vector3.ZERO
	if upstream != null and leg > 0.0:
		upstream_dir = upstream.flow_dir()
		var old_span := upstream._span_length
		upstream.global_position -= upstream_dir * (leg * 0.5)
		if not upstream._knee.is_empty():
			var j: Vector3 = upstream._knee["joint"]
			upstream._knee["joint"] = j + Vector3(0, 0, -leg * 0.5)
		upstream.set_span(old_span - leg)
		upstream._build_knee()
	var ref := up if absf(d1.dot(up)) < 0.999 else up.cross(Vector3.RIGHT).normalized()
	var basis := Basis.looking_at(d1, ref)
	var centre := (c_start + d1 * leg + c_end) * 0.5
	segment.global_transform = Transform3D(basis, centre - basis.y * PIPE_HEIGHT)
	segment.set_span(c_start.distance_to(c_end) - leg)
	if upstream != null and leg > 0.0:
		segment.set_knee(c_start, upstream_dir)

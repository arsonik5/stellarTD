extends Node
## PowerNetwork - grids, supply/demand, brownout (design/02-core-mechanics.md C10, roadmap G3).
##
## Topology: power poles (group "power_pole") link to every other pole within LINK_RANGE; a power building
## (any Building with power_draw > 0, a generator or a battery) plugs into the nearest pole within POLE_REACH.
## Each connected set of poles plus what is plugged into them is one grid with one shared pool.
##
## Every FactoryClock tick, per grid: supply = what generators can give, demand = what working consumers draw.
## Surplus charges batteries; a deficit drains them; what is still missing is a BROWNOUT: every consumer on that
## grid slows by the same fraction (readable, not punishing). Machines that do not need power still run without
## a grid at their base speed; power pushes them to POWERED_BOOST (design: "machines run faster on power").
## Machines that need power (needs_power) stop without it and say "No power".
##
## Distances are straight-line in 3D, so this works the same on any body at any orientation.

signal grids_changed

const LINK_RANGE := 16.0      # pole <-> pole, metres
const POLE_REACH := 9.0       # pole -> building, metres
## Work speed of a non-essential machine at full power (1.0 = its unpowered speed).
const POWERED_BOOST := 2.0

## Per grid: {"poles": [], "consumers": [], "producers": [], "batteries": [], "supply": kW, "demand": kW,
##  "satisfaction": 0..1, "stored": kJ, "capacity": kJ}
var grids: Array = []
var _grid_of: Dictionary = {}   # node -> grid index
var _dirty := true
var _wires: MeshInstance3D

func _ready() -> void:
	FactoryClock.tick.connect(_on_tick)
	GameEvents.building_placed.connect(func(_id: String, _n: Node) -> void: mark_dirty())
	GameEvents.building_removed.connect(func(_id: String, _n: Node) -> void: mark_dirty())
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is Building:
			mark_dirty())
	get_tree().node_removed.connect(func(n: Node) -> void:
		if n is Building:
			mark_dirty())

func mark_dirty() -> void:
	_dirty = true

## Grid info for a building ({} when it is not on a grid).
func grid_for(node: Node) -> Dictionary:
	if _dirty:
		rebuild()
	var i: int = _grid_of.get(node, -1)
	return grids[i] if i >= 0 and i < grids.size() else {}

static func is_power_node(b: Node) -> bool:
	if not (b is Building) or not is_instance_valid(b) or b.is_queued_for_deletion():
		return false
	return b.is_in_group("power_pole") or float(b.get("power_draw")) > 0.0 or b.has_method("power_available") \
		or b.has_method("battery_capacity")

func rebuild() -> void:
	_dirty = false
	grids.clear()
	_grid_of.clear()
	var tree := get_tree()
	var poles: Array = []
	for n in tree.get_nodes_in_group("power_pole"):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n.is_inside_tree():
			poles.append(n)
	# union-find over poles by link range
	var parent := range(poles.size())
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	var links: Array = []
	for i in poles.size():
		for j in range(i + 1, poles.size()):
			if (poles[i] as Node3D).global_position.distance_to((poles[j] as Node3D).global_position) <= LINK_RANGE:
				links.append([poles[i], poles[j]])
				var a: int = find.call(i)
				var b: int = find.call(j)
				if a != b:
					parent[a] = b
	var root_to_grid := {}
	for i in poles.size():
		var r: int = find.call(i)
		if not root_to_grid.has(r):
			root_to_grid[r] = grids.size()
			grids.append({"poles": [], "consumers": [], "producers": [], "batteries": [], "supply": 0.0,
				"demand": 0.0, "satisfaction": 1.0, "stored": 0.0, "capacity": 0.0})
		var g: int = root_to_grid[r]
		grids[g].poles.append(poles[i])
		_grid_of[poles[i]] = g
	# plug buildings into the nearest pole in reach
	var plugs: Array = []
	for n in tree.get_nodes_in_group("building"):
		if n.is_in_group("power_pole") or not is_power_node(n) or not n.is_inside_tree():
			continue
		var best: Node3D = null
		var best_d := POLE_REACH
		for p: Node3D in poles:
			var d := p.global_position.distance_to((n as Node3D).global_position)
			if d <= best_d:
				best_d = d
				best = p
		if best == null:
			continue
		var gi: int = _grid_of[best]
		_grid_of[n] = gi
		plugs.append([best, n])
		if n.has_method("power_available"):
			grids[gi].producers.append(n)
		if n.has_method("battery_capacity"):
			grids[gi].batteries.append(n)
		if float(n.get("power_draw")) > 0.0:
			grids[gi].consumers.append(n)
	_draw_wires(links, plugs)
	grids_changed.emit()

func _on_tick(dt: float) -> void:
	if _dirty:
		rebuild()
	var on_grid := {}
	for g: Dictionary in grids:
		_step_grid(g, dt)
		for c in g.consumers:
			on_grid[c] = true
	# consumers on no grid run at their unpowered speed
	for n in get_tree().get_nodes_in_group("building"):
		if not on_grid.has(n) and n is Building and float(n.get("power_draw")) > 0.0:
			(n as Building).work_speed = 0.0 if n.needs_power else 1.0

func _step_grid(g: Dictionary, dt: float) -> void:
	var supply := 0.0
	for p in g.producers:
		if is_instance_valid(p):
			supply += float(p.power_available())
	var demand := 0.0
	for c in g.consumers:
		if is_instance_valid(c) and c.wants_power():
			demand += float(c.power_draw)
	var stored := 0.0
	var capacity := 0.0
	for b in g.batteries:
		if is_instance_valid(b):
			stored += float(b.stored_kj)
			capacity += float(b.battery_capacity())
	var satisfaction := 1.0
	var used_from_generators := minf(supply, demand)
	if supply >= demand:
		# surplus charges the batteries (each up to its own rate)
		var surplus := (supply - demand) * dt
		for b in g.batteries:
			if surplus <= 0.0:
				break
			if is_instance_valid(b):
				var took: float = b.charge(surplus, dt)
				surplus -= took
				used_from_generators += took / dt
	else:
		var missing := (demand - supply) * dt
		for b in g.batteries:
			if missing <= 0.0:
				break
			if is_instance_valid(b):
				missing -= b.discharge(missing, dt)
		satisfaction = clampf(1.0 - missing / (demand * dt), 0.0, 1.0) if demand > 0.0 else 1.0
	# generators burn fuel for what was actually drawn from them
	for p in g.producers:
		if is_instance_valid(p) and supply > 0.0:
			p.power_drawn(used_from_generators * float(p.power_available()) / supply, dt)
	for c in g.consumers:
		if not is_instance_valid(c):
			continue
		var b := c as Building
		b.work_speed = satisfaction if b.needs_power else lerpf(1.0, POWERED_BOOST, satisfaction)
	g.supply = supply
	g.demand = demand
	g.satisfaction = satisfaction
	g.stored = stored
	g.capacity = capacity

## Wires: one immediate-mesh line per link (pole-pole) and per plug (pole-building), redrawn on topology change.
func _draw_wires(links: Array, plugs: Array) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _wires == null or not is_instance_valid(_wires):
		_wires = MeshInstance3D.new()
		_wires.name = "PowerWires"
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.12, 0.12, 0.13)
		_wires.material_override = m
		_wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _wires.get_parent() != scene:
		if _wires.get_parent() != null:
			_wires.get_parent().remove_child(_wires)
		scene.add_child(_wires)
	var im := ImmediateMesh.new()
	if links.is_empty() and plugs.is_empty():
		_wires.mesh = null
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair in links + plugs:
		var a: Node3D = pair[0]
		var b: Node3D = pair[1]
		var ta := _wire_point(a)
		var tb := _wire_point(b)
		# a little sag at the middle, along the local down: cables hang, rods don't
		var mid := (ta + tb) * 0.5 - PlanetPhysics.get_up((ta + tb) * 0.5) * ta.distance_to(tb) * 0.06
		im.surface_add_vertex(ta)
		im.surface_add_vertex(mid)
		im.surface_add_vertex(mid)
		im.surface_add_vertex(tb)
	im.surface_end()
	_wires.mesh = im
	_wires.global_transform = Transform3D.IDENTITY

func _wire_point(n: Node3D) -> Vector3:
	var h: float = 2.9 if n.is_in_group("power_pole") else 1.2
	return n.global_position + PlanetPhysics.get_up(n.global_position) * h

## Nothing to persist: topology is derived from placed buildings, battery charge and fuel live in the buildings.
func save_state() -> Dictionary:
	return {}

func load_state(_data: Dictionary) -> void:
	mark_dirty()

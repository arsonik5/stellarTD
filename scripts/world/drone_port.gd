class_name DronePort
extends Building
## Drone Port (first robot, design C5 "Haul" card - arc 5 teaser): a powered pad that launches one cargo drone.
## Pick a SOURCE and a DESTINATION storage in its panel (any building within RANGE that holds items); the drone
## flies - a real rigid body under radial gravity - to the source, loads up to CARGO items of whatever is there,
## flies to the destination and unloads, forever, while the port has power. A robot doing your carrying.

const RANGE := 80.0
const CARGO := 20

var source: Building
var destination: Building
var drone: CargoDrone
var trips := 0
## Saved as positions (buildings have no stable ids); resolved to the nearest building on load.
var _source_pos := Vector3.INF
var _dest_pos := Vector3.INF

func _ready() -> void:
	recipes = []
	inventory_slots = 0
	inventory_capacity = 0
	modifier_slots = 0
	max_health = 300.0
	power_draw = 15.0
	needs_power = true
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()
	_spawn_drone.call_deferred()

func can_accept_input(_id: String, _n: int) -> bool:
	return false

func wants_power() -> bool:
	return true

func _spawn_drone() -> void:
	if not is_inside_tree():
		return
	if _source_pos != Vector3.INF:
		source = _nearest_storage(_source_pos)
	if _dest_pos != Vector3.INF:
		destination = _nearest_storage(_dest_pos)
	drone = load("res://scenes/cargo_drone.tscn").instantiate()
	drone.port = self
	get_tree().current_scene.add_child(drone)
	drone.global_position = pad_point()

## Where the drone rests: just above the pad, along local up.
func pad_point() -> Vector3:
	return global_position + PlanetPhysics.get_up(global_position) * 1.4

func idle_reason() -> String:
	if work_speed <= 0.0:
		return "No power"
	if not _valid(source) or not _valid(destination):
		return "Pick a source and a destination"
	return ""

func status_text() -> String:
	var r := idle_reason()
	if r != "":
		return r.to_upper()
	return "HAULING  ·  %d TRIPS  ·  %s" % [trips, drone.state_name() if drone != null else ""]

func get_active_recipe_index() -> int:
	return 0 if idle_reason() == "" else -1

static func _valid(b: Node) -> bool:
	return b != null and is_instance_valid(b) and not b.is_queued_for_deletion()

## Storage-like buildings in range (chests, drills, crushers, anything that holds items and is not this port).
func storages_in_range() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("building"):
		var b := n as Building
		if b == null or b == self or b is DronePort or b.inventory_slots <= 0:
			continue
		if b.global_position.distance_to(global_position) <= RANGE:
			out.append(b)
	out.sort_custom(func(a: Node3D, c: Node3D) -> bool: return a.global_position.distance_to(global_position) < c.global_position.distance_to(global_position))
	return out

func _nearest_storage(p: Vector3) -> Building:
	var best: Building = null
	var best_d := 1.0
	for b in storages_in_range():
		var d: float = (b as Node3D).global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = b
	return best

func set_route(src: Building, dst: Building) -> void:
	source = src
	destination = dst

func build_ui_extras(box: VBoxContainer, refresh: Callable) -> void:
	box.add_child(UiKit.section("Route"))
	box.add_child(UiKit.label("The drone carries up to %d items per trip from the source to the destination." % CARGO, "DimLabel"))
	for b in storages_in_range():
		var row := UiKit.hbox(6)
		var def := Inventory.get_item_def(String(b.get_meta(SaveManager.ITEM_ID_META, "")))
		var nm := UiKit.label("%s  ·  %d m  ·  %d items" % [def.display_name if def else b.name,
			roundi((b as Node3D).global_position.distance_to(global_position)), (b as Building).get_total_count()])
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var s := UiKit.button("Source", func() -> void:
			source = b
			refresh.call())
		s.toggle_mode = true
		s.button_pressed = b == source
		row.add_child(s)
		var d := UiKit.button("Destination", func() -> void:
			destination = b
			refresh.call())
		d.toggle_mode = true
		d.button_pressed = b == destination
		row.add_child(d)
		box.add_child(row)
	PowerUi.grid_section(box, self)

func save_state() -> Dictionary:
	var d := super.save_state()
	d["route"] = {
		"src": SaveManager.vec3_to_array(source.global_position) if _valid(source) else [],
		"dst": SaveManager.vec3_to_array(destination.global_position) if _valid(destination) else [],
		"trips": trips}
	return d

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	var r: Dictionary = data.get("route", {})
	trips = int(r.get("trips", 0))
	if (r.get("src", []) as Array).size() == 3:
		_source_pos = SaveManager.array_to_vec3(r["src"])
	if (r.get("dst", []) as Array).size() == 3:
		_dest_pos = SaveManager.array_to_vec3(r["dst"])
	# restored buildings appear in the same frame; resolve the route once they all exist
	(func() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		if _source_pos != Vector3.INF:
			source = _nearest_storage(_source_pos)
		if _dest_pos != Vector3.INF:
			destination = _nearest_storage(_dest_pos)).call()

func _exit_tree() -> void:
	if drone != null and is_instance_valid(drone):
		drone.queue_free()

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# landing pad on four short legs; charging contacts in the middle; a mast light shows the port is live
	Blockout.box(m, Vector3(1.9, 0.12, 1.9), Vector3(0, 0.5, 0), Blockout.PAINT)
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		Blockout.box(m, Vector3(0.15, 0.5, 0.15), Vector3(d.x * 0.8, 0.22, d.y * 0.8), Blockout.STEEL)
	Blockout.box(m, Vector3(0.6, 0.04, 0.6), Vector3(0, 0.58, 0), Color(0.75, 0.5, 0.25))
	Blockout.box(m, Vector3(0.08, 1.2, 0.08), Vector3(0.85, 1.15, 0.85), Blockout.STEEL)
	Blockout.cyl(m, 0.07, 0.1, Vector3(0.85, 1.8, 0.85), UiTokens.ACCENT, "y", "Light", true)

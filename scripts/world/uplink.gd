class_name Uplink
extends Building
## Uplink (design M26): where the factory's work leaves the planet. It accepts only goods that an open Directive
## still needs (pipes stop pushing anything else), hands them to Progression, and every LAUNCH_BATCH items - or
## the moment a directive completes - fires a capsule up its rail along the body's radial up. Launches are loud:
## they spike the radiation signature (GameEvents.signature_spike, read by RadiationSignature in G4).

const DELIVER_INTERVAL := 0.5        # seconds between hand-overs
const DELIVER_PER_STEP := 5
const LAUNCH_BATCH := 20
const LAUNCH_TIME := 3.5             # seconds the capsule takes to clear the sky
const LAUNCH_HEIGHT := 140.0
## Signature added per launched item - launches are what make an uplink base visible from orbit.
const SIGNATURE_PER_ITEM := 0.15

var launched_total := 0
var _pending := 0                    # delivered since the last launch
var _timer := 0.0
var _capsule: Node3D
var _flights: Array = []             # [node, t]

func _ready() -> void:
	recipes = []
	inventory_slots = 8
	inventory_capacity = 200
	max_health = 600.0
	marker_height = 5.4
	if get_node_or_null("Model") == null:
		_build_blockout()
	power_draw = 10.0
	super._ready()
	FactoryClock.tick.connect(_on_uplink_tick)

func can_accept_input(item_id: String, amount: int) -> bool:
	return Progression.wants(item_id) and get_total_count() + amount <= inventory_capacity

func output_ids() -> Array:
	return []

func idle_reason() -> String:
	if work_speed <= 0.0:
		return "No power"
	if Progression.open_directives().is_empty():
		return "No open orders"
	return ""

func status_text() -> String:
	var r := idle_reason()
	if r != "":
		return r.to_upper()
	return "LINKED  ·  %d LAUNCHED" % launched_total if get_total_count() == 0 else "LOADING  ·  %d / %d" % [_pending, LAUNCH_BATCH]

func get_active_recipe_index() -> int:
	return 0 if get_total_count() > 0 and idle_reason() == "" else -1

func get_process_progress() -> float:
	return clampf(float(_pending) / float(LAUNCH_BATCH), 0.0, 1.0)

func _on_uplink_tick(dt: float) -> void:
	_timer += dt * work_speed
	if _timer < DELIVER_INTERVAL:
		return
	_timer = 0.0
	deliver_step()

## Hand up to DELIVER_PER_STEP items to Progression. Public for tests.
func deliver_step() -> int:
	var budget := DELIVER_PER_STEP
	var moved := 0
	var done_before := Progression.completed.size()
	for slot in _inventory:
		if budget <= 0:
			break
		if slot.item_id == "" or slot.count <= 0:
			continue
		var id: String = slot.item_id
		var n := Progression.deliver(id, mini(slot.count, budget))
		if n > 0:
			remove_item(id, n)
			moved += n
			budget -= n
	_pending += moved
	# a full capsule goes up; so does a part-load that just finished a directive (nobody waits for the rest)
	if _pending >= LAUNCH_BATCH or (_pending > 0 and Progression.completed.size() > done_before):
		launch()
	return moved

## Fire a capsule with whatever has been delivered since the last launch.
func launch() -> void:
	if _pending <= 0:
		return
	var n := _pending
	_pending = 0
	launched_total += n
	GameEvents.signature_spike.emit(n * SIGNATURE_PER_ITEM, self)
	GameEvents.uplink_launched.emit(n, self)
	UiSound.play("confirm")
	if _capsule == null or not is_inside_tree():
		return
	# a copy of the cradle capsule flies; the cradle one stays as the next load
	var c := _capsule.duplicate() as Node3D
	get_tree().current_scene.add_child(c)
	c.global_transform = _capsule.global_transform
	var flame := Blockout.cyl(c, 0.12, 0.6, Vector3(0, -0.6, 0), Color(1.0, 0.6, 0.2), "y", "", true)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flights.append([c, 0.0, c.global_position, PlanetPhysics.get_up(global_position)])

func _process(delta: float) -> void:
	super._process(delta)
	for f in _flights.duplicate():
		var node: Node3D = f[0]
		if not is_instance_valid(node):
			_flights.erase(f)
			continue
		f[1] += delta
		var t: float = f[1] / LAUNCH_TIME
		# eased climb: slow off the rail, then fast - a launch, not a lift
		node.global_position = f[2] + f[3] * LAUNCH_HEIGHT * t * t
		if t >= 1.0:
			node.queue_free()
			_flights.erase(f)

## Open directives and their progress, in the machine panel.
func build_ui_extras(box: VBoxContainer, _refresh: Callable) -> void:
	box.add_child(UiKit.section("Open orders"))
	var open := Progression.open_directives()
	if open.is_empty():
		box.add_child(UiKit.label("No open orders. Finish the tutorial objectives first.", "DimLabel"))
	for d: Dictionary in open:
		box.add_child(UiKit.label(String(d.title), "HudLabel"))
		var got := Progression.progress_of(d)
		for i in d.item_ids.size():
			var def := Inventory.get_item_def(d.item_ids[i])
			var have := int(got.get(d.item_ids[i], 0))
			box.add_child(UiKit.label("   %s  %d / %d" % [def.display_name if def else d.item_ids[i], have, int(d.amounts[i])],
				"AccentLabel" if have >= int(d.amounts[i]) else "DimLabel"))
	box.add_child(UiKit.label("Launched so far: %d  ·  Credit %d" % [launched_total, Progression.credit], "DimLabel"))

func save_state() -> Dictionary:
	var d := super.save_state()
	d["uplink"] = {"launched": launched_total, "pending": _pending}
	return d

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	var u: Dictionary = data.get("uplink", {})
	launched_total = int(u.get("launched", 0))
	_pending = int(u.get("pending", 0))

## Blockout (no Blender model yet). Every part has a job:
func _build_blockout() -> void:
	var m := Blockout.root(self)
	# launch pad: a thick concrete slab that takes the blast
	Blockout.box(m, Vector3(1.9, 0.3, 1.9), Vector3(0, 0.15, 0), Blockout.PAINT)
	# blast deflector plate under the rail foot (scorched dark)
	Blockout.box(m, Vector3(0.8, 0.06, 0.8), Vector3(-0.3, 0.33, 0), Blockout.DARK)
	# launch rail: two guide rails on a spine, bolted to the slab, the capsule rides between them
	Blockout.box(m, Vector3(0.12, 4.6, 0.12), Vector3(-0.3, 2.6, 0.22), Blockout.STEEL)
	Blockout.box(m, Vector3(0.12, 4.6, 0.12), Vector3(-0.3, 2.6, -0.22), Blockout.STEEL)
	Blockout.box(m, Vector3(0.1, 4.6, 0.5), Vector3(-0.42, 2.6, 0), Blockout.DARK)
	Blockout.bolts(m, Vector3(-0.35, 0.3, 0), 0.3)
	# capsule in its cradle at the foot of the rail
	_capsule = Node3D.new()
	_capsule.name = "Capsule"
	_capsule.position = Vector3(-0.3, 1.0, 0)
	m.add_child(_capsule)
	Blockout.cyl(_capsule, 0.2, 0.9, Vector3.ZERO, Blockout.HAZARD)
	Blockout.cyl(_capsule, 0.12, 0.25, Vector3(0, 0.55, 0), Blockout.STEEL)
	# loading hopper on the input side: goods arrive by pipe here and are packed into the capsule
	Blockout.box(m, Vector3(0.6, 0.7, 0.8), Vector3(0.55, 0.65, 0), Blockout.PAINT)
	Blockout.port(m, 0.55)
	# antenna mast + dish: the link to Earth that brings Directives in
	Blockout.box(m, Vector3(0.1, 1.6, 0.1), Vector3(0.6, 1.8, 0.6), Blockout.STEEL)
	var dish := Blockout.cyl(m, 0.45, 0.06, Vector3(0.6, 2.65, 0.6), Blockout.PAINT)
	dish.rotation.x = 0.6
	Blockout.cyl(m, 0.06, 0.1, Vector3(0.6, 2.75, 0.68), UiTokens.ACCENT, "y", "Light", true)

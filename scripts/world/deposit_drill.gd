class_name DepositDrill
extends Building
## Deposit Drill (design/02-core-mechanics.md C2): the automated half of extraction. It really bores the voxel
## terrain under itself with the hand drill's own bite code (TerrainDrill), pays ore for the rock it removes,
## and holds it for pipes to carry away. The shaft it leaves is the feedback: walk up and look down the hole.
##
## Boring pattern: a shaft straight down (along the body's radial "down", never world Y) from just under the base;
## the head advances when the rock around it is gone, to MAX_DEPTH_M. Then the next shaft of PATTERN, offset to
## the side, so one drill opens a pit ~5 m across. When every shaft is at full depth the drill is exhausted and
## must be moved - deposits are finite per region (open decision 2, proposed default).
##
## Stone is voided by default (a drill that fills up with rubble and stops is not fun); "Keep stone" sends it out
## with the ore for a crusher line.
##
## Terrain only exists near a viewer: when the bore area is not editable (streamed out), the drill pauses with a
## reason rather than pretending - see idle_reason().

const BITE_INTERVAL := 0.25          # seconds between bites at full power (4 bites/s; the hand drill is 20/s)
const BORE_RADIUS_M := 1.0
## A machine bit cuts harder than the hand drill per bite (it bites 5x less often). Tuned in drill_test: ~0.3 m/s
## down through stone, so a 24 m shaft takes ~1.5 min and a 5-shaft pit ~7 min - long enough to be a building,
## short enough to see it work.
const STRENGTH_MULT := 3.0
## The head starts half a radius under the base so the first bites break the surface: the open mouth of the pit
## is the drill's main feedback (starting a full radius down only dimpled the ground).
const START_DEPTH_M := 0.5
const STEP_M := 0.5                  # head advance once the face around it is clear
const MAX_DEPTH_M := 24.0            # iron sits 2-34 m down: mk1 reaches most shallow deposits
## Lateral offsets (metres, in the drill's own tangent frame) of the shafts it bores in order.
const PATTERN := [Vector2(0, 0), Vector2(1.6, 0), Vector2(-1.6, 0), Vector2(0, 1.6), Vector2(0, -1.6)]
## The head moves on once its centre voxel is at most this solid, or after MAX_BITES_HERE bites at one spot.
const CLEAR_SOLID := 0.25
const MAX_BITES_HERE := 80

var keep_stone := false
var depth_m := START_DEPTH_M
var shaft := 0
var exhausted := false
var mined: Dictionary = {}           # item_id -> total paid, for the panel and statistics
var _carry: Dictionary = {}
var _bite_timer := 0.0
var _bites_here := 0
## Bites taken over this drill's life (statistics; tests check the clock drives it).
var bites_total := 0
var _blocked_reason := ""
var _last_item := ""
var _bit: Node3D
var _light: MeshInstance3D

func _ready() -> void:
	recipes = []
	inventory_slots = 6
	inventory_capacity = 300
	max_health = 400.0
	if get_node_or_null("Model") == null:
		_build_blockout()
	power_draw = 25.0
	compatible_modifiers = ["speed_module", "efficiency_module", "yield_module"]
	super._ready()
	FactoryClock.tick.connect(_on_drill_tick)

## Extractors take nothing in.
func can_accept_input(_item_id: String, _amount: int) -> bool:
	return false

func can_add_output(_item_id: String, amount: int) -> bool:
	return get_total_count() + amount <= inventory_capacity

## Everything it holds is output.
func output_ids() -> Array:
	var ids := []
	for slot in _inventory:
		if slot.item_id != "" and not ids.has(slot.item_id):
			ids.append(slot.item_id)
	return ids

func idle_reason() -> String:
	if exhausted:
		return "Depleted - move the drill"
	if work_speed <= 0.0:
		return "No power"
	if get_total_count() >= inventory_capacity:
		return "Output full"
	return _blocked_reason

func status_text() -> String:
	var r := idle_reason()
	if r != "":
		return r.to_upper()
	return "BORING  ·  SHAFT %d/%d  ·  %.1f m" % [shaft + 1, PATTERN.size(), depth_m]

func get_process_progress() -> float:
	return clampf(_bite_timer / BITE_INTERVAL, 0.0, 1.0)

func get_active_recipe_index() -> int:
	return 0 if idle_reason() == "" else -1

## World-space centre of the bore head right now.
func head_position() -> Vector3:
	var up := PlanetPhysics.get_up(global_position)
	var b := global_transform.basis
	# the drill's own tangent axes, re-orthogonalised against the true radial up
	var x := (b.x - up * b.x.dot(up)).normalized()
	var z := up.cross(x).normalized() * -1.0
	var off: Vector2 = PATTERN[shaft]
	return global_position + x * off.x + z * off.y - up * depth_m

func _on_drill_tick(dt: float) -> void:
	if exhausted:
		_spin(0.0)
		return
	_bite_timer += dt * work_speed * modifier_speed()
	if _bite_timer < BITE_INTERVAL:
		return
	_bite_timer -= BITE_INTERVAL
	if get_total_count() >= inventory_capacity:
		_spin(0.0)
		return
	bite_once()

## One bite at the head. Public so tests can drive it without waiting on the clock.
func bite_once() -> Dictionary:
	var terrain := PlanetPhysics.get_nearest_terrain(global_position)
	if terrain == null:
		_blocked_reason = "No ground to drill"
		return {}
	var tool := terrain.get_voxel_tool()
	var scale := terrain.scale.x if terrain.scale.x > 0.0001 else 1.0
	var r_local := BORE_RADIUS_M / scale
	var head_local := terrain.to_local(head_position())
	var area := AABB(head_local - Vector3.ONE * (r_local + 2.0), Vector3.ONE * (r_local + 2.0) * 2.0)
	if not tool.is_area_editable(area):
		_blocked_reason = "Terrain not loaded - stay within range"
		_spin(0.0)
		return {}
	_blocked_reason = ""
	bites_total += 1
	var material := TerrainDrill.dominant_material_at(tool, Vector3i(head_local.floor()))
	var removed := TerrainDrill.bite(tool, head_local, r_local, minf(TerrainDrill.strength_for(material) * STRENGTH_MULT, 1.0))
	# a yield module pays more for the same rock (it sorts the cuttings better)
	var paid := TerrainDrill.payout(_carry, removed, scale * scale * scale * modifier_yield())
	for id: String in paid:
		if id == "stone" and not keep_stone:
			continue
		var n: int = paid[id]
		add_output(id, n)
		mined[id] = int(mined.get(id, 0)) + n
		_last_item = id
		GameEvents.item_mined.emit(id, n, self)
	_spin(1.0)
	if bites_total % 4 == 0:
		var up_w := PlanetPhysics.get_up(global_position)
		WorldFx.burst("dust", global_position + up_w * 0.3, up_w)
		WorldFx.sound("drill_machine", global_position, 1.0, 0.25)
	# Stay at this depth until the head centre is cut out, then step down half a radius so the next sphere
	# overlaps and finishes the walls. Not "until nothing is removed": deep rock's SDF has to travel a long way
	# before any volume counts as removed, so the first bites at a new spot remove ~0 and that rule raced the head
	# down a needle without paying. MAX_BITES_HERE bails out of rock too hard for this drill tier.
	_bites_here += 1
	tool.set_channel(VoxelBuffer.CHANNEL_SDF)
	var centre_solid := clampf(0.5 - tool.get_voxel_f(Vector3i(head_local.round())), 0.0, 1.0)
	if centre_solid < CLEAR_SOLID or _bites_here >= MAX_BITES_HERE:
		_advance()
	return paid

func _advance() -> void:
	_bites_here = 0
	depth_m += STEP_M
	if depth_m <= MAX_DEPTH_M:
		return
	shaft += 1
	depth_m = START_DEPTH_M
	if shaft >= PATTERN.size():
		shaft = PATTERN.size() - 1
		depth_m = MAX_DEPTH_M
		exhausted = true
		_spin(0.0)

func _spin(on: float) -> void:
	if _bit != null:
		_bit.set_meta("spin", on)
	if _light != null:
		var m := _light.material_override as StandardMaterial3D
		var col := UiTokens.GOOD if on > 0.0 else (UiTokens.DANGER if exhausted else UiTokens.WARN)
		m.albedo_color = col
		m.emission = col

func _process(delta: float) -> void:
	super._process(delta)
	if _bit != null and float(_bit.get_meta("spin", 0.0)) > 0.0:
		_bit.rotate_object_local(Vector3.UP, delta * 6.0)

## Machine panel: a "Keep stone" toggle and what this drill has paid so far.
func build_ui_extras(box: VBoxContainer, refresh: Callable) -> void:
	box.add_child(UiKit.section("Drill"))
	var row := UiKit.hbox(6)
	box.add_child(row)
	var b := UiKit.button("Keep stone")
	b.toggle_mode = true
	b.button_pressed = keep_stone
	b.tooltip_text = "Send stone out with the ore (for a crusher). Off: stone is left in the hole."
	b.toggled.connect(func(on: bool) -> void:
		keep_stone = on
		refresh.call())
	row.add_child(b)
	var parts := []
	for id: String in mined:
		var def := Inventory.get_item_def(id)
		parts.append("%s %d" % [def.display_name if def else id, mined[id]])
	box.add_child(UiKit.label("Mined: " + (", ".join(parts) if not parts.is_empty() else "nothing yet"), "DimLabel"))
	box.add_child(UiKit.label("Shaft %d of %d, %.1f m of %.0f m" % [shaft + 1, PATTERN.size(), depth_m, MAX_DEPTH_M], "DimLabel"))
	PowerUi.grid_section(box, self)

func save_state() -> Dictionary:
	var d := super.save_state()
	d["drill"] = {"keep_stone": keep_stone, "depth": depth_m, "shaft": shaft, "exhausted": exhausted,
		"mined": mined.duplicate(), "carry": _carry.duplicate()}
	return d

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	var d: Dictionary = data.get("drill", {})
	keep_stone = bool(d.get("keep_stone", false))
	depth_m = float(d.get("depth", START_DEPTH_M))
	shaft = clampi(int(d.get("shaft", 0)), 0, PATTERN.size() - 1)
	exhausted = bool(d.get("exhausted", false))
	mined = d.get("mined", {}).duplicate()
	_carry = d.get("carry", {}).duplicate()

## Blockout (no Blender model yet). Every part has a job:
func _build_blockout() -> void:
	var m := Blockout.root(self)
	# two skids carry the whole rig and spread its weight on loose regolith
	Blockout.box(m, Vector3(1.9, 0.18, 0.22), Vector3(0, 0.09, 0.75), Blockout.DARK)
	Blockout.box(m, Vector3(1.9, 0.18, 0.22), Vector3(0, 0.09, -0.75), Blockout.DARK)
	# deck plate bolted across the skids: the floor the mast stands on, with the bore hole in its centre
	Blockout.box(m, Vector3(1.9, 0.1, 1.9), Vector3(0, 0.23, 0), Blockout.PAINT)
	# mast: four corner posts welded to the deck, a top frame tying them together - takes the drill's reaction torque
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		Blockout.box(m, Vector3(0.12, 2.3, 0.12), Vector3(d.x * 0.6, 1.43, d.y * 0.6), Blockout.STEEL)
	Blockout.box(m, Vector3(1.32, 0.14, 1.32), Vector3(0, 2.6, 0), Blockout.STEEL)
	# gearbox + motor hang under the top frame and turn the kelly bar
	Blockout.box(m, Vector3(0.6, 0.45, 0.6), Vector3(0, 2.3, 0), Blockout.PAINT)
	Blockout.bolts(m, Vector3(0, 2.52, 0), 0.24)
	Blockout.cyl(m, 0.2, 0.5, Vector3(0.45, 2.3, 0), Blockout.DARK, "x")     # motor, flanged to the gearbox side
	# kelly bar: the spinning drill pipe from gearbox down through the deck into the hole (hazard-striped: it moves)
	_bit = Node3D.new()
	_bit.name = "Bit"
	m.add_child(_bit)
	Blockout.cyl(_bit, 0.09, 2.3, Vector3(0, 1.0, 0), Blockout.HAZARD)
	Blockout.box(_bit, Vector3(0.05, 2.2, 0.22), Vector3(0, 1.0, 0), Blockout.STEEL)  # flight on the bar, shows the spin
	# collection hopper beside the bore: cuttings are lifted into it; it feeds the output port
	Blockout.box(m, Vector3(0.5, 0.55, 0.8), Vector3(0.62, 0.55, 0), Blockout.PAINT)
	Blockout.port(m, 0.55)
	# status light on the top frame: mint = boring, amber = waiting, red = depleted
	_light = Blockout.cyl(m, 0.08, 0.12, Vector3(0.55, 2.73, 0.55), UiTokens.WARN, "y", "Light", true)

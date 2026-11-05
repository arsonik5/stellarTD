class_name BurnerGenerator
extends Building
## Burner generator: burns coal or carbon for OUTPUT_KW. Fuel is used only for what the grid actually draws
## (a generator on an idle grid keeps its fuel). Feed it by hand or by pipe.

const OUTPUT_KW := 30.0
## Energy per fuel item, kJ (= kW x s). Coal runs it 5 s at full load, carbon 10 s.
const FUEL_KJ := {"ore_coal": 150.0, "refined_carbon": 300.0}

var _buffer_kj := 0.0
var _light: MeshInstance3D
var _load := 0.0

func _ready() -> void:
	recipes = []
	inventory_slots = 4
	inventory_capacity = 200
	max_health = 300.0
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

func can_accept_input(item_id: String, amount: int) -> bool:
	return FUEL_KJ.has(item_id) and get_total_count() + amount <= inventory_capacity

func output_ids() -> Array:
	return []

## kW this generator can give right now.
func power_available() -> float:
	return OUTPUT_KW if _buffer_kj > 0.0 or _has_fuel() else 0.0

## The network took `kw` from this generator for `dt` seconds: burn fuel for it.
func power_drawn(kw: float, dt: float) -> void:
	_load = kw / OUTPUT_KW
	var need := kw * dt
	while need > 0.0:
		if _buffer_kj <= 0.0 and not _refuel():
			break
		var take := minf(_buffer_kj, need)
		_buffer_kj -= take
		need -= take
	_glow()

func _has_fuel() -> bool:
	for id: String in FUEL_KJ:
		if get_inventory_count(id) > 0:
			return true
	return false

func _refuel() -> bool:
	for id: String in FUEL_KJ:
		if get_inventory_count(id) > 0 and remove_item(id, 1):
			_buffer_kj += float(FUEL_KJ[id])
			return true
	return false

func idle_reason() -> String:
	return "" if power_available() > 0.0 else "No fuel"

func status_text() -> String:
	if power_available() <= 0.0:
		return "NO FUEL"
	return "RUNNING  ·  %d%% LOAD" % roundi(_load * 100.0)

func get_active_recipe_index() -> int:
	return 0 if _load > 0.0 else -1

func _glow() -> void:
	if _light != null:
		var m := _light.material_override as StandardMaterial3D
		m.emission_energy_multiplier = 0.2 + 2.0 * _load

func build_ui_extras(box: VBoxContainer, _refresh: Callable) -> void:
	box.add_child(UiKit.label("Burns coal (5 s) or carbon (10 s) at full load for %d kW." % int(OUTPUT_KW), "DimLabel"))
	PowerUi.grid_section(box, self)

func save_state() -> Dictionary:
	var d := super.save_state()
	d["buffer_kj"] = _buffer_kj
	return d

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	_buffer_kj = float(data.get("buffer_kj", 0.0))

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# skid base carries the firebox and the alternator on one frame so their shafts stay aligned
	Blockout.box(m, Vector3(1.9, 0.16, 1.2), Vector3(0, 0.08, 0), Blockout.DARK)
	# firebox: fuel burns in here; its door faces the input side
	Blockout.box(m, Vector3(0.9, 1.0, 1.0), Vector3(-0.45, 0.66, 0), Blockout.PAINT)
	_light = Blockout.cyl(m, 0.18, 0.04, Vector3(-0.92, 0.6, 0), Color(1.0, 0.45, 0.15), "x", "Fire", true)
	# exhaust stack from the firebox top: smoke has to go somewhere
	Blockout.cyl(m, 0.12, 1.2, Vector3(-0.6, 1.75, 0.25), Blockout.STEEL)
	# turbine/alternator housing bolted to the firebox: turns heat into power
	Blockout.cyl(m, 0.38, 0.8, Vector3(0.45, 0.55, 0), Blockout.STEEL, "x")
	Blockout.bolts(m, Vector3(0.05, 0.16, 0), 0.3)
	# terminal box where the pole's wire lands
	Blockout.box(m, Vector3(0.25, 0.3, 0.3), Vector3(0.8, 1.0, 0), Blockout.DARK)

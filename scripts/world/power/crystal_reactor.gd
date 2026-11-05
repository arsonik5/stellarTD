class_name CrystalReactor
extends Building
## Crystal reactor: burns crystal cells for OUTPUT_KW - ten burner generators' worth - and while it runs it is a
## big, steady radiation signature source (RadiationSignature sums group "signature_source"). The mid-game's
## central risk/reward choice (design C10).

const OUTPUT_KW := 300.0
const CELL_KJ := 36000.0        # one cell = 2 minutes at full load
const SIGNATURE_RUNNING := 12.0 # added to the signature while it has a charge in the core

var _buffer_kj := 0.0
var _load := 0.0
var _core: MeshInstance3D

func _ready() -> void:
	recipes = []
	inventory_slots = 4
	inventory_capacity = 40
	max_health = 900.0
	marker_height = 4.2
	add_to_group("signature_source")
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

func can_accept_input(item_id: String, amount: int) -> bool:
	return item_id == "crystal_cell" and get_total_count() + amount <= inventory_capacity

func output_ids() -> Array:
	return []

func power_available() -> float:
	return OUTPUT_KW if _buffer_kj > 0.0 or get_inventory_count("crystal_cell") > 0 else 0.0

func power_drawn(kw: float, dt: float) -> void:
	_load = kw / OUTPUT_KW
	var need := kw * dt
	while need > 0.0:
		if _buffer_kj <= 0.0:
			if not remove_item("crystal_cell", 1):
				break
			_buffer_kj += CELL_KJ
		var take := minf(_buffer_kj, need)
		_buffer_kj -= take
		need -= take
	if _core != null:
		(_core.material_override as StandardMaterial3D).emission_energy_multiplier = 0.3 + 3.0 * _load

## Signature this source adds right now (RadiationSignature reads it every tick).
func signature_contribution() -> float:
	return SIGNATURE_RUNNING if power_available() > 0.0 else 0.0

func idle_reason() -> String:
	return "" if power_available() > 0.0 else "No crystal cells"

func status_text() -> String:
	return "NO FUEL" if power_available() <= 0.0 else "CRITICAL  ·  %d%% LOAD  ·  SIGNATURE +%d" % [roundi(_load * 100.0), int(SIGNATURE_RUNNING)]

func get_active_recipe_index() -> int:
	return 0 if _load > 0.0 else -1

func build_ui_extras(box: VBoxContainer, _refresh: Callable) -> void:
	box.add_child(UiKit.label("One crystal cell runs it two minutes at full load. While loaded it can be seen from orbit.", "WarnLabel"))
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
	# containment plinth: thick concrete, takes the vessel's weight and shields the ground
	Blockout.box(m, Vector3(1.9, 0.4, 1.9), Vector3(0, 0.2, 0), Blockout.PAINT)
	# pressure vessel around the core
	Blockout.cyl(m, 0.7, 2.4, Vector3(0, 1.6, 0), Blockout.STEEL)
	# viewport ring onto the core: the crystal's glow (mint) shows how hard it is running
	_core = Blockout.cyl(m, 0.45, 0.5, Vector3(0, 1.6, 0.48), Blockout.GLASS, "z", "Core", true)
	# coolant loop: out of the vessel top, down to the heat exchanger and back
	Blockout.cyl(m, 0.08, 1.2, Vector3(0.75, 2.4, 0), Blockout.STEEL, "x")
	Blockout.box(m, Vector3(0.35, 1.6, 0.6), Vector3(0.75, 1.2, 0), Blockout.DARK)
	Blockout.bolts(m, Vector3(0, 0.4, 0), 0.65)

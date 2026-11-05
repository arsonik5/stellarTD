class_name BatteryBank
extends Building
## Battery bank: stores surplus grid power and gives it back during a deficit (night, fuel gap, peak load).

const CAPACITY_KJ := 3000.0
const RATE_KW := 40.0

var stored_kj := 0.0

func _ready() -> void:
	recipes = []
	inventory_slots = 0
	inventory_capacity = 0
	modifier_slots = 0
	max_health = 250.0
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

func can_accept_input(_id: String, _n: int) -> bool:
	return false

func battery_capacity() -> float:
	return CAPACITY_KJ

## Store up to `kj`, limited by rate and room. Returns kJ taken.
func charge(kj: float, dt: float) -> float:
	var take := minf(minf(kj, RATE_KW * dt), CAPACITY_KJ - stored_kj)
	stored_kj += maxf(take, 0.0)
	return maxf(take, 0.0)

## Give up to `kj`, limited by rate and charge. Returns kJ given.
func discharge(kj: float, dt: float) -> float:
	var give := minf(minf(kj, RATE_KW * dt), stored_kj)
	stored_kj -= maxf(give, 0.0)
	return maxf(give, 0.0)

func status_text() -> String:
	return "%d%%  ·  %d / %d kJ" % [roundi(stored_kj / CAPACITY_KJ * 100.0), roundi(stored_kj), roundi(CAPACITY_KJ)]

func get_process_progress() -> float:
	return stored_kj / CAPACITY_KJ

func build_ui_extras(box: VBoxContainer, _refresh: Callable) -> void:
	PowerUi.grid_section(box, self)

func save_state() -> Dictionary:
	var d := super.save_state()
	d["stored_kj"] = stored_kj
	return d

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	stored_kj = clampf(float(data.get("stored_kj", 0.0)), 0.0, CAPACITY_KJ)

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# rack frame on a base plate holds the cell modules
	Blockout.box(m, Vector3(1.4, 0.1, 1.0), Vector3(0, 0.05, 0), Blockout.DARK)
	for i in 3:
		# cell modules, bolted into the rack
		Blockout.box(m, Vector3(0.38, 1.1, 0.8), Vector3(-0.45 + i * 0.45, 0.65, 0), Blockout.PAINT)
	# bus bar across the module tops ties the cells together; the pole's wire lands on its end
	Blockout.box(m, Vector3(1.35, 0.06, 0.12), Vector3(0, 1.24, 0), Color(0.75, 0.5, 0.25))
	Blockout.cyl(m, 0.05, 0.08, Vector3(0.45, 1.28, 0.3), UiTokens.GOOD, "y", "Light", true)

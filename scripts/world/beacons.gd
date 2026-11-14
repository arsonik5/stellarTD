class_name Beacon
extends Building
## Beacons (design M7 / M30). One script, two roles set by `kind`:
##   "respawn"  - a respawn point (PlayerVitals uses the nearest one in group "respawn_point")
##   "waypoint" - a marker the HUD shows with its name and distance from anywhere on the body
## Both are small, cheap, and have a light so they read at night.

@export_enum("respawn", "waypoint") var kind := "waypoint"
var label := ""

func _ready() -> void:
	recipes = []
	inventory_slots = 0
	inventory_capacity = 0
	modifier_slots = 0
	max_health = 150.0
	marker_height = 2.6
	if kind == "respawn":
		add_to_group("respawn_point")
	else:
		add_to_group("waypoint")
	if label == "":
		label = "Respawn" if kind == "respawn" else "Waypoint %d" % (get_tree().get_nodes_in_group("waypoint").size())
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

func can_accept_input(_id: String, _n: int) -> bool:
	return false

func status_text() -> String:
	return label.to_upper()

func build_ui_extras(box: VBoxContainer, refresh: Callable) -> void:
	if kind == "respawn":
		box.add_child(UiKit.label("If your suit fails, you come back at the nearest respawn beacon.", "DimLabel"))
		return
	box.add_child(UiKit.label("Shown on your HUD with its distance, anywhere on this world.", "DimLabel"))
	var row := UiKit.hbox(6)
	box.add_child(row)
	var edit := LineEdit.new()
	edit.text = label
	edit.custom_minimum_size.x = 220
	edit.text_submitted.connect(func(t: String) -> void:
		label = t.strip_edges() if t.strip_edges() != "" else label
		refresh.call())
	row.add_child(edit)

func save_state() -> Dictionary:
	var d := super.save_state()
	d["beacon_label"] = label
	return d

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	label = String(data.get("beacon_label", label))

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# tripod feet hold the mast upright on uneven ground
	for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		Blockout.box(m, Vector3(0.08, 0.9, 0.08), Vector3(cos(a) * 0.3, 0.4, sin(a) * 0.3), Blockout.STEEL).rotation = Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35)
	Blockout.cyl(m, 0.05, 2.0, Vector3(0, 1.3, 0), Blockout.STEEL)
	var col := UiTokens.GOOD if kind == "respawn" else UiTokens.ACCENT
	Blockout.cyl(m, 0.12, 0.25, Vector3(0, 2.35, 0), col, "y", "Light", true)

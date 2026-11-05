class_name PowerPole
extends Building
## Power pole: links to poles within PowerNetwork.LINK_RANGE and plugs in buildings within POLE_REACH.
## Holds nothing; its panel shows the grid it belongs to.

func _ready() -> void:
	recipes = []
	inventory_slots = 0
	inventory_capacity = 0
	modifier_slots = 0
	max_health = 120.0
	marker_height = 3.2
	add_to_group("power_pole")
	if get_node_or_null("Model") == null:
		_build_blockout()
	super._ready()

func can_accept_input(_id: String, _n: int) -> bool:
	return false

func status_text() -> String:
	var g := PowerNetwork.grid_for(self)
	if g.is_empty():
		return "NOT LINKED"
	return "GRID  ·  %d kW / %d kW  ·  %d%%" % [roundi(g.demand), roundi(g.supply), roundi(g.satisfaction * 100.0)]

func build_ui_extras(box: VBoxContainer, _refresh: Callable) -> void:
	PowerUi.grid_section(box, self)

func _build_blockout() -> void:
	var m := Blockout.root(self)
	# foot plate bolted to the ground, the post stands on it
	Blockout.box(m, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.04, 0), Blockout.DARK)
	Blockout.bolts(m, Vector3(0, 0.08, 0), 0.18)
	# post: carries the cross-arm high enough to clear people and vehicles
	Blockout.box(m, Vector3(0.14, 2.9, 0.14), Vector3(0, 1.5, 0), Blockout.STEEL)
	# cross-arm with two insulators: the wires clamp to these
	Blockout.box(m, Vector3(0.9, 0.08, 0.1), Vector3(0, 2.85, 0), Blockout.STEEL)
	for x in [-0.38, 0.38]:
		Blockout.cyl(m, 0.05, 0.14, Vector3(x, 2.96, 0), Color(0.5, 0.75, 0.9))

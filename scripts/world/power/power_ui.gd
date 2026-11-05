class_name PowerUi
extends RefCounted
## Shared machine-panel section: the grid a building is on, and its own draw or output.

static func grid_section(box: VBoxContainer, b: Building) -> void:
	box.add_child(UiKit.section("Power"))
	var g := PowerNetwork.grid_for(b)
	if g.is_empty():
		var msg := "Not connected - place a power pole within %d m." % int(PowerNetwork.POLE_REACH)
		if b.needs_power:
			msg += " This machine cannot run without power."
		elif b.power_draw > 0.0:
			msg += " Runs at base speed; power doubles it."
		box.add_child(UiKit.label(msg, "WarnLabel" if b.needs_power else "DimLabel"))
		return
	var sat := float(g.satisfaction)
	box.add_child(UiKit.label("Grid: %d kW used of %d kW  ·  %d%% satisfied  ·  %d poles" % [roundi(g.demand), roundi(g.supply),
		roundi(sat * 100.0), g.poles.size()], "AccentLabel" if sat >= 0.999 else "WarnLabel"))
	if float(g.capacity) > 0.0:
		box.add_child(UiKit.label("Batteries: %d / %d kJ" % [roundi(g.stored), roundi(g.capacity)], "DimLabel"))
	if b.power_draw > 0.0:
		box.add_child(UiKit.label("This machine draws %d kW while working  ·  speed x%.1f" % [roundi(b.power_draw), b.work_speed], "DimLabel"))

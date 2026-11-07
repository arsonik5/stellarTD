extends Node
## Dev test for the console commands (no UI): godot --headless --path . res://scenes/dev/console_test.tscn
func _ready() -> void:
	await get_tree().process_frame
	var fails := 0
	DevConsole.run("give iron 50")
	fails += _check("give alias iron -> ore_a x50", Inventory.get_count("ore_a") == 50)
	DevConsole.run("/give stone 7")
	fails += _check("slash prefix + stone", Inventory.get_count("stone") == 7)
	DevConsole.run("give nope 5")
	fails += _check("unknown item changes nothing", Inventory.get_count("nope") == 0)
	DevConsole.run("give ore_a abc")
	fails += _check("bad amount changes nothing", Inventory.get_count("ore_a") == 50)
	DevConsole.run("clear iron")
	fails += _check("clear iron", Inventory.get_count("ore_a") == 0 and Inventory.get_count("stone") == 7)
	DevConsole.run("clear")
	fails += _check("clear all", Inventory.get_count("stone") == 0)
	DevConsole.run("spawn stone 3")
	fails += _check("spawn = give", Inventory.get_count("stone") == 3)
	DevConsole.run("ores 5")
	fails += _check("ores gives every ore", Inventory.get_count("ore_a") == 5 and Inventory.get_count("ore_crystal") == 5)
	DevConsole._field.text = ""
	fails += _check("empty input suggests every command", DevConsole._build_suggestions().size() == DevConsole.COMMANDS.size())
	DevConsole._field.text = "give "
	fails += _check("'give ' suggests items", DevConsole._build_suggestions().size() > 10)
	DevConsole._field.text = "gi"
	fails += _check("'gi' narrows to give", DevConsole._build_suggestions().size() == 1)
	DevConsole.run("items copper")
	DevConsole.run("help")
	DevConsole.run("bogus")
	print("CONSOLETEST %s" % ("FAIL %d" % fails if fails > 0 else "PASS"))
	get_tree().quit()
func _check(label: String, ok: bool) -> int:
	print(("PASS " if ok else "FAIL ") + label)
	return 0 if ok else 1

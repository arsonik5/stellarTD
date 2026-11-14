extends Node3D
## Dev test for the tool rule (docs/game/tools.md): LMB uses the LEFT-hand tool, RMB the RIGHT-hand tool.
##   godot --headless --path . res://scenes/dev/tool_flow_test.tscn
const PLAYER := preload("res://scenes/player.tscn")
const BUILD_UI := preload("res://scenes/build_ui.tscn")
var player: Node
var fails := 0
const L := MOUSE_BUTTON_LEFT
const R := MOUSE_BUTTON_RIGHT

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	cs.shape = shape
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	add_child(BUILD_UI.instantiate())
	player = PLAYER.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.05, 0)
	player.set("_spawn_resolved", true)
	await get_tree().create_timer(0.6).timeout
	_run()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_after_frame()
	print("TOOLFLOW %s" % ("FAIL %d" % fails if fails > 0 else "PASS"))
	get_tree().quit()

func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1

func _hand(side: String, id: String) -> void:
	Inventory.set_slot({"kind": "hand", "side": side}, id, 1 if id != "" else 0)

func _run() -> void:
	# start state: mining left, building right, scanner in the grid
	_check(Inventory.hand_holding("mining_tool") == "left" and Inventory.hand_holding("building_tool") == "right", "start: mining left, building right")
	player.call("_on_hand_button", L, true)
	_check(player.get("_dig_held") == true and player.get("_dig_button") == L, "LMB with mining in the left hand starts the drill")
	player.call("_on_hand_button", L, false)
	_check(player.get("_dig_held") == false, "releasing LMB stops the drill")
	player.call("_on_hand_button", R, true)
	_check(player.get("_build_mode") == true, "RMB with the building tool in the right hand opens build mode")
	player.call("_exit_build_mode")
	# scanner into the right hand (where the building tool was): mining on the left must still work
	_hand("right", "scanner_tool")
	player.call("_on_hand_button", R, true)
	_check(float(player.get("_scan_anim_left")) > 0.0 and player.get("_build_mode") == false, "RMB with the scanner in the right hand scans (and does not open build mode)")
	player.call("_on_hand_button", L, true)
	_check(player.get("_dig_held") == true, "LMB still drills with the scanner in the other hand")
	player.call("_on_hand_button", L, false)
	# empty left hand: LMB does nothing
	_hand("left", "")
	player.call("_on_hand_button", L, true)
	_check(player.get("_dig_held") == false, "LMB with an empty left hand does nothing")
	# drill in the right hand: RMB drills, and taking it away mid-hold stops it
	_hand("right", "mining_tool")
	player.call("_on_hand_button", R, true)
	_check(player.get("_dig_held") == true and player.get("_dig_button") == R, "RMB drills when the mining tool is in the right hand")
	_hand("right", "")

func _after_frame() -> void:
	_check(player.get("_dig_held") == false, "taking the drill out of the hand stops it (no stuck drill)")

extends Node

## Dev test: rebuilt card lists must not stack cards on top of each other (build menu tab switches).
## Opens the real build menu, switches tabs with different gaps between switches, then checks every card has its
## own slot. Screenshot: art_src/ingame/ui_stack.png.   godot --path . res://scenes/dev/ui_stack_test.tscn
var _fails := 0

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check_grid(grid: GridContainer, what: String) -> void:
	var rects: Array[Rect2] = []
	for c in grid.get_children():
		if c is Control and not c.is_queued_for_deletion():
			rects.append(Rect2((c as Control).position, (c as Control).size))
	var bad := 0
	for a in rects.size():
		for b in range(a + 1, rects.size()):
			if rects[a].grow(-2.0).intersects(rects[b].grow(-2.0)):
				bad += 1
	var ok := bad == 0 and rects.size() > 0
	print("UISTACK %s %s (%d cards, %d overlaps)" % ["PASS" if ok else "FAIL", what, rects.size(), bad])
	if not ok:
		_fails += 1

func _ready() -> void:
	var ui: CanvasLayer = load("res://scenes/build_ui.tscn").instantiate()
	add_child(ui)
	await _frames(3)
	# the game's path: build tool out (show_ui), menu opens; pick Oxygen Post, menu closes; open again (C)
	ui.show_ui()
	ui.set_menu_open(true)
	await _frames(2)
	var grid: GridContainer = ui._grid
	ui._selected_index = ui.BUILDABLE_RECIPES.size() - 1          # Oxygen Post -> reopens on Production
	for gap in [0, 1, 3, 20]:
		ui.set_menu_open(false)
		await _frames(gap)
		ui.set_menu_open(true)
		await get_tree().create_timer(1.0).timeout
		_check_grid(grid, "reopen on production, %d frames closed" % gap)
	# cards rebuilt while the menu can't lay them out yet (hidden), shown a few frames later
	for gap in [1, 3, 10]:
		(ui._frame.root as Control).visible = false
		ui._show_tab("structure")
		ui._show_tab("production")
		await _frames(gap)
		(ui._frame.root as Control).visible = true
		await get_tree().create_timer(1.2).timeout
		_check_grid(grid, "rebuilt while hidden, shown %d frames later" % gap)
	# input can arrive inside a physics step (the C key, a tab click): open the menu from there
	for i in 3:
		ui.set_menu_open(false)
		await get_tree().physics_frame
		ui.set_menu_open(true)
		await get_tree().create_timer(1.0).timeout
		_check_grid(grid, "reopen from inside a physics step #%d" % i)
		await get_tree().physics_frame
		ui._show_tab("structure")
		await get_tree().physics_frame
		ui._show_tab("production")
		await get_tree().create_timer(1.0).timeout
		_check_grid(grid, "tab switch from inside a physics step #%d" % i)
	for gap in [0, 1, 20]:
		ui.hide_ui()
		await _frames(gap)
		ui.show_ui()
		ui.set_menu_open(true)
		await get_tree().create_timer(1.0).timeout
		_check_grid(grid, "build tool put away and out again, %d frames" % gap)
	# gaps between tab switches: same frame, one frame, a few frames, mid-animation
	for gap in [0, 1, 2, 5, 12]:
		for t in ["structure", "production", "defense", "production"]:
			ui._show_tab(t)
			await _frames(gap)
		await get_tree().create_timer(1.0).timeout
		_check_grid(grid, "production after switches %d frames apart" % gap)
	# a building already in the inventory (crafted, or given by a command) places without materials
	var crafter: Recipe = ui.BUILDABLE_RECIPES.filter(func(r: Recipe) -> bool: return r.output_id == "basic_crafter")[0]
	var mats_before := {}
	for id in crafter.input_ids:
		mats_before[id] = Inventory.get_count(id)
	Inventory.add("basic_crafter", 1)
	await _frames(2)
	var card: Button = ui._cards[ui.BUILDABLE_RECIPES.find(crafter)]
	var cost_text: String = (card.find_child("Cost", true, false) as Label).text
	var ok_pay: bool = ui.can_pay(crafter) and ui.pay(crafter)
	var mats_same := true
	for id in crafter.input_ids:
		mats_same = mats_same and Inventory.get_count(id) == mats_before[id]
	var ok := ok_pay and Inventory.get_count("basic_crafter") == 0 and mats_same and cost_text == "1 in inventory"
	print("UISTACK %s carried Crafter places free (card '%s', pay %s, left %d, materials untouched %s)" % ["PASS" if ok else "FAIL", cost_text, ok_pay, Inventory.get_count("basic_crafter"), mats_same])
	if not ok:
		_fails += 1
	var no_more: bool = not ui.can_pay(crafter) or crafter.input_ids.all(func(id: String) -> bool: return Inventory.get_count(id) >= crafter.get_amount(id) if crafter.has_method("get_amount") else true)
	print("UISTACK %s with none carried it needs materials again" % ("PASS" if no_more else "FAIL"))
	if not no_more:
		_fails += 1
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://art_src/ingame/ui_stack.png"))
	print("UISTACK_DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

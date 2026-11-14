extends Node
## Feature tour + layout check: boots the REAL game from a throwaway save, builds a small G2-G5 base around the
## player, photographs every new building from its own framed camera, a raid up close, and EVERY screen - and
## checks each screen's layout: any visible control whose rectangle leaves the viewport is a FAIL (content inside
## scroll containers is allowed to scroll). Run at both supported sizes:
##   godot --path . res://scenes/dev/feature_tour.tscn -- tag=g4                     (1152 x 648)
##   godot --resolution 1920x1080 --path . res://scenes/dev/feature_tour.tscn -- tag=g4hd
## Shots: art_src/ingame/ux/<tag>_<nn>_<name>.png. Prints PASS/FAIL and "FEATURETOUR DONE fails=N".
const OUT := "res://art_src/ingame/ux"
const SLOT_NAME := "Feature Tour (dev)"
var tag := "g4"
var _slot := ""
var _n := 0
var _fails := 0
var player: Node3D
var up := Vector3.UP

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = a.substr(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_n += 1
	var path := "%s/%s_%02d_%s.png" % [OUT, tag, _n, shot_name]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", path)

## Every visible control inside `root` must lie inside the viewport (content of ScrollContainers excepted).
func _layout_ok(root: Node, screen_name: String) -> void:
	var vp := get_viewport().get_visible_rect().size
	var bad: Array[String] = []
	_walk_layout(root, vp, bad)
	_check(bad.is_empty(), "%s fits %dx%d%s" % [screen_name, int(vp.x), int(vp.y), ("" if bad.is_empty() else ": " + ", ".join(bad.slice(0, 4)))])

func _walk_layout(n: Node, vp: Vector2, bad: Array[String]) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0 and (r.position.x < -2.0 or r.position.y < -2.0 or r.end.x > vp.x + 2.0 or r.end.y > vp.y + 2.0):
			bad.append("%s %s" % [c.name, str(r)])
			return
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_walk_layout(ch, vp, bad)

func _cam_at(from: Vector3, look: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 60.0
	get_tree().current_scene.add_child(cam)
	cam.global_position = from
	cam.look_at(look, PlanetPhysics.get_up(look))
	cam.make_current()
	return cam

## A camera 7 m out from `b` toward the player and 4 m up, looking at its middle.
func _frame(b: Node3D, shot_name: String, dist := 7.0, height := 4.0) -> void:
	var u := PlanetPhysics.get_up(b.global_position)
	var away := player.global_position - b.global_position
	away -= u * away.dot(u)
	if away.length() < 0.1:
		away = u.cross(Vector3.RIGHT)
	var cam := _cam_at(b.global_position + away.normalized() * dist + u * height, b.global_position + u * 1.2)
	await _wait(0.4)
	await _shot(shot_name)
	cam.queue_free()

func _run() -> void:
	await get_tree().process_frame
	for s: Dictionary in SaveManager.list_slots():
		if s.name == SLOT_NAME:
			SaveManager.delete_slot(s.id)
	_slot = SaveManager.create_slot(SLOT_NAME)
	SaveManager.begin_session(_slot, SaveManager.read_state(_slot))
	get_tree().change_scene_to_file("res://scenes/world.tscn")
	await _wait(0.5)
	for i in 1500:
		await _wait(0.2)
		player = get_tree().get_first_node_in_group("player")
		if player != null and player.is_spawn_resolved():
			break
	if player == null:
		print("TOUR FAIL no spawn")
		return _finish()
	await _wait(1.5)
	_check(RadiationSignature.tier() == RadiationSignature.Tier.NONE, "a new game starts QUIET (signature %.1f)" % RadiationSignature.signature())
	up = PlanetPhysics.get_up(player.global_position)
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := fwd.cross(up).normalized()
	# a ring of buildings around the player (a cliff on one side cannot hide all of them), dropped on the ground
	var layout := ["deposit_drill", "crusher", "power_pole", "burner_generator", "uplink", "crystal_reactor",
		"turret_gun", "solar_panel", "drone_port", "containment_field", "waypoint_beacon"]
	var built := {}
	for i in layout.size():
		var id: String = layout[i]
		var item: Item = Inventory.get_item_def(id)
		var b: Node3D = item.building_scene.instantiate()
		get_tree().current_scene.add_child(b)
		var ang := float(i) / float(layout.size()) * TAU
		var p: Vector3 = player.global_position + (fwd * cos(ang) + right * sin(ang)) * (12.0 if id != "power_pole" else 6.0)
		var q := PhysicsRayQueryParameters3D.create(p + up * 40.0, p - up * 40.0)
		q.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		b.global_transform = Transform3D(Basis.looking_at(-right, up), hit.position if not hit.is_empty() else p)
		SaveManager.mark_placed(b, id)
		built[id] = b
	(built.burner_generator as Building).add_input("ore_coal", 20)
	(built.crystal_reactor as Building).add_input("crystal_cell", 2)
	(built.turret_gun as Building).add_input("iron_piercing_ammo", 50)
	# bore the drill's SECOND shaft (beside the rig, so the pit is visible), with stone kept
	var drill := built.deposit_drill as DepositDrill
	drill.shaft = 1
	drill.keep_stone = true
	for i in 160:
		drill.bite_once()
		if i % 20 == 0:
			await get_tree().process_frame
	await _wait(2.0)        # remesh
	var aerial := _cam_at(player.global_position + up * 30.0 - fwd * 22.0, player.global_position)
	await _wait(1.0)
	await _shot("base_aerial")
	aerial.queue_free()
	await _frame(drill, "drill_shaft", 6.0, 6.5)
	for id in ["crusher", "uplink", "crystal_reactor", "turret_gun", "burner_generator", "solar_panel", "drone_port", "containment_field"]:
		await _frame(built[id], id, 7.0 if id != "uplink" else 10.0, 4.0 if id != "uplink" else 5.0)
	# raid up close: a gunship and a dropship 30 m out, a camera behind the base looking at them
	var td: ThreatDirector = get_tree().get_first_node_in_group("threat_director")
	td.enabled = false
	var wave: Array = td.launch_wave({"gunship": 1, "dropship": 1}, fwd)
	for e in wave:
		(e as Node3D).global_position = player.global_position + fwd * 30.0 + up * 14.0 + right * (6.0 if e is Gunship else -8.0)
		(e as RigidBody3D).freeze = true
	var rc := _cam_at(player.global_position - fwd * 4.0 + up * 6.0, player.global_position + fwd * 30.0 + up * 12.0)
	await _wait(0.4)
	await _shot("raiders")
	rc.queue_free()
	for e in wave:
		e.queue_free()
	# --- screens: each one photographed and layout-checked ---
	var hud := get_tree().get_first_node_in_group("compact_hud")
	GameEvents.wave_warning.emit(player.global_position + right * 600.0, 38.0, {"gunship": 2, "dropship": 1})
	await _wait(0.5)
	_layout_ok(hud, "HUD")
	await _shot("hud")
	player.call("_toggle_inventory")
	await _wait(0.4)
	_layout_ok(get_tree().get_first_node_in_group("inventory_ui"), "inventory")
	await _shot("inventory")
	player.call("_toggle_inventory")
	await _wait(0.3)
	player.call("_toggle_build_mode")
	await _wait(0.3)
	var bui := get_tree().get_first_node_in_group("build_ui")
	for t in ["production", "power"]:
		bui.call("_show_tab", t)
		await _wait(0.3)
		_layout_ok(bui, "build menu " + t)
		await _shot("build_" + t)
	player.call("_toggle_build_mode")
	var mui := get_tree().get_first_node_in_group("building_ui")
	for id in ["deposit_drill", "uplink", "drone_port", "burner_generator"]:
		mui.show_for(built[id])
		await _wait(0.4)
		_layout_ok(mui, "machine panel " + id)
		await _shot("panel_" + id)
		mui.close()
	var j := get_tree().get_first_node_in_group("journal_ui")
	j.open()
	for page in ["Tutorial", "Directives", "Research", "Supply", "Stats"]:
		j.show_page(page)
		await _wait(0.3)
		_layout_ok(j, "journal " + page)
		await _shot("journal_" + page.to_lower())
	j.close()
	var pm := get_tree().get_first_node_in_group("pause_menu")
	if pm != null:
		player.call("_toggle_pause_menu")
		await _wait(0.4)
		_layout_ok(pm, "pause menu")
		await _shot("pause")
		if pm.has_method("tour_pages"):
			for page: String in pm.tour_pages():
				pm.call("show_page", page)
				await _wait(0.3)
				_layout_ok(pm, "pause " + page)
				await _shot("pause_" + page)
	_finish()

func _finish() -> void:
	SaveManager.end_session()
	if _slot != "":
		SaveManager.delete_slot(_slot)
	print("FEATURETOUR DONE fails=%d shots=%d" % [_fails, _n])
	get_tree().quit(_fails)

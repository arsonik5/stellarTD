extends Node

## Dev test for the rocket pod and the weapon control system, on the real planet:
## hangs a ship (core + rocket pod under it) 60 m up, nose 20 degrees down, frozen in place. Checks:
##   1. one rocket lands near the CCIP prediction (unguided spread allowed)
##   2. a 16-round salvo fires 16 and stops; ripple keeps going while held
##   3. ammo is saved and restored (save_extra / load_extra)
## Screenshots: art_src/ingame/rocket_<n>.png.   godot --path . res://scenes/dev/rocket_test.tscn
const OUT := "res://art_src/ingame"
var _fails := 0

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/rocket_%s.png" % [OUT, name]
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", path)

func _check(ok: bool, what: String) -> void:
	print("ROCKET %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _ready() -> void:
	var player: Node3D = null
	for i in 900:
		await _wait(0.2)
		player = get_tree().get_first_node_in_group("player")
		if player != null and player.is_spawn_resolved():
			break
	await _wait(3.0)
	# daylight: park the star 35 degrees up behind the line of fire (as terrain_look.gd does)
	var star := get_tree().current_scene.find_child("Star", true, false) as Node3D
	var planet := get_tree().get_first_node_in_group("planet") as Node3D
	if star != null and planet != null:
		var u := PlanetPhysics.get_up(player.global_position)
		var e := u.cross(Vector3.UP).normalized() if absf(u.dot(Vector3.UP)) < 0.9 else u.cross(Vector3.RIGHT).normalized()
		var sun := (u * sin(deg_to_rad(35.0)) + e * cos(deg_to_rad(35.0))).normalized()
		star.global_position = player.global_position + sun * star.global_position.distance_to(planet.global_position)
	await _wait(1.0)
	var cam: Camera3D = get_viewport().get_camera_3d()
	var up := PlanetPhysics.get_up(player.global_position)
	var fwd := -cam.global_transform.basis.z
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var pos := player.global_position + up * 60.0
	var ship := Ship.new()
	ship.is_player_ship = true
	get_tree().current_scene.add_child(ship)
	var aim := fwd.rotated(fwd.cross(up).normalized(), deg_to_rad(-20.0))
	ship.global_transform = Transform3D(Basis.looking_at(aim, up), pos)
	ship.freeze = true
	var core: ShipBlock = preload("res://scenes/ship_core.tscn").instantiate()
	ship.add_child(core)
	var a0 := Ship.anchor_for_center(Vector3.ZERO, core.ship_size())
	core.position = Ship.block_center(a0, core.ship_size())
	ship.add_block(a0, core)
	var pod: ShipRocketPod = preload("res://scenes/part_rocket_pod.tscn").instantiate()
	ship.add_child(pod)
	var a1 := Vector3i(-1, a0.y - 2, -3)
	pod.position = Ship.block_center(a1, pod.ship_size())
	ship.add_block(a1, pod)
	var wc := ShipWeaponControl.of(ship)
	wc.refresh()
	_check(wc.secondary_groups().size() == 1 and wc.ammo_of(wc.selected_group()) == Vector2i(160, 160), "pod registered, 160 rockets")

	# a camera beside and behind the ship, looking along the line of fire
	var side := aim.cross(up).normalized()
	var c2 := Camera3D.new()
	add_child(c2)
	c2.global_position = pos + side * 9.0 + up * 3.0 - aim * 10.0
	c2.look_at(pos + aim * 40.0, up)
	c2.far = 20000.0
	c2.make_current()
	var hud := get_tree().get_first_node_in_group("compact_hud")
	if hud != null:
		hud.set_piloted_ship(ship)
	await _wait(1.0)

	# 1. single rocket vs CCIP
	wc._update_ccip()
	var pred: Dictionary = wc.ccip.duplicate()
	_check(pred.get("hit", false), "CCIP finds the ground (%.0f m, %.1f s)" % [pos.distance_to(pred.get("position", pos)), pred.get("time", 0.0)])
	wc.salvo_index["ROCKETS"] = 0                     # salvo 1
	Rocket.last_impact = Vector3.INF
	wc.set_secondary(true)
	await _wait(0.25)
	await _shot("launch")
	wc.set_secondary(false)
	for i in 100:
		await _wait(0.1)
		if Rocket.last_impact != Vector3.INF:
			break
	var miss := Rocket.last_impact.distance_to(pred.get("position", Vector3.ZERO))
	var rng := pos.distance_to(pred.get("position", pos))
	_check(Rocket.last_impact != Vector3.INF and miss < maxf(4.0, rng * 0.02), "rocket lands %.1f m from the CCIP point at %.0f m" % [miss, rng])
	await _shot("impact")
	_check(pod.ammo == 159, "one round used (ammo %d)" % pod.ammo)

	# 2. salvo of 16
	wc.salvo_index["ROCKETS"] = 4                     # SALVOS[4] = 16
	wc.set_secondary(true)
	await _wait(0.5)
	await _shot("salvo")
	await _wait(1.5)
	wc.set_secondary(false)
	_check(pod.ammo == 159 - 16, "salvo 16 fired exactly 16 (ammo %d)" % pod.ammo)
	# ripple while held
	wc.salvo_index["ROCKETS"] = 5
	wc.set_secondary(true)
	await _wait(0.7)
	wc.set_secondary(false)
	var after := pod.ammo
	await _wait(0.5)
	_check(after < 143 and pod.ammo == after, "ripple fires while held and stops on release (ammo %d)" % pod.ammo)
	await _wait(4.0)
	await _shot("craters")

	# player input path: the pilot controller turns a real LMB press into a salvo (no guns fitted -> LMB = selected)
	var ctl := PlayerShipController.new()
	ctl.ship = ship
	ship.add_child(ctl)
	wc.salvo_index["ROCKETS"] = 2                     # salvo 4
	var before := pod.ammo
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.6)
	var up_ev := ev.duplicate()
	up_ev.pressed = false
	Input.parse_input_event(up_ev)
	await _wait(0.3)
	_check(before - pod.ammo == 4, "LMB through the pilot controller fires a salvo of 4 (%d)" % (before - pod.ammo))
	var hk := InputEventKey.new()
	hk.keycode = KEY_H
	hk.physical_keycode = KEY_H
	hk.pressed = true
	Input.parse_input_event(hk)
	await _wait(0.1)
	_check(wc.salvo_label(wc.selected_group()) == "SALVO 8", "H steps the salvo (%s)" % wc.salvo_label(wc.selected_group()))
	ctl.queue_free()

	# 3. save / load
	var state := ship.save_state()
	var ship2 := Ship.new()
	get_tree().current_scene.add_child(ship2)
	ship2.load_state(state)
	ship2.freeze = true
	var pods := ship2.find_children("*", "", true, false).filter(func(n): return n is ShipRocketPod)
	_check(pods.size() == 1 and pods[0].ammo == pod.ammo, "ammo saved and loaded (%d)" % (pods[0].ammo if pods.size() == 1 else -1))
	print("ROCKET_DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

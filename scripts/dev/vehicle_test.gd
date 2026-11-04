extends Node3D
## Dev test for modular vehicles: builds a buggy out of parts on the 0.5 m grid (vehicle core, open driver seat,
## engine, four 1 m wheels, beams, plus one classic 2 m hull block on top to prove big and small blocks mix), drops
## it on the ground, lets the springs settle, then drives forward, turns left and stops - all through the same
## desired_linear_thrust the player's controller sets. Prints what happened and saves art_src/ingame/vehicle_*.png.
## godot --path . res://scenes/dev/vehicle_test.tscn   (add --write-movie art_src/ingame/vehicle.avi to record)

const OUT := "res://art_src/ingame"
var ship: Ship
var lander: Ship
var _t := 0.0
var _cam: Camera3D
var _start := Vector3.ZERO
var _shots := {}

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200), Basis(), Color(0.14, 0.12, 0.1))
	_box(Vector3(0, -0.1, -14), Vector3(8, 0.5, 1.5), Basis(Vector3.RIGHT, 0.3), Color(0.3, 0.25, 0.2))   # a bump
	for i in 12:                                                                                      # markers
		_box(Vector3(-6, 0.2, -i * 4.0), Vector3(0.2, 0.4, 0.2), Basis(), Color(0.6, 0.55, 0.2))
	ship = Ship.new()
	ship.is_player_ship = true
	ship.fallback_gravity = Vector3(0, -9.8, 0)
	add_child(ship)
	ship.global_position = Vector3(0, 1.6, 0)
	var parts := [
		["vehicle_core", Vector3i(-1, -1, -1), 0.0],
		["driver_seat", Vector3i(-1, -1, -3), 0.0],
		["engine", Vector3i(-1, -1, 1), 0.0],
		["beam_4", Vector3i(-2, -1, -3), 0.0], ["beam_4", Vector3i(1, -1, -3), 0.0],
		["beam_2", Vector3i(-2, -1, 1), 0.0], ["beam_2", Vector3i(1, -1, 1), 0.0],
		["wheel_small", Vector3i(2, -2, -3), 0.0], ["wheel_small", Vector3i(-4, -2, -3), PI],
		["wheel_small", Vector3i(2, -2, 1), 0.0], ["wheel_small", Vector3i(-4, -2, 1), PI],
		["ship_hull", Vector3i(-2, 1, 0), 0.0],
	]
	for p in parts:
		var item: Item = Inventory.get_item_def(p[0])
		var block: ShipBlock = item.block_scene.instantiate()
		block.basis = Basis(Vector3.UP, p[2])
		var ok := ship.try_add_block(p[1], block)
		print("ADD %-12s at %s -> %s" % [p[0], p[1], ok])
		if not ok:
			block.queue_free()
	print("SHIP mass %.0f kg, wheels %d, drive %.0f N, state %s" % [ship.mass, ship._wheels.size(), ship._drive_force, ship.ship_state])
	# second build: a lander on four landing-gear legs, an RCS block and an oxygen tank, 12 m to the right
	lander = Ship.new()
	lander.is_player_ship = true
	lander.fallback_gravity = Vector3(0, -9.8, 0)
	add_child(lander)
	lander.global_position = Vector3(12, 2.6, 0)
	for p in [["ship_core", Vector3i(-2, -2, -2)], ["landing_gear", Vector3i(-2, -4, -2)], ["landing_gear", Vector3i(0, -4, -2)],
			["landing_gear", Vector3i(-2, -4, 0)], ["landing_gear", Vector3i(0, -4, 0)], ["rcs", Vector3i(0, 2, 0)],
			["o2_tank", Vector3i(-2, 2, -2)]]:
		var b: ShipBlock = (Inventory.get_item_def(p[0]) as Item).block_scene.instantiate()
		print("LANDER ADD %-12s -> %s" % [p[0], lander.try_add_block(p[1], b)])
	print("LANDER O2 took %.1f s, left %.1f s" % [lander.take_oxygen(10.0), lander.oxygen_left()])
	_cam = Camera3D.new()
	_cam.fov = 60
	add_child(_cam)
	_cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

func _box(pos: Vector3, size: Vector3, b: Basis, col: Color) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	mi.material_override = m
	body.add_child(mi)
	add_child(body)
	body.transform = Transform3D(b, pos)

func _wheel_report() -> String:
	var s := ""
	for w in ship._wheels:
		s += "%s drop %.3f  " % ["on" if w.contact else "air", w._drop]
	return s

func _physics_process(delta: float) -> void:
	_t += delta
	var thrust := Vector3.ZERO
	if _t > 2.0 and _t < 6.0:
		thrust.z = -1.0                    # W: drive forward
	elif _t >= 6.0 and _t < 8.5:
		thrust = Vector3(-1.0, 0, -1.0).normalized()   # W + A: turn left
	ship.desired_linear_thrust = thrust
	if is_equal_approx(snappedf(_t, 0.5), _t) or absf(_t - snappedf(_t, 0.5)) < delta * 0.5:
		var yaw := rad_to_deg(ship.global_transform.basis.get_euler().y)
		print("T %.1f pos %s speed %.2f yaw %.0f | %s" % [_t, ship.global_position.snapped(Vector3.ONE * 0.01),
			ship.linear_velocity.length(), yaw, _wheel_report()])
	if _t > 1.9 and _start == Vector3.ZERO:
		_start = ship.global_position
	# chase camera
	var back := ship.global_transform.basis.z
	var target := ship.global_position + back * 7.0 + Vector3.UP * 3.5 + ship.global_transform.basis.x * 3.0
	_cam.global_position = _cam.global_position.lerp(target, 0.1) if _t > 0.1 else target
	_cam.look_at(ship.global_position + Vector3.UP * 0.3)
	for k in [1.8, 4.5, 7.5]:
		if _t >= k and not _shots.has(k):
			_shots[k] = true
			_shot("vehicle_%d" % int(k * 10))
	if absf(_t - 2.5) < delta * 0.5 or absf(_t - 6.0) < delta * 0.5:
		var gears := ""
		for w in lander._wheels:
			gears += "%s %.3f  " % ["on" if w.contact else "air", w._drop]
		print("LANDER t %.1f height %.2f | %s" % [_t, lander.global_position.y, gears])
	if absf(_t - 3.0) < delta * 0.5:
		lander.toggle_landing_gear()
		print("LANDER gear up")
	if _t > 10.0:
		print("RESULT moved %.1f m, final speed %.2f, yaw %.0f deg" % [_start.distance_to(ship.global_position),
			ship.linear_velocity.length(), rad_to_deg(ship.global_transform.basis.get_euler().y)])
		print("VEHICLETEST DONE")
		get_tree().quit()

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, n]))
	print("SAVED ", n)

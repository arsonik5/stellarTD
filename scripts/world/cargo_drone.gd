class_name CargoDrone
extends RigidBody3D
## The Drone Port's hauler: a small rigid body flown by a PD controller (same flight model as the raiders,
## EnemyFlyer), under radial gravity. State machine: HOME -> to SOURCE (load) -> to DESTINATION (unload) -> repeat.
## It cruises CRUISE_ALT above the higher end of the leg, so it clears what it flies over.

const MAX_ACCEL := 9.0
const CRUISE := 12.0
const CRUISE_ALT := 8.0
const DOCK_DIST := 1.6
const DOCK_TIME := 0.8

enum S { HOME, TO_SOURCE, LOADING, TO_DEST, UNLOADING }
var port: DronePort
var state := S.HOME
var cargo: Dictionary = {}       # item_id -> count
var _timer := 0.0
var _goal := Vector3.ZERO

func _ready() -> void:
	gravity_scale = 0.0
	can_sleep = false
	mass = 60.0
	add_to_group("player_drone")
	set_meta("faction", "player")
	var h := Health.ensure(self, 60.0, "player")
	h.free_owner_on_death = false
	h.died.connect(func(_s: Node) -> void: queue_free())
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.0, 0.4, 1.0)
	cs.shape = sh
	add_child(cs)
	# body, four rotor rings, a cargo cage underneath, a status light
	Blockout.box(self, Vector3(0.6, 0.25, 0.6), Vector3.ZERO, Blockout.PAINT)
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		Blockout.box(self, Vector3(0.35, 0.04, 0.08), Vector3(d.x * 0.25, 0.0, d.y * 0.25), Blockout.STEEL).rotation.y = atan2(d.y, d.x)
		Blockout.cyl(self, 0.16, 0.03, Vector3(d.x * 0.42, 0.06, d.y * 0.42), Blockout.HAZARD)
	Blockout.box(self, Vector3(0.45, 0.25, 0.45), Vector3(0, -0.25, 0), Blockout.DARK)
	Blockout.cyl(self, 0.04, 0.05, Vector3(0, 0.15, 0.25), UiTokens.ACCENT, "y", "", true)

func state_name() -> String:
	return ["AT PORT", "TO SOURCE", "LOADING", "TO DESTINATION", "UNLOADING"][state]

func cargo_count() -> int:
	var n := 0
	for id: String in cargo:
		n += int(cargo[id])
	return n

func _physics_process(delta: float) -> void:
	if port == null or not is_instance_valid(port):
		queue_free()
		return
	var powered := port.work_speed > 0.0
	var ok_route := DronePort._valid(port.source) and DronePort._valid(port.destination)
	match state:
		S.HOME:
			_goal = port.pad_point()
			if powered and ok_route:
				state = S.TO_DEST if cargo_count() > 0 else S.TO_SOURCE
		S.TO_SOURCE:
			if not ok_route or not powered:
				state = S.HOME
			else:
				_fly_to(port.source)
				if _docked(port.source):
					state = S.LOADING
					_timer = 0.0
		S.LOADING:
			_timer += delta
			if _timer >= DOCK_TIME:
				_load()
				state = S.TO_DEST if cargo_count() > 0 else S.HOME
		S.TO_DEST:
			if not DronePort._valid(port.destination) or not powered:
				state = S.HOME
			else:
				_fly_to(port.destination)
				if _docked(port.destination):
					state = S.UNLOADING
					_timer = 0.0
		S.UNLOADING:
			_timer += delta
			if _timer >= DOCK_TIME:
				_unload()
				port.trips += 1
				state = S.HOME if not ok_route else S.TO_SOURCE

func _dock_point(b: Node3D) -> Vector3:
	return b.global_position + PlanetPhysics.get_up(b.global_position) * 2.6

## Climb to cruise altitude first, then cross, then descend onto the target (a leg over the base, not through it).
func _fly_to(b: Node3D) -> void:
	var target := _dock_point(b)
	var up := PlanetPhysics.get_up(global_position)
	var flat := target - global_position
	flat -= up * flat.dot(up)
	if flat.length() > 3.0:
		var alt := maxf((global_position - PlanetPhysics.get_planet_center(global_position)).length(),
			(target - PlanetPhysics.get_planet_center(target)).length()) + CRUISE_ALT
		var centre := PlanetPhysics.get_planet_center(global_position)
		var high_here := centre + (global_position - centre).normalized() * alt
		_goal = high_here + flat.normalized() * minf(flat.length(), CRUISE * 1.5)
	else:
		_goal = target

func _docked(b: Node3D) -> bool:
	return global_position.distance_to(_dock_point(b)) < DOCK_DIST

func _load() -> void:
	var room := DronePort.CARGO - cargo_count()
	for slot in port.source._inventory:
		if room <= 0:
			break
		if slot.item_id == "" or slot.count <= 0:
			continue
		var id: String = slot.item_id
		var n := mini(slot.count, room)
		if port.source.remove_item(id, n):
			cargo[id] = int(cargo.get(id, 0)) + n
			room -= n

func _unload() -> void:
	for id: String in cargo.keys():
		var n: int = cargo[id]
		# only what the destination actually takes (a smelter takes ore, a chest takes anything); the rest rides home
		var put := port.destination.add_input(id, n)
		cargo[id] = n - put
		if int(cargo[id]) <= 0:
			cargo.erase(id)

func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	var want := (_goal - global_position) * 0.9
	if want.length() > CRUISE:
		want = want.normalized() * CRUISE
	var accel := (want - st.linear_velocity) * 2.0
	if accel.length() > MAX_ACCEL:
		accel = accel.normalized() * MAX_ACCEL
	st.apply_central_force(accel * mass)     # engines give (accel - g), gravity gives g
	# stay level to the local up, nose along travel
	var up := PlanetPhysics.get_up(global_position)
	var cur := global_transform.basis.orthonormalized()
	var fwd := st.linear_velocity - up * st.linear_velocity.dot(up)
	var want_b := Basis.looking_at(fwd.normalized(), up) if fwd.length() > 0.5 else Basis.looking_at(-cur.z - up * (-cur.z).dot(up) if (-cur.z - up * (-cur.z).dot(up)).length() > 0.1 else up.cross(Vector3.RIGHT), up)
	var dq := (want_b * cur.inverse()).get_rotation_quaternion()
	var ax := dq.get_axis()
	var ang := dq.get_angle()
	if ang > PI:
		ang -= TAU
	st.angular_velocity = ax * ang * 3.0 if ax.is_finite() and absf(ang) > 0.001 else Vector3.ZERO

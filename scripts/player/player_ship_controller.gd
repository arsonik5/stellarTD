class_name PlayerShipController
extends Node

## Drives a possessed Ship from WASD/mouse/Space+Ctrl/Q+E, purely by setting
## its desired_linear_thrust/desired_angular_velocity each physics tick -
## same inputs any AI controller sets (see ship_steering.gd), so the player
## and every enemy genuinely share one flight model, not parallel ones.
## Spawned by player.gd's _enter_ship() and freed again on exit.

const MOUSE_SENSITIVITY := 0.0025
const MAX_TURN_RATE := 2.0
const ROLL_RATE := 1.2

signal exit_requested

var ship: Ship = null
var cockpit_camera: Camera3D = null
var chase_camera: Camera3D = null

var _mouse_delta := Vector2.ZERO
var _using_chase := false

func activate(cockpit_cam: Camera3D, chase_cam: Camera3D) -> void:
	cockpit_camera = cockpit_cam
	chase_camera = chase_cam
	_using_chase = false
	if cockpit_camera != null:
		cockpit_camera.far = 1000000.0
		cockpit_camera.current = true
	if chase_camera != null:
		chase_camera.far = 1000000.0

## Weapons (War Thunder style, see ShipWeaponControl). LMB = primary guns (or the selected weapon when the ship has
## no guns), MMB or B = secondary (the selected group), wheel / 1-9 = select secondary group, H = salvo size.
func weapons() -> ShipWeaponControl:
	return ShipWeaponControl.of(ship) if ship != null and is_instance_valid(ship) else null

func _has_primary(wc: ShipWeaponControl) -> bool:
	for g in wc.groups:
		if g["trigger"] == "primary":
			return true
	return false

func _exit_tree() -> void:
	var wc := weapons()
	if wc != null:
		wc.set_primary(false)
		wc.set_secondary(false)

func _unhandled_input(event: InputEvent) -> void:
	var wc := weapons()
	if wc != null and event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _has_primary(wc):
					wc.set_primary(event.pressed)
				else:
					wc.set_secondary(event.pressed)
			MOUSE_BUTTON_MIDDLE:
				wc.set_secondary(event.pressed)
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					wc.select_next(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					wc.select_next(1)
	if wc != null and event is InputEventKey and not event.echo:
		if event.keycode == KEY_B:
			wc.set_secondary(event.pressed)
		elif event.pressed and event.keycode == KEY_H:
			wc.cycle_salvo()
		elif event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var i: int = event.keycode - KEY_1
			if i < wc.secondary_groups().size():
				wc.selected = i
	if event is InputEventMouseMotion:
		_mouse_delta += event.relative
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V:
			_toggle_camera()
		elif event.keycode == KEY_G:
			ship.toggle_landing_gear()
		elif event.keycode == KEY_X:
			ship.dampeners_enabled = not ship.dampeners_enabled
		elif event.keycode == KEY_E or event.keycode == KEY_F or event.keycode == KEY_ESCAPE:
			exit_requested.emit()

func get_active_camera() -> Camera3D:
	return chase_camera if _using_chase else cockpit_camera

func _toggle_camera() -> void:
	_using_chase = not _using_chase
	if _using_chase and chase_camera != null:
		chase_camera.current = true
	elif not _using_chase and cockpit_camera != null:
		cockpit_camera.current = true

func _physics_process(_delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return

	var thrust := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		thrust.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		thrust.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		thrust.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		thrust.x += 1.0
	if Input.is_physical_key_pressed(KEY_SPACE):
		thrust.y += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL):
		thrust.y -= 1.0
	if thrust.length() > 1.0:
		thrust = thrust.normalized()
	ship.desired_linear_thrust = thrust

	var angular := Vector3(
		-_mouse_delta.y * MOUSE_SENSITIVITY / _delta,
		-_mouse_delta.x * MOUSE_SENSITIVITY / _delta,
		0.0
	)
	_mouse_delta = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_Q):
		angular.z += ROLL_RATE
	if Input.is_physical_key_pressed(KEY_R):
		angular.z -= ROLL_RATE
	if angular.length() > MAX_TURN_RATE:
		angular = angular.normalized() * MAX_TURN_RATE
	ship.desired_angular_velocity = angular

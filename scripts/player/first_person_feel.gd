class_name FirstPersonFeel
extends Node
## Everything that makes the first-person view feel physical (docs/game/ux-bible.md, "Feel"). The player script
## only moves the body and turns the head; this node layers motion on top, every frame at render rate:
##   camera  - step bob (a dip per footstep, not a smooth wave), small sideways sway and roll, landing dip,
##             sprint FOV push
##   tools   - lag behind the aim (sway), figure-eight bob in step with the camera, lean into strafes, a lowered
##             sprint pose, a drop on landing, raise on equip, and short kicks for using a tool
## All amplitudes are in one block below and scale with GameSettings head_bob / tool_sway, so a player who gets queasy
## can turn it down without losing anything else. `stepped` fires on each footstep (for sounds later).

signal stepped(left_foot: bool)

# --- tuning (metres, degrees, seconds). Change here only. -------------------------------------------------
const STEP_LENGTH := 1.9           # metres per footstep: 6 m/s -> 3.2 steps/s (a jog), 9.5 m/s sprint -> 5 steps/s
const CAM_BOB_Y := 0.045           # camera dip per step at full walk speed
const CAM_BOB_X := 0.022           # sideways shift, once per stride (two steps)
const CAM_ROLL := 0.55             # degrees of roll per stride
const SPRINT_BOB := 1.35           # bob multiplier while sprinting
const LAND_DIP_PER_MS := 0.018     # camera dip per m/s of landing speed
const LAND_DIP_MAX := 0.22
const SPRINT_FOV := 6.0            # degrees added at full sprint
const VM_SWAY := 0.00055           # tool offset per pixel of mouse motion (smoothed)
const VM_SWAY_MAX := 0.045
const VM_SWAY_ROT := 0.09          # degrees of tool yaw/pitch per pixel
const VM_BOB_X := 0.011
const VM_BOB_Y := 0.009
const VM_STRAFE_ROLL := 3.0        # degrees of lean at full strafe speed
const VM_IDLE := 0.0025            # breathing
const EQUIP_TIME := 0.28

var _player: CharacterBody3D
var _camera: Camera3D
var _vm: Node3D
var _cam_base := Vector3.ZERO
var _vm_rest := Transform3D.IDENTITY

var _phase := 0.0                  # stride phase, radians: one stride (left + right step) = TAU
var _move_blend := 0.0             # 0 standing .. 1 full walk speed, smoothed
var _sprint_blend := 0.0
var _look := Vector2.ZERO          # smoothed mouse delta (pixels/frame-ish)
var _look_accum := Vector2.ZERO
var _land := 0.0                   # current landing dip (metres), springs back
var _land_vel := 0.0
var _kick_pos := Vector3.ZERO      # tool kick offset, springs back
var _kick_rot := Vector3.ZERO
var _kick_vel_p := Vector3.ZERO
var _kick_vel_r := Vector3.ZERO
var _equip := 1.0                  # 0 = just equipped (lowered), 1 = up
var _shake := Vector3.ZERO
var _lunge := 0.0                  # smoothed 0..1 toward _lunge_target
var _lunge_target := 0.0
var _windup := 0.0
var _windup_target := 0.0
var _cam_shake := 0.0              # metres of camera jitter (the cutter buzzing in the hand), set every frame
var _time := 0.0
var _last_step := 0

func setup(player: CharacterBody3D, camera: Camera3D, viewmodel: Node3D) -> void:
	_player = player
	_camera = camera
	_vm = viewmodel
	_cam_base = camera.position
	_vm_rest = viewmodel.transform

## Mouse motion in pixels (already scaled by sensitivity).
func add_look(rel: Vector2) -> void:
	_look_accum += rel

## Drill vibration etc. - a per-frame jitter the player script computes.
func set_shake(v: Vector3) -> void:
	_shake = v

## 1 while the drill is boring: the tool pushes out toward the crosshair and stays there, like pressing into the rock.
func set_lunge(v: float) -> void:
	_lunge_target = v

## 0..1 while the drill spins up: the tool draws back and tilts up a little, like bracing before it bites.
func set_windup(v: float) -> void:
	_windup_target = v

## A fine buzz of the view while a tool vibrates (camera offset, so it never fights the player's own look).
func set_cam_shake(amount: float) -> void:
	_cam_shake = amount

func land(fall_speed: float) -> void:
	if fall_speed < 2.0:
		return
	_land_vel -= minf(fall_speed * LAND_DIP_PER_MS * 9.0, LAND_DIP_MAX * 9.0)
	_kick(Vector3(0, -minf(fall_speed * 0.006, 0.05), 0), Vector3(-minf(fall_speed * 0.8, 6.0), 0, 0))

func jump() -> void:
	_kick(Vector3(0, -0.02, 0.0), Vector3(3.0, 0, 0))

func equip() -> void:
	_equip = 0.0

## Short tool kicks: "place" (build tool shoves forward), "scan" (scanner bucks up), "deny" (small shake no).
func kick(kind: String) -> void:
	match kind:
		"place":
			_kick(Vector3(0, 0.0, -0.05), Vector3(-4.0, 0, 0))
		"scan":
			_kick(Vector3(0, 0.015, 0.03), Vector3(9.0, 0, 0))
		"deny":
			_kick(Vector3(0.012, 0, 0), Vector3(0, 0, 4.0))
		"hit":
			_kick(Vector3(0, -0.01, 0.025), Vector3(5.0, 0, 2.0))
		"engage":
			# the drill reaches speed and bites in: a hard shove forward
			_kick(Vector3(0, 0.004, -0.06), Vector3(-5.0, 0, 0))
		"mine":
			# one bite: a short extra shove forward and a tiny random jolt, on top of the held lunge
			_kick(Vector3(randf_range(-0.004, 0.004), randf_range(-0.003, 0.003), -0.022), Vector3(-1.5, 0, randf_range(-1.0, 1.0)))

func _kick(p: Vector3, r_deg: Vector3) -> void:
	_kick_vel_p += p * 22.0
	_kick_vel_r += r_deg * 22.0

func _process(delta: float) -> void:
	if _player == null:
		return
	delta = minf(delta, 0.05)
	_time += delta
	var bob_amt := float(GameSettings.get_value("head_bob"))
	var sway_amt := float(GameSettings.get_value("tool_sway"))
	var up := _player.up_direction
	var v := _player.velocity
	var flat := v - up * v.dot(up)
	var speed := flat.length()
	var grounded := _player.is_on_floor()
	var sprinting: bool = _player.get("sprinting") == true
	_move_blend = lerpf(_move_blend, clampf(speed / 6.0, 0.0, 1.6) if grounded else 0.0, minf(delta * 10.0, 1.0))
	_sprint_blend = lerpf(_sprint_blend, 1.0 if sprinting and speed > 3.0 else 0.0, minf(delta * 6.0, 1.0))

	# stride phase advances with distance walked, so steps land where the feet would
	if grounded and speed > 0.3:
		_phase += speed / STEP_LENGTH * PI * delta
		var step := int(floor(_phase / PI))
		if step != _last_step:
			_last_step = step
			stepped.emit(step % 2 == 0)
	else:
		# settle the phase back to a foot-planted pose so the camera doesn't freeze mid-bob
		var target := roundf(_phase / PI) * PI
		_phase = lerpf(_phase, target, minf(delta * 6.0, 1.0))

	# --- springs: landing dip and tool kicks (critically damped-ish) ----------------------------------
	_land_vel += (-_land * 140.0 - _land_vel * 18.0) * delta
	_land += _land_vel * delta
	_land = clampf(_land, -LAND_DIP_MAX, 0.05)
	_kick_vel_p += (-_kick_pos * 260.0 - _kick_vel_p * 24.0) * delta
	_kick_pos += _kick_vel_p * delta
	_kick_vel_r += (-_kick_rot * 260.0 - _kick_vel_r * 24.0) * delta
	_kick_rot += _kick_vel_r * delta

	# --- camera -----------------------------------------------------------------------------------------
	var amp := _move_blend * (1.0 + (SPRINT_BOB - 1.0) * _sprint_blend) * bob_amt
	var step_dip := -absf(sin(_phase)) * CAM_BOB_Y * amp            # sharp dip on each footfall
	var side := sin(_phase * 0.5) * CAM_BOB_X * amp                  # one sway per stride
	_camera.position = _cam_base + Vector3(side, step_dip + CAM_BOB_Y * amp * 0.5 + _land, 0.0)
	_camera.rotation.z = deg_to_rad(sin(_phase * 0.5) * CAM_ROLL * amp)
	_camera.fov = float(GameSettings.get_value("fov")) + SPRINT_FOV * _sprint_blend
	_camera.h_offset = randf_range(-1.0, 1.0) * _cam_shake * bob_amt
	_camera.v_offset = randf_range(-1.0, 1.0) * _cam_shake * bob_amt

	# --- tool ------------------------------------------------------------------------------------------
	_look = _look.lerp(_look_accum, minf(delta * 14.0, 1.0))
	_look_accum = _look_accum.lerp(Vector2.ZERO, minf(delta * 20.0, 1.0))
	_equip = minf(_equip + delta / EQUIP_TIME, 1.0)
	var e := 1.0 - pow(1.0 - _equip, 3.0)                           # ease-out
	var sway := Vector3(-_look.x, _look.y, 0.0) * VM_SWAY * sway_amt
	sway.x = clampf(sway.x, -VM_SWAY_MAX, VM_SWAY_MAX)
	sway.y = clampf(sway.y, -VM_SWAY_MAX, VM_SWAY_MAX)
	var bob := Vector3(sin(_phase * 0.5) * VM_BOB_X, -absf(cos(_phase * 0.5)) * VM_BOB_Y, 0.0) * amp
	var idle := Vector3(0, sin(_time * 1.6) * VM_IDLE, 0) * (1.0 - _move_blend)
	var right := _player.global_transform.basis.x
	var strafe := clampf(flat.dot(right) / 6.0, -1.0, 1.0)
	var sprint_pos := Vector3(0.03, -0.06, 0.05) * _sprint_blend
	_lunge = lerpf(_lunge, _lunge_target, minf(delta * 12.0, 1.0))
	_windup = lerpf(_windup, _windup_target, minf(delta * 14.0, 1.0))
	var lunge_pos := Vector3(-0.015, 0.012, -0.12) * _lunge        # forward (-Z), a touch toward the crosshair
	lunge_pos += Vector3(0.0, -0.01, 0.05) * _windup                # winding up: drawn back toward the player
	var pos := _vm_rest.origin + sway + bob + idle + sprint_pos + _kick_pos + _shake + lunge_pos
	pos.y -= (1.0 - e) * 0.28
	pos.y += _land * 0.35
	var rot := Vector3(
		deg_to_rad(_look.y * VM_SWAY_ROT * sway_amt - 12.0 * _sprint_blend - (1.0 - e) * 25.0 + _kick_rot.x + 4.0 * _windup),
		deg_to_rad(-_look.x * VM_SWAY_ROT * sway_amt + 22.0 * _sprint_blend + _kick_rot.y),
		deg_to_rad(-strafe * VM_STRAFE_ROLL * sway_amt + _kick_rot.z))
	var scale := _vm_rest.basis.get_scale()
	_vm.transform = Transform3D(Basis.from_euler(rot).scaled(scale), pos)

class_name MiningToolFx
extends Node
## Everything the Mining Tool (a hand-held rock drill) shows and sounds like while it bores (docs/game/ux-bible.md,
## "Mining tool"). The player script decides WHEN it bites and WHAT came away; this node turns that into:
##   motion   on the drill's own hand only (the other hand's tool stays still): pull-back and rattle while it winds
##            up; then it shoves forward a little (REACH) and turns partway toward the face so the bit points in,
##            but stays in the hand; a steady buzz, a small knock back on every bite, eases back on release
##   debris   chips in the colour of the rock being bored (the terrain's own texture x tint) thrown out of the face
##            and falling under planet gravity, dust in the same colour drifting off, sparks on hard rock
##   sound    two loops made in code: the motor (pitch follows the spin) and the grind (only while rock comes away,
##            higher on harder rock) - no per-bite clicks
## No beams or glows: it is a drill (Michael, 2026-11-08). One per player (Player._tool_fx). Particles live in the
## world (they stay where they fell when you turn).

const CONTACT_HOLD := 0.18               # s a contact point stays valid without a new bite
const REACH := 0.14                      # how far (world m) the drill shoves forward while it bores (it stays in the hand)
const TIP_IN := 0.06                     # how far the bit tip goes past the contact point (world m)
const BIT_TIP := 0.365                   # the bit tip, from the bit's pivot along its axis (model units)

var player: Node3D
var tool: Node3D                         # the MiningTool viewmodel node
var _bit: Node3D
var _tip_local := Vector3(0, 0.075, -0.57) # the bit tip in the tool's own frame (measured at setup)
var _chips: CPUParticles3D
var _dust: CPUParticles3D
var _sparks: CPUParticles3D
var _motor: AudioStreamPlayer
var _grind: AudioStreamPlayer

var _contact := Vector3.ZERO
var _contact_normal := Vector3.UP
var _contact_age := 99.0
var _cutting_age := 99.0                 # s since a bite last removed rock
var _hard := 1.0                         # hardness of the rock last bored
var _pulse := 0.0                        # bite thump, decays
var _recoil := 0.0
var _recoil_vel := 0.0
var _roll := 0.0
var _ext := 0.0                          # current push forward (parent-local m)
var _aim := 0.0                          # 0 = rest pose, 1 = turned toward the contact
var _t := 0.0
var _colours := {}                       # material index -> Color

func setup(p: Node3D, mining_tool: Node3D) -> void:
	player = p
	tool = mining_tool
	_bit = tool.find_child("*_Bit", true, false) as Node3D
	if _bit != null:
		# the tip in the tool's frame, walking the node chain (works before the tool is in the tree)
		var tip := _bit.transform * Vector3(0, 0, -BIT_TIP)
		var n: Node = _bit.get_parent()
		while n != null and n != tool and n is Node3D:
			tip = (n as Node3D).transform * tip
			n = n.get_parent()
		_tip_local = tip
	var world: Node = self                      # not a Node3D: 3D children here sit in world space, and the scene may still be loading
	_chips = _make_chips()
	_dust = _make_dust()
	_sparks = _make_sparks()
	for c in [_chips, _dust, _sparks]:
		world.add_child(c)
	_motor = _loop_player(_synth_motor(), -16.0)
	_grind = _loop_player(_synth_grind(), -14.0)

## A bite landed at `point` (world). removed = rock came away; hardness = the rock's (VoxelMaterials.hardness_for).
func bite(point: Vector3, toward_eye: Vector3, material_index: int, removed: bool, hardness: float) -> void:
	_contact = point
	# chips leave the face mostly upward (planet up), only partly toward the eye, so they don't fly into the camera
	_contact_normal = (toward_eye.normalized() * 0.35 + PlanetPhysics.get_up(point) * 0.65).normalized()
	_contact_age = 0.0
	_hard = hardness
	_pulse = 1.0
	_recoil_vel += 0.3 if removed else 0.18
	_roll = randf_range(-1.0, 1.0)
	if removed:
		_cutting_age = 0.0
		var c := colour_of(material_index)
		_chips.color = c
		_dust.color = Color(c.lightened(0.05), 0.32)

## Every frame. drilling = trigger held with the drill in hand; spin 0..1 over the wind-up; boring = spun up.
func update(delta: float, drilling: bool, spin: float, boring: bool, _aim_from: Vector3, _aim_dir: Vector3, _reach: float) -> void:
	_t += delta
	_contact_age += delta
	_cutting_age += delta
	var cutting := boring and _cutting_age < CONTACT_HOLD
	var touching := boring and _contact_age < CONTACT_HOLD
	_pulse = maxf(_pulse - delta * 9.0, 0.0)
	_place_debris(touching)
	_chips.emitting = cutting
	_dust.emitting = cutting
	_sparks.emitting = cutting and _hard >= 1.25
	_update_motion(delta, drilling, spin, boring, touching)
	_update_sound(drilling, spin, cutting)

## True while the bit is pushed into the face (tests).
func is_engaged() -> bool:
	return _ext > 0.05 and _contact_age < CONTACT_HOLD

## The bit tip in world space (tests).
func bit_tip() -> Vector3:
	return tool.global_transform * _tip_local

func last_contact() -> Vector3:
	return _contact

func _place_debris(touching: bool) -> void:
	if not touching:
		return
	for n: CPUParticles3D in [_chips, _dust, _sparks]:
		n.global_transform = Transform3D(_basis_toward(_contact_normal), _contact + _contact_normal * 0.05)
	var g := PlanetPhysics.get_up(_contact) * -7.5
	_chips.gravity = g
	_sparks.gravity = g * 0.6
	_dust.gravity = -g * 0.03

static func _basis_toward(n: Vector3) -> Basis:
	# local +Y = n (CPUParticles3D shoot along their local direction, set to +Y)
	var x := n.cross(Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	return Basis(x, n, x.cross(n).normalized())

# --- motion (the drill's hand only) -----------------------------------------------------------------------------------
func _update_motion(delta: float, drilling: bool, spin: float, boring: bool, touching: bool) -> void:
	if tool == null or not tool.visible:
		return
	var base_pos: Vector3 = tool.get_meta("vm_base_pos", tool.position)
	var base_rot: Vector3 = tool.get_meta("vm_base_rot", tool.rotation)
	var parent := tool.get_parent() as Node3D
	_recoil_vel += (-_recoil * 900.0 - _recoil_vel * 38.0) * delta
	_recoil += _recoil_vel * delta
	var rest := Basis.from_euler(base_rot)
	var aim_basis := rest
	var want_ext := 0.0
	var want_aim := 0.0
	if touching and parent != null:
		# turn toward the contact and push forward until the tip is TIP_IN past it (parent-local units)
		var c := parent.global_transform.affine_inverse() * _contact
		var to := c - base_pos
		var d := to.length()
		if d > 0.05:
			aim_basis = Basis.looking_at(to / d, Vector3.UP)
			var sc := parent.global_transform.basis.get_scale().x
			want_ext = clampf(d - absf(_tip_local.z) + TIP_IN / sc, 0.0, REACH / sc)
			want_aim = 1.0
	_ext = lerpf(_ext, want_ext, 1.0 - exp(-delta * (9.0 if want_ext > _ext else 6.0)))
	_aim = lerpf(_aim, want_aim, 1.0 - exp(-delta * 8.0))
	var windup := spin if (drilling and not boring) else 0.0
	var buzz := 0.0
	if boring:
		buzz = 0.0013
	elif drilling:
		buzz = 0.0025 * spin                             # the rattle as it winds up
	var b := rest.slerp(aim_basis, _aim * 0.55)        # turned partway toward the face: the bit points in, the drill stays in the hand
	var fwd := -b.z
	var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * buzz
	var wander := Vector3(sin(_t * 7.1), sin(_t * 5.3 + 1.0), 0.0) * 0.002 * (1.0 if boring else 0.0)
	var pos := base_pos + fwd * (_ext - _recoil * 0.02) + jit + wander
	pos += Vector3(0.0, -0.006, 0.035) * windup                # drawn back toward the body while it winds up
	var tilt := Basis.from_euler(Vector3(deg_to_rad(3.5 * windup + 2.0 * _recoil), 0.0, deg_to_rad(0.8 * _roll * _recoil)))
	tool.transform = Transform3D(b * tilt, pos)
	if player.get("feel") != null:
		player.feel.set_cam_shake((0.0008 + 0.0012 * _pulse) if boring else 0.0)

# --- sound -----------------------------------------------------------------------------------------------------------
func _update_sound(drilling: bool, spin: float, cutting: bool) -> void:
	var run := drilling
	if run and not _motor.playing:
		_motor.play()
	_motor.pitch_scale = lerpf(_motor.pitch_scale, (0.45 + 0.6 * spin) if run else 0.3, 0.12)
	var target_db := -16.0 if run else -60.0
	_motor.volume_db = lerpf(_motor.volume_db, target_db, 0.08 if run else 0.04)
	if not run and _motor.volume_db < -50.0 and _motor.playing:
		_motor.stop()
	if cutting and not _grind.playing:
		_grind.play()
	_grind.pitch_scale = lerpf(_grind.pitch_scale, 0.75 + 0.35 * clampf(_hard, 0.5, 2.5) / 2.5 + 0.2 * _pulse, 0.2)
	_grind.volume_db = lerpf(_grind.volume_db, -12.0 if cutting else -60.0, 0.25 if cutting else 0.1)
	if not cutting and _grind.volume_db < -50.0 and _grind.playing:
		_grind.stop()

func _loop_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -60.0
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(p)
	return p

const RATE := 22050

## Motor: a 1 s loop of a buzzy whine (whole cycles of 110 Hz and its overtones, so the loop has no seam), with a
## slow wobble like a loaded gearbox.
static func _synth_motor() -> AudioStreamWAV:
	var n := RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * 110.0 * t
		var v := 0.45 * sin(ph) + 0.25 * sin(2.0 * ph + 0.3) + 0.16 * sin(3.0 * ph + 1.1) + 0.1 * sin(5.0 * ph)
		v += 0.08 * sin(TAU * 440.0 * t) * (0.6 + 0.4 * sin(TAU * 4.0 * t))
		v *= 0.85 + 0.15 * sin(TAU * 6.0 * t)
		data.encode_s16(i * 2, int(clampf(v * 0.6, -1.0, 1.0) * 32767.0))
	return _wav(data)

## Grind: crackling band-limited noise (rock coming away), 1 s loop, cross-faded at the seam.
static func _synth_grind() -> AudioStreamWAV:
	var n := RATE
	var raw := PackedFloat32Array()
	raw.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var crack := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.35
		lp2 += (lp - lp2) * 0.08
		var band := lp - lp2                                # keep the mid band: a gritty hiss, not rumble or fizz
		if rng.randf() < 0.004:
			crack = 1.0
		crack *= 0.985
		raw[i] = band * (0.7 + 1.6 * crack) + 0.25 * lp2 * sin(TAU * 60.0 * float(i) / RATE)
	var fade := 2000
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := raw[i]
		if i < fade:
			var k := float(i) / fade
			v = v * k + raw[n - fade + i] * (1.0 - k)
		data.encode_s16(i * 2, int(clampf(v * 1.4, -1.0, 1.0) * 32767.0))
	return _wav(data.slice(0, (n - fade) * 2))

static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = data.size() / 2
	return s

# --- rock colour -----------------------------------------------------------------------------------------------------
## The colour of material `index` as the terrain draws it: its texture layer's average x the planet's tint.
func colour_of(index: int) -> Color:
	if _colours.has(index):
		return _colours[index]
	var c := Color(0.45, 0.42, 0.38)
	var terrain = player.get("_terrain")
	var mat: ShaderMaterial = terrain.material if terrain != null and terrain.get("material") is ShaderMaterial else null
	if mat != null:
		var arr := mat.get_shader_parameter("tex_albedo") as Texture2DArray
		var tints: Variant = mat.get_shader_parameter("pal_tint_rough")
		if arr != null and index < arr.get_layers():
			var img := arr.get_layer_data(index)
			if img != null:
				img = img.duplicate()
				if img.is_compressed():
					img.decompress()
				img.resize(4, 4, Image.INTERPOLATE_BILINEAR)
				var acc := Color(0, 0, 0)
				for y in 4:
					for x in 4:
						acc += img.get_pixel(x, y)
				c = Color(acc.r / 16.0, acc.g / 16.0, acc.b / 16.0)
		if tints is PackedVector4Array and index < (tints as PackedVector4Array).size():
			var tv: Vector4 = tints[index]
			c = Color(c.r * tv.x, c.g * tv.y, c.b * tv.z)
	c = Color(clampf(c.r, 0.05, 0.95), clampf(c.g, 0.05, 0.95), clampf(c.b, 0.05, 0.95))
	_colours[index] = c
	return c

# --- builders --------------------------------------------------------------------------------------------------------
static func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g

func _base_particles(amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.direction = Vector3.UP
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.18
	return p

## Rock chips: small irregular lumps, lit, tumbling, falling.
func _make_chips() -> CPUParticles3D:
	var p := _base_particles(140, 1.1)
	p.spread = 55.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.6
	p.damping_min = 0.5
	p.damping_max = 1.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.particle_flag_rotate_y = true
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.75, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.mesh = _chip_mesh()
	p.color_initial_ramp = _ramp(Color(0.55, 0.55, 0.55), Color(1.0, 1.0, 1.0))   # x the rock colour (set per bite)
	return p

static func _chip_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.026
	s.height = 0.034
	s.radial_segments = 5
	s.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	s.material = mat
	return s

## Dust: soft lit puffs that grow and drift.
func _make_dust() -> CPUParticles3D:
	var p := _base_particles(26, 2.0)
	p.spread = 45.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 2.2))
	p.scale_amount_curve = curve
	var alpha := Gradient.new()
	alpha.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	alpha.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	p.color_ramp = alpha
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Rocket._puff()
	mat.roughness = 1.0
	mat.disable_receive_shadows = true
	q.material = mat
	p.mesh = q
	p.color = Color(0.6, 0.55, 0.5, 0.55)
	return p

## Sparks: thin white-hot streaks, aligned with their flight.
func _make_sparks() -> CPUParticles3D:
	var p := _base_particles(60, 0.45)
	p.emission_sphere_radius = 0.08
	p.spread = 70.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.particle_flag_align_y = true
	var b := BoxMesh.new()
	b.size = Vector3(0.006, 0.07, 0.006)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.62, 0.25)
	mat.emission_energy_multiplier = 6.0
	b.material = mat
	p.mesh = b
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = shrink
	return p

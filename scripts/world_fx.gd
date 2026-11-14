extends Node
## WorldFx (autoload) - the world half of pillar 5 "every action answers back" (design/04-small-things.md):
## positional sound and one-shot particles for drilling, firing, impacts, explosions, launches and wrecks.
##
## Sound: synthesised at start-up with UiSound's own generators (no audio files yet; res://audio/world/<name>.wav
## wins over the synth when it exists). Played through a pool of AudioStreamPlayer3D. Air carries sound: the
## volume follows PlanetPhysics.get_air_density at the source, so in vacuum you only hear what is right next to
## you (through your suit), and a thin atmosphere sounds thin.
##
## Particles: CPUParticles3D (works on every renderer, including the compatibility one), gravity set from
## PlanetPhysics.get_gravity_accel at the spot - debris falls toward the planet's centre, never world -Y.

const VOICES := 16
const GAIN := {
	"drill": -14.0, "drill_machine": -18.0, "gun": -9.0, "cannon": -6.0, "hit": -14.0, "boom": -3.0,
	"launch": -6.0, "alien_fire": -12.0, "crash": -4.0, "clank": -12.0,
}
## Past this distance a sound is not played at all (cheap culling).
const MAX_HEAR := 260.0

var _streams := {}
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _last := {}

func _ready() -> void:
	for n: String in GAIN:
		var path := "res://audio/world/%s.wav" % n
		_streams[n] = load(path) if ResourceLoader.exists(path) else _synth(n)
	GameEvents.uplink_launched.connect(func(_n: int, src: Node) -> void:
		if src is Node3D:
			var p := (src as Node3D).global_position
			sound("launch", p)
			burst("smoke", p, PlanetPhysics.get_up(p)))
	GameEvents.destroyed.connect(func(t: Node, _s: Node) -> void:
		if t is Node3D and is_instance_valid(t):
			var p := (t as Node3D).global_position
			if t is Building or t is EnemyDrone:
				burst("explosion", p, PlanetPhysics.get_up(p))
				sound("boom", p))

func _synth(n: String) -> AudioStreamWAV:
	var u = UiSound
	var s := PackedFloat32Array()
	match n:
		"drill": s = u._mix([u._noise(0.16, 0.9, 0.01), u._tone([92.0, 184.0], 0.16, 0.01, 0.15, 1.0)])
		"drill_machine": s = u._mix([u._noise(0.3, 0.7, 0.02), u._tone([61.0, 122.0], 0.3, 0.02, 0.28, 1.0)])
		"gun": s = u._mix([u._noise(0.09, 1.0, 0.0005), u._glide(220.0, 70.0, 0.1, 0.0005, 1.0)])
		"cannon": s = u._mix([u._noise(0.35, 1.0, 0.0005), u._glide(110.0, 35.0, 0.4, 0.0005, 1.0)])
		"hit": s = u._mix([u._tone([1250.0, 2900.0], 0.06, 0.0005, 0.05, 0.6), u._noise(0.03, 0.6)])
		"boom": s = u._mix([u._noise(1.1, 1.0, 0.001), u._glide(90.0, 28.0, 1.0, 0.001, 1.0)])
		"launch": s = u._mix([u._noise(2.2, 0.8, 0.25), u._glide(60.0, 240.0, 2.2, 0.2, 0.6)])
		"alien_fire": s = u._glide(2400.0, 380.0, 0.16, 0.001, 0.4)
		"crash": s = u._mix([u._noise(0.8, 1.0, 0.001), u._tone([140.0, 420.0], 0.5, 0.001, 0.4, 1.0)])
		"clank": s = u._tone([620.0, 1490.0, 2310.0], 0.22, 0.0005, 0.2, 0.3)
	return u._to_wav(s)

## Voices live under this autoload (still in the root viewport's 3D world), so a scene change or reload can never
## free them out from under the pool.
func _voice() -> AudioStreamPlayer3D:
	if _players.size() < VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 12.0
		p.max_distance = MAX_HEAR
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players.append(p)
	var v := _players[_next]
	_next = (_next + 1) % VOICES
	return v

## Play `name` at a world position. Repeats closer than `min_gap` s (per sound) are dropped.
func sound(sound_name: String, pos: Vector3, pitch: float = 1.0, min_gap: float = 0.04) -> void:
	if not _streams.has(sound_name):
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var dist := cam.global_position.distance_to(pos) if cam != null else 0.0
	if dist > MAX_HEAR:
		return
	var air := PlanetPhysics.get_air_density(pos)
	# vacuum: only contact range carries (through the suit, muffled)
	if air < 0.02 and dist > 6.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound_name, -1.0)) < min_gap:
		return
	_last[sound_name] = now
	var v := _voice()
	if v == null:
		return
	v.stream = _streams[sound_name]
	v.global_position = pos
	v.volume_db = float(GAIN[sound_name]) + (linear_to_db(clampf(air, 0.05, 1.0)) if air < 1.0 else 0.0)
	v.pitch_scale = pitch * randf_range(0.95, 1.05) * (0.75 if air < 0.02 else 1.0)
	v.play()

## One-shot particle burst. kinds: dust, sparks, explosion, smoke, muzzle. `up` = local up at the spot.
func burst(kind: String, pos: Vector3, up: Vector3, tint: Color = Color(0.55, 0.53, 0.5)) -> CPUParticles3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.gravity = PlanetPhysics.get_gravity_accel(pos)
	p.direction = Vector3.UP        # in the particle node's local frame, which is aligned to `up` below
	var mesh := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	var life := 0.6
	match kind:
		"dust":
			p.amount = 14
			mesh.size = Vector2(0.25, 0.25)
			p.spread = 70.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 3.5
			p.color = Color(tint, 0.7)
			life = 0.9
		"sparks":
			p.amount = 16
			mesh.size = Vector2(0.05, 0.05)
			p.spread = 80.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 9.0
			p.color = Color(1.0, 0.7, 0.3)
			life = 0.4
		"muzzle":
			p.amount = 6
			mesh.size = Vector2(0.35, 0.35)
			p.spread = 15.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 5.0
			p.color = Color(1.0, 0.85, 0.5)
			life = 0.12
		"explosion":
			p.amount = 40
			mesh.size = Vector2(0.9, 0.9)
			p.spread = 180.0
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 12.0
			p.color = Color(1.0, 0.55, 0.2)
			life = 1.1
		"smoke":
			p.amount = 24
			mesh.size = Vector2(1.2, 1.2)
			p.spread = 25.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 3.0
			p.gravity = -p.gravity * 0.3   # hot smoke rises (along local up), against gravity
			p.color = Color(0.18, 0.17, 0.17, 0.6)
			p.explosiveness = 0.3
			life = 3.0
	p.lifetime = life
	scene.add_child(p)
	var u := up.normalized() if up.length() > 0.01 else Vector3.UP
	var side := u.cross(Vector3.RIGHT if absf(u.x) < 0.9 else Vector3.FORWARD).normalized()
	p.global_transform = Transform3D(Basis(side, u, side.cross(u)), pos)
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
	return p

## A smoking point that keeps puffing for `seconds` (wrecks, burning buildings).
func smoke_for(node: Node3D, seconds: float) -> void:
	if node == null:
		return
	var t := 0.0
	while t < seconds and is_instance_valid(node) and node.is_inside_tree():
		burst("smoke", node.global_position + PlanetPhysics.get_up(node.global_position) * 0.8, PlanetPhysics.get_up(node.global_position))
		await get_tree().create_timer(1.5).timeout
		t += 1.5

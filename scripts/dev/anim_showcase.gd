extends Node3D
## Animation reel: every machine running its Working loop, the turrets tracking a target and firing (their real
## _aim_at + the Fire animation), items flowing through a pipe run with knees and up a slope, the building pieces,
## and an orbiting camera. Record it with Godot's movie maker:
##   godot --path . res://scenes/dev/anim_showcase.tscn --write-movie art_src/ingame/reel.avi --fixed-fps 30
## (it quits by itself after DURATION seconds), then ffmpeg -i reel.avi -c:v libx264 -crf 20 reel.mp4

const DURATION := 24.0
const MACHINES := [
	["smelter", Vector3(-6.0, 0, 0)], ["processor", Vector3(-3.5, 0, 0)], ["constructor", Vector3(-1.5, 0, 0)],
	["chest", Vector3(0.5, 0, 0)], ["turret_gun", Vector3(3.0, 0, 0)], ["turret_cannon", Vector3(5.2, 0, 0)],
	["pipe_merger", Vector3(-3.5, 0, 3.5)], ["pipe_splitter", Vector3(-1.8, 0, 3.5)],
	["ship_core", Vector3(-6.0, 1.0, -4.5)], ["ship_gyroscope", Vector3(-3.6, 0.8, -4.5)],
	["ship_garage", Vector3(3.5, 0, -5.0)],
]
const PIECES := [
	["foundation", Vector3(7.5, 0.125, 3.0)], ["foundation_1m", Vector3(9.5, 0.5, 3.0)], ["foundation_2m", Vector3(11.5, 1.0, 3.0)],
	["ramp_1m", Vector3(9.5, 0.5, 5.0)], ["stairs_1m", Vector3(11.5, 0.5, 5.0)], ["frame_2m", Vector3(13.5, 1.0, 3.0)],
]
const PIPE := preload("res://scenes/pipe_segment.tscn")
const RUN := [Vector3(0, 0, 9), Vector3(0, 0, 6), Vector3(3, 1.07, 6), Vector3(6, 1.07, 8.5), Vector3(6, 3.0, 8.5)]

var _t := 0.0
var _cam: Camera3D
var _turrets: Array = []
var _pipes: Array[PipeSegment] = []
var _fire_t := 0.0
var _feed_t := 0.0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.035, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.52)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	_ground(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	for entry in MACHINES + PIECES:
		var node: Node3D = load("res://scenes/%s.tscn" % entry[0]).instantiate()
		node.position = entry[1]
		add_child(node)
		for p: AnimationPlayer in node.find_children("*", "AnimationPlayer", true, false):
			for a in p.get_animation_list():
				if String(a).begins_with("Working"):
					p.get_animation(a).loop_mode = Animation.LOOP_LINEAR
					p.play(a)
		if node is Turret:
			_turrets.append(node)
	# a pipe run laid the way the build tool lays it, with knees
	var upstream: PipeSegment = null
	for i in RUN.size() - 1:
		var p: PipeSegment = PIPE.instantiate()
		add_child(p)
		var c0: Vector3 = upstream.output_point() if upstream != null else RUN[i] + Vector3.UP * PipeSegment.PIPE_HEIGHT
		var c1: Vector3 = RUN[i + 1] + Vector3.UP * PipeSegment.PIPE_HEIGHT
		var leg := maxf(PipeSegment.knee_leg_for(upstream, c0, c1), 0.0)
		PipeSegment.lay(p, c0, c1, upstream if leg > 0.0 else null, leg, Vector3.UP)
		_pipes.append(p)
		upstream = p
	PipeSegment.relink_all(get_tree())
	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)
	_cam.make_current()

func _ground(pos: Vector3, size: Vector3) -> void:
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
	m.albedo_color = Color(0.13, 0.11, 0.1)
	m.roughness = 0.95
	mi.material_override = m
	body.add_child(mi)
	add_child(body)
	body.position = pos

func _process(delta: float) -> void:
	_t += delta
	# camera: a slow orbit, then close passes over the machines, the turrets and the pipe run
	var keys := [
		[0.0, Vector3(-2, 9, 16), Vector3(1, 0.5, 0)],
		[6.0, Vector3(-9, 3.2, 5), Vector3(-3.5, 1.0, 0)],
		[11.0, Vector3(8, 3.0, 5), Vector3(4.0, 1.2, 0)],
		[16.0, Vector3(-3, 3.5, 13), Vector3(3, 1.0, 7)],
		[20.0, Vector3(16, 4.5, 10), Vector3(10.5, 0.5, 3.5)],
		[24.0, Vector3(-2, 9, 16), Vector3(1, 0.5, 0)],
	]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if _t >= a[0] and _t < b[0]:
			var f := smoothstep(0.0, 1.0, (_t - a[0]) / (b[0] - a[0]))
			_cam.global_position = (a[1] as Vector3).lerp(b[1], f)
			_cam.look_at((a[2] as Vector3).lerp(b[2], f))
	# turrets track a target circling overhead and fire every 1.4 s
	var target := Vector3(sin(_t * 0.6) * 10.0, 5.0 + sin(_t * 0.9) * 2.0, -10.0 + cos(_t * 0.6) * 4.0)
	for turret: Turret in _turrets:
		turret._aim_at(target, delta)
	_fire_t += delta
	if _fire_t > 1.4:
		_fire_t = 0.0
		for turret: Turret in _turrets:
			for p: AnimationPlayer in turret.find_children("*", "AnimationPlayer", true, false):
				if p.has_animation("Fire"):
					p.stop()
					p.play("Fire")
	# items into the pipe run
	_feed_t += delta
	if _feed_t > 0.5 and _pipes.size() > 0:
		_feed_t = 0.0
		_pipes[0].pipe_accept(["ore_a", "ore_b", "ore_coal"][randi() % 3])
	if _pipes.size() > 0 and _pipes[-1].has_ready_item():
		_pipes[-1]._held_item_id = ""
		_pipes[-1]._item_cube.visible = false
	if _t > DURATION:
		get_tree().quit()

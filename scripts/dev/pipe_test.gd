extends Node3D
## Dev test for modular pipes and knees: lays a run the way the build tool does (PipeSegment.knee_leg_for + lay):
## level, up a 15 degree slope, a turn to the right, a 45 degree diagonal, then straight up. Sends an item in at
## the start and reports where it gets to, then saves screenshots to art_src/ingame/pipe_*.png and quits.
## godot --path . res://scenes/dev/pipe_test.tscn

const OUT := "res://art_src/ingame"
const PIPE := preload("res://scenes/pipe_segment.tscn")
## build-plane points of the run (the centreline is 0.45 m above them)
const RUN := [Vector3(0, 0, 6), Vector3(0, 0, 2), Vector3(0, 1.07, -2), Vector3(4, 1.07, -2), Vector3(7, 1.07, -5),
		Vector3(7, 3.6, -5)]

var _pipes: Array[PipeSegment] = []
var _frame := 0
var _cam: Camera3D

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
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	# ground with collision (the supports look for it) and a ramp under the slope
	_ground(Vector3(0, -0.5, 0), Vector3(40, 1, 40), Basis())
	var ramp_basis := Basis(Vector3.RIGHT, atan2(1.07, 4.0))
	_ground(Vector3(0, 0.535 - 0.5 * cos(atan2(1.07, 4.0)), 0), Vector3(3, 1, sqrt(1.07 * 1.07 + 16.0)), ramp_basis)
	_ground(Vector3(4, 1.07 - 0.5, -4), Vector3(9, 1, 6), Basis())
	var upstream: PipeSegment = null
	for i in RUN.size() - 1:
		var p: PipeSegment = PIPE.instantiate()
		add_child(p)
		var c_start: Vector3 = upstream.output_point() if upstream != null else RUN[i] + Vector3.UP * PipeSegment.PIPE_HEIGHT
		var c_end: Vector3 = RUN[i + 1] + Vector3.UP * PipeSegment.PIPE_HEIGHT
		var leg := PipeSegment.knee_leg_for(upstream, c_start, c_end)
		print("PIPE %d leg %.3f angle %.1f" % [i, leg, rad_to_deg(upstream.flow_dir().angle_to((c_end - c_start).normalized())) if upstream else 0.0])
		if leg < 0.0:
			push_error("pipe %d cannot be laid" % i)
			leg = 0.0
		PipeSegment.lay(p, c_start, c_end, upstream if leg > 0.0 else null, leg, Vector3.UP)
		_pipes.append(p)
		upstream = p
	PipeSegment.relink_all(get_tree())
	for i in _pipes.size() - 1:
		print("LINK %d -> %s" % [i, _pipes[i]._next == _pipes[i + 1]])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

func _ground(pos: Vector3, size: Vector3, basis: Basis) -> void:
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
	body.transform = Transform3D(basis, pos)

func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 20:
		_pipes[0].pipe_accept("ore_a")
	if _frame == 80:
		for i in _pipes.size():
			if _pipes[i]._held_item_id != "":
				print("ITEM in pipe %d progress %.2f" % [i, _pipes[i]._progress])
		_shot("pipe_run", Vector3(-6.5, 6.0, 8.0), Vector3(3.0, 1.0, -1.0))
	elif _frame == 90:
		_shot("pipe_knee_slope", Vector3(-1.8, 1.2, 3.0), Vector3(0, 0.6, 1.6))
	elif _frame == 100:
		_shot("pipe_knee_turn", Vector3(-1.2, 3.4, 0.2), Vector3(0.6, 1.5, -2.0))
	elif _frame == 105:
		_shot("pipe_support", Vector3(1.1, 0.75, 4.9), Vector3(0, 0.25, 4.0))
	elif _frame == 110:
		_shot("pipe_knee_up", Vector3(9.5, 2.6, -1.5), Vector3(7.0, 2.0, -5.0))
	elif _frame > 120 and (_frame > 2400 or (_pipes[-1]._held_item_id != "" and _pipes[-1]._progress >= 1.0)):
		var where := -1
		for i in _pipes.size():
			if _pipes[i]._held_item_id != "":
				where = i
		print("ITEM finally in pipe %d of %d at frame %d (last = reached the end)" % [where, _pipes.size() - 1, _frame])
		print("PIPETEST DONE")
		get_tree().quit()

func _shot(shot_name: String, from: Vector3, look: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 55
		add_child(_cam)
		_cam.make_current()
	_cam.global_position = from
	_cam.look_at(look)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, shot_name]))
	print("SAVED ", shot_name)

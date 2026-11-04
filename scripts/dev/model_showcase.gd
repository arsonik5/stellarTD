extends Node3D
## Dev showcase: spawns every building scene in a row, runs their animations, aims the turrets, saves
## screenshots from the game's own renderer, then quits.
## godot --path . res://scenes/dev/model_showcase.tscn

const ROW := [
	["smelter", Vector3(-5.5, 0, 0)], ["processor", Vector3(-3.0, 0, 0)], ["constructor", Vector3(-1.0, 0, 0)],
	["chest", Vector3(1.0, 0, 0)], ["turret_gun", Vector3(3.0, 0, 0)], ["turret_cannon", Vector3(5.0, 0, 0)],
	["pipe_segment", Vector3(-3.0, 0, 3.0)], ["pipe_merger", Vector3(-2.0, 0, 3.0)], ["pipe_splitter", Vector3(-1.0, 0, 3.0)],
	["foundation", Vector3(1.5, 0.125, 3.2)],
	["ship_core", Vector3(-5.0, 1.0, -4.0)], ["ship_cockpit", Vector3(-5.0, 0.8, -6.0)], ["ship_hull", Vector3(-3.0, 1.0, -4.0)],
	["ship_gyroscope", Vector3(-1.0, 0.8, -4.0)], ["ship_thruster", Vector3(-5.0, 1.0, -2.2)], ["ship_garage", Vector3(3.0, 0, -5.0)],
]
const OUT := "res://art_src/ingame"

var _frame := 0
var _turrets: Array = []

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
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.13, 0.11, 0.1)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	for entry in ROW:
		var packed: PackedScene = load("res://scenes/%s.tscn" % entry[0])
		var node: Node3D = packed.instantiate()
		node.position = entry[1]
		add_child(node)
		for p: AnimationPlayer in node.find_children("*", "AnimationPlayer", true, false):
			for anim_name in p.get_animation_list():
				if String(anim_name).begins_with("Working"):
					p.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
					p.play(anim_name)
		if node is Turret:
			_turrets.append(node)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

func _process(delta: float) -> void:
	_frame += 1
	# turrets track a point that swings left/right and up/down, through the real aim code path
	var t := _frame * 0.03
	for turret: Turret in _turrets:
		var target := turret.global_position + Vector3(sin(t) * 8.0, 2.0 + sin(t * 0.7) * 3.0, -8.0)
		turret._aim_at(target, delta)
	if _frame == 90:
		_shot("overview", Vector3(2.0, 6.5, 12.0), Vector3(0, 0.8, -0.5))
	elif _frame == 100:
		_shot("machines", Vector3(-1.5, 2.2, 6.5), Vector3(-1.5, 1.0, 0))
	elif _frame == 110:
		_shot("turrets", Vector3(6.5, 2.6, 4.5), Vector3(4.0, 1.3, 0))
	elif _frame == 120:
		_shot("ships", Vector3(-1.0, 3.5, 2.0), Vector3(-2.5, 0.8, -4.5))
	elif _frame == 130:
		_shot("logistics", Vector3(-0.5, 1.6, 6.0), Vector3(-1.5, 0.5, 3.0))
	elif _frame > 135:
		print("SHOWCASE DONE")
		get_tree().quit()

var _cam: Camera3D

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
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, shot_name]))
	print("SAVED ", shot_name)

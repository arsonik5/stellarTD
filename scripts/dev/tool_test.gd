extends Node3D
## Dev view of the held tools as the player sees them (same holder offset as scenes/player.tscn), animations running.
## Saves art_src/ingame/tool_<name>.png and quits.  godot --path . res://scenes/dev/tool_test.tscn
const TOOLS := ["MiningTool", "ScannerTool", "BuildTool"]
const PLAYER := preload("res://scenes/player.tscn")
var _frame := 0
var _holder: Node3D
var _cam: Camera3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.15, 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.8
	add_child(sun)
	# take the holder out of the player scene, so the offsets are exactly the game's
	var player := PLAYER.instantiate()
	var src: Node3D = player.get_node("Camera3D/ViewmodelTool")
	_cam = Camera3D.new()
	_cam.fov = 75
	add_child(_cam)
	_cam.make_current()
	_holder = src.duplicate() as Node3D
	_cam.add_child(_holder)
	player.free()
	for p: AnimationPlayer in _holder.find_children("*", "AnimationPlayer", true, false):
		for a in p.get_animation_list():
			if String(a).begins_with("Working"):
				p.get_animation(a).loop_mode = Animation.LOOP_LINEAR
				p.play(a)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art_src/ingame"))

func _show(only: String) -> void:
	for t in TOOLS:
		(_holder.get_node(t) as Node3D).visible = t == only

func _process(_d: float) -> void:
	_frame += 1
	for i in TOOLS.size():
		if _frame == 10 + i * 20:
			_show(TOOLS[i])
		elif _frame == 18 + i * 20:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://art_src/ingame/tool_%s.png" % TOOLS[i].to_lower()))
			print("SAVED ", TOOLS[i])
	if _frame > 80:
		get_tree().quit()

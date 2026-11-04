extends Node
## Icon baker (docs/game/ux-bible.md, "Icons"). Renders every item that has a model - buildings, ship parts, tools -
## into data/icons/<item_id>.png: 160 px, transparent, one fixed three-quarter camera, the same three lights for
## every icon, so the whole set reads as one family. Items without a model (ores, ingots, ammo) keep the drawn glyph
## in ItemIcon until they get pickup models. Rerun after any model change, then import:
##   godot --path . res://scenes/dev/bake_icons.tscn
##   godot --headless --path . --import
const OUT := "res://data/icons"
const SIZE := 160
const TOOL_MODELS := {
	"mining_tool": "res://data/models/tools/tool_mining/SM_MiningTool.glb",
	"scanner_tool": "res://data/models/tools/tool_scanner/SM_ScannerTool.glb",
	"building_tool": "res://data/models/tools/tool_build/SM_BuildTool.glb",
}
## Camera direction (from the object toward the camera) - three-quarter, slightly above, like a catalogue shot.
const VIEW_DIR := Vector3(1.0, 0.75, 1.35)

var _sv: SubViewport
var _cam: Camera3D
var _stage: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_sv = SubViewport.new()
	_sv.size = Vector2i(SIZE, SIZE)
	_sv.transparent_bg = true
	_sv.own_world_3d = true
	_sv.msaa_3d = Viewport.MSAA_8X
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8a949c")
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	_sv.add_child(env)
	for spec in [[Vector3(-40, 35, 0), 2.0, Color("fff4e6")], [Vector3(-15, -120, 0), 0.6, Color("b8d0e0")], [Vector3(-60, 160, 0), 0.9, Color("ffffff")]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_energy = spec[1]
		l.light_color = spec[2]
		_sv.add_child(l)
	_cam = Camera3D.new()
	_cam.fov = 30
	_sv.add_child(_cam)
	_run.call_deferred()

func _scene_for(id: String) -> PackedScene:
	if TOOL_MODELS.has(id):
		return load(TOOL_MODELS[id])
	var item := Inventory.get_item_def(id)
	if item == null:
		return null
	if item.building_scene != null:
		return item.building_scene
	if item.block_scene != null:
		return item.block_scene
	return null

func _run() -> void:
	var made := 0
	for id: String in ItemInfo.INFO:
		var scene := _scene_for(id)
		if scene == null:
			continue
		if _stage != null:
			_stage.queue_free()
		_stage = ModelMeshes.extract(scene)
		_sv.add_child(_stage)
		var box := ModelMeshes.bounds(_stage)
		if box.size.length() < 0.001:
			continue
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var dist := r / sin(deg_to_rad(_cam.fov * 0.5)) * 1.02
		_cam.look_at_from_position(c + VIEW_DIR.normalized() * dist, c, Vector3.UP)
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := _sv.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, id]))
		made += 1
		print("ICON ", id)
	print("ICONS DONE %d" % made)
	get_tree().quit()

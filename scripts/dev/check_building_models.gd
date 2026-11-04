extends SceneTree
## Headless check that every wired building scene loads, has its model, and that the model's animations and
## turret parts are where the code expects them.
## godot --headless --path . --script res://scripts/dev/check_building_models.gd

const SCENES := [
	"smelter", "processor", "constructor", "chest", "turret_gun", "turret_cannon", "foundation",
	"ship_core", "ship_cockpit", "ship_hull", "ship_gyroscope", "ship_thruster", "ship_garage",
	"pipe_segment", "pipe_merger", "pipe_splitter",
	"foundation_1m", "foundation_2m", "frame_2m", "ramp_1m", "stairs_1m",
]

func _init() -> void:
	var failures := 0
	for scene_name in SCENES:
		var path := "res://scenes/%s.tscn" % scene_name
		var packed: PackedScene = load(path)
		if packed == null:
			print("FAIL ", scene_name, ": scene did not load")
			failures += 1
			continue
		var root: Node = packed.instantiate()
		var model: Node = root.get_node_or_null("Model")
		if model == null:
			model = root.get_node_or_null("Body")
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		var players := root.find_children("*", "AnimationPlayer", true, false)
		var anims: Array = []
		for p: AnimationPlayer in players:
			anims.append_array(p.get_animation_list())
		var line := "%-15s model=%s meshes=%d anims=%s" % [scene_name, model != null, meshes.size(), str(anims)]
		if scene_name.begins_with("turret"):
			var head: Node = model.find_child("*_Head", true, false) if model else null
			var cradle: Node = model.find_child("*_Cradle", true, false) if model else null
			line += " head=%s cradle=%s cradle_under_head=%s" % [head != null, cradle != null, cradle != null and head != null and head.is_ancestor_of(cradle)]
			if head == null or cradle == null or not anims.has("Fire"):
				failures += 1
				line = "FAIL " + line
		if model == null or meshes.is_empty():
			failures += 1
			line = "FAIL " + line
		print(line)
		root.free()
	print("CHECK DONE failures=", failures)
	quit(1 if failures > 0 else 0)

extends SceneTree
## Lists every rock model's meshes: name, AABB size (m), triangles. Used to split rock-set files into scatter items.
##     godot --headless --path . --script res://scripts/dev/rock_inspect.gd
func _init() -> void:
	for d in DirAccess.get_directories_at("res://data/models/rocks"):
		for f in DirAccess.get_files_at("res://data/models/rocks/" + d):
			if not f.ends_with(".gltf"):
				continue
			var sc: PackedScene = load("res://data/models/rocks/%s/%s" % [d, f])
			if sc == null:
				print("ROCK %s LOAD FAIL" % d)
				continue
			var root := sc.instantiate()
			for mi in root.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).mesh
				var tris := 0
				for s in m.get_surface_count():
					tris += m.surface_get_array_len(s) / 3 if m.surface_get_array_index_len(s) <= 0 else m.surface_get_array_index_len(s) / 3
				print("ROCK %-24s %-28s size %s tris %d" % [d, mi.name, str(m.get_aabb().size * (mi as Node3D).global_transform.basis.get_scale() if mi.is_inside_tree() else m.get_aabb().size), tris])
			root.free()
	quit(0)

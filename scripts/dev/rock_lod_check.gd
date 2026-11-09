extends SceneTree
## Rock LOD0 vs LOD1: mesh bounds and the MeshInstance transform inside each .glb. They must agree, or the far LOD
## (and its shadow) sits somewhere else than the near one.
func _init() -> void:
	var root := "res://data/models/rocks"
	for m in DirAccess.get_directories_at(root):
		var dir := "%s/%s/game" % [root, m]
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
			continue
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".glb") or f.ends_with("_lod1.glb"):
				continue
			var a := _info("%s/%s" % [dir, f])
			var b := _info("%s/%s" % [dir, f.trim_suffix(".glb") + "_lod1.glb"])
			var bad := "" if b.is_empty() or (a.aabb.position.distance_to(b.aabb.position) < 0.05 and a.aabb.size.distance_to(b.aabb.size) < 0.1 and a.xf.is_equal_approx(b.xf)) else "  <-- MISMATCH"
			print("ROCK %-28s lod0 %s %s | lod1 %s %s%s" % [m + "/" + f.get_basename(), a.aabb, a.xf.origin, b.get("aabb"), b.xf.origin if not b.is_empty() else "-", bad])
	quit()

func _info(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var sc := load(path) as PackedScene
	var r := sc.instantiate()
	var mis := r.find_children("*", "MeshInstance3D", true, false)
	var out := {}
	if not mis.is_empty():
		var mi := mis[0] as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != r:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		out = {"aabb": mi.mesh.get_aabb(), "xf": xf}
	r.free()
	return out

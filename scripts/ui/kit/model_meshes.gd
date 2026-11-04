class_name ModelMeshes
## Copies just the visible meshes out of a scene (a building, a ship part, a tool) into a bare Node3D, without
## adding the original to the tree - so none of its scripts run. Used for the build ghost (the real silhouette as a
## hologram) and the icon baker (scripts/dev/bake_icons.gd). Meshes keep their transforms relative to the root.

static func extract(scene: PackedScene, material: Material = null) -> Node3D:
	var out := Node3D.new()
	if scene == null:
		return out
	var src := scene.instantiate()
	_walk(src, Transform3D.IDENTITY, out, material, true)
	src.free()
	return out

static func _walk(n: Node, xf: Transform3D, out: Node3D, material: Material, is_root: bool) -> void:
	var here := xf
	if n is Node3D and not is_root:
		here = xf * (n as Node3D).transform
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = (n as MeshInstance3D).mesh
		mi.transform = here
		mi.skeleton = NodePath()
		if material != null:
			mi.material_override = material
		else:
			mi.material_override = (n as MeshInstance3D).material_override
			for s in (n as MeshInstance3D).get_surface_override_material_count():
				mi.set_surface_override_material(s, (n as MeshInstance3D).get_surface_override_material(s))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if material != null else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		out.add_child(mi)
	for c in n.get_children():
		_walk(c, here, out, material, false)

## World-space-ish AABB of everything extracted (in the root's frame).
static func bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var b := mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

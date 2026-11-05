class_name Blockout
extends RefCounted
## Blockout models built in code for buildings that do not have a Blender model yet (BLOCKOUT stage of the
## model workflow, docs/workflow/claude-skill-blender-game-models/SKILL.md). Every piece still gets a job and a
## mount, per Michael's rule that every part must make mechanical sense - the comment at each call says what the
## part does and what it is fastened to. Replace with a real model (scene child named "Model") when one exists;
## buildings only build a blockout when that child is missing.

const STEEL := Color(0.42, 0.44, 0.46)
const DARK := Color(0.2, 0.21, 0.22)
const PAINT := Color(0.55, 0.56, 0.55)      # grey by default (art-direction, paint tool later)
const HAZARD := Color(0.85, 0.62, 0.15)     # moving / dangerous parts only
const GLASS := Color(0.45, 0.95, 0.85, 0.6) # crystal / status light (mint = OK, the UI's accent)

static func _mat(c: Color, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.metallic = 0.3
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = 1.5
	return m

static func root(owner: Node3D) -> Node3D:
	var r := Node3D.new()
	r.name = "Model"
	owner.add_child(r)
	return r

static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color = PAINT, name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = _mat(color)
	mi.position = pos
	if name != "":
		mi.name = name
	parent.add_child(mi)
	return mi

## Cylinder along local Y unless `axis` says otherwise ("x" or "z").
static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color = STEEL, axis := "y",
		name := "", emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	mi.mesh = m
	mi.material_override = _mat(color, emissive)
	mi.position = pos
	if axis == "x":
		mi.rotation.z = PI / 2.0
	elif axis == "z":
		mi.rotation.x = PI / 2.0
	if name != "":
		mi.name = name
	parent.add_child(mi)
	return mi

## Four bolts on a square flange: they fasten the part above to the part below.
static func bolts(parent: Node3D, center: Vector3, half: float) -> void:
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		cyl(parent, 0.035, 0.05, center + Vector3(d.x * half, 0.025, d.y * half), DARK)

## Output port on the footprint edge (+X side by convention, where pipes connect): a flange box with a collar.
static func port(parent: Node3D, height: float, side := 1.0) -> void:
	box(parent, Vector3(0.12, 0.5, 0.5), Vector3(0.94 * side, height, 0), DARK)                   # flange plate, welded to the casing
	cyl(parent, 0.18, 0.12, Vector3(1.0 * side, height, 0), STEEL, "x")                            # pipe collar the vacuum pipe clamps onto

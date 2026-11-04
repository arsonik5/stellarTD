class_name PipeKneeMesh
extends RefCounted
## Builds a pipe knee for any angle in any direction: the glass tube and its four guide rails swept along a
## circular arc (radius PipeSegment.KNEE_RADIUS), with the pipe's own collars on both ends (copies of the
## modular pipe model's EndIn/EndOut), so the knee bolts to the pipe before it and the pipe after it like any
## other joint. Nothing is a pre-made fixed-angle part; the bend is exactly the angle between the two pipes.

const GLASS_R := 0.25
const GLASS_IN := 0.235
const RAIL_RING := 0.262
const RAIL_R := 0.012
const RING_SEG := 32
const RAIL_SEG := 8

## g: PipeSegment._knee_geometry() (pipe-local). Returns a node to add under the pipe.
static func build(pipe: PipeSegment, g: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Knee"
	var body: Node3D = pipe.get_node("Body")
	var glass_mat: Material = null
	var steel_mat: Material = null
	var tube := body.find_child("SM_VacuumPipe", false, false) as MeshInstance3D
	if tube != null and tube.mesh != null:
		for i in tube.mesh.get_surface_count():
			var m := tube.mesh.surface_get_material(i)
			if m == null:
				continue
			if m.resource_name.contains("Glass"):
				glass_mat = m
			else:
				steel_mat = m
	var angle: float = g["angle"]
	var steps := maxi(4, ceili(rad_to_deg(angle) / 6.0))
	var d0: Vector3 = g["d0"]
	var axis: Vector3 = g["axis"]
	var c: Vector3 = g["c"]
	var a0: Vector3 = g["a0"]
	var up := Vector3.UP - d0 * Vector3.UP.dot(d0)
	if up.length() < 0.01:
		up = axis
	var n0 := up.normalized()
	var frames: Array = []
	for i in steps + 1:
		var phi := angle * i / steps
		var t := d0.rotated(axis, phi)
		var n := n0.rotated(axis, phi)
		frames.append([c + (a0 - c).rotated(axis, phi), t, n, t.cross(n)])
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sweep(glass, frames, Vector2.ZERO, GLASS_R, false)
	_sweep(glass, frames, Vector2.ZERO, GLASS_IN, true)
	_cap_annulus(glass, frames[0], GLASS_IN, GLASS_R, true)
	_cap_annulus(glass, frames[-1], GLASS_IN, GLASS_R, false)
	glass.generate_normals()
	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var off := Vector2(cos(a), sin(a)) * RAIL_RING
		_sweep(steel, frames, off, RAIL_R, false, RAIL_SEG)
		_cap_disc(steel, frames[0], off, RAIL_R, true)
		_cap_disc(steel, frames[-1], off, RAIL_R, false)
	steel.generate_normals()
	var mesh := glass.commit()
	if glass_mat != null:
		mesh.surface_set_material(0, glass_mat)
	steel.commit(mesh)
	if steel_mat != null:
		mesh.surface_set_material(1, steel_mat)
	var mi := MeshInstance3D.new()
	mi.name = "KneeTube"
	mi.mesh = mesh
	root.add_child(mi)
	# collars: input collar faces the upstream pipe at p0, output collar meets this pipe's own input collar at p1
	var end_in := body.find_child("*EndIn", true, false) as Node3D
	var end_out := body.find_child("*EndOut", true, false) as Node3D
	if end_in != null:
		var ci := end_in.duplicate() as Node3D
		root.add_child(ci)
		ci.transform = Transform3D(Basis.looking_at(d0, n0), g["p0"])
	if end_out != null:
		var d1: Vector3 = g["d1"]
		var co := end_out.duplicate() as Node3D
		root.add_child(co)
		co.transform = Transform3D(Basis.looking_at(d1, n0.rotated(axis, angle)), g["p1"])
	return root

## A tube of radius r swept through the frames, its centre offset by `off` in the frame's (normal, binormal) plane.
static func _sweep(st: SurfaceTool, frames: Array, off: Vector2, r: float, inward: bool, seg: int = RING_SEG) -> void:
	var rings: Array = []
	for f in frames:
		var p: Vector3 = f[0]
		var n: Vector3 = f[2]
		var b: Vector3 = f[3]
		var centre := p + n * off.x + b * off.y
		var ring: Array[Vector3] = []
		for k in seg:
			var a := TAU * k / seg
			ring.append(centre + (n * cos(a) + b * sin(a)) * r)
		rings.append(ring)
	for i in rings.size() - 1:
		for k in seg:
			var k2 := (k + 1) % seg
			var p00: Vector3 = rings[i][k]
			var p01: Vector3 = rings[i][k2]
			var p10: Vector3 = rings[i + 1][k]
			var p11: Vector3 = rings[i + 1][k2]
			_quad(st, p00, p10, p11, p01, inward)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flip: bool) -> void:
	var tri := [a, b, c, a, c, d] if not flip else [a, c, b, a, d, c]
	for p in tri:
		st.set_uv(Vector2(p.x + p.z, p.y))
		st.add_vertex(p)

static func _cap_annulus(st: SurfaceTool, f: Array, r_in: float, r_out: float, start: bool) -> void:
	var p: Vector3 = f[0]
	var n: Vector3 = f[2]
	var b: Vector3 = f[3]
	for k in RING_SEG:
		var a1 := TAU * k / RING_SEG
		var a2 := TAU * (k + 1) / RING_SEG
		var o1 := p + (n * cos(a1) + b * sin(a1)) * r_out
		var o2 := p + (n * cos(a2) + b * sin(a2)) * r_out
		var i1 := p + (n * cos(a1) + b * sin(a1)) * r_in
		var i2 := p + (n * cos(a2) + b * sin(a2)) * r_in
		_quad(st, i1, o1, o2, i2, not start)

static func _cap_disc(st: SurfaceTool, f: Array, off: Vector2, r: float, start: bool) -> void:
	var n: Vector3 = f[2]
	var b: Vector3 = f[3]
	var centre: Vector3 = f[0] + n * off.x + b * off.y
	for k in RAIL_SEG:
		var a1 := TAU * k / RAIL_SEG
		var a2 := TAU * (k + 1) / RAIL_SEG
		var p1 := centre + (n * cos(a1) + b * sin(a1)) * r
		var p2 := centre + (n * cos(a2) + b * sin(a2)) * r
		var tri := [centre, p1, p2] if not start else [centre, p2, p1]
		for p in tri:
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)

class_name PipeRoute
extends RefCounted
## Plans one pipe run between two points and lays it as a chain of PipeSegments (each a straight span with an inlet
## knee). The bends live INSIDE the new run, so laying a run never moves or shortens a pipe that is already there.
##
## Ends: "free" (ground, no direction), "pipe" (the open outlet / inlet of an existing pipe or junction: the run
## must carry on in that pipe's direction) or "port" (a machine's port: the run leaves / enters straight along the
## port's axis for PORT_STUB before it may bend).
## Modes:
##   STRAIGHT  runs along the ground axes and straight up/down, joined by tight 90 degree knees (KNEE_RADIUS)
##   CURVED    the shortest natural path: one wide arc (up to R_MAX) out of a fixed direction, two for an S
## A route is {"ok", "why", "points": centreline corners V0..Vn, "radii": bend radius per corner (0 at the ends),
## "legs": knee leg per corner}; build() turns it into pipes, samples() into a preview.

const PORT_STUB := 1.2               # straight out of / into a machine before the first bend
const PORT_KEEP := 0.5               # a bend may never eat closer than this to the machine
const MIN_SPAN := 0.3                # shortest straight a segment can have (PipeSegment.set_span clamps at 0.25)
const R_TIGHT := PipeSegment.KNEE_RADIUS
const R_MAX := 5.0
const SKIP := 0.03                   # a first leg the knee uses up entirely is not laid as its own pipe

static func plan(a: Vector3, a_dir: Vector3, a_kind: String, e: Vector3, e_dir: Vector3, e_kind: String,
		up: Vector3, curved: bool, hint: Vector3) -> Dictionary:
	if a.distance_to(e) < 0.3:
		return _fail("Too short")
	var l90 := PipeSegment.knee_leg(PI * 0.5, R_TIGHT)
	# straight stubs the ends force before the free part of the route
	var sa := 0.0
	if a_kind == "port":
		sa = PORT_STUB
	elif a_kind == "pipe" and not curved:
		sa = l90                                       # room for a 90 degree knee straight off the pipe's collar
	var se := 0.0
	if e_kind == "port":
		se = PORT_STUB
	elif e_kind == "pipe" and not curved:
		se = l90 + MIN_SPAN
	var p := a + a_dir * sa if a_dir != Vector3.ZERO else a
	var q := e - e_dir * se if e_dir != Vector3.ZERO else e
	var core: Array[Vector3] = []
	if curved:
		core = _curved_core(p, a_dir, q, e_dir, MIN_SPAN if e_kind != "port" else PORT_KEEP)
		if core.size() == 1 and core[0] == Vector3.INF:
			core = _manhattan(p, a_dir, q, e_dir, up, hint)
	else:
		core = _manhattan(p, a_dir, q, e_dir, up, hint)
	if core.size() == 1 and core[0] == Vector3.INF:
		return _fail("Can't turn back on itself here")
	var res := _assemble(a, p, sa, core, q, se, e, a_dir, e_dir, curved, a_kind == "port", e_kind == "port")
	if not res.ok and not core.is_empty():
		# no room for the axis route's bends (say a 20 cm step up): the direct line, sloped, between the stubs
		var direct := _assemble(a, p, sa, [], q, se, e, a_dir, e_dir, true, a_kind == "port", e_kind == "port")
		if direct.ok:
			return direct
	return res

static func _assemble(a: Vector3, p: Vector3, sa: float, core: Array[Vector3], q: Vector3, se: float, e: Vector3,
		a_dir: Vector3, e_dir: Vector3, curved: bool, a_port: bool, e_port: bool) -> Dictionary:
	var pts: Array[Vector3] = [a]
	if sa > 0.0:
		pts.append(p)
	pts.append_array(core)
	if se > 0.0:
		pts.append(q)
	pts.append(e)
	pts = _simplify(pts)
	if pts.size() < 2:
		return _fail("Too short")
	return _fit(pts, a_dir, e_dir, curved, a_port, e_port)

static func _fail(why: String) -> Dictionary:
	return {"ok": false, "why": why, "points": [], "radii": [], "legs": []}

## Corners between p and q along the ground axes and up: every order of the (up to three) axis moves is tried; the
## one with the fewest turns that never doubles back wins, rising/falling last when it's a tie.
static func _manhattan(p: Vector3, din: Vector3, q: Vector3, dout: Vector3, up: Vector3, hint: Vector3) -> Array[Vector3]:
	var e1 := _level(din, up)
	if e1 == Vector3.ZERO:
		e1 = _level(dout, up)
	if e1 == Vector3.ZERO:
		e1 = _level(q - p, up)
	if e1 == Vector3.ZERO:
		e1 = _level(hint, up)
	if e1 == Vector3.ZERO:
		e1 = up.cross(Vector3.RIGHT).normalized()
	var e2 := up.cross(e1).normalized()
	var d := q - p
	var moves: Array[Vector3] = []
	for axis in [e1, e2, up]:
		var c: float = d.dot(axis)
		if absf(c) > 0.01:
			moves.append(axis * c)
	var best: Array[Vector3] = [Vector3.INF]
	var best_score := INF
	for order in _orders(moves.size()):
		var dirs: Array[Vector3] = []
		if din != Vector3.ZERO:
			dirs.append(din)
		for i in order:
			dirs.append(moves[i].normalized())
		if dout != Vector3.ZERO:
			dirs.append(dout)
		var turns := 0
		var ok := true
		for k in dirs.size() - 1:
			var dot := dirs[k].dot(dirs[k + 1])
			if dot < cos(PipeSegment.KNEE_MAX_ANGLE):
				ok = false
				break
			if dot < 0.999:
				turns += 1
		if not ok:
			continue
		var vertical_late := 0
		for k in order.size():
			if absf(moves[order[k]].normalized().dot(up)) > 0.9 and k < order.size() - 1:
				vertical_late = 1
		var score := turns * 10.0 + vertical_late
		if score < best_score:
			best_score = score
			best = []
			var at := p
			for i in order:
				at += moves[i]
				best.append(at)
			if not best.is_empty():
				best.pop_back()                            # q itself is added by the caller
	return best

static func _orders(n: int) -> Array:
	match n:
		0: return [[]]
		1: return [[0]]
		2: return [[0, 1], [1, 0]]
	return [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

## A natural path: with a fixed start direction, one arc that comes out pointing straight at q (the corner sits where
## both tangent legs are equal); with a fixed end direction the mirror of that; with both, an S of two arcs.
## [INF] when q is behind the fixed direction (the caller falls back to the axis route, bent wide).
static func _curved_core(p: Vector3, din: Vector3, q: Vector3, dout: Vector3, keep: float) -> Array[Vector3]:
	var d := q - p
	var dl := d.length()
	if din == Vector3.ZERO and dout == Vector3.ZERO:
		return []
	if din != Vector3.ZERO and dout != Vector3.ZERO:
		if din.dot(d) <= 0.0 or dout.dot(d) <= 0.0:
			return [Vector3.INF]
		var k := dl * 0.35
		var out: Array[Vector3] = [p + din * k, q - dout * k]
		if din.dot(dout) > 0.999 and (q - p).normalized().dot(din) > 0.999:
			return []
		return out
	var dir := din if din != Vector3.ZERO else -dout
	var base := p if din != Vector3.ZERO else q
	var dd := d if din != Vector3.ZERO else -d
	var along := dd.dot(dir)
	if (dd - dir * along).length() < 0.02:
		return [] if along > 0.0 else [Vector3.INF]
	var m := keep
	var denom := 2.0 * (along + m)
	if denom <= 0.1:
		return [Vector3.INF]
	var t := (dd.length_squared() - m * m) / denom
	if t < 0.05:
		return [Vector3.INF]
	return [base + dir * t]

static func _level(v: Vector3, up: Vector3) -> Vector3:
	var l := v - up * v.dot(up)
	return l.normalized() if l.length() > 0.05 else Vector3.ZERO

static func _simplify(pts: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for v in pts:
		if not out.is_empty() and out[-1].distance_to(v) < 0.01:
			continue
		if out.size() >= 2:
			var d0 := (out[-1] - out[-2]).normalized()
			var d1 := (v - out[-1]).normalized()
			if d0.dot(d1) > 0.9995:
				out[-1] = v
				continue
		out.append(v)
	return out

## Bend radius per corner: as wide as the legs allow (CURVED, up to R_MAX) or tight (STRAIGHT), then every straight
## left between bends must still be a pipe of at least MIN_SPAN (or nothing at all for a fully used first leg).
static func _fit(pts: Array[Vector3], a_dir: Vector3, e_dir: Vector3, curved: bool, a_port: bool, e_port: bool) -> Dictionary:
	var n := pts.size()
	var lens: Array[float] = []
	var dirs: Array[Vector3] = []
	for i in n - 1:
		lens.append(pts[i].distance_to(pts[i + 1]))
		dirs.append((pts[i + 1] - pts[i]).normalized())
	if a_dir != Vector3.ZERO and dirs[0].dot(a_dir) < 0.999:
		return _fail("Can't bend right at the joint")
	if e_dir != Vector3.ZERO and dirs[-1].dot(e_dir) < 0.999:
		return _fail("Can't bend right at the joint")
	var radii: Array[float] = []
	var legs: Array[float] = []
	radii.resize(n)
	legs.resize(n)
	radii.fill(0.0)
	legs.fill(0.0)
	for i in range(1, n - 1):
		var ang := dirs[i - 1].angle_to(dirs[i])
		if ang > PipeSegment.KNEE_MAX_ANGLE:
			return _fail("Too sharp a turn")
		if ang < PipeSegment.KNEE_MIN_ANGLE:
			continue
		var th := tan(ang * 0.5)
		var before := lens[i - 1] - (PORT_KEEP if a_port else 0.0) if i == 1 else (lens[i - 1] - MIN_SPAN) * 0.5
		var after := lens[i] - (PORT_KEEP if e_port else MIN_SPAN) if i == n - 2 else (lens[i] - MIN_SPAN) * 0.5
		var want := (R_MAX if curved else R_TIGHT) * th + PipeSegment.COLLAR_W
		var leg := minf(want, minf(before, after))
		if leg < R_TIGHT * th + PipeSegment.COLLAR_W - 0.001:
			return _fail("No room to bend")
		legs[i] = leg
		radii[i] = (leg - PipeSegment.COLLAR_W) / th
	# the first leg is either used up by its knee (not laid) or long enough to be a pipe; a wide bend may grow to use
	# it up rather than leave a sliver
	var span0 := lens[0] - legs[1] if n > 2 else lens[0]
	if n > 2 and span0 > SKIP and span0 < MIN_SPAN:
		if curved and not a_port and legs[1] > 0.0:
			var th := tan(dirs[0].angle_to(dirs[1]) * 0.5)
			var grown := lens[0]
			var after1 := lens[1] - MIN_SPAN if n == 3 else (lens[1] - MIN_SPAN) * 0.5
			if grown <= after1:
				legs[1] = grown
				radii[1] = (grown - PipeSegment.COLLAR_W) / th
				span0 = 0.0
		if span0 > SKIP:
			return _fail("Too short a piece")
	for i in range(1, n - 1):
		var span := lens[i] - legs[i] - legs[i + 1]
		if span < MIN_SPAN - 0.001:
			return _fail("Too short a piece")
	if n == 2 and lens[0] < MIN_SPAN:
		return _fail("Too short")
	return {"ok": true, "why": "", "points": pts, "radii": radii, "legs": legs}

## Lays the route: one PipeSegment per leg (the first leg is skipped when its knee uses it up), each knee on the
## pipe after its corner. Returns the new pipes, upstream first. They are added under `parent`.
static func build(route: Dictionary, parent: Node, scene: PackedScene, up_at: Callable) -> Array[PipeSegment]:
	var out: Array[PipeSegment] = []
	var pts: Array = route["points"]
	var legs: Array = route["legs"]
	var radii: Array = route["radii"]
	var n := pts.size()
	for i in n - 1:
		var v0: Vector3 = pts[i]
		var v1: Vector3 = pts[i + 1]
		var d := (v1 - v0).normalized()
		var c0 := v0 + d * float(legs[i])
		var c1 := v1 - d * float(legs[i + 1])
		if i == 0 and c0.distance_to(c1) < SKIP and n > 2:
			continue
		var seg := scene.instantiate() as PipeSegment
		parent.add_child(seg)
		var up: Vector3 = up_at.call((c0 + c1) * 0.5)
		var ref := up if absf(d.dot(up)) < 0.999 else up.cross(Vector3.RIGHT).normalized()
		var basis := Basis.looking_at(d, ref)
		seg.global_transform = Transform3D(basis, (c0 + c1) * 0.5 - basis.y * PipeSegment.PIPE_HEIGHT)
		seg.set_span(c0.distance_to(c1))
		if i > 0 and float(legs[i]) > 0.0:
			seg.set_knee(v0, (v0 - pts[i - 1]).normalized(), float(radii[i]))
		seg.grid_pos = Vector3i(floori(seg.global_position.x), floori(seg.global_position.y), floori(seg.global_position.z))
		out.append(seg)
	return out

## How many pipes build() will lay (what the run costs).
static func piece_count(route: Dictionary) -> int:
	var pts: Array = route["points"]
	var legs: Array = route["legs"]
	var n := pts.size() - 1
	if pts.size() > 2 and float(pts[0].distance_to(pts[1])) - float(legs[1]) < SKIP:
		n -= 1
	return n

## Points along the route's centreline every `step` m: [position, flow direction], arcs included.
static func samples(route: Dictionary, step: float) -> Array:
	var pts: Array = route["points"]
	var radii: Array = route["radii"]
	var legs: Array = route["legs"]
	var path: Array = []                          # [position, tangent] dense
	var n := pts.size()
	for i in n - 1:
		var v0: Vector3 = pts[i]
		var v1: Vector3 = pts[i + 1]
		var d := (v1 - v0).normalized()
		var t0 := float(legs[i]) - PipeSegment.COLLAR_W if float(legs[i]) > 0.0 else 0.0
		var t1 := float(legs[i + 1]) - PipeSegment.COLLAR_W if float(legs[i + 1]) > 0.0 else 0.0
		if i > 0 and float(radii[i]) > 0.0:
			# the arc round corner i
			var dp: Vector3 = (v0 - (pts[i - 1] as Vector3)).normalized()
			var ang: float = dp.angle_to(d)
			var r := float(radii[i])
			var a0: Vector3 = v0 - dp * t0
			var axis: Vector3 = dp.cross(d).normalized()
			var c: Vector3 = a0 + (d - dp * dp.dot(d)).normalized() * r
			var k := maxi(2, ceili(r * ang / 0.1))
			for j in k + 1:
				var phi: float = ang * j / k
				path.append([c + (a0 - c).rotated(axis, phi), dp.rotated(axis, phi)])
		var s0 := v0 + d * t0
		var s1 := v1 - d * t1
		var k2 := maxi(1, ceili(s0.distance_to(s1) / 0.1))
		for j in k2 + 1:
			path.append([s0.lerp(s1, float(j) / k2), d])
	# resample at `step`
	var out: Array = []
	var acc := 0.0
	for j in range(1, path.size()):
		var seg_len: float = (path[j][0] as Vector3).distance_to(path[j - 1][0])
		acc += seg_len
		if acc >= step:
			acc = 0.0
			out.append(path[j])
	if out.is_empty() and not path.is_empty():
		out.append(path[path.size() / 2])
	return [path, out]

## A see-through tube along the route (surface 0, the caller colours it) with white arrowheads on top pointing the
## way items will flow (surface 1): the build ghost of a run.
static func preview_mesh(route: Dictionary, up_at: Callable) -> ArrayMesh:
	var s := samples(route, 1.0)
	var path: Array = s[0]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 16
	var r := 0.27
	var prev: Array[Vector3] = []
	for j in path.size():
		var p: Vector3 = path[j][0]
		var t: Vector3 = path[j][1]
		var up: Vector3 = up_at.call(p)
		var nrm := (up - t * up.dot(t))
		if nrm.length() < 0.01:
			nrm = t.cross(Vector3.RIGHT)
		nrm = nrm.normalized()
		var bin := t.cross(nrm).normalized()
		var ring: Array[Vector3] = []
		for k in seg:
			var a := TAU * k / seg
			ring.append(p + (nrm * cos(a) + bin * sin(a)) * r)
		if not prev.is_empty() and (path[j][0] as Vector3).distance_to(path[j - 1][0]) > 0.001:
			for k in seg:
				var k2 := (k + 1) % seg
				for v in [prev[k], ring[k], ring[k2], prev[k], ring[k2], prev[k2]]:
					st.add_vertex(v)
		prev = ring
	var mesh := st.commit()
	# arrows on their own surface, solid white, so they read on the see-through tube (mint or red)
	var arrows := SurfaceTool.new()
	arrows.begin(Mesh.PRIMITIVE_TRIANGLES)
	arrows_into(arrows, s[1], up_at, r + 0.04)
	arrows.commit(mesh)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	white.albedo_color = Color(1, 1, 1)
	mesh.surface_set_material(1, white)
	return mesh

## Flat arrowheads riding on top of a run (positions + flow directions), `lift` above the centreline.
static func arrows_into(st: SurfaceTool, marks: Array, up_at: Callable, lift: float) -> void:
	for m in marks:
		var p: Vector3 = m[0]
		var t: Vector3 = m[1]
		var up: Vector3 = up_at.call(p)
		var nrm := up - t * up.dot(t)
		if nrm.length() < 0.01:
			nrm = t.cross(Vector3.RIGHT)
		nrm = nrm.normalized()
		var side := t.cross(nrm).normalized()
		var c := p + nrm * lift
		var tip := c + t * 0.22
		var l := c - t * 0.13 + side * 0.17
		var rr := c - t * 0.13 - side * 0.17
		var notch := c - t * 0.03
		for v in [tip, l, notch, tip, notch, rr]:
			st.add_vertex(v)

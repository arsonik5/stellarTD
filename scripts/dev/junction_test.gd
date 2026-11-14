extends Node3D
## Headless test: merger and splitter connect in ANY orientation (round planet: local up is rarely world +Y).
## Builds  pipe A -> merger -> pipe B -> splitter -> pipes C, D, E  in a frame whose up is +Y, +X, and a random
## tilt, feeds 3 items into A and checks one item reaches each of C, D, E.
##   godot --headless --path . res://scenes/dev/junction_test.tscn
const PIPE := preload("res://scenes/pipe_segment.tscn")
const MERGER := preload("res://scenes/pipe_merger.tscn")
const SPLITTER := preload("res://scenes/pipe_splitter.tscn")

func _ready() -> void:
	var frames := {
		"up_y": Basis(),
		"up_x": Basis(Vector3(0, 0, 1), -PI / 2.0),
		"tilted": Basis(Vector3(0.3, 0.8, -0.5).normalized(), 1.1) * Basis(Vector3(1, 0, 0), 0.7),
	}
	var fails := 0
	for name in frames:
		var ok: bool = await _run(name, frames[name])
		print("JUNCTION %s %s" % [name, "PASS" if ok else "FAIL"])
		if not ok:
			fails += 1
	print("JUNCTION_DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func _pipe(root: Node3D, a: Vector3, b: Vector3, up: Vector3) -> PipeSegment:
	var p: PipeSegment = PIPE.instantiate()
	root.add_child(p)
	PipeSegment.lay(p, a + up * PipeSegment.PIPE_HEIGHT, b + up * PipeSegment.PIPE_HEIGHT, null, 0.0, up)
	return p

func _run(_name: String, rb: Basis) -> bool:
	var root := Node3D.new()
	root.position = Vector3(100, 50, -30)   # away from the origin, like anywhere on a planet
	add_child(root)
	var up := rb.y
	var fwd := -rb.z
	var right := rb.x
	var o := root.position
	var merger: PipeSegment = MERGER.instantiate()
	root.add_child(merger)
	merger.global_transform = Transform3D(rb, o)
	var a := _pipe(root, o - fwd * 3.0, o - fwd * 0.5, up)
	var b := _pipe(root, o + fwd * 0.5, o + fwd * 3.0, up)
	var s_pos := o + fwd * 3.5
	var splitter: PipeSegment = SPLITTER.instantiate()
	root.add_child(splitter)
	splitter.global_transform = Transform3D(rb, s_pos)
	var c := _pipe(root, s_pos + fwd * 0.5, s_pos + fwd * 3.0, up)
	var d := _pipe(root, s_pos - right * 0.5, s_pos - right * 3.0, up)
	var e := _pipe(root, s_pos + right * 0.5, s_pos + right * 3.0, up)
	PipeSegment.relink_all(get_tree())
	var outs := [c, d, e]
	var got := {}
	for i in 3:
		for t in 200:                           # wait until A can take the next item
			if a.pipe_accept("iron_ore"):
				break
			await get_tree().physics_frame
		for t in 240:
			await get_tree().physics_frame
	for p: PipeSegment in outs:
		got[p] = p.has_ready_item() or p._held_item_id != ""
	var n := 0
	for p in got:
		if got[p]:
			n += 1
	print("  %s: items in C/D/E = %s %s %s" % [_name, got[c], got[d], got[e]])
	root.queue_free()
	await get_tree().physics_frame
	return n == 3

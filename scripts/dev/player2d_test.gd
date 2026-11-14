extends Node

## Player2D movement rules on a hand-made map (no rendering needed).
##   godot --headless --path . res://scenes/dev/player2d_test.tscn

var _fails := 0

func _ready() -> void:
	var g := WorldGrid.new(40, 40)            # all level 0, no ramps
	# a 3-level mesa, x 20..29, y 5..14
	for y in range(5, 15):
		for x in range(20, 30):
			g.set_level(x, y, 3)
	# a ramp staircase at y 30: x 10 level 0 (ramp), x 11 level 1 (ramp), x 12.. level 2
	for x in range(11, 20):
		g.set_level(x, 30, 1 if x == 11 else 2)
	for x in [10, 11, 12]:
		g.flags[g.idx(x, 30)] |= WorldGrid.F_RAMP
	for x in range(12, 20):
		for y in [29, 31]:
			g.set_level(x, y, 2)                # walls on both sides of the upper path
	# two cliff corners touching diagonally at (5,5)/(6,6) with a gap tile (6,5)/(5,6) blocked too
	g.set_level(6, 5, 4)
	g.set_level(5, 6, 4)

	var p := Player2D.new()
	add_child(p)
	p.setup(g, null, Vector2i(15, 10))

	# 1) walk east into the mesa wall: stopped before x = 20
	await _walk(p, Vector2.RIGHT, 2.0)
	_check(p.position.x < 20 * 32 and p.level == 0, "a cliff stops you (x %.0f px, level %d)" % [p.position.x, p.level])

	# 2) up the ramp staircase to level 2
	p.position = Vector2(8.5, 30.5) * 32
	p.level = 0
	await _walk(p, Vector2.RIGHT, 2.0)
	_check(p.level == 2 and p.tile().x >= 13, "a ramp takes you up two levels (tile %s, level %d)" % [p.tile(), p.level])

	# 3) and back down
	await _walk(p, Vector2.LEFT, 2.0)
	_check(p.level == 0, "and back down (level %d)" % p.level)

	# 4) no squeezing between two diagonal cliff corners
	p.position = Vector2(5.5, 5.5) * 32
	p.level = 0
	await _walk(p, Vector2(1, 1).normalized(), 1.0)
	_check(p.tile() == Vector2i(5, 5), "no squeezing diagonally between two cliff corners (tile %s)" % p.tile())

	# 5) open ground: walking 1 s covers ~6 tiles
	p.position = Vector2(5.5, 20.5) * 32
	var x0 := p.position.x
	await _walk(p, Vector2.RIGHT, 1.0)
	var tiles := (p.position.x - x0) / 32.0
	_check(tiles > 4.5 and tiles < 6.5, "walk speed about 6 m/s (%.1f tiles in 1 s)" % tiles)

	print("PLAYER2D DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)

func _walk(p: Player2D, dir: Vector2, secs: float) -> void:
	p.input_override = dir
	var t := 0.0
	while t < secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	p.input_override = Vector2.ZERO
	p.velocity = Vector2.ZERO

func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

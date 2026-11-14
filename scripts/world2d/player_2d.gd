class_name Player2D
extends Node2D

## Top-down player (pivot-2d.md P1): WASD walks, the mouse aims. Movement is tile collision on WorldGrid data, not
## physics bodies: a step is allowed when WorldGrid.can_step says so (same level, or one level with a ramp), so
## cliffs block and ramps carry you up and down. Standing on level L the player is drawn with that level's lean,
## so it stays on its terrace when the camera moves (WorldView lean shader math).

signal level_changed(level: int)

const SPEED := 6.0 * WorldGrid.TILE_PX      ## px per second (6 m/s walk)
const RADIUS := 9.0                         ## collision half-size in px
const ACCEL := 12.0

var grid: WorldGrid
var view: WorldView
var level := 0
var aim := Vector2.RIGHT
var velocity := Vector2.ZERO
var input_override := Vector2.ZERO          ## tests drive movement through this (ignores the keyboard when set)

## --- mining (Mining2D): hold LMB on a tile in reach
var dig_target := Vector2i(-1, -1)
var dig_progress := 0.0                     ## 0..1 of the current tile
var dig_refused := ""                       ## why the tile under the cursor can't be dug ("" = it can)
var mine_override := Vector2i(-1, -1)       ## tests: dig this tile as if LMB were held on it
var mining_enabled := true                  ## off while build mode owns the mouse
var _hit_cool := 0.0
var _body: Node2D

func setup(g: WorldGrid, v: WorldView, at_tile: Vector2i) -> void:
	grid = g
	view = v
	position = (Vector2(at_tile) + Vector2(0.5, 0.5)) * WorldGrid.TILE_PX
	level = grid.level_at(at_tile.x, at_tile.y)
	_body = Node2D.new()
	_body.set_script(preload("res://scripts/world2d/player_body_2d.gd"))
	add_child(_body)
	_update_draw()

func tile() -> Vector2i:
	return grid.tile_of(position)

func _physics_process(dt: float) -> void:
	if grid == null:
		return
	var want := input_override
	if want == Vector2.ZERO:
		want = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_physical_key_pressed(KEY_A): want.x = -1.0
		if Input.is_physical_key_pressed(KEY_D): want.x = 1.0
		if Input.is_physical_key_pressed(KEY_W): want.y = -1.0
		if Input.is_physical_key_pressed(KEY_S): want.y = 1.0
		want = want.limit_length(1.0)
	velocity = velocity.lerp(want * SPEED, clampf(ACCEL * dt, 0.0, 1.0))
	# axis by axis, so you slide along a cliff instead of sticking to it
	_try_move(Vector2(velocity.x * dt, 0.0))
	_try_move(Vector2(0.0, velocity.y * dt))
	var t := tile()
	var lv := grid.level_at(t.x, t.y)
	if lv != level:
		level = lv
		level_changed.emit(level)
	if input_override == Vector2.ZERO:
		var mouse := get_global_mouse_position()
		if mouse.distance_to(position) > 2.0:
			aim = (mouse - position).normalized()
	_update_mining(dt)
	_update_draw()

func _update_mining(dt: float) -> void:
	var held := mine_override.x >= 0 or (mining_enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	var target := mine_override if mine_override.x >= 0 else grid.tile_of(_ground_point_under_mouse())
	dig_refused = Mining2D.refuse_reason(grid, tile(), level, target)
	if not held or dig_refused != "":
		dig_progress = 0.0
		dig_target = target
		return
	if target != dig_target:
		dig_target = target
		dig_progress = 0.0
	aim = (Vector2(target) + Vector2(0.5, 0.5) - position / WorldGrid.TILE_PX).normalized()
	dig_progress += dt / Mining2D.seconds_for(grid, target.x, target.y)
	_hit_cool -= dt
	if _hit_cool <= 0.0:
		_hit_cool = 0.18
		UiSound.play("mine_hit", randf_range(0.9, 1.1))
	if dig_progress >= 1.0:
		var paid := Mining2D.dig(grid, target.x, target.y)
		for id: String in paid:
			var took := Inventory.add(id, int(paid[id]))
			GameEvents.item_mined.emit(id, took, self)
		dig_progress = 0.0
		UiSound.play("pickup")

func _ground_point_under_mouse() -> Vector2:
	if view == null:
		return get_global_mouse_position()
	var tt := view.pick_tile(get_global_mouse_position(), level)
	return (Vector2(tt) + Vector2(0.5, 0.5)) * WorldGrid.TILE_PX

func _try_move(d: Vector2) -> void:
	if d == Vector2.ZERO:
		return
	var to := position + d
	var from_t := tile()
	for corner: Vector2 in [Vector2(-RADIUS, -RADIUS), Vector2(RADIUS, -RADIUS), Vector2(-RADIUS, RADIUS), Vector2(RADIUS, RADIUS)]:
		var ct := grid.tile_of(to + corner)
		if ct == from_t:
			continue
		if not _enterable(from_t, ct):
			return
	position = to

## Can the player's body overlap tile b while standing on tile a? Neighbours by can_step; a diagonal corner tile
## must be reachable through either side tile, so you cannot squeeze between two cliff corners.
func _enterable(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if absi(d.x) + absi(d.y) == 1:
		return grid.can_step(a.x, a.y, b.x, b.y)
	if absi(d.x) == 1 and absi(d.y) == 1:
		var via1 := Vector2i(b.x, a.y)
		var via2 := Vector2i(a.x, b.y)
		return (grid.can_step(a.x, a.y, via1.x, via1.y) and grid.can_step(via1.x, via1.y, b.x, b.y)) \
			or (grid.can_step(a.x, a.y, via2.x, via2.y) and grid.can_step(via2.x, via2.y, b.x, b.y))
	return false

## Lean like the terrain under us, and draw in that level's z band.
func _update_draw() -> void:
	z_index = WorldView.z_for_level(level)
	if _body == null or view == null or view.camera == null:
		return
	var cam := view.camera.get_screen_center_position()
	_body.position = (position - cam) * (float(level) * WorldGrid.LEVEL_HEIGHT / WorldView.CAM_HEIGHT)
	_body.set("aim", aim)
	_body.queue_redraw()

extends Node2D

## Tile cursor for the player's mining (and later building): an outline on the tile under the mouse, drawn with that
## tile's lean, white when it can be dug, red with the reason when not, cracks growing with dig progress.

var player: Player2D
var view: WorldView

func _ready() -> void:
	z_index = 200

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player == null or view == null or view.camera == null:
		return
	var t := player.dig_target
	var g := player.grid
	if not g.in_bounds(t.x, t.y):
		return
	var lv := g.level_at(t.x, t.y)
	var cam := view.camera.get_screen_center_position()
	var k := float(lv) * WorldGrid.LEVEL_HEIGHT / WorldView.CAM_HEIGHT
	var p := Vector2(t) * WorldGrid.TILE_PX
	var a := p + (p - cam) * k
	var b := p + Vector2(WorldGrid.TILE_PX, WorldGrid.TILE_PX)
	b = b + (b - cam) * k
	var ok := player.dig_refused == ""
	var col := Color(1, 1, 1, 0.8) if ok else Color(1, 0.35, 0.3, 0.6)
	draw_rect(Rect2(a, b - a), col, false, 1.0)
	if ok and player.dig_progress > 0.0:
		# cracks: lines from the centre outward, more and longer as the tile gives
		var c := (a + b) * 0.5
		var n := 2 + int(player.dig_progress * 6.0)
		for i in n:
			var ang := float(i) * 2.399 + float(t.x * 7 + t.y * 3)
			var len := (b - a).x * 0.5 * clampf(player.dig_progress * 1.2, 0.2, 1.0)
			draw_line(c, c + Vector2(cos(ang), sin(ang)) * len, Color(0.08, 0.07, 0.07, 0.9), 1.0)

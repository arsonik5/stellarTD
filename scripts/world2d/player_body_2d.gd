extends Node2D

## Placeholder astronaut drawn in code until real sprites exist (art is open, see PIVOT-PROGRESS.md): shadow, suit,
## backpack, visor facing the aim direction.

var aim := Vector2.RIGHT

func _draw() -> void:
	draw_circle(Vector2(3, 4), 9.0, Color(0, 0, 0, 0.35))                     # shadow
	var back := -aim * 6.0
	draw_rect(Rect2(back - Vector2(5, 5), Vector2(10, 10)), Color("#9aa0ae"))  # backpack
	draw_circle(Vector2.ZERO, 8.0, Color("#16161f"))
	draw_circle(Vector2.ZERO, 7.0, Color("#e6e8ee"))                          # suit
	draw_circle(aim * 3.5, 3.5, Color("#16161f"))
	draw_circle(aim * 3.5, 2.6, Color("#e8823a"))                             # visor
	draw_line(Vector2.ZERO, aim * 13.0, Color("#5c5f70"), 2.0)                # tool in hand

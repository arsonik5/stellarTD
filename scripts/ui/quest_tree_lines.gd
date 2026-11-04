extends Control

## Draws the connector lines between quest nodes in the Journal's tech tree.
## A separate Control sitting behind the node buttons rather than each
## button drawing its own edges, since a prerequisite->dependent edge
## naturally belongs to neither node alone.
var _segments: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(segments: Array) -> void:
	_segments = segments
	QuestManager.changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	for segment: Dictionary in _segments:
		var done: bool = QuestManager.get_state(segment.from_id) == "complete"
		var color := Color(UiTokens.ACCENT, 0.8) if done else Color(UiTokens.LINE_HI, 0.8)
		# right-angled connectors, like a schematic
		var mid_x: float = (segment.from_pos.x + segment.to_pos.x) * 0.5
		draw_polyline(PackedVector2Array([segment.from_pos, Vector2(mid_x, segment.from_pos.y), Vector2(mid_x, segment.to_pos.y), segment.to_pos]), color, 2.0)

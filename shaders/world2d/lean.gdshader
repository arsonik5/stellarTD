shader_type canvas_item;
// Perspective lean for the straight-down camera (pivot-2d.md 6.1, Unfallen): a vertex `h` px above the ground is
// drawn (world - cam_center) * h / cam_height further out from the screen centre. Height comes in UV.x (px).
// Used by terrain (tops and cliff walls) and anything else that stands up (buildings' raised layers, trees).

uniform vec2 cam_center;
uniform float cam_height = 420.0;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	VERTEX += (world - cam_center) * (UV.x / cam_height);
}

void fragment() {
	COLOR = COLOR;
}

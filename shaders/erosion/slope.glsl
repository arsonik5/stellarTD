#[compute]
#version 450

// Landform slope, measured on the FULL-resolution map and max-pooled down to
// mask resolution.
//
// The generator needs to know where the ground is steep so rock goes on cliffs
// and dust on flats. It used to difference a mask-resolution copy of the height,
// and that could not see a cliff: at ~61 m per texel a narrow escarpment is
// averaged into the flatter ground around it, and a 54 degree face measured as
// near-flat - so gating the rock band by it stripped the rock off that face.
//
// Differentiating an averaged height flattens a cliff; averaging a slope does
// not, and taking the MAX over the footprint keeps even a narrow one. So the
// slope is taken here at full resolution first, and only the result is shrunk.
//
// Output is the slope ANGLE / 90 degrees, 0..1, so it survives the generator's
// clamp-to-0..1 mask sampling and its thresholds read in degrees.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Normalised height, 0..1 over the body's whole relief.
layout(set = 0, binding = 0, r32f) uniform restrict readonly image2D height;
// Slope angle / 90, at mask resolution.
layout(set = 0, binding = 1, r32f) uniform restrict writeonly image2D slope;

layout(push_constant, std430) uniform Params {
	int width;
	int height_px;
	int out_width;
	int out_height;
	// Metres of height per unit of normalised height.
	float relief_m;
	// Metres of ground per texel along y (and along x at the equator).
	float metres_per_texel;
	float pad0;
	float pad1;
} params;

// NOTE: 8 words / 32 bytes. erosion_baker.gd must push exactly that - Godot
// refuses a mismatched push constant and skips the dispatch without failing.

ivec2 wrap(ivec2 p) {
	// Explicit, not `%`: GLSL leaves % on a negative operand undefined, and on this GPU it put a one-texel ridge
	// down the +-180 meridian of every full-size bake (2026-11-09).
	p.x = p.x < 0 ? p.x + params.width : (p.x >= params.width ? p.x - params.width : p.x);
	p.y = clamp(p.y, 0, params.height_px - 1);
	return p;
}

float h_at(ivec2 p) {
	return imageLoad(height, wrap(p)).r;
}

// cos(latitude): an x-texel covers less ground toward the poles. Same floor as
// the erosion passes, which keeps the east-west difference bounded at the rows
// the map cannot represent anyway.
float x_metric(int y) {
	float lat = 1.57079632679 - (float(y) + 0.5) / float(params.height_px) * 3.14159265359;
	return max(cos(lat), 0.05);
}

void main() {
	ivec2 o = ivec2(gl_GlobalInvocationID.xy);
	if (o.x >= params.out_width || o.y >= params.out_height) { return; }

	int fx = max(params.width / params.out_width, 1);
	int fy = max(params.height_px / params.out_height, 1);
	ivec2 base = ivec2(o.x * params.width / params.out_width,
		o.y * params.height_px / params.out_height);

	float steepest = 0.0;
	for (int dy = 0; dy < fy; dy++) {
		for (int dx = 0; dx < fx; dx++) {
			ivec2 p = base + ivec2(dx, dy);
			float gx = (h_at(p + ivec2(1, 0)) - h_at(p - ivec2(1, 0)))
				/ (2.0 * params.metres_per_texel * x_metric(p.y));
			float gy = (h_at(p + ivec2(0, 1)) - h_at(p - ivec2(0, 1)))
				/ (2.0 * params.metres_per_texel);
			float grade = length(vec2(gx, gy)) * params.relief_m;
			steepest = max(steepest, atan(grade));
		}
	}
	imageStore(slope, o, vec4(steepest / 1.57079632679, 0.0, 0.0, 0.0));
}

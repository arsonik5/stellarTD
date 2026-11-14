#[compute]
#version 450

// Turns a fixed-point accumulator into a normalised 0..1 float image.
//
// This exists because the CPU cannot afford to. The same work in GDScript is a
// per-pixel loop - decode, log, compare, scale, set_pixel - and at 10240x5120
// that is 52 million iterations per image, four images per bake. It was already
// the single largest cost at 4096 (4.7 s of readback against 7.4 s of actual
// erosion); at 2.5x the width it would have been minutes.
//
// Three dispatches, all trivial:
//   MODE_RANGE      find min and max, by atomics into an SSBO
//   MODE_HISTOGRAM  bin the values, so percentiles can be read off on the CPU
//   MODE_APPLY      map [lo, hi] -> [0, 1] into a float image
//
// Only the 2048-bin histogram crosses the bus before the final image, and that
// is 8 KB. The readback afterwards is a straight memcpy into Image.create_from_data
// with no per-pixel work on the CPU at all.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r32i) uniform restrict readonly iimage2D src;
layout(set = 0, binding = 1, r32f) uniform restrict writeonly image2D dst;

// bins[0 .. BINS-1]  histogram
// bins[BINS]         min, as a scaled int
// bins[BINS + 1]     max, as a scaled int
const int BINS = 2048;
layout(set = 0, binding = 2, std430) restrict buffer Bins {
	int bins[];
} b;

const int MODE_RANGE = 0;
const int MODE_HISTOGRAM = 1;
const int MODE_APPLY = 2;
// As APPLY, but past [lo, hi] the value rolls off (slope 1 at the edge, flattening to SOFT_KNEE beyond) instead of being
// clamped: a clamp turns whatever lies beyond the percentiles (crater floors, summits) into flat plates.
const int MODE_APPLY_SOFT = 3;
const float SOFT_KNEE = 0.15;

layout(push_constant, std430) uniform Params {
	int width;
	int height_px;
	int mode;
	int logarithmic;
	float scale;
	float lo;
	float hi;
	float pad;
} params;

// Values are compared as fixed-point ints so the atomics can be integer ones.
// GLSL has no float atomicMin/atomicMax.
const float RANGE_SCALE = 4096.0;

float value_at(ivec2 px) {
	float v = float(imageLoad(src, px).r) / params.scale;
	if (params.logarithmic != 0) {
		// log1p: zero stays zero, and the compression is gentle at the low end
		// where most of the surface lives.
		v = log(1.0 + max(v, 0.0));
	}
	return v;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= params.width || px.y >= params.height_px) { return; }

	float v = value_at(px);

	if (params.mode == MODE_RANGE) {
		int q = int(clamp(v * RANGE_SCALE, -2.0e9, 2.0e9));
		atomicMin(b.bins[BINS], q);
		atomicMax(b.bins[BINS + 1], q);
		return;
	}

	float span = max(params.hi - params.lo, 1e-9);

	if (params.mode == MODE_HISTOGRAM) {
		int bin = int(clamp((v - params.lo) / span, 0.0, 1.0) * float(BINS - 1));
		atomicAdd(b.bins[bin], 1);
		return;
	}

	float t = (v - params.lo) / span;
	if (params.mode == MODE_APPLY_SOFT) {
		if (t < 0.0) { t = -SOFT_KNEE * (1.0 - exp(t / SOFT_KNEE)); }
		else if (t > 1.0) { t = 1.0 + SOFT_KNEE * (1.0 - exp(-(t - 1.0) / SOFT_KNEE)); }
	} else {
		t = clamp(t, 0.0, 1.0);
	}
	imageStore(dst, px, vec4(t, 0.0, 0.0, 0.0));
}

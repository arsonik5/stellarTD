#[compute]
#version 450

// Thermal erosion: material on a slope steeper than its angle of repose slides
// down until it is not.
//
// This is what produces TALUS - the straight-sided debris aprons at the foot of
// every cliff in the reference photography, and the flat-topped, steep-sided
// look of a weathered plateau. Hydraulic erosion alone cuts valleys but leaves
// unnaturally steep walls standing; thermal erosion is what relaxes them to a
// believable angle and piles the result at the bottom.
//
// It is also the cheap half. One stencil pass over the map, no atomics, no
// ordering - each cell decides independently how much to shed to its lower
// neighbours.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r32i) uniform restrict readonly iimage2D src;
layout(set = 0, binding = 1, r32i) uniform restrict writeonly iimage2D dst;

// Thermal deposition, kept SEPARATE from the droplets' deposition mask.
//
// Both are "sediment", but they are different sediment in different places, and
// merging them loses the distinction that matters most for placing rock.
// Hydraulic deposition is silt and sand dropped where water slowed - valley
// floors, alluvial fans. Thermal deposition is TALUS: coarse angular blocks
// that fell off a face and came to rest at the angle of repose below it.
//
// Boulders belong on the second and not the first. A scree apron under a scarp
// is the single most common setting for loose rock on an airless world, and a
// silt fan is where boulders are conspicuously absent. With the two summed into
// one mask, boulders were being scattered across both.
layout(set = 0, binding = 2, r32i) uniform restrict iimage2D talus_map;

layout(push_constant, std430) uniform Params {
	int width;
	int height_px;
	float fixed_scale;
	// Maximum height difference between neighbouring cells that can stand, in
	// height units. Everything above this slides. This IS the angle of repose,
	// expressed per cell rather than in degrees.
	float talus;
	// Fraction of the excess moved per iteration. Below 0.5 for stability - at
	// higher values a cell can overshoot past its neighbours and the surface
	// oscillates into a checkerboard.
	float rate;
	float pad0;
	float pad1;
	float pad2;
} params;

ivec2 wrap(ivec2 p) {
	p.x = (p.x % params.width + params.width) % params.width;
	p.y = clamp(p.y, 0, params.height_px - 1);
	return p;
}

float h_at(ivec2 p) {
	return float(imageLoad(src, wrap(p)).r) / params.fixed_scale;
}

// How much real ground one texel of x covers, relative to one texel of y.
//
// On an equirectangular map this is cos(latitude): meridians converge, so near
// a pole two horizontally adjacent texels are almost the same place, while two
// vertically adjacent ones are as far apart as anywhere else.
//
// Ignoring this was the ring artifact. The angle of repose is an angle, so the
// height drop it permits between two cells has to scale with the real distance
// between them. With a constant per-cell limit, an east-west slope near the
// pole was allowed to stand 1/cos(lat) times steeper than the angle of repose -
// measured at 4.1-4.7x at +-80 degrees against 1.0 at the equator, on a base
// field that was isotropic (1.00) at every latitude. The poles kept corrugation
// that everywhere else got relaxed away, and on the sphere that reads as
// banding around the pole.
//
// Floored rather than allowed to reach zero: the top and bottom rows would
// otherwise permit no drop at all between x-neighbours and shed their entire
// difference every iteration. 0.05 is about 87 degrees of latitude, inside the
// row the map cannot represent meaningfully anyway.
float x_metric(int y) {
	float lat = 1.57079632679 - (float(y) + 0.5) / float(params.height_px) * 3.14159265359;
	return max(cos(lat), 0.05);
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= params.width || px.y >= params.height_px) { return; }

	float h = h_at(px);

	// Gather rather than scatter: this cell works out what it LOSES to lower
	// neighbours and what it GAINS from higher ones, all from reads. That is
	// what removes the need for atomics and makes the pass order-independent.
	float loss = 0.0;
	float gain = 0.0;
	float mx = x_metric(px.y);

	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			if (ox == 0 && oy == 0) { continue; }
			// Real distance to the neighbour, in units of one y-texel. This
			// covers the diagonals (further apart, so they support a larger drop
			// before the slope exceeds the angle of repose) and the east-west
			// compression toward the poles in the same expression.
			float ex = float(ox) * mx;
			float dist = sqrt(ex * ex + float(oy * oy));
			float limit = params.talus * dist;
			float hn = h_at(px + ivec2(ox, oy));

			float down = h - hn - limit;
			if (down > 0.0) { loss += down; }

			float up = hn - h - limit;
			if (up > 0.0) { gain += up; }
		}
	}

	// Divided by 8 because the excess was summed over all eight neighbours and
	// each of them is computing the mirror of this exchange. Without it the
	// same material is moved eight times and the surface collapses flat.
	float delta = (gain - loss) * params.rate / 8.0;
	imageStore(dst, px, ivec4(int((h + delta) * params.fixed_scale), 0, 0, 0));

	// Only the gain side: a cell that SHED material is being stripped, and a
	// cell that RECEIVED it is accumulating debris. Recording the net would
	// cancel the two against each other on a slope that is passing material
	// through, which is most of a talus field.
	if (delta > 0.0) {
		imageAtomicAdd(talus_map, px, int(delta * params.fixed_scale));
	}
}

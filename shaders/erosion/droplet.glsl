#[compute]
#version 450

// Hydraulic erosion by droplet simulation.
//
// This is the thing noise fundamentally cannot do. Noise produces a field whose
// statistics are the same everywhere; erosion produces CAUSES - water runs
// downhill, cuts where it is fast, drops what it carries where it slows. That
// is what makes valleys connect to each other, ridges sharpen between them, and
// sediment fan out at the bottom of slopes. Every one of those was being faked
// with a spline on a noise field before, and every one of those splines drew a
// visible contour band instead.
//
// One invocation per droplet. Height lives in an integer image as fixed point
// because GLSL has no float image atomics, and droplets genuinely do collide -
// several will touch the same cell in the same dispatch.
//
// The races that remain are benign and deliberate: a droplet may read a height
// another droplet is mid-way through changing. Erosion is a stochastic process
// averaged over millions of droplets, so a small amount of read/write skew
// changes nothing measurable. Serialising it would cost far more than it buys.

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, r32i) uniform restrict iimage2D height;

// The three EROSION MASKS, accumulated as the droplets run.
//
// This is the half of the World Machine model we were missing. Its erosion
// devices emit flow, wear and deposition alongside the height, and those masks
// are how it decides where rock, sediment and scree go. We were picking
// materials from an unrelated noise field instead, which is why the ground
// never agreed with the landform - dust sat on ridge crests, bare rock sat in
// basins, and no amount of tuning the noise could fix it, because the noise did
// not know where the water had been.
//
// They are nearly free: the droplets already compute all three, they were just
// being thrown away each step.
//
//   flow  - water volume that passed through the cell. Drainage networks, the
//           power-law channel structure you see from orbit.
//   wear  - total material removed. Scoured rock, cut banks, exposed bedrock.
//   depo  - total material dropped. Valley floors, fans, silt.
layout(set = 0, binding = 1, r32i) uniform restrict iimage2D flow_map;
layout(set = 0, binding = 2, r32i) uniform restrict iimage2D wear_map;
layout(set = 0, binding = 3, r32i) uniform restrict iimage2D depo_map;

// Flow is summed over every droplet that ever crossed a cell, so it reaches
// values thousands of times larger than any height. A coarser fixed point keeps
// it clear of a 32-bit overflow in the channels, where it matters most.
const float FLOW_SCALE = 1024.0;

layout(push_constant, std430) uniform Params {
	int width;
	int height_px;
	int seed;
	int droplet_count;

	int max_steps;
	float inertia;
	float capacity;
	float erode_rate;

	float deposit_rate;
	float evaporate;
	float gravity;
	float fixed_scale;

	float min_slope;
	float start_water;
	float start_speed;
	// Width of the dispatch grid in invocations, so a droplet id can be
	// recovered from a 2D dispatch. See main().
	int dispatch_width;
} params;

// NOTE: this block is 16 words / 64 bytes, and erosion_baker.gd must push
// exactly that. Godot validates the size and REFUSES a mismatched dispatch
// rather than truncating it, so getting this wrong does not crash - it produces
// a planet with no hydraulic erosion whatsoever, which still looks plausible.

// Longitude wraps, latitude clamps. Getting this wrong puts a seam of
// artificial cliffs down the +-180 meridian, which then collects drainage and
// becomes a permanent feature of every planet.
ivec2 wrap(ivec2 p) {
	p.x = (p.x % params.width + params.width) % params.width;
	p.y = clamp(p.y, 0, params.height_px - 1);
	return p;
}

float height_at(ivec2 p) {
	return float(imageLoad(height, wrap(p)).r) / params.fixed_scale;
}

float height_bilinear(vec2 pos) {
	ivec2 b = ivec2(floor(pos));
	vec2 f = fract(pos);
	float h00 = height_at(b);
	float h10 = height_at(b + ivec2(1, 0));
	float h01 = height_at(b + ivec2(0, 1));
	float h11 = height_at(b + ivec2(1, 1));
	return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}

// How much real ground one texel of x covers, relative to one texel of y.
//
// cos(latitude) on an equirectangular map. Water runs down the REAL slope, not
// the slope of the texel grid, and near a pole those are very different things:
// two horizontally adjacent texels there are nearly the same place. Without
// this, a droplet reads an east-west drop as gentle when it is not, and steps
// a full texel east when that covers almost no ground.
//
// Floored at 0.05 (about 87 degrees latitude) so the step below stays bounded.
float x_metric(float y) {
	float lat = 1.57079632679 - (y + 0.5) / float(params.height_px) * 3.14159265359;
	return max(cos(lat), 0.05);
}

// Gradient by central difference on the bilinear field, per unit of REAL
// distance rather than per texel.
vec2 gradient_at(vec2 pos) {
	float e = 1.0;
	float hx = height_bilinear(pos + vec2(e, 0.0)) - height_bilinear(pos - vec2(e, 0.0));
	float hy = height_bilinear(pos + vec2(0.0, e)) - height_bilinear(pos - vec2(0.0, e));
	return vec2(hx / x_metric(pos.y), hy) * 0.5;
}

// Deposit/erode spread over the four surrounding cells, weighted bilinearly.
// Applying the whole change to one cell leaves single-pixel spikes that survive
// into the mesh as visible needles.
void modify(vec2 pos, float amount) {
	ivec2 b = ivec2(floor(pos));
	vec2 f = fract(pos);
	float w00 = (1.0 - f.x) * (1.0 - f.y);
	float w10 = f.x * (1.0 - f.y);
	float w01 = (1.0 - f.x) * f.y;
	float w11 = f.x * f.y;
	imageAtomicAdd(height, wrap(b), int(amount * w00 * params.fixed_scale));
	imageAtomicAdd(height, wrap(b + ivec2(1, 0)), int(amount * w10 * params.fixed_scale));
	imageAtomicAdd(height, wrap(b + ivec2(0, 1)), int(amount * w01 * params.fixed_scale));
	imageAtomicAdd(height, wrap(b + ivec2(1, 1)), int(amount * w11 * params.fixed_scale));
}

// Erosion spread over a fixed 3x3 falloff kernel, not over the four cells under
// the droplet.
//
// This is the single thing that decides whether droplets carve a drainage
// network or a field of slots. Cutting into four cells means each droplet digs
// its own one-texel trench and neighbouring trenches never merge, so what comes
// out is a knife-edged slot with near-vertical walls rather than a valley. On a
// 12 m texel that is a 12 m wide, tens-of-metres deep gash, which the mesher
// renders as a fan of parallel corrugations - the artifact that looked like
// texture stretching in game and is visible in the bare heightmap with every
// noise band disabled.
//
// The offline numpy baker this was ported from always had the brush, and its
// own notes say why: "erode through a falloff brush disc, not a point... without
// it every droplet digs its own pit and they never merge into channels". The GPU
// port dropped it.
//
// FIXED 3x3 with constant weights rather than a radius loop. The first version
// took the radius as a parameter and computed distances per cell, which is 25
// loop iterations per erosion step - across 190 steps and tens of millions of
// droplets that was enough for the driver to decide the device had hung and
// reset it mid-bake. Weights are 1 - d/1.6 for d of 0, 1 and sqrt(2).
//
// Deposition deliberately stays bilinear: sediment IS dropped locally, and it is
// the erosion side that needs neighbouring droplet paths to overlap.
// Bilinear splat into a mask, matching how modify() spreads height. Writing the
// whole amount to one cell leaves single-texel speckle in the mask, which then
// shows up as speckled material assignment on the ground.
#define SPLAT(img, pos, amount, scale) { 	ivec2 b_ = ivec2(floor(pos)); 	vec2 f_ = fract(pos); 	imageAtomicAdd(img, wrap(b_), int((amount) * (1.0 - f_.x) * (1.0 - f_.y) * (scale))); 	imageAtomicAdd(img, wrap(b_ + ivec2(1, 0)), int((amount) * f_.x * (1.0 - f_.y) * (scale))); 	imageAtomicAdd(img, wrap(b_ + ivec2(0, 1)), int((amount) * (1.0 - f_.x) * f_.y * (scale))); 	imageAtomicAdd(img, wrap(b_ + ivec2(1, 1)), int((amount) * f_.x * f_.y * (scale))); }

uint rng_state;
float rand01() {
	rng_state ^= rng_state << 13;
	rng_state ^= rng_state >> 17;
	rng_state ^= rng_state << 5;
	return float(rng_state & 0xffffffu) / float(0xffffff);
}

void main() {
	// Dispatched in 2D, and this flattens it back to one droplet index.
	//
	// Vulkan guarantees only 65535 workgroups per dimension. At 64 droplets per
	// group that caps a 1D dispatch at about 4.2 million, and a 10240-wide map
	// wants 94 million - so the dispatch was over the limit and the driver
	// dropped it, running roughly 0.5% of the droplets in 351 ms where the work
	// should have taken 46 s. It failed silently: no error, no warning, just a
	// barely-eroded planet that still looked plausible.
	uint id = gl_GlobalInvocationID.x + gl_GlobalInvocationID.y * uint(params.dispatch_width);
	if (id >= uint(params.droplet_count)) { return; }

	rng_state = id * 747796405u + uint(params.seed) * 2891336453u + 1u;
	for (int i = 0; i < 4; i++) { rand01(); }

	// Spawned uniformly over the SPHERE, not over the map.
	//
	// An equirectangular row near a pole represents far less real surface than
	// one at the equator, so spawning uniformly in (u,v) concentrates droplets
	// at the poles and over-erodes them. The previous fix was to taper erosion
	// strength by latitude, which traded that for a visible horizontal band
	// where the taper kicked in - a ring right around the planet.
	//
	// Inverting the area distribution instead removes the problem rather than
	// masking it: lat = asin(1 - 2u) gives uniform density per unit sphere area,
	// so every droplet represents the same amount of ground and no taper is
	// needed anywhere.
	float lat = asin(clamp(1.0 - 2.0 * rand01(), -1.0, 1.0));
	float v_norm = (1.57079632679 - lat) / 3.14159265359;
	vec2 pos = vec2(rand01() * float(params.width), v_norm * float(params.height_px));
	vec2 dir = vec2(0.0);
	float speed = params.start_speed;
	float water = params.start_water;
	float sediment = 0.0;

	// Equirectangular cells shrink toward the poles, so a droplet there covers
	// far more real ground per step than one at the equator. Tapering its effect
	// stops the poles turning into an over-eroded scar - the same reason the
	// offline baker tapered them.
	// No taper: the spawn distribution above already accounts for cell area.
	float taper = 1.0;

	for (int step = 0; step < params.max_steps; step++) {
		ivec2 cell = ivec2(floor(pos));
		float h_old = height_bilinear(pos);
		vec2 grad = gradient_at(pos);

		// Momentum: a droplet does not turn instantly into the steepest
		// direction, which is what lets it cut through a saddle instead of
		// pooling in every local dip.
		dir = dir * params.inertia - grad * (1.0 - params.inertia);
		float len = length(dir);
		if (len < 1e-5) {
			// Stalled in a flat spot - nudge it randomly rather than killing it,
			// or basins never drain and fill with deposited sediment.
			dir = vec2(rand01() * 2.0 - 1.0, rand01() * 2.0 - 1.0);
			len = length(dir);
			if (len < 1e-5) { break; }
		}
		dir /= len;
		// One step of constant REAL length. Near a pole that is many texels east
		// and one texel north, which is what keeps a droplet's path a straight
		// line on the sphere instead of on the map.
		vec2 step_v = vec2(dir.x / x_metric(pos.y), dir.y);
		// Capped in TEXELS, because erosion is applied at discrete touch points.
		// A droplet running east near a pole would otherwise jump twenty texels
		// per step and deposit into the four cells around each landing, leaving
		// unmodified gaps between them - a dotted trail rather than a channel.
		// That high-frequency east-west structure is what remained of the ring
		// artifact once the angle of repose and the step length were corrected.
		float step_len = length(step_v);
		if (step_len > 2.0) { step_v *= 2.0 / step_len; }
		pos += step_v;

		if (pos.y < 1.0 || pos.y > float(params.height_px) - 2.0) { break; }

		float h_new = height_bilinear(pos);
		float dh = h_new - h_old;

		// Water that passed through here. Recorded per step regardless of
		// whether anything was eroded, because a channel is defined by the water
		// crossing it, not by whether that stretch happened to be cutting.
		SPLAT(flow_map, pos, water, FLOW_SCALE)

		// Carrying capacity falls with slope and speed. The max() is what stops
		// a droplet on flat ground from having zero capacity and dumping its
		// whole load as a pimple.
		float cap = max(-dh, params.min_slope) * speed * water * params.capacity;

		if (sediment > cap || dh > 0.0) {
			// Going uphill or over capacity: drop sediment. Uphill deposits only
			// enough to fill the step, which is what forms flat valley floors
			// rather than dams.
			float amount = (dh > 0.0) ? min(dh, sediment)
				: (sediment - cap) * params.deposit_rate;
			sediment -= amount;
			modify(pos - step_v, amount * taper);
			SPLAT(depo_map, pos - step_v, amount * taper, params.fixed_scale)
		} else {
			float amount = min((cap - sediment) * params.erode_rate, -dh);
			sediment += amount;
			modify(pos - step_v, -amount * taper);
			SPLAT(wear_map, pos - step_v, amount * taper, params.fixed_scale)
		}

		speed = sqrt(max(speed * speed + dh * params.gravity, 0.0));
		water *= (1.0 - params.evaporate);
		if (water < 0.001) { break; }
	}
}

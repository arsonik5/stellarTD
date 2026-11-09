#[compute]
#version 450

// Dust mantling: sediment settles into topography and subdues it.
//
// This is a real process and the dominant one on an airless or arid world.
// Fines drift, settle preferentially into low ground, and drape over everything
// below their own depth. It is why regolith plains read as SMOOTH while the rock
// beneath them is not, and why a gully system on a dusty world is softer-edged
// than the same system on bare stone.
//
// It is also the fix for a specific artifact. Hydraulic erosion cuts a dense
// comb of parallel channels down every slope, and on gentle mid-ground - where
// there is no landform to break them up - that comb reads as ripples across the
// whole meadow. Adding smooth material on TOP does not help, because the ripples
// are in the height field. This blurs the height field itself, and only where
// sediment actually collected.
//
// Weighted by the deposition mask, so it is selective rather than a global
// smooth. A global blur would take the edge off the ridges and scarps too, which
// are the parts that are working.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r32i) uniform restrict readonly iimage2D src;
layout(set = 0, binding = 1, r32i) uniform restrict writeonly iimage2D dst;
// Normalised deposition, 0..1.
layout(set = 0, binding = 2, r32f) uniform restrict readonly image2D depo;

layout(push_constant, std430) uniform Params {
	int width;
	int height_px;
	// Blur radius in texels. The channels being subdued are a few texels wide,
	// so this only has to be a few texels to reach across them.
	int radius;
	int pad0;
	// Deposition range over which mantling ramps from none to full.
	float dust_low;
	float dust_high;
	// Ceiling on the blend, so even the dustiest ground keeps some of its own
	// shape. At 1.0 the flattest areas go to glass and stop reading as ground.
	float max_blend;
	// FLOOR on the blend - applied everywhere, including bare scoured rock.
	//
	// Hydraulic erosion carves a comb of channels whose spacing is set by the
	// texel grid, so at 12.3 m per texel they land 30-50 m apart. That is right
	// for a gully system and wrong for a hillside, where it reads as regular
	// corrugation across the whole slope. Measured: at 24.6 m per texel the same
	// settings produce natural irregular terrain and the pattern disappears
	// entirely, which is what identified the channels rather than the noise or
	// the interpolation as the cause.
	//
	// The deposition weighting above cannot fix it, because the worst of it is
	// on scoured ground where there is no sediment to mantle. This takes the
	// edge off the comb everywhere while the weighting still does the real
	// mantling in the basins.
	float min_blend;
} params;

ivec2 wrap(ivec2 p) {
	// Explicit, not `%`: GLSL leaves % on a negative operand undefined, and on this GPU it put a one-texel ridge
	// down the +-180 meridian of every full-size bake (2026-11-09).
	p.x = p.x < 0 ? p.x + params.width : (p.x >= params.width ? p.x - params.width : p.x);
	p.y = clamp(p.y, 0, params.height_px - 1);
	return p;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= params.width || px.y >= params.height_px) { return; }

	int centre = imageLoad(src, px).r;
	float d = imageLoad(depo, px).r;
	float t = max(params.min_blend,
		smoothstep(params.dust_low, params.dust_high, d) * params.max_blend);
	if (t <= 0.001) {
		imageStore(dst, px, ivec4(centre, 0, 0, 0));
		return;
	}

	// Box blur rather than gaussian. Iterated - the baker runs this several
	// times - a box converges on a gaussian anyway, and it costs no weight
	// lookups. The east-west metric correction the other passes need does not
	// apply: this is a blur, not a slope measurement, so a wider real footprint
	// near the poles is harmless.
	float sum = 0.0;
	float n = 0.0;
	for (int oy = -params.radius; oy <= params.radius; oy++) {
		for (int ox = -params.radius; ox <= params.radius; ox++) {
			sum += float(imageLoad(src, wrap(px + ivec2(ox, oy))).r);
			n += 1.0;
		}
	}
	float blurred = sum / max(n, 1.0);
	imageStore(dst, px, ivec4(int(mix(float(centre), blurred, t)), 0, 0, 0));
}

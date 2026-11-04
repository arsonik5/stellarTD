#[compute]
#version 450

// Base heightfield for a planet, before erosion.
//
// Written into an equirectangular map but SAMPLED ON THE SPHERE DIRECTION, not
// on the (u,v) grid. Sampling the grid directly would squash features toward
// the poles and tear at the +-180 degree seam; going through the direction
// vector makes the field genuinely spherical, so the map wraps and the poles
// behave.
//
// Height is stored as FIXED POINT in an integer image, because the erosion pass
// needs imageAtomicAdd and GLSL has no float atomics. One unit = 1/FIXED_SCALE.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r32i) uniform restrict iimage2D height;

layout(push_constant, std430) uniform Params {
	int width;
	int height_px;
	int seed;
	int octaves;
	float frequency;
	float lacunarity;
	float gain;
	float fixed_scale;
	// Ridged share: 0 = pure fBm rolling hills, 1 = fully ridged. A blend of
	// the two is what gives both broad landmasses and sharp divides before
	// erosion has done anything.
	float ridge_mix;
	float warp_strength;
	// Mass shaping, applied to the base BEFORE erosion.
	//
	// Plain fBm is uniformly rolling: every part of it has the same amplitude,
	// so erosion has no distinct high masses to carve into and simply averages
	// the whole field toward its mean. That is why the result read as smooth
	// blobs with thin ridges and no mountains.
	//
	// This is NOT the same mistake as putting a spline on the final field. That
	// painted contour bands because the level sets survived into the output.
	// Here the curve shapes MASS and erosion then destroys those level sets by
	// carving through them - which is exactly what a real orogeny does.
	float mass_low;    // below this the base is pushed down into plains
	float mass_high;   // above this it is pushed up into massif
} params;

// Integer bit-mixing hash. A float product hash loses precision badly at the
// magnitudes involved here and degenerates into visible structure.
uint hash3(ivec3 p, uint seed) {
	uvec3 q = uvec3(p + ivec3(1024)) * uvec3(1597334673u, 3812015801u, 2798796415u);
	uint n = (q.x ^ q.y ^ q.z ^ seed) * 2654435761u;
	n ^= n >> 15;
	n *= 2246822519u;
	n ^= n >> 13;
	return n;
}

float hash3f(ivec3 p, uint seed) {
	return float(hash3(p, seed) & 0xffffffu) / float(0xffffff);
}

float value_noise(vec3 p, uint seed) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	// Quintic: continuous second derivative, so gradients stay smooth and the
	// erosion pass does not pick up lattice creases as drainage lines.
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	ivec3 b = ivec3(i);
	float n000 = hash3f(b + ivec3(0, 0, 0), seed);
	float n100 = hash3f(b + ivec3(1, 0, 0), seed);
	float n010 = hash3f(b + ivec3(0, 1, 0), seed);
	float n110 = hash3f(b + ivec3(1, 1, 0), seed);
	float n001 = hash3f(b + ivec3(0, 0, 1), seed);
	float n101 = hash3f(b + ivec3(1, 0, 1), seed);
	float n011 = hash3f(b + ivec3(0, 1, 1), seed);
	float n111 = hash3f(b + ivec3(1, 1, 1), seed);
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

const mat3 OCT_ROT = mat3(
	0.00, 0.80, 0.60,
	-0.80, 0.36, -0.48,
	-0.60, -0.48, 0.64);

float fbm(vec3 p, uint seed) {
	float sum = 0.0;
	float norm = 0.0;
	float amp = 1.0;
	float freq = params.frequency;
	for (int i = 0; i < params.octaves; i++) {
		float n = value_noise(p * freq, seed + uint(i) * 7919u);
		// Ridged form creases along the noise's zero set. Mixed rather than
		// chosen: pure fBm gives shapeless swells, pure ridged gives a uniform
		// corrugation, and erosion needs both broad mass and initial divides to
		// work with.
		float ridged = 1.0 - abs(n * 2.0 - 1.0);
		n = mix(n, ridged, params.ridge_mix);
		sum += n * amp;
		norm += amp;
		amp *= params.gain;
		freq *= params.lacunarity;
		p = OCT_ROT * p;
	}
	return norm > 0.0 ? sum / norm : 0.5;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= params.width || px.y >= params.height_px) { return; }

	// Equirectangular -> direction. Must match PlanetHeightmap.sample() exactly
	// or the eroded map will be applied rotated relative to how it was baked.
	float lon = (float(px.x) + 0.5) / float(params.width) * 6.28318530718 - 3.14159265359;
	float lat = 1.57079632679 - (float(px.y) + 0.5) / float(params.height_px) * 3.14159265359;
	vec3 dir = vec3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon));

	uint seed = uint(params.seed);
	// Domain warp, which is what stops the landmasses reading as symmetrical
	// blobs. Cheap here because this pass runs once, not per voxel.
	if (params.warp_strength > 0.0) {
		vec3 w = vec3(
			value_noise(dir * params.frequency * 0.5, seed + 101u),
			value_noise(dir * params.frequency * 0.5, seed + 202u),
			value_noise(dir * params.frequency * 0.5, seed + 303u)) - 0.5;
		dir = normalize(dir + w * params.warp_strength);
	}

	float h = fbm(dir, seed);

	// Redistribute: compress the middle, expand the ends. Plains become flatter
	// and uplands become genuinely higher, so there is relief for water to work
	// on rather than a uniform swell.
	if (params.mass_high > params.mass_low) {
		float t = clamp((h - params.mass_low) / (params.mass_high - params.mass_low), 0.0, 1.0);
		h = t * t * (3.0 - 2.0 * t);
	}
	imageStore(height, px, ivec4(int(h * params.fixed_scale), 0, 0, 0));
}

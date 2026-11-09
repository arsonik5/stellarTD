#[compute]
#version 450

// Impact craters from CraterField, added to the base heightfield BEFORE erosion (so erosion weathers them), plus two
// masks the rest of the planet reads:
//   fresh        bright immature ejecta of young craters: interior walls, the continuous blanket, rays (0..1)
//   crater_floor the inner floors of craters, where fines pond and crater-floor traits (crystal fields) sit (0..1)
// Profiles: CraterField's header. Every piece is smooth (smoothstep / smooth-min), because a kink in a profile
// becomes a ring in the hillshade.
//
// A pixel loops only the craters binned to its tile (CraterField.bin_tiles), so cost is per overlap, not per crater.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r32i) uniform restrict iimage2D height;
layout(set = 0, binding = 1, r32f) uniform restrict image2D fresh;
layout(set = 0, binding = 2, r32f) uniform restrict image2D floor_mask;
layout(set = 0, binding = 3, std430) restrict readonly buffer Craters { vec4 cr[]; };
layout(set = 0, binding = 4, std430) restrict readonly buffer TileStart { int tile_start[]; };
layout(set = 0, binding = 5, std430) restrict readonly buffer TileList { int tile_list[]; };

layout(push_constant, std430) uniform Params {
	int width;
	int height_px;
	int tile_px;
	int tiles_x;
	int y0;            // first row of this strip (the image is done in strips so no dispatch runs long)
	int accumulate;    // 0 = first pass writes the masks, 1 = later pass keeps the max
	int pad1;
	int pad2;
	float planet_radius_m;
	float fixed_per_m;  // fixed-point height units per metre of relief
	float ray_strength; // planet's: reach and brightness of rays
	float young_age;    // CraterField.YOUNG_AGE
	float pad3;         // padding in the middle: a trailing unused member is stripped and the sizes stop matching
	float pad4;
	// Only craters with age in [age_lo, age_hi) in this pass: old ones go in before erosion (and get worn and
	// filled), young ones after it (fresh bowls; water would otherwise fill every pit with sediment).
	float age_lo;
	float age_hi;
} p;

float hash1(float n) { return fract(sin(n * 12.9898 + 78.233) * 43758.5453); }

// smooth minimum (polynomial), k = blend width
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-4), 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// periodic wobble around the rim: irregular, never a lathe-turned circle
float wobble(float th, float s) {
	return 0.5 * sin(3.0 * th + s) + 0.3 * sin(5.0 * th + s * 1.7) + 0.2 * sin(9.0 * th + s * 2.3);
}

// one ray family: n rays at seeded angles, each with its own reach and width. Value 0..1.
float rays(float th, float d, float R, float s, float reach) {
	const float N = 28.0;
	float cell = th / 6.2831853 * N;
	float ci = floor(cell);
	float v = 0.0;
	for (int k = -1; k <= 1; k++) {
		float c = ci + float(k);
		float cw = mod(c, N);
		float h0 = hash1(cw + s);
		float h1 = hash1(cw * 1.31 + s * 0.7);
		float h2 = hash1(cw * 2.17 + s * 1.3);
		if (h2 < 0.35) { continue; }                           // gaps between ray groups
		float ang = (c + 0.2 + 0.6 * h0) / N * 6.2831853;
		float lat = (th - ang) * d;                            // lateral distance from the ray's axis, metres
		float len = R * (2.0 + (reach - 2.0) * h1);
		float w = R * (0.12 + 0.05 * d / R) * (0.6 + 0.8 * h2);
		float along = 1.0 - smoothstep(0.25 * len, len, d);
		float streak = 0.65 + 0.35 * sin(d / R * 2.7 + h0 * 40.0);   // rays are chains of secondaries, not lines
		v = max(v, exp(-(lat * lat) / (w * w)) * along * streak);
	}
	return v;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy) + ivec2(0, p.y0);
	if (px.x >= p.width || px.y >= p.height_px) { return; }

	// Equirectangular -> direction, exactly as generate.glsl.
	float lon = (float(px.x) + 0.5) / float(p.width) * 6.28318530718 - 3.14159265359;
	float lat = 1.57079632679 - (float(px.y) + 0.5) / float(p.height_px) * 3.14159265359;
	vec3 dir = vec3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon));

	int t = (px.y / p.tile_px) * p.tiles_x + (px.x / p.tile_px);
	float dh = 0.0;
	float fr = 0.0;
	float fl = 0.0;
	for (int i = tile_start[t]; i < tile_start[t + 1]; i++) {
		int k = tile_list[i] * 3;
		vec4 a = cr[k];
		vec4 b = cr[k + 1];
		vec4 e = cr[k + 2];
		float R = a.w;
		float age = b.z;
		if (age < p.age_lo || age >= p.age_hi) { continue; }
		float young = age < p.young_age ? 1.0 - age / p.young_age : 0.0;
		float reach = (young > 0.0 && p.ray_strength > 0.0) ? 3.0 + 9.0 * p.ray_strength : 3.0;
		vec3 v = dir - a.xyz;
		float chord = length(v);
		float d = 2.0 * asin(min(chord * 0.5, 1.0)) * p.planet_radius_m;   // great-circle distance, precise when small
		if (d > R * reach) { continue; }
		vec3 north = cross(a.xyz, e.xyz);
		float th = atan(dot(v, north), dot(v, e.xyz));
		float s = e.w;
		float wob = wobble(th, s);
		float x = d / R / (1.0 + 0.06 * wob);                 // irregular outline
		float depth = b.x;
		float rim = b.y * (1.0 + 0.3 * wobble(th * 1.0, s + 11.0));
		float kind = b.w;

		// --- height ------------------------------------------------------------------------------------------------
		float inner;
		if (kind < 0.5) {
			// simple: parabolic bowl; old ones have filled floors (flatter bottom)
			inner = -depth + (depth + rim) * pow(x, 2.0 + 3.0 * age);
		} else {
			// complex: flat floor, slumped walls in terraces
			float xf = 0.45;
			float tw = clamp((x - xf) / (1.0 - xf), 0.0, 4.0);
			float w = pow(tw, 1.6);
			float N = 3.0 + floor(hash1(s) * 2.0);
			float steps = (floor(w * N) + smoothstep(0.55, 1.0, fract(w * N))) / N;
			w = mix(w, steps, (0.55 * (1.0 - age)) * step(tw, 1.0));
			inner = -depth + (depth + rim) * w;
			if (kind > 1.5) {
				// central peak: a cluster, not a cone
				float px_r = 0.2 * (1.0 + 0.35 * wobble(th * 2.0, s + 5.0));
				float pk = clamp(1.0 - x / px_r, 0.0, 1.0);
				inner += depth * 0.45 * (1.0 - 0.5 * age) * pk * pk * (3.0 - 2.0 * pk);
			}
		}
		// outside: ejecta thickness ~ (r/R)^-3, faded to exactly zero at 3 R
		float outer = rim * pow(max(x, 1.0), -3.0) * (1.0 - smoothstep(2.2, 3.0, x));
		// inside, `outer` is the flat rim level and the bowl is lower; outside the bowl curve keeps rising and the
		// ejecta falls: the smooth minimum of the two is the whole profile, with a rounded crest (rounder when old)
		float h = smin(inner, outer, rim * (0.5 + 1.5 * age) + 1.0);
		h *= 1.0 - smoothstep(2.6, 3.0, x);
		dh += h;

		// --- masks -------------------------------------------------------------------------------------------------
		if (young > 0.0) {
			float wall = (1.0 - smoothstep(0.85, 1.0, x)) * smoothstep(0.2, 0.7, x) * 0.6;
			float blanket = smoothstep(0.85, 1.05, x) * (1.0 - smoothstep(1.2, 2.3 + 0.4 * wob, x)) * 0.85;
			float ry = (x > 0.9) ? rays(th, d, R, s, reach) * 0.75 : 0.0;
			fr = max(fr, young * max(wall, max(blanket, ry)));
		}
		if (R > 60.0) {
			fl = max(fl, 1.0 - smoothstep(0.45, 0.8, x));
		}
	}
	if (dh != 0.0) {
		int cur = imageLoad(height, px).r;
		imageStore(height, px, ivec4(cur + int(dh * p.fixed_per_m), 0, 0, 0));
	}
	if (p.accumulate != 0) {
		fr = max(fr, imageLoad(fresh, px).r);
		fl = max(fl, imageLoad(floor_mask, px).r);
	}
	imageStore(fresh, px, vec4(fr, 0.0, 0.0, 0.0));
	imageStore(floor_mask, px, vec4(fl, 0.0, 0.0, 0.0));
}

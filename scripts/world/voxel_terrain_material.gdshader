shader_type spatial;
// Back-face culling ON. cull_disabled also drew the inside of the surface, and Transvoxel's LOD transition cells
// produce thin near-coincident slivers whose back faces then z-fight with their own front faces.
render_mode depth_draw_opaque;

// Terrain surface (stage 2 of reports/AAA voxel terrain fidelity.md, 2026-11-09).
//
// Per pixel:
//   1. up to all FOUR materials the mesher blended at this vertex (MIXEL4), skipping any under 2% weight
//   2. each sampled BIPLANAR: only the two projections the surface faces most (IQ), with true gradients through
//      textureGrad, and the normal map turned into world space on that projection's own axes ("whiteout", Golus),
//      sign-corrected on back-facing projections so bumps light the same on every side
//   3. a DISTANCE LADDER per material (Space Engineers 1): the tile grows x4 every x4 in distance, cross-faded over
//      the last part of each step, ending in the material's flat far colour - no tile repeat at any range, and
//      from orbit the planet reads as its materials' real colours instead of a crawling texture
//   4. a HEIGHT BLEND of the layers (Unity TerrainLit / SE2-style): the material standing taller at a point wins
//      the contested band, with a narrow transition and a slow wander so edges follow the rock, not the voxel grid
//   5. per-material grade (saturation, height scale), macro albedo drift, specular occlusion and horizon fade
//
// Maps (packed by tools/pack_surface_set.py from CC0 photoscans, BC7 via scripts/dev/compress_surfaces.gd):
//     albedo array   RGB = albedo, A = roughness
//     normal array   RG  = normal XY (OpenGL), B = occlusion, A = height

uniform sampler2DArray tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_normal : hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_enable;

// Per-material palette, uploaded by the owning Planet (SurfacePalette). Zero defaults mean "unchanged".
uniform vec4 pal_tint_rough[16];   // rgb = albedo tint, a = roughness scale
uniform vec4 pal_extra[16];        // x = normal strength, y = metallic, z = specular, w = tile size (m)
uniform vec4 pal_grade[16];        // x = saturation - 1, y = height blend scale - 1, z = height offset, w = crack polygon m (0 = none)
uniform vec4 pal_far[16];          // rgb = far colour (linear, tinted), a = 1 when set (0 = derive from the ladder)

uniform float macro_scale : hint_range(4.0, 600.0) = 140.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.30;
// Biplanar weight sharpness (IQ's k). Higher = tighter seams between the two projections.
uniform float biplanar_sharpness : hint_range(1.0, 16.0) = 8.0;
// Height blend: transition width (in height units) and how much the materials' own heights decide the edge.
uniform float height_blend : hint_range(0.0, 1.0) = 0.65;
uniform float blend_edge : hint_range(0.02, 1.0) = 0.2;
// Slow wander of material edges (height-map noise at 2.3 m and 9.7 m), so a boundary meanders like a real one.
uniform float blend_noise : hint_range(0.0, 1.0) = 0.8;
// Distance ladder: the first step starts at ladder_start metres; each step is x4 the distance and x4 the tile.
// Past ladder_far_start (in steps) the material fades to its far colour.
uniform float ladder_start : hint_range(1.0, 200.0) = 32.0;
uniform float ladder_band : hint_range(0.05, 1.0) = 0.6;
uniform float ladder_far_start : hint_range(1.0, 6.0) = 3.0;
// Specular occlusion from the maps' AO, and the horizon fade that stops normal-mapped reflections pointing into
// the ground (Marmoset / Activision).
uniform float spec_occlusion : hint_range(0.0, 1.0) = 0.8;

// Diagnostic output. 0 = normal shading.
//   1 = total vertex weight   2 = dominant material index   3 = biplanar weights (major red, median green)
//   4 = geometric normal      5 = flat white                6 = blend (t of the top two, height)
//   7 = ladder step (blue = near, red = far colour)
uniform int debug_view : hint_range(0, 7) = 0;
// Kept so older materials / the terrain lab that still set them don't error; no longer used.
// Planet-wide feature map (stage 4b), equirectangular on the planet's own directions: R = "fresh" (bright, unweathered
// ejecta and rays of young craters, CraterField / craters.glsl). Space weathering darkens and reddens exposed regolith
// over time; fresh ejecta has not had that time, so it reads brighter and greyer from orbit down to the ground.
uniform sampler2D feature_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool has_features = false;
uniform vec3 planet_center = vec3(0.0);
uniform mat3 planet_basis_inv = mat3(1.0);
uniform float feature_texel_m = 30.0;
uniform float ray_strength : hint_range(0.0, 1.0) = 0.0;
uniform float ray_brighten = 0.55;
// Fine layering inside the rock beds (laminae, partings), per pixel from the true radius: the beds themselves come from
// the voxel materials, which at LOD 1-2 cannot hold anything under a few metres. Cliff, bedrock and strata slots.
uniform float strata_lamination : hint_range(0.0, 1.0) = 0.0;
// The beds themselves on exposed cliff rock (slot 11 -> hard beds in the strata scan, slot 13): exactly
// PlanetGraphGenerator.strata_params / _strata, so they meet the ledges and what a dig exposes. 0 period = off.
uniform float strata_period = 0.0;      // metres per hard + soft cycle
uniform float strata_base = 0.0;        // radius (m) where t = 0
uniform float strata_phase = 0.0;
uniform float strata_wob_ratio = 0.381966;
uniform float strata_wob_amp = 0.1458;
uniform float strata_hard_share = 0.34;
uniform float triplanar_sharpness = 6.0;
uniform int antitile = 1;
uniform float antitile_scale = 0.37;

varying flat vec4 v_indices;
varying vec4 v_weights;
varying vec3 v_world_pos;
// World position split into a small block-relative part and the block's origin: the planet is 20 km across, so a
// raw world position near 20000 has ~2 mm precision, which as a UV becomes 'barcode' streaks. Kept apart, exact.
varying vec3 v_rel_pos;
varying flat vec3 v_origin;
varying vec3 v_world_normal;

vec4 decode_8bit_vec4(float v) {
	uint i = floatBitsToUint(v);
	return vec4(float(i & uint(0xff)), float((i >> uint(8)) & uint(0xff)),
		float((i >> uint(16)) & uint(0xff)), float((i >> uint(24)) & uint(0xff)));
}

void vertex() {
	v_indices = decode_8bit_vec4(CUSTOM1.x);
	v_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_rel_pos = mat3(MODEL_MATRIX) * VERTEX;
	v_origin = MODEL_MATRIX[3].xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_n(vec4 n) {
	vec2 xy = n.rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// The two projections the surface faces most. a = (normal axis, u axis, v axis), cyclic so u x v = +normal axis.
struct Biplanar {
	ivec3 ma;
	ivec3 me;
	vec2 w;      // weights of major and median projection (sum 1)
	vec2 sgn;    // sign of the normal along each projection's axis (back-facing projections are mirrored back)
};

Biplanar biplanar(vec3 n, float k) {
	vec3 an = abs(n);
	Biplanar b;
	b.ma = (an.x > an.y && an.x > an.z) ? ivec3(0, 1, 2) : (an.y > an.z) ? ivec3(1, 2, 0) : ivec3(2, 0, 1);
	ivec3 mi = (an.x < an.y && an.x < an.z) ? ivec3(0, 1, 2) : (an.y < an.z) ? ivec3(1, 2, 0) : ivec3(2, 0, 1);
	b.me = ivec3(3) - mi - b.ma;
	vec2 w = vec2(an[b.ma.x], an[b.me.x]);
	// IQ's remap: the minor plane's share is zero at the cube diagonal (0.5773), so dropping it leaves no seam
	w = clamp((w - 0.5773) / (1.0 - 0.5773), 0.0, 1.0);
	w = pow(w, vec2(k / 8.0));
	b.w = w / max(w.x + w.y, 1e-5);
	b.sgn = vec2(n[b.ma.x] < 0.0 ? -1.0 : 1.0, n[b.me.x] < 0.0 ? -1.0 : 1.0);
	return b;
}

// One projection of one layer at uv scale `s`: albedo+rough, world normal (whiteout), occlusion+height.
void sample_plane(int layer, ivec3 a, float sgn, vec3 p, vec3 dpx, vec3 dpy, float s, vec3 wn,
		out vec4 alb, out vec3 nw, out vec2 oh) {
	vec2 uv = vec2(p[a.y] * sgn, p[a.z]) * s;
	vec2 gx = vec2(dpx[a.y] * sgn, dpx[a.z]) * s;
	vec2 gy = vec2(dpy[a.y] * sgn, dpy[a.z]) * s;
	alb = textureGrad(tex_albedo, vec3(uv, float(layer)), gx, gy);
	vec4 nm = textureGrad(tex_normal, vec3(uv, float(layer)), gx, gy);
	vec3 tn = unpack_n(nm);
	tn.x *= sgn;                                   // mirrored u on the back-facing side
	vec3 w = vec3(0.0);
	w[a.y] = tn.x + wn[a.y];
	w[a.z] = tn.y + wn[a.z];
	w[a.x] = abs(tn.z) * wn[a.x];
	nw = w;
	oh = nm.ba;
}

// --- contraction cracks (stage 4b): Voronoi polygons on flat ground (mud, permafrost, sulfur crust) ---------------
// Periodic hash: cell indices wrap every `per` cells, so a pattern computed from block-relative coordinates (origin
// reduced modulo per * cell) joins exactly across blocks.
vec2 crack_hash(vec2 c, float per) {
	c = mod(c, per);
	vec3 q = fract(vec3(c.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

// Distance to the nearest polygon edge in cell units (IQ's exact Voronoi border distance, 3x3 second pass), and the
// direction pointing away from that edge into the polygon (xy of the result: .x = distance, .yz = direction).
vec3 crack_edge(vec2 x, float per) {
	vec2 n = floor(x);
	vec2 f = x - n;
	vec2 mr = vec2(0.0);
	vec2 mg = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + crack_hash(n + g, per) * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; }
		}
	}
	md = 8.0;
	vec2 away = vec2(0.0, 1.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + crack_hash(n + g, per) * 0.8 + 0.1 - f;
			vec2 dd = r - mr;
			if (dot(dd, dd) > 1e-5) {
				vec2 nd = normalize(dd);
				float d = dot(0.5 * (mr + r), nd);
				if (d < md) { md = d; away = -nd; }
			}
		}
	}
	return vec3(md, away);
}

// Smooth value noise on the same periodic lattice (for the crack width wandering along a crack).
float crack_vnoise(vec2 x, float per) {
	vec2 i = floor(x);
	vec2 f = x - i;
	f = f * f * (3.0 - 2.0 * f);
	float a = crack_hash(i, per).x;
	float b = crack_hash(i + vec2(1.0, 0.0), per).x;
	float c = crack_hash(i + vec2(0.0, 1.0), per).x;
	float d = crack_hash(i + vec2(1.0, 1.0), per).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Cracks for polygons of `cell` metres at a block-relative position. Returns x = trough (0..1, V-shaped), y = rim
// (the lighter lip either side), and in `tilt` a world-space vector to add to the normal: the trough's walls lean
// toward its line, so the light shades the depression instead of the crack reading as a painted line. Trough width
// grows with the polygon (mud ~2 cm, permafrost troughs ~0.8 m) and wanders 50-150% along each crack.
vec2 cracks_at(vec3 rel, vec3 origin, float cell, Biplanar b, float px_m, out vec3 tilt) {
	const float PER = 64.0;
	vec3 pc = (rel + mod(origin, cell * PER)) / cell;
	vec2 q = vec2(pc[b.ma.y], pc[b.ma.z]);
	vec3 e = crack_edge(q, PER);
	// the pixel's ground size is passed in: derivatives inside the branch that calls this would be undefined
	float aa = max(px_m / cell, 1e-4);
	float w = clamp(0.02 + cell * 0.005, 0.02, 0.07) * (0.5 + crack_vnoise(q * 1.7, PER * 1.7));
	float t = clamp(1.0 - e.x / (w + aa), 0.0, 1.0);
	float trough = t * t * (3.0 - 2.0 * t);
	float rim = smoothstep(w, w + 0.02 + aa, e.x) * (1.0 - smoothstep(w + 0.03, w + 0.08 + aa, e.x));
	// wall slope: the trough profile's derivative across the crack, toward the crack line (in the major plane)
	float wall = 6.0 * t * (1.0 - t);
	tilt = vec3(0.0);
	tilt[b.ma.y] = -e.y * wall * 0.25;
	tilt[b.ma.z] = -e.z * wall * 0.25;
	return vec2(trough, rim);
}

// One layer at one scale, both projections blended.
void sample_layer(int layer, Biplanar b, vec3 p, vec3 dpx, vec3 dpy, float s, vec3 wn,
		out vec4 alb, out vec3 nw, out vec2 oh) {
	vec4 a0; vec3 n0; vec2 o0;
	sample_plane(layer, b.ma, b.sgn.x, p, dpx, dpy, s, wn, a0, n0, o0);
	if (b.w.y < 0.01) {
		alb = a0; nw = normalize(n0); oh = o0;
		return;
	}
	vec4 a1; vec3 n1; vec2 o1;
	sample_plane(layer, b.me, b.sgn.y, p, dpx, dpy, s, wn, a1, n1, o1);
	alb = a0 * b.w.x + a1 * b.w.y;
	nw = normalize(n0 * b.w.x + n1 * b.w.y);
	oh = o0 * b.w.x + o1 * b.w.y;
}

void fragment() {
	vec4 wv = v_weights;
	float wsum = wv.x + wv.y + wv.z + wv.w;
	wv = wsum > 0.0001 ? wv / wsum : vec4(1.0, 0.0, 0.0, 0.0);
	float ws[4] = float[](wv.x, wv.y, wv.z, wv.w);
	int ids[4] = int[](int(v_indices.x), int(v_indices.y), int(v_indices.z), int(v_indices.w));

	// Projection normal: the smoothed vertex normal AND the true face normal must agree (the face normal vetoes a
	// bad vertex normal on steep cut walls / LOD seams, which otherwise projects along the wall into streaks).
	vec3 face_n = normalize(cross(dFdx(v_rel_pos), dFdy(v_rel_pos)) + vec3(1e-6));
	vec3 wn = normalize(v_world_normal);
	vec3 proj_n = (dot(face_n, wn) < 0.0) ? -face_n : face_n;
	proj_n = normalize(mix(proj_n, wn, 0.35));
	Biplanar bp = biplanar(proj_n, biplanar_sharpness);

	vec3 dpx = dFdx(v_rel_pos);
	vec3 dpy = dFdy(v_rel_pos);
	float dist = length(VERTEX);
	float px_m = max(length(fwidth(v_rel_pos)), 1e-4);              // ground metres under one pixel

	// distance ladder position: step 0 below ladder_start, then one step per x4 in distance
	float lad = max(log2(max(dist, 0.01) / ladder_start) * 0.5 + 1.0, 0.0);   // log4(d / start) + 1
	float step0 = floor(lad);
	float frac_s = lad - step0;
	float band_t = smoothstep(1.0 - ladder_band, 1.0, frac_s);              // cross-fade over the end of a step
	float far_t = smoothstep(ladder_far_start - 0.5, ladder_far_start + 0.5, lad);

	// slow noise for edge wander and macro drift: the albedo array itself, sampled huge, triplanar-ish via biplanar
	vec3 mp = v_rel_pos / macro_scale + mod(v_origin, macro_scale) / macro_scale;
	vec2 muv = vec2(mp[bp.ma.y], mp[bp.ma.z]);
	float macro = texture(tex_albedo, vec3(muv, float(ids[0]))).r;
	vec3 np = v_rel_pos / 9.7 + mod(v_origin, 9.7) / 9.7;
	float wander = texture(tex_normal, vec3(np[bp.ma.y], np[bp.ma.z], float(ids[0]))).a;
	// slow field for the anti-tiling blend below (a height map read at ~60x its tile, so it varies over tens of metres)
	float tile_mix = smoothstep(0.3, 0.7, texture(tex_normal, vec3(muv * 2.3 + 0.37, float(ids[0]))).a);
	float antitile_t = smoothstep(0.3, 0.8, lad);                           // from ~16 m out

	// --- layers -------------------------------------------------------------------------------------------------
	vec4 L_alb[4];
	vec3 L_n[4];
	vec2 L_oh[4];
	float L_h[4];
	float hmax = -10.0;
	for (int k = 0; k < 4; k++) {
		L_alb[k] = vec4(0.0); L_n[k] = wn; L_oh[k] = vec2(1.0, 0.0); L_h[k] = -10.0;
		if (ws[k] < 0.02) {
			continue;
		}
		int id = ids[k];
		vec4 ex = pal_extra[id];
		vec4 gr = pal_grade[id];
		float ts = max(ex.w, 0.01);
		float s0 = 1.0 / (ts * pow(4.0, step0));                                  // uv per metre at this step
		vec3 p = v_rel_pos + mod(v_origin, ts * pow(4.0, step0 + 1.0));      // precision: origin reduced per scale
		vec4 alb; vec3 nw; vec2 oh;
		if (far_t < 0.999 || pal_far[id].a < 0.5) {
			sample_layer(id, bp, p, dpx, dpy, s0, wn, alb, nw, oh);
			if (band_t > 0.01) {
				vec4 alb2; vec3 nw2; vec2 oh2;
				sample_layer(id, bp, p, dpx, dpy, s0 * 0.25, wn, alb2, nw2, oh2);
				alb = mix(alb, alb2, band_t);
				nw = normalize(mix(nw, nw2, band_t));
				oh = mix(oh, oh2, band_t);
			}
			// anti-tiling: a second read at 5/4 the frequency (both periods divide this step's precision period, so no
			// block seams) blended by a slow field. Two lattices at a 5:4 ratio only repeat every 4 tiles, and the blend
			// wanders, so the regular dot grid of a single repeating scan is gone; the mean colour is unchanged.
			if (antitile != 0 && antitile_t > 0.01) {
				vec4 alb3; vec3 nw3; vec2 oh3;
				sample_layer(id, bp, p + vec3(0.37, 0.61, 0.13) * ts * pow(4.0, step0), dpx, dpy, s0 * 1.25, wn,
					alb3, nw3, oh3);
				float m3 = mix(0.2, 0.8, tile_mix) * antitile_t;
				alb = mix(alb, alb3, m3);
				nw = normalize(mix(nw, nw3, m3));
				oh = mix(oh, oh3, m3);
			}
		} else {
			alb = vec4(0.18, 0.18, 0.18, 0.9); nw = wn; oh = vec2(1.0, 0.5);
		}
		// far colour: the material's real average, so distant ground keeps its true colour without any texture
		if (pal_far[id].a > 0.5 && far_t > 0.001) {
			vec3 far_c = pal_far[id].rgb / max(pal_tint_rough[id].rgb, vec3(0.01));   // tint is applied below
			alb.rgb = mix(alb.rgb, far_c, far_t);
			nw = normalize(mix(nw, wn, far_t));
		}
		// grade: saturation around the layer's own luminance
		float lum = dot(alb.rgb, vec3(0.299, 0.587, 0.114));
		alb.rgb = mix(vec3(lum), alb.rgb, 1.0 + gr.x);
		// beds on exposed cliff rock: inside a hard bed the face is the strata rock (its own scan and tint)
		if (strata_period > 0.0 && id == 11) {
			float rr = length(v_world_pos - planet_center);
			float t = (rr - strata_base) / strata_period;
			t += strata_wob_amp * sin(6.2831853 * strata_wob_ratio * t + strata_phase);
			float fr = fract(t);
			float bed = floor(t);
			// every bed its own: hard-bed share 60-140% of the mean, its own tone (+-12%)
			float hb = fract(sin(bed * 12.9898) * 43758.5453);
			float hb2 = fract(sin(bed * 78.233 + 1.7) * 24634.6345);
			float share = strata_hard_share * (0.6 + 0.8 * hb);
			float soft_edge = max(px_m / strata_period, 0.004);             // at least a pixel wide: no stair-stepping
			float hard = smoothstep(0.0, 0.05 + soft_edge, fr)
				* (1.0 - smoothstep(share - 0.05 - soft_edge, share + 0.03 + soft_edge, fr));
			alb.rgb *= mix(1.0, 0.88 + 0.24 * hb2, 1.0 - hard);              // soft beds vary in tone too
			if (hard > 0.01) {
				vec4 ex13 = pal_extra[13];
				float ts13 = max(ex13.w, 0.01);
				vec3 p13 = v_rel_pos + mod(v_origin, ts13 * pow(4.0, step0 + 1.0));
				vec4 a13; vec3 n13; vec2 o13;
				sample_layer(13, bp, p13, dpx, dpy, 1.0 / (ts13 * pow(4.0, step0)), wn, a13, n13, o13);
				if (pal_far[13].a > 0.5 && far_t > 0.001) {
					a13.rgb = mix(a13.rgb, pal_far[13].rgb / max(pal_tint_rough[13].rgb, vec3(0.01)), far_t);
				}
				float l13 = dot(a13.rgb, vec3(0.299, 0.587, 0.114));
				a13.rgb = mix(vec3(l13), a13.rgb, 1.0 + pal_grade[13].x);
				// this layer is tinted with slot 11's tint later: carry slot 13's tint over as a ratio
				a13.rgb *= pal_tint_rough[13].rgb / max(pal_tint_rough[11].rgb, vec3(0.01));
				a13.rgb *= 0.88 + 0.24 * fract(hb2 * 7.31);
				alb = mix(alb, a13, hard);
				nw = normalize(mix(nw, n13, hard));
				oh = mix(oh, o13, hard);
			}
		}
		// laminae in rock: thin beds of slightly different tone and dark partings, level on the planet's radius
		if (strata_lamination > 0.0 && (id == 11 || id == 12 || id == 13)) {
			float lfade = (1.0 - smoothstep(0.12, 0.45, px_m)) * strata_lamination;
			if (lfade > 0.01) {
				float r = length(v_world_pos - planet_center) + (wander - 0.5) * 0.6;
				float lam = sin(r * 6.2831853 / 0.9 + 2.0 * sin(r * 6.2831853 / 3.7));
				float part = 1.0 - smoothstep(0.0, 0.06, abs(fract(r / 2.3) - 0.5) - 0.44);   // thin parting every 2.3 m
				alb.rgb *= 1.0 + lfade * (0.12 * lam - 0.25 * (1.0 - part));
			}
		}
		// contraction cracks on this slot's ground, near only (the polygons are under a pixel past ~40 cells)
		if (gr.w > 0.0) {
			float cfade = (1.0 - smoothstep(gr.w * 25.0, gr.w * 45.0, dist)) * (1.0 - smoothstep(90.0, 160.0, dist));
			if (cfade > 0.01) {
				vec3 ctilt;
				vec2 cr = cracks_at(v_rel_pos, v_origin, gr.w, bp, px_m, ctilt) * cfade;
				nw = normalize(nw + ctilt * cfade);
				alb.rgb *= (1.0 - 0.4 * cr.x) * (1.0 + 0.08 * cr.y);
				alb.a = mix(alb.a, 1.0, cr.x);
				oh.x *= 1.0 - 0.6 * cr.x;
				oh.y += 0.1 * cr.y - 0.35 * cr.x;   // trough low, rim a little high: drives the layers' height blend
			}
		}
		// normal strength per material
		nw = normalize(mix(wn, nw, ex.x));
		L_alb[k] = alb;
		L_n[k] = nw;
		L_oh[k] = oh;
		// height for the blend: the map's height (scaled, offset), plus the vertex weight, plus a slow wander that
		// pushes the strongest layer's edge in and out
		float wob = (k == 0 ? 1.0 : -1.0) * (wander - 0.5) * blend_noise * 0.6;
		L_h[k] = (oh.y * (1.0 + gr.y) + gr.z) * height_blend + ws[k] + wob;
		hmax = max(hmax, L_h[k]);
	}

	// --- height blend (max-minus-transition, weighted by the vertex weights) --------------------------------------
	float bw[4];
	float bsum = 0.0;
	for (int k = 0; k < 4; k++) {
		bw[k] = (L_h[k] > -5.0) ? max(L_h[k] - hmax + blend_edge, 0.0) * ws[k] : 0.0;
		bsum += bw[k];
	}
	vec4 alb_r = vec4(0.0);
	vec3 n_mat = vec3(0.0);
	float occ = 0.0;
	vec3 tint = vec3(0.0);
	float rough_scale = 0.0;
	float metallic = 0.0;
	float specular = 0.0;
	int dom = 0;
	for (int k = 0; k < 4; k++) {
		float b = bw[k] / max(bsum, 1e-5);
		if (b <= 0.0) {
			continue;
		}
		if (b > bw[dom] / max(bsum, 1e-5)) { dom = k; }
		int id = ids[k];
		alb_r += L_alb[k] * b;
		n_mat += L_n[k] * b;
		occ += L_oh[k].x * b;
		tint += pal_tint_rough[id].rgb * b;
		rough_scale += pal_tint_rough[id].a * b;
		metallic += pal_extra[id].y * b;
		specular += pal_extra[id].z * b;
	}
	n_mat = normalize(n_mat + wn * 1e-4);

	// --- planet features: crater ejecta and rays (brighter, less weathered) ------------------------------------------
	float fresh = 0.0;
	if (has_features && ray_strength > 0.0) {
		vec3 dir = normalize(planet_basis_inv * (v_world_pos - planet_center));
		// SphereUV: godot_voxel's heightmap projection (u mirrored, v by skew3), sampled at pixel corners like the node
		vec2 fuv = vec2(0.5 - atan(dir.z, dir.x) * 0.15915494, 0.5 - 0.25 * (dir.y * dir.y * dir.y + dir.y));
		fuv += 0.5 / vec2(textureSize(feature_map, 0));
		// mip from the ground a pixel covers (px_m: block-relative, continuous across the map's seam)
		fresh = textureLod(feature_map, fuv, max(log2(px_m / feature_texel_m), 0.0)).r * ray_strength;
		float lum0 = dot(alb_r.rgb, vec3(0.299, 0.587, 0.114));
		alb_r.rgb = mix(alb_r.rgb, vec3(lum0), fresh * 0.35) * (1.0 + ray_brighten * fresh);
	}
	float macro_mul = mix(1.0 - macro_strength * 0.5, 1.0 + macro_strength * 0.5, macro);

	if (debug_view != 0) {
		vec3 dbg = vec3(1.0);
		if (debug_view == 1) { dbg = vec3(clamp(wsum, 0.0, 1.0)); }
		else if (debug_view == 2) { float fi = float(ids[dom]); dbg = vec3(fract(fi * 0.37), fract(fi * 0.61 + 0.3), fract(fi * 0.13 + 0.7)); }
		else if (debug_view == 3) { dbg = vec3(bp.w.x, bp.w.y, 0.0); }
		else if (debug_view == 4) { dbg = v_world_normal * 0.5 + 0.5; }
		else if (debug_view == 6) { dbg = vec3(bw[0] / max(bsum, 1e-5), bw[1] / max(bsum, 1e-5), L_oh[0].y); }
		else if (debug_view == 5) { dbg = vec3(fresh); }
		else if (debug_view == 7) { dbg = vec3(far_t, frac_s * 0.5, 1.0 - min(lad / 4.0, 1.0)); }
		ALBEDO = dbg;
		ROUGHNESS = 1.0; METALLIC = 0.0; SPECULAR = 0.0; AO = 1.0;
		NORMAL = normalize((VIEW_MATRIX * vec4(v_world_normal, 0.0)).xyz);
	} else {
		ALBEDO = alb_r.rgb * tint * macro_mul;
		ROUGHNESS = clamp(alb_r.a * rough_scale, 0.04, 1.0);
		float lum = dot(alb_r.rgb, vec3(0.299, 0.587, 0.114));
		METALLIC = metallic * smoothstep(0.42, 0.72, lum);         // metal ores: only the bright grains are metal
		vec3 n_view = normalize((VIEW_MATRIX * vec4(n_mat, 0.0)).xyz);
		vec3 g_view = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		vec3 r = reflect(-VIEW, g_view);
		float horizon = clamp(1.0 + 1.3 * dot(n_view, r), 0.0, 1.0);
		SPECULAR = specular * horizon * horizon * mix(1.0, occ, spec_occlusion);
		AO = occ;
		AO_LIGHT_AFFECT = 0.5;
		NORMAL = n_view;
	}
}

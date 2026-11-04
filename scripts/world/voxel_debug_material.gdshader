shader_type spatial;
// Back-face culling ON. cull_disabled also drew the inside of the surface, and
// Transvoxel's LOD transition cells produce thin near-coincident slivers whose
// back faces then z-fight with their own front faces - visible as dark edges
// outlining cells that flicker as the camera moves.
render_mode depth_draw_opaque;

// Terrain surface.
//
// Reads the FOUR per-vertex material indices + blend weights the Transvoxel
// mesher bakes into CUSTOM1 when texturing_mode is TEXTURES_MIXEL4_S4, and
// blends them. The previous TEXTURES_SINGLE_S4 path carried one index per cell,
// so every material boundary was a hard cell-shaped square. Indices stay `flat`
// (they are per-cell identities; interpolating them is meaningless); the WEIGHTS
// interpolate, and that is what softens the seam.
//
// Look is driven ENTIRELY by the palette uniforms below, which the owning Planet
// uploads from its own biomes and ores. There is no per-material branch in this
// shader any more - see surface_palette.gd for why that mattered.

// rgb = albedo, a = roughness.
uniform vec4 pal_albedo_rough[16];
// bump strength, bump scale (m), fracture strength, dust albedo gain.
uniform vec4 pal_relief[16];
// cavity strength, metallic, specular, spare.
uniform vec4 pal_extra[16];

uniform float macro_scale : hint_range(4.0, 400.0) = 90.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.45;
uniform float tint_scale : hint_range(4.0, 600.0) = 210.0;
uniform float tint_strength : hint_range(0.0, 1.0) = 0.5;
// How strongly dust collects in hollows. This is the difference between a
// surface that looks DEPOSITED and one that looks painted.
uniform float curvature_strength : hint_range(0.0, 3.0) = 1.5;
uniform float strata_strength : hint_range(0.0, 1.0) = 0.30;
uniform float strata_period : hint_range(0.2, 20.0) = 3.5;
uniform float dust_slope_threshold : hint_range(0.0, 1.0) = 0.62;

varying flat vec4 v_indices;
varying vec4 v_weights;
varying vec3 v_world_pos;
// LOCAL position, i.e. relative to the body's own centre. Normalising it gives
// radial up for free, correct per body, with no uniform to set - which matters
// because one material instance serves a whole planet and a "centre" uniform
// would be wrong for every other body.
varying vec3 v_local_pos;
varying vec3 v_world_normal;

vec4 decode_8bit_vec4(float v) {
	uint i = floatBitsToUint(v);
	return vec4(
		float(i & uint(0xff)),
		float((i >> uint(8)) & uint(0xff)),
		float((i >> uint(16)) & uint(0xff)),
		float((i >> uint(24)) & uint(0xff)));
}

void vertex() {
	v_indices = decode_8bit_vec4(CUSTOM1.x);
	v_weights = decode_8bit_vec4(CUSTOM1.y) / 255.0;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_pos = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Integer bit-mixing hash on the lattice cell, NOT a float product.
//
// The previous hash was `fract(p.x*p.y*p.z*(p.x+p.y+p.z))` on world coordinates.
// At planetary magnitudes that product reaches ~2.5e5, where float32's 24-bit
// mantissa has a ULP around 0.03 - so `fract` could only return ~30 distinct
// values, in a structured rather than random pattern. That is a moire generator,
// not noise. Integer mixing has no magnitude-dependent precision loss at all.
uint hash_cell(uvec3 p) {
	p *= uvec3(uint(374761393), uint(668265263), uint(1274126177));
	uint h = p.x ^ p.y ^ p.z;
	h *= uint(1274126177);
	return h ^ (h >> uint(15));
}

float hash13(vec3 cell) {
	uvec3 c = uvec3(ivec3(floor(cell)) + ivec3(4096));
	return float(hash_cell(c) & uint(0xffffff)) / float(0xffffff);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	// Quintic rather than cubic smoothstep: its SECOND derivative is also zero
	// at the cell edges, so the derivative-based normals below stay continuous.
	// With cubic interpolation the normal has a visible crease on every lattice
	// boundary - a faint grid over the whole surface.
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

const mat3 OCTAVE_ROT = mat3(
	vec3(0.00, 0.80, 0.60),
	vec3(-0.80, 0.36, -0.48),
	vec3(-0.60, -0.48, 0.64));

// `active_octaves` fades the finest layers out as the pixel footprint grows -
// procedural noise has no mipmaps, so sub-pixel octaves alias into crawling
// fizz. The fractional part fades the last octave in rather than popping it.
float fbm(vec3 p, float active_octaves) {
	float sum = 0.0;
	float norm = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 6; i++) {
		float k = clamp(active_octaves - float(i), 0.0, 1.0);
		if (k <= 0.0) {
			break;
		}
		sum += value_noise(p) * amp * k;
		norm += amp * k;
		p = OCTAVE_ROT * p * 2.0;
		amp *= 0.5;
	}
	return norm > 0.0001 ? sum / norm : 0.5;
}

void fragment() {
	// Renormalize: the generator quantizes weights to 4 bits, so rounding can
	// leave the four slots summing slightly off 1.0.
	vec4 w = v_weights;
	float wsum = w.x + w.y + w.z + w.w;
	w = wsum > 0.0001 ? w / wsum : vec4(1.0, 0.0, 0.0, 0.0);

	int i0 = int(v_indices.x);
	int i1 = int(v_indices.y);
	int i2 = int(v_indices.z);
	int i3 = int(v_indices.w);

	vec4 ar = pal_albedo_rough[i0] * w.x + pal_albedo_rough[i1] * w.y
		+ pal_albedo_rough[i2] * w.z + pal_albedo_rough[i3] * w.w;
	vec4 rel = pal_relief[i0] * w.x + pal_relief[i1] * w.y
		+ pal_relief[i2] * w.z + pal_relief[i3] * w.w;
	vec4 ext = pal_extra[i0] * w.x + pal_extra[i1] * w.y
		+ pal_extra[i2] * w.z + pal_extra[i3] * w.w;

	float bump_strength = rel.x;
	float bump_scale = max(rel.y, 0.02);
	float fracture_strength = rel.z;
	float dust_gain = rel.w;
	float cavity_strength = ext.x;
	float metallic = ext.y;
	float specular = ext.z;
	float dust_resistance = ext.w;

	// --- pixel footprint, the basis for every level-of-detail decision -----
	vec3 dpdx = dFdx(v_world_pos);
	vec3 dpdy = dFdy(v_world_pos);
	// The world-space width of one pixel. Everything below fades against this
	// rather than against camera distance: distance ignores view angle, and
	// ground seen at a grazing angle has a huge footprint while still being
	// close. Fading on distance alone left speckle along every horizon.
	float pixel_world = max(max(length(dpdx), length(dpdy)), 0.00001);

	// Octaves still worth evaluating.
	//
	// Octave i has feature size bump_scale / 2^i, and is worth sampling only
	// while that stays above about two pixels. Solving for i:
	//
	//     bump_scale / 2^i > 2 * pixel_world   ->   i < log2(bump_scale / (2 * pixel))
	//
	// The previous form computed `6.0 - log2(max(2*pixel/bump_scale, 1.0))`,
	// which is the same expression with the ratio INVERTED and then clamped at
	// 1 - so whenever features were near pixel size the log clamped to zero and
	// it evaluated all six octaves anyway, down to centimetre detail on a
	// decimetre pixel. That is the stipple that covered every mid-distance
	// slope, and it survived every other aliasing fix because those were all
	// treating the symptom.
	float resolvable = log2(max(bump_scale / (2.0 * pixel_world), 1.0));
	float active_octaves = clamp(resolvable, 1.0, 6.0);

	vec3 up = normalize(v_local_pos);
	vec3 world_up = normalize((MODEL_MATRIX * vec4(up, 0.0)).xyz);
	float flatness = clamp(dot(v_world_normal, world_up), 0.0, 1.0);

	// --- surface relief ----------------------------------------------------
	// One height field feeds the normal, the cavity term, the deposition term
	// and the albedo mottling, so all four agree about where the bumps are.
	// Separate fields would light, shade, deposit and colour different geometry.
	vec3 p = v_world_pos / bump_scale;
	float h = fbm(p, active_octaves);
	// Kept before creases and strata are cut into it. Albedo uses THIS.
	//
	// Feeding the creased field to both the normal and the albedo darkened every
	// crease twice - once as shading, once as paint - which is what made the
	// surface read as splotchy cave wall rather than as lit rock. Relief belongs
	// in the normal; the albedo should only carry actual colour variation.
	float h_albedo = h;

	// A deliberately coarser sample of the SAME field. Their difference is a
	// curvature proxy: positive on convex crests, negative inside hollows.
	float h_coarse = fbm(p * 0.25, min(active_octaves, 3.0));
	float curvature = h - h_coarse;

	// --- deposition: where loose material ends up --------------------------
	// Computed here, before the crease/strata/normal work below, because both
	// of those now need to know how much dust sits on this fragment: dust
	// smooths the relief it covers and it hides strata (the rock underneath
	// is what is banded, not the dust sheet on top of it).
	//
	// Dust settles on flats AND in hollows, and sheds from steep faces and
	// crests. Driving it off curvature as well as slope is what stops the
	// dust/rock split from reading as a single contour line at one slope
	// angle. `dust_resistance` is per-material (bedrock/cliff/construction
	// block resist regardless of local slope; loose regolith does not), and
	// the h_coarse jitter breaks the boundary into an organic, uneven edge
	// instead of a clean iso-line - it reuses a field already sampled above,
	// so it costs nothing extra.
	float hollow = clamp(0.5 - curvature * curvature_strength, 0.0, 1.0);
	float dust_input = flatness * (0.55 + hollow * 0.9) * (1.0 - dust_resistance * 0.85);
	float dust = smoothstep(dust_slope_threshold - 0.22, dust_slope_threshold + 0.22,
		dust_input + (h_coarse - 0.5) * 0.22);

	// Fracture creases at two scales, so slabs break into smaller slabs instead
	// of every crack being the same size. Subtracted, so a crease is a groove
	// cut into the surface rather than a ridge standing proud of it.
	float f1 = fbm(p * 0.18, min(active_octaves, 3.0));
	float f2 = fbm(p * 0.55, min(active_octaves, 3.0));
	float crease = max(1.0 - abs(f1 - 0.5) * 6.0, 0.0) * 0.65
		+ max(1.0 - abs(f2 - 0.5) * 8.0, 0.0) * 0.35;
	// A buried crease does not show - the dust sheet fills it in, not just
	// dims it. Without this, fracture lines kept reading straight through a
	// full dust cover.
	h -= crease * fracture_strength * (1.0 - dust * 0.8);

	// Horizontal bedding, along the body's RADIAL axis so strata stay level with
	// the local horizon rather than with an arbitrary world plane. Bedding is
	// exposed by erosion on slopes, not seen on flat ground, and it is a ROCK
	// feature - a dusted-over face should not show it either. The falloff
	// against flatness is a softer power curve than a straight lerp so it stays
	// strong across most of a near-vertical face rather than only right at 90
	// degrees, which is what cliff faces need to actually read as bedded.
	float band = fract(dot(v_local_pos, up) / max(strata_period, 0.01));
	float strata = abs(band * 2.0 - 1.0);
	float strata_mix = strata_strength * pow(clamp(1.0 - flatness, 0.0, 1.0), 0.6) * (1.0 - dust * 0.6);
	h = mix(h, h * 0.55 + strata * 0.45, strata_mix);

	// DOWNSLOPE STREAKING WAS TRIED HERE AND REVERTED. Compressing the sample
	// position along the fall line turned the surface to fine static:
	// `v_world_pos` has magnitude ~8000 here, so a per-pixel variation in the
	// fall line of 1e-4 - which any bumpy mesh normal has - moves the sample by
	// nearly a metre against a 0.4 m feature. Same failure as the old float
	// hash: a computation assuming small coordinates, fed planetary ones.

	// Normal perturbation WITHOUT tangents, from screen-space derivatives of the
	// height field (Mikkelsen). The mesh has no UVs and the noise is procedural,
	// so there is no tangent frame to use - and this costs two hardware
	// derivatives instead of the three extra fbm evaluations hand-differencing
	// would need.
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 n = v_world_normal;
	vec3 grad = dhdx * cross(dpdy, n) + dhdy * cross(n, dpdx);
	// Fade the perturbation out once even the COARSEST octave stops being
	// resolvable. Reducing octave count is not enough on its own: the single
	// surviving octave is still sub-pixel at grazing angles, and perturbing a
	// normal by an unresolved field is how the horizon fills with crawling
	// speckle.
	float bump_vis = clamp(resolvable, 0.0, 1.0);
	// Dust is a settled layer, not a paint tint: it fills and rounds off the
	// small-scale relief it covers instead of leaving the bare-rock bump
	// pattern showing through underneath it. Bare rock (dust == 0) is
	// untouched; a full dust sheet cuts perturbation to less than half.
	float dust_bump_scale = mix(1.0, 0.42, dust);
	vec3 bumped = normalize(n - grad * bump_strength * dust_bump_scale * bump_vis);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);

	// --- albedo ------------------------------------------------------------
	// Three scales with different jobs: macro breaks up planet-wide uniformity,
	// the relief field supplies mid mottling, and the fine grain only exists
	// close enough to be resolved.
	float macro = fbm(v_world_pos / macro_scale, 3.0);
	float grain_fade = clamp(1.0 - pixel_world * 90.0, 0.0, 1.0);
	// Higher frequency and a heavier blend weight than the mid-distance mottle:
	// this is what puts visible granularity in the foreground, where it is
	// resolvable, without touching anything past a few metres (grain_fade is
	// already zero there, so the extra octave costs nothing at range).
	float grain = grain_fade > 0.0 ? fbm(p * 11.0, 3.0) : 0.5;
	float variation = mix(h_albedo, mix(h_albedo, grain, 0.55), grain_fade);

	// Pits see less sky, so they are darker.
	float cavity = mix(1.0 - cavity_strength * 0.6, 1.0, smoothstep(0.2, 0.8, h_albedo));
	// Contact/ambient darkening: concave hollows (same `hollow` term that
	// decides where dust banks up) see less of the sky than a convex crest
	// does, independent of the fine-relief cavity term above - this is what
	// sells depth where two slopes meet, at a scale coarser than individual
	// bumps.
	cavity *= mix(1.0, 1.0 - cavity_strength * 0.35, hollow);

	vec3 albedo = ar.rgb;
	// Slow hue drift, so one material is not a single flat colour across a whole
	// planet - real regolith varies with mineral content and space weathering.
	float tint = fbm(v_world_pos / tint_scale, 2.0);
	albedo *= mix(vec3(0.94, 0.97, 1.06), vec3(1.06, 1.0, 0.94),
		smoothstep(0.35, 0.65, tint)) * tint_strength
		+ vec3(1.0) * (1.0 - tint_strength);
	albedo *= mix(1.0 - macro_strength * 0.7, 1.0 + macro_strength * 0.7, macro);
	albedo = mix(albedo, albedo * (1.0 + dust_gain) * vec3(1.02, 1.0, 0.97), dust);
	// Narrow. Real rock under one sun does not swing 2:1 in local albedo; the
	// wide range was standing in for the relief shading that was missing before
	// normals existed, and now double-counts it.
	albedo *= mix(0.84, 1.16, variation) * cavity;

	ALBEDO = albedo;
	// Dust is finer and scatters more evenly than the rock under it, so it reads
	// slightly smoother - but nothing here goes glossy. A natural mineral
	// surface below ~0.55 roughness looks wet, not polished.
	ROUGHNESS = clamp(ar.a - dust * 0.06 + (variation - 0.5) * 0.10, 0.55, 1.0);
	METALLIC = metallic;
	SPECULAR = specular;
	AO = cavity;
	AO_LIGHT_AFFECT = 1.0;
}

// Full BRDF: Oren-Nayar diffuse + GGX specular.
//
// BOTH halves have to be here. Defining light() at all overrides Godot's ENTIRE
// lighting pipeline for this material, not just the diffuse part - so the first
// version of this function, which only wrote DIFFUSE_LIGHT, silently removed
// every specular highlight in the game. ROUGHNESS was still being set and still
// fed the diffuse term, which made the omission invisible in code review and
// nearly invisible on matte rock; it shows up on ice and crystal, where the
// missing sheen is the whole material.
//
// Diffuse is Oren-Nayar rather than Lambert because Lambert models a SMOOTH
// surface and falls off as cos(theta), which is why untextured terrain reads as
// a shiny sphere with a soft terminator. Dust and rough rock are made of
// self-shadowing microfacets: they stay bright toward grazing angles and the
// terminator is hard. That flat-lit quality is a large part of why lunar
// photography looks the way it does, and no amount of albedo work reproduces it.
// Fujii's approximation is used - the full model needs an acos and a tan per
// pixel.
void light() {
	// Clamped rather than early-returned: Godot rejects `return` inside the
	// light processor function.
	float NdotL = max(dot(NORMAL, LIGHT), 0.0);
	float NdotV = max(dot(NORMAL, VIEW), 0.0);

	// --- Oren-Nayar diffuse ---
	float sigma = clamp(ROUGHNESS, 0.0, 1.0);
	float sigma2 = sigma * sigma;
	float A = 1.0 - 0.5 * sigma2 / (sigma2 + 0.33);
	float B = 0.45 * sigma2 / (sigma2 + 0.09);
	float s = dot(LIGHT, VIEW) - NdotL * NdotV;
	float t = s <= 0.0 ? 1.0 : max(NdotL, NdotV);
	float on = A + B * s / max(t, 0.0001);

	// A metal has no diffuse lobe at all - all of its reflection is specular
	// and tinted by its own colour.
	vec3 diffuse_colour = ALBEDO * (1.0 - METALLIC);
	// No 1/PI. Godot's light() convention already folds it into LIGHT_COLOR, and
	// dividing again made the whole planet read about three times too dark -
	// which looked like an albedo problem and very nearly got "fixed" by
	// brightening the rock, hiding the real cause.
	DIFFUSE_LIGHT += diffuse_colour * LIGHT_COLOR * ATTENUATION * NdotL * on;

	// --- GGX specular ---
	vec3 H = normalize(LIGHT + VIEW);
	float NdotH = max(dot(NORMAL, H), 0.0);
	float VdotH = max(dot(VIEW, H), 0.0);

	float a = max(sigma * sigma, 0.002);
	float a2 = a * a;
	float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
	float D = a2 / max(PI * denom * denom, 0.0001);

	// Smith height-correlated visibility, Schlick-GGX form.
	float k = a * 0.5;
	float Gv = NdotV / max(NdotV * (1.0 - k) + k, 0.0001);
	float Gl = NdotL / max(NdotL * (1.0 - k) + k, 0.0001);
	float G = Gv * Gl;

	// Dielectrics reflect ~4% at normal incidence; a metal reflects its albedo
	// instead.
	//
	// The per-material `specular` value is NOT used here: SPECULAR is a
	// fragment-only output in Godot and cannot be read inside light(). That
	// costs less than it sounds - between two dielectrics it is ROUGHNESS that
	// decides how a highlight reads, and roughness IS per-material. It still
	// feeds Godot's own SPECULAR output in fragment() for anything that samples
	// it (reflection probes, SSR), so the value is not dead.
	vec3 F0 = mix(vec3(0.04), ALBEDO, METALLIC);
	vec3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);

	// The NdotL of the reflectance equation cancels against the denominator's,
	// leaving 1 / (4 * NdotV).
	SPECULAR_LIGHT += D * G * F / (4.0 * max(NdotV, 0.0001)) * LIGHT_COLOR * ATTENUATION;
}

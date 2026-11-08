shader_type spatial;
// Back-face culling ON. cull_disabled also drew the inside of the surface, and
// Transvoxel's LOD transition cells produce thin near-coincident slivers whose
// back faces then z-fight with their own front faces - visible as dark edges
// outlining cells that flicker as the camera moves.
render_mode depth_draw_opaque;

// Terrain surface, textured.
//
// This replaces a fully procedural material that evaluated SEVEN fbm fields per
// fragment, each up to six octaves of eight hash lookups - roughly 300 hash
// operations per pixel. That was simultaneously the frame-rate problem (20-30
// fps near the ground) and the quality ceiling: value noise can make mottling,
// but it cannot make a rock. Real texture data is both cheaper and better, and
// those two facts are the same fact.
//
// Maps are baked by tools/bake_surface_textures.py and packed two-deep:
//     albedo array   RGB = albedo (de-lit), A = roughness
//     normal array   RG  = normal XY,       B = occlusion, A = height
//
// Arrays, not individual textures, because the Transvoxel mesher hands us four
// material INDICES per vertex and the shader must be able to look any of them
// up without a branch per material - the same reason the palette exists.

uniform sampler2DArray tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray tex_normal : hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_enable;

// Per-material tint and response, uploaded by the owning Planet. The texture
// supplies detail; these let one planet's regolith read warmer or darker than
// another's without a second texture set.
uniform vec4 pal_tint_rough[16];   // rgb = albedo tint, a = roughness scale
uniform vec4 pal_extra[16];        // x = normal strength, y = metallic, z = specular, w = tex scale (m per tile)

// Large-scale albedo drift, so a tiled texture does not read as a repeating
// grid across a whole planet. ONE cheap noise field - the thing that was
// expensive before was doing this seven times at six octaves.
uniform float macro_scale : hint_range(4.0, 600.0) = 140.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.30;
// Sharpness of the triplanar axis blend. Higher = tighter seams on the
// dominant axis, lower = wider crossfade.
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;
// How much the two blended materials interlock by height rather than
// cross-fading. A linear crossfade between two rock textures looks like a
// dissolve; letting the taller surface win makes the boundary follow the rock.
uniform float height_blend : hint_range(0.0, 1.0) = 0.65;
// Narrow, noisy material edges (terrain lab 2026-11-08). The generator's weights fade over metres, and a linear
// cross-fade over that width looked smudged. The edge is squeezed into a band of +-blend_edge around the 50/50
// point, and shifted by noise from the two materials' own height maps (2.3 m + 9.7 m), so it wanders like a real boundary.
// blend_edge = 1.0, blend_noise = 0.0 is the old wide fade.
uniform float blend_edge : hint_range(0.02, 1.0) = 0.2;
uniform float blend_noise : hint_range(0.0, 1.0) = 0.8;

// Diagnostic output. 0 = normal shading.
//
// Exists because every artifact in this shader so far has been diagnosed by
// staring at a beauty render and guessing, and most of those guesses were
// wrong. A mode that paints the actual value being questioned answers the
// question directly.
//   1 = total vertex weight   (black = NO material written at this vertex)
//   2 = material index 0      (distinct colour per index)
//   3 = triplanar blend axes  (rgb = x/y/z plane weights)
//   4 = geometric normal
//   5 = flat white            (isolates geometry: holes stay background)
// Anti-tiling. 0 = off. 1 = each material is sampled a second time at a different scale and rotation, and the two
// are mixed by a slow world-space mask, so the repeat of one tile is never visible across a slope (terrain lab
// 2026-11-07: at a 2.5 m tile the repeat read as a grid from 20 m away). Costs a second set of texture fetches.
uniform int antitile : hint_range(0, 1) = 1;
uniform float antitile_scale = 0.37;
uniform int debug_view : hint_range(0, 7) = 0;

varying flat vec4 v_indices;
varying vec4 v_weights;
varying vec3 v_world_pos;
// World position split into a small part relative to the mesh block and the block's own world origin. The planet is
// 20 km across, so a world position near 20000 only has ~2 mm of float precision: used directly as a texture
// coordinate, that quantisation turns steep faces into stretched 'barcode' streaks. Kept apart, both parts stay exact.
varying vec3 v_rel_pos;
varying flat vec3 v_origin;
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
	v_rel_pos = mat3(MODEL_MATRIX) * VERTEX;
	v_origin = MODEL_MATRIX[3].xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// One material sampled triplanar. Returns albedo.rgb / roughness in .a, and
// writes the tangent-space-ish normal, occlusion and height through out params.
//
// Triplanar rather than UVs because a voxel surface has no UV parameterisation
// at all - Transvoxel emits arbitrary polygons from a density field, and there
// is no consistent way to unwrap them. World-space projection is the standard
// answer and has the useful property that edits (digging) produce correctly
// textured new faces with no extra work.
vec4 sample_planes(int layer, vec3 uvw, vec3 blend, out vec4 nrm) {
	vec4 ax = texture(tex_albedo, vec3(uvw.zy, float(layer)));
	vec4 ay = texture(tex_albedo, vec3(uvw.xz, float(layer)));
	vec4 az = texture(tex_albedo, vec3(uvw.xy, float(layer)));
	vec4 nx = texture(tex_normal, vec3(uvw.zy, float(layer)));
	vec4 ny = texture(tex_normal, vec3(uvw.xz, float(layer)));
	vec4 nz = texture(tex_normal, vec3(uvw.xy, float(layer)));
	nrm = nx * blend.x + ny * blend.y + nz * blend.z;
	return ax * blend.x + ay * blend.y + az * blend.z;
}

vec4 sample_material(int layer, vec3 rel, vec3 origin, vec3 blend, float tex_scale, float tile_mix,
		out vec3 nrm_ts, out float occ, out float height) {
	float ts = max(tex_scale, 0.01);
	// (rel + origin) / ts, with the big term reduced mod one tile first (exact: fmod loses nothing).
	vec3 uvw = rel / ts + mod(origin, ts) / ts;
	if (antitile == 1) {
		vec4 n1;
		vec4 a1 = sample_planes(layer, uvw, blend, n1);
		// second sample: bigger tile, rotated ~37 degrees about every axis pair, offset
		float ts2 = ts / antitile_scale;
		vec3 uvw2 = rel / ts2 + mod(origin, ts2) / ts2;
		const float c = 0.7986;
		const float sn = 0.6018;
		uvw2 = vec3(c * uvw2.x - sn * uvw2.z, uvw2.y, sn * uvw2.x + c * uvw2.z) + vec3(0.37, 0.11, 0.73);
		vec4 n2;
		vec4 a2 = sample_planes(layer, uvw2, blend, n2);
		vec4 nrm = mix(n1, n2, tile_mix);
		nrm_ts = vec3(nrm.rg * 2.0 - 1.0, 1.0);
		occ = nrm.b;
		height = nrm.a;
		return mix(a1, a2, tile_mix);
	}
	// Each plane drops the axis it projects along.
	vec2 uv_x = uvw.zy;
	vec2 uv_y = uvw.xz;
	vec2 uv_z = uvw.xy;

	vec4 ax = texture(tex_albedo, vec3(uv_x, float(layer)));
	vec4 ay = texture(tex_albedo, vec3(uv_y, float(layer)));
	vec4 az = texture(tex_albedo, vec3(uv_z, float(layer)));
	vec4 alb = ax * blend.x + ay * blend.y + az * blend.z;

	vec4 nx = texture(tex_normal, vec3(uv_x, float(layer)));
	vec4 ny = texture(tex_normal, vec3(uv_y, float(layer)));
	vec4 nz = texture(tex_normal, vec3(uv_z, float(layer)));
	vec4 nrm = nx * blend.x + ny * blend.y + nz * blend.z;

	nrm_ts = vec3(nrm.rg * 2.0 - 1.0, 1.0);
	occ = nrm.b;
	height = nrm.a;
	return alb;
}

void fragment() {
	// Renormalize: the generator quantizes weights to 4 bits, so rounding can
	// leave the four slots summing slightly off 1.0.
	vec4 w = v_weights;
	float wsum = w.x + w.y + w.z + w.w;
	w = wsum > 0.0001 ? w / wsum : vec4(1.0, 0.0, 0.0, 0.0);

	// Only the TOP TWO materials are sampled.
	//
	// Four layers triplanar would be 24 texture fetches per fragment. Two is 12,
	// and the third and fourth weights are almost always negligible - the mesher
	// sorts them, and a voxel genuinely straddling four materials is rare enough
	// that losing the tail is invisible. This is the single biggest lever on
	// the cost of this shader.
	// The mesher does NOT order the four slots by weight (measured in the terrain lab: a voxel whose only weight was
	// in slot 0 still rendered as slot 1's material), so the two strongest are picked here rather than assumed to be
	// .x and .y. Reading .x/.y blindly showed whichever materials happened to land in the first two slots.
	float ws[4] = float[](w.x, w.y, w.z, w.w);
	float is[4] = float[](v_indices.x, v_indices.y, v_indices.z, v_indices.w);
	int a = 0;
	for (int k = 1; k < 4; k++) {
		if (ws[k] > ws[a]) { a = k; }
	}
	int b = (a == 0) ? 1 : 0;
	for (int k = 0; k < 4; k++) {
		if (k != a && ws[k] > ws[b]) { b = k; }
	}
	int i0 = int(is[a]);
	int i1 = int(is[b]);
	float w0 = ws[a];
	float w1 = ws[b];
	// Re-normalise the pair so dropping the tail does not darken the surface.
	float wsum2 = max(w0 + w1, 0.0001);
	w0 /= wsum2;
	w1 /= wsum2;

	// Triplanar axis weights from the geometric normal.
	// Two normals have to agree before a projection axis gets weight: the smoothed vertex normal AND the true face
	// normal (from screen-space derivatives of the position). Where the mesher hands a steep cut wall or a LOD seam
	// a bad vertex normal (pointing up on what is really a vertical face), the vertex normal alone picks the
	// projection that runs ALONG the wall and the texture smears into 'barcode' streaks. The face normal cannot be
	// wrong about which way the triangle faces, so it vetoes that.
	vec3 face_n = abs(normalize(cross(dFdx(v_rel_pos), dFdy(v_rel_pos)) + vec3(0.000001)));
	vec3 blend_v = pow(abs(v_world_normal), vec3(triplanar_sharpness));
	vec3 blend_f = pow(face_n, vec3(triplanar_sharpness));
	vec3 blend = blend_v * blend_f;
	if (blend.x + blend.y + blend.z < 0.0001) {
		blend = blend_f;
	}
	blend /= max(blend.x + blend.y + blend.z, 0.0001);

	vec4 e0 = pal_extra[i0];
	vec4 e1 = pal_extra[i1];

	vec3 n0;
	vec3 n1;
	float occ0;
	float occ1;
	float h0;
	float h1;
	// slow world-space mask for anti-tiling: the albedo array itself, sampled huge, as a cheap noise
	float tile_mix = 0.0;
	if (antitile == 1) {
		vec3 big = v_rel_pos / 23.0 + mod(v_origin, 23.0) / 23.0;
		float m = texture(tex_albedo, vec3(big.xz * blend.y + big.zy * blend.x + big.xy * blend.z, 0.0)).g;
		m += texture(tex_albedo, vec3(big.xz * 0.31 + 0.5, 1.0)).g;
		tile_mix = smoothstep(0.55, 0.95, m);
	}
	vec4 a0 = sample_material(i0, v_rel_pos, v_origin, blend, e0.w, tile_mix, n0, occ0, h0);
	vec4 a1 = sample_material(i1, v_rel_pos, v_origin, blend, e1.w, tile_mix, n1, occ1, h1);

	// Height-aware blend: the material whose surface stands taller at this point
	// wins the contested band, so a boundary follows cracks and grain instead of
	// fading through a grey average.
	float bias = (h0 * w0 - h1 * w1) * height_blend;
	float d = w1 - w0 - bias;
	if (i0 != i1 && w1 > 0.001) {
		// two octaves of the material's own height map: ~2.3 m grain + ~9.7 m wander, at odd scales and a rotation so
		// neither lines up with the texture tile (a single octave repeated visibly along a straight boundary)
		vec3 nb = v_rel_pos / 2.3 + mod(v_origin, 2.3) / 2.3;
		vec2 p1 = nb.xz * blend.y + nb.zy * blend.x + nb.xy * blend.z;
		p1 = vec2(0.83 * p1.x - 0.56 * p1.y, 0.56 * p1.x + 0.83 * p1.y);
		vec3 nc = v_rel_pos / 9.7 + mod(v_origin, 9.7) / 9.7;
		vec2 p2 = nc.xz * blend.y + nc.zy * blend.x + nc.xy * blend.z;
		float nz = texture(tex_normal, vec3(p1, float(i0))).a + 1.6 * texture(tex_normal, vec3(p2 + 0.31, float(i1))).a;
		d += (nz / 2.6 - 0.5) * blend_noise * 2.0;
	}
	float t = smoothstep(-blend_edge, blend_edge, d);

	vec4 albedo_rough = mix(a0, a1, t);
	vec3 nrm_ts = normalize(mix(n0, n1, t));
	float occ = mix(occ0, occ1, t);

	vec3 tint = mix(pal_tint_rough[i0].rgb, pal_tint_rough[i1].rgb, t);
	float rough_scale = mix(pal_tint_rough[i0].a, pal_tint_rough[i1].a, t);
	float normal_strength = mix(e0.x, e1.x, t);
	float metallic = mix(e0.y, e1.y, t);
	float specular = mix(e0.z, e1.z, t);

	// --- macro variation --------------------------------------------------
	// A single low-frequency sample of the albedo texture itself, at a very
	// different scale, reused as a variation field. Cheaper than a noise
	// function and it already has the right statistics, because it is the same
	// rock.
	float macro = texture(tex_albedo, vec3(v_world_pos.xz / macro_scale, float(i0))).r;
	float macro_mul = mix(1.0 - macro_strength * 0.5, 1.0 + macro_strength * 0.5, macro);

	// Triplanar normals: rotate each plane's tangent normal into world space by
	// swizzling, then blend. Whiteout blending (adding the geometric normal)
	// keeps detail from cancelling on slopes.
	vec3 wn = v_world_normal;
	vec3 n_world = normalize(vec3(
		nrm_ts.z * sign(wn.x) * blend.x + wn.x,
		nrm_ts.y * blend.y + wn.y,
		nrm_ts.x * sign(wn.z) * blend.z + wn.z));
	n_world = normalize(mix(wn, n_world, normal_strength));

	if (debug_view != 0) {
		vec3 dbg = vec3(0.0);
		if (debug_view == 1) {
			// Raw, pre-normalisation weight sum. If this is black the mesher
			// received no material at all for this vertex.
			dbg = vec3(clamp(wsum, 0.0, 1.0));
		} else if (debug_view == 2) {
			float fi = float(i0);
			dbg = vec3(fract(fi * 0.37), fract(fi * 0.61 + 0.3), fract(fi * 0.13 + 0.7));
		} else if (debug_view == 3) {
			dbg = blend;
		} else if (debug_view == 6) {
				dbg = vec3(t, w1, h0);
			} else if (debug_view == 7) {
				dbg = vec3(a0.r, a1.r, 0.0);
			} else if (debug_view == 4) {
			dbg = v_world_normal * 0.5 + 0.5;
		} else {
			dbg = vec3(1.0);
		}
		ALBEDO = dbg;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		SPECULAR = 0.0;
		AO = 1.0;
		NORMAL = normalize((VIEW_MATRIX * vec4(v_world_normal, 0.0)).xyz);
	} else {
	ALBEDO = albedo_rough.rgb * tint * macro_mul;
	ROUGHNESS = clamp(albedo_rough.a * rough_scale, 0.04, 1.0);
	METALLIC = metallic;
	SPECULAR = specular;
	AO = occ;
	AO_LIGHT_AFFECT = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	}
}

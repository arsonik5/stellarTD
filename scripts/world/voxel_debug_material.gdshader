shader_type spatial;

// Procedural material coloring for Slice 1 (no texture art yet). Reads the
// dominant per-cell material index the Transvoxel mesher bakes into CUSTOM1.x
// when the mesher's texturing_mode is TEXTURES_SINGLE_S4, then breaks up each
// material's flat fill with cheap hash-based noise (two octaves) so terrain
// doesn't read as solid-color plastic, plus a subtle planet-latitude tint.

varying flat vec4 v_indices;
varying vec3 v_world_pos;

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
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Trilinear value noise from the hash above - no texture samples needed.
float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

void fragment() {
	int idx = int(v_indices.x);

	vec3 base_color;
	float base_rough;
	if (idx == 1) {
		base_color = vec3(0.72, 0.38, 0.14); // iron ore
		base_rough = 0.75;
	} else if (idx == 2) {
		base_color = vec3(0.15, 0.55, 0.68); // copper ore
		base_rough = 0.7;
	} else if (idx == 3) {
		base_color = vec3(0.82, 0.8, 0.55); // placed alloy block
		base_rough = 0.5;
	} else if (idx == 4) {
		base_color = vec3(0.92, 0.82, 0.18); // sulfur
		base_rough = 0.85;
	} else if (idx == 5) {
		base_color = vec3(0.09, 0.09, 0.1); // coal
		base_rough = 0.95;
	} else if (idx == 6) {
		base_color = vec3(0.88, 0.84, 0.72); // silica
		base_rough = 0.35;
	} else if (idx == 7) {
		base_color = vec3(0.35, 0.95, 0.3); // radioactive crystal
		base_rough = 0.2;
	} else {
		base_color = vec3(0.42, 0.4, 0.38); // stone
		base_rough = 0.95;
	}

	float n1 = value_noise(v_world_pos * 0.6);
	float n2 = value_noise(v_world_pos * 3.5);
	float variation = mix(n1, n2, 0.4);
	float shade = mix(0.82, 1.12, variation);
	vec3 color = base_color * shade;

	// Frostier near the planet's poles, warmer near the equator - reads as
	// one coherent sphere instead of an arbitrary blob of colored rock.
	vec3 dir_from_center = normalize(v_world_pos);
	float lat = abs(dir_from_center.y);
	color = mix(color, color * vec3(1.05, 1.05, 1.15) + vec3(0.03), smoothstep(0.6, 1.0, lat) * 0.5);

	ALBEDO = color;
	ROUGHNESS = clamp(base_rough + (variation - 0.5) * 0.15, 0.05, 1.0);
}

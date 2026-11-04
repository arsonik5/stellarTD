shader_type spatial;
// Emissive, unlit, and never shadowed - a star is its own light source, so
// letting the renderer light it would be wrong in both directions.
render_mode unshaded, shadows_disabled, cull_back;

// The star's photosphere as REAL GEOMETRY, not a disc painted on the sky.
// That distinction is the whole point: a sky-painted sun cannot be approached,
// cannot occlude anything in front of it, and cannot be flown into. This is a
// sphere the player can actually reach.

uniform vec3 star_color : source_color = vec3(1.0, 0.95, 0.85);
// Peak intensity at the centre of the disc, in pre-tonemap HDR units.
//
// This has to stay in a narrow band to work at all. The scene tonemaps with
// ACES at white = 6, so anything past ~5 lands within a couple of percent of
// pure white NO MATTER what the limb law does - at the old 8.0 the entire disc
// clipped and the star drew as a flat white circle with a hard edge. Around 3
// the centre still saturates (a star should) while the outer half of the disc
// falls back down the curve and shows its actual colour.
uniform float brightness : hint_range(0.0, 40.0) = 3.2;
// Quadratic limb darkening, I(mu)/I(1) = 1 - a(1-mu) - b(1-mu)^2, the law
// actually used to fit stellar discs. The linear term alone is too gentle to
// see here: for a sphere mu = sqrt(1 - (r/R)^2), which stays above 0.5 until
// 87% of the way to the edge, so a linear law crams all its falloff into the
// outermost few pixels. The quadratic term is what makes the dimming start
// somewhere you can see it.
uniform float limb_darkening : hint_range(0.0, 1.0) = 0.45;
uniform float limb_darkening_quad : hint_range(0.0, 1.0) = 0.35;
uniform float granulation_scale : hint_range(0.0, 40.0) = 7.0;
uniform float granulation_strength : hint_range(0.0, 1.0) = 0.22;
uniform float time_scale : hint_range(0.0, 2.0) = 0.05;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

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
	f = f * f * (3.0 - 2.0 * f);
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

void fragment() {
	// Convection granulation, drifting slowly. Two octaves is enough at the
	// distances a star is normally viewed from.
	vec3 p = normalize(v_local) * granulation_scale;
	float t = TIME * time_scale;
	float n = value_noise(p + vec3(t, 0.0, 0.0)) * 0.65
		+ value_noise(p * 2.7 - vec3(0.0, t, 0.0)) * 0.35;

	// cos of the angle between the surface normal and the view direction: 1 at
	// the centre of the visible disc, 0 at the limb. NORMAL and VIEW are both
	// view-space in a Godot fragment shader (VIEW points toward the camera),
	// so this is a plain dot product - no matrix juggling needed.
	float mu = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float d = 1.0 - mu;
	float limb = clamp(1.0 - limb_darkening * d - limb_darkening_quad * d * d, 0.0, 1.0);

	float intensity = brightness * limb * mix(1.0 - granulation_strength, 1.0 + granulation_strength, n);

	// Hotter toward the centre of the disc, cooler and redder at the limb. Keyed
	// off the raw limb factor rather than the darkened intensity so the colour
	// shift survives the centre clipping to white.
	vec3 col = mix(star_color * vec3(1.0, 0.72, 0.45), star_color, smoothstep(0.0, 1.0, limb));

	// Write ALBEDO, not EMISSION.
	//
	// Under `render_mode unshaded` Godot outputs ALBEDO directly and skips the
	// lighting pass entirely - which means EMISSION is never read. Putting the
	// colour in EMISSION and leaving ALBEDO at zero drew the star as a
	// perfectly positioned, correctly sized, pure BLACK sphere against black
	// space. It was invisible while being rendered exactly as asked.
	//
	// Values above 1.0 are what the Environment's glow picks up as bloom, so
	// the halo comes from this being a genuine HDR value.
	ALBEDO = col * intensity;
}

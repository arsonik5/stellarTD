shader_type spatial;
// Additive, never occluding, never lit, and never writing depth - a corona is
// light in the air between the star and the camera, not a surface.
render_mode unshaded, blend_add, shadows_disabled, depth_draw_never, cull_disabled;

// The star's outer glow, as GEOMETRY rather than post-processing bloom.
//
// Bloom was the original approach and it does not work here: Environment glow
// has ONE hdr threshold for the whole frame, and sunlit terrain sits just above
// 1.0 in HDR. Any threshold low enough to give the star a corona also fed the
// entire ground into an additive blur and washed the surface out to flat white;
// any threshold high enough to spare the terrain left the star a bare white
// dot. The two are not separable with a single global knob, so the corona moved
// onto the star itself where it can be tuned without touching anything else.
//
// A camera-facing quad rather than a shell: a sphere would need front faces
// when the camera is outside it and back faces when inside, and either choice
// is wrong half the time. A billboard has no inside.

uniform vec3 star_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float intensity : hint_range(0.0, 8.0) = 1.35;
// Quad radius in star radii. The disc itself occupies 1.0 of this, everything
// beyond is corona.
uniform float shell_ratio : hint_range(1.5, 20.0) = 3.0;
// Higher = tighter halo hugging the limb, lower = broader diffuse glow.
uniform float falloff : hint_range(0.5, 16.0) = 7.0;
// Width of the bright rim right at the limb, as a fraction of the star radius.
// Reference photography of a real star shows a SHARPLY bounded white disc with
// a thin warm ring on it, then a modest halo - not a broad diffuse fog. The
// first version of this shader had a near-linear outer term that produced
// exactly that fog.
uniform float rim_width : hint_range(0.02, 1.0) = 0.22;
uniform float rim_boost : hint_range(0.0, 6.0) = 2.4;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	// Standard Godot billboard: keep the model's translation, take orientation
	// from the inverse view matrix so the quad always faces the camera. Scale
	// comes from the mesh size, so distance falloff is plain perspective.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	// Distance from the quad centre, in star radii.
	float u = length(v_uv - vec2(0.5)) * 2.0 * shell_ratio;
	// 1 inside the disc, falling to 0 at the quad edge. The disc region is
	// normally hidden behind the photosphere, which draws over it.
	float t = clamp((shell_ratio - u) / (shell_ratio - 1.0), 0.0, 1.0);
	// A bright ring hugging the limb, plus a modest halo behind it. The ring is
	// keyed off distance from the limb in STAR RADII rather than off t, so its
	// width does not change when shell_ratio is retuned.
	float rim = 1.0 - smoothstep(0.0, rim_width, max(u - 1.0, 0.0));
	float halo = pow(t, falloff);
	float glow = rim * rim_boost + halo;
	// Warmer at the outer edge, matching the limb of the disc it surrounds.
	// Warm at the rim, cooling outward into the halo - the orange ring in the
	// reference is the photosphere seen through its own outer layers.
	vec3 col = mix(star_color * vec3(1.0, 0.52, 0.22), star_color, rim * 0.65);
	ALBEDO = col * glow * intensity;
	ALPHA = 1.0;
}

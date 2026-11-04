shader_type spatial;
// Full-screen pass. Unshaded and depth-test-disabled because the quad is
// forced to clip space in vertex() and must never be occluded by the scene
// it is compositing over.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix;

// Physically-based single-scattering atmosphere, raymarched per pixel.
//
// ONE integral produces every behaviour the old system faked separately:
//   - sky colour from the ground            (was: sky shader gradient)
//   - haze on distant terrain               (was: Environment fog)
//   - the lit limb seen from orbit          (was: a translucent proxy sphere)
//   - gradual fade on leaving the atmosphere (was: an atmosphere_factor lerp)
//
// It is also the reason there is no "up" vector anywhere here. The old sky
// gradient was built on EYEDIR.y - the WORLD Y axis - which is only the
// player's real up at the north pole. This is purely geometric: it intersects
// a sphere and integrates along the view ray, so it is correct at every point
// on every body automatically.
//
// Multi-body: every registered body is marched in the same frame, so flying
// between two planets crossfades on its own with no reload and no blending
// logic on the CPU side.

#define MAX_BODIES 4

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform int body_count = 0;
uniform vec3 body_center[MAX_BODIES];
uniform float body_surface_radius[MAX_BODIES];
// Radius used ONLY to stop the ray passing through the planet. It is the
// LOWEST point terrain can reach, not the nominal radius.
//
// Clamping at the nominal radius drew a hard horizontal seam across the sky:
// terrain actually spans radius +- relief, so the nominal sphere's horizon sits
// at a different angle than the real terrain's, and rays either side of it got
// very different path lengths. The seam moved with altitude, so it appeared
// and disappeared as the player jumped. Using the minimum terrain radius means
// the analytic clamp can never cut a ray shorter than real terrain would -
// the depth buffer (scene_dist) handles the accurate case.
uniform float body_ground_radius[MAX_BODIES];
uniform float body_shell_radius[MAX_BODIES];
uniform vec3 body_rayleigh[MAX_BODIES];
uniform vec3 body_ozone[MAX_BODIES];
uniform float body_mie[MAX_BODIES];
uniform float body_mie_g[MAX_BODIES];
uniform float body_rayleigh_scale[MAX_BODIES];
uniform float body_mie_scale[MAX_BODIES];
// Ozone gets its OWN vertical profile instead of riding the Rayleigh density
// curve. Real ozone sits in a layer well above the densest air (Earth's
// ozone layer peaks ~25 km up, clear of most of the Rayleigh column below
// it) - that separation is exactly what paints the distinct cyan/navy band
// above the orange/white haze in a limb photograph. Sharing Rayleigh's
// exp(-h/scale) profile (the pre-2026-09-11 behaviour) ties ozone to the
// same altitude as the thick air, so it can only ever tint the existing haze
// rather than add its own band above it. Height is expressed as a fraction
// of shell thickness (body_shell_radius - body_surface_radius), consistent
// with every other atmosphere ratio in this project being radius-relative.
uniform float body_ozone_peak[MAX_BODIES];
uniform float body_ozone_width[MAX_BODIES];
uniform float body_energy[MAX_BODIES];

// The star's POSITION, not a direction. A single global sun direction is
// wrong the moment there is more than one body: two planets on opposite sides
// of a star are lit from opposite directions, and the old uniform lit both as
// though the sun were in the same place for each. Direction is now derived
// per body, inside the loop.
uniform vec3 star_position = vec3(0.0, 1.0, 0.0);
// Distance at which sun_intensity is calibrated. Brightness scales as
// (reference/actual)^2 from here - the SAME convention Star.gd uses for the
// DirectionalLight3D's energy, so the lit terrain and the lit sky brighten
// and dim together instead of drifting apart.
uniform float star_reference_distance = 1100.0;
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.92);
uniform float sun_intensity : hint_range(0.0, 100000.0) = 4200.0;

uniform int view_samples : hint_range(4, 128) = 64;
uniform int light_samples : hint_range(2, 16) = 6;

void vertex() {
	// Force a full-screen triangle regardless of where the node actually sits.
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

// Distances along `dir` where the ray enters and exits a sphere. Returns
// vec2(-1.0) when it misses. `dir` must be normalized.
vec2 ray_sphere(vec3 origin, vec3 dir, vec3 center, float radius) {
	vec3 oc = origin - center;
	float b = dot(oc, dir);
	float c = dot(oc, oc) - radius * radius;
	float disc = b * b - c;
	if (disc < 0.0) {
		return vec2(-1.0);
	}
	float s = sqrt(disc);
	return vec2(-b - s, -b + s);
}

// Cheap per-pixel hash, used to jitter the raymarch start so adjacent pixels
// sample slightly different points along the ray. Banding was step aliasing:
// the shell is now wrapped around an 8 km body instead of a 500 m one, so
// each of the (unchanged) 24 view samples covers ~16x the distance, and a
// march that coarse quantises into visible concentric rings on the limb and
// sky. Raising sample counts alone would fix it but costs linearly forever;
// dithering turns the same banding into noise, which the eye reads as smooth
// - the standard raymarch-banding fix, far cheaper than brute-forcing samples.
//
// Interleaved Gradient Noise rather than fract(sin(dot(...))).
//
// The sin-hash is cheap and badly distributed: it clumps, so its error lands in
// blotches rather than as even grain. That is invisible against a bright sky,
// where the error is a small fraction of the signal, and very visible on the
// night limb, where the signal is almost zero and the same absolute error is
// most of what is on screen. IGN is the standard choice for exactly this and
// costs the same.
float dither_hash(vec2 co) {
	return fract(52.9829189 * fract(dot(co, vec2(0.06711056, 0.00583715))));
}

float rayleigh_phase(float mu) {
	return 3.0 / (16.0 * PI) * (1.0 + mu * mu);
}

float mie_phase(float mu, float g) {
	float g2 = g * g;
	float denom = 1.0 + g2 - 2.0 * g * mu;
	return 3.0 / (8.0 * PI) * ((1.0 - g2) * (1.0 + mu * mu))
		/ ((2.0 + g2) * pow(max(denom, 0.0001), 1.5));
}

// Ozone density as a function of height above the surface, as a fraction of
// this body's shell thickness - a Gaussian bump centred at `peak`, NOT the
// Rayleigh exponential. A real ozone layer sits in a band well clear of the
// ground; approximating it as a bump rather than reusing exp(-h/scale) is
// what lets it paint its own colour band above the Rayleigh/Mie haze instead
// of just tinting it. `width` is the bump's standard deviation, same units.
float ozone_density(float h, float shell_height, float peak, float width) {
	if (shell_height <= 0.0) {
		return 0.0;
	}
	float t = h / shell_height;
	float d = (t - peak) / max(width, 0.001);
	return exp(-0.5 * d * d);
}

// Optical depth from `p` toward the sun, as (rayleigh_units, mie_units,
// ozone_units). Returns a large value if the ray to the sun is blocked by
// the planet body, which is what puts the night side in shadow and reddens a
// low sun.
vec3 sun_optical_depth(int i, vec3 p, vec3 sun_dir) {
	vec3 c = body_center[i];
	float surf = body_surface_radius[i];
	float shell = body_shell_radius[i];
	float shell_height = shell - surf;

	// Blocked by the body itself -> no direct sunlight reaches p.
	vec2 ground = ray_sphere(p, sun_dir, c, body_ground_radius[i]);
	if (ground.x > 0.0) {
		return vec3(1e6);
	}

	vec2 hit = ray_sphere(p, sun_dir, c, shell);
	if (hit.y <= 0.0) {
		return vec3(0.0);
	}
	float march = hit.y / float(light_samples);
	vec3 depth = vec3(0.0);
	for (int s = 0; s < light_samples; s++) {
		vec3 sp = p + sun_dir * (float(s) + 0.5) * march;
		float h = max(length(sp - c) - surf, 0.0);
		depth.x += exp(-h / body_rayleigh_scale[i]) * march;
		depth.y += exp(-h / body_mie_scale[i]) * march;
		depth.z += ozone_density(h, shell_height, body_ozone_peak[i], body_ozone_width[i]) * march;
	}
	return depth;
}

// In-scattered light from one body along [t_start, t_end], and the
// transmittance the background behind it survives with.
void scatter_body(int i, vec3 origin, vec3 dir, float t_start, float t_end,
		vec3 sun_dir, float sun_scale, float jitter, out vec3 inscatter, out vec3 transmittance) {
	inscatter = vec3(0.0);
	transmittance = vec3(1.0);

	vec3 c = body_center[i];
	float surf = body_surface_radius[i];
	float shell_height = body_shell_radius[i] - surf;
	// Sample count scales with how LONG the ray is inside the shell.
	//
	// A fixed count spreads the same 24 samples over a 2 km vertical crossing
	// and a 300 km grazing limb ray, so the limb is sampled two orders of
	// magnitude more coarsely - and the limb is exactly where the artifact
	// shows. Dithering converts that error from stair-step bands into grain but
	// cannot remove it; on the dark side, where the eye is adapted and the
	// signal is small, the grain is what reads as "glitching".
	//
	// Scaled against the shell's own diameter so it is resolution-independent
	// and needs no per-planet tuning: a ray crossing one shell-diameter of
	// atmosphere gets the base count, a limb ray crossing several gets
	// proportionally more, capped so a grazing ray cannot run away.
	float span = t_end - t_start;
	float shell_diameter = 2.0 * body_shell_radius[i];
	float coverage = clamp(span / max(shell_diameter, 1.0), 0.25, 1.0);
	int samples = int(clamp(float(view_samples) * (0.5 + 1.5 * coverage),
		8.0, float(view_samples) * 2.0));
	float march = span / float(samples);
	if (march <= 0.0) {
		return;
	}

	float mu = dot(dir, sun_dir);
	float ph_r = rayleigh_phase(mu);
	float ph_m = mie_phase(mu, body_mie_g[i]);

	vec3 beta_r = body_rayleigh[i];
	float beta_m = body_mie[i];
	vec3 beta_o = body_ozone[i];
	float ozone_peak = body_ozone_peak[i];
	float ozone_width = body_ozone_width[i];

	vec3 view_depth = vec3(0.0);

	for (int s = 0; s < samples; s++) {
		// +jitter (in -0.5..0.5) moves the sample off the bin centre by a
		// per-pixel-random fraction of one step, which turns the fixed ring
		// pattern into noise instead - see dither_hash() above.
		vec3 p = origin + dir * (t_start + (float(s) + 0.5 + jitter) * march);
		float h = max(length(p - c) - surf, 0.0);

		float dr = exp(-h / body_rayleigh_scale[i]) * march;
		float dm = exp(-h / body_mie_scale[i]) * march;
		float do_ = ozone_density(h, shell_height, ozone_peak, ozone_width) * march;
		view_depth += vec3(dr, dm, do_);

		vec3 sd = sun_optical_depth(i, p, sun_dir);

		// Beer-Lambert over the whole path: sun -> sample -> camera. Ozone
		// now carries its OWN accumulated depth (.z) instead of reusing
		// Rayleigh's (.x) - see ozone_density() for why that separation is
		// what produces a distinct high-altitude colour band.
		vec3 tau = beta_r * (sd.x + view_depth.x)
			+ vec3(beta_m) * 1.1 * (sd.y + view_depth.y)
			+ beta_o * (sd.z + view_depth.z);
		vec3 att = exp(-tau);

		inscatter += att * (beta_r * ph_r * dr + vec3(beta_m) * ph_m * dm);
	}

	vec3 total_tau = beta_r * view_depth.x
		+ vec3(beta_m) * 1.1 * view_depth.y
		+ beta_o * view_depth.z;
	transmittance = exp(-total_tau);
	inscatter *= sun_color * sun_intensity * sun_scale * body_energy[i];
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;

	// World-space view ray for this pixel, reconstructed from the far plane.
	vec4 view_far = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	view_far.xyz /= view_far.w;
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(view_far.xyz, 0.0)).xyz);

	// Distance to whatever the scene already drew at this pixel. Sky pixels
	// come back at (or beyond) the far plane, which is deliberately NOT
	// special-cased: every span below is clamped with min() against the
	// shell exit anyway, so the result is the same under either depth
	// convention and no reverse-Z detection is needed.
	float raw_depth = texture(depth_tex, SCREEN_UV).x;
	vec4 view_p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	view_p.xyz /= view_p.w;
	float scene_dist = length(view_p.xyz);

	vec3 color = texture(screen_tex, SCREEN_UV).rgb;

	// One hash per pixel, reused for every body this pixel marches - each body
	// gets a different-looking dither because its own march step differs, so
	// no visible correlation between bodies' bands.
	float jitter = dither_hash(FRAGCOORD.xy) - 0.5;

	for (int i = 0; i < MAX_BODIES; i++) {
		if (i >= body_count) {
			break;
		}

		vec2 shell = ray_sphere(cam, dir, body_center[i], body_shell_radius[i]);
		if (shell.y <= 0.0) {
			continue;
		}

		float t0 = max(shell.x, 0.0);
		float t1 = min(shell.y, scene_dist);

		// Terrain can also cut the span short from inside the shell; and if
		// the body's solid surface is in front of us, stop there.
		// Conservative: only blocks rays that would pass below ALL possible
		// terrain. Anything above that is resolved by scene depth instead.
		vec2 ground = ray_sphere(cam, dir, body_center[i], body_ground_radius[i]);
		if (ground.x > 0.0) {
			t1 = min(t1, ground.x);
		}

		if (t1 <= t0) {
			continue;
		}

		// Direction to the star from THIS body, and how bright the star is
		// here relative to the reference distance the intensity was tuned at.
		// Treating the star as directional per body is a good approximation
		// while it is far compared to the body's own radius, and it keeps the
		// integral cheap; it stops being true only if a body is flown very
		// close to the star, which is not reachable geometry yet.
		vec3 to_star = star_position - body_center[i];
		float star_dist = max(length(to_star), 0.001);
		vec3 sun_dir = to_star / star_dist;
		float sun_scale = (star_reference_distance * star_reference_distance) / (star_dist * star_dist);

		vec3 inscatter;
		vec3 transmittance;
		scatter_body(i, cam, dir, t0, t1, sun_dir, sun_scale, jitter,
			inscatter, transmittance);
		color = color * transmittance + inscatter;
	}

	ALBEDO = color;
	ALPHA = 1.0;
}

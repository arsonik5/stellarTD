shader_type sky;

// Basic procedural atmosphere: a zenith->horizon->ground gradient plus a sun
// disc and soft glow read from the scene's DirectionalLight (LIGHT0_*).
// All look-defining values are uniforms so a different planet is just a
// different set of parameters (see PlanetAtmosphere/world.gd), not a
// different shader.

uniform vec4 zenith_color : source_color = vec4(0.1, 0.28, 0.65, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.68, 0.78, 0.88, 1.0);
uniform vec4 ground_color : source_color = vec4(0.14, 0.12, 0.11, 1.0);
uniform float horizon_curve : hint_range(0.2, 8.0) = 2.0;

uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float sun_angular_size : hint_range(0.001, 0.2) = 0.03;
uniform vec4 sun_glow_color : source_color = vec4(1.0, 0.7, 0.4, 1.0);
uniform float sun_glow_intensity : hint_range(0.0, 6.0) = 1.8;
uniform float sun_glow_exponent : hint_range(1.0, 128.0) = 10.0;
uniform float atmosphere_energy : hint_range(0.0, 3.0) = 1.0;

void sky() {
	float up = EYEDIR.y;

	float sky_t = pow(clamp(up, 0.0, 1.0), 1.0 / horizon_curve);
	vec3 sky_col = mix(horizon_color.rgb, zenith_color.rgb, sky_t);

	float ground_t = pow(clamp(-up, 0.0, 1.0), 1.0 / horizon_curve);
	vec3 below_col = mix(horizon_color.rgb, ground_color.rgb, ground_t);

	vec3 col = mix(below_col, sky_col, step(0.0, up));

	// LIGHT0_DIRECTION points from the viewer toward the sun, so this peaks
	// at 1.0 when looking straight at it.
	float sun_dot = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);

	float glow = pow(sun_dot, sun_glow_exponent) * sun_glow_intensity * atmosphere_energy;
	col += sun_glow_color.rgb * glow;

	float disc = smoothstep(cos(sun_angular_size), cos(sun_angular_size * 0.9), sun_dot);
	col = mix(col, sun_color.rgb * max(LIGHT0_ENERGY, 0.2), disc);

	COLOR = col;
}

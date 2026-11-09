shader_type spatial;
render_mode depth_draw_opaque;

// Scattered rocks (ScatterEngine, stage 4a of reports/AAA voxel terrain fidelity.md). The scan's own maps, plus three
// things that make a rock read as part of the ground it lies on instead of an asset set on top of it:
//   - colour match: the rock is pulled toward the ground's colour (same geology, same weathering)
//   - burial blend: within blend_height of where it enters the ground, the rock takes on the ground material itself
//     (sampled from the planet's own terrain array, projected on the planet's radial up)
//   - dust: up-facing surfaces carry the ground's fines
// No depth reads and no transparency, so it costs one extra texture fetch near the base.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;   // glTF: G rough, B metal
uniform bool has_orm = false;
uniform vec3 rock_mean = vec3(0.4);             // the scan's mean albedo (linear), for the colour match

uniform sampler2DArray terrain_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_terrain = false;               // false: blend toward ground_colour (no texture)
uniform int ground_layer = 0;
uniform float ground_tile_m = 2.5;
uniform vec3 ground_colour = vec3(0.2);         // the ground's far colour (linear, tinted)
uniform vec3 ground_tint = vec3(1.0);
uniform vec3 planet_center = vec3(0.0);

uniform float colour_match : hint_range(0.0, 1.0) = 0.55;
uniform float dust : hint_range(0.0, 1.0) = 0.35;
uniform float burial_m = 0.1;                    // how deep this instance sits (approximate, per line)
uniform float blend_height_m = 0.18;

varying vec3 v_world;
varying float v_h;                               // metres above the rock's base, in its own up

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_h = VERTEX.y * length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	vec3 c = alb.rgb;
	// colour match: scale the scan toward the ground's colour, keeping its own variation
	vec3 ratio = ground_colour / max(rock_mean, vec3(0.02));
	c *= mix(vec3(1.0), clamp(ratio, vec3(0.2), vec3(3.0)), colour_match);

	vec3 up = normalize(v_world - planet_center);
	vec3 t = normalize(cross(up, abs(up.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 b = cross(up, t);
	vec2 guv = vec2(dot(v_world, t), dot(v_world, b)) / ground_tile_m;
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float upness = smoothstep(0.55, 0.92, dot(n_world, up));
	float base = 1.0 - smoothstep(burial_m, burial_m + blend_height_m, v_h);
	float g_amt = max(base, upness * dust);
	if (g_amt > 0.01) {
		vec3 g = has_terrain ? texture(terrain_albedo, vec3(guv, float(ground_layer))).rgb * ground_tint : ground_colour;
		c = mix(c, g, g_amt);
	}
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.4, g_amt);
	float rough = has_orm ? texture(orm_tex, UV).g : 0.85;
	ROUGHNESS = mix(rough, 0.95, g_amt);
	SPECULAR = 0.4;
}

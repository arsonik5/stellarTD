shader_type canvas_item;
// Behind every full-screen UI (UiKit.shade): the world, blurred (mip levels of the screen), darkened with the UI
// tint and a soft vignette - the content floats on the game instead of hiding it behind a grey box.
// `fade` and `blur` are animated on open (UiKit.screen_in).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 3.2;
uniform vec4 tint : source_color = vec4(0.016, 0.024, 0.035, 0.70);
uniform float vignette : hint_range(0.0, 1.0) = 0.6;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * pow(2.0, blur) * 0.75;
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur).rgb * 0.36;
	c += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), blur).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), blur).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), blur).rgb * 0.16;
	c += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), blur).rgb * 0.16;
	c = mix(c, tint.rgb, tint.a);
	vec2 d = UV - vec2(0.5);
	c *= 1.0 - smoothstep(0.25, 0.95, length(d * vec2(1.05, 1.35))) * vignette;
	COLOR = vec4(c, fade);
}

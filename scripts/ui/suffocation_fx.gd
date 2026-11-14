class_name SuffocationFX
extends CanvasLayer

## Out of air: the screen wobbles and blurs (dizziness), colour drains, a red tunnel closes in, a warning flashes with
## a countdown, and when the countdown ends the player dies (Player.dying -> fade to black -> respawn).
##
## Everything is driven by `Player.suffocation` (0 at the first empty breath, 1 at death), so the effect gets
## stronger by itself as the seconds run out. A faint version also starts while the suit is merely low.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity = 0.0;
uniform float t = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c);
	float k = intensity;
	// slow drunken sway and breathing zoom, stronger toward the edges
	vec2 wob = vec2(sin(uv.y * 8.0 + t * 1.6), cos(uv.x * 6.0 + t * 1.2)) * 0.007 * k * (0.3 + r);
	wob += vec2(sin(t * 0.7), cos(t * 0.9)) * 0.006 * k;
	float zoom = 1.0 - 0.035 * k * (0.5 + 0.5 * sin(t * 0.8));
	vec2 suv = c * zoom + 0.5 + wob;
	float blur = k * 3.2 * (0.25 + r);
	vec3 col;
	col.r = textureLod(screen_tex, suv + c * 0.014 * k, blur).r;
	col.g = textureLod(screen_tex, suv, blur).g;
	col.b = textureLod(screen_tex, suv - c * 0.014 * k, blur).b;
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g), 0.55 * k);
	// tunnel vision that pulses like a heartbeat
	float beat = 0.5 + 0.5 * sin(t * (2.0 + 4.0 * k));
	float inner = mix(0.95, 0.12, k) - 0.06 * k * beat;
	float dark = smoothstep(inner, 0.78, r);
	col *= 1.0 - dark * (0.45 + 0.55 * k);
	col += vec3(0.16, 0.0, 0.0) * dark * k * (0.5 + 0.5 * beat);
	COLOR = vec4(col, 1.0);
}
"""

var _fx: ColorRect
var _mat: ShaderMaterial
var _over: Control          # undistorted layer: warning text, death fade
var _over_layer: CanvasLayer
var _t := 0.0
var _player: Node = null
var _beat_t := 0.0

func _ready() -> void:
	layer = 60
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.material = _mat
	_fx.visible = false
	add_child(_fx)
	_over_layer = CanvasLayer.new()
	_over_layer.layer = 61
	add_child(_over_layer)
	_over = Control.new()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_on_draw)
	_over_layer.add_child(_over)

func _process(delta: float) -> void:
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var k := _intensity()
	_fx.visible = k > 0.003
	if _fx.visible:
		_mat.set_shader_parameter("intensity", k)
		_mat.set_shader_parameter("t", _t)
	var sus: float = _player.get("suffocation")
	if sus > 0.0 and not _player.get("dying"):
		# a thump on every heartbeat, quicker as it gets worse
		_beat_t -= delta
		if _beat_t <= 0.0:
			_beat_t = lerpf(1.1, 0.4, sus)
			UiSound.play("mine_hit", lerpf(0.5, 0.8, sus), 0.1)
	_over.queue_redraw()

func _intensity() -> float:
	var sus: float = _player.get("suffocation")
	var o2: float = _player.get("suit_o2")
	var k := 0.0
	if sus > 0.0:
		k = 0.12 + 0.88 * pow(clampf(sus, 0.0, 1.0), 1.3)
	elif o2 < 30.0:
		k = 0.06 * (1.0 - o2 / 30.0)          # a faint warning of what is coming
	if _player.get("dying"):
		k = 1.0
	return k

func _on_draw() -> void:
	if _player == null:
		return
	var size := _over.size
	var sus: float = _player.get("suffocation")
	var font: Font = _over.get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var dying: bool = _player.get("dying")
	if sus > 0.0 and not dying:
		# A suit warning, not an alarm: one small panel under the objective line that breathes slowly and goes from
		# amber to red as the seconds run out. No full-screen flashing.
		var pulse := 0.5 + 0.5 * sin(_t * lerpf(1.6, 3.2, sus))
		var col := UiTokens.WARN.lerp(UiTokens.DANGER, sus)
		var left := ceili(_player.get("SUFFOCATE_SECONDS") * (1.0 - sus))
		var w := 380.0
		var p := Vector2(size.x * 0.5 - w * 0.5, size.y * 0.16)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.02, 0.02, 0.62)
		sb.border_color = Color(col, 0.45 + 0.45 * pulse)
		sb.set_border_width_all(1)
		sb.corner_radius_top_left = UiTokens.CORNER_BIG
		sb.corner_radius_bottom_right = UiTokens.CORNER_BIG
		sb.corner_radius_top_right = UiTokens.CORNER_SMALL
		sb.corner_radius_bottom_left = UiTokens.CORNER_SMALL
		_over.draw_style_box(sb, Rect2(p, Vector2(w, 74.0)))
		_over.draw_rect(Rect2(p.x + 14.0, p.y + 14.0, 3.0, 24.0), Color(col, 0.6 + 0.4 * pulse))
		_over.draw_string(font, p + Vector2(26.0, 33.0), "SUIT O2 CRITICAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(col, 0.75 + 0.25 * pulse))
		_over.draw_string(font, p + Vector2(w - 110.0, 33.0), "%d s" % left, HORIZONTAL_ALIGNMENT_RIGHT, 96.0, 20, UiTokens.TEXT)
		_over.draw_string(font, p + Vector2(26.0, 56.0), "Life support empty. Reach a garage or a sealed cockpit.", HORIZONTAL_ALIGNMENT_LEFT, w - 40.0, 12, UiTokens.TEXT_DIM)
		_over.draw_rect(Rect2(p.x + 1.0, p.y + 70.0, (w - 2.0) * (1.0 - sus), 3.0), Color(col, 0.8))
	if dying:
		var fade := clampf(float(_player.get("dying_time")) / 1.6, 0.0, 1.0)
		_over.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, fade))
		_over.draw_string(font, Vector2(size.x * 0.5 - 300.0, size.y * 0.5), "YOU SUFFOCATED",
			HORIZONTAL_ALIGNMENT_CENTER, 600.0, 48, Color(UiTokens.DANGER, fade))

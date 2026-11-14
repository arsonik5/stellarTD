extends Node
## UI sound (autoload "UiSound"; docs/game/ux-bible.md, "Feedback"). Every interaction answers with sound as well as
## motion. The sounds are synthesised here at start-up - short, soft, clean digital tones that suit the thin-line
## look - so there are no audio files to manage yet. They play on the "UI" bus (Settings > Audio > Interface sounds)
## and keep playing while the game is paused.
##   UiSound.play("click")   names: hover click confirm back open close error toggle_on toggle_off tick
##                                  place deny pickup objective warn
## Swap in recorded sounds later by putting res://audio/ui/<name>.wav in place: a file wins over the synth.

const RATE := 44100
const VOICES := 8
## Gain per sound (dB) - hover and tick sit far under everything else, they happen constantly.
const GAIN := {
	"hover": -21.0, "click": -12.0, "confirm": -10.0, "back": -12.0, "open": -15.0, "close": -16.0,
	"error": -10.0, "toggle_on": -13.0, "toggle_off": -13.0, "tick": -24.0, "place": -8.0, "deny": -11.0,
	"pickup": -15.0, "objective": -9.0, "warn": -12.0, "mine_hit": -9.0, "spinup": -13.0, "spindown": -15.0, "blip": -19.0,
}

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_play := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
		add_child(p)
		_players.append(p)
	for n: String in GAIN:
		var path := "res://audio/ui/%s.wav" % n
		_streams[n] = load(path) if ResourceLoader.exists(path) else _synth(n)

## Play a UI sound. Repeats of the same sound closer than `min_gap` seconds are dropped (hover over a grid).
func play(sound: String, pitch: float = 1.0, min_gap: float = 0.035) -> void:
	if not _streams.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(sound, -1.0)) < min_gap:
		return
	_last_play[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.volume_db = GAIN[sound]
	p.pitch_scale = pitch * randf_range(0.985, 1.015)       # a hair of variation so repeats don't machine-gun
	p.play()

# --- synthesis ------------------------------------------------------------------------------------------
func _synth(n: String) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	match n:
		"hover": s = _tone([2600.0], 0.022, 0.001, 0.02, 0.6)
		"click": s = _mix([_glide(1500.0, 950.0, 0.045, 0.001), _noise(0.008, 0.25)])
		"confirm": s = _seq([_tone([880.0, 1760.0], 0.07, 0.003, 0.06), _tone([1318.5, 2637.0], 0.12, 0.003, 0.11)])
		"back": s = _seq([_tone([1046.5], 0.05, 0.002, 0.045), _tone([740.0], 0.08, 0.002, 0.07)])
		"open": s = _mix([_glide(320.0, 960.0, 0.18, 0.04, 0.5), _noise(0.16, 0.12, 0.05)])
		"close": s = _mix([_glide(900.0, 300.0, 0.14, 0.005, 0.5), _noise(0.12, 0.10, 0.01)])
		"error": s = _seq([_tone([196.0, 588.0], 0.075, 0.002, 0.06, 1.0), _silence(0.035), _tone([174.6, 523.8], 0.10, 0.002, 0.09, 1.0)])
		"toggle_on": s = _glide(900.0, 1400.0, 0.06, 0.001)
		"toggle_off": s = _glide(1300.0, 800.0, 0.06, 0.001)
		"tick": s = _tone([3200.0], 0.010, 0.0005, 0.009, 0.5)
		"place": s = _mix([_glide(140.0, 55.0, 0.18, 0.002, 1.0), _noise(0.03, 0.5)])
		"deny": s = _seq([_tone([233.1, 466.2], 0.06, 0.002, 0.05, 1.0), _tone([207.7, 415.3], 0.08, 0.002, 0.07, 1.0)])
		"pickup": s = _glide(1400.0, 2100.0, 0.07, 0.002)
		"objective": s = _seq([_tone([659.3, 1318.5], 0.09, 0.004, 0.08), _tone([880.0, 1760.0], 0.09, 0.004, 0.08), _tone([1318.5, 2637.0], 0.28, 0.004, 0.27)])
		"spinup": s = _mix([_glide(70.0, 380.0, 0.35, 0.02, 0.6), _noise(0.35, 0.15, 0.1)])
		"spindown": s = _glide(300.0, 60.0, 0.22, 0.005, 0.6)
		"mine_hit": s = _mix([_glide(210.0, 85.0, 0.06, 0.001, 1.0), _noise(0.04, 0.55)])
		"warn": s = _seq([_tone([987.8], 0.08, 0.002, 0.07), _silence(0.06), _tone([987.8], 0.08, 0.002, 0.07)])
	return _to_wav(s)

## Sum of sine partials (each next one quieter), attack/decay envelope. `drive` > 0 adds odd harmonics (buzz).
func _tone(freqs: Array, dur: float, attack: float, decay: float, drive: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(dur * RATE)
	out.resize(count)
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		var amp := 1.0
		for f: float in freqs:
			v += sin(TAU * f * t) * amp
			if drive > 0.0:
				v += sin(TAU * f * 3.0 * t) * amp * 0.3 * drive
			amp *= 0.35
		out[i] = v * _env(t, dur, attack, decay)
	return out

## Pitch glide from f0 to f1 (exponential), optional softer attack.
func _glide(f0: float, f1: float, dur: float, attack: float, sub: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(dur * RATE)
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var f := f0 * pow(f1 / f0, t / dur)
		phase += TAU * f / RATE
		out[i] = (sin(phase) + sin(phase * 0.5) * sub) * _env(t, dur, attack, dur * 0.9)
	return out

func _noise(dur: float, amp: float, attack: float = 0.0005) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(dur * RATE)
	out.resize(count)
	var lp := 0.0
	for i in count:
		var t := float(i) / RATE
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.35)            # a little low-pass: soft air, not hiss
		out[i] = lp * amp * _env(t, dur, attack, dur)
	return out

func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return out

## Fast attack, exponential decay to silence at `dur`.
func _env(t: float, dur: float, attack: float, decay: float) -> float:
	var a := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var d := exp(-maxf(t - attack, 0.0) / maxf(decay * 0.35, 0.0001))
	var tail := clampf((dur - t) / 0.004, 0.0, 1.0)           # never end on a click
	return a * d * tail

func _seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: PackedFloat32Array in parts:
		out.append_array(p)
	return out

func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p: PackedFloat32Array in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p: PackedFloat32Array in parts:
		for i in p.size():
			out[i] += p[i]
	return out

func _to_wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] / peak * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w

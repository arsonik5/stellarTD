class_name ScannerHUD
extends CanvasLayer

## Resource scanner readout: a directional pulse, not a map.
##
## The scanner knows where deposits are (see OreScanner), but it does NOT draw
## them. What it shows is a single signal that strengthens as the tool is aimed
## at a deposit and as you close on it - a metal detector, not a minimap.
##
## The difference is the point. Markers with names and distances turn
## prospecting into reading a list and walking to the top entry: one press and
## the answer is on screen, and the tool is never used again during the walk.
## A directional pulse makes you sweep, notice the signal rise, turn until it
## peaks, and keep checking as you go - the tool stays in your hands and finding
## the deposit is something you did rather than something you were told.
##
## It deliberately withholds distance and position. The only information is "you
## are pointed at something" and "it is getting stronger", which is enough to
## home in on and not enough to skip the search.

## Contacts expire. A sweep is a snapshot of what was in range when you pinged,
## and letting it persist would put the search back on rails.
const CONTACT_LIFETIME := 90.0

## How tightly the signal is focused around the aim direction.
##
## Higher is a narrower beam and a more demanding sweep. 6 gives a lobe roughly
## 40 degrees wide at half strength - broad enough to catch while turning at a
## normal speed, tight enough that the peak is a real direction rather than
## "somewhere ahead".
const BEAM_SHARPNESS := 6.0

## Range over which proximity contributes. Matches the scanner's own reach, so a
## contact at the edge of a sweep registers faintly rather than not at all.
const FALLOFF_M := 2048.0

## Pulse rate at zero and full signal, in Hz. The acceleration is most of what
## the effect communicates - a rising rate reads as "warmer" long before the
## brightness difference is obvious.
const PULSE_HZ_MIN := 1.1
const PULSE_HZ_MAX := 7.0

## Signal below this is treated as nothing, so a faint contact behind you does
## not leave the screen permanently breathing.
const SIGNAL_FLOOR := 0.04

## Ore tint, so a strong signal says WHAT it is without saying where. Knowing
## you are chasing crystal rather than iron changes whether you bother; knowing
## the bearing and range would remove the search.
const ORE_COLOURS := {
	"iron": Color(0.86, 0.55, 0.40),
	"copper": Color(0.92, 0.58, 0.28),
	"coal": Color(0.60, 0.63, 0.70),
	"silica": Color(0.70, 0.87, 0.94),
	"sulfur": Color(0.95, 0.87, 0.35),
	"crystal": Color(0.72, 0.60, 0.96),
}
const DEFAULT_COLOUR := Color(0.55, 0.85, 0.75)

var _active := true
var _contacts: Array = []
var _elapsed := 0.0
var _status := ""
var _status_until := 0.0
## Smoothed so the pulse does not jitter frame to frame as the aim wanders
## across a contact's edge.
var _signal := 0.0
var _tint := DEFAULT_COLOUR
var _phase := 0.0
var _draw: Control

func _ready() -> void:
	layer = 40
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)

## Runs a sweep from `origin` and arms the detector with what it found.
func scan_from(terrain: VoxelLodTerrain, origin: Vector3, ore_names: Dictionary) -> void:
	var found: Array = OreScanner.scan(terrain, origin, ore_names)
	_contacts.clear()
	for h in found:
		_contacts.append({
			"position": h["position"],
			"name": String(ore_names.get(h["material_index"], "unknown")),
			"born": _elapsed,
		})
	# Deliberately vague. A count would tell the player how much is left to find
	# and turn the sweep into a checklist.
	_flash("Scanner active" if not found.is_empty() else "No return")

## False while the scanner is not in a hand: no pulse, no ring, no status text. Contacts are kept, so picking the
## scanner up again within their lifetime shows the same sweep.
func set_active(v: bool) -> void:
	_active = v
	if not v:
		_signal = 0.0
		_status = ""
		_draw.queue_redraw()

func _flash(text: String) -> void:
	_status = text
	_status_until = _elapsed + 3.0

func _process(delta: float) -> void:
	_elapsed += delta

	var i := _contacts.size() - 1
	while i >= 0:
		if _elapsed - _contacts[i]["born"] > CONTACT_LIFETIME:
			_contacts.remove_at(i)
		i -= 1

	var target := 0.0
	var target_tint := DEFAULT_COLOUR
	var cam := get_viewport().get_camera_3d()
	if not _active:
		cam = null   # scanner put away: nothing to detect, the signal fades to zero
	if cam != null:
		var eye := cam.global_position
		var forward := -cam.global_transform.basis.z
		for c in _contacts:
			var to: Vector3 = c["position"] - eye
			var dist: float = to.length()
			if dist < 0.001:
				continue
			# Two independent terms, multiplied. Aim decides whether there is a
			# signal at all; proximity decides how strong it can get. Either one
			# alone would be useless - proximity without aim is a compass with no
			# needle, aim without proximity never tells you you are arriving.
			var aim: float = maxf(forward.dot(to / dist), 0.0)
			var beam: float = pow(aim, BEAM_SHARPNESS)
			var near: float = clampf(1.0 - dist / FALLOFF_M, 0.0, 1.0)
			# Squared, so the last stretch is where the signal really climbs.
			# Linear proximity feels flat right where the player needs feedback.
			var strength: float = beam * near * near
			if strength > target:
				target = strength
				target_tint = ORE_COLOURS.get(c["name"], DEFAULT_COLOUR)

	if target < SIGNAL_FLOOR:
		target = 0.0
	# Asymmetric smoothing: rises quickly so sweeping across a contact is felt
	# immediately, falls slowly so the peak is not missed between frames.
	var rate: float = 9.0 if target > _signal else 3.0
	_signal = lerpf(_signal, target, clampf(delta * rate, 0.0, 1.0))
	_tint = _tint.lerp(target_tint, clampf(delta * 4.0, 0.0, 1.0))

	# Phase is integrated rather than derived from absolute time, so changing the
	# rate speeds the pulse up smoothly instead of jumping mid-cycle.
	_phase += delta * lerpf(PULSE_HZ_MIN, PULSE_HZ_MAX, _signal) * TAU
	if _phase > TAU:
		_phase -= TAU

	if _signal > 0.001 or _elapsed < _status_until or not _contacts.is_empty():
		_draw.queue_redraw()

func _on_draw() -> void:
	var size := _draw.size
	var font := ThemeDB.fallback_font

	if _elapsed < _status_until and not _status.is_empty():
		_draw.draw_string(font, Vector2(size.x * 0.5 - 130.0, size.y - 120.0),
			_status, HORIZONTAL_ALIGNMENT_CENTER, 260.0, 15,
			Color(0.80, 0.86, 0.92, 0.85))

	if _signal <= 0.001:
		return

	# 0..1 throb. Kept off zero at the bottom so a strong signal reads as a
	# steady glow that pulses, not as flashing.
	var throb: float = 0.55 + 0.45 * sin(_phase)
	var amount: float = _signal * throb

	# The ring. Tightens toward the centre as the signal climbs, so the effect
	# converges on the crosshair rather than just brightening.
	var centre := size * 0.5
	var radius: float = lerpf(190.0, 74.0, _signal)
	var col := _tint
	col.a = clampf(0.22 + 0.55 * amount, 0.0, 0.85)
	_draw.draw_arc(centre, radius, 0.0, TAU, 64, col, lerpf(1.5, 4.0, _signal), true)

	# A second ring expanding outward from the first, which is what makes it read
	# as a pulse travelling out rather than a circle changing size.
	var wave: float = fposmod(_phase / TAU, 1.0)
	var wave_col := _tint
	wave_col.a = (1.0 - wave) * 0.32 * _signal
	_draw.draw_arc(centre, radius + wave * 90.0, 0.0, TAU, 64, wave_col, 2.0, true)

	# Edge vignette, so the signal is felt peripherally while the player is
	# looking at the terrain rather than at the middle of the screen.
	var edge := _tint
	edge.a = 0.16 * amount
	var band := 54.0
	_draw.draw_rect(Rect2(0, 0, size.x, band), edge)
	_draw.draw_rect(Rect2(0, size.y - band, size.x, band), edge)
	_draw.draw_rect(Rect2(0, 0, band, size.y), edge)
	_draw.draw_rect(Rect2(size.x - band, 0, band, size.y), edge)

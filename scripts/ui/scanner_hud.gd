class_name ScannerHUD
extends CanvasLayer

## Resource scanner: a radar minigame, then a lock-on guide.
##
## 1. Press the scanner button: a ping runs (OreScanner) and a radar screen opens. It is an early-jet "B-scope": the
##    width is bearing (-90..+90 degrees from where you are facing), the height is range (near at the bottom), and a
##    sweep bar crosses the screen left to right. Every contact the bar passes lights up and fades like phosphor.
## 2. Tune it: mouse wheel or keys 1-6 pick which ore the radar looks for. Only that ore is traced.
## 3. Turn until a trace sits on the centre line (the bracket shows it), press the scanner button: LOCK.
## 4. The radar closes and the guide takes over: a marker on the ground target with an estimated distance, an edge
##    arrow when it is off screen, a closeness bar, and a beep that speeds up as you close in. Close in and the
##    estimate sharpens (two finer re-scans of just that deposit).
## X closes the radar; X again (radar closed) drops the lock. Taking the scanner out of the hand hides everything.

## Bearing window either side of the centre line in which a trace can be locked.
const LOCK_DEG := 7.0
## Radar range at the top of the screen, metres. The scan reaches about +-1000 m, with corners to ~1700 m.
const RANGE_M := 1800.0
const SWEEP_SECONDS := 2.4
## How long a trace takes to fade after the bar passes it.
const FADE_SECONDS := 2.2
## Re-scan the locked deposit finer when you get this close (metres, LOD of the re-scan).
const REFINE := [[500.0, 4], [160.0, 3]]

const DEFAULT_COLOUR := Color(0.55, 0.85, 0.75)

var _active := true
var _terrain: VoxelLodTerrain = null
var _ore_idx: Dictionary = {}        # ore id -> material index
var _ore_order: Array = []           # ore ids, in tuning order
var _ore_depths: Dictionary = {}     # ore id -> Vector2(depth_min, depth_max)
var _contacts: Array = []            # {position, name, samples, lit}
var _radar_open := false
var _sel := 0
var _sweep := 0.0
var _elapsed := 0.0
var _status := ""
var _status_until := 0.0
var _lock: Dictionary = {}           # {position, name, samples, stage, start_dist}
var _beep_t := 0.0
var _draw: Control

func _ready() -> void:
	layer = 40
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)

# --- public ---------------------------------------------------------------------------------------------------

## Pings from `origin` and opens the radar. `ore_names`: material index -> ore id. `ore_depths`: ore id -> Vector2.
func scan_from(terrain: VoxelLodTerrain, origin: Vector3, ore_names: Dictionary, ore_depths: Dictionary = {}) -> void:
	_terrain = terrain
	_ore_depths = ore_depths
	_ore_idx.clear()
	var keys := ore_names.keys()
	keys.sort()
	_ore_order.clear()
	for k in keys:
		var id := String(ore_names[k])
		_ore_idx[id] = int(k)
		_ore_order.append(id)
	_sel = clampi(_sel, 0, maxi(_ore_order.size() - 1, 0))
	_contacts.clear()
	for h in OreScanner.scan(terrain, origin, ore_names):
		_contacts.append({
			"position": h["position"],
			"name": String(ore_names.get(h["material_index"], "unknown")),
			"samples": int(h["samples"]),
			"lit": 0.0,
		})
	_radar_open = not _ore_order.is_empty()
	_sweep = 0.0
	if _radar_open:
		UiSound.play("open", 1.2)
	_draw.queue_redraw()

func is_radar_open() -> bool:
	return _radar_open and _active

## The scanner button while the radar is open: lock the trace on the centre line.
func lock_press() -> bool:
	var cand := _candidate()
	if cand.is_empty():
		_flash("Nothing on the centre line")
		UiSound.play("deny")
		return false
	_lock = {
		"position": cand["position"], "name": cand["name"], "samples": cand["samples"],
		"stage": 0, "start_dist": maxf(_dist_to(cand["position"]), 1.0),
	}
	_radar_open = false
	_beep_t = 0.0
	UiSound.play("confirm")
	_flash("Locked: %s" % String(cand["name"]).capitalize())
	return true

## False while the scanner is not in a hand: no radar, no guide, no status text. A lock is kept, so picking the
## scanner up again resumes the guide.
func set_active(v: bool) -> void:
	_active = v
	if not v:
		_radar_open = false
		_status = ""
	_draw.queue_redraw()

func _flash(text: String) -> void:
	_status = text
	_status_until = _elapsed + 2.5

# --- input ----------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _active or (DevConsole != null and DevConsole.is_open):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X:
			if _radar_open:
				_radar_open = false
				UiSound.play("close", 1.0)
				get_viewport().set_input_as_handled()
			elif not _lock.is_empty():
				_lock = {}
				_flash("Lock dropped")
				UiSound.play("back")
				get_viewport().set_input_as_handled()
		elif _radar_open and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_tune(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
	elif _radar_open and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_tune(_sel - 1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_tune(_sel + 1)
			get_viewport().set_input_as_handled()

func _tune(i: int) -> void:
	if _ore_order.is_empty():
		return
	i = posmod(i, _ore_order.size())
	if i == _sel:
		return
	_sel = i
	_sweep = 0.0
	for c in _contacts:
		c["lit"] = 0.0
	UiSound.play("tick", 1.4)

# --- geometry -------------------------------------------------------------------------------------------------

func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()

func _dist_to(pos: Vector3) -> float:
	var cam := _camera()
	return cam.global_position.distance_to(pos) if cam != null else 0.0

## Bearing in degrees (-180..180, 0 = straight ahead along the ground, + = right) of `pos` as seen from the camera,
## measured around the local "up" (away from the nearest body's centre) so it still works on a sphere.
func _bearing_deg(cam: Camera3D, pos: Vector3) -> float:
	var up := Vector3.UP
	var body := PlanetPhysics.get_nearest_body(cam.global_position)
	if body != null:
		up = (cam.global_position - body.global_position).normalized()
	var fwd := -cam.global_transform.basis.z
	fwd = (fwd - up * fwd.dot(up))
	if fwd.length() < 0.05:
		fwd = cam.global_transform.basis.y - up * cam.global_transform.basis.y.dot(up)
	fwd = fwd.normalized()
	var right := fwd.cross(up).normalized()
	var to := pos - cam.global_position
	to -= up * to.dot(up)
	if to.length() < 0.01:
		return 0.0
	return rad_to_deg(atan2(to.dot(right), to.dot(fwd)))

## The trace of the tuned ore nearest the centre line, within LOCK_DEG; empty if none.
func _candidate() -> Dictionary:
	var cam := _camera()
	if cam == null or _ore_order.is_empty():
		return {}
	var want: String = _ore_order[_sel]
	var best := {}
	var best_score := INF
	for c in _contacts:
		if c["name"] != want:
			continue
		var b := absf(_bearing_deg(cam, c["position"]))
		if b > LOCK_DEG:
			continue
		var score: float = b + _dist_to(c["position"]) / RANGE_M
		if score < best_score:
			best_score = score
			best = c
	return best

static func fmt_dist(d: float) -> String:
	if d >= 1000.0:
		return "%.1f km" % (d / 1000.0)
	if d >= 100.0:
		return "%d m" % (int(round(d / 10.0)) * 10)
	return "%d m" % (int(round(d / 5.0)) * 5)

# --- per frame ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_elapsed += delta
	# The radar belongs to the world view. Any menu, inventory, console or build screen takes the screen over, so the
	# radar shuts instead of floating on top of it. (Only locking, X, or putting the scanner away closes it otherwise.)
	if _radar_open and (UiState.is_any_open() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED):
		_radar_open = false
		_draw.queue_redraw()
	var cam := _camera()
	if _active and cam != null:
		if _radar_open:
			_update_radar(delta, cam)
		if not _lock.is_empty():
			_update_lock(delta, cam)
	if _active and (_radar_open or not _lock.is_empty() or _elapsed < _status_until):
		_draw.queue_redraw()

func _update_radar(delta: float, cam: Camera3D) -> void:
	var prev := _sweep
	_sweep += delta / SWEEP_SECONDS
	var wrapped := false
	if _sweep >= 1.0:
		_sweep -= 1.0
		wrapped = true
	var want: String = _ore_order[_sel]
	for c in _contacts:
		c["lit"] = maxf(float(c["lit"]) - delta / FADE_SECONDS, 0.0)
		if c["name"] != want:
			continue
		var b := _bearing_deg(cam, c["position"])
		if absf(b) > 90.0:
			continue
		var u: float = (b + 90.0) / 180.0
		var crossed: bool = (u >= prev and u < _sweep) if not wrapped else (u >= prev or u < _sweep)
		if crossed:
			c["lit"] = 1.0
			var d := _dist_to(c["position"])
			UiSound.play("blip", lerpf(1.7, 0.8, clampf(d / RANGE_M, 0.0, 1.0)), 0.05)

func _update_lock(delta: float, cam: Camera3D) -> void:
	var pos: Vector3 = _lock["position"]
	var d := cam.global_position.distance_to(pos)
	# Sharpen the estimate as you close in.
	var stage: int = _lock["stage"]
	if stage < REFINE.size() and d < float(REFINE[stage][0]) and _terrain != null:
		_lock["stage"] = stage + 1
		var lod: int = REFINE[stage][1]
		var idx: int = int(_ore_idx.get(_lock["name"], -1))
		if idx >= 0:
			var best := Vector3.ZERO
			var best_d := INF
			for h in OreScanner.scan(_terrain, pos, {idx: _lock["name"]}, lod):
				var dd: float = (h["position"] as Vector3).distance_to(pos)
				# Only ever the SAME deposit: a nearby different one would make the marker jump away from the
				# trace that was locked.
				if dd < best_d and dd < float(1 << lod) * 5.0:
					best_d = dd
					best = h["position"]
			if best_d < INF:
				_lock["position"] = best
	# Beep: slow far away, quick and higher when close.
	var near: float = 1.0 - clampf(d / 1500.0, 0.0, 1.0)
	_beep_t -= delta
	if _beep_t <= 0.0:
		_beep_t = lerpf(1.5, 0.22, near)
		UiSound.play("blip", 0.8 + near * 0.9, 0.1)

# --- drawing --------------------------------------------------------------------------------------------------

func _on_draw() -> void:
	if not _active:
		return
	var size := _draw.size
	var font: Font = _draw.get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	if _radar_open:
		_draw_radar(size, font)
	if not _lock.is_empty():
		_draw_guide(size, font)
	if _elapsed < _status_until and not _status.is_empty():
		var a: float = clampf((_status_until - _elapsed) / 0.5, 0.0, 1.0)
		var col := UiTokens.TEXT
		col.a = a
		_draw.draw_string(font, Vector2(size.x * 0.5 - 200.0, size.y * 0.74), _status,
			HORIZONTAL_ALIGNMENT_CENTER, 400.0, 18, col)

func _ore_col(id: String) -> Color:
	return OrePalette.hud(id, DEFAULT_COLOUR)

func _draw_radar(size: Vector2, font: Font) -> void:
	var cam := _camera()
	if cam == null:
		return
	var w := 600.0
	var h := 400.0
	var p := Vector2(size.x * 0.5 - w * 0.5, size.y - h - 130.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.04, 0.055, 0.82)
	sb.border_color = UiTokens.LINE_HI
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = UiTokens.CORNER_BIG
	sb.corner_radius_bottom_right = UiTokens.CORNER_BIG
	sb.corner_radius_top_right = UiTokens.CORNER_SMALL
	sb.corner_radius_bottom_left = UiTokens.CORNER_SMALL
	_draw.draw_style_box(sb, Rect2(p, Vector2(w, h)))

	var gx0 := p.x + 52.0
	var gx1 := p.x + w - 22.0
	var gy0 := p.y + 66.0
	var gy1 := p.y + h - 62.0
	var gw := gx1 - gx0
	var gh := gy1 - gy0
	var want: String = _ore_order[_sel]
	var tint := _ore_col(want)
	var grid := Color(0.56, 0.86, 0.95, 0.13)
	var grid_hi := Color(0.56, 0.86, 0.95, 0.30)

	# Title and ore tuning chips.
	_draw.draw_rect(Rect2(p.x + 16.0, p.y + 18.0, 3.0, 20.0), UiTokens.ACCENT)
	_draw.draw_string(font, Vector2(p.x + 26.0, p.y + 34.0), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTokens.TEXT)
	var cx := p.x + 110.0
	for i in _ore_order.size():
		var id: String = _ore_order[i]
		var count := 0
		for c in _contacts:
			if c["name"] == id:
				count += 1
		var label := "%d %s" % [i + 1, id.to_upper()]
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var chip := Rect2(cx, p.y + 16.0, tw + 36.0, 24.0)
		var oc := _ore_col(id)
		if i == _sel:
			var fill := oc
			fill.a = 0.22
			_draw.draw_rect(chip, fill)
			_draw.draw_rect(chip, oc, false, 1.0)
		_draw.draw_circle(Vector2(chip.position.x + 11.0, chip.position.y + 12.0), 3.5,
			oc if count > 0 else Color(oc, 0.35))
		_draw.draw_string(font, Vector2(chip.position.x + 20.0, chip.position.y + 17.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTokens.TEXT if i == _sel else UiTokens.TEXT_DIM)
		cx += chip.size.x + 6.0

	# Scope field.
	_draw.draw_rect(Rect2(gx0, gy0, gw, gh), Color(0.0, 0.02, 0.03, 0.55))
	# Lock band either side of the centre line.
	var band := gw * (LOCK_DEG / 180.0)
	var mid := gx0 + gw * 0.5
	_draw.draw_rect(Rect2(mid - band, gy0, band * 2.0, gh), Color(tint, 0.07))
	# Bearing lines every 30 degrees.
	for k in range(-3, 4):
		var x := mid + gw * (float(k) * 30.0 / 180.0)
		_draw.draw_line(Vector2(x, gy0), Vector2(x, gy1), grid_hi if k == 0 else grid, 1.0)
		var t := "0" if k == 0 else ("%d" % absi(k * 30))
		_draw.draw_string(font, Vector2(x - 12.0, gy1 + 16.0), t, HORIZONTAL_ALIGNMENT_CENTER, 24.0, 11, UiTokens.TEXT_FAINT)
	_draw.draw_string(font, Vector2(gx0 - 2.0, gy1 + 30.0), "LEFT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTokens.TEXT_FAINT)
	_draw.draw_string(font, Vector2(gx1 - 30.0, gy1 + 30.0), "RIGHT", HORIZONTAL_ALIGNMENT_RIGHT, 30.0, 10, UiTokens.TEXT_FAINT)
	# Range lines (square-root scale so the near ground gets room).
	for m in [200.0, 500.0, 1000.0, 1500.0]:
		var y := gy1 - sqrt(m / RANGE_M) * gh
		_draw.draw_line(Vector2(gx0, y), Vector2(gx1, y), grid, 1.0)
		_draw.draw_string(font, Vector2(p.x + 8.0, y + 4.0), fmt_dist(m), HORIZONTAL_ALIGNMENT_LEFT, 42.0, 10, UiTokens.TEXT_FAINT)

	# A little scope static.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_elapsed * 14.0)
	for i in 36:
		_draw.draw_rect(Rect2(gx0 + rng.randf() * gw, gy0 + rng.randf() * gh, 2, 1), Color(0.6, 0.9, 1.0, 0.07 + rng.randf() * 0.08))

	# Sweep bar with a fading wake behind it.
	var sx := gx0 + _sweep * gw
	var wake := minf(130.0, sx - gx0)
	if wake > 1.0:
		_draw.draw_polygon(
			PackedVector2Array([Vector2(sx - wake, gy0), Vector2(sx, gy0), Vector2(sx, gy1), Vector2(sx - wake, gy1)]),
			PackedColorArray([Color(tint, 0.0), Color(tint, 0.26), Color(tint, 0.26), Color(tint, 0.0)]))
	_draw.draw_line(Vector2(sx, gy0), Vector2(sx, gy1), Color(1.0, 1.0, 1.0, 0.85), 2.0)

	# Traces.
	var cand := _candidate()
	var shown := 0
	for c in _contacts:
		if c["name"] != want:
			continue
		var b := _bearing_deg(cam, c["position"])
		if absf(b) > 90.0:
			continue
		var d := _dist_to(c["position"])
		var x := mid + gw * (b / 180.0)
		var y := gy1 - sqrt(clampf(d / RANGE_M, 0.0, 1.0)) * gh
		var lit: float = c["lit"]
		var r := 3.0 + minf(sqrt(float(c["samples"])), 6.0)
		if lit > 0.01:
			shown += 1
			var smear := 8.0 + 18.0 * lit
			_draw.draw_line(Vector2(x, y - smear), Vector2(x, y + smear), Color(tint, 0.35 * lit), 2.0)
			_draw.draw_circle(Vector2(x, y), r * (1.0 + 0.5 * lit), Color(tint, 0.25 * lit))
			_draw.draw_circle(Vector2(x, y), r, Color(tint, 0.35 + 0.65 * lit))
			_draw.draw_string(font, Vector2(x + r + 4.0, y + 4.0), fmt_dist(d),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(UiTokens.TEXT, minf(lit * 1.5, 1.0)))
		else:
			_draw.draw_circle(Vector2(x, y), 2.0, Color(tint, 0.18))
		if not cand.is_empty() and cand == c:
			var q := r + 8.0
			var bc := Color(UiTokens.TEXT, 0.9)
			for sgn in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var corner: Vector2 = Vector2(x, y) + sgn * q
				_draw.draw_line(corner, corner - Vector2(sgn.x * 7.0, 0.0), bc, 2.0)
				_draw.draw_line(corner, corner - Vector2(0.0, sgn.y * 7.0), bc, 2.0)
	# Centre line on top.
	_draw.draw_line(Vector2(mid, gy0), Vector2(mid, gy1), Color(tint, 0.55), 1.0)

	# Footer.
	var foot := "WHEEL / 1-%d  tune     LMB/RMB scanner button  lock     X  close" % _ore_order.size()
	var fcol := UiTokens.TEXT_DIM
	if _contacts.is_empty() or not _contacts.any(func(c): return c["name"] == want):
		foot = "No %s within reach. Move on and ping again." % want
		fcol = UiTokens.WARN
	elif not cand.is_empty():
		foot = "Trace on the line: press the scanner button to LOCK"
		fcol = UiTokens.GOOD
	_draw.draw_string(font, Vector2(p.x + 16.0, p.y + h - 12.0), foot, HORIZONTAL_ALIGNMENT_LEFT, w - 32.0, 12, fcol)

func _draw_guide(size: Vector2, font: Font) -> void:
	var cam := _camera()
	if cam == null:
		return
	var pos: Vector3 = _lock["position"]
	var id: String = _lock["name"]
	var col := _ore_col(id)
	var d := cam.global_position.distance_to(pos)
	var centre := size * 0.5
	var behind := cam.is_position_behind(pos)
	var sp := cam.unproject_position(pos)
	if behind:
		sp = centre - (sp - centre)
	var margin := 80.0
	var inside := (not behind) and sp.x > margin and sp.x < size.x - margin and sp.y > margin and sp.y < size.y - margin
	var arrived := d < 30.0

	if inside:
		# Beacon: a diamond on the target with a tall line above it, so it can be seen from a long way off.
		var s := 13.0
		var pts := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0), sp + Vector2(0, -s)])
		_draw.draw_polyline(pts, col, 2.5, true)
		_draw.draw_circle(sp, 3.0, col)
		_draw.draw_line(sp + Vector2(0, -s - 4.0), sp + Vector2(0, -s - 70.0), Color(col, 0.7), 2.0)
		var lab := ("DIG HERE" if arrived else id.to_upper())
		_draw.draw_string(font, sp + Vector2(-80, s + 22.0), lab, HORIZONTAL_ALIGNMENT_CENTER, 160.0, 15, UiTokens.TEXT)
		_draw.draw_string(font, sp + Vector2(-80, s + 42.0), "≈ " + fmt_dist(d), HORIZONTAL_ALIGNMENT_CENTER, 160.0, 18, col)
		if d < 400.0 and _ore_depths.has(id):
			var dep: Vector2 = _ore_depths[id]
			_draw.draw_string(font, sp + Vector2(-90, s + 60.0), "dig %d-%d m down" % [int(dep.x), int(dep.y)],
				HORIZONTAL_ALIGNMENT_CENTER, 180.0, 12, UiTokens.TEXT_DIM)
	else:
		# Off screen: an arrow on the screen edge pointing the way, with the distance beside it.
		var dir := (sp - centre)
		if dir.length() < 1.0:
			dir = Vector2.DOWN
		dir = dir.normalized()
		var half := size * 0.5 - Vector2(margin, margin)
		var k := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
		var ep := centre + dir * k
		var perp := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([ep + dir * 20.0, ep - dir * 12.0 + perp * 15.0, ep - dir * 12.0 - perp * 15.0])
		_draw.draw_colored_polygon(tri, col)
		var tx := clampf(ep.x - 60.0, 10.0, size.x - 130.0)
		var ty := clampf(ep.y + (30.0 if dir.y < 0.0 else -22.0), 40.0, size.y - 30.0)
		_draw.draw_string(font, Vector2(tx, ty), id.to_upper() + "  ≈ " + fmt_dist(d), HORIZONTAL_ALIGNMENT_CENTER, 140.0, 14, UiTokens.TEXT)

	# Top card: what you are chasing, how far, and how much of the way is done.
	var cw := 340.0
	var cp := Vector2(size.x * 0.5 - cw * 0.5, 58.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.04, 0.055, 0.7)
	sb.border_color = UiTokens.LINE
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = UiTokens.CORNER_BIG
	sb.corner_radius_bottom_right = UiTokens.CORNER_BIG
	sb.corner_radius_top_right = UiTokens.CORNER_SMALL
	sb.corner_radius_bottom_left = UiTokens.CORNER_SMALL
	_draw.draw_style_box(sb, Rect2(cp, Vector2(cw, 62.0)))
	_draw.draw_rect(Rect2(cp.x + 14.0, cp.y + 14.0, 3.0, 22.0), col)
	_draw.draw_string(font, cp + Vector2(26.0, 25.0), "LOCKED  " + id.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTokens.TEXT)
	_draw.draw_string(font, cp + Vector2(cw - 150.0, 30.0), ("ON TARGET" if arrived else "≈ " + fmt_dist(d)),
		HORIZONTAL_ALIGNMENT_RIGHT, 134.0, 20, col)
	var prog := clampf(1.0 - d / float(_lock["start_dist"]), 0.0, 1.0)
	_draw.draw_rect(Rect2(cp.x + 14.0, cp.y + 46.0, cw - 28.0, 3.0), Color(1, 1, 1, 0.12))
	_draw.draw_rect(Rect2(cp.x + 14.0, cp.y + 46.0, (cw - 28.0) * prog, 3.0), col)
	_draw.draw_string(font, cp + Vector2(0, 76.0), "X  drop lock", HORIZONTAL_ALIGNMENT_CENTER, cw, 11, UiTokens.TEXT_FAINT)

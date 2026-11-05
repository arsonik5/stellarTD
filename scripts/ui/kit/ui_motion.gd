class_name UiMotion
## anime.js-style motion for Godot UI (docs/game/ux-bible.md, "Motion"). Same model as anime.js v3, so motion
## ideas from the web carry over one to one:
##
##   UiMotion.animate(targets, {"modulate:a": [0.0, 1.0], "x": [-14, 0]},
##       {"duration": 0.5, "delay": UiMotion.stagger(0.03), "easing": "outExpo"})
##
## - targets: one CanvasItem or an Array of them
## - props: property path -> [from, to] or just `to` (from = current value). Floats, Vector2/3, Colors.
##   Shorthands: "x" / "y" move relative to where the layout put the control (translateX / translateY),
##   "opacity" = modulate:a, "scale" accepts a float.
## - opts: duration (s, default 0.5), delay (float or a stagger Callable), easing (name, default "outExpo"),
##   on_complete (Callable, after the last target finishes)
## - easings: linear, in/out/inOut x Quad Cubic Quart Quint Sine Expo Circ Back Bounce, inElastic(a, p) /
##   outElastic(a, p) / inOutElastic(a, p), spring(mass, stiffness, damping, velocity) - its duration is the
##   real settle time, like anime.js, so a "duration" passed with a spring is ignored.
## Every tween is bound to its target: a freed control just drops its animation.

const DEFAULT_DURATION := 0.5
const DEFAULT_EASING := "outExpo"

# --- stagger --------------------------------------------------------------------------------------------
## anime.stagger(value, {start, from, ease}): delay for target i of n. from = "first" | "center" | "last" | index.
static func stagger(step: float, opts: Dictionary = {}) -> Callable:
	var start: float = opts.get("start", 0.0)
	var from: Variant = opts.get("from", "first")
	var ease_name: String = opts.get("ease", "")
	return func(i: int, n: int) -> float:
		var origin := 0.0
		if from is String:
			origin = {"first": 0.0, "center": (n - 1) * 0.5, "last": float(n - 1)}.get(from, 0.0)
		else:
			origin = float(from)
		var d := absf(float(i) - origin)
		var max_d := maxf(origin, float(n - 1) - origin)
		if ease_name != "" and max_d > 0.0:
			d = easing(ease_name).call(d / max_d) * max_d
		return start + d * step

# --- animate --------------------------------------------------------------------------------------------
static func animate(targets: Variant, props: Dictionary, opts: Dictionary = {}) -> void:
	var list: Array = targets if targets is Array else [targets]
	list = list.filter(func(t: Variant) -> bool: return t is Object and is_instance_valid(t))
	if list.is_empty():
		return
	# translateX/Y is relative to where the container puts the control, so wait one frame for that layout;
	# meanwhile apply the starting opacity so nothing flashes in at full strength
	if (props.has("x") or props.has("y")) and not opts.get("_laid_out", false):
		for t: CanvasItem in list:
			for k in ["opacity", "modulate:a"]:
				if props.has(k) and props[k] is Array:
					t.modulate.a = float(props[k][0])
		var tree := (list[0] as CanvasItem).get_tree()
		if tree == null:
			return
		var o := opts.duplicate()
		o["_laid_out"] = true
		# the layout position is remembered the first time a control is moved (its rest position); call
		# UiMotion.rebase(control) if a container later moves it somewhere else for good
		tree.process_frame.connect(func() -> void: animate(list, props, o), CONNECT_ONE_SHOT)
		return
	var n := list.size()
	var ease_name: String = opts.get("easing", DEFAULT_EASING)
	var f := easing(ease_name)
	var dur: float = spring_duration(ease_name) if ease_name.begins_with("spring") else float(opts.get("duration", DEFAULT_DURATION))
	var delay_v: Variant = opts.get("delay", 0.0)
	var done: Callable = opts.get("on_complete", Callable())
	var last_end := -1.0
	var last_i := 0
	for i in n:
		var d: float = (delay_v as Callable).call(i, n) if delay_v is Callable else float(delay_v)
		if d + dur > last_end:
			last_end = d + dur
			last_i = i
	for i in n:
		var t: CanvasItem = list[i]
		var d: float = (delay_v as Callable).call(i, n) if delay_v is Callable else float(delay_v)
		var tracks := _tracks(t, props)
		# apply the "from" values now, so nothing flashes at its end state during the delay
		for tr: Array in tracks:
			t.set_indexed(tr[0], tr[1])
		var key := "_uimotion_" + "_".join(props.keys()).replace(":", "_").replace("/", "_")
		# get_meta(key, null) still errors when the key is missing (null = "no default"), so test first
		var old: Tween = t.get_meta(key) if t.has_meta(key) else null
		if old != null and old.is_valid():
			old.kill()
		var tw := t.create_tween()
		t.set_meta(key, tw)
		if d > 0.0:
			tw.tween_interval(d)
		tw.tween_method(func(k: float) -> void:
			if not is_instance_valid(t):
				return
			var e: float = f.call(k)
			for tr: Array in tracks:
				t.set_indexed(tr[0], _mix(tr[1], tr[2], e)), 0.0, 1.0, maxf(dur, 0.001))
		if i == last_i and done.is_valid():
			tw.tween_callback(done)

## Resolve shorthands and [from, to] pairs into [path, from, to] tracks.
static func _tracks(t: CanvasItem, props: Dictionary) -> Array:
	var out: Array = []
	for k: String in props:
		var v: Variant = props[k]
		var path := k
		var base: Variant = null
		match k:
			"opacity":
				path = "modulate:a"
			"x":
				path = "position:x"
				base = t.get_meta("_uimotion_base_x", (t as Control).position.x if t is Control else 0.0)
				t.set_meta("_uimotion_base_x", base)
			"y":
				path = "position:y"
				base = t.get_meta("_uimotion_base_y", (t as Control).position.y if t is Control else 0.0)
				t.set_meta("_uimotion_base_y", base)
			"scale":
				path = "scale"
		var from: Variant
		var to: Variant
		if v is Array:
			from = v[0]
			to = v[1]
		else:
			from = t.get_indexed(NodePath(path))
			to = v
		if path == "scale" and (from is float or from is int):
			from = Vector2(from, from)
		if path == "scale" and (to is float or to is int):
			to = Vector2(to, to)
		if base != null:
			from = float(base) + float(from)
			to = float(base) + float(to)
		out.append([NodePath(path), from, to])
	return out

## Forget the remembered layout position of a control (call after its container re-sorted it).
static func rebase(c: Control) -> void:
	c.remove_meta("_uimotion_base_x")
	c.remove_meta("_uimotion_base_y")

static func _mix(a: Variant, b: Variant, t: float) -> Variant:
	if a is float or a is int:
		return lerpf(float(a), float(b), t)
	return a.lerp(b, t)

# --- easing ---------------------------------------------------------------------------------------------
static var _cache := {}

## "outExpo", "inOutBack", "outElastic(1, .6)", "spring(1, 80, 10, 0)" -> Callable(t: float) -> float
static func easing(name: String) -> Callable:
	if _cache.has(name):
		return _cache[name]
	var f: Callable
	var args: Array = []
	var base := name
	var p := name.find("(")
	if p >= 0:
		base = name.substr(0, p)
		for s in name.substr(p + 1, name.length() - p - 2).split(","):
			args.append(float(s.strip_edges()))
	if base == "linear":
		f = func(t: float) -> float: return t
	elif base == "spring":
		f = _spring(args)
	elif base.begins_with("inOut"):
		var fi := _in(base.substr(5), args)
		f = func(t: float) -> float: return fi.call(t * 2.0) * 0.5 if t < 0.5 else 1.0 - fi.call(-2.0 * t + 2.0) * 0.5
	elif base.begins_with("in"):
		f = _in(base.substr(2), args)
	elif base.begins_with("out"):
		var fo := _in(base.substr(3), args)
		f = func(t: float) -> float: return 1.0 - fo.call(1.0 - t)
	else:
		push_warning("UiMotion: unknown easing '%s', using outExpo" % name)
		return easing("outExpo")
	_cache[name] = f
	return f

## The "in" form of each Penner curve (anime.js's set); out and inOut are derived from it.
static func _in(kind: String, args: Array) -> Callable:
	match kind:
		"Quad": return func(t: float) -> float: return t * t
		"Cubic": return func(t: float) -> float: return t * t * t
		"Quart": return func(t: float) -> float: return t * t * t * t
		"Quint": return func(t: float) -> float: return t * t * t * t * t
		"Sine": return func(t: float) -> float: return 1.0 - cos(t * PI * 0.5)
		"Expo": return func(t: float) -> float: return 0.0 if t <= 0.0 else pow(2.0, 10.0 * t - 10.0)
		"Circ": return func(t: float) -> float: return 1.0 - sqrt(maxf(1.0 - t * t, 0.0))
		"Back": return func(t: float) -> float: return t * t * (2.70158 * t - 1.70158)
		"Bounce":
			return func(t: float) -> float:
				var pow2: float
				var b := 4.0
				t = 1.0 - t
				pow2 = pow(2.0, b)
				while t < (pow2 - 1.0) / 11.0:
					b -= 1.0
					pow2 = pow(2.0, b)
				return 1.0 - (1.0 / pow(4.0, 3.0 - b) - 7.5625 * pow((pow2 * 3.0 - 2.0) / 22.0 - t, 2.0))
		"Elastic":
			var a := clampf(args[0] if args.size() > 0 else 1.0, 1.0, 10.0)
			var per := clampf(args[1] if args.size() > 1 else 0.5, 0.1, 2.0)
			return func(t: float) -> float:
				if t <= 0.0 or t >= 1.0:
					return t
				return -a * pow(2.0, 10.0 * (t - 1.0)) * sin(((t - 1.0) - (per / TAU * asin(1.0 / a))) * TAU / per)
	push_warning("UiMotion: unknown curve '%s'" % kind)
	return func(t: float) -> float: return t

## Damped spring, anime.js v3 formula. Progress is over the real settle time (spring_duration).
static func _spring(args: Array) -> Callable:
	var mass := clampf(args[0] if args.size() > 0 else 1.0, 0.1, 100.0)
	var stiffness := clampf(args[1] if args.size() > 1 else 100.0, 0.1, 100.0)
	var damping := clampf(args[2] if args.size() > 2 else 10.0, 0.1, 100.0)
	var velocity := clampf(args[3] if args.size() > 3 else 0.0, 0.1, 100.0) if args.size() > 3 else 0.0
	var settle := _spring_settle(mass, stiffness, damping, velocity)
	return func(t: float) -> float:
		if t <= 0.0 or t >= 1.0:
			return clampf(t, 0.0, 1.0)
		return _spring_at(t * settle, mass, stiffness, damping, velocity)

static func _spring_at(s: float, mass: float, stiffness: float, damping: float, velocity: float) -> float:
	var w0 := sqrt(stiffness / mass)
	var zeta := damping / (2.0 * sqrt(stiffness * mass))
	var wd := w0 * sqrt(1.0 - zeta * zeta) if zeta < 1.0 else 0.0
	var b := (zeta * w0 - velocity) / wd if zeta < 1.0 else -velocity + w0
	var p: float
	if zeta < 1.0:
		p = exp(-s * zeta * w0) * (cos(wd * s) + b * sin(wd * s))
	else:
		p = (1.0 + b * s) * exp(-s * w0)
	return 1.0 - p

static var _settle_cache := {}

static func _spring_settle(mass: float, stiffness: float, damping: float, velocity: float) -> float:
	var key := "%f/%f/%f/%f" % [mass, stiffness, damping, velocity]
	if _settle_cache.has(key):
		return _settle_cache[key]
	# walk forward until the spring stays within 0.1 % of rest for 16 consecutive 1/60 s steps (as anime.js)
	var s := 0.0
	var rest := 0
	while s < 10.0:
		s += 1.0 / 60.0
		if absf(1.0 - _spring_at(s, mass, stiffness, damping, velocity)) < 0.001:
			rest += 1
			if rest >= 16:
				break
		else:
			rest = 0
	_settle_cache[key] = s
	return s

## Seconds a "spring(...)" easing name takes to settle.
static func spring_duration(name: String) -> float:
	var args: Array = []
	var p := name.find("(")
	if p >= 0:
		for s in name.substr(p + 1, name.length() - p - 2).split(","):
			args.append(float(s.strip_edges()))
	var mass := clampf(args[0] if args.size() > 0 else 1.0, 0.1, 100.0)
	var stiffness := clampf(args[1] if args.size() > 1 else 100.0, 0.1, 100.0)
	var damping := clampf(args[2] if args.size() > 2 else 10.0, 0.1, 100.0)
	var velocity := clampf(args[3] if args.size() > 3 else 0.0, 0.1, 100.0) if args.size() > 3 else 0.0
	return _spring_settle(mass, stiffness, damping, velocity)

# --- keyframes ------------------------------------------------------------------------------------------
## anime.js keyframes for one property: e.g. a "no" shake: UiMotion.keys(c, "x", [-8, 8, -5, 5, -2, 0], 0.32)
static func keys(t: CanvasItem, prop: String, values: Array, duration: float, ease_name: String = "outQuad") -> void:
	if not is_instance_valid(t) or values.is_empty():
		return
	var rel := prop in ["x", "y"]
	var path := NodePath("position:" + prop) if rel else NodePath(prop)
	var key := "_uimotion_keys_" + prop
	var old: Tween = t.get_meta(key) if t.has_meta(key) else null
	if old != null and old.is_valid():
		old.kill()
		if rel:
			t.set_indexed(path, float(t.get_meta(key + "_base", t.get_indexed(path))))
	var base: float = float(t.get_indexed(path)) if rel else 0.0
	t.set_meta(key + "_base", base)
	var f := easing(ease_name)
	var seg := duration / float(values.size())
	var tw := t.create_tween()
	t.set_meta(key, tw)
	var prev: float = 0.0 if rel else float(t.get_indexed(path))
	for v in values:
		var a := prev
		var b := float(v)
		tw.tween_method(func(k: float) -> void:
			if is_instance_valid(t):
				t.set_indexed(path, base + lerpf(a, b, f.call(k))), 0.0, 1.0, seg)
		prev = b

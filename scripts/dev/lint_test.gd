extends Node
## Lint: compiles EVERY script under res://scripts inside the running project (autoloads and class names
## resolved), and instantiates every scene under res://scenes except dev scenes. Catches parse errors in files
## no other suite happens to load (a broken HUD script once passed every planet-free suite). ~5 s, headless.
##   godot --headless --path . res://scenes/dev/lint_test.tscn
var _fails := 0
## Already broken before the lint existed and owned elsewhere - listed so the lint guards everything else.
## Fix and remove from here: erosion_* are terrain dev tools (call the coroutine bake() without await);
## verify_counts.gd is a stray analysis script calling String.strip().
const KNOWN_BROKEN := ["res://scripts/dev/erosion_aniso.gd", "res://scripts/dev/erosion_masks.gd",
	"res://scripts/dev/erosion_sweep.gd", "res://scripts/player/verify_counts.gd"]

func _ready() -> void:
	var scripts := _walk("res://scripts", ".gd").filter(func(p: String) -> bool: return not KNOWN_BROKEN.has(p))
	print("SKIP %d known-broken scripts: %s" % [KNOWN_BROKEN.size(), ", ".join(KNOWN_BROKEN)])
	for path in scripts:
		var s := load(path) as Script
		if s == null or not s.can_instantiate() and not path.ends_with("_probe_methods.gd"):
			_fail("script does not compile: " + path)
	var scenes := _walk("res://scenes", ".tscn").filter(func(p: String) -> bool: return not p.begins_with("res://scenes/dev"))
	var ok := 0
	for path in scenes:
		var ps := load(path) as PackedScene
		if ps == null:
			_fail("scene does not load: " + path)
			continue
		var inst := ps.instantiate()
		if inst == null:
			_fail("scene does not instantiate: " + path)
			continue
		ok += 1
		inst.free()
	print("PASS %d scripts compile" % (scripts.size() - _fails))
	print("PASS %d scenes instantiate" % ok)
	print("LINT DONE fails=%d" % _fails)
	get_tree().quit(_fails)

func _fail(msg: String) -> void:
	print("FAIL " + msg)
	_fails += 1

func _walk(dir: String, ext: String) -> Array:
	var out := []
	for f in ResourceLoader.list_directory(dir):
		var p := dir + "/" + f.trim_suffix("/")
		if f.ends_with("/"):
			out.append_array(_walk(p, ext))
		elif f.ends_with(ext):
			out.append(p)
	return out

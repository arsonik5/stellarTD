class_name TerrainLog
extends RefCounted

## Toggleable diagnostics for world generation, in one place.
##
## Exists because every terrain question so far - how long a planet takes to
## become walkable, what the profile derived, whether the graph compiled, which
## materials actually reach the surface - was answered by writing a throwaway
## harness scene. Those harnesses measure a slightly different thing each time
## and none of them survive the session. This logs the same numbers from the
## real game, so a question is answered by reading a file instead of building an
## instrument.
##
## OFF by default and cheap when off: every entry point returns immediately, and
## the strings are built inside the guard so a disabled log costs one bool test.
##
## Turn it on with any of:
##     godot --path . -- --terrain-log          (user args, after the -- )
##     STELLAR_TERRAIN_LOG=1 godot --path .
##     TerrainLog.enabled = true                (from code, e.g. a test)

const LOG_PATH := "user://logs/terrain.log"
const FLAG := "--terrain-log"
const ENV_VAR := "STELLAR_TERRAIN_LOG"
const COST_FLAG := "--terrain-cost"
const COST_ENV := "STELLAR_TERRAIN_COST"

static var enabled: bool = _detect()
## Also mirror to stdout. Off when only the file matters (a long session would
## otherwise drown the console).
static var to_stdout: bool = true
## Per-voxel cost measurement. Separate from `enabled` because it is not an
## observation - it generates blocks purely to time them, and measured 8.5 s PER
## BODY at 8 km. Left on by default it would dominate the very load time it is
## supposed to be reporting.
##     godot --path . -- --terrain-log --terrain-cost
static var measure_cost: bool = _detect_flag(COST_FLAG, COST_ENV)

static var _file: FileAccess = null
static var _start_ms: int = 0

static func _detect() -> bool:
	return _detect_flag(FLAG, ENV_VAR)

static func _detect_flag(flag: String, env_var: String) -> bool:
	if OS.get_environment(env_var) == "1":
		return true
	return OS.get_cmdline_user_args().has(flag) or OS.get_cmdline_args().has(flag)

## Starts a fresh log. Safe to call more than once; later calls are ignored so
## a reloaded scene does not truncate the run that is already being recorded.
static func begin(context: String = "") -> void:
	if not enabled or _file != null:
		return
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(LOG_PATH).get_base_dir())
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_start_ms = Time.get_ticks_msec()
	write("run", "%s  %s" % [Time.get_datetime_string_from_system(), context])
	write("run", "path %s" % ProjectSettings.globalize_path(LOG_PATH))

## One line, prefixed with elapsed time and a section tag.
static func write(section: String, message: String) -> void:
	if not enabled:
		return
	if _file == null:
		begin()
	var line := "[%7.2fs] %-9s %s" % [
		float(Time.get_ticks_msec() - _start_ms) / 1000.0, section, message]
	if _file != null:
		_file.store_line(line)
		# Flushed every line on purpose: the questions this answers are mostly
		# about runs that hang or crash, and a buffered log loses exactly the
		# tail that explains why.
		_file.flush()
	if to_stdout:
		print(line)

## Key/value block, so a dump of many related numbers stays readable.
static func write_fields(section: String, title: String, fields: Dictionary) -> void:
	if not enabled:
		return
	write(section, title)
	var keys := fields.keys()
	keys.sort()
	for k in keys:
		write(section, "    %-22s %s" % [k, fields[k]])

static func close() -> void:
	if _file != null:
		_file.close()
		_file = null

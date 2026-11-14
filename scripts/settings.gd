extends Node
## Player settings (autoload "GameSettings"): one table of options, stored in user://settings.cfg, applied the moment
## they change. The settings screen (scripts/ui/settings_panel.gd) is built from SPEC, so a new option is one entry
## here plus whatever reads it - never a hand-made widget. Gameplay code reads values with GameSettings.get_value()
## and listens to `changed` if it caches anything.

signal changed(key: String)

const PATH := "user://settings.cfg"

## key: [page, label, kind, default, extra, help]. kind: "slider" (extra = [min, max, step, suffix]),
## "toggle", "choice" (extra = option labels; the value is the index).
const SPEC := {
	"window_mode": ["Video", "Display mode", "choice", 0, ["Windowed", "Borderless fullscreen", "Fullscreen"], ""],
	"vsync": ["Video", "V-Sync", "toggle", true, null, "Stops tearing. Turn off for the lowest input delay."],
	"max_fps": ["Video", "Frame rate limit", "choice", 0, ["Unlimited", "30", "60", "120", "144", "240"], ""],
	"fov": ["Video", "Field of view", "slider", 75.0, [60.0, 110.0, 1.0, " deg"], "Vertical. 75 is the default."],
	"msaa": ["Video", "Anti-aliasing", "choice", 2, ["Off", "2x MSAA", "4x MSAA", "8x MSAA"], "Edges of distant terrain shimmer without it."],
	"shadows": ["Video", "Shadow quality", "choice", 2, ["Low", "Medium", "High"], ""],
	"ui_scale": ["Video", "Interface size", "slider", 1.0, [0.8, 1.5, 0.05, "x"], ""],
	"vol_master": ["Audio", "Master volume", "slider", 0.8, [0.0, 1.0, 0.05, ""], ""],
	"vol_music": ["Audio", "Music", "slider", 0.6, [0.0, 1.0, 0.05, ""], ""],
	"vol_sfx": ["Audio", "Effects", "slider", 0.8, [0.0, 1.0, 0.05, ""], ""],
	"vol_ui": ["Audio", "Interface sounds", "slider", 0.7, [0.0, 1.0, 0.05, ""], ""],
	"mouse_sens": ["Controls", "Mouse sensitivity", "slider", 1.0, [0.2, 3.0, 0.05, "x"], ""],
	"invert_y": ["Controls", "Invert look up/down", "toggle", false, null, ""],
	"head_bob": ["Gameplay", "Head bob", "slider", 1.0, [0.0, 1.0, 0.05, ""], "Camera and tool motion while walking. Lower it if it makes you queasy."],
	"tool_sway": ["Gameplay", "Tool sway", "slider", 1.0, [0.0, 1.0, 0.05, ""], "How much held tools lag behind your aim."],
	"key_hints": ["Gameplay", "Key hints", "toggle", true, null, "Small key prompts on the HUD."],
	"raids": ["Gameplay", "Raids", "choice", 2, ["Off", "Calm", "Normal", "Relentless"], "How often the aliens come when your signature is loud. Off: build in peace (scouts still look)."],
}
const PAGES := ["Video", "Audio", "Controls", "Gameplay"]
const BUSES := ["Music", "SFX", "UI"]
const FPS_CHOICES := [0, 30, 60, 120, 144, 240]

var _values := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in SPEC:
		_values[k] = SPEC[k][3]
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for k in SPEC:
			if cfg.has_section_key("settings", k):
				_values[k] = cfg.get_value("settings", k)
	_ensure_buses()
	for k in SPEC:
		_apply(k)

func get_value(key: String) -> Variant:
	return _values.get(key, SPEC[key][3] if SPEC.has(key) else null)

func set_value(key: String, value: Variant) -> void:
	if not SPEC.has(key) or _values.get(key) == value:
		return
	_values[key] = value
	_apply(key)
	_save()
	changed.emit(key)

func reset_page(page: String) -> void:
	for k in SPEC:
		if SPEC[k][0] == page:
			set_value(k, SPEC[k][3])

func _save() -> void:
	var cfg := ConfigFile.new()
	for k in _values:
		cfg.set_value("settings", k, _values[k])
	cfg.save(PATH)

## Audio buses exist from the start so every sound added later has a slider to answer to.
func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

func _apply(key: String) -> void:
	var v: Variant = _values[key]
	match key:
		"window_mode":
			if DisplayServer.get_name() == "headless":
				return
			var modes := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
			var want: int = modes[clampi(int(v), 0, 2)]
			# the game starts windowed; only touch the window when the player has chosen something else
			if DisplayServer.window_get_mode() != want and not (want == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
				DisplayServer.window_set_mode(want)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = FPS_CHOICES[clampi(int(v), 0, FPS_CHOICES.size() - 1)]
		"msaa":
			get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(int(v), 0, 3)]
		"shadows":
			RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][clampi(int(v), 0, 2)], true)
		"ui_scale":
			get_tree().root.content_scale_factor = float(v)
		"vol_master":
			_set_bus("Master", float(v))
		"vol_music":
			_set_bus("Music", float(v))
		"vol_sfx":
			_set_bus("SFX", float(v))
		"vol_ui":
			_set_bus("UI", float(v))
		_:
			pass                         # read on demand by the systems that use them (fov, mouse, bob, ...)

func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)

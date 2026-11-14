extends Node2D

## P0.1 lit-sprite check (pivot-2d.md D11): one machine sprite as albedo + normal map (+ emissive) on lit ground,
## a sun that walks around it, a point light at the furnace, a shadow cast along the sun. Saves four frames
## (morning, noon, evening, night) and a contact sheet, then quits.
##   godot --path . res://scenes/dev/lit_test.tscn -- --sprite=art_src/style_lock/lit/obj_smelter
## (`--sprite` = path stem without extension; expects <stem>.png, <stem>_n.png, optional <stem>_e.png)

var sprite_stem := "art_src/style_lock/lit/obj_smelter"
var sun: DirectionalLight2D
var shadow: Sprite2D
var body: Sprite2D
var glow: Sprite2D
var lamp: PointLight2D
var canvas_mod: CanvasModulate
const SHOTS := [
	{"name": "morning", "angle": -60.0, "energy": 0.9, "tint": Color(1.0, 0.85, 0.7), "ambient": Color(0.55, 0.5, 0.5)},
	{"name": "noon", "angle": 0.0, "energy": 1.1, "tint": Color(1.0, 0.97, 0.92), "ambient": Color(0.62, 0.62, 0.66)},
	{"name": "evening", "angle": 65.0, "energy": 0.85, "tint": Color(1.0, 0.7, 0.5), "ambient": Color(0.45, 0.4, 0.45)},
	{"name": "night", "angle": 120.0, "energy": 0.15, "tint": Color(0.6, 0.7, 1.0), "ambient": Color(0.16, 0.18, 0.26)},
]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sprite="):
			sprite_stem = a.substr(9)
	RenderingServer.set_default_clear_color(Color.BLACK)
	var root := ProjectSettings.globalize_path("res://")
	var albedo := _tex(root + sprite_stem + ".png")
	var normal := _tex(root + sprite_stem + "_n.png")
	var emissive := _tex(root + sprite_stem + "_e.png")
	if albedo == null or normal == null:
		push_error("lit_test: missing %s(.png/_n.png)" % sprite_stem)
		get_tree().quit(1)
		return

	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	canvas_mod = CanvasModulate.new()
	add_child(canvas_mod)

	# ground: a lit flat plane with a little relief so the sun angle shows on it too
	var ground := Sprite2D.new()
	var gt := CanvasTexture.new()
	gt.diffuse_texture = _flat_tex(Color(0.62, 0.55, 0.47), 512)
	gt.normal_texture = _noise_normal(512)
	gt.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.texture = gt
	ground.region_enabled = true
	ground.region_rect = Rect2(0, 0, 1600, 1000)
	add_child(ground)

	shadow = Sprite2D.new()
	shadow.texture = albedo
	shadow.modulate = Color(0, 0, 0, 0.45)
	var sm := CanvasItemMaterial.new()
	sm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	shadow.material = sm
	add_child(shadow)

	body = Sprite2D.new()
	var bt := CanvasTexture.new()
	bt.diffuse_texture = albedo
	bt.normal_texture = normal
	bt.specular_color = Color(0.5, 0.5, 0.5)
	bt.specular_shininess = 0.6
	body.texture = bt
	add_child(body)

	if emissive != null:
		glow = Sprite2D.new()
		glow.texture = emissive
		var gm := CanvasItemMaterial.new()
		gm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = gm
		add_child(glow)

	sun = DirectionalLight2D.new()
	sun.height = 0.55        # how steep the light comes in: lower = longer relief shading
	add_child(sun)

	lamp = PointLight2D.new()
	lamp.texture = _radial(256)
	lamp.color = Color(1.0, 0.6, 0.3)
	lamp.texture_scale = 2.0
	lamp.height = 40.0
	lamp.position = Vector2(0, body.texture.get_height() * 0.25)
	add_child(lamp)
	_run.call_deferred()

func _run() -> void:
	var paths: Array[String] = []
	for s: Dictionary in SHOTS:
		_apply(s)
		for i in 4:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var p := "user://lit_test_%s.png" % s["name"]
		img.save_png(p)
		paths.append(ProjectSettings.globalize_path(p))
	print("LIT shots: ", ", ".join(paths))
	print("LIT DONE")
	get_tree().quit()

func _apply(s: Dictionary) -> void:
	var ang := deg_to_rad(float(s["angle"]))
	# DirectionalLight2D points along +Y rotated by `rotation`; the light comes FROM the opposite side
	sun.rotation = ang
	sun.energy = float(s["energy"])
	sun.color = s["tint"]
	canvas_mod.color = s["ambient"]
	lamp.energy = 1.6 if s["name"] == "night" else 0.6
	# shadow falls away from the sun, longer when the sun is low, squashed onto the ground
	var dir := Vector2(0, 1).rotated(ang)
	var length := 0.15 + 0.35 * absf(sin(ang))
	var h := body.texture.get_height()
	shadow.position = dir * h * length + Vector2(0, h * 0.08)
	shadow.skew = -dir.x * 0.5
	shadow.scale = Vector2(1.0, 0.6 + length)
	shadow.visible = s["name"] != "night"

static func _tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	return ImageTexture.create_from_image(Image.load_from_file(path))

static func _flat_tex(c: Color, size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	for y in size:
		for x in size:
			var v := n.get_noise_2d(x, y) * 0.06
			img.set_pixel(x, y, Color(c.r + v, c.g + v, c.b + v))
	return ImageTexture.create_from_image(img)

static func _noise_normal(size: int) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.06
	n.fractal_octaves = 3
	var img := n.get_seamless_image(size, size, false, true, 0.1)
	img.convert(Image.FORMAT_RGBA8)
	img.bump_map_to_normal_map(3.0)
	return ImageTexture.create_from_image(img)

static func _radial(size: int) -> Texture2D:
	var g := GradientTexture2D.new()
	g.width = size
	g.height = size
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color.WHITE)
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	return g

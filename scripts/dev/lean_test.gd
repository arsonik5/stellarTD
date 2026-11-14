extends Node2D

## Pixel-art building look check (pivot-2d.md, art + camera): code-drawn sprites (tools/codeart) seen straight
## down like Mindustry/Unfallen, lit by normal maps, with the raised part leaning away from the screen centre by its
## height (perspective lean, Unfallen) and the gap filled as walls (stacked, darker copies). Sun shadows, and a night
## shot with light pools. Saves frames to user://lean_test_*.png and quits.
##   godot --path . res://scenes/dev/lean_test.tscn

const DIR := "res://art_src/codeart/out/"
const ZOOM := 3.0
## Perspective: a point `h` px above the ground at screen offset d from the camera centre shows at d * (1 + h / CAM_H).
const CAM_H := 420.0
const ROOF_PX := 14.0            ## how high the housing roof stands (px)
const WALL_STEPS := 6

var cam: Camera2D
var sun: DirectionalLight2D
var ambient: CanvasModulate
var _roofs: Array[Dictionary] = []   # {anchor: Vector2, top: Node2D, walls: Array[Sprite2D], glow: Sprite2D}
var _shadows: Array[Sprite2D] = []
var _lamps: Array[PointLight2D] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color.BLACK)
	cam = Camera2D.new()
	cam.zoom = Vector2.ONE * ZOOM
	add_child(cam)
	cam.make_current()
	ambient = CanvasModulate.new()
	add_child(ambient)

	var ground := Sprite2D.new()
	var gt := CanvasTexture.new()
	gt.diffuse_texture = _ground_tex(128)
	gt.normal_texture = _ground_normal(128)
	gt.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.texture = gt
	ground.region_enabled = true
	ground.region_rect = Rect2(0, 0, 1400, 900)
	add_child(ground)

	var albedo := _load("smelter.png")
	var normal := _load("smelter_n.png")
	var top_tex := _load("smelter_top.png")
	var top_n := _load("smelter_top_n.png")
	var emit := _load("smelter_e.png")
	for gy in 3:
		for gx in 4:
			var at := Vector2((gx - 1.5) * 112.0, (gy - 1) * 104.0)
			_add_building(at, albedo, normal, top_tex, top_n, emit)

	sun = DirectionalLight2D.new()
	sun.height = 0.6
	add_child(sun)
	_run.call_deferred()

func _add_building(at: Vector2, albedo: Texture2D, normal: Texture2D, top_tex: Texture2D, top_n: Texture2D, emit: Texture2D) -> void:
	var sh := Sprite2D.new()                      # sun shadow of the housing, on the ground
	sh.texture = top_tex
	sh.modulate = Color(0, 0, 0, 0.42)
	sh.material = _unshaded()
	sh.position = at
	add_child(sh)
	_shadows.append(sh)

	var base := Sprite2D.new()
	base.texture = _ct(albedo, normal)
	base.position = at
	add_child(base)

	var walls: Array[Sprite2D] = []
	var sil := _silhouette(top_tex)
	for i in WALL_STEPS:                          # the housing's side walls: its silhouette in the side colour
		var w := Sprite2D.new()
		var ct := CanvasTexture.new()
		ct.diffuse_texture = sil
		w.texture = ct
		# hull side tone, a band of darker panel seam every other step, darkest at the foot
		var k := float(i) / WALL_STEPS
		w.modulate = Color("#565a70").lerp(Color("#868a9e"), k) if i % 3 != 1 else Color("#33364a")
		if i == 0:
			w.modulate = Color("#16161f")      # the outline where the wall meets the ground
		add_child(w)
		walls.append(w)
	var top := Sprite2D.new()
	top.texture = _ct(top_tex, top_n)
	add_child(top)
	var glow := Sprite2D.new()
	glow.texture = emit
	var gm := CanvasItemMaterial.new()
	gm.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	add_child(glow)
	_roofs.append({"anchor": at, "top": top, "walls": walls, "glow": glow})

	var lamp := PointLight2D.new()                # furnace light pool (only matters at night)
	lamp.texture = _radial(128)
	lamp.color = Color(1.0, 0.55, 0.25)
	lamp.texture_scale = 0.9
	lamp.position = at + Vector2(0, 16)
	lamp.height = 24.0
	add_child(lamp)
	_lamps.append(lamp)

## Roof lean: the housing is ROOF_PX above the ground, so it shows (anchor - camera) * ROOF_PX / CAM_H further out
## from the screen centre; walls fill the steps in between. Whole pixels, so the pixel art never smears.
func _process(_dt: float) -> void:
	for r in _roofs:
		var anchor: Vector2 = r["anchor"]
		var lean := (anchor - cam.global_position) * (ROOF_PX / CAM_H)
		var walls: Array[Sprite2D] = r["walls"]
		for i in walls.size():
			walls[i].position = (anchor + lean * float(i) / walls.size()).round()
		(r["top"] as Sprite2D).position = (anchor + lean).round()
		(r["glow"] as Sprite2D).position = (anchor + lean).round()

const SHOTS := [
	{"name": "noon_left", "cam": Vector2(-140, -40), "sun": 25.0, "energy": 1.0, "tint": Color(1, 0.97, 0.92), "amb": Color(0.62, 0.62, 0.68), "lamp": 0.0},
	{"name": "noon_right", "cam": Vector2(140, 40), "sun": 25.0, "energy": 1.0, "tint": Color(1, 0.97, 0.92), "amb": Color(0.62, 0.62, 0.68), "lamp": 0.0},
	{"name": "evening", "cam": Vector2(0, 0), "sun": 75.0, "energy": 0.85, "tint": Color(1.0, 0.7, 0.5), "amb": Color(0.45, 0.4, 0.46), "lamp": 0.25},
	{"name": "night", "cam": Vector2(0, 0), "sun": 120.0, "energy": 0.05, "tint": Color(0.6, 0.7, 1.0), "amb": Color(0.07, 0.08, 0.13), "lamp": 0.9},
]

func _run() -> void:
	for s: Dictionary in SHOTS:
		cam.position = s["cam"]
		var ang := deg_to_rad(float(s["sun"]))
		sun.rotation = ang
		sun.energy = float(s["energy"])
		sun.color = s["tint"]
		ambient.color = s["amb"]
		var dir := Vector2(0, 1).rotated(ang)
		for i in _shadows.size():
			var a: Vector2 = _roofs[i]["anchor"]
			_shadows[i].position = (a + dir * ROOF_PX * (0.6 + 0.8 * absf(sin(ang)))).round()
			_shadows[i].visible = float(s["energy"]) > 0.2
		for l in _lamps:
			l.energy = float(s["lamp"])
		for i in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://lean_test_%s.png" % s["name"])
	print("LEAN DONE ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()

func _load(f: String) -> Texture2D:
	return ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(DIR + f)))

static func _ct(a: Texture2D, n: Texture2D) -> CanvasTexture:
	var c := CanvasTexture.new()
	c.diffuse_texture = a
	c.normal_texture = n
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return c

## White silhouette of a sprite (alpha kept) for walls.
static func _silhouette(src: Texture2D) -> Texture2D:
	var img := src.get_image()
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)

static func _unshaded() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m

## Pixel ground: a few tones of regolith in 2x2 clumps (placeholder until the ground tiles exist).
static func _ground_tex(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.08
	var tones := [Color("#5b5048"), Color("#665a50"), Color("#716459"), Color("#7c6e62")]
	for y in size:
		for x in size:
			var v := n.get_noise_2d(float(x >> 1), float(y >> 1)) * 0.5 + 0.5
			img.set_pixel(x, y, tones[clampi(int(v * 4.0), 0, 3)])
	return ImageTexture.create_from_image(img)

static func _ground_normal(size: int) -> Texture2D:
	var n := FastNoiseLite.new()
	n.frequency = 0.08
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := n.get_noise_2d(float(x >> 1), float(y >> 1)) * 0.5 + 0.5
			var q := float(clampi(int(v * 4.0), 0, 3)) / 3.0
			img.set_pixel(x, y, Color(q, q, q))
	img.bump_map_to_normal_map(1.5)
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

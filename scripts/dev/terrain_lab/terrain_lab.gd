extends Node3D

## Terrain lab: an isolated sandbox for terrain materials. 16 tiles (4 x 4), one material each, rendered with the
## game's real terrain shader and mesher (MIXEL4 Transvoxel), so whatever looks right here looks right in the game.
##   godot --path . res://scenes/dev/terrain_lab.tscn -- look=ps2 blend=0 tag=a
## look:  pbr | ps2 | current   (baked sets from art_src/terrain_lab/baked, or the game's six current textures)
## blend: metres of cross-fade between neighbouring tiles (0 = hard edges)
## Writes screenshots to art_src/terrain_lab/shots/<tag>_<look>_b<blend>_<view>.png and quits.

const BAKED := "res://art_src/terrain_lab/baked"
const CURRENT := "res://data/textures/surfaces"
const SHOTS := "res://art_src/terrain_lab/shots"
const MATERIAL := preload("res://scripts/world/voxel_terrain_material.tres")
const Gen := preload("res://scripts/dev/terrain_lab/lab_generator.gd")
const TerrainGen := preload("res://scripts/dev/terrain_lab/lab_terrain_gen.gd")

## Slot -> CC0 set. Sixteen, one per tile, roughly ordered loose -> rock -> cold.
const SETS := [
	"Ground091", "Ground097", "Ground080", "Ground102",
	"Ground110", "Gravel040", "Rocks022", "Rock030",
	"Rock035", "Rock051", "Rock058", "Rock061",
	"Rock062", "Snow010A", "Snow015", "Ice002",
]
const CURRENT_SETS := ["regolith", "bedrock", "cliffrock", "frozen", "sulfur", "crystal"]

var look := "ps2"
var blend := 0.0
var tag := "a"
var tex_scale := 2.5
## "materials" = the 4 x 4 grid; any other value = a 192 m shape prototype of that planet type (lab_terrain_gen.gd)
var biome := "materials"
var antitile := 0
## material edge: band half-width and noise (shader blend_edge / blend_noise); -1 = shader default
var edge := -1.0
var edge_noise := -1.0
var _cam: Camera3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"look": look = kv[1]
			"blend": blend = float(kv[1])
			"tag": tag = kv[1]
			"scale": tex_scale = float(kv[1])
			"biome": biome = kv[1]
			"antitile": antitile = int(kv[1])
			"edge": edge = float(kv[1])
			"noise": edge_noise = float(kv[1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	_build_env()
	_build_terrain()
	if biome == "materials":
		_label_tiles()
		_run.call_deferred()
	else:
		_run_terrain.call_deferred()

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.20, 0.30, 0.48)
	mat.sky_horizon_color = Color(0.62, 0.66, 0.72)
	mat.ground_horizon_color = Color(0.40, 0.40, 0.42)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 60
	add_child(_cam)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 160
	_cam.add_child(viewer)

func _images(names: Array, dir: String, suffix: String) -> Array[Image]:
	var out: Array[Image] = []
	for i in 16:
		var n: String = names[i % names.size()]
		var p := ProjectSettings.globalize_path("%s/%s%s" % [dir, n, suffix])
		var img := Image.load_from_file(p)
		var want := out[0].get_width() if not out.is_empty() else img.get_width()
		if img.get_width() != want:
			img.resize(want, want, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		out.append(img)
	return out

func _build_terrain() -> void:
	var t := VoxelTerrain.new()
	if biome == "materials":
		var gen := Gen.new()
		gen.blend_width = blend
		t.generator = gen
	else:
		var tg := TerrainGen.new()
		tg.biome = biome
		t.generator = tg
	var fmt := VoxelFormat.new()
	fmt.set_channel_depth(VoxelBuffer.CHANNEL_INDICES, VoxelBuffer.DEPTH_16_BIT)
	t.format = fmt
	var mesher := VoxelMesherTransvoxel.new()
	mesher.texturing_mode = VoxelMesherTransvoxel.TEXTURES_MIXEL4_S4
	t.mesher = mesher
	t.bounds = AABB(Vector3(-32, -32, -32), Vector3(128, 64, 128)) if biome == "materials" else AABB(Vector3(0, -48, 0), Vector3(192, 112, 192))
	var m: ShaderMaterial = MATERIAL.duplicate()
	var alb: Array[Image]
	var nrm: Array[Image]
	if look == "current":
		alb = _images(CURRENT_SETS, CURRENT, "_alb.png")
		nrm = _images(CURRENT_SETS, CURRENT, "_nrm.png")
	else:
		alb = _images(SETS, BAKED, "_%s_alb.png" % look)
		nrm = _images(SETS, BAKED, "_%s_nrm.png" % look)
	var aa := Texture2DArray.new()
	aa.create_from_images(alb)
	var na := Texture2DArray.new()
	na.create_from_images(nrm)
	var tint := PackedVector4Array()
	var extra := PackedVector4Array()
	for i in 16:
		tint.append(Vector4(1, 1, 1, 1))
		extra.append(Vector4(1.0, 0.0, 0.35, tex_scale))
	m.set_shader_parameter("tex_albedo", aa)
	m.set_shader_parameter("tex_normal", na)
	m.set_shader_parameter("pal_tint_rough", tint)
	m.set_shader_parameter("pal_extra", extra)
	m.set_shader_parameter("antitile", antitile)
	if edge >= 0.0:
		m.set_shader_parameter("blend_edge", edge)
	if edge_noise >= 0.0:
		m.set_shader_parameter("blend_noise", edge_noise)
	t.material_override = m
	t.max_view_distance = 512
	add_child(t)

func _label_tiles() -> void:
	for i in 16:
		var l := Label3D.new()
		var names: Array = CURRENT_SETS if look == "current" else SETS
		l.text = "%d %s" % [i, names[i % names.size()]]
		l.font_size = 64
		l.pixel_size = 0.02
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = Vector3((i % 4 + 0.5) * 16.0, 7.5, (i / 4 + 0.5) * 16.0)
		add_child(l)

func _shot(view: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var p := ("%s/%s_%s_b%d_t%d_%s.png" % [SHOTS, tag, look, int(blend), antitile, view]) if biome == "materials" else ("%s/%s_%s_%s.png" % [SHOTS, tag, biome, view])
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(p))
	print("SHOT ", p)

func _aim(from: Vector3, to: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(to, Vector3.UP)

func _run() -> void:
	_aim(Vector3(32, 60, -22), Vector3(32, 0, 34))
	await get_tree().create_timer(8.0).timeout
	await _shot("overview")
	await _fps("overview")
	# each 2 x 2 block of tiles from a low, player-like angle
	for q in 4:
		var bx := (q % 2) * 32.0
		var bz := (q / 2) * 32.0
		_aim(Vector3(bx + 16, 9, bz - 4), Vector3(bx + 16, 0, bz + 18))
		await get_tree().create_timer(2.0).timeout
		await _shot("q%d" % q)
		if q == 0:
			await _fps("q0")
	# ground level, looking into one trench (tile 9: a cliff rock)
	_aim(Vector3(16 + 11.5, 1.7, 32 + 1), Vector3(16 + 11.5, -1.0, 32 + 12))
	await get_tree().create_timer(1.5).timeout
	await _shot("trench")
	print("LAB_DONE")
	get_tree().quit()

func _run_terrain() -> void:
	(_cam.get_child(0) as VoxelViewer).view_distance = 320
	_aim(Vector3(-40, 70, -40), Vector3(96, 0, 96))
	await get_tree().create_timer(40.0).timeout
	await _shot("overview")
	_aim(Vector3(20, 6, 30), Vector3(110, 2, 110))
	await get_tree().create_timer(4.0).timeout
	await _shot("ground_a")
	_aim(Vector3(170, 8, 175), Vector3(90, 0, 80))
	await get_tree().create_timer(4.0).timeout
	await _shot("ground_b")
	if biome == "mountain":
		# the designed cave: its mouth from outside, then inside the first chamber with a lamp
		var vt: VoxelTerrain = find_children("*", "VoxelTerrain", true, false)[0]
		var pts: Array = vt.generator.get("_cave_pts")
		var mouth: Vector3 = pts[0]
		var into: Vector3 = (pts[2] - pts[0]).normalized()
		_aim(mouth - into * 14.0 + Vector3(0, 4, 0), mouth + into * 4.0)
		await get_tree().create_timer(4.0).timeout
		await _shot("cave_mouth")
		var lamp := SpotLight3D.new()
		lamp.spot_range = 40.0
		lamp.spot_angle = 50.0
		lamp.light_energy = 4.0
		_cam.add_child(lamp)
		_aim(pts[7] + Vector3(0, 0.5, 0), pts[10])
		await get_tree().create_timer(4.0).timeout
		await _shot("cave_chamber")
		_aim(pts[4] + Vector3(0, 0.3, 0), pts[6])
		await get_tree().create_timer(3.0).timeout
		await _shot("cave_tunnel")
	print("LAB_DONE")
	get_tree().quit()

## Average frame rate over 3 s at the current view (vsync off for the measurement).
func _fps(view: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await get_tree().create_timer(0.5).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(3.0).timeout
	var fps := float(Engine.get_frames_drawn() - f0) / ((Time.get_ticks_msec() - t0) / 1000.0)
	print("FPS %s look=%s antitile=%d view=%s : %.0f" % [tag, look, antitile, view, fps])

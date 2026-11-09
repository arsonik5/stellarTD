class_name ErosionBaker
extends RefCounted

## Bakes an eroded planetary heightmap on the GPU, once, at world creation.
##
## This is the architecture change that stops terrain being noise.
##
## Noise produces a field whose statistics are identical everywhere; erosion
## produces CAUSES. Water runs downhill, cuts where it moves fast and drops what
## it carries where it slows, so valleys connect, ridges sharpen between them and
## debris collects at the bottom of slopes. None of that can be approximated by
## adding more noise bands - the previous generator had eight, and every spline
## used to fake an erosion feature drew a visible contour band instead, because a
## steep curve on a smooth field paints its level set.
##
## This is also what Space Engineers 2 does. VRAGE3 planets are heightmap-first;
## the difference is that theirs ship pre-baked per planet and ours must be
## generated from a seed, so the bake moves to world creation and is cached.
##
## Two processes, both needed:
##   hydraulic (droplet.glsl) - cuts valleys and drainage networks
##   thermal   (thermal.glsl) - relaxes slopes to an angle of repose, producing
##                              the talus aprons and flat-topped plateaus that
##                              hydraulic erosion alone leaves out
##
## Runs on a local RenderingDevice. **There is no GPU context in a headless
## Godot run**, so this cannot be exercised with `--headless`; the probe that
## established that is worth remembering before writing a headless test for it.

const GENERATE_SHADER := "res://shaders/erosion/generate.glsl"
const NORMALIZE_SHADER := "res://shaders/erosion/normalize.glsl"
const MANTLE_SHADER := "res://shaders/erosion/mantle.glsl"
const DROPLET_SHADER := "res://shaders/erosion/droplet.glsl"
const THERMAL_SHADER := "res://shaders/erosion/thermal.glsl"
const SLOPE_SHADER := "res://shaders/erosion/slope.glsl"

## Height is carried as fixed point in an integer image because GLSL has no
## float image atomics and the droplet pass needs imageAtomicAdd. 1 unit =
## 1/FIXED_SCALE, giving ~7 significant digits over a 0..1 range - far finer
## than the 16-bit PNG this is eventually written to.
const FIXED_SCALE := 1000000.0

class Settings extends RefCounted:
	var width: int = 2048
	var height: int = 1024
	var seed: int = 1

	## Base field, before anything erodes it.
	##
	## These are the "e_deep" values from the sweep in scripts/dev/erosion_sweep.gd,
	## chosen from hillshaded previews rather than raw height maps - a greyscale
	## height map cannot distinguish a plateau from a blob, and judging bakes from
	## one is how an over-eroded map became the default in the first place.
	##
	## The combination that matters: a RIDGED-dominant base (0.85) gives water
	## sharp divides to cut between instead of a uniform swell; the mass curve
	## pushes uplands genuinely high so there is something to carve; long droplet
	## runs (190 steps) let channels join into systems rather than stopping as
	## isolated gullies; and heavy thermal erosion (90 passes at a large talus)
	## flattens the tops and builds the debris aprons, which is what turns an
	## eroded lump into a mesa.
	var octaves: int = 7
	var frequency: float = 1.5
	var lacunarity: float = 2.03
	var gain: float = 0.55
	## 0 = rolling swells, 1 = fully ridged. A blend gives erosion both broad
	## landmass and initial divides to work with.
	var ridge_mix: float = 0.85
	## 0.35 FOLDED THE DOMAIN and that is what the hairline seams were.
	##
	## The warp displaces the sample direction by `strength * noise`. Past a
	## point that map stops being injective: two separated directions land on the
	## same noise coordinate, the field tears, and the tear runs along a smooth
	## curve across the landscape. In the generated surface it is a one-texel
	## slot with near-vertical walls, tens of metres deep at this relief, which
	## the mesher renders as a fan of parallel corrugations - in game it reads as
	## a stretched, streaked wedge on a slope.
	##
	## Proved by A/B on the generator's own isosurface: present with hydraulic
	## erosion disabled entirely (so not the water), gone completely at warp 0,
	## gone at 0.15.
	##
	## Note the risk SCALES WITH PLANET RADIUS: `frequency` is multiplied by
	## radius / FREQUENCY_REFERENCE_RADIUS, so a bigger body samples the warp at a
	## higher frequency, its gradient rises, and a strength that was safe at 8 km
	## folds at 20 km. Raise this only with a fresh hillshade at the largest body
	## in play.
	var warp_strength: float = 0.15
	## Mass shaping before erosion: below `mass_low` becomes plain, above
	## `mass_high` becomes massif. Equal values disable it.
	var mass_low: float = 0.25
	var mass_high: float = 0.85

	## Droplets as a multiple of cell count. Around 1 is enough for drainage to
	## emerge; far more mostly costs time.
	var droplet_density: float = 1.8
	var droplet_steps: int = 190
	var inertia: float = 0.05
	var capacity: float = 12.0
	var erode_rate: float = 0.3
	## Needed to turn the normalised height into a real slope angle for the
	## slope mask. Set by the caller from the body's profile; the baker itself
	## has no idea how many metres its 0..1 range spans.
	var relief_m: float = 0.0
	var metres_per_texel: float = 0.0
	var deposit_rate: float = 0.22
	var evaporate: float = 0.012
	var gravity: float = 4.0
	var min_slope: float = 0.01
	var pole_taper: float = 0.85

	## Dust mantling: how many blur passes to run on the height where sediment
	## collected. See mantle.glsl - this is what subdues the comb of hydraulic
	## channels on gentle ground without touching the ridges.
	var mantle_iterations: int = 4
	var mantle_radius: int = 2
	## Deposition range over which mantling ramps in. Matches the dust field in
	## planet_graph_generator.gd, so the geometry and the material detail agree
	## about where dust is.
	var mantle_low: float = 0.02
	var mantle_high: float = 0.22
	## Ceiling on the blend. Below 1.0 so even the dustiest ground keeps some of
	## its own shape instead of going to glass.
	var mantle_strength: float = 0.85
	## Floor on the mantle blend, applied even to bare rock. Takes the edge off
	## the hydraulic channel comb, which the deposition weighting cannot reach
	## because the comb is worst on scoured ground. See mantle.glsl.
	var mantle_floor: float = 0.40

	## Thermal passes interleaved with hydraulic batches.
	var thermal_iterations: int = 90
	var talus: float = 0.0065
	var thermal_rate: float = 0.4

	## Hydraulic work is split into batches with thermal passes between them, so
	## slopes relax as they are cut rather than only at the end - which is what
	## real weathering does, and it avoids a final pass having to relax
	## everything at once.
	## Also bounds how long any single dispatch runs. A batch that takes tens of
	## seconds is long enough for the GPU driver to decide the device has hung and
	## reset it, which surfaces as "Can't create buffer ... 0x887a0005" from every
	## later call and a half-written cache file.
	var batches: int = 40

	## Impact craters to add before erosion (CraterField.build), and the body radius in metres they are measured on.
	## Empty -> no crater pass, and the "fresh" / "crater_floor" masks come back blank.
	var craters: Dictionary = {}
	var planet_radius_m: float = 0.0

var last_stats: Dictionary = {}

## The erosion masks from the last bake: "flow", "wear", "deposition", each a
## normalised FORMAT_RF Image the same size as the heightmap. Empty if the bake
## failed. See the readback in bake() for why flow is normalised differently.
var last_masks: Dictionary = {}

## Must match FLOW_SCALE in droplet.glsl.
const FLOW_SCALE := 1024.0

## Resolution the masks are kept at, regardless of the height map's size. See
## the downsample in bake() for why.
const MASK_WIDTH := 2048
## The crater "fresh" mask (ejecta, rays) is shown by the terrain shader directly, and a ray is a few hundred metres
## wide, so it keeps twice the other masks' resolution.
const FRESH_WIDTH := 4096
const CRATER_SHADER := "res://shaders/erosion/craters.glsl"
const REPROJECT_SHADER := "res://shaders/erosion/reproject.glsl"
const CRATER_TILE_PX := 64
## Rows per crater dispatch, so no single dispatch runs long enough for the driver to call the GPU hung.
const CRATER_STRIP_ROWS := 512
## Craters older than this go in before erosion (worn, partly filled); younger ones after it (fresh).
const CRATER_AGE_SPLIT := 0.45
## Talus passes after the young craters go in.
const CRATER_SETTLE_PASSES := 6

## Emitted as the bake advances, 0..1, with a short label. The bake is ~56 s at
## full resolution and the window cannot paint during a synchronous GPU
## sequence, so without this the first launch of a seed is a black screen.
signal progress(fraction: float, label: String)

## Returns a normalised Image (FORMAT_RF, 0..1) or null on failure.
##
## A COROUTINE - call it with `await`. It yields to the main loop between
## erosion batches, which is what lets the loading screen draw and animate
## while the GPU works. Threading was the other option and a worse one: a local
## RenderingDevice driven from a second thread is a much larger surface for
## driver-specific breakage than yielding between submits, and the total time is
## the same either way. What changes is only whether the window responds.
func bake(settings: Settings) -> Image:
	var t_start := Time.get_ticks_msec()
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		push_warning("ErosionBaker: no local RenderingDevice (headless?). Skipping erosion.")
		return null

	var gen_shader := _load_shader(rd, GENERATE_SHADER)
	var drop_shader := _load_shader(rd, DROPLET_SHADER)
	var therm_shader := _load_shader(rd, THERMAL_SHADER)
	if not gen_shader.is_valid() or not drop_shader.is_valid() or not therm_shader.is_valid():
		rd.free()
		return null

	var tex_a := _make_texture(rd, settings.width, settings.height)
	var tex_b := _make_texture(rd, settings.width, settings.height)
	# The three erosion masks. Accumulators, not ping-ponged: every batch adds
	# into the same images, so what comes out is the whole history of the bake
	# rather than the last batch of it.
	var tex_flow := _make_texture(rd, settings.width, settings.height)
	var tex_wear := _make_texture(rd, settings.width, settings.height)
	var tex_depo := _make_texture(rd, settings.width, settings.height)
	var tex_talus := _make_texture(rd, settings.width, settings.height)

	# ---------------------------------------------------------------- base
	var gen_pipe := rd.compute_pipeline_create(gen_shader)
	var gen_set := _image_set(rd, gen_shader, [tex_a])
	var gen_pc := PackedByteArray()
	gen_pc.resize(48)
	gen_pc.encode_s32(0, settings.width)
	gen_pc.encode_s32(4, settings.height)
	gen_pc.encode_s32(8, settings.seed)
	gen_pc.encode_s32(12, settings.octaves)
	gen_pc.encode_float(16, settings.frequency)
	gen_pc.encode_float(20, settings.lacunarity)
	gen_pc.encode_float(24, settings.gain)
	gen_pc.encode_float(28, FIXED_SCALE)
	gen_pc.encode_float(32, settings.ridge_mix)
	gen_pc.encode_float(36, settings.warp_strength)
	gen_pc.encode_float(40, settings.mass_low)
	gen_pc.encode_float(44, settings.mass_high)
	_dispatch(rd, gen_pipe, gen_set, gen_pc,
		int(ceil(settings.width / 8.0)), int(ceil(settings.height / 8.0)), 1)

	# ------------------------------------------------------------- craters
	# Before erosion, so the same water and talus passes weather them like every other landform.
	var tex_fresh := _make_float_texture(rd, settings.width, settings.height)
	var tex_floor := _make_float_texture(rd, settings.width, settings.height)
	var crater_ms := _craters(rd, settings, tex_a, tex_fresh, tex_floor, CRATER_AGE_SPLIT, 2.0, false)

	var t_base := Time.get_ticks_msec()

	# --------------------------------------------- hydraulic + thermal loop
	var total_droplets := int(settings.width * settings.height * settings.droplet_density)
	var per_batch := int(total_droplets / max(settings.batches, 1))

	var drop_pipe := rd.compute_pipeline_create(drop_shader)
	var therm_pipe := rd.compute_pipeline_create(therm_shader)

	var current := tex_a
	var other := tex_b

	for batch in settings.batches:
		# Yield BEFORE the batch, not after: the submit+sync below blocks until
		# the GPU is done, so the frame has to be given away first.
		progress.emit(float(batch) / float(maxi(settings.batches, 1)) * 0.9,
			"Eroding terrain")
		await Engine.get_main_loop().process_frame

		var drop_set := _image_set(rd, drop_shader,
			[current, tex_flow, tex_wear, tex_depo])
		var pc := PackedByteArray()
		# Exactly the size droplet.glsl declares: 16 words. Godot rejects a
		# mismatch outright and skips the dispatch, which shows up as a planet
		# with no hydraulic erosion at all rather than as a crash.
		pc.resize(64)
		pc.encode_s32(0, settings.width)
		pc.encode_s32(4, settings.height)
		pc.encode_s32(8, settings.seed + batch * 9176)
		pc.encode_s32(12, per_batch)
		pc.encode_s32(16, settings.droplet_steps)
		pc.encode_float(20, settings.inertia)
		pc.encode_float(24, settings.capacity)
		pc.encode_float(28, settings.erode_rate)
		pc.encode_float(32, settings.deposit_rate)
		pc.encode_float(36, settings.evaporate)
		pc.encode_float(40, settings.gravity)
		pc.encode_float(44, FIXED_SCALE)
		pc.encode_float(48, settings.min_slope)
		pc.encode_float(52, 1.0)
		pc.encode_float(56, 1.0)
		# 2D dispatch. A 1D one tops out at 65535 groups of 64 = 4.2M droplets,
		# and this bake wants 94M; going over that limit fails SILENTLY, which is
		# how it went unnoticed - see the comment in droplet.glsl.
		var groups: int = int(ceil(per_batch / 64.0))
		var gx: int = mini(groups, 1024)
		var gy: int = int(ceil(float(groups) / float(gx)))
		pc.encode_s32(60, gx * 64)
		_dispatch(rd, drop_pipe, drop_set, pc, gx, gy, 1)

		var thermal_per_batch := int(settings.thermal_iterations / max(settings.batches, 1))
		for _i in max(thermal_per_batch, 1):
			var tset := _image_set(rd, therm_shader, [current, other, tex_talus])
			var tpc := PackedByteArray()
			tpc.resize(32)
			tpc.encode_s32(0, settings.width)
			tpc.encode_s32(4, settings.height)
			tpc.encode_float(8, FIXED_SCALE)
			tpc.encode_float(12, settings.talus)
			tpc.encode_float(16, settings.thermal_rate)
			_dispatch(rd, therm_pipe, tset, tpc,
				int(ceil(settings.width / 8.0)), int(ceil(settings.height / 8.0)), 1)
			var swap := current
			current = other
			other = swap

	# Young craters after the water: a fresh bowl on a dry world is not a sediment trap. Then a few talus passes,
	# so their walls slump to the angle of repose and drop scree on the floor like every other slope.
	crater_ms += _craters(rd, settings, current, tex_fresh, tex_floor, -1.0, CRATER_AGE_SPLIT, true)
	if int(settings.craters.get("count", 0)) > 0:
		for _i in CRATER_SETTLE_PASSES:
			var sset := _image_set(rd, therm_shader, [current, other, tex_talus])
			var spc := PackedByteArray()
			spc.resize(32)
			spc.encode_s32(0, settings.width)
			spc.encode_s32(4, settings.height)
			spc.encode_float(8, FIXED_SCALE)
			spc.encode_float(12, settings.talus)
			spc.encode_float(16, settings.thermal_rate)
			_dispatch(rd, therm_pipe, sset, spc,
				int(ceil(settings.width / 8.0)), int(ceil(settings.height / 8.0)), 1)
			var sw := current
			current = other
			other = sw

	var t_erode := Time.get_ticks_msec()

	# ------------------------------------------------------------- readback
	progress.emit(0.92, "Settling dust")
	await Engine.get_main_loop().process_frame

	var norm_shader := _load_shader(rd, NORMALIZE_SHADER)
	if not norm_shader.is_valid():
		rd.free()
		return null

	# Deposition is normalised FIRST and kept on the GPU, because the mantle pass
	# consumes it before the height is finalised. Everything else could be read
	# straight back; this one is a real dependency in the bake.
	var depo_rid := _gpu_normalize(rd, norm_shader, tex_depo, settings,
		FIXED_SCALE, false, 0.10, 0.995)

	# Dust settles into the topography and subdues it. Must happen here, on the
	# fixed-point accumulator, before normalisation.
	var mantled := _mantle(rd, settings, depo_rid, current, other)

	# Height goes through the same GPU normaliser as the masks. It used to be a
	# mean-and-3-SD clamp computed per pixel in GDScript; 0.135% and 99.865% are
	# where +-3 SD falls on a normal distribution, so this is the same trim
	# expressed as percentiles - and the histogram already gives percentiles for
	# free, without a second CPU pass over 52 million pixels.
	# Kept on the GPU rather than read back through _gpu_mask, because the
	# slope pass below reads it at full resolution.
	# SOFT: the extremes are rolled off past 0 and 1 rather than clamped. A clamp cut the deepest crater floors and
	# the highest summits into flat plates with a hard edge (2026-11-09, the first complex crater).
	var height_rid := _gpu_normalize(rd, norm_shader, mantled, settings,
		FIXED_SCALE, false, 0.00135, 0.99865, true)
	var img := _read_float_image(rd, height_rid, settings.width, settings.height)
	var slope_img := _slope_mask(rd, settings, height_rid)
	rd.free_rid(height_rid)

	# Flow is normalised on a LOG scale, the other two linearly.
	#
	# Drainage is power-law: a trunk channel carries orders of magnitude more
	# water than the slopes feeding it. Normalised linearly, the trunk takes the
	# whole range and every tributary rounds to zero - the mask becomes a few
	# bright threads on black, useless for material selection. Log compression is
	# what turns it into the branching network that is actually visible from
	# orbit, and it is what World Machine's own flow output does.
	# Flow is anchored at its MEDIAN: half the planet is ordinary hillside that
	# water merely crosses, and a channel is defined by carrying much more than
	# that. Wear and deposition are anchored lower, because large parts of the
	# surface genuinely accumulate neither and those zeros are real information.
	last_masks = {}
	if true:
		last_masks = {
			"flow": _gpu_mask(rd, norm_shader, tex_flow, settings,
				FLOW_SCALE, true, 0.50, 0.999),
			"wear": _gpu_mask(rd, norm_shader, tex_wear, settings,
				FIXED_SCALE, false, 0.20, 0.995),
			"deposition": _read_float_image(rd, depo_rid,
				settings.width, settings.height),
			"talus": _gpu_mask(rd, norm_shader, tex_talus, settings,
				FIXED_SCALE, false, 0.10, 0.995),
		}
		# Slope arrives already at mask resolution - max-pooled on the GPU,
		# which the Lanczos resize below would undo, so it joins afterwards.

		rd.free_rid(norm_shader)
		rd.free_rid(depo_rid)
		# Masks are downsampled; the height is not.
		#
		# At 10216x5108 each mask is 210 MB, so keeping four of them at full
		# resolution costs 840 MB of RAM and 747 MB on disk - more than the
		# terrain itself, for data that never needed it. A mask answers "is this
		# ground scoured, silted or buried in talus", and that varies over
		# hundreds of metres, not over the 12.3 m the height map resolves. The
		# height genuinely does need every texel: it IS the landform.
		for k in last_masks:
			var m: Image = last_masks[k]
			if m.get_width() > MASK_WIDTH:
				m.resize(MASK_WIDTH, MASK_WIDTH / 2, Image.INTERPOLATE_LANCZOS)

	if slope_img != null:
		last_masks["slope"] = slope_img

	# Crater masks: already 0..1. `fresh` (rays) is kept sharper than the other masks because the terrain shader
	# shows it directly and a ray is narrow; `crater_floor` only answers "is this inside a crater".
	var fresh_img := _read_float_image(rd, tex_fresh, settings.width, settings.height)
	var floor_img := _read_float_image(rd, tex_floor, settings.width, settings.height)
	var fw := mini(FRESH_WIDTH, settings.width)
	if fresh_img.get_width() > fw:
		fresh_img.resize(fw, fw / 2, Image.INTERPOLATE_LANCZOS)
	var mw := mini(MASK_WIDTH, settings.width)
	if floor_img.get_width() > mw:
		floor_img.resize(mw, mw / 2, Image.INTERPOLATE_LANCZOS)
	last_masks["fresh"] = fresh_img
	last_masks["crater_floor"] = floor_img
	rd.free_rid(tex_fresh)
	rd.free_rid(tex_floor)

	# Everything above works on an equirectangular grid (the erosion's metric assumes it). The terrain reads these
	# maps through godot_voxel's own projection, so hand it every map in that projection (SphereUV).
	var rshader := _load_shader(rd, REPROJECT_SHADER)
	if rshader.is_valid():
		img = _reproject(rd, rshader, img)
		for k in last_masks:
			last_masks[k] = _reproject(rd, rshader, last_masks[k])
		rd.free_rid(rshader)
	else:
		push_error("ErosionBaker: reproject shader missing; maps stay equirectangular and will be distorted in game")

	rd.free_rid(tex_a)
	rd.free_rid(tex_b)
	rd.free_rid(tex_flow)
	rd.free_rid(tex_wear)
	rd.free_rid(tex_depo)
	rd.free_rid(tex_talus)
	rd.free_rid(gen_shader)
	rd.free_rid(drop_shader)
	rd.free_rid(therm_shader)
	rd.free()

	progress.emit(1.0, "Terrain ready")
	var t_end := Time.get_ticks_msec()
	last_stats = {
		"size": "%dx%d" % [settings.width, settings.height],
		"droplets": total_droplets,
		"thermal_iterations": settings.thermal_iterations,
		"base_ms": t_base - t_start,
		"crater_ms": crater_ms,
		"craters": int(settings.craters.get("count", 0)),
		"erode_ms": t_erode - t_base,
		"readback_ms": t_end - t_erode,
		"total_ms": t_end - t_start,
	}
	return img

## Adds CraterField's craters to the fixed-point height and writes the fresh / floor masks. Returns ms spent.
func _craters(rd: RenderingDevice, settings: Settings, height_rid: RID, fresh_rid: RID, floor_rid: RID,
		age_lo: float, age_hi: float, accumulate: bool) -> int:
	var t0 := Time.get_ticks_msec()
	var field := settings.craters
	if field.is_empty() or int(field.get("count", 0)) <= 0 or settings.planet_radius_m <= 0.0 \
			or settings.relief_m <= 0.0:
		return 0
	var shader := _load_shader(rd, CRATER_SHADER)
	if not shader.is_valid():
		return 0
	var bins := CraterField.bin_tiles(field, settings.width, settings.height, settings.planet_radius_m,
		CRATER_TILE_PX)
	var cr_bytes := (field.data as PackedFloat32Array).to_byte_array()
	var st_bytes := (bins.start as PackedInt32Array).to_byte_array()
	var li_bytes := (bins.list as PackedInt32Array).to_byte_array()
	var cr_buf := rd.storage_buffer_create(cr_bytes.size(), cr_bytes)
	var st_buf := rd.storage_buffer_create(st_bytes.size(), st_bytes)
	var li_buf := rd.storage_buffer_create(li_bytes.size(), li_bytes)
	var us: Array[RDUniform] = []
	var ids := [height_rid, fresh_rid, floor_rid, cr_buf, st_buf, li_buf]
	for i in ids.size():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE if i < 3 else RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(ids[i])
		us.append(u)
	var set_rid := rd.uniform_set_create(us, shader, 0)
	var pipe := rd.compute_pipeline_create(shader)
	var y := 0
	while y < settings.height:
		var rows := mini(CRATER_STRIP_ROWS, settings.height - y)
		var pc := PackedByteArray()
		pc.resize(64)
		pc.encode_s32(0, settings.width)
		pc.encode_s32(4, settings.height)
		pc.encode_s32(8, CRATER_TILE_PX)
		pc.encode_s32(12, int(bins.tiles_x))
		pc.encode_s32(16, y)
		pc.encode_s32(20, 1 if accumulate else 0)
		pc.encode_float(56, age_lo)
		pc.encode_float(60, age_hi)
		pc.encode_float(32, settings.planet_radius_m)
		pc.encode_float(36, FIXED_SCALE / settings.relief_m)
		pc.encode_float(40, float(field.get("ray_strength", 0.0)))
		pc.encode_float(44, CraterField.YOUNG_AGE)
		_dispatch(rd, pipe, set_rid, pc, int(ceil(settings.width / 8.0)), int(ceil(rows / 8.0)), 1)
		y += rows
	rd.free_rid(pipe)
	rd.free_rid(cr_buf)
	rd.free_rid(st_buf)
	rd.free_rid(li_buf)
	rd.free_rid(shader)
	return Time.get_ticks_msec() - t0

## One FORMAT_RF image from the bake's equirectangular grid into SphereUV's projection, same size. See reproject.glsl.
func _reproject(rd: RenderingDevice, shader: RID, src_img: Image) -> Image:
	var w := src_img.get_width()
	var h := src_img.get_height()
	var fmt := RDTextureFormat.new()
	fmt.width = w
	fmt.height = h
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT 		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var src_rid := rd.texture_create(fmt, RDTextureView.new(), [src_img.get_data()])
	var dst := _make_float_texture(rd, w, h)
	var pipe := rd.compute_pipeline_create(shader)
	var set_rid := _image_set(rd, shader, [src_rid, dst])
	var pc := PackedByteArray()
	pc.resize(16)
	pc.encode_s32(0, w)
	pc.encode_s32(4, h)
	_dispatch(rd, pipe, set_rid, pc, int(ceil(w / 8.0)), int(ceil(h / 8.0)), 1)
	var out := _read_float_image(rd, dst, w, h)
	rd.free_rid(pipe)
	rd.free_rid(src_rid)
	rd.free_rid(dst)
	return out

## Normalises one accumulator on the GPU and reads back a finished Image.
##
## Replaces the GDScript per-pixel loop in _to_mask(). Same result - percentile
## range, optional log compression - but the only thing crossing the bus before
## the final image is a 2048-entry histogram.
##
## Three dispatches: find the range, bin it, then map [lo, hi] -> [0, 1].
## The percentile lookup happens on the CPU, on 2048 integers.
func _gpu_normalize(rd: RenderingDevice, shader: RID, src: RID, settings: Settings,
		scale: float, logarithmic: bool, lo_pct: float, hi_pct: float, soft: bool = false) -> RID:
	var w := settings.width
	var h := settings.height
	var pipe := rd.compute_pipeline_create(shader)
	var dst := _make_float_texture(rd, w, h)

	# bins[0..2047] histogram, bins[2048] min, bins[2049] max, seeded so the
	# atomics converge from the right side.
	const BINS := 2048
	var init := PackedInt32Array()
	init.resize(BINS + 2)
	init.fill(0)
	init[BINS] = 0x7fffffff
	init[BINS + 1] = -0x7fffffff
	var buf := rd.storage_buffer_create(init.size() * 4, init.to_byte_array())

	var set_rid := _mixed_set(rd, shader, src, dst, buf)
	var gx := int(ceil(w / 8.0))
	var gy := int(ceil(h / 8.0))

	# --- pass 1: range
	_dispatch(rd, pipe, set_rid, _norm_pc(w, h, 0, logarithmic, scale, 0.0, 0.0), gx, gy, 1)
	var back := rd.buffer_get_data(buf).to_int32_array()
	# Guarded, because indexing past the end of a PackedInt32Array in GDScript
	# does not raise cleanly - it prints an error and then the process dies with
	# an illegal instruction, which looks like a GPU fault rather than a bounds
	# bug. If the readback comes back short, something upstream failed and the
	# right move is to say so and give up on this layer.
	if back.size() < BINS + 2:
		push_error("ErosionBaker: histogram readback returned %d ints, expected %d"
			% [back.size(), BINS + 2])
		rd.free_rid(buf)
		rd.free_rid(pipe)
		return dst
	const RANGE_SCALE := 4096.0
	var vmin := float(back[BINS]) / RANGE_SCALE
	var vmax := float(back[BINS + 1]) / RANGE_SCALE
	if vmax <= vmin:
		rd.free_rid(buf)
		rd.free_rid(pipe)
		return dst

	# --- pass 2: histogram over that range
	init.fill(0)
	init[BINS] = 0x7fffffff
	init[BINS + 1] = -0x7fffffff
	rd.buffer_update(buf, 0, init.size() * 4, init.to_byte_array())
	_dispatch(rd, pipe, set_rid, _norm_pc(w, h, 1, logarithmic, scale, vmin, vmax), gx, gy, 1)
	var hist := rd.buffer_get_data(buf).to_int32_array()
	if hist.size() < BINS:
		push_error("ErosionBaker: histogram pass returned %d ints, expected %d"
			% [hist.size(), BINS])
		rd.free_rid(buf)
		rd.free_rid(pipe)
		return dst

	var count := w * h
	var lo_target := int(count * lo_pct)
	var hi_target := int(count * hi_pct)
	var seen := 0
	var lo := vmin
	var hi := vmax
	var got_lo := false
	var span := vmax - vmin
	for i in BINS:
		seen += hist[i]
		if not got_lo and seen >= lo_target:
			lo = vmin + float(i) / float(BINS) * span
			got_lo = true
		if seen >= hi_target:
			hi = vmin + (float(i) + 1.0) / float(BINS) * span
			break

	# --- pass 3: apply
	_dispatch(rd, pipe, set_rid, _norm_pc(w, h, 3 if soft else 2, logarithmic, scale, lo, hi), gx, gy, 1)
	rd.free_rid(buf)
	rd.free_rid(pipe)
	return dst

## Normalise and read straight back, for the masks that are only ever consumed
## on the CPU side.
func _gpu_mask(rd: RenderingDevice, shader: RID, src: RID, settings: Settings,
		scale: float, logarithmic: bool, lo_pct: float, hi_pct: float) -> Image:
	var rid := _gpu_normalize(rd, shader, src, settings, scale, logarithmic,
		lo_pct, hi_pct)
	var img := _read_float_image(rd, rid, settings.width, settings.height)
	rd.free_rid(rid)
	return img

## Full-resolution slope, max-pooled to mask resolution. See slope.glsl.
##
## Returns null if the caller did not supply relief and texel size - a slope
## with no scale is not an angle, and guessing one would put the rock/dust
## split in the wrong place on every body.
func _slope_mask(rd: RenderingDevice, settings: Settings, height_rid: RID) -> Image:
	if settings.relief_m <= 0.0 or settings.metres_per_texel <= 0.0:
		push_warning("ErosionBaker: no relief_m/metres_per_texel, skipping slope mask")
		return null
	var shader := _load_shader(rd, SLOPE_SHADER)
	if not shader.is_valid():
		return null
	var ow := mini(MASK_WIDTH, settings.width)
	var oh := ow / 2
	var dst := _make_float_texture(rd, ow, oh)
	var pipe := rd.compute_pipeline_create(shader)
	var pc := PackedByteArray()
	# 4 ints + 4 floats - exactly slope.glsl's Params. Godot refuses a
	# mismatched push constant and skips the dispatch without failing.
	pc.resize(32)
	pc.encode_s32(0, settings.width)
	pc.encode_s32(4, settings.height)
	pc.encode_s32(8, ow)
	pc.encode_s32(12, oh)
	pc.encode_float(16, settings.relief_m)
	pc.encode_float(20, settings.metres_per_texel)
	var set_rid := _image_set(rd, shader, [height_rid, dst])
	_dispatch(rd, pipe, set_rid, pc, int(ceil(ow / 8.0)), int(ceil(oh / 8.0)), 1)
	var out := _read_float_image(rd, dst, ow, oh)
	rd.free_rid(dst)
	rd.free_rid(pipe)
	rd.free_rid(shader)
	return out

func _read_float_image(rd: RenderingDevice, rid: RID, w: int, h: int) -> Image:
	return Image.create_from_data(w, h, false, Image.FORMAT_RF,
		rd.texture_get_data(rid, 0))

## Blurs the height where sediment collected, leaving bare rock sharp.
##
## See mantle.glsl. Runs after erosion and before the height is normalised,
## because it operates on the same fixed-point accumulator the erosion passes
## use. Returns whichever of the ping-pong pair now holds the result.
func _mantle(rd: RenderingDevice, settings: Settings, depo_rid: RID,
		current: RID, other: RID) -> RID:
	if settings.mantle_iterations <= 0:
		return current
	var shader := _load_shader(rd, MANTLE_SHADER)
	if not shader.is_valid():
		return current
	var pipe := rd.compute_pipeline_create(shader)
	var gx := int(ceil(settings.width / 8.0))
	var gy := int(ceil(settings.height / 8.0))
	var pc := PackedByteArray()
	pc.resize(32)
	pc.encode_s32(0, settings.width)
	pc.encode_s32(4, settings.height)
	pc.encode_s32(8, settings.mantle_radius)
	pc.encode_float(16, settings.mantle_low)
	pc.encode_float(20, settings.mantle_high)
	pc.encode_float(24, settings.mantle_strength)
	pc.encode_float(28, settings.mantle_floor)

	var a := current
	var b := other
	for _i in settings.mantle_iterations:
		var set_rid := _image_set(rd, shader, [a, b, depo_rid])
		_dispatch(rd, pipe, set_rid, pc, gx, gy, 1)
		var swap := a
		a = b
		b = swap
	rd.free_rid(pipe)
	rd.free_rid(shader)
	return a

func _norm_pc(w: int, h: int, mode: int, logarithmic: bool, scale: float,
		lo: float, hi: float) -> PackedByteArray:
	var pc := PackedByteArray()
	pc.resize(32)
	pc.encode_s32(0, w)
	pc.encode_s32(4, h)
	pc.encode_s32(8, mode)
	pc.encode_s32(12, 1 if logarithmic else 0)
	pc.encode_float(16, scale)
	pc.encode_float(20, lo)
	pc.encode_float(24, hi)
	return pc

func _make_float_texture(rd: RenderingDevice, w: int, h: int) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = w
	fmt.height = h
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT 		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT 		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return rd.texture_create(fmt, RDTextureView.new(), [])

## Two images plus a storage buffer in one set.
func _mixed_set(rd: RenderingDevice, shader: RID, src: RID, dst: RID, buf: RID) -> RID:
	var us: Array[RDUniform] = []
	for i in 2:
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = i
		u.add_id(src if i == 0 else dst)
		us.append(u)
	var ub := RDUniform.new()
	ub.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ub.binding = 2
	ub.add_id(buf)
	us.append(ub)
	return rd.uniform_set_create(us, shader, 0)

func _load_shader(rd: RenderingDevice, path: String) -> RID:
	var file: RDShaderFile = load(path)
	if file == null:
		push_error("ErosionBaker: could not load %s" % path)
		return RID()
	var spirv := file.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("ErosionBaker: %s failed to compile: %s" % [path, spirv.compile_error_compute])
		return RID()
	return rd.shader_create_from_spirv(spirv)

func _make_texture(rd: RenderingDevice, w: int, h: int) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = w
	fmt.height = h
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SINT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return rd.texture_create(fmt, RDTextureView.new(), [])

func _image_set(rd: RenderingDevice, shader: RID, textures: Array) -> RID:
	var uniforms: Array[RDUniform] = []
	for i in textures.size():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = i
		u.add_id(textures[i])
		uniforms.append(u)
	return rd.uniform_set_create(uniforms, shader, 0)

func _image_pair_set(rd: RenderingDevice, shader: RID, src: RID, dst: RID) -> RID:
	return _image_set(rd, shader, [src, dst])

func _dispatch(rd: RenderingDevice, pipeline: RID, uniform_set: RID,
		push_constant: PackedByteArray, gx: int, gy: int, gz: int) -> void:
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_set_push_constant(cl, push_constant, push_constant.size())
	rd.compute_list_dispatch(cl, max(gx, 1), max(gy, 1), max(gz, 1))
	rd.compute_list_end()
	rd.submit()
	rd.sync()

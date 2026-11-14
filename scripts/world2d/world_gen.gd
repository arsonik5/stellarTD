class_name WorldGen
extends RefCounted

## World generator v1 for flat 2D maps (pivot-2d.md 4.3). Same idea chain as the planet generator, sampled on a
## plane: landforms -> levels + ramps -> ground rules -> ore. Noise runs in C++ (FastNoiseLite images); script
## loops touch each tile a fixed small number of times. Budget: whole 1024^2 map well under 5 s (test enforces it).
##
## Landforms in v1: continents (broad plains and basins), ridged mountain ranges (masked into ranges, not
## everywhere), canyons (inverted ridges carved down), mesas (terraced plateaus). Still to port from the planet
## generator (later steps): erosion bake, craters (CraterField), trait ground rules, scatter, POIs, roofs/caves.

const RAMP_GRADIENT := 0.6     ## max continuous height change per tile (levels) for a level step to be a ramp

static var last_timing := {}   ## step -> ms, for the budget test and the loading bar

static func generate(g: WorldGrid, seed_in: int, ore_types: Array = []) -> void:
	g.seed_value = seed_in
	var w := g.width
	var hgt := g.height
	var n := w * hgt
	var t0 := Time.get_ticks_usec()
	last_timing = {}

	# --- noise fields (C++), each as one byte per tile
	var base := _field(seed_in, w, hgt, 0.0022, 5, FastNoiseLite.FRACTAL_FBM)
	var mmask := _field(seed_in + 1, w, hgt, 0.0030, 3, FastNoiseLite.FRACTAL_FBM)
	var ridge := _field(seed_in + 2, w, hgt, 0.0070, 4, FastNoiseLite.FRACTAL_RIDGED)
	var cmask := _field(seed_in + 3, w, hgt, 0.0025, 2, FastNoiseLite.FRACTAL_FBM)
	var canyon := _field(seed_in + 4, w, hgt, 0.0050, 3, FastNoiseLite.FRACTAL_RIDGED)
	var mesa := _field(seed_in + 5, w, hgt, 0.0040, 2, FastNoiseLite.FRACTAL_FBM)
	var detail := _field(seed_in + 6, w, hgt, 0.0500, 2, FastNoiseLite.FRACTAL_FBM)
	var gnoise := _field(seed_in + 7, w, hgt, 0.0200, 3, FastNoiseLite.FRACTAL_FBM)
	last_timing["noise"] = (Time.get_ticks_usec() - t0) / 1000.0

	# --- continuous height in levels
	var t1 := Time.get_ticks_usec()
	var hf := PackedFloat32Array()
	hf.resize(n)
	var inv := 1.0 / 255.0
	for i in n:
		var b := float(base[i]) * inv
		var h := (b - 0.42) * 9.0                                          # plains around 0, basins below
		var mm := clampf((float(mmask[i]) * inv - 0.56) * 6.0, 0.0, 1.0)  # where mountain ranges are
		var r := float(ridge[i]) * inv
		h += mm * r * r * 20.0                                             # ridged ranges up to ~+20
		var cm := clampf((float(cmask[i]) * inv - 0.5) * 5.0, 0.0, 1.0)
		var c := float(canyon[i]) * inv
		if c > 0.82:
			h -= cm * (c - 0.82) / 0.18 * 7.0                              # canyons cut down into the plain
		var ms := float(mesa[i]) * inv
		if ms > 0.62 and mm < 0.3:
			var top := h + (ms - 0.62) * 40.0                              # mesa: flat top, sheer risers
			h = maxf(h, floorf(top / 3.0) * 3.0)
		h += (float(detail[i]) * inv - 0.5) * 0.7
		hf[i] = h
	last_timing["height"] = (Time.get_ticks_usec() - t1) / 1000.0

	# --- quantise to levels, ramps where the slope is gentle, ground rules
	var t2 := Time.get_ticks_usec()
	var off := WorldGrid.LEVEL_OFFSET
	var lo := WorldGrid.MIN_LEVEL
	var hi := WorldGrid.MAX_LEVEL
	for i in n:
		g.elevation[i] = clampi(floori(hf[i]), lo, hi) + off
	for y in hgt:
		var row := y * w
		for x in w:
			var i := row + x
			var e := int(g.elevation[i])
			var h := hf[i]
			var hx := hf[i + 1] if x + 1 < w else h
			var hy := hf[i + w] if y + 1 < hgt else h
			var grad := maxf(absf(hx - h), absf(hy - h))
			var step := false
			if x + 1 < w and absi(int(g.elevation[i + 1]) - e) == 1:
				step = true
			elif y + 1 < hgt and absi(int(g.elevation[i + w]) - e) == 1:
				step = true
			elif x > 0 and absi(int(g.elevation[i - 1]) - e) == 1:
				step = true
			elif y > 0 and absi(int(g.elevation[i - w]) - e) == 1:
				step = true
			g.flags[i] = WorldGrid.F_RAMP if step and grad < RAMP_GRADIENT else 0
			var lv := e - off
			var gv := int(gnoise[i])
			var gr := WorldGrid.Ground.REGOLITH
			if lv >= 11:
				gr = WorldGrid.Ground.BASALT
			elif grad > 0.45:
				gr = WorldGrid.Ground.GRAVEL
			elif lv <= -1 and gv > 110:
				gr = WorldGrid.Ground.SAND
			elif gv < 60:
				gr = WorldGrid.Ground.GRAVEL
			elif gv > 200:
				gr = WorldGrid.Ground.SAND
			g.ground[i] = gr
	last_timing["levels"] = (Time.get_ticks_usec() - t2) / 1000.0

	# --- ore deposits on walkable flat ground (not on ramps or cliff edges)
	var t3 := Time.get_ticks_usec()
	_ores(g, seed_in, ore_types if not ore_types.is_empty() else load_ore_types())
	last_timing["ore"] = (Time.get_ticks_usec() - t3) / 1000.0
	last_timing["total"] = (Time.get_ticks_usec() - t0) / 1000.0

static func _field(s: int, w: int, h: int, freq: float, octaves: int, fractal: int) -> PackedByteArray:
	var f := FastNoiseLite.new()
	f.seed = s
	f.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	f.frequency = freq
	f.fractal_type = fractal
	f.fractal_octaves = octaves
	return f.get_image(w, h, false, false, true).get_data()

static func load_ore_types() -> Array:
	var out := []
	for id: String in WorldGrid.ORE_IDS:
		if id == "":
			continue
		var p := "res://data/ore_types/%s.tres" % id
		if ResourceLoader.exists(p):
			out.append(load(p))
	return out

static func _ores(g: WorldGrid, seed_in: int, types: Array) -> void:
	var w := g.width
	var n := w * g.height
	var fields: Array[PackedByteArray] = []
	var cuts: Array[int] = []
	var ids: Array[int] = []
	for t: OreType in types:
		var oi := WorldGrid.ORE_IDS.find(t.id)
		if oi <= 0:
			continue
		# blob size from the ore's own noise_frequency (tuned in metres for the 3D world: same scale here)
		fields.append(_field(seed_in + 100 + oi, w, g.height, t.noise_frequency * 0.35, 2, FastNoiseLite.FRACTAL_FBM))
		# rarer ores (higher base_threshold) need a higher noise value: ~2-5% of the map each
		cuts.append(int(255.0 * clampf(0.80 + t.base_threshold * 0.25, 0.80, 0.95)))
		ids.append(oi)
	var k := fields.size()
	for i in n:
		if (g.flags[i] & WorldGrid.F_RAMP) != 0:
			continue
		for j in k:
			var v := int(fields[j][i])
			if v > cuts[j]:
				g.ore[i] = ids[j]
				g.ore_amount[i] = clampi(40 + (v - cuts[j]) * 8, 40, 255)
				break

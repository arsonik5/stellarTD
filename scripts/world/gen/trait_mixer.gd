class_name TraitMixer
extends RefCounted

## Seed + body facts -> the planet's weighted trait mix. Deterministic: the same seed and facts always give the same
## planet, so a save only stores its seed (the No Man's Sky arrangement; reports/AAA voxel terrain fidelity.md).
##
## 1. Every trait gets weight = base_weight x fit(facts) x a seeded roll (0.35..1.65).
## 2. The heaviest becomes the DOMINANT trait (it owns the planet's base ground).
## 3. The dominant trait's affinities scale the others; excluded traits drop out.
## 4. Up to MAX_SECONDARY more traits join if they are heavy enough and pass a seeded chance, so most planets are a
##    clear identity with one or two flavours, not a grey average of everything.
## 5. Weights are normalised so the dominant keeps >= DOMINANT_MIN of the total.

const LIBRARY_DIR := "res://data/traits"
const MAX_SECONDARY := 2
const SECONDARY_MIN := 0.22            # of the dominant's weight
const DOMINANT_MIN := 0.55

static var _library: Array[PlanetTrait] = []

static func library() -> Array[PlanetTrait]:
	if _library.is_empty():
		var dir := DirAccess.open(LIBRARY_DIR)
		if dir != null:
			for f in dir.get_files():
				var fn := f.trim_suffix(".remap")
				if fn.ends_with(".tres"):
					var t := load("%s/%s" % [LIBRARY_DIR, fn]) as PlanetTrait
					if t != null:
						_library.append(t)
		_library.sort_custom(func(a: PlanetTrait, b: PlanetTrait) -> bool: return String(a.id) < String(b.id))
	return _library

static func find(id: StringName) -> PlanetTrait:
	for t in library():
		if t.id == id:
			return t
	return null

## Returns [{"trait": PlanetTrait, "weight": float}, ...], dominant first, weights summing to 1.
static func mix(seed: int, facts: Dictionary, lib: Array[PlanetTrait] = []) -> Array:
	if lib.is_empty():
		lib = library()
	var rng := RandomNumberGenerator.new()
	var scored: Array = []
	for t in lib:
		rng.seed = hash([seed, "trait", String(t.id)])
		var w := t.base_weight * t.fit(facts) * rng.randf_range(0.35, 1.65)
		if w > 0.0:
			scored.append({"trait": t, "weight": w})
	if scored.is_empty():
		return []
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight)
	var dom: Dictionary = scored[0]
	var dom_t: PlanetTrait = dom.trait
	var rest: Array = []
	for i in range(1, scored.size()):
		var s: Dictionary = scored[i]
		var t: PlanetTrait = s.trait
		if dom_t.excludes.has(t.id) or t.excludes.has(dom_t.id):
			continue
		s.weight *= float(dom_t.affinity.get(String(t.id), dom_t.affinity.get(t.id, 1.0)))
		rest.append(s)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight)
	var out: Array = [dom]
	rng.seed = hash([seed, "secondary"])
	for s in rest:
		if out.size() > MAX_SECONDARY:
			break
		var t: PlanetTrait = s.trait
		var clash := false
		for o in out:
			var ot: PlanetTrait = o.trait
			if ot.excludes.has(t.id) or t.excludes.has(ot.id):
				clash = true
			# the saturation budget: one accent (saturated or glowing) trait per planet, so it reads as THE accent
			if (ot.accent or ot.emissive) and (t.accent or t.emissive):
				clash = true
		if clash or s.weight < dom.weight * SECONDARY_MIN:
			continue
		if rng.randf() < clampf(s.weight / dom.weight + 0.15, 0.0, 0.95):
			out.append(s)
	# normalise, keeping the dominant's share >= DOMINANT_MIN
	var total := 0.0
	for o in out:
		total += o.weight
	for o in out:
		o.weight /= total
	if out[0].weight < DOMINANT_MIN and out.size() > 1:
		var others: float = 1.0 - out[0].weight
		var scale: float = (1.0 - DOMINANT_MIN) / maxf(others, 1e-6)
		out[0].weight = DOMINANT_MIN
		for i in range(1, out.size()):
			out[i].weight *= scale
	return out

## The trait mix a body uses: its explicit trait_override if set, else generated from its seed and facts when
## generate_traits is on; [] = the body still uses its hand-authored biome surfaces. Cached per body.
static var _cache := {}

static func of(body: CelestialBody) -> Array:
	if body == null:
		return []
	if _cache.has(body):
		return _cache[body]
	var m: Array = []
	if not body.trait_override.is_empty():
		var total := 0.0
		for id in body.trait_override:
			total += float(body.trait_override[id])
		for id in body.trait_override:
			var t := find(StringName(id))
			if t != null:
				m.append({"trait": t, "weight": float(body.trait_override[id]) / maxf(total, 1e-6)})
		m.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight)
	elif body.generate_traits:
		m = mix(body.seed, facts_for(body))
	_cache[body] = m
	return m

## Body facts from a CelestialBody: radius, air density, temperature, activity flags. The temperature here is a
## first approximation from the body's climate bias; the system generator (stage 7) will compute it from the
## star's luminosity and the orbit.
static func facts_for(body: CelestialBody) -> Dictionary:
	var air := 0.0
	if body.atmosphere != null:
		air = body.atmosphere.surface_air_density
	var temp: float = body.climate_bias.x
	# Planet.VOXEL_SCALE read at run time, so this file (and the trait lab) doesn't compile-depend on planet.gd
	var vs: float = float((load("res://scripts/world/planet.gd") as Script).get_script_constant_map().get("VOXEL_SCALE", 1.0))
	var r := body.radius * vs
	return {
		"radius_m": r, "air_density": air, "temperature": temp,
		"atmosphere": air > 0.01, "water": air > 0.3 and temp > 0.3 and temp < 0.75,
		"geologically_active": r > 2000.0,
	}

## The planet's landform numbers: each trait's, weighted by its share of the mix. Air erases rays (a thin atmosphere
## halves them by ~0.1 kg/m3), so `rays` already carries that. Empty mix -> all zero (hand-authored bodies).
static func landform(body: CelestialBody) -> Dictionary:
	var out := {"craters": 0.0, "rays": 0.0, "ledges": 0.0, "lava_tubes": 0.0, "lava_region": 0.0}
	var m := of(body)
	for o in m:
		var t: PlanetTrait = o.trait
		var w: float = o.weight
		out.craters += t.crater_density * w
		out.rays += t.ray_strength * w
		out.ledges += t.ledge_strength * w
		out.lava_tubes = maxf(out.lava_tubes, t.lava_tubes)
		if t.lava_tubes > 0.0:
			out.lava_region = maxf(out.lava_region, w)
	var air: float = body.atmosphere.surface_air_density if body != null and body.atmosphere != null else 0.0
	out.rays *= 1.0 / (1.0 + air * 10.0)
	return out

## A short human-readable form: "airless 0.70 + crystalline 0.30".
static func describe(m: Array) -> String:
	var parts: Array[String] = []
	for o in m:
		parts.append("%s %.2f" % [(o.trait as PlanetTrait).id, o.weight])
	return " + ".join(parts)

class_name PlanetTrait
extends Resource

## One trait a planet can have: airless, icy, volcanic, crystalline, desert, sulfur, life... A planet is not a preset
## type but a weighted MIX of traits picked from its seed and physical facts (TraitMixer), so a crystal moon is
## `airless 0.7 + crystalline 0.3` and an icy world with cryovolcanoes is `icy 0.75 + volcanic 0.25`.
## Design: reports/AAA voxel terrain fidelity.md, "Traits replace planet presets".
##
## A trait declares what it contributes (materials per ground role, colour rules, asset lines, landmarks), when it
## can occur (fit to the body's facts) and how it combines with other traits (requires / excludes / affinity).
## Nothing in the shader or the generator knows a trait by name: they only read what traits contribute.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("When it occurs")
## Weight before facts and the seed's dice. Common traits (rocky, airless) high, rare ones (crystalline) low.
@export_range(0.0, 2.0, 0.01) var base_weight: float = 1.0
## Fits best between these surface temperatures (0 = cryogenic, 0.5 = temperate, 1 = molten), fading out over
## temperature_soft outside.
@export var temperature_range := Vector2(0.0, 1.0)
@export_range(0.01, 1.0, 0.01) var temperature_soft: float = 0.2
## Air density range (kg/m3; Earth sea level 1.225). Airless traits want ~0, desert/life want some.
@export var air_range := Vector2(0.0, 100.0)
@export_range(0.001, 5.0, 0.001) var air_soft: float = 0.3
## Body radius range in metres it suits (small bodies can't hold atmospheres or stay volcanic for long).
@export var radius_range := Vector2(0.0, 1.0e9)
## Body facts that must be true ("atmosphere", "water", "geologically_active", ...).
@export var requires_facts: Array[StringName] = []
## Traits this one can't share a planet with.
@export var excludes: Array[StringName] = []
## Other trait id -> weight multiplier when THIS trait is present (volcanic boosts sulfur, icy boosts crystalline).
@export var affinity: Dictionary = {}

@export_group("Where it shows")
## How the trait claims ground on a planet it is part of, used by the surface rules (stage 3): global (everywhere,
## the dominant trait), regional (noise patches), lowland, highland, crater_floor, polar, fault, cold_trap.
@export_enum("global", "regional", "lowland", "highland", "crater_floor", "polar", "fault", "cold_trap") var spatial := "regional"
## replace = its material replaces the base inside its mask; overlay = drawn on top (frost, dust, lichen) by rule;
## modulate = only shifts tint / roughness of what is there.
@export_enum("replace", "overlay", "modulate") var material_mode := "replace"

@export_group("Materials")
## Ground role -> material (SurfaceStyle from data/surfaces/library). Roles: surface, surface_alt, regional, cliff,
## bedrock, strata_a, strata_b, fresh_cut. A trait only fills what it has; the PaletteBuilder takes the dominant
## trait's base roles and gives secondary traits the regional slots by weight.
@export var materials: Dictionary = {}

@export_group("Colour")
## OKLCH hue (degrees) this trait's materials sit around, and how saturated they may be. Only an ACCENT trait may
## use real saturation on a planet (the saturation budget); everything else stays muted so the accent reads.
@export_range(0.0, 360.0) var hue: float = 60.0
@export_range(0.0, 0.4, 0.005) var chroma_max: float = 0.04
@export var accent: bool = false
## Light emitted at night (crystal glow, lava): counts against the planet's saturation budget.
@export var emissive: bool = false

@export_group("Landforms")
## Impact craters per area, relative to a fully airless, never-resurfaced body (1). Volcanic and wind-worked worlds
## bury or erase theirs. Feeds CraterField (baked into the heightmap before erosion, so erosion weathers them).
@export_range(0.0, 1.0, 0.01) var crater_density: float = 0.3
## How bright and long the rays and ejecta of young craters are. Space weathering and air both erase them.
@export_range(0.0, 1.0, 0.01) var ray_strength: float = 0.3
## Hard and soft rock layers eroded unevenly into benches on steep faces (0 = smooth faces).
@export_range(0.0, 2.0, 0.01) var ledge_strength: float = 0.0
## Contraction cracks on this trait's flat ground: polygon size in metres (0 = none). Mud ~0.5, permafrost 5-20.
@export_range(0.0, 30.0, 0.05) var crack_cell_m: float = 0.0
## Drained lava tubes under this trait's ground, with skylights and collapse trenches (0 = none, 1 = common).
@export_range(0.0, 1.0, 0.01) var lava_tubes: float = 0.0

@export_group("Content (later stages)")
## Asset lines this trait brings (rock kits, crystals, flora...), by line id. Stage 4.
@export var asset_lines: Array[StringName] = []
## Hero landmarks this trait can supply. Stage 4e.
@export var landmarks: Array[StringName] = []

## How well a body's facts suit this trait: 0 = impossible, 1 = ideal.
func fit(facts: Dictionary) -> float:
	for f in requires_facts:
		if not facts.get(String(f), false):
			return 0.0
	var t: float = facts.get("temperature", 0.5)
	var air: float = facts.get("air_density", 0.0)
	var r: float = facts.get("radius_m", 10000.0)
	if r < radius_range.x or r > radius_range.y:
		return 0.0
	return _band(t, temperature_range, temperature_soft) * _band(air, air_range, air_soft)

static func _band(v: float, rng: Vector2, soft: float) -> float:
	if v >= rng.x and v <= rng.y:
		return 1.0
	var d := (rng.x - v) if v < rng.x else (v - rng.y)
	return clampf(1.0 - d / soft, 0.0, 1.0)

func material(role: String) -> SurfaceStyle:
	return materials.get(role, null) as SurfaceStyle

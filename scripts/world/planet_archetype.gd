class_name PlanetArchetype
extends Resource
## What a planet IS, as one resource (design/05-planets.md "Target architecture", W4): No Man's Sky's lesson that
## variety comes BETWEEN planets and coherence WITHIN one. A body picks an archetype and commits to it - one terrain
## recipe, one palette, one set of biomes, one scatter set, one POI table - so it reads as one picture.
##
## Colour harmony: `palette` holds the world's key colours. Surface tints are multiplied by `ground_tint`, and the
## ambient fill is derived from the SAME colours (`ambient_tint()`) instead of being tuned on its own. (A sky tint
## for the scattering pass is the obvious next step; it is not built - the home sky is still the physical default.)

@export var display_name := "Barren"
## One word the HUD / scanner / journal can show ("Barren", "Frozen", "Sulfur", "Crystal", "Mesa", "Exotic").
@export var kind := "barren"

@export_group("Terrain")
@export var terrain: TerrainRecipe
## Replaces the body's own biome list when not empty (an archetype commits to its biomes).
@export var biomes: Array[Biome] = []

@export_group("Palette")
## Dust / plains, rock / cliffs, accent (ore glow, crystal, ice sheen). Linear colours.
@export var palette: PackedColorArray = PackedColorArray([Color(0.62, 0.6, 0.57), Color(0.42, 0.41, 0.4),
	Color(0.45, 0.95, 0.85)])
## Multiplies every terrain surface tint on this body (1,1,1 = untouched).
@export var ground_tint := Color(1, 1, 1)
## How much of the ground colour leaks into the ambient fill (0 = neutral grey-blue, 1 = fully ground-coloured).
## Real shadows are lit by the sky AND by light bounced off the surrounding ground.
@export_range(0.0, 1.0) var ambient_ground_share := 0.35

@export_group("Populate")
@export var scatter: ScatterSet
@export var pois: Array[PoiSpec] = []
## Minimum ground distance between points of interest, metres. ~1.5 km keeps something on the horizon from
## almost any landing spot (NMS rule) without crowding.
@export var poi_min_spacing_m := 1500.0

@export_group("Hazard")
## 0..1 each. Read by suit modules later (design C9 / M31); shown in the scanner readout.
@export_range(0.0, 1.0) var cold := 0.0
@export_range(0.0, 1.0) var heat := 0.0
@export_range(0.0, 1.0) var toxic := 0.0
@export_range(0.0, 1.0) var radiation := 0.0

## Ambient fill colour: the vacuum/air ambient blended toward the ground's own dust colour.
func ambient_tint(base: Color) -> Color:
	var dust: Color = palette[0] if palette.size() > 0 else Color(0.6, 0.6, 0.6)
	# Normalise the dust colour to unit luminance so only its HUE leaks in, not its brightness.
	var lum := maxf(dust.get_luminance(), 0.001)
	var hue := Color(dust.r / lum, dust.g / lum, dust.b / lum)
	return base.lerp(Color(base.r * hue.r, base.g * hue.g, base.b * hue.b), ambient_ground_share)

## The biome list a body actually uses: its archetype's when that commits to one, else the body's own.
static func biomes_of(body: CelestialBody) -> Array:
	var a := of(body)
	if a != null and not a.biomes.is_empty():
		return a.biomes
	return body.biomes if body != null else []

static func of(body: CelestialBody) -> PlanetArchetype:
	if body == null or TerrainRecipe.legacy_world():
		return null
	return body.get("archetype") as PlanetArchetype

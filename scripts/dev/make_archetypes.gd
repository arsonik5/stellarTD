extends SceneTree
## Writes the planet archetype resources (design/05-planets.md W4/W5). The values live HERE, with the reason for
## each, so a tuning change is a code review rather than an inspector click lost in a .tres diff.
##   godot --headless --path . -s res://scripts/dev/make_archetypes.gd
## Then re-run scenes/dev/planet_test.tscn and landform_ab.tscn before committing the regenerated .tres files.

const OUT := "res://data/archetypes"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var probe := _poi("probe", "Continuance Probe", 1.0, 0.0)
	var crash := _poi("crash_site", "Crash Site", 0.8, 1.1)
	var spire := _poi("crystal_spire", "Crystal Outcrop", 0.5, 0.5)
	_save(_barren(probe, crash, spire), "barren_home")
	_save(_frozen(probe, crash), "frozen_moon")
	quit()

func _poi(t: String, n: String, w: float, sink: float) -> PoiSpec:
	var p := PoiSpec.new()
	p.poi_type = t
	p.display_name = n
	p.weight = w
	p.sink_m = sink
	return p

func _save(r: Resource, file: String) -> void:
	var path := "%s/%s.tres" % [OUT, file]
	var err := ResourceSaver.save(r, path)
	print("%s -> %s" % [path, "ok" if err == OK else "ERROR %d" % err])

## HOME: one coherent barren world. Regolith only, grey dust over darker rock, Earth-thin air.
## Character: the W2 erosion on (calm plains, sharp highs), plus the identity layers - mesa highlands (terraces
## above mid altitude in ~30% of the planet), canyon systems through ~35%, and spire fields (70 m cells inside ~15% of the planet: dense where they occur, absent elsewhere). Something to see
## from most landing spots, not everywhere at once.
func _barren(probe: PoiSpec, crash: PoiSpec, spire: PoiSpec) -> PlanetArchetype:
	var a := PlanetArchetype.new()
	a.display_name = "Barren"
	a.kind = "barren"
	a.biomes = [load("res://data/biomes/regolith_plains.tres")]
	var t := TerrainRecipe.new()
	t.terrace_enabled = true
	t.terrace_step_m = 24.0
	t.terrace_riser = 0.2
	t.terrace_patch_m = 3200.0
	t.terrace_coverage = 0.3
	t.terrace_min_altitude = 0.45
	t.canyon_enabled = true
	t.canyon_feature_m = 3600.0
	t.canyon_depth_m = 40.0
	t.canyon_width = 0.04
	t.canyon_sharpness = 2.5
	t.canyon_coverage = 0.35
	t.spire_enabled = true
	t.spire_spacing_m = 70.0
	t.spire_radius_m = 8.0
	t.spire_height_m = 40.0
	t.spire_density = 0.15
	a.terrain = t
	a.palette = PackedColorArray([Color(0.62, 0.6, 0.57), Color(0.4, 0.4, 0.41), Color(0.45, 0.95, 0.85)])
	a.ground_tint = Color(1.0, 0.985, 0.96)          # a hair warmer than raw regolith: sunlit dust, not ash
	a.ambient_ground_share = 0.3
	var s := ScatterSet.new()                          # W5 defaults: talus + broken edges, clumped
	a.scatter = s
	a.pois = [probe, crash, spire]
	a.poi_min_spacing_m = 1500.0
	return a

## MOON: a distinct Frozen world. Ice crust, cold blue-white palette, vacuum.
## Character: heavily cratered (no weather to erase them), smooth ice plains (strong slope erosion), crevasse
## canyons - narrow, deep, sheer, through most of the surface - and no mesas or spires (ice flows, it does not
## stand in columns). Sparse, pale boulders. Probes and crash sites only: no crystal here.
func _frozen(probe: PoiSpec, crash: PoiSpec) -> PlanetArchetype:
	var a := PlanetArchetype.new()
	a.display_name = "Frozen"
	a.kind = "frozen"
	a.biomes = [load("res://data/biomes/frozen_wastes.tres")]
	var t := TerrainRecipe.new()
	t.slope_erosion = 0.85
	t.altitude_erosion = 0.3
	t.crater_amplitude_mult = 1.5
	t.swell_amplitude_m = 2.5
	t.crag_amplitude_m = 3.0
	t.canyon_enabled = true
	t.canyon_feature_m = 900.0
	t.canyon_depth_m = 18.0
	t.canyon_width = 0.018
	t.canyon_sharpness = 5.0
	t.canyon_coverage = 0.7
	a.terrain = t
	a.palette = PackedColorArray([Color(0.82, 0.88, 0.95), Color(0.55, 0.62, 0.72), Color(0.6, 0.85, 1.0)])
	a.ground_tint = Color(0.9, 0.96, 1.08)
	a.ambient_ground_share = 0.55
	var s := ScatterSet.new()
	s.density = 0.006
	s.tint = Color(0.85, 0.9, 1.0)
	s.clump_strength = 0.85
	a.scatter = s
	a.pois = [probe, crash]
	a.poi_min_spacing_m = 900.0
	a.cold = 0.8
	return a

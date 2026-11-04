# 05 - Planets: the architecture pass

Direction (Michael, 2026-11-04): **keep big SE2-scale planets, with an appetite for No Man's Sky** - many worlds,
each one worth landing on, built on top of what NMS does well. Planets are the deepest system in the code and
still "aren't good". This file says why, what to build, and in what order. Technique detail stays in
`architecture/terrain-generator.md`; this is the design layer above it.

## Why the planets are not good yet (diagnosis)

The generator is technically strong (compiled graph, 8-20 km radius, caves, craters, cliffs, PBR, streaming,
saves). What is missing is mostly not engineering - it is **identity and purpose**:

1. **No identity.** One home planet + a test moon, both read as "grey rock with patches". NMS's core lesson is
   that **variety comes between planets and coherence within one**: every planet picks one archetype, one
   palette, one sky, one mood, and commits. Ours blends four biomes into a generic average.
2. **Relief without landforms.** Bands (crag/rock/grain/swell/craters) give texture at every scale but few
   *shapes you'd name* - mesas, canyons, arches, spires, terraces, basins. Open items 1-2 (meadows, carpet) are
   symptoms: tuning noise amplitudes cannot create a landform the recipe doesn't contain.
3. **Colour is not doing work.** Surface, sky, fog and light are tuned separately; NMS sells a world by a
   harmonised palette (terrain colour <-> sky tint <-> fog <-> light colour).
4. **Nothing on the surface but rocks.** No points of interest, no flora-equivalent, no scatter with rules
   (open item 5: boulders read random). Nothing to travel *to*.
5. **One planet.** Travel (arc 3-4) has nowhere to go.

## What NMS does that we take (from public talks; behaviour, not code)

Sources: Sean Murray, *Building Worlds Using Math(s)*, GDC 2017; Innes McKendrick, *Continuous World Generation in
No Man's Sky*, GDC 2017. Claims below marked (talk) are from those; (common knowledge) are widely documented
behaviours of the shipped game - verify against Michael's capture session.

- **One "uber noise" with per-planet parameters** (talk): a single terrain function whose knobs (domain warp,
  ridged vs billowed sharpness, **slope erosion** = damp high octaves where the lower octaves are steep,
  **altitude erosion** = smoother low ground and sharper peaks, terracing/plateaus) are set from the planet
  seed. Planets differ by *parameters*, not by different code. We already have most knobs as separate bands;
  the change is to make them a parameter set chosen per planet and to add derivative-based slope erosion.
- **Pipeline: voxels -> polygonise -> texture -> populate -> simulate**, generated in regions around the player
  and streamed (talk). We have the same stages via godot_voxel; "populate" is our weakest stage.
- **Planet = archetype + palette + atmosphere + weather + flora/fauna set + resources** (common knowledge). The
  archetype is the unit of variety the player perceives ("frozen", "toxic", "barren", "lush", "exotic").
- **Exotic planets** break the rules on purpose (common knowledge): pillars, floating rock, giant bubbles. Rare
  and memorable - a reason to keep scanning systems.
- **Points of interest everywhere within a short flight** (common knowledge): something visible on the horizon
  from almost any landing spot. Distance between POIs matters more than their count.

What we deliberately keep from SE2 instead: **real scale, real mining** (deposits underground, 1 m class
voxels, deformation persists), heightmap-first base with 3D detail layered on (already our arrangement).

## Target architecture

```
CelestialBody (data: radius, mass, orbit, seed, spin)
   |-- PlanetArchetype (NEW resource, chosen from seed or hand-set)
   |      terrain_recipe : TerrainRecipe   (uber-noise parameter set + which landform layers are on)
   |      palette        : SurfacePalette  (biome materials + their colours, harmonised)
   |      atmosphere     : PlanetAtmosphere (exists; tint derived from palette)
   |      weather        : WeatherProfile  (exists as design)
   |      scatter_sets   : Array[ScatterSet] (rocks, crystals, flora-equivalents, with placement rules)
   |      poi_table      : Array[PoiSpec]  (landmarks, wrecks, probes, caves, with spacing)
   |      resources      : ore table + depth bands (exists as ore_types)
   |      hazards        : cold/heat/toxic/radiation levels -> suit modules
   |-- PlanetProfile (exists: derives physical numbers - relief fraction, continent wavelength, temperature)
   `-- Generator graph (exists) reads recipe + profile; no per-planet code
```

- **Archetype list for 1.0 (6):** Barren (home-like regolith, craters), Frozen (ice sheets, crevasses,
  hydrogen), Sulfur/Toxic (yellow flats, vents, sulfur), Crystal (spires, high signature, rich), Mesa/Canyon
  (terraced plateaus, deep canyons, copper), Exotic (rule-breaker, rare). Home planet = Barren with a gentle
  recipe; its moon = Frozen.
- **Landform layers** (each a graph sub-graph with on/off + params in `TerrainRecipe`): continents, ridged
  mountains, terraces/mesas (quantised height with smooth risers), canyons (inverted ridged, carved), craters
  (exists), dunes (exists, swell), spires/pillars (3D sdf spots), arches/overhangs (3D detail layer, phase 2),
  caves (exists).
- **Slope + altitude erosion** inside the recipe (the NMS trick): estimate slope from the low octaves (finite
  differences on the coarse layer - the graph has no derivative node, two extra samples of the base are
  affordable) and scale the detail octaves down on steep ground; raise detail with altitude. This targets open
  items 1-2 directly: flats get calm, ridges get sharp, without per-band gates.
- **Populate stage (VoxelInstancer):** scatter sets with rules - density by slope, altitude, biome weight,
  distance to rock outcrops (fixes open item 5); **POIs** placed by a sphere-spots field with minimum spacing
  so something is always within ~1-2 km; deposits announce themselves with surface stains + crystal outcrops.
- **Palette harmony:** palette defines 3-5 key colours; atmosphere scatter tint, fog, ambient and sun tint are
  derived from it (not tuned separately) so every planet reads as one picture.
- **Scale:** keep 8-20 km radius. Interplanetary distances require the floating origin (`architecture/large-
  world.md`) before a second *full* planet can be flown to; until then extra bodies are moons in the local
  frame (already proven).

## Order of work

1. **TerrainRecipe extraction** - move current band constants into a recipe resource; home planet recipe
   reproduces today's terrain exactly (measure with `micro_hillshade` before/after; no visual change).
2. **Slope + altitude erosion** in the recipe; re-measure meadows and cliffs against open items 1-2.
3. **Landform layers:** terraces/mesas and canyons first (biggest identity gain per cost), spires second.
4. **PlanetArchetype + palette harmony**; make the moon a real Frozen archetype - first proof of variety.
5. **Populate:** scatter rules (fix boulders), then POIs (probe + crash site + crystal spire).
6. **Second planet** after floating origin; Exotic archetype last.

## Capture checklist for the NMS / SE2 study session (Michael)

Goal: a behaviour spec, not assets. For each game, a short note + screenshots:
- **Landing view:** from 5 random landings, what is on the horizon? Count POIs visible, estimate distance.
- **Same spot at 3 heights:** ground, 100 m, 1 km+ - what detail appears/disappears (LOD, scatter fade, fog).
- **Planet from orbit vs surface:** do colours match? What changes (sky tint, fog colour) with altitude?
- **Archetype list:** for 10 planets, one word for each + its 3 dominant colours + whether it felt distinct.
- **Terrain shapes:** screenshots of the 5 most memorable landforms; note scale (use the player as a ruler).
- **Mining (SE2):** drill speed, hole size, ore surface hint, how deposits look when exposed.
- **Building (SE2):** grid sizes, how small and large blocks mix, how joints/rotors behave (for C5).
- **Scatter:** where rocks/plants cluster (slopes? valleys? around POIs?), how dense, how they fade.
- Numbers > adjectives: "spires every ~400 m, 30-60 m tall" is usable; "looks great" is not.

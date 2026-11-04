# Terrain reference targets

The images in this folder are the standing visual target for the terrain,
ground materials and biome design. Compare against them directly - do not work
from a remembered description of them.

Capture comparisons with the dev harness, which fixes both the framings and the
sun angle so successive passes are actually comparable:

    godot --path . res://scenes/dev/terrain_look.tscn -- --tag=<name> --no-atmo

`--no-atmo` matters: the atmosphere currently washes the surface badly and the
decision was made (2026-09-11) NOT to fix it yet, because fixing it would mask
terrain and material deficiencies rather than remove them. Judge the ground with
it off.

---

## What the references actually contain

Broken down so the work can be assigned. Each item says whether it is a SHAPE
problem (voxel generator), a SCATTER problem (instanced geometry) or a MATERIAL
problem (shader) - conflating those has already cost this project time, most
recently trying to solve distant surface markings with LOD.

### `regolith-boulder-plain.jpg` - the primary Regolith target

| What you see | Kind | Have it? |
|---|---|---|
| Scattered angular BOULDERS, many sizes, foreground to mid | scatter | **no** |
| Rock debris partially BURIED in dust | scatter + material | no |
| Smooth dust plain with faint dune ripples | shape + material | partial |
| Mountain massif with sharp faceted ridgelines | shape | partial |
| Talus / scree aprons at the base of slopes | shape + scatter | **no** |
| Shallow crater rims and circular depressions | shape | **no** |
| Rock outcrops emerging through the dust sheet | shape + material | no |
| Near-black shadows, long, from a low sun | lighting | yes |
| Warm grey-tan dust over darker grey rock | material | partial |

**The single biggest gap is boulders.** The foreground third of that image is
rubble. No amount of shader work produces it - it is geometry.

### `layered-mesa-plateau.jpg` - the stratified target

| What you see | Kind | Have it? |
|---|---|---|
| Flat-topped MESAS with near-vertical cliff faces | shape | **no** |
| Horizontal strata banding the cliff faces | material | partial |
| Talus fans at cliff bases | shape + scatter | no |
| Smooth sediment plain between landforms | shape | yes |
| Distant buttes and spires in silhouette | shape | no |
| Cool blue-grey, low saturation throughout | material | yes |

**Mesas are a SHAPE problem, not a material one.** A flat top with a vertical
face needs the height field quantised into terraces - `NODE_STEPIFY` exists in
the graph. Painting strata on a smooth dome does not read as a mesa.

---

## Standards this work is held to

1. **Measure cost in-process.** `VoxelGeneratorGraph.debug_measure_microseconds_per_voxel(false)`,
   interleaved repetitions. End-to-end launch timing on this machine has
   measured 23.6 / 31.3 / 39.9 us for identical code. A previous pass shipped a
   3.2x generation regression because only the look was checked.
2. **Capture frames and look at them.** Headless cannot answer a rendering
   question. Tag every capture and compare tags.
3. **Run the instrument against a known-good config before diagnosing.** A test
   that cannot detect success cannot diagnose failure.
4. **Keep it scale-free.** Any constant tuned for one radius is a bug - express
   it relative to radius, wavelength or relief. This has bitten relief, noise
   frequency, atmosphere energy, LOD distance and cave ceilings.
5. **Anchor scripted edits on whole lines and assert the match count.**
   `lod_count = \d+` also matches `collision_lod_count = 1`.

---

## Open finding: the spawn sits on a noise extremum

**The player always spawns at +Y** (`world.tscn` puts them at `(0, radius+400, 0)`),
and every terrain field is sampled on the normalised direction. `(0,1,0)` is a
lattice point for the underlying noise, so the fields hit their EXTREMES there.

Measured on the mesa gate: raw noise `= 1.000` exactly at the spawn direction,
gate `= 1.0`, versus `0.0` only 30 degrees away and **17% terraced globally**.

Two consequences, both real:

1. **Every capture is taken at the least representative point on the planet.**
   This produced a completely wrong conclusion during tuning - terracing looked
   like it covered the world and was cut from a 0.55 dead zone to 0.88 chasing
   it, when the real figure was already a reasonable 17%. Judge regional
   features by sampling the sphere, not from the spawn camera.
2. **Gameplay: every planet starts the player at a noise extremum**, so the
   opening view is systematically atypical of that world.

`ZN_FastNoiseLite` exposes `rotation_type_3d`, which exists precisely to break
axis alignment in 3D domains. A per-seed domain rotation would remove the
special status of the cardinal axes. Not applied yet - it belongs to whoever
owns `planet_graph_generator.gd`.

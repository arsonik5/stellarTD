# Terrain critical path

### Terrain Critical Path â€” scoped 2026-09-09

Everything terrain-related now blocks on three pieces, in this order. Nothing
else in the terrain backlog is worth starting first.

**Where we actually are (measured, not estimated):**

| | value |
|---|---|
| Generator speed | 4.2-4.7 us/voxel (GDScript), flat in radius |
| Playable planet | 200 m radius, player lands in ~12 s |
| 2 km planet | collision never arrives in 170 s - **not viable** |
| Persistence | none. Every launch regenerates from scratch |
| Base representation | pure 3D noise SDF, no heightmap layer |

---

#### Piece 1 â€” `VoxelGeneratorGraph` port (~20-50x)

The single highest-leverage change. Removes the per-voxel GDScript
interpreter and gets automatic range analysis for block culling.

Node set already verified present in this build: `NODE_OUTPUT_SINGLE_TEXTURE`,
`NODE_OUTPUT_WEIGHT`, `NODE_CURVE` (splines), `NODE_IMAGE_2D`,
`NODE_SDF_SPHERE_HEIGHTMAP`, `NODE_SPOTS_3D`, `NODE_EXPRESSION`,
`NODE_FUNCTION`. **`FastNoise2` is NOT compiled in**, so budget 20-50x rather
than 50-200x; recompiling godot_voxel with FastNoise2 is the next lever after
this if it is still short.

Build order matters: hand-author one reference graph in the editor first (the
tuning IS the quality, and the editor has a live preview), then port it to a
programmatic builder driven by `CelestialBody`. Keep `ore_generator.gd` behind
a flag as the reference to diff against.

Unlocks: 2 km planets, and probably makes Piece 2 optional at that scale.

#### Piece 2 â€” Generate once, stream from disk (`VoxelStreamSQLite`)

We regenerate terrain from scratch every time the player moves, and again on
every launch. That is the actual cause of "terrain still popping in behind me
after I already landed" - the generator loses a race against the viewer.

`VoxelStreamSQLite` ships with the addon. Generate the planet once behind a
loading screen, persist it, and afterwards read blocks from disk. Disk reads
beat a GDScript generator by orders of magnitude, which turns scale from a CPU
problem into a storage one.

**User has explicitly accepted a loading screen for this (2026-09-09).** That
is what makes this route open, and it changes the architecture: we stop
optimising for "generate fast enough to keep up with a moving player" and
start optimising for "generate once, correctly, then read."

Also closes the long-standing "no save system exists" gap for terrain.

#### Piece 3 â€” Baked eroded heightmaps (the World Machine look)

**This is the piece that actually delivers the requested look, and it is not
optional for it.** No amount of layered noise reproduces real drainage
networks, river valleys or talus slopes - those are the product of simulated
erosion, which is iterative and non-local and cannot run per-block on demand.

Run real hydraulic erosion once per seed, offline (numpy or a Godot tool
script), into a 2048-4096 square heightmap. Sample it via
`NODE_SDF_SPHERE_HEIGHTMAP` / `NODE_IMAGE_2D` and let the graph add all detail
below pixel scale.

Open question to resolve first: which projection `NODE_SDF_SPHERE_HEIGHTMAP`
expects (equirectangular vs cube-face). Cube-face needs a branch on dominant
axis, which the graph cannot express.

---


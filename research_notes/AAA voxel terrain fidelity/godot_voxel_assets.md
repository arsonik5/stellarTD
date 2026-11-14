# Godot 4.x + godot_voxel terrain fidelity, and CC0 ground/rock assets

Researched 2026-11-08. godot_voxel's latest tagged release is **v1.7 (20 Aug 2026)**, a custom Godot build from the **4.7 branch** with the module included ([release v1.7](https://github.com/Zylann/godot_voxel/releases/tag/v1.7)). master is "1.7.1 dev" ([changelog](https://github.com/Zylann/godot_voxel/blob/master/doc/source/changelog.md)). Docs quoted below come from `doc/source/*.md` on master, which is what voxel-tools.readthedocs.io/latest renders.

## godot_voxel: VoxelInstancer, Transvoxel texturing, distant normalmaps, shader API, performance

### Takeaway
godot_voxel already gives you most of what you need: VoxelInstancer scatters multimesh rocks/pebbles per terrain LOD, with slope/height/noise/voxel-texture filters and a Sphere up-mode for planets, and it removes instances when the ground under them is dug. Transvoxel MIXEL4_S4 writes 4 indices + 4 weights into CUSTOM1 (8-bit each). VoxelLodTerrain can bake model-space detail normalmaps for distant LODs (default begins at LOD 2), but edited areas only show up there with `full_load_mode_enabled`, and GPU generation skips edited voxels.

### Cited Findings

**VoxelInstancer (scatter)**
- VoxelInstancer must be a child of a voxel terrain. It spawns models on the surface "which can later be removed when modified". Two item kinds: multimesh items ("can be extremely numerous, and can optionally have collision") and scene items (much slower, lower default density, complex scenes at high counts can freeze or crash Godot). — [instancing.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/instancing.md)
- For planets, set `up_mode` = `UP_MODE_SPHERE`: "Up is opposite from the direction where the terrain's origin is." Default is `UP_MODE_POSITIVE_Y`. — [VoxelInstancer API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelInstancer/)
- Per-LOD layers: each `VoxelInstanceLibraryItem` has `lod_index`. LOD 0 is the closest, smallest range. Higher indices spawn on bigger chunks that reach further, but they're less precise, so instances can float or sink near ridges and caves. Fixes: `offset_along_normal`, or `snap_to_generator_sdf_enabled` (slower, needs `VoxelGeneratorGraph` series generation, and it **doesn't account for edited areas**). — [instancing.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/instancing.md)
- VoxelInstanceGenerator properties: `density` (0.1), `emit_mode` (EMIT_FROM_VERTICES fastest but patterned / EMIT_FROM_FACES_FAST / EMIT_FROM_FACES slowest, no pattern / EMIT_ONE_PER_TRIANGLE + `jitter`), `min/max_height` + falloffs, `min/max_slope_degrees` + falloffs, `noise` / `noise_graph` (VoxelGraphFunction) / `noise_dimension` / `noise_threshold` / `noise_falloff` / `noise_on_scale`, `min/max_scale`, `scale_distribution`, `random_rotation`, `random_vertical_flip`, `vertical_alignment`, `offset_along_normal`, `triangle_area_threshold`, and `voxel_texture_filter_enabled` / `voxel_texture_filter_array` / `voxel_texture_filter_threshold` ("which voxel texture indices on top of which instances may spawn"). — [VoxelInstanceGenerator API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelInstanceGenerator/)
- Edits: instances get removed in-game when the player digs the ground they spawned on. Non-persistent items respawn wherever the procedural rules still hold. With `persistent` on the item and a stream that supports it (only `VoxelStreamSQLite`), instances in edited blocks are saved and "will no longer regenerate". Manual placement in the editor isn't supported. — [instancing.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/instancing.md)
- Mesh LOD for multimesh items: 3 mesh LOD slots plus distance ratios, preferred over Visibility Ranges because ranges would duplicate multimesh data. Known issue: there's a perf hit when `MultiMesh.mesh` swaps LOD (waiting on Godot PR #79833). `VoxelInstancer.mesh_lod_update_budget_microseconds` defaults to 500. `fading_enabled` / `fading_duration` (0.3 s) drive a per-instance shader parameter for fade in/out. — [instancing.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/instancing.md), [VoxelInstancer API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelInstancer/)
- Collision on multimesh items can't be set in the inspector. Build the item from a scene whose root is a physics body ("Setup from scene"). — [instancing.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/instancing.md)
- v1.7 fix: multimesh mesh-LOD distances didn't scale with `lod_index` on VoxelLodTerrain with the Octree streaming system. — [changelog](https://github.com/Zylann/godot_voxel/blob/master/doc/source/changelog.md)
- Open issues worth knowing about: #765 manual instancing, #761 LOD/multimesh-like collision shapes, #336 VoxelInstanceGenerator hard to derive from (custom generators aren't scriptable), #338 setup-from-scene doesn't set LODs beyond 0, #422 CPU spin when removing a noise texture. — [godot_voxel issues](https://github.com/Zylann/godot_voxel/issues?q=instancer)

**Transvoxel texturing (VoxelMesherTransvoxel)**
- `texturing_mode`: `TEXTURES_NONE` (0, fastest, for procedural shaders), `TEXTURES_MIXEL4_S4` (1; voxels hold 4×4-bit indices in CHANNEL_INDICES and 4×4-bit weights in CHANNEL_WEIGHTS), `TEXTURES_SINGLE_S4` (2; one 8-bit index per voxel, the mesher still outputs 4 indices + 4 weights). `TEXTURES_BLEND_4_OVER_16` is a deprecated alias of MIXEL4_S4. Other props: `transitions_enabled` (true), `edge_clamp_margin` (0.02), `mesh_optimization_enabled` / `_error_threshold` (0.005) / `_target_ratio`. — [VoxelMesherTransvoxel API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelMesherTransvoxel/)
- Mixel4 caps you at 16 textures, indices must be unique, defaults are indices (0,1,2,3) and weights (1,0,0,0), and you edit with VoxelTool TEXTURE_PAINT mode. Single mode gives 256 textures but no gradients (paint with SET). — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)
- Vertex output: `CUSTOM1.x` = 4 index bytes, `CUSTOM1.y` = 4 weight bytes (8-bit precision). The doc shader decodes with `floatBitsToUint` + shifts (`decode_8bit_vec4`), divides weights by 255, normalizes, then triplanar-samples a `sampler2DArray u_texture_array : source_color`. More than 4 textures in one cell can cause artifacts. — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)

**LOD seams / fading**
- `CUSTOM0` carries the secondary (transition) position plus border masks. The engine sets `uniform int u_transition_mask` (bits -X,X,-Y,Y,-Z,Z). The doc vertex function `get_transvoxel_position()` moves vertices and collapses inactive transition triangles to degenerate ones (`pos *= transition_cull`), so transitions share a mesh and draw call. **If you displace vertices, apply it after this.** — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)
- `lod_fade_duration` (default 0, try 0.25) + `uniform vec2 u_lod_fade` → discard-based dithered crossfade. Known issue: noisy self-shadow patches during the fade, with no fix yet. — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)
- v1.7 added manual per-LOD distance settings to VoxelLodTerrain (#379). — [changelog](https://github.com/Zylann/godot_voxel/blob/master/doc/source/changelog.md)

**Distant detail normalmaps (VoxelLodTerrain only, SDF only)**
- Properties: `normalmap_enabled` (false), `normalmap_begin_lod_index` (2), `normalmap_tile_resolution_min` (4), `normalmap_tile_resolution_max` (8 in the API; the guide suggests up to 16), `normalmap_max_deviation_degrees` (60), `normalmap_octahedral_encoding_enabled` (about 33% less memory, some quality loss), `normalmap_use_gpu` (Vulkan, generator must support it), `set_normalmap_generator_override(gen)` + `_begin_lod_index`. Tile resolution doubles at each LOD from the begin index. — [VoxelLodTerrain API](https://voxel-tools.readthedocs.io/en/latest/api/VoxelLodTerrain/)
- How it works: per Transvoxel cell it picks an axis projection and generates a tile of model-space normals by forward-difference SDF sampling (from the generator plus LOD-0 edited voxels) into an atlas, with a lookup texture. Cost: slower meshing and more memory. Tips: start at LOD 2, use a simplified override generator (no caves), use SIMD noise (FastNoise2). Works best with `full_load_mode_enabled`; without it, edited regions don't appear in distant normalmaps. GPU mode doesn't support edited voxels (falls back to CPU). Only VoxelGeneratorGraph has a GLSL variant. — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)
- Shader workarounds: `u_voxel_cell_lookup` is declared as a float `sampler2D : filter_nearest` because Godot doesn't bind integer samplers (godot#57841). Black-artifact guard: mix toward the geometry normal by `dot(n,n)`. — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)

**Shader API (uniforms the module fills in)**
- `u_lod_fade` (vec2), `u_voxel_cell_lookup` (RG8, cell index + 2-bit axis), `u_voxel_normalmap_atlas` (model-space normals), `u_voxel_virtual_texture_tile_size` (int), `u_voxel_cell_size` (float, >0 only when normalmaps exist), `u_voxel_block_size` (int), `u_voxel_virtual_texture_fade` (float 0..1, fades detail in as it arrives), `u_voxel_virtual_texture_offset_scale` (vec4, for sampling the parent LOD's sub-region while the mesh's own textures aren't ready), `u_transition_mask` (int), `u_voxel_lod_info` (int: LOD count in the high byte, LOD index in the low byte; for debugging). — [smooth_terrain.md, "Shader API reference"](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)

**Performance and limits**
- Voxel size is fixed at 1 unit. Scale the node uniformly to change it (not recommended at small scales). LOD i+1 doubles voxel and block size. Bounds rounding: mesh block 16 with 4 LODs → 256 is optimal, then 512 / 5 LODs, 1024 / 6 LODs; a 32 block means one LOD fewer. — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)
- Streaming systems: `Octree` (single viewer, spherical) vs `Clipbox` (multi-viewer, concentric boxes). — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)
- Vulkan slowdown when moving fast: Godot 4 frees mesh buffers slowly on the main thread, so thousands of 16³ chunks churning causes CPU spikes. The module spreads destruction over time, but the only real fixes are mesh block size 32, capping player speed near voxels, or a lower LOD distance. — [performance.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/performance.md)

### Inferences
- For a ~20 km planet at 1 m voxels, mesh block 32 is probably the better choice (fewer chunks, avoids the Vulkan free spikes), at the cost of more expensive edits.
- Rock/pebble scatter: multimesh items at `lod_index` 0-1 for pebbles and 2-3 for boulders, `up_mode` Sphere, slope filter for cliffs vs flats, and `voxel_texture_filter_array` to put gravel only on gravel-indexed voxels. Dug holes remove instances for free. Mark boulders `persistent` only if you switch to VoxelStreamSQLite.
- Note: with `UP_MODE_SPHERE`, min/max_height semantics on a planet (radius vs. Y) aren't documented. Test before relying on them.
- MIXEL4 has a hard 16-texture cap. Five ores + a few ground types fit, but plan the palette.

### Gaps
- No published FPS/ms or instance-count numbers for VoxelInstancer or detail normalmaps; the docs only give qualitative cost.
- I didn't confirm whether `min/max_height` uses distance from origin under `UP_MODE_SPHERE`.
- I didn't check the extension (GDExtension) build vs. module build for feature parity on 4.7.

## Godot 4 rendering features for terrain (Forward+)

### Takeaway
Texture2DArray imports support VRAM compression (BC7 with High Quality, RGTC for normals, and a per-array "Normal Map (RG Channels)" pack). Decals are clustered in Forward+ (512 clustered elements per view by default, raisable). Visibility ranges work on MultiMeshInstance3D for HLOD, but only with alpha fading. SDFGI only takes GI contributions from Static meshes, so runtime voxel chunks receive GI but don't bounce it, and edits leave GI stale.

### Cited Findings
- Texture2DArray is an import type. VRAM Compressed = S3TC/BPTC/ETC2 by platform. "High Quality" (Forward+/Mobile) uses BPTC on desktop (BC7 SDR, BC6H HDR), ASTC on mobile. Without it: DXT1 (BC1) opaque, DXT5 (BC3) transparent, normals as RGTC. Forcing Normal Map = Enable imports as RGTC. For layered textures, Channel Pack "Normal Map (RG Channels)" forces RG format on all layers (VRAM Compressed / Basis only). Mipmaps are generated on import; Mipmaps > Limit "is currently not implemented". Built-in shaders can't display arrays, so you need a custom shader. — [Godot docs: Importing images](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html)
- The same page points to `Rendering > Textures > Default Filters > Texture Mipmap Bias` for sharpening. It doesn't cover the anisotropic setting. — [Importing images](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html)
- Decals: Forward+ clusters them, with "a default limit of 512 clustered elements" per view, shared with omni/spot/area lights and reflection probes. Raise it via Rendering > Limits > Cluster Builder > Max Clustered Elements. Mobile/Compatibility: 8 decals per Mesh resource (Compatibility also 64 per view). Cost scales mainly with screen coverage. Distance Fade fully culls them. Normal Fade has a small cost. Decal filter setting: Rendering > Textures > Decals > Filter (anisotropic is best quality but slower). Decals can't change height/parallax and can't use custom shaders. — [Godot docs: Using decals](https://docs.godotengine.org/en/latest/tutorials/3d/using_decals.html)
- SDFGI: Forward+ only, "scales to any world size", has a Max Distance (keep it below camera far). More cascades cost CPU+GPU, especially with a fast camera (≤4 cascades suggested; consider disabling during fast moves). Only Static meshes contribute; Dynamic behaves like Disabled. Changed static meshes leave stale GI until the camera moves away or SDFGI is toggled. Y Scale 50/75% reduces leaks in mostly-flat scenes. — [Godot docs: Using SDFGI](https://docs.godotengine.org/en/latest/tutorials/3d/global_illumination/using_sdfgi.html)
- Visibility ranges: Begin/End/margins, Visibility Parent, Fade Mode Disabled (fastest) / Self (forces transparency) / Dependencies (HLOD). They work on MeshInstance3D, MultiMeshInstance3D and GPUParticles3D. "Godot currently only supports alpha-based fading". Can be combined with automatic mesh LOD. — [Godot docs: Visibility ranges](https://docs.godotengine.org/en/latest/tutorials/3d/visibility_ranges.html)

### Inferences
- Pack albedo+height (RGBA, BC7 High Quality) and normal (RG, RGTC/BC5-style) as separate arrays. RG normals require a z reconstruction in the shader. Put roughness/AO in a third array or in the normal array's spare channels only if you drop RG compression.
- SDFGI's assumptions about a vertical Y axis (Y Scale) and its Static-only contribution make it a poor fit for a dug, spherical voxel planet. SSAO/SSIL plus a sun with good shadows is the safer route (not verified in this pass).
- Decals for dig scorch/scuff marks are fine in Forward+ as long as the cluster limit is shared sensibly with lights.

### Gaps
- Not fetched this pass (training-knowledge only, so verify before relying on it): no tessellation shader stage in Godot 4; SSAO/SSIL parameters and cost; the exact anisotropic project setting name/level; GPUParticles3D collision (SDF/heightfield) behaviour on voxel meshes; whether POM can self-shadow or write depth correctly.

## Godot terrain projects to learn from

### Takeaway
Only Terrain3D was checked this pass, and its texture-painting page doesn't document shader internals. It confirms albedo+height and normal+roughness texture sets with height-based blending.

### Cited Findings
- Terrain3D picks textures by weighing "the height texture from each set". It stores base ID, overlay ID and blend per pixel, packs textures as albedo+height and normal+roughness, has Angle/Scale paint modifiers, and multiplies a color map for macro variation. — [Terrain3D: texture painting](https://terrain3d.readthedocs.io/en/latest/docs/texture_painting.html)
- godot_voxel's own docs carry a full triplanar + Texture2DArray MIXEL4 example shader. — [smooth_terrain.md](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)

### Gaps
- I didn't verify Terrain3D's detiling/channel layout (its "texture preparation" page wasn't fetched), HTerrain, stochastic/hex-tiling Godot shaders, or Godot triplanar POM examples. All still need sourcing.

## CC0 / free photoscanned materials and rock models

### Takeaway
ambientCG and Poly Haven are both plain CC0 (commercial use, no attribution, redistribution allowed) and between them cover regolith, gravel, rock faces, cracked ground, sand, snow and ice at 4K-16K with full PBR sets. Poly Haven even has seven "Moon Rock" scanned models and desert boulders. Megascans on Fab are **not CC0**: they're under the Fab Standard License, which allows any engine, and their free status after 2024 wasn't confirmed.

### Cited Findings
**Licences**
- ambientCG: all assets CC0 1.0. Copy/modify/distribute/commercial use OK, raw files can ship in a game, no attribution required. — [ambientCG license](https://docs.ambientcg.com/license/)
- Poly Haven: "Our assets are all licensed as CC0". Any purpose, commercial OK, no credit required, redistribution OK even in sold products. Site renders, logos and text are not CC0, and the ToS bars scraping without permission (the API has its own terms). — [Poly Haven license](https://polyhaven.com/license)
- Megascans: free to claim for everyone under the Fab Standard License until end of 2024, and claimed assets stay yours. Assets claimed via Quixel/Bridge get a Fab Standard licence. "You can use Fab Standard licensed assets in any engine or tool". Some Megascans won't move to Fab. Free Megascans claimed before 22 Oct 2024 stay on Quixel/Bridge under the old terms. — [Epic forum, Megascans update March 2025](https://forums.unrealengine.com/t/megascans-update-march-2025/2419561), [CG Channel Oct 2024](https://www.cgchannel.com/2024/10/epic-games-has-made-megascans-free-to-all-but-only-until-the-end-of-2024/), [80.lv](https://80.lv/articles/megascans-no-longer-free-after-2024/)

**ambientCG materials (queried from the public API v2, sorted by popularity)**
- Map set per material: color, displacement, normal (GL and DX), roughness, ambient-occlusion. Example Ground054: 2K-JPG zip ≈ 33 MB. — [ambientCG API Ground054](https://ambientcg.com/api/v2/full_json?id=Ground054&include=downloadData,mapData)
- Gravel / ground (1K-8K, JPG+PNG): Ground111, Ground110, Ground108, Ground112, Ground109, Ground106, Ground103, Gravel043, Gravel041, Gravel023, Ground079S, Ground081 (up to 16K). — [ambientCG gravel](https://ambientcg.com/list?q=gravel), [ambientCG ground](https://ambientcg.com/list?q=ground)
- Rock (1K-8K): Rock064, Rock063, Rock058, Rock051, Rock060, Rock035, Rock061, Rock062, Ground068. — [ambientCG rock](https://ambientcg.com/list?q=rock)
- Sand / desert: Ground054 (up to 16K), Ground080, Ground093A, Ground093C, Ground097. — [ambientCG sand](https://ambientcg.com/list?q=sand)
- Ice / snow: Ice001-Ice004 (1K-4K), Snow006, Snow008A, Snow010A, Snow011-Snow015 (1K-8K). — [ambientCG ice](https://ambientcg.com/list?q=ice), [snow](https://ambientcg.com/list?q=snow)
- A search for "regolith" returned no ambientCG materials. — [ambientCG API](https://ambientcg.com/api/v2/full_json?type=Material&q=regolith)

**Poly Haven (queried from api.polyhaven.com)**
- Texture map set: Diffuse, nor_gl, nor_dx, Rough, AO, Displacement, arm (AO/Rough/Metal packed), plus blend/gltf/mtlx. — [Poly Haven API files: rocky_trail](https://api.polyhaven.com/files/rocky_trail)
- Rocky/alien ground textures (max res): rock_face_03 (16K), dry_riverbed_rock (16K), rock_boulder_dry (16K), rocky_trail_02 (16K), rocky_trail (8K), gray_rocks (8K), rocks_ground_02 (8K), rock_05 / rock_08 / rock_01 (8K), rocky_terrain (8K), sandstone_cracks (8K, cracked ground), brown_mud_dry (8K), sand_01 (8K), coast_sand_01 (8K), aerial_beach_01 (8K), snow_01 / snow_02 (8K), granular_concrete (8K, gravel look), ganges_river_pebbles (16K). — [Poly Haven textures API](https://api.polyhaven.com/assets?t=textures)
- Rock models: moon_rock_01 … moon_rock_07 (tagged lunar, regolith, dusted), namaqualand_boulder_02-06, namaqualand_boulders_01, namaqualand_rocks_01, namaqualand_stones_01, namaqualand_cliff_01/02 (desert), rock_07, rock_09, rock_face_01/02, boulder_01, mountainside, stone_01, sand_rocks_small_01, coast_rocks_01-05, coastal_cliff_01/02/04. Model downloads include AO, arm, Diffuse, Displacement, nor_gl/nor_dx, Rough plus fbx/gltf/blend/usd. — [Poly Haven models API](https://api.polyhaven.com/assets?t=models&c=nature), [moon_rock_01 files](https://api.polyhaven.com/files/moon_rock_01)

### Inferences
- Best fit for a lunar/rocky alien planet: Poly Haven moon_rock_01-07 as instanced boulders, plus ambientCG Ground/Gravel sets and Poly Haven rocky_trail / dry_riverbed_rock / rock_face_03 as the triplanar layers. Recolor in-shader for alien tints.
- Use 2K (or 4K for hero rock faces) in arrays. All layers in a Texture2DArray must share one resolution and format, so downsample the 8-16K sources.
- Several Poly Haven rock textures are tagged moss/grass (aerial_rocks_*, mossy_rock), so skip or desaturate those for a barren world.

### Gaps
- Sketchfab CC0 scans and NASA lunar/Mars terrain data (e.g. LRO/HiRISE DEMs, which are public-domain US government works) weren't researched or sourced this pass.
- Current (2026) Fab pricing for newly listed Megascans and whether Professional-tier licences apply to studios above a revenue threshold weren't confirmed.
- Per-material physical tile size (metres) for the ambientCG and Poly Haven sets wasn't collected.

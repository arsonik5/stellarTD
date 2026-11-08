# Procedural ground scatter, terrain decals and AO for rocky ground (0-50 m)

Research date: 2026-11-08. Target engine: Godot 4.x Forward+. Searches: 17 tool calls. Items marked "background knowledge" in Inferences were not re-verified this session; treat them as leads to check.

## Rule-based scatter: density functions, placement, size distributions, burying

### Takeaway
The best documented shipped system (Horizon Zero Dawn) does not place objects directly: artist graphs output one density map per asset from world maps (height, erosion, cavity, flow, topology, variance), multiplied and curve-remapped, then a precomputed blue-noise-style point pattern with per-point thresholds turns density into deterministic positions spaced by each asset's footprint. For rock sizes, real lunar boulder fields follow a steep power law when young and drift toward an exponential distribution as they age.

### Cited Findings
- HZD is a density-based system: procedural logic does not place objects directly; this keeps results deterministic and locally stable on the GPU — [Guerrilla GDC 2017 slides (PDF)](https://www.guerrilla-games.com/media/News/Files/GDC2017_VanMuijden_GPUBasedProceduralPlacementInHorizonZeroDawn.pdf)
- HZD world data: 2D maps streamed in sections around the player, mostly BC7, ~4 MB/km² (~32 bits/m²). Height layers (terrain, objects, water) at 0.5 m; placement maps at 1-2 m with encoded meaning (e.g. Placement_Trees near 0 = edge trees, near 1 = inner trees); topology (roads, water, objects) at 0.5 m; natural/variance maps: erosion (wear, flow, deposition), terrain cavity, water flow, variance for colour/density/lichen, mostly generated in WorldMachine and rarely painted; ecotope maps A-H at 2 m — [Guerrilla slides via SlideShare](https://www.slideshare.net/slideshow/gpubased-procedural-placement-in-horizon-zero-dawn/72897079)
- HZD operators: node graphs (like shader graphs) output one density per asset/group; multiply to mask (trees × object × water × road masks), inverse nodes make clearings, curves remap, shared subgraphs reused across ecotopes. Several thousand layers merged down to several hundred active around the player — [SlideShare](https://www.slideshare.net/slideshow/gpubased-procedural-placement-in-horizon-zero-dawn/72897079)
- HZD density stage: compute shader evaluates each layer into a 64×64 density texture per block; block size scales with footprint, 128×128 m for large trees, 32×32 m for grass — [SlideShare](https://www.slideshare.net/slideshow/gpubased-procedural-placement-in-horizon-zero-dawn/72897079)
- HZD discretisation: a precomputed pattern of 2D points each with an implicit threshold (not a Bayer grid); thresholds evenly spread and ordered to maximise distance between consecutive thresholds (so any density level gives well-spaced points); pattern scaled so spacing equals the asset footprint; user noise offset breaks line patterns at high density; steps: range test, threshold test, heightmap position lookup, normal construction, append. ~10 µs for this stage — [SlideShare](https://www.slideshare.net/slideshow/gpubased-procedural-placement-in-horizon-zero-dawn/72897079)
- HZD collisions between layers: each asset has a footprint (trees ~6 m apart, undergrowth ~1 m). Same-footprint layers use "layered dithering": density stored as two-sided [min,max] ranges so each sample point picks at most one layer, avoiding overlaps with no GPU readback. Stacks often exceed 20 same-footprint layers. Cross-footprint collision via readback was considered and not shipped — [SlideShare](https://www.slideshare.net/slideshow/gpubased-procedural-placement-in-horizon-zero-dawn/72897079); "Two values in density map, two-sided threshold test" — [Guerrilla PDF](https://www.guerrilla-games.com/media/News/Files/GDC2017_VanMuijden_GPUBasedProceduralPlacementInHorizonZeroDawn.pdf)
- HZD placement: builds a basis + bounding box per point using pattern index/ID for deterministic RNG; per-object tilt, rotation, elevation applied; output is one 3×4 world matrix per instance (~7 µs) — [SlideShare](https://www.slideshare.net/slideshow/gpubased-procedural-placement-in-horizon-zero-dawn/72897079)
- Far Cry 5 (Ubisoft, GDC 2018, Étienne Carrier): Houdini tools generated biomes, terrain texturing, freshwater networks, cliff rocks, fog density map; vegetation where "each species has its own reason for growing at a specific location"; grass oriented on a wind vector map — [GDC Vault](https://gdcvault.com/play/1025557/Procedural-World-Generation-of-Far); [PlayStation Blog](https://blog.eu.playstation.com/2018/03/22/how-the-stunning-open-world-of-far-cry-5s-hope-county-montana-was-created/); [SideFX talk page](https://www.sidefx.com/learn/talks/procedural-world-generation-far-cry-5/). Companion talk "Terrain Rendering in Far Cry 5" (Jeremy Moore) covers procedural cliffs and displacement — [GDC Vault](https://gdcvault.com/play/1025480/Terrain-Rendering-in-Far-Cry)
- Ghost of Tsushima grass: terrain tiled, compute shaders generate grass per render tile, writing compact per-blade data (position, facing, wind, shape); procedural Voronoi groups blades into clumps (useful precedent for clustering) — [GDC Vault](https://gdcvault.com/play/1027214/Advanced-Graphics-Summit-Procedural-Grass) (summary via search results; talk itself is gated)
- Lunar boulders: cumulative block size-frequency distributions go from power law in young populations (<~50 Myr) to exponential in older ones (catastrophic rupture model, Ruesch et al.; calibrated on Tycho, measured from LROC NAC images) — [INAF open access PDF](https://openaccess.inaf.it/bitstreams/093842b4-b20f-44e2-a7df-9c0995e976c8/download); [arXiv 2009.00957](https://pdf.arxiv.org/pdf/2009.00957)
- Linné crater ejecta: ~12,000 boulders ≥4.4 m mapped on LROC images; cumulative number per km² fits a power law with index −4.03 (+0.09/−0.10) — [Pajola et al., arXiv 1812.00590](https://arxiv.org/abs/1812.00590v1)
- Caution: on small bodies (Vesta) a Weibull fit may beat a power law, and fitted exponents depend mostly on the size range measured — [arXiv 2112.13879](https://web3.arxiv.org/abs/2112.13879)

### Inferences
- For Stellar TD the HZD recipe maps well to a sphere if density inputs are evaluated in the planet's local tangent frame per chunk: slope = angle between voxel surface normal and radial up (not world Y), cavity/curvature from the density field, "distance to cliff" as a blurred slope mask, crater rims/ejecta as a radial falloff from each crater centre. Multiply masks, remap with curves, per-asset footprint.
- Size distribution: sample radius by inverse-CDF of a cumulative power law N(>D) ∝ D^−b. Lunar measurements give b ≈ 3-4 for fresh crater ejecta (Linné: 4.03); use steeper/fresher near young craters and an exponential-ish tail on old plains. This gives many pebbles, few boulders, which is what reads as "real".
- Clustering: HZD-style threshold pattern gives blue-noise spacing; add clusters by modulating density with a low-frequency Voronoi/worley field (Ghost of Tsushima uses Voronoi clumps for grass) and by spawning child pebbles around each boulder (debris aprons).
- Alignment and burying (background knowledge, not sourced here): align the instance up-axis to a blend of surface normal and radial up (small rocks follow the normal, big boulders mostly radial), random yaw, small tilt; sink each rock by ~10-40% of its height along the normal so the widest part sits at or below ground. A rock sitting on its lowest point looks placed; one cut by the ground looks embedded.
- Godot: no GPU compute-driven placement is built in, but a RenderingDevice compute shader (or plain GDScript/C++ on a worker thread for small chunks) can write MultiMesh transform buffers; `RenderingServer.multimesh_set_buffer` accepts a packed float array of 3×4 transforms, the same layout HZD outputs. Determinism by seeding from chunk id + point index lets chunks regenerate identically.

### Gaps
- No primary source found on lunar regolith pebble/cobble size-frequency at cm scale (Surveyor/Apollo surface counts); only boulder-scale (metres) LRO data was found.
- No source found that quantifies how much to bury rocks or how games do it; the burying numbers above are background knowledge.
- Star Citizen ground-scatter specifics: only secondhand fan-wiki/news material found (Planet Tech v4/v5 "improved object scattering", data-driven rules) — [starcitizen.tools](https://starcitizen.tools/CitizenCon_2019_-_Terra_Firmer). No CIG primary technical source.
- Curvature/distance-to-cliff inputs were not explicitly named in HZD material; cavity and erosion maps are the nearest equivalents.

## Rendering: instancing, LODs, impostors, fade, shadow budgets, instance counts

### Takeaway
Shipped numbers: HZD runs 100,000+ placed objects of 500+ asset types for ~250 µs average GPU busy time, with placement stages around 10 µs each. In Godot the main tools are MultiMeshInstance3D per chunk, visibility ranges (alpha fade is Forward+ only and forces transparency during fade; dithering needs a custom material), and turning shadows off for small debris.

### Cited Findings
- HZD scale: 500+ asset types, 100,000+ objects in the scene, ~250 µs average GPU busy load; generate stage ~10 µs, placement ~7 µs; all results copied to CPU in one transfer to avoid hundreds of µs of sync — [Guerrilla PDF](https://www.guerrilla-games.com/media/News/Files/GDC2017_VanMuijden_GPUBasedProceduralPlacementInHorizonZeroDawn.pdf); [SlideShare](https://www.slideshare.net/slideshow/gpubased-procedural-placement-in-horizon-zero-dawn/72897079). One slide version says ~250 placed "per frame" while moving; it conflicts with the µs unit, don't conflate.
- Ghost of Yōtei doubled the grass and renderable items its GPU compute renderer may produce, processing instances without CPU involvement — [PlayStation Blog](https://blog.playstation.com/?p=411201) (via search summary)
- Unreal PCG Runtime Generation creates and cleans up components near "PCG Generation Sources"; cleanup radius ≥ generate radius; Epic recommends pairing it with Hierarchical Generation so finer detail only spawns where needed; some nodes can run on GPU — [Epic docs: PCG generation modes](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-pcg-generation-modes-in-unreal-engine); [Epic docs: PCG framework](https://dev.epicgames.com/documentation/unreal-engine/procedural-content-generation-framework-in-unreal-engine). Forum reports of trouble at scale (e.g. 40k PCG tasks) — [Unreal forum](https://forums.unrealengine.com/t/pcg-achieving-parity-with-landscape-grass-keep-getting-too-many-instaces/1960549)
- Godot visibility ranges: fade mode Disabled is cheapest; Self and Dependencies force transparent rendering during the fade and are Forward+ only (Mobile/Compatibility act as Disabled without hysteresis). Godot only supports alpha-based fading; dithering requires separate materials per LOD using distance/object dither — [Godot docs: visibility ranges](https://docs.godotengine.org/en/4.2/tutorials/3d/visibility_ranges.html); [GeometryInstance3D](https://docs.godotengine.org/en/4.2/classes/class_geometryinstance3d.html)
- Godot: `cast_shadow = off` recommended for small geometry unlikely to cast noticeable shadows, "such as debris"; unique materials per LOD have their own cost — [GeometryInstance3D docs](https://docs.godotengine.org/en/4.2/classes/class_geometryinstance3d.html)

### Inferences
- A MultiMeshInstance3D has one visibility range for all its instances, so per-instance distance culling/fade needs either small chunks (e.g. 16-32 m cells, matching HZD's 32 m block for small stuff) each with their own range, or a vertex-shader scale-to-zero/dither by distance. Dither in the shader (discard against a screen-space noise vs. distance) avoids the transparent pass entirely.
- Practical Godot tiering (inference): pebbles 0-15/20 m, no shadows, single LOD, dither-out; rocks 0-50 m, shadows only in the nearest cascade(s), mesh auto-LOD; boulders long range, shadows on, part of the terrain silhouette. Impostors are rarely worth it for rocks under 50 m; they matter for boulders seen far away.
- Godot's built-in mesh LOD (auto-generated on import) applies to MultiMesh too (background knowledge; verify on the version in use).

### Gaps
- No primary source gave per-frame instance counts for Ghost of Tsushima, Far Cry 5 or Star Citizen.
- No source checked on Godot's indirect draw status in 2026 (no compute-driven indirect draw is assumed per the brief).

## Blending scatter into terrain

### Takeaway
Common techniques are dithered depth-based edge blending, pixel depth offset (Unreal), and shading the rock's lower part with the terrain material (CryEngine-style "terrain layer blending into objects"). A ready MIT Godot shader exists for dithered terrain-mesh blending, with known shadow artifacts.

### Cited Findings
- Unreal community material function blends rock edges into ground using only dithering, claimed cheap — [Unreal forum](https://forums.unrealengine.com/t/distance-field-edge-blending/89617)
- Godot "Terrain Mesh Blending with Dithering" shader (MIT): blends meshes into terrain by changing depth with dithering; uses `depth_draw_alpha_prepass` to avoid non-convex mesh problems; lists shadow artifacts as a known problem — [godotshaders.com](https://godotshaders.com/shader/terrain-mesh-blending-with-dithering/)
- Pixel depth offset used to blend two surfaces so texturing stays at a consistent scale independent of rock scale — [Polycount](https://polycount.com/discussion/comment/2427535); PDO artifacts reported (black artifacts with heightmap-driven PDO) — [Unreal answers](https://answers.unrealengine.com/questions/906492/view.html)
- CryEngine has a documented "Terrain Layer Blending into Objects" feature with soft depth test, distance ratio and range parameters — [CryEngine docs](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756816/pages/36340007)
- Deferred approach (BotW-style) blending by modifying depth/G-buffer — [Unity forum](https://discussions.unity.com/t/solved-zelda-botw-terrain-intersection-blending/760769)

### Inferences
- Cheapest robust option in Godot Forward+ without screen reads: in the rock shader, compute height above ground along the instance's up axis (known at placement: store burial depth in INSTANCE_CUSTOM) and lerp albedo/roughness toward the terrain's triplanar material (same textures, same world-space UVs) over the bottom 5-20 cm, plus add dust in upward-facing crevices (normal·radial-up). This needs no depth texture and no transparency.
- Contact darkening: a darker band near the ground line on the rock, plus a small projected decal or a baked "contact AO" vertex term in the terrain under large boulders.
- Avoid real transparency for blending; Godot Forward+ transparent objects don't get SSAO and sort poorly (background knowledge).

### Gaps
- No primary AAA talk found on "terrain-matched rock shading"; sources are community and engine docs.

## Terrain decals

### Takeaway
Godot Forward+ decals are clustered: count is limited by performance with a default cap of 512 clustered elements (decals + lights + probes) in view, raisable in settings; cost scales mainly with screen coverage. Normal-only decals are possible.

### Cited Findings
- Forward+ uses clustering for decals; default limit 512 clustered elements in view (omni, spot, decals, reflection probes); raise via Rendering > Limits > Cluster — [Godot docs: using decals](https://docs.godotengine.org/en/4.1/tutorials/3d/using_decals.html)
- Decal performance mostly depends on screen coverage, then count; a few large screen-covering decals cost more than many small scattered ones — [Godot docs](https://docs.godotengine.org/en/4.1/tutorials/3d/using_decals.html)
- Normal map impact multiplied by albedo alpha; normal-only decal = albedo texture loaded with albedo_mix 0.0; Normal Fade > 0 adds a small cost — [Godot Decal class](https://docs.godotengine.org/en/4.2/classes/class_decal.html)
- Decals supported in Forward+ and Mobile, not Compatibility; older 4.0 docs gave a Mobile limit of 8 decals per mesh resource — [Godot Decal class 4.0](https://docs.godotengine.org/en/4.0/classes/class_decal.html)

### Inferences
- Use Decal nodes sparingly for unique features (crater rims, footprints near player, crack patches at dig sites). For widespread dust drifts, cracks and crater ejecta rays, put them in the terrain shader as procedural/world-space masks instead, since they cover a lot of screen and would cost more as decals.
- Footprints: a ring buffer of small decals near the player (well under 512) is fine. Godot decals project along their box; on a sphere orient each decal's -Y to the local radial down.
- Forward vs. deferred: Godot Forward+ decals are applied in the forward pass per cluster, so they can modify albedo/normal/ORM/emission without a G-buffer (background knowledge consistent with the clustering docs).

### Gaps
- No AAA source collected on crater-rim or dust-drift decal workflows specifically.

## Ambient occlusion

### Takeaway
Voxel/isosurface engines commonly bake cheap per-vertex AO by sampling the density field around each vertex (count solid vs. air in a small neighbourhood, apply a curve). Godot gives SSAO (ambient-only by default, with light_affect and ao_channel_affect knobs) and SSIL in Forward+, plus a per-material AO_LIGHT_AFFECT.

### Cited Findings
- Surface Nets per-vertex AO: sample the density function in a 3×3×3 region around each vertex, count terrain vs. air samples, apply a curve; reduces the blocky look of Surface Nets/Dual Contouring — [jedjoud10 blog](https://jedjoud10.github.io/blog/per-vertex-ao-surface-nets); [jedjoud10 blog 2](https://jedjoud10.github.io/blog/surface-nets-ao)
- Minecraft-style per-vertex AO from side/corner occupancy (cube worlds only) — [0fps](https://0fps.net/2013/07/03/ambient-occlusion-for-minecraft-like-worlds/)
- Volumetric AO approximated from the distribution of density values in a neighbourhood — [Volumetric ambient occlusion paper (PDF)](https://dugi-doc.udg.edu/bitstream/10256/12313/1/Volumetric-ambient-occlusion.pdf); Houdini has a Volume Ambient Occlusion node — [SideFX docs](https://sidefx.com/docs/houdini/model/volumeambientocclusion.html)
- Godot Environment SSAO: radius 1.0, intensity 2.0, power 1.5, detail 0.5, horizon 0.06, sharpness 0.98, light_affect 0.0 (SSAO only on ambient light by default, "in real life, ambient occlusion only applies to indirect light"), ao_channel_affect 0.0 (how much SSAO shows on materials with an AO texture). SSIL: off by default, Forward+ only, radius 5.0, intensity 1.0, normal_rejection 1.0 — [Godot Environment class](https://docs.godotengine.org/en/stable/classes/class_environment.html)
- Per-material `AO_LIGHT_AFFECT` built-in in spatial shaders (forum example, Godot 4.5) — [Godot forum](https://forum.godotengine.org/t/ursc-and-ssao-getting-psx-shaders-to-work-with-ambient-occlusion/123317)

### Inferences
- On an airless body, nearly all light is direct sun; SSAO at default light_affect 0 will barely show in sunlit areas. For lunar look, raise `ssao_light_affect` a little (e.g. 0.2-0.4) and rely on real shadows for contact, or bake density AO into vertex colour and feed it as AO with a non-zero AO_LIGHT_AFFECT. Tune by eye; these numbers are not sourced.
- Density-field AO fits Stellar TD's voxel mesher directly: compute it at mesh build time (it's free to recompute when a chunk is re-meshed after digging). A larger-radius sample (e.g. 5×5×5 or a few rays) catches crater floors and trenches; the 3×3×3 version catches crevices.
- Scatter instances can read the same baked AO (sampled at placement) and darken themselves in cavities; cheaper than relying on SSAO.
- GTAO, bent normals, sun micro-shadowing: Godot's SSAO is its own implementation; bent normals and micro-shadowing would be custom shader work (background knowledge).

### Gaps
- No source collected on Transvoxel-specific AO or AO across LOD seams.
- No primary source collected for GTAO or micro-shadowing (e.g. Activision/UE talks) this session.

## Dug terrain: scatter removal and fresh faces

### Takeaway
No shipped-game technical source was found on what happens to scatter when ground is removed. Systems that are deterministic and per-chunk (HZD, Unreal PCG runtime generation) make "regenerate the chunk from rules" the natural answer.

### Cited Findings
- HZD placement is fully real-time and generated from logic as the player moves, with no offline bakes; deterministic and locally stable, so moving terrain/rivers/gameplay doesn't need redressing; edit re-evaluation cost not given — [SlideShare](https://www.slideshare.net/slideshow/gpubased-procedural-placement-in-horizon-zero-dawn/72897079)
- Unreal PCG Runtime Generation generates and cleans up around sources; claims that PCG "adapts" to terrain edits come only from a third-party tutorial — [Epic docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-pcg-generation-modes-in-unreal-engine); [strayspark blog](https://www.strayspark.studio/blog/ue5-pcg-framework-getting-started)

### Inferences
- Recommended approach for a voxel dig (inference): on each edit, find scatter chunks whose bounds overlap the edit sphere; for instances inside the removed volume (or whose base point's density is now air, or whose support is gone), either delete them or convert the few big ones into physics debris (RigidBody) and pool them; then re-run placement for that chunk with a "fresh dig" mask so new rubble spawns on the new faces. Save only an edit mask/seed, not the instances, so save files stay small; regeneration is deterministic.
- Fresh faces: store a per-voxel "exposed time"/"fresh" byte (or a separate 3D mask) written by the dig; the terrain shader shows less dust, sharper/brighter rock and more contrast where fresh, fading over game time; spawn rubble/pebbles at the base of new slopes (talus) by adding "below a fresh steep face" to the density rules.

### Gaps
- No technical source from Astroneer, Deep Rock Galactic, Teardown, No Man's Sky or similar on scatter-after-dig handling.

## Asset creation: rock kits, licensing, procedural rocks, poly budgets

### Takeaway
Megascans is now on Fab: assets claimed under the Fab Standard License may be used in any engine including commercially, while assets from the old Quixel/Bridge route under the Epic Content License are Unreal-only. Current 2026 pricing/free status could not be confirmed.

### Cited Findings
- Until end of 2024 Megascans were free on Fab under the Fab Standard License for "all engines and tools", commercial use allowed per the EULA; assets added to a library during that promotion stay usable under the Standard License after it ended — [CG Channel](https://www.cgchannel.com/2024/10/epic-games-has-made-megascans-free-to-all-but-only-until-the-end-of-2024/); [Epic forum FAQ](https://forums.unrealengine.com/t/quixel-to-fab-transition-faqs/2033839)
- Old Quixel/Bridge downloads fall under the Epic Content License (free only in Unreal); Fab Standard assets may be used in any engine or tool — [Epic forum, March 2025 update](https://forums.unrealengine.com/t/megascans-update-march-2025/2419561)
- Megascans no longer free after 2024 — [80.lv](https://80.lv/articles/megascans-no-longer-free-after-2024/)

### Inferences
- Poly Haven and ambientCG publish CC0 assets (background knowledge; licence pages not fetched this session). CC0 removes all licence risk for a commercial game.
- Procedural rocks in Blender (fits the repo's existing headless Blender pipeline, see `blender-game-models`): displaced/voronoi-cracked icospheres with boolean cuts, then bake normals from high to low. Typical budgets (background knowledge, verify): pebble 50-200 tris, rock 300-1500, boulder LOD0 2-8k with 2-3 LODs. A handful (8-16) of rock meshes, varied by non-uniform scale and rotation and terrain-matched shading, usually reads better than many unique meshes.

### Gaps
- Poly Haven / ambientCG catalogue sizes and licence pages not fetched.
- No source on current (2026) Fab Megascans pricing.
- No sourced poly budgets per LOD for scatter rocks.

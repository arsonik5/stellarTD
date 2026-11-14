# Shipped games with voxel / destructible / procedural-planet terrain: how they render high-fidelity ground

Researched 2026-11-08. About 15 tool calls; several primary pages (GDC Vault videos, Unreal developer interview, blog.voxagon.se, Keen Games' talks) could not be read in full. Items tagged **[unverified / from prior knowledge]** come from the researcher's background knowledge, not from a page fetched this session. Treat them as leads to check, not facts.

## 1. How each game textures its voxel or planet surface (triplanar vs UV, materials per pixel, blending, sources, resolution)

### Takeaway
The only game with a fully documented voxel-material schema is Space Engineers 1. It uses triplanar maps (separate side and top textures), PBR packed as ColorMetal + NormalGloss + Ext, and up to three far texture sets plus a flat far colour per material. SE2 (VRAGE3) adds height-aware transition masks that blend across several triangles instead of one, plus tessellation and parallax. Star Citizen v5 drives texture choice and blending from planet data layers (temperature, humidity, geology, soil). For DRG, Enshrouded, Astroneer, Empyrion, Dual Universe, NMS and Satisfactory no primary texturing detail was found this session.

### Cited Findings
**Space Engineers 1 (VRAGE2, live since 2013; schema as documented on the community modding wiki, page current 2026)**
- Each voxel material has close-range textures with separate XZ (side) and Y (top) variants: `ColorMetalXZnY`/`ColorMetalY` (albedo + metalness), `NormalGlossXZnY`/`NormalGlossY` (normal + gloss), `ExtXZnY`/`ExtY` (extension maps). Y falls back to XZ if undefined. That is a triplanar split with a distinct top projection. — [SE wiki: VoxelMaterial Definition](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- Three far levels per material: `Far1Distance`/`Far1Scale` (default scale 400), `Far2Distance`/`Far2Scale` (default 2000), each with optional separate texture sets, and `Far3Distance`/`Far3Scale` (7000) where a flat `Far3Color` (RGBA) takes over. — [SE wiki](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- Tiling ladder: `InitialDistance` 5 m, `InitialScale` 2, `ScaleMultiplier` 4, `DistanceMultiplier` 4, `TilingScale` 32. So the texture scale is multiplied by 4 each time the distance goes up 4x, a mip-like texture-scale cascade that also hides repetition. A `SimpleTilingSetup` overrides these at low/medium shader quality. — [SE wiki](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- `BareVariant` (e.g. dirt under grass) and `DamagedMaterial` (the material it turns into when hit by impacts, explosions or drills) are per-material fields. — [SE wiki](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- `ColorKey` lets planets recolour a surface material when ore lies beneath it (an ore-hint tint). — [SE wiki](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- Engine limit of 128 active voxel materials (8-bit-ish material id per voxel), reported on Keen's support forum. — [Keen support thread](https://support.keenswh.com/spaceengineers/pc/topic/22619/vote/add/1) (user report)

**Space Engineers 2 (VRAGE3, early access 2025)**
- Official: the "GPU-driven pipeline delivers ... raytracing, global illumination, tessellated terrain, and parallax mapping." — [SE2 game guide](https://2.spaceengineersgame.com/game-guide/)
- Patch note (via search snippet): "In SE1, material blending between voxels occurred simply over the surface of a single voxel (one triangle). In SE2, these transitions can extend across multiple voxels and triangles. Additionally, a transition mask with height information allows for significantly more natural-looking material transitions." — [SteamDB patch notes](https://steamdb.info/patchnotes/19659200) (snippet only; full note not read)
- New VRAGE3 material system with PBR variants including **parallax, alpha cutout, triplanar, transparent**, authored per target asset type (models, voxels). — [Jan Hloušek guest post, 2023-04-24](https://blog.marekrosa.org/2023/04/guest-post-jan-hlousek-vrage3/)
- "New tiling methods" to raise texture resolution without visible repetition or large memory cost (stated for armour; no voxel-specific claim). — [Hloušek, 2023-04-24](https://blog.marekrosa.org/2023/04/guest-post-jan-hlousek-vrage3/)
- Keen's tech page: voxel terrain is "multi-material, mineable and fully destructible", multiple LOD levels, procedurally generated in real time. — [Keen tech page](https://welcometothejungle.com/en/companies/keen-software-house/tech)
- SE2 adds overhangs; SE1 terrain was "largely restricted to pyramid-shaped hills and simple rock formations." — [Marek's dev diary, 2025-08-21](https://2.spaceengineersgame.com/mareks-dev-diary-august-21-2025/)

**Star Citizen (Planet Tech v4 shipped Alpha 3.8, Dec 2019; v5 "Genesis" in staged rollout, first Evocati preview autumn 2025)**
- v4: "terrain texture blending, objects scattering and biome transitions", with biome selection driven by temperature and humidity maps. — [SC Wiki: Planet Tech v4](https://starcitizen.tools/Planet_Tech_v4) (edited 2026-04-14)
- v5: planetary data layers (temperature, humidity, geology, soil type, soil depth, nutrients; derived sunlight exposure and slope aspect) drive the assignment and blending of terrain textures, and the blending is "tiled without visible repetition." — [SC Wiki: Planet Tech v5](https://starcitizen.tools/Planet_Tech_v5)
- Status conflict: the wiki lists v5 as "planned for Alpha 4.11 through 1.0"; Nyx I was shown at CitizenCon 2025 (2025-10-11) as the first v5 planet, expected 2026. — [SC Wiki v5](https://starcitizen.tools/Planet_Tech_v5)

**Astroneer (UE4, System Era)**
- Terrain is "procedurally generated in a uniquely rendered voxel engine" built into UE4; the low-poly style was chosen partly to keep content cost down, and a developer said the style means "no textures in the game" (flat/vertex-coloured shading). — [Wikipedia: Astroneer](https://en.wikipedia.org/wiki/Astroneer), [IGF page](https://igf.com/astroneer). The Unreal developer interview returned 403.

**No Man's Sky (Hello Games, own engine)**
- GDC 2017 "Continuous World Generation in No Man's Sky" (Innes McKendrick) covers the pipeline voxel generation → polygonization → texturing → population → simulation. — [GDC Vault](https://www.gdcvault.com/play/1024265/Continuous-World-Generation-in-No), [Game Developer](https://gamedeveloper.com/programming/video-how-continuous-world-generation-works-in-i-no-man-s-sky-i-)
- **[unverified / from prior knowledge]** NMS uses triplanar-mapped terrain with a small palette of tiling materials per planet, blended per vertex; the talk reportedly uses dual contouring rather than marching cubes. Not confirmed from a fetched source.

**Enshrouded (Keen Games, Holistic engine; EA Jan 2024, 1.0 Oct 2025/2026 — see gap)**
- Own "Holistic" engine with a renderer generating the voxel terrain in real time; won Best Technical Achievement at the German Developer Awards. — [PCGH 1.0 tech test](https://www.pcgameshardware.de/Enshrouded-Spiel-74267/Specials/1-0-Technik-Test-Benchmarks-Release-1556566/), [German Computer Game Award page](https://deutscher-computerspielpreis.de/chronik/enshrouded/?lang=en)
- World built with voxel brushes, negative stamps, voxel objects and splines, then a procedural "beautify" pass. — [Gameoneer on Keen devlog](https://gameoneer.com/enshrouded-developers-showcase-how-they-developed-a-detailed-world/)
- Meshing algorithm unknown publicly; community guesses dual contouring. — [r/VoxelGameDev, Apr 2024](https://lr.in.psf.lt/r/VoxelGameDev/comments/1c453u3/isosurface_algorithm_used_by_keen_games_in) (speculation)

**Teardown (Tuxedo Labs)**
- Not meshed: objects are rasterised as bounding boxes and a ray is traced through the voxel volume in the fragment shader (modified DDA, mip chain as dense octree). — [third-party breakdown](https://juandiegomontoya.github.io/teardown_breakdown.html)
- Each voxel has a material/palette entry rather than textures; CEO: turning ray tracing off makes the screen black because every pixel's colour is ray traced. — [TechRadar](https://www.techradar.com/gaming/consoles-pc/ray-tracing-is-so-crucial-to-teardown-that-the-world-goes-black-if-you-turn-it-off)
- Large levels ≈ half a billion voxels (per Gustafsson's blog, via PCGH). — [PCGH tech test](https://www.pcgameshardware.de/Teardown-Spiel-73677/Specials/PC-Game-Test-Benchmark-Voxel-Dynamic-Destruction-1394545/2/)

**Deep Rock Galactic (UE4, Ghost Ship)**
- No developer source found. Community guess: ~0.5 m voxels, marching-cubes/dual-contouring style meshing, real-time remeshing on dig. — [r/howdidtheycodeit, Jul 2024](https://lr.eu.psf.lt/r/howdidtheycodeit/comments/1e69166/how_did_they_code_the_pathfinding_implementation) (speculation)

### Inferences
- The SE1 schema is a ready-made blueprint for a Transvoxel planet: per material, triplanar side/top textures, a 4x tiling-scale cascade with distance, 2–3 far texture sets and a flat far colour. It is cheap and shipped on very old hardware.
- SE2's step up over SE1 is mainly two things: height-based blend masks across several triangles (instead of a per-triangle vertex blend), and tessellation/parallax. That is the clearest sign of what "SE1 looks dated, SE2 looks modern" comes from at close range.
- Data-driven texture choice (Star Citizen v5) is how big planets avoid "same material everywhere": the material is picked from slope, moisture, geology masks rather than painted.

### Gaps
- No primary detail on texture resolutions for any title (SE1 stock textures are 2k DDS per community knowledge, unverified).
- Material count per pixel: SE1 is believed to blend up to 3 materials per triangle (one per vertex) **[unverified]**; SE2, NMS, Enshrouded unknown.
- No primary detail for Empyrion, Dual Universe (Novaquark, voxel planets, shut down/relaunched), Satisfactory (UE Landscape, not voxel), DRG, Astroneer shading.
- Whether photogrammetry is used: no source found for any title.

## 2. How they hide tiling (macro/detail, distance blending, stochastic tiling)

### Takeaway
SE1 hides tiling with a distance-driven texture-scale cascade (scale x4 per distance x4) plus separate far texture sets and a flat far colour. Star Citizen v5 claims non-repeating tiling driven by planet data. SE2 mentions "new tiling methods" without saying what they are. No title was found to document stochastic (hex/Heitz-Neyret) tiling.

### Cited Findings
- SE1: `InitialDistance` 5, `InitialScale` 2, `ScaleMultiplier` 4, `DistanceMultiplier` 4, `TilingScale` 32; Far1/Far2 at scales 400/2000 with their own textures; Far3 flat colour at scale 7000. — [SE wiki](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- SC v5: texture blending "tiled without visible repetition"; distance terrain colour uses data about assets not yet loaded (trees, grass) so distant ground colour matches what will stream in. — [SC Wiki v5](https://starcitizen.tools/Planet_Tech_v5)
- VRAGE3: "new tiling methods" to avoid visible repetition without much memory cost. — [Hloušek 2023](https://blog.marekrosa.org/2023/04/guest-post-jan-hlousek-vrage3/)

### Inferences
- The SC v5 trick (bake the average colour of scatter/flora into the distance terrain colour) is directly useful: it stops the "grass vanishes and ground goes brown" band at the scatter cull distance.
- For a hobby Transvoxel planet, the SE1 approach (same texture sampled at two scales and blended by distance, plus a far colour) is the proven low-cost baseline; stochastic tiling would be an addition no source here confirms in a shipped voxel game.

### Gaps
- No talk or post found that names stochastic/hex tiling or texture bombing in any of these games.
- NMS anti-tiling approach not confirmed.

## 3. Scatter (pebbles, rocks, grass, debris) on terrain and on dug surfaces

### Takeaway
SE1 attaches GPU foliage (grass blades or pebbles) to voxel materials by density per m², so when digging changes the material or removes the surface, the foliage follows the material. SE2 makes trees and rocks destructible. Star Citizen v5 places flora by competition rules and rocks by erosion simulation. No game was found that documents regenerating scatter on freshly dug faces.

### Cited Findings
- SE1: `FoliageDensity` (blades or pebbles per m², times the player's grass-density setting), `FoliageType` 0 = grass, 1 = pebbles, `FoliageScale`, `FoliageRandomRescaleMult`, `FoliageColorTextureArray` (alpha = grass mask; pebbles colour only), `FoliageNormalTextureArray`. — [SE wiki](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- SE1: `BareVariant` gives the material underground beneath foliage-bearing surface materials (e.g. dirt under grass), and `DamagedMaterial` is what a material turns into when drilled or blasted. So dug ground switches to a bare material with no foliage. — [SE wiki](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- SE2 VS2 (2025-11-10 post): trees and rocks are fully destructible and react to impacts; flora generation improved. — [SE2 VS2 flora post](https://2.spaceengineersgame.com/space-engineers-2-voxel-density-vs2-flora/)
- SC v5: flora distributed by competition rules and override variables; physics-interactable assets can be in distributions; rocks and debris placed by erosion simulation; denser rock formations got more physically accurate placement (March 2025 monthly report). Loose rock gathers under cliffs and along slopes. — [SC Wiki v5](https://starcitizen.tools/Planet_Tech_v5), [The Impound guide](https://theimpound.com/pages/star-citizen-starchitect-planet-tech-v5)
- SC v4: custom particles can spawn locked to the terrain surface and flow around contours under wind/gravity. — [SC Wiki v4](https://starcitizen.tools/Planet_Tech_v4)

### Inferences
- The SE1 pattern (scatter keyed to the surface material, dug voxels switch to a bare/damaged material) solves "pebbles floating over a hole" for free: the scatter is regenerated from the material on the new mesh. It fits a Transvoxel chunk remesh well: rebuild the chunk's scatter list whenever its mesh is rebuilt.
- Placement rules from SC v5 (rocks at slope bases, by erosion/slope masks) are a cheap heuristic: weight pebble density by slope and concavity/AO.

### Gaps
- No source on whether Enshrouded, DRG or NMS regenerate or delete scatter on dug faces (NMS is widely observed to delete flora in a dug radius **[unverified]**).
- No scatter instance counts or density numbers beyond SE1's per-m² field.

## 4. Lighting tricks (AO, micro-shadowing, specular occlusion, GI, contact shadows, POM/tessellation)

### Takeaway
The documented big levers are dynamic GI (SE2 ray traced; Enshrouded voxel-based diffuse and specular GI; Teardown fully ray traced voxels), good sun shadows at planet scale (VRAGE3 cascades), and parallax/tessellation on terrain (SE2). No title documented micro-shadowing or specular occlusion this session.

### Cited Findings
- VRAGE3: "Dynamic Global Illumination using raytracing"; GPU-driven pipeline with GPU-issued draw calls on DX12. — [Hloušek 2023](https://blog.marekrosa.org/2023/04/guest-post-jan-hlousek-vrage3/)
- VRAGE3 sun shadows: cascades for planetary distances, 2x2 edge-aware AA pass, Fibonacci-spiral Poisson sampling, full-kernel sampling in each cascade during blends, larger minimum kernel at steep angles against moiré, shadow origin stabilised on a pivot (cockpit) not the camera. — [Hloušek 2023](https://blog.marekrosa.org/2023/04/guest-post-jan-hlousek-vrage3/)
- SE2: tessellated terrain and parallax mapping. — [SE2 game guide](https://2.spaceengineersgame.com/game-guide/)
- Enshrouded: a talk "Dynamic Diffuse & Specular Global Illumination in Enshrouded" is listed at the Graphics Programming Conference (speaker attribution on the listing looked inconsistent). Light propagates through terrain voxels and player builds. — [Khronos GPC listing](https://www.khronos.org/events/graphics-programming-conference), [GTX Gaming](https://www.gtxgaming.co.uk/?p=42517) (secondary)
- Teardown: every pixel's colour comes from ray tracing; cost scales with ray length, resolution and raymarch step size. — [TechRadar](https://www.techradar.com/gaming/consoles-pc/ray-tracing-is-so-crucial-to-teardown-that-the-world-goes-black-if-you-turn-it-off), [PCGH](https://www.pcgameshardware.de/Teardown-Spiel-73677/Specials/PC-Game-Test-Benchmark-Voxel-Dynamic-Destruction-1394545/4/)
- Background research (not a game): "Triplanar Displacement Mapping for Terrain Rendering" (Eurographics 2020, TUM) combines triplanar mapping with GPU tessellation displacement. — [TUM](https://cs.cit.tum.de/cg/research/publications/2020/triplanar-displacement-mapping)

### Inferences
- In a dig game, the cave/hole interior is where GI or at least strong AO matters most. Both "AAA-looking" voxel games here (Enshrouded, SE2) invested in dynamic GI; SE1 without it reads as flat in dug areas.
- Heightmap-based blending (SE2) plus parallax uses the same height channel, so one height map per material pays twice.

### Gaps
- No AO technique specified (SSAO/GTAO vs. baked voxel AO) for any title.
- No source on contact shadows or specular occlusion.

## 5. Dug-terrain look: strata, revealed materials, cut faces

### Takeaway
SE1 is the documented case: digging turns surface material into a `BareVariant`/`DamagedMaterial`, and ore deposits beneath can tint the surface (`ColorKey`). SE2 crater/furrow deformation uses metaball SDF spheres sized by impulse. Teardown cuts by removing voxels with per-voxel material colours. No source described explicit geological strata shading.

### Cited Findings
- SE1 `BareVariant`, `DamagedMaterial`, `ColorKey` ore-hint recolour; `MinedOre` + `MinedOreRatio` tie volume removed to ore yield. — [SE wiki](https://spaceengineers.wiki.gg/wiki/Modding/Reference/SBC/VoxelMaterial_Definition)
- VRAGE3 crash craters and furrows: metaball SDFs of spheres at contact points, radii from impulse; rock damages ships more than sand. "Far from final" (2023). — [Hloušek 2023](https://blog.marekrosa.org/2023/04/guest-post-jan-hlousek-vrage3/)
- SE2 VS2: terrain hardness varies dynamically and affects landing/crash outcomes. — [SE2 VS2 post](https://2.spaceengineersgame.com/space-engineers-2-voxel-density-vs2-flora/)
- SE2 players report big memory growth from dug terrain (claims ~10 GB). — [Keen support forum](https://support.keenswh.com/spaceengineers2/pc/topic/54552/vote/add/1) (user report, unverified)

### Inferences
- Cheapest "good cut face" recipe evidenced here: switch dug voxels to a dedicated bare/damaged material with its own triplanar side texture (the XZ slot carries the rock-face look), and let ore show through by voxel material id. Strata could be layered as material ids by depth from the planet radius, but no shipped game was found documenting it.
- Edit memory is a real risk: SE2's forum complaints suggest storing per-chunk edit deltas compactly matters.

### Gaps
- DRG, Enshrouded, NMS cut-face treatment: no primary source found.
- No source on blending dug faces with the original surface (edge darkening, rim debris).

## 6. Published performance numbers

### Takeaway
Very few hard numbers are public. The ones found: SE1 spends more than three CPU cores on rendering (the reason VRAGE3 went GPU-driven); Teardown big levels hold about half a billion voxels; SE1 caps at 128 active voxel materials.

### Cited Findings
- SE1 renderer uses >3 CPU cores; VRAGE3 moves draw-call issue to the GPU (DX12). — [Hloušek 2023](https://blog.marekrosa.org/2023/04/guest-post-jan-hlousek-vrage3/)
- Teardown ≈ 0.5 billion voxels in large levels. — [PCGH](https://www.pcgameshardware.de/Teardown-Spiel-73677/Specials/PC-Game-Test-Benchmark-Voxel-Dynamic-Destruction-1394545/2/)
- SE1 limit of 128 active voxel materials. — [Keen support](https://support.keenswh.com/spaceengineers/pc/topic/22619/vote/add/1)
- Enshrouded: many torches/lights in large bases are the main GI cost spike (secondary source). — [GTX Gaming](https://www.gtxgaming.co.uk/?p=42517)
- SC v5: virtual terrain system with real-time compression "nearing completion" (March 2025 report); no ms figures. — [SC Wiki v5](https://starcitizen.tools/Planet_Tech_v5)

### Inferences
- The industry direction (SE2, SC) is GPU-driven rendering and virtual/compressed terrain data; for a Godot project the transferable part is keeping per-chunk draw calls low (one multi-material shader per chunk, MultiMesh for scatter).

### Gaps
- No ms budgets, draw-call counts or scatter instance counts were found for any title.
- Sources not read in full this session and worth reading next: the GDC 2017 NMS talk video, Jan Hloušek's VS2 video deep-dive (Nov 2025), the Enshrouded GPC GI talk, blog.voxagon.se (Teardown), the Unreal Astroneer interview (403), SC CitizenCon 2019 "Terra Firmer" and CitizenCon 2024 "Brave New Worlds" panels.
- Enshrouded 1.0 date conflict: a secondary site gives 15 Oct 2026; not checked against Keen's own announcement.

# Real-time terrain material shader techniques for triplanar voxel meshes (Godot 4)

Context: spherical voxel planet, Transvoxel mesh, up to 4 material indices + weights per vertex, triplanar mapping (arbitrary orientation, radial "up"). Target: Godot 4 spatial shader, RTX 3060 at 1080p/1440p.

Verification note: this session could fetch the primary sources for hex-tiling (Mikkelsen JCGT 2022, full text and code), Heitz & Neyret 2018 (author page), GPU Gems 3 ch.1 (triplanar), Zylann voxel-tools docs (Transvoxel packing), Unity TerrainLit height blend (via search excerpts). Ben Golus's Medium article returned 403 and IQ's biplanar article returned 404 to the fetcher, so formulas attributed to them below are marked "recalled" where they come from prior knowledge rather than a page read this session. No measured ms numbers for these techniques on an RTX 3060 were found (see Gaps).

## Height-based material blending (4+ layers, blend contrast)

### Takeaway
The standard, cheap and production-proven formula is "max-height minus transition": per layer h'_i = h_i + w_i (or h_i * w_i), take m = max_i(h'_i), weight_i = max(h'_i - m + t, 0) * w_i, renormalize. It generalises to any layer count, costs nothing extra beyond the height channel already packed into a texture, and t (transition/contrast) is the one artist knob. It slots directly onto the voxel-tools 4-index/4-weight vertex format.

### Cited Findings
- Unity URP/HDRP TerrainLit height blend: takes the max height across layers ("higher height should be more visible"), subtracts it, uses a transition width clamped to a minimum (`half transition = max(_HeightTransition, 1e-5);`), multiplies by the original splat masks. HDRP LayeredLit `ApplyHeightBlend` uses `maxHeight = max(Max3(heights.r, heights.g, heights.b), heights.a);` for 4 layers — [Unity SRP TerrainLitSplatCommon.hlsl](https://plastichub.unity.cn/unity-tech-cn/ScriptableRenderPipeline/src/commit/654f18cb-413f-4e79-92bf-227477626df1...com.unity.render-pipelines.high-definition/HDRP/Material/TerrainLit/TerrainLitSplatCommon.hlsl)
- Unity Terrain Lit reads height from the blue channel of the Mask Map, and ignores height blend when more than 4 terrain layers are on the terrain (i.e. it is a per-4-layer-pass feature) — [Unity Manual: Terrain Lit](https://docs.unity3d.com/Manual/urp/shader-terrain-lit.html)
- WGSL terrain implementation (plumesplat): `let blend = max(height_weighted - max_height + sharpness, vec4<f32>(0.0));` over 4 weighted heights — [plumesplat blending.wgsl](https://docs.rs/crate/plumesplat/0.1.1/source/src/shaders/blending.wgsl)
- Transvoxel/voxel-tools packing: CUSTOM1.x holds 4 texture indices as 4 bytes, CUSTOM1.y holds 4 weights as 4 bytes (decode with floatBitsToUint, weights /255); voxel storage is 4 bits per texture (16-bit INDICES and WEIGHTS channels), up to 16 textures per mesh; reference shader normalizes `weights /= (weights.x + weights.y + weights.z + weights.w + 0.00001);` and samples a `sampler2DArray` triplanar per index — [Zylann voxel-tools: Smooth terrain](https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/)
- Voxel-tools notes blending more than 4 textures in one cell can artifact (judged rare), and the weights lose precision going 4-bit voxel -> 8-bit mesh — [voxel-tools docs](https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/)

### Inferences
- Recommended Godot formula (combining the above), per fragment after the 4 height samples:
  ```glsl
  vec4 h = vec4(hA, hB, hC, hD) + w * u_weight_bias;   // or h * w; additive keeps a 0-weight layer from popping
  float m = max(max(h.x, h.y), max(h.z, h.w));
  vec4 b = max(h - m + u_transition, 0.0) * w;           // u_transition ~0.05-0.2 in height units
  b /= max(b.x + b.y + b.z + b.w, 1e-5);
  ```
  Smaller u_transition = sharper, more "AAA" edges (stones poke through dirt). Per-layer height scale/offset uniforms (array-indexed by material id) let artists bias which material wins.
- Because the 4 heights are already sampled for the 4 materials, height blend adds only ALU. The cost is that the height channel must be sampled before final weights are known, so all 4 layers' height must be fetched even if blend later zeros one (skip-on-zero only works on the vertex weight, not the final weight).
- Height per material must itself be triplanar-blended first (blend the 3 projections' heights by triplanar weights), then fed into the layer height blend. Alternative cheaper order: height-blend the triplanar weights too ("height-aware triplanar", h_proj_i * w_proj_i with the same max trick) which sharpens the triplanar seams in the same style.
- 4-weights-per-vertex interpolation across a triangle where neighbouring vertices hold *different* index sets is the known Transvoxel/texture-array seam problem; voxel-tools avoids it by giving each cell's vertices the same 4 indices (S4 format). Keep that invariant.

### Gaps
- Frostbite terrain talks (Andersson 2007 procedural shader splatting; Widmark 2012) and UE Landscape's exact "LB_HeightBlend" formula were not fetched; the UE formula could not be quoted from a primary source this session.

## Anti-tiling: stochastic / hex tiling, bombing, macro + detail, distance UV blending

### Takeaway
Mikkelsen's 2022 hex-tiling is the practical choice: 3 SampleGrad fetches per texture, no precomputed LUTs, works on normals (with random rotation) and colour (with a contrast curve). With triplanar x 4 layers this multiplies fetches by 3 and is unaffordable on every layer/projection; use it selectively (one detail/normal layer, or only the dominant projection, or only near the camera) and use macro variation + distance UV-scale blending for the rest.

### Cited Findings
- Heitz & Neyret 2018: output space on a triangle grid, each vertex assigned a random patch of the example, each pixel blends 3 patches with a histogram-preserving operator (Gaussianize via transform T, variance-preserving blend, inverse T^-1); claimed >20x faster than comparable procedural noise; targets stochastic textures (moss, granite, sand, bark) — [Heitz research page](https://eheitzresearch.wordpress.com/722-2/)
- Mikkelsen 2022: the original needs precomputed T and T^-1 textures sampled instead of the source, i.e. deep engine integration. Hex-tiling drops histogram preservation and samples the source texture directly — [Mikkelsen, JCGT 11(2)](https://jcgt.org/published/0011/03/05/)
- Weights: w'_i = δ(x_i)·ω_i^γ / Σ_j δ(x_j)·ω_j^γ (exponentiation from Burley 2019 to reduce ghosting). For normals δ_N = (1−β) + β·sqrt(|d|²/(1+|d|²)) (sine of slope angle of the derivative d); for colour δ_C = (1−β) + β·luminance(x) with (0.299, 0.587, 0.114). Defaults γ = 7, β = 0.6 — [Mikkelsen 2022](https://jcgt.org/published/0011/03/05/)
- Colour contrast loss fixed with Perlin/Hoffert gain S-curve on the weights, k = log(1−r)/log(0.5), r = 0.5 is identity; conservative r in [0.65, 0.75]; r = 0.75 used for albedo and roughness, normals use r = 0.5 — [Mikkelsen 2022](https://jcgt.org/published/0011/03/05/)
- Implementation details: st *= 2·sqrt(3); skew matrix (1, −0.57735027; 0, 1.15470054) to triangle grid; per-vertex hash offset `frac(sin(mul(float2x2(127.1,311.7,269.5,183.3),p))*43758.5453)`; per-tile rotation from integer vertex id scaled by rotStrength; must use SampleGrad with the ddx/ddy rotated by the tile's rotation; normal maps blended as derivatives (dH/du, dH/dv), back to normal via normalize(float3(−deriv.xy, 1)) — [Mikkelsen 2022 appendix listings 1-10](https://jcgt.org/published/0011/03/05/)
- Rotation only works for normals when histogram preservation is off (directions must be rotated per tile before blending); rotation removes visible same-orientation features (pebbles) — [Mikkelsen 2022](https://jcgt.org/published/0011/03/05/)
- Demo code: https://github.com/mmikk/hextile-demo — [Mikkelsen 2022](https://jcgt.org/published/0011/03/05/)
- The three-hex-tiling library uses a higher exponent plus a `lookupSkipThreshold` to skip texture lookups where a tile's weight is negligible — [three-hex-tiling typings](https://cdn.jsdelivr.net/npm/three-hex-tiling@0.1.5/dist/index.d.ts)
- No published performance numbers for hex-tiling were found; the paper only argues simplicity vs histogram preservation — (search summary of [JCGT paper](https://jcgt.org/published/0011/03/05/paper-lowres.pdf) and [80.lv](https://80.lv/articles/a-new-method-of-hiding-seams-between-hex-tiles/))
- GPU Gems 3 recommends breaking repetition in triplanar terrain by mixing projected textures with procedural terms (noise-perturbed normals) and a low-frequency noise lookup into a 2D colour texture keyed by altitude — [GPU Gems 3 ch.1](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-1-generating-complex-procedural-terrains-using-gpu)

### Inferences
- Fetch math: hex-tiling = 3 fetches per texture per projection. Triplanar (3) x 4 layers x 2 textures (albedo+height, normal+rough+AO) = 24 fetches baseline; hex-tiled = 72. Not viable at full width. Practical budgets:
  - Hex-tile only the normal/detail texture, only for the top 1-2 weighted layers, only for the dominant 1-2 projections (biplanar), and fade to plain sampling past ~30-50 m (when weights collapse you can skip 2 of 3 hex fetches, the `lookupSkipThreshold` idea; with γ=7 most pixels are dominated by one tile).
  - Cheap alternative with a lot of the benefit: two-scale sampling (uv and uv*0.27 rotated) blended by a low-frequency noise mask, plus a world-space macro variation texture (1 fetch) modulating albedo/roughness. 2 fetches instead of 3, no hash, no SampleGrad needed if no per-tile offset.
- Distance-based UV scale blending: sample at scale s near and s/4 far, lerp by smoothstep on view distance. Doubling fetches only inside the transition band is possible with a branch on dynamic uniform-ish distance; in practice it is ~2x fetch cost everywhere unless branched.
- Godot 4 has `textureGrad()` for sampler2DArray, so hex-tiling ports directly; use `dFdx/dFdy` of the per-projection UV computed before any fract/offset. On a planet, world-space triplanar UVs at large coordinates lose float precision; use camera-relative or chunk-relative positions with a wrap period multiple of the tile size.
- Hex-tiling on triplanar is per projection: each of the 3 planar UVs gets its own triangle grid. Hex rotation on normal maps composes fine with Golus-style swizzle because rotation happens in the projection's 2D tangent space before the swizzle.

### Gaps
- No RTX 3060 (or any) ms numbers for hex/stochastic tiling were found.
- Texture bombing (GPU Gems 1 ch.20) was not fetched this session.
- Heitz & Neyret mip/filter handling (they need a filtered LUT; the inverse transform at low mips is lossy) is not described on the author page.

## Triplanar normal mapping done right; biplanar mapping

### Takeaway
Treat each projection's tangent-space normal as a perturbation in that plane, swizzle it into world space, fix the sign on negative faces, then blend with triplanar weights. Whiteout or RNM blend against the geometry normal gives correct results; the naive "blend the tangent normals then use the mesh TBN" is wrong. Biplanar (IQ) cuts 3 projections to 2 at the price of manual gradients and slight artifacts near (±1,±1,±1) normals.

### Cited Findings
- GPU Gems 3 triplanar weights: `w = abs(N); w = (w - 0.2) * 7; w = max(w, 0); w /= (w.x + w.y + w.z);` giving a ~10-20 degree transition; normal maps per projection: `bump1 = (0, b.x, b.y)`, `bump2 = (b.y, 0, b.x)`, `bump3 = (b.x, b.y, 0)`, blended and added: `N = normalize(N_orig + blended_bump)` — the chapter calls its own tangent basis "oversimplified" and notes sign placement depends on map storage; 6 fetches (3 colour + 3 bump) — [GPU Gems 3 ch.1](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-1-generating-complex-procedural-terrains-using-gpu)
- Whiteout triplanar implementation citing Ben Golus: weights `pow(abs(N), sharpness)` normalized; per axis swizzle with the world normal sign: `wnX = (nX.z*sign(N.x), nX.y, nX.x)`, `wnY = (nY.x, nY.z*sign(N.y), nY.y)`, `wnZ = (nZ.x, nZ.y, nZ.z*sign(N.z))`, blended by weights and normalized — [plumesplat triplanar.wgsl](https://docs.rs/crate/plumesplat/latest/source/src/shaders/triplanar.wgsl)
- Recalled (Golus article not fetchable this session, 403): the article's recommended forms, with tangent normals tnX/tnY/tnZ sampled from UVs zy, xz, xy and N the world normal:
  - UDN: `tnX = vec3(tnX.xy + N.zy, N.x)` etc., cheapest, flattens strong detail.
  - Whiteout: `tnX = vec3(tnX.xy + N.zy, abs(tnX.z) * N.x)` etc.
  - RNM: per axis `t = N.zyx-swizzled + (0,0,1)`, `u = tn * (-1,-1,1)`, `r = t*dot(t,u)/t.z - u`, best quality, a few more ALU.
  - Negative-side fix: flip tangent x by `sign(N.axis)` (uv.x *= sign) so mirrored faces don't invert lighting; final `normalize(swizzled_X*w.x + swizzled_Y*w.y + swizzled_Z*w.z)`.
  - Reported cost difference between UDN, whiteout and RNM is ALU only, small vs fetches — [Ben Golus, Normal Mapping for a Triplanar Shader](https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a)
- UDN described as cheap because it ignores the z of the detail map; UDN and Whiteout can flatten detail in some cases, so RNM is often preferred — [Godot Shaders dual texture blender](https://godotshaders.com/?p=11498); [zenn.dev](https://zenn.dev/katopan/articles/f071723a9e4d58)
- RNM for triplanar: swizzle vertex normal to match the map, blend, swizzle back — [Selfshadow "Blending in Detail" discussion](https://discourse.selfshadow.com/t/blending-in-detail/21?page=3)
- Biplanar mapping: 2 texture reads instead of 3 at extra ALU; texture gradients must be supplied by hand (textureGrad), which is most of the complexity — [iquilezles.org/articles/biplanar](https://iquilezles.org/articles/biplanar) (via search summary); artifacts near normals along (±1,±1,±1), where only the two largest-weight faces are fetched — [Scrapbox note](https://scrapbox.io/0b5vr/Biplanar%20Mapping); "eliminating one texture fetch at the expense of some extra logic" — [r/VoxelGameDev, Cubiquity developer](https://redlib.hbubli.cc/r/VoxelGameDev/comments/jzjv1u/biplanar_mapping_a_potentially_cheaper); shipped as Babylon.js BiPlanarBlock — [Babylon.js source](https://app.unpkg.com/@babylonjs/core@8.12.1/files/Materials/Node/Blocks/biPlanarBlock.js)
- Recalled IQ biplanar algorithm (article not fetched): `n = abs(N)`; major axis `ma` = index of max, minor `mi` = min, median `me = 3 - ma - mi`; sample two planes (ma, me) with `textureGrad(tex, vec2(p[ma.y], p[ma.z]), dpdx-swizzle, dpdy-swizzle)`; weights `m = vec2(n[ma.x], n[me.x])`, remap `m = clamp((m - 0.5773)/(1 - 0.5773), 0, 1)` (0.5773 = 1/sqrt(3), so the minor plane's weight at the diagonal is 0), then `m = pow(m, k/8)`, result `(x*m.x + y*m.y)/(m.x+m.y)` — [iquilezles.org/articles/biplanar](https://iquilezles.org/articles/biplanar)

### Inferences
- For the planet: blend weights must come from the *interpolated vertex normal* (smooth Transvoxel normal), not the derivative/flat normal, or seams follow triangles. Voxel-tools' shader already does this.
- Sharper triplanar weights (pow 4-8, or GPU Gems' (w-0.2)*7) shrink the band where 3 projections are live; combined with a dynamic `if (w.x > 0.01)` per projection, most pixels fetch only 1-2 projections. On NVIDIA, divergent branches inside a 2x2 quad / warp still pay for both, but terrain normals vary slowly, so warps are coherent most of the time. Biplanar makes this deterministic (always 2) and removes the branch.
- Biplanar x 4 layers x 2 textures = 16 fetches vs triplanar 24; this is the single biggest fetch saving available and stacks with height-blend.
- Godot specifics: sample normal maps with `hint_normal` (Godot then reconstructs z for RG/BC5 maps — `NORMAL_MAP` expects tangent space; for triplanar you must compute the world normal yourself and write `NORMAL` in view space: `NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);` and not use NORMAL_MAP). Reconstruct z manually: `n.z = sqrt(max(1.0 - dot(n.xy, n.xy), 0.0))`.

### Gaps
- Exact Golus and IQ code could not be re-read this session; the recalled forms should be checked against the pages before shipping (sign conventions differ between DirectX/OpenGL normal maps; Godot expects OpenGL Y+).

## Parallax occlusion mapping on triplanar and alternatives

### Takeaway
Full POM on triplanar x 4 layers is a fetch explosion (N steps x 3 projections x layers) and Godot's built-in POM does not work with triplanar. On voxel terrain the cost-effective path is: cheap height-based self-shadow / micro-shadow terms in the lighting, plus optional single-layer, dominant-projection POM only near the camera. True displacement needs vertex displacement in the mesher or vertex shader since Godot 4 has no tessellation.

### Cited Findings
- Godot's built-in POM ("Depth" with "Deep parallax") needs mesh binormals and does not work in combination with triplanar — [Godot forum](https://forum.godotengine.org/t/triplanar-mapping/15093) (via search summary)
- Community Godot POM implementations exist, including POM with self-shadowing, iterative parallax, and silhouette/prism POM references for edge artifacts — [Godot Shaders: POM with self-shadowing](https://godotshaders.com/shader/parallax-occlusion-mapping-with-self-shadowing/); [Iterative parallax mapping](https://godotshaders.com/shader/iterative-parallax-mapping/); [godotforums thread on parallax over edges](https://godotforums.org/d/22874-proper-parallax-mapping-over-geometry-edges)
- GPU Gems 3 marks a spot in its triplanar shader for conditional displacement mapping, skipping projections with zero weight — [GPU Gems 3 ch.1](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-1-generating-complex-procedural-terrains-using-gpu)

### Inferences
- Triplanar POM: each projection has a trivially known tangent frame (the two world axes of the plane, plus sign(N.axis) as the normal), so the view vector in projection space is just a swizzle of world V: for X-plane, V_ts = (V.z*sign(N.x), V.y, |V.x|) etc. Ray-march each live projection separately with its own height layer, then triplanar-blend the offset UVs' results. With biplanar + dominant layer only: 2 projections x 8-16 steps = 16-32 height fetches on top of the base. Use a distance fade (POM off beyond ~10-20 m) and a weight threshold.
- Multi-material POM is not well defined (each layer has its own heightfield); the usual approach is to POM-march on the *height-blended* combined height, which means sampling all 4 layers' height per step (too expensive) or marching only the dominant layer's height. Recommend dominant-layer only.
- Cheap alternatives that read as "depth" on rocky ground:
  - Height-based micro-shadow: `shadow = saturate((h_sample_toward_light - h) * k)`, one extra height fetch offset along the light direction projected into the plane (1-2 fetches, dominant projection).
  - Micro-shadowing from AO (UE4/Naughty Dog style): `microShadow = saturate(abs(NdotL) + 2*AO*AO - 1)` (recalled, Naughty Dog "Uncharted 4" lighting; not verified this session).
  - Contact-refinement parallax: a 4-8-step coarse march plus one binary/secant refinement step; much cheaper than 32-step POM with similar look on gentle heightfields.
- Real displacement: Godot 4 spatial shaders can displace in `vertex()` (VERTEX += NORMAL * h * amp) but texture LOD in vertex shaders must use `textureLod`, and Transvoxel vertex density (1 vertex per voxel, ~0.5-1 m) is too coarse for pebble-scale detail; it only helps for metre-scale bumps and creates cracks at LOD seams unless the same displacement is applied to transition cells. Mesher-side displacement (bake a noise/height into the SDF before meshing) is the robust option and costs zero per-pixel.
- Anything needing tessellation (hardware displacement) is unavailable in Godot 4; compute-shader re-meshing via RenderingDevice is possible but outside spatial shaders.

### Gaps
- No primary source for triplanar POM costs or for the micro-shadow formula was read this session.

## Specular occlusion, horizon/micro occlusion, cavity roughness, wetness/dust, slope/curvature layers

### Takeaway
These are mostly ALU on data already fetched (AO, height, normal), so they are the cheapest "AAA" wins: specular occlusion from AO, horizon occlusion on normal-mapped reflections, roughness darkened/raised by cavity, and procedural layers driven by slope (dot(N, radial up)), height-in-cavity, and curvature.

### Cited Findings
- Jimenez et al. (Activision) "Practical Real-Time Strategies for Accurate Indirect Occlusion": GTAO plus specular occlusion as a generalization of AO for arbitrary specular BRDFs, and directional/bent-normal occlusion — [Activision technical memo](https://www.activision.com/cdn/research/Practical_Real_Time_Strategies_for_Accurate_Indirect_Occlusion_NEW%20VERSION_COLOR.pdf); [SIGGRAPH 2016 slides](https://blog.selfshadow.com/publications/s2016-shading-course/activision/s2016_pbs_activision_occlusion.pdf)
- Unity HDRP (Lagarde) default specular occlusion uses AO with the "Tri-ace trick", takes the min of screen-space SO and visibility-cone SO, bent normal when available — [Unity SRP commit](https://plastichub.unity.cn/unity-tech-cn/ScriptableRenderPipeline/commit/05c7d851-0de0-4f49-8c9f-043ed3b72b51); [cone SO commit](https://plastichub.unity.cn/unity-tech-cn/ScriptableRenderPipeline/commit/23bcdad7-0eeb-44a0-b536-7969effbe443)
- Lygia `specularAO` cites Lagarde "Moving Frostbite to PBR" §4.10.2: roughness-dependent power curve of N·V and AO — [lygia specularAO.glsl](https://git.gay/kaneraZh/lygia/src/branch/main/lighting/common/specularAO.glsl) (page 502 on fetch; formula recalled as `saturate(pow(NdotV + ao, exp2(-16*roughness - 1)) - 1 + ao)`, Frostbite course notes)
- Horizon fade (credited to Marmoset): `h = clamp(1 + horizonFade * dot(N_mapped, R), 0, 1); h *= h;` with horizonFade default 1.3 — [Adobe Substance Painter lib-pbr](https://experienceleague.adobe.com/en/docs/substance-3d-painter/using/scripting-and-development/shader-api-reference/libraries-shader-api/lib-pbr-shader-api). Note: the search summary says "ndl"; in Marmoset/Substance this is applied with the reflection vector against the vertex normal (recalled). Purpose: stops normal-mapped reflections pointing below the geometric horizon; users report ~0.7 multipliers looking good — [Babylon.js forum](https://forum.babylonjs.com/t/pbrmaterial-normal-map-looks-incorrect-at-high-angles/29159)

### Inferences
- Godot 4 already multiplies AO into indirect specular via `AO` and `AO_LIGHT_AFFECT`; specular occlusion beyond that requires reducing `SPECULAR`/raising `ROUGHNESS` or a custom `light()` function (custom light() disables some built-in paths; test cost). Writing horizon fade into `SPECULAR` is the cheapest option.
- Slope layer: `slope = 1 - dot(N_world_smooth, normalize(world_pos - planet_center))` — radial up, never world Y. Rock on steep: add `smoothstep(s0, s1, slope)` as weight bias to the rock material's height before the height blend (so rock emerges by height, not by a soft fade).
- Cavity/dust: `cavity = 1 - height_blended` (or AO); dust weight `= smoothstep(c0, c1, cavity) * (1 - slope)`; dust = albedo tint + roughness to ~0.9 + flattened normal (lerp normal toward geometric normal). Costs 0 fetches.
- Wetness (rain/ice planets): darken albedo (`albedo *= mix(1, 0.3-0.5, wet*porosity)`), roughness toward 0.1-0.2, normal toward geometric where puddles (wet & low height). 0 fetches.
- Scree at slope base needs curvature or a "distance to steep slope" term, which a fragment shader cannot get locally; options: compute per-vertex in the mesher (Transvoxel already has SDF gradients; curvature = divergence of normal, or SDF Laplacian sampled at the vertex) and pass it in a CUSTOM channel; or approximate screen-space curvature with `length(fwidth(N))/fwidth(pos)` (noisy, view-dependent, avoid). Mesher-side is the right answer.
- Roughness from cavity: `rough = mix(rough, rough + 0.15, cavity)` for dirt-filled cracks, or lower in wet cavities.

### Gaps
- The exact Frostbite specular occlusion formula and the Marmoset horizon occlusion formula were not read from the primary sources (pages unavailable); verify before quoting as exact.

## Texture packing, compression, array budgets, mip bias, anisotropic filtering

### Takeaway
Pack 2 textures per material: A = albedo RGB + height A (BC7 or BC3), B = normal XY + roughness + AO (two arrays: BC5 for normal XY, BC4/BC7 for rough/AO, or one BC7 RGBA with normal XY in RG, rough B, AO A at some quality loss). Godot 4 supports sampler2DArray with mipmaps and anisotropic filter hints, which is what terrain needs.

### Cited Findings
- Unity Terrain Lit Mask Map convention puts height in the blue channel of a packed mask (metallic/AO/height/smoothness) — [Unity Manual: Terrain Lit](https://docs.unity3d.com/Manual/urp/shader-terrain-lit.html)
- Voxel-tools recommends a Texture2DArray when there are more than 4 textures, indexed by the per-vertex material id — [voxel-tools docs](https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/)
- Hex-tiling requires SampleGrad (textureGrad) because of per-tile offsets, i.e. explicit gradients, which also means mip bias must be applied by scaling the gradients — [Mikkelsen 2022](https://jcgt.org/published/0011/03/05/)

### Inferences (not source-verified this session; based on general GPU knowledge)
- Sizes: BC7/BC3 = 1 byte/texel, BC5 = 1 byte/texel, BC4 = 0.5 byte/texel; mips add 33%. A 2048² BC7 layer = 4 MiB +mips ≈ 5.3 MiB. 16 materials x (albedo+height BC7 + normal BC5 + rough/AO BC5-ish) at 2048² ≈ 16 x 16 MiB ≈ 256 MiB. At 1024² ≈ 64 MiB. A 12 GB RTX 3060 fits 2048² comfortably; 1024² with good hex/detail tiling usually looks nearly as good for terrain at 1-4 m tile size.
- Normal maps: BC5 (Godot calls it RGTC; enable "Normal Map" import so it uses RG compression) and reconstruct z; never BC1/BC3 RGB for normals. Avoid putting height in the alpha of a BC1 (1-bit alpha).
- Height precision matters for height blend: BC7 alpha or BC4 single channel is fine; avoid DXT5 alpha only if banding shows.
- Anisotropic filtering: use `filter_linear_mipmap_anisotropic` on the array samplers (Godot hint). Terrain at grazing angles is where AF matters most; with textureGrad, AF still works as long as true gradients are passed. Cost on modern NVIDIA is small but multiplies with fetch count.
- Mip bias: slight negative bias (−0.25 to −0.5) sharpens ground with TAA/FSR; in Godot, global via the project's texture mipmap bias (linked to FSR/TAA scaling) or per-sample `texture(s, uv, bias)`; with textureGrad scale gradients by exp2(bias).
- Triplanar derivatives: compute per-projection UV derivatives from `dFdx(world_pos)`/`dFdy(world_pos)` swizzled, so that any later per-pixel branching or offsets don't break quad derivatives.

### Gaps
- No primary source fetched this session for Godot 4's exact import behaviour of normal maps in Texture2DArray (whether "Normal Map" RG compression applies to array imports) and its AF hint behaviour on arrays; check the Godot docs (`Texture2DArray` import, `filter_*_anisotropic` hints).

## Performance: fetch counts and ms budgets on mid-range GPUs

### Takeaway
No measured RTX 3060 ms numbers for these techniques were found. Fetch counting gives the useful comparison: naive triplanar x 4 layers x 2 packed textures = 24 fetches; biplanar = 16; biplanar + only-2-dominant-layers = 8; adding hex-tiling to one texture of the top layer adds ~4 more. Height blend, slope/cavity/dust/wetness, horizon/specular occlusion are ALU-only.

### Cited Findings
- GPU Gems 3 triplanar = 6 fetches for one material (3 colour + 3 bump) — [GPU Gems 3 ch.1](https://developer.nvidia.com/gpugems/gpugems3/part-i-geometry/chapter-1-generating-complex-procedural-terrains-using-gpu)
- Voxel-tools reference Transvoxel shader samples up to 4 indices x 3 projections ≈ 12 lookups for albedo alone — [voxel-tools docs](https://voxel-tools.readthedocs.io/en/latest/smooth_terrain/) (count is the fetcher's inference from the code)
- Biplanar's motivation: texture reads are expensive relative to ALU, so 3→2 fetches is the main saving — [IQ biplanar (search summary)](https://iquilezles.org/articles/biplanar)
- Hex-tiling: 3 SampleGrad per texture; skip thresholds can cut lookups — [Mikkelsen 2022](https://jcgt.org/published/0011/03/05/); [three-hex-tiling](https://cdn.jsdelivr.net/npm/three-hex-tiling@0.1.5/dist/index.d.ts)

### Inferences
- Recommended tiered budget for this project (fragment shader, per terrain pixel):
  - Tier 0 (always): biplanar, 4 vertex-weighted layers but skip layers with vertex weight < ~0.02 (dynamic branch; coherent per triangle), 2 packed textures per layer, height blend, slope/cavity/dust ALU, horizon fade. ~8-16 fetches.
  - Tier 1 (near, < ~40 m): hex-tile the normal (and optionally albedo) of the dominant layer on the dominant projection: +4-6 fetches. Plus 1 macro variation fetch everywhere.
  - Tier 2 (very near, < ~10 m): dominant-layer contact-refinement parallax or height micro-shadow: +4-10 fetches.
- Terrain typically covers 30-60% of the screen in a first-person ground view; at 1440p that is ~1.1-2.2 M pixels shaded (plus overdraw from Godot's depth prepass reducing it to ~1x). A 3060's texture rate is ~200 GTexel/s nominal (bilinear); 30 fetches x 2 M px = 60 M fetches/frame — well under budget in throughput terms. The real limits are cache misses from 16 array layers and trilinear/aniso multiplying taps. Expect a heavy terrain shader in the 1-3 ms range at 1440p; this is an estimate, not a measurement. Measure with Godot's GPU profiler / RenderDoc / Nsight before tuning.
- Biggest wins in order: biplanar (−33% fetches), layer skipping on zero vertex weight, sharp triplanar weights, distance-tiered hex/POM. Height blend and the procedural layers are near-free and give the most visual gain per ms.

### Gaps
- No benchmark source found for triplanar/biplanar/hex-tiling ms costs on RTX 3060 or similar at 1080p/1440p; all ms figures above are estimates. Needs an in-engine measurement (Godot's Visual Profiler GPU timings, or Nsight Graphics).
- Frostbite/Guerrilla/Ubisoft GDC terrain talks (virtual texturing, procedural splatting costs) were not fetched in this session; their published numbers relate to heightmap terrain with virtual texturing rather than triplanar voxel meshes and may not transfer.

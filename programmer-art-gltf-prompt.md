# Programmer-art glTF pass — prompt

Paste this whole thing when asking Claude to model the game's placeholder assets. Goal: functional, consistent, silhouette-readable programmer art — not final art. Every asset should look like it was made by the same process at the same effort level; nothing should look more "finished" than anything else.

## Constraints (apply to every asset, no exceptions)

- **Primitives only.** Boxes, cylinders, cones, wedges, and simple boolean combinations/chamfers of those. No sculpting, no organic geometry, no freeform curves.
- **Poly budget**: roughly 100–500 tris per asset. Small items (ammo, ore chunks, casings) at the low end, buildings at the high end. If two assets are in the same category, keep their tri counts within the same order of magnitude — don't let one turret be 10x denser than the other.
- **One foundation tile = 2.0 world units.** Every building's footprint is a clean multiple of that (1x1, 2x1, 2x2). Scale every asset against this unit so they're consistent relative to each other and to the player (~1.8 units tall) without eyeballing it per-asset.
- **Origin/pivot**: centered on X/Z, sitting on Y=0 (base of the object touches the ground plane at the origin), so every export drops into the engine at the correct place with no manual offset.
- **+Y up, real-world meter scale**, matching Godot's glTF import expectations — don't bake in a different up-axis or unit scale per asset.
- **Silhouette must read at a glance.** Each asset needs a distinct outline from every other asset in its category — don't rely on color alone to tell them apart.
- **Flat materials only, no texture maps.** glTF supports real materials, so use them directly — but keep every material a flat `baseColorFactor` (plus `emissiveFactor` where noted), zero image textures, zero normal/roughness maps. This is a color-blocking pass, not a texturing pass.
- **One material slot per logical part**, named clearly, assigned directly in the glTF (no need to split into separate mesh objects the way a colorless format would require — multiple material slots on one mesh is fine):
  - `chassis` — the neutral structural body (main mass of the object)
  - `accent` — the part that carries the category's signal color (see below)
  - `emissive` — a small indicator strip/light, `emissiveFactor` set to the category accent color, only on assets with a power/active state (omit on raw ore, ammo, static structural pieces)
  - `hazard` — a stripe/edge only on genuinely dangerous parts (turret muzzle, smelter face); omit on everything else
- **No surface detail beyond shape.** Bolts, vents, panel seams — skip entirely at this pass. That's a later normal-map pass, not something to fake with extra geometry or a decal texture now.

## Category → color values

Use these exact values as `baseColorFactor` (linear RGB, alpha 1.0) so every asset in a category matches exactly rather than "close enough":

| Category | Assets | Chassis (neutral) | Accent |
|---|---|---|---|
| Processing | Processor, Smelter, Constructor | `#7A7E82` | amber `#E08A2E` |
| Logistics | Vacuum Pipe, Merger, Splitter, Chest | `#7A7E82` | cyan/teal `#2EB8B0` |
| Combat | Turret Gun, Turret Cannon, Iron Piercing Ammo, HE Shell | `#7A7E82` | red `#D93A3A` |
| Structural | Metal Foundation, Placeable Block | `#7A7E82` | none — chassis only |
| Raw ore (iron/copper/coal/silica/sulfur) | ore_a, ore_b, ore_coal, ore_silica, sulfur | mineral-natural color as the whole chassis (iron dull steel grey, copper reddish-brown, coal matte black, silica pale sandy, sulfur pale yellow-green) | none |
| Refined material | Refined Copper Ingot, Refined Carbon, Refined Silica, Refined Material, Copper Casing, Piercing Core, Gunpowder | a cleaner, more saturated version of its raw ore's own color | none |
| Tools (held) | Mining Tool, Building Tool, Basic Crafter | `#7A7E82` | amber if processing-adjacent, otherwise chassis-only |

Hazard stripe, where used: black `#1A1A1A` / safety-yellow `#E8C93A` diagonal, alternating.

## Scale/shape cues per asset (so silhouettes stay distinct within a category)

- **Turret Gun** vs **Turret Cannon**: gun is slender, tall barrel, small footprint; cannon is thick-barreled, wider stance, visibly heavier.
- **Processor** vs **Smelter** vs **Constructor**: three distinct silhouettes even though all three "process something" — vary footprint shape and height, not just color.
- **Vacuum Pipe / Merger / Splitter**: pipe is a simple tube segment; merger and splitter are visibly branching (Y-junction or T-junction geometry), distinguishable from each other by which side has the single opening vs the multiple openings.
- **Chest**: simple box with a lid seam, no lid animation needed — the seam line is enough of a shape cue.
- **Metal Foundation**: flat plate, edges match neighbor-snapping (flush square edges, no bevel that would create gaps when tiled edge-to-edge).
- **Ore chunks (ore_a/b/coal/silica, sulfur)**: irregular, non-uniform boolean-combined primitives (not a clean sphere or box) — should read as "raw mineral," not "prop."
- **Refined ingots/casings**: clean, regular geometric shapes (bar, cylinder, disc) — should read as "manufactured," a deliberate contrast to the raw ore's irregularity.
- **Ammo (Iron Piercing Ammo)**: slender, pointed.
- **HE Shell**: stubbier, finned tail.
- **Projectile** (in-flight visual): small and simple — a stretched capsule or cone, since it's seen briefly and fast.
- **Enemy Dummy**: keep it a simple placeholder silhouette distinct from every building/item shape (e.g., a humanoid-proportioned or blocky "target" capsule) — this is a stand-in, not final enemy art, so don't over-invest here.

## Full scope to cover (don't skip any — partial coverage breaks the "equal quality everywhere" goal)

Buildings/placed structures: Chest, Constructor, Processor, Smelter, Metal Foundation, Turret Gun, Turret Cannon, Vacuum Pipe segment, Pipe Merger, Pipe Splitter, Placeable Block.

Held tools: Mining Tool, Building Tool, Basic Crafter.

Ores (raw): ore_a (iron), ore_b (copper), ore_coal, ore_silica, sulfur.

Refined materials/components: Refined Copper Ingot, Refined Carbon, Refined Silica, Refined Material, Copper Casing, Piercing Core, Gunpowder.

Ammo/combat: Iron Piercing Ammo, HE Shell, Projectile (in-flight visual).

Placeholder actor: Enemy Dummy.

## Output

One `.glb` (binary glTF, self-contained — no separate texture/bin files to lose track of) per asset, named to match its existing `data/items/*.tres` or `scenes/*.tscn` identifier (e.g. `turret_gun.glb`, `ore_coal.glb`), with materials assigned directly as specified above so it drops straight into Godot fully colored with no post-import material pass required.

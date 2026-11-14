# Pivot references (2026-11-14)

Michael's direction change: 2.5D top-down pixel art (Mindustry is the gameplay-read reference), mechanics stay,
height stays, flat instanced worlds, ships fly locally and go to a small 2.5D space scene by climbing high.
Two reels he sent as art + visual/gameplay direction. Raw frames and transcripts:
`Documents\Database\SM_DB\Reference-Videos\raw\stellartd-ref1` and `stellartd-ref2`.

## Ref 2: Garbage Country (Noio), the LOOK reference

Instagram reel, 12 s, "the mood is: water", no voice. Gameplay clips of Garbage Country.

- What it is: post-apocalyptic exploration sim by Noio (Cloud Gardens, Kingdom: New Lands). Drive a car across a
  wasteland, **tower-defense battles against waves of bots**, upgrade the car to go further. Procedural terrain with
  hand-made landmarks. Releasing 2026 (PC, Mac). [VERIFIED Steam app 2530870, store text]
- How it looks: **3D rendered as pixel art**, not hand-drawn sprites. [VERIFIED: listings say "pixel art 3D
  wasteland"]. High three-quarter top-down camera, low internal resolution scaled up with hard pixels.
- On screen (frames 0-12 s): layered sandstone cliffs with clear horizontal strata, river with white pixel foam
  lines along every shore, sun sparkle on water, yellow grass tufts and palms as billboards/low-poly, hazy pink-peach
  sky with tall thin pines fading into fog, bridges and a road along cliff ledges, small jeep with a white wake.
- Steal:
  - The whole render approach: our 3D world + models, camera high and angled, render small, upscale with nearest.
    Height reads for free (cliffs, terraces), which Michael wants to keep.
  - Strata on cliff faces as the main terrain detail (we already draw strata per pixel).
  - Shoreline foam as a 1-pixel white line that moves; water sparkle.
  - Warm hazy palette, depth fog to the horizon, few strong colours per scene.
  - Gameplay match: vehicle + TD waves + upgrades is very close to Stellar TD's own loop.
- Don't copy: their assets, palette 1:1, the jeep, any footage.

## Ref 1: pixelfx (patch.gg), the EFFECTS source

Instagram reel, 24 s, ~140 wpm voice-over, 2 cuts per 10 s, "Open Source Daily #002".

- What it is: 244 pixel-art effects (fire, explosions, lightning, ice, magic, weather, UI, pickups) each written as
  a small piece of code. Preview in the browser, recolour with a palette ramp, export a PNG sprite sheet + JSON
  (Aseprite-style) for Godot/Unity/Phaser. Comes with a Claude Code skill for making new effects. **MIT**, free, no
  API key. [VERIFIED github.com/patch-gg/pixelfx, pixelfx.io]
- The catch it states itself: character effects (slashes, casts) have to be fitted to your own sprites.
- Steal:
  - Explosions, muzzle flashes, sparks, smoke, lightning, shield hits for turrets, drills and waves: export as sheets,
    recolour to our palette, play as AnimatedSprite3D/2D. MIT, so commercial use is fine (keep the licence file).
  - Its Claude Code skill for new effects in the same style, so effects stay consistent with each other.

## What this means for the pivot (needs Michael's call)

The two references point at different build methods:
- **Mindustry-style**: true 2D, flat sprites drawn per tile/building (Qwen Image would draw them). Height has to be
  faked (layers, shadows). Most of the 3D world, models and terrain shader are thrown away.
- **Garbage Country-style**: keep Godot 3D, flatten the world to a heightmap terrain, fixed high camera, render at low
  resolution with pixel-snapping and a toon/palette pass. Height, cliffs, ships climbing to space all stay natural.
  Our Blender kit models stay usable; Qwen Image does textures, UI, icons, decals.

## Try next

Pixel render test: one flat chunk of the existing terrain + 3 existing machine models, orthographic camera at ~50
degrees, 480x270 internal render upscaled to 1080p, palette quantise. Compare against the Garbage Country frames.

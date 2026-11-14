#!/usr/bin/env bash
# Qwen pixel-art test (pivot-2d.md 6.2): ask for pixel art directly, then snap it onto a real grid.
# Refuses (exit 2) while someone is at furryass; just run it again later.
cd "$(dirname "$0")"
PY=/c/Users/Admin/AppData/Local/Programs/Python/Python312/python.exe; G=~/.claude/skills/qwen-image/gen_image.py
gen() { [ -f "$1.png" ] || $PY -I $G $3 --size 1024x1024 --out "$PWD/$1.png" --prompt "$2" || exit 2; }
gen px_terrain "pixel art, 16-bit, top-down game map of an alien desert planet seen straight from above, layered rocky cliffs and a raised mesa plateau with crisp pixel edges, scattered boulders, small crystal clusters, cracked ground, limited muted palette in the style of Mindustry, hard pixels, no anti-aliasing, no text"
gen px_ground "pixel art seamless ground texture for a top-down game, dusty alien regolith with small pebbles and cracks, viewed straight from above, 32x32 tile style, limited palette of 5 muted brown grey tones, hard pixels, no anti-aliasing, flat lighting, no text"
gen px_rocks "pixel art sprite sheet of 6 boulders and rock clusters for a top-down sci-fi game seen straight from above, muted grey and brown palette, 1 pixel dark outline, light from top left, hard pixels, no anti-aliasing, isolated on transparent background" --rgba
for f in px_terrain px_ground px_rocks; do $PY -I ../../tools/sprite_pipeline.py snap $f.png --out ${f}_snap.png --colors 24; done
echo QWEN_PX_DONE

#!/bin/sh
# Rebuild the photoscanned terrain material sets (git-ignored, ~750 MB) on a fresh clone or after adding scans:
#   1. download the CC0 scans (ambientCG, Poly Haven API) to ~/.stellar-assets/scans   tools/fetch_scans.py
#   2. pack them into the shader's two maps at 2048 in data/textures/surfaces/scan     tools/pack_surface_set.py
#   3. import in Godot, then compress every set to BC7 + mips in data/textures/surfaces/bc7
# Run from the repo root:  sh tools/setup_surfaces.sh
set -e
PY="${PYTHON:-C:/Users/Admin/AppData/Local/Programs/Python/Python312/python.exe}"
GODOT="${GODOT:-C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe}"
"$PY" -I tools/fetch_scans.py
"$PY" -I tools/pack_surface_set.py --all
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://scripts/dev/compress_surfaces.gd

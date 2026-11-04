#!/bin/sh
# Build + render one building: sh art_src/build.sh <name> [views...]   (run from the repo root)
# Writes art_src/<name>/<SM_*>.blend|glb + parts.md, renders to art_src/<name>/renders, copies the glb to
# data/models/buildings/<name>/.
#   sh art_src/build.sh <name> --blockout   stage 1: big parts only, flat colours, part sheet + audit, no export
#   sh art_src/build.sh <name> --audit      run the generator and the part audit only (fast, no bake)
# The build stops when the part audit finds problems (AUDIT=warn sh art_src/build.sh ... to push through a WIP).
B="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
N=$1; shift
D="$(pwd -W)/art_src/$N"
case "$1" in
  --blockout) export BLOCKOUT=1; shift ;;
  --audit) export AUDIT_ONLY=1; shift ;;
esac
LOG=$("$B" -b -P "$D/$N.py" -- "$D" 2>&1)
echo "$LOG" | grep -E 'REPORT|AUDIT|BLOCKOUT|Error|Traceback|File ".*py", line|DONE'
echo "$LOG" | grep -qE 'Traceback|AUDIT FAIL' && exit 1
[ -n "$AUDIT_ONLY" ] && exit 0
echo "$LOG" | grep -q '^DONE' || exit 1
case "$N" in tool_*) K=tools ;; vehicle_*) K=vehicles ;; part_*) K=parts ;; *) K=buildings ;; esac   # where the game loads it from
mkdir -p "$D/renders" "data/models/$K/$N"
BL=$(ls "$D"/SM_*.blend | grep -v _audit | head -1)
rm -f "$D"/renders/[!b]*.png
[ -z "$BLOCKOUT" ] && "$B" -b "$BL" -P "$(pwd -W)/art_src/render_building.py" -- "$D/renders" "$N" "$@" 2>&1 | grep -E 'Error|Traceback|line [0-9]+|DONE'
cp "$D"/SM_*.glb "data/models/$K/$N/"

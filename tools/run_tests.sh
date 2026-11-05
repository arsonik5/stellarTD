#!/usr/bin/env bash
# Runs every driven test scene and fails if any check fails or any script error is printed.
#   tools/run_tests.sh            # all
#   tools/run_tests.sh systems    # just one (name = scenes/dev/<name>_test.tscn)
# Uses xvfb-run when there is no display, so mouse-capture checks work in CI/containers
# (pure --headless cannot capture the mouse). GODOT can point at the engine binary.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TESTS=("systems" "build_fp" "vehicle" "pipe" "game")
[ $# -gt 0 ] && TESTS=("$@")
RUN=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
  RUN=(xvfb-run -a -s "-screen 0 1280x720x24")
fi
LOGDIR="${TMPDIR:-/tmp}/stellartd-tests"
mkdir -p "$LOGDIR"
total_fail=0
for t in "${TESTS[@]}"; do
  scene="res://scenes/dev/${t}_test.tscn"
  log="$LOGDIR/$t.log"
  start=$(date +%s)
  timeout 600 "${RUN[@]}" "$GODOT" --path . "$scene" >"$log" 2>&1 &
  pid=$!
  # a script that fails to load leaves the scene idling until the timeout: stop it as soon as that shows
  while kill -0 $pid 2>/dev/null; do
    if grep -q -E 'Parse Error|Failed to load script' "$log" 2>/dev/null; then
      pkill -P $pid 2>/dev/null; kill $pid 2>/dev/null; pkill -f "$scene" 2>/dev/null; break
    fi
    sleep 1
  done
  wait $pid 2>/dev/null
  secs=$(( $(date +%s) - start ))
  fails=$(grep -c '^FAIL' "$log")
  errs=$(grep -c -E "SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Cannot call|does not have any .meta." "$log")
  done_line=$(grep -c -E 'DONE' "$log")
  status=ok
  if [ "$fails" -gt 0 ] || [ "$errs" -gt 0 ] || [ "$done_line" -eq 0 ]; then status=FAILED; total_fail=$((total_fail+1)); fi
  printf '%-10s %-7s %3ss  fails=%s script_errors=%s  (log %s)\n' "$t" "$status" "$secs" "$fails" "$errs" "$log"
  if [ "$status" = FAILED ]; then
    grep -E '^FAIL|SCRIPT ERROR|Parse Error|Invalid (call|access)|Cannot call' -A2 "$log" | head -20
  fi
done
echo "TESTS DONE failed_suites=$total_fail"
exit $total_fail

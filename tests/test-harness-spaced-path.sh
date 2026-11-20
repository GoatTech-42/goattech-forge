#!/usr/bin/env bash
# Regression test: harness/build-real.sh must work when the harness, the
# Marlin tree and the output dir all live under paths containing spaces.
# Copies harness/ into a disposable "forge test dir" and builds and runs it.
# Host build only: no hardware validation.
set -u
TREE="${1:?usage: test-harness-spaced-path.sh <marlin-tree containing Marlin/>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TREE="$(cd "$TREE" && pwd)"
[ -f "$TREE/Marlin/src/module/planner.cpp" ] || { echo "no Marlin/src/module/planner.cpp under $TREE" >&2; exit 1; }
B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
D="$B/forge test dir"
fails=0
chk(){ if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fails=$((fails+1)); fi; }

mkdir -p "$D"
cp -r "$ROOT/harness" "$D/harness"
ln -s "$TREE" "$D/marlin tree"     # tree path with a space (read only)
bash "$D/harness/build-real.sh" "$D/marlin tree" "$D/build out" >"$B/build.log" 2>&1
rc=$?; [ $rc = 0 ] || tail -n 15 "$B/build.log" | sed 's/^/  build: /'
chk $rc "build-real.sh builds from \"$D\""
"$D/build out/harness-real" >"$B/run.txt" 2>&1; rc=$?
chk $rc "harness-real built under a spaced path runs (exit 0)"
grep -qxF 'block 0 steps=800,0,0,0 events=800 mm=10.000 nominal_speed=50.00 nominal_rate=4000' "$B/run.txt"
chk $? "spaced-path build reaches the real planner (800 X steps for 10 mm)"
grep -qxF 'blocks total=6' "$B/run.txt"; chk $? "spaced-path build drains all 6 blocks"

[ $fails = 0 ] && echo "RESULT: all checks passed" || echo "RESULT: $fails failure(s)"
[ $fails = 0 ]

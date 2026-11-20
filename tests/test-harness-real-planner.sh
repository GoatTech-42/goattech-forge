#!/usr/bin/env bash
# Forge F1(a): Marlin's REAL planner.cpp and temperature.cpp, compiled from the
# pinned tree with the host config (harness/config) and linked into a host
# executable (harness/build-real.sh). Queues known moves through the real
# Planner, drains the blocks, and checks step counts, block lengths, nominal
# speeds/rates, cold-extrusion handling, target-temperature setters/clamp and
# thermistor conversion. Negative check: the same expectations must FAIL when
# X steps/mm is deliberately wrong (81 instead of 80).
# Host simulation only: compile + host execution != hardware validation.
set -u
TREE="${1:?usage: test-harness-real-planner.sh <marlin-tree containing Marlin/>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
fails=0
chk(){ if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fails=$((fails+1)); fi; }

bash "$ROOT/harness/build-real.sh" "$TREE" "$OUT" >"$OUT/build.log" 2>&1
rc=$?; [ $rc = 0 ] || sed 's/^/  build: /' "$OUT/build.log"
chk $rc "real planner.o + temperature.o link into a host executable"
[ $rc = 0 ] || { echo "RESULT: $fails failure(s)"; exit 1; }
for m in planner.cpp temperature.cpp; do
  grep -qxF "host config marker present in $m" "$OUT/build.log"
  chk $? "$m compiled with harness/config (host config marker found)"
done

# Expected output for the Ender 3 V3 SE host config (80/80/400/715.12 steps/mm).
EXPECT='config steps_per_mm=80.00,80.00,400.00,715.12
block 0 steps=800,0,0,0 events=800 mm=10.000 nominal_speed=50.00 nominal_rate=4000
block 1 steps=0,800,0,0 events=800 mm=10.000 nominal_speed=50.00 nominal_rate=4000
block 2 steps=800,800,0,0 events=800 mm=14.142 nominal_speed=100.00 nominal_rate=5657
block 3 steps=0,0,80,0 events=80 mm=0.200 nominal_speed=5.00 nominal_rate=2001
hotend_cold=1
block 4 steps=1600,0,0,0 events=1600 mm=20.000 nominal_speed=30.00 nominal_rate=2400
block 5 steps=800,0,0,715 events=800 mm=10.000 nominal_speed=30.00 nominal_rate=2400
hotend target=210
hotend clamp=300 max_target=300
bed target=60
thermistor raw=1000 hotend_c=233.5 bed_c=209.6
thermistor raw=4000 hotend_c=153.9 bed_c=138.6
thermistor raw=8000 hotend_c=112.2 bed_c=102.2
thermistor raw=12000 hotend_c=78.0 bed_c=73.7
thermistor raw=15000 hotend_c=40.4 bed_c=39.9
blocks total=6'

# mismatches <run-output-file>: print and count expected lines missing from a run
mismatches(){
  local n=0
  while IFS= read -r line; do
    grep -qxF "$line" "$1" || { echo "  missing: $line" >&2; n=$((n+1)); }
  done <<<"$EXPECT"
  echo "$n"
}

"$OUT/harness-real" >"$OUT/good.txt"; rc=$?
chk $rc "harness-real runs (exit 0)"
sed 's/^/  | /' "$OUT/good.txt"
n=$(mismatches "$OUT/good.txt"); chk $([ "$n" = 0 ]; echo $?) "real planner/temperature output matches expected ($n mismatches)"
grep -q 'error' "$OUT/good.txt"; chk $([ $? = 1 ]; echo $?) "every queued block drained"

# Negative check: wrong X steps/mm must be caught by the same expectations.
"$OUT/harness-real" --steps-x 81 >"$OUT/bad.txt"; rc=$?
chk $rc "harness-real --steps-x 81 runs"
n=$(mismatches "$OUT/bad.txt" 2>"$OUT/bad.miss")
sed 's/^/  negative /' "$OUT/bad.miss"
chk $([ "$n" -gt 0 ]; echo $?) "wrong X steps/mm (81) is detected ($n mismatches)"
grep -qxF 'block 0 steps=810,0,0,0 events=810 mm=10.000 nominal_speed=50.00 nominal_rate=4050' "$OUT/bad.txt"
chk $? "wrong steps/mm actually reaches the real planner (810 X steps for 10 mm)"

echo "NOTE: host simulation of the real planner/temperature modules; no hardware validation."
[ $fails = 0 ] && echo "RESULT: all checks passed" || echo "RESULT: $fails failure(s)"
[ $fails = 0 ]
